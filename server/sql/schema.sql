-- 公益中转站广告奖励系统 数据库结构（PostgreSQL）
-- psql -d linuxdo_ad_reward -f sql/schema.sql

-- 用户表
CREATE TABLE IF NOT EXISTS users (
    id BIGSERIAL PRIMARY KEY,
    username VARCHAR(100) UNIQUE,
    email VARCHAR(255),
    phone VARCHAR(50),
    password_hash VARCHAR(255),
    status VARCHAR(30) NOT NULL DEFAULT 'active', -- active | banned
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- Linux.do 绑定关系表（OAuth2 绑定后 linuxdo_user_id 为论坛不可变用户 ID）
CREATE TABLE IF NOT EXISTS linuxdo_bindings (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id),
    linuxdo_user_id VARCHAR(100),
    linuxdo_username VARCHAR(100) NOT NULL,
    trust_level INT,
    bind_status VARCHAR(30) NOT NULL DEFAULT 'pending', -- pending | bound | unbound
    bound_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- 一个 Linux.do 账号只能被一个中转站账号绑定（仅对 bound 生效，解绑后可重新绑定）
CREATE UNIQUE INDEX IF NOT EXISTS uniq_linuxdo_bound_user
    ON linuxdo_bindings (linuxdo_user_id) WHERE bind_status = 'bound';
CREATE UNIQUE INDEX IF NOT EXISTS uniq_user_bound
    ON linuxdo_bindings (user_id) WHERE bind_status = 'bound';

-- 钱包表
CREATE TABLE IF NOT EXISTS wallets (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL UNIQUE REFERENCES users(id),
    balance NUMERIC(18, 6) NOT NULL DEFAULT 0,
    total_ad_income NUMERIC(18, 6) NOT NULL DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- 余额流水表
CREATE TABLE IF NOT EXISTS wallet_records (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id),
    amount NUMERIC(18, 6) NOT NULL,
    balance_after NUMERIC(18, 6) NOT NULL,
    type VARCHAR(50) NOT NULL,   -- ad_reward | admin_adjust | consume ...
    source VARCHAR(50) NOT NULL, -- ad_callback | admin | system ...
    related_id VARCHAR(100),     -- 关联的 task_token 等
    remark VARCHAR(255),
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_wallet_records_user ON wallet_records (user_id, created_at DESC);

-- 广告任务表
CREATE TABLE IF NOT EXISTS ad_tasks (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id),
    ad_platform VARCHAR(50) NOT NULL,
    ad_unit_id VARCHAR(100),
    task_token VARCHAR(100) NOT NULL UNIQUE,
    reward_amount NUMERIC(18, 6) NOT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'created', -- created | rewarded | expired
    callback_payload TEXT,
    policy_snapshot JSONB NOT NULL DEFAULT '{}'::jsonb,
    client_transaction_id VARCHAR(150),
    client_completed_at TIMESTAMP,
    expires_at TIMESTAMP,
    watched_at TIMESTAMP,
    rewarded_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_ad_tasks_user ON ad_tasks (user_id, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS uniq_ad_tasks_client_transaction
    ON ad_tasks (ad_platform, client_transaction_id)
    WHERE client_transaction_id IS NOT NULL;

-- 广告平台回调审计：无论验证成功或失败都记录，签名原文不会入库
CREATE TABLE IF NOT EXISTS ad_callback_audits (
    id BIGSERIAL PRIMARY KEY,
    provider VARCHAR(30) NOT NULL,
    request_method VARCHAR(10) NOT NULL,
    request_path VARCHAR(300) NOT NULL,
    user_id VARCHAR(100),
    transaction_id VARCHAR(150),
    task_token VARCHAR(150),
    placement_id VARCHAR(150),
    has_extra_info BOOLEAN NOT NULL DEFAULT FALSE,
    signature_present BOOLEAN NOT NULL DEFAULT FALSE,
    signature_valid BOOLEAN,
    http_status INT,
    outcome VARCHAR(300),
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    received_at TIMESTAMP NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_ad_callback_audits_received
    ON ad_callback_audits (received_at DESC);
CREATE INDEX IF NOT EXISTS idx_ad_callback_audits_transaction
    ON ad_callback_audits (provider, transaction_id)
    WHERE transaction_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_ad_callback_audits_task
    ON ad_callback_audits (task_token, received_at DESC)
    WHERE task_token IS NOT NULL;

-- 管理员登录审计（管理员身份与 App 用户身份完全分离）
CREATE TABLE IF NOT EXISTS admin_audit_logs (
    id BIGSERIAL PRIMARY KEY,
    username VARCHAR(100),
    event_type VARCHAR(60) NOT NULL,
    result VARCHAR(30) NOT NULL,
    detail VARCHAR(300),
    ip_address VARCHAR(60),
    user_agent VARCHAR(300),
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_admin_audit_created
    ON admin_audit_logs (created_at DESC);

-- Web 插屏埋点，仅用于统计，绝不参与额度或游戏积分结算
CREATE TABLE IF NOT EXISTS ad_client_events (
    id BIGSERIAL PRIMARY KEY,
    event_id VARCHAR(64) NOT NULL UNIQUE,
    creative_id VARCHAR(100),
    placement VARCHAR(100) NOT NULL,
    trigger_name VARCHAR(60) NOT NULL,
    event_type VARCHAR(30) NOT NULL,
    session_id VARCHAR(64),
    source_ip_hash VARCHAR(128),
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    occurred_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_ad_client_event_type CHECK (
      event_type IN ('impression', 'click', 'close', 'load_failed')
    )
);
CREATE INDEX IF NOT EXISTS idx_ad_client_events_created
    ON ad_client_events (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ad_client_events_type
    ON ad_client_events (event_type, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ad_client_events_trigger
    ON ad_client_events (trigger_name, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ad_client_events_ip_rate
    ON ad_client_events (source_ip_hash, created_at DESC)
    WHERE source_ip_hash IS NOT NULL;

-- 可由管理端调整的非密钥运营参数；每次修改同时写管理员审计。
CREATE TABLE IF NOT EXISTS runtime_settings (
    setting_key VARCHAR(80) PRIMARY KEY,
    setting_value JSONB NOT NULL DEFAULT '{}'::jsonb,
    updated_by VARCHAR(100),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_runtime_settings_updated
    ON runtime_settings (updated_at DESC);

-- 每日广告次数表
CREATE TABLE IF NOT EXISTS daily_ad_limits (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id),
    date DATE NOT NULL,
    watched_count INT NOT NULL DEFAULT 0,
    max_count INT NOT NULL DEFAULT 6,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, date)
);

-- OAuth2 state 表（防 CSRF，一次性使用，替代 Redis 的最小实现）
CREATE TABLE IF NOT EXISTS oauth_states (
    state VARCHAR(100) PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id),
    used BOOLEAN NOT NULL DEFAULT FALSE,
    expires_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- App 版本表
CREATE TABLE IF NOT EXISTS app_versions (
    id BIGSERIAL PRIMARY KEY,
    platform VARCHAR(30) NOT NULL DEFAULT 'android',
    version_name VARCHAR(50) NOT NULL,
    version_code INT NOT NULL,
    apk_url VARCHAR(500) NOT NULL,
    force_update BOOLEAN NOT NULL DEFAULT FALSE,
    changelog TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);
