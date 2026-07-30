// 广告任务路由
//
// GET  /api/ad-task/today               今日次数与奖励信息
// POST /api/ad-task/start               创建广告任务，签发一次性 task_token
// GET  /api/ad-task/status/:task_token  查询任务状态（App 播完广告后轮询）
// POST /api/ad-callback/reward          广告平台服务端回调（在 index.js 单独挂载，不走用户鉴权）
//
// v2：金额统一 BIGINT microunits（1 元 = 1,000,000）；发奖后通过 stationClient
// 幂等入账中转站（方案 §8.2），本地钱包作为余额镜像（§16）。

import { Router } from 'express';
import crypto from 'node:crypto';
import { query, withTransaction } from '../db.js';
import { config } from '../config.js';
import { requireAuth } from '../middleware/auth.js';
import { creditReward } from '../services/stationClient.js';
import {
  businessDate,
  callbackPlacementMatchesTask,
  getAdRiskContext,
  verifyHjCallback,
  verifyHmacCallback,
} from '../services/adSecurity.js';
import { claimProviderTransaction } from '../services/adTransactions.js';
import { verifyGameRecoveryCallback } from '../services/gameRecovery.js';
import { getRuntimeSettings } from '../services/runtimeSettings.js';

export const adTaskRouter = Router();
export const adCallbackRouter = Router();

const adPlatform = () => config.ad.provider;
// 首页余额广告位（唯一允许进钱包发奖逻辑的广告位）。
// 小游戏补救广告位（AD_UNIT_REWARDED_GAME）不建任务、不回调、永不发奖。
const homeUnitId = () => config.ad.unitRewardedHome;

const toLegacyAmount = (micro) => (Number(micro) / 1000000).toFixed(6);

function rejectReward(status, message) {
  const err = new Error(message);
  err.code = 'AD_REWARD_REJECTED';
  err.status = status;
  throw err;
}

async function getTodayLimit(userId, adSettings) {
  const date = businessDate();
  const { rows } = await query(
    `SELECT watched_count, max_count, rewarded_microunits, max_reward_microunits
     FROM daily_ad_limits WHERE user_id = $1 AND date = $2`,
    [userId, date]
  );
  return {
    date,
    watched_count: Number(rows[0]?.watched_count || 0),
    max_count: Math.min(Number(rows[0]?.max_count ?? adSettings.daily_max), adSettings.daily_max),
    rewarded_microunits: Number(rows[0]?.rewarded_microunits || 0),
    max_reward_microunits: Math.min(
      Number(rows[0]?.max_reward_microunits ?? adSettings.daily_reward_max_microunits),
      adSettings.daily_reward_max_microunits
    ),
  };
}

async function getSubjectLimit(subjectType, subjectHash, date) {
  if (!subjectHash) return null;
  const { rows } = await query(
    `SELECT watched_count, rewarded_microunits, max_count, max_reward_microunits
     FROM daily_ad_subject_limits
     WHERE subject_type = $1 AND subject_hash = $2 AND date = $3`,
    [subjectType, subjectHash, date]
  );
  return rows[0] || null;
}

function subjectPolicy(subjectType, adSettings) {
  if (subjectType === 'device') {
    return {
      maxCount: adSettings.device_daily_max,
      maxReward: adSettings.device_reward_max_microunits,
    };
  }
  return {
    maxCount: adSettings.ip_daily_max,
    maxReward: adSettings.ip_reward_max_microunits,
  };
}

async function incrementSubjectLimit(
  client,
  subjectType,
  subjectHash,
  date,
  rewardMicrounits,
  adSettings
) {
  if (!subjectHash) return true;
  const policy = subjectPolicy(subjectType, adSettings);
  if (policy.maxCount <= 0 || policy.maxReward <= 0) return true;
  const { rows } = await client.query(
    `INSERT INTO daily_ad_subject_limits
       (subject_type, subject_hash, date, watched_count, rewarded_microunits,
        max_count, max_reward_microunits)
     VALUES ($1, $2, $3, 1, $4, $5, $6)
     ON CONFLICT (subject_type, subject_hash, date) DO UPDATE
       SET watched_count = daily_ad_subject_limits.watched_count + 1,
           rewarded_microunits = daily_ad_subject_limits.rewarded_microunits + EXCLUDED.rewarded_microunits,
           max_count = LEAST(daily_ad_subject_limits.max_count, EXCLUDED.max_count),
           max_reward_microunits = LEAST(
             daily_ad_subject_limits.max_reward_microunits,
             EXCLUDED.max_reward_microunits
           ),
           updated_at = NOW()
       WHERE daily_ad_subject_limits.watched_count < LEAST(
               daily_ad_subject_limits.max_count, EXCLUDED.max_count
             )
         AND daily_ad_subject_limits.rewarded_microunits + EXCLUDED.rewarded_microunits
               <= LEAST(
                 daily_ad_subject_limits.max_reward_microunits,
                 EXCLUDED.max_reward_microunits
               )
     RETURNING watched_count`,
    [subjectType, subjectHash, date, rewardMicrounits, policy.maxCount, policy.maxReward]
  );
  return rows.length > 0;
}

export function adPolicyAllowsReward(policy, rewardedMicrounits, watchedCount, rewardMicrounits) {
  return Number(watchedCount) < Number(policy.maxCount) &&
    Number(rewardedMicrounits) + Number(rewardMicrounits) <= Number(policy.maxReward);
}

adTaskRouter.get('/today', requireAuth, async (req, res, next) => {
  try {
    const adSettings = await getRuntimeSettings('ad');
    const limit = await getTodayLimit(req.user.id, adSettings);
    const rewardQuota = Math.round(
      (adSettings.reward_microunits * config.station.quotaPerCny) / 1000000
    );
    res.json({
      date: limit.date,
      watched_count: limit.watched_count,
      max_count: limit.max_count,
      remaining_count: Math.max(0, limit.max_count - limit.watched_count),
      enabled: adSettings.rewarded_enabled,
      reward_amount_microunits: adSettings.reward_microunits,
      reward_quota: rewardQuota,
      reward_usd: rewardQuota / config.station.quotaPerUsd,
    });
  } catch (err) {
    next(err);
  }
});

adTaskRouter.post('/start', requireAuth, async (req, res, next) => {
  try {
    const adSettings = await getRuntimeSettings('ad');
    if (!adSettings.rewarded_enabled) {
      return res.status(503).json({ code: 'REWARDED_AD_DISABLED', message: '激励广告暂未开放' });
    }
    // v2 主身份判断：users.linuxdo_user_id（不再查 linuxdo_bindings）
    if (!req.user.linuxdo_user_id) {
      return res.status(403).json({ code: 403, message: '请先通过 Linux.do 登录' });
    }
    if (!req.user.station_user_id) {
      return res.status(403).json({
        code: 'STATION_ACCOUNT_REQUIRED',
        message: '本站中转账号未关联，暂时不能领取额度',
      });
    }
    const risk = getAdRiskContext(req);
    const limit = await getTodayLimit(req.user.id, adSettings);
    if (limit.watched_count >= limit.max_count) {
      return res.status(429).json({ code: 429, message: '今日广告次数已用完' });
    }
    if (
      limit.rewarded_microunits + adSettings.reward_microunits >
      limit.max_reward_microunits
    ) {
      return res.status(429).json({ code: 429, message: '今日广告奖励额度已达上限' });
    }
    for (const [type, hash] of [['device', risk.deviceHash], ['ip', risk.ipHash]]) {
      const policy = subjectPolicy(type, adSettings);
      if (!hash || policy.maxCount <= 0) continue;
      const subject = await getSubjectLimit(type, hash, limit.date);
      const effectivePolicy = {
        maxCount: subject ? Math.min(Number(subject.max_count), policy.maxCount) : policy.maxCount,
        maxReward: subject
          ? Math.min(Number(subject.max_reward_microunits), policy.maxReward)
          : policy.maxReward,
      };
      if (subject && !adPolicyAllowsReward(
        effectivePolicy,
        subject.rewarded_microunits,
        subject.watched_count,
        adSettings.reward_microunits
      )) {
        return res.status(429).json({
          code: type === 'device' ? 'DEVICE_DAILY_LIMIT' : 'NETWORK_DAILY_LIMIT',
          message: type === 'device' ? '本设备今日奖励次数已用完' : '当前网络今日奖励次数已达上限',
        });
      }
    }

    const taskToken = `ad_task_${crypto.randomBytes(16).toString('hex')}`;
    const created = await withTransaction(async (client) => {
      // 锁用户行，使并发 start 请求串行检查冷却和待处理任务数。
      await client.query(`SELECT id FROM users WHERE id = $1 FOR UPDATE`, [req.user.id]);
      await client.query(
        `UPDATE ad_tasks SET status = 'expired', updated_at = NOW()
         WHERE user_id = $1 AND status = 'created' AND expires_at <= NOW()`,
        [req.user.id]
      );
      const { rows: recentRows } = await client.query(
        `SELECT created_at FROM ad_tasks
         WHERE user_id = $1 AND created_at > NOW() - ($2 || ' seconds')::interval
         ORDER BY created_at DESC LIMIT 1`,
        [req.user.id, String(config.ad.taskStartCooldownSec)]
      );
      if (recentRows.length > 0) return { ok: false, message: '操作过快，请稍后再试' };
      const { rows: pendingRows } = await client.query(
        `SELECT COUNT(*)::int AS count FROM ad_tasks
         WHERE user_id = $1 AND status = 'created' AND expires_at > NOW()`,
        [req.user.id]
      );
      if (pendingRows[0].count >= config.ad.maxPendingPerUser) {
        return { ok: false, message: '已有广告任务处理中，请稍后再试' };
      }
      if (risk.deviceHash && config.risk.maxPendingPerDevice > 0) {
        const { rows: devicePendingRows } = await client.query(
          `SELECT COUNT(*)::int AS count FROM ad_tasks
           WHERE device_hash = $1 AND status = 'created' AND expires_at > NOW()`,
          [risk.deviceHash]
        );
        if (devicePendingRows[0].count >= config.risk.maxPendingPerDevice) {
          return { ok: false, message: '本设备已有广告任务处理中，请稍后再试' };
        }
      }
      await client.query(
        `INSERT INTO ad_tasks (user_id, ad_platform, ad_unit_id, task_token,
                               reward_amount, reward_amount_microunits, device_hash,
                               start_ip_hash, policy_snapshot, expires_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9::jsonb,
                 NOW() + ($10 || ' minutes')::interval)`,
        [
          req.user.id,
          adPlatform(),
          homeUnitId(),
          taskToken,
          toLegacyAmount(adSettings.reward_microunits),
          adSettings.reward_microunits,
          risk.deviceHash,
          risk.ipHash,
          JSON.stringify(adSettings),
          String(config.ad.taskExpireMinutes),
        ]
      );
      return { ok: true };
    });
    if (!created.ok) {
      return res.status(429).json({ code: 'AD_TASK_BUSY', message: created.message });
    }
    res.json({
      task_token: taskToken,
      ad_platform: adPlatform(),
      ad_unit_id: homeUnitId(),
      reward_amount_microunits: adSettings.reward_microunits,
    });
  } catch (err) {
    next(err);
  }
});

adTaskRouter.get('/status/:task_token', requireAuth, async (req, res, next) => {
  try {
    const { rows } = await query(
      `SELECT task_token, status, reward_amount_microunits, rewarded_at,
              client_transaction_id, provider_transaction_id
       FROM ad_tasks
       WHERE task_token = $1 AND user_id = $2`,
      [req.params.task_token, req.user.id]
    );
    if (rows.length === 0) {
      return res.status(404).json({ code: 404, message: '任务不存在' });
    }
    const task = rows[0];
    res.json({
      task_token: task.task_token,
      status: task.status,
      reward_amount_microunits: Number(task.reward_amount_microunits),
      rewarded_at: task.rewarded_at,
      client_evidence_received: Boolean(task.client_transaction_id),
      platform_callback_received: Boolean(task.provider_transaction_id),
    });
  } catch (err) {
    next(err);
  }
});

// SDK 的 onVideoRewarded 回传 transId 后由 App 立即登记。
// 该接口只保存交叉核对凭据，绝不发奖；钱包入账仍只能由签名广告回调触发。
adTaskRouter.post('/client-complete', requireAuth, async (req, res, next) => {
  try {
    const taskToken = String(req.body?.task_token || '').trim();
    const transactionId = String(req.body?.transaction_id || '').trim();
    if (!taskToken || !/^[^\s\u0000-\u001f]{4,150}$/.test(transactionId)) {
      return res.status(400).json({ code: 'INVALID_AD_EVIDENCE', message: '广告交易凭据无效' });
    }

    const result = await withTransaction(async (client) => {
      const { rows } = await client.query(
        `SELECT id, ad_platform, status, expires_at, client_transaction_id,
                provider_transaction_id
         FROM ad_tasks
         WHERE task_token = $1 AND user_id = $2
         FOR UPDATE`,
        [taskToken, req.user.id]
      );
      const task = rows[0];
      if (!task) return { ok: false, status: 404, message: '广告任务不存在' };
      if (task.client_transaction_id && task.client_transaction_id !== transactionId) {
        return { ok: false, status: 409, message: '该任务已登记其他交易号' };
      }
      if (task.provider_transaction_id && task.provider_transaction_id !== transactionId) {
        return { ok: false, status: 409, message: '客户端交易号与平台回调不一致' };
      }
      if (task.status !== 'rewarded' && task.expires_at && new Date(task.expires_at) < new Date()) {
        return { ok: false, status: 410, message: '广告任务已过期' };
      }
      const { rows: duplicates } = await client.query(
        `SELECT 1 FROM ad_tasks
         WHERE ad_platform = $1 AND client_transaction_id = $2 AND id <> $3
         LIMIT 1`,
        [task.ad_platform, transactionId, task.id]
      );
      if (duplicates.length > 0) {
        return { ok: false, status: 409, message: '该广告交易号已被其他任务使用' };
      }
      await client.query(
        `UPDATE ad_tasks
         SET client_transaction_id = $2,
             client_completed_at = COALESCE(client_completed_at, NOW()),
             updated_at = NOW()
         WHERE id = $1`,
        [task.id, transactionId]
      );
      return {
        ok: true,
        already_rewarded: task.status === 'rewarded',
        platform_callback_received: Boolean(task.provider_transaction_id),
      };
    });
    if (!result.ok) {
      return res.status(result.status).json({ code: 'AD_EVIDENCE_REJECTED', message: result.message });
    }
    res.json(result);
  } catch (err) {
    if (err?.code === '23505') {
      return res.status(409).json({ code: 'AD_EVIDENCE_DUPLICATE', message: '广告交易号已被使用' });
    }
    next(err);
  }
});

// 开发用：模拟广告平台回调（真实广告 SDK 接入前的演示闭环）
// 仅 AD_DEV_SIMULATE=true 时开放；自签 HMAC 后走真实回调逻辑，不绕过任何校验
adTaskRouter.post('/dev-complete', requireAuth, async (req, res, next) => {
  try {
    if (!config.ad.devSimulate) {
      return res.status(404).json({ code: 404, message: '接口不存在' });
    }
    const { task_token } = req.body || {};
    if (!task_token) {
      return res.status(400).json({ code: 400, message: '缺少 task_token' });
    }
    const timestamp = Math.floor(Date.now() / 1000);
    const transactionId = `dev_sim_${task_token}`;
    const sign = crypto
      .createHmac('sha256', config.ad.callbackSecret)
      .update(`${task_token}\n${req.user.id}\n${timestamp}\n${transactionId}`)
      .digest('hex');
    const cbRes = await fetch(`http://localhost:${config.port}/api/ad-callback/reward`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        task_token,
        user_id: req.user.id,
        timestamp,
        sign,
        transaction_id: transactionId,
      }),
    });
    res.status(cbRes.status).json(await cbRes.json());
  } catch (err) {
    next(err);
  }
});

// ===== 广告平台服务端回调 =====
//
// 签名校验方式因广告平台而异（穿山甲/优量汇/AdMob SSV 各不相同），
// 这里实现一个通用的 HMAC-SHA256 占位方案：
// sign = HMAC(secret, task_token + "\\n" + user_id + "\\n" + timestamp + "\\n" + transaction_id)
// 接入实际平台时替换 verifySign 即可，其余幂等发奖逻辑通用。
function firstCallbackValue(source, names) {
  for (const name of names) {
    const value = source?.[name];
    if (value != null && String(value).trim() !== '') return value;
  }
  return '';
}

function parseHjExtraInfo(raw) {
  if (raw && typeof raw === 'object') return raw;
  let text = String(raw || '').trim();
  if (!text) return {};
  try {
    text = decodeURIComponent(text);
  } catch (_) {
    // Express may already have URL-decoded the query value.
  }
  try {
    const parsed = JSON.parse(text);
    if (parsed && typeof parsed === 'object') return parsed;
  } catch (_) {
    // Some adapters serialize Java maps as {key=value, key2=value2}.
  }
  const result = {};
  for (const match of text.matchAll(/(?:^|[,{&]\s*)([A-Za-z0-9_]+)\s*[:=]\s*["']?([^,"'}&]+)/g)) {
    result[match[1]] = match[2].trim();
  }
  return result;
}

export function normalizeHjCallback(queryString) {
  const extraRaw = firstCallbackValue(queryString, ['extra_info', 'extrainfo', 'EXTRAINFO']);
  const extra = parseHjExtraInfo(extraRaw);
  return {
    callback_provider: 'hj',
    purpose:
      firstCallbackValue(extra, ['purpose']) ||
      firstCallbackValue(queryString, ['purpose', 'PURPOSE']),
    task_token:
      firstCallbackValue(extra, ['task_token', 'taskToken']) ||
      firstCallbackValue(queryString, ['task_token', 'taskToken']),
    user_id: firstCallbackValue(queryString, ['user_id', 'userId', 'USER_ID']),
    transaction_id: firstCallbackValue(queryString, [
      'transaction_id',
      'trans_id',
      'transId',
      'TRANS_ID',
    ]),
    sign: firstCallbackValue(queryString, ['sign', 'SIGN']),
    placement_id: firstCallbackValue(queryString, [
      'placement_id',
      'placementId',
      'PLACEMENT_ID',
    ]),
    reward_amount: firstCallbackValue(queryString, [
      'reward_amount',
      'rewardAmount',
      'REWARD_AMOUNT',
    ]),
    reward_name: firstCallbackValue(queryString, [
      'reward_name',
      'rewardName',
      'REWARD_NAME',
    ]),
    extra_info: extraRaw,
  };
}

export function sanitizeHjCallbackQuery(queryString) {
  const sanitized = {};
  for (const [key, rawValue] of Object.entries(queryString || {})) {
    if (String(key).toLowerCase() === 'sign') {
      sanitized[key] = '[redacted]';
      continue;
    }
    const values = Array.isArray(rawValue) ? rawValue : [rawValue];
    sanitized[key] = values
      .map((value) => String(value ?? '').slice(0, 4000))
      .join(',');
  }
  return sanitized;
}

async function beginHjCallbackAudit(req, payload) {
  const { rows } = await query(
    `INSERT INTO ad_callback_audits
       (provider, request_method, request_path, user_id, transaction_id,
        task_token, placement_id, has_extra_info, signature_present, payload)
     VALUES ('hj', $1, $2, $3, $4, $5, $6, $7, $8, $9::jsonb)
     RETURNING id`,
    [
      req.method,
      req.path,
      String(payload.user_id || '') || null,
      String(payload.transaction_id || '') || null,
      String(payload.task_token || '') || null,
      String(payload.placement_id || '') || null,
      Boolean(payload.extra_info),
      Boolean(payload.sign),
      JSON.stringify(sanitizeHjCallbackQuery(req.query)),
    ]
  );
  return rows[0]?.id || null;
}

function finishHjCallbackAudit(req, res) {
  if (!req.adCallbackAuditId) return;
  query(
    `UPDATE ad_callback_audits
     SET signature_valid = $2, http_status = $3, outcome = $4,
         completed_at = NOW()
     WHERE id = $1`,
    [
      req.adCallbackAuditId,
      req.adCallbackSignatureValid ?? null,
      res.statusCode,
      String(req.adCallbackOutcome || (res.statusCode < 400 ? 'accepted' : 'rejected')).slice(0, 300),
    ]
  ).catch((err) => {
    console.error('[ad-callback] 更新HJ回调审计失败:', err.message);
  });
}

function callbackError(req, res, hj, status, message) {
  req.adCallbackOutcome = message;
  return res.status(status).json(hj ? { isValid: false } : { code: status, message });
}

async function rewardCallback(req, res, next) {
  try {
    const payload = req.adCallbackPayload || req.body || {};
    const isHj = payload.callback_provider === 'hj';
    const signatureValid = isHj
      ? verifyHjCallback(payload)
      : verifyHmacCallback(payload);
    req.adCallbackSignatureValid = signatureValid;
    if (!signatureValid) {
      return callbackError(req, res, isHj, 403, '广告回调签名校验失败');
    }

    if (
      payload.purpose === 'game_recovery' ||
      String(payload.task_token || '').startsWith('game_ad_')
    ) {
      const recovery = await verifyGameRecoveryCallback(payload);
      if (!recovery.ok) {
        return callbackError(req, res, isHj, recovery.status, recovery.message);
      }
      req.adCallbackOutcome = recovery.duplicated ? '游戏广告回调已处理' : '游戏广告回调已验证';
      return res.json(
        isHj
          ? { isValid: true }
          : { code: 0, message: recovery.duplicated ? '已处理' : '复活广告已验证' }
      );
    }

    const result = await withTransaction(async (client) => {
      // 行锁防并发重复发奖
      const { rows: taskRows } = await client.query(
        `SELECT id, user_id, ad_platform, ad_unit_id, reward_amount_microunits,
                device_hash, start_ip_hash, status, expires_at, policy_snapshot,
                client_transaction_id, provider_transaction_id
         FROM ad_tasks
         WHERE task_token = $1 FOR UPDATE`,
        [payload.task_token]
      );
      const task = taskRows[0];
      if (!task) return { ok: false, status: 404, message: 'task_token 不存在' };
      const taskPolicy = {
        ...(await getRuntimeSettings('ad')),
        ...(task.policy_snapshot || {}),
      };
      if (String(task.user_id) !== String(payload.user_id)) {
        return { ok: false, status: 403, message: '任务不属于该用户' };
      }
      if (isHj && task.ad_platform !== 'hj') {
        return { ok: false, status: 403, message: '广告平台与任务不匹配' };
      }
      // 只有首页余额广告位允许发奖；小游戏位（rewarded_game）或任何
      // 未知广告位的回调一律拒绝，杜绝游戏广告刷余额
      if (task.ad_unit_id !== config.ad.unitRewardedHome) {
        return { ok: false, status: 403, message: '该广告位不参与余额发奖' };
      }
      if (
        !callbackPlacementMatchesTask({
          isHj,
          taskUnitId: task.ad_unit_id,
          callbackPlacementId: payload.placement_id,
        })
      ) {
        return { ok: false, status: 403, message: '回调广告位与任务不匹配' };
      }
      if (
        task.client_transaction_id &&
        task.client_transaction_id !== String(payload.transaction_id || '')
      ) {
        return { ok: false, status: 409, message: '平台回调与客户端交易号不一致' };
      }
      if (
        task.provider_transaction_id &&
        task.provider_transaction_id !== String(payload.transaction_id || '')
      ) {
        return { ok: false, status: 409, message: '任务已由另一笔广告交易完成' };
      }
      const transactionClaim = await claimProviderTransaction(client, {
        provider: task.ad_platform,
        transactionId: payload.transaction_id,
        purpose: 'home_balance',
        taskToken: payload.task_token,
        userId: task.user_id,
      });
      if (!transactionClaim.ok) {
        return { ok: false, status: 409, message: transactionClaim.message };
      }
      // 广告平台 transaction_id 防重放：同一次播放只能发一次奖
      // （task_token 行锁保证同任务幂等，这里防的是同一 transaction_id
      //  被用于不同 task_token 的跨任务重放）
      if (payload.transaction_id) {
        const { rows: dupRows } = await client.query(
          `SELECT 1 FROM reward_orders
           WHERE provider = $1 AND provider_transaction_id = $2
             AND ad_task_id <> $3`,
          [task.ad_platform, String(payload.transaction_id), payload.task_token]
        );
        if (dupRows.length > 0) {
          return { ok: false, status: 409, message: 'transaction_id 已被使用' };
        }
      }
      if (task.status === 'rewarded') {
        // 幂等：重复回调直接返回成功。若上次进程在本地事务提交后、调用
        // 中转站前退出，pending 订单仍属于“确定尚未发出”，可由本次回调接续。
        const orderNo = `AD_REWARD_${payload.task_token}`;
        const { rows: pendingOrders } = await client.query(
          `SELECT order_no, station_user_id, linuxdo_user_id, amount_microunits,
                  source, ad_task_id, provider, provider_transaction_id
           FROM reward_orders WHERE order_no = $1 AND status = 'pending' FOR UPDATE`,
          [orderNo]
        );
        return { ok: true, duplicated: true, order: pendingOrders[0] || null };
      }
      if (task.expires_at && new Date(task.expires_at) < new Date()) {
        await client.query(
          `UPDATE ad_tasks SET status = 'expired', updated_at = NOW() WHERE id = $1`,
          [task.id]
        );
        return { ok: false, status: 410, message: '任务已过期' };
      }

      const { rows: userRows } = await client.query(
        `SELECT id, status, linuxdo_user_id, station_user_id FROM users WHERE id = $1`,
        [task.user_id]
      );
      const user = userRows[0];
      if (!user || !user.station_user_id) {
        return { ok: false, status: 409, message: '中转站账号未关联，无法发放额度' };
      }
      if (user?.status === 'banned') {
        return { ok: false, status: 403, message: '用户已被封禁' };
      }

      const rewardDate = businessDate();
      const micro = Number(task.reward_amount_microunits);
      // 账号次数 + 奖励总额同时原子校验，防止并发突破每日上限。
      const { rows: limitRows } = await client.query(
        `INSERT INTO daily_ad_limits
           (user_id, date, watched_count, max_count, rewarded_microunits, max_reward_microunits)
         VALUES ($1, $2, 1, $3, $4, $5)
         ON CONFLICT (user_id, date) DO UPDATE
           SET watched_count = daily_ad_limits.watched_count + 1,
               rewarded_microunits = daily_ad_limits.rewarded_microunits + EXCLUDED.rewarded_microunits,
               max_count = LEAST(daily_ad_limits.max_count, EXCLUDED.max_count),
               max_reward_microunits = LEAST(
                 COALESCE(daily_ad_limits.max_reward_microunits, EXCLUDED.max_reward_microunits),
                 EXCLUDED.max_reward_microunits
               ),
               updated_at = NOW()
           WHERE daily_ad_limits.watched_count < LEAST(daily_ad_limits.max_count, EXCLUDED.max_count)
             AND daily_ad_limits.rewarded_microunits + EXCLUDED.rewarded_microunits
                 <= LEAST(
                   COALESCE(daily_ad_limits.max_reward_microunits, EXCLUDED.max_reward_microunits),
                   EXCLUDED.max_reward_microunits
                 )
         RETURNING watched_count`,
        [
          task.user_id,
          rewardDate,
          taskPolicy.daily_max,
          micro,
          taskPolicy.daily_reward_max_microunits,
        ]
      );
      if (limitRows.length === 0) {
        rejectReward(429, '今日广告次数或奖励额度已达上限');
      }

      if (!(await incrementSubjectLimit(
        client,
        'device',
        task.device_hash,
        rewardDate,
        micro,
        taskPolicy
      ))) {
        rejectReward(429, '本设备今日奖励已达上限');
      }
      if (!(await incrementSubjectLimit(
        client,
        'ip',
        task.start_ip_hash,
        rewardDate,
        micro,
        taskPolicy
      ))) {
        rejectReward(429, '当前网络今日奖励已达上限');
      }

      // 本地钱包镜像：微单位为准，旧 NUMERIC 列同步写入便于对账（§16.2）
      const { rows: walletRows } = await client.query(
        `UPDATE wallets
         SET balance_microunits = balance_microunits + $2,
             total_ad_income_microunits = total_ad_income_microunits + $2,
             balance = balance + $3::numeric,
             total_ad_income = total_ad_income + $3::numeric,
             updated_at = NOW()
         WHERE user_id = $1
         RETURNING balance_microunits`,
        [task.user_id, micro, toLegacyAmount(micro)]
      );
      const balanceAfter = Number(walletRows[0].balance_microunits);
      await client.query(
        `INSERT INTO wallet_records (user_id, amount, balance_after, amount_microunits,
                                     balance_after_microunits, type, source, related_id, remark)
         VALUES ($1, $2::numeric, $3::numeric, $4, $5, 'ad_reward', 'ad_callback', $6, '激励视频广告奖励')`,
        [
          task.user_id,
          toLegacyAmount(micro),
          toLegacyAmount(balanceAfter),
          micro,
          balanceAfter,
          payload.task_token,
        ]
      );
      await client.query(
        `UPDATE ad_tasks
         SET status = 'rewarded', callback_payload = $2, provider_transaction_id = $3,
             watched_at = NOW(), rewarded_at = NOW(), updated_at = NOW()
         WHERE id = $1`,
        [
          task.id,
          JSON.stringify({ ...payload, sign: undefined }),
          String(payload.transaction_id || '') || null,
        ]
      );

      // 中转站奖励订单（§8.2），先落 pending，提交后异步入账
      const orderNo = `AD_REWARD_${payload.task_token}`;
      await client.query(
        `INSERT INTO reward_orders (order_no, user_id, station_user_id, linuxdo_user_id,
                                    amount_microunits, source, ad_task_id, provider, provider_transaction_id)
         VALUES ($1, $2, $3, $4, $5, 'rewarded_ad', $6, $7, $8)
         ON CONFLICT (order_no) DO NOTHING`,
        [
          orderNo,
          task.user_id,
          user?.station_user_id || null,
          user?.linuxdo_user_id || null,
          micro,
          payload.task_token,
          task.ad_platform,
          payload.transaction_id || null,
        ]
      );
      return {
        ok: true,
        order: {
          order_no: orderNo,
          station_user_id: user?.station_user_id ? Number(user.station_user_id) : null,
          linuxdo_user_id: user?.linuxdo_user_id || null,
          amount_microunits: micro,
          source: 'rewarded_ad',
          ad_task_id: payload.task_token,
          provider: task.ad_platform,
          provider_transaction_id: payload.transaction_id || null,
        },
      };
    });

    if (!result.ok) {
      return callbackError(req, res, isHj, result.status, result.message);
    }

    // 事务提交后调用中转站入账。状态机：pending -> crediting -> success
    // crediting 是"已发出请求、结果未知"的中间态：进程崩溃/重启后停在 crediting 的订单
    // 需人工核对中转站账本后处理，绝不能自动重发（newapi 模式无服务端幂等，重发即重复发奖）
    if (result.order?.station_user_id) {
      const orderNo = result.order.order_no;
      try {
        const { rowCount } = await query(
          `UPDATE reward_orders SET status = 'crediting', updated_at = NOW()
           WHERE order_no = $1 AND status = 'pending'`,
          [orderNo]
        );
        if (rowCount > 0) {
          const credit = await creditReward(result.order);
          await query(
            `UPDATE reward_orders
             SET status = 'success', station_transaction_id = $2, updated_at = NOW()
             WHERE order_no = $1`,
            [orderNo, credit.station_transaction_id || null]
          );
        }
      } catch (err) {
        console.error('[ad-callback] 中转站入账异常（订单停留 crediting 待人工核对）:', err.message);
        await query(
          `UPDATE reward_orders SET fail_reason = $2, updated_at = NOW() WHERE order_no = $1`,
          [orderNo, String(err.message).slice(0, 300)]
        ).catch(() => {});
      }
    }

    req.adCallbackOutcome = result.duplicated ? '奖励回调已处理' : '奖励回调已验证并发放';
    res.json(
      isHj
        ? { isValid: true }
        : { code: 0, message: result.duplicated ? '已处理（重复回调）' : '奖励已发放' }
    );
  } catch (err) {
    if (err.code === 'AD_REWARD_REJECTED') {
      const isHj = (req.adCallbackPayload || req.body || {}).callback_provider === 'hj';
      return callbackError(req, res, isHj, err.status || 429, err.message);
    }
    req.adCallbackOutcome = `内部异常: ${String(err.message || 'unknown').slice(0, 260)}`;
    next(err);
  }
}

adCallbackRouter.post('/reward', rewardCallback);
adCallbackRouter.get('/hj/reward', async (req, res, next) => {
  req.adCallbackPayload = normalizeHjCallback(req.query);
  try {
    req.adCallbackAuditId = await beginHjCallbackAudit(req, req.adCallbackPayload);
    res.once('finish', () => finishHjCallbackAudit(req, res));
  } catch (err) {
    // 审计失败不能阻断广告平台回调，否则平台只会快速重试三次后放弃。
    console.error('[ad-callback] 记录HJ回调审计失败:', err.message);
  }
  console.info('[ad-callback] 收到HJ奖励回调', {
    task_token: req.adCallbackPayload.task_token || '(missing)',
    user_id: req.adCallbackPayload.user_id || '(missing)',
    placement_id: req.adCallbackPayload.placement_id || '(missing)',
    has_transaction_id: Boolean(req.adCallbackPayload.transaction_id),
    has_extra_info: Boolean(req.adCallbackPayload.extra_info),
  });
  return rewardCallback(req, res, next);
});
