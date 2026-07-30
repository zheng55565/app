import { Router } from 'express';

import { config } from '../config.js';
import { getRuntimeSettings } from '../services/runtimeSettings.js';

const router = Router();

// 只下发公开能力，不返回中转站地址、管理令牌或上游密钥。
router.get('/config', async (req, res, next) => {
  try {
    const [aiSettings, adSettings] = await Promise.all([
      getRuntimeSettings('ai'),
      getRuntimeSettings('ad'),
    ]);
    const stationPublicBaseUrl = config.station.publicBaseUrl || null;
    const openaiCompatibleBaseUrl = stationPublicBaseUrl
      ? (/\/v1$/i.test(stationPublicBaseUrl)
          ? stationPublicBaseUrl
          : `${stationPublicBaseUrl}/v1`)
      : null;
    res.setHeader('Cache-Control', 'public, max-age=60');
    res.json({
    app_name: config.appName,
    public_base_url: config.baseUrl,
    station_public_base_url: stationPublicBaseUrl,
    openai_compatible_base_url: openaiCompatibleBaseUrl,
    api_entry: 'platform_proxy',
    station_address_exposed: false,
    features: {
      workbench: aiSettings.enabled,
      image_generation: aiSettings.enabled && aiSettings.image_models.length > 0,
      documents: aiSettings.enabled && config.documents.enabled,
      web_search: false,
      rewarded_ads: adSettings.rewarded_enabled,
      games: true,
    },
    ai: {
      gateway_mode: 'platform_new_api',
      user_api_key_supported: config.ai.allowUserApiKey,
      shared_access_enabled: Boolean(config.ai.sharedApiKey),
      custom_upstream_url_supported: false,
      chat_models_dynamic: true,
      image_models: aiSettings.image_models,
      max_concurrent_per_user: config.ai.maxConcurrentPerUser,
      max_output_tokens: config.ai.maxOutputTokens,
    },
    quota: {
      ledger: 'platform_new_api',
      usable_for_platform_api: true,
      usable_for_external_stations: false,
      transferable: false,
      withdrawable: false,
    },
    rewarded_ads: {
      reward_microunits: adSettings.reward_microunits,
      daily_max_per_account: adSettings.daily_max,
      daily_max_per_device: adSettings.device_daily_max,
      business_timezone: config.ad.businessTimezone,
    },
    });
  } catch (err) {
    next(err);
  }
});

export default router;
