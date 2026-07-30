import 'dart:async';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../ai/ai_service.dart';
import '../ai/conversation_service.dart';
import '../ai/document_service.dart';
import '../api/api_client.dart';
import '../config.dart';
import '../preview/preview_data.dart';

class WorkbenchPage extends StatefulWidget {
  const WorkbenchPage({super.key, required this.onOpenProfile});

  final VoidCallback onOpenProfile;

  @override
  State<WorkbenchPage> createState() => _WorkbenchPageState();
}

class _ChatMessage {
  _ChatMessage(this.role, this.content, {required this.segmentIndex});

  final String role;
  String content;
  int segmentIndex;
}

enum _WorkbenchTool { chat, word, ppt }

extension on _WorkbenchTool {
  String get label => switch (this) {
    _WorkbenchTool.chat => '对话',
    _WorkbenchTool.word => 'Word',
    _WorkbenchTool.ppt => 'PPT配图',
  };

  String get hint => switch (this) {
    _WorkbenchTool.chat => '给 AI 发送消息',
    _WorkbenchTool.word => '描述需要生成的 Word 文档',
    _WorkbenchTool.ppt => '描述需要生成的 PPT，自动生成配图',
  };

  IconData get icon => switch (this) {
    _WorkbenchTool.chat => Icons.chat_bubble_outline,
    _WorkbenchTool.word => Icons.description_outlined,
    _WorkbenchTool.ppt => Icons.slideshow_outlined,
  };
}

class _WorkbenchPageState extends State<WorkbenchPage> {
  final _promptController = TextEditingController();
  final _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  final Map<int, GlobalKey> _turnKeys = {};
  List<DocumentJob> _documentJobs = const [];
  List<ConversationItem> _conversations = const [];
  List<String> _summaries = const [];
  List<String> _models = const [];
  String? _selectedModel;
  String? _conversationId;
  String? _conversationTitle;
  String? _error;
  int _currentSegment = 0;
  int? _activeTurnMessageIndex;
  _WorkbenchTool _selectedTool = _WorkbenchTool.chat;
  bool _loadingModels = true;
  bool _loadingHistory = true;
  bool _loadingConversation = false;
  bool _sending = false;
  bool _creatingDocument = false;
  Timer? _documentTimer;

  @override
  void initState() {
    super.initState();
    _loadModels();
    _loadConversations();
    _loadDocumentJobs();
    _documentTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_documentJobs.any((job) => job.active)) {
        _loadDocumentJobs(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _promptController.dispose();
    _scrollController.dispose();
    _documentTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDocumentJobs({bool silent = false}) async {
    try {
      final jobs = await DocumentService.instance.list();
      if (mounted) setState(() => _documentJobs = jobs);
    } catch (_) {
      if (!silent && mounted) setState(() => _error = '文档任务暂时无法加载');
    }
  }

  Future<void> _loadModels() async {
    setState(() {
      _loadingModels = true;
      _error = null;
    });
    if (AppConfig.previewMode) {
      setState(() {
        _models = PreviewData.chatModels;
        _selectedModel = PreviewData.chatModels.first;
        _loadingModels = false;
      });
      return;
    }
    try {
      final models = await AiService.instance.loadModels();
      if (!mounted) return;
      setState(() {
        _models = models;
        _selectedModel = models.contains(_selectedModel)
            ? _selectedModel
            : (models.isEmpty ? null : models.first);
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '模型列表加载失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _loadingModels = false);
    }
  }

  Future<void> _loadConversations() async {
    setState(() => _loadingHistory = true);
    try {
      final items = await ConversationService.instance.list();
      if (mounted) setState(() => _conversations = items);
    } catch (_) {
      // 历史不可用不阻断新对话。
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  Future<void> _openConversation(ConversationItem item) async {
    Navigator.of(context).pop();
    setState(() {
      _loadingConversation = true;
      _error = null;
    });
    try {
      final contextData = await ConversationService.instance.load(item.id);
      if (!mounted) return;
      setState(() {
        _conversationId = item.id;
        _conversationTitle = item.title;
        _selectedModel = _models.contains(item.model)
            ? item.model
            : _selectedModel;
        _summaries = contextData.summaries;
        _currentSegment = contextData.currentSegment;
        _messages
          ..clear()
          ..addAll(
            contextData.messages.map(
              (message) => _ChatMessage(
                message.role,
                message.content,
                segmentIndex: message.segmentIndex,
              ),
            ),
          );
        _turnKeys.clear();
        _activeTurnMessageIndex = _lastUserMessageIndex();
      });
      _scrollToEnd();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loadingConversation = false);
    }
  }

  void _newConversation() {
    if (_sending) return;
    setState(() {
      _resetConversationState();
    });
  }

  void _resetConversationState() {
    _conversationId = null;
    _conversationTitle = null;
    _currentSegment = 0;
    _summaries = const [];
    _messages.clear();
    _turnKeys.clear();
    _activeTurnMessageIndex = null;
    _error = null;
  }

  int? _lastUserMessageIndex() {
    for (var index = _messages.length - 1; index >= 0; index--) {
      if (_messages[index].role == 'user') return index;
    }
    return null;
  }

  List<int> get _turnMessageIndices => [
    for (var index = 0; index < _messages.length; index++)
      if (_messages[index].role == 'user') index,
  ];

  void _focusTurn(int messageIndex) {
    setState(() => _activeTurnMessageIndex = messageIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final targetContext = _turnKeys[messageIndex]?.currentContext;
      if (targetContext == null) return;
      Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: 0.12,
      );
    });
  }

  String _titleFor(String prompt) {
    final singleLine = prompt.replaceAll(RegExp(r'\s+'), ' ').trim();
    return singleLine.length <= 24
        ? singleLine
        : '${singleLine.substring(0, 24)}…';
  }

  Future<bool> _ensureConversation(String prompt, String model) async {
    if (_conversationId != null) return true;
    try {
      final item = await ConversationService.instance.create(
        title: _titleFor(prompt),
        model: model,
      );
      if (!mounted) return false;
      setState(() {
        _conversationId = item.id;
        _conversationTitle = item.title;
        _conversations = [item, ..._conversations];
      });
      return true;
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
      return false;
    }
  }

  Future<void> _send() async {
    final prompt = _promptController.text.trim();
    final model = _selectedModel;
    if (prompt.isEmpty || model == null || _sending) return;
    setState(() => _sending = true);
    if (!await _ensureConversation(prompt, model)) {
      if (mounted) setState(() => _sending = false);
      return;
    }
    _promptController.clear();
    final history = <Map<String, String>>[
      if (_summaries.isNotEmpty)
        {'role': 'system', 'content': '前序对话摘要：\n${_summaries.join('\n\n')}'},
      ..._messages.map(
        (message) => {'role': message.role, 'content': message.content},
      ),
      {'role': 'user', 'content': prompt},
    ];
    setState(() {
      final userMessageIndex = _messages.length;
      _messages.add(
        _ChatMessage('user', prompt, segmentIndex: _currentSegment),
      );
      _messages.add(
        _ChatMessage('assistant', '', segmentIndex: _currentSegment),
      );
      _activeTurnMessageIndex = userMessageIndex;
      _error = null;
    });
    _scrollToEnd();

    var succeeded = false;
    if (AppConfig.previewMode) {
      await Future<void>.delayed(const Duration(milliseconds: 550));
      if (!mounted) return;
      setState(() => _messages.last.content = PreviewData.chatReply(prompt));
      succeeded = true;
    } else {
      try {
        await for (final chunk in AiService.instance.streamChat(
          model: model,
          messages: history,
        )) {
          if (!mounted) return;
          setState(() => _messages.last.content += chunk);
          _scrollToEnd();
        }
        if (mounted && _messages.last.content.isEmpty) {
          setState(() => _messages.last.content = '模型未返回可显示内容');
        } else {
          succeeded = true;
        }
      } on ApiException catch (error) {
        if (mounted) {
          setState(() => _messages.last.content = '请求失败：${error.message}');
        }
      } catch (_) {
        if (mounted) setState(() => _messages.last.content = '连接中断，请重试');
      }
    }

    if (succeeded && mounted) {
      try {
        final saved = await ConversationService.instance.saveTurn(
          conversationId: _conversationId!,
          userContent: prompt,
          assistantContent: _messages.last.content,
          model: model,
        );
        if (mounted) {
          setState(() {
            _currentSegment = saved.segmentIndex;
            _messages[_messages.length - 2].segmentIndex = saved.segmentIndex;
            _messages.last.segmentIndex = saved.segmentIndex;
          });
        }
        await _loadConversations();
      } catch (_) {
        if (mounted) {
          setState(() => _error = '回复已完成，但对话历史暂未同步');
        }
      }
    }
    if (mounted) setState(() => _sending = false);
    _scrollToEnd();
  }

  Future<void> _submit() async {
    if (_selectedTool == _WorkbenchTool.chat) {
      await _send();
      return;
    }
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty || _sending || _creatingDocument) return;
    await _createDocument(prompt, _selectedTool);
  }

  Future<void> _createDocument(String prompt, _WorkbenchTool tool) async {
    final model = _selectedModel;
    if (model == null) return;
    setState(() {
      _creatingDocument = true;
      _error = null;
    });
    if (!await _ensureConversation(prompt, model)) {
      if (mounted) setState(() => _creatingDocument = false);
      return;
    }
    try {
      String? imageModel;
      final useImages = tool == _WorkbenchTool.ppt;
      if (useImages) {
        final imageModels = AppConfig.previewMode
            ? PreviewData.imageModels
            : await AiService.instance.loadModels(image: true);
        if (imageModels.isEmpty) {
          throw ApiException('NO_IMAGE_MODEL', '后台尚未配置生图模型');
        }
        imageModel = imageModels.first;
      }
      final job = await DocumentService.instance.create(
        kind: tool == _WorkbenchTool.ppt ? 'pptx' : 'docx',
        prompt: prompt,
        model: model,
        conversationId: _conversationId,
        imageModel: imageModel,
        useImages: useImages,
      );
      if (!mounted) return;
      _promptController.clear();
      setState(() {
        _documentJobs = [
          job,
          ..._documentJobs.where((item) => item.id != job.id),
        ];
      });
      final response = tool == _WorkbenchTool.ppt
          ? '已提交 PPT 生成任务，将自动生成内容和配图。'
          : '已提交 Word 文档生成任务。';
      await _appendToolTurn(prompt, response, model);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is StateError ? error.message : '文档任务创建失败',
        );
      }
    } finally {
      if (mounted) setState(() => _creatingDocument = false);
    }
  }

  Future<void> _appendToolTurn(
    String prompt,
    String response,
    String model,
  ) async {
    final userIndex = _messages.length;
    setState(() {
      _messages.add(
        _ChatMessage('user', prompt, segmentIndex: _currentSegment),
      );
      _messages.add(
        _ChatMessage('assistant', response, segmentIndex: _currentSegment),
      );
      _activeTurnMessageIndex = userIndex;
    });
    _scrollToEnd();
    try {
      final saved = await ConversationService.instance.saveTurn(
        conversationId: _conversationId!,
        userContent: prompt,
        assistantContent: response,
        model: model,
      );
      if (!mounted) return;
      setState(() {
        _currentSegment = saved.segmentIndex;
        _messages[userIndex].segmentIndex = saved.segmentIndex;
        _messages[userIndex + 1].segmentIndex = saved.segmentIndex;
      });
      await _loadConversations();
    } catch (_) {
      if (mounted) setState(() => _error = '文档任务已创建，但对话历史暂未同步');
    }
  }

  Future<void> _openDocument(DocumentJob job) async {
    try {
      final filePath = await DocumentService.instance.download(job);
      await OpenFilex.open(filePath);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('文件已保存：$filePath')));
    } on StateError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '文件下载或打开失败');
    }
  }

  Future<void> _cancelDocument(DocumentJob job) async {
    try {
      await DocumentService.instance.cancel(job.id);
      await _loadDocumentJobs(silent: true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _deleteConversation(ConversationItem item) async {
    try {
      await ConversationService.instance.delete(item.id);
      if (!mounted) return;
      setState(() {
        _conversations = _conversations
            .where((conversation) => conversation.id != item.id)
            .toList();
        if (_conversationId == item.id) _resetConversationState();
      });
    } catch (_) {
      if (mounted) setState(() => _error = '删除对话失败');
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  String _shortDate(DateTime value) {
    final local = value.toLocal();
    return '${local.month}/${local.day}';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      drawer: Drawer(
        width: 320,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _newConversation();
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('新对话'),
                  ),
                ),
              ),
              if (_loadingHistory) const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: _conversations.isEmpty
                    ? const Center(child: Text('暂无历史对话'))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: _conversations.length,
                        itemBuilder: (context, index) {
                          final item = _conversations[index];
                          final selected = item.id == _conversationId;
                          return ListTile(
                            selected: selected,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            leading: const Icon(Icons.chat_bubble_outline),
                            title: Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${item.model} · ${_shortDate(item.updatedAt)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: IconButton(
                              tooltip: '删除对话',
                              onPressed: () => _deleteConversation(item),
                              icon: const Icon(Icons.delete_outline, size: 19),
                            ),
                            onTap: () => _openConversation(item),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
      appBar: AppBar(
        toolbarHeight: 52,
        titleSpacing: 4,
        title: Text(
          _conversationTitle ?? '新对话',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: '切换模型',
            enabled: !_loadingModels && !_sending,
            initialValue: _selectedModel,
            onSelected: (value) => setState(() => _selectedModel = value),
            itemBuilder: (_) => _models
                .map((model) => PopupMenuItem(value: model, child: Text(model)))
                .toList(),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.memory_outlined, size: 18),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        _selectedModel ?? '选择模型',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: '新对话',
            onPressed: _sending ? null : _newConversation,
            icon: const Icon(Icons.add_comment_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loadingModels || _loadingConversation)
            const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Container(
              width: double.infinity,
              color: colorScheme.errorContainer,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!)),
                  TextButton(
                    onPressed: widget.onOpenProfile,
                    child: const Text('设置'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _messages.isEmpty
                ? _summaries.isNotEmpty
                      ? _CompressedContextState(summary: _summaries.last)
                      : _WorkbenchEmptyState(
                          onSuggestion: (value) {
                            _promptController.text = value;
                            _promptController.selection =
                                TextSelection.collapsed(offset: value.length);
                          },
                        )
                : Stack(
                    children: [
                      Positioned.fill(
                        left: 20,
                        child: SingleChildScrollView(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(8, 12, 12, 16),
                          child: Column(
                            children: [
                              for (
                                var index = 0;
                                index < _messages.length;
                                index++
                              )
                                KeyedSubtree(
                                  key: _messages[index].role == 'user'
                                      ? _turnKeys.putIfAbsent(
                                          index,
                                          () => GlobalKey(),
                                        )
                                      : null,
                                  child: _ConversationMessageItem(
                                    message: _messages[index],
                                    showSegment:
                                        _messages[index].segmentIndex > 0 &&
                                        (index == 0 ||
                                            _messages[index - 1].segmentIndex !=
                                                _messages[index].segmentIndex),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: 20,
                        child: _ConversationLocator(
                          messageIndices: _turnMessageIndices,
                          messages: _messages,
                          activeMessageIndex: _activeTurnMessageIndex,
                          onSelected: _focusTurn,
                        ),
                      ),
                    ],
                  ),
          ),
          if (_documentJobs.isNotEmpty)
            _DocumentJobStrip(
              jobs: _documentJobs.take(8).toList(),
              onOpen: _openDocument,
              onCancel: _cancelDocument,
            ),
          SafeArea(
            top: false,
            child: Container(
              color: colorScheme.surface,
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
                child: Column(
                  children: [
                    TextField(
                      controller: _promptController,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: _selectedTool.hint,
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        PopupMenuButton<_WorkbenchTool>(
                          key: const ValueKey('workbench-tool-menu'),
                          tooltip: '选择工具',
                          enabled: !_sending && !_creatingDocument,
                          initialValue: _selectedTool,
                          onSelected: (value) {
                            setState(() => _selectedTool = value);
                          },
                          itemBuilder: (context) => _WorkbenchTool.values
                              .map(
                                (tool) => PopupMenuItem(
                                  key: ValueKey('workbench-tool-${tool.name}'),
                                  value: tool,
                                  child: Row(
                                    children: [
                                      Icon(tool.icon, size: 18),
                                      const SizedBox(width: 8),
                                      Text(tool.label),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 5,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _selectedTool.icon,
                                  size: 17,
                                  color: colorScheme.primary,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  _selectedTool.label,
                                  style: TextStyle(
                                    color: colorScheme.primary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Icon(Icons.arrow_drop_down, size: 17),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            _selectedModel ?? '未选择模型',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const Spacer(),
                        IconButton.filled(
                          key: const ValueKey('workbench-submit'),
                          tooltip: '发送',
                          onPressed:
                              _sending ||
                                  _creatingDocument ||
                                  _selectedModel == null
                              ? null
                              : _submit,
                          icon: _sending || _creatingDocument
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.arrow_upward, size: 20),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentJobStrip extends StatelessWidget {
  const _DocumentJobStrip({
    required this.jobs,
    required this.onOpen,
    required this.onCancel,
  });

  final List<DocumentJob> jobs;
  final ValueChanged<DocumentJob> onOpen;
  final ValueChanged<DocumentJob> onCancel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 112,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        itemCount: jobs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final job = jobs[index];
          return SizedBox(
            key: ValueKey('document-job-${job.id}'),
            width: 290,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                child: Row(
                  children: [
                    Icon(
                      job.kind == 'pptx'
                          ? Icons.slideshow_outlined
                          : Icons.description_outlined,
                      color: job.completed
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            job.title ?? '${job.kindLabel} 生成任务',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            job.errorMessage?.isNotEmpty == true
                                ? job.errorMessage!
                                : job.statusLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: job.status == 'failed'
                                  ? colorScheme.error
                                  : colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (job.active) ...[
                            const SizedBox(height: 7),
                            LinearProgressIndicator(
                              value: job.status == 'queued'
                                  ? null
                                  : job.progress / 100,
                              minHeight: 3,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (job.completed)
                      IconButton(
                        tooltip: '下载并打开',
                        onPressed: () => onOpen(job),
                        icon: const Icon(Icons.download_outlined, size: 20),
                      )
                    else if (job.active)
                      IconButton(
                        tooltip: '取消任务',
                        onPressed: () => onCancel(job),
                        icon: const Icon(Icons.close, size: 19),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ConversationMessageItem extends StatelessWidget {
  const _ConversationMessageItem({
    required this.message,
    required this.showSegment,
  });

  final _ChatMessage message;
  final bool showSegment;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (showSegment)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    '新主题',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const Expanded(child: Divider()),
              ],
            ),
          ),
        _MessageBubble(message: message),
      ],
    );
  }
}

class _ConversationLocator extends StatelessWidget {
  const _ConversationLocator({
    required this.messageIndices,
    required this.messages,
    required this.activeMessageIndex,
    required this.onSelected,
  });

  final List<int> messageIndices;
  final List<_ChatMessage> messages;
  final int? activeMessageIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight > 16
            ? constraints.maxHeight - 16
            : constraints.maxHeight;
        final wantedHeight = messageIndices.length * 18.0;
        final locatorHeight = wantedHeight < availableHeight
            ? wantedHeight
            : availableHeight;
        return Align(
          alignment: Alignment.center,
          child: SizedBox(
            height: locatorHeight,
            child: Column(
              children: [
                for (var order = 0; order < messageIndices.length; order++)
                  Expanded(
                    child: _TurnMarker(
                      key: ValueKey('conversation-turn-marker-${order + 1}'),
                      order: order,
                      message: messages[messageIndices[order]],
                      startsSegment:
                          order == 0 ||
                          messages[messageIndices[order - 1]].segmentIndex !=
                              messages[messageIndices[order]].segmentIndex,
                      active: activeMessageIndex == messageIndices[order],
                      onTap: () => onSelected(messageIndices[order]),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TurnMarker extends StatelessWidget {
  const _TurnMarker({
    super.key,
    required this.order,
    required this.message,
    required this.startsSegment,
    required this.active,
    required this.onTap,
  });

  final int order;
  final _ChatMessage message;
  final bool startsSegment;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final shortPrompt = message.content.replaceAll(RegExp(r'\s+'), ' ').trim();
    final prompt = shortPrompt.length <= 12
        ? shortPrompt
        : '${shortPrompt.substring(0, 12)}…';
    final tooltip =
        '第 ${order + 1} 轮 · 主题 ${message.segmentIndex + 1} · $prompt';
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 350),
      child: Semantics(
        button: true,
        label: tooltip,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: active ? 12 : (startsSegment ? 10 : 6),
              height: active ? 3 : 2,
              decoration: BoxDecoration(
                color: active
                    ? colorScheme.primary
                    : startsSegment
                    ? colorScheme.onSurfaceVariant
                    : colorScheme.outline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final user = message.role == 'user';
    final colorScheme = Theme.of(context).colorScheme;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 760),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: user
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          border: user ? null : Border.all(color: colorScheme.outlineVariant),
        ),
        child: message.content.isEmpty
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : SelectableText(message.content),
      ),
    );
  }
}

class _CompressedContextState extends StatelessWidget {
  const _CompressedContextState({required this.summary});

  final String summary;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.compress, size: 32, color: colorScheme.primary),
              const SizedBox(height: 10),
              Text('上下文已压缩', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                summary,
                maxLines: 8,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkbenchEmptyState extends StatelessWidget {
  const _WorkbenchEmptyState({required this.onSuggestion});

  final ValueChanged<String> onSuggestion;

  @override
  Widget build(BuildContext context) {
    const suggestions = ['帮我分析这个需求的技术方案', '整理一份项目开发计划', '检查接口并发与内存风险'];
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome,
              size: 38,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text('今天想解决什么问题？', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: suggestions
                  .map(
                    (suggestion) => ActionChip(
                      label: Text(suggestion),
                      onPressed: () => onSuggestion(suggestion),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}
