import crypto from 'node:crypto';

import { config } from '../config.js';
import { query } from '../db.js';

function encryptionKey() {
  const secret = String(config.ai.credentialEncryptionKey || '');
  if (!secret) {
    const err = new Error('跨端 Key 同步尚未配置');
    err.code = 'KEY_SYNC_NOT_CONFIGURED';
    err.status = 503;
    throw err;
  }
  if (/^[a-f\d]{64}$/i.test(secret)) return Buffer.from(secret, 'hex');
  const decoded = Buffer.from(secret, 'base64');
  if (decoded.length === 32 && decoded.toString('base64').replace(/=+$/, '') === secret.replace(/=+$/, '')) {
    return decoded;
  }
  return crypto.createHash('sha256').update(secret, 'utf8').digest();
}

export function encryptCredential(value) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', encryptionKey(), iv);
  const ciphertext = Buffer.concat([cipher.update(value, 'utf8'), cipher.final()]);
  return {
    ciphertext: ciphertext.toString('base64'),
    iv: iv.toString('base64'),
    authTag: cipher.getAuthTag().toString('base64'),
    fingerprint: crypto.createHash('sha256').update(value).digest('hex').slice(0, 16),
  };
}

export function decryptCredential(record) {
  const decipher = crypto.createDecipheriv(
    'aes-256-gcm',
    encryptionKey(),
    Buffer.from(record.key_iv, 'base64')
  );
  decipher.setAuthTag(Buffer.from(record.key_auth_tag, 'base64'));
  return Buffer.concat([
    decipher.update(Buffer.from(record.key_ciphertext, 'base64')),
    decipher.final(),
  ]).toString('utf8');
}

export async function saveUserCredential(userId, value) {
  const encrypted = encryptCredential(value);
  const { rows } = await query(
    `INSERT INTO user_ai_credentials
       (user_id, key_ciphertext, key_iv, key_auth_tag, key_fingerprint)
     VALUES ($1, $2, $3, $4, $5)
     ON CONFLICT (user_id) DO UPDATE SET
       key_ciphertext = EXCLUDED.key_ciphertext,
       key_iv = EXCLUDED.key_iv,
       key_auth_tag = EXCLUDED.key_auth_tag,
       key_fingerprint = EXCLUDED.key_fingerprint,
       updated_at = NOW()
     RETURNING key_fingerprint, updated_at`,
    [userId, encrypted.ciphertext, encrypted.iv, encrypted.authTag, encrypted.fingerprint]
  );
  return rows[0];
}

export async function getUserCredential(userId) {
  const { rows } = await query(
    `SELECT key_ciphertext, key_iv, key_auth_tag, key_fingerprint, updated_at
     FROM user_ai_credentials WHERE user_id = $1`,
    [userId]
  );
  if (rows.length === 0) return null;
  return { key: decryptCredential(rows[0]), ...rows[0] };
}

export async function deleteUserCredential(userId) {
  await query(`DELETE FROM user_ai_credentials WHERE user_id = $1`, [userId]);
}
