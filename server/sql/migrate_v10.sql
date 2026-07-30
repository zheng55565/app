-- v10: administrator audit and client-side interstitial telemetry.
-- Telemetry is analytics-only and can never issue wallet or game rewards.
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
