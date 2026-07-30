/// 环境配置
///
/// Android 模拟器访问宿主机用 10.0.2.2；真机调试改为电脑局域网 IP 或
/// `adb reverse tcp:3001 tcp:3001` 后用 localhost；生产替换为正式 HTTPS 域名。
class AppConfig {
  /// 仅用于本地界面验收。正式构建不传此参数时始终为 false。
  static const bool previewMode = bool.fromEnvironment(
    'PREVIEW_MODE',
    defaultValue: false,
  );

  /// 真实广告联调包：隐藏 Linux.do，改用服务端签发的开发检查账号。
  /// 服务端只会在 development + STATION_MODE=mock 下开放对应登录接口。
  static const bool adPreviewMode = bool.fromEnvironment(
    'AD_PREVIEW_MODE',
    defaultValue: false,
  );

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3001',
  );

  /// 本站小游戏地址（WebView 加载）。生产替换为业务后台或CDN的HTTPS地址，
  /// 小游戏即可在线更新，无需发版。
  ///
  /// 开发默认用 localhost 而非 10.0.2.2：WebView（Chromium）走系统代理，
  /// 模拟器的全局代理会劫持 10.0.2.2 导致加载失败；localhost 默认绕过代理，
  /// 经 `adb reverse tcp:3001 tcp:3001`（启动脚本已配）直达宿主后端。
  static const String gameUrl = String.fromEnvironment(
    'GAME_URL',
    defaultValue: 'http://localhost:3001/games/',
  );

  /// 真实广告SDK初始化前必须展示的隐私政策。正式包必须配置HTTPS地址；
  /// 未配置时保持广告禁用，不能静默视为用户同意。
  static const String privacyPolicyUrl = String.fromEnvironment(
    'PRIVACY_POLICY_URL',
    defaultValue: '',
  );

  /// 授权回跳自定义 scheme（与后端 APP_LINK_IOS_SCHEME / AndroidManifest 保持一致）
  static const String callbackScheme = 'gongyiapp';
}
