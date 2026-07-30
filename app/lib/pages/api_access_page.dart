import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../config.dart';

class ApiAccessPage extends StatefulWidget {
  const ApiAccessPage({super.key});

  @override
  State<ApiAccessPage> createState() => _ApiAccessPageState();
}

class _ApiAccessPageState extends State<ApiAccessPage> {
  bool _loading = true;
  String? _baseUrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (AppConfig.previewMode) {
      setState(() {
        _baseUrl = 'https://station.example.com/v1';
        _loading = false;
      });
      return;
    }
    try {
      final value = await ApiClient.instance.requestLegacy(
        'GET',
        '/api/platform/config',
        auth: false,
      );
      if (!mounted) return;
      setState(() {
        _baseUrl = value['openai_compatible_base_url']?.toString();
        if (_baseUrl == null || _baseUrl!.isEmpty) {
          _error = '管理员尚未配置本站 API 公网地址';
        }
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '本站 API 地址加载失败');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _copy(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label 已复制')));
  }

  String get _curl =>
      '''curl ${_baseUrl ?? 'https://station.example.com/v1'}/chat/completions \\
  -H "Authorization: Bearer YOUR_API_KEY" \\
  -H "Content-Type: application/json" \\
  -d '{"model":"YOUR_MODEL_ID","messages":[{"role":"user","content":"你好"}]}' ''';

  String get _python =>
      '''from openai import OpenAI

client = OpenAI(
    api_key="YOUR_API_KEY",
    base_url="${_baseUrl ?? 'https://station.example.com/v1'}",
)

response = client.chat.completions.create(
    model="YOUR_MODEL_ID",
    messages=[{"role": "user", "content": "你好"}],
)
print(response.choices[0].message.content)''';

  String get _node =>
      '''import OpenAI from "openai";

const client = new OpenAI({
  apiKey: process.env.STATION_API_KEY,
  baseURL: "${_baseUrl ?? 'https://station.example.com/v1'}",
});

const response = await client.chat.completions.create({
  model: "YOUR_MODEL_ID",
  messages: [{ role: "user", content: "你好" }],
});
console.log(response.choices[0].message.content);''';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('本站 API 接入'),
        actions: [
          IconButton(
            tooltip: '刷新地址',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_error!),
              ),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'OpenAI 兼容地址',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  SelectableText(_baseUrl ?? '尚未配置'),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _baseUrl == null
                        ? null
                        : () => _copy(_baseUrl!, 'API 地址'),
                    icon: const Icon(Icons.copy_outlined),
                    label: const Text('复制地址'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          _CodeCard(
            title: 'cURL',
            code: _curl,
            onCopy: () => _copy(_curl, 'cURL 示例'),
          ),
          const SizedBox(height: 8),
          _CodeCard(
            title: 'Python · OpenAI SDK',
            code: _python,
            onCopy: () => _copy(_python, 'Python 示例'),
          ),
          const SizedBox(height: 8),
          _CodeCard(
            title: 'Node.js · OpenAI SDK',
            code: _node,
            onCopy: () => _copy(_node, 'Node.js 示例'),
          ),
          const SizedBox(height: 12),
          const Text(
            '模型名称必须使用“模型中心”里实际返回的 ID。Claude、GPT、DeepSeek 等文本模型均通过 OpenAI 兼容格式调用；生图模型以后台白名单为准。',
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({
    required this.title,
    required this.code,
    required this.onCopy,
  });

  final String title;
  final String code;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: '复制示例',
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy_outlined),
                ),
              ],
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                code,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
