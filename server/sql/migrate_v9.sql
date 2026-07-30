-- v9: persist every HJ server callback attempt, including rejected callbacks.
-- The raw signature is never stored; only presence and verification result are recorded.
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
