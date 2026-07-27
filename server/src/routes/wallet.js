// 钱包路由
// GET /api/wallet           余额概览：中转站（new-api）账本为资产真相来源（方案 §16），
//                           实时查询中转站额度；本地 microunits 仅作镜像/对账
// GET /api/wallet/records   本地流水分页
import { Router } from 'express';
import { query } from '../db.js';
import { config } from '../config.js';
import { requireAuth } from '../middleware/auth.js';
import { findAccountByLinuxdoId } from '../services/stationClient.js';

const router = Router();

const microToQuota = (m) =>
  Math.round((Number(m) * config.station.quotaPerCny) / 1000000);
const quotaToUsd = (q) => Number(q) / config.station.quotaPerUsd;

router.get('/', requireAuth, async (req, res, next) => {
  try {
    const { rows } = await query(
      `SELECT balance_microunits, total_ad_income_microunits FROM wallets WHERE user_id = $1`,
      [req.user.id]
    );
    const wallet = rows[0] || { balance_microunits: 0, total_ad_income_microunits: 0 };
    // 今日/累计收益从真实发奖订单（success）统计，与中转站账本口径一致
    const { rows: earnedRows } = await query(
      `SELECT
         COALESCE(SUM(amount_microunits) FILTER (WHERE created_at >= CURRENT_DATE), 0) AS today_micro,
         COALESCE(SUM(amount_microunits), 0) AS total_micro
       FROM reward_orders WHERE user_id = $1 AND status = 'success'`,
      [req.user.id]
    );
    const todayMicro = Number(earnedRows[0].today_micro);
    const totalMicro = Number(earnedRows[0].total_micro);

    // 实时读取中转站账户（失败时降级为 null，App 回退本地镜像展示）
    let stationQuota = null;
    if (req.user.linuxdo_user_id) {
      try {
        const account = await findAccountByLinuxdoId(
          req.user.linuxdo_user_id,
          req.user.linuxdo_username
        );
        stationQuota = account?.station_quota ?? null;
      } catch (err) {
        console.error('[wallet] 中转站余额查询失败，降级本地镜像:', err.message);
      }
    }

    res.json({
      // 中转站账本（资产真相来源）
      station_quota: stationQuota,
      station_balance_usd: stationQuota == null ? null : quotaToUsd(stationQuota),
      today_earned_quota: microToQuota(todayMicro),
      today_earned_usd: quotaToUsd(microToQuota(todayMicro)),
      total_earned_quota: microToQuota(totalMicro),
      total_earned_usd: quotaToUsd(microToQuota(totalMicro)),
      // 本地镜像（对账用）
      balance_microunits: Number(wallet.balance_microunits),
      total_ad_income_microunits: Number(wallet.total_ad_income_microunits),
      today_ad_income_microunits: todayMicro,
    });
  } catch (err) {
    next(err);
  }
});

router.get('/records', requireAuth, async (req, res, next) => {
  try {
    const page = Math.max(1, Number(req.query.page) || 1);
    const pageSize = Math.min(50, Math.max(1, Number(req.query.page_size) || 20));
    const { rows } = await query(
      `SELECT id, amount_microunits, balance_after_microunits, type, source, related_id, remark, created_at
       FROM wallet_records WHERE user_id = $1
       ORDER BY created_at DESC LIMIT $2 OFFSET $3`,
      [req.user.id, pageSize, (page - 1) * pageSize]
    );
    res.json({
      page,
      page_size: pageSize,
      records: rows.map((r) => ({
        ...r,
        amount_microunits: Number(r.amount_microunits),
        balance_after_microunits: Number(r.balance_after_microunits),
        amount_quota: microToQuota(r.amount_microunits),
        amount_usd: quotaToUsd(microToQuota(r.amount_microunits)),
      })),
    });
  } catch (err) {
    next(err);
  }
});

export default router;
