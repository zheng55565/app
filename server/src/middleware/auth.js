import jwt from 'jsonwebtoken';
import { config } from '../config.js';
import { query } from '../db.js';

export function signToken(user) {
  return jwt.sign({ uid: user.id, username: user.username }, config.jwt.secret, {
    expiresIn: config.jwt.expiresIn,
  });
}

// 要求请求头携带 Authorization: Bearer <token>，验证通过后挂载 req.user
export async function requireAuth(req, res, next) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) {
    return res.status(401).json({ code: 401, message: '未登录' });
  }
  let payload;
  try {
    payload = jwt.verify(token, config.jwt.secret);
  } catch {
    return res.status(401).json({ code: 401, message: 'Token 无效或已过期' });
  }
  const { rows } = await query(
    `SELECT id, username, email, status, linuxdo_user_id, linuxdo_username, station_user_id
     FROM users WHERE id = $1`,
    [payload.uid]
  );
  const user = rows[0];
  if (!user) {
    return res.status(401).json({ code: 401, message: '用户不存在' });
  }
  if (user.status === 'banned') {
    return res.status(403).json({ code: 403, message: '账号已被封禁' });
  }
  req.user = user;
  next();
}
