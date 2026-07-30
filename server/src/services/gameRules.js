import crypto from 'node:crypto';

export const MICROPOINTS_PER_POINT = 1_000_000n;
export const GAME_STAKE_OPTIONS = Object.freeze([10, 50, 100]);
export const BATTLE_STAKE_OPTIONS = Object.freeze([1, 10, 50]);
export const RPS_STAKE = 10n * MICROPOINTS_PER_POINT;
export const RPS_PAYOUT = 15n * MICROPOINTS_PER_POINT;
export const MINE_PACKET_TOTAL = 10n * MICROPOINTS_PER_POINT;
export const MINE_LIABILITY = 15n * MICROPOINTS_PER_POINT;
export const MINE_CLAIM_COUNT = 7;
export const MINE_PACKET_TTL_DAYS = 7;
export const BATTLE_ROUND_SECONDS = 60;
export const BATTLE_SWITCH_SECONDS = 20;
export const BATTLE_FREEZE_SECONDS = 5;
export const BATTLE_ROOM_COUNT = 8;
export const BATTLE_MIN_ELIMINATED = 2;
export const BATTLE_MAX_ELIMINATED = 3;
export const FEE_NUMERATOR = 10n;
export const FEE_DENOMINATOR = 100n;

const rpsChoices = ['rock', 'paper', 'scissors'];

export function assertRpsChoice(choice) {
  if (!rpsChoices.includes(choice)) {
    const err = new Error('请选择石头、剪刀或布');
    err.code = 'INVALID_RPS_CHOICE';
    err.status = 400;
    throw err;
  }
  return choice;
}

export function randomRpsChoice(randomInt = crypto.randomInt) {
  return rpsChoices[randomInt(0, rpsChoices.length)];
}

export function rpsOutcome(userChoice, botChoice) {
  assertRpsChoice(userChoice);
  assertRpsChoice(botChoice);
  if (userChoice === botChoice) return 'draw';
  if (
    (userChoice === 'rock' && botChoice === 'scissors') ||
    (userChoice === 'scissors' && botChoice === 'paper') ||
    (userChoice === 'paper' && botChoice === 'rock')
  ) {
    return 'win';
  }
  return 'loss';
}

export function stakeMicropoints(rawPoints, label = '对局积分') {
  const points = Number(rawPoints ?? GAME_STAKE_OPTIONS[0]);
  if (!Number.isSafeInteger(points) || !GAME_STAKE_OPTIONS.includes(points)) {
    const err = new Error(`${label}只能选择10、50或100积分`);
    err.code = 'INVALID_GAME_STAKE';
    err.status = 400;
    throw err;
  }
  return BigInt(points) * MICROPOINTS_PER_POINT;
}

export function rpsSettlement(outcome, rawStake = RPS_STAKE, payoutBasisPoints = 15000) {
  const stake = BigInt(rawStake);
  const payout = (stake * BigInt(payoutBasisPoints)) / 10000n;
  if (outcome === 'win') {
    return {
      stake,
      payout,
      fee: 0n,
      netProfit: payout - stake,
    };
  }
  if (outcome === 'draw') {
    return { stake, payout: stake, fee: 0n, netProfit: 0n };
  }
  return { stake, payout: 0n, fee: 0n, netProfit: -stake };
}

export function mineLiability(totalMicropoints, basisPoints = 15000) {
  return (BigInt(totalMicropoints) * BigInt(basisPoints)) / 10000n;
}

export function splitMinePacket(totalOrRandom = MINE_PACKET_TOTAL, randomInt = crypto.randomInt) {
  // 兼容旧调用 splitMinePacket(randomInt)。以0.01积分为最小随机单位，
  // 保证7份均为正数且总和严格等于所选档位。
  const legacyRandom = typeof totalOrRandom === 'function';
  const total = legacyRandom ? MINE_PACKET_TOTAL : BigInt(totalOrRandom);
  const random = legacyRandom ? totalOrRandom : randomInt;
  const totalCents = Number(total / 10_000n);
  if (!Number.isSafeInteger(totalCents) || totalCents < MINE_CLAIM_COUNT) {
    throw new Error('红包总额无效');
  }
  const cuts = new Set();
  while (cuts.size < MINE_CLAIM_COUNT - 1) cuts.add(random(1, totalCents));
  const points = [0, ...[...cuts].sort((a, b) => a - b), totalCents];
  return points.slice(1).map((point, index) => {
    const cents = point - points[index];
    return BigInt(cents) * 10_000n;
  });
}

export function mineHit(amountMicropoints, mineDigit) {
  const cents = BigInt(amountMicropoints) / 10_000n;
  return Number(cents % 10n) === Number(mineDigit);
}

export function feeOn(value, basisPoints = 1000) {
  return (BigInt(value) * BigInt(basisPoints)) / 10000n;
}

export function redeemableGameBalance(balance, redeemablePrincipal) {
  const current = BigInt(balance);
  const remainingPrincipal = BigInt(redeemablePrincipal);
  if (current <= 0n || remainingPrincipal <= 0n) return 0n;
  return current < remainingPrincipal ? current : remainingPrincipal;
}

export function battleEliminatedRooms(seedHex, roundId, options = {}) {
  const digest = crypto
    .createHash('sha256')
    .update(`${seedHex}:${roundId}`)
    .digest();
  const minimum = Math.max(
    1,
    Math.min(BATTLE_ROOM_COUNT - 1, Number(options.minEliminated ?? BATTLE_MIN_ELIMINATED))
  );
  const maximum = Math.max(
    minimum,
    Math.min(BATTLE_ROOM_COUNT - 1, Number(options.maxEliminated ?? BATTLE_MAX_ELIMINATED))
  );
  const count = minimum + (digest[0] % (maximum - minimum + 1));
  const rooms = Array.from({ length: BATTLE_ROOM_COUNT }, (_, index) => index + 1);
  for (let index = rooms.length - 1; index > 0; index -= 1) {
    const swapIndex = digest[(rooms.length - index) % digest.length] % (index + 1);
    [rooms[index], rooms[swapIndex]] = [rooms[swapIndex], rooms[index]];
  }
  return rooms.slice(0, count).sort((a, b) => a - b);
}

export function battleOpponentEntries(seedHex, roundId, options = {}) {
  const digest = crypto
    .createHash('sha256')
    .update(`opponents:${seedHex}:${roundId}`)
    .digest();
  const entries = [];
  const minCount = Math.max(0, Math.min(5, Number(options.minCount ?? 1)));
  const maxCount = Math.max(minCount, Math.min(5, Number(options.maxCount ?? 2)));
  const minStake = Math.max(1, Number(options.minStake ?? 5));
  const maxStake = Math.max(minStake, Number(options.maxStake ?? 30));
  for (let roomNo = 1; roomNo <= BATTLE_ROOM_COUNT; roomNo += 1) {
    const count = minCount + (digest[roomNo] % (maxCount - minCount + 1));
    for (let index = 0; index < count; index += 1) {
      const stakePoints = minStake +
        (digest[(roomNo * 3 + index) % digest.length] % (maxStake - minStake + 1));
      entries.push({
        id: `opponent-${roomNo}-${index + 1}`,
        roomNo,
        stake: BigInt(stakePoints) * MICROPOINTS_PER_POINT,
        opponent: true,
      });
    }
  }
  return entries;
}

export function match3ChestOutcome(randomInt = crypto.randomInt, options = {}) {
  const roll = randomInt(0, 10_000);
  const again = Number(options.againBasisPoints ?? 9000);
  const points1 = again + Number(options.points1BasisPoints ?? 500);
  const points5 = points1 + Number(options.points5BasisPoints ?? 400);
  if (roll < again) return { result: 'again', reward: 0n };
  if (roll < points1) return { result: 'points_1', reward: 1n * MICROPOINTS_PER_POINT };
  if (roll < points5) return { result: 'points_5', reward: 5n * MICROPOINTS_PER_POINT };
  return { result: 'points_10', reward: 10n * MICROPOINTS_PER_POINT };
}

export function match3OddsText(settings = {}) {
  const percent = (basisPoints) => `${Number(basisPoints || 0) / 100}%`;
  return {
    again: percent(settings.match3_chest_again_basis_points),
    points_1: percent(settings.match3_chest_1_basis_points),
    points_5: percent(settings.match3_chest_5_basis_points),
    points_10: percent(settings.match3_chest_10_basis_points),
  };
}

export function battleSettlement(entries, eliminatedRooms, feeBasisPoints = 1000) {
  const eliminated = new Set(eliminatedRooms.map(Number));
  const normalized = entries.map((entry) => ({
    ...entry,
    roomNo: Number(entry.roomNo),
    stake: BigInt(entry.stake),
  }));
  const losers = normalized.filter((entry) => eliminated.has(entry.roomNo));
  const winners = normalized.filter((entry) => !eliminated.has(entry.roomNo));
  const losingPool = losers.reduce((sum, entry) => sum + entry.stake, 0n);
  const winningStake = winners.reduce((sum, entry) => sum + entry.stake, 0n);
  if (winners.length === 0 || winningStake === 0n) {
    return {
      losingPool: 0n,
      fee: 0n,
      distributable: 0n,
      refunded: true,
      entries: normalized.map((entry) => ({
        ...entry,
        result: 'refund',
        payout: entry.stake,
        fee: 0n,
      })),
    };
  }
  const fee = feeOn(losingPool, feeBasisPoints);
  const distributable = losingPool - fee;
  const allocations = winners.map((entry) => {
    const weighted = distributable * entry.stake;
    return {
      entry,
      profit: weighted / winningStake,
      remainder: weighted % winningStake,
    };
  });
  let undistributed = distributable - allocations.reduce((sum, item) => sum + item.profit, 0n);
  allocations
    .slice()
    .sort((left, right) => {
      if (left.remainder !== right.remainder) return left.remainder > right.remainder ? -1 : 1;
      return String(left.entry.id).localeCompare(String(right.entry.id));
    })
    .forEach((item) => {
      if (undistributed <= 0n) return;
      item.profit += 1n;
      undistributed -= 1n;
    });
  const profitByEntry = new Map(allocations.map((item) => [item.entry, item.profit]));
  return {
    losingPool,
    fee,
    distributable,
    refunded: false,
    entries: normalized.map((entry) => {
      if (eliminated.has(entry.roomNo)) {
        return {
          ...entry,
          result: 'loss',
          payout: 0n,
          fee: feeOn(entry.stake, feeBasisPoints),
        };
      }
      const profit = profitByEntry.get(entry) || 0n;
      return { ...entry, result: 'win', payout: entry.stake + profit, fee: 0n };
    }),
  };
}

export function pointsText(value) {
  const amount = BigInt(value);
  const sign = amount < 0n ? '-' : '';
  const absolute = amount < 0n ? -amount : amount;
  const whole = absolute / MICROPOINTS_PER_POINT;
  const fraction = String(absolute % MICROPOINTS_PER_POINT).padStart(6, '0').replace(/0+$/, '');
  return `${sign}${whole}${fraction ? `.${fraction}` : ''}`;
}
