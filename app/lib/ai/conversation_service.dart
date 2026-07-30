import '../api/api_client.dart';
import '../config.dart';

class ConversationItem {
  const ConversationItem({
    required this.id,
    required this.title,
    required this.model,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String model;
  final DateTime updatedAt;

  factory ConversationItem.fromJson(Map<String, dynamic> json) {
    return ConversationItem(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '未命名对话',
      model: json['model']?.toString() ?? '',
      updatedAt:
          DateTime.tryParse(json['updated_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class ConversationMessage {
  const ConversationMessage({
    required this.role,
    required this.content,
    required this.segmentIndex,
  });

  final String role;
  final String content;
  final int segmentIndex;

  factory ConversationMessage.fromJson(Map<String, dynamic> json) {
    return ConversationMessage(
      role: json['role']?.toString() ?? 'assistant',
      content: json['content']?.toString() ?? '',
      segmentIndex: (json['segment_index'] as num?)?.toInt() ?? 0,
    );
  }
}

class ConversationContext {
  const ConversationContext({
    required this.messages,
    required this.summaries,
    required this.currentSegment,
  });

  final List<ConversationMessage> messages;
  final List<String> summaries;
  final int currentSegment;
}

class SavedTurn {
  const SavedTurn({
    required this.segmentIndex,
    required this.startedNewSegment,
  });

  final int segmentIndex;
  final bool startedNewSegment;
}

class CompactedConversation {
  const CompactedConversation({
    required this.currentSegment,
    required this.summary,
  });

  final int currentSegment;
  final String summary;
}

class ConversationService {
  ConversationService._();
  static final ConversationService instance = ConversationService._();

  final List<ConversationItem> _previewItems = [
    ConversationItem(
      id: 'preview-1',
      title: 'Flutter 客户端并发设计',
      model: 'gpt-5.4',
      updatedAt: DateTime(2026, 7, 28, 18, 20),
    ),
    ConversationItem(
      id: 'preview-2',
      title: '广告额度防作弊方案',
      model: 'claude-sonnet-4.6',
      updatedAt: DateTime(2026, 7, 28, 16, 10),
    ),
  ];

  final Map<String, List<ConversationMessage>> _previewMessages = {
    'preview-1': const [
      ConversationMessage(
        role: 'user',
        content: 'Flutter 桌面端多人并发时应该怎样控制任务数量？',
        segmentIndex: 0,
      ),
      ConversationMessage(
        role: 'assistant',
        content: '客户端只负责发起任务，并发总量应由服务端租约控制；单用户和全局上限需要分开设置。',
        segmentIndex: 0,
      ),
      ConversationMessage(
        role: 'user',
        content: '如果同时有很多人生图，怎样避免服务整体卡死？',
        segmentIndex: 0,
      ),
      ConversationMessage(
        role: 'assistant',
        content: '将生图放入独立任务队列，设置全局并发、单用户并发、超时和熔断，不能让请求无限堆积。',
        segmentIndex: 0,
      ),
      ConversationMessage(
        role: 'user',
        content: '聊天记录应该全部放在手机本地吗？',
        segmentIndex: 0,
      ),
      ConversationMessage(
        role: 'assistant',
        content: '本机只保留当前段和最近两段全文，旧段压缩为摘要放到云端，需要时再拉取。',
        segmentIndex: 0,
      ),
      ConversationMessage(
        role: 'user',
        content: '换个主题，模型中心怎样和网页版保持一致？',
        segmentIndex: 1,
      ),
      ConversationMessage(
        role: 'assistant',
        content: '模型列表统一读取本站网关接口，网页与 App 使用同一份可用模型配置。',
        segmentIndex: 1,
      ),
      ConversationMessage(
        role: 'user',
        content: '本站 Key 在多个设备之间怎样同步？',
        segmentIndex: 1,
      ),
      ConversationMessage(
        role: 'assistant',
        content: '登录后从加密凭据仓拉取，更新和删除也写回同一账号；本机只存安全副本。',
        segmentIndex: 1,
      ),
      ConversationMessage(
        role: 'user',
        content: '生图历史需要保存哪些信息？',
        segmentIndex: 1,
      ),
      ConversationMessage(
        role: 'assistant',
        content: '保存原提示词、最终拼接参数、模型、比例、生成时间，以及本地图片或远程地址。',
        segmentIndex: 1,
      ),
    ],
    'preview-2': const [
      ConversationMessage(
        role: 'user',
        content: '怎样避免脚本跳过广告直接领取额度？',
        segmentIndex: 0,
      ),
      ConversationMessage(
        role: 'assistant',
        content: '奖励必须以广告平台服务端回调为准，并对用户、设备、IP、任务令牌同时做幂等与日限额。',
        segmentIndex: 0,
      ),
    ],
  };

  Future<List<ConversationItem>> list() async {
    if (AppConfig.previewMode) return List.unmodifiable(_previewItems);
    final data = await ApiClient.instance.requestLegacy(
      'GET',
      '/api/ai/conversations',
    );
    return (data['conversations'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ConversationItem.fromJson)
        .toList();
  }

  Future<ConversationItem> create({
    required String title,
    required String model,
  }) async {
    if (AppConfig.previewMode) {
      final item = ConversationItem(
        id: 'preview-${DateTime.now().microsecondsSinceEpoch}',
        title: title,
        model: model,
        updatedAt: DateTime.now(),
      );
      _previewItems.insert(0, item);
      _previewMessages[item.id] = [];
      return item;
    }
    final data = await ApiClient.instance.requestLegacy(
      'POST',
      '/api/ai/conversations',
      body: {'title': title, 'model': model},
    );
    return ConversationItem.fromJson(data);
  }

  Future<ConversationContext> load(String id) async {
    if (AppConfig.previewMode) {
      final messages = List<ConversationMessage>.from(
        _previewMessages[id] ?? const [],
      );
      final current = messages.isEmpty ? 0 : messages.last.segmentIndex;
      return ConversationContext(
        messages: messages,
        summaries: const [],
        currentSegment: current,
      );
    }
    final data = await ApiClient.instance.requestLegacy(
      'GET',
      '/api/ai/conversations/$id/context',
    );
    final conversation = data['conversation'] as Map<String, dynamic>? ?? {};
    return ConversationContext(
      messages: (data['messages'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ConversationMessage.fromJson)
          .toList(),
      summaries: (data['summaries'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((item) => item['summary']?.toString() ?? '')
          .where((summary) => summary.isNotEmpty)
          .toList(),
      currentSegment: (conversation['current_segment'] as num?)?.toInt() ?? 0,
    );
  }

  Future<SavedTurn> saveTurn({
    required String conversationId,
    required String userContent,
    required String assistantContent,
    required String model,
  }) async {
    if (AppConfig.previewMode) {
      final messages = _previewMessages.putIfAbsent(conversationId, () => []);
      final current = messages.isEmpty ? 0 : messages.last.segmentIndex;
      messages.addAll([
        ConversationMessage(
          role: 'user',
          content: userContent,
          segmentIndex: current,
        ),
        ConversationMessage(
          role: 'assistant',
          content: assistantContent,
          segmentIndex: current,
        ),
      ]);
      return SavedTurn(segmentIndex: current, startedNewSegment: false);
    }
    final data = await ApiClient.instance.requestLegacy(
      'POST',
      '/api/ai/conversations/$conversationId/turns',
      body: {
        'user_content': userContent,
        'assistant_content': assistantContent,
        'model': model,
      },
    );
    return SavedTurn(
      segmentIndex: (data['segment_index'] as num?)?.toInt() ?? 0,
      startedNewSegment: data['started_new_segment'] == true,
    );
  }

  Future<void> delete(String id) async {
    if (AppConfig.previewMode) {
      _previewItems.removeWhere((item) => item.id == id);
      _previewMessages.remove(id);
      return;
    }
    await ApiClient.instance.requestLegacy(
      'DELETE',
      '/api/ai/conversations/$id',
    );
  }

  Future<CompactedConversation> compact(String id, String summary) async {
    if (AppConfig.previewMode) {
      _previewMessages[id] = [];
      return CompactedConversation(currentSegment: 1, summary: summary);
    }
    final data = await ApiClient.instance.requestLegacy(
      'POST',
      '/api/ai/conversations/$id/compact',
      body: {'summary': summary},
    );
    return CompactedConversation(
      currentSegment: (data['current_segment'] as num?)?.toInt() ?? 1,
      summary: data['summary']?.toString() ?? summary,
    );
  }
}
