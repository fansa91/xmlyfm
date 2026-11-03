import 'package:flutter/material.dart';

import '../services/settings_service.dart';
import '../widgets/detail_scaffold.dart';

/// 主题设置页：深浅模式、动态取色开关、纯黑开关、种子色预设。
/// 作为详情页打开时包一层 DetailScaffold 显示迷你播放器。
class ThemeSettingsScreen extends StatelessWidget {
  final SettingsService settings;
  const ThemeSettingsScreen({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    return DetailScaffold(
      child: Scaffold(
        appBar: AppBar(title: const Text('主题设置')),
        body: ListenableBuilder(
          listenable: settings,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              _SectionTitle('主题模式'),
              RadioGroup<ThemeMode>(
                groupValue: settings.themeMode,
                onChanged: (v) {
                  if (v != null) settings.setThemeMode(v);
                },
                child: const Column(
                  children: [
                    RadioListTile<ThemeMode>(
                      value: ThemeMode.system,
                      title: Text('跟随系统'),
                    ),
                    RadioListTile<ThemeMode>(
                      value: ThemeMode.light,
                      title: Text('浅色'),
                    ),
                    RadioListTile<ThemeMode>(
                      value: ThemeMode.dark,
                      title: Text('深色'),
                    ),
                  ],
                ),
              ),
              const Divider(),
              SwitchListTile(
                title: const Text('动态取色'),
                subtitle: const Text('使用系统壁纸配色（Android 12+）'),
                value: settings.dynamicColor,
                onChanged: (v) => settings.setDynamicColor(v),
              ),
              const Divider(),
              SwitchListTile(
                title: const Text('纯黑模式'),
                subtitle: const Text('深色模式下背景使用纯黑'),
                value: settings.pureBlack,
                onChanged: (v) => settings.setPureBlack(v),
              ),
              const Divider(),
              _SectionTitle('主题颜色'),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final preset in SettingsService.themePresets)
                      _ColorDot(
                        color: Color(preset.value),
                        label: preset.name,
                        selected: !settings.dynamicColor &&
                            settings.themeSeed == preset.value,
                        onTap: () => settings.setThemeSeed(preset.value),
                      ),
                    for (final value in settings.customColors)
                      _ColorDot(
                        color: Color(value),
                        label: '自定义',
                        selected: !settings.dynamicColor &&
                            settings.themeSeed == value,
                        onTap: () => settings.setThemeSeed(value),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Text(
                  '当前主题：${settings.themeName}'
                  '${settings.dynamicColor ? '（动态取色开启时以系统色为准）' : ''}',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ColorDot({
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: selected
                ? Border.all(
                    color: Theme.of(context).colorScheme.onSurface,
                    width: 2.5)
                : null,
          ),
          child: selected
              ? const Icon(Icons.check, color: Colors.white, size: 20)
              : null,
        ),
      ),
    );
  }
}
