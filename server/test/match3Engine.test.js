import assert from 'node:assert/strict';
import test from 'node:test';

import {
  MATCH3_HEIGHT,
  MATCH3_START_MOVES,
  MATCH3_WIDTH,
  createMatch3Board,
  resolveMatch3Move,
} from '../src/services/match3Engine.js';

test('消消乐初始棋盘尺寸稳定且至少存在一个有效交换', () => {
  const cells = createMatch3Board('match3-test-seed');
  assert.equal(cells.length, MATCH3_WIDTH * MATCH3_HEIGHT);
  let valid = null;
  for (let y = 0; y < MATCH3_HEIGHT && !valid; y += 1) {
    for (let x = 0; x < MATCH3_WIDTH && !valid; x += 1) {
      for (const [dx, dy] of [[1, 0], [0, 1]]) {
        if (x + dx >= MATCH3_WIDTH || y + dy >= MATCH3_HEIGHT) continue;
        const result = resolveMatch3Move({
          cells,
          score: 0,
          movesLeft: MATCH3_START_MOVES,
          seed: 'match3-test-seed',
          rngNonce: 0,
          from: { x, y },
          to: { x: x + dx, y: y + dy },
        });
        if (result.valid) valid = result;
      }
    }
  }
  assert.ok(valid);
  assert.equal(valid.movesLeft, MATCH3_START_MOVES - 1);
  assert.ok(valid.cleared >= 3);
  assert.equal(valid.cells.length, MATCH3_WIDTH * MATCH3_HEIGHT);
});

