/// 广告抽象层
///
/// 广告位统一契约。业务代码只依赖 [AdService]/[AdProvider]，
/// 接入真实广告 SDK 时新增一个 Provider 实现并在 [AdService] 按后端下发的
/// provider 字段选择，业务零改动。
///
/// 激励视频分两个互相隔离的用途（绝不能混用广告位）：
/// - home_balance：首页余额广告，走 task_token + 广告平台服务端回调发奖，
///   计入每日次数；
/// - game_recovery：小游戏本局补救（复活/续时/提示……），只回传本局结果，
///   不建任务、不轮询余额、永不发奖到钱包。
library;

/// 激励视频播放结果
enum RewardedAdResult {
  /// 用户完整看完（真实 SDK 场景奖励仍以服务端回调 / isReward 校验为准）
  earned,

  /// 用户中途关闭，无奖励
  dismissed,

  /// 加载或播放失败
  failed,

  /// 广告位被远程配置关闭（或 SDK 未初始化），未尝试播放
  disabled,
}

/// 一次激励视频播放请求（购前上下文）
class RewardedRequest {
  const RewardedRequest.homeBalance({required String this.taskToken, this.userId = ''})
      : purpose = 'home_balance',
        gameId = null,
        recoveryType = null,
        requestId = null;

  const RewardedRequest.gameRecovery({
    required String this.gameId,
    required String this.recoveryType,
    required String this.requestId,
    this.userId = '',
  })  : purpose = 'game_recovery',
        taskToken = null;

  /// 'home_balance' | 'game_recovery'
  final String purpose;

  /// 仅 home_balance：服务端签发的一次性任务凭证
  final String? taskToken;

  /// 仅 game_recovery：游戏与补救类型、去重用的唯一请求 id
  final String? gameId;
  final String? recoveryType;
  final String? requestId;

  /// 广告平台的用户标识（真实 SDK 的 userId 字段）
  final String userId;
}

/// 一次激励视频播放结果（含广告平台的交易 id，透传给游戏侧防重）
class RewardedOutcome {
  const RewardedOutcome(this.result, {this.transId});

  final RewardedAdResult result;

  /// 广告平台标识本次播放的唯一 id（mock 场景为伪造值）
  final String? transId;

  static const disabled = RewardedOutcome(RewardedAdResult.disabled);
  static const dismissed = RewardedOutcome(RewardedAdResult.dismissed);
  static const failed = RewardedOutcome(RewardedAdResult.failed);
}

/// 单个广告位的远程配置（来自 GET /api/app/ad-config）
///
/// 频控字段由服务端下发（环境变量可调，无需发版）；旧版服务端不下发时
/// 取内置默认值，向后兼容。
class AdSlotConfig {
  const AdSlotConfig({
    required this.enabled,
    required this.unitId,
    this.cooldownSec = 180,
    this.dailyMax = 0,
    this.minIntervalSec = 0,
  });

  final bool enabled;
  final String unitId;

  /// 两次展示的最小间隔（秒），当前用于插屏
  final int cooldownSec;

  /// 每日最多展示次数，0 = 不限
  final int dailyMax;

  /// 开屏热启动（回前台）最小间隔（秒），接真实 SDK 时使用
  final int minIntervalSec;

  factory AdSlotConfig.fromJson(Map<String, dynamic>? json) => AdSlotConfig(
        enabled: (json?['enabled'] as bool?) ?? false,
        unitId: (json?['unit_id'] as String?) ?? '',
        cooldownSec: (json?['cooldown_sec'] as num?)?.toInt() ?? 180,
        dailyMax: (json?['daily_max'] as num?)?.toInt() ?? 0,
        minIntervalSec: (json?['min_interval_sec'] as num?)?.toInt() ?? 0,
      );

  static const disabled = AdSlotConfig(enabled: false, unitId: '');
}

/// 广告配置总览
class AdConfig {
  const AdConfig({
    required this.provider,
    this.appId = '',
    required this.splash,
    required this.rewardedHome,
    required this.rewardedGame,
    required this.interstitial,
  });

  final String provider;

  /// 广告 SDK 的应用 Id（provider=hj 等真实 SDK 时必填）
  final String appId;

  final AdSlotConfig splash;

  /// 首页余额广告位（唯一走钱包发奖链路的广告位）
  final AdSlotConfig rewardedHome;

  /// 小游戏补救广告位（只回传本局结果，与钱包无关）
  final AdSlotConfig rewardedGame;

  final AdSlotConfig interstitial;

  /// 兼容旧代码：rewarded 即 rewardedHome
  AdSlotConfig get rewarded => rewardedHome;

  factory AdConfig.fromJson(Map<String, dynamic> json) => AdConfig(
        provider: (json['provider'] as String?) ?? 'mock',
        appId: (json['app_id'] as String?) ?? '',
        splash: AdSlotConfig.fromJson(json['splash'] as Map<String, dynamic>?),
        // 新服务端下发 rewarded_home；旧服务端只有 rewarded，回退兼容
        rewardedHome: AdSlotConfig.fromJson(
            (json['rewarded_home'] ?? json['rewarded']) as Map<String, dynamic>?),
        rewardedGame: AdSlotConfig.fromJson(
            json['rewarded_game'] as Map<String, dynamic>?),
        interstitial:
            AdSlotConfig.fromJson(json['interstitial'] as Map<String, dynamic>?),
      );

  /// 无远程配置也无本地缓存时的保守默认：全部禁用。
  /// 发奖流程依赖后端（/api/ad-task/start），后端不可达时开广告位没有意义；
  /// 更不能把真实 provider 静默降级成 mock（会播假广告且必然发奖失败）。
  static const fallback = AdConfig(
    provider: 'mock',
    splash: AdSlotConfig.disabled,
    rewardedHome: AdSlotConfig.disabled,
    rewardedGame: AdSlotConfig.disabled,
    interstitial: AdSlotConfig.disabled,
  );
}

/// 广告提供方抽象。真实 SDK 接入时实现本接口。
///
/// 约定：所有方法都不得抛异常——失败一律通过返回值表达
/// （splash/interstitial 返回 false，rewarded 返回 failed 结果），
/// 保证业务层不需要每处调用都包 try/catch。
abstract class AdProvider {
  /// SDK 初始化（申请权限、预加载等）。App 启动时调用一次。
  Future<void> init(AdConfig config);

  /// 配置热更新（开关/频控变化时由 [AdService] 调用）。
  /// 只更新配置快照，不得重新初始化 SDK；provider 种类切换仍需冷重启。
  void updateConfig(AdConfig config);

  /// 开屏广告：App 冷启动时展示。返回是否成功展示（失败/超时应直接放行，
  /// 不得阻塞启动流程）。[context] 由调用方保证挂载中。
  Future<bool> showSplash(covariant Object context);

  /// 激励视频。按 [slot] 指定广告位播放，[request] 携带用途上下文：
  /// - home_balance：taskToken 透传给广告平台（服务端回调发奖的关联凭证）；
  /// - game_recovery：requestId 透传，实现方不得发起任何发奖相关请求。
  Future<RewardedOutcome> showRewarded(
    covariant Object context, {
    required AdSlotConfig slot,
    required RewardedRequest request,
  });

  /// 插屏广告：页面切换等时机插入。返回是否成功展示。
  /// 调用频控由 [AdService.maybeShowInterstitial] 统一管理，实现方无需重复限频。
  Future<bool> showInterstitial(covariant Object context);
}

/// 全禁用 provider：未知 provider 名、或真实 SDK 未获隐私同意时的兜底。
/// 绝不能把未知 provider 静默映射成 mock——那会播假广告并走
/// dev-complete（生产已关闭），用户看完拿不到奖励。
class DisabledAdProvider implements AdProvider {
  @override
  Future<void> init(AdConfig config) async {}

  @override
  void updateConfig(AdConfig config) {}

  @override
  Future<bool> showSplash(Object context) async => false;

  @override
  Future<RewardedOutcome> showRewarded(
    Object context, {
    required AdSlotConfig slot,
    required RewardedRequest request,
  }) async =>
      RewardedOutcome.disabled;

  @override
  Future<bool> showInterstitial(Object context) async => false;
}
