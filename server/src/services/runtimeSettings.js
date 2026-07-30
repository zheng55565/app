import { config } from '../config.js';
import { query, withTransaction } from '../db.js';

const CACHE_TTL_MS = 3000;
const cache = new Map();

function integer(value, fallback, min, max) {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < min || parsed > max) return fallback;
  return parsed;
}

function boolean(value, fallback) {
  return typeof value === 'boolean' ? value : fallback;
}

function stringList(value, fallback, maxItems = 100) {
  if (!Array.isArray(value)) return [...fallback];
  const cleaned = [...new Set(value.map((item) => String(item || '').trim()).filter(Boolean))];
  if (cleaned.length > maxItems || cleaned.some((item) => item.length > 200)) return [...fallback];
  return cleaned;
}

export function defaultGameSettings() {
  return {
    rps_enabled: true,
    mine_enabled: true,
    battle_enabled: true,
    match3_enabled: true,
    rps_payout_basis_points: 15000,
    mine_liability_basis_points: 15000,
    mine_fee_basis_points: 1000,
    battle_fee_basis_points: 1000,
    battle_min_eliminated: 2,
    battle_max_eliminated: 3,
    battle_opponent_min_count: 1,
    battle_opponent_max_count: 2,
    battle_opponent_min_stake: 5,
    battle_opponent_max_stake: 30,
    match3_clear_reward_points: 1,
    match3_chest_again_basis_points: 9000,
    match3_chest_1_basis_points: 500,
    match3_chest_5_basis_points: 400,
    match3_chest_10_basis_points: 100,
  };
}

export function normalizeGameSettings(input = {}) {
  const defaults = defaultGameSettings();
  const value = {
    rps_enabled: boolean(input.rps_enabled, defaults.rps_enabled),
    mine_enabled: boolean(input.mine_enabled, defaults.mine_enabled),
    battle_enabled: boolean(input.battle_enabled, defaults.battle_enabled),
    match3_enabled: boolean(input.match3_enabled, defaults.match3_enabled),
    rps_payout_basis_points: integer(input.rps_payout_basis_points, defaults.rps_payout_basis_points, 10000, 30000),
    mine_liability_basis_points: integer(input.mine_liability_basis_points, defaults.mine_liability_basis_points, 10000, 30000),
    mine_fee_basis_points: integer(input.mine_fee_basis_points, defaults.mine_fee_basis_points, 0, 3000),
    battle_fee_basis_points: integer(input.battle_fee_basis_points, defaults.battle_fee_basis_points, 0, 3000),
    battle_min_eliminated: integer(input.battle_min_eliminated, defaults.battle_min_eliminated, 1, 7),
    battle_max_eliminated: integer(input.battle_max_eliminated, defaults.battle_max_eliminated, 1, 7),
    battle_opponent_min_count: integer(input.battle_opponent_min_count, defaults.battle_opponent_min_count, 0, 5),
    battle_opponent_max_count: integer(input.battle_opponent_max_count, defaults.battle_opponent_max_count, 0, 5),
    battle_opponent_min_stake: integer(input.battle_opponent_min_stake, defaults.battle_opponent_min_stake, 1, 1000),
    battle_opponent_max_stake: integer(input.battle_opponent_max_stake, defaults.battle_opponent_max_stake, 1, 1000),
    match3_clear_reward_points: integer(input.match3_clear_reward_points, defaults.match3_clear_reward_points, 0, 100),
    match3_chest_again_basis_points: integer(input.match3_chest_again_basis_points, defaults.match3_chest_again_basis_points, 0, 10000),
    match3_chest_1_basis_points: integer(input.match3_chest_1_basis_points, defaults.match3_chest_1_basis_points, 0, 10000),
    match3_chest_5_basis_points: integer(input.match3_chest_5_basis_points, defaults.match3_chest_5_basis_points, 0, 10000),
    match3_chest_10_basis_points: integer(input.match3_chest_10_basis_points, defaults.match3_chest_10_basis_points, 0, 10000),
  };
  if (value.battle_min_eliminated > value.battle_max_eliminated) {
    [value.battle_min_eliminated, value.battle_max_eliminated] =
      [value.battle_max_eliminated, value.battle_min_eliminated];
  }
  if (value.battle_opponent_min_count > value.battle_opponent_max_count) {
    [value.battle_opponent_min_count, value.battle_opponent_max_count] =
      [value.battle_opponent_max_count, value.battle_opponent_min_count];
  }
  if (value.battle_opponent_min_stake > value.battle_opponent_max_stake) {
    [value.battle_opponent_min_stake, value.battle_opponent_max_stake] =
      [value.battle_opponent_max_stake, value.battle_opponent_min_stake];
  }
  const chestTotal = value.match3_chest_again_basis_points +
    value.match3_chest_1_basis_points + value.match3_chest_5_basis_points +
    value.match3_chest_10_basis_points;
  if (chestTotal !== 10000) {
    value.match3_chest_again_basis_points = defaults.match3_chest_again_basis_points;
    value.match3_chest_1_basis_points = defaults.match3_chest_1_basis_points;
    value.match3_chest_5_basis_points = defaults.match3_chest_5_basis_points;
    value.match3_chest_10_basis_points = defaults.match3_chest_10_basis_points;
  }
  return value;
}

export function defaultAdSettings() {
  return {
    rewarded_enabled: config.ad.rewardedEnabled,
    reward_microunits: config.ad.rewardMicrounits,
    daily_max: config.ad.dailyMax,
    daily_reward_max_microunits: config.risk.dailyRewardMaxMicrounits,
    device_daily_max: config.risk.dailyMaxPerDevice,
    device_reward_max_microunits: config.risk.dailyRewardMaxPerDeviceMicrounits,
    ip_daily_max: config.risk.dailyMaxPerIp,
    ip_reward_max_microunits: config.risk.dailyRewardMaxPerIpMicrounits,
  };
}

export function normalizeAdSettings(input = {}) {
  const defaults = defaultAdSettings();
  return {
    rewarded_enabled: boolean(input.rewarded_enabled, defaults.rewarded_enabled),
    reward_microunits: integer(input.reward_microunits, defaults.reward_microunits, 1, 100000000),
    daily_max: integer(input.daily_max, defaults.daily_max, 1, 100),
    daily_reward_max_microunits: integer(input.daily_reward_max_microunits, defaults.daily_reward_max_microunits, 1, 1000000000),
    device_daily_max: integer(input.device_daily_max, defaults.device_daily_max, 1, 500),
    device_reward_max_microunits: integer(input.device_reward_max_microunits, defaults.device_reward_max_microunits, 1, 1000000000),
    ip_daily_max: integer(input.ip_daily_max, defaults.ip_daily_max, 1, 5000),
    ip_reward_max_microunits: integer(input.ip_reward_max_microunits, defaults.ip_reward_max_microunits, 1, 10000000000),
  };
}

export function defaultAiSettings() {
  return { enabled: config.ai.enabled, image_models: [...config.ai.imageModels] };
}

export function normalizeAiSettings(input = {}) {
  const defaults = defaultAiSettings();
  return {
    enabled: boolean(input.enabled, defaults.enabled),
    image_models: stringList(input.image_models, defaults.image_models),
  };
}

const namespaces = {
  game: normalizeGameSettings,
  ad: normalizeAdSettings,
  ai: normalizeAiSettings,
};

const integerRanges = {
  game: {
    rps_payout_basis_points: [10000, 30000],
    mine_liability_basis_points: [10000, 30000],
    mine_fee_basis_points: [0, 3000],
    battle_fee_basis_points: [0, 3000],
    battle_min_eliminated: [1, 7],
    battle_max_eliminated: [1, 7],
    battle_opponent_min_count: [0, 5],
    battle_opponent_max_count: [0, 5],
    battle_opponent_min_stake: [1, 1000],
    battle_opponent_max_stake: [1, 1000],
    match3_clear_reward_points: [0, 100],
    match3_chest_again_basis_points: [0, 10000],
    match3_chest_1_basis_points: [0, 10000],
    match3_chest_5_basis_points: [0, 10000],
    match3_chest_10_basis_points: [0, 10000],
  },
  ad: {
    reward_microunits: [1, 100000000],
    daily_max: [1, 100],
    daily_reward_max_microunits: [1, 1000000000],
    device_daily_max: [1, 500],
    device_reward_max_microunits: [1, 1000000000],
    ip_daily_max: [1, 5000],
    ip_reward_max_microunits: [1, 10000000000],
  },
};

function invalidSetting(message) {
  const error = new Error(message);
  error.code = 'INVALID_RUNTIME_SETTINGS';
  error.status = 400;
  return error;
}

export function validateRuntimeSettingsInput(namespace, input) {
  if (!namespaces[namespace]) throw invalidSetting(`未知运行配置: ${namespace}`);
  if (!input || typeof input !== 'object' || Array.isArray(input)) {
    throw invalidSetting('配置内容必须是对象');
  }
  const booleanFields = namespace === 'game'
    ? ['rps_enabled', 'mine_enabled', 'battle_enabled', 'match3_enabled']
    : namespace === 'ad'
      ? ['rewarded_enabled']
      : ['enabled'];
  for (const field of booleanFields) {
    if (typeof input[field] !== 'boolean') throw invalidSetting(`${field} 必须是布尔值`);
  }
  for (const [field, [min, max]] of Object.entries(integerRanges[namespace] || {})) {
    if (!Number.isSafeInteger(input[field]) || input[field] < min || input[field] > max) {
      throw invalidSetting(`${field} 必须是 ${min} 到 ${max} 之间的整数`);
    }
  }
  if (namespace === 'game') {
    if (input.battle_min_eliminated > input.battle_max_eliminated) {
      throw invalidSetting('最少淘汰房间不能大于最多淘汰房间');
    }
    if (input.battle_opponent_min_count > input.battle_opponent_max_count) {
      throw invalidSetting('每房最少对手不能大于最多对手');
    }
    if (input.battle_opponent_min_stake > input.battle_opponent_max_stake) {
      throw invalidSetting('对手最少投入不能大于最多投入');
    }
    const chestTotal = input.match3_chest_again_basis_points +
      input.match3_chest_1_basis_points + input.match3_chest_5_basis_points +
      input.match3_chest_10_basis_points;
    if (chestTotal !== 10000) throw invalidSetting('宝箱概率合计必须等于 100%');
  }
  if (namespace === 'ai') {
    if (!Array.isArray(input.image_models)) throw invalidSetting('生图模型白名单必须是数组');
    if (input.image_models.some((item) => typeof item !== 'string')) {
      throw invalidSetting('生图模型 ID 必须是非空字符串');
    }
    const cleaned = stringList(input.image_models, [], 100);
    if (cleaned.length !== input.image_models.length) {
      throw invalidSetting('生图模型最多 100 个，不能重复、留空或超过 200 个字符');
    }
  }
  if (namespace === 'ad') {
    if (input.daily_reward_max_microunits < input.reward_microunits) {
      throw invalidSetting('账号每日额度上限不能小于单次奖励');
    }
    if (input.device_reward_max_microunits < input.reward_microunits) {
      throw invalidSetting('设备每日额度上限不能小于单次奖励');
    }
    if (input.ip_reward_max_microunits < input.reward_microunits) {
      throw invalidSetting('IP 每日额度上限不能小于单次奖励');
    }
  }
  return true;
}

export function normalizeRuntimeSettings(namespace, value) {
  const normalize = namespaces[namespace];
  if (!normalize) throw new Error(`未知运行配置: ${namespace}`);
  return normalize(value);
}

export async function getRuntimeSettings(namespace, { fresh = false } = {}) {
  const normalize = namespaces[namespace];
  if (!normalize) throw new Error(`未知运行配置: ${namespace}`);
  const cached = cache.get(namespace);
  if (!fresh && cached && cached.expiresAt > Date.now()) return structuredClone(cached.value);
  const { rows } = await query(
    `SELECT setting_value FROM runtime_settings WHERE setting_key=$1`,
    [namespace]
  );
  const value = normalize(rows[0]?.setting_value || {});
  cache.set(namespace, { value, expiresAt: Date.now() + CACHE_TTL_MS });
  return structuredClone(value);
}

export async function updateRuntimeSettings(namespace, input, adminUsername, requestMeta = {}) {
  const value = normalizeRuntimeSettings(namespace, input);
  await withTransaction(async (client) => {
    const { rows } = await client.query(
      `SELECT setting_value FROM runtime_settings WHERE setting_key=$1 FOR UPDATE`,
      [namespace]
    );
    const previous = namespaces[namespace](rows[0]?.setting_value || {});
    await client.query(
      `INSERT INTO runtime_settings (setting_key,setting_value,updated_by,updated_at)
       VALUES ($1,$2::jsonb,$3,NOW())
       ON CONFLICT (setting_key) DO UPDATE SET
         setting_value=EXCLUDED.setting_value,updated_by=EXCLUDED.updated_by,updated_at=NOW()`,
      [namespace, JSON.stringify(value), adminUsername]
    );
    await client.query(
      `INSERT INTO admin_audit_logs
         (username,event_type,result,detail,ip_address,user_agent)
       VALUES ($1,'runtime_settings_update','success',$2,$3,$4)`,
      [
        adminUsername,
        JSON.stringify({ namespace, previous, current: value }).slice(0, 300),
        String(requestMeta.ip || '').slice(0, 60) || null,
        String(requestMeta.userAgent || '').slice(0, 300) || null,
      ]
    );
  });
  cache.delete(namespace);
  return value;
}

export function clearRuntimeSettingsCache() {
  cache.clear();
}
