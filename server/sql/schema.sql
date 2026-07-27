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
    expires_at TIMESTAMP,
    watched_at TIMESTAMP,
    rewarded_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_ad_tasks_user ON ad_tasks (user_id, created_at DESC);

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
