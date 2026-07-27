/// 小游戏页面：WebView 承载 Unity WebGL，JavaScriptChannel 双向通信
///
/// 通信协议（与 Unity 侧 jslib 桥接约定）：
/// Unity -> Flutter（经 window.GongyiBridge.postMessage）：
///   {"type":"game_reward_request","requestId":"...","gameId":"snake","recoveryType":"revive"}
///   {"type":"game_ready"}   // 可选：游戏加载完成
///   {"type":"game_exit"}    // 可选：请求返回 App
/// Flutter -> Unity（经 evaluateJavascript 调 window.onGongyiMessage(json)）：
///   {"type":"game_reward_result","requestId":"原样返回","result":"earned|dismissed|failed","transId":"..."}
///
/// 隔离铁律：本页面的广告只走 AdService.showGameRecoveryRewarded
/// （rewarded_game 广告位），绝不调用 /api/ad-task/start、不轮询余额、
/// 不触碰首页每日次数。requestId 两端各自去重，一次请求只消费一次。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../ads/ad_provider.dart';
import '../ads/ad_service.dart';
import '../config.dart';

class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> with WidgetsBindingObserver {
  late final WebViewController _controller;
  bool _loading = true;
  String? _loadError;

  /// 本页已处理过的 requestId（Flutter 侧第一道去重；AdService 内还有一道）
  final Set<String> _handledRequestIds = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel(
        'GongyiBridge',
        onMessageReceived: (msg) => _onGameMessage(msg.message),
      )
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
        },
        onWebResourceError: (e) {
          // 只处理主文档加载失败；子资源错误不整页报错
          if (e.isForMainFrame == true && mounted) {
            setState(() {
              _loading = false;
              _loadError = '小游戏加载失败（${e.errorCode}），请检查网络后重试';
            });
          }
        },
      ))
      ..loadRequest(Uri.parse(AppConfig.gameUrl));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // 卸载页面内容：否则原生 WebView 要等 Dart GC 才销毁，Unity 的
    // WebAudio 音乐/WASM 逻辑会在返回首页后继续跑
    _controller.loadRequest(Uri.parse('about:blank'));
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 切后台暂停游戏（Chromium 不会自动停 WebAudio）；回前台恢复。
    // 通知型消息，游戏侧未实现 onGongyiMessage 时静默无害。
    if (state == AppLifecycleState.paused) {
      _postToGame({'type': 'app_paused'});
      _controller.runJavaScript(
        'try{window.unityInstance&&window.unityInstance.Module'
        '&&(window.unityInstance.Module.pauseMainLoop&&window.unityInstance.Module.pauseMainLoop());'
        'window.AudioContext&&void 0}catch(e){}',
      ).catchError((_) {});
    } else if (state == AppLifecycleState.resumed) {
      _postToGame({'type': 'app_resumed'});
      _controller.runJavaScript(
        'try{window.unityInstance&&window.unityInstance.Module'
        '&&(window.unityInstance.Module.resumeMainLoop&&window.unityInstance.Module.resumeMainLoop())}catch(e){}',
      ).catchError((_) {});
    }
  }

  Future<void> _onGameMessage(String raw) async {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      final msg = decoded;
      switch (msg['type']) {
        case 'game_reward_request':
          await _handleRewardRequest(msg);
        case 'game_exit':
          if (mounted) Navigator.of(context).maybePop();
        // game_ready 等其他消息暂不处理
      }
    } catch (_) {
      // 游戏页是远程内容：畸形消息（非 JSON、字段类型错误）一律忽略，
      // 绝不让 WebView 消息打崩宿主
    }
  }

  Future<void> _handleRewardRequest(Map<String, dynamic> msg) async {
    // 远程内容发来的字段类型不可信，用 is 检查而非 as 强转
    final requestId = msg['requestId'] is String ? msg['requestId'] as String : '';
    final gameId = msg['gameId'] is String ? msg['gameId'] as String : '';
    final recoveryType =
        msg['recoveryType'] is String ? msg['recoveryType'] as String : '';
    if (requestId.isEmpty || gameId.isEmpty) return;

    // 同一 requestId 只消费一次（重复消息直接忽略，连 failed 都不回，
    // 避免游戏侧把重复回执当成新结果）
    if (_handledRequestIds.contains(requestId)) return;
    _handledRequestIds.add(requestId);

    RewardedOutcome outcome;
    if (!mounted) return;
    try {
      outcome = await AdService.instance.showGameRecoveryRewarded(
        context,
        gameId: gameId,
        recoveryType: recoveryType,
        requestId: requestId,
      );
    } catch (_) {
      outcome = RewardedOutcome.failed;
    }

    if (!mounted) return;
    final result = switch (outcome.result) {
      RewardedAdResult.earned => 'earned',
      RewardedAdResult.dismissed => 'dismissed',
      _ => 'failed', // failed 与 disabled 对游戏侧同义：不得改变游戏状态
    };
    _postToGame({
      'type': 'game_reward_result',
      'requestId': requestId,
      'result': result,
      if (outcome.transId != null) 'transId': outcome.transId,
    });
  }

  void _postToGame(Map<String, dynamic> message) {
    final js = 'window.onGongyiMessage&&window.onGongyiMessage('
        '${jsonEncode(jsonEncode(message))})';
    _controller.runJavaScript(js).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('小游戏'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _loading = true;
                _loadError = null;
              });
              _controller.reload();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const Center(child: CircularProgressIndicator()),
          if (_loadError != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.wifi_off, size: 48, color: Colors.grey.shade500),
                    const SizedBox(height: 12),
                    Text(_loadError!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70)),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () {
                        setState(() {
                          _loading = true;
                          _loadError = null;
                        });
                        _controller.reload();
                      },
                      child: const Text('重新加载'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
