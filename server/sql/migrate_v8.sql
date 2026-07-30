-- v8: record the rewarded-ad transaction observed by the App.
-- Client evidence never credits the wallet by itself; the signed provider callback remains required.
ALTER TABLE ad_tasks ADD COLUMN IF NOT EXISTS client_transaction_id VARCHAR(150);
ALTER TABLE ad_tasks ADD COLUMN IF NOT EXISTS client_completed_at TIMESTAMP;

CREATE UNIQUE INDEX IF NOT EXISTS uniq_ad_tasks_client_transaction
    ON ad_tasks (ad_platform, client_transaction_id)
    WHERE client_transaction_id IS NOT NULL;
