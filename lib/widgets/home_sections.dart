import 'package:flutter/material.dart';

import '../core/utils.dart';
import '../models/models.dart';
import 'cover_image.dart';

/// 分类名 → 金刚区图标：按关键词映射 M3 内置图标，无命中的用通用
/// 分类图标兜底（不引用任何外部图标资源）。
IconData iconForCategoryName(String name) {
  if (name.contains('小说') || name.contains('图书')) {
    return Icons.auto_stories;
  }
  if (name.contains('儿童') || name.contains('少儿') || name.contains('宝宝')) {
    return Icons.child_care;
  }
  if (name.contains('相声')) return Icons.theater_comedy;
  if (name.contains('评书')) return Icons.record_voice_over;
  if (name.contains('历史')) return Icons.history_edu;
  if (name.contains('音乐')) return Icons.music_note;
  if (name.contains('播客')) return Icons.podcasts;
  if (name.contains('电台') || name.contains('广播')) return Icons.radio;
  if (name.contains('资讯') || name.contains('新闻')) return Icons.newspaper;
  if (name.contains('财经') || name.contains('商业')) {
    return Icons.trending_up;
  }
  if (name.contains('健康')) return Icons.health_and_safety;
  if (name.contains('外语') || name.contains('英语')) return Icons.language;
  if (name.contains('情感')) return Icons.favorite;
  if (name.contains('悬疑') || name.contains('推理')) return Icons.fingerprint;
  if (name.contains('娱乐')) return Icons.celebration;
  if (name.contains('国学') || name.contains('人文')) return Icons.menu_book;
  if (name.contains('成长') || name.contains('大师课')) return Icons.school;
  if (name.contains('汽车')) return Icons.directions_car;
  if (name.contains('影视') || name.contains('广播剧')) {
    return Icons.movie;
  }
  if (name.contains('生活')) return Icons.local_florist;
  return Icons.category;
}

/// 首页「分类金刚区」：圆形图标宫格。[categories] 之外固定带一个
/// 「更多」格（点击进分类页）。列数由调用方按窗口档位给定
/// （紧凑/中等 4 列，宽屏 8 列一整排）。
class CategoryGrid extends StatelessWidget {
  final List<HomeTab> categories;
  final int crossAxisCount;
  final void Function(HomeTab tab) onCategoryTap;
  final VoidCallback onMoreTap;

  const CategoryGrid({
    super.key,
    required this.categories,
    required this.crossAxisCount,
    required this.onCategoryTap,
    required this.onMoreTap,
  });

  @override
  Widget build(BuildContext context) {
    final cells = categories.length + 1; // + 「更多」
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisExtent: 92,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: cells,
      itemBuilder: (context, i) {
        if (i >= categories.length) {
          return _GridCell(
            icon: Icons.apps,
            label: '更多',
            onTap: onMoreTap,
          );
        }
        final tab = categories[i];
        return _GridCell(
          icon: iconForCategoryName(tab.title),
          label: tab.title,
          onTap: () => onCategoryTap(tab),
        );
      },
    );
  }
}

class _GridCell extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _GridCell({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 25,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Icon(
              icon,
              size: 25,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium,
          ),
        ],
      ),
    );
  }
}

/// 首页「排行榜」预览卡：全站热播榜前三（名次徽标 + 封面/标题/播放量），
/// 右上「更多」进全站排行榜页。数据为空时由调用方整卡不渲染。
class RankPreviewCard extends StatelessWidget {
  final List<RankAlbum> albums;
  final VoidCallback onMore;
  final void Function(RankAlbum album) onAlbumTap;

  const RankPreviewCard({
    super.key,
    required this.albums,
    required this.onMore,
    required this.onAlbumTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.emoji_events,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  '排行榜',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.onSurfaceVariant,
                  ),
                  onPressed: onMore,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('更多'),
                      Icon(Icons.chevron_right, size: 16),
                    ],
                  ),
                ),
              ],
            ),
            for (var i = 0; i < albums.length; i++)
              _RankPreviewRow(
                rank: i + 1,
                album: albums[i],
                onTap: () => onAlbumTap(albums[i]),
              ),
          ],
        ),
      ),
    );
  }
}

class _RankPreviewRow extends StatelessWidget {
  final int rank;
  final RankAlbum album;
  final VoidCallback onTap;

  const _RankPreviewRow({
    required this.rank,
    required this.album,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (bg, fg) = switch (rank) {
      1 => (scheme.primary, scheme.onPrimary),
      2 => (scheme.secondary, scheme.onSecondary),
      3 => (scheme.tertiary, scheme.onTertiary),
      _ => (scheme.surfaceContainerHigh, scheme.onSurfaceVariant),
    };
    final sub = album.playsCounts > 0
        ? '${formatPlayCount(album.playsCounts)}播放'
        : album.nickname;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            CircleAvatar(
              radius: 13,
              backgroundColor: bg,
              child: Text(
                '$rank',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: fg, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 10),
            CoverImage(url: album.cover, size: 48, radius: 8),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    album.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (sub.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
