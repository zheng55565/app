// 登录页与登录结果轮询。
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../auth/auth_service.dart';
import '../config.dart';
import '../preview/preview_session.dart';
import 'auth_browser_page.dart';
import 'main_shell_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

enum _Phase { idle, waiting, accountNotFound, error }

class _LoginPageState extends State<LoginPage> {
  _Phase _phase = _Phase.idle;
  String _message = '';
  String? _guideUsername;
  Timer? _pollTimer;
  int _pollCount = 0;
  bool _checking = false;
  bool _previewSubmitting = false;
  String? _previewError;
  final TextEditingController _previewAccountController = TextEditingController(
    text: 'preview_user',
  );
  final TextEditingController _previewPasswordController =
      TextEditingController(text: '123456');

  @override
  void dispose() {
    _pollTimer?.cancel();
    _previewAccountController.dispose();
    _previewPasswordController.dispose();
    super.dispose();
  }

  Future<void> _previewLogin() async {
    final account = _previewAccountController.text.trim();
    final password = _previewPasswordController.text;
    if (account.isEmpty || password.isEmpty) {
      setState(() => _previewError = '请输入检查账号和检查口令');
      return;
    }
    setState(() {
      _previewSubmitting = true;
      _previewError = null;
    });
    try {
      if (AppConfig.adPreviewMode) {
        await AuthService.instance.loginAdPreview(account, password);
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        PreviewSession.signIn(account);
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainShellPage()),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _previewError = e.message);
    } catch (_) {
      if (mounted) setState(() => _previewError = '检查服务连接失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _previewSubmitting = false);
    }
  }

  Future<void> _login() async {
    setState(() {
      _phase = _Phase.waiting;
      _message = '正在打开 Linux.do 授权页面……';
    });
    try {
      final authUrl = await AuthService.instance.startLogin();
      if (!mounted) return;
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => AuthBrowserPage(initialUrl: authUrl),
        ),
      );
      if (!mounted || _phase != _Phase.waiting) return;
      setState(() => _message = '正在确认授权结果……');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _message = e.message;
      });
      return;
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _message = switch (e.type) {
          DioExceptionType.connectionTimeout ||
          DioExceptionType.sendTimeout ||
          DioExceptionType.receiveTimeout => '连接服务器超时，请检查网络后重试',
          DioExceptionType.connectionError => '无法连接服务器，请检查网络或稍后重试',
          DioExceptionType.badCertificate => '服务器 HTTPS 证书异常，请联系管理员',
          _ => '网络请求失败，请稍后重试',
        };
      });
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _message = '无法打开授权页面或网络异常：$e';
      });
      return;
    }
    // 会话已建立。此后的瞬时网络错误不判失败（用户可能正在浏览器里授权），
    // 由 _checkOnce 内部吞掉并靠轮询重试（§10）。
    await _checkOnce();
    if (!mounted || _phase != _Phase.waiting) return;
    _startPolling();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollCount = 0;
    // 每 2 秒一次，最长 60 秒，之后允许手动“重新检查”（§10）
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (t) async {
      if (_phase != _Phase.waiting || ++_pollCount > 30) {
        t.cancel();
        if (mounted && _phase == _Phase.waiting) {
          setState(() => _message = '等待超时。完成授权后请点击“重新检查”。');
        }
        return;
      }
      await _checkOnce();
    });
  }

  /// 查询一次登录状态。防重入（Timer.periodic 不等待上次回调完成，
  /// “重新检查”按钮也会并发触发）；每个 await 之后都重查 mounted 与
  /// _phase（期间用户可能点了“取消登录”）。
  Future<void> _checkOnce() async {
    if (_checking || _phase != _Phase.waiting || !mounted) return;
    _checking = true;
    try {
      final r = await AuthService.instance.pollLoginResult();
      if (!mounted || _phase != _Phase.waiting) return;
      switch (r.status) {
        case 'authorized':
          _pollTimer?.cancel();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const MainShellPage()),
          );
        case 'pending':
          break; // 继续等
        case 'completed':
          // 服务端已完成过一次换发（exchange 提交后响应丢失等场景），
          // 该会话的 login_code 已一次性作废，只能重新发起登录
          _pollTimer?.cancel();
          await AuthService.instance.clearPendingSession();
          if (!mounted || _phase != _Phase.waiting) return;
          setState(() {
            _phase = _Phase.error;
            _message = '登录会话已被使用，请重新发起登录';
          });
        case 'account_not_found':
          _pollTimer?.cancel();
          await AuthService.instance.clearPendingSession();
          if (!mounted || _phase != _Phase.waiting) return;
          setState(() {
            _phase = _Phase.accountNotFound;
            _guideUsername = r.linuxdoUsername;
          });
        case 'expired':
          _pollTimer?.cancel();
          await AuthService.instance.clearPendingSession();
          if (!mounted || _phase != _Phase.waiting) return;
          setState(() {
            _phase = _Phase.error;
            _message = '登录已过期，请重新发起登录';
          });
        default:
          _pollTimer?.cancel();
          await AuthService.instance.clearPendingSession();
          if (!mounted || _phase != _Phase.waiting) return;
          setState(() {
            _phase = _Phase.error;
            _message = switch (r.errorCode) {
              'LINUXDO_ACCOUNT_REJECTED' => 'Linux.do 账号状态或信任等级不满足要求',
              'ACCOUNT_DISABLED' => '中转站账号不可用，请联系管理员',
              'STATION_UNAVAILABLE' => '中转站服务暂不可用，请稍后重试',
              _ => '登录失败（${r.errorCode ?? r.status}），请重试',
            };
          });
      }
    } on ApiException catch (e) {
      if (!mounted || _phase != _Phase.waiting) return;
      if (e.code == 'AUTH_SESSION_PROOF_INVALID' ||
          e.code == 'AUTH_SESSION_EXPIRED') {
        _pollTimer?.cancel();
        await AuthService.instance.clearPendingSession();
        if (!mounted || _phase != _Phase.waiting) return;
        setState(() {
          _phase = _Phase.error;
          _message = '登录会话失效，请重新发起登录';
        });
      }
      // 其余（如瞬时业务错误）下个轮询周期重试
    } catch (_) {
      // 网络层异常（DioException：超时/断网/DNS）：瞬时错误，下个轮询周期重试
    } finally {
      _checking = false;
    }
  }

  void _reset() {
    _pollTimer?.cancel();
    setState(() {
      _phase = _Phase.idle;
      _message = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (AppConfig.previewMode || AppConfig.adPreviewMode) {
      return _buildPreviewLogin();
    }

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.volunteer_activism,
                size: 72,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 12),
              const Text(
                '公益中转站',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
              ),
              const Text(
                '看广告，做公益，攒额度',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 48),
              ..._buildBody(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewLogin() {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.auto_awesome_outlined,
                      size: 34,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'AI 公益工作台',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppConfig.adPreviewMode
                        ? '无需 L 站授权 · 真实广告联调版'
                        : '无需 L 站授权检查版',
                    style: TextStyle(
                      fontSize: 15,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    key: const ValueKey('preview-account'),
                    controller: _previewAccountController,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.username],
                    decoration: const InputDecoration(
                      labelText: '检查账号',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('preview-password'),
                    controller: _previewPasswordController,
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) =>
                        _previewSubmitting ? null : _previewLogin(),
                    decoration: const InputDecoration(
                      labelText: '检查口令',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                  ),
                  if (_previewError != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _previewError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    key: const ValueKey('preview-login'),
                    onPressed: _previewSubmitting ? null : _previewLogin,
                    icon: _previewSubmitting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.login),
                    label: Text(
                      _previewSubmitting
                          ? '正在进入'
                          : AppConfig.adPreviewMode
                          ? '登录广告联调版'
                          : '进入检查版',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            AppConfig.adPreviewMode
                                ? '账号会发送到本机开发服务端。广告使用真实 HJ SDK，额度只在广告平台回调验证通过后进入隔离测试账本。'
                                : '本版本仅供检查页面与交互。账号和口令不发送到服务器，广告、API调用和真实额度均为演示数据。',
                            style: const TextStyle(fontSize: 12, height: 1.45),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildBody() {
    switch (_phase) {
      case _Phase.idle:
        return [
          FilledButton.icon(
            onPressed: _login,
            icon: const Icon(Icons.login),
            label: const Text('使用 Linux.do 登录'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ];
      case _Phase.waiting:
        return [
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 16),
          Text(_message, textAlign: TextAlign.center),
          const SizedBox(height: 24),
          TextButton(
            onPressed: () {
              setState(() => _message = '正在重新检查……');
              _pollCount = 0;
              _checkOnce();
              _startPolling();
            },
            child: const Text('我已完成授权，重新检查'),
          ),
          TextButton(onPressed: _reset, child: const Text('取消登录')),
        ];
      case _Phase.accountNotFound:
        return [
          Text(
            'Linux.do 账号 ${_guideUsername ?? ''} 尚未注册中转站',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 8),
          const Text(
            '请先前往 API 中转站使用 Linux.do 注册账号，然后回来重新登录。',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _login, child: const Text('注册完成，重新登录')),
          TextButton(onPressed: _reset, child: const Text('返回')),
        ];
      case _Phase.error:
        return [
          Icon(Icons.error_outline, color: Colors.red.shade400, size: 40),
          const SizedBox(height: 8),
          Text(_message, textAlign: TextAlign.center),
          const SizedBox(height: 24),
          FilledButton(onPressed: _login, child: const Text('重新登录')),
        ];
    }
  }
}
