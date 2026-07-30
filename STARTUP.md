# 启动指南（STARTUP.md）

> 本文档面向 **AI 助手 / 自动化工具**，也适用于人工操作。所有路径、端口、坑点均为本机（Windows 11，远程桌面环境）实测结论，直接照做即可，不要凭通用经验替换命令。

## 0. TL;DR

```bash
# Git Bash 中直接执行（AI 建议后台运行，全程最长约 5 分钟，等模拟器开机）
D:/new-api-app/start-dev.bat            # 启动全部 + 安装现有 debug APK
D:/new-api-app/start-dev.bat build      # 改过 App 代码时用：先 flutter build 再安装
D:/new-api-app/start-dev.bat nodeploy   # 只起服务和模拟器，不装 App
D:/new-api-app/stop-dev.bat             # 一键全部停止
```

脚本是幂等的：重复执行会跳过已在运行的组件，只补齐缺的部分。**模拟器重启后必须重跑一次**（第 5 步的 adb 配置在模拟器重启后会丢失）。

## 1. 项目构成

| 组件 | 位置 | 技术栈 | 端口/入口 |
|---|---|---|---|
| 后端 API | `D:\new-api-app\server` | Node ≥18 + Express + pg | `http://localhost:3001`，健康检查 `GET /healthz` |
| 数据库 | `server/scripts/dev-db.js`（内嵌 PostgreSQL，数据在 `server/.pgdata`） | embedded-postgres | `postgres://postgres:postgres@localhost:5433/linuxdo_ad_reward` |
| App | `D:\new-api-app\app` | Flutter 3.44.6 | 包名 `com.gongyiapp.gongyi_app`，入口 `.MainActivity` |
| 需求文档 | `D:\new-api-app\docs\_extracted.txt` | — | PRD 验收标准在 §8 |

- 后端配置在 `server/.env`（已配好，含 Linux.do OAuth 凭据，勿覆盖）。
- App 的后端地址在 `app/lib/config.dart`：默认 `http://10.0.2.2:3001`（模拟器内访问宿主机的固定 IP），可用 `--dart-define=API_BASE_URL=...` 覆盖。
- `dev-db.js` 每次启动会自动建库并幂等执行 `sql/schema.sql` + `sql/migrate_v2.sql`，无需手动迁移。

## 2. 本机环境常量（勿猜测，直接使用）

| 项 | 值 |
|---|---|
| Flutter SDK | `D:\dev\flutter`（已在 PATH） |
| Android SDK | `D:\dev\android-sdk`（adb/emulator 已在 PATH） |
| JDK 17 | `D:\dev\jdk-17.0.19+10`（JAVA_HOME 已设） |
| 模拟器 AVD | `dev_phone`（Pixel 7 / Android 15，AEHD 加速） |
| 本机代理 | Clash，`http://127.0.0.1:7897`（环境变量 HTTP_PROXY/HTTPS_PROXY 全局已设） |
| 模拟器视角的宿主机 | `10.0.2.2`（后端即 `10.0.2.2:3001`，Clash 即 `10.0.2.2:7897`） |

## 3. 三条铁律（违反必然失败，均已踩坑验证）

1. **后端必须带代理变量启动**：`NODE_USE_ENV_PROXY=1 NO_PROXY=localhost,127.0.0.1`。Node 的 fetch 默认不读代理环境变量，缺了它访问 `connect.linux.do` 超时（UND_ERR_CONNECT_TIMEOUT），OAuth 换 token 必失败、授权码作废报 invalid_request。
2. **模拟器必须在清空代理环境变量后启动**（bash 用 `env -u`，cmd 用 `set HTTP_PROXY=`）。QEMU 会把代理变量应用到整个虚拟机，导致 App 连不上 `10.0.2.2:3001`。远程桌面下还必须加 `-gpu swiftshader_indirect` 软渲染，否则黑屏。
3. **模拟器每次开机后必须重做两条 adb 配置**（start-dev.bat 第 5 步自动做）：
   ```bash
   adb shell settings put global http_proxy 10.0.2.2:7897   # 模拟器内浏览器走 Clash，才能打开 linux.do 授权页
   adb reverse tcp:3001 tcp:3001                             # OAuth 回调的 localhost:3001 在模拟器内可达
   ```
   注：浏览器认这个全局代理而 Dart/dio 不认，所以它不影响 App 直连 10.0.2.2 后端，互不干扰。

## 4. AI 专用注意事项

- **不要用交互式 `flutter run`**——无 TTY 会崩。改代码后的部署方式固定为：
  ```bash
  cd D:/new-api-app/app && flutter build apk --debug \
    && adb install -r build/app/outputs/flutter-apk/app-debug.apk \
    && adb shell am start -n com.gongyiapp.gongyi_app/.MainActivity
  ```
  等价于 `D:/new-api-app/start-dev.bat build`。
- **后端改代码不用重启**：server 用 `node --watch` 起的，保存即自动重载。
- 长时间运行的进程（dev-db / server / 模拟器）如果不走 start-dev.bat 而手动起，必须用后台方式运行（Claude Code 的 `run_in_background`），否则会阻塞会话。
- start-dev.bat 会阻塞到模拟器开机完成（最长 5 分钟），AI 调用时设长超时或后台运行后轮询输出。
- 看 App 日志：`adb logcat -s flutter`；截屏验证 UI：`adb exec-out screencap -p > /tmp/screen.png` 然后用 Read 工具看图。
- 端到端冒烟脚本：`cd D:/new-api-app/server && node scripts/test-v2-flow.js`（测 v2 登录/token 流程，需 DB + server 已起）。

## 5. 手动分步启动（不用脚本时的等价 bash 命令）

按顺序执行，①②③是长驻进程需后台运行：

```bash
# ① 数据库（5433）
cd D:/new-api-app/server && node scripts/dev-db.js

# ② 后端（3001）—— 三条铁律之一，代理变量不可省
cd D:/new-api-app/server && NODE_USE_ENV_PROXY=1 NO_PROXY=localhost,127.0.0.1 npm run dev

# ③ 模拟器 —— 必须清代理变量 + 软渲染
env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
  D:/dev/android-sdk/emulator/emulator.exe -avd dev_phone -gpu swiftshader_indirect

# ④ 等开机完成（sys.boot_completed 输出 1）
adb wait-for-device && adb shell getprop sys.boot_completed

# ⑤ 模拟器网络配置（每次模拟器重启后重做）
adb shell settings put global http_proxy 10.0.2.2:7897
adb reverse tcp:3001 tcp:3001

# ⑥ 装 App 并启动
adb install -r D:/new-api-app/app/build/app/outputs/flutter-apk/app-debug.apk
adb shell am start -n com.gongyiapp.gongyi_app/.MainActivity
```

## 6. 启动后的验证清单

| 检查 | 命令 | 期望 |
|---|---|---|
| 后端存活 | `curl --noproxy '*' -s http://127.0.0.1:3001/healthz` | `{"ok":true}` |
| 数据库端口 | `netstat -ano \| grep 5433 \| grep LISTEN` | 有输出 |
| 模拟器在线 | `adb devices` | `emulator-5554  device` |
| 回调通道 | `adb reverse --list` | 含 `tcp:3001` |
| 浏览器代理 | `adb shell settings get global http_proxy` | `10.0.2.2:7897` |
| App 在跑 | `adb shell pidof com.gongyiapp.gongyi_app` | 输出 PID |

全链路人工验证：App 打开 → 「使用 Linux.do 登录」→ 模拟器内浏览器能打开 linux.do 授权页 → 授权后回 App 进首页显示额度卡片。

## 7. 故障排查（按症状查）

| 症状 | 原因 | 处理 |
|---|---|---|
| 登录时后端日志 UND_ERR_CONNECT_TIMEOUT / invalid_request | 后端没带 `NODE_USE_ENV_PROXY=1` 启动 | 关掉 server 窗口，重跑 start-dev.bat |
| App 报网络异常、连不上后端 | 模拟器启动时没清代理变量；或 `adb reverse` 丢了 | 重跑 start-dev.bat（会自动补第 5 步）；仍不行则关模拟器重跑 |
| 模拟器内浏览器打不开 linux.do | 全局 http_proxy 没设（模拟器重启后丢失） | 重做第 5 步两条命令 |
| 模拟器黑屏/不出画面 | 远程桌面下用了硬件 GPU | 必须带 `-gpu swiftshader_indirect` 启动 |
| 端口被占报错 | 上次进程没退干净 | 跑 `stop-dev.bat` 再 `start-dev.bat` |
| 数据库起不来且 dev-db 窗口报锁/pid 错误 | 上次被强杀留了残留 | 删 `server/.pgdata/postmaster.pid` 后重试；数据仍在 |
| flutter build 卡在 Gradle 下载 | 代理/镜像配置在 `C:\Users\18744\.gradle\gradle.properties`，勿动 | 网络恢复后重试即可 |
| 模拟器里无法用电脑键盘打字 | AVD 配置 | `config.ini` 需 `hw.keyboard = yes`（已配） |

## 8. 停止

```bash
D:/new-api-app/stop-dev.bat
```

先 `adb emu kill` 优雅关模拟器，再关 api-server / dev-db 窗口，最后兜底清理 3001/5433 端口残留进程。数据库数据（`server/.pgdata`）不会丢。
