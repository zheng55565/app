import crypto from 'node:crypto';

import { config } from '../config.js';
import { query, withTransaction } from '../db.js';
import { callbackPlacementMatchesTask } from './adSecurity.js';
import { claimProviderTransaction } from './adTransactions.js';
import { MATCH3_RECOVERY_MOVES } from './match3Engine.js';

function recoveryError(code, message, status = 400) {
  const err = new Error(message);
  err.code = code;
  err.status = status;
  return err;
}

export async function createGameRecoveryTask(userId, sessionId) {
  if (!config.ad.gameRewardedEnabled || !config.ad.unitRewardedGame) {
    throw recoveryError('GAME_AD_DISABLED', '复活广告暂不可用', 409);
  }
  return withTransaction(async (client) => {
    const { rows } = await client.query(
      `SELECT id,status,recovery_count FROM game_match3_sessions
       WHERE id=$1 AND user_id=$2 FOR UPDATE`,
      [sessionId, userId]
    );
    const session = rows[0];
    if (!session) throw recoveryError('MATCH3_SESSION_NOT_FOUND', '关卡不存在', 404);
    if (session.status !== 'failed') {
      throw recoveryError('MATCH3_RECOVERY_NOT_REQUIRED', '当前关卡不需要复活', 409);
    }
    if (Number(session.recovery_count) >= 3) {
      throw recoveryError('MATCH3_RECOVERY_LIMIT', '本关复活次数已用完', 409);
    }
    await client.query(
      `UPDATE game_recovery_ad_tasks SET status='expired',updated_at=NOW()
       WHERE user_id=$1 AND session_id=$2 AND status='created' AND expires_at<=NOW()`,
      [userId, sessionId]
    );
    const existing = await client.query(
      `SELECT task_token,ad_unit_id,status,expires_at FROM game_recovery_ad_tasks
       WHERE user_id=$1 AND session_id=$2 AND status IN ('created','verified')
         AND expires_at>NOW() ORDER BY created_at DESC LIMIT 1 FOR UPDATE`,
      [userId, sessionId]
    );
    if (existing.rows[0]) return existing.rows[0];
    const taskToken = `game_ad_${crypto.randomBytes(18).toString('hex')}`;
    const taskId = crypto.randomUUID();
    const { rows: inserted } = await client.query(
      `INSERT INTO game_recovery_ad_tasks
       (id,task_token,user_id,session_id,ad_platform,ad_unit_id,expires_at)
       VALUES ($1,$2,$3,$4,$5,$6,NOW()+INTERVAL '15 minutes')
       RETURNING task_token,ad_unit_id,status,expires_at`,
      [taskId, taskToken, userId, sessionId, config.ad.provider, config.ad.unitRewardedGame]
    );
    return inserted[0];
  });
}

export async function getGameRecoveryTask(userId, taskToken) {
  const { rows } = await query(
    `SELECT task_token,status,expires_at,verified_at,consumed_at
     FROM game_recovery_ad_tasks WHERE task_token=$1 AND user_id=$2`,
    [taskToken, userId]
  );
  if (!rows[0]) throw recoveryError('GAME_AD_TASK_NOT_FOUND', '复活任务不存在', 404);
  return rows[0];
}

export async function verifyGameRecoveryCallback(payload) {
  return withTransaction(async (client) => {
    const { rows } = await client.query(
      `SELECT * FROM game_recovery_ad_tasks WHERE task_token=$1 FOR UPDATE`,
      [payload.task_token]
    );
    const task = rows[0];
    if (!task) return { ok: false, status: 404, message: 'task_token 不存在' };
    if (String(task.user_id) !== String(payload.user_id)) {
      return { ok: false, status: 403, message: '任务不属于该用户' };
    }
    if (task.ad_platform !== 'hj' && payload.callback_provider === 'hj') {
      return { ok: false, status: 403, message: '广告平台与任务不匹配' };
    }
    if (!callbackPlacementMatchesTask({
      isHj: payload.callback_provider === 'hj',
      taskUnitId: task.ad_unit_id,
      callbackPlacementId: payload.placement_id,
    })) {
      return { ok: false, status: 403, message: '广告位与任务不匹配' };
    }
    if (
      task.provider_transaction_id &&
      task.provider_transaction_id !== String(payload.transaction_id || '')
    ) {
      return { ok: false, status: 409, message: '任务已由另一笔广告验证' };
    }
    const transactionClaim = await claimProviderTransaction(client, {
      provider: task.ad_platform,
      transactionId: payload.transaction_id,
      purpose: 'game_recovery',
      taskToken: payload.task_token,
      userId: task.user_id,
    });
    if (!transactionClaim.ok) {
      return { ok: false, status: 409, message: transactionClaim.message };
    }
    if (['verified', 'consumed'].includes(task.status)) {
      return { ok: true, duplicated: true };
    }
    if (task.status !== 'created' || new Date(task.expires_at) < new Date()) {
      await client.query(
        `UPDATE game_recovery_ad_tasks SET status='expired',updated_at=NOW() WHERE id=$1`,
        [task.id]
      );
      return { ok: false, status: 410, message: '复活任务已过期' };
    }
    try {
      await client.query(
        `UPDATE game_recovery_ad_tasks SET status='verified',provider_transaction_id=$2,
         callback_payload=$3::jsonb,verified_at=NOW(),updated_at=NOW() WHERE id=$1`,
        [
          task.id,
          String(payload.transaction_id || '') || null,
          JSON.stringify({ ...payload, sign: undefined }),
        ]
      );
    } catch (error) {
      if (error.code === '23505') {
        return { ok: false, status: 409, message: '该广告交易已经使用' };
      }
      throw error;
    }
    return { ok: true };
  });
}

export async function consumeGameRecoveryTask(userId, taskToken) {
  return withTransaction(async (client) => {
    const { rows } = await client.query(
      `SELECT * FROM game_recovery_ad_tasks WHERE task_token=$1 AND user_id=$2 FOR UPDATE`,
      [taskToken, userId]
    );
    const task = rows[0];
    if (!task) throw recoveryError('GAME_AD_TASK_NOT_FOUND', '复活任务不存在', 404);
    if (task.status === 'consumed') {
      const current = await client.query(
        `SELECT * FROM game_match3_sessions WHERE id=$1 AND user_id=$2`,
        [task.session_id, userId]
      );
      return { session: current.rows[0], duplicated: true };
    }
    if (task.status !== 'verified') {
      throw recoveryError('GAME_AD_NOT_VERIFIED', '广告尚未完成验证', 409);
    }
    const sessionRows = await client.query(
      `SELECT * FROM game_match3_sessions WHERE id=$1 AND user_id=$2 FOR UPDATE`,
      [task.session_id, userId]
    );
    const session = sessionRows.rows[0];
    if (!session || session.status !== 'failed') {
      throw recoveryError('MATCH3_RECOVERY_NOT_REQUIRED', '当前关卡无法复活', 409);
    }
    if (Number(session.recovery_count) >= 3) {
      throw recoveryError('MATCH3_RECOVERY_LIMIT', '本关复活次数已用完', 409);
    }
    const { rows: updated } = await client.query(
      `UPDATE game_match3_sessions SET status='active',moves_left=$2,
       recovery_count=recovery_count+1,updated_at=NOW() WHERE id=$1 RETURNING *`,
      [session.id, MATCH3_RECOVERY_MOVES]
    );
    await client.query(
      `UPDATE game_recovery_ad_tasks SET status='consumed',consumed_at=NOW(),updated_at=NOW()
       WHERE id=$1`,
      [task.id]
    );
    return { session: updated[0] };
  });
}
