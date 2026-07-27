/// 我的页面（PRD §4）：账号卡片 + 关联状态 + 退出登录（带确认）
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../auth/auth_service.dart';
import 'login_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Map<String, dynamic>? _me;
  bool _loggingOut = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final me = await ApiClient.instance.requestLegacy('GET', '/api/auth/me');
      if (mounted) setState(() => _me = me);
    } catch (_) {
      // 静默：卡片回退展示 AuthService.currentUser
    }
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定要退出当前账号吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('退出')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

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
    final username = (_me?['linuxdo_username'] as String?) ??
        AuthService.instance.currentUser?.linuxdoUsername ??
        '';
    // 关联状态以中转站字段为准（Linux.do 身份 ≠ 中转站关联）；
    // me 接口失败（_me == null）时状态未知，回退 currentUser，不能默认已关联
    final stationUserId = _me?['station_user_id'] ??
        AuthService.instance.currentUser?.stationUserId;
    final bool? linked = (_me == null && stationUserId == null)
        ? null // 未知：me 请求失败且本地无缓存
        : stationUserId != null;
    final userId = _me?['id']?.toString();

    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    const CircleAvatar(radius: 28, child: Icon(Icons.person, size: 32)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            username.isEmpty ? '未知用户' : username,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            switch (linked) {
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
                            Text('账号 ID: $userId',
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.grey)),
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
                leading: Icon(Icons.logout, color: Colors.red.shade400),
                title: Text('退出登录',
                    style: TextStyle(color: Colors.red.shade400)),
                trailing: _loggingOut
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
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
