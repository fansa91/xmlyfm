import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/settings_service.dart';
import '../widgets/detail_scaffold.dart';
import 'download_format_dialog.dart';
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
            ListTile(
              title: Text('播放',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.high_quality_outlined),
              title: const Text('默认音质'),
              subtitle: Text(Quality.nameOf(settings.defaultQuality)),
              trailing: MenuAnchor(
                builder: (context, controller, _) => TextButton(
                  onPressed: () => controller.isOpen
                      ? controller.close()
                      : controller.open(),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(Quality.nameOf(settings.defaultQuality)),
                      const Icon(Icons.arrow_drop_down, size: 20),
                    ],
                  ),
                ),
                menuChildren: [
                  for (final level in Quality.levels)
                    MenuItemButton(
                      leadingIcon: Icon(
                        level == settings.defaultQuality ? Icons.check : null,
                        size: 18,
                      ),
                      onPressed: () => settings.setDefaultQuality(level),
                      child: Text(Quality.nameOf(level)),
                    ),
                ],
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
            ListTile(
              title: Text('下载',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('下载文件名格式'),
              subtitle: Text(settings.downloadFileNameFormat),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final result = await showDialog<String>(
                  context: context,
                  builder: (_) => DownloadFormatDialog(
                    initial: settings.downloadFileNameFormat,
                  ),
                );
                if (result != null) {
                  settings.setDownloadFileNameFormat(result);
                }
              },
            ),
            const Divider(),
            ListTile(
              title: Text('外观',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
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
            ListTile(
              title: Text('关于',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
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
