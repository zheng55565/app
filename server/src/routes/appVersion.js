// App 版本检查 & 广告位配置
// GET /api/app/version?platform=android&version_code=1
// GET /api/app/ad-config   广告开关与单元 ID（服务端可远程开关广告位，无需发版）
import { Router } from 'express';
import { query } from '../db.js';
import { config } from '../config.js';
import { getRuntimeSettings } from '../services/runtimeSettings.js';

const router = Router();

// 真实 provider 配了占位 unit_id 属于配置错误：喂给 SDK 会持续 load 失败。
// 下发时强制关闭该广告位并打日志，避免线上静默故障。
const PLACEHOLDER_UNITS = new Set([
  'splash_001',
  'reward_video_001',
  'reward_game_001',
  'interstitial_001',
]);

function slot(name, enabled, unitId, extra = {}) {
  if (enabled && config.ad.provider !== 'mock' && PLACEHOLDER_UNITS.has(unitId)) {
    console.warn(
      `[ad-config] ${name} 使用占位 unit_id "${unitId}"（provider=${config.ad.provider}），已下发 enabled=false，请配置 AD_UNIT_* 环境变量`
    );
    enabled = false;
  }
  return { enabled, unit_id: unitId, ...extra };
}

// 广告位配置下发。App 启动时拉取；接入真实广告 SDK 后只改服务端环境变量。
// rewarded_home（首页余额，走 task_token 发奖）与 rewarded_game（小游戏
// 本局补救，绝不发奖到钱包）是两个独立广告位，客户端不得混用。
router.get('/ad-config', async (req, res, next) => {
  try {
    const adSettings = await getRuntimeSettings('ad');
    const home = slot(
      'rewarded_home',
      adSettings.rewarded_enabled,
      config.ad.unitRewardedHome
    );
    res.json({
    provider: config.ad.provider,
    app_id: config.ad.hjAppId,
    splash: slot('splash', config.ad.splashEnabled, config.ad.unitSplash, {
      min_interval_sec: config.ad.splashMinIntervalSec,
      daily_max: config.ad.splashDailyMax,
    }),
    // rewarded = rewarded_home 的别名，兼容旧版 App（只认 rewarded 字段）
    rewarded: home,
    rewarded_home: home,
    rewarded_game: slot(
      'rewarded_game',
      config.ad.gameRewardedEnabled,
      config.ad.unitRewardedGame
    ),
    interstitial: slot(
      'interstitial',
      config.ad.interstitialEnabled,
      config.ad.unitInterstitial,
      {
        cooldown_sec: config.ad.interstitialCooldownSec,
        daily_max: config.ad.interstitialDailyMax,
      }
    ),
      reward_policy: {
        reward_microunits: adSettings.reward_microunits,
        daily_max: adSettings.daily_max,
      },
    });
  } catch (err) {
    next(err);
  }
});

router.get('/version', async (req, res, next) => {
  try {
    const platform = req.query.platform || 'android';
    const currentCode = Number(req.query.version_code) || 0;
    const { rows } = await query(
      `SELECT version_name, version_code, apk_url, force_update, changelog
       FROM app_versions WHERE platform = $1
       ORDER BY version_code DESC LIMIT 1`,
      [platform]
    );
    const latest = rows[0];
    if (!latest) {
      return res.json({ has_update: false });
    }
    res.json({
      has_update: latest.version_code > currentCode,
      ...latest,
    });
  } catch (err) {
    next(err);
  }
});

export default router;
