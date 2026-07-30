// 广告服务门面：业务层唯一入口。
//
// 职责：远程配置、provider选择、频控、隐私门禁和激励广告全局互斥。
// 首页余额广告携带taskToken并由服务端回调发奖；游戏补救广告只影响本局。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/api_client.dart';
import '../auth/auth_service.dart';
import 'ad_provider.dart';
import 'hj_ad_provider.dart';
import 'mock_ad_provider.dart';

class AdService {
  AdService._();
  static final AdService instance = AdService._();

  static const _storage = FlutterSecureStorage();
  static const _kConfigCache = 'ad_config_cache';
  static const _kConsent = 'ad_sdk_consent';
  static const _kInterstitialDaily = 'ad_interstitial_daily';
  static const _kSplashDaily = 'ad_splash_daily';

  /// 配置视为新鲜的时长；超过后在广告入口静默重拉，让远程开关在长会话中生效
  static const _configTtl = Duration(minutes: 30);

  AdConfig _config = AdConfig.fallback;
  AdProvider _provider = DisabledAdProvider();
  bool _initialized = false;
  bool _consentGranted = false;
  DateTime? _lastConfigFetchAt;
  DateTime? _lastInterstitialAt;
  int _interstitialShownToday = 0;
  String _interstitialCountDate = '';
  int _splashShownToday = 0;
  String _splashCountDate = '';
  DateTime? _lastSplashAt;

  /// 激励广告全局互斥：同一时间只允许一个激励广告在播（首页/游戏共用一把锁）
  bool _rewardedShowing = false;

  /// 已消费过的 game_recovery requestId（同一请求绝不重复出结果）
  final Set<String> _consumedRequestIds = <String>{};

  AdConfig get config => _config;
  bool get splashEnabled => _config.splash.enabled;
  bool get rewardedEnabled => _config.rewardedHome.enabled;
  bool get gameRewardedEnabled => _config.rewardedGame.enabled;
  bool get requiresConsent => _config.provider != 'mock' && !_consentGranted;

  /// App 启动时调用。任何失败都不阻塞启动。
  Future<void> init() async {
    await initConfig();
    await initSdk();
  }

  /// 第一步：确定生效配置。优先远程，失败用上次成功的本地缓存，
  /// 再失败才用 [AdConfig.fallback]（全部禁用）。
  /// 绝不因一次网络抖动把真实 provider 静默换成 mock。
  Future<void> initConfig() async {
    final cached = await _readCache();
    if (cached != null) _config = cached;
    _consentGranted = await _storage.read(key: _kConsent) == 'true';
    await _refreshConfig();
  }

  /// 第二步：初始化广告 provider/SDK（隐私门禁在 [_createProvider] 内强制）。
  Future<void> initSdk() async {
    _provider = _createProvider(_config.provider);
    await _provider.init(_config);
    _initialized = true;
  }

  /// 用户同意隐私政策后调用（持久化，后续启动直接放行真实 SDK）。
  /// 若当前因未同意被降级为 Disabled，立即用真实 provider 重新初始化。
  Future<void> grantConsent() async {
    _consentGranted = true;
    await _storage.write(key: _kConsent, value: 'true');
    if ((!_initialized || _provider is DisabledAdProvider) &&
        _config.provider != 'mock') {
      await initSdk();
    }
  }

  /// 拉取远程配置；成功则更新内存/缓存并同步 provider 快照，
  /// 失败保持现状（缓存或 fallback）。
  Future<void> _refreshConfig() async {
    try {
      final json = await ApiClient.instance.requestLegacy(
        'GET',
        '/api/app/ad-config',
        auth: false,
      );
      _config = AdConfig.fromJson(json);
      _lastConfigFetchAt = DateTime.now();
      await _storage.write(key: _kConfigCache, value: jsonEncode(json));
      // 开关/频控热更新到 provider（provider 种类切换仍需冷重启）
      _provider.updateConfig(_config);
    } catch (_) {
      // 静默：远程开关的实时性由入口处的 _refreshConfigIfStale 兜底
    }
  }

  /// 本会话从未拉到过配置、或配置已超过 TTL 时重拉一次。
  Future<void> _refreshConfigIfStale() async {
    final last = _lastConfigFetchAt;
    if (last == null || DateTime.now().difference(last) > _configTtl) {
      await _refreshConfig();
    }
  }

  Future<AdConfig?> _readCache() async {
    try {
      final raw = await _storage.read(key: _kConfigCache);
      if (raw == null) return null;
      return AdConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// 隐私门禁 + provider 选择。未知 provider 一律 Disabled（绝不回落 mock）。
  AdProvider _createProvider(String name) {
    // 真实 SDK 必须在用户同意隐私政策之后才能初始化（mock 不采集，不受限）
    if (name != 'mock' && !_consentGranted) return DisabledAdProvider();
    switch (name) {
      case 'hj':
        return HjAdProvider();
      case 'mock':
        return MockAdProvider();
      default:
        return DisabledAdProvider();
    }
  }

  String get _adUserId =>
      AuthService.instance.currentUser?.userId?.toString() ?? '';

  /// 开屏广告（冷启动）。未初始化/未启用/失败都直接放行。
  Future<void> maybeShowSplash(BuildContext context) async {
    if (!_initialized || !_config.splash.enabled) return;
    final now = DateTime.now();
    await _loadSplashCount(now);
    final dailyMax = _config.splash.dailyMax;
    if (dailyMax > 0 && _splashShownToday >= dailyMax) return;
    final minInterval = Duration(seconds: _config.splash.minIntervalSec);
    if (_lastSplashAt != null && now.difference(_lastSplashAt!) < minInterval) {
      return;
    }
    if (!context.mounted) return;
    final shown = await _provider.showSplash(context);
    if (!shown) return;
    _lastSplashAt = now;
    _splashShownToday++;
    await _storage.write(
      key: _kSplashDaily,
      value:
          '$_splashCountDate|$_splashShownToday|${now.millisecondsSinceEpoch}',
    );
  }

  Future<void> _loadSplashCount(DateTime now) async {
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    if (_splashCountDate == today) return;
    _splashCountDate = today;
    _splashShownToday = 0;
    _lastSplashAt = null;
    try {
      final raw = await _storage.read(key: _kSplashDaily);
      final parts = raw?.split('|');
      if (parts != null && parts.length == 3 && parts[0] == today) {
        _splashShownToday = int.tryParse(parts[1]) ?? 0;
        final lastMs = int.tryParse(parts[2]);
        if (lastMs != null) {
          _lastSplashAt = DateTime.fromMillisecondsSinceEpoch(lastMs);
        }
      }
    } catch (_) {
      // 频控状态读取失败时按本次会话重新计数，不阻塞启动。
    }
  }

  /// 首页余额广告（发奖核心流程）。
  /// 远程总闸在此统一拦截：后端 AD_REWARDED_ENABLED=false 时不发版即可下线。
  Future<RewardedOutcome> showBalanceRewarded(
    BuildContext context, {
    required String taskToken,
  }) async {
    if (!_initialized) return RewardedOutcome.disabled;
    await _refreshConfigIfStale();
    if (!_config.rewardedHome.enabled) return RewardedOutcome.disabled;
    if (_adUserId.isEmpty) return RewardedOutcome.failed;
    if (!context.mounted) return RewardedOutcome.failed;
    if (_rewardedShowing) return RewardedOutcome.failed;
    _rewardedShowing = true;
    try {
      return await _provider.showRewarded(
        context,
        slot: _config.rewardedHome,
        request: RewardedRequest.homeBalance(
          taskToken: taskToken,
          userId: _adUserId,
        ),
      );
    } finally {
      _rewardedShowing = false;
    }
  }

  /// 小游戏补救广告。只返回播放结果（含 transId），此路径与钱包/任务系统
  /// 完全隔离：不调 /api/ad-task/*，不产生任何余额变化。
  /// [requestId] 全局去重——同一 id 第二次调用直接返回 failed，防止游戏侧
  /// 重复请求刷出两次奖励。
  Future<RewardedOutcome> showGameRecoveryRewarded(
    BuildContext context, {
    required String taskToken,
    required String gameId,
    required String recoveryType,
    required String requestId,
  }) async {
    if (!_initialized) return RewardedOutcome.disabled;
    if (requestId.isEmpty || _consumedRequestIds.contains(requestId)) {
      return RewardedOutcome.failed;
    }
    _consumedRequestIds.add(requestId);
    if (_consumedRequestIds.length > 500) {
      // 防无限增长：会话内保留最近 500 个即可
      _consumedRequestIds.remove(_consumedRequestIds.first);
    }
    await _refreshConfigIfStale();
    if (!_config.rewardedGame.enabled) return RewardedOutcome.disabled;
    if (!context.mounted) return RewardedOutcome.failed;
    if (_rewardedShowing) return RewardedOutcome.failed;
    _rewardedShowing = true;
    try {
      return await _provider.showRewarded(
        context,
        slot: _config.rewardedGame,
        request: RewardedRequest.gameRecovery(
          taskToken: taskToken,
          gameId: gameId,
          recoveryType: recoveryType,
          requestId: requestId,
          userId: _adUserId,
        ),
      );
    } finally {
      _rewardedShowing = false;
    }
  }

  /// 插屏广告：带本地频控（冷却间隔 + 每日上限均由服务端下发，可远程调整）。
  Future<void> maybeShowInterstitial(BuildContext context) async {
    if (!_initialized) return;
    await _refreshConfigIfStale();
    if (!_config.interstitial.enabled) return;
    if (!context.mounted) return;

    final now = DateTime.now();
    final cooldown = Duration(seconds: _config.interstitial.cooldownSec);
    if (_lastInterstitialAt != null &&
        now.difference(_lastInterstitialAt!) < cooldown) {
      return;
    }
    await _loadInterstitialCount(now);
    final dailyMax = _config.interstitial.dailyMax;
    if (dailyMax > 0 && _interstitialShownToday >= dailyMax) return;
    if (!context.mounted) return;

    final shown = await _provider.showInterstitial(context);
    if (shown) {
      _lastInterstitialAt = now;
      _interstitialShownToday++;
      await _storage.write(
        key: _kInterstitialDaily,
        value: '$_interstitialCountDate|$_interstitialShownToday',
      );
    }
  }

  /// 每日插屏计数（持久化，跨重启生效；跨天自动清零）
  Future<void> _loadInterstitialCount(DateTime now) async {
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    if (_interstitialCountDate == today) return;
    _interstitialCountDate = today;
    _interstitialShownToday = 0;
    try {
      final raw = await _storage.read(key: _kInterstitialDaily);
      final parts = raw?.split('|');
      if (parts != null && parts.length == 2 && parts[0] == today) {
        _interstitialShownToday = int.tryParse(parts[1]) ?? 0;
      }
    } catch (_) {
      // 读失败按 0 计，最坏多展示几次，不影响核心业务
    }
  }
}
