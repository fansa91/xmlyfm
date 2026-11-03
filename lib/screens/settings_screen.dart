import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../core/responsive.dart';
import '../models/models.dart';
import '../services/download_service.dart';
import '../services/settings_service.dart';
import '../widgets/detail_scaffold.dart';
import 'download_directory_dialog.dart';
import 'download_format_dialog.dart';
import 'theme_settings_screen.dart';

/// 「下载格式」选项的展示名
String _downloadFormatName(String value) =>
    value == SettingsService.downloadFormatQuality ? '音质优先' : 'MP3 优先';

/// 「下载格式」选项的说明（设置行副标题与菜单项共用）
String _downloadFormatDesc(String value) =>
    value == SettingsService.downloadFormatQuality
    ? '音质更好，但 M4A 文件无法写入标签。'
          '播放音质设为无损时将下载无损原文件（体积明显更大、不写标签）'
    : '可写入文件标签';

/// 设置页：默认音质、baseInfo v4 切换、主题入口、关于。
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final downloads = context.watch<DownloadService>();
    return DetailScaffold(
      child: Scaffold(
        appBar: AppBar(title: const Text('设置')),
        body: ConstrainedCenter(
          child: ListView(
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
              leading: const Icon(Icons.audio_file_outlined),
              title: const Text('下载格式'),
              subtitle: Text(_downloadFormatDesc(settings.downloadFormat)),
              trailing: MenuAnchor(
                builder: (context, controller, _) => TextButton(
                  onPressed: () => controller.isOpen
                      ? controller.close()
                      : controller.open(),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_downloadFormatName(settings.downloadFormat)),
                      const Icon(Icons.arrow_drop_down, size: 20),
                    ],
                  ),
                ),
                menuChildren: [
                  for (final format in const [
                    SettingsService.downloadFormatMp3,
                    SettingsService.downloadFormatQuality,
                  ])
                    MenuItemButton(
                      leadingIcon: Icon(
                        format == settings.downloadFormat ? Icons.check : null,
                        size: 18,
                      ),
                      onPressed: () => settings.setDownloadFormat(format),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_downloadFormatName(format)),
                          Text(
                            _downloadFormatDesc(format),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
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
            // iOS 固定使用应用沙盒目录，不开放自定义下载路径
            if (settings.showDownloadDirectorySetting)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: const Text('默认下载路径'),
                subtitle: Text(
                  settings.downloadDirectory.isNotEmpty
                      ? settings.downloadDirectory
                      : '默认${downloads.defaultDirPath == null ? '' : '：${downloads.defaultDirPath}'}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final result = await showDialog<String>(
                    context: context,
                    builder: (_) => DownloadDirectoryDialog(
                      current: settings.downloadDirectory,
                      defaultPath: downloads.defaultDirPath ?? '',
                    ),
                  );
                  if (result != null) {
                    await settings.setDownloadDirectory(result);
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
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('xmlyfm'),
              subtitle: FutureBuilder<PackageInfo>(
                future: PackageInfo.fromPlatform(),
                builder: (context, snapshot) {
                  final info = snapshot.data;
                  // 版本号不在代码里硬编码：CI 构建时由 git tag 解析出
                  // --build-name 注入（见 .github/workflows/release.yml），
                  // 运行时经 package_info_plus 读回；本地开发构建读到的是
                  // pubspec 的 version。读取中/失败时不显示假版本号。
                  final versionLine =
                      (info != null && info.version.isNotEmpty)
                          ? '版本 ${info.version}'
                              '${info.buildNumber.isNotEmpty ? '（构建 ${info.buildNumber}）' : ''}\n'
                          : '';
                  return Text(
                    '$versionLine喜马拉雅访客态只读客户端：不登录、不保存账号信息。\n'
                    '付费专辑的收费集仅支持试听，完整播放需官方客户端。',
                  );
                },
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }
}
