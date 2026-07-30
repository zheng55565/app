import { Router } from 'express';

import { requireAuth } from '../middleware/auth.js';
import { getAdRiskContext } from '../services/adSecurity.js';
import {
  convertAiQuotaToGamePoints,
  convertGamePointsToAiQuota,
  createMinePacket,
  gameDashboard,
  gameHistory,
  getBattleState,
  getGameWallet,
  getMatch3State,
  grabMinePacket,
  joinBattleRound,
  listOpenMinePackets,
  moveMatch3,
  openMatch3Chest,
  playRps,
  startMatch3Level,
  todayLeaderboard,
} from '../services/gameEngine.js';
import {
  consumeGameRecoveryTask,
  createGameRecoveryTask,
  getGameRecoveryTask,
} from '../services/gameRecovery.js';

const router = Router();
router.use(requireAuth);

function installHash(req) {
  const risk = getAdRiskContext(req);
  if (!risk.deviceHash) {
    const err = new Error('缺少设备安装标识，请升级App后重试');
    err.code = 'INSTALL_ID_REQUIRED';
    err.status = 400;
    throw err;
  }
  return risk.deviceHash;
}

router.get('/dashboard', async (req, res, next) => {
  try {
    res.setHeader('Cache-Control', 'private, no-store');
    res.json(await gameDashboard(req.user.id));
  } catch (err) {
    next(err);
  }
});

router.get('/wallet', async (req, res, next) => {
  try {
    res.setHeader('Cache-Control', 'private, no-store');
    res.json(await getGameWallet(req.user.id));
  } catch (err) {
    next(err);
  }
});

router.post('/convert', async (req, res, next) => {
  try {
    const direction = req.body?.direction || 'ai_to_game';
    if (!['ai_to_game', 'game_to_ai'].includes(direction)) {
      const err = new Error('兑换方向无效');
      err.code = 'INVALID_CONVERSION_DIRECTION';
      err.status = 400;
      throw err;
    }
    const convert = direction === 'game_to_ai'
      ? convertGamePointsToAiQuota
      : convertAiQuotaToGamePoints;
    const result = await convert(req.user, req.body?.amount, req.body?.request_id);
    res.json(result);
  } catch (err) {
    next(err);
  }
});

router.post('/rps/play', async (req, res, next) => {
  try {
    res.json(
      await playRps(
        req.user.id,
        req.body?.choice,
        req.body?.stake,
        req.body?.request_id
      )
    );
  } catch (err) {
    next(err);
  }
});

router.get('/mines', async (req, res, next) => {
  try {
    res.setHeader('Cache-Control', 'private, no-store');
    res.json({ packets: await listOpenMinePackets(req.user.id) });
  } catch (err) {
    next(err);
  }
});

router.post('/mines', async (req, res, next) => {
  try {
    res.json(
      await createMinePacket(
        req.user.id,
        installHash(req),
        req.body?.mine_digit,
        req.body?.total,
        req.body?.request_id
      )
    );
  } catch (err) {
    next(err);
  }
});

router.post('/mines/:id/grab', async (req, res, next) => {
  try {
    res.json(
      await grabMinePacket(
        req.user.id,
        installHash(req),
        req.params.id,
        req.body?.request_id
      )
    );
  } catch (err) {
    next(err);
  }
});

router.get('/battle/current', async (req, res, next) => {
  try {
    res.setHeader('Cache-Control', 'private, no-store');
    res.json(await getBattleState(req.user.id));
  } catch (err) {
    next(err);
  }
});

router.post('/battle/:id/join', async (req, res, next) => {
  try {
    res.json(
      await joinBattleRound(
        req.user.id,
        installHash(req),
        req.params.id,
        req.body?.room_no,
        req.body?.stake,
        req.body?.request_id
      )
    );
  } catch (err) {
    next(err);
  }
});

router.get('/match3', async (req, res, next) => {
  try {
    res.setHeader('Cache-Control', 'private, no-store');
    res.json(await getMatch3State(req.user.id));
  } catch (err) {
    next(err);
  }
});

router.post('/match3/start', async (req, res, next) => {
  try {
    res.json(await startMatch3Level(req.user.id, req.body?.level_no));
  } catch (err) {
    next(err);
  }
});

router.post('/match3/:id/move', async (req, res, next) => {
  try {
    res.json(
      await moveMatch3(
        req.user.id,
        req.params.id,
        req.body,
        req.body?.request_id
      )
    );
  } catch (err) {
    next(err);
  }
});

router.post('/match3/chests/:level/open', async (req, res, next) => {
  try {
    res.json(await openMatch3Chest(req.user.id, req.params.level));
  } catch (err) {
    next(err);
  }
});

router.post('/match3/:id/recovery/start', async (req, res, next) => {
  try {
    res.json(await createGameRecoveryTask(req.user.id, req.params.id));
  } catch (err) {
    next(err);
  }
});

router.get('/match3/recovery/:taskToken', async (req, res, next) => {
  try {
    res.setHeader('Cache-Control', 'private, no-store');
    res.json(await getGameRecoveryTask(req.user.id, req.params.taskToken));
  } catch (err) {
    next(err);
  }
});

router.post('/match3/recovery/:taskToken/consume', async (req, res, next) => {
  try {
    const recovery = await consumeGameRecoveryTask(req.user.id, req.params.taskToken);
    res.json({ recovery, match3: await getMatch3State(req.user.id) });
  } catch (err) {
    next(err);
  }
});

router.get('/history', async (req, res, next) => {
  try {
    res.setHeader('Cache-Control', 'private, no-store');
    res.json({
      records: await gameHistory(
        req.user.id,
        req.query.limit,
        req.query.game_type
      ),
    });
  } catch (err) {
    next(err);
  }
});

router.get('/leaderboard/today', async (req, res, next) => {
  try {
    res.setHeader('Cache-Control', 'private, max-age=10');
    res.json({ records: await todayLeaderboard(req.query.limit) });
  } catch (err) {
    next(err);
  }
});

export default router;
