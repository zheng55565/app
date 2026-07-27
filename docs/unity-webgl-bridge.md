# Unity WebGL ⇆ Flutter App 桥接与广告接入说明

> 面向后续做 Unity 侧接入的开发者/AI。Flutter 侧、服务端、广告插件已全部就绪，
> 本文档说明 Unity 项目（`D:\new-api-app\huanyouyu\HuanYouYu-main`）要做什么。

## 架构

```
Unity WebGL 构建（在线托管，可热更新）
  ↕ jslib（Assets/Plugins/WebGL/GongyiAppBridge.jslib，已提供）
window.GongyiBridge（Flutter WebView 注入的 JavaScriptChannel）
  ↕
Flutter GamePage（app/lib/pages/game_page.dart）
  ↕
AdService.showGameRecoveryRewarded（rewarded_game 广告位）
  ↕
flutter_ads_plugin → HJ 聚合 SDK → 各广告渠道
```

广告展示在 Flutter Activity 上（原生全屏），Unity 侧只收结果。

## 两类广告的隔离铁律（违者即资损事故）

| | 首页余额广告 | 小游戏补救广告 |
|---|---|---|
| purpose | home_balance | game_recovery |
| 广告位 | rewarded_home（AD_UNIT_REWARDED_HOME） | rewarded_game（AD_UNIT_REWARDED_GAME） |
| 服务端任务 | POST /api/ad-task/start 签发 task_token | **绝不建任务** |
| 发奖 | 广告平台服务端回调 → 后端校验 → 钱包入账 | **只回传本局结果，永不进钱包** |
| 每日次数 | 计入 | 不计入 |
| 代码入口 | AdService.showBalanceRewarded | AdService.showGameRecoveryRewarded |

服务端已双保险：回调发奖时校验 `ad_tasks.ad_unit_id === AD_UNIT_REWARDED_HOME`，
rewarded_game 的回调即使伪造 task_token 也过不了广告位校验。

## 通信协议

Unity → Flutter（`window.GongyiBridge.postMessage(json)`）：

```json
{"type":"game_reward_request","requestId":"req_1710000000_123456","gameId":"snake","recoveryType":"revive"}
{"type":"game_exit"}
```

Flutter → Unity（`window.onGongyiMessage(json)` → SendMessage 到注册的 GameObject）：

```json
{"type":"game_reward_result","requestId":"原样返回","result":"earned|dismissed|failed","transId":"广告交易ID"}
```

- `requestId` 每次请求唯一（时间戳+随机数），**两端各自去重、只消费一次**：
  Flutter 侧 GamePage + AdService 双重去重；Unity 侧 GongyiAppBridge.cs 的
  `_pending/_consumed` 去重。重复/迟到/未知回执一律丢弃。
- `result` 只有 `earned` 允许修改本局状态；`dismissed`（提前关闭）与
  `failed`（加载失败/无库存/广告被远程关闭）只恢复 UI。

## Unity 侧已提供的文件

- `Assets/Plugins/WebGL/GongyiAppBridge.jslib` — JS 桥（WebGL 构建自动链接）
- `Assets/Common/Scripts/GongyiAppBridge.cs` — C# 单例，用法见文件头注释

## Unity 侧待做清单

1. **切换构建目标到标准 WebGL**：项目当前面向微信小游戏（含 WX-WASM-SDK-V2）。
   标准 WebGL 构建时不要包含 WX SDK 相关代码路径（用 `#if !WECHAT` 或
   直接在 Hall 配置里禁用）。WebGL 模板需把 unityInstance 暴露为
   `window.unityInstance`（默认模板的 createUnityInstance().then(inst => ...) 里加一行）。
2. **场景挂桥**：大厅场景加常驻 GameObject `GongyiAppBridge`，挂上同名脚本。
3. **试点 3 个游戏接补救广告**（贪吃蛇 / 俄罗斯方块 / 跳一跳）：
   - 贪吃蛇（gameId=snake, recoveryType=revive）：死亡后从最后安全位置复活一次
   - 俄罗斯方块（gameId=tetris, recoveryType=clear_top）：无路可走时清除顶部若干行
   - 跳一跳（gameId=jumpjump, recoveryType=revive）：死亡后从最后平台复活一次
4. **产品规则（每个接入的游戏都要遵守）**：
   - 绝不自动弹广告，必须玩家主动点击；按钮文案明确（“看视频，继续本局”）
   - 必须保留“重新开始”和“返回大厅”
   - 每关最多一次（长局最多两次）——游戏侧自行计数
   - 刚开局或无有效进度时不提供补救入口
   - `IsInApp == false`（浏览器直开/微信内）时隐藏补救按钮
   - AI星露谷第一版不接广告
5. **构建产物部署**：WebGL 构建输出整个目录放到
   `D:\new-api-app\server\public\games\`（替换现有测试页 index.html），
   App 内即可访问；生产改放 CDN，并用 `--dart-define=GAME_URL=https://...`
   重定 App 的游戏地址（无需改代码）。

## 联调方式

1. `D:\new-api-app\start-dev.bat`（见 STARTUP.md）拉起全套环境；
2. App 首页 → 点“小游戏”卡片 → WebView 加载 `http://10.0.2.2:3000/games/`；
3. 构建产物部署前，现有测试页可先验证桥接：点“看视频复活”按钮 →
   App 弹出 mock 激励视频 → 看完/关闭 → 测试页日志显示 earned/dismissed；
4. 验证隔离：整个流程中后端日志不得出现 `/api/ad-task/start`（可
   `grep "ad-task/start"` server 窗口输出），首页“今日已观看 x/6”不得变化。

## 广告配置（服务端环境变量）

```
AD_PROVIDER=hj                      # 接真实 SDK 时改 hj；默认 mock
AD_HJ_APP_ID=<HJ 平台申请的 AppId>
AD_UNIT_REWARDED_HOME=<首页广告位ID>
AD_UNIT_REWARDED_GAME=<小游戏广告位ID>
AD_GAME_REWARDED_ENABLED=true       # 小游戏广告独立总闸（远程可关）
```

注意：`AD_PROVIDER=hj` 且 unit_id 仍为占位值时，服务端会强制下发
enabled=false 并打告警日志（防呆）。App 侧真实 SDK 在用户同意隐私政策
（`AdService.grantConsent()`）之前不会初始化，未同意时广告一律 disabled。
