/// HJ 聚合广告 SDK Provider（基于 flutter_ads_plugin）
///
/// 激励视频流程：load（带 codeId/userId/透传参数）-> 等 onVideoAdLoadSuccess
/// -> show -> 按回调 complete：
/// - onVideoRewarded 且 isReward=true → earned（附 transId）
/// - onVideoAdClosed 且未拿到有效奖励 → dismissed
/// - load/play error、show 未 ready、超时 → failed
///
/// 隔离保证：home_balance 的 taskToken 通过 option（customData/extra）透传给
/// 广告平台做服务端回调；game_recovery 只透传 requestId，本类不发起任何
/// 网络请求——发奖与否完全由调用方按返回值处理。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_ads_plugin/flutter_ads_plugin.dart';

import 'ad_provider.dart';

class HjAdProvider implements AdProvider {
  AdConfig? _config;
  final FlutterAdsPlugin _plugin = FlutterAdsPlugin.instance;
  bool _sdkStarted = false;

  /// 广告加载超时（弱网下不让用户无限等待）
  static const _loadTimeout = Duration(seconds: 12);

  /// 单次播放会话（load→show→close 全程），用完即弃。
  /// 播放超时后不清空而是标记为僵尸（[_RewardSession.zombie]）：原生广告
  /// 可能仍在播放，此时新的 loadReward 会销毁播放中的实例（SDK 行为未定义），
  /// 必须等旧会话真正 closed/error 后才允许下一场。
  _RewardSession? _session;

  /// 个性化广告开关（个保法第 24 条要求提供关闭入口）。
  /// 由设置页调用 [setPersonalizedAd] 持久化后在下次 init 时生效。
  static bool personalizedAdOn = true;

  @override
  Future<void> init(AdConfig config) async {
    _config = config;
    if (_sdkStarted || config.appId.isEmpty) return;
    try {
      await _plugin.initAd(
        config.appId,
        debugEnable: false,
        personalizedAdOn: personalizedAdOn,
        adult: true,
      );
      _sdkStarted = true;
    } catch (_) {
      // SDK 初始化失败：后续 show* 都会走 failed，不抛异常
    }
  }

  @override
  void updateConfig(AdConfig config) {
    _config = config;
  }

  @override
  Future<bool> showSplash(covariant BuildContext context) async {
    // HJ 开屏是原生全屏窗口，走 loadAndShow；失败/超时直接放行
    final slot = _config?.splash;
    if (!_sdkStarted || slot == null || !slot.enabled || slot.unitId.isEmpty) {
      return false;
    }
    final done = Completer<bool>();
    try {
      await _plugin.loadAndShowSplash(
        slot.unitId,
        onSplashClosed: () {
          if (!done.isCompleted) done.complete(true);
        },
        onSplashAdFailToLoad: (_, __, ___) {
          if (!done.isCompleted) done.complete(false);
        },
      );
      return await done.future.timeout(
        const Duration(seconds: 8),
        onTimeout: () => false,
      );
    } catch (_) {
      return false;
    }
  }

  @override
  Future<RewardedOutcome> showRewarded(
    covariant BuildContext context, {
    required AdSlotConfig slot,
    required RewardedRequest request,
  }) async {
    if (!_sdkStarted || !slot.enabled || slot.unitId.isEmpty) {
      return RewardedOutcome.disabled;
    }
    // 上一场会话未结束（含播放超时后的僵尸态：原生广告可能仍在播，
    // 此时 loadReward 会销毁播放中的实例）一律拒绝
    if (_session != null) return RewardedOutcome.failed;

    final session = _RewardSession();
    _session = session;
    var zombie = false;
    try {
      // 透传参数：home_balance 带 task_token 供平台服务端回调；
      // game_recovery 带 requestId 仅作日志关联
      final option = <String, dynamic>{
        'purpose': request.purpose,
        if (request.taskToken != null) 'task_token': request.taskToken,
        if (request.requestId != null) 'request_id': request.requestId,
        if (request.gameId != null) 'game_id': request.gameId,
      };

      await _plugin.loadReward(
        slot.unitId,
        request.userId,
        option,
        onVideoAdLoadSuccess: (_) => session.loaded(),
        onVideoAdLoadError: (code, msg, _) => session.fail('load $code:$msg'),
        onVideoAdPlayError: (code, msg, _) => session.fail('play $code:$msg'),
        onVideoRewarded: (transId, isReward) =>
            session.rewarded(transId, isReward),
        onVideoAdClosed: () => session.closed(),
      );

      final ready = await session.waitLoaded.timeout(
        _loadTimeout,
        onTimeout: () => false,
      );
      if (!ready) return RewardedOutcome.failed;

      final shown = await _plugin.showReward(option);
      if (!shown) return RewardedOutcome.failed;

      // 等待关闭（播放最长几分钟，给足余量）。超时不能立刻放行下一场：
      // 原生广告可能还在播，标记僵尸，等真正 closed/error 时再释放会话
      try {
        return await session.waitOutcome
            .timeout(const Duration(minutes: 10));
      } on TimeoutException {
        zombie = true;
        session.waitOutcome.whenComplete(() {
          if (identical(_session, session)) _session = null;
        });
        return RewardedOutcome.failed;
      }
    } catch (_) {
      return RewardedOutcome.failed;
    } finally {
      if (!zombie) _session = null;
    }
  }

  @override
  Future<bool> showInterstitial(covariant BuildContext context) async {
    final slot = _config?.interstitial;
    if (!_sdkStarted || slot == null || !slot.enabled || slot.unitId.isEmpty) {
      return false;
    }
    final done = Completer<bool>();
    try {
      await _plugin.loadInterstitial(
        slot.unitId,
        onInterstitialAdLoadSuccess: (_) => _plugin.showInterstitial(),
        onInterstitialAdClosed: () {
          if (!done.isCompleted) done.complete(true);
        },
        onInterstitialAdLoadError: (_, __, ___) {
          if (!done.isCompleted) done.complete(false);
        },
        onInterstitialAdPlayError: (_, __, ___) {
          if (!done.isCompleted) done.complete(false);
        },
      );
      return await done.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () => false,
      );
    } catch (_) {
      return false;
    }
  }
}

/// 一次激励视频播放的状态机。事件乱序/重复时以奖励优先：
/// onVideoRewarded(isReward=true) 一旦出现，后续 play error / closed 都按
/// earned 收尾（部分联盟在片尾/关闭动画阶段误报 play error）。
class _RewardSession {
  final _loadedC = Completer<bool>();
  final _outcomeC = Completer<RewardedOutcome>();
  String? _transId;
  bool _isReward = false;

  Future<bool> get waitLoaded => _loadedC.future;
  Future<RewardedOutcome> get waitOutcome => _outcomeC.future;

  RewardedOutcome get _earnedOutcome =>
      RewardedOutcome(RewardedAdResult.earned, transId: _transId);

  void loaded() {
    if (!_loadedC.isCompleted) _loadedC.complete(true);
  }

  void fail(String reason) {
    if (!_loadedC.isCompleted) _loadedC.complete(false);
    if (_outcomeC.isCompleted) return;
    // 已拿到有效奖励的播放尾段报错不能吞掉奖励
    _outcomeC.complete(_isReward ? _earnedOutcome : RewardedOutcome.failed);
  }

  void rewarded(String transId, bool isReward) {
    // 只记录，等 closed 再定论——HJ 的 onVideoRewarded 先于 onVideoAdClosed
    _transId = transId;
    _isReward = isReward;
  }

  void closed() {
    if (_outcomeC.isCompleted) return;
    _outcomeC.complete(_isReward ? _earnedOutcome : RewardedOutcome.dismissed);
  }
}
