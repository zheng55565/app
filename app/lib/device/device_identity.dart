import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// App 安装标识：用于服务端设备维度限额。
///
/// 这是反批量滥用的一项信号，不是硬件身份，也不能替代 Play Integrity 等
/// 平台完整性证明。值只保存在系统安全存储，不展示给用户。
class DeviceIdentity {
  DeviceIdentity._();
  static final DeviceIdentity instance = DeviceIdentity._();

  static const _storage = FlutterSecureStorage();
  static const _key = 'install_identity_v1';
  String? _cached;

  Future<String> getOrCreate() async {
    final cached = _cached;
    if (cached != null) return cached;
    final existing = await _storage.read(key: _key);
    if (existing != null &&
        RegExp(r'^[A-Za-z0-9_-]{20,128}$').hasMatch(existing)) {
      _cached = existing;
      return existing;
    }
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final created = base64UrlEncode(bytes).replaceAll('=', '');
    await _storage.write(key: _key, value: created);
    _cached = created;
    return created;
  }
}
