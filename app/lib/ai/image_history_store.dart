import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

class ImageHistoryRecord {
  const ImageHistoryRecord({
    required this.id,
    required this.prompt,
    required this.renderedPrompt,
    required this.model,
    required this.ratio,
    required this.createdAt,
    this.localPath,
    this.imageUrl,
  });

  final String id;
  final String prompt;
  final String renderedPrompt;
  final String model;
  final String ratio;
  final DateTime createdAt;
  final String? localPath;
  final String? imageUrl;

  factory ImageHistoryRecord.fromJson(Map<String, dynamic> json) {
    return ImageHistoryRecord(
      id: json['id']?.toString() ?? '',
      prompt: json['prompt']?.toString() ?? '',
      renderedPrompt: json['rendered_prompt']?.toString() ?? '',
      model: json['model']?.toString() ?? '',
      ratio: json['ratio']?.toString() ?? '1:1',
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      localPath: json['local_path']?.toString(),
      imageUrl: json['image_url']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'prompt': prompt,
    'rendered_prompt': renderedPrompt,
    'model': model,
    'ratio': ratio,
    'created_at': createdAt.toIso8601String(),
    'local_path': localPath,
    'image_url': imageUrl,
  };
}

class ImageHistoryStore {
  ImageHistoryStore._();
  static final ImageHistoryStore instance = ImageHistoryStore._();

  static const _maxRecords = 30;

  Future<Directory> _directory() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      '${support.path}${Platform.pathSeparator}generated_images',
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<File> _indexFile() async {
    final directory = await _directory();
    return File('${directory.path}${Platform.pathSeparator}history.json');
  }

  Future<List<ImageHistoryRecord>> load() async {
    try {
      final file = await _indexFile();
      if (!await file.exists()) return [];
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List<dynamic>) return [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(ImageHistoryRecord.fromJson)
          .where((item) => item.id.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<ImageHistoryRecord> save({
    required String prompt,
    required String renderedPrompt,
    required String model,
    required String ratio,
    Uint8List? imageBytes,
    String? imageUrl,
  }) async {
    final directory = await _directory();
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    String? localPath;
    if (imageBytes != null && imageBytes.isNotEmpty) {
      final file = File('${directory.path}${Platform.pathSeparator}$id.png');
      await file.writeAsBytes(imageBytes, flush: true);
      localPath = file.path;
    }
    final record = ImageHistoryRecord(
      id: id,
      prompt: prompt,
      renderedPrompt: renderedPrompt,
      model: model,
      ratio: ratio,
      createdAt: DateTime.now(),
      localPath: localPath,
      imageUrl: imageUrl,
    );
    final records = await load();
    records.insert(0, record);
    while (records.length > _maxRecords) {
      final removed = records.removeLast();
      final path = removed.localPath;
      if (path != null) {
        try {
          final file = File(path);
          if (await file.exists()) await file.delete();
        } on FileSystemException {
          // 历史索引仍可更新；遗留文件可在下次清理。
        }
      }
    }
    await (await _indexFile()).writeAsString(
      jsonEncode(records.map((item) => item.toJson()).toList()),
      flush: true,
    );
    return record;
  }
}
