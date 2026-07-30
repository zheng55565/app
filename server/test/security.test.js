import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import test from 'node:test';

process.env.AD_CALLBACK_SECRET = 'test-callback-secret-that-is-long-enough';
process.env.RISK_HASH_SECRET = 'test-risk-secret-that-is-long-enough-value';
process.env.AD_REQUIRE_TRANSACTION_ID = 'true';
process.env.AI_IMAGE_MODELS = 'image-test';

const {
  businessDate,
  callbackPlacementMatchesTask,
  hashRiskSubject,
  verifyHjCallback,
  verifyHmacCallback,
} = await import(
  '../src/services/adSecurity.js'
);
const {
  adPolicyAllowsReward,
  normalizeHjCallback,
  sanitizeHjCallbackQuery,
} = await import('../src/routes/adTask.js');
const { validateChatBody, validateImageBody } = await import('../src/services/aiGateway.js');
const { claimProviderTransaction } = await import('../src/services/adTransactions.js');

test('businessDate uses configured timezone instead of client date', () => {
  const date = new Date('2026-07-27T16:30:00.000Z');
  assert.equal(businessDate(date, 'Asia/Shanghai'), '2026-07-28');
  assert.equal(businessDate(date, 'UTC'), '2026-07-27');
});

test('risk hashes are deterministic and scoped by subject type', () => {
  assert.equal(hashRiskSubject('device', 'abc'), hashRiskSubject('device', 'abc'));
  assert.notEqual(hashRiskSubject('device', 'abc'), hashRiskSubject('ip', 'abc'));
  assert.equal(hashRiskSubject('device', 'abc').length, 64);
});

test('advertising callback requires a valid transaction and signature', () => {
  const timestamp = Math.floor(Date.now() / 1000);
  const payload = {
    task_token: 'ad_task_test',
    user_id: 42,
    timestamp,
    transaction_id: 'tx-1',
  };
  payload.sign = crypto
    .createHmac('sha256', process.env.AD_CALLBACK_SECRET)
    .update(
      `${payload.task_token}\n${payload.user_id}\n${payload.timestamp}\n${payload.transaction_id}`
    )
    .digest('hex');
  assert.equal(verifyHmacCallback(payload), true);
  assert.equal(verifyHmacCallback({ ...payload, transaction_id: '' }), false);
  assert.equal(verifyHmacCallback({ ...payload, transaction_id: 'tx-tampered' }), false);
  assert.equal(verifyHmacCallback({ ...payload, sign: '0'.repeat(64) }), false);
  assert.equal(verifyHmacCallback({ ...payload, timestamp: timestamp - 601 }), false);
});

test('advertising policy rejects count and reward overflow at exact boundaries', () => {
  const policy = { maxCount: 6, maxReward: 120000 };
  assert.equal(adPolicyAllowsReward(policy, 100000, 5, 20000), true);
  assert.equal(adPolicyAllowsReward(policy, 100000, 6, 20000), false);
  assert.equal(adPolicyAllowsReward(policy, 100001, 5, 20000), false);
});

test('HJ callback uses SHA-256 securityKey:transId signature', () => {
  const payload = { transaction_id: 'hj-trans-1' };
  payload.sign = crypto
    .createHash('sha256')
    .update(`${process.env.AD_CALLBACK_SECRET}:${payload.transaction_id}`)
    .digest('hex');
  assert.equal(verifyHjCallback(payload), true);
  assert.equal(verifyHjCallback({ ...payload, transaction_id: 'tampered' }), false);
  assert.equal(verifyHjCallback({ ...payload, sign: '0'.repeat(64) }), false);
});

test('HJ callback macros normalize JSON and Java-map EXTRAINFO', () => {
  const base = {
    userId: '42',
    transId: 'tx-1',
    sign: 'a'.repeat(64),
    placementId: 'reward-home',
  };
  const json = normalizeHjCallback({
    ...base,
    extrainfo: JSON.stringify({ purpose: 'home_balance', task_token: 'ad_task_json' }),
  });
  assert.equal(json.task_token, 'ad_task_json');
  assert.equal(json.purpose, 'home_balance');
  assert.equal(json.user_id, '42');
  assert.equal(json.transaction_id, 'tx-1');
  assert.equal(json.placement_id, 'reward-home');

  const javaMap = normalizeHjCallback({
    ...base,
    extrainfo: '{purpose=home_balance, task_token=ad_task_java}',
  });
  assert.equal(javaMap.task_token, 'ad_task_java');
  assert.equal(javaMap.purpose, 'home_balance');

  const recovery = normalizeHjCallback({
    ...base,
    extrainfo: '{purpose=game_recovery, task_token=game_ad_example}',
  });
  assert.equal(recovery.task_token, 'game_ad_example');
  assert.equal(recovery.purpose, 'game_recovery');
});

test('HJ callback audit payload redacts signatures without losing macro evidence', () => {
  const sanitized = sanitizeHjCallbackQuery({
    userId: '7',
    transId: 'tx-audit-1',
    sign: 'secret-signature-value',
    extrainfo: '{purpose=home_balance, task_token=ad_task_audit}',
  });
  assert.equal(sanitized.sign, '[redacted]');
  assert.equal(sanitized.userId, '7');
  assert.equal(sanitized.transId, 'tx-audit-1');
  assert.match(sanitized.extrainfo, /ad_task_audit/);
});

test('HJ callback accepts the signed runtime placement while other providers stay strict', () => {
  assert.equal(
    callbackPlacementMatchesTask({
      isHj: true,
      taskUnitId: 'aggregate-slot-1',
      callbackPlacementId: 'runtime-network-slot-9',
    }),
    true
  );
  assert.equal(
    callbackPlacementMatchesTask({
      isHj: false,
      taskUnitId: 'aggregate-slot-1',
      callbackPlacementId: 'runtime-network-slot-9',
    }),
    false
  );
  assert.equal(
    callbackPlacementMatchesTask({
      isHj: false,
      taskUnitId: 'aggregate-slot-1',
      callbackPlacementId: 'aggregate-slot-1',
    }),
    true
  );
});

test('one provider transaction cannot reward quota and revive a game', async () => {
  const ledger = new Map();
  const client = {
    async query(sql, params) {
      const key = `${params[0]}:${params[1]}`;
      if (sql.includes('INSERT INTO ad_provider_transactions')) {
        if (ledger.has(key)) return { rows: [] };
        ledger.set(key, { purpose: params[2], task_token: params[3], user_id: params[4] });
        return { rows: [{ provider: params[0] }] };
      }
      return { rows: ledger.has(key) ? [ledger.get(key)] : [] };
    },
  };
  const first = await claimProviderTransaction(client, {
    provider: 'hj', transactionId: 'tx-global-1', purpose: 'home_balance',
    taskToken: 'ad_task_home', userId: 7,
  });
  const retry = await claimProviderTransaction(client, {
    provider: 'hj', transactionId: 'tx-global-1', purpose: 'home_balance',
    taskToken: 'ad_task_home', userId: 7,
  });
  const replay = await claimProviderTransaction(client, {
    provider: 'hj', transactionId: 'tx-global-1', purpose: 'game_recovery',
    taskToken: 'game_ad_other', userId: 7,
  });
  assert.equal(first.ok, true);
  assert.equal(retry.duplicated, true);
  assert.equal(replay.ok, false);
});

test('AI request validation bounds prompt and output size', () => {
  assert.equal(
    validateChatBody({ model: 'test', messages: [{ role: 'user', content: 'hello' }], n: 1 }),
    null
  );
  assert.match(
    validateChatBody({ model: 'test', messages: [{ role: 'user', content: 'hello' }], n: 2 }),
    /n=1/
  );
  assert.match(
    validateChatBody({
      model: 'test',
      messages: [{ role: 'user', content: 'hello' }],
      max_tokens: -1,
    }),
    /正整数/
  );
  assert.equal(validateImageBody({ model: 'image-test', prompt: 'a clean diagram', n: 1 }), null);
  assert.match(validateImageBody({ model: 'image-test', prompt: '', n: 1 }), /提示词/);
  assert.match(validateImageBody({ model: 'image-test', prompt: 'ok', n: 1.5 }), /1-4/);
});
