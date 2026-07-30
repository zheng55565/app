# linuxdo-ad-reward-server

公益中转站广告奖励 App 后端。**v2 已切换为「Linux.do 唯一身份」登录体系**（详见《移动端Linuxdo-OAuth登录方案.md》），旧的密码注册已停用、密码登录仅迁移期保留。

## v2 登录体系（/api/v1/auth）

- `POST /api/v1/auth/linuxdo/start` — 创建登录会话，返回 `auth_url + login_session_id + session_secret`（secret 仅 App 持有，绝不进 URL）
- `GET  /api/v1/auth/linuxdo/callback` — Linux.do OAuth 回调（回跳不携带任何凭证）
- `POST /api/v1/auth/linuxdo/status` — App 轮询；首次有效轮询原子签发一次性 `login_code`（4 分钟过期，可持 secret 立即换发）
- `POST /api/v1/auth/exchange` — `session_id + secret + login_code` 三要素原子校验，签发 Access Token（15 分钟）+ Refresh Token（30 天，轮换 + 复用检测家族撤销）
- `POST /api/v1/auth/refresh` / `POST /api/v1/auth/logout`

登录前提：用户已在 API 中转站通过 Linux.do 注册（`STATION_MODE=mock` 时由本地 `mock_station_accounts` 表模拟；接入 new-api 后改 `STATION_MODE=http` 并实现内部 API）。

金额已统一为 **BIGINT microunits（1 元 = 1,000,000）**，旧 NUMERIC 列保留对账。广告发奖后通过 `reward_orders` 幂等入账中转站，本地钱包为余额镜像。

⚠️ Linux.do 应用设置中需登记 v2 回调地址：`{BASE_URL}/api/v1/auth/linuxdo/callback`

## 旧版功能（v1，迁移期保留）

- 用户注册 / 登录（JWT）
- **Linux.do 账号绑定 —— 使用官方 LINUX DO Connect OAuth2**（不收集用户密码）
- 广告任务创建（一次性 task_token，10 分钟过期）
- 广告平台服务端回调（签名校验 + 幂等发奖 + 行锁防并发）
- 每日 6 次限制（后端原子控制）
- 钱包余额 + 流水
- App 版本检查接口

## LinuxDo Connect 接入规则（重点）

1. 到 **https://connect.linux.do/dash/sso** 「我的应用接入 → 申请新接入」，回调地址填 `{BASE_URL}/api/linuxdo/bind/callback`，拿到 Client Id / Client Secret。
2. 三个端点：
   - 授权：`https://connect.linux.do/oauth2/authorize?response_type=code&client_id=...&state=...`
   - 换 Token：`POST https://connect.linux.do/oauth2/token`，HTTP Basic 认证（`base64(client_id:client_secret)`）
   - 用户信息：`GET https://connect.linux.do/api/user`（⚠️ 不是 `/oauth2/userinfo`，用错返回 403），Bearer access_token
3. 可拿到字段：`id`（不可变唯一标识，用它做绑定去重）、`username`、`name`、`avatar_template`、`active`、`trust_level`（0-4）、`silenced` 等。
4. 本框架内置校验：禁言/未激活账号拒绝绑定；可通过 `LINUXDO_MIN_TRUST_LEVEL` 要求最低信任等级；同一 Linux.do id 只能绑定一个中转站账号（数据库部分唯一索引兜底）。

## 快速开始

```bash
cd server
npm install
cp .env.example .env      # 填写数据库、JWT、LinuxDo Client Id/Secret
psql -d linuxdo_ad_reward -f sql/schema.sql
npm run dev
```

## 绑定流程（App 侧）

1. `POST /api/linuxdo/bind/start`（带用户 JWT）→ 返回 `authorize_url`
2. App 用浏览器 / WebView 打开 `authorize_url`，用户在 Linux.do 授权
3. Linux.do 重定向到 `/api/linuxdo/bind/callback?code=...&state=...`，后端换 token、拉用户信息、落库绑定
4. App 轮询 `GET /api/linuxdo/bind/status` 确认绑定完成

## 广告奖励流程

1. `POST /api/ad-task/start` → 校验已绑定 + 今日次数 < 6 → 返回 `task_token`
2. App 播放激励视频（把 task_token 作为透传参数传给广告 SDK）
3. SDK 返回 `transId` 后，App 调用 `POST /api/ad-task/client-complete` 登记客户端凭据；该接口不发奖
4. HJ 服务端回调 `GET /api/ad-callback/hj/reward`，服务端验证平台签名、交易号幂等与风控后发奖
4. 后端事务内：行锁任务 → 幂等检查 → 次数原子递增 → 加余额 → 写流水
5. App 轮询 `GET /api/ad-task/status/:task_token` 展示到账

## 目录结构

```
server/
  sql/schema.sql          数据库结构
  src/
    index.js              入口 & 路由挂载
    config.js             环境变量配置
    db.js                 PG 连接池 & 事务封装
    middleware/auth.js    JWT 鉴权
    services/linuxdoClient.js  LinuxDo Connect OAuth2 客户端
    routes/
      auth.js             注册/登录/me
      linuxdo.js          绑定/回调/状态/解绑
      adTask.js           广告任务 + 服务端回调发奖
      wallet.js           余额/流水
      appVersion.js       版本检查
```

## 尚未实现（按文档规划的后续项）

- Redis 限流 / 风控（当前用 PG 表实现 state 与每日次数，单机够用）
- 管理后台
- 实际广告平台 SDK 对接（穿山甲 / 优量汇 / AdMob SSV 的签名校验各不相同，替换 `adTask.js` 中的 `verifySign`）
- Flutter App 端
