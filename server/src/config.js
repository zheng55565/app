import 'dotenv/config';

function required(name, fallback) {
  const v = process.env[name] ?? fallback;
  if (v === undefined || v === '') {
    console.warn(`[config] 环境变量 ${name} 未设置`);
  }
  return v;
}

export const config = {
  env: process.env.NODE_ENV || 'development',
  host: process.env.HOST || '127.0.0.1',
  port: Number(process.env.PORT || 3001),
  baseUrl: process.env.BASE_URL || 'http://localhost:3001',
  trustProxy: Number(process.env.TRUST_PROXY_HOPS || 0),
  jsonLimit: process.env.JSON_BODY_LIMIT || '2mb',
  appName: process.env.APP_NAME || 'AI 公益工作台',
  gameClientLogEnabled:
    process.env.GAME_CLIENT_LOG_ENABLED === 'true' || process.env.NODE_ENV !== 'production',

  databaseUrl: required('DATABASE_URL', 'postgres://postgres:postgres@localhost:5432/linuxdo_ad_reward'),
  database: {
    poolMax: Number(process.env.DB_POOL_MAX || 20),
    idleTimeoutMs: Number(process.env.DB_IDLE_TIMEOUT_MS || 30000),
    connectionTimeoutMs: Number(process.env.DB_CONNECTION_TIMEOUT_MS || 5000),
    timezone: process.env.DB_TIMEZONE || 'Asia/Shanghai',
  },

  jwt: {
    secret: required('JWT_SECRET', 'dev-secret-do-not-use-in-prod'),
    expiresIn: process.env.JWT_EXPIRES_IN || '7d',
  },

  // 管理后台使用独立身份和 JWT 域，不能复用 App 用户令牌。
  admin: {
    enabled: process.env.ADMIN_AUTH_ENABLED === 'true',
    username: process.env.ADMIN_USERNAME || '',
    passwordHash: process.env.ADMIN_PASSWORD_HASH || '',
    jwtSecret: process.env.ADMIN_JWT_SECRET || '',
    jwtExpiresIn: process.env.ADMIN_JWT_EXPIRES_IN || '8h',
  },

  // LinuxDo Connect OAuth2（https://connect.linux.do）
  linuxdo: {
    clientId: process.env.LINUXDO_CLIENT_ID || '',
    clientSecret: process.env.LINUXDO_CLIENT_SECRET || '',
    redirectUri: process.env.LINUXDO_REDIRECT_URI || '',
    // v2 登录流回调（方案 §6.3），需同步登记到 Linux.do 应用设置
    redirectUriV2:
      process.env.LINUXDO_REDIRECT_URI_V2 ||
      `${process.env.BASE_URL || 'http://localhost:3001'}/api/v1/auth/linuxdo/callback`,
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
    preview: {
      enabled: process.env.PREVIEW_AUTH_ENABLED === 'true',
      username: process.env.PREVIEW_AUTH_USERNAME || '',
      password: process.env.PREVIEW_AUTH_PASSWORD || '',
    },
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
    // 下发给用户用于 OpenAI 兼容调用的公网入口，与容器内管理地址分离。
    publicBaseUrl: (process.env.STATION_PUBLIC_BASE_URL || '').replace(/\/$/, ''),
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

  // App 内 AI 能力走业务后台代理。地址只存在服务端，不下发给 App。
  // 默认复用 STATION_BASE_URL，也可单独指向另一个 OpenAI 兼容入口。
  ai: {
    enabled: process.env.AI_ENABLED !== 'false',
    upstreamBaseUrl: (
      process.env.AI_UPSTREAM_BASE_URL || process.env.STATION_BASE_URL || ''
    ).replace(/\/$/, ''),
    sharedApiKey: process.env.AI_SHARED_API_KEY || '',
    allowUserApiKey: process.env.AI_ALLOW_USER_API_KEY !== 'false',
    requestTimeoutMs: Number(process.env.AI_REQUEST_TIMEOUT_MS || 300000),
    leaseTtlSec: Number(process.env.AI_LEASE_TTL_SEC || 360),
    maxConcurrent: Number(process.env.AI_MAX_CONCURRENT || 100),
    maxConcurrentPerUser: Number(process.env.AI_MAX_CONCURRENT_PER_USER || 3),
    maxPromptChars: Number(process.env.AI_MAX_PROMPT_CHARS || 120000),
    maxOutputTokens: Number(process.env.AI_MAX_OUTPUT_TOKENS || 16384),
    imageModels: (process.env.AI_IMAGE_MODELS || '')
      .split(',')
      .map((v) => v.trim())
      .filter(Boolean),
    credentialSyncEnabled: process.env.AI_CREDENTIAL_SYNC_ENABLED !== 'false',
    credentialEncryptionKey: process.env.AI_CREDENTIAL_ENCRYPTION_KEY || '',
  },

  documents: {
    enabled: process.env.AI_DOCUMENTS_ENABLED !== 'false',
    outputDir: process.env.AI_DOCUMENT_OUTPUT_DIR || 'var/documents',
    workers: Math.max(1, Number(process.env.AI_DOCUMENT_WORKERS || 2)),
    maxActivePerUser: Math.max(1, Number(process.env.AI_DOCUMENT_MAX_ACTIVE_PER_USER || 2)),
    retentionHours: Math.max(1, Number(process.env.AI_DOCUMENT_RETENTION_HOURS || 72)),
    pollIntervalMs: Math.max(500, Number(process.env.AI_DOCUMENT_POLL_INTERVAL_MS || 1500)),
    maxSlides: Math.max(3, Math.min(30, Number(process.env.AI_DOCUMENT_MAX_SLIDES || 15))),
    maxSections: Math.max(3, Math.min(40, Number(process.env.AI_DOCUMENT_MAX_SECTIONS || 20))),
    maxImages: Math.max(0, Math.min(10, Number(process.env.AI_DOCUMENT_MAX_IMAGES || 4))),
    maxImageBytes:
      Math.max(1, Number(process.env.AI_DOCUMENT_MAX_IMAGE_MB || 8)) * 1024 * 1024,
    maxArtifactBytes:
      Math.max(5, Number(process.env.AI_DOCUMENT_MAX_ARTIFACT_MB || 50)) * 1024 * 1024,
  },

  ad: {
    callbackSecret: process.env.AD_CALLBACK_SECRET || '',
    dailyMax: Number(process.env.AD_DAILY_MAX || 6),
    businessTimezone: process.env.AD_BUSINESS_TIMEZONE || 'Asia/Shanghai',
    rewardAmount: process.env.AD_REWARD_AMOUNT || '0.020000',
    // 微单位金额（1 元 = 1,000,000），优先于 AD_REWARD_AMOUNT
    rewardMicrounits: Number(
      process.env.AD_REWARD_MICROUNITS ||
        Math.round(Number(process.env.AD_REWARD_AMOUNT || '0.02') * 1000000)
    ),
    taskExpireMinutes: Number(process.env.AD_TASK_EXPIRE_MINUTES || 10),
    taskStartCooldownSec: Number(process.env.AD_TASK_START_COOLDOWN_SEC || 5),
    maxPendingPerUser: Number(process.env.AD_MAX_PENDING_PER_USER || 2),
    requireTransactionId: process.env.AD_REQUIRE_TRANSACTION_ID !== 'false',
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
    interstitialCooldownSec: Number(process.env.AD_INTERSTITIAL_COOLDOWN_SEC || 600),
    interstitialDailyMax: Number(process.env.AD_INTERSTITIAL_DAILY_MAX || 2),
    splashMinIntervalSec: Number(process.env.AD_SPLASH_MIN_INTERVAL_SEC || 43200),
    splashDailyMax: Number(process.env.AD_SPLASH_DAILY_MAX || 1),
  },

  webInterstitial: {
    enabled:
      process.env.WEB_INTERSTITIAL_ENABLED === 'true' ||
      (process.env.WEB_INTERSTITIAL_ENABLED === undefined &&
        process.env.AD_INTERSTITIAL_ENABLED === 'true'),
    creativeId: process.env.WEB_INTERSTITIAL_CREATIVE_ID || 'house-ai-workbench-v1',
    title: process.env.WEB_INTERSTITIAL_TITLE || 'AI 公益工作台',
    body:
      process.env.WEB_INTERSTITIAL_BODY ||
      '工作台、生图和趣味游戏均可使用本站额度。',
    mediaUrl: process.env.WEB_INTERSTITIAL_MEDIA_URL || '',
    clickUrl: process.env.WEB_INTERSTITIAL_CLICK_URL || '',
    cooldownSec: Math.max(0, Number(process.env.WEB_INTERSTITIAL_COOLDOWN_SEC || 60)),
  },

  risk: {
    hashSecret: process.env.RISK_HASH_SECRET || process.env.JWT_SECRET || '',
    requireInstallId: process.env.REQUIRE_INSTALL_ID !== 'false',
    dailyMaxPerDevice: Number(process.env.AD_DAILY_MAX_PER_DEVICE || 6),
    dailyMaxPerIp: Number(process.env.AD_DAILY_MAX_PER_IP || 30),
    maxPendingPerDevice: Number(process.env.AD_MAX_PENDING_PER_DEVICE || 2),
    dailyRewardMaxMicrounits: Number(
      process.env.AD_DAILY_REWARD_MICROUNITS_MAX ||
        Number(process.env.AD_DAILY_MAX || 6) *
          Number(
            process.env.AD_REWARD_MICROUNITS ||
              Math.round(Number(process.env.AD_REWARD_AMOUNT || '0.1') * 1000000)
          )
    ),
    dailyRewardMaxPerDeviceMicrounits: Number(
      process.env.AD_DAILY_REWARD_MICROUNITS_PER_DEVICE_MAX ||
        Number(process.env.AD_DAILY_MAX_PER_DEVICE || 6) *
          Number(
            process.env.AD_REWARD_MICROUNITS ||
              Math.round(Number(process.env.AD_REWARD_AMOUNT || '0.1') * 1000000)
          )
    ),
    dailyRewardMaxPerIpMicrounits: Number(
      process.env.AD_DAILY_REWARD_MICROUNITS_PER_IP_MAX ||
        Number(process.env.AD_DAILY_MAX_PER_IP || 30) *
          Number(
            process.env.AD_REWARD_MICROUNITS ||
              Math.round(Number(process.env.AD_REWARD_AMOUNT || '0.1') * 1000000)
          )
    ),
  },
};

function isPlaceholder(value) {
  return !value || /change-me|do-not-use|YOUR_|__.+__/i.test(value);
}

export function validateProductionConfig() {
  if (config.env !== 'production') return;
  const errors = [];
  if (!config.baseUrl.startsWith('https://')) errors.push('BASE_URL 必须使用 HTTPS');
  if (isPlaceholder(config.jwt.secret) || config.jwt.secret.length < 32) {
    errors.push('JWT_SECRET 必须是至少 32 字符的随机值');
  }
  if (config.admin.enabled) {
    if (!config.admin.username) errors.push('启用管理后台时必须配置 ADMIN_USERNAME');
    if (!/^\$2[aby]\$/.test(config.admin.passwordHash)) {
      errors.push('启用管理后台时必须配置 bcrypt 格式的 ADMIN_PASSWORD_HASH');
    }
    if (isPlaceholder(config.admin.jwtSecret) || config.admin.jwtSecret.length < 32) {
      errors.push('启用管理后台时 ADMIN_JWT_SECRET 必须是至少 32 字符的随机值');
    }
    if (config.admin.jwtSecret === config.jwt.secret) {
      errors.push('ADMIN_JWT_SECRET 不能与 JWT_SECRET 相同');
    }
  }
  if (isPlaceholder(config.risk.hashSecret) || config.risk.hashSecret.length < 32) {
    errors.push('RISK_HASH_SECRET 必须是至少 32 字符的独立随机值');
  }
  if (config.risk.hashSecret === config.jwt.secret) {
    errors.push('RISK_HASH_SECRET 不能与 JWT_SECRET 相同');
  }
  if (config.ad.devSimulate) errors.push('生产环境禁止 AD_DEV_SIMULATE=true');
  if (config.auth.preview.enabled) errors.push('生产环境禁止 PREVIEW_AUTH_ENABLED=true');
  if (config.ad.rewardedEnabled && config.ad.provider === 'mock') {
    errors.push('生产环境启用奖励广告时，AD_PROVIDER 不能为 mock');
  }
  if (config.ad.rewardedEnabled && config.ad.provider !== 'mock') {
    if (isPlaceholder(config.ad.callbackSecret) || config.ad.callbackSecret.length < 32) {
      errors.push('真实广告必须配置至少 32 字符的 AD_CALLBACK_SECRET');
    }
  }
  if (config.station.mode !== 'mock') {
    if (!config.station.baseUrl) errors.push('必须配置 STATION_BASE_URL');
    if (config.station.mode === 'newapi' && isPlaceholder(config.station.adminToken)) {
      errors.push('newapi 模式必须配置 STATION_ADMIN_TOKEN');
    }
    if (config.station.mode === 'newapi' && !config.station.publicBaseUrl.startsWith('https://')) {
      errors.push('newapi 模式必须配置 HTTPS 的 STATION_PUBLIC_BASE_URL');
    }
  }
  if (config.ai.enabled && !config.ai.upstreamBaseUrl) {
    errors.push('AI_ENABLED=true 时必须配置 AI_UPSTREAM_BASE_URL 或 STATION_BASE_URL');
  }
  if (config.ai.enabled && !config.ai.allowUserApiKey && isPlaceholder(config.ai.sharedApiKey)) {
    errors.push('禁用用户 API Key 时必须配置 AI_SHARED_API_KEY');
  }
  if (
    config.ai.credentialSyncEnabled &&
    (isPlaceholder(config.ai.credentialEncryptionKey) || config.ai.credentialEncryptionKey.length < 32)
  ) {
    errors.push('启用跨端 Key 同步时必须配置至少 32 字符的 AI_CREDENTIAL_ENCRYPTION_KEY');
  }
  if (errors.length > 0) {
    throw new Error(`生产配置不安全:\n- ${errors.join('\n- ')}`);
  }
}
