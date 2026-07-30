import crypto from 'node:crypto';

import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';

import { config } from '../config.js';

export function adminAuthReady(currentConfig = config) {
  const admin = currentConfig.admin || {};
  return Boolean(
    admin.enabled &&
      admin.username &&
      /^\$2[aby]\$/.test(admin.passwordHash || '') &&
      admin.jwtSecret
  );
}

export function constantTimeTextEqual(actual, expected) {
  const actualHash = crypto.createHash('sha256').update(String(actual)).digest();
  const expectedHash = crypto.createHash('sha256').update(String(expected)).digest();
  return crypto.timingSafeEqual(actualHash, expectedHash);
}

export async function adminCredentialsMatch(
  username,
  password,
  currentConfig = config,
  compare = bcrypt.compare
) {
  if (!adminAuthReady(currentConfig)) return false;
  const usernameMatches = constantTimeTextEqual(username, currentConfig.admin.username);
  // 即使用户名错误仍执行 bcrypt，避免通过响应时间探测管理员账号。
  const passwordMatches = await compare(String(password), currentConfig.admin.passwordHash);
  return usernameMatches && passwordMatches;
}

export function signAdminToken(username, currentConfig = config) {
  return jwt.sign(
    { scope: 'admin', username: String(username) },
    currentConfig.admin.jwtSecret,
    {
      subject: `admin:${String(username)}`,
      expiresIn: currentConfig.admin.jwtExpiresIn,
      issuer: 'gongyi-admin',
      audience: 'gongyi-admin-web',
    }
  );
}

export function requireAdmin(req, res, next) {
  if (!adminAuthReady()) {
    return res.status(404).json({ code: 404, message: '管理后台未启用' });
  }
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : '';
  if (!token) {
    return res.status(401).json({ code: 401, message: '管理员未登录' });
  }
  try {
    const payload = jwt.verify(token, config.admin.jwtSecret, {
      issuer: 'gongyi-admin',
      audience: 'gongyi-admin-web',
    });
    if (
      payload.scope !== 'admin' ||
      !constantTimeTextEqual(payload.username || '', config.admin.username)
    ) {
      return res.status(403).json({ code: 403, message: '管理员令牌权限不足' });
    }
    req.admin = { username: config.admin.username };
    return next();
  } catch {
    return res.status(401).json({ code: 401, message: '管理员登录已过期' });
  }
}
