// 用户注册 / 登录
import { Router } from 'express';
import bcrypt from 'bcryptjs';
import crypto from 'node:crypto';
import { query, withTransaction } from '../db.js';
import { config } from '../config.js';
import { signToken, requireAuth } from '../middleware/auth.js';

const router = Router();

export function previewLoginEnabled(currentConfig = config) {
  const preview = currentConfig.auth?.preview;
  return Boolean(
    currentConfig.env !== 'production' &&
      currentConfig.station?.mode === 'mock' &&
      preview?.enabled &&
      preview.username &&
      preview.password
  );
}

function secretMatches(actual, expected) {
  const actualHash = crypto.createHash('sha256').update(String(actual)).digest();
  const expectedHash = crypto.createHash('sha256').update(String(expected)).digest();
  return crypto.timingSafeEqual(actualHash, expectedHash);
}

export function previewCredentialsMatch(username, password, currentConfig = config) {
  if (!previewLoginEnabled(currentConfig)) return false;
  return (
    secretMatches(username, currentConfig.auth.preview.username) &&
    secretMatches(password, currentConfig.auth.preview.password)
  );
}

// 真实广告联调账号。只在 development + mock 中转账本下存在，正式环境返回404。
router.post('/preview', async (req, res, next) => {
  try {
    if (!previewLoginEnabled()) {
      return res.status(404).json({ code: 404, message: '接口不存在' });
    }
    const { username, password } = req.body || {};
    if (!previewCredentialsMatch(username || '', password || '')) {
      return res.status(401).json({ code: 401, message: '检查账号或口令错误' });
    }

    const previewIdentity = `preview:${config.auth.preview.username}`;
    const user = await withTransaction(async (client) => {
      const { rows: stationRows } = await client.query(
        `INSERT INTO mock_station_accounts (linuxdo_user_id, username)
         VALUES ($1, $2)
         ON CONFLICT (linuxdo_user_id) DO UPDATE SET
           username = EXCLUDED.username,
           status = 'active',
           updated_at = NOW()
         RETURNING id`,
        [previewIdentity, config.auth.preview.username]
      );
      const stationUserId = stationRows[0].id;
      const { rows: userRows } = await client.query(
        `INSERT INTO users
           (username, linuxdo_user_id, linuxdo_username, station_user_id, last_login_at)
         VALUES ($1, $2, $1, $3, NOW())
         ON CONFLICT (username) DO UPDATE SET
           linuxdo_user_id = EXCLUDED.linuxdo_user_id,
           linuxdo_username = EXCLUDED.linuxdo_username,
           station_user_id = EXCLUDED.station_user_id,
           status = 'active',
           last_login_at = NOW(),
           updated_at = NOW()
         RETURNING id, username, linuxdo_username, station_user_id`,
        [config.auth.preview.username, previewIdentity, stationUserId]
      );
      await client.query(
        `INSERT INTO wallets (user_id) VALUES ($1) ON CONFLICT (user_id) DO NOTHING`,
        [userRows[0].id]
      );
      return userRows[0];
    });

    res.json({
      code: 0,
      token: signToken(user),
      user: {
        id: Number(user.id),
        username: user.username,
        linuxdo_username: user.linuxdo_username,
        station_user_id: Number(user.station_user_id),
        station_status: 'active',
      },
    });
  } catch (err) {
    next(err);
  }
});

router.post('/register', async (req, res, next) => {
  try {
    // §16 迁移决策：停止新增密码注册，存量密码登录迁移期内保留
    if (!config.auth.allowPasswordRegister) {
      return res.status(403).json({
        code: 403,
        message: '密码注册已停用，请使用 Linux.do 登录（POST /api/v1/auth/linuxdo/start）',
      });
    }
    const { username, password, email } = req.body || {};
    if (!username || !password) {
      return res.status(400).json({ code: 400, message: '用户名和密码不能为空' });
    }
    if (password.length < 6) {
      return res.status(400).json({ code: 400, message: '密码至少 6 位' });
    }
    const passwordHash = await bcrypt.hash(password, 10);
    const user = await withTransaction(async (client) => {
      const { rows } = await client.query(
        `INSERT INTO users (username, email, password_hash) VALUES ($1, $2, $3)
         ON CONFLICT (username) DO NOTHING
         RETURNING id, username`,
        [username, email || null, passwordHash]
      );
      if (rows.length === 0) return null;
      // 注册即开钱包
      await client.query(`INSERT INTO wallets (user_id) VALUES ($1)`, [rows[0].id]);
      return rows[0];
    });
    if (!user) {
      return res.status(409).json({ code: 409, message: '用户名已存在' });
    }
    res.json({ code: 0, token: signToken(user), user });
  } catch (err) {
    next(err);
  }
});

router.post('/login', async (req, res, next) => {
  try {
    const { username, password } = req.body || {};
    if (!username || !password) {
      return res.status(400).json({ code: 400, message: '用户名和密码不能为空' });
    }
    const { rows } = await query(
      `SELECT id, username, password_hash, status FROM users WHERE username = $1`,
      [username]
    );
    const user = rows[0];
    if (!user || !(await bcrypt.compare(password, user.password_hash || ''))) {
      return res.status(401).json({ code: 401, message: '用户名或密码错误' });
    }
    if (user.status === 'banned') {
      return res.status(403).json({ code: 403, message: '账号已被封禁' });
    }
    res.json({ code: 0, token: signToken(user), user: { id: user.id, username: user.username } });
  } catch (err) {
    next(err);
  }
});

router.get('/me', requireAuth, async (req, res, next) => {
  try {
    // v2 登录只写 users 表；旧 OAuth 绑定流写 linuxdo_bindings。
    // 以 users 为准，bindings 作为存量数据回退。
    let linuxdoUsername = req.user.linuxdo_username || null;
    if (!linuxdoUsername) {
      const { rows } = await query(
        `SELECT b.linuxdo_username FROM linuxdo_bindings b
         WHERE b.user_id = $1 AND b.bind_status = 'bound'`,
        [req.user.id]
      );
      linuxdoUsername = rows[0]?.linuxdo_username || null;
    }
    res.json({
      id: req.user.id,
      username: req.user.username,
      email: req.user.email,
      linuxdo_username: linuxdoUsername,
      station_user_id: req.user.station_user_id
        ? Number(req.user.station_user_id)
        : null,
    });
  } catch (err) {
    next(err);
  }
});

export default router;
