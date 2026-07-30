import assert from 'node:assert/strict';
import http from 'node:http';
import { after, test } from 'node:test';

import express from 'express';

let receivedAuthorization = '';
const upstream = http.createServer(async (req, res) => {
  receivedAuthorization = String(req.headers.authorization || '');
  if (req.url === '/v1/models') {
    res.setHeader('Content-Type', 'application/json');
    res.end(
      JSON.stringify({
        object: 'list',
        data: [{ id: 'chat-model' }, { id: 'image-model' }],
      })
    );
    return;
  }
  if (req.url === '/v1/chat/completions') {
    let body = '';
    for await (const chunk of req) body += chunk;
    const parsed = JSON.parse(body || '{}');
    if (parsed.response_format?.type === 'json_object') {
      res.setHeader('Content-Type', 'application/json');
      res.end(JSON.stringify({ choices: [{ message: { content: '{"title":"测试"}' } }] }));
      return;
    }
    res.setHeader('Content-Type', 'text/event-stream');
    res.write('data: {"choices":[{"delta":{"content":"hello"}}]}\n\n');
    res.end('data: [DONE]\n\n');
    return;
  }
  if (req.url === '/v1/images/generations') {
    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify({ data: [{ b64_json: Buffer.from('image').toString('base64') }] }));
    return;
  }
  res.statusCode = 404;
  res.end();
});

await new Promise((resolve) => upstream.listen(0, '127.0.0.1', resolve));
const upstreamAddress = upstream.address();
process.env.AI_UPSTREAM_BASE_URL = `http://127.0.0.1:${upstreamAddress.port}`;
process.env.AI_IMAGE_MODELS = 'image-model';
process.env.AI_REQUEST_TIMEOUT_MS = '5000';

const { fetchModels, proxyAiResponse, requestChatCompletion, requestImageBase64 } = await import(
  '../src/services/aiGateway.js'
);

after(async () => {
  await new Promise((resolve) => upstream.close(resolve));
});

test('model gateway authenticates and filters configured image models', async () => {
  const result = await fetchModels('user-secret-key', 'image', {
    allowedImageModels: ['image-model'],
  });
  assert.equal(receivedAuthorization, 'Bearer user-secret-key');
  assert.deepEqual(result.data, [{ id: 'image-model' }]);
});

test('AI proxy preserves an upstream SSE response', async () => {
  const app = express();
  app.use(express.json());
  app.post('/proxy', async (req, res, next) => {
    try {
      await proxyAiResponse(req, res, {
        apiKey: 'stream-secret-key',
        path: '/v1/chat/completions',
        body: req.body,
      });
    } catch (err) {
      next(err);
    }
  });
  const proxyServer = http.createServer(app);
  await new Promise((resolve) => proxyServer.listen(0, '127.0.0.1', resolve));
  try {
    const address = proxyServer.address();
    const response = await fetch(`http://127.0.0.1:${address.port}/proxy`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ model: 'chat-model', messages: [{ role: 'user', content: 'hi' }] }),
    });
    assert.equal(response.status, 200);
    assert.match(response.headers.get('content-type') || '', /text\/event-stream/);
    assert.equal(response.headers.get('x-accel-buffering'), 'no');
    const body = await response.text();
    assert.match(body, /"content":"hello"/);
    assert.match(body, /data: \[DONE\]/);
    assert.equal(receivedAuthorization, 'Bearer stream-secret-key');
  } finally {
    await new Promise((resolve) => proxyServer.close(resolve));
  }
});

test('document helpers request structured text and base64 images', async () => {
  const content = await requestChatCompletion('document-key', {
    model: 'chat-model',
    messages: [{ role: 'user', content: '生成文档' }],
  });
  assert.equal(content, '{"title":"测试"}');
  const image = await requestImageBase64('document-key', {
    model: 'image-model',
    prompt: '配图',
  });
  assert.equal(image.toString(), 'image');
});
