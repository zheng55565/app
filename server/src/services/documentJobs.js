import crypto from 'node:crypto';
import path from 'node:path';
import { mkdir, rename, rm, stat, writeFile } from 'node:fs/promises';

import { config } from '../config.js';
import { query, withTransaction } from '../db.js';
import {
  acquireAiLease,
  releaseAiLease,
  requestChatCompletion,
  requestImageBase64,
} from './aiGateway.js';
import { getUserCredential } from './credentialVault.js';
import {
  documentPlanningMessages,
  parseDocumentPlan,
  renderDocx,
  renderPptx,
  safeArtifactTitle,
} from './documentRenderer.js';

const outputRoot = path.resolve(process.cwd(), config.documents.outputDir);
let workerState = null;

function publicJob(row) {
  if (!row) return null;
  const { artifact_path: ignoredPath, ...safe } = row;
  void ignoredPath;
  return {
    ...safe,
    downloadable: row.status === 'completed' && Boolean(row.artifact_path),
  };
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function insideOutputRoot(filePath) {
  const resolved = path.resolve(filePath || '');
  return resolved.startsWith(`${outputRoot}${path.sep}`);
}

export async function createDocumentJob(userId, input) {
  return withTransaction(async (client) => {
    await client.query(`SELECT pg_advisory_xact_lock(hashtext($1))`, [`document-user:${userId}`]);
    const active = await client.query(
      `SELECT COUNT(*)::int AS count
       FROM ai_document_jobs
       WHERE user_id = $1 AND status IN ('queued', 'processing')`,
      [userId]
    );
    if (active.rows[0].count >= config.documents.maxActivePerUser) {
      const err = new Error('同时生成的文档已达上限，请等待当前任务完成');
      err.code = 'DOCUMENT_CONCURRENCY_LIMIT';
      err.status = 429;
      throw err;
    }
    if (input.conversationId) {
      const conversation = await client.query(
        `SELECT 1 FROM ai_conversations WHERE id = $1 AND user_id = $2`,
        [input.conversationId, userId]
      );
      if (conversation.rows.length === 0) {
        const err = new Error('关联的对话不存在');
        err.code = 'CONVERSATION_NOT_FOUND';
        err.status = 404;
        throw err;
      }
    }
    const id = crypto.randomUUID();
    const { rows } = await client.query(
      `INSERT INTO ai_document_jobs
         (id, user_id, conversation_id, kind, prompt, model, image_model, use_images)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
       RETURNING *`,
      [
        id,
        userId,
        input.conversationId || null,
        input.kind,
        input.prompt,
        input.model,
        input.imageModel || null,
        Boolean(input.useImages),
      ]
    );
    return publicJob(rows[0]);
  });
}

export async function listDocumentJobs(userId, { conversationId, limit = 30 } = {}) {
  const params = [userId];
  let conversationFilter = '';
  if (conversationId) {
    params.push(conversationId);
    conversationFilter = ` AND conversation_id = $${params.length}`;
  }
  params.push(Math.max(1, Math.min(100, Number(limit) || 30)));
  const { rows } = await query(
    `SELECT * FROM ai_document_jobs
     WHERE user_id = $1${conversationFilter}
     ORDER BY created_at DESC
     LIMIT $${params.length}`,
    params
  );
  return rows.map(publicJob);
}

export async function getDocumentJob(userId, id) {
  const { rows } = await query(
    `SELECT * FROM ai_document_jobs WHERE id = $1 AND user_id = $2`,
    [id, userId]
  );
  return publicJob(rows[0]);
}

export async function cancelDocumentJob(userId, id) {
  const { rows } = await query(
    `UPDATE ai_document_jobs
     SET status = CASE
           WHEN status IN ('queued', 'processing') THEN 'cancelled'
           ELSE status
         END,
         updated_at = NOW()
     WHERE id = $1 AND user_id = $2
     RETURNING *`,
    [id, userId]
  );
  const row = rows[0];
  if (!row) return null;
  if (row.status === 'completed' && row.artifact_path && insideOutputRoot(row.artifact_path)) {
    await rm(row.artifact_path, { force: true }).catch(() => {});
    const updated = await query(
      `UPDATE ai_document_jobs
       SET status = 'cancelled', artifact_path = NULL, artifact_bytes = NULL, updated_at = NOW()
       WHERE id = $1 AND user_id = $2 RETURNING *`,
      [id, userId]
    );
    return publicJob(updated.rows[0]);
  }
  return publicJob(row);
}

export async function resolveDocumentDownload(userId, id) {
  const { rows } = await query(
    `SELECT * FROM ai_document_jobs WHERE id = $1 AND user_id = $2`,
    [id, userId]
  );
  const row = rows[0];
  if (!row) return null;
  if (row.status !== 'completed' || !row.artifact_path) {
    const err = new Error(row.status === 'expired' ? '文件已过期' : '文件尚未生成完成');
    err.code = row.status === 'expired' ? 'DOCUMENT_EXPIRED' : 'DOCUMENT_NOT_READY';
    err.status = row.status === 'expired' ? 410 : 409;
    throw err;
  }
  if (!insideOutputRoot(row.artifact_path)) {
    const err = new Error('文件路径校验失败');
    err.code = 'INVALID_ARTIFACT_PATH';
    err.status = 500;
    throw err;
  }
  await stat(row.artifact_path).catch(() => {
    const err = new Error('文件已不存在');
    err.code = 'ARTIFACT_MISSING';
    err.status = 410;
    throw err;
  });
  return { path: row.artifact_path, name: row.artifact_name };
}

async function claimNextJob() {
  const { rows } = await query(
    `WITH next_job AS (
       SELECT id FROM ai_document_jobs
       WHERE status = 'queued' AND attempts < 3
       ORDER BY created_at
       FOR UPDATE SKIP LOCKED
       LIMIT 1
     )
     UPDATE ai_document_jobs AS job
     SET status = 'processing', progress = GREATEST(progress, 5),
         attempts = attempts + 1, started_at = COALESCE(started_at, NOW()), updated_at = NOW()
     FROM next_job
     WHERE job.id = next_job.id
     RETURNING job.*`
  );
  return rows[0] || null;
}

async function updateProgress(id, progress) {
  await query(
    `UPDATE ai_document_jobs SET progress = $2, updated_at = NOW()
     WHERE id = $1 AND status = 'processing'`,
    [id, Math.max(0, Math.min(99, Math.round(progress)))]
  );
}

async function requeueJob(id) {
  await query(
    `UPDATE ai_document_jobs SET status = 'queued', progress = 0, updated_at = NOW()
     WHERE id = $1 AND status = 'processing'`,
    [id]
  );
}

async function failJob(id, error) {
  const message = String(error?.message || '文档生成失败').slice(0, 1000);
  await query(
    `UPDATE ai_document_jobs
     SET status = 'failed', error_message = $2, updated_at = NOW(), completed_at = NOW()
     WHERE id = $1 AND status = 'processing'`,
    [id, message]
  );
}

async function completeJob(job, { title, artifactPath, artifactName, bytes, metadata }) {
  const { rowCount } = await query(
    `UPDATE ai_document_jobs
     SET status = 'completed', progress = 100, title = $2, artifact_path = $3,
         artifact_name = $4, artifact_bytes = $5, output_metadata = $6::jsonb,
         error_message = NULL, completed_at = NOW(), updated_at = NOW(),
         expires_at = NOW() + ($7 || ' hours')::interval
     WHERE id = $1 AND status = 'processing'`,
    [
      job.id,
      title,
      artifactPath,
      artifactName,
      bytes,
      JSON.stringify(metadata),
      String(config.documents.retentionHours),
    ]
  );
  if (rowCount === 0) await rm(artifactPath, { force: true }).catch(() => {});
}

async function documentApiKey(userId) {
  const credential = await getUserCredential(userId).catch(() => null);
  return credential?.key || config.ai.sharedApiKey || '';
}

async function processJob(job) {
  let leaseId;
  try {
    const apiKey = await documentApiKey(job.user_id);
    if (!apiKey) throw new Error('请先在“我的”页面绑定并同步本站 Key');
    const lease = await acquireAiLease(job.user_id, 'document');
    if (!lease.ok) {
      await requeueJob(job.id);
      await delay(1000);
      return;
    }
    leaseId = lease.leaseId;
    const maxItems = job.kind === 'docx' ? config.documents.maxSections : config.documents.maxSlides;
    const messages = documentPlanningMessages({
      kind: job.kind,
      prompt: job.prompt,
      maxItems,
      useImages: job.use_images,
    });
    const rawPlan = await requestChatCompletion(apiKey, {
      model: job.model,
      messages,
      maxTokens: Math.min(config.ai.maxOutputTokens, 12000),
    });
    const plan = parseDocumentPlan(rawPlan, job.kind, {
      maxSections: config.documents.maxSections,
      maxSlides: config.documents.maxSlides,
    });
    await updateProgress(job.id, 38);

    const imageBuffers = new Map();
    if (job.kind === 'pptx' && job.use_images && job.image_model && config.documents.maxImages > 0) {
      const candidates = plan.slides
        .map((slide, index) => ({ index, prompt: slide.imagePrompt }))
        .filter((item) => item.prompt)
        .slice(0, config.documents.maxImages);
      for (let position = 0; position < candidates.length; position++) {
        const item = candidates[position];
        const image = await requestImageBase64(apiKey, {
          model: job.image_model,
          prompt: `${item.prompt} --ar 16:9 --style raw`,
        }).catch(() => null);
        if (image) imageBuffers.set(item.index, image);
        await updateProgress(job.id, 40 + ((position + 1) / Math.max(1, candidates.length)) * 35);
      }
    }

    const buffer = job.kind === 'docx' ? await renderDocx(plan) : await renderPptx(plan, imageBuffers);
    if (
      !Buffer.isBuffer(buffer) ||
      buffer.length === 0 ||
      buffer.length > config.documents.maxArtifactBytes
    ) {
      throw new Error('生成的文件大小异常');
    }
    await updateProgress(job.id, 88);
    await mkdir(outputRoot, { recursive: true });
    const extension = job.kind;
    const artifactName = `${safeArtifactTitle(plan.title)}.${extension}`;
    const artifactPath = path.join(outputRoot, `${job.id}.${extension}`);
    const tempPath = `${artifactPath}.tmp-${crypto.randomUUID()}`;
    await writeFile(tempPath, buffer, { flag: 'wx' });
    await rename(tempPath, artifactPath).catch(async (error) => {
      await rm(tempPath, { force: true }).catch(() => {});
      throw error;
    });
    await completeJob(job, {
      title: plan.title,
      artifactPath,
      artifactName,
      bytes: buffer.length,
      metadata: {
        item_count: job.kind === 'docx' ? plan.sections.length : plan.slides.length + 1,
        generated_images: imageBuffers.size,
        model: job.model,
        image_model: job.image_model || null,
      },
    });
  } catch (error) {
    await failJob(job.id, error);
  } finally {
    await releaseAiLease(leaseId).catch(() => {});
  }
}

async function cleanupExpiredDocuments() {
  const { rows } = await query(
    `WITH expired AS (
       SELECT id, artifact_path FROM ai_document_jobs
       WHERE status = 'completed' AND expires_at <= NOW()
       FOR UPDATE SKIP LOCKED
     )
     UPDATE ai_document_jobs AS job
     SET status = 'expired', artifact_path = NULL, updated_at = NOW()
     FROM expired
     WHERE job.id = expired.id
     RETURNING expired.artifact_path`
  );
  for (const row of rows) {
    if (row.artifact_path && insideOutputRoot(row.artifact_path)) {
      await rm(row.artifact_path, { force: true }).catch(() => {});
    }
  }
}

async function recoverStaleJobs() {
  const staleSeconds = Math.max(600, Math.ceil(config.ai.requestTimeoutMs / 1000) * 2);
  await query(
    `UPDATE ai_document_jobs
     SET status = CASE WHEN attempts >= 3 THEN 'failed' ELSE 'queued' END,
         error_message = CASE WHEN attempts >= 3 THEN '任务多次中断，请重新创建' ELSE error_message END,
         progress = CASE WHEN attempts >= 3 THEN progress ELSE 0 END,
         updated_at = NOW()
     WHERE status = 'processing'
       AND updated_at < NOW() - ($1 || ' seconds')::interval`,
    [String(staleSeconds)]
  );
}

async function workerLoop(state) {
  while (!state.stopping) {
    try {
      const job = await claimNextJob();
      if (job) await processJob(job);
      else await delay(config.documents.pollIntervalMs);
    } catch (error) {
      console.error('[documents] Worker异常:', error.message);
      await delay(Math.max(2000, config.documents.pollIntervalMs));
    }
  }
}

export function startDocumentWorkers() {
  if (!config.documents.enabled || workerState) return;
  const state = { stopping: false, loops: [] };
  workerState = state;
  void recoverStaleJobs().catch((error) => {
    console.error('[documents] 恢复中断任务失败:', error.message);
  });
  void cleanupExpiredDocuments().catch(() => {});
  for (let index = 0; index < config.documents.workers; index++) {
    state.loops.push(workerLoop(state));
  }
  state.cleanupTimer = setInterval(() => {
    void cleanupExpiredDocuments().catch((error) => {
      console.error('[documents] 清理过期文件失败:', error.message);
    });
  }, 60 * 60 * 1000);
  state.cleanupTimer.unref();
}

export async function stopDocumentWorkers() {
  const state = workerState;
  if (!state) return;
  state.stopping = true;
  clearInterval(state.cleanupTimer);
  await Promise.race([Promise.allSettled(state.loops), delay(5000)]);
  workerState = null;
}
