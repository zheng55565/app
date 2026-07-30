# 源码交付状态

交付日期：2026-07-30

## 交付范围

- `app/`：Flutter Android/Windows App，包含登录、AI 工作台、生图、额度流水、游戏大厅、记录和个人中心。
- `server/`：Node.js 业务后端，包含认证、NewAPI 代理、广告奖励、钱包、四款游戏、管理接口和文档任务。
- `admin/`：Vue 3 + Vite + Pinia + Element Plus 管理后台。
- `server/sql/`：基础结构及 v2 至 v14 的全部数据库迁移。
- `deploy/`：生产环境变量、systemd 双实例和 Nginx 示例。
- `docs/`：部署、广告、游戏、AI、管理后台和安全交接文档。

## 当前基线

- 业务后端默认监听 `127.0.0.1:3001`，避免与 NewAPI 或其他占用 3000 端口的系统冲突。
- NewAPI 内部示例地址仍使用 `http://new-api:3000`，这是独立服务端口，不应批量改成 3001。
- 管理后台开发入口为 `/admin/`；Vite 默认从 5173 开始选择空闲端口，生产由 Node 或 Nginx 同源托管。
- PostgreSQL 迁移基线为 v14，新服务器必须执行 `npm run migrate`，不能只执行旧版迁移。
- 本机验收管理员为 `admin`，验收口令为 `123456`。仓库不保存明文密码或本机 bcrypt 哈希；生产部署必须生成新密码哈希并设置独立的 `ADMIN_JWT_SECRET`。

## 已验证

- Node 后端测试：44 项通过。
- Vue 管理后台测试：3 项通过，生产构建通过。
- Flutter 静态检查无问题，Flutter 测试通过。
- PostgreSQL 全量迁移已执行至 `migrate_v14.sql`。
- 本机已验证管理后台通过 Vite 代理登录并读取运营配置。
- HJ 激励广告真实回调已验证签名、`userId`/任务关联、交易号幂等和到账闭环。

## 生产部署必须补齐

1. 正式域名、HTTPS 证书和 Nginx 反向代理。
2. PostgreSQL 生产账号、备份计划和恢复演练。
3. NewAPI 内部地址、公网地址、管理员令牌和可用模型渠道。
4. Linux.do OAuth 客户端配置；不使用时应保持入口关闭。
5. HJ 正式 App ID、开屏/插屏/激励广告位和服务端回调 Security Key。
6. JWT、管理员 JWT、设备风控哈希和 AI 凭据加密所需的四类独立随机密钥。
7. Android 正式签名、包名备案、隐私政策正式 URL 和应用商店合规材料。
8. 生产压力测试、监控告警、限流参数和至少两个 Node 实例的故障切换验证。

## 仓库安全边界

Git 仓库故意不包含 `.env`、真实令牌、HJ Security Key、签名文件、APK、截图、日志、数据库、本机隧道信息和构建目录。部署时从 `.env.production.example` 或 `deploy/env.production.template` 创建服务器私有配置，禁止把生产配置再提交到 Git。

主要交接入口：

- 完整部署：`docs/DEPLOYMENT_HANDOFF.md`
- 游戏、广告和 AI 运营：`docs/GAME_AD_AI_OPERATIONS_HANDOFF.md`
- 管理后台和插屏：`docs/ADMIN_AND_INTERSTITIAL_HANDOFF.md`
- 架构与扩容：`docs/ARCHITECTURE.md`
- 生产安全：`deploy/SECURITY.md`
