import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 用户在网站生成的 New API Key。
///
/// Key 仅保存在手机系统安全存储；业务后台只在单次AI请求中透传，不持久化。
class StationCredentialService {
  StationCredentialService._();
  static final StationCredentialService instance = StationCredentialService._();

  static const _storage = FlutterSecureStorage();
  static const _legacyKey = 'station_api_key_v1';
  String? _activeStorageKey;
  String? _cached;
  bool _loaded = false;

  /// 将凭据空间绑定到当前 App 账号，防止同一设备切换账号后复用前一人的 Key。
  Future<void> activateAccount(String? accountId) async {
    final normalized = accountId?.trim();
    final nextKey = normalized == null || normalized.isEmpty
        ? null
        : 'station_api_key_v2_$normalized';
    if (_activeStorageKey == nextKey) return;
    _activeStorageKey = nextKey;
    _cached = null;
    _loaded = false;
    // v1 Key 没有账号归属，不能安全迁移到任意新登录账号。
    await _storage.delete(key: _legacyKey);
  }

  Future<String?> read() async {
    if (_loaded) return _cached;
    final key = _activeStorageKey;
    if (key == null) return null;
    _cached = (await _storage.read(key: key))?.trim();
    _loaded = true;
    return _cached;
  }

  Future<void> save(String value) async {
    final normalized = value.trim().replaceFirst(
      RegExp(r'^Bearer\s+', caseSensitive: false),
      '',
    );
    if (normalized.length < 8 ||
        normalized.length > 512 ||
        normalized.contains(RegExp(r'[\r\n\x00]'))) {
      throw const FormatException('API Key格式无效');
    }
    final key = _activeStorageKey;
    if (key == null) throw StateError('请先联网完成登录后再保存API Key');
    await _storage.write(key: key, value: normalized);
    _cached = normalized;
    _loaded = true;
  }

  Future<void> clear() async {
    final key = _activeStorageKey;
    if (key != null) await _storage.delete(key: key);
    _cached = null;
    _loaded = true;
  }

  Future<bool> get isConfigured async => (await read())?.isNotEmpty == true;

  Future<String?> masked() async {
    final value = await read();
    if (value == null || value.isEmpty) return null;
    if (value.length <= 10) return '已配置';
    return '${value.substring(0, 4)}••••${value.substring(value.length - 4)}';
  }
}
