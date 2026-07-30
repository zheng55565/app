// Mock广告提供方：用于本地可视化联调开屏、激励视频和插屏流程。
import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import 'ad_provider.dart';

class MockAdProvider implements AdProvider {
  AdConfig? _config;

  @override
  Future<void> init(AdConfig config) async {
    _config = config;
  }

  @override
  void updateConfig(AdConfig config) {
    _config = config;
  }

  @override
  Future<bool> showSplash(covariant BuildContext context) async {
    if (!(_config?.splash.enabled ?? false)) return false;
    if (!context.mounted) return false;
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        pageBuilder: (_, _, _) => const _MockSplashPage(),
      ),
    );
    return true;
  }

  @override
  Future<RewardedOutcome> showRewarded(
    covariant BuildContext context, {
    required AdSlotConfig slot,
    required RewardedRequest request,
  }) async {
    if (!slot.enabled) return RewardedOutcome.disabled;
    if (!context.mounted) return RewardedOutcome.failed;
    final watched = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _MockRewardedDialog(),
    );
    final transId =
        'mock_${DateTime.now().millisecondsSinceEpoch}_${request.requestId ?? request.taskToken ?? ''}';
    if (watched != true) return RewardedOutcome.dismissed;

    // 小游戏补救广告：只回传本局结果，绝不触碰任何发奖接口
    if (request.purpose == 'game_recovery') {
      return RewardedOutcome(RewardedAdResult.earned, transId: transId);
    }

    // 首页余额广告：模拟广告平台服务端回调
    // （真实 SDK 场景由平台服务器直接回调后端，App 不参与）
    try {
      await ApiClient.instance.requestLegacy(
        'POST',
        '/api/ad-task/dev-complete',
        body: {'task_token': request.taskToken},
      );
      return RewardedOutcome(RewardedAdResult.earned, transId: transId);
    } on ApiException {
      return RewardedOutcome.failed;
    } catch (_) {
      return RewardedOutcome.failed;
    }
  }

  @override
  Future<bool> showInterstitial(covariant BuildContext context) async {
    if (!(_config?.interstitial.enabled ?? false)) return false;
    if (!context.mounted) return false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        child: Container(
          color: Colors.black87,
          child: Stack(
            children: [
              const Center(
                child: Text(
                  '模拟插屏广告',
                  style: TextStyle(color: Colors.white, fontSize: 24),
                ),
              ),
              Positioned(
                top: 48,
                right: 16,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return true;
  }
}

/// 模拟开屏页：3 秒倒计时，右上角可跳过
class _MockSplashPage extends StatefulWidget {
  const _MockSplashPage();

  @override
  State<_MockSplashPage> createState() => _MockSplashPageState();
}

class _MockSplashPageState extends State<_MockSplashPage> {
  int _seconds = 3;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_seconds <= 1) {
        t.cancel();
        _close();
      } else {
        setState(() => _seconds--);
      }
    });
  }

  /// 关闭开屏页。pop 后的退出动画期间 State 仍 mounted，倒计时若在此窗口
  /// 到点会二次 pop 弹掉底下刚推入的页面（黑屏），因此必须先确认本路由
  /// 仍是栈顶（isCurrent）才 pop。
  void _close() {
    _timer?.cancel();
    if (ModalRoute.of(context)?.isCurrent == true) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.deepPurple.shade900,
      body: SafeArea(
        child: Stack(
          children: [
            const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.campaign, size: 96, color: Colors.white70),
                  SizedBox(height: 16),
                  Text(
                    '模拟开屏广告',
                    style: TextStyle(color: Colors.white, fontSize: 22),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: Colors.black38,
                  foregroundColor: Colors.white,
                ),
                onPressed: _close,
                child: Text('跳过 $_seconds'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 模拟激励视频：5 秒倒计时，结束后才能领取奖励；中途关闭无奖励
class _MockRewardedDialog extends StatefulWidget {
  const _MockRewardedDialog();

  @override
  State<_MockRewardedDialog> createState() => _MockRewardedDialogState();
}

class _MockRewardedDialogState extends State<_MockRewardedDialog> {
  int _seconds = 5;
  Timer? _timer;

  bool get _done => _seconds <= 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_seconds <= 1) {
        t.cancel();
        setState(() => _seconds = 0);
      } else {
        setState(() => _seconds--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: Container(
        color: Colors.black,
        child: SafeArea(
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _done ? Icons.check_circle : Icons.play_circle_fill,
                      size: 96,
                      color: _done ? Colors.greenAccent : Colors.white70,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _done ? '播放完成' : '模拟激励视频播放中… $_seconds 秒',
                      style: const TextStyle(color: Colors.white, fontSize: 20),
                    ),
                    const SizedBox(height: 32),
                    if (_done)
                      FilledButton.icon(
                        icon: const Icon(Icons.card_giftcard),
                        label: const Text('领取奖励'),
                        onPressed: () => Navigator.of(context).pop(true),
                      ),
                  ],
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
