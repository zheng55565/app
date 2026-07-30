import crypto from 'node:crypto';

import { query, withTransaction } from '../db.js';
import { businessDate } from './adSecurity.js';
import {
  BATTLE_FREEZE_SECONDS,
  BATTLE_ROOM_COUNT,
  BATTLE_ROUND_SECONDS,
  BATTLE_STAKE_OPTIONS,
  BATTLE_SWITCH_SECONDS,
  GAME_STAKE_OPTIONS,
  MICROPOINTS_PER_POINT,
  MINE_CLAIM_COUNT,
  MINE_PACKET_TTL_DAYS,
  MINE_PACKET_TOTAL,
  assertRpsChoice,
  battleEliminatedRooms,
  battleOpponentEntries,
  battleSettlement,
  feeOn,
  match3ChestOutcome,
  match3OddsText,
  mineLiability,
  mineHit,
  pointsText,
  randomRpsChoice,
  redeemableGameBalance,
  rpsOutcome,
  rpsSettlement,
  splitMinePacket,
  stakeMicropoints,
} from './gameRules.js';
import {
  MATCH3_HEIGHT,
  MATCH3_START_MOVES,
  MATCH3_WIDTH,
  createMatch3Board,
  match3Target,
  resolveMatch3Move,
} from './match3Engine.js';
import { creditQuota, debitQuota, findAccountByLinuxdoId } from './stationClient.js';
import { getRuntimeSettings } from './runtimeSettings.js';

const REQUEST_ID_RE = /^[A-Za-z0-9_-]{12,100}$/;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function gameError(code, message, status = 400) {
  const err = new Error(message);
  err.code = code;
  err.status = status;
  return err;
}

function ensureGameEnabled(settings, key, label) {
  if (settings[`${key}_enabled`] === false) {
    throw gameError('GAME_DISABLED', `${label}当前暂停开放`, 503);
  }
}

function battleRuleOptions(settings = {}) {
  return {
    minEliminated: settings.battle_min_eliminated,
    maxEliminated: settings.battle_max_eliminated,
  };
}

function assertRequestId(value) {
  const requestId = String(value || '').trim();
  if (!REQUEST_ID_RE.test(requestId)) throw gameError('INVALID_REQUEST_ID', '请求编号格式无效');
  return requestId;
}

function assertUuid(value, label = '对局') {
  const id = String(value || '').trim();
  if (!UUID_RE.test(id)) throw gameError('INVALID_GAME_ID', `${label}编号无效`);
  return id;
}

function micropointsJson(value) {
  const amount = BigInt(value || 0);
  return { micropoints: amount.toString(), points: pointsText(amount) };
}

async function ensureWallet(client, userId) {
  await client.query(
    `INSERT INTO game_wallets (user_id) VALUES ($1)
     ON CONFLICT (user_id) DO NOTHING`,
    [userId]
  );
}

async function lockWallets(client, userIds) {
  const ids = [...new Set(userIds.map(String))].sort((a, b) => {
    const left = BigInt(a);
    const right = BigInt(b);
    return left < right ? -1 : left > right ? 1 : 0;
  });
  for (const id of ids) await ensureWallet(client, id);
  const { rows } = await client.query(
    `SELECT user_id, balance_micropoints FROM game_wallets
     WHERE user_id = ANY($1::bigint[]) ORDER BY user_id FOR UPDATE`,
    [ids]
  );
  return new Map(rows.map((row) => [String(row.user_id), BigInt(row.balance_micropoints)]));
}

async function applyWalletChange(
  client,
  balances,
  userId,
  amount,
  {
    type,
    gameType = null,
    relatedId = null,
    requestId = null,
    remark = null,
    redeemableDelta = 0n,
  } = {}
) {
  const key = String(userId);
  const delta = BigInt(amount);
  const before = balances.get(key) ?? 0n;
  const after = before + delta;
  if (after < 0n) throw gameError('GAME_POINTS_INSUFFICIENT', '游戏积分不足', 409);
  await client.query(
    `UPDATE game_wallets SET balance_micropoints = $2,
       redeemable_micropoints = LEAST(
         $2::bigint,
         GREATEST(0, redeemable_micropoints + $3::bigint)
       ),
       updated_at = NOW()
     WHERE user_id = $1`,
    [userId, after.toString(), BigInt(redeemableDelta).toString()]
  );
  await client.query(
    `INSERT INTO game_wallet_records
       (id, user_id, amount_micropoints, balance_after_micropoints, type,
        game_type, related_id, request_id, remark)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
    [
      crypto.randomUUID(),
      userId,
      delta.toString(),
      after.toString(),
      type,
      gameType,
      relatedId,
      requestId,
      remark,
    ]
  );
  balances.set(key, after);
  return after;
}

function resultJson(row) {
  return {
    id: row.id,
    game_id: row.game_id,
    game_type: row.game_type,
    mode: row.mode,
    result: row.result,
    stake: pointsText(row.stake_micropoints),
    payout: pointsText(row.payout_micropoints),
    fee: pointsText(row.fee_micropoints),
    net_profit: pointsText(row.net_profit_micropoints),
    detail: row.detail || {},
    created_at: row.created_at,
  };
}

async function existingAction(userId, requestId, gameType, mode) {
  const { rows } = await query(
    `SELECT gr.* FROM game_wallet_records wr
     JOIN game_results gr
       ON gr.user_id = wr.user_id AND gr.game_id = wr.related_id
      AND gr.game_type = $3 AND gr.mode = $4
     WHERE wr.user_id = $1 AND wr.request_id = $2 LIMIT 1`,
    [userId, requestId, gameType, mode]
  );
  return rows[0] ? resultJson(rows[0]) : null;
}

async function insertResult(client, input) {
  const { rows } = await client.query(
    `INSERT INTO game_results
       (id, user_id, game_type, game_id, mode, result, stake_micropoints,
        payout_micropoints, fee_micropoints, net_profit_micropoints, detail)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11::jsonb)
     ON CONFLICT (user_id, game_type, game_id, mode) DO UPDATE SET
       result = EXCLUDED.result,
       stake_micropoints = EXCLUDED.stake_micropoints,
       payout_micropoints = EXCLUDED.payout_micropoints,
       fee_micropoints = EXCLUDED.fee_micropoints,
       net_profit_micropoints = EXCLUDED.net_profit_micropoints,
       detail = EXCLUDED.detail
     RETURNING *`,
    [
      crypto.randomUUID(),
      input.userId,
      input.gameType,
      input.gameId,
      input.mode || 'human',
      input.result,
      BigInt(input.stake || 0).toString(),
      BigInt(input.payout || 0).toString(),
      BigInt(input.fee || 0).toString(),
      BigInt(input.netProfit || 0).toString(),
      JSON.stringify(input.detail || {}),
    ]
  );
  return rows[0];
}

export async function getGameWallet(userId) {
  const { rows } = await query(
    `INSERT INTO game_wallets (user_id) VALUES ($1)
     ON CONFLICT (user_id) DO UPDATE SET user_id = EXCLUDED.user_id
     RETURNING balance_micropoints, redeemable_micropoints,
       total_staked_micropoints,
       total_payout_micropoints`,
    [userId]
  );
  const redeemable = redeemableGameBalance(
    rows[0].balance_micropoints,
    rows[0].redeemable_micropoints
  );
  return {
    balance: pointsText(rows[0].balance_micropoints),
    balance_micropoints: String(rows[0].balance_micropoints),
    total_staked: pointsText(rows[0].total_staked_micropoints),
    total_payout: pointsText(rows[0].total_payout_micropoints),
    redeemable_balance: pointsText(redeemable),
    redeemable_micropoints: redeemable.toString(),
  };
}

export async function convertAiQuotaToGamePoints(user, rawAmount, rawRequestId) {
  const requestId = assertRequestId(rawRequestId);
  const amountPoints = Number(rawAmount);
  if (!Number.isSafeInteger(amountPoints) || amountPoints < 10 || amountPoints > 100000) {
    throw gameError('INVALID_CONVERSION_AMOUNT', '单次兑换必须是10至100000的整数额度');
  }
  const { rows: existingRows } = await query(
    `SELECT * FROM game_conversion_orders WHERE user_id = $1 AND request_id = $2`,
    [user.id, requestId]
  );
  const existing = existingRows[0];
  if (existing?.status === 'completed') {
    return {
      direction: 'ai_to_game',
      converted_points: String(existing.amount_points),
      duplicated: true,
      wallet: await getGameWallet(user.id),
    };
  }
  if (existing) {
    throw gameError(
      'CONVERSION_REVIEW_REQUIRED',
      '该兑换订单状态待核对，请勿重复提交',
      409
    );
  }
  let stationUserId = user.station_user_id;
  if (!stationUserId && user.linuxdo_user_id) {
    const account = await findAccountByLinuxdoId(user.linuxdo_user_id, user.linuxdo_username);
    stationUserId = account?.station_user_id;
  }
  if (!stationUserId) throw gameError('STATION_ACCOUNT_REQUIRED', '本站中转账号未关联', 409);
  const orderId = crypto.randomUUID();
  const amountMicropoints = BigInt(amountPoints) * MICROPOINTS_PER_POINT;
  await query(
    `INSERT INTO game_conversion_orders
       (id,user_id,station_user_id,amount_points,amount_micropoints,request_id,direction)
     VALUES ($1,$2,$3,$4,$5,$6,'ai_to_game')`,
    [orderId, user.id, stationUserId, amountPoints, amountMicropoints.toString(), requestId]
  );
  let debitResult;
  try {
    debitResult = await debitQuota({
      order_no: `game_convert_${orderId}`,
      station_user_id: stationUserId,
      quota: amountPoints,
    });
  } catch (err) {
    const ambiguous = err.code === 'STATION_UNAVAILABLE' || Number(err.status) >= 500;
    await query(
      `UPDATE game_conversion_orders SET status = $2, error_message = $3, updated_at = NOW()
       WHERE id = $1`,
      [orderId, ambiguous ? 'review' : 'failed', String(err.message || '兑换失败').slice(0, 1000)]
    );
    throw err;
  }
  await withTransaction(async (client) => {
    const { rows } = await client.query(
      `SELECT status FROM game_conversion_orders WHERE id = $1 FOR UPDATE`,
      [orderId]
    );
    if (rows[0]?.status === 'completed') return;
    const balances = await lockWallets(client, [user.id]);
    await applyWalletChange(client, balances, user.id, amountMicropoints, {
      type: 'ai_conversion',
      relatedId: orderId,
      remark: `AI额度兑换游戏积分 ${amountPoints}`,
      redeemableDelta: amountMicropoints,
    });
    await client.query(
      `UPDATE game_wallets SET
         ai_converted_in_micropoints=ai_converted_in_micropoints+$2
       WHERE user_id=$1`,
      [user.id, amountMicropoints.toString()]
    );
    await client.query(
      `UPDATE game_conversion_orders SET status='completed', station_transaction_id=$2,
       completed_at=NOW(), updated_at=NOW() WHERE id=$1`,
      [orderId, debitResult.station_transaction_id || null]
    );
  });
  return {
    direction: 'ai_to_game',
    converted_points: String(amountPoints),
    wallet: await getGameWallet(user.id),
  };
}

export async function convertGamePointsToAiQuota(user, rawAmount, rawRequestId) {
  const requestId = assertRequestId(rawRequestId);
  const amountPoints = Number(rawAmount);
  if (!Number.isSafeInteger(amountPoints) || amountPoints < 10 || amountPoints > 100000) {
    throw gameError('INVALID_CONVERSION_AMOUNT', '单次兑换必须是10至100000的整数额度');
  }
  const { rows: existingRows } = await query(
    `SELECT * FROM game_conversion_orders WHERE user_id=$1 AND request_id=$2`,
    [user.id, requestId]
  );
  const existing = existingRows[0];
  if (existing?.status === 'completed') {
    return {
      direction: 'game_to_ai',
      converted_points: String(existing.amount_points),
      duplicated: true,
      wallet: await getGameWallet(user.id),
    };
  }
  if (existing) {
    throw gameError('CONVERSION_REVIEW_REQUIRED', '该兑换订单状态待核对，请勿重复提交', 409);
  }
  let stationUserId = user.station_user_id;
  if (!stationUserId && user.linuxdo_user_id) {
    const account = await findAccountByLinuxdoId(user.linuxdo_user_id, user.linuxdo_username);
    stationUserId = account?.station_user_id;
  }
  if (!stationUserId) throw gameError('STATION_ACCOUNT_REQUIRED', '本站中转账号未关联', 409);

  const orderId = crypto.randomUUID();
  const amountMicropoints = BigInt(amountPoints) * MICROPOINTS_PER_POINT;
  await withTransaction(async (client) => {
    await client.query(
      `INSERT INTO game_conversion_orders
         (id,user_id,station_user_id,amount_points,amount_micropoints,request_id,direction)
       VALUES ($1,$2,$3,$4,$5,$6,'game_to_ai')`,
      [orderId, user.id, stationUserId, amountPoints, amountMicropoints.toString(), requestId]
    );
    const balances = await lockWallets(client, [user.id]);
    const { rows } = await client.query(
      `SELECT balance_micropoints,redeemable_micropoints
       FROM game_wallets WHERE user_id=$1`,
      [user.id]
    );
    const redeemable = redeemableGameBalance(
      rows[0].balance_micropoints,
      rows[0].redeemable_micropoints
    );
    if (redeemable < amountMicropoints) {
      throw gameError(
        'GAME_POINTS_NOT_REDEEMABLE',
        `当前最多可兑回${pointsText(redeemable)}积分，参与过游戏的积分不可兑回AI额度`,
        409
      );
    }
    await applyWalletChange(client, balances, user.id, -amountMicropoints, {
      type: 'ai_conversion_out',
      relatedId: orderId,
      requestId,
      remark: `游戏积分兑回AI额度 ${amountPoints}`,
      redeemableDelta: -amountMicropoints,
    });
    await client.query(
      `UPDATE game_wallets SET
         ai_converted_out_micropoints=ai_converted_out_micropoints+$2
       WHERE user_id=$1`,
      [user.id, amountMicropoints.toString()]
    );
  });

  let creditResult;
  try {
    creditResult = await creditQuota({
      order_no: `game_redeem_${orderId}`,
      station_user_id: stationUserId,
      quota: amountPoints,
    });
  } catch (err) {
    const ambiguous = err.code === 'STATION_UNAVAILABLE' || Number(err.status) >= 500;
    if (ambiguous) {
      await query(
        `UPDATE game_conversion_orders SET status='review',error_message=$2,updated_at=NOW()
         WHERE id=$1`,
        [orderId, String(err.message || '兑回失败').slice(0, 1000)]
      );
    } else {
      await withTransaction(async (client) => {
        const { rows } = await client.query(
          `SELECT status FROM game_conversion_orders WHERE id=$1 FOR UPDATE`,
          [orderId]
        );
        if (rows[0]?.status !== 'pending') return;
        const balances = await lockWallets(client, [user.id]);
        await applyWalletChange(client, balances, user.id, amountMicropoints, {
          type: 'ai_conversion_refund',
          relatedId: orderId,
          remark: '游戏积分兑回AI额度失败退款',
          redeemableDelta: amountMicropoints,
        });
        await client.query(
          `UPDATE game_wallets SET ai_converted_out_micropoints=
             GREATEST(0,ai_converted_out_micropoints-$2) WHERE user_id=$1`,
          [user.id, amountMicropoints.toString()]
        );
        await client.query(
          `UPDATE game_conversion_orders SET status='failed',error_message=$2,updated_at=NOW()
           WHERE id=$1`,
          [orderId, String(err.message || '兑回失败').slice(0, 1000)]
        );
      });
    }
    throw err;
  }

  await query(
    `UPDATE game_conversion_orders SET status='completed',station_transaction_id=$2,
       completed_at=NOW(),updated_at=NOW() WHERE id=$1 AND status='pending'`,
    [orderId, creditResult.station_transaction_id || null]
  );
  return {
    direction: 'game_to_ai',
    converted_points: String(amountPoints),
    wallet: await getGameWallet(user.id),
  };
}

export async function playRps(userId, choice, rawStakePoints, rawRequestId) {
  const gameSettings = await getRuntimeSettings('game');
  ensureGameEnabled(gameSettings, 'rps', '石头剪刀布');
  const requestId = assertRequestId(rawRequestId);
  assertRpsChoice(choice);
  const stake = stakeMicropoints(rawStakePoints, '石头剪刀布积分');
  const duplicate = await existingAction(userId, requestId, 'rps', 'bot');
  if (duplicate) return { ...duplicate, duplicated: true };
  return withTransaction(async (client) => {
    const duplicateRows = await client.query(
      `SELECT 1 FROM game_wallet_records WHERE user_id=$1 AND request_id=$2`,
      [userId, requestId]
    );
    if (duplicateRows.rows.length) throw gameError('ACTION_IN_PROGRESS', '本局正在结算', 409);
    const gameId = crypto.randomUUID();
    const botChoice = randomRpsChoice();
    const outcome = rpsOutcome(choice, botChoice);
    const settlement = rpsSettlement(outcome, stake, gameSettings.rps_payout_basis_points);
    const balances = await lockWallets(client, [userId]);
    await applyWalletChange(client, balances, userId, -stake, {
      type: 'game_stake',
      gameType: 'rps',
      relatedId: gameId,
      requestId,
      remark: `石头剪刀布投入${pointsText(stake)}积分`,
      redeemableDelta: -stake,
    });
    if (settlement.payout > 0n) {
      await applyWalletChange(client, balances, userId, settlement.payout, {
        type: outcome === 'draw' ? 'game_refund' : 'game_payout',
        gameType: 'rps',
        relatedId: gameId,
        remark: outcome === 'draw'
          ? `石头剪刀布平局退回${pointsText(stake)}积分`
          : `石头剪刀布获胜到账${pointsText(settlement.payout)}积分`,
      });
    }
    await client.query(
      `UPDATE game_wallets SET
         total_staked_micropoints = total_staked_micropoints + $2,
         total_payout_micropoints = total_payout_micropoints + $3
       WHERE user_id=$1`,
      [userId, stake.toString(), settlement.payout.toString()]
    );
    const row = await insertResult(client, {
      userId,
      gameType: 'rps',
      gameId,
      mode: 'bot',
      result: outcome,
      stake: settlement.stake,
      payout: settlement.payout,
      fee: settlement.fee,
      netProfit: settlement.netProfit,
      detail: {
        user_choice: choice,
        bot_choice: botChoice,
        stake_points: pointsText(stake),
        odds: (gameSettings.rps_payout_basis_points / 10000).toFixed(2),
        rules_snapshot: { ...gameSettings },
      },
    });
    return { ...resultJson(row), wallet_balance: pointsText(balances.get(String(userId))) };
  });
}

function packetJson(row) {
  const claims = Array.isArray(row.claims)
    ? row.claims.map((claim) => ({
        username: claim.username || '用户',
        amount: pointsText(claim.amount_micropoints || 0),
        hit: claim.hit === true,
        claimed_by_me: claim.claimed_by_me === true,
        claimed_at: claim.claimed_at,
      }))
    : [];
  return {
    id: row.id,
    creator_user_id: String(row.creator_user_id),
    creator_name: row.creator_name || '用户',
    mine_digit: Number(row.mine_digit),
    total: pointsText(row.total_micropoints),
    liability: pointsText(row.liability_micropoints),
    claimed_count: Number(row.claimed_count),
    claim_count: Number(row.claim_count),
    status: row.status,
    expires_at: row.expires_at,
    created_at: row.created_at,
    claims,
  };
}

export async function createMinePacket(
  userId,
  installHash,
  rawDigit,
  rawTotalPoints,
  rawRequestId
) {
  const gameSettings = await getRuntimeSettings('game');
  ensureGameEnabled(gameSettings, 'mine', '扫雷红包');
  // 兼容旧服务调用 createMinePacket(userId, installHash, digit, requestId)。
  if (rawRequestId == null) {
    rawRequestId = rawTotalPoints;
    rawTotalPoints = GAME_STAKE_OPTIONS[0];
  }
  const requestId = assertRequestId(rawRequestId);
  const digit = Number(rawDigit);
  if (!Number.isInteger(digit) || digit < 0 || digit > 9) {
    throw gameError('INVALID_MINE_DIGIT', '雷号必须是0至9');
  }
  const total = stakeMicropoints(rawTotalPoints, '红包积分');
  const liability = mineLiability(total, gameSettings.mine_liability_basis_points);
  const { rows: duplicate } = await query(
    `SELECT p.*, u.username AS creator_name FROM game_wallet_records wr
     JOIN game_mine_packets p ON p.id=wr.related_id
     JOIN users u ON u.id=p.creator_user_id
     WHERE wr.user_id=$1 AND wr.request_id=$2 LIMIT 1`,
    [userId, requestId]
  );
  if (duplicate[0]) return { ...packetJson(duplicate[0]), duplicated: true };
  return withTransaction(async (client) => {
    const packetId = crypto.randomUUID();
    const balances = await lockWallets(client, [userId]);
    await applyWalletChange(client, balances, userId, -total, {
      type: 'game_stake',
      gameType: 'mine',
      relatedId: packetId,
      requestId,
      remark: `创建${pointsText(total)}积分扫雷红包`,
      redeemableDelta: -total,
    });
    const { rows } = await client.query(
      `INSERT INTO game_mine_packets
         (id,creator_user_id,creator_install_hash,mine_digit,total_micropoints,
          liability_micropoints,rules_snapshot,expires_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7::jsonb,NOW()+($8::int * INTERVAL '1 day')) RETURNING *`,
      [
        packetId,
        userId,
        installHash,
        digit,
        total.toString(),
        liability.toString(),
        JSON.stringify(gameSettings),
        MINE_PACKET_TTL_DAYS,
      ]
    );
    const shares = splitMinePacket(total);
    for (let index = 0; index < shares.length; index++) {
      await client.query(
        `INSERT INTO game_mine_shares (packet_id,slot,amount_micropoints)
         VALUES ($1,$2,$3)`,
        [packetId, index + 1, shares[index].toString()]
      );
    }
    await client.query(
      `UPDATE game_wallets SET total_staked_micropoints=total_staked_micropoints+$2
       WHERE user_id=$1`,
      [userId, total.toString()]
    );
    return { ...packetJson({ ...rows[0], creator_name: '我' }), wallet_balance: pointsText(balances.get(String(userId))) };
  });
}

async function finalizeMineCreator(client, packet, refund = 0n) {
  const payout = BigInt(packet.creator_payout_micropoints || 0) + refund;
  const net = payout - BigInt(packet.total_micropoints);
  const result = net > 0n ? 'win' : net < 0n ? 'loss' : 'draw';
  const { rows: claims } = await client.query(
    `SELECT u.username,s.amount_micropoints,s.is_mine,s.claimed_at
     FROM game_mine_shares s
     JOIN users u ON u.id=s.claimed_by_user_id
     WHERE s.packet_id=$1 AND s.claimed_by_user_id IS NOT NULL
     ORDER BY s.claimed_at ASC`,
    [packet.id]
  );
  await insertResult(client, {
    userId: packet.creator_user_id,
    gameType: 'mine',
    gameId: packet.id,
    mode: 'creator',
    result,
    stake: packet.total_micropoints,
    payout,
    fee: packet.platform_fee_micropoints,
    netProfit: net,
    detail: {
      role: 'creator',
      mine_digit: Number(packet.mine_digit),
      claimed_count: Number(packet.claimed_count),
      claims: claims.map((claim) => ({
        username: claim.username,
        amount: pointsText(claim.amount_micropoints),
        hit: claim.is_mine === true,
        claimed_at: claim.claimed_at,
      })),
    },
  });
}

export async function expireMinePackets() {
  const { rows } = await query(
    `SELECT id FROM game_mine_packets
     WHERE status='open' AND expires_at <= NOW() ORDER BY expires_at LIMIT 100`
  );
  for (const item of rows) {
    await withTransaction(async (client) => {
      const { rows: packets } = await client.query(
        `SELECT * FROM game_mine_packets
         WHERE id=$1 AND status='open' AND expires_at <= NOW() FOR UPDATE`,
        [item.id]
      );
      const packet = packets[0];
      if (!packet) return;
      const { rows: unclaimed } = await client.query(
        `SELECT COALESCE(SUM(amount_micropoints),0) AS refund
         FROM game_mine_shares WHERE packet_id=$1 AND claimed_by_user_id IS NULL`,
        [packet.id]
      );
      const refund = BigInt(unclaimed[0].refund);
      const balances = await lockWallets(client, [packet.creator_user_id]);
      if (refund > 0n) {
        await applyWalletChange(client, balances, packet.creator_user_id, refund, {
          type: 'game_refund',
          gameType: 'mine',
          relatedId: packet.id,
          remark: '扫雷红包未抢完退款',
        });
      }
      packet.creator_payout_micropoints = (
        BigInt(packet.creator_payout_micropoints) + refund
      ).toString();
      await client.query(
        `UPDATE game_mine_packets SET status='expired', completed_at=NOW(),
         creator_payout_micropoints=$2 WHERE id=$1`,
        [packet.id, packet.creator_payout_micropoints]
      );
      await finalizeMineCreator(client, packet, 0n);
    });
  }
}

export async function listOpenMinePackets(userId) {
  await expireMinePackets();
  const { rows } = await query(
    `WITH visible AS (
       SELECT DISTINCT ON (id) id,bucket FROM (
         SELECT p.id,0 AS bucket FROM game_mine_packets p
         WHERE p.status='open' AND p.expires_at>NOW()
         UNION ALL
         SELECT recent.id,1 AS bucket FROM (
           SELECT p.id,p.created_at FROM game_mine_packets p
           WHERE p.creator_user_id=$1 OR EXISTS(
             SELECT 1 FROM game_mine_shares mine
             WHERE mine.packet_id=p.id AND mine.claimed_by_user_id=$1
           )
           ORDER BY p.created_at DESC LIMIT 2
         ) recent
       ) candidates ORDER BY id,bucket
     )
     SELECT p.*,u.username AS creator_name,
       EXISTS(SELECT 1 FROM game_mine_shares s
              WHERE s.packet_id=p.id AND s.claimed_by_user_id=$1) AS already_claimed,
       COALESCE((
         SELECT jsonb_agg(
           jsonb_build_object(
             'username',claimant.username,
             'amount_micropoints',s.amount_micropoints::text,
             'hit',COALESCE(s.is_mine,false),
             'claimed_by_me',s.claimed_by_user_id=$1,
             'claimed_at',s.claimed_at
           ) ORDER BY s.claimed_at ASC
         )
         FROM game_mine_shares s
         JOIN users claimant ON claimant.id=s.claimed_by_user_id
         WHERE s.packet_id=p.id AND s.claimed_by_user_id IS NOT NULL
       ),'[]'::jsonb) AS claims
     FROM visible v
     JOIN game_mine_packets p ON p.id=v.id
     JOIN users u ON u.id=p.creator_user_id
     ORDER BY v.bucket ASC,
       CASE WHEN p.status='open' THEN p.created_at END ASC,
       p.created_at DESC LIMIT 32`,
    [userId]
  );
  return rows.map((row) => ({
    ...packetJson(row),
    already_claimed: row.already_claimed,
    is_creator: String(row.creator_user_id) === String(userId),
  }));
}

export async function grabMinePacket(userId, installHash, rawPacketId, rawRequestId) {
  const currentSettings = await getRuntimeSettings('game');
  ensureGameEnabled(currentSettings, 'mine', '扫雷红包');
  const packetId = assertUuid(rawPacketId, '红包');
  const requestId = assertRequestId(rawRequestId);
  const duplicate = await existingAction(userId, requestId, 'mine', 'claimant');
  if (duplicate) {
    const wallet = await getGameWallet(userId);
    return {
      ...duplicate,
      amount: duplicate.detail?.amount || duplicate.payout,
      hit: duplicate.detail?.hit === true,
      wallet_balance: wallet.balance,
      duplicated: true,
    };
  }
  return withTransaction(async (client) => {
    const { rows: packets } = await client.query(
      `SELECT * FROM game_mine_packets
       WHERE id=$1 AND status='open' AND expires_at > NOW() FOR UPDATE`,
      [packetId]
    );
    const packet = packets[0];
    if (!packet) {
      throw gameError('MINE_PACKET_CLOSED', '红包已抢完或已过期', 409);
    }
    const isCreator = String(packet.creator_user_id) === String(userId);
    if (!isCreator && packet.creator_install_hash === installHash) {
      throw gameError('MINE_DEVICE_CONFLICT', '同一设备不能参与该红包', 409);
    }
    const { rows: claimed } = await client.query(
      `SELECT claimed_by_user_id,claimant_install_hash FROM game_mine_shares
       WHERE packet_id=$1 AND (claimed_by_user_id=$2 OR claimant_install_hash=$3)`,
      [packetId, userId, installHash]
    );
    if (claimed.some((item) => String(item.claimed_by_user_id) === String(userId))) {
      throw gameError('MINE_ALREADY_CLAIMED', '每人每个红包只能抢一次', 409);
    }
    if (claimed.length) {
      throw gameError('MINE_DEVICE_ALREADY_CLAIMED', '同一设备每个红包只能参与一次', 409);
    }
    const { rows: available } = await client.query(
      `SELECT slot,amount_micropoints FROM game_mine_shares
       WHERE packet_id=$1 AND claimed_by_user_id IS NULL ORDER BY slot FOR UPDATE`,
      [packetId]
    );
    if (!available.length) throw gameError('MINE_PACKET_CLOSED', '红包已抢完', 409);
    const selected = available[crypto.randomInt(0, available.length)];
    const amount = BigInt(selected.amount_micropoints);
    const hit = mineHit(amount, packet.mine_digit);
    const liability = BigInt(packet.liability_micropoints);
    const rules = packet.rules_snapshot || currentSettings;
    const fee = hit ? feeOn(liability, rules.mine_fee_basis_points ?? 1000) : 0n;
    const creatorPayout = liability - fee;
    const balances = await lockWallets(client, [userId, packet.creator_user_id]);
    if ((balances.get(String(userId)) || 0n) < liability) {
      throw gameError(
        'MINE_LIABILITY_INSUFFICIENT',
        `至少需要${pointsText(liability)}游戏积分才能抢该红包`,
        409
      );
    }
    const claimantNet = amount - (hit ? liability : 0n);
    await applyWalletChange(client, balances, userId, claimantNet, {
      type: hit ? 'mine_hit' : 'mine_claim',
      gameType: 'mine',
      relatedId: packetId,
      requestId,
      remark: hit ? `扫雷红包中雷，赔付${pointsText(liability)}积分` : '扫雷红包领取',
      redeemableDelta: hit ? -liability : 0n,
    });
    if (hit) {
      await applyWalletChange(client, balances, packet.creator_user_id, creatorPayout, {
        type: 'mine_compensation',
        gameType: 'mine',
        relatedId: packetId,
        remark: `扫雷赔付到账${pointsText(creatorPayout)}积分`,
      });
    }
    const { rows: assigned } = await client.query(
      `UPDATE game_mine_shares SET claimed_by_user_id=$3,claimant_install_hash=$4,
       is_mine=$5,compensation_micropoints=$6,fee_micropoints=$7,claimed_at=NOW()
       WHERE packet_id=$1 AND slot=$2 AND claimed_by_user_id IS NULL
         AND NOT EXISTS (
           SELECT 1 FROM game_mine_shares previous
           WHERE previous.packet_id=$1
             AND (previous.claimed_by_user_id=$3 OR previous.claimant_install_hash=$4)
         )
       RETURNING slot`,
      [
        packetId,
        selected.slot,
        userId,
        installHash,
        hit,
        hit ? liability.toString() : '0',
        fee.toString(),
      ]
    );
    if (!assigned.length) {
      throw gameError('MINE_ALREADY_CLAIMED', '每人每个红包只能抢一次', 409);
    }
    const claimedCount = Number(packet.claimed_count) + 1;
    const accumulatedCreatorPayout =
      BigInt(packet.creator_payout_micropoints) + (hit ? creatorPayout : 0n);
    const platformFee = BigInt(packet.platform_fee_micropoints) + fee;
    const completed = claimedCount >= MINE_CLAIM_COUNT;
    await client.query(
      `UPDATE game_mine_packets SET claimed_count=$2,creator_payout_micropoints=$3,
       platform_fee_micropoints=$4,status=$5,completed_at=CASE WHEN $6 THEN NOW() ELSE NULL END
       WHERE id=$1`,
      [packetId, claimedCount, accumulatedCreatorPayout.toString(), platformFee.toString(), completed ? 'completed' : 'open', completed]
    );
    const row = await insertResult(client, {
      userId,
      gameType: 'mine',
      gameId: packetId,
      mode: 'claimant',
      result: hit ? 'loss' : 'claimed',
      stake: hit ? liability : 0n,
      payout: amount,
      fee,
      netProfit: claimantNet,
      detail: {
        role: 'claimant',
        amount: pointsText(amount),
        packet_total: pointsText(packet.total_micropoints),
        liability: pointsText(liability),
        mine_digit: Number(packet.mine_digit),
        hit,
      },
    });
    if (completed) {
      packet.claimed_count = claimedCount;
      packet.creator_payout_micropoints = accumulatedCreatorPayout.toString();
      packet.platform_fee_micropoints = platformFee.toString();
      await finalizeMineCreator(client, packet);
    }
    return {
      ...resultJson(row),
      amount: pointsText(amount),
      hit,
      claimed_count: claimedCount,
      wallet_balance: pointsText(balances.get(String(userId))),
    };
  });
}

async function createBattleRound(client, gameSettings) {
  const id = crypto.randomUUID();
  const seed = crypto.randomBytes(32).toString('hex');
  const commit = crypto.createHash('sha256').update(`${seed}:${id}`).digest('hex');
  const opponents = battleOpponentEntries(seed, id, {
    minCount: gameSettings.battle_opponent_min_count,
    maxCount: gameSettings.battle_opponent_max_count,
    minStake: gameSettings.battle_opponent_min_stake,
    maxStake: gameSettings.battle_opponent_max_stake,
  }).map((entry) => ({
    id: entry.id,
    room_no: entry.roomNo,
    stake_micropoints: entry.stake.toString(),
  }));
  const { rows } = await client.query(
    `INSERT INTO game_battle_rounds
       (id,rng_seed_hex,rng_commit,opponent_entries,rules_snapshot,closes_at)
     VALUES ($1,$2,$3,$4::jsonb,$5::jsonb,NOW()+($6 * INTERVAL '1 second')) RETURNING *`,
    [id, seed, commit, JSON.stringify(opponents), JSON.stringify(gameSettings), BATTLE_ROUND_SECONDS]
  );
  return rows[0];
}

async function settleBattleRound(roundId) {
  return withTransaction(async (client) => {
    const { rows: rounds } = await client.query(
      `SELECT * FROM game_battle_rounds WHERE id=$1 FOR UPDATE`,
      [roundId]
    );
    const round = rounds[0];
    if (!round || round.status !== 'betting' || new Date(round.closes_at) > new Date()) return false;
    const { rows: entries } = await client.query(
      `SELECT * FROM game_battle_entries WHERE round_id=$1 ORDER BY id FOR UPDATE`,
      [round.id]
    );
    const opponentEntries = (round.opponent_entries || []).map((entry) => ({
      id: entry.id,
      roomNo: Number(entry.room_no),
      stake: BigInt(entry.stake_micropoints),
      opponent: true,
    }));
    const rules = round.rules_snapshot || {};
    const eliminated = battleEliminatedRooms(
      round.rng_seed_hex,
      round.id,
      battleRuleOptions(rules)
    );
    const settlement = battleSettlement(
      [
        ...entries.map((entry) => ({
          ...entry,
          roomNo: entry.room_no,
          stake: entry.stake_micropoints,
          opponent: false,
        })),
        ...opponentEntries,
      ],
      eliminated,
      rules.battle_fee_basis_points ?? 1000
    );
    const balances = await lockWallets(client, entries.map((entry) => entry.user_id));
    for (const settled of settlement.entries) {
      if (settled.opponent) continue;
      if (settled.payout > 0n) {
        await applyWalletChange(client, balances, settled.user_id, settled.payout, {
          type: settled.result === 'refund' ? 'game_refund' : 'game_payout',
          gameType: 'battle',
          relatedId: round.id,
          remark: settled.result === 'refund' ? '八房生存局异常退款' : '八房生存局结算',
        });
      }
      const stake = BigInt(settled.stake);
      const net = settled.payout - stake;
      await client.query(
        `UPDATE game_battle_entries
         SET payout_micropoints=$2,fee_micropoints=$3,result=$4 WHERE id=$1`,
        [settled.id, settled.payout.toString(), settled.fee.toString(), settled.result]
      );
      await client.query(
        `UPDATE game_wallets SET total_payout_micropoints=total_payout_micropoints+$2
         WHERE user_id=$1`,
        [settled.user_id, settled.payout.toString()]
      );
      await insertResult(client, {
        userId: settled.user_id,
        gameType: 'battle',
        gameId: round.id,
        result: settled.result,
        stake,
        payout: settled.payout,
        fee: settled.fee,
        netProfit: net,
        detail: {
          room_no: settled.roomNo,
          eliminated_rooms: eliminated,
          winning_stake_micropoints: settlement.entries
            .filter((item) => item.result === 'win')
            .reduce((sum, item) => sum + BigInt(item.stake), 0n)
            .toString(),
          includes_opponents: true,
        },
      });
    }
    const roomTotals = Array.from({ length: BATTLE_ROOM_COUNT }, (_, index) => {
      const roomNo = index + 1;
      const roomEntries = settlement.entries.filter((entry) => entry.roomNo === roomNo);
      return {
        room_no: roomNo,
        players: roomEntries.length,
        stake_micropoints: roomEntries
          .reduce((sum, entry) => sum + BigInt(entry.stake), 0n)
          .toString(),
      };
    });
    await client.query(
      `UPDATE game_battle_rounds SET status=$2,eliminated_rooms=$3,
       losing_pool_micropoints=$4,distributable_micropoints=$5,
       platform_fee_micropoints=$6,room_totals=$7::jsonb,settled_at=NOW() WHERE id=$1`,
      [
        round.id,
        settlement.refunded ? 'refunded' : 'settled',
        eliminated,
        settlement.losingPool.toString(),
        settlement.distributable.toString(),
        settlement.fee.toString(),
        JSON.stringify(roomTotals),
      ]
    );
    return true;
  });
}

export async function settleDueBattleRounds() {
  const { rows } = await query(
    `SELECT id FROM game_battle_rounds
     WHERE status='betting' AND closes_at<=NOW() ORDER BY closes_at LIMIT 10`
  );
  for (const round of rows) await settleBattleRound(round.id);
}

export async function getBattleState(userId) {
  const gameSettings = await getRuntimeSettings('game');
  await settleDueBattleRounds();
  let { rows } = await query(
    `SELECT * FROM game_battle_rounds WHERE status='betting' AND closes_at>NOW()
     ORDER BY created_at DESC LIMIT 1`
  );
  let round = rows[0];
  if (!round) {
    round = await withTransaction(async (client) => {
      await client.query(`SELECT pg_advisory_xact_lock(hashtext('game_battle_round_create_v1'))`);
      const locked = await client.query(
        `SELECT * FROM game_battle_rounds WHERE status='betting' AND closes_at>NOW()
         ORDER BY created_at DESC LIMIT 1 FOR UPDATE`
      );
      return locked.rows[0] || createBattleRound(client, gameSettings);
    });
  }
  const { rows: entries } = await query(
    `SELECT room_no,COUNT(*)::int AS players,COALESCE(SUM(stake_micropoints),0) AS stake,
       BOOL_OR(user_id=$2) AS joined,
       MAX(stake_micropoints) FILTER (WHERE user_id=$2) AS user_stake
     FROM game_battle_entries WHERE round_id=$1 GROUP BY room_no ORDER BY room_no`,
    [round.id, userId]
  );
  const opponents = Array.isArray(round.opponent_entries) ? round.opponent_entries : [];
  const rooms = Array.from({ length: BATTLE_ROOM_COUNT }, (_, index) => {
    const roomNo = index + 1;
    const item = entries.find((entry) => Number(entry.room_no) === roomNo);
    const roomOpponents = opponents.filter((entry) => Number(entry.room_no) === roomNo);
    const opponentStake = roomOpponents.reduce(
      (sum, entry) => sum + BigInt(entry.stake_micropoints || 0),
      0n
    );
    return {
      room_no: roomNo,
      players: Number(item?.players || 0) + roomOpponents.length,
      opponents: roomOpponents.length,
      total_stake: pointsText(BigInt(item?.stake || 0) + opponentStake),
      joined: item?.joined === true,
      user_stake: item?.user_stake == null ? null : pointsText(item.user_stake),
    };
  });
  const { rows: issueRows } = await query(
    `SELECT COUNT(*)::bigint AS issue_no FROM game_battle_rounds
     WHERE created_at < $1 OR (created_at = $1 AND id::text <= $2)`,
    [round.created_at, round.id]
  );
  const issueNo = Number(issueRows[0]?.issue_no || 1);
  const { rows: previous } = await query(
    `WITH ranked AS (
       SELECT source.*,
         ROW_NUMBER() OVER (ORDER BY source.created_at ASC,source.id::text ASC)::bigint AS issue_no
       FROM game_battle_rounds source
     )
     SELECT r.id,r.issue_no,r.status,r.rng_seed_hex,r.rng_commit,r.eliminated_rooms,
       r.room_totals,r.settled_at,gr.result AS user_result,
       gr.net_profit_micropoints AS user_net_profit,gr.detail AS user_detail
     FROM ranked r
     LEFT JOIN game_results gr ON gr.game_type='battle' AND gr.game_id=r.id
       AND gr.user_id=$1
     WHERE r.status IN ('settled','refunded')
     ORDER BY r.settled_at DESC LIMIT 10`,
    [userId]
  );
  const freezeAt = new Date(
    new Date(round.closes_at).getTime() - BATTLE_FREEZE_SECONDS * 1000
  );
  const switchUntil = new Date(
    new Date(round.created_at).getTime() + BATTLE_SWITCH_SECONDS * 1000
  );
  const frozen = freezeAt <= new Date();
  return {
    id: round.id,
    issue_no: issueNo,
    status: round.status,
    rng_commit: round.rng_commit,
    closes_at: round.closes_at,
    freeze_at: freezeAt,
    switch_until: switchUntil,
    can_switch: !frozen && switchUntil > new Date(),
    frozen,
    eliminated_rooms: frozen
      ? battleEliminatedRooms(
          round.rng_seed_hex,
          round.id,
          battleRuleOptions(round.rules_snapshot || gameSettings)
        )
      : [],
    rooms,
    recent_rounds: previous.map((item) => ({
      id: item.id,
      issue_no: Number(item.issue_no),
      status: item.status,
      eliminated_rooms: item.eliminated_rooms || [],
      surviving_rooms: Array.from({ length: BATTLE_ROOM_COUNT }, (_, index) => index + 1)
        .filter((roomNo) => !(item.eliminated_rooms || []).map(Number).includes(roomNo)),
      room_totals: item.room_totals || [],
      rng_seed: item.rng_seed_hex,
      rng_commit: item.rng_commit,
      settled_at: item.settled_at,
      user_result: item.user_result || null,
      user_net_profit: pointsText(item.user_net_profit || 0),
      user_room_no: item.user_detail?.room_no || null,
    })),
    previous: previous[0]
      ? {
          id: previous[0].id,
          issue_no: Number(previous[0].issue_no),
          status: previous[0].status,
          eliminated_rooms: previous[0].eliminated_rooms || [],
          rng_seed: previous[0].rng_seed_hex,
          rng_commit: previous[0].rng_commit,
          settled_at: previous[0].settled_at,
        }
      : null,
  };
}

export async function joinBattleRound(
  userId,
  installHash,
  rawRoundId,
  rawRoomNo,
  rawStakePoints,
  rawRequestId
) {
  const gameSettings = await getRuntimeSettings('game');
  ensureGameEnabled(gameSettings, 'battle', '八房生存局');
  const roundId = assertUuid(rawRoundId, '回合');
  const requestId = assertRequestId(rawRequestId);
  const roomNo = Number(rawRoomNo);
  const stakePoints = Number(rawStakePoints);
  if (!Number.isInteger(roomNo) || roomNo < 1 || roomNo > BATTLE_ROOM_COUNT) {
    throw gameError('INVALID_BATTLE_ROOM', '请选择1至8号房间');
  }
  if (
    !Number.isSafeInteger(stakePoints) ||
    (stakePoints !== 0 && !BATTLE_STAKE_OPTIONS.includes(stakePoints))
  ) {
    throw gameError('INVALID_BATTLE_STAKE', '每次追加只能选择1、10或50积分');
  }
  const stake = BigInt(stakePoints) * MICROPOINTS_PER_POINT;
  return withTransaction(async (client) => {
    const { rows: rounds } = await client.query(
      `SELECT * FROM game_battle_rounds WHERE id=$1 FOR UPDATE`,
      [roundId]
    );
    const round = rounds[0];
    const freezeAt = round
      ? new Date(new Date(round.closes_at).getTime() - BATTLE_FREEZE_SECONDS * 1000)
      : null;
    if (!round || round.status !== 'betting' || freezeAt <= new Date()) {
      throw gameError('BATTLE_BETTING_CLOSED', '本轮已经封盘，不能切换或追加', 409);
    }
    const { rows: duplicate } = await client.query(
      `SELECT id,user_id,install_hash,room_no,stake_micropoints FROM game_battle_entries
       WHERE round_id=$1 AND (user_id=$2 OR install_hash=$3)`,
      [roundId, userId, installHash]
    );
    const userEntry = duplicate.find(
      (item) => String(item.user_id) === String(userId)
    );
    if (userEntry) {
      const { rows: repeatedActions } = await client.query(
        `SELECT 1 FROM game_wallet_records
         WHERE user_id=$1 AND request_id=$2 AND related_id=$3 LIMIT 1`,
        [userId, requestId, roundId]
      );
      if (repeatedActions.length) {
        const { rows: wallets } = await client.query(
          `SELECT balance_micropoints FROM game_wallets WHERE user_id=$1`,
          [userId]
        );
        return {
          round_id: roundId,
          room_no: Number(userEntry.room_no),
          stake: pointsText(userEntry.stake_micropoints),
          added_stake: String(stakePoints),
          duplicated: true,
          wallet_balance: pointsText(wallets[0]?.balance_micropoints || 0),
          closes_at: round.closes_at,
        };
      }
      const switchUntil = new Date(
        new Date(round.created_at).getTime() + BATTLE_SWITCH_SECONDS * 1000
      );
      const switchingRoom = Number(userEntry.room_no) !== roomNo;
      if (switchingRoom && switchUntil <= new Date()) {
        throw gameError('BATTLE_SWITCH_CLOSED', '开局前20秒已结束，不能再切换房间', 409);
      }
      if (stakePoints === 0) {
        if (switchingRoom) {
          await client.query(
            `UPDATE game_battle_entries SET room_no=$2 WHERE id=$1`,
            [userEntry.id, roomNo]
          );
        }
        const { rows: wallets } = await client.query(
          `SELECT balance_micropoints FROM game_wallets WHERE user_id=$1`,
          [userId]
        );
        return {
          round_id: roundId,
          room_no: roomNo,
          stake: pointsText(userEntry.stake_micropoints),
          added_stake: '0',
          switched: switchingRoom,
          wallet_balance: pointsText(wallets[0]?.balance_micropoints || 0),
          closes_at: round.closes_at,
          switch_until: switchUntil,
        };
      }
      const balances = await lockWallets(client, [userId]);
      await applyWalletChange(client, balances, userId, -stake, {
        type: 'game_stake',
        gameType: 'battle',
        relatedId: roundId,
        requestId,
        remark: `八房生存局${roomNo}号房追加${stakePoints}积分`,
        redeemableDelta: -stake,
      });
      const totalStake = BigInt(userEntry.stake_micropoints) + stake;
      await client.query(
        `UPDATE game_battle_entries
         SET room_no=$2,stake_micropoints=$3 WHERE id=$1`,
        [userEntry.id, roomNo, totalStake.toString()]
      );
      await client.query(
        `UPDATE game_wallets SET total_staked_micropoints=total_staked_micropoints+$2
         WHERE user_id=$1`,
        [userId, stake.toString()]
      );
      return {
        round_id: roundId,
        room_no: roomNo,
        stake: pointsText(totalStake),
        added_stake: String(stakePoints),
        switched: switchingRoom,
        wallet_balance: pointsText(balances.get(String(userId))),
        closes_at: round.closes_at,
        switch_until: switchUntil,
      };
    }
    if (duplicate.length) {
      throw gameError('BATTLE_DEVICE_ALREADY_JOINED', '同一设备每回合只能参与一次', 409);
    }
    if (stakePoints === 0) {
      throw gameError('BATTLE_STAKE_REQUIRED', '首次选房请先选择1、10或50积分', 409);
    }
    const balances = await lockWallets(client, [userId]);
    const entryId = crypto.randomUUID();
    await applyWalletChange(client, balances, userId, -stake, {
      type: 'game_stake',
      gameType: 'battle',
      relatedId: roundId,
      requestId,
      remark: `八房生存局选择${roomNo}号房`,
      redeemableDelta: -stake,
    });
    await client.query(
      `INSERT INTO game_battle_entries
       (id,round_id,user_id,install_hash,room_no,stake_micropoints)
       VALUES ($1,$2,$3,$4,$5,$6)`,
      [entryId, roundId, userId, installHash, roomNo, stake.toString()]
    );
    await client.query(
      `UPDATE game_wallets SET total_staked_micropoints=total_staked_micropoints+$2
       WHERE user_id=$1`,
      [userId, stake.toString()]
    );
    return {
      round_id: roundId,
      room_no: roomNo,
      stake: String(stakePoints),
      added_stake: String(stakePoints),
      wallet_balance: pointsText(balances.get(String(userId))),
      closes_at: round.closes_at,
    };
  });
}

function match3SessionJson(row) {
  if (!row) return null;
  return {
    id: row.id,
    level_no: Number(row.level_no),
    status: row.status,
    width: MATCH3_WIDTH,
    height: MATCH3_HEIGHT,
    board: row.board,
    score: Number(row.score),
    target_score: Number(row.target_score),
    moves_left: Number(row.moves_left),
    recovery_count: Number(row.recovery_count),
    updated_at: row.updated_at,
  };
}

export async function getMatch3State(userId) {
  const gameSettings = await getRuntimeSettings('game');
  const [progressRows, sessionRows, chestRows] = await Promise.all([
    query(
      `SELECT COALESCE(MAX(level_no),0)::int AS completed_level
       FROM game_match3_level_rewards WHERE user_id=$1`,
      [userId]
    ),
    query(
      `SELECT * FROM game_match3_sessions WHERE user_id=$1 AND status IN ('active','failed')
       ORDER BY CASE WHEN status='active' THEN 0 ELSE 1 END,updated_at DESC LIMIT 1`,
      [userId]
    ),
    query(
      `SELECT reward.level_no AS milestone, session.rules_snapshot
       FROM game_match3_level_rewards reward
       JOIN game_match3_sessions session ON session.id=reward.session_id
       WHERE reward.user_id=$1 AND reward.level_no % 10=0 AND NOT EXISTS(
         SELECT 1 FROM game_match3_chests c
         WHERE c.user_id=$1 AND c.milestone_level=reward.level_no
       ) ORDER BY reward.level_no LIMIT 1`,
      [userId]
    ),
  ]);
  const completedLevel = Number(progressRows.rows[0]?.completed_level || 0);
  const chestRules = Object.keys(chestRows.rows[0]?.rules_snapshot || {}).length
    ? chestRows.rows[0].rules_snapshot
    : gameSettings;
  return {
    completed_level: completedLevel,
    next_level: completedLevel + 1,
    session: match3SessionJson(sessionRows.rows[0]),
    chest_available: chestRows.rows[0]?.milestone || null,
    chest_odds: match3OddsText(chestRules),
  };
}

export async function startMatch3Level(userId, rawLevelNo) {
  const gameSettings = await getRuntimeSettings('game');
  ensureGameEnabled(gameSettings, 'match3', '宝石消消乐');
  const requestedLevel = Number(rawLevelNo || 0);
  return withTransaction(async (client) => {
    await ensureWallet(client, userId);
    await client.query(`SELECT user_id FROM game_wallets WHERE user_id=$1 FOR UPDATE`, [userId]);
    const active = await client.query(
      `SELECT * FROM game_match3_sessions WHERE user_id=$1 AND status='active'
       ORDER BY updated_at DESC LIMIT 1 FOR UPDATE`,
      [userId]
    );
    if (active.rows[0]) return { session: match3SessionJson(active.rows[0]), resumed: true };
    await client.query(
      `UPDATE game_recovery_ad_tasks SET status='expired',updated_at=NOW()
       WHERE user_id=$1 AND status IN ('created','verified')`,
      [userId]
    );
    const progress = await client.query(
      `SELECT COALESCE(MAX(level_no),0)::int AS completed_level
       FROM game_match3_level_rewards WHERE user_id=$1`,
      [userId]
    );
    const levelNo = Number(progress.rows[0].completed_level) + 1;
    if (requestedLevel && requestedLevel !== levelNo) {
      throw gameError('MATCH3_LEVEL_LOCKED', `请先完成第${levelNo}关`, 409);
    }
    const id = crypto.randomUUID();
    const board = createMatch3Board(`${id}:${userId}:${levelNo}`);
    const { rows } = await client.query(
      `INSERT INTO game_match3_sessions
       (id,user_id,level_no,board,target_score,moves_left,rules_snapshot)
       VALUES ($1,$2,$3,$4::jsonb,$5,$6,$7::jsonb) RETURNING *`,
      [
        id,
        userId,
        levelNo,
        JSON.stringify(board),
        match3Target(levelNo),
        MATCH3_START_MOVES,
        JSON.stringify(gameSettings),
      ]
    );
    return { session: match3SessionJson(rows[0]), resumed: false };
  });
}

export async function moveMatch3(userId, rawSessionId, input, rawRequestId) {
  const gameSettings = await getRuntimeSettings('game');
  ensureGameEnabled(gameSettings, 'match3', '宝石消消乐');
  const sessionId = assertUuid(rawSessionId, '关卡');
  const requestId = assertRequestId(rawRequestId);
  return withTransaction(async (client) => {
    const duplicate = await client.query(
      `SELECT response FROM game_match3_moves WHERE user_id=$1 AND request_id=$2`,
      [userId, requestId]
    );
    if (duplicate.rows[0]) return { ...duplicate.rows[0].response, duplicated: true };
    const { rows } = await client.query(
      `SELECT * FROM game_match3_sessions WHERE id=$1 AND user_id=$2 FOR UPDATE`,
      [sessionId, userId]
    );
    const session = rows[0];
    if (!session) throw gameError('MATCH3_SESSION_NOT_FOUND', '关卡不存在', 404);
    if (session.status !== 'active') {
      throw gameError('MATCH3_SESSION_NOT_ACTIVE', '本关已经结束', 409);
    }
    const rules = Object.keys(session.rules_snapshot || {}).length
      ? session.rules_snapshot
      : gameSettings;
    let resolved;
    try {
      resolved = resolveMatch3Move({
        cells: session.board,
        score: session.score,
        movesLeft: session.moves_left,
        seed: `${session.id}:${session.user_id}:${session.level_no}`,
        rngNonce: session.rng_nonce,
        from: { x: Number(input?.from_x), y: Number(input?.from_y) },
        to: { x: Number(input?.to_x), y: Number(input?.to_y) },
      });
    } catch (error) {
      throw gameError(error.message, '只能交换相邻的两个方块');
    }
    const completed = resolved.valid && resolved.score >= Number(session.target_score);
    const failed = resolved.valid && !completed && resolved.movesLeft === 0;
    let reward = 0n;
    let walletBalance = null;
    if (resolved.valid) {
      const { rows: updated } = await client.query(
        `UPDATE game_match3_sessions SET board=$2::jsonb,score=$3,moves_left=$4,
         rng_nonce=$5,status=$6,completed_at=CASE WHEN $7 THEN NOW() ELSE NULL END,
         updated_at=NOW() WHERE id=$1 RETURNING *`,
        [
          session.id,
          JSON.stringify(resolved.cells),
          resolved.score,
          resolved.movesLeft,
          resolved.rngNonce,
          completed ? 'completed' : failed ? 'failed' : 'active',
          completed,
        ]
      );
      session.board = updated[0].board;
      session.score = updated[0].score;
      session.moves_left = updated[0].moves_left;
      session.rng_nonce = updated[0].rng_nonce;
      session.status = updated[0].status;
      session.updated_at = updated[0].updated_at;
    }
    if (completed) {
      reward = BigInt(rules.match3_clear_reward_points) * MICROPOINTS_PER_POINT;
      const rewardInsert = await client.query(
        `INSERT INTO game_match3_level_rewards
         (id,user_id,session_id,level_no,reward_micropoints)
         VALUES ($1,$2,$3,$4,$5)
         ON CONFLICT (user_id,level_no) DO NOTHING RETURNING id`,
        [crypto.randomUUID(), userId, session.id, session.level_no, reward.toString()]
      );
      if (rewardInsert.rows.length) {
        const balances = await lockWallets(client, [userId]);
        walletBalance = await applyWalletChange(client, balances, userId, reward, {
          type: 'level_reward',
          gameType: 'match3',
          relatedId: session.id,
          remark: `消消乐第${session.level_no}关首次通关奖励`,
        });
        await insertResult(client, {
          userId,
          gameType: 'match3',
          gameId: session.id,
          result: 'win',
          payout: reward,
          netProfit: reward,
          detail: {
            level_no: Number(session.level_no),
            score: resolved.score,
            rules_snapshot: rules,
          },
        });
      }
    }
    const response = {
      valid: resolved.valid,
      score_delta: resolved.scoreDelta,
      cleared: resolved.cleared,
      cascades: resolved.cascades,
      completed,
      failed,
      reward: pointsText(reward),
      wallet_balance: walletBalance == null ? null : pointsText(walletBalance),
      chest_available: completed && Number(session.level_no) % 10 === 0
        ? Number(session.level_no)
        : null,
      session: match3SessionJson(session),
    };
    await client.query(
      `INSERT INTO game_match3_moves
       (id,session_id,user_id,request_id,from_x,from_y,to_x,to_y,
        cleared_count,score_after,response)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11::jsonb)`,
      [
        crypto.randomUUID(),
        session.id,
        userId,
        requestId,
        Number(input?.from_x),
        Number(input?.from_y),
        Number(input?.to_x),
        Number(input?.to_y),
        resolved.cleared,
        resolved.score,
        JSON.stringify(response),
      ]
    );
    return response;
  });
}

export async function openMatch3Chest(userId, rawMilestoneLevel) {
  const gameSettings = await getRuntimeSettings('game');
  ensureGameEnabled(gameSettings, 'match3', '宝石消消乐');
  const milestoneLevel = Number(rawMilestoneLevel);
  if (!Number.isInteger(milestoneLevel) || milestoneLevel < 10 || milestoneLevel % 10 !== 0) {
    throw gameError('MATCH3_CHEST_INVALID', '宝箱里程碑无效');
  }
  return withTransaction(async (client) => {
    const balances = await lockWallets(client, [userId]);
    const eligible = await client.query(
      `SELECT session.rules_snapshot
       FROM game_match3_level_rewards reward
       JOIN game_match3_sessions session ON session.id=reward.session_id
       WHERE reward.user_id=$1 AND reward.level_no=$2`,
      [userId, milestoneLevel]
    );
    if (!eligible.rows.length) {
      throw gameError('MATCH3_CHEST_LOCKED', `完成第${milestoneLevel}关后才能开启`, 409);
    }
    const existing = await client.query(
      `SELECT result,reward_micropoints FROM game_match3_chests
       WHERE user_id=$1 AND milestone_level=$2 FOR UPDATE`,
      [userId, milestoneLevel]
    );
    if (existing.rows[0]) {
      return {
        result: existing.rows[0].result,
        reward: pointsText(existing.rows[0].reward_micropoints),
        duplicated: true,
      };
    }
    const rules = Object.keys(eligible.rows[0].rules_snapshot || {}).length
      ? eligible.rows[0].rules_snapshot
      : gameSettings;
    const outcome = match3ChestOutcome(crypto.randomInt, {
      againBasisPoints: rules.match3_chest_again_basis_points,
      points1BasisPoints: rules.match3_chest_1_basis_points,
      points5BasisPoints: rules.match3_chest_5_basis_points,
      points10BasisPoints: rules.match3_chest_10_basis_points,
    });
    await client.query(
      `INSERT INTO game_match3_chests
       (id,user_id,milestone_level,result,reward_micropoints)
       VALUES ($1,$2,$3,$4,$5)`,
      [crypto.randomUUID(), userId, milestoneLevel, outcome.result, outcome.reward.toString()]
    );
    let walletBalance = null;
    if (outcome.reward > 0n) {
      walletBalance = await applyWalletChange(client, balances, userId, outcome.reward, {
        type: 'chest_reward',
        gameType: 'match3',
        remark: `消消乐第${milestoneLevel}关宝箱奖励`,
      });
    }
    return {
      result: outcome.result,
      reward: pointsText(outcome.reward),
      wallet_balance: walletBalance == null ? null : pointsText(walletBalance),
    };
  });
}

export async function gameHistory(userId, limit = 20, rawGameType = '') {
  const bounded = Math.max(1, Math.min(20, Number(limit) || 20));
  const gameType = String(rawGameType || '').trim();
  if (gameType && !['rps', 'mine', 'battle', 'match3'].includes(gameType)) {
    throw gameError('INVALID_GAME_TYPE', '游戏记录类型无效');
  }
  if (gameType === 'battle') {
    const { rows } = await query(
      `WITH ranked AS (
         SELECT source.*,
           ROW_NUMBER() OVER (ORDER BY source.created_at ASC,source.id::text ASC)::bigint AS issue_no
         FROM game_battle_rounds source
       )
       SELECT r.id,r.issue_no,r.id AS game_id,'battle' AS game_type,'public' AS mode,
         COALESCE(gr.result,'settled') AS result,
         COALESCE(gr.stake_micropoints,0) AS stake_micropoints,
         COALESCE(gr.payout_micropoints,0) AS payout_micropoints,
         COALESCE(gr.fee_micropoints,0) AS fee_micropoints,
         COALESCE(gr.net_profit_micropoints,0) AS net_profit_micropoints,
         COALESCE(gr.detail,'{}'::jsonb) AS detail,
         r.eliminated_rooms,r.settled_at AS created_at
       FROM game_battle_rounds r
       LEFT JOIN game_results gr ON gr.user_id=$1 AND gr.game_type='battle'
         AND gr.game_id=r.id
       WHERE r.status IN ('settled','refunded')
       ORDER BY r.settled_at DESC LIMIT $2`,
      [userId, bounded]
    );
    return rows.map((row) => {
      const eliminated = (row.eliminated_rooms || []).map(Number).sort((a, b) => a - b);
      const eliminatedSet = new Set(eliminated);
      return {
        ...resultJson(row),
        detail: {
          ...(row.detail || {}),
          issue_no: Number(row.issue_no),
          eliminated_rooms: eliminated,
          surviving_rooms: Array.from({ length: BATTLE_ROOM_COUNT }, (_, index) => index + 1).filter(
            (room) => !eliminatedSet.has(room)
          ),
          participated: row.detail?.room_no != null,
        },
      };
    });
  }
  const { rows } = await query(
    `SELECT * FROM game_results WHERE user_id=$1
     AND ($3::text='' OR game_type=$3)
     ORDER BY created_at DESC LIMIT $2`,
    [userId, bounded, gameType]
  );
  return rows.map(resultJson);
}

export async function todayLeaderboard(limit = 30) {
  const date = businessDate();
  const bounded = Math.max(1, Math.min(100, Number(limit) || 30));
  const { rows } = await query(
    `SELECT gr.user_id,u.username,
       SUM(gr.net_profit_micropoints)::bigint AS net_profit,
       COUNT(*)::int AS games,
       COUNT(*) FILTER (WHERE gr.result='win')::int AS wins
     FROM game_results gr JOIN users u ON u.id=gr.user_id
     WHERE gr.created_at >= $1::date AND gr.created_at < ($1::date+INTERVAL '1 day')
     GROUP BY gr.user_id,u.username
     ORDER BY net_profit DESC,games DESC,gr.user_id ASC LIMIT $2`,
    [date, bounded]
  );
  return rows.map((row, index) => ({
    rank: index + 1,
    user_id: String(row.user_id),
    username: row.username,
    net_profit: pointsText(row.net_profit),
    games: Number(row.games),
    wins: Number(row.wins),
  }));
}

export async function gameDashboard(userId) {
  const gameSettings = await getRuntimeSettings('game');
  await Promise.all([expireMinePackets(), settleDueBattleRounds()]);
  const [wallet, mines, battle, match3, history, leaderboard] = await Promise.all([
    getGameWallet(userId),
    listOpenMinePackets(userId),
    getBattleState(userId),
    getMatch3State(userId),
    gameHistory(userId, 20),
    todayLeaderboard(20),
  ]);
  return {
    wallet,
    rules: {
      enabled: {
        rps: gameSettings.rps_enabled,
        mine: gameSettings.mine_enabled,
        battle: gameSettings.battle_enabled,
        match3: gameSettings.match3_enabled,
      },
      rps: {
        stakes: GAME_STAKE_OPTIONS,
        odds: (gameSettings.rps_payout_basis_points / 10000).toFixed(2),
      },
      battle_stakes: BATTLE_STAKE_OPTIONS,
      mine: {
        packet_totals: GAME_STAKE_OPTIONS,
        claims: 7,
        liability_multiplier: (gameSettings.mine_liability_basis_points / 10000).toFixed(2),
        receiver_rate: `${100 - gameSettings.mine_fee_basis_points / 100}%`,
        ttl_days: MINE_PACKET_TTL_DAYS,
        order: 'oldest_first',
      },
      battle: {
        rooms: BATTLE_ROOM_COUNT,
        eliminated: `${gameSettings.battle_min_eliminated}-${gameSettings.battle_max_eliminated}`,
        fee_rate: `${gameSettings.battle_fee_basis_points / 100}%`,
        round_seconds: BATTLE_ROUND_SECONDS,
        freeze_seconds: BATTLE_FREEZE_SECONDS,
      },
      match3: {
        clear_reward: String(gameSettings.match3_clear_reward_points),
        reward_once_per_level: true,
        chest_every_levels: 10,
        recovery: 'rewarded_ad',
      },
      conversion: {
        direction: 'bidirectional',
        ratio: '1:1',
        reverse_limit: 'converted_principal_only',
      },
    },
    mines,
    battle,
    match3,
    history,
    leaderboard,
  };
}
