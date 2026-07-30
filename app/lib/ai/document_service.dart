import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../api/api_client.dart';
import '../config.dart';

class DocumentJob {
  const DocumentJob({
    required this.id,
    required this.kind,
    required this.status,
    required this.prompt,
    required this.model,
    required this.progress,
    required this.createdAt,
    this.title,
    this.artifactName,
    this.errorMessage,
    this.useImages = false,
    this.downloadable = false,
    this.outputMetadata = const {},
  });

  final String id;
  final String kind;
  final String status;
  final String prompt;
  final String model;
  final int progress;
  final DateTime createdAt;
  final String? title;
  final String? artifactName;
  final String? errorMessage;
  final bool useImages;
  final bool downloadable;
  final Map<String, dynamic> outputMetadata;

  bool get active => status == 'queued' || status == 'processing';
  bool get completed => status == 'completed';

  String get kindLabel => kind == 'pptx' ? 'PPT' : 'Word';

  String get statusLabel => switch (status) {
    'queued' => '排队中',
    'processing' => '生成中 $progress%',
    'completed' => '已完成',
    'failed' => '生成失败',
    'cancelled' => '已取消',
    'expired' => '文件已过期',
    _ => status,
  };

  factory DocumentJob.fromJson(Map<String, dynamic> json) {
    return DocumentJob(
      id: json['id']?.toString() ?? '',
      kind: json['kind']?.toString() ?? 'docx',
      status: json['status']?.toString() ?? 'queued',
      prompt: json['prompt']?.toString() ?? '',
      model: json['model']?.toString() ?? '',
      progress: (json['progress'] as num?)?.toInt() ?? 0,
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      title: json['title']?.toString(),
      artifactName: json['artifact_name']?.toString(),
      errorMessage: json['error_message']?.toString(),
      useImages: json['use_images'] == true,
      downloadable: json['downloadable'] == true,
      outputMetadata:
          json['output_metadata'] as Map<String, dynamic>? ?? const {},
    );
  }

  DocumentJob copyWith({
    String? status,
    int? progress,
    String? title,
    String? artifactName,
    bool? downloadable,
    Map<String, dynamic>? outputMetadata,
  }) {
    return DocumentJob(
      id: id,
      kind: kind,
      status: status ?? this.status,
      prompt: prompt,
      model: model,
      progress: progress ?? this.progress,
      createdAt: createdAt,
      title: title ?? this.title,
      artifactName: artifactName ?? this.artifactName,
      errorMessage: errorMessage,
      useImages: useImages,
      downloadable: downloadable ?? this.downloadable,
      outputMetadata: outputMetadata ?? this.outputMetadata,
    );
  }
}

class DocumentService {
  DocumentService._();
  static final DocumentService instance = DocumentService._();

  final List<DocumentJob> _previewJobs = [
    DocumentJob(
      id: 'preview-docx',
      kind: 'docx',
      status: 'completed',
      prompt: '整理AI工具APP开发说明',
      model: 'deepseek-v3.2',
      progress: 100,
      createdAt: DateTime(2026, 7, 29, 9, 20),
      title: 'AI工具APP开发说明',
      artifactName: 'AI工具APP开发说明.docx',
      downloadable: true,
      outputMetadata: {'item_count': 8, 'generated_images': 0},
    ),
    DocumentJob(
      id: 'preview-pptx',
      kind: 'pptx',
      status: 'completed',
      prompt: '制作产品功能介绍PPT',
      model: 'gpt-5.4',
      progress: 100,
      createdAt: DateTime(2026, 7, 29, 8, 40),
      title: 'AI公益工作台产品介绍',
      artifactName: 'AI公益工作台产品介绍.pptx',
      useImages: true,
      downloadable: true,
      outputMetadata: {'item_count': 10, 'generated_images': 4},
    ),
  ];

  Future<List<DocumentJob>> list({String? conversationId}) async {
    if (AppConfig.previewMode) {
      final now = DateTime.now();
      for (var index = 0; index < _previewJobs.length; index++) {
        final job = _previewJobs[index];
        if (job.active && now.difference(job.createdAt).inMilliseconds > 1300) {
          _previewJobs[index] = job.copyWith(
            status: 'completed',
            progress: 100,
            title: job.kind == 'pptx' ? 'AI生成演示文稿' : 'AI生成Word文档',
            artifactName: job.kind == 'pptx'
                ? 'AI生成演示文稿.pptx'
                : 'AI生成Word文档.docx',
            downloadable: true,
            outputMetadata: {
              'item_count': job.kind == 'pptx' ? 9 : 7,
              'generated_images': job.useImages ? 3 : 0,
            },
          );
        }
      }
      return List.unmodifiable(_previewJobs);
    }
    final suffix = conversationId == null
        ? ''
        : '?conversation_id=${Uri.encodeQueryComponent(conversationId)}';
    final data = await ApiClient.instance.requestLegacy(
      'GET',
      '/api/ai/documents$suffix',
    );
    return (data['jobs'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(DocumentJob.fromJson)
        .toList();
  }

  Future<DocumentJob> create({
    required String kind,
    required String prompt,
    required String model,
    String? conversationId,
    String? imageModel,
    bool useImages = false,
  }) async {
    if (AppConfig.previewMode) {
      final job = DocumentJob(
        id: 'preview-${DateTime.now().microsecondsSinceEpoch}',
        kind: kind,
        status: 'processing',
        prompt: prompt,
        model: model,
        progress: 18,
        createdAt: DateTime.now(),
        useImages: useImages,
      );
      _previewJobs.insert(0, job);
      return job;
    }
    final data = await ApiClient.instance.requestLegacy(
      'POST',
      '/api/ai/documents',
      body: {
        'kind': kind,
        'prompt': prompt,
        'model': model,
        'conversation_id': conversationId,
        'use_images': useImages,
        'image_model': imageModel,
      },
    );
    return DocumentJob.fromJson(data);
  }

  Future<DocumentJob?> cancel(String id) async {
    if (AppConfig.previewMode) {
      final index = _previewJobs.indexWhere((job) => job.id == id);
      if (index < 0) return null;
      final job = _previewJobs[index].copyWith(
        status: 'cancelled',
        progress: 0,
      );
      _previewJobs[index] = job;
      return job;
    }
    final data = await ApiClient.instance.requestLegacy(
      'DELETE',
      '/api/ai/documents/$id',
    );
    return DocumentJob.fromJson(data);
  }

  Future<String> download(DocumentJob job) async {
    if (AppConfig.previewMode) {
      throw StateError('预览模式展示任务流程，不生成真实文件');
    }
    final bytes = await ApiClient.instance.downloadLegacy(
      '/api/ai/documents/${job.id}/download',
    );
    final directory =
        await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    final fallback = job.kind == 'pptx' ? 'AI文档.pptx' : 'AI文档.docx';
    final safeName = (job.artifactName ?? fallback).replaceAll(
      RegExp(r'[<>:"/\\|?*\x00-\x1F]'),
      '_',
    );
    final file = File('${directory.path}${Platform.pathSeparator}$safeName');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}
