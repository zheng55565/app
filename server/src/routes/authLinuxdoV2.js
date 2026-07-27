// v2 登录体系：Linux.do 唯一身份 + session_secret 保护的登录会话
// （《移动端Linuxdo-OAuth登录方案.md》§4/§6/§7/§12）
//
// POST /api/v1/auth/linuxdo/start      创建登录会话，返回 auth_url + session_secret
// GET  /api/v1/auth/linuxdo/callback   Linux.do OAuth 回调（回跳 URL 不携带任何凭证）
// POST /api/v1/auth/linuxdo/status     App 轮询：secret 校验 + 首次轮询原子生成 login_code
// POST /api/v1/auth/exchange           三要素原子校验，签发 Access/Refresh Token
// POST /api/v1/auth/refresh            Refresh Token 轮换 + 复用检测家族撤销
// POST /api/v1/auth/logout             撤销 Refresh Token 会话

import { Router } from 'express';
import crypto from 'node:crypto';
import { query, withTransaction } from '../db.js';
import { config } from '../config.js';
import {
  buildAuthorizeUrl,
  exchangeCodeForToken,
  fetchLinuxdoUser,
} from '../services/linuxdoClient.js';
import { findAccountByLinuxdoId } from '../services/stationClient.js';
import {
  sha256,
  timingSafeEqualHex,
  signAccessToken,
  issueRefreshToken,
  revokeFamily,
  consumeRefreshToken,
  markReplaced,
} from '../services/appTokens.js';
import { requireAuth } from '../middleware/auth.js';

const router = Router();

const newRequestId = () => `req_${crypto.randomBytes(8).toString('hex')}`;
const rand = (prefix, bytes = 24) => `${prefix}_${crypto.randomBytes(bytes).toString('hex')}`;

function ok(res, data) {
  res.json({ success: true, data, request_id: newRequestId() });
}
function fail(res, http, code, message) {
  res.status(http).json({ success: false, error: { code, message }, request_id: newRequestId() });
}

async function audit(req, userId, eventType, result, detail) {
  try {
    await query(
      `INSERT INTO auth_audit_logs (user_id, event_type, result, detail, ip_address, user_agent)
       VALUES ($1, $2, $3, $4, $5, $6)`,
      [
        userId || null,
        eventType,
        result,
        detail ? String(detail).slice(0, 300) : null,
        req.ip || null,
        (req.headers['user-agent'] || '').slice(0, 300),
      ]
    );
  } catch {
    // 审计失败不阻断主流程
  }
}

// 会话定位 + session_secret 校验（§12.2：session_id 只是定位符，secret 才是凭证）
async function loadSessionWithProof(loginSessionId, sessionSecret) {
  if (!loginSessionId || !sessionSecret) return { error: 'AUTH_SESSION_PROOF_INVALID' };
  const { rows } = await query(
    `SELECT * FROM oauth_login_sessions WHERE login_session_id = $1`,
    [loginSessionId]
  );
  const session = rows[0];
  if (!session) return { error: 'AUTH_SESSION_EXPIRED' };
  if (!timingSafeEqualHex(sha256(sessionSecret), session.session_secret_hash)) {
    return { error: 'AUTH_SESSION_PROOF_INVALID' };
  }
  return { session };
}

// ============ 7.1 创建登录会话 ============
router.post('/linuxdo/start', async (req, res, next) => {
  try {
    if (!config.linuxdo.clientId || !config.linuxdo.clientSecret) {
      return fail(res, 503, 'STATION_UNAVAILABLE', '服务端未配置 LinuxDo Connect');
    }
    const platform = req.body?.platform === 'ios' ? 'ios' : 'android';
    const loginSessionId = rand('ls');
    const sessionSecret = rand('ss', 32);
    const state = crypto.randomBytes(24).toString('hex');

    await query(
      `INSERT INTO oauth_login_sessions
         (login_session_id, session_secret_hash, state_hash, platform, app_version, status, expires_at)
       VALUES ($1, $2, $3, $4, $5, 'pending', NOW() + ($6 || ' minutes')::interval)`,
      [
        loginSessionId,
        sha256(sessionSecret),
        sha256(state),
        platform,
        (req.body?.app_version || '').slice(0, 50) || null,
        String(config.auth.loginSessionTtlMin),
      ]
    );
    await audit(req, null, 'login_session_created', 'ok', `platform=${platform}`);

    ok(res, {
      login_session_id: loginSessionId,
      session_secret: sessionSecret,
      auth_url: buildAuthorizeUrl(state, config.linuxdo.redirectUriV2),
      expires_in: config.auth.loginSessionTtlMin * 60,
    });
  } catch (err) {
    next(err);
  }
});

// ============ 7.2 OAuth 回调（浏览器访问，回跳不携带凭证 §6.4） ============
// 导出 handler：旧绑定回调路由按 state 分流到这里（Linux.do 只认后台登记的回调地址）
export async function v2CallbackHandler(req, res, next) {
  try {
    const { code, state } = req.query;
    if (!code || !state) {
      return fail(res, 400, 'AUTH_STATE_INVALID', '缺少 code 或 state 参数');
    }

    // state 一次性消费（原子），防 CSRF / 重放
    const { rows: sessionRows } = await query(
      `UPDATE oauth_login_sessions
       SET state_used_at = NOW(), updated_at = NOW()
       WHERE state_hash = $1 AND state_used_at IS NULL AND expires_at > NOW() AND status = 'pending'
       RETURNING *`,
      [sha256(String(state))]
    );
    const session = sessionRows[0];
    if (!session) {
      return fail(res, 400, 'AUTH_STATE_INVALID', 'state 无效、已使用或已过期，请重新发起登录');
    }

    let status = 'failed';
    let errorCode = null;
    let ldUser = null;
    let stationUserId = null;

    try {
      const token = await exchangeCodeForToken(String(code), config.linuxdo.redirectUriV2);
      ldUser = await fetchLinuxdoUser(token.access_token);

      if (ldUser.silenced || ldUser.active === false) {
        status = 'linuxdo_account_rejected';
        errorCode = 'LINUXDO_ACCOUNT_REJECTED';
      } else if (
        config.linuxdo.minTrustLevel > 0 &&
        (ldUser.trust_level ?? 0) < config.linuxdo.minTrustLevel
      ) {
        status = 'linuxdo_account_rejected';
        errorCode = 'LINUXDO_ACCOUNT_REJECTED';
      } else {
        // 中转站账号核验（§4）；用户名作为 newapi 模式的搜索提示
        const account = await findAccountByLinuxdoId(ldUser.id, ldUser.username);
        if (!account) {
          status = 'account_not_found';
          errorCode = 'ACCOUNT_NOT_FOUND';
        } else if (account.status !== 'active') {
          status = 'account_disabled';
          errorCode = 'ACCOUNT_DISABLED';
        } else {
          status = 'authorized';
          stationUserId = account.station_user_id;
        }
      }
    } catch (err) {
      console.error('[auth-v2] callback 处理失败:', err.message);
      status = 'failed';
      errorCode = err.code === 'STATION_UNAVAILABLE' ? 'STATION_UNAVAILABLE' : 'AUTH_CALLBACK_FAILED';
    }

    // 保存结果与注册引导所需的短期 Linux.do 资料（§7.2 步骤 8-9），不生成明文 login_code
    const avatarUrl = ldUser?.avatar_template
      ? `https://linux.do${String(ldUser.avatar_template).replace('{size}', '120')}`
      : null;
    await query(
      `UPDATE oauth_login_sessions
       SET status = $2, error_code = $3, linuxdo_user_id = $4, linuxdo_username = $5,
           linuxdo_avatar_url = $6, linuxdo_trust_level = $7, station_user_id = $8, updated_at = NOW()
       WHERE id = $1`,
      [
        session.id,
        status,
        errorCode,
        ldUser ? String(ldUser.id) : null,
        ldUser?.username || null,
        avatarUrl,
        ldUser?.trust_level ?? null,
        stationUserId,
      ]
    );
    await audit(req, null, 'oauth_callback', status, errorCode);

    // 平台回跳：不携带 session_id / secret / login_code（§6.4）
    if (session.platform === 'ios') {
      return res.redirect(`${config.appLinks.iosScheme}://auth/complete?result=complete`);
    }
    if (config.appLinks.android) {
      return res.redirect(`${config.appLinks.android}?result=complete`);
    }
    // 开发模式（未配置 Android App Link）：用自定义 scheme 拉回 App，
    // 桌面浏览器打开时显示提示文本（scheme 无法解析则停留本页，App 侧有轮询兜底）
    const scheme = `${config.appLinks.iosScheme}://auth/complete?result=complete`;
    res
      .set('Content-Type', 'text/html; charset=utf-8')
      .send(`<!DOCTYPE html><html><head><meta charset="utf-8"><title>授权完成</title></head>
<body style="font-family:sans-serif;text-align:center;padding-top:20vh">
<h2>授权流程已完成</h2>
<p>正在返回 App…… 如果没有自动跳转，请<a href="${scheme}">点这里返回 App</a>，或手动切回 App。</p>
<script>location.href=${JSON.stringify(scheme)};</script>
</body></html>`);
  } catch (err) {
    next(err);
  }
}
router.get('/linuxdo/callback', v2CallbackHandler);

// ============ 7.3 查询登录状态（POST，secret 不进 URL） ============
router.post('/linuxdo/status', async (req, res, next) => {
  try {
    const { login_session_id, session_secret } = req.body || {};
    const { session, error } = await loadSessionWithProof(login_session_id, session_secret);
    if (error) {
      await audit(req, null, 'login_status_query', 'denied', error);
      return fail(res, 401, error, '登录会话凭证无效，请重新发起登录');
    }

    if (session.status === 'pending' && new Date(session.expires_at) < new Date()) {
      return ok(res, { status: 'expired' });
    }

    if (session.status !== 'authorized') {
      const data = { status: session.status };
      if (session.error_code) data.error_code = session.error_code;
      // 注册引导页所需的展示资料（§9.3，来自会话而非 users 表）
      if (session.status === 'account_not_found') {
        data.linuxdo_username = session.linuxdo_username;
        data.linuxdo_avatar_url = session.linuxdo_avatar_url;
      }
      return ok(res, data);
    }

    // authorized：首次有效轮询原子生成 login_code；响应丢失时持 secret 可立即换发（§7.3）
    if (session.login_code_used_at) {
      return ok(res, { status: 'completed' });
    }
    const loginCode = rand('lc');
    const { rows: updated } = await query(
      `UPDATE oauth_login_sessions
       SET login_code_hash = $2, login_code_issued_at = NOW(),
           login_code_expires_at = NOW() + ($3 || ' seconds')::interval, updated_at = NOW()
       WHERE id = $1 AND status = 'authorized' AND login_code_used_at IS NULL
       RETURNING id`,
      [session.id, sha256(loginCode), String(config.auth.loginCodeTtlSec)]
    );
    if (updated.length === 0) {
      // 并发换发/已交换的竞态，让 App 重查
      return ok(res, { status: 'completed' });
    }
    await audit(req, null, 'login_code_issued', 'ok', `session=${session.login_session_id}`);
    ok(res, { status: 'authorized', login_code: loginCode });
  } catch (err) {
    next(err);
  }
});

// ============ 7.4 一次性登录码换取 App Token（三要素原子校验） ============
router.post('/exchange', async (req, res, next) => {
  try {
    const { login_session_id, session_secret, login_code, device_name } = req.body || {};
    if (!login_session_id || !session_secret || !login_code) {
      return fail(res, 400, 'AUTH_SESSION_PROOF_INVALID', '缺少必要参数');
    }

    const result = await withTransaction(async (client) => {
      const { rows } = await client.query(
        `SELECT * FROM oauth_login_sessions WHERE login_session_id = $1 FOR UPDATE`,
        [login_session_id]
      );
      const session = rows[0];
      if (!session) return { error: ['AUTH_SESSION_EXPIRED', '登录会话不存在或已过期'] };
      if (!timingSafeEqualHex(sha256(session_secret), session.session_secret_hash)) {
        return { error: ['AUTH_SESSION_PROOF_INVALID', '会话凭证校验失败'] };
      }
      if (session.login_code_used_at) {
        return { error: ['LOGIN_CODE_USED', '登录码已被使用'] };
      }
      if (session.status !== 'authorized') {
        return { error: ['AUTH_SESSION_EXPIRED', '登录会话状态不允许交换'] };
      }
      if (
        !session.login_code_hash ||
        !timingSafeEqualHex(sha256(login_code), session.login_code_hash)
      ) {
        return { error: ['AUTH_SESSION_PROOF_INVALID', '登录码校验失败'] };
      }
      if (new Date(session.login_code_expires_at) < new Date()) {
        return { error: ['LOGIN_CODE_EXPIRED', '登录码已过期，请重新查询状态'] };
      }

      // 标记会话完成
      await client.query(
        `UPDATE oauth_login_sessions
         SET login_code_used_at = NOW(), status = 'completed', updated_at = NOW()
         WHERE id = $1`,
        [session.id]
      );

      // 确认中转站账号后 upsert 用户主身份（§11.1）
      const { rows: userRows } = await client.query(
        `INSERT INTO users (linuxdo_user_id, linuxdo_username, linuxdo_avatar_url,
                            linuxdo_trust_level, station_user_id, last_login_at)
         VALUES ($1, $2, $3, $4, $5, NOW())
         ON CONFLICT (linuxdo_user_id) WHERE linuxdo_user_id IS NOT NULL
         DO UPDATE SET linuxdo_username = EXCLUDED.linuxdo_username,
                       linuxdo_avatar_url = EXCLUDED.linuxdo_avatar_url,
                       linuxdo_trust_level = EXCLUDED.linuxdo_trust_level,
                       station_user_id = EXCLUDED.station_user_id,
                       last_login_at = NOW(), updated_at = NOW()
         RETURNING id, username, linuxdo_username, station_user_id, status`,
        [
          session.linuxdo_user_id,
          session.linuxdo_username,
          session.linuxdo_avatar_url,
          session.linuxdo_trust_level,
          session.station_user_id,
        ]
      );
      const user = userRows[0];
      if (user.status === 'banned') {
        return { error: ['ACCOUNT_DISABLED', '账号已被封禁'] };
      }
      // 保证钱包存在（本地镜像账本）
      await client.query(
        `INSERT INTO wallets (user_id) VALUES ($1) ON CONFLICT (user_id) DO NOTHING`,
        [user.id]
      );

      const { token: refreshToken } = await issueRefreshToken(
        client,
        user.id,
        (device_name || '').slice(0, 200)
      );
      return { user, refreshToken };
    });

    if (result.error) {
      await audit(req, null, 'token_exchange', 'denied', result.error[0]);
      const httpCode = result.error[0] === 'ACCOUNT_DISABLED' ? 403 : 401;
      return fail(res, httpCode, result.error[0], result.error[1]);
    }

    await audit(req, result.user.id, 'token_exchange', 'ok', null);
    ok(res, {
      access_token: signAccessToken(result.user),
      expires_in: config.auth.accessTokenTtlSec,
      refresh_token: result.refreshToken,
      user: {
        linuxdo_username: result.user.linuxdo_username,
        station_user_id: result.user.station_user_id ? Number(result.user.station_user_id) : null,
        station_status: 'active',
      },
    });
  } catch (err) {
    next(err);
  }
});

// ============ 7.5 刷新（轮换 + 复用检测） ============
router.post('/refresh', async (req, res, next) => {
  try {
    const { refresh_token } = req.body || {};
    if (!refresh_token) {
      return fail(res, 400, 'REFRESH_TOKEN_INVALID', '缺少 refresh_token');
    }

    const result = await withTransaction(async (client) => {
      let consumed;
      try {
        consumed = await consumeRefreshToken(client, refresh_token);
      } catch (err) {
        return { error: [err.code || 'REFRESH_TOKEN_INVALID', err.message] };
      }
      const { rows: userRows } = await client.query(
        `SELECT id, username, linuxdo_username, station_user_id, status FROM users WHERE id = $1`,
        [consumed.userId]
      );
      const user = userRows[0];
      if (!user || user.status === 'banned') {
        await revokeFamily(client, consumed.familyId);
        return { error: ['ACCOUNT_DISABLED', '账号不可用，会话已撤销'] };
      }
      const { token: newRefreshToken, id: newId } = await issueRefreshToken(
        client,
        user.id,
        null,
        consumed.familyId
      );
      await markReplaced(client, consumed.oldId, newId);
      return { user, newRefreshToken };
    });

    if (result.error) {
      await audit(req, null, 'token_refresh', 'denied', result.error[0]);
      const httpCode = result.error[0] === 'ACCOUNT_DISABLED' ? 403 : 401;
      return fail(res, httpCode, result.error[0], result.error[1]);
    }

    await audit(req, result.user.id, 'token_refresh', 'ok', null);
    ok(res, {
      access_token: signAccessToken(result.user),
      expires_in: config.auth.accessTokenTtlSec,
      refresh_token: result.newRefreshToken,
      // 回传用户信息：App 冷启动静默续期后无需额外请求即可展示用户名
      user: {
        linuxdo_username: result.user.linuxdo_username,
        station_user_id: result.user.station_user_id
          ? Number(result.user.station_user_id)
          : null,
        station_status: 'active',
      },
    });
  } catch (err) {
    next(err);
  }
});

// ============ 7.6 退出登录 ============
router.post('/logout', requireAuth, async (req, res, next) => {
  try {
    const { refresh_token } = req.body || {};
    if (refresh_token) {
      await withTransaction(async (client) => {
        const { rows } = await client.query(
          `SELECT token_family_id, user_id FROM refresh_tokens WHERE token_hash = $1`,
          [sha256(refresh_token)]
        );
        if (rows[0] && String(rows[0].user_id) === String(req.user.id)) {
          await revokeFamily(client, rows[0].token_family_id);
        }
      });
    } else {
      // 未提供 refresh_token 时撤销该用户全部会话
      await query(
        `UPDATE refresh_tokens SET revoked_at = NOW() WHERE user_id = $1 AND revoked_at IS NULL`,
        [req.user.id]
      );
    }
    await audit(req, req.user.id, 'logout', 'ok', null);
    ok(res, { logged_out: true });
  } catch (err) {
    next(err);
  }
});

export default router;
