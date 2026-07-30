import express from 'express';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { config, validateProductionConfig } from './config.js';
import { pool } from './db.js';
import authRouter from './routes/auth.js';
import authV2Router from './routes/authLinuxdoV2.js';
import linuxdoRouter from './routes/linuxdo.js';
import { adTaskRouter, adCallbackRouter } from './routes/adTask.js';
import walletRouter from './routes/wallet.js';
import appVersionRouter from './routes/appVersion.js';
import platformRouter from './routes/platform.js';
import aiRouter from './routes/ai.js';
import gamesRouter from './routes/games.js';
import adminRouter from './routes/admin.js';
import webAdsRouter from './routes/webAds.js';
import { startDocumentWorkers, stopDocumentWorkers } from './services/documentJobs.js';
import { expireMinePackets } from './services/gameEngine.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const app = express();
app.disable('x-powered-by');
// 部署在 nginx/caddy 反代之后：信任一层代理，req.ip 才能拿到真实客户端 IP
// （审计日志 auth_audit_logs.ip_address 依赖它），否则全是 127.0.0.1。
app.set('trust proxy', config.trustProxy);
app.use(express.json({ limit: config.jsonLimit }));
app.use((req, res, next) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Referrer-Policy', 'no-referrer');
  res.setHeader('Permissions-Policy', 'camera=(), microphone=(), geolocation=()');
  next();
});

// 防呆：dev-complete 是免广告发奖路径，真实 provider 下误开即可自助刷奖。
// 直接拒绝启动，把配置错误挡在部署阶段。
if (config.ad.devSimulate && config.ad.provider !== 'mock') {
  console.error(
    `[fatal] AD_DEV_SIMULATE=true 与 AD_PROVIDER=${config.ad.provider} 不能同时开启：` +
      'dev-complete 会绕过真实广告直接发奖。生产请移除 AD_DEV_SIMULATE。'
  );
  process.exit(1);
}
validateProductionConfig();

app.get('/healthz', (req, res) => res.json({ ok: true }));

// 广告 SDK 初始化前展示的公开隐私政策。页面不加载第三方资源，便于
// Android WebView 与广告平台审核在同一 HTTPS 域名下访问。
app.use('/privacy', (req, res, next) => {
  res.setHeader(
    'Content-Security-Policy',
    "default-src 'none'; style-src 'unsafe-inline'; img-src 'self'; " +
      "frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'"
  );
  next();
});
app.use('/privacy', express.static(path.join(__dirname, '..', 'public', 'privacy')));

// 本站小游戏静态托管（生产可放同源CDN，这里便于本地联调与在线更新）
app.use('/games', (req, res, next) => {
  res.setHeader(
    'Content-Security-Policy',
    "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; " +
      "img-src 'self' data:; connect-src 'none'; frame-src 'none'; " +
      "object-src 'none'; base-uri 'none'; form-action 'none'"
  );
  next();
});
app.use('/games', express.static(path.join(__dirname, '..', 'public', 'games')));

// 小游戏页错误上报（联调用）：WebView 里看不到 JS console，把加载错误落到
// 本地文件便于排查。只追加、不解析、限长，无安全暴露面。
if (config.gameClientLogEnabled) {
  app.post('/games/client-log', express.text({ type: '*/*', limit: '16kb' }), (req, res) => {
    const line = `[${new Date().toISOString()}] ${String(req.body).slice(0, 4000)}\n`;
    fs.appendFile(path.join(__dirname, '..', 'games-client.log'), line, () => {});
    res.json({ ok: true });
  });
}

app.get('/readyz', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ ok: true });
  } catch {
    res.status(503).json({ ok: false });
  }
});

// v2：Linux.do 唯一身份登录（方案 §7），迁移完成后旧 /api/auth 下线
app.use('/api/v1/auth', authV2Router);

app.use('/api/auth', authRouter);
app.use('/api/linuxdo', linuxdoRouter);
app.use('/api/ad-task', adTaskRouter);
app.use('/api/ad-callback', adCallbackRouter); // 广告平台服务端回调，不走用户鉴权
app.use('/api/wallet', walletRouter);
app.use('/api/app', appVersionRouter);
app.use('/api/platform', platformRouter);
app.use('/api/ai', aiRouter);
app.use('/api/games', gamesRouter);
app.use('/api', webAdsRouter);
app.use('/api/admin', adminRouter);

// 管理端生产构建由同一服务托管；开发时由 Vite 代理 /api。
const adminDist = path.join(__dirname, '..', '..', 'admin', 'dist');
if (fs.existsSync(adminDist)) {
  app.use('/admin', express.static(adminDist, { index: false, maxAge: '1h' }));
  app.get(['/admin', '/admin/*'], (req, res) => {
    res.setHeader('Cache-Control', 'no-store');
    res.sendFile(path.join(adminDist, 'index.html'));
  });
}

// /api/me 便捷别名
app.get('/api/me', (req, res) => res.redirect(307, '/api/auth/me'));

app.use((req, res) => {
  res.status(404).json({ code: 404, message: '接口不存在' });
});

// 统一错误处理
app.use((err, req, res, next) => {
  console.error('[error]', err);
  if (res.headersSent) return next(err);
  const status = Number(err.status) || (err.name === 'AbortError' ? 504 : 500);
  res.status(status).json({
    code: err.code || status,
    message: status >= 500 ? (status === 504 ? '上游请求超时' : '服务器内部错误') : err.message,
  });
});

let gameMaintenanceTimer;
let gameMaintenanceRunning = false;

function startGameMaintenance() {
  const settleExpiredPackets = async () => {
    if (gameMaintenanceRunning) return;
    gameMaintenanceRunning = true;
    try {
      await expireMinePackets();
    } catch (err) {
      console.error('[game-maintenance] 扫雷红包过期清算失败', err);
    } finally {
      gameMaintenanceRunning = false;
    }
  };
  settleExpiredPackets();
  gameMaintenanceTimer = setInterval(settleExpiredPackets, 60_000);
  gameMaintenanceTimer.unref();
}

const server = app.listen(config.port, config.host, () => {
  console.log(`linuxdo-ad-reward-server 已启动: http://${config.host}:${config.port}`);
  startDocumentWorkers();
  startGameMaintenance();
});

async function shutdown(signal) {
  console.log(`[shutdown] 收到 ${signal}，停止接收新请求`);
  if (gameMaintenanceTimer) clearInterval(gameMaintenanceTimer);
  server.close(async () => {
    await stopDocumentWorkers().catch(() => {});
    await pool.end().catch(() => {});
    process.exit(0);
  });
  setTimeout(() => process.exit(1), 15000).unref();
}

process.once('SIGTERM', () => shutdown('SIGTERM'));
process.once('SIGINT', () => shutdown('SIGINT'));
