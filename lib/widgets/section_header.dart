import 'package:flutter/material.dart';

/// 区块标题行：标题 + 右侧"更多"
class SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onMore;

  const SectionHeader({super.key, required this.title, this.onMore});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 6),
      child: Row(
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          if (onMore != null)
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.onSurfaceVariant,
              ),
              onPressed: onMore,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('更多'),
                  Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
