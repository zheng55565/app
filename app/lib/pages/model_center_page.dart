import 'package:flutter/material.dart';

import '../ai/ai_service.dart';
import '../ai/station_credential_service.dart';
import '../api/api_client.dart';
import '../config.dart';
import '../preview/preview_data.dart';

class ModelCenterPage extends StatefulWidget {
  const ModelCenterPage({super.key});

  @override
  State<ModelCenterPage> createState() => _ModelCenterPageState();
}

class _ModelCenterPageState extends State<ModelCenterPage> {
  final _searchController = TextEditingController();
  List<String> _chatModels = const [];
  List<String> _imageModels = const [];
  String? _maskedKey;
  String? _error;
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final masked = AppConfig.previewMode
          ? 'sk-p••••demo'
          : await StationCredentialService.instance.masked();
      final chat = AppConfig.previewMode
          ? PreviewData.chatModels
          : await AiService.instance.loadModels();
      final image = AppConfig.previewMode
          ? PreviewData.imageModels
          : await AiService.instance.loadModels(image: true);
      if (!mounted) return;
      setState(() {
        _maskedKey = masked;
        _chatModels = chat;
        _imageModels = image;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '模型列表加载失败');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<String> _filtered(List<String> values) {
    if (_query.isEmpty) return values;
    return values
        .where((value) => value.toLowerCase().contains(_query.toLowerCase()))
        .toList();
  }

  String _provider(String model) {
    final lower = model.toLowerCase();
    if (lower.contains('claude') ||
        lower.contains('opus') ||
        lower.contains('sonnet') ||
        lower.contains('haiku')) {
      return 'Anthropic';
    }
    if (lower.contains('deepseek')) return 'DeepSeek';
    if (lower.contains('gemini')) return 'Google';
    if (lower.contains('gpt') || lower.contains('o1') || lower.contains('o3')) {
      return 'OpenAI';
    }
    if (lower.contains('flux')) return 'Black Forest Labs';
    return '兼容模型';
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 52,
          title: const Text('模型中心'),
          actions: [
            IconButton(
              tooltip: '刷新模型',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: '对话模型'),
              Tab(text: '生图模型'),
            ],
          ),
        ),
        body: Column(
          children: [
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value.trim()),
                    decoration: const InputDecoration(
                      hintText: '搜索模型',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        _maskedKey == null
                            ? Icons.link_off_outlined
                            : Icons.verified_outlined,
                        size: 17,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _maskedKey == null
                            ? '尚未绑定本站 Key'
                            : '本站 Key $_maskedKey',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_error != null)
              Container(
                width: double.infinity,
                color: Theme.of(context).colorScheme.errorContainer,
                padding: const EdgeInsets.all(10),
                child: Text(_error!),
              ),
            Expanded(
              child: TabBarView(
                children: [
                  _ModelList(
                    models: _filtered(_chatModels),
                    providerFor: _provider,
                    icon: Icons.chat_bubble_outline,
                  ),
                  _ModelList(
                    models: _filtered(_imageModels),
                    providerFor: _provider,
                    icon: Icons.image_outlined,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModelList extends StatelessWidget {
  const _ModelList({
    required this.models,
    required this.providerFor,
    required this.icon,
  });

  final List<String> models;
  final String Function(String model) providerFor;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    if (models.isEmpty) {
      return const Center(child: Text('暂无匹配模型'));
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: models.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final model = models[index];
        return ListTile(
          leading: CircleAvatar(child: Icon(icon, size: 20)),
          title: Text(model),
          subtitle: Text(providerFor(model)),
          trailing: const Icon(Icons.check_circle_outline, size: 20),
        );
      },
    );
  }
}
