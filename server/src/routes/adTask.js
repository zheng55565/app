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

export const adTaskRouter = Router();
export const adCallbackRouter = Router();

const AD_PLATFORM = 'example_ad_platform'; // 接入实际广告平台后替换
// 首页余额广告位（唯一允许进钱包发奖逻辑的广告位）。
// 小游戏补救广告位（AD_UNIT_REWARDED_GAME）不建任务、不回调、永不发奖。
const homeUnitId = () => config.ad.unitRewardedHome;

const toLegacyAmount = (micro) => (Number(micro) / 1000000).toFixed(6);

async function getTodayLimit(userId) {
  const { rows } = await query(
    `SELECT watched_count, max_count FROM daily_ad_limits WHERE user_id = $1 AND date = CURRENT_DATE`,
    [userId]
  );
  return rows[0] || { watched_count: 0, max_count: config.ad.dailyMax };
}

adTaskRouter.get('/today', requireAuth, async (req, res, next) => {
  try {
    const limit = await getTodayLimit(req.user.id);
    const rewardQuota = Math.round(
      (config.ad.rewardMicrounits * config.station.quotaPerCny) / 1000000
    );
    res.json({
      date: new Date().toISOString().slice(0, 10),
      watched_count: limit.watched_count,
      max_count: limit.max_count,
      remaining_count: Math.max(0, limit.max_count - limit.watched_count),
      reward_amount_microunits: config.ad.rewardMicrounits,
      reward_quota: rewardQuota,
      reward_usd: rewardQuota / config.station.quotaPerUsd,
    });
  } catch (err) {
    next(err);
  }
});

adTaskRouter.post('/start', requireAuth, async (req, res, next) => {
  try {
    // v2 主身份判断：users.linuxdo_user_id（不再查 linuxdo_bindings）
    if (!req.user.linuxdo_user_id) {
      return res.status(403).json({ code: 403, message: '请先通过 Linux.do 登录' });
    }
    const limit = await getTodayLimit(req.user.id);
    if (limit.watched_count >= limit.max_count) {
      return res.status(429).json({ code: 429, message: '今日广告次数已用完' });
    }

    const taskToken = `ad_task_${crypto.randomBytes(16).toString('hex')}`;
    await query(
      `INSERT INTO ad_tasks (user_id, ad_platform, ad_unit_id, task_token,
                             reward_amount, reward_amount_microunits, expires_at)
       VALUES ($1, $2, $3, $4, $5, $6, NOW() + ($7 || ' minutes')::interval)`,
      [
        req.user.id,
        AD_PLATFORM,
        homeUnitId(),
        taskToken,
        toLegacyAmount(config.ad.rewardMicrounits),
        config.ad.rewardMicrounits,
        String(config.ad.taskExpireMinutes),
      ]
    );
    res.json({
      task_token: taskToken,
      ad_platform: AD_PLATFORM,
      ad_unit_id: homeUnitId(),
      reward_amount_microunits: config.ad.rewardMicrounits,
    });
  } catch (err) {
    next(err);
  }
});

adTaskRouter.get('/status/:task_token', requireAuth, async (req, res, next) => {
  try {
    const { rows } = await query(
      `SELECT task_token, status, reward_amount_microunits, rewarded_at FROM ad_tasks
       WHERE task_token = $1 AND user_id = $2`,
      [req.params.task_token, req.user.id]
    );
    if (rows.length === 0) {
      return res.status(404).json({ code: 404, message: '任务不存在' });
    }
    const task = rows[0];
    res.json({ ...task, reward_amount_microunits: Number(task.reward_amount_microunits) });
  } catch (err) {
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
    const sign = crypto
      .createHmac('sha256', config.ad.callbackSecret)
      .update(`${task_token}${req.user.id}${timestamp}`)
      .digest('hex');
    const cbRes = await fetch(`http://localhost:${config.port}/api/ad-callback/reward`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        task_token,
        user_id: req.user.id,
        timestamp,
        sign,
        transaction_id: `dev_sim_${task_token}`,
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
// 这里实现一个通用的 HMAC-SHA256 占位方案：sign = HMAC(secret, task_token + user_id + timestamp)
// 接入实际平台时替换 verifySign 即可，其余幂等发奖逻辑通用。
function verifySign({ task_token, user_id, timestamp, sign }) {
  if (!config.ad.callbackSecret) return false;
  if (!task_token || !user_id || !timestamp || !sign) return false;
  // 回调时间与当前时间偏差超过 10 分钟视为无效，防重放
  if (Math.abs(Date.now() / 1000 - Number(timestamp)) > 600) return false;
  const expected = crypto
    .createHmac('sha256', config.ad.callbackSecret)
    .update(`${task_token}${user_id}${timestamp}`)
    .digest('hex');
  return crypto.timingSafeEqual(
    Buffer.from(expected),
    Buffer.from(String(sign).padEnd(expected.length).slice(0, expected.length))
  );
}

adCallbackRouter.post('/reward', async (req, res, next) => {
  try {
    const payload = req.body || {};
    if (!verifySign(payload)) {
      return res.status(403).json({ code: 403, message: '签名校验失败' });
    }

    const result = await withTransaction(async (client) => {
      // 行锁防并发重复发奖
      const { rows: taskRows } = await client.query(
        `SELECT id, user_id, ad_unit_id, reward_amount_microunits, status, expires_at FROM ad_tasks
         WHERE task_token = $1 FOR UPDATE`,
        [payload.task_token]
      );
      const task = taskRows[0];
      if (!task) return { ok: false, status: 404, message: 'task_token 不存在' };
      if (String(task.user_id) !== String(payload.user_id)) {
        return { ok: false, status: 403, message: '任务不属于该用户' };
      }
      // 只有首页余额广告位允许发奖；小游戏位（rewarded_game）或任何
      // 未知广告位的回调一律拒绝，杜绝游戏广告刷余额
      if (task.ad_unit_id !== config.ad.unitRewardedHome) {
        return { ok: false, status: 403, message: '该广告位不参与余额发奖' };
      }
      // 广告平台 transaction_id 防重放：同一次播放只能发一次奖
      // （task_token 行锁保证同任务幂等，这里防的是同一 transaction_id
      //  被用于不同 task_token 的跨任务重放）
      if (payload.transaction_id) {
        const { rows: dupRows } = await client.query(
          `SELECT 1 FROM reward_orders
           WHERE provider = $1 AND provider_transaction_id = $2
             AND ad_task_id <> $3`,
          [AD_PLATFORM, String(payload.transaction_id), payload.task_token]
        );
        if (dupRows.length > 0) {
          return { ok: false, status: 409, message: 'transaction_id 已被使用' };
        }
      }
      if (task.status === 'rewarded') {
        // 幂等：重复回调直接返回成功
        return { ok: true, duplicated: true };
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
      if (user?.status === 'banned') {
        return { ok: false, status: 403, message: '用户已被封禁' };
      }

      // 今日次数校验 + 原子递增
      const { rows: limitRows } = await client.query(
        `INSERT INTO daily_ad_limits (user_id, date, watched_count, max_count)
         VALUES ($1, CURRENT_DATE, 1, $2)
         ON CONFLICT (user_id, date) DO UPDATE
           SET watched_count = daily_ad_limits.watched_count + 1, updated_at = NOW()
           WHERE daily_ad_limits.watched_count < daily_ad_limits.max_count
         RETURNING watched_count`,
        [task.user_id, config.ad.dailyMax]
      );
      if (limitRows.length === 0) {
        return { ok: false, status: 429, message: '今日次数已达上限' };
      }

      const micro = Number(task.reward_amount_microunits);
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
         SET status = 'rewarded', callback_payload = $2, watched_at = NOW(), rewarded_at = NOW(), updated_at = NOW()
         WHERE id = $1`,
        [task.id, JSON.stringify(payload)]
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
          AD_PLATFORM,
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
          provider: AD_PLATFORM,
          provider_transaction_id: payload.transaction_id || null,
        },
      };
    });

    if (!result.ok) {
      return res.status(result.status).json({ code: result.status, message: result.message });
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

    res.json({ code: 0, message: result.duplicated ? '已处理（重复回调）' : '奖励已发放' });
  } catch (err) {
    next(err);
  }
});
