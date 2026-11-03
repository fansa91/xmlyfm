import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/utils.dart';
import '../models/models.dart';
import '../services/library_service.dart';
import '../services/player_service.dart';
import '../widgets/cover_image.dart';

/// 全屏播放页：封面、标题、进度（试听上限截断）、上一首/下一首、
/// 倍速、定时关闭、音质切换 chips（0/1/2/3 标准/高清/臻品/无损）、播放模式。
class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerService>();
    final library = context.watch<LibraryService>();
    final theme = Theme.of(context);
    final track = player.current;

    return Scaffold(
      appBar: AppBar(
        title: const Text('正在播放'),
        actions: [
          if (track != null)
            IconButton(
              icon: Icon(
                library.isFavoriteTrack(track.trackId)
                    ? Icons.favorite
                    : Icons.favorite_border,
                color: library.isFavoriteTrack(track.trackId)
                    ? theme.colorScheme.primary
                    : null,
              ),
              tooltip: '收藏声音',
              onPressed: () => library.toggleFavoriteTrack(track),
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.timer_outlined),
            tooltip: '定时关闭',
            onSelected: (v) {
              if (v == 'off') {
                player.setSleepTimer(null);
              } else {
                player.setSleepTimer(Duration(minutes: int.parse(v)));
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: '15', child: Text('15 分钟后关闭')),
              const PopupMenuItem(value: '30', child: Text('30 分钟后关闭')),
              const PopupMenuItem(value: '60', child: Text('60 分钟后关闭')),
              if (player.sleepAt != null)
                const PopupMenuItem(value: 'off', child: Text('取消定时')),
            ],
          ),
        ],
      ),
      body: track == null
          ? const Center(child: Text('暂无播放内容'))
          : Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  CoverImage(url: track.cover, size: 260, radius: 24),
                  const SizedBox(height: 24),
                  Text(
                    track.title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 19, fontWeight: FontWeight.bold, height: 1.3),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    track.nickname,
                    style: TextStyle(
                        fontSize: 14,
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                  if (player.sleepAt != null) ...[
                    const SizedBox(height: 8),
                    Chip(
                      avatar: const Icon(Icons.timer, size: 16),
                      label: Text(
                          '定时关闭：${player.sleepAt!.difference(DateTime.now()).inMinutes + 1} 分钟内'),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                  const Spacer(),
                  if (player.isSample) _buildSampleBanner(context, player),
                  if (player.errorMessage != null) ...[
                    Text(
                      player.errorMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: theme.colorScheme.error, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                  ],
                  _buildProgress(context, player),
                  const SizedBox(height: 4),
                  _buildControls(context, player),
                  const SizedBox(height: 8),
                  _buildExtraRow(context, player),
                  const SizedBox(height: 8),
                  _buildQualityRow(context, player),
                ],
              ),
            ),
    );
  }

  Widget _buildSampleBanner(BuildContext context, PlayerService player) {
    final theme = Theme.of(context);
    final result = player.currentResult;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        result?.notice ??
            '付费内容，仅支持试听 ${result?.sampleDuration ?? 0} 秒',
        textAlign: TextAlign.center,
        style: TextStyle(
            fontSize: 12.5, color: theme.colorScheme.onTertiaryContainer),
      ),
    );
  }

  Widget _buildProgress(BuildContext context, PlayerService player) {
    final duration = player.effectiveDuration;
    final maxMs = (duration?.inMilliseconds ?? 0).toDouble();
    final posMs = player.position.inMilliseconds
        .clamp(0, maxMs > 0 ? maxMs.toInt() : 1 << 62)
        .toDouble();
    return Column(
      children: [
        Slider(
          value: maxMs > 0 ? posMs : 0,
          max: maxMs > 0 ? maxMs : 1,
          onChanged: maxMs > 0
              ? (v) => player.seek(Duration(milliseconds: v.toInt()))
              : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(formatDuration(player.position),
                  style: const TextStyle(fontSize: 12)),
              Text(
                duration != null ? formatDuration(duration) : '--:--',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildControls(BuildContext context, PlayerService player) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          icon: Icon(_modeIcon(player.mode)),
          tooltip: player.modeLabel,
          onPressed: player.cycleMode,
        ),
        IconButton(
          icon: const Icon(Icons.skip_previous, size: 36),
          onPressed: player.hasQueue ? () => player.prev() : null,
        ),
        IconButton.filled(
          iconSize: 44,
          icon: Icon(player.playing ? Icons.pause : Icons.play_arrow),
          onPressed: () => player.toggle(),
        ),
        IconButton(
          icon: const Icon(Icons.skip_next, size: 36),
          onPressed: player.hasQueue ? () => player.next() : null,
        ),
        IconButton(
          icon: const Icon(Icons.queue_music),
          tooltip: '播放队列',
          onPressed: () => _showQueue(context, player),
        ),
      ],
    );
  }

  IconData _modeIcon(PlayMode mode) => switch (mode) {
        PlayMode.sequence => Icons.arrow_right_alt,
        PlayMode.loop => Icons.repeat,
        PlayMode.single => Icons.repeat_one,
        PlayMode.shuffle => Icons.shuffle,
      };

  Widget _buildExtraRow(BuildContext context, PlayerService player) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('倍速', style: TextStyle(fontSize: 13)),
        const SizedBox(width: 8),
        DropdownButton<double>(
          value: player.speed,
          underline: const SizedBox.shrink(),
          items: const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0]
              .map((s) => DropdownMenuItem(
                    value: s,
                    child: Text('${s}x'),
                  ))
              .toList(),
          onChanged: (v) {
            if (v != null) player.setSpeed(v);
          },
        ),
      ],
    );
  }

  Widget _buildQualityRow(BuildContext context, PlayerService player) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('音质', style: TextStyle(fontSize: 13)),
        const SizedBox(width: 8),
        for (final level in Quality.levels)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label:
                  Text(Quality.nameOf(level), style: const TextStyle(fontSize: 12)),
              selected: player.quality == level,
              onSelected: (_) => player.setQuality(level),
            ),
          ),
      ],
    );
  }

  void _showQueue(BuildContext context, PlayerService player) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Text('播放队列（${player.queue.length}）',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        player.clearQueue();
                        Navigator.of(sheetContext).pop();
                      },
                      child: const Text('清空'),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: player.queue.length,
                  itemBuilder: (_, i) {
                    final t = player.queue[i];
                    final isCurrent = i == player.index;
                    return ListTile(
                      dense: true,
                      leading: isCurrent
                          ? Icon(Icons.play_arrow,
                              color:
                                  Theme.of(context).colorScheme.primary)
                          : Text('${i + 1}'),
                      title: Text(
                        t.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: isCurrent
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      onTap: () {
                        player.jumpTo(i);
                        Navigator.of(sheetContext).pop();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
