import { Router } from 'express';

import { config } from '../config.js';
import { query } from '../db.js';
import {
  adminAuthReady,
  adminCredentialsMatch,
  requireAdmin,
  signAdminToken,
} from '../middleware/adminAuth.js';
import {
  getRuntimeSettings,
  normalizeRuntimeSettings,
  updateRuntimeSettings,
  validateRuntimeSettingsInput,
} from '../services/runtimeSettings.js';

const router = Router();

export function parsePagination(input = {}) {
  const page = Math.max(1, Math.min(100000, Number.parseInt(input.page, 10) || 1));
  const pageSize = Math.max(1, Math.min(100, Number.parseInt(input.page_size, 10) || 20));
  return { page, pageSize, offset: (page - 1) * pageSize };
}

function clipped(value, max) {
  return String(value || '').slice(0, max);
}

async function audit(req, { username, result, detail }) {
  try {
    await query(
      `INSERT INTO admin_audit_logs
         (username, event_type, result, detail, ip_address, user_agent)
       VALUES ($1, 'login', $2, $3, $4, $5)`,
      [
        clipped(username, 100) || null,
        result,
        clipped(detail, 300) || null,
        clipped(req.ip, 60) || null,
        clipped(req.headers['user-agent'], 300) || null,
      ]
    );
  } catch (err) {
    console.error('[admin-audit] 写入失败:', err.message);
  }
}

router.get('/auth/status', (req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  res.json({ enabled: adminAuthReady() });
});

router.post('/auth/login', async (req, res, next) => {
  try {
    if (!adminAuthReady()) {
      return res.status(404).json({ code: 404, message: '管理后台未启用' });
    }
    const username = clipped(req.body?.username, 100);
    const password = String(req.body?.password || '');
    if (!username || !password || password.length > 200) {
      return res.status(400).json({ code: 400, message: '请输入管理员账号和密码' });
    }
    const { rows: attempts } = await query(
      `SELECT COUNT(*)::int AS count FROM admin_audit_logs
       WHERE event_type = 'login' AND result = 'failure' AND ip_address = $1
         AND created_at > NOW() - INTERVAL '15 minutes'`,
      [clipped(req.ip, 60)]
    );
    if (Number(attempts[0]?.count || 0) >= 10) {
      return res.status(429).json({ code: 429, message: '尝试次数过多，请15分钟后再试' });
    }
    if (!(await adminCredentialsMatch(username, password))) {
      await audit(req, { username, result: 'failure', detail: '凭据错误' });
      return res.status(401).json({ code: 401, message: '账号或密码错误' });
    }
    const token = signAdminToken(config.admin.username);
    await audit(req, { username, result: 'success', detail: '登录成功' });
    return res.json({
      code: 0,
      token,
      expires_in: config.admin.jwtExpiresIn,
      admin: { username: config.admin.username },
    });
  } catch (err) {
    next(err);
  }
});

router.get('/me', requireAdmin, (req, res) => {
  res.json({ username: req.admin.username, role: 'administrator' });
});

router.get('/overview', requireAdmin, async (req, res, next) => {
  try {
    const { rows } = await query(
      `SELECT
         (SELECT COUNT(*)::int FROM users) AS users_total,
         (SELECT COUNT(*)::int FROM users WHERE status = 'active') AS users_active,
         (SELECT COUNT(*)::int FROM ad_tasks WHERE created_at >= CURRENT_DATE) AS ad_tasks_today,
         (SELECT COUNT(*)::int FROM ad_tasks
           WHERE status = 'rewarded' AND rewarded_at >= CURRENT_DATE) AS rewarded_today,
         (SELECT COALESCE(SUM(amount_microunits), 0)::bigint FROM reward_orders
           WHERE status = 'success' AND updated_at >= CURRENT_DATE) AS reward_microunits_today,
         (SELECT COUNT(*)::int FROM ad_callback_audits
           WHERE received_at >= CURRENT_DATE AND COALESCE(http_status, 500) >= 400) AS callback_failures_today,
         (SELECT COUNT(*)::int FROM ad_client_events
           WHERE event_type = 'impression' AND created_at >= CURRENT_DATE) AS impressions_today,
         (SELECT COUNT(*)::int FROM ad_client_events
           WHERE event_type = 'click' AND created_at >= CURRENT_DATE) AS clicks_today,
         (SELECT COUNT(*)::int FROM game_results WHERE created_at >= CURRENT_DATE) AS game_rounds_today`
    );
    const data = rows[0] || {};
    res.json({
      ...data,
      reward_microunits_today: Number(data.reward_microunits_today || 0),
      generated_at: new Date().toISOString(),
    });
  } catch (err) {
    next(err);
  }
});

router.get('/users', requireAdmin, async (req, res, next) => {
  try {
    const { page, pageSize, offset } = parsePagination(req.query);
    const q = clipped(req.query.q, 100).trim();
    const status = ['active', 'banned'].includes(req.query.status) ? req.query.status : '';
    const params = [q || null, status || null, pageSize, offset];
    const where = `WHERE ($1::text IS NULL OR u.username ILIKE '%' || $1 || '%'
                      OR u.linuxdo_username ILIKE '%' || $1 || '%'
                      OR u.id::text = $1)
                     AND ($2::text IS NULL OR u.status = $2)`;
    const [itemsResult, totalResult] = await Promise.all([
      query(
        `SELECT u.id, u.username, u.linuxdo_username, u.status, u.station_user_id,
                u.created_at, u.last_login_at,
                COALESCE(w.balance_microunits, 0) AS balance_microunits,
                COALESCE(gw.balance_micropoints, 0) AS game_balance_micropoints
         FROM users u
         LEFT JOIN wallets w ON w.user_id = u.id
         LEFT JOIN game_wallets gw ON gw.user_id = u.id
         ${where}
         ORDER BY u.id DESC LIMIT $3 OFFSET $4`,
        params
      ),
      query(`SELECT COUNT(*)::int AS total FROM users u ${where}`, params.slice(0, 2)),
    ]);
    res.json({ items: itemsResult.rows, total: totalResult.rows[0].total, page, page_size: pageSize });
  } catch (err) {
    next(err);
  }
});

router.get('/ad-tasks', requireAdmin, async (req, res, next) => {
  try {
    const { page, pageSize, offset } = parsePagination(req.query);
    const status = ['created', 'rewarded', 'expired'].includes(req.query.status)
      ? req.query.status
      : '';
    const [items, count] = await Promise.all([
      query(
        `SELECT t.id, t.user_id, u.username, t.ad_platform, t.ad_unit_id,
                t.reward_amount_microunits, t.status, t.client_transaction_id,
                t.provider_transaction_id, t.created_at, t.rewarded_at, t.expires_at
         FROM ad_tasks t LEFT JOIN users u ON u.id = t.user_id
         WHERE ($1::text IS NULL OR t.status = $1)
         ORDER BY t.id DESC LIMIT $2 OFFSET $3`,
        [status || null, pageSize, offset]
      ),
      query(`SELECT COUNT(*)::int AS total FROM ad_tasks WHERE ($1::text IS NULL OR status = $1)`, [status || null]),
    ]);
    res.json({ items: items.rows, total: count.rows[0].total, page, page_size: pageSize });
  } catch (err) {
    next(err);
  }
});

router.get('/ad-callbacks', requireAdmin, async (req, res, next) => {
  try {
    const { page, pageSize, offset } = parsePagination(req.query);
    const { rows } = await query(
      `SELECT id, provider, transaction_id, task_token, placement_id,
              signature_present, signature_valid, http_status, outcome,
              received_at, completed_at
       FROM ad_callback_audits ORDER BY id DESC LIMIT $1 OFFSET $2`,
      [pageSize, offset]
    );
    const total = await query(`SELECT COUNT(*)::int AS total FROM ad_callback_audits`);
    res.json({ items: rows, total: total.rows[0].total, page, page_size: pageSize });
  } catch (err) {
    next(err);
  }
});

router.get('/ad-events', requireAdmin, async (req, res, next) => {
  try {
    const { page, pageSize, offset } = parsePagination(req.query);
    const eventType = [...new Set(['impression', 'click', 'close', 'load_failed'])].includes(
      req.query.event_type
    )
      ? req.query.event_type
      : '';
    const [items, count] = await Promise.all([
      query(
        `SELECT id, event_id, creative_id, placement, trigger_name, event_type,
                session_id, metadata, occurred_at, created_at
         FROM ad_client_events WHERE ($1::text IS NULL OR event_type = $1)
         ORDER BY id DESC LIMIT $2 OFFSET $3`,
        [eventType || null, pageSize, offset]
      ),
      query(
        `SELECT COUNT(*)::int AS total FROM ad_client_events
         WHERE ($1::text IS NULL OR event_type = $1)`,
        [eventType || null]
      ),
    ]);
    res.json({ items: items.rows, total: count.rows[0].total, page, page_size: pageSize });
  } catch (err) {
    next(err);
  }
});

router.get('/settings', requireAdmin, async (req, res, next) => {
  try {
    const [game, ad, ai] = await Promise.all([
      getRuntimeSettings('game', { fresh: true }),
      getRuntimeSettings('ad', { fresh: true }),
      getRuntimeSettings('ai', { fresh: true }),
    ]);
    res.setHeader('Cache-Control', 'no-store');
    res.json({ game, ad, ai });
  } catch (err) {
    next(err);
  }
});

router.put('/settings/:namespace', requireAdmin, async (req, res, next) => {
  try {
    const namespace = String(req.params.namespace || '');
    if (!['game', 'ad', 'ai'].includes(namespace)) {
      return res.status(404).json({ code: 404, message: '配置分组不存在' });
    }
    if (JSON.stringify(req.body || {}).length > 20000) {
      return res.status(413).json({ code: 413, message: '配置内容过大' });
    }
    if (namespace === 'ai' && req.body?.enabled === true && !config.ai.upstreamBaseUrl) {
      return res.status(409).json({
        code: 'AI_UPSTREAM_NOT_CONFIGURED',
        message: '请先在服务器配置 AI_UPSTREAM_BASE_URL 或 STATION_BASE_URL',
      });
    }
    validateRuntimeSettingsInput(namespace, req.body || {});
    const normalized = normalizeRuntimeSettings(namespace, req.body || {});
    const value = await updateRuntimeSettings(
      namespace,
      normalized,
      req.admin.username,
      { ip: req.ip, userAgent: req.headers['user-agent'] }
    );
    res.json({ namespace, value, effective_for: 'new_tasks_and_rounds' });
  } catch (err) {
    next(err);
  }
});

router.get('/game-results', requireAdmin, async (req, res, next) => {
  try {
    const { page, pageSize, offset } = parsePagination(req.query);
    const gameType = ['rps', 'mine', 'battle', 'match3'].includes(req.query.game_type)
      ? req.query.game_type
      : '';
    const [items, count] = await Promise.all([
      query(
        `SELECT r.id,r.user_id,u.username,r.game_type,r.game_id,r.mode,r.result,
                r.stake_micropoints,r.payout_micropoints,r.fee_micropoints,
                r.net_profit_micropoints,r.detail,r.created_at
         FROM game_results r JOIN users u ON u.id=r.user_id
         WHERE ($1::text IS NULL OR r.game_type=$1)
         ORDER BY r.created_at DESC,r.id DESC LIMIT $2 OFFSET $3`,
        [gameType || null, pageSize, offset]
      ),
      query(
        `SELECT COUNT(*)::int AS total FROM game_results
         WHERE ($1::text IS NULL OR game_type=$1)`,
        [gameType || null]
      ),
    ]);
    res.json({ items: items.rows, total: count.rows[0].total, page, page_size: pageSize });
  } catch (err) {
    next(err);
  }
});

router.get('/setting-audits', requireAdmin, async (req, res, next) => {
  try {
    const { page, pageSize, offset } = parsePagination(req.query);
    const [items, count] = await Promise.all([
      query(
        `SELECT id,username,event_type,result,detail,ip_address,created_at
         FROM admin_audit_logs WHERE event_type='runtime_settings_update'
         ORDER BY id DESC LIMIT $1 OFFSET $2`,
        [pageSize, offset]
      ),
      query(
        `SELECT COUNT(*)::int AS total FROM admin_audit_logs
         WHERE event_type='runtime_settings_update'`
      ),
    ]);
    res.json({ items: items.rows, total: count.rows[0].total, page, page_size: pageSize });
  } catch (err) {
    next(err);
  }
});

export default router;
