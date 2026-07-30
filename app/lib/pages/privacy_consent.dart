import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../config.dart';

Future<bool> requestAdPrivacyConsent(BuildContext context) async {
  final uri = Uri.tryParse(AppConfig.privacyPolicyUrl.trim());
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    return false;
  }
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('隐私与广告'),
          content: const Text(
            '为提供奖励广告，您同意后我们才会初始化广告SDK。广告服务商可能按照隐私政策处理设备信息、网络信息和广告交互数据。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).push(
                MaterialPageRoute(
                  builder: (_) => _PrivacyPolicyPage(url: uri.toString()),
                ),
              ),
              child: const Text('查看隐私政策'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('暂不同意'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('同意并继续'),
            ),
          ],
        ),
      ) ??
      false;
}

class _PrivacyPolicyPage extends StatefulWidget {
  const _PrivacyPolicyPage({required this.url});

  final String url;

  @override
  State<_PrivacyPolicyPage> createState() => _PrivacyPolicyPageState();
}

class _PrivacyPolicyPageState extends State<_PrivacyPolicyPage> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('隐私政策')),
      body: SafeArea(child: WebViewWidget(controller: _controller)),
    );
  }
}
