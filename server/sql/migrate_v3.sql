-- v3：AI代理并发租约 + 奖励广告多维风控
-- 可重复执行。生产发布时必须先执行本迁移，再切换新版服务。

ALTER TABLE ad_tasks ADD COLUMN IF NOT EXISTS device_hash VARCHAR(64);
ALTER TABLE ad_tasks ADD COLUMN IF NOT EXISTS start_ip_hash VARCHAR(64);
ALTER TABLE ad_tasks ADD COLUMN IF NOT EXISTS provider_transaction_id VARCHAR(150);

CREATE INDEX IF NOT EXISTS idx_ad_tasks_user_active
    ON ad_tasks (user_id, status, expires_at DESC);
CREATE INDEX IF NOT EXISTS idx_ad_tasks_device_active
    ON ad_tasks (device_hash, status, expires_at DESC)
    WHERE device_hash IS NOT NULL;

ALTER TABLE daily_ad_limits ADD COLUMN IF NOT EXISTS rewarded_microunits BIGINT NOT NULL DEFAULT 0;
ALTER TABLE daily_ad_limits ADD COLUMN IF NOT EXISTS max_reward_microunits BIGINT;

-- device/ip 等风控主体共用。subject_hash 使用服务端密钥 HMAC，不保存原始标识。
CREATE TABLE IF NOT EXISTS daily_ad_subject_limits (
    id BIGSERIAL PRIMARY KEY,
    subject_type VARCHAR(20) NOT NULL, -- device | ip
    subject_hash VARCHAR(64) NOT NULL,
    date DATE NOT NULL,
    watched_count INT NOT NULL DEFAULT 0,
    rewarded_microunits BIGINT NOT NULL DEFAULT 0,
    max_count INT NOT NULL,
    max_reward_microunits BIGINT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (subject_type, subject_hash, date)
);
CREATE INDEX IF NOT EXISTS idx_daily_ad_subject_date
    ON daily_ad_subject_limits (date, subject_type);

-- 跨进程/多副本AI并发租约。进程崩溃后由 expires_at 自动失效。
CREATE TABLE IF NOT EXISTS api_request_leases (
    lease_id UUID PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    kind VARCHAR(30) NOT NULL,
    expires_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_api_request_leases_active
    ON api_request_leases (expires_at, user_id);
