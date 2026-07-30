import assert from 'node:assert/strict';
import test from 'node:test';

import { safeHttpUrl, validateAdEventBody } from '../src/routes/webAds.js';

const validEvent = {
  event_id: '4f0f55b5-2e87-4ffd-86fa-2391b4775046',
  creative_id: 'house-ai-workbench-v1',
  placement: 'global_interstitial',
  trigger: 'game_settlement',
  event_type: 'impression',
  session_id: '48afb2a8-b828-49bb-8e64-7d89b65d46c0',
  metadata: { route: '/games' },
};

test('ad telemetry accepts bounded idempotency fields', () => {
  const result = validateAdEventBody(validEvent);
  assert.equal(result.ok, true);
  assert.equal(result.value.eventType, 'impression');
});

test('ad telemetry rejects invalid events and oversized metadata', () => {
  assert.equal(validateAdEventBody({ ...validEvent, event_type: 'reward' }).ok, false);
  assert.equal(validateAdEventBody({ ...validEvent, event_id: 'not-a-uuid' }).ok, false);
  assert.equal(
    validateAdEventBody({ ...validEvent, metadata: { data: 'x'.repeat(5000) } }).ok,
    false
  );
});

test('web ad click URLs only permit http and https', () => {
  assert.match(safeHttpUrl('https://example.com/path'), /^https:/);
  assert.equal(safeHttpUrl('javascript:alert(1)'), '');
  assert.equal(safeHttpUrl('file:///tmp/secret'), '');
});
