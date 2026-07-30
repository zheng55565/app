import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../ai/ai_service.dart';
import '../ai/image_history_store.dart';
import '../api/api_client.dart';
import '../config.dart';
import '../preview/preview_data.dart';

class ImageStudioPage extends StatefulWidget {
  const ImageStudioPage({super.key, required this.onOpenProfile});

  final VoidCallback onOpenProfile;

  @override
  State<ImageStudioPage> createState() => _ImageStudioPageState();
}

class _ImageStudioPageState extends State<ImageStudioPage> {
  final _promptController = TextEditingController();
  final _parameterController = TextEditingController();
  List<String> _models = const [];
  List<ImageHistoryRecord> _history = const [];
  String? _selectedModel;
  String _ratio = '1:1';
  String _view = 'create';
  String? _lastRenderedPrompt;
  Uint8List? _imageBytes;
  String? _imageUrl;
  String? _error;
  bool _loadingModels = true;
  bool _loadingHistory = true;
  bool _generating = false;
  bool _previewGenerated = false;

  @override
  void initState() {
    super.initState();
    _loadModels();
    _loadHistory();
  }

  @override
  void dispose() {
    _promptController.dispose();
    _parameterController.dispose();
    super.dispose();
  }

  Future<void> _loadModels() async {
    setState(() {
      _loadingModels = true;
      _error = null;
    });
    if (AppConfig.previewMode) {
      setState(() {
        _models = PreviewData.imageModels;
        _selectedModel = PreviewData.imageModels.first;
        _loadingModels = false;
      });
      return;
    }
    try {
      final models = await AiService.instance.loadModels(image: true);
      if (!mounted) return;
      setState(() {
        _models = models;
        if (models.isEmpty) _error = '后台尚未配置生图模型';
        _selectedModel = models.contains(_selectedModel)
            ? _selectedModel
            : (models.isEmpty ? null : models.first);
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '生图模型加载失败');
    } finally {
      if (mounted) setState(() => _loadingModels = false);
    }
  }

  Future<void> _loadHistory() async {
    setState(() => _loadingHistory = true);
    final records = AppConfig.previewMode
        ? PreviewData.imageHistory()
        : await ImageHistoryStore.instance.load();
    if (!mounted) return;
    setState(() {
      _history = records;
      _loadingHistory = false;
    });
  }

  String _sizeForRatio(String ratio) {
    return switch (ratio) {
      '16:9' => '1536x1024',
      '3:4' => '1024x1536',
      _ => '1024x1024',
    };
  }

  String _renderPrompt(String prompt) {
    final extra = _parameterController.text.trim();
    return '$prompt --ar $_ratio --style raw${extra.isEmpty ? '' : ' $extra'}';
  }

  Future<void> _generate() async {
    final model = _selectedModel;
    final prompt = _promptController.text.trim();
    if (model == null || prompt.isEmpty || _generating) return;
    final renderedPrompt = _renderPrompt(prompt);
    setState(() {
      _generating = true;
      _error = null;
      _imageBytes = null;
      _imageUrl = null;
      _previewGenerated = false;
      _lastRenderedPrompt = renderedPrompt;
    });
    if (AppConfig.previewMode) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;
      final record = ImageHistoryRecord(
        id: 'preview-${DateTime.now().microsecondsSinceEpoch}',
        prompt: prompt,
        renderedPrompt: renderedPrompt,
        model: model,
        ratio: _ratio,
        createdAt: DateTime.now(),
      );
      setState(() {
        _previewGenerated = true;
        _history = [record, ..._history];
        _generating = false;
      });
      return;
    }
    try {
      final result = await AiService.instance.generateImage(
        model: model,
        prompt: renderedPrompt,
        size: _sizeForRatio(_ratio),
      );
      final data = result['data'] as List<dynamic>?;
      final first = data?.isNotEmpty == true
          ? data!.first as Map<String, dynamic>
          : null;
      if (first == null) throw const FormatException('模型未返回图片');
      final b64 = first['b64_json']?.toString();
      final url = first['url']?.toString();
      final bytes = b64 == null || b64.isEmpty ? null : base64Decode(b64);
      if (bytes == null && (url == null || url.isEmpty)) {
        throw const FormatException('模型未返回可显示的图片');
      }
      final record = await ImageHistoryStore.instance.save(
        prompt: prompt,
        renderedPrompt: renderedPrompt,
        model: model,
        ratio: _ratio,
        imageBytes: bytes,
        imageUrl: url,
      );
      if (!mounted) return;
      setState(() {
        _imageBytes = bytes;
        _imageUrl = url;
        _history = [record, ..._history];
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '生成失败，请检查模型和参数');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  void _reuse(ImageHistoryRecord record) {
    setState(() {
      _promptController.text = record.prompt;
      _ratio = record.ratio;
      _selectedModel = _models.contains(record.model)
          ? record.model
          : _selectedModel;
      _view = 'create';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 52,
        title: const Text('生图工作室'),
        actions: [
          IconButton(
            tooltip: '刷新模型',
            onPressed: _loadingModels ? null : _loadModels,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loadingModels || _loadingHistory)
            const LinearProgressIndicator(minHeight: 2),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: _PillSelector(
              value: _view,
              options: const [
                _PillOption(
                  value: 'create',
                  icon: Icons.auto_awesome_outlined,
                  label: '创作',
                ),
                _PillOption(value: 'history', icon: Icons.history, label: '历史'),
              ],
              onChanged: (value) => setState(() => _view = value),
            ),
          ),
          Expanded(
            child: _view == 'create'
                ? _buildCreateView(context)
                : _buildHistoryView(context),
          ),
        ],
      ),
    );
  }

  Widget _buildCreateView(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 18),
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey(_selectedModel),
          initialValue: _selectedModel,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: '生图模型',
            prefixIcon: Icon(Icons.memory_outlined),
            isDense: true,
          ),
          items: _models
              .map(
                (model) => DropdownMenuItem(value: model, child: Text(model)),
              )
              .toList(),
          onChanged: _generating
              ? null
              : (value) => setState(() => _selectedModel = value),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _promptController,
          minLines: 3,
          maxLines: 7,
          decoration: const InputDecoration(
            labelText: '提示词',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 8),
        _PillSelector(
          value: _ratio,
          enabled: !_generating,
          options: const [
            _PillOption(value: '1:1', icon: Icons.crop_square, label: '1:1'),
            _PillOption(
              value: '16:9',
              icon: Icons.crop_landscape,
              label: '16:9',
            ),
            _PillOption(value: '3:4', icon: Icons.crop_portrait, label: '3:4'),
          ],
          onChanged: (value) => setState(() => _ratio = value),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _parameterController,
          decoration: const InputDecoration(
            labelText: '补充参数',
            hintText: '--seed 42 --stylize 100',
            prefixIcon: Icon(Icons.tune),
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        _GlowGenerateButton(
          loading: _generating,
          onPressed: _generating || _selectedModel == null ? null : _generate,
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFD6336C), Color(0xFFB02A59)],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                const Icon(Icons.error_outline, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(_error!)),
                TextButton(
                  onPressed: widget.onOpenProfile,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF00C0F9),
                  ),
                  child: const Text('设置'),
                ),
              ],
            ),
          ),
        ],
        if (_previewGenerated || _imageBytes != null || _imageUrl != null) ...[
          const SizedBox(height: 12),
          if (_previewGenerated)
            _PreviewImage(prompt: _promptController.text.trim(), ratio: _ratio)
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: _imageBytes != null
                  ? Image.memory(
                      _imageBytes!,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                    )
                  : Image.network(
                      _imageUrl!,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('图片地址无法加载'),
                      ),
                    ),
            ),
          if (_lastRenderedPrompt != null) ...[
            const SizedBox(height: 8),
            SelectableText(
              _lastRenderedPrompt!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildHistoryView(BuildContext context) {
    if (_history.isEmpty) {
      return const Center(child: Text('暂无生成记录'));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 840
            ? 3
            : constraints.maxWidth >= 540
            ? 2
            : 1;
        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: columns == 1 ? 1.55 : 0.82,
          ),
          itemCount: _history.length,
          itemBuilder: (context, index) {
            return _HistoryCard(
              record: _history[index],
              onReuse: () => _reuse(_history[index]),
            );
          },
        );
      },
    );
  }
}

class _PillOption {
  const _PillOption({
    required this.value,
    required this.icon,
    required this.label,
  });

  final String value;
  final IconData icon;
  final String label;
}

class _PillSelector extends StatelessWidget {
  const _PillSelector({
    required this.value,
    required this.options,
    required this.onChanged,
    this.enabled = true,
  });

  final String value;
  final List<_PillOption> options;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x73163E70),
        border: Border.all(color: const Color(0x2E64C8FF)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          children: options
              .map(
                (option) => Expanded(
                  child: _PillChoice(
                    option: option,
                    selected: value == option.value,
                    enabled: enabled,
                    onTap: () => onChanged(option.value),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _PillChoice extends StatefulWidget {
  const _PillChoice({
    required this.option,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final _PillOption option;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_PillChoice> createState() => _PillChoiceState();
}

class _PillChoiceState extends State<_PillChoice> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? 0.96 : 1,
      duration: const Duration(milliseconds: 120),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          gradient: widget.selected
              ? const LinearGradient(
                  colors: [Color(0xFF0099E8), Color(0xFF00C0F9)],
                )
              : null,
          borderRadius: BorderRadius.circular(20),
          boxShadow: widget.selected
              ? const [
                  BoxShadow(
                    color: Color(0x4000AAF0),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onHighlightChanged: widget.enabled
                ? (value) => setState(() => _pressed = value)
                : null,
            onTap: widget.enabled ? widget.onTap : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    widget.option.icon,
                    size: 18,
                    color: widget.enabled
                        ? widget.selected
                              ? Colors.white
                              : const Color(0xFF89A8CB)
                        : const Color(0xFF547092),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      widget.option.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: widget.enabled
                            ? widget.selected
                                  ? Colors.white
                                  : const Color(0xFF89A8CB)
                            : const Color(0xFF547092),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlowGenerateButton extends StatefulWidget {
  const _GlowGenerateButton({required this.loading, required this.onPressed});

  final bool loading;
  final VoidCallback? onPressed;

  @override
  State<_GlowGenerateButton> createState() => _GlowGenerateButtonState();
}

class _GlowGenerateButtonState extends State<_GlowGenerateButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glow;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _glow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
      lowerBound: 0,
      upperBound: 1,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return AnimatedScale(
      scale: _pressed ? 0.96 : 1,
      duration: const Duration(milliseconds: 120),
      child: AnimatedBuilder(
        animation: _glow,
        builder: (context, child) => Opacity(
          opacity: enabled ? 1 : 0.4,
          child: Container(
            height: 46,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0099E8), Color(0xFF00C0F9)],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: Color.lerp(
                          const Color(0x2400AAF0),
                          const Color(0x6600AAF0),
                          _glow.value,
                        )!,
                        blurRadius: 12 + (_glow.value * 10),
                        spreadRadius: _glow.value * 1.5,
                      ),
                    ]
                  : null,
            ),
            child: child,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onHighlightChanged: enabled
                ? (value) => setState(() => _pressed = value)
                : null,
            onTap: widget.onPressed,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.loading)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  else
                    const Icon(Icons.auto_awesome, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    widget.loading ? '生成中' : '生成图片',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.record, required this.onReuse});

  final ImageHistoryRecord record;
  final VoidCallback onReuse;

  @override
  Widget build(BuildContext context) {
    final path = record.localPath;
    final fileExists = path != null && File(path).existsSync();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onReuse,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SizedBox(
                width: double.infinity,
                child: fileExists
                    ? Image.file(File(path), fit: BoxFit.cover)
                    : record.imageUrl != null
                    ? Image.network(record.imageUrl!, fit: BoxFit.cover)
                    : DecoratedBox(
                        decoration: const BoxDecoration(
                          color: Color(0x73163E70),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.image_outlined,
                            size: 42,
                            color: Color(0xFF00C0F9),
                          ),
                        ),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.prompt,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${record.model} · ${record.ratio}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
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

class _PreviewImage extends StatelessWidget {
  const _PreviewImage({required this.prompt, required this.ratio});

  final String prompt;
  final String ratio;

  @override
  Widget build(BuildContext context) {
    final aspectRatio = switch (ratio) {
      '16:9' => 16 / 9,
      '3:4' => 3 / 4,
      _ => 1.0,
    };
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 520),
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF183A66),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.auto_awesome,
                    color: Color(0xFFBFD6FF),
                    size: 52,
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    '图片生成预览',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    prompt,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFDCE8FA)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
