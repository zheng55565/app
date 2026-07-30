import assert from 'node:assert/strict';
import test from 'node:test';

import {
  defaultAdSettings,
  defaultGameSettings,
  normalizeGameSettings,
  validateRuntimeSettingsInput,
} from '../src/services/runtimeSettings.js';

test('运营配置拒绝静默修正的反向范围和错误宝箱概率', () => {
  const game = defaultGameSettings();
  assert.throws(
    () => validateRuntimeSettingsInput('game', {
      ...game,
      battle_min_eliminated: 4,
      battle_max_eliminated: 2,
    }),
    /最少淘汰房间/
  );
  assert.throws(
    () => validateRuntimeSettingsInput('game', {
      ...game,
      match3_chest_again_basis_points: 8999,
    }),
    /概率合计/
  );
});

test('运营配置接受完整合法设置并保持数值', () => {
  const game = {
    ...defaultGameSettings(),
    rps_payout_basis_points: 18000,
    battle_min_eliminated: 3,
    battle_max_eliminated: 4,
  };
  assert.equal(validateRuntimeSettingsInput('game', game), true);
  assert.deepEqual(normalizeGameSettings(game), game);
});

test('广告上限必须能够容纳至少一次奖励', () => {
  const ad = defaultAdSettings();
  assert.throws(
    () => validateRuntimeSettingsInput('ad', {
      ...ad,
      reward_microunits: 20000,
      daily_reward_max_microunits: 10000,
    }),
    /账号每日额度上限/
  );
  assert.equal(validateRuntimeSettingsInput('ad', ad), true);
});

test('生图白名单拒绝重复、空白和过长模型 ID', () => {
  assert.throws(
    () => validateRuntimeSettingsInput('ai', {
      enabled: true,
      image_models: ['image-a', 'image-a'],
    }),
    /不能重复/
  );
  assert.throws(
    () => validateRuntimeSettingsInput('ai', {
      enabled: true,
      image_models: [123],
    }),
    /必须是非空字符串/
  );
  assert.equal(validateRuntimeSettingsInput('ai', {
    enabled: true,
    image_models: ['gpt-image-1', 'flux-pro'],
  }), true);
});
