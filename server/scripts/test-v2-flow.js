// v2 登录流 + 发奖闭环端到端测试（本地）
// 用法: node scripts/test-v2-flow.js
// 前提: dev-db 与 server 均已启动。真实浏览器授权无法自动化，
//       本脚本直接把登录会话置为 authorized 模拟回调完成，其余全走真实 API。

import pg from 'pg';
import crypto from 'node:crypto';

const BASE = 'http://localhost:3001';
const DB = 'postgres://postgres:postgres@localhost:5433/linuxdo_ad_reward';
const AD_SECRET = 'local-test-ad-secret';

const results = [];
function check(name, cond, detail = '') {
  results.push({ name, pass: !!cond, detail });
  console.log(`${cond ? 'PASS' : 'FAIL'}  ${name}${detail ? '  -- ' + detail : ''}`);
}

async function api(method, path, body, headers = {}) {
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: { 'Content-Type': 'application/json', ...headers },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { status: res.status, body: await res.json().catch(() => ({})) };
}

const db = new pg.Client(DB);
await db.connect();

// ---------- 1. 创建登录会话 ----------
const start = await api('POST', '/api/v1/auth/linuxdo/start', { platform: 'android', app_version: '1.0.0' });
check('start 返回会话三元组', start.body?.data?.login_session_id && start.body?.data?.session_secret && start.body?.data?.auth_url);
const { login_session_id, session_secret } = start.body.data;

// ---------- 2. pending 状态轮询 ----------
const pending = await api('POST', '/api/v1/auth/linuxdo/status', { login_session_id, session_secret });
check('授权前状态为 pending', pending.body?.data?.status === 'pending');

// ---------- 3. 错误 secret 被拒绝 ----------
const badSecret = await api('POST', '/api/v1/auth/linuxdo/status', { login_session_id, session_secret: 'ss_' + '0'.repeat(64) });
check('错误 session_secret 返回 401 AUTH_SESSION_PROOF_INVALID', badSecret.status === 401 && badSecret.body?.error?.code === 'AUTH_SESSION_PROOF_INVALID');

// ---------- 4. 模拟 OAuth 回调完成（真实流程由浏览器授权触发） ----------
await db.query(
  `UPDATE oauth_login_sessions
   SET status='authorized', state_used_at=NOW(), linuxdo_user_id='445129', linuxdo_username='9988663q',
       linuxdo_trust_level=2, station_user_id=1, updated_at=NOW()
   WHERE login_session_id=$1`, [login_session_id]);

// ---------- 5. 首次轮询领取 login_code ----------
const st1 = await api('POST', '/api/v1/auth/linuxdo/status', { login_session_id, session_secret });
check('authorized 轮询返回 login_code', st1.body?.data?.status === 'authorized' && st1.body?.data?.login_code);
const code1 = st1.body.data.login_code;

// ---------- 6. 响应丢失场景：再次轮询立即换发新码，旧码作废 ----------
const st2 = await api('POST', '/api/v1/auth/linuxdo/status', { login_session_id, session_secret });
const code2 = st2.body?.data?.login_code;
check('再次轮询换发新 login_code', code2 && code2 !== code1);
const exOld = await api('POST', '/api/v1/auth/exchange', { login_session_id, session_secret, login_code: code1, device_name: 'test' });
check('被换发作废的旧码无法交换', exOld.status === 401);

// ---------- 7. 用新码交换 Token（三要素校验） ----------
const exBadSecret = await api('POST', '/api/v1/auth/exchange', { login_session_id, session_secret: 'ss_' + '0'.repeat(64), login_code: code2 });
check('exchange 校验 session_secret', exBadSecret.status === 401 && exBadSecret.body?.error?.code === 'AUTH_SESSION_PROOF_INVALID');
const ex = await api('POST', '/api/v1/auth/exchange', { login_session_id, session_secret, login_code: code2, device_name: 'Test Device' });
check('exchange 成功返回 access+refresh', ex.body?.data?.access_token && ex.body?.data?.refresh_token, `user=${JSON.stringify(ex.body?.data?.user)}`);
const { access_token, refresh_token } = ex.body.data;

// ---------- 8. login_code 只能用一次 ----------
const exAgain = await api('POST', '/api/v1/auth/exchange', { login_session_id, session_secret, login_code: code2 });
check('login_code 重复交换被拒绝', exAgain.status === 401 && exAgain.body?.error?.code === 'LOGIN_CODE_USED');

// ---------- 9. Access Token 可用（走旧鉴权中间件） ----------
const me = await api('GET', '/api/auth/me', null, { Authorization: `Bearer ${access_token}` });
check('access_token 可访问受保护接口', me.body?.linuxdo_username === '9988663q', JSON.stringify(me.body));

// ---------- 10. Refresh 轮换 ----------
const rf1 = await api('POST', '/api/v1/auth/refresh', { refresh_token });
check('refresh 轮换成功', rf1.body?.data?.refresh_token && rf1.body?.data?.refresh_token !== refresh_token);
const refresh_token2 = rf1.body.data.refresh_token;

// ---------- 11. 旧 refresh_token 复用 → 家族整体撤销 ----------
const rfReuse = await api('POST', '/api/v1/auth/refresh', { refresh_token });
check('旧 refresh_token 复用被检测', rfReuse.status === 401 && rfReuse.body?.error?.code === 'REFRESH_TOKEN_REUSED');
const rfFamily = await api('POST', '/api/v1/auth/refresh', { refresh_token: refresh_token2 });
check('复用后整个家族被撤销（新 token 也失效）', rfFamily.status === 401);

// ---------- 12. 重新登录拿一套干净 token 测广告闭环 ----------
const start2 = await api('POST', '/api/v1/auth/linuxdo/start', { platform: 'android' });
const s2 = start2.body.data;
await db.query(
  `UPDATE oauth_login_sessions
   SET status='authorized', state_used_at=NOW(), linuxdo_user_id='445129', linuxdo_username='9988663q',
       linuxdo_trust_level=2, station_user_id=1, updated_at=NOW()
   WHERE login_session_id=$1`, [s2.login_session_id]);
const st3 = await api('POST', '/api/v1/auth/linuxdo/status', { login_session_id: s2.login_session_id, session_secret: s2.session_secret });
const ex2 = await api('POST', '/api/v1/auth/exchange', { login_session_id: s2.login_session_id, session_secret: s2.session_secret, login_code: st3.body.data.login_code });
const at = ex2.body.data.access_token;

// ---------- 13. 广告任务 + 回调发奖 + 中转站入账 ----------
const before = await api('GET', '/api/wallet', null, { Authorization: `Bearer ${at}` });
const task = await api('POST', '/api/ad-task/start', null, { Authorization: `Bearer ${at}` });
check('广告任务创建（linuxdo 主身份校验通过）', !!task.body?.task_token, JSON.stringify(task.body));
const taskToken = task.body.task_token;

const { rows: uidRows } = await db.query(`SELECT id FROM users WHERE linuxdo_user_id='445129'`);
const uid = uidRows[0].id;
const ts = Math.floor(Date.now() / 1000);
const sign = crypto.createHmac('sha256', AD_SECRET).update(`${taskToken}${uid}${ts}`).digest('hex');
const cb = await api('POST', '/api/ad-callback/reward', { task_token: taskToken, user_id: uid, timestamp: ts, sign, transaction_id: 'tx_test_' + ts });
check('广告回调发奖成功', cb.body?.code === 0, cb.body?.message);

const cbDup = await api('POST', '/api/ad-callback/reward', { task_token: taskToken, user_id: uid, timestamp: ts, sign, transaction_id: 'tx_test_' + ts });
check('重复回调幂等', cbDup.body?.code === 0 && cbDup.body?.message?.includes('重复'));

const after = await api('GET', '/api/wallet', null, { Authorization: `Bearer ${at}` });
check('本地钱包镜像 +100000 microunits', Number(after.body?.balance_microunits) === Number(before.body?.balance_microunits) + 100000,
  `${before.body?.balance_microunits} -> ${after.body?.balance_microunits}`);

const { rows: orderRows } = await db.query(`SELECT status, station_transaction_id, amount_microunits FROM reward_orders WHERE ad_task_id=$1`, [taskToken]);
check('奖励订单入账 success', orderRows[0]?.status === 'success' && orderRows[0]?.station_transaction_id, JSON.stringify(orderRows[0]));

const { rows: stationRows } = await db.query(`SELECT balance_microunits FROM mock_station_accounts WHERE linuxdo_user_id='445129'`);
check('mock 中转站余额同步增加', stationRows.length === 1, `station balance=${stationRows[0]?.balance_microunits}`);

// ---------- 14. 密码注册已停用 ----------
const reg = await api('POST', '/api/auth/register', { username: 'newuser_' + ts, password: 'pass123456' });
check('密码注册返回 403 停用提示', reg.status === 403);

// ---------- 15. 登出撤销 ----------
const lo = await api('POST', '/api/v1/auth/logout', { refresh_token: ex2.body.data.refresh_token }, { Authorization: `Bearer ${at}` });
check('logout 成功', lo.body?.data?.logged_out === true);
const rfAfterLogout = await api('POST', '/api/v1/auth/refresh', { refresh_token: ex2.body.data.refresh_token });
check('登出后 refresh_token 失效', rfAfterLogout.status === 401);

await db.end();
const failed = results.filter((r) => !r.pass);
console.log(`\n===== ${results.length - failed.length}/${results.length} 通过 =====`);
process.exit(failed.length ? 1 : 0);
