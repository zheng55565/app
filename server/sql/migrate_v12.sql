-- v12: freeze match-3 rewards and chest odds when a level starts.
ALTER TABLE game_match3_sessions
    ADD COLUMN IF NOT EXISTS rules_snapshot JSONB NOT NULL DEFAULT '{}'::jsonb;
