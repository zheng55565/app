# AI 公益工作台

本项目由 Flutter App、Node.js业务后台和现有New API实例组成。用户通过Linux.do登录，看奖励广告获得New API额度；同一额度可在网站API、App工作台和生图页面使用。

## 当前能力

- App四栏：AI工作台、生图、额度与娱乐、我的。
- App只连接业务后台，不保存New API管理地址。
- 用户网站API Key保存在手机安全存储，后台按白名单代理模型列表、聊天和生图接口。
- 奖励广告采用一次性任务、服务器回调、交易号幂等、账户/设备/IP每日上限。
- AI请求采用数据库并发租约，支持多Node副本统一限流。
- New API继续负责渠道聚合、模型路由和实际API额度扣减。
- AI额度与游戏积分支持1:1双向兑换；仅本人转入后尚未参与游戏的本金可兑回，游戏到账不可兑回、转赠或提现。
- 游戏大厅包含石头剪刀布、固定7人扫雷红包、八房生存局和宝石消消乐，结算与随机结果均由服务端负责。
- 游戏模块采用深蓝与浅蓝科技游戏风四栏导航；首页三张主游戏卡先进入专属选择页，再进入实际对局，消消乐保留在游戏大厅。
- 石头剪刀布支持10/50/100积分档位，获胜到账1.5倍；扫雷发布弹窗支持10/50/100积分和雷号选择，发布者本人也可领取，单账号与单设备每个红包只能领取一次。
- 八房进入对局前不选积分；进入房间后每次可追加1/10/50积分并自动累计。开局前20秒可切换房间且换房不重复扣分，最后5秒封盘。
- 八房页面按2行4列展示房间，每期使用稳定期号并保留最近10期淘汰与存活记录。
- 扫雷红包按发布时间从早到晚展示；拆红包采用红色开盖页，领取后进入独立详情页，仅展示昵称、金额、领取时间和中雷状态；发布7天仍未领完时，未领取份额自动退回发布者。
- 游戏记录保存个人逐局盈亏，排行榜只统计业务时区内的当日净盈利。

## 中转站与额度边界

- App只配置一个业务后台地址，不在安装包中暴露New API管理地址。
- “只能走本站”指额度账本：看广告得到的额度进入本站New API账号，只能由本站签发的API Key消费。
- “模型不只一家”：可在本站New API后台增加OpenAI兼容渠道，App刷新模型列表后即可使用，仍扣本站统一额度。
- 用户随意填写外部中转地址不属于当前范围。外部站额度与本站额度无法互通，且由业务后台代理任意URL会产生SSRF风险。
- 若以后开放外部站，应由管理员建立服务端白名单，并在界面明确显示“消耗外部站余额”，不能把它包装成本站广告额度。

## 目录

- `app/`：Flutter Android/Windows客户端。
- `admin/`：Vue 3 管理后台和全局网页插屏组件。
- `server/`：登录、广告奖励、钱包镜像、AI代理和风控后台。
- `server/sql/schema.sql`、`server/sql/migrate_v2.sql` 至 `migrate_v14.sql`：完整数据库结构、游戏、广告、后台管理和风控迁移。
- `deploy/`：生产环境变量、systemd、Nginx和安全边界示例。
- `docs/DEPLOYMENT_HANDOFF.md`：Windows/Android/HJ/NewAPI/Linux完整部署与交接手册。
- `docs/ADMIN_AND_INTERSTITIAL_HANDOFF.md`：管理后台、网页插屏、埋点和上线验收手册。
- `docs/DELIVERY_STATUS.md`：本次源码交付范围、已验证结果和生产部署待办。
- `server/public/games/`：App内游戏大厅网页，由Flutter白名单桥接服务端游戏接口。

## 本地启动

1. 在 `server/` 执行 `npm ci`。
2. 根据 `server/.env.example` 创建本地 `.env`。
3. 启动开发数据库：`node scripts/dev-db.js`。
4. 启动后台：`npm run dev`。
5. 在 `admin/` 执行 `npm ci && npm run dev` 启动管理后台；生产先执行 `npm run build`，Node 会同源托管 `/admin/`。
6. Flutter构建时通过 `--dart-define=API_BASE_URL=...` 指定业务后台；不要填写New API管理地址。
7. 正式广告包必须同时配置 `--dart-define=PRIVACY_POLICY_URL=https://...`；缺少该地址时真实广告SDK保持禁用。

本地可构建两种互不混淆的检查包：

- `PREVIEW_MODE=true`：纯界面检查，完全不请求真实广告，也不发额度。
- `AD_PREVIEW_MODE=true`：无需 Linux.do 的真实广告联调包；检查账号由开发服务端验证，
  HJ SDK 播放真实广告，只有 HJ 服务端签名回调成功才写入隔离的 mock 中转账本。
  服务端必须同时满足 `NODE_ENV!=production`、`STATION_MODE=mock`、
  `PREVIEW_AUTH_ENABLED=true`，生产配置会强制拒绝该模式。

生图还必须在后台设置 `AI_IMAGE_MODELS` 白名单，内容是New API模型ID并用逗号分隔；留空时生图入口不会把普通聊天模型误当成生图模型。

生产部署前必须阅读 `deploy/SECURITY.md`，按顺序执行 v2 至 v14 数据库迁移，并从公网验证内部端口不可达。

完整部署、广告回调和故障排查见 `docs/DEPLOYMENT_HANDOFF.md`；系统边界、扩容方式和Codex式任务服务的后续拆分见 `docs/ARCHITECTURE.md`。
