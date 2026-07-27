/// 公益中转站 App 入口
///
/// 启动流程（PRD §9.1 简化版）：初始化广告配置与 provider（与登录恢复
/// 并行、失败不阻塞）-> 读取本地 Refresh Token 静默续期 -> 开屏广告
/// （若服务端开启）-> 首页或登录页。
import 'package:flutter/material.dart';

import 'ads/ad_service.dart';
import 'auth/auth_service.dart';
import 'pages/login_page.dart';
import 'pages/main_shell_page.dart';

void main() {
  runApp(const GongyiApp());
}

class GongyiApp extends StatelessWidget {
  const GongyiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '公益中转站',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const SplashPage(),
    );
  }
}

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // 广告配置与登录恢复并行；两者内部各自兜底异常，这里再兜一层，
    // 保证任何情况下导航都会执行（不能让用户永久停在转圈页）
    AuthUser? user;
    try {
      final adInit = AdService.instance.init();
      user = await AuthService.instance.refresh();
      await adInit;
    } catch (_) {
      // 广告初始化失败不阻塞启动；user 保持 null 时走登录页
    }
    if (!mounted) return;

    // 开屏广告预留触发点：冷启动完成、进入主页面之前（服务端未开启时为空操作）
    await AdService.instance.maybeShowSplash(context);
    if (!mounted) return;

    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) =>
          user != null ? const MainShellPage() : const LoginPage(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
