import { Router } from 'express';

import { config } from '../config.js';
import { query } from '../db.js';
import { hashRiskSubject, normalizeIp } from '../services/adSecurity.js';

const router = Router();
const EVENT_TYPES = new Set(['impression', 'click', 'close', 'load_failed']);
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const NAME_PATTERN = /^[A-Za-z0-9_.:-]{1,100}$/;

export function safeHttpUrl(value) {
  if (!value) return '';
  try {
    const url = new URL(String(value));
    return url.protocol === 'http:' || url.protocol === 'https:' ? url.toString() : '';
  } catch {
    return '';
  }
}

export function validateAdEventBody(body) {
  const eventId = String(body?.event_id || '').trim();
  const creativeId = String(body?.creative_id || '').trim();
  const placement = String(body?.placement || '').trim();
  const triggerName = String(body?.trigger || '').trim();
  const eventType = String(body?.event_type || '').trim();
  const sessionId = String(body?.session_id || '').trim();
  const metadata = body?.metadata ?? {};
  if (!UUID_PATTERN.test(eventId)) return { ok: false, message: 'event_id 格式无效' };
  if (creativeId && !NAME_PATTERN.test(creativeId)) {
    return { ok: false, message: 'creative_id 格式无效' };
  }
  if (!NAME_PATTERN.test(placement)) return { ok: false, message: 'placement 格式无效' };
  if (!NAME_PATTERN.test(triggerName) || triggerName.length > 60) {
    return { ok: false, message: 'trigger 格式无效' };
  }
  if (!EVENT_TYPES.has(eventType)) return { ok: false, message: 'event_type 无效' };
  if (sessionId && !UUID_PATTERN.test(sessionId)) {
    return { ok: false, message: 'session_id 格式无效' };
  }
  if (!metadata || Array.isArray(metadata) || typeof metadata !== 'object') {
    return { ok: false, message: 'metadata 必须是对象' };
  }
  const metadataJson = JSON.stringify(metadata);
  if (metadataJson.length > 4000) return { ok: false, message: 'metadata 过大' };
  let occurredAt = null;
  if (body?.occurred_at) {
    const parsed = new Date(body.occurred_at);
    if (Number.isNaN(parsed.getTime())) return { ok: false, message: 'occurred_at 无效' };
    occurredAt = parsed;
  }
  return {
    ok: true,
    value: {
      eventId,
      creativeId: creativeId || null,
      placement,
      triggerName,
      eventType,
      sessionId: sessionId || null,
      metadataJson,
      occurredAt,
    },
  };
}

router.get('/web-ads/interstitial', (req, res) => {
  const placement = String(req.query.placement || 'global_interstitial');
  if (!NAME_PATTERN.test(placement)) {
    return res.status(400).json({ code: 400, message: '广告位置无效' });
  }
  res.setHeader('Cache-Control', 'no-store');
  if (!config.webInterstitial.enabled) {
    return res.json({ enabled: false, cooldown_seconds: config.webInterstitial.cooldownSec });
  }
  return res.json({
    enabled: true,
    creative: {
      id: config.webInterstitial.creativeId,
      title: config.webInterstitial.title,
      body: config.webInterstitial.body,
      media_url: safeHttpUrl(config.webInterstitial.mediaUrl),
      click_url: safeHttpUrl(config.webInterstitial.clickUrl),
    },
    cooldown_seconds: config.webInterstitial.cooldownSec,
  });
});

router.post('/ad-events', async (req, res, next) => {
  try {
    const parsed = validateAdEventBody(req.body);
    if (!parsed.ok) {
      return res.status(400).json({ code: 400, message: parsed.message });
    }
    const event = parsed.value;
    const sourceIpHash = hashRiskSubject('web-ad-ip', normalizeIp(req.ip));
    const { rows: rateRows } = await query(
      `SELECT COUNT(*)::int AS count FROM ad_client_events
       WHERE source_ip_hash = $1 AND created_at > NOW() - INTERVAL '1 minute'`,
      [sourceIpHash]
    );
    if (Number(rateRows[0]?.count || 0) >= 120) {
      return res.status(429).json({ code: 429, message: '上报过于频繁' });
    }
    const { rows } = await query(
      `INSERT INTO ad_client_events
         (event_id, creative_id, placement, trigger_name, event_type,
          session_id, source_ip_hash, metadata, occurred_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8::jsonb, $9)
       ON CONFLICT (event_id) DO NOTHING
       RETURNING id`,
      [
        event.eventId,
        event.creativeId,
        event.placement,
        event.triggerName,
        event.eventType,
        event.sessionId,
        sourceIpHash,
        event.metadataJson,
        event.occurredAt,
      ]
    );
    return res.json({ ok: true, duplicated: rows.length === 0 });
  } catch (err) {
    next(err);
  }
});

export default router;
