import crypto from 'node:crypto';
import { Readable } from 'node:stream';

import { config } from '../config.js';
import { query, withTransaction } from '../db.js';
import { getRuntimeSettings } from './runtimeSettings.js';

const ADMISSION_LOCK_KEY = 'ai_request_admission_v1';

export function resolveUserApiKey(req) {
  const supplied = String(req.headers['x-station-key'] || '').trim();
  const key = supplied || config.ai.sharedApiKey;
  if (!key) {
    const err = new Error('请先在“我的”页面配置网站 API Key');
    err.code = 'STATION_KEY_REQUIRED';
    err.status = 400;
    throw err;
  }
  if (supplied && !config.ai.allowUserApiKey) {
    const err = new Error('当前服务不允许使用个人 API Key');
    err.code = 'USER_API_KEY_DISABLED';
    err.status = 403;
    throw err;
  }
  if (key.length < 8 || key.length > 512 || /[\r\n\0]/.test(key)) {
    const err = new Error('API Key 格式无效');
    err.code = 'INVALID_STATION_KEY';
    err.status = 400;
    throw err;
  }
  return key.replace(/^Bearer\s+/i, '');
}

export function validateChatBody(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    return '请求体格式错误';
  }
  if (typeof body.model !== 'string' || body.model.length < 1 || body.model.length > 200) {
    return '请选择有效模型';
  }
  if (!Array.isArray(body.messages) || body.messages.length < 1 || body.messages.length > 200) {
    return 'messages 数量无效';
  }
  const chars = body.messages.reduce((sum, message) => {
    if (!message || typeof message !== 'object') return sum + config.ai.maxPromptChars + 1;
    if (typeof message.content === 'string') return sum + message.content.length;
    return sum + JSON.stringify(message.content ?? '').length;
  }, 0);
  if (chars > config.ai.maxPromptChars) return '输入内容过长';
  const rawMaxTokens = body.max_tokens ?? body.max_completion_tokens;
  if (rawMaxTokens != null) {
    const maxTokens = Number(rawMaxTokens);
    if (!Number.isInteger(maxTokens) || maxTokens < 1) return 'max_tokens 必须是正整数';
    if (maxTokens > config.ai.maxOutputTokens) return 'max_tokens 超过平台限制';
  }
  if (body.n != null && Number(body.n) !== 1) return '当前只允许 n=1';
  return null;
}

export function validateImageBody(body, allowedModels = config.ai.imageModels) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) return '请求体格式错误';
  if (allowedModels.length === 0) return '后台尚未配置生图模型';
  if (typeof body.model !== 'string' || body.model.length < 1 || body.model.length > 200) {
    return '请选择有效模型';
  }
  if (!allowedModels.includes(body.model)) return '该模型未开放生图能力';
  if (typeof body.prompt !== 'string' || body.prompt.trim().length < 1) return '请输入提示词';
  if (body.prompt.length > Math.min(config.ai.maxPromptChars, 20000)) return '提示词过长';
  if (
    body.n != null &&
    (!Number.isInteger(Number(body.n)) || Number(body.n) < 1 || Number(body.n) > 4)
  ) {
    return '生成数量必须为 1-4';
  }
  return null;
}

export async function acquireAiLease(userId, kind) {
  return withTransaction(async (client) => {
    await client.query(`SELECT pg_advisory_xact_lock(hashtext($1))`, [ADMISSION_LOCK_KEY]);
    await client.query(`DELETE FROM api_request_leases WHERE expires_at <= NOW()`);
    const { rows } = await client.query(
      `SELECT COUNT(*)::int AS total,
              COUNT(*) FILTER (WHERE user_id = $1)::int AS user_total
       FROM api_request_leases WHERE expires_at > NOW()`,
      [userId]
    );
    if (rows[0].total >= config.ai.maxConcurrent) {
      return { ok: false, code: 'AI_BUSY', message: '当前使用人数较多，请稍后重试' };
    }
    if (rows[0].user_total >= config.ai.maxConcurrentPerUser) {
      return { ok: false, code: 'USER_CONCURRENCY_LIMIT', message: '同时进行的AI任务已达上限' };
    }
    const leaseId = crypto.randomUUID();
    await client.query(
      `INSERT INTO api_request_leases (lease_id, user_id, kind, expires_at)
       VALUES ($1, $2, $3, NOW() + ($4 || ' seconds')::interval)`,
      [leaseId, userId, kind, String(config.ai.leaseTtlSec)]
    );
    return { ok: true, leaseId };
  });
}

export async function releaseAiLease(leaseId) {
  if (!leaseId) return;
  await query(`DELETE FROM api_request_leases WHERE lease_id = $1`, [leaseId]);
}

function upstreamUrl(path) {
  if (!config.ai.upstreamBaseUrl) {
    const err = new Error('AI上游未配置');
    err.code = 'AI_NOT_CONFIGURED';
    err.status = 503;
    throw err;
  }
  return `${config.ai.upstreamBaseUrl}${path}`;
}

async function upstreamFetch(path, { apiKey, method = 'GET', body, signal }) {
  const response = await fetch(upstreamUrl(path), {
    method,
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
      Accept: 'application/json, text/event-stream',
    },
    body: body === undefined ? undefined : JSON.stringify(body),
    signal,
    redirect: 'manual',
  });
  if (response.status >= 300 && response.status < 400) {
    response.body?.cancel().catch(() => {});
    const err = new Error('AI上游返回了不安全的重定向');
    err.code = 'UPSTREAM_REDIRECT_REJECTED';
    err.status = 502;
    throw err;
  }
  return response;
}

async function readJsonLimited(response, maxBytes) {
  const contentLength = Number(response.headers.get('content-length') || 0);
  if (contentLength > maxBytes) throw new Error('模型响应超过大小限制');
  if (!response.body) return null;
  const reader = response.body.getReader();
  const chunks = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > maxBytes) {
      await reader.cancel().catch(() => {});
      throw new Error('模型响应超过大小限制');
    }
    chunks.push(Buffer.from(value));
  }
  if (total === 0) return null;
  return JSON.parse(Buffer.concat(chunks, total).toString('utf8'));
}

async function upstreamJson(
  path,
  { apiKey, body, timeoutMs = config.ai.requestTimeoutMs, maxResponseBytes = 12 * 1024 * 1024 }
) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await upstreamFetch(path, {
      apiKey,
      method: 'POST',
      body,
      signal: controller.signal,
    });
    const json = await readJsonLimited(response, maxResponseBytes).catch((error) => {
      if (error instanceof SyntaxError) return null;
      throw error;
    });
    if (!response.ok || !json) {
      const err = new Error(
        json?.error?.message || json?.message || `模型服务返回 ${response.status}`
      );
      err.code = 'AI_UPSTREAM_ERROR';
      err.status = response.status >= 400 && response.status < 500 ? response.status : 502;
      throw err;
    }
    return json;
  } finally {
    clearTimeout(timer);
  }
}

export async function requestChatCompletion(apiKey, { model, messages, maxTokens }) {
  const body = {
    model,
    messages,
    stream: false,
    n: 1,
    temperature: 0.3,
    max_tokens: Math.min(config.ai.maxOutputTokens, Math.max(512, Number(maxTokens || 8192))),
  };
  let json;
  try {
    json = await upstreamJson('/v1/chat/completions', {
      apiKey,
      body: { ...body, response_format: { type: 'json_object' } },
    });
  } catch (error) {
    if (error?.status !== 400) throw error;
    json = await upstreamJson('/v1/chat/completions', { apiKey, body });
  }
  const content = json?.choices?.[0]?.message?.content;
  if (typeof content === 'string' && content.trim()) return content;
  if (Array.isArray(content)) {
    const text = content
      .map((item) => (typeof item?.text === 'string' ? item.text : ''))
      .join('')
      .trim();
    if (text) return text;
  }
  const err = new Error('模型未返回文档内容');
  err.code = 'EMPTY_DOCUMENT_PLAN';
  err.status = 502;
  throw err;
}

export async function requestImageBase64(apiKey, { model, prompt, size = '1536x1024' }) {
  const json = await upstreamJson('/v1/images/generations', {
    apiKey,
    body: { model, prompt, size, n: 1, response_format: 'b64_json' },
    maxResponseBytes: Math.ceil(config.documents.maxImageBytes * 1.45) + 1024 * 1024,
  });
  const encoded = json?.data?.[0]?.b64_json;
  if (typeof encoded !== 'string' || encoded.length === 0) return null;
  const buffer = Buffer.from(encoded, 'base64');
  if (buffer.length === 0 || buffer.length > config.documents.maxImageBytes) return null;
  return buffer;
}

export async function fetchModels(apiKey, capability, { allowedImageModels } = {}) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), Math.min(config.ai.requestTimeoutMs, 30000));
  try {
    const upstream = await upstreamFetch('/v1/models', { apiKey, signal: controller.signal });
    const json = await upstream.json().catch(() => null);
    if (!upstream.ok || !json) {
      const err = new Error(json?.error?.message || json?.message || `模型服务返回 ${upstream.status}`);
      err.code = 'AI_UPSTREAM_ERROR';
      err.status = upstream.status >= 400 && upstream.status < 500 ? upstream.status : 502;
      throw err;
    }
    let models = Array.isArray(json.data) ? json.data : [];
    if (capability === 'image') {
      const configured = allowedImageModels || (await getRuntimeSettings('ai')).image_models;
      const allowed = new Set(configured);
      models = models.filter((item) => allowed.has(item?.id));
    }
    return { ...json, data: models };
  } finally {
    clearTimeout(timer);
  }
}

export async function proxyAiResponse(req, res, { apiKey, path, body }) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), config.ai.requestTimeoutMs);
  const abort = () => controller.abort();
  req.once('aborted', abort);
  try {
    const upstream = await upstreamFetch(path, {
      apiKey,
      method: 'POST',
      body,
      signal: controller.signal,
    });
    res.status(upstream.status);
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('X-Accel-Buffering', 'no');
    const contentType = upstream.headers.get('content-type');
    if (contentType) res.setHeader('Content-Type', contentType);
    if (!upstream.body) {
      res.end();
      return;
    }
    await new Promise((resolve, reject) => {
      const stream = Readable.fromWeb(upstream.body);
      stream.on('error', reject);
      res.on('finish', resolve);
      res.on('close', resolve);
      stream.pipe(res);
    });
  } finally {
    clearTimeout(timer);
    req.off('aborted', abort);
  }
}
