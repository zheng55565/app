// Linux.do 绑定路由
//
// POST /api/linuxdo/bind/start     生成 state 并返回授权跳转地址（App 内打开浏览器/WebView）
// GET  /api/linuxdo/bind/callback  LinuxDo 授权回调（code + state），完成绑定
// GET  /api/linuxdo/bind/status    查询绑定状态
// POST /api/linuxdo/unbind         解绑

import { Router } from 'express';
import crypto from 'node:crypto';
import { query, withTransaction } from '../db.js';
import { config } from '../config.js';
import { requireAuth } from '../middleware/auth.js';
import { v2CallbackHandler } from './authLinuxdoV2.js';
import {
  generateState,
  buildAuthorizeUrl,
  exchangeCodeForToken,
  fetchLinuxdoUser,
} from '../services/linuxdoClient.js';

const router = Router();

// 发起绑定：生成一次性 state 绑定到当前用户，返回授权地址
router.post('/bind/start', requireAuth, async (req, res, next) => {
  try {
    if (!config.linuxdo.clientId || !config.linuxdo.clientSecret) {
      return res.status(503).json({ code: 503, message: '服务端未配置 LinuxDo Connect，请先在 connect.linux.do 申请接入' });
    }
    const { rows } = await query(
      `SELECT id FROM linuxdo_bindings WHERE user_id = $1 AND bind_status = 'bound'`,
      [req.user.id]
    );
    if (rows.length > 0) {
      return res.status(400).json({ code: 400, message: '已绑定 Linux.do 账号，请先解绑' });
    }

    const state = generateState();
    await query(
      `INSERT INTO oauth_states (state, user_id, expires_at) VALUES ($1, $2, NOW() + INTERVAL '10 minutes')`,
      [state, req.user.id]
    );
    res.json({ authorize_url: buildAuthorizeUrl(state), state });
  } catch (err) {
    next(err);
  }
});

// OAuth2 回调：由 LinuxDo 重定向到这里，通过 state 找回用户身份
// 注意：Linux.do 只认后台登记的回调地址，v2 登录流复用本地址，按 state 归属分流
router.get('/bind/callback', async (req, res, next) => {
  try {
    const { code, state } = req.query;
    if (!code || !state) {
      return res.status(400).json({ code: 400, message: '缺少 code 或 state 参数' });
    }

    // v2 登录会话的 state（哈希存储）→ 交给 v2 处理器
    const stateHash = crypto.createHash('sha256').update(String(state)).digest('hex');
    const { rows: v2Rows } = await query(
      `SELECT 1 FROM oauth_login_sessions WHERE state_hash = $1`,
      [stateHash]
    );
    if (v2Rows.length > 0) {
      return v2CallbackHandler(req, res, next);
    }

    // state 一次性消费，防 CSRF / 重放
    const { rows: stateRows } = await query(
      `UPDATE oauth_states SET used = TRUE
       WHERE state = $1 AND used = FALSE AND expires_at > NOW()
       RETURNING user_id`,
      [state]
    );
    if (stateRows.length === 0) {
      return res.status(400).json({ code: 400, message: 'state 无效或已过期，请重新发起绑定' });
    }
    const userId = stateRows[0].user_id;

    const token = await exchangeCodeForToken(code);
    const ldUser = await fetchLinuxdoUser(token.access_token);

    if (ldUser.silenced) {
      return res.status(403).json({ code: 403, message: '该 Linux.do 账号处于禁言状态，无法绑定' });
    }
    if (ldUser.active === false) {
      return res.status(403).json({ code: 403, message: '该 Linux.do 账号未激活，无法绑定' });
    }
    const minLevel = config.linuxdo.minTrustLevel;
    if (minLevel > 0 && (ldUser.trust_level ?? 0) < minLevel) {
      return res.status(403).json({ code: 403, message: `绑定要求 Linux.do 信任等级不低于 ${minLevel}` });
    }

    await withTransaction(async (client) => {
      // 一个 Linux.do 账号只能绑定一个中转站账号
      const { rows: dup } = await client.query(
        `SELECT user_id FROM linuxdo_bindings WHERE linuxdo_user_id = $1 AND bind_status = 'bound'`,
        [String(ldUser.id)]
      );
      if (dup.length > 0 && dup[0].user_id !== userId) {
        throw Object.assign(new Error('该 Linux.do 账号已被其他账号绑定'), { status: 409 });
      }
      await client.query(
        `INSERT INTO linuxdo_bindings (user_id, linuxdo_user_id, linuxdo_username, trust_level, bind_status, bound_at)
         VALUES ($1, $2, $3, $4, 'bound', NOW())`,
        [userId, String(ldUser.id), ldUser.username, ldUser.trust_level ?? null]
      );
    });

    // App 内 WebView 可拦截该 JSON；如果是外部浏览器，可改为重定向到 App scheme
    res.json({
      code: 0,
      message: '绑定成功',
      linuxdo_username: ldUser.username,
      trust_level: ldUser.trust_level,
    });
  } catch (err) {
    if (err.status === 409) {
      return res.status(409).json({ code: 409, message: err.message });
    }
    next(err);
  }
});

router.get('/bind/status', requireAuth, async (req, res, next) => {
  try {
    const { rows } = await query(
      `SELECT linuxdo_username, trust_level, bound_at FROM linuxdo_bindings
       WHERE user_id = $1 AND bind_status = 'bound'`,
      [req.user.id]
    );
    if (rows.length === 0) {
      return res.json({ bound: false });
    }
    res.json({ bound: true, ...rows[0] });
  } catch (err) {
    next(err);
  }
});

router.post('/unbind', requireAuth, async (req, res, next) => {
  try {
    const { rowCount } = await query(
      `UPDATE linuxdo_bindings SET bind_status = 'unbound', updated_at = NOW()
       WHERE user_id = $1 AND bind_status = 'bound'`,
      [req.user.id]
    );
    if (rowCount === 0) {
      return res.status(400).json({ code: 400, message: '当前未绑定 Linux.do 账号' });
    }
    res.json({ code: 0, message: '已解绑' });
  } catch (err) {
    next(err);
  }
});

export default router;
