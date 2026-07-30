# 游戏、广告与 AI 运营后台交接

更新日期：2026-07-30

## 1. 已交付范围

管理后台位于 `/admin/`，当前包含：

- 游戏运营：四款游戏开关、石头剪刀布到账倍率、扫雷赔付与手续费、八房手续费/淘汰范围/对手参数、消消乐通关奖励与宝箱概率。
- 游戏审计：最近结算流水、投入、到账、手续费、净盈亏和配置修改日志。
- 广告运营：激励广告开关、单次奖励、账号/设备/IP 每日次数与奖励额度上限。
- 模型运营：AI 总开关和生图模型白名单。
- 用户与广告审计：用户状态、广告任务、HJ 回调、奖励订单和网页插屏埋点。

后台不提供“指定某个用户输或赢”。石头剪刀布由服务端安全随机数出拳，八房结果由开盘前种子决定并在结算记录中保存。运营只能修改公开的全局倍率、手续费和范围，所有修改都写入管理员审计日志。

## 2. 数据库升级

新服务器必须先执行 `server/sql/schema.sql`，再按数字顺序执行全部 `migrate_v*.sql`。项目脚本会自动完成该顺序：

```bash
cd server
npm ci
npm run migrate
```

本次新增：

- v11：`runtime_settings`、广告任务策略快照、扫雷和八房规则快照。
- v12：消消乐关卡规则快照。
- v13：扫雷红包发布者结算与领取者结算分离，修复发布者本人领取时的结果覆盖问题。
- v14：增加广告平台交易全局防重，修复 HJ 动态广告位导致消消乐复活回调被误拒绝的问题。

规则快照保证后台改参数后只影响新任务、新红包和新回合。已经创建的广告任务、红包、八房回合和消消乐关卡继续按创建时规则结算。

发布前必须备份 PostgreSQL。不要通过删除列或回滚迁移恢复旧版本，应使用新的向前修复迁移。

## 3. NewAPI 与模型

生产环境至少配置：

```text
STATION_MODE=newapi
STATION_BASE_URL=https://newapi-internal.example
STATION_PUBLIC_BASE_URL=https://api.example.com
STATION_ADMIN_TOKEN=<仅服务端保存>
STATION_ADMIN_ID=1
AI_ENABLED=true
AI_UPSTREAM_BASE_URL=https://newapi-internal.example
AI_ALLOW_USER_API_KEY=true
AI_CREDENTIAL_ENCRYPTION_KEY=<至少32字符的独立随机密钥>
```

`STATION_BASE_URL` 和 `AI_UPSTREAM_BASE_URL` 是服务端内部地址；`STATION_PUBLIC_BASE_URL` 是用户可以访问的 NewAPI 公网根地址，不能填写 Docker 服务名、内网地址或管理令牌。App“我的 -> 本站 API 接入”会展示 `${STATION_PUBLIC_BASE_URL}/v1` 及 cURL、Python、Node.js 调用示例。

文本模型不写死在 App。工作台和模型中心每次通过本服务读取 NewAPI `/v1/models`；只要 NewAPI 真实返回某个模型 ID，例如未来可用的 Claude Opus 型号，用户就能选择并按该原始 ID 调用，无需重新构建 App。模型是否实际可用、计费多少和上下文上限由 NewAPI 对应渠道决定。

生图同样调用 OpenAI 兼容的 `/v1/images/generations`，但必须先在后台“广告与模型”加入真实生图模型 ID 白名单，防止把文本模型误发到生图接口。

## 4. 广告奖励安全边界

激励广告到账链路：

```text
App 创建一次性任务 -> SDK 播放并传入 userId/task_token
-> App 登记 transId（仅作交叉核对，不发奖）
-> HJ 服务端签名回调
-> 后端校验签名、用户、任务、交易号、账号/设备/IP 日限额
-> PostgreSQL 幂等入账 -> NewAPI 额度订单
```

客户端的播放完成事件永远不能直接加额度。只有广告平台服务端签名回调可以把任务改成 `rewarded`。`task_token`、平台 `transId`、钱包流水和奖励订单均有幂等约束，重复回调不会重复入账；同一个平台 `transId` 也不能跨“额度奖励”和“游戏复活”重复使用。

后台所有次数和额度上限必须是正整数；每日奖励额度必须不小于单次奖励。服务端会再次校验，脚本绕过前端也无法保存非法配置。配置变更只影响新创建的广告任务；同一自然日已使用的较低上限不会因临时调高配置而被绕过。

## 5. 游戏结算口径

- 石头剪刀布：用户选拳、服务端对手随机出拳；平局退回本金；后台配置的是赢家总到账倍率，不把净盈利误记为手续费。
- 扫雷红包：同一账号和同一安装设备每个红包只能领取一次；发布者本人可以领取；发布者结算和领取者结果使用独立身份记录，不会互相覆盖；中雷赔付与手续费使用红包创建时快照；7 天未领完的剩余红包退回发布者。
- 八房生存：每次只能追加 1/10/50 积分，可多次累计；前 20 秒可换房，最后 5 秒封盘；失败池扣手续费后，按全部幸存投入（含服务端对手）占比分配利润并返还幸存者本金。
- 消消乐：每关只能首次通关奖励一次；关卡奖励和第 10 关宝箱概率按开局规则快照；宝箱每个里程碑只能打开一次；复活只能由独立的广告签名回调确认。

所有钱包扣减、领取、结算和奖励使用 PostgreSQL 事务、行锁、唯一索引及请求幂等号。App 传来的胜负、金额或余额不作为结算依据。

## 6. 构建与发布

```bash
# 服务端
cd server
npm ci
npm run migrate
npm test
npm start

# 管理后台
cd ../admin
npm ci
npm test
NODE_OPTIONS=--max-old-space-size=1024 npm run build

# Flutter
cd ../app
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

Windows 的管理员账户不能启动项目使用的嵌入式 PostgreSQL 迁移测试；这时应对独立测试库或 Docker PostgreSQL 执行 `npm run migrate`。Linux CI 建议继续执行 `npm run test:migrations`。

生产发布顺序：备份数据库 -> 迁移 -> 发布 Node -> 构建并发布 `admin/dist` -> 健康检查 -> 小流量验证 -> 发布 APK。

## 7. 上线验收

1. 管理员登录后能打开“游戏运营”和“广告与模型”，非法概率或反向范围保存时返回 400。
2. 修改一个无风险参数后，`admin_audit_logs` 出现对应记录；旧回合快照不变化。
3. 同一广告任务重复回调只入账一次；伪造客户端完成接口不能加额度。
4. 同一账号或设备重复拆同一红包返回 409；八房重复请求不会重复扣分。
5. 工作台能列出 NewAPI 文本模型；生图页只列出后台白名单与 NewAPI 返回列表的交集。
6. “我的 -> 本站 API 接入”只显示公网 `/v1` 地址和占位 Key，不泄露管理令牌、共享 Key或内部地址。
7. `/healthz`、`/readyz`、`/admin/`、`/api/platform/config`、`/api/app/ad-config` 均通过 HTTPS 访问。

真实密钥、管理员密码、HJ Security Key 和 NewAPI 管理令牌只放服务器密钥系统或未提交的 `.env`，不得写入 Git、APK、截图或交接文档。
