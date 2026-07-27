import 'dotenv/config';

function required(name, fallback) {
  const v = process.env[name] ?? fallback;
  if (v === undefined || v === '') {
    console.warn(`[config] 环境变量 ${name} 未设置`);
  }
  return v;
}

export const config = {
  port: Number(process.env.PORT || 3000),
  baseUrl: process.env.BASE_URL || 'http://localhost:3000',

  databaseUrl: required('DATABASE_URL', 'postgres://postgres:postgres@localhost:5432/linuxdo_ad_reward'),

  jwt: {
    secret: required('JWT_SECRET', 'dev-secret-do-not-use-in-prod'),
    expiresIn: process.env.JWT_EXPIRES_IN || '7d',
  },

  // LinuxDo Connect OAuth2（https://connect.linux.do）
  linuxdo: {
    clientId: process.env.LINUXDO_CLIENT_ID || '',
    clientSecret: process.env.LINUXDO_CLIENT_SECRET || '',
    redirectUri: process.env.LINUXDO_REDIRECT_URI || '',
    // v2 登录流回调（方案 §6.3），需同步登记到 Linux.do 应用设置
    redirectUriV2:
      process.env.LINUXDO_REDIRECT_URI_V2 ||
      `${process.env.BASE_URL || 'http://localhost:3000'}/api/v1/auth/linuxdo/callback`,
    // 官方端点，注意用户信息端点是 /api/user 而不是 /oauth2/userinfo
    authorizeUrl: 'https://connect.linux.do/oauth2/authorize',
    tokenUrl: 'https://connect.linux.do/oauth2/token',
    userInfoUrl: 'https://connect.linux.do/api/user',
    minTrustLevel: Number(process.env.LINUXDO_MIN_TRUST_LEVEL || 0),
  },

  // v2 登录体系（方案 §7）
  auth: {
    accessTokenTtlSec: Number(process.env.ACCESS_TOKEN_TTL_SEC || 900), // 15 分钟
    refreshTokenTtlDays: Number(process.env.REFRESH_TOKEN_TTL_DAYS || 30),
    loginSessionTtlMin: Number(process.env.LOGIN_SESSION_TTL_MIN || 10),
    loginCodeTtlSec: Number(process.env.LOGIN_CODE_TTL_SEC || 240), // 3-5 分钟取 4 分钟
    allowPasswordRegister: process.env.ALLOW_PASSWORD_REGISTER === 'true', // §16：停止新增密码注册
  },

  // 平台回跳（方案 §6）。Android 未配置 App Link 时回调返回 JSON（本地开发模式）
  appLinks: {
    android: process.env.APP_LINK_ANDROID || '',
    iosScheme: process.env.APP_LINK_IOS_SCHEME || 'gongyiapp',
  },

  // API 中转站（方案 §8）。mock = 本地模拟；newapi = new-api 管理 API 适配；http = 自研内部 API
  station: {
    mode: process.env.STATION_MODE || 'mock',
    baseUrl: (process.env.STATION_BASE_URL || '').replace(/\/$/, ''),
    apiKey: process.env.STATION_API_KEY || '',
    // newapi 模式：管理员 access_token 与其用户 ID
    adminToken: process.env.STATION_ADMIN_TOKEN || '',
    adminUserId: process.env.STATION_ADMIN_ID || '1',
    // 1 元人民币 = 多少 new-api quota（默认 70000 ≈ $0.14，按 500000 quota/$ 与 7.2 汇率）
    quotaPerCny: Number(process.env.STATION_QUOTA_PER_CNY || 70000),
    // new-api 的 quota/美元 显示比例（QuotaPerUnit，默认 500000 = $1）
    quotaPerUsd: Number(process.env.STATION_QUOTA_PER_USD || 500000),
    timeoutMs: Number(process.env.STATION_TIMEOUT_MS || 8000),
  },

  ad: {
    callbackSecret: process.env.AD_CALLBACK_SECRET || '',
    dailyMax: Number(process.env.AD_DAILY_MAX || 6),
    rewardAmount: process.env.AD_REWARD_AMOUNT || '0.100000',
    // 微单位金额（1 元 = 1,000,000），优先于 AD_REWARD_AMOUNT
    rewardMicrounits: Number(
      process.env.AD_REWARD_MICROUNITS ||
        Math.round(Number(process.env.AD_REWARD_AMOUNT || '0.1') * 1000000)
    ),
    taskExpireMinutes: Number(process.env.AD_TASK_EXPIRE_MINUTES || 10),
    // 开发用模拟广告完成接口开关（生产必须关闭）
    devSimulate: process.env.AD_DEV_SIMULATE === 'true',
    // ===== 广告位配置（下发给 App，接真实 SDK 后改环境变量即可，无需发版）=====
    provider: process.env.AD_PROVIDER || 'mock', // mock | hj | pangle | ylh | admob ...
    // HJ 聚合 SDK 的 App Id（provider=hj 时必填）
    hjAppId: process.env.AD_HJ_APP_ID || '',
    splashEnabled: process.env.AD_SPLASH_ENABLED === 'true',
    rewardedEnabled: process.env.AD_REWARDED_ENABLED !== 'false',
    // 小游戏补救广告独立开关：只影响游戏内复活/续时等本局功能，与钱包无关
    gameRewardedEnabled: process.env.AD_GAME_REWARDED_ENABLED !== 'false',
    interstitialEnabled: process.env.AD_INTERSTITIAL_ENABLED === 'true',
    unitSplash: process.env.AD_UNIT_SPLASH || 'splash_001',
    // 首页余额广告位（走 task_token + 服务端回调发奖，计入每日次数）
    unitRewardedHome:
      process.env.AD_UNIT_REWARDED_HOME || process.env.AD_UNIT_REWARDED || 'reward_video_001',
    // 小游戏补救广告位（绝不进钱包发奖逻辑，只回传本局结果）
    unitRewardedGame: process.env.AD_UNIT_REWARDED_GAME || 'reward_game_001',
    unitInterstitial: process.env.AD_UNIT_INTERSTITIAL || 'interstitial_001',
    // ===== 频控（秒/次，随 ad-config 下发，调整无需发版）=====
    interstitialCooldownSec: Number(process.env.AD_INTERSTITIAL_COOLDOWN_SEC || 180),
    interstitialDailyMax: Number(process.env.AD_INTERSTITIAL_DAILY_MAX || 0), // 0 = 不限
    splashMinIntervalSec: Number(process.env.AD_SPLASH_MIN_INTERVAL_SEC || 300), // 热启动最小间隔
  },
};
