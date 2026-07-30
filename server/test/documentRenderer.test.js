import assert from 'node:assert/strict';
import test from 'node:test';

import {
  parseDocumentPlan,
  renderDocx,
  renderPptx,
  safeArtifactTitle,
} from '../src/services/documentRenderer.js';

test('document plans are bounded and rendered as Office packages', async () => {
  const wordPlan = parseDocumentPlan(
    JSON.stringify({
      title: '项目计划',
      subtitle: '实施说明',
      sections: [
        { heading: '目标', paragraphs: ['完成客户端与服务端联调。'], bullets: ['可验证', '可下载'] },
      ],
    }),
    'docx',
    { maxSections: 5 }
  );
  const word = await renderDocx(wordPlan);
  assert.equal(word.subarray(0, 2).toString(), 'PK');
  assert.ok(word.length > 1000);

  const pptPlan = parseDocumentPlan(
    JSON.stringify({
      title: '产品方案',
      subtitle: 'AI工作台',
      slides: [
        {
          title: '能力',
          bullets: ['生成Word', '生成PPT'],
          body: '支持异步任务与下载。',
          speaker_notes: '介绍文档队列和配图能力。',
        },
      ],
    }),
    'pptx',
    { maxSlides: 5 }
  );
  const onePixelPng = Buffer.from(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    'base64'
  );
  const ppt = await renderPptx(pptPlan, new Map([[0, onePixelPng]]));
  assert.equal(ppt.subarray(0, 2).toString(), 'PK');
  assert.ok(ppt.length > 1000);
});

test('document parser rejects empty content and sanitizes file names', () => {
  assert.throws(() => parseDocumentPlan('{"title":"空","sections":[]}', 'docx'));
  assert.equal(safeArtifactTitle('方案:2026/测试?'), '方案_2026_测试_');
});
