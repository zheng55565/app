// LinuxDo Connect OAuth2 客户端封装
//
// 接入规则（https://wiki.linux.do/Community/LinuxDoConnect）：
// 1. 在 https://connect.linux.do/dash/sso 申请接入，填写回调地址，获得 Client Id / Secret
// 2. 授权端点:   GET  https://connect.linux.do/oauth2/authorize?response_type=code&client_id=...&state=...&redirect_uri=...
// 3. Token 端点: POST https://connect.linux.do/oauth2/token
//    认证方式为 HTTP Basic: base64(client_id:client_secret)，body 为 grant_type=authorization_code&code=...&redirect_uri=...
// 4. 用户信息:   GET  https://connect.linux.do/api/user  （注意不是 /oauth2/userinfo，用错会 403）
//    携带 Authorization: Bearer <access_token>
// 5. 返回字段: id（不可变唯一标识）、username、name、avatar_template、active、
//    trust_level（0-4 信任等级）、silenced、external_ids、api_key
//    建议基于 id 做绑定与频控，基于 trust_level 做额度分配。

import crypto from 'node:crypto';
import { config } from '../config.js';

const ld = config.linuxdo;

export function generateState() {
  return crypto.randomBytes(24).toString('hex');
}

// 构造授权跳转地址（redirectUri 可覆盖：绑定流与 v2 登录流回调端点不同）
export function buildAuthorizeUrl(state, redirectUri = ld.redirectUri) {
  const params = new URLSearchParams({
    response_type: 'code',
    client_id: ld.clientId,
    state,
    redirect_uri: redirectUri,
  });
  return `${ld.authorizeUrl}?${params.toString()}`;
}

// 用授权码换取 access_token
export async function exchangeCodeForToken(code, redirectUri = ld.redirectUri) {
  const basic = Buffer.from(`${ld.clientId}:${ld.clientSecret}`).toString('base64');
  const res = await fetch(ld.tokenUrl, {
    method: 'POST',
    headers: {
      Authorization: `Basic ${basic}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: new URLSearchParams({
      grant_type: 'authorization_code',
      code,
      redirect_uri: redirectUri,
    }),
  });
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new Error(`LinuxDo token 接口返回 ${res.status}: ${text}`);
  }
  return res.json(); // { access_token, refresh_token, token_type, expires_in, ... }
}

// 获取论坛用户信息
export async function fetchLinuxdoUser(accessToken) {
  const res = await fetch(ld.userInfoUrl, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new Error(`LinuxDo 用户信息接口返回 ${res.status}: ${text}`);
  }
  return res.json(); // { id, username, name, avatar_template, active, trust_level, silenced, ... }
}
