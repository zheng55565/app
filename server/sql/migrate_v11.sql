-- v11: auditable runtime operations settings and immutable rule snapshots.
CREATE TABLE IF NOT EXISTS runtime_settings (
    setting_key VARCHAR(80) PRIMARY KEY,
    setting_value JSONB NOT NULL DEFAULT '{}'::jsonb,
    updated_by VARCHAR(100),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

ALTER TABLE ad_tasks
    ADD COLUMN IF NOT EXISTS policy_snapshot JSONB NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE game_mine_packets
    ADD COLUMN IF NOT EXISTS rules_snapshot JSONB NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE game_battle_rounds
    ADD COLUMN IF NOT EXISTS rules_snapshot JSONB NOT NULL DEFAULT '{}'::jsonb;

CREATE INDEX IF NOT EXISTS idx_runtime_settings_updated
    ON runtime_settings (updated_at DESC);

