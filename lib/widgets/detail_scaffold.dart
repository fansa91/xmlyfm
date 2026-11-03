import 'package:flutter/material.dart';

import 'mini_player.dart';

/// 详情页脚手架：内容区 + 底部悬浮迷你播放器。
/// 详情页是 push 到 AppShell 之上的新路由，不包这一层的话
/// 迷你播放器会被盖住。
class DetailScaffold extends StatelessWidget {
  final Widget child;
  const DetailScaffold({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(child: child),
          const MiniPlayer(),
        ],
      ),
    );
  }
}
