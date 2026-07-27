/// 首页 Tab（PRD §3）：中转站额度 / 观看广告 / 小游戏 三个模块
import 'dart:async';

import 'package:flutter/material.dart';

import '../ads/ad_provider.dart';
import '../ads/ad_service.dart';
import '../api/api_client.dart';
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
    try {
      final api = ApiClient.instance;
      final wallet = await api.requestLegacy('GET', '/api/wallet');
      final today = await api.requestLegacy('GET', '/api/ad-task/today');
      if (!mounted) return;
      setState(() {
        _wallet = wallet;
        _today = today;
        _error = null;
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
    final api = ApiClient.instance;
    try {
      final task = await api.requestLegacy('POST', '/api/ad-task/start');
      final token = task['task_token'] as String;

      if (!mounted) return;
      final result = await AdService.instance
          .showBalanceRewarded(context, taskToken: token);
      if (!mounted) return;
      if (result == RewardedAdResult.disabled) {
        setState(() => _lastRewardText = '广告暂时不可用，请稍后再试');
        return;
      }
      if (result == RewardedAdResult.dismissed) {
        setState(() => _lastRewardText = '未看完广告，本次无奖励');
        return;
      }
      if (result == RewardedAdResult.failed) {
        setState(() => _lastRewardText = '广告播放失败，请稍后重试');
        return;
      }

      // 轮询到账（服务端确认后才算数）
      var rewarded = false;
      for (var i = 0; i < 10 && mounted; i++) {
        final st = await api.requestLegacy('GET', '/api/ad-task/status/$token');
        if (!mounted) return;
        if (st['status'] == 'rewarded') {
          rewarded = true;
          final usd = (_today?['reward_usd'] as num?) ?? 0;
          setState(() => _lastRewardText = '+${_fmtUsd(usd)} 额度已到账');
          break;
        }
        await Future.delayed(const Duration(seconds: 1));
      }
      if (!mounted) return;
      if (!rewarded) {
        setState(() => _lastRewardText = '奖励处理中，稍后下拉刷新查看');
      }
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _lastRewardText = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _lastRewardText = '网络异常，请重试');
    } finally {
      if (mounted) setState(() => _watching = false);
    }
  }

  /// microunits -> 元（1 元 = 1,000,000），中转站不可达时的降级展示
  static String _fmtAmount(num micro) => '¥${(micro / 1000000).toStringAsFixed(2)}';

  /// 中转站额度（美元口径，与 new-api 显示一致）
  static String _fmtUsd(num usd) => '\$${usd.toStringAsFixed(2)}';

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
      appBar: AppBar(title: const Text('公益中转站')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null)
              Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_error!,
                      style: TextStyle(color: Colors.red.shade700)),
                ),
              ),
            // ---- 模块 1：中转站额度（PRD §3.1）----
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Text('中转站额度', style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 8),
                    Text(
                      !walletLoaded
                          ? '--'
                          : stationUsd != null
                              ? _fmtUsd(stationUsd)
                              : _fmtAmount(
                                  (_wallet?['balance_microunits'] as num?) ?? 0),
                      style: const TextStyle(
                          fontSize: 34, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      walletLoaded
                          ? '今日收益 ${_fmtUsd((_wallet?['today_earned_usd'] as num?) ?? 0)}'
                              ' · 累计 ${_fmtUsd((_wallet?['total_earned_usd'] as num?) ?? 0)}'
                          : (_error != null ? '加载失败，下拉刷新重试' : '加载中……'),
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
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
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.play_circle_outline),
                      label: Text(!todayLoaded
                          ? (_error != null ? '加载失败，下拉刷新重试' : '加载中……')
                          : remaining > 0
                              ? (_watching ? '播放中……' : '观看广告（剩余 $remaining 次）')
                              : '今日次数已用完'),
                      style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14)),
                    ),
                    if (_lastRewardText != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _lastRewardText!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _lastRewardText!.startsWith('+')
                              ? Colors.green.shade700
                              : Colors.orange.shade800,
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
