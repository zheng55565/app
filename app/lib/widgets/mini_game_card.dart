/// 小游戏入口卡片（PRD §3.3）：打开 Unity WebGL 游戏页
import 'package:flutter/material.dart';

import '../pages/game_page.dart';

class MiniGameCard extends StatelessWidget {
  const MiniGameCard({super.key});

  @override
  Widget build(BuildContext context) {
    // 弱化样式（描边 + 灰色调），不与广告主按钮竞争（PRD §7）
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const GamePage()),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(Icons.videogame_asset_outlined,
                  size: 40, color: Colors.deepPurple.shade300),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('小游戏',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.deepPurple.shade50,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text('试玩',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.deepPurple.shade400)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('休闲小游戏合集，随点随玩',
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}
