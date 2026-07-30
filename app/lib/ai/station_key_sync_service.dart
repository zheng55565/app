import '../api/api_client.dart';
import 'station_credential_service.dart';

class StationKeySyncResult {
  const StationKeySyncResult({
    required this.configured,
    this.key,
    this.masked,
    this.updatedAt,
  });

  final bool configured;
  final String? key;
  final String? masked;
  final DateTime? updatedAt;
}

class StationKeySyncService {
  StationKeySyncService._();
  static final StationKeySyncService instance = StationKeySyncService._();

  Future<StationKeySyncResult> pull() async {
    final data = await ApiClient.instance.requestLegacy(
      'GET',
      '/api/ai/credential',
    );
    final configured = data['configured'] == true;
    final key = data['key']?.toString();
    if (configured && key != null && key.isNotEmpty) {
      await StationCredentialService.instance.save(key);
    }
    return StationKeySyncResult(
      configured: configured,
      key: key,
      masked: data['masked']?.toString(),
      updatedAt: DateTime.tryParse(data['updated_at']?.toString() ?? ''),
    );
  }

  Future<StationKeySyncResult> save(String value) async {
    try {
      final data = await ApiClient.instance.requestLegacy(
        'PUT',
        '/api/ai/credential',
        body: {'key': value},
      );
      final key = data['key']?.toString() ?? value;
      await StationCredentialService.instance.save(key);
      return StationKeySyncResult(
        configured: true,
        key: key,
        masked: data['masked']?.toString(),
        updatedAt: DateTime.tryParse(data['updated_at']?.toString() ?? ''),
      );
    } on ApiException catch (error) {
      if (error.httpStatus != 503) rethrow;
      await StationCredentialService.instance.save(value);
      return StationKeySyncResult(
        configured: true,
        key: value,
        masked: await StationCredentialService.instance.masked(),
      );
    }
  }

  Future<void> deleteEverywhere() async {
    try {
      await ApiClient.instance.requestLegacy('DELETE', '/api/ai/credential');
    } on ApiException catch (error) {
      if (error.httpStatus != 503) rethrow;
    }
    await StationCredentialService.instance.clear();
  }
}
