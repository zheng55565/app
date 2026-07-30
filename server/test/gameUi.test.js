import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const gameHtml = fs.readFileSync(
  new URL('../public/games/index.html', import.meta.url),
  'utf8'
);

test('大逃杀在对局内使用1/10/50累计下注，选择页不展示下注档位', () => {
  assert.match(gameHtml, /data-battle-stake="1"/);
  assert.match(gameHtml, /data-battle-stake="10"/);
  assert.match(gameHtml, /data-battle-stake="50"/);
  assert.match(gameHtml, /多次投入自动累加/);
  assert.match(gameHtml, /var showStake = gameType === 'rps'/);
  assert.doesNotMatch(gameHtml, /id="battleStake"/);
});

test('扫雷红包没有复盘入口并允许发布者进入拆红包流程', () => {
  assert.match(gameHtml, /button\.textContent = canGrab \? '拆红包' : '查看详情'/);
  assert.match(gameHtml, /class="mine-open-modal"/);
  assert.match(gameHtml, /class="mine-detail-page"/);
  assert.match(gameHtml, /恭喜发财，大吉大利/);
  assert.match(gameHtml, /mineOpenAction/);
  assert.match(gameHtml, /mine-detail-time/);
  assert.doesNotMatch(gameHtml, /复盘|mineReplay|replay-cell/);
  assert.doesNotMatch(gameHtml, /尾号/);
  assert.doesNotMatch(gameHtml, /!packet\.is_creator/);
});

test('石头剪刀布页面统一展示1.5倍赔率', () => {
  assert.match(gameHtml, /获胜到账1\.5倍/);
  assert.doesNotMatch(gameHtml, /获胜到账1\.8倍|积分 · 1\.8倍/);
});
