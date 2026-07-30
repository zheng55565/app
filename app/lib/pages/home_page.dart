// 额度Tab：统一额度、观看广告和小游戏入口。
import 'dart:async';

import 'package:flutter/material.dart';

import '../ads/ad_provider.dart';
import '../ads/ad_service.dart';
import '../api/api_client.dart';
import '../config.dart';
import '../preview/preview_data.dart';
import '../widgets/mini_game_card.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Map<String, dynamic>? _wallet;
  Map<String, dynamic>? _today;
  bool _watching = false;
  String? _lastRewardText;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (AppConfig.previewMode) {
      setState(() {
        _wallet = PreviewData.wallet();
        _today = PreviewData.adTask();
        _error = null;
      });
      return;
    }
    try {
      final previousWatched = (_today?['watched_count'] as num?)?.toInt();
      final api = ApiClient.instance;
      final wallet = await api.requestLegacy('GET', '/api/wallet');
      final today = await api.requestLegacy('GET', '/api/ad-task/today');
      if (!mounted) return;
      setState(() {
        _wallet = wallet;
        _today = today;
        _error = null;
        final nextWatched = (today['watched_count'] as num?)?.toInt();
        final pendingMessage =
            _lastRewardText?.contains('等待') == true ||
            _lastRewardText?.contains('验证') == true;
        if (previousWatched != null &&
            nextWatched != null &&
            nextWatched > previousWatched &&
            pendingMessage) {
          final usd = (today['reward_usd'] as num?) ?? 0;
          _lastRewardText = '+${_fmtUsd(usd)} 额度已到账';
        }
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '网络异常，请下拉刷新重试');
    }
  }

  /// 看广告：领任务 -> AdService 播放激励视频 -> 轮询到账 -> 刷新
  /// 记账原则（PRD §3.2）：到账以服务端广告回调 + 幂等发奖为准，客户端只轮询结果。
  ///
  /// 播放与轮询期间用户可切标签退出登录（销毁本页面），所以每个 await 之后
  /// 的 setState 都必须重查 mounted。
  Future<void> _watchAd() async {
    setState(() {
      _watching = true;
      _lastRewardText = null;
    });
    if (AppConfig.previewMode) {
      setState(() {
        _lastRewardText = '检查版未连接真实广告，不播放广告，也不会发放额度';
        _watching = false;
      });
      return;
    }
    final api = ApiClient.instance;
    var adCompleted = false;
    try {
      final task = await api.requestLegacy('POST', '/api/ad-task/start');
      final token = task['task_token'] as String;

      if (!mounted) return;
      setState(() => _lastRewardText = '广告播放中，无需下载应用；请按广告页提示完整观看');
      final outcome = await AdService.instance.showBalanceRewarded(
        context,
        taskToken: token,
      );
      if (!mounted) return;
      if (outcome.result == RewardedAdResult.disabled) {
        setState(() => _lastRewardText = '广告暂时不可用，请稍后再试');
        return;
      }
      if (outcome.result == RewardedAdResult.dismissed) {
        setState(() => _lastRewardText = '未看完广告，本次无奖励');
        return;
      }
      if (outcome.result == RewardedAdResult.failed) {
        setState(() => _lastRewardText = '广告播放失败，请稍后重试');
        return;
      }

      adCompleted = true;
      final transId = outcome.transId?.trim() ?? '';
      if (transId.isEmpty) {
        setState(() => _lastRewardText = '广告已播完，但平台未返回交易号，本次无法验证奖励');
        return;
      }
      setState(() => _lastRewardText = '广告已完成，正在登记交易并等待平台验证');

      // 客户端完成事件不直接发奖，只把 HJ transId 登记到任务上。
      // 最终仍必须收到 HJ 签名回调，防止脚本伪造该接口刷额度。
      var evidenceUploaded = false;
      for (var attempt = 0; attempt < 3 && mounted; attempt++) {
        try {
          await api.requestLegacy(
            'POST',
            '/api/ad-task/client-complete',
            body: {'task_token': token, 'transaction_id': transId},
          );
          evidenceUploaded = true;
          break;
        } catch (_) {
          if (attempt < 2) {
            await Future<void>.delayed(const Duration(milliseconds: 600));
          }
        }
      }
      if (!mounted) return;
      if (!evidenceUploaded) {
        setState(() => _lastRewardText = '广告交易登记失败，正在继续查询平台回调');
      }

      // 轮询到账（服务端确认后才算数）。SDK 完成与平台服务端回调并非同一时刻，
      // 查询偶发失败只影响状态展示，不能把已完成的广告误报成播放失败。
      var rewarded = false;
      var clientEvidenceReceived = evidenceUploaded;
      var platformCallbackReceived = false;
      for (var i = 0; i < 30 && mounted; i++) {
        try {
          final st = await api.requestLegacy(
            'GET',
            '/api/ad-task/status/$token',
          );
          if (!mounted) return;
          clientEvidenceReceived =
              st['client_evidence_received'] == true || clientEvidenceReceived;
          platformCallbackReceived = st['platform_callback_received'] == true;
          if (st['status'] == 'rewarded') {
            rewarded = true;
            final usd = (_today?['reward_usd'] as num?) ?? 0;
            setState(() => _lastRewardText = '+${_fmtUsd(usd)} 额度已到账');
            break;
          }
          if (st['status'] == 'expired' || st['status'] == 'failed') break;
        } catch (_) {
          // 继续轮询；最终仍按“回调待验证”展示，不误导用户重新看一次。
        }
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      if (!mounted) return;
      if (!rewarded) {
        setState(() {
          if (clientEvidenceReceived && !platformCallbackReceived) {
            _lastRewardText = '播放凭据已登记，仍在等待HJ平台回调；无需再次下载或观看';
          } else if (platformCallbackReceived && !clientEvidenceReceived) {
            _lastRewardText = '平台回调已到达，客户端凭据尚未登记；请稍后下拉刷新';
          } else {
            _lastRewardText = '广告已完成，奖励仍在验证；无需再次下载或观看';
          }
        });
      }
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(
        () => _lastRewardText = adCompleted
            ? '广告已完成，奖励状态暂时无法查询；请稍后下拉刷新'
            : e.message,
      );
    } catch (_) {
      if (!mounted) return;
      setState(
        () =>
            _lastRewardText = adCompleted ? '广告已完成，奖励验证中；请稍后下拉刷新' : '网络异常，请重试',
      );
    } finally {
      if (mounted) setState(() => _watching = false);
    }
  }

  /// microunits -> 元（1 元 = 1,000,000），中转站不可达时的降级展示
  static String _fmtAmount(num micro) =>
      '¥${(micro / 1000000).toStringAsFixed(2)}';

  /// 中转站额度（美元口径，与 new-api 显示一致）
  static String _fmtUsd(num usd) =>
      '\$${usd.abs() < 0.01 && usd != 0 ? usd.toStringAsFixed(4) : usd.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    // _wallet/_today 为 null 表示尚未加载成功：显示占位而非伪装成 0（PRD §3.1）
    final walletLoaded = _wallet != null;
    final todayLoaded = _today != null;
    final remaining = (_today?['remaining_count'] as num?) ?? 0;
    final watched = (_today?['watched_count'] as num?) ?? 0;
    final maxCount = (_today?['max_count'] as num?) ?? 6;
    final rewardUsd = (_today?['reward_usd'] as num?) ?? 0;
    final stationUsd = _wallet?['station_balance_usd'] as num?;

    return Scaffold(
      appBar: AppBar(title: const Text('额度与娱乐')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null)
              Card(
                color: const Color(0xFFD6336C),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            // ---- 模块 1：中转站额度（PRD §3.1）----
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Text(
                      '可用API额度',
                      style: TextStyle(color: Color(0xFF89A8CB)),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      !walletLoaded
                          ? '--'
                          : stationUsd != null
                          ? _fmtUsd(stationUsd)
                          : _fmtAmount(
                              (_wallet?['balance_microunits'] as num?) ?? 0,
                            ),
                      style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '可用于网站API、App工作台和生图，不可提现或转赠',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF89A8CB), fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      walletLoaded
                          ? '今日收益 ${_fmtUsd((_wallet?['today_earned_usd'] as num?) ?? 0)}'
                                ' · 累计 ${_fmtUsd((_wallet?['total_earned_usd'] as num?) ?? 0)}'
                          : (_error != null ? '加载失败，下拉刷新重试' : '加载中……'),
                      style: const TextStyle(
                        color: Color(0xFF89A8CB),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            // ---- 模块 2：观看广告（PRD §3.2）----
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(
                      todayLoaded
                          ? '今日已观看 $watched / $maxCount 次，单次奖励 ${_fmtUsd(rewardUsd)} 额度'
                          : (_error != null ? '任务信息加载失败' : '任务信息加载中……'),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: (_watching || !todayLoaded || remaining <= 0)
                          ? null
                          : _watchAd,
                      icon: _watching
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.play_circle_outline),
                      label: Text(
                        !todayLoaded
                            ? (_error != null ? '加载失败，下拉刷新重试' : '加载中……')
                            : remaining > 0
                            ? (_watching ? '播放中……' : '观看广告（剩余 $remaining 次）')
                            : '今日次数已用完',
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                    if (_lastRewardText != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _lastRewardText!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _lastRewardText!.startsWith('+')
                              ? const Color(0xFF2ED573)
                              : const Color(0xFF00C0F9),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            // ---- 模块 3：小游戏占位（PRD §3.3）----
            const MiniGameCard(),
          ],
        ),
      ),
    );
  }
}
