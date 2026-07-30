import crypto from 'node:crypto';

import { config } from '../config.js';

export function businessDate(date = new Date(), timeZone = config.ad.businessTimezone) {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(date);
  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return `${values.year}-${values.month}-${values.day}`;
}

export function normalizeIp(value) {
  const ip = String(value || '').trim();
  if (ip.startsWith('::ffff:')) return ip.slice(7);
  return ip || 'unknown';
}

export function hashRiskSubject(type, value) {
  if (!value) return null;
  return crypto
    .createHmac('sha256', config.risk.hashSecret)
    .update(`${type}:${String(value).trim()}`)
    .digest('hex');
}

export function getAdRiskContext(req) {
  const installId = String(req.headers['x-install-id'] || '').trim();
  if (config.risk.requireInstallId && !installId) {
    const err = new Error('缺少设备安装标识，请升级App后重试');
    err.code = 'INSTALL_ID_REQUIRED';
    err.status = 400;
    throw err;
  }
  if (installId && (!/^[A-Za-z0-9_-]{20,128}$/.test(installId) || installId.length > 128)) {
    const err = new Error('设备安装标识格式无效');
    err.code = 'INVALID_INSTALL_ID';
    err.status = 400;
    throw err;
  }
  return {
    deviceHash: installId ? hashRiskSubject('device', installId) : null,
    ipHash: hashRiskSubject('ip', normalizeIp(req.ip)),
  };
}

export function callbackPlacementMatchesTask({ isHj, taskUnitId, callbackPlacementId }) {
  if (!callbackPlacementId) return true;
  // HJ reports the runtime network placement, not necessarily the aggregate placement requested by the App.
  if (isHj) return true;
  return String(taskUnitId) === String(callbackPlacementId);
}

export function verifyHmacCallback(payload, nowMs = Date.now()) {
  const { task_token, user_id, timestamp, sign, transaction_id } = payload || {};
  if (!config.ad.callbackSecret) return false;
  if (!task_token || !user_id || !timestamp || !sign) return false;
  if (config.ad.requireTransactionId && !transaction_id) return false;
  if (Math.abs(nowMs / 1000 - Number(timestamp)) > 600) return false;
  if (!/^[a-fA-F0-9]{64}$/.test(String(sign))) return false;
  const expected = crypto
    .createHmac('sha256', config.ad.callbackSecret)
    .update(`${task_token}\n${user_id}\n${timestamp}\n${transaction_id || ''}`)
    .digest();
  const actual = Buffer.from(String(sign), 'hex');
  return actual.length === expected.length && crypto.timingSafeEqual(expected, actual);
}

export function verifyHjCallback(payload) {
  const { sign, transaction_id } = payload || {};
  if (!config.ad.callbackSecret || !transaction_id || !sign) return false;
  if (!/^[a-fA-F0-9]{64}$/.test(String(sign))) return false;
  const expected = crypto
    .createHash('sha256')
    .update(`${config.ad.callbackSecret}:${transaction_id}`)
    .digest();
  const actual = Buffer.from(String(sign), 'hex');
  return actual.length === expected.length && crypto.timingSafeEqual(expected, actual);
}
