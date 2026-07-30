import { Router } from 'express';

import { config } from '../config.js';
import { requireAuth } from '../middleware/auth.js';
import {
  acquireAiLease,
  fetchModels,
  proxyAiResponse,
  releaseAiLease,
  resolveUserApiKey,
  validateChatBody,
  validateImageBody,
} from '../services/aiGateway.js';
import {
  deleteUserCredential,
  getUserCredential,
  saveUserCredential,
} from '../services/credentialVault.js';
import {
  appendConversationTurn,
  compactConversation,
  createConversation,
  deleteConversation,
  getConversationContext,
  listConversations,
} from '../services/conversationStore.js';
import {
  cancelDocumentJob,
  createDocumentJob,
  getDocumentJob,
  listDocumentJobs,
  resolveDocumentDownload,
} from '../services/documentJobs.js';
import { getRuntimeSettings } from '../services/runtimeSettings.js';

const router = Router();

router.use(requireAuth);

router.get('/credential', async (req, res, next) => {
  try {
    res.setHeader('Cache-Control', 'no-store');
    if (!config.ai.credentialSyncEnabled) {
      return res.status(503).json({ code: 'KEY_SYNC_DISABLED', message: '跨端 Key 同步未启用' });
    }
    const credential = await getUserCredential(req.user.id);
    if (!credential) return res.json({ configured: false });
    res.json({
      configured: true,
      key: credential.key,
      masked: `${credential.key.slice(0, 4)}••••${credential.key.slice(-4)}`,
      fingerprint: credential.key_fingerprint,
      updated_at: credential.updated_at,
    });
  } catch (err) {
    next(err);
  }
});

router.put('/credential', async (req, res, next) => {
  try {
    res.setHeader('Cache-Control', 'no-store');
    if (!config.ai.credentialSyncEnabled) {
      return res.status(503).json({ code: 'KEY_SYNC_DISABLED', message: '跨端 Key 同步未启用' });
    }
    const key = String(req.body?.key || '').trim().replace(/^Bearer\s+/i, '');
    if (key.length < 8 || key.length > 512 || /[\r\n\0]/.test(key)) {
      return res.status(400).json({ code: 'INVALID_STATION_KEY', message: 'API Key 格式无效' });
    }
    await fetchModels(key);
    const saved = await saveUserCredential(req.user.id, key);
    res.json({
      configured: true,
      key,
      masked: `${key.slice(0, 4)}••••${key.slice(-4)}`,
      fingerprint: saved.key_fingerprint,
      updated_at: saved.updated_at,
    });
  } catch (err) {
    next(err);
  }
});

router.delete('/credential', async (req, res, next) => {
  try {
    await deleteUserCredential(req.user.id);
    res.setHeader('Cache-Control', 'no-store');
    res.json({ configured: false });
  } catch (err) {
    next(err);
  }
});

router.use((req, res, next) => {
  getRuntimeSettings('ai')
    .then((settings) => {
      if (!settings.enabled) {
        return res.status(503).json({ code: 'AI_DISABLED', message: 'AI功能暂未开放' });
      }
      req.aiSettings = settings;
      return next();
    })
    .catch(next);
});

router.get('/conversations', async (req, res, next) => {
  try {
    res.json({ conversations: await listConversations(req.user.id) });
  } catch (err) {
    next(err);
  }
});

router.post('/conversations', async (req, res, next) => {
  try {
    const title = String(req.body?.title || '').trim().slice(0, 120);
    const model = String(req.body?.model || '').trim().slice(0, 200);
    if (!title || !model) {
      return res.status(400).json({ code: 'INVALID_CONVERSATION', message: '会话标题和模型不能为空' });
    }
    res.status(201).json(await createConversation(req.user.id, { title, model }));
  } catch (err) {
    next(err);
  }
});

router.get('/conversations/:id/context', async (req, res, next) => {
  try {
    const context = await getConversationContext(req.user.id, req.params.id);
    if (!context) return res.status(404).json({ code: 'CONVERSATION_NOT_FOUND', message: '对话不存在' });
    res.json(context);
  } catch (err) {
    next(err);
  }
});

router.post('/conversations/:id/turns', async (req, res, next) => {
  try {
    const userContent = String(req.body?.user_content || '').trim();
    const assistantContent = String(req.body?.assistant_content || '').trim();
    const model = String(req.body?.model || '').trim().slice(0, 200);
    if (!userContent || !assistantContent || !model) {
      return res.status(400).json({ code: 'INVALID_TURN', message: '对话内容和模型不能为空' });
    }
    if (userContent.length > config.ai.maxPromptChars || assistantContent.length > 200000) {
      return res.status(413).json({ code: 'TURN_TOO_LARGE', message: '对话内容过长' });
    }
    const result = await appendConversationTurn(req.user.id, req.params.id, {
      userContent,
      assistantContent,
      model,
    });
    if (!result) return res.status(404).json({ code: 'CONVERSATION_NOT_FOUND', message: '对话不存在' });
    res.status(201).json(result);
  } catch (err) {
    next(err);
  }
});

router.post('/conversations/:id/compact', async (req, res, next) => {
  try {
    const summary = String(req.body?.summary || '').trim();
    if (summary.length < 20 || summary.length > 12000) {
      return res.status(400).json({
        code: 'INVALID_CONTEXT_SUMMARY',
        message: '上下文摘要长度无效',
      });
    }
    const result = await compactConversation(req.user.id, req.params.id, summary);
    if (!result) {
      return res.status(404).json({ code: 'CONVERSATION_NOT_FOUND', message: '对话不存在' });
    }
    res.json(result);
  } catch (err) {
    next(err);
  }
});

router.delete('/conversations/:id', async (req, res, next) => {
  try {
    const deleted = await deleteConversation(req.user.id, req.params.id);
    if (!deleted) return res.status(404).json({ code: 'CONVERSATION_NOT_FOUND', message: '对话不存在' });
    res.json({ deleted: true });
  } catch (err) {
    next(err);
  }
});

router.get('/documents', async (req, res, next) => {
  try {
    if (!config.documents.enabled) {
      return res.status(503).json({ code: 'DOCUMENTS_DISABLED', message: '文档生成功能暂未开放' });
    }
    const conversationId = String(req.query.conversation_id || '').trim();
    const jobs = await listDocumentJobs(req.user.id, {
      conversationId: conversationId || undefined,
      limit: req.query.limit,
    });
    res.setHeader('Cache-Control', 'no-store');
    res.json({ jobs });
  } catch (err) {
    next(err);
  }
});

router.post('/documents', async (req, res, next) => {
  try {
    if (!config.documents.enabled) {
      return res.status(503).json({ code: 'DOCUMENTS_DISABLED', message: '文档生成功能暂未开放' });
    }
    const kind = String(req.body?.kind || '').trim().toLowerCase();
    const prompt = String(req.body?.prompt || '').trim();
    const model = String(req.body?.model || '').trim().slice(0, 200);
    const conversationId = String(req.body?.conversation_id || '').trim();
    const useImages = kind === 'pptx' && req.body?.use_images === true;
    const imageModel = String(req.body?.image_model || '').trim().slice(0, 200);
    if (!['docx', 'pptx'].includes(kind)) {
      return res.status(400).json({ code: 'INVALID_DOCUMENT_KIND', message: '请选择 Word 或 PPT' });
    }
    if (prompt.length < 2 || prompt.length > Math.min(config.ai.maxPromptChars, 30000)) {
      return res.status(400).json({ code: 'INVALID_DOCUMENT_PROMPT', message: '文档需求长度无效' });
    }
    if (!model) {
      return res.status(400).json({ code: 'INVALID_DOCUMENT_MODEL', message: '请选择内容模型' });
    }
    if (useImages && (!imageModel || !req.aiSettings.image_models.includes(imageModel))) {
      return res.status(400).json({ code: 'INVALID_IMAGE_MODEL', message: '请选择已开放的生图模型' });
    }
    const storedCredential = await getUserCredential(req.user.id).catch(() => null);
    if (!storedCredential?.key && !config.ai.sharedApiKey) {
      return res.status(400).json({
        code: 'DOCUMENT_KEY_REQUIRED',
        message: '异步文档任务需要先在“我的”页面绑定并同步本站 Key',
      });
    }
    const job = await createDocumentJob(req.user.id, {
      kind,
      prompt,
      model,
      conversationId: conversationId || undefined,
      useImages,
      imageModel: useImages ? imageModel : undefined,
    });
    res.status(202).json(job);
  } catch (err) {
    next(err);
  }
});

router.get('/documents/:id', async (req, res, next) => {
  try {
    const job = await getDocumentJob(req.user.id, req.params.id);
    if (!job) return res.status(404).json({ code: 'DOCUMENT_NOT_FOUND', message: '文档任务不存在' });
    res.setHeader('Cache-Control', 'no-store');
    res.json(job);
  } catch (err) {
    next(err);
  }
});

router.get('/documents/:id/download', async (req, res, next) => {
  try {
    const artifact = await resolveDocumentDownload(req.user.id, req.params.id);
    if (!artifact) {
      return res.status(404).json({ code: 'DOCUMENT_NOT_FOUND', message: '文档任务不存在' });
    }
    res.setHeader('Cache-Control', 'private, no-store');
    res.download(artifact.path, artifact.name, (error) => {
      if (error && !res.headersSent) next(error);
    });
  } catch (err) {
    next(err);
  }
});

router.delete('/documents/:id', async (req, res, next) => {
  try {
    const job = await cancelDocumentJob(req.user.id, req.params.id);
    if (!job) return res.status(404).json({ code: 'DOCUMENT_NOT_FOUND', message: '文档任务不存在' });
    res.json(job);
  } catch (err) {
    next(err);
  }
});

router.get('/models', async (req, res, next) => {
  try {
    const apiKey = resolveUserApiKey(req);
    const result = await fetchModels(apiKey, req.query.capability);
    res.setHeader('Cache-Control', 'private, max-age=60');
    res.json(result);
  } catch (err) {
    next(err);
  }
});

router.post('/chat/completions', async (req, res, next) => {
  let leaseId;
  try {
    const validationError = validateChatBody(req.body);
    if (validationError) {
      return res.status(400).json({ code: 'INVALID_AI_REQUEST', message: validationError });
    }
    const apiKey = resolveUserApiKey(req);
    const lease = await acquireAiLease(req.user.id, 'chat');
    if (!lease.ok) return res.status(429).json({ code: lease.code, message: lease.message });
    leaseId = lease.leaseId;
    await proxyAiResponse(req, res, {
      apiKey,
      path: '/v1/chat/completions',
      body: { ...req.body, n: 1 },
    });
  } catch (err) {
    if (!res.headersSent) next(err);
    else res.end();
  } finally {
    await releaseAiLease(leaseId).catch((err) => {
      console.error('[ai] 释放并发租约失败:', err.message);
    });
  }
});

router.post('/images/generations', async (req, res, next) => {
  let leaseId;
  try {
    const validationError = validateImageBody(req.body, req.aiSettings.image_models);
    if (validationError) {
      return res.status(400).json({ code: 'INVALID_IMAGE_REQUEST', message: validationError });
    }
    const apiKey = resolveUserApiKey(req);
    const lease = await acquireAiLease(req.user.id, 'image');
    if (!lease.ok) return res.status(429).json({ code: lease.code, message: lease.message });
    leaseId = lease.leaseId;
    await proxyAiResponse(req, res, {
      apiKey,
      path: '/v1/images/generations',
      body: { ...req.body, n: Math.min(4, Math.max(1, Number(req.body.n || 1))) },
    });
  } catch (err) {
    if (!res.headersSent) next(err);
    else res.end();
  } finally {
    await releaseAiLease(leaseId).catch((err) => {
      console.error('[ai] 释放并发租约失败:', err.message);
    });
  }
});

export default router;
