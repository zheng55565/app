import assert from 'node:assert/strict';
import test from 'node:test';

import {
  BATTLE_FREEZE_SECONDS,
  BATTLE_ROOM_COUNT,
  BATTLE_ROUND_SECONDS,
  BATTLE_STAKE_OPTIONS,
  BATTLE_SWITCH_SECONDS,
  GAME_STAKE_OPTIONS,
  MICROPOINTS_PER_POINT,
  MINE_PACKET_TOTAL,
  MINE_PACKET_TTL_DAYS,
  battleEliminatedRooms,
  battleOpponentEntries,
  battleSettlement,
  match3ChestOutcome,
  match3OddsText,
  mineLiability,
  mineHit,
  pointsText,
  redeemableGameBalance,
  rpsOutcome,
  rpsSettlement,
  splitMinePacket,
  stakeMicropoints,
} from '../src/services/gameRules.js';

test('石头剪刀布支持10/50/100积分、赢家按1.5倍到账、平局退款', () => {
  assert.deepEqual(GAME_STAKE_OPTIONS, [10, 50, 100]);
  assert.deepEqual(BATTLE_STAKE_OPTIONS, [1, 10, 50]);
  assert.equal(rpsOutcome('rock', 'scissors'), 'win');
  assert.equal(rpsOutcome('paper', 'paper'), 'draw');
  assert.equal(rpsOutcome('scissors', 'rock'), 'loss');
  assert.equal(rpsSettlement('win').payout, 15n * MICROPOINTS_PER_POINT);
  assert.equal(rpsSettlement('win').fee, 0n);
  assert.equal(rpsSettlement('win').netProfit, 5n * MICROPOINTS_PER_POINT);
  assert.equal(rpsSettlement('draw').payout, 10n * MICROPOINTS_PER_POINT);
  const stake50 = stakeMicropoints(50);
  assert.equal(rpsSettlement('win', stake50).payout, 75n * MICROPOINTS_PER_POINT);
  assert.equal(rpsSettlement('win', stake50).netProfit, 25n * MICROPOINTS_PER_POINT);
  assert.equal(rpsSettlement('draw', stake50).payout, stake50);
  assert.equal(rpsSettlement('win', stake50, 18000).payout, 90n * MICROPOINTS_PER_POINT);
  assert.throws(() => stakeMicropoints(20), /10、50或100/);
});

test('扫雷红包支持10/50/100档、固定7份并按金额末位中雷', () => {
  assert.equal(MINE_PACKET_TTL_DAYS, 7);
  let cursor = 0;
  const deterministic = [100, 220, 360, 510, 700, 850];
  const shares = splitMinePacket(() => deterministic[cursor++]);
  assert.equal(shares.length, 7);
  assert.equal(shares.reduce((sum, amount) => sum + amount, 0n), MINE_PACKET_TOTAL);
  let cursor50 = 0;
  const shares50 = splitMinePacket(
    50n * MICROPOINTS_PER_POINT,
    () => [100, 500, 1200, 2000, 3200, 4100][cursor50++]
  );
  assert.equal(shares50.length, 7);
  assert.equal(
    shares50.reduce((sum, amount) => sum + amount, 0n),
    50n * MICROPOINTS_PER_POINT
  );
  assert.equal(mineLiability(50n * MICROPOINTS_PER_POINT), 75n * MICROPOINTS_PER_POINT);
  assert.equal(mineHit(1_230_000n, 3), true);
  assert.equal(mineHit(1_230_000n, 4), false);
});

test('游戏盈利不能突破本人AI额度转入的可兑回上限', () => {
  assert.equal(redeemableGameBalance(20n, 10n), 10n);
  assert.equal(redeemableGameBalance(4n, 10n), 4n);
  assert.equal(redeemableGameBalance(20n, 0n), 0n);
});

test('八房失败池扣10%后按全部幸存投入占比分配', () => {
  const entries = [1, 2, 3, 4, 5, 6, 7, 8].map((roomNo) => ({
    id: String(roomNo),
    roomNo,
    stake: 10n * MICROPOINTS_PER_POINT,
  }));
  const settled = battleSettlement(entries, [1, 2]);
  assert.equal(settled.losingPool, 20n * MICROPOINTS_PER_POINT);
  assert.equal(settled.fee, 2n * MICROPOINTS_PER_POINT);
  assert.equal(settled.entries.find((entry) => entry.id === '1').fee, 1n * MICROPOINTS_PER_POINT);
  assert.equal(settled.entries.find((entry) => entry.id === '3').fee, 0n);
  assert.equal(settled.entries.find((entry) => entry.id === '3').payout, 13_000_000n);
  assert.equal(
    settled.entries.reduce((sum, entry) => sum + entry.payout, 0n),
    78n * MICROPOINTS_PER_POINT
  );
  assert.equal(pointsText(-14_500_000n), '-14.5');
});

test('八房按比例分配时把微积分尾差完整分给幸存者', () => {
  const entries = [
    { id: 'a', roomNo: 1, stake: 1n },
    { id: 'b', roomNo: 2, stake: 1n },
    { id: 'c', roomNo: 3, stake: 1n },
    { id: 'd', roomNo: 4, stake: 1n },
    { id: 'e', roomNo: 5, stake: 1n },
  ];
  const settled = battleSettlement(entries, [1, 2]);
  const winnerPayout = settled.entries
    .filter((entry) => entry.result === 'win')
    .reduce((sum, entry) => sum + entry.payout, 0n);
  assert.equal(winnerPayout, 3n + settled.distributable);
});

test('八房生存局随机淘汰2至3房且由开盘前种子稳定决定', () => {
  assert.equal(BATTLE_ROUND_SECONDS, 60);
  assert.equal(BATTLE_SWITCH_SECONDS, 20);
  assert.equal(BATTLE_FREEZE_SECONDS, 5);
  const seed = 'ab'.repeat(32);
  const first = battleEliminatedRooms(seed, 'round-1');
  const second = battleEliminatedRooms(seed, 'round-1');
  assert.deepEqual(first, second);
  assert.equal(BATTLE_ROOM_COUNT, 8);
  assert.ok(first.length === 2 || first.length === 3);
  assert.equal(new Set(first).size, first.length);
  assert.ok(first.every((room) => room >= 1 && room <= 8));
});

test('服务端对手覆盖八个房间且投入使用整数微积分', () => {
  const entries = battleOpponentEntries('cd'.repeat(32), 'round-opponents');
  assert.deepEqual(new Set(entries.map((entry) => entry.roomNo)), new Set([1,2,3,4,5,6,7,8]));
  assert.ok(entries.every((entry) => entry.opponent && entry.stake > 0n));
});

test('消消乐宝箱概率边界严格为90/5/4/1', () => {
  assert.deepEqual(match3ChestOutcome(() => 0), { result: 'again', reward: 0n });
  assert.equal(match3ChestOutcome(() => 8999).result, 'again');
  assert.equal(match3ChestOutcome(() => 9000).result, 'points_1');
  assert.equal(match3ChestOutcome(() => 9499).result, 'points_1');
  assert.equal(match3ChestOutcome(() => 9500).result, 'points_5');
  assert.equal(match3ChestOutcome(() => 9899).result, 'points_5');
  assert.equal(match3ChestOutcome(() => 9900).result, 'points_10');
  assert.equal(
    match3ChestOutcome(() => 7999, {
      againBasisPoints: 8000,
      points1BasisPoints: 1000,
      points5BasisPoints: 500,
      points10BasisPoints: 500,
    }).result,
    'again'
  );
  assert.equal(
    match3ChestOutcome(() => 8000, {
      againBasisPoints: 8000,
      points1BasisPoints: 1000,
      points5BasisPoints: 500,
      points10BasisPoints: 500,
    }).result,
    'points_1'
  );
  assert.deepEqual(match3OddsText({
    match3_chest_again_basis_points: 8000,
    match3_chest_1_basis_points: 1000,
    match3_chest_5_basis_points: 500,
    match3_chest_10_basis_points: 500,
  }), { again: '80%', points_1: '10%', points_5: '5%', points_10: '5%' });
});
