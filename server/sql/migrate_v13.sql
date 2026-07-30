-- v13: keep mine claimant and creator settlements as separate idempotent results.
UPDATE game_results
SET mode = CASE detail->>'role'
  WHEN 'creator' THEN 'creator'
  WHEN 'claimant' THEN 'claimant'
  ELSE mode
END
WHERE game_type = 'mine' AND detail->>'role' IN ('creator', 'claimant');

ALTER TABLE game_results
  DROP CONSTRAINT IF EXISTS game_results_user_id_game_type_game_id_key;

CREATE UNIQUE INDEX IF NOT EXISTS uniq_game_results_user_game_mode
  ON game_results (user_id, game_type, game_id, mode);
