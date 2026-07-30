import crypto from 'node:crypto';

import { Board, Matcher, collapse } from 'miaoda-game-match3-core';

export const MATCH3_WIDTH = 8;
export const MATCH3_HEIGHT = 8;
export const MATCH3_SYMBOLS = 6;
export const MATCH3_START_MOVES = 22;
export const MATCH3_RECOVERY_MOVES = 5;

function deterministicInt(seed, nonce, counter, max) {
  const digest = crypto
    .createHash('sha256')
    .update(`${seed}:${nonce}:${counter}`)
    .digest();
  return digest.readUInt32BE(0) % max;
}

function boardFromCells(cells) {
  if (!Array.isArray(cells) || cells.length !== MATCH3_WIDTH * MATCH3_HEIGHT) {
    throw new Error('MATCH3_BOARD_INVALID');
  }
  const board = new Board({ width: MATCH3_WIDTH, height: MATCH3_HEIGHT });
  cells.forEach((value, index) => {
    board.set(index % MATCH3_WIDTH, Math.floor(index / MATCH3_WIDTH), Number(value));
  });
  return board;
}

function hasPlayableSwap(board) {
  const matcher = new Matcher(board);
  for (let y = 0; y < MATCH3_HEIGHT; y += 1) {
    for (let x = 0; x < MATCH3_WIDTH; x += 1) {
      for (const [dx, dy] of [[1, 0], [0, 1]]) {
        const to = { x: x + dx, y: y + dy };
        if (!board.contains(to.x, to.y)) continue;
        const from = { x, y };
        board.swap(from, to);
        const playable = matcher.anyMatch(3);
        board.swap(from, to);
        if (playable) return true;
      }
    }
  }
  return false;
}

export function createMatch3Board(seed) {
  for (let attempt = 0; attempt < 32; attempt += 1) {
    const cells = [];
    for (let y = 0; y < MATCH3_HEIGHT; y += 1) {
      for (let x = 0; x < MATCH3_WIDTH; x += 1) {
        const forbidden = new Set();
        if (x >= 2 && cells[y * MATCH3_WIDTH + x - 1] === cells[y * MATCH3_WIDTH + x - 2]) {
          forbidden.add(cells[y * MATCH3_WIDTH + x - 1]);
        }
        if (
          y >= 2 &&
          cells[(y - 1) * MATCH3_WIDTH + x] === cells[(y - 2) * MATCH3_WIDTH + x]
        ) {
          forbidden.add(cells[(y - 1) * MATCH3_WIDTH + x]);
        }
        const choices = Array.from({ length: MATCH3_SYMBOLS }, (_, value) => value)
          .filter((value) => !forbidden.has(value));
        const index = deterministicInt(seed, attempt, cells.length, choices.length);
        cells.push(choices[index]);
      }
    }
    const board = boardFromCells(cells);
    if (hasPlayableSwap(board)) return cells;
  }
  throw new Error('MATCH3_BOARD_GENERATION_FAILED');
}

export function match3Target(levelNo) {
  return Math.min(900, 150 + Math.max(0, Number(levelNo) - 1) * 20);
}

export function resolveMatch3Move({
  cells,
  score,
  movesLeft,
  seed,
  rngNonce,
  from,
  to,
}) {
  const coords = [from?.x, from?.y, to?.x, to?.y].map(Number);
  if (coords.some((value) => !Number.isInteger(value))) {
    throw new Error('MATCH3_COORDINATES_INVALID');
  }
  if (
    ![from, to].every((tile) =>
      tile.x >= 0 && tile.x < MATCH3_WIDTH && tile.y >= 0 && tile.y < MATCH3_HEIGHT
    ) ||
    Math.abs(from.x - to.x) + Math.abs(from.y - to.y) !== 1
  ) {
    throw new Error('MATCH3_SWAP_INVALID');
  }
  const board = boardFromCells(cells);
  const matcher = new Matcher(board);
  board.swap(from, to);
  if (!matcher.anyMatch(3)) {
    board.swap(from, to);
    return {
      valid: false,
      cells: board.toArray(),
      score: Number(score),
      scoreDelta: 0,
      cleared: 0,
      cascades: [],
      movesLeft: Number(movesLeft),
      rngNonce: Number(rngNonce),
    };
  }

  let nonce = Number(rngNonce);
  let clearedTotal = 0;
  let scoreDelta = 0;
  const cascades = [];
  for (let combo = 1; combo <= 20; combo += 1) {
    const matched = matcher.matchAll(3);
    if (!matched.length) break;
    const clearedKeys = new Set();
    for (const run of matched) {
      for (const tile of run.tiles) clearedKeys.add(`${tile.x}:${tile.y}`);
    }
    const cleared = [...clearedKeys].map((key) => {
      const [x, y] = key.split(':').map(Number);
      board.set(x, y, null);
      return { x, y };
    });
    const localNonce = nonce;
    let spawnCounter = 0;
    const gravity = collapse(board, () => {
      const value = deterministicInt(seed, localNonce, spawnCounter, MATCH3_SYMBOLS);
      spawnCounter += 1;
      return value;
    });
    nonce += 1;
    clearedTotal += cleared.length;
    scoreDelta += cleared.length * 10 * combo;
    cascades.push({ combo, cleared, falls: gravity.falls, spawns: gravity.spawns });
  }

  return {
    valid: true,
    cells: board.toArray(),
    score: Number(score) + scoreDelta,
    scoreDelta,
    cleared: clearedTotal,
    cascades,
    movesLeft: Math.max(0, Number(movesLeft) - 1),
    rngNonce: nonce,
  };
}

