import 'dart:async';
import 'dart:convert';

import '../api/api_client.dart';

class AiService {
  AiService._();
  static final AiService instance = AiService._();

  Future<List<String>> loadModels({bool image = false}) async {
    final suffix = image ? '?capability=image' : '';
    final json = await ApiClient.instance.requestLegacy(
      'GET',
      '/api/ai/models$suffix',
      stationAuth: true,
    );
    final data = json['data'] as List<dynamic>? ?? const [];
    return data
        .map((item) => (item as Map<String, dynamic>?)?['id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  Stream<String> streamChat({
    required String model,
    required List<Map<String, String>> messages,
  }) async* {
    final response = await ApiClient.instance.requestAiStream(
      '/api/ai/chat/completions',
      body: {'model': model, 'messages': messages, 'stream': true, 'n': 1},
    );
    final lines = response.data!.stream
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    await for (final line in lines) {
      if (!line.startsWith('data:')) continue;
      final data = line.substring(5).trim();
      if (data.isEmpty || data == '[DONE]') continue;
      try {
        final json = jsonDecode(data) as Map<String, dynamic>;
        final choices = json['choices'] as List<dynamic>?;
        if (choices == null || choices.isEmpty) continue;
        final choice = choices.first as Map<String, dynamic>;
        final delta = choice['delta'] as Map<String, dynamic>?;
        final content = delta?['content'];
        if (content is String && content.isNotEmpty) yield content;
      } catch (_) {
        // 忽略上游心跳/非标准扩展事件，不中断整次对话。
      }
    }
  }

  Future<Map<String, dynamic>> generateImage({
    required String model,
    required String prompt,
    required String size,
  }) {
    return ApiClient.instance.requestLegacy(
      'POST',
      '/api/ai/images/generations',
      stationAuth: true,
      body: {
        'model': model,
        'prompt': prompt,
        'size': size,
        'n': 1,
        'response_format': 'b64_json',
      },
    );
  }
}
