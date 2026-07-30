# 生产网络与密钥边界

## 公网入口

- App 业务后台只开放 HTTPS 443，Node 服务监听 `127.0.0.1:3001`。
- New API 可使用独立的公开 API 域名供用户调用，但管理接口必须由 New API 自身鉴权和限流。
- New API 的上游中转端口、PostgreSQL、Redis和Node内部端口不得对公网开放。
- `STATION_ADMIN_TOKEN` 只存在 `/etc/gongyi-app.env`，权限设置为 `0600`，不能写进App、网页或日志。

## 防火墙验收

上线前从外网扫描服务器。除 80/443 和经批准的运维入口外，不应看到：

- Node 内部端口（默认3001）
- New API内部管理/容器端口
- 上游中转站端口
- PostgreSQL、Redis及调试端口

## 广告奖励

- 生产必须关闭 `AD_DEV_SIMULATE`。
- App播放完成事件不能加额度，只有广告平台服务器回调可以入账。
- 接入真实平台时必须替换/核对该平台的签名验证规则，不能把通用HMAC示例当成所有平台的正式协议。
- 设备安装标识只能作为限额信号；正式防设备农场还需接入 Play Integrity、App Attest 或发布渠道提供的等价能力。

## AI代理

- App只知道业务域名，不下发 `AI_UPSTREAM_BASE_URL` 或 `STATION_BASE_URL`。
- 用户New API Key按登录账号隔离，只保存在手机安全存储，每次请求临时透传，服务端不得记录完整Key。
- Nginx必须关闭AI流式响应缓冲；Node并发由数据库租约控制，不能无限创建任务。
- 不允许客户端提交任意上游Base URL给Node代理；需要增加外部中转站时只能使用服务端白名单，防止SSRF访问内网。
- `AI_SHARED_API_KEY`只适合限量试用。正式的广告额度闭环应要求用户使用自己的本站Key，否则无法按New API用户账本准确扣费。

## 多副本与故障隔离

- 生产至少运行两个Node副本并放在同一Nginx upstream中；副本使用不同端口、共享PostgreSQL。
- AI并发租约和广告限额都在PostgreSQL中，多副本不能改回单进程内存计数。
- 每个副本设置独立内存上限。单副本被系统重启时，Nginx应把新请求转给健康副本。
- New API、PostgreSQL和广告回调仍需独立监控；Node多副本不能消除这些依赖的单点故障。

仓库提供 `gongyi-app@.service` 与双副本Nginx示例。部署后启用 `gongyi-app@3001`、`gongyi-app@3002`，并确认两个 `/readyz` 都通过后再切流量。
