/// 主容器：底部双标签导航（PRD §2/§5）
///
/// IndexedStack 保留各标签的滚动位置与已加载数据；
/// 切换标签不重建页面、不重复登录流程。
import 'package:flutter/material.dart';

import '../ads/ad_service.dart';
import 'home_page.dart';
import 'profile_page.dart';

class MainShellPage extends StatefulWidget {
  const MainShellPage({super.key});

  @override
  State<MainShellPage> createState() => _MainShellPageState();
}

class _MainShellPageState extends State<MainShellPage> {
  int _index = 0;

  void _onSelect(int i) {
    if (i == _index) return;
    setState(() => _index = i);
    // 插屏广告预留触发点：标签切换（服务端未开启时为空操作，无任何请求）
    AdService.instance.maybeShowInterstitial(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [HomePage(), ProfilePage()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _onSelect,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
