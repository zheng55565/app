/// 环境配置
///
/// Android 模拟器访问宿主机用 10.0.2.2；真机调试改为电脑局域网 IP 或
/// `adb reverse tcp:3000 tcp:3000` 后用 localhost；生产替换为正式 HTTPS 域名。
class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );

  /// Unity WebGL 小游戏地址（WebView 加载）。生产替换为 CDN/静态站 HTTPS 地址，
  /// 小游戏即可在线更新，无需发版。
  ///
  /// 开发默认用 localhost 而非 10.0.2.2：WebView（Chromium）走系统代理，
  /// 模拟器的全局代理会劫持 10.0.2.2 导致加载失败；localhost 默认绕过代理，
  /// 经 `adb reverse tcp:3000 tcp:3000`（启动脚本已配）直达宿主后端。
  static const String gameUrl = String.fromEnvironment(
    'GAME_URL',
    defaultValue: 'http://localhost:3000/games/',
  );

  /// 授权回跳自定义 scheme（与后端 APP_LINK_IOS_SCHEME / AndroidManifest 保持一致）
  static const String callbackScheme = 'gongyiapp';
}
