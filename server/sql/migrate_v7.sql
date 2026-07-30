-- v7: 八房生存局、权威消消乐关卡、宝箱与广告复活任务。

ALTER TABLE game_battle_entries
    DROP CONSTRAINT IF EXISTS game_battle_entries_room_no_check;
ALTER TABLE game_battle_entries
    ADD CONSTRAINT game_battle_entries_room_no_check
    CHECK (room_no BETWEEN 1 AND 8);

ALTER TABLE game_battle_rounds
    ADD COLUMN IF NOT EXISTS opponent_entries JSONB NOT NULL DEFAULT '[]'::jsonb,
    ADD COLUMN IF NOT EXISTS room_totals JSONB NOT NULL DEFAULT '[]'::jsonb;

ALTER TABLE game_results
    DROP CONSTRAINT IF EXISTS game_results_game_type_check;
ALTER TABLE game_results
    ADD CONSTRAINT game_results_game_type_check
    CHECK (game_type IN ('rps', 'mine', 'battle', 'match3'));

CREATE TABLE IF NOT EXISTS game_match3_sessions (
    id UUID PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    level_no INTEGER NOT NULL CHECK (level_no BETWEEN 1 AND 100000),
    status VARCHAR(16) NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'failed', 'completed')),
    board JSONB NOT NULL,
    score INTEGER NOT NULL DEFAULT 0 CHECK (score >= 0),
    target_score INTEGER NOT NULL CHECK (target_score > 0),
    moves_left INTEGER NOT NULL CHECK (moves_left >= 0),
    recovery_count SMALLINT NOT NULL DEFAULT 0 CHECK (recovery_count BETWEEN 0 AND 3),
    rng_nonce INTEGER NOT NULL DEFAULT 0 CHECK (rng_nonce >= 0),
    started_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_game_match3_sessions_user
    ON game_match3_sessions (user_id, updated_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS uniq_game_match3_active_session
    ON game_match3_sessions (user_id) WHERE status = 'active';

CREATE TABLE IF NOT EXISTS game_match3_moves (
    id UUID PRIMARY KEY,
    session_id UUID NOT NULL REFERENCES game_match3_sessions(id) ON DELETE CASCADE,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    request_id VARCHAR(100) NOT NULL,
    from_x SMALLINT NOT NULL,
    from_y SMALLINT NOT NULL,
    to_x SMALLINT NOT NULL,
    to_y SMALLINT NOT NULL,
    cleared_count INTEGER NOT NULL DEFAULT 0,
    score_after INTEGER NOT NULL DEFAULT 0,
    response JSONB NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, request_id)
);

CREATE TABLE IF NOT EXISTS game_match3_level_rewards (
    id UUID PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    session_id UUID NOT NULL REFERENCES game_match3_sessions(id) ON DELETE CASCADE,
    level_no INTEGER NOT NULL,
    reward_micropoints BIGINT NOT NULL DEFAULT 1000000,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, level_no)
);

CREATE TABLE IF NOT EXISTS game_match3_chests (
    id UUID PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    milestone_level INTEGER NOT NULL CHECK (milestone_level > 0 AND milestone_level % 10 = 0),
    result VARCHAR(16) NOT NULL CHECK (result IN ('again', 'points_1', 'points_5', 'points_10')),
    reward_micropoints BIGINT NOT NULL DEFAULT 0 CHECK (reward_micropoints >= 0),
    opened_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, milestone_level)
);

CREATE TABLE IF NOT EXISTS game_recovery_ad_tasks (
    id UUID PRIMARY KEY,
    task_token VARCHAR(80) NOT NULL UNIQUE,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    session_id UUID NOT NULL REFERENCES game_match3_sessions(id) ON DELETE CASCADE,
    ad_platform VARCHAR(32) NOT NULL,
    ad_unit_id VARCHAR(100) NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'created'
        CHECK (status IN ('created', 'verified', 'consumed', 'expired')),
    provider_transaction_id VARCHAR(160),
    callback_payload JSONB,
    expires_at TIMESTAMP NOT NULL,
    verified_at TIMESTAMP,
    consumed_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS uniq_game_recovery_provider_tx
    ON game_recovery_ad_tasks (ad_platform, provider_transaction_id)
    WHERE provider_transaction_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_game_recovery_user
    ON game_recovery_ad_tasks (user_id, created_at DESC);

