// 我的页面：账号状态、API Key和退出登录。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ai/station_key_sync_service.dart';
import '../ai/station_credential_service.dart';
import '../api/api_client.dart';
import '../auth/auth_service.dart';
import '../config.dart';
import '../preview/preview_data.dart';
import '../preview/preview_session.dart';
import 'login_page.dart';
import 'api_access_page.dart';
import 'model_center_page.dart';
import 'quota_records_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Map<String, dynamic>? _me;
  bool _loggingOut = false;
  bool _savingKey = false;
  bool _syncingKey = false;
  bool _editingKey = false;
  bool _showKey = false;
  String? _maskedKey;
  String? _keyMessage;
  final _apiKeyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    _loadKeyState();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (AppConfig.previewMode) {
      setState(() => _me = PreviewData.profile());
      return;
    }
    try {
      final me = await ApiClient.instance.requestLegacy('GET', '/api/auth/me');
      if (mounted) setState(() => _me = me);
    } catch (_) {
      // 静默：卡片回退展示 AuthService.currentUser
    }
  }

  Future<void> _loadKeyState() async {
    if (AppConfig.previewMode) {
      setState(() => _maskedKey = 'sk-p••••demo');
      return;
    }
    final masked = await StationCredentialService.instance.masked();
    if (mounted) setState(() => _maskedKey = masked);
  }

  Future<void> _pullStationKey() async {
    setState(() {
      _syncingKey = true;
      _keyMessage = null;
    });
    if (AppConfig.previewMode) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      setState(() {
        _maskedKey = 'sk-p••••demo';
        _keyMessage = '已从本站同步 Key';
        _syncingKey = false;
      });
      return;
    }
    try {
      final result = await StationKeySyncService.instance.pull();
      if (!mounted) return;
      setState(() {
        _maskedKey = result.masked;
        _keyMessage = result.configured
            ? '本站 Key 已同步到本机安全存储'
            : '本站尚无已绑定 Key，请先绑定';
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _keyMessage = error.message);
    } finally {
      if (mounted) setState(() => _syncingKey = false);
    }
  }

  Future<void> _copyStationKey() async {
    final key = AppConfig.previewMode
        ? 'sk-preview-demo-key-2026'
        : await StationCredentialService.instance.read();
    if (!mounted) return;
    if (key == null || key.isEmpty) {
      setState(() => _keyMessage = '当前没有可复制的 Key');
      return;
    }
    await Clipboard.setData(ClipboardData(text: key));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Key 已复制')));
    }
  }

  Future<void> _saveApiKey() async {
    final value = _apiKeyController.text.trim();
    if (value.isEmpty) {
      setState(() => _keyMessage = '请输入网站生成的API Key');
      return;
    }
    setState(() {
      _savingKey = true;
      _keyMessage = null;
    });
    if (AppConfig.previewMode) {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!mounted) return;
      _apiKeyController.clear();
      setState(() {
        _maskedKey = 'sk-p••••demo';
        _keyMessage = '预览模式不会保存真实 Key';
        _savingKey = false;
      });
      return;
    }
    try {
      final result = await StationKeySyncService.instance.save(value);
      _apiKeyController.clear();
      if (mounted) {
        setState(() {
          _maskedKey = result.masked;
          _keyMessage = '已绑定并同步，可在工作台和生图页使用';
          _editingKey = false;
        });
      }
    } on FormatException catch (e) {
      if (mounted) setState(() => _keyMessage = e.message.toString());
    } on StateError catch (e) {
      if (mounted) setState(() => _keyMessage = e.message);
    } finally {
      if (mounted) setState(() => _savingKey = false);
    }
  }

  Future<void> _clearApiKey() async {
    if (AppConfig.previewMode) {
      setState(() {
        _maskedKey = null;
        _apiKeyController.clear();
        _keyMessage = '已清除预览 Key';
      });
      return;
    }
    await StationKeySyncService.instance.deleteEverywhere();
    if (mounted) {
      setState(() {
        _maskedKey = null;
        _apiKeyController.clear();
        _keyMessage = 'Key 已从云端与本机删除';
      });
    }
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: Text(AppConfig.previewMode ? '确定要退出本机检查账号吗？' : '确定要退出当前账号吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    if (AppConfig.previewMode) {
      PreviewSession.signOut();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
      return;
    }

    setState(() => _loggingOut = true);
    await AuthService.instance.logout();
    if (!mounted) return;
    // 路由替换并清空栈：返回键不能回到已登录页面（PRD §4）
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final username =
        (_me?['linuxdo_username'] as String?) ??
        AuthService.instance.currentUser?.linuxdoUsername ??
        '';
    // 关联状态以中转站字段为准（Linux.do 身份 ≠ 中转站关联）；
    // me 接口失败（_me == null）时状态未知，回退 currentUser，不能默认已关联
    final stationUserId =
        _me?['station_user_id'] ??
        AuthService.instance.currentUser?.stationUserId;
    final bool? linked = (_me == null && stationUserId == null)
        ? null // 未知：me 请求失败且本地无缓存
        : stationUserId != null;
    final userId = _me?['id']?.toString();

    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: RefreshIndicator(
        onRefresh: () async {
          await _load();
          await _loadKeyState();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    const CircleAvatar(
                      radius: 28,
                      child: Icon(Icons.person, size: 32),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            username.isEmpty ? '未知用户' : username,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            AppConfig.previewMode
                                ? '本机检查账号 · 无需 L 站授权'
                                : switch (linked) {
                                    true => 'Linux.do 账号 · 中转站已关联',
                                    false => 'Linux.do 账号 · 未关联中转站',
                                    null => 'Linux.do 账号 · 关联状态获取失败，下拉刷新',
                                  },
                            style: TextStyle(
                              fontSize: 13,
                              color: linked == true
                                  ? Colors.grey
                                  : Colors.orange.shade700,
                            ),
                          ),
                          if (userId != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              '账号 ID: $userId',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                leading: const Icon(Icons.receipt_long_outlined),
                title: const Text('额度收支明细'),
                subtitle: const Text('查看广告收入、AI与游戏支出'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const QuotaRecordsPage()),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                leading: const Icon(Icons.api_outlined),
                title: const Text('本站 API 接入'),
                subtitle: const Text('公网地址与 cURL、Python、Node.js 示例'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ApiAccessPage()),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                leading: const Icon(Icons.hub_outlined),
                title: const Text('模型中心'),
                subtitle: const Text('DeepSeek、GPT、Claude 与生图模型'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ModelCenterPage()),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.key_outlined),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '本站 Key',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        if (_maskedKey != null)
                          Text(
                            _maskedKey!,
                            style: const TextStyle(color: Colors.grey),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: _syncingKey ? null : _pullStationKey,
                          icon: _syncingKey
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.cloud_download_outlined),
                          label: const Text('获取本站Key'),
                        ),
                        IconButton.outlined(
                          tooltip: '复制 Key',
                          onPressed: _maskedKey == null
                              ? null
                              : _copyStationKey,
                          icon: const Icon(Icons.copy_outlined),
                        ),
                        IconButton.outlined(
                          tooltip: '绑定或更新 Key',
                          onPressed: () {
                            setState(() => _editingKey = !_editingKey);
                          },
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton.outlined(
                          tooltip: '删除 Key',
                          onPressed: _maskedKey == null ? null : _clearApiKey,
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                    if (_editingKey) ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: _apiKeyController,
                        obscureText: !_showKey,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          labelText: _maskedKey == null
                              ? '输入本站 Key'
                              : '输入新 Key 以替换',
                          prefixIcon: const Icon(Icons.vpn_key_outlined),
                          suffixIcon: IconButton(
                            tooltip: _showKey ? '隐藏' : '显示',
                            onPressed: () {
                              setState(() => _showKey = !_showKey);
                            },
                            icon: Icon(
                              _showKey
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: _savingKey ? null : _saveApiKey,
                        icon: _savingKey
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_outlined),
                        label: const Text('绑定并同步'),
                      ),
                    ],
                    if (_keyMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(_keyMessage!, style: const TextStyle(fontSize: 13)),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: Icon(Icons.logout, color: Colors.red.shade400),
                title: Text(
                  '退出登录',
                  style: TextStyle(color: Colors.red.shade400),
                ),
                trailing: _loggingOut
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
                onTap: _loggingOut ? null : _confirmLogout,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
