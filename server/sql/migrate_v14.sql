-- v14: one provider transaction can serve exactly one reward or recovery task.
CREATE TABLE IF NOT EXISTS ad_provider_transactions (
    provider VARCHAR(60) NOT NULL,
    transaction_id VARCHAR(160) NOT NULL,
    purpose VARCHAR(32) NOT NULL CHECK (purpose IN ('home_balance', 'game_recovery')),
    task_token VARCHAR(120) NOT NULL,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    PRIMARY KEY (provider, transaction_id)
);
CREATE INDEX IF NOT EXISTS idx_ad_provider_transactions_user
    ON ad_provider_transactions (user_id, created_at DESC);

INSERT INTO ad_provider_transactions
    (provider,transaction_id,purpose,task_token,user_id,created_at)
SELECT provider,provider_transaction_id,'home_balance',ad_task_id,user_id,created_at
FROM reward_orders
WHERE provider IS NOT NULL AND provider_transaction_id IS NOT NULL
  AND ad_task_id IS NOT NULL
ON CONFLICT (provider,transaction_id) DO NOTHING;

INSERT INTO ad_provider_transactions
    (provider,transaction_id,purpose,task_token,user_id,created_at)
SELECT ad_platform,provider_transaction_id,'game_recovery',task_token,user_id,created_at
FROM game_recovery_ad_tasks
WHERE provider_transaction_id IS NOT NULL
ON CONFLICT (provider,transaction_id) DO NOTHING;
