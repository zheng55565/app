// App Token 服务：短效 Access Token（JWT）+ 可轮换 Refresh Token（方案 §7.4/7.5/12.3）
//
// Refresh Token 明文只出现在响应中，数据库只存 SHA-256 哈希。
// 轮换时旧 token 标记 replaced_by；检测到已轮换/已撤销的 token 再次使用时撤销整个家族。

import crypto from 'node:crypto';
import jwt from 'jsonwebtoken';
import { config } from '../config.js';

export const sha256 = (s) => crypto.createHash('sha256').update(String(s)).digest('hex');

export function timingSafeEqualHex(aHex, bHex) {
  const a = Buffer.from(String(aHex));
  const b = Buffer.from(String(bHex));
  if (a.length !== b.length) return false;
  return crypto.timingSafeEqual(a, b);
}

export function signAccessToken(user) {
  return jwt.sign(
    {
      uid: user.id,
      username: user.linuxdo_username || user.username,
      auth: 'linuxdo',
      typ: 'access',
    },
    config.jwt.secret,
    { expiresIn: config.auth.accessTokenTtlSec }
  );
}

// 在事务 client 内签发 Refresh Token；familyId 为空时开新家族（首次登录）
export async function issueRefreshToken(client, userId, deviceName, familyId) {
  const token = `rt_${crypto.randomBytes(32).toString('hex')}`;
  const family = familyId || `rtf_${crypto.randomBytes(16).toString('hex')}`;
  const { rows } = await client.query(
    `INSERT INTO refresh_tokens (user_id, token_hash, token_family_id, device_name, expires_at)
     VALUES ($1, $2, $3, $4, NOW() + ($5 || ' days')::interval)
     RETURNING id`,
    [userId, sha256(token), family, deviceName || null, String(config.auth.refreshTokenTtlDays)]
  );
  return { token, familyId: family, id: rows[0].id };
}

export async function revokeFamily(client, familyId) {
  await client.query(
    `UPDATE refresh_tokens SET revoked_at = NOW() WHERE token_family_id = $1 AND revoked_at IS NULL`,
    [familyId]
  );
}

// 轮换：返回 { user_id, familyId, oldId } 或抛出带 code 的错误
// REFRESH_TOKEN_INVALID  不存在/已过期
// REFRESH_TOKEN_REUSED   已被轮换或撤销的 token 再次使用 -> 家族已被整体撤销
export async function consumeRefreshToken(client, plainToken) {
  const { rows } = await client.query(
    `SELECT id, user_id, token_family_id, expires_at, revoked_at, replaced_by_token_id
     FROM refresh_tokens WHERE token_hash = $1 FOR UPDATE`,
    [sha256(plainToken)]
  );
  const rt = rows[0];
  if (!rt) {
    const err = new Error('Refresh Token 无效');
    err.code = 'REFRESH_TOKEN_INVALID';
    throw err;
  }
  if (rt.revoked_at || rt.replaced_by_token_id) {
    // 复用检测：撤销整个家族（§7.5）
    await revokeFamily(client, rt.token_family_id);
    const err = new Error('Refresh Token 已被使用，检测到异常复用');
    err.code = 'REFRESH_TOKEN_REUSED';
    throw err;
  }
  if (new Date(rt.expires_at) < new Date()) {
    const err = new Error('Refresh Token 已过期');
    err.code = 'REFRESH_TOKEN_INVALID';
    throw err;
  }
  return { userId: rt.user_id, familyId: rt.token_family_id, oldId: rt.id };
}

export async function markReplaced(client, oldId, newId) {
  await client.query(
    `UPDATE refresh_tokens SET replaced_by_token_id = $2, revoked_at = NOW() WHERE id = $1`,
    [oldId, newId]
  );
}
