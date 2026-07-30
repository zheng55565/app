// AI公益工作台入口：登录恢复、隐私门禁、广告初始化和页面导航。
import 'package:flutter/material.dart';

import 'ads/ad_service.dart';
import 'auth/auth_service.dart';
import 'config.dart';
import 'pages/login_page.dart';
import 'pages/main_shell_page.dart';
import 'pages/privacy_consent.dart';

void main() {
  runApp(const GongyiApp());
}

class GongyiApp extends StatelessWidget {
  const GongyiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI 公益工作台',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00C0F9),
          onPrimary: Color(0xFFFFFFFF),
          primaryContainer: Color(0xFF0099E8),
          onPrimaryContainer: Color(0xFFFFFFFF),
          secondary: Color(0xFF2ED573),
          onSecondary: Color(0xFF051937),
          secondaryContainer: Color(0xFF163E70),
          onSecondaryContainer: Color(0xFFE6F2FF),
          surface: Color(0x73163E70),
          onSurface: Color(0xFFFFFFFF),
          surfaceContainerHighest: Color(0x73163E70),
          onSurfaceVariant: Color(0xFF89A8CB),
          error: Color(0xFFFF4757),
          onError: Color(0xFFFFFFFF),
          errorContainer: Color(0xFFD6336C),
          onErrorContainer: Color(0xFFFFFFFF),
          outline: Color(0x2E64C8FF),
          outlineVariant: Color(0x2E64C8FF),
        ),
        canvasColor: const Color(0xFF051937),
        scaffoldBackgroundColor: Colors.transparent,
        textTheme: const TextTheme(
          headlineSmall: TextStyle(
            color: Color(0xFFFFFFFF),
            fontSize: 19,
            fontWeight: FontWeight.w700,
          ),
          titleMedium: TextStyle(
            color: Color(0xFFFFFFFF),
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          bodyMedium: TextStyle(color: Color(0xFFE6F2FF), fontSize: 14),
          bodySmall: TextStyle(color: Color(0xFF89A8CB), fontSize: 12),
          labelSmall: TextStyle(color: Color(0xFF89A8CB), fontSize: 12),
        ),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          backgroundColor: Color(0xD9051937),
          foregroundColor: Color(0xFFFFFFFF),
          surfaceTintColor: Colors.transparent,
          toolbarHeight: 52,
          titleTextStyle: TextStyle(
            color: Color(0xFFFFFFFF),
            fontSize: 19,
            fontWeight: FontWeight.w700,
          ),
        ),
        cardTheme: const CardThemeData(
          elevation: 2,
          shadowColor: Color(0x52000000),
          color: Color(0x73163E70),
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
            side: BorderSide(color: Color(0x2E64C8FF)),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0x73163E70),
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: Color(0x2E64C8FF)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: Color(0xFF00C0F9), width: 1.4),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(44, 42),
            backgroundColor: const Color(0xFF0099E8),
            foregroundColor: const Color(0xFFFFFFFF),
            disabledBackgroundColor: const Color(0x660099E8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: ButtonStyle(
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? const Color(0xFFFFFFFF)
                  : const Color(0xFF89A8CB),
            ),
            backgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? const Color(0xFF0099E8)
                  : Colors.transparent,
            ),
            side: const WidgetStatePropertyAll(
              BorderSide(color: Color(0x2E64C8FF)),
            ),
            shape: const WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(20)),
              ),
            ),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          height: 64,
          elevation: 0,
          backgroundColor: const Color(0xE6051937),
          indicatorColor: const Color(0x3300AAF0),
          iconTheme: WidgetStateProperty.resolveWith(
            (states) => IconThemeData(
              color: states.contains(WidgetState.selected)
                  ? const Color(0xFF00C0F9)
                  : const Color(0xFF89A8CB),
            ),
          ),
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              fontSize: 12,
              color: states.contains(WidgetState.selected)
                  ? const Color(0xFFE6F2FF)
                  : const Color(0xFF89A8CB),
            ),
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0x1F6EB4E6),
          thickness: 1,
          space: 1,
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: Color(0xF2163E70),
          surfaceTintColor: Colors.transparent,
        ),
        useMaterial3: true,
      ),
      // 检查版保留登录页，但登录只建立本机会话，不请求 Linux.do。
      home: AppConfig.previewMode ? const LoginPage() : const SplashPage(),
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
    // 只拉广告配置，不初始化真实SDK；必须先经过隐私同意门禁。
    AuthUser? user;
    try {
      final adConfig = AdService.instance.initConfig();
      user = await AuthService.instance.refresh();
      await adConfig;
    } catch (_) {
      // 广告配置或登录恢复失败不阻塞启动。
    }
    if (!mounted) return;

    try {
      if (AdService.instance.requiresConsent) {
        final agreed = await requestAdPrivacyConsent(context);
        if (agreed) {
          await AdService.instance.grantConsent();
        } else {
          await AdService.instance.initSdk();
        }
      } else {
        await AdService.instance.initSdk();
      }
    } catch (_) {
      // SDK初始化失败只禁用广告，不能阻塞登录和AI功能。
    }
    if (!mounted) return;

    // 开屏广告预留触发点：冷启动完成、进入主页面之前（服务端未开启时为空操作）
    await AdService.instance.maybeShowSplash(context);
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            user != null ? const MainShellPage() : const LoginPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
