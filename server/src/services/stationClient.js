// API 中转站内部接口客户端（方案 §8）
//
// STATION_MODE=mock    本地模拟中转站（mock_station_accounts 表），开发期使用
// STATION_MODE=newapi  对接 new-api 实例的管理 API（无需改动 new-api 代码）：
//                        - 查账号: GET /api/user/search + GET /api/user/?p=N 匹配 linux_do_id
//                        - 加额:   POST /api/user/manage {id, action:"add_quota", mode:"add", value}（原子增量）
//                        - 鉴权:   Authorization: <管理员 access_token> + New-Api-User: <管理员ID>
//                        - 换算:   quota = amount_microunits * STATION_QUOTA_PER_CNY / 1_000_000
//                        - 幂等由本服务 reward_orders 表保证（new-api 侧无幂等键）
// STATION_MODE=http    对接自研内部 API（/internal/v1/...，二开后启用）
//
// 三种模式暴露同一接口：
//   findAccountByLinuxdoId(linuxdoUserId, usernameHint?) -> { station_user_id, username, status, balance_microunits } | null
//   creditReward(order)                                  -> { order_no, status, station_transaction_id, credited_microunits }
//   getRewardOrder(orderNo)                              -> 订单 | null

import { query, withTransaction } from '../db.js';
import { config } from '../config.js';

const station = () => config.station;

// ---------- mock 实现 ----------

async function mockFindAccount(linuxdoUserId) {
  const { rows } = await query(
    `SELECT id, username, status, balance_microunits FROM mock_station_accounts WHERE linuxdo_user_id = $1`,
    [String(linuxdoUserId)]
  );
  if (rows.length === 0) return null;
  const a = rows[0];
  return {
    station_user_id: Number(a.id),
    username: a.username,
    status: a.status,
    balance_microunits: Number(a.balance_microunits),
  };
}

async function mockCreditReward(order) {
  return withTransaction(async (client) => {
    // 幂等：同一 order_no 只入账一次，重复请求返回首次结果（§8.2）
    const { rows: existing } = await client.query(
      `SELECT t.id, t.amount_microunits, t.balance_after_microunits
       FROM mock_station_transactions t WHERE t.order_no = $1`,
      [order.order_no]
    );
    if (existing.length > 0) {
      const t = existing[0];
      if (Number(t.amount_microunits) !== Number(order.amount_microunits)) {
        const err = new Error('幂等订单金额不一致');
        err.code = 'IDEMPOTENCY_CONFLICT';
        throw err;
      }
      return {
        order_no: order.order_no,
        status: 'success',
        station_transaction_id: `mock_tx_${t.id}`,
        credited_microunits: Number(t.amount_microunits),
        balance_microunits: Number(t.balance_after_microunits),
        duplicated: true,
      };
    }

    const { rows: accountRows } = await client.query(
      `SELECT id, status, balance_microunits FROM mock_station_accounts WHERE id = $1 FOR UPDATE`,
      [order.station_user_id]
    );
    const account = accountRows[0];
    if (!account) {
      const err = new Error('中转站账号不存在');
      err.code = 'ACCOUNT_NOT_FOUND';
      throw err;
    }
    if (account.status !== 'active') {
      const err = new Error('中转站账号不可用');
      err.code = 'ACCOUNT_DISABLED';
      throw err;
    }

    const newBalance = Number(account.balance_microunits) + Number(order.amount_microunits);
    await client.query(
      `UPDATE mock_station_accounts SET balance_microunits = $2, updated_at = NOW() WHERE id = $1`,
      [account.id, newBalance]
    );
    const { rows: txRows } = await client.query(
      `INSERT INTO mock_station_transactions (station_user_id, order_no, amount_microunits, balance_after_microunits, source)
       VALUES ($1, $2, $3, $4, $5) RETURNING id`,
      [account.id, order.order_no, order.amount_microunits, newBalance, order.source || 'rewarded_ad']
    );
    return {
      order_no: order.order_no,
      status: 'success',
      station_transaction_id: `mock_tx_${txRows[0].id}`,
      credited_microunits: Number(order.amount_microunits),
      balance_microunits: newBalance,
    };
  });
}

async function mockGetRewardOrder(orderNo) {
  const { rows } = await query(
    `SELECT order_no, amount_microunits, balance_after_microunits, created_at
     FROM mock_station_transactions WHERE order_no = $1`,
    [orderNo]
  );
  if (rows.length === 0) return null;
  return { ...rows[0], status: 'success' };
}

// ---------- newapi 实现（new-api 管理 API 适配） ----------

async function newapiRequest(method, path, body) {
  const s = station();
  const res = await fetch(`${s.baseUrl}${path}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      // new-api 的 AdminAuth：Authorization 直接放 access_token（无 Bearer 前缀），
      // 且必须携带 New-Api-User = 该 token 所属管理员的用户 ID
      Authorization: s.adminToken,
      'New-Api-User': String(s.adminUserId),
    },
    body: body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(s.timeoutMs),
  });
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    const err = new Error(`new-api 返回 ${res.status}: ${text.slice(0, 200)}`);
    err.code = 'STATION_UNAVAILABLE';
    throw err;
  }
  const json = await res.json();
  if (json.success === false) {
    const err = new Error(`new-api 业务失败: ${json.message || '未知错误'}`);
    err.code = 'STATION_UNAVAILABLE';
    throw err;
  }
  return json;
}

function newapiToAccount(u) {
  return {
    station_user_id: Number(u.id),
    username: u.username,
    // new-api: status 1=启用 2=禁用
    status: Number(u.status) === 1 ? 'active' : 'disabled',
    // quota 原样透传，余额展示以本地镜像为准
    station_quota: Number(u.quota ?? 0),
    balance_microunits: null,
  };
}

async function newapiFindAccount(linuxdoUserId, usernameHint) {
  const target = String(linuxdoUserId);
  // 优先用 Linux.do 用户名做关键词搜索（linuxdo 注册的 new-api 账号用户名通常与之相关）
  if (usernameHint) {
    try {
      const r = await newapiRequest(
        'GET',
        `/api/user/search?keyword=${encodeURIComponent(usernameHint)}&p=1&page_size=50`
      );
      const items = r.data?.items || [];
      const hit = items.find((u) => String(u.linux_do_id ?? '') === target);
      if (hit) return newapiToAccount(hit);
    } catch {
      // 搜索失败继续走全量翻页
    }
  }
  // 兜底：翻页扫描（新实例用户量小；上限 10 页防御）
  for (let p = 1; p <= 10; p++) {
    const r = await newapiRequest('GET', `/api/user/?p=${p}&page_size=100`);
    const items = r.data?.items || [];
    const hit = items.find((u) => String(u.linux_do_id ?? '') === target);
    if (hit) return newapiToAccount(hit);
    if (items.length < 100) break;
  }
  return null;
}

async function newapiCreditReward(order) {
  const s = station();
  // 微单位(1元=1e6) -> new-api quota
  const quota = Math.round((Number(order.amount_microunits) * s.quotaPerCny) / 1000000);
  if (quota <= 0) {
    const err = new Error(`换算后 quota 为 0（amount=${order.amount_microunits}）`);
    err.code = 'IDEMPOTENCY_CONFLICT';
    throw err;
  }
  await newapiRequest('POST', '/api/user/manage', {
    id: Number(order.station_user_id),
    action: 'add_quota',
    mode: 'add',
    value: quota,
  });
  return {
    order_no: order.order_no,
    status: 'success',
    station_transaction_id: `newapi_quota_${quota}_${order.order_no}`,
    credited_microunits: Number(order.amount_microunits),
    credited_quota: quota,
  };
}

// ---------- http 实现（自研内部 API，二开后启用） ----------

async function httpRequest(method, path, body, headers = {}) {
  const res = await fetch(`${station().baseUrl}${path}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${station().apiKey}`,
      ...headers,
    },
    body: body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(station().timeoutMs),
  });
  if (res.status === 404) return null;
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    const err = new Error(`中转站内部接口返回 ${res.status}: ${text.slice(0, 200)}`);
    err.code = 'STATION_UNAVAILABLE';
    throw err;
  }
  return res.json();
}

// ---------- 导出 ----------

export function findAccountByLinuxdoId(linuxdoUserId, usernameHint) {
  if (station().mode === 'mock') return mockFindAccount(linuxdoUserId);
  if (station().mode === 'newapi') return newapiFindAccount(linuxdoUserId, usernameHint);
  return httpRequest('GET', `/internal/v1/users/by-linuxdo/${encodeURIComponent(linuxdoUserId)}`);
}

export function creditReward(order) {
  if (station().mode === 'mock') return mockCreditReward(order);
  if (station().mode === 'newapi') return newapiCreditReward(order);
  return httpRequest('POST', '/internal/v1/reward-orders', order, { 'Idempotency-Key': order.order_no });
}

export function getRewardOrder(orderNo) {
  if (station().mode === 'mock') return mockGetRewardOrder(orderNo);
  if (station().mode === 'newapi') return null; // new-api 无订单概念，以本地 reward_orders 为准
  return httpRequest('GET', `/internal/v1/reward-orders/${encodeURIComponent(orderNo)}`);
}
