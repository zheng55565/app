// 本站小游戏页：仅允许配置域名导航，并通过白名单桥接游戏接口。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../api/api_client.dart';
import '../ads/ad_provider.dart';
import '../ads/ad_service.dart';
import '../config.dart';
import '../game/game_service.dart';

class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  late final WebViewController _controller;
  late final Uri _trustedGameUri;
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _trustedGameUri = Uri.parse(AppConfig.gameUrl);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF051937))
      ..addJavaScriptChannel(
        'GongyiBridge',
        onMessageReceived: (msg) => _onGameMessage(msg.message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final target = Uri.tryParse(request.url);
            return target != null && _isTrustedNavigation(target)
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
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
        ),
      )
      ..loadRequest(Uri.parse(AppConfig.gameUrl));
  }

  @override
  void dispose() {
    // 主动卸载页面，避免WebView脚本在返回首页后继续运行。
    _controller.loadRequest(Uri.parse('about:blank'));
    super.dispose();
  }

  bool _isTrustedNavigation(Uri target) {
    if (target.scheme == 'about' && target.path == 'blank') return true;
    return target.scheme == _trustedGameUri.scheme &&
        target.host == _trustedGameUri.host &&
        target.port == _trustedGameUri.port;
  }

  Future<void> _onGameMessage(String raw) async {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      final msg = decoded;
      switch (msg['type']) {
        case 'game_api_request':
          await _handleApiRequest(msg);
        case 'game_exit':
          if (mounted) Navigator.of(context).maybePop();
        // game_ready 等其他消息暂不处理
      }
    } catch (_) {
      // 游戏页是远程内容：畸形消息（非 JSON、字段类型错误）一律忽略，
      // 绝不让 WebView 消息打崩宿主
    }
  }

  Future<void> _handleApiRequest(Map<String, dynamic> msg) async {
    final requestId = msg['requestId'] is String
        ? msg['requestId'] as String
        : '';
    final action = msg['action'] is String ? msg['action'] as String : '';
    final payload = msg['payload'] is Map
        ? Map<String, dynamic>.from(msg['payload'] as Map)
        : <String, dynamic>{};
    if (requestId.isEmpty || action.isEmpty) return;
    try {
      if (action == 'match3_recover_ad') {
        final data = await _recoverMatch3(payload);
        _postToGame({
          'type': 'game_api_result',
          'requestId': requestId,
          'ok': true,
          'data': data,
        });
        return;
      }
      final data = await GameService.instance.execute(action, payload);
      _postToGame({
        'type': 'game_api_result',
        'requestId': requestId,
        'ok': true,
        'data': data,
      });
    } on ApiException catch (error) {
      _postToGame({
        'type': 'game_api_result',
        'requestId': requestId,
        'ok': false,
        'error': {'code': error.code, 'message': error.message},
      });
    } catch (_) {
      _postToGame({
        'type': 'game_api_result',
        'requestId': requestId,
        'ok': false,
        'error': {'code': 'GAME_REQUEST_FAILED', 'message': '游戏服务暂时不可用'},
      });
    }
  }

  Future<Map<String, dynamic>> _recoverMatch3(
    Map<String, dynamic> payload,
  ) async {
    final sessionId = payload['session_id']?.toString() ?? '';
    final actionRequestId = payload['action_request_id']?.toString() ?? '';
    final task = await GameService.instance.execute('match3_recovery_start', {
      'session_id': sessionId,
    });
    final taskToken = task['task_token']?.toString() ?? '';
    if (taskToken.isEmpty) {
      throw ApiException('GAME_AD_TASK_FAILED', '无法创建复活广告任务');
    }
    if (task['status'] == 'verified' || task['status'] == 'consumed') {
      return GameService.instance.execute('match3_recovery_consume', {
        'task_token': taskToken,
      });
    }
    if (!mounted) throw ApiException('GAME_PAGE_CLOSED', '游戏页面已关闭');
    final outcome = await AdService.instance.showGameRecoveryRewarded(
      context,
      taskToken: taskToken,
      gameId: sessionId,
      recoveryType: 'match3_moves',
      requestId: actionRequestId,
    );
    if (outcome.result == RewardedAdResult.disabled) {
      throw ApiException('GAME_AD_DISABLED', '复活广告暂不可用');
    }
    if (outcome.result != RewardedAdResult.earned) {
      throw ApiException('GAME_AD_NOT_COMPLETED', '完整看完广告后才能复活');
    }
    for (var attempt = 0; attempt < 15; attempt += 1) {
      final status = await GameService.instance.execute(
        'match3_recovery_status',
        {'task_token': taskToken},
      );
      if (status['status'] == 'verified' || status['status'] == 'consumed') {
        return GameService.instance.execute('match3_recovery_consume', {
          'task_token': taskToken,
        });
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    throw ApiException('GAME_AD_CALLBACK_PENDING', '广告正在验证，请稍后重试');
  }

  void _postToGame(Map<String, dynamic> message) {
    final js =
        'window.onGongyiMessage&&window.onGongyiMessage('
        '${jsonEncode(jsonEncode(message))})';
    _controller.runJavaScript(js).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF051937),
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
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (_loadError != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.wifi_off, size: 48, color: Colors.grey.shade500),
                    const SizedBox(height: 12),
                    Text(
                      _loadError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
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
