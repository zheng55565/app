// API客户端：统一响应解析、Access Token注入和401自动刷新重试。
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../config.dart';
import '../ai/station_credential_service.dart';
import '../device/device_identity.dart';

/// v1 接口错误（携带稳定 error.code，App 按 code 处理业务，方案 §7/§13）
class ApiException implements Exception {
  ApiException(this.code, this.message, {this.httpStatus});

  final String code;
  final String message;
  final int? httpStatus;

  @override
  String toString() => '$code: $message';
}

class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      // 业务错误码由我们自己解析，不让 dio 按 HTTP 状态抛异常
      validateStatus: (_) => true,
    ),
  );

  /// 内存中的 Access Token（方案 §12.3：尽量只放内存）
  String? _accessToken;

  /// 401 时由 AuthService 注入的刷新回调；返回 true 表示刷新成功可重试
  Future<bool> Function()? onUnauthorized;

  void setAccessToken(String? token) => _accessToken = token;

  /// 请求 v1 接口（{success, data, error} 格式），失败抛 ApiException
  Future<Map<String, dynamic>> requestV1(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool auth = false,
    bool retried = false,
  }) async {
    final res = await _dio.request(
      path,
      data: body,
      options: Options(method: method, headers: await _headers(auth)),
    );
    final data = res.data;
    if (data is Map<String, dynamic> && data['success'] == true) {
      return (data['data'] as Map<String, dynamic>?) ?? {};
    }
    final responseMap = data is Map<String, dynamic> ? data : null;
    final error = responseMap?['error'] as Map<String, dynamic>?;
    final code =
        error?['code']?.toString() ??
        responseMap?['code']?.toString() ??
        'UNKNOWN';
    if (res.statusCode == 401 && auth && !retried && await _tryRefresh()) {
      return requestV1(method, path, body: body, auth: auth, retried: true);
    }
    throw ApiException(
      code,
      error?['message'] as String? ??
          responseMap?['message'] as String? ??
          '请求失败',
      httpStatus: res.statusCode,
    );
  }

  /// 请求旧版接口（平铺 JSON，错误为 {code, message}）
  Future<Map<String, dynamic>> requestLegacy(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool auth = true,
    bool stationAuth = false,
    bool retried = false,
  }) async {
    final res = await _dio.request(
      path,
      data: body,
      options: Options(
        method: method,
        headers: await _headers(auth, stationAuth: stationAuth),
      ),
    );
    final data = res.data as Map<String, dynamic>? ?? {};
    final status = res.statusCode ?? 0;
    if (status >= 200 && status < 300) return data;
    if (status == 401 && auth && !retried && await _tryRefresh()) {
      return requestLegacy(
        method,
        path,
        body: body,
        auth: auth,
        stationAuth: stationAuth,
        retried: true,
      );
    }
    throw ApiException(
      'HTTP_$status',
      data['message'] as String? ?? '请求失败',
      httpStatus: status,
    );
  }

  /// AI流式请求。平台登录Token与网站API Key分开传递，避免相互覆盖。
  Future<Response<ResponseBody>> requestAiStream(
    String path, {
    required Map<String, dynamic> body,
    bool retried = false,
  }) async {
    final res = await _dio.post<ResponseBody>(
      path,
      data: body,
      options: Options(
        headers: await _headers(true, stationAuth: true),
        responseType: ResponseType.stream,
        receiveTimeout: const Duration(minutes: 6),
      ),
    );
    final status = res.statusCode ?? 0;
    final rawError = status >= 200 && status < 300
        ? null
        : (res.data == null
              ? ''
              : await utf8.decoder
                    .bind(res.data!.stream.cast<List<int>>())
                    .join());
    if (status == 401 && !retried && await _tryRefresh()) {
      return requestAiStream(path, body: body, retried: true);
    }
    if (status < 200 || status >= 300) {
      String message = 'AI请求失败';
      String code = 'HTTP_$status';
      try {
        final json = jsonDecode(rawError!) as Map<String, dynamic>;
        code = json['code']?.toString() ?? code;
        message =
            json['message']?.toString() ??
            (json['error'] as Map<String, dynamic>?)?['message']?.toString() ??
            message;
      } catch (_) {}
      throw ApiException(code, message, httpStatus: status);
    }
    return res;
  }

  Future<List<int>> downloadLegacy(String path, {bool retried = false}) async {
    final res = await _dio.get<List<int>>(
      path,
      options: Options(
        headers: await _headers(true),
        responseType: ResponseType.bytes,
        receiveTimeout: const Duration(minutes: 3),
      ),
    );
    final status = res.statusCode ?? 0;
    if (status == 401 && !retried && await _tryRefresh()) {
      return downloadLegacy(path, retried: true);
    }
    if (status < 200 || status >= 300 || res.data == null) {
      String message = '文件下载失败';
      try {
        final raw = utf8.decode(res.data ?? const []);
        final json = jsonDecode(raw) as Map<String, dynamic>;
        message = json['message']?.toString() ?? message;
      } catch (_) {}
      throw ApiException('HTTP_$status', message, httpStatus: status);
    }
    return res.data!;
  }

  Future<Map<String, String>> _headers(
    bool auth, {
    bool stationAuth = false,
  }) async {
    final headers = <String, String>{
      'X-Install-ID': await DeviceIdentity.instance.getOrCreate(),
    };
    if (auth && _accessToken != null) {
      headers['Authorization'] = 'Bearer $_accessToken';
    }
    if (stationAuth) {
      final key = await StationCredentialService.instance.read();
      if (key != null && key.isNotEmpty) headers['X-Station-Key'] = key;
    }
    return headers;
  }

  Future<bool> _tryRefresh() async {
    final cb = onUnauthorized;
    if (cb == null) return false;
    try {
      return await cb();
    } catch (_) {
      return false;
    }
  }
}
