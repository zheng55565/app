-- v6：独立游戏积分钱包、对局历史与三类小游戏状态。
-- 1 游戏积分 = 1,000,000 micropoints，所有结算使用 BIGINT，禁止浮点金额。

CREATE TABLE IF NOT EXISTS game_wallets (
    user_id BIGINT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    balance_micropoints BIGINT NOT NULL DEFAULT 0 CHECK (balance_micropoints >= 0),
    ai_converted_in_micropoints BIGINT NOT NULL DEFAULT 0
        CHECK (ai_converted_in_micropoints >= 0),
    ai_converted_out_micropoints BIGINT NOT NULL DEFAULT 0
        CHECK (ai_converted_out_micropoints >= 0),
    redeemable_micropoints BIGINT NOT NULL DEFAULT 0
        CHECK (redeemable_micropoints >= 0 AND redeemable_micropoints <= balance_micropoints),
    total_staked_micropoints BIGINT NOT NULL DEFAULT 0 CHECK (total_staked_micropoints >= 0),
    total_payout_micropoints BIGINT NOT NULL DEFAULT 0 CHECK (total_payout_micropoints >= 0),
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);
ALTER TABLE game_wallets
    ADD COLUMN IF NOT EXISTS ai_converted_in_micropoints BIGINT NOT NULL DEFAULT 0
        CHECK (ai_converted_in_micropoints >= 0),
    ADD COLUMN IF NOT EXISTS ai_converted_out_micropoints BIGINT NOT NULL DEFAULT 0
        CHECK (ai_converted_out_micropoints >= 0);

CREATE TABLE IF NOT EXISTS game_wallet_records (
    id UUID PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    amount_micropoints BIGINT NOT NULL,
    balance_after_micropoints BIGINT NOT NULL CHECK (balance_after_micropoints >= 0),
    type VARCHAR(40) NOT NULL,
    game_type VARCHAR(24),
    related_id UUID,
    request_id VARCHAR(100),
    remark VARCHAR(255),
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX IF NOT EXISTS uniq_game_wallet_record_request
    ON game_wallet_records (user_id, request_id) WHERE request_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_game_wallet_records_user
    ON game_wallet_records (user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS game_conversion_orders (
    id UUID PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    station_user_id BIGINT NOT NULL,
    amount_points BIGINT NOT NULL CHECK (amount_points > 0),
    amount_micropoints BIGINT NOT NULL CHECK (amount_micropoints > 0),
    direction VARCHAR(16) NOT NULL DEFAULT 'ai_to_game'
        CHECK (direction IN ('ai_to_game', 'game_to_ai')),
    request_id VARCHAR(100) NOT NULL,
    status VARCHAR(24) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'completed', 'review', 'failed')),
    station_transaction_id VARCHAR(200),
    error_message TEXT,
    completed_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, request_id)
);
ALTER TABLE game_conversion_orders
    ADD COLUMN IF NOT EXISTS direction VARCHAR(16) NOT NULL DEFAULT 'ai_to_game'
        CHECK (direction IN ('ai_to_game', 'game_to_ai'));

-- 兼容已执行过旧版v6的实例。只在首次增加本金列时回填，保证脚本重跑
-- 不会覆盖新版本已经实时维护的可兑回余额。
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = current_schema()
          AND table_name = 'game_wallets'
          AND column_name = 'redeemable_micropoints'
    ) THEN
        ALTER TABLE game_wallets
            ADD COLUMN redeemable_micropoints BIGINT NOT NULL DEFAULT 0
            CHECK (redeemable_micropoints >= 0);

        WITH conversion_totals AS (
            SELECT user_id,
                COALESCE(SUM(amount_micropoints) FILTER (
                    WHERE direction = 'ai_to_game' AND status = 'completed'
                ), 0) AS converted_in,
                COALESCE(SUM(amount_micropoints) FILTER (
                    WHERE direction = 'game_to_ai'
                      AND status IN ('pending', 'review', 'completed')
                ), 0) AS converted_out
            FROM game_conversion_orders
            GROUP BY user_id
        )
        UPDATE game_wallets AS wallet
        SET ai_converted_in_micropoints = totals.converted_in,
            ai_converted_out_micropoints = totals.converted_out,
            redeemable_micropoints = LEAST(
                wallet.balance_micropoints,
                GREATEST(
                    0,
                    totals.converted_in - totals.converted_out
                      - wallet.total_staked_micropoints
                )
            )
        FROM conversion_totals AS totals
        WHERE wallet.user_id = totals.user_id;
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS game_results (
    id UUID PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    game_type VARCHAR(24) NOT NULL CHECK (game_type IN ('rps', 'mine', 'battle')),
    game_id UUID NOT NULL,
    mode VARCHAR(16) NOT NULL DEFAULT 'human',
    result VARCHAR(16) NOT NULL CHECK (result IN ('win', 'loss', 'draw', 'refund', 'claimed')),
    stake_micropoints BIGINT NOT NULL DEFAULT 0,
    payout_micropoints BIGINT NOT NULL DEFAULT 0,
    fee_micropoints BIGINT NOT NULL DEFAULT 0,
    net_profit_micropoints BIGINT NOT NULL DEFAULT 0,
    detail JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, game_type, game_id)
);
CREATE INDEX IF NOT EXISTS idx_game_results_user
    ON game_results (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_game_results_today_rank
    ON game_results (created_at, net_profit_micropoints DESC);

CREATE TABLE IF NOT EXISTS game_mine_packets (
    id UUID PRIMARY KEY,
    creator_user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    creator_install_hash CHAR(64) NOT NULL,
    mine_digit SMALLINT NOT NULL CHECK (mine_digit BETWEEN 0 AND 9),
    total_micropoints BIGINT NOT NULL,
    liability_micropoints BIGINT NOT NULL,
    creator_payout_micropoints BIGINT NOT NULL DEFAULT 0,
    platform_fee_micropoints BIGINT NOT NULL DEFAULT 0,
    claim_count SMALLINT NOT NULL DEFAULT 7 CHECK (claim_count = 7),
    claimed_count SMALLINT NOT NULL DEFAULT 0 CHECK (claimed_count BETWEEN 0 AND 7),
    status VARCHAR(16) NOT NULL DEFAULT 'open'
        CHECK (status IN ('open', 'completed', 'expired')),
    expires_at TIMESTAMP NOT NULL,
    completed_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_game_mine_packets_open
    ON game_mine_packets (created_at ASC) WHERE status = 'open';

CREATE TABLE IF NOT EXISTS game_mine_shares (
    packet_id UUID NOT NULL REFERENCES game_mine_packets(id) ON DELETE CASCADE,
    slot SMALLINT NOT NULL CHECK (slot BETWEEN 1 AND 7),
    amount_micropoints BIGINT NOT NULL CHECK (amount_micropoints > 0),
    claimed_by_user_id BIGINT REFERENCES users(id) ON DELETE SET NULL,
    claimant_install_hash CHAR(64),
    is_mine BOOLEAN,
    compensation_micropoints BIGINT NOT NULL DEFAULT 0,
    fee_micropoints BIGINT NOT NULL DEFAULT 0,
    claimed_at TIMESTAMP,
    PRIMARY KEY (packet_id, slot)
);
CREATE UNIQUE INDEX IF NOT EXISTS uniq_game_mine_claimant
    ON game_mine_shares (packet_id, claimed_by_user_id)
    WHERE claimed_by_user_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uniq_game_mine_claimant_install
    ON game_mine_shares (packet_id, claimant_install_hash)
    WHERE claimant_install_hash IS NOT NULL;

CREATE TABLE IF NOT EXISTS game_battle_rounds (
    id UUID PRIMARY KEY,
    status VARCHAR(16) NOT NULL DEFAULT 'betting'
        CHECK (status IN ('betting', 'settling', 'settled', 'refunded')),
    rng_seed_hex CHAR(64) NOT NULL,
    rng_commit CHAR(64) NOT NULL,
    eliminated_rooms SMALLINT[],
    losing_pool_micropoints BIGINT NOT NULL DEFAULT 0,
    distributable_micropoints BIGINT NOT NULL DEFAULT 0,
    platform_fee_micropoints BIGINT NOT NULL DEFAULT 0,
    closes_at TIMESTAMP NOT NULL,
    settled_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_game_battle_rounds_status
    ON game_battle_rounds (status, closes_at);

CREATE TABLE IF NOT EXISTS game_battle_entries (
    id UUID PRIMARY KEY,
    round_id UUID NOT NULL REFERENCES game_battle_rounds(id) ON DELETE CASCADE,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    install_hash CHAR(64) NOT NULL,
    room_no SMALLINT NOT NULL CHECK (room_no BETWEEN 1 AND 6),
    stake_micropoints BIGINT NOT NULL CHECK (stake_micropoints > 0),
    payout_micropoints BIGINT NOT NULL DEFAULT 0,
    fee_micropoints BIGINT NOT NULL DEFAULT 0,
    result VARCHAR(16) CHECK (result IN ('win', 'loss', 'refund')),
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (round_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_game_battle_entries_round
    ON game_battle_entries (round_id, room_no);
CREATE UNIQUE INDEX IF NOT EXISTS uniq_game_battle_install
    ON game_battle_entries (round_id, install_hash);
