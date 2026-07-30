// 登录服务：浏览器授权、状态轮询、Token交换与安全存储。
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/api_client.dart';
import '../ai/station_credential_service.dart';
import '../ai/station_key_sync_service.dart';

class LoginStatusResult {
  LoginStatusResult(this.status, {this.errorCode, this.linuxdoUsername});
  final String status;
  final String? errorCode;
  final String? linuxdoUsername;
}

class AuthUser {
  AuthUser({
    this.userId,
    required this.linuxdoUsername,
    this.stationUserId,
    this.stationStatus,
  });
  final int? userId;
  final String linuxdoUsername;
  final int? stationUserId;
  final String? stationStatus;
}

class AuthService {
  AuthService._() {
    // 401 重试语义：只有真正换到了新 Access Token 才值得重发原请求
    ApiClient.instance.onUnauthorized = () => refreshForRetry();
  }
  static final AuthService instance = AuthService._();

  static const _storage = FlutterSecureStorage();
  static const _kRefreshToken = 'refresh_token';
  static const _kPendingSession = 'pending_login_session';

  final _api = ApiClient.instance;
  AuthUser? currentUser;

  String? _pendingSessionId;
  String? _pendingSecret;

  // ---------- 登录发起 ----------

  /// 创建登录会话并返回授权地址，由 App 内置浏览器负责打开。
  /// 内置浏览器关闭后应调用 [pollLoginResult]。
  Future<Uri> startLogin() async {
    final data = await _api.requestV1(
      'POST',
      '/api/v1/auth/linuxdo/start',
      body: {
        'platform': Platform.isIOS ? 'ios' : 'android',
        'app_version': '1.0.0',
      },
    );
    _pendingSessionId = data['login_session_id'] as String;
    _pendingSecret = data['session_secret'] as String;
    // 应对系统杀进程：短期落安全存储，流程结束立即删除（方案 §7.1）
    await _storage.write(
      key: _kPendingSession,
      value: '$_pendingSessionId|$_pendingSecret',
    );

    return Uri.parse(data['auth_url'] as String);
  }

  /// 无 Linux.do 的真实广告联调登录。
  ///
  /// 此接口只在开发服务端 + mock 中转账本下存在。它签发真实服务端 Token，
  /// 因此广告任务、HJ 回调和钱包入账仍完整走服务端，客户端不能自行加额度。
  Future<AuthUser> loginAdPreview(String username, String password) async {
    final data = await _api.requestLegacy(
      'POST',
      '/api/auth/preview',
      body: {'username': username, 'password': password},
      auth: false,
    );
    final token = data['token'] as String?;
    final rawUser = data['user'] as Map<String, dynamic>?;
    if (token == null || token.isEmpty || rawUser == null) {
      throw ApiException('PREVIEW_LOGIN_INVALID', '检查账号登录响应无效');
    }

    final rawUserId = rawUser['id'];
    final userId = rawUserId is num
        ? rawUserId.toInt()
        : int.tryParse(rawUserId?.toString() ?? '');
    if (userId == null) {
      throw ApiException('PREVIEW_LOGIN_INVALID', '检查账号缺少用户编号');
    }

    await _storage.delete(key: _kRefreshToken);
    await clearPendingSession();
    _api.setAccessToken(token);
    await StationCredentialService.instance.activateAccount(userId.toString());
    final user = AuthUser(
      userId: userId,
      linuxdoUsername:
          rawUser['linuxdo_username'] as String? ??
          rawUser['username'] as String? ??
          username,
      stationUserId: (rawUser['station_user_id'] as num?)?.toInt(),
      stationStatus: rawUser['station_status'] as String? ?? 'active',
    );
    currentUser = user;
    return user;
  }

  /// 轮询登录状态；authorized 时自动领码换 Token 并返回用户
  Future<LoginStatusResult> pollLoginResult() async {
    final sid = _pendingSessionId;
    final secret = _pendingSecret;
    if (sid == null || secret == null) return LoginStatusResult('failed');

    final data = await _api.requestV1(
      'POST',
      '/api/v1/auth/linuxdo/status',
      body: {'login_session_id': sid, 'session_secret': secret},
    );
    final status = data['status'] as String;
    if (status != 'authorized') {
      return LoginStatusResult(
        status,
        errorCode: data['error_code'] as String?,
        linuxdoUsername: data['linuxdo_username'] as String?,
      );
    }

    final loginCode = data['login_code'] as String;
    final ex = await _api.requestV1(
      'POST',
      '/api/v1/auth/exchange',
      body: {
        'login_session_id': sid,
        'session_secret': secret,
        'login_code': loginCode,
        'device_name': Platform.isIOS ? 'iOS Device' : 'Android Device',
      },
    );
    await _onTokenIssued(ex);
    await clearPendingSession();
    return LoginStatusResult('authorized');
  }

  Future<void> clearPendingSession() async {
    _pendingSessionId = null;
    _pendingSecret = null;
    await _storage.delete(key: _kPendingSession);
  }

  // ---------- Token 管理 ----------

  Future<void> _onTokenIssued(Map<String, dynamic> data) async {
    _api.setAccessToken(data['access_token'] as String);
    await _storage.write(
      key: _kRefreshToken,
      value: data['refresh_token'] as String,
    );
    final u = data['user'] as Map<String, dynamic>?;
    if (u != null) {
      final rawUserId = u['id'];
      final userId = rawUserId is num
          ? rawUserId.toInt()
          : int.tryParse(rawUserId?.toString() ?? '');
      await StationCredentialService.instance.activateAccount(
        userId?.toString(),
      );
      currentUser = AuthUser(
        userId: userId,
        linuxdoUsername: u['linuxdo_username'] as String? ?? '',
        stationUserId: u['station_user_id'] as int?,
        stationStatus: u['station_status'] as String?,
      );
      try {
        await StationKeySyncService.instance.pull();
      } catch (_) {
        // 云端尚未配置 Key 或暂时不可达时继续使用本机安全存储。
      }
    }
  }

  /// 启动时静默恢复登录：用 Refresh Token 换新 Access Token（轮换）。
  /// 返回值回答“该不该进主页”：网络/服务器瞬时故障时保留凭据乐观放行。
  Future<AuthUser?> refresh() async => (await _refreshShared()).user;

  /// 401 自动重试用：回答“是否真正换到了新 Access Token”。
  /// 网络异常/5xx 时必须返回 false——否则会拿同一个过期 token 原样重试。
  Future<bool> refreshForRetry() async => (await _refreshShared()).issued;

  /// single-flight：并发 401 各自触发刷新时只发一次请求。服务端对旧
  /// refresh_token 的二次使用会判定复用并撤销整个 token 家族（强制登出），
  /// 因此绝不能让两个刷新请求带着同一个旧 token 同时出门。
  Future<({AuthUser? user, bool issued})> _refreshShared() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<({AuthUser? user, bool issued})>? _refreshing;

  Future<({AuthUser? user, bool issued})> _doRefresh() async {
    final rt = await _storage.read(key: _kRefreshToken);
    if (rt == null) return (user: null, issued: false);
    try {
      final data = await _api.requestV1(
        'POST',
        '/api/v1/auth/refresh',
        body: {'refresh_token': rt},
      );
      await _onTokenIssued(data);
      currentUser ??= AuthUser(linuxdoUsername: '');
      return (user: currentUser, issued: true);
    } on ApiException catch (e) {
      // 只有服务端明确判定凭据无效（401/403）才清本地凭据回登录页；
      // 5xx/网关错误是服务器侧故障，误删会把用户永久登出
      if (e.httpStatus == 401 || e.httpStatus == 403) {
        await _storage.delete(key: _kRefreshToken);
        await StationCredentialService.instance.clear();
        await StationCredentialService.instance.activateAccount(null);
        _api.setAccessToken(null);
        currentUser = null;
        return (user: null, issued: false);
      }
      currentUser ??= AuthUser(linuxdoUsername: '');
      return (user: currentUser, issued: false);
    } catch (_) {
      // 网络层异常（超时/断网等）：token 本身可能仍有效，保留本地凭据，
      // 按已登录进入主页，页面请求 401 时会再次触发刷新重试
      currentUser ??= AuthUser(linuxdoUsername: '');
      return (user: currentUser, issued: false);
    }
  }

  Future<void> logout() async {
    final rt = await _storage.read(key: _kRefreshToken);
    try {
      await _api.requestV1(
        'POST',
        '/api/v1/auth/logout',
        body: {'refresh_token': rt},
        auth: true,
      );
    } catch (_) {
      // 网络失败也继续本地清理
    }
    await _storage.delete(key: _kRefreshToken);
    await StationCredentialService.instance.clear();
    await StationCredentialService.instance.activateAccount(null);
    _api.setAccessToken(null);
    currentUser = null;
  }
}
