import express from 'express';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { config } from './config.js';
import authRouter from './routes/auth.js';
import authV2Router from './routes/authLinuxdoV2.js';
import linuxdoRouter from './routes/linuxdo.js';
import { adTaskRouter, adCallbackRouter } from './routes/adTask.js';
import walletRouter from './routes/wallet.js';
import appVersionRouter from './routes/appVersion.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const app = express();
// 部署在 nginx/caddy 反代之后：信任一层代理，req.ip 才能拿到真实客户端 IP
// （审计日志 auth_audit_logs.ip_address 依赖它），否则全是 127.0.0.1。
app.set('trust proxy', 1);
app.use(express.json());

// 防呆：dev-complete 是免广告发奖路径，真实 provider 下误开即可自助刷奖。
// 直接拒绝启动，把配置错误挡在部署阶段。
if (config.ad.devSimulate && config.ad.provider !== 'mock') {
  console.error(
    `[fatal] AD_DEV_SIMULATE=true 与 AD_PROVIDER=${config.ad.provider} 不能同时开启：` +
      'dev-complete 会绕过真实广告直接发奖。生产请移除 AD_DEV_SIMULATE。'
  );
  process.exit(1);
}

app.get('/healthz', (req, res) => res.json({ ok: true }));

// Unity WebGL 小游戏静态托管（生产建议放 CDN，这里便于本地联调与在线更新）
app.use('/games', express.static(path.join(__dirname, '..', 'public', 'games')));

// 小游戏页错误上报（联调用）：WebView 里看不到 JS console，把加载错误落到
// 本地文件便于排查。只追加、不解析、限长，无安全暴露面。
app.post('/games/client-log', express.text({ type: '*/*', limit: '64kb' }), (req, res) => {
  const line = `[${new Date().toISOString()}] ${String(req.body).slice(0, 8000)}\n`;
  fs.appendFile(path.join(__dirname, '..', 'games-client.log'), line, () => {});
  res.json({ ok: true });
});

// v2：Linux.do 唯一身份登录（方案 §7），迁移完成后旧 /api/auth 下线
app.use('/api/v1/auth', authV2Router);

app.use('/api/auth', authRouter);
app.use('/api/linuxdo', linuxdoRouter);
app.use('/api/ad-task', adTaskRouter);
app.use('/api/ad-callback', adCallbackRouter); // 广告平台服务端回调，不走用户鉴权
app.use('/api/wallet', walletRouter);
app.use('/api/app', appVersionRouter);

// /api/me 便捷别名
app.get('/api/me', (req, res) => res.redirect(307, '/api/auth/me'));

app.use((req, res) => {
  res.status(404).json({ code: 404, message: '接口不存在' });
});

// 统一错误处理
app.use((err, req, res, next) => {
  console.error('[error]', err);
  res.status(500).json({ code: 500, message: '服务器内部错误' });
});

app.listen(config.port, () => {
  console.log(`linuxdo-ad-reward-server 已启动: http://localhost:${config.port}`);
});
