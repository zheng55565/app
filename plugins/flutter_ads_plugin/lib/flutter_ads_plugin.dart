/// flutter_ads_plugin — HJ 聚合广告 SDK 的 Flutter 封装
///
/// 修复说明（相对初版）：
/// - 每个 EventChannel 只维护一份持久订阅，load* 只替换回调处理器，
///   不再每次 load 重复 listen 产生重复回调；
/// - 激励视频事件按会话 nonce 过滤：loadReward 时下发自增 nonce，原生在
///   每个事件里回带，Dart 侧丢弃 nonce 不匹配的迟到/重复事件，双广告位
///   交替使用时旧播放的事件不会串进新会话；
/// - onVideoRewarded 透传原生侧 isReward 校验结果（HJRewardVerify）。
import 'dart:async';

import 'package:flutter/services.dart';

typedef OnSplashAdSuccessPresent = void Function();
typedef OnSplashAdSuccessLoad = void Function(String placementId);
typedef OnSplashAdFailToLoad = void Function(String code, String msg, String placementId);
typedef OnSplashAdClicked = void Function();
typedef OnSplashClosed = void Function();

typedef OnInterstitialAdLoadSuccess = void Function(String placementId);
typedef OnInterstitialAdPlayStart = void Function();
typedef OnInterstitialAdPlayEnd = void Function();
typedef OnInterstitialAdClicked = void Function();
typedef OnInterstitialAdClosed = void Function();
typedef OnInterstitialAdLoadError = void Function(String code, String msg, String placementId);
typedef OnInterstitialAdPlayError = void Function(String code, String msg, String placementId);

typedef OnVideoAdLoadSuccess = void Function(String placementId);
typedef OnVideoAdPlayEnd = void Function();
typedef OnVideoAdPlayStart = void Function();
typedef OnVideoAdClicked = void Function();

/// [isReward] 为原生侧 HJRewardVerify.isReward() 的结果；false 表示广告平台
/// 判定本次播放不满足发奖条件，调用方不得发奖。
typedef OnVideoRewarded = void Function(String transId, bool isReward);
typedef OnVideoAdClosed = void Function();
typedef OnVideoAdLoadError = void Function(String code, String msg, String placementId);
typedef OnVideoAdPlayError = void Function(String code, String msg, String placementId);

class _RewardHandlers {
  OnVideoAdLoadSuccess? onLoadSuccess;
  OnVideoAdPlayEnd? onPlayEnd;
  OnVideoAdPlayStart? onPlayStart;
  OnVideoAdClicked? onClicked;
  OnVideoRewarded? onRewarded;
  OnVideoAdClosed? onClosed;
  OnVideoAdLoadError? onLoadError;
  OnVideoAdPlayError? onPlayError;
}

class _SplashHandlers {
  OnSplashAdSuccessPresent? onSuccessPresent;
  OnSplashAdSuccessLoad? onSuccessLoad;
  OnSplashAdFailToLoad? onFailToLoad;
  OnSplashAdClicked? onClicked;
  OnSplashClosed? onClosed;
}

class _InterstitialHandlers {
  OnInterstitialAdLoadSuccess? onLoadSuccess;
  OnInterstitialAdPlayStart? onPlayStart;
  OnInterstitialAdPlayEnd? onPlayEnd;
  OnInterstitialAdClicked? onClicked;
  OnInterstitialAdClosed? onClosed;
  OnInterstitialAdLoadError? onLoadError;
  OnInterstitialAdPlayError? onPlayError;
}

class FlutterAdsPlugin {
  FlutterAdsPlugin._();
  static final FlutterAdsPlugin instance = FlutterAdsPlugin._();

  /// 兼容旧用法 `FlutterAdsPlugin()`，仍返回单例
  factory FlutterAdsPlugin() => instance;

  static const MethodChannel _method =
      MethodChannel('flutter_ads_plugin/method');
  static const EventChannel _splashEvents =
      EventChannel('flutter_ads_plugin/events_SplashAd');
  static const EventChannel _interstitialEvents =
      EventChannel('flutter_ads_plugin/events_InterstitialAd');
  static const EventChannel _rewardEvents =
      EventChannel('flutter_ads_plugin/events_RewardAd');

  StreamSubscription? _splashSub;
  StreamSubscription? _interstitialSub;
  StreamSubscription? _rewardSub;

  final _SplashHandlers _splash = _SplashHandlers();
  final _InterstitialHandlers _interstitial = _InterstitialHandlers();
  final _RewardHandlers _reward = _RewardHandlers();

  Future<void> logd(String msg) =>
      _method.invokeMethod<void>('log', {'msg': msg});

  /// SDK 初始化。必须在用户同意隐私政策后调用。
  /// [debugEnable]/[personalizedAdOn]/[adult] 生产环境按合规配置。
  Future<void> initAd(
    String initId, {
    bool debugEnable = false,
    bool personalizedAdOn = true,
    bool adult = true,
  }) =>
      _method.invokeMethod<void>('init', {
        'initId': initId,
        'debugEnable': debugEnable,
        'personalizedAdOn': personalizedAdOn,
        'adult': adult,
      });

  // ---------- 开屏 ----------

  void _ensureSplashSub() {
    _splashSub ??= _splashEvents.receiveBroadcastStream().listen((event) {
      final e = (event as Map).cast<String, dynamic>();
      switch (e['event']) {
        case 'onSplashAdSuccessPresent':
          _splash.onSuccessPresent?.call();
        case 'onSplashAdSuccessLoad':
          _splash.onSuccessLoad?.call(e['placementId'] as String? ?? '');
        case 'onSplashAdFailToLoad':
          _splash.onFailToLoad?.call(
              '${e['code']}', '${e['msg']}', e['placementId'] as String? ?? '');
        case 'onSplashAdClicked':
          _splash.onClicked?.call();
        case 'onSplashClosed':
          _splash.onClosed?.call();
      }
    });
  }

  Future<void> loadSplash(
    String codeId, {
    OnSplashAdSuccessPresent? onSplashAdSuccessPresent,
    OnSplashAdSuccessLoad? onSplashAdSuccessLoad,
    OnSplashAdFailToLoad? onSplashAdFailToLoad,
    OnSplashAdClicked? onSplashAdClicked,
    OnSplashClosed? onSplashClosed,
  }) {
    _ensureSplashSub();
    _splash
      ..onSuccessPresent = onSplashAdSuccessPresent
      ..onSuccessLoad = onSplashAdSuccessLoad
      ..onFailToLoad = onSplashAdFailToLoad
      ..onClicked = onSplashAdClicked
      ..onClosed = onSplashClosed;
    return _method.invokeMethod<void>('loadSplash', {'codeId': codeId});
  }

  Future<void> showSplash() => _method.invokeMethod<void>('showSplash');

  Future<void> loadAndShowSplash(
    String codeId, {
    OnSplashAdSuccessPresent? onSplashAdSuccessPresent,
    OnSplashAdSuccessLoad? onSplashAdSuccessLoad,
    OnSplashAdFailToLoad? onSplashAdFailToLoad,
    OnSplashAdClicked? onSplashAdClicked,
    OnSplashClosed? onSplashClosed,
  }) {
    _ensureSplashSub();
    _splash
      ..onSuccessPresent = onSplashAdSuccessPresent
      ..onSuccessLoad = onSplashAdSuccessLoad
      ..onFailToLoad = onSplashAdFailToLoad
      ..onClicked = onSplashAdClicked
      ..onClosed = onSplashClosed;
    return _method.invokeMethod<void>('loadAndShowSplash', {'codeId': codeId});
  }

  // ---------- 插屏 ----------

  void _ensureInterstitialSub() {
    _interstitialSub ??=
        _interstitialEvents.receiveBroadcastStream().listen((event) {
      final e = (event as Map).cast<String, dynamic>();
      switch (e['event']) {
        case 'onInterstitialAdLoadSuccess':
          _interstitial.onLoadSuccess?.call(e['placementId'] as String? ?? '');
        case 'onInterstitialAdPlayStart':
          _interstitial.onPlayStart?.call();
        case 'onInterstitialAdPlayEnd':
          _interstitial.onPlayEnd?.call();
        case 'onInterstitialAdClicked':
          _interstitial.onClicked?.call();
        case 'onInterstitialAdClosed':
          _interstitial.onClosed?.call();
        case 'onInterstitialAdLoadError':
          _interstitial.onLoadError?.call(
              '${e['code']}', '${e['msg']}', e['placementId'] as String? ?? '');
        case 'onInterstitialAdPlayError':
          _interstitial.onPlayError?.call(
              '${e['code']}', '${e['msg']}', e['placementId'] as String? ?? '');
      }
    });
  }

  Future<void> loadInterstitial(
    String codeId, {
    OnInterstitialAdLoadSuccess? onInterstitialAdLoadSuccess,
    OnInterstitialAdPlayStart? onInterstitialAdPlayStart,
    OnInterstitialAdPlayEnd? onInterstitialAdPlayEnd,
    OnInterstitialAdClicked? onInterstitialAdClicked,
    OnInterstitialAdClosed? onInterstitialAdClosed,
    OnInterstitialAdLoadError? onInterstitialAdLoadError,
    OnInterstitialAdPlayError? onInterstitialAdPlayError,
  }) {
    _ensureInterstitialSub();
    _interstitial
      ..onLoadSuccess = onInterstitialAdLoadSuccess
      ..onPlayStart = onInterstitialAdPlayStart
      ..onPlayEnd = onInterstitialAdPlayEnd
      ..onClicked = onInterstitialAdClicked
      ..onClosed = onInterstitialAdClosed
      ..onLoadError = onInterstitialAdLoadError
      ..onPlayError = onInterstitialAdPlayError;
    return _method.invokeMethod<void>('loadInterstitial', {'codeId': codeId});
  }

  Future<void> showInterstitial() =>
      _method.invokeMethod<void>('showInterstitial');

  // ---------- 激励视频 ----------

  /// 当前激励视频会话 nonce。loadReward 自增并随 method call 下发，
  /// 原生在每个事件 Map 里回带；不匹配的事件属于旧会话，直接丢弃。
  int _rewardNonce = 0;

  void _ensureRewardSub() {
    _rewardSub ??= _rewardEvents.receiveBroadcastStream().listen((event) {
      final e = (event as Map).cast<String, dynamic>();
      final nonce = e['nonce'];
      if (nonce is num && nonce.toInt() != _rewardNonce) return; // 旧会话迟到事件
      switch (e['event']) {
        case 'onVideoAdLoadSuccess':
          _reward.onLoadSuccess?.call(e['placementId'] as String? ?? '');
        case 'onVideoAdPlayEnd':
          _reward.onPlayEnd?.call();
        case 'onVideoAdPlayStart':
          _reward.onPlayStart?.call();
        case 'onVideoAdClicked':
          _reward.onClicked?.call();
        case 'onVideoRewarded':
          _reward.onRewarded?.call(
              e['transId'] as String? ?? '', e['isReward'] as bool? ?? false);
        case 'onVideoAdClosed':
          _reward.onClosed?.call();
        case 'onVideoAdLoadError':
          _reward.onLoadError?.call(
              '${e['code']}', '${e['msg']}', e['placementId'] as String? ?? '');
        case 'onVideoAdPlayError':
          _reward.onPlayError?.call(
              '${e['code']}', '${e['msg']}', e['placementId'] as String? ?? '');
      }
    });
  }

  /// 加载激励视频。重复调用会替换回调处理器并递增会话 nonce（旧播放的
  /// 迟到事件按 nonce 过滤丢弃）。codeId/userId 变化时原生侧销毁重建实例。
  Future<void> loadReward(
    String codeId,
    String userId,
    Map<String, dynamic> option, {
    OnVideoAdLoadSuccess? onVideoAdLoadSuccess,
    OnVideoAdPlayEnd? onVideoAdPlayEnd,
    OnVideoAdPlayStart? onVideoAdPlayStart,
    OnVideoAdClicked? onVideoAdClicked,
    OnVideoRewarded? onVideoRewarded,
    OnVideoAdClosed? onVideoAdClosed,
    OnVideoAdLoadError? onVideoAdLoadError,
    OnVideoAdPlayError? onVideoAdPlayError,
  }) {
    _ensureRewardSub();
    _rewardNonce++;
    _reward
      ..onLoadSuccess = onVideoAdLoadSuccess
      ..onPlayEnd = onVideoAdPlayEnd
      ..onPlayStart = onVideoAdPlayStart
      ..onClicked = onVideoAdClicked
      ..onRewarded = onVideoRewarded
      ..onClosed = onVideoAdClosed
      ..onLoadError = onVideoAdLoadError
      ..onPlayError = onVideoAdPlayError;
    return _method.invokeMethod<void>('loadReward', {
      'codeId': codeId,
      'userId': userId,
      'option': option,
      'nonce': _rewardNonce,
    });
  }

  /// 展示已加载的激励视频。返回 false 表示广告未 ready（未加载/已消费），
  /// 调用方不应等待任何播放事件。
  Future<bool> showReward(Map<String, dynamic> option) async {
    final shown =
        await _method.invokeMethod<bool>('showReward', {'option': option});
    return shown ?? false;
  }

  /// 释放事件订阅（一般不需要调用；热重启/测试用）
  Future<void> dispose() async {
    await _splashSub?.cancel();
    await _interstitialSub?.cancel();
    await _rewardSub?.cancel();
    _splashSub = null;
    _interstitialSub = null;
    _rewardSub = null;
  }
}
