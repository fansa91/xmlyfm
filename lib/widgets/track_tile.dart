import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/utils.dart';
import '../models/models.dart';
import '../services/player_service.dart';

/// 小徽章（付费 / 试听 / 会员免费等）
class MiniBadge extends StatelessWidget {
  final String text;
  final Color? color;

  const MiniBadge(this.text, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: c, width: 0.7),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: c, height: 1.2),
      ),
    );
  }
}

/// 专辑节目列表里的一行声音。
/// 徽章规则按字段渲染：收费集显示「付费」，可试听显示「试听 XX 秒」。
class TrackTile extends StatelessWidget {
  final Track track;
  final int? indexLabel;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// 覆盖默认 leading（如多选模式的复选框）
  final Widget? leading;

  /// 覆盖默认 trailing（如下载状态按钮）
  final Widget? trailing;

  /// 选中态（多选模式高亮，走 ListTile 原生 selected 配色）
  final bool selected;

  const TrackTile({
    super.key,
    required this.track,
    this.indexLabel,
    this.onTap,
    this.onLongPress,
    this.leading,
    this.trailing,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerService>();
    final theme = Theme.of(context);
    final isCurrent = player.current?.trackId == track.trackId;
    final isPlayingThis = isCurrent && player.playing;

    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      selected: selected,
      selectedTileColor: theme.colorScheme.secondaryContainer,
      leading:
          leading ??
          SizedBox(
            width: 36,
            child: Center(
              child: isCurrent
                  ? Icon(
                      isPlayingThis ? Icons.graphic_eq : Icons.play_arrow,
                      color: theme.colorScheme.primary,
                      size: 20,
                    )
                  : Text(
                      indexLabel != null ? '$indexLabel' : '',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
            ),
          ),
      title: Text(
        track.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
          color: isCurrent ? theme.colorScheme.primary : null,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            Icon(
              Icons.play_circle_outline,
              size: 13,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 3),
            Text(
              formatPlayCount(track.playtimes),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              Icons.schedule,
              size: 13,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 3),
            Text(
              formatSeconds(track.duration),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            if (track.isChargeTrack) ...[
              const MiniBadge('付费'),
              const SizedBox(width: 6),
            ],
            if (track.isChargeTrack && track.sampleDuration > 0)
              MiniBadge(
                '试听 ${track.sampleDuration} 秒',
                color: theme.colorScheme.tertiary,
              ),
          ],
        ),
      ),
      trailing:
          trailing ??
          (isCurrent
              ? IconButton(
                  icon: Icon(isPlayingThis ? Icons.pause : Icons.play_arrow),
                  color: theme.colorScheme.primary,
                  onPressed: () => player.toggle(),
                )
              : null),
    );
  }
}
