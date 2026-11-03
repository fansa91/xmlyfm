import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/responsive.dart';
import '../core/utils.dart';
import '../models/models.dart';
import '../services/library_service.dart';
import '../services/player_service.dart';
import '../widgets/cover_image.dart';
import '../widgets/download_button.dart';

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
          if (track != null)
            // 播放页不知所属专辑名/集序号，文件名 {album}/{index} 走服务内回落
            TrackDownloadButton(
              track: track,
              albumTitle: '',
              index: 0,
              compact: true,
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
          : isExpanded(context)
          ? _buildWideBody(context, player, track)
          : Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  _buildMeta(context, player, track, coverSize: 260),
                  const Spacer(),
                  _buildControlPanel(context, player),
                ],
              ),
            ),
    );
  }

  /// 封面 + 标题 + 主播（+ 定时 chip）：单列与双栏共用
  Widget _buildMeta(
    BuildContext context,
    PlayerService player,
    Track track, {
    required double coverSize,
  }) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CoverImage(url: track.cover, size: coverSize, radius: 24),
        const SizedBox(height: 24),
        Text(
          track.title,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          track.nickname,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (player.sleepAt != null) ...[
          const SizedBox(height: 8),
          Chip(
            avatar: const Icon(Icons.timer, size: 16),
            label: Text(
              '定时关闭：${player.sleepAt!.difference(DateTime.now()).inMinutes + 1} 分钟内',
            ),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ],
    );
  }

  /// 试听横幅 / 报错 / 进度 / 控制 / 倍速 / 音质：单列与双栏共用
  Widget _buildControlPanel(BuildContext context, PlayerService player) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (player.isSample) _buildSampleBanner(context, player),
        if (player.errorMessage != null) ...[
          Text(
            player.errorMessage!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
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
    );
  }

  /// 宽屏（≥900）双栏：左封面信息，右控制区；整体限宽 1200 居中
  Widget _buildWideBody(
    BuildContext context,
    PlayerService player,
    Track track,
  ) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 16, 32, 24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _buildMeta(context, player, track, coverSize: 340),
              ),
              const SizedBox(width: 48),
              Expanded(child: _buildControlPanel(context, player)),
            ],
          ),
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
        result?.notice ?? '付费内容，仅支持试听 ${result?.sampleDuration ?? 0} 秒',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onTertiaryContainer,
        ),
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
              Text(
                formatDuration(player.position),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                duration != null ? formatDuration(duration) : '--:--',
                style: Theme.of(context).textTheme.bodySmall,
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
    final theme = Theme.of(context);
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('倍速', style: theme.textTheme.labelLarge),
        const SizedBox(width: 8),
        MenuAnchor(
          builder: (context, controller, _) => TextButton(
            onPressed: () =>
                controller.isOpen ? controller.close() : controller.open(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${player.speed}x'),
                const Icon(Icons.arrow_drop_down, size: 20),
              ],
            ),
          ),
          menuChildren: [
            for (final s in speeds)
              MenuItemButton(
                leadingIcon: Icon(
                  s == player.speed ? Icons.check : null,
                  size: 18,
                ),
                onPressed: () => player.setSpeed(s),
                child: Text('${s}x'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildQualityRow(BuildContext context, PlayerService player) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('音质', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(width: 8),
        for (final level in Quality.levels)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text(Quality.nameOf(level)),
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
                    Text(
                      '播放队列（${player.queue.length}）',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
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
                          ? Icon(
                              Icons.play_arrow,
                              color: Theme.of(context).colorScheme.primary,
                            )
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
