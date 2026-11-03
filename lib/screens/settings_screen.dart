import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/settings_service.dart';
import '../widgets/detail_scaffold.dart';
import 'theme_settings_screen.dart';

/// 设置页：默认音质、baseInfo v4 切换、主题入口、关于。
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    return DetailScaffold(
      child: Scaffold(
        appBar: AppBar(title: const Text('设置')),
        body: ListView(
          children: [
            const ListTile(
              title: Text('播放', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.high_quality_outlined),
              title: const Text('默认音质'),
              subtitle: Text(Quality.nameOf(settings.defaultQuality)),
              trailing: DropdownButton<int>(
                value: settings.defaultQuality,
                underline: const SizedBox.shrink(),
                items: Quality.levels
                    .map((level) => DropdownMenuItem(
                          value: level,
                          child: Text(Quality.nameOf(level)),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) settings.setDefaultQuality(v);
                },
              ),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.verified_user_outlined),
              title: const Text('baseInfo v4 签名接口'),
              subtitle: const Text('普通声音播放地址走 v4（带 sign）而非 v3'),
              value: settings.baseInfoV4,
              onChanged: (v) => settings.setBaseInfoV4(v),
            ),
            const Divider(),
            const ListTile(
              title: Text('外观', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('主题与配色'),
              subtitle: const Text('深浅模式、动态取色、纯黑、种子色'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ThemeSettingsScreen(settings: settings),
                ),
              ),
            ),
            const Divider(),
            const ListTile(
              title: Text('关于', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('xmlyfm'),
              subtitle: Text(
                '版本 0.1.0\n喜马拉雅访客态只读客户端：不登录、不保存账号信息。\n'
                '付费专辑的收费集仅支持试听，完整播放需官方客户端。',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
