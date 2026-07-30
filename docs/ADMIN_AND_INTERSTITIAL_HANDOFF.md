# 管理后台与网页插屏交接手册

游戏运营、广告额度、NewAPI 动态模型和本站 API 地址的最新交接说明见 `docs/GAME_AD_AI_OPERATIONS_HANDOFF.md`。

更新日期：2026-07-30

## 1. 功能范围

`admin/` 是独立的 Vue 3 管理后台，使用 Vite、Pinia、Vue Router 和 Element Plus。当前包含：

- 运营总览：用户、广告任务、广告奖励、回调异常、网页插屏漏斗和游戏结算数据。
- 用户管理：按用户 ID 或昵称查询账号状态、AI 额度、游戏积分和中转站用户 ID。
- 广告中心：奖励任务、HJ 平台回调审计、网页插屏曝光/点击/关闭/失败埋点。
- 全局插屏：加载、素材展示、关闭、失败静默退出、冷却和全局调用。

管理端和 App 用户使用两套令牌。管理员 JWT 的 `scope`、签发者、受众和密钥均独立，不能用 App 用户 Token 访问管理接口。

## 2. 本地启动

先启动 PostgreSQL 和 Node 服务端：

```powershell
cd server
npm.cmd ci
npm.cmd run migrate
npm.cmd start
```

再启动管理后台：

```powershell
cd admin
npm.cmd ci
npm.cmd run dev
```

Vite 会自动选择可用端口，并把 `/api` 与 `/healthz` 代理到 `http://127.0.0.1:3001`。页面默认地址为 `http://127.0.0.1:5173/admin/`；若 5173 已占用，以终端显示的端口为准。

## 3. 管理员配置

服务端环境变量：

```text
ADMIN_AUTH_ENABLED=true
ADMIN_USERNAME=admin
ADMIN_PASSWORD_HASH=<bcrypt 哈希，禁止填明文>
ADMIN_JWT_SECRET=<至少 32 字符的独立随机密钥>
ADMIN_JWT_EXPIRES_IN=8h
```

生成 bcrypt 哈希：

```powershell
node -e "import('bcryptjs').then(async ({default:b}) => console.log(await b.hash(process.argv[1], 12)))" "替换为强密码"
```

`ADMIN_JWT_SECRET` 不能与 App 的 `JWT_SECRET` 相同。生产凭据只保存在服务器密钥系统或未提交的 `.env`，不得写入 Git、APK、截图或交接文档。

## 4. 数据库迁移

管理后台和网页插屏依赖 `server/sql/migrate_v10.sql`，新增：

- `admin_audit_logs`：管理员登录审计。
- `ad_client_events`：网页插屏客户端埋点。

统一执行全部迁移：

```powershell
cd server
npm.cmd run migrate
```

迁移脚本可重复执行。发布前先备份 PostgreSQL；迁移完成后再发布 Node 和管理端静态文件。

## 5. 生产构建与托管

```powershell
cd admin
npm.cmd ci
npm.cmd run test
npm.cmd run build
```

产物位于 `admin/dist/`。Node 启动时会检测该目录，并同源托管：

- `/admin/`：管理后台。
- `/api/admin/*`：管理员接口。
- `/api/web-ads/interstitial`：网页插屏素材。
- `/api/ad-events`：网页插屏埋点。

Vue 路由使用 `/admin/` history base，Node 已为 `/admin/*` 回退到 `index.html`。现有 Nginx 的 `location /` 会把这些地址代理给 Node，不需要另加 SPA 回退规则。若以后把 `admin/dist` 放到 CDN/Nginx 静态目录，必须保留 `/admin/* -> /admin/index.html` 的回退。

构建已把 Vue 运行时、Element Plus 和其余依赖拆成独立缓存包，降低业务页面更新时的重复下载量。首次加载仍应启用 Brotli 或 gzip，并为带 hash 的 `/admin/assets/*` 设置长期缓存。

## 6. 网页插屏配置

服务端环境变量以 `server/.env.example` 和 `server/.env.production.example` 为准，核心配置包括开关、素材 ID、标题、正文、图片地址、点击地址和默认冷却秒数。图片与点击地址仅允许 `http` 或 `https`。

全局组件：

- `admin/src/components/GlobalInterstitialAd.vue`
- `admin/src/stores/interstitialAd.ts`
- `admin/src/composables/useBusinessAdTriggers.ts`

App 根组件只挂载一次 `GlobalInterstitialAd`。任何页面通过 Pinia 调用：

```ts
import { useInterstitialAdStore } from '@/stores/interstitialAd'

const interstitial = useInterstitialAdStore()
await interstitial.show({
  trigger: 'profile_opened',
  placement: 'global_interstitial',
  cooldownSeconds: 60,
  metadata: { source: 'profile' },
})
```

三个业务触发示例位于 `admin/src/examples/interstitial-triggers.ts`：

```ts
const { onRewardedAdCompleted, onGameSettled, onRedPacketClaimed } = useBusinessAdTriggers()

await onRewardedAdCompleted()
await onGameSettled(roundId)
await onRedPacketClaimed(packetId)
```

规则：

- 默认 60 秒内同一 `placement` 不重复展示，时间写入 `localStorage`。
- 同一时刻仅允许一个加载或展示请求，防止多业务回调并发弹窗。
- 素材请求失败或图片加载失败会自动关闭，不抛错打断原业务。
- 曝光只在素材可见后上报；点击、关闭和加载失败分别上报独立事件。
- 埋点使用 UUID 幂等；服务端按来源 IP 限制每分钟最多 120 条。
- 插屏是普通展示广告，不负责 AI 额度发奖。AI 额度只能由 HJ 激励视频的服务器签名回调发放。

## 7. Flutter 插屏触发

Flutter 当前在用户主动切换到底部“生图”或“我的”时尝试展示原生插屏。不要把触发放进两个页面的 `initState`，因为 `IndexedStack` 会在 App 启动时同时初始化子页面，导致误弹。

App 开屏、插屏、激励广告是三种独立广告位：

- 开屏：隐私同意且 SDK 初始化成功后的冷启动阶段，受服务端每日次数和间隔限制。
- 插屏：页面切换或游戏流程结束后的低频展示，不发额度。
- 激励：用户主动点击观看，只有 HJ 服务器回调验证成功才发 AI 额度或确认游戏复活。

下载广告素材是否出现由 HJ 和上游广告源决定。App 不得把“下载安装”作为发奖条件，也不得在只有客户端播放完成事件时直接加额度。

## 8. 上线验收

每次发布至少检查：

1. 未登录访问 `/admin/` 会跳转登录页；App Token 不能访问 `/api/admin/*`。
2. 登录失败和成功均写入管理员审计，响应不泄露密码、哈希或 JWT 密钥。
3. 总览、用户、奖励任务、回调和插屏埋点均能加载。
4. 插屏打开后出现曝光记录，关闭或点击后出现对应记录；冷却期内不重复展示。
5. 素材接口 500、超时或图片 404 时弹窗自动消失，原业务继续执行。
6. 在 390 x 844 手机尺寸下无整页横向滚动；导航变为抽屉，宽表只在卡片内部滚动。
7. 浏览器控制台无应用错误，`npm run build` 无超大业务主包警告。
8. `server npm test`、`admin npm test`、`admin npm run build`、`flutter analyze` 和 `flutter test` 全部通过。

## 9. 常见排查

- 管理端显示未启用：核对 `ADMIN_AUTH_ENABLED`、bcrypt 格式哈希和独立 JWT 密钥，重启 Node。
- 登录后立即返回登录页：检查系统时间、`ADMIN_JWT_EXPIRES_IN` 和反代是否移除了 `Authorization`。
- 插屏不出现：先清除对应 placement 的本地冷却记录，再检查素材接口是否返回 `enabled=true`。
- 插屏出现但后台无记录：检查 `/api/ad-events` 的 HTTP 状态、v10 迁移和反代限流。
- 激励视频播放完成但不到账：去广告中心查看平台回调；没有回调时检查 SDK 是否传入 `userId/task_token`，有回调时按签名、任务、交易号和发奖订单逐项排查。
