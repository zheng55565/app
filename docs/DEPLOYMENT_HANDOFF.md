# AI公益工作台部署与交接

更新日期：2026-07-30

## 1. 系统组成

- `app/`：Flutter App，包含工作台、生图、额度、游戏和“我的”。
- `server/`：Node.js 业务后端，处理登录、AI代理、广告任务、钱包、游戏和文档任务。
- PostgreSQL：所有余额、广告幂等、设备风控和游戏结算的最终数据源。
- NewAPI/中转站：实际 AI 模型和 API 额度账户。
- HJ 聚合广告：App 只负责播放；额度只能由 HJ 服务端回调后发放。
- Nginx/Caddy：生产环境 HTTPS、限流、请求大小和反向代理入口。

游戏积分和 AI 额度均不能提现、不能转赠。不要在客户端保存 NewAPI 管理令牌、HJ Security Key 或服务端密钥。

## 2. 本机已验证状态

- PostgreSQL 16 Docker 容器：`freenew-postgres`，本机端口 `5433`。
- Node 服务：`http://127.0.0.1:3001`。
- 健康检查：`/healthz`；数据库就绪：`/readyz`。
- 隐私政策：`/privacy/`；游戏大厅：`/games/`。
- 临时 HTTPS 隧道仅用于联调，`trycloudflare.com` 地址重启后可能变化，不能用于生产。
- Flutter、Android 与管理后台构建产物均可由本仓库源码和锁文件复现。
- Git 交付只包含源码、迁移、部署模板和文档；APK、截图、日志、`dist/`、`build/` 与本机 `outputs/` 不进入仓库。
- HJ 激励视频服务器回调已启用，真实 Security Key 已写入本机未提交的 `server/.env`，并已通过签名、幂等和跨任务重放验证。

本机 HJ 联调包和 HJ 后台回调都绑定当前临时隧道。隧道停止或地址变化后，需要同时更新 HJ 后台回调地址并重新构建 APK。

## 3. Windows 本机启动

首次启动 Docker Desktop 后创建数据库：

```powershell
docker run -d --name freenew-postgres `
  -e POSTGRES_USER=postgres `
  -e POSTGRES_PASSWORD=postgres `
  -e POSTGRES_DB=linuxdo_ad_reward `
  -p 127.0.0.1:5433:5432 `
  postgres:16-alpine
```

已创建过时只需：

```powershell
docker start freenew-postgres
```

初始化或升级数据库时，先执行 `server/sql/schema.sql`，再按数字顺序执行全部 `migrate_v*.sql`。脚本必须可重复执行；任何新增迁移都要加入部署流程。

启动后端：

```powershell
cd server
npm.cmd ci
npm.cmd start
```

启动临时 HTTPS 隧道：

```powershell
cloudflared tunnel --url http://127.0.0.1:3001 --no-autoupdate
```

至少验证：

```text
GET /healthz
GET /readyz
GET /privacy/
GET /games/
GET /api/app/ad-config
```

## 4. Android 构建

环境要求：Flutter 3.44、JDK 17、Android SDK、CMake 3.22.1，并接受 Android licenses。

本机内存较小，`app/android/gradle.properties` 已限制为 1.28GB 和单 worker。不要恢复 Kotlin daemon 的 `-Xmx8G` 配置。

无需 L 站授权检查包只演示界面，不调用 Linux.do、业务后台或真实 HJ 广告：

```powershell
cd app
flutter pub get
flutter build apk --debug --split-per-abi --dart-define=PREVIEW_MODE=true
```

检查包仍保留登录页，默认检查账号为 `preview_user`、检查口令为 `123456`。
登录只建立当前 App 进程内的本机会话，账号和口令不会发送或落库；退出登录会返回该登录页。
登录后可以检查工作台、生图、额度收支和四款本地游戏。检查包不会初始化真实广告，
点击广告入口只显示“未连接真实广告”，不会播放、增加次数或修改额度；禁止用本地假到账
冒充广告联调成功。所有余额、AI回复和游戏结算都是演示数据，不能用于真实账号、API调用
或广告回调验证。

构建完成后，Flutter 默认将 APK 写入：

```text
app/build/app/outputs/flutter-apk/
```

ARM64 适用于绝大多数近年安卓手机；只有较老的 32 位设备才使用 ARM32 包。

无需 Linux.do 的真实 HJ 广告联调包先在本机服务端设置：

```text
NODE_ENV=development
STATION_MODE=mock
PREVIEW_AUTH_ENABLED=true
PREVIEW_AUTH_USERNAME=preview_user
PREVIEW_AUTH_PASSWORD=<本机检查口令>
AD_PROVIDER=hj
AD_DEV_SIMULATE=false
```

然后构建：

```powershell
flutter build apk --debug --split-per-abi `
  --dart-define=AD_PREVIEW_MODE=true `
  --dart-define=API_BASE_URL=https://your-test-domain.example `
  --dart-define=GAME_URL=https://your-test-domain.example/games/ `
  --dart-define=PRIVACY_POLICY_URL=https://your-test-domain.example/privacy/
```

该包保留登录页但隐藏 Linux.do；账号口令会发到开发服务端换取短期 Token。它不使用
`PreviewData`，钱包、广告任务和游戏接口都是真实服务端数据。服务端仅在非生产环境且
`STATION_MODE=mock` 时开放 `/api/auth/preview`；任一条件不满足即返回404，生产启动校验也会
拒绝 `PREVIEW_AUTH_ENABLED=true`。点击“看广告”只创建一次性任务并调用 HJ SDK，创建任务本身
不改余额；只有 HJ 回调签名、用户、广告位、设备/IP限额与 `transId` 全部通过才入账。

真实广告联调包保留本机检查登录页，连接构建时指定的业务后台与同源游戏页；不包含 NewAPI 管理地址。二进制包由接手方使用目标域名和目标 HJ 配置重新构建，避免把过期临时隧道写入安装包。

HJ 聚合 SDK 自带的原生广告库同时包含 `arm64-v8a` 与 `armeabi-v7a`，因此真实广告联调包
采用 universal APK，一份即可覆盖近年64位手机与旧32位手机。

正式发布前必须配置独立签名，移除 `release` 使用 debug signing 的临时设置。HJ 平台登记包名必须与 `applicationId` 完全一致。

## 5. HJ 广告配置

### 5.1 后端环境变量

```text
AD_PROVIDER=hj
AD_HJ_APP_ID=<HJ App ID>
AD_UNIT_REWARDED_HOME=<首页激励广告位>
AD_UNIT_REWARDED_GAME=<小游戏复活激励广告位>
AD_CALLBACK_SECRET=<HJ 后台 Security Key>
AD_REWARDED_ENABLED=true
AD_GAME_REWARDED_ENABLED=true
AD_DEV_SIMULATE=false
```

开屏和插屏通过服务端远程开关控制。本机 v11 联调配置已开启：开屏在冷启动完成且隐私授权通过后展示，每日最多1次、间隔12小时；插屏固定在用户退出游戏大厅返回额度页时尝试展示，每10分钟最多1次、每日最多2次，不得在下注、动画或结算中途打断。正式生产应给小游戏复活配置独立广告位，便于统计和隔离风险。无论是否复用广告位，`purpose=game_recovery` 都只验证一次性复活任务，绝不进入 AI 额度钱包。

开屏、插屏、激励必须分别使用 HJ 后台对应类型且审核通过的广告位 ID，不能互相替代。关闭或调整频控后重启 Node 即可，App 会从 `/api/app/ad-config` 获取配置，无需重新发版。

真实激励广告不能与 `PREVIEW_MODE=true` 的纯界面检查包混用；应使用正式登录包或
`AD_PREVIEW_MODE=true` 的隔离联调包。真实到账必须具备服务端登录账号、一次性
`task_token`、HJ SDK 完整播放事件和HJ服务端签名回调；客户端播放完成事件本身不能发额度。

### 5.2 HJ 服务端回调

在 HJ 后台启用激励视频服务端回调，使用：

```text
https://your-domain.example/api/ad-callback/hj/reward?userId={{USER_ID}}&rewardAmount={{REWARD_AMOUNT}}&rewardName={{REWARD_NAME}}&transId={{TRANS_ID}}&sign={{SIGN}}&extrainfo={{EXTRAINFO}}&placementId={{PLACEMENT_ID}}
```

然后复制该应用的 Security Key 到服务端 `AD_CALLBACK_SECRET`，重启 Node。不要把 Security Key 写进 Flutter、Git、截图或交接文档。

HJ 回调成功响应为：

```json
{"isValid":true}
```

失败签名返回 403；同一 `transId` 用于另一任务返回 409；同一任务的重复回调返回成功但不重复入账。`migrate_v9.sql` 新增 `ad_callback_audits`，所有到达请求（包括签名错误或业务拒绝）都会保存脱敏参数、HTTP 状态和拒绝原因，签名原文不会入库。

HJ 实测的 `PLACEMENT_ID` 会返回本次瀑布流命中的动态渠道代码位，不一定等于 App 请求时使用的 HJ 聚合广告位。因此 HJ 回调不能对这两个值做等值校验；仍必须校验 HJ 签名、随机一次性 `task_token`、`user_id`、客户端 `transId`，并确认数据库任务本身使用的是首页激励广告位。其他广告平台仍保留广告位严格匹配。

### 5.3 广告到账链路

```text
App 创建 task_token -> HJ SDK 播放完整视频 -> App 登记 SDK transId
HJ 签名回调后端 -> 交叉核对客户端 transId（已登记时）
-> 校验 Security Key 签名、用户、任务广告位资格、设备/IP日限额和 transId
-> PostgreSQL 事务入账 -> NewAPI 入账 -> App 轮询 rewarded 并刷新余额
```

`POST /api/ad-task/client-complete` 只登记客户端看到的交易号，不会加额度。脚本即使伪造该接口，也无法绕过 HJ 的服务器签名回调。`GET /api/ad-task/status/:task_token` 会返回 `client_evidence_received` 和 `platform_callback_received`，用于区分“App 已完成但 HJ 尚未回调”和“平台已回调并已入账”。

激励视频是否展示下载型素材由 HJ 及其上游渠道的库存、素材和投放策略决定，Flutter 端不能把下载设为发奖条件，也不能强行把下载型素材改成纯视频。App 只认可 SDK 的 `onVideoRewarded(isReward=true)`；用户无需主动下载应用。若大量素材要求下载或 `isReward=false`，应让 HJ 技术支持按应用/广告位调整广告源，并提供广告位 ID、发生时间、手机型号和 `transId`，不要提供 Security Key。

消消乐复活使用独立状态机：`created -> verified -> consumed`。客户端播放完成事件不增加步数；只有 HJ 签名回调把任务改为 `verified` 后，App 才能消费任务并由服务端增加5步。`task_token`、广告交易号和消费操作均为一次性。

仅客户端收到 `onVideoRewarded` 不代表到账。排查“看完没额度”时依次检查：

1. App 是否为正式包或 `AD_PREVIEW_MODE` 联调包，且用户已同意隐私政策；
   `PREVIEW_MODE` 纯界面包不会加载广告。
2. `/api/app/ad-config` 是否返回 `provider=hj` 且首页广告位启用。
3. `ad_tasks` 是否创建、是否过期、广告位是否正确。
4. HJ 后台回调地址和 Security Key 是否已保存。
5. `ad_callback_audits` 是否出现该 `transId`，并查看 `signature_valid`、`http_status` 和 `outcome`。
6. `client_transaction_id` 是否已登记，以及 `provider_transaction_id`、`wallet_records` 和 `reward_orders` 状态。
7. `reward_orders=crediting` 时先人工核对 NewAPI，禁止自动重发。

```sql
SELECT received_at, user_id, transaction_id, task_token, placement_id,
       signature_valid, http_status, outcome
FROM ad_callback_audits
ORDER BY id DESC
LIMIT 20;
```

如果App已收到播放完成事件，但任务仍为`created`，同时HJ数据中心展示量仍为0，说明正式广告位尚未记录有效展示，不能在客户端补发额度。应连接手机读取`HJ######TAG`日志，核对`onVideoAdPlayStart`、`onVideoRewarded`中的广告位和交易号，再用新的播放任务确认HJ服务端回调是否到达。App只显示“奖励验证中”，不得把客户端完成事件当成到账凭证。

2026-07-30 本机最终实测：HJ SDK 已依次触发加载、开始播放、`isReward=true` 和关闭事件；HJ 服务端随后两次回调同一 `transId`，`userId`、`task_token` 和签名均正确。原后端因把动态 `PLACEMENT_ID` 与聚合广告位做等值判断而返回403；移除这项 HJ 专属错误判断后，同一条已签名验证的真实回调成功返回 `{"isValid":true}`，任务状态为 `rewarded`、每日次数为1/6、奖励订单为`success`，App显示今日收益 `$0.0028`。提交 HJ 技术支持时可提供广告位 ID、播放时间和交易号，但绝不要提供 Security Key。

## 6. NewAPI 与 AI

生产建议：

```text
STATION_MODE=newapi
STATION_BASE_URL=https://newapi.example
STATION_ADMIN_TOKEN=<服务端管理令牌>
STATION_ADMIN_ID=1
AI_ENABLED=true
AI_UPSTREAM_BASE_URL=https://newapi.example
AI_ALLOW_USER_API_KEY=true
AI_CREDENTIAL_ENCRYPTION_KEY=<至少32字符随机密钥>
```

服务端负责模型列表、对话、生图、文档任务和额度扣费。Flutter 只访问本站后端，不直接获得管理令牌。用户自带 Key 必须加密保存，日志中不得输出明文。

## 7. Linux 生产部署

建议 Node 20/22 LTS、PostgreSQL 16、Nginx 和 systemd。参考：

- `deploy/gongyi-app.service`
- `deploy/gongyi-app@.service`
- `deploy/nginx-gongyi-app.conf.example`
- `deploy/env.production.template`

生产环境必须满足：

```text
NODE_ENV=production
BASE_URL=https://your-domain.example
TRUST_PROXY_HOPS=1
AD_DEV_SIMULATE=false
```

JWT、风控哈希、AI Key 加密和 HJ 回调必须使用四个不同的随机密钥。部署后先跑迁移，再启动 Node，最后放开 Nginx 流量。

## 8. 并发与内存

- 钱包、广告发奖、红包领取、八房结算、消消乐通关奖励和宝箱使用数据库事务、行锁、唯一索引和请求幂等号，多实例共用同一 PostgreSQL 时仍可防重复。
- 八房进入对局后每次只接受1/10/50积分，允许同一回合多次追加并原子累计；前20秒可用0积分请求移动全部已有投入，换房不再次扣分；最后5秒封盘后拒绝切换和追加。
- 八房结算公式为：个人幸存投入 / 全部幸存投入（含服务端对手） × 失败池扣10%后的利润，再加本人本金。每轮随机淘汰2至3房。
- 消消乐每次交换都由服务端保存并重算棋盘；`(user_id, level_no)` 保证每关只发一次1积分，宝箱结果由服务端按90%/5%/4%/1%抽取。
- Node 数据库连接池默认每实例 20。实例数乘以池大小必须小于 PostgreSQL `max_connections`，并预留运维连接。
- AI 默认每实例总并发 100、单用户 3。多实例部署时这是“每实例”限制；正式大规模上线应增加 Redis/数据库分布式信号量，或按实例数降低 `AI_MAX_CONCURRENT`。
- 文档任务由队列领取，单实例默认 2 worker。先压测 CPU、内存和磁盘，再增加 worker。
- 生图和大模型响应使用流式转发，禁止把大响应完整缓存在 Node 内存。
- 至少配置两个 Node 实例和负载均衡健康检查；单实例异常时从代理摘除，不应拖死全部用户。
- HJ 回调和钱包接口在 Nginx 设置单独限流，但不能阻断平台正常重试。

## 9. 备份与恢复

每日备份 PostgreSQL，并把备份复制到另一台机器或对象存储：

```bash
pg_dump -Fc -d linuxdo_ad_reward -f backup-$(date +%F-%H%M).dump
```

恢复演练：

```bash
createdb linuxdo_ad_reward_restore
pg_restore --clean --if-exists -d linuxdo_ad_reward_restore backup.dump
```

同时备份生产 `.env` 到受控密钥系统，不要放入 Git。文档产物目录按保留周期清理，数据库流水和审计记录不要与临时文件一起删除。

## 10. 发布、回滚与验收

发布顺序：数据库备份 -> 在 `server/` 执行 `npm run migrate` -> 发布后端 -> 健康检查 -> 小流量验证 -> 发布 App。

回滚原则：

- 后端代码可回滚到上一个构建，但已经执行的数据库迁移不要直接删除列或表。
- 使用向前修复迁移恢复兼容性。
- 广告异常时先远程设置 `AD_REWARDED_ENABLED=false`，避免继续创建任务。
- NewAPI 异常时暂停发奖入口，保留 `reward_orders` 供人工对账。

每次上线至少验收：

- 重复抢同一红包只能成功一次，按钮显示“已领”且不可再次点击。
- 游戏历史分类、胜负、中雷、投入、到账、手续费和净盈亏完整。
- 八房最近10局无需参与也可查看；最后5秒封盘并高亮幽灵淘汰的2至3个房间。
- 红包发布者本人可以领取；同一账号或设备第二次领取必须返回409。拆红包先展示红色开盖页，再进入独立领取详情页；详情只显示昵称、金额、领取时间和中雷标记，不得出现尾号或任何复盘数据。
- 消消乐重复通关不重复发奖；第10关宝箱只能开启一次；未验证广告不能复活。
- 错误广告签名拒绝；正确回调仅入账一次；跨任务重放拒绝。
- App 隐私同意前不初始化真实广告 SDK。
- `/healthz`、`/readyz`、隐私页、游戏页和广告配置均通过 HTTPS 访问。
