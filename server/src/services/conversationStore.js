import crypto from 'node:crypto';

import { query, withTransaction } from '../db.js';

const MAX_FULL_SEGMENTS = 3;
const MAX_TURNS_PER_SEGMENT = 15;

function tokens(value) {
  const normalized = String(value || '').toLowerCase();
  const result = new Set(normalized.match(/[a-z\d]{3,}|[\u4e00-\u9fff]{2}/g) || []);
  return result;
}

export function shouldStartNewSegment(previousPrompt, nextPrompt, turnCount) {
  if (turnCount < 3) return false;
  const previous = tokens(previousPrompt);
  const next = tokens(nextPrompt);
  if (previous.size < 2 || next.size < 2) return false;
  let shared = 0;
  for (const token of next) if (previous.has(token)) shared++;
  return shared / Math.min(previous.size, next.size) < 0.12;
}

function compactSummary(messages) {
  const userTopics = messages
    .filter((message) => message.role === 'user')
    .map((message) => message.content.replace(/\s+/g, ' ').trim())
    .filter(Boolean)
    .slice(0, 5);
  const lastAnswer = [...messages]
    .reverse()
    .find((message) => message.role === 'assistant')
    ?.content.replace(/\s+/g, ' ')
    .trim();
  const parts = [];
  if (userTopics.length > 0) parts.push(`用户主题：${userTopics.join('；')}`);
  if (lastAnswer) parts.push(`阶段结论：${lastAnswer}`);
  return parts.join('\n').slice(0, 1800) || '该阶段无可用摘要';
}

async function compactOldSegments(client, conversationId, currentIndex) {
  const cutoff = currentIndex - (MAX_FULL_SEGMENTS - 1);
  if (cutoff <= 0) return;
  const { rows: segments } = await client.query(
    `SELECT id FROM ai_conversation_segments
     WHERE conversation_id = $1 AND segment_index < $2 AND summary IS NULL
     ORDER BY segment_index ASC LIMIT 8`,
    [conversationId, cutoff]
  );
  for (const segment of segments) {
    const { rows: messages } = await client.query(
      `SELECT role, content FROM ai_conversation_messages
       WHERE segment_id = $1 ORDER BY id ASC`,
      [segment.id]
    );
    await client.query(
      `UPDATE ai_conversation_segments SET summary = $2, updated_at = NOW() WHERE id = $1`,
      [segment.id, compactSummary(messages)]
    );
    await client.query(`DELETE FROM ai_conversation_messages WHERE segment_id = $1`, [segment.id]);
  }
}

export async function createConversation(userId, { title, model }) {
  const id = crypto.randomUUID();
  const { rows } = await query(
    `INSERT INTO ai_conversations (id, user_id, title, model)
     VALUES ($1, $2, $3, $4)
     RETURNING id, title, model, current_segment, created_at, updated_at`,
    [id, userId, title, model]
  );
  return rows[0];
}

export async function listConversations(userId) {
  const { rows } = await query(
    `SELECT id, title, model, current_segment, created_at, updated_at
     FROM ai_conversations WHERE user_id = $1
     ORDER BY updated_at DESC LIMIT 100`,
    [userId]
  );
  return rows;
}

export async function deleteConversation(userId, conversationId) {
  const result = await query(
    `DELETE FROM ai_conversations WHERE id = $1 AND user_id = $2`,
    [conversationId, userId]
  );
  return result.rowCount > 0;
}

export async function getConversationContext(userId, conversationId) {
  const { rows: conversations } = await query(
    `SELECT id, title, model, current_segment, created_at, updated_at
     FROM ai_conversations WHERE id = $1 AND user_id = $2`,
    [conversationId, userId]
  );
  if (conversations.length === 0) return null;
  const { rows: fullSegments } = await query(
    `SELECT id, segment_index, turn_count FROM ai_conversation_segments
     WHERE conversation_id = $1
     ORDER BY segment_index DESC LIMIT $2`,
    [conversationId, MAX_FULL_SEGMENTS]
  );
  const segmentIds = fullSegments.map((segment) => segment.id);
  let messages = [];
  if (segmentIds.length > 0) {
    const { rows } = await query(
      `SELECT m.id, m.role, m.content, m.created_at, s.segment_index
       FROM ai_conversation_messages m
       JOIN ai_conversation_segments s ON s.id = m.segment_id
       WHERE m.segment_id = ANY($1::bigint[])
       ORDER BY s.segment_index ASC, m.id ASC`,
      [segmentIds]
    );
    messages = rows;
  }
  const { rows: summaries } = await query(
    `SELECT segment_index, summary, updated_at
     FROM ai_conversation_segments
     WHERE conversation_id = $1 AND summary IS NOT NULL
     ORDER BY segment_index ASC LIMIT 50`,
    [conversationId]
  );
  return { conversation: conversations[0], messages, summaries };
}

export async function appendConversationTurn(
  userId,
  conversationId,
  { userContent, assistantContent, model }
) {
  return withTransaction(async (client) => {
    const { rows: conversations } = await client.query(
      `SELECT id, current_segment FROM ai_conversations
       WHERE id = $1 AND user_id = $2 FOR UPDATE`,
      [conversationId, userId]
    );
    if (conversations.length === 0) return null;
    let segmentIndex = Number(conversations[0].current_segment) || 0;
    const { rows: segments } = await client.query(
      `SELECT id, turn_count FROM ai_conversation_segments
       WHERE conversation_id = $1 AND segment_index = $2`,
      [conversationId, segmentIndex]
    );
    let segment = segments[0];
    let previousPrompt = '';
    if (segment) {
      const { rows: previous } = await client.query(
        `SELECT content FROM ai_conversation_messages
         WHERE segment_id = $1 AND role = 'user' ORDER BY id DESC LIMIT 1`,
        [segment.id]
      );
      previousPrompt = previous[0]?.content || '';
    }
    const startNew =
      !segment ||
      Number(segment.turn_count) >= MAX_TURNS_PER_SEGMENT ||
      shouldStartNewSegment(previousPrompt, userContent, Number(segment?.turn_count) || 0);
    if (startNew) {
      if (segment) segmentIndex++;
      const { rows } = await client.query(
        `INSERT INTO ai_conversation_segments
           (conversation_id, segment_index, topic_anchor)
         VALUES ($1, $2, $3)
         RETURNING id, turn_count`,
        [conversationId, segmentIndex, userContent.slice(0, 500)]
      );
      segment = rows[0];
    }
    await client.query(
      `INSERT INTO ai_conversation_messages (segment_id, role, content)
       VALUES ($1, 'user', $2), ($1, 'assistant', $3)`,
      [segment.id, userContent, assistantContent]
    );
    await client.query(
      `UPDATE ai_conversation_segments
       SET turn_count = turn_count + 1, updated_at = NOW() WHERE id = $1`,
      [segment.id]
    );
    await client.query(
      `UPDATE ai_conversations
       SET current_segment = $3, model = $4, updated_at = NOW()
       WHERE id = $1 AND user_id = $2`,
      [conversationId, userId, segmentIndex, model]
    );
    await compactOldSegments(client, conversationId, segmentIndex);
    return { segment_index: segmentIndex, started_new_segment: startNew };
  });
}

export async function compactConversation(userId, conversationId, summary) {
  return withTransaction(async (client) => {
    const { rows } = await client.query(
      `SELECT id FROM ai_conversations
       WHERE id = $1 AND user_id = $2 FOR UPDATE`,
      [conversationId, userId]
    );
    if (rows.length === 0) return null;
    await client.query(
      `DELETE FROM ai_conversation_segments WHERE conversation_id = $1`,
      [conversationId]
    );
    await client.query(
      `INSERT INTO ai_conversation_segments
         (conversation_id, segment_index, turn_count, topic_anchor, summary)
       VALUES ($1, 0, 0, '手动压缩上下文', $2),
              ($1, 1, 0, '压缩后的新对话', NULL)`,
      [conversationId, summary]
    );
    await client.query(
      `UPDATE ai_conversations
       SET current_segment = 1, updated_at = NOW()
       WHERE id = $1 AND user_id = $2`,
      [conversationId, userId]
    );
    return { current_segment: 1, summary };
  });
}
