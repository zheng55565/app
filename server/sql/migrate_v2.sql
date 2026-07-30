-- v2 迁移：Linux.do 唯一身份 + 微单位金额模型
-- 幂等设计，可重复执行。对应《移动端Linuxdo-OAuth登录方案.md》第 11/16 节。
-- 金额固定比例：1 元 = 1,000,000 microunits，与 NUMERIC(18,6) 六位小数精度一致。

-- ============ 1. users 表：增加 Linux.do 主身份字段 ============
ALTER TABLE users ADD COLUMN IF NOT EXISTS linuxdo_user_id VARCHAR(100);
ALTER TABLE users ADD COLUMN IF NOT EXISTS linuxdo_username VARCHAR(100);
ALTER TABLE users ADD COLUMN IF NOT EXISTS linuxdo_avatar_url VARCHAR(500);
ALTER TABLE users ADD COLUMN IF NOT EXISTS linuxdo_trust_level INT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS station_user_id BIGINT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS last_login_at TIMESTAMP;

-- 迁移期允许为空（旧密码用户尚无 Linux.do 身份），有值时必须唯一
CREATE UNIQUE INDEX IF NOT EXISTS uniq_users_linuxdo_user_id
    ON users (linuxdo_user_id) WHERE linuxdo_user_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uniq_users_station_user_id
    ON users (station_user_id) WHERE station_user_id IS NOT NULL;

-- 用 linuxdo_bindings 中的有效绑定回填主身份（§16.2 步骤 3）
UPDATE users u
SET linuxdo_user_id = b.linuxdo_user_id,
    linuxdo_username = b.linuxdo_username,
    linuxdo_trust_level = b.trust_level,
    updated_at = NOW()
FROM linuxdo_bindings b
WHERE b.user_id = u.id AND b.bind_status = 'bound' AND u.linuxdo_user_id IS NULL;

-- ============ 2. OAuth 登录会话表（§11.2） ============
CREATE TABLE IF NOT EXISTS oauth_login_sessions (
    id BIGSERIAL PRIMARY KEY,
    login_session_id VARCHAR(100) NOT NULL UNIQUE,
    session_secret_hash VARCHAR(128) NOT NULL,
    state_hash VARCHAR(128) NOT NULL UNIQUE,
    platform VARCHAR(30),
    app_version VARCHAR(50),
    status VARCHAR(40) NOT NULL DEFAULT 'pending',
    -- pending | authorized | account_not_found | account_disabled
    -- | linuxdo_account_rejected | failed | expired | completed
    linuxdo_user_id VARCHAR(100),
    linuxdo_username VARCHAR(100),
    linuxdo_avatar_url VARCHAR(500),
    linuxdo_trust_level INT,
    station_user_id BIGINT,
    error_code VARCHAR(60),
    login_code_hash VARCHAR(128),
    login_code_issued_at TIMESTAMP,
    login_code_expires_at TIMESTAMP,
    login_code_used_at TIMESTAMP,
    state_used_at TIMESTAMP,
    expires_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- ============ 3. Refresh Token 表（§11.3，轮换 + 家族撤销） ============
CREATE TABLE IF NOT EXISTS refresh_tokens (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id),
    token_hash VARCHAR(128) NOT NULL UNIQUE,
    token_family_id VARCHAR(100) NOT NULL,
    device_name VARCHAR(200),
    expires_at TIMESTAMP NOT NULL,
    revoked_at TIMESTAMP,
    replaced_by_token_id BIGINT,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_family ON refresh_tokens (token_family_id);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user ON refresh_tokens (user_id);

-- ============ 4. 登录审计表（§11.4） ============
CREATE TABLE IF NOT EXISTS auth_audit_logs (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT,
    event_type VARCHAR(60) NOT NULL,
    result VARCHAR(30) NOT NULL,
    detail VARCHAR(300),
    ip_address VARCHAR(60),
    user_agent VARCHAR(300),
    request_id VARCHAR(60),
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_auth_audit_user ON auth_audit_logs (user_id, created_at DESC);

-- ============ 5. 奖励订单表（§8.2，中转站入账镜像） ============
CREATE TABLE IF NOT EXISTS reward_orders (
    id BIGSERIAL PRIMARY KEY,
    order_no VARCHAR(120) NOT NULL UNIQUE,
    user_id BIGINT NOT NULL REFERENCES users(id),
    station_user_id BIGINT,
    linuxdo_user_id VARCHAR(100),
    amount_microunits BIGINT NOT NULL,
    source VARCHAR(50) NOT NULL DEFAULT 'rewarded_ad',
    ad_task_id VARCHAR(120),
    provider VARCHAR(60),
    provider_transaction_id VARCHAR(150),
    status VARCHAR(30) NOT NULL DEFAULT 'pending', -- pending | crediting | success | failed | review
    station_transaction_id VARCHAR(120),
    fail_reason VARCHAR(300),
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);
-- 同一广告平台交易只能发奖一次（§8.2）
CREATE UNIQUE INDEX IF NOT EXISTS uniq_reward_provider_tx
    ON reward_orders (provider, provider_transaction_id)
    WHERE provider_transaction_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_reward_orders_user ON reward_orders (user_id, created_at DESC);

-- ============ 6. 金额迁移：NUMERIC(18,6) -> BIGINT microunits（§16.2 步骤 5） ============
-- 旧 NUMERIC 列保留用于对账，结构删除单独发布（§16.2 步骤 9）。
ALTER TABLE wallets ADD COLUMN IF NOT EXISTS balance_microunits BIGINT;
ALTER TABLE wallets ADD COLUMN IF NOT EXISTS total_ad_income_microunits BIGINT;
UPDATE wallets
SET balance_microunits = ROUND(balance * 1000000)::BIGINT,
    total_ad_income_microunits = ROUND(total_ad_income * 1000000)::BIGINT
WHERE balance_microunits IS NULL;
ALTER TABLE wallets ALTER COLUMN balance_microunits SET DEFAULT 0;
ALTER TABLE wallets ALTER COLUMN total_ad_income_microunits SET DEFAULT 0;
UPDATE wallets SET balance_microunits = 0 WHERE balance_microunits IS NULL;
UPDATE wallets SET total_ad_income_microunits = 0 WHERE total_ad_income_microunits IS NULL;
ALTER TABLE wallets ALTER COLUMN balance_microunits SET NOT NULL;
ALTER TABLE wallets ALTER COLUMN total_ad_income_microunits SET NOT NULL;

ALTER TABLE wallet_records ADD COLUMN IF NOT EXISTS amount_microunits BIGINT;
ALTER TABLE wallet_records ADD COLUMN IF NOT EXISTS balance_after_microunits BIGINT;
UPDATE wallet_records
SET amount_microunits = ROUND(amount * 1000000)::BIGINT,
    balance_after_microunits = ROUND(balance_after * 1000000)::BIGINT
WHERE amount_microunits IS NULL;

ALTER TABLE ad_tasks ADD COLUMN IF NOT EXISTS reward_amount_microunits BIGINT;
UPDATE ad_tasks
SET reward_amount_microunits = ROUND(reward_amount * 1000000)::BIGINT
WHERE reward_amount_microunits IS NULL;

-- ============ 7. 本地 mock 中转站（STATION_MODE=mock 时使用） ============
-- 模拟 new-api 侧「通过 Linux.do 注册的中转站账号」。接入真实 new-api 内部 API 后弃用。
CREATE TABLE IF NOT EXISTS mock_station_accounts (
    id BIGSERIAL PRIMARY KEY,
    linuxdo_user_id VARCHAR(100) NOT NULL UNIQUE,
    username VARCHAR(100),
    status VARCHAR(30) NOT NULL DEFAULT 'active', -- active | disabled
    balance_microunits BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS mock_station_transactions (
    id BIGSERIAL PRIMARY KEY,
    station_user_id BIGINT NOT NULL REFERENCES mock_station_accounts(id),
    order_no VARCHAR(120) NOT NULL UNIQUE,
    amount_microunits BIGINT NOT NULL,
    balance_after_microunits BIGINT NOT NULL,
    source VARCHAR(50),
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- 用已绑定用户给 mock 中转站开户，模拟「已在中转站注册」
INSERT INTO mock_station_accounts (linuxdo_user_id, username, balance_microunits)
SELECT u.linuxdo_user_id, u.linuxdo_username,
       COALESCE(w.balance_microunits, 0)
FROM users u
LEFT JOIN wallets w ON w.user_id = u.id
WHERE u.linuxdo_user_id IS NOT NULL
ON CONFLICT (linuxdo_user_id) DO NOTHING;
