import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/download_service.dart';

/// 单集下载状态按钮（专辑页行尾 / 播放页 AppBar 共用）。
/// 状态：未下载（下载图标）→ 排队（沙漏）→ 下载中（环形进度，点按取消）
/// → 已完成（对勾 + 「已下载」，compact 时只显示对勾）→ 失败（重试图标）。
/// 颜色全部走 ColorScheme（含「已下载」标记，用 primary 而非写死绿色）。
class TrackDownloadButton extends StatelessWidget {
  final Track track;
  final String albumTitle;
  final int index;

  /// 紧凑模式（AppBar 等窄位置）：已完成只显示对勾图标，不带文字
  final bool compact;

  const TrackDownloadButton({
    super.key,
    required this.track,
    required this.albumTitle,
    required this.index,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final downloads = context.watch<DownloadService>();
    final theme = Theme.of(context);
    final task = downloads.taskFor(track.trackId);

    if (task != null) {
      switch (task.status) {
        case DownloadStatus.completed:
          final check = Icon(
            Icons.check_circle,
            color: theme.colorScheme.primary,
            size: 22,
          );
          if (compact) return IconButton(icon: check, onPressed: null);
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '已下载',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 4),
              check,
            ],
          );
        case DownloadStatus.downloading:
          return IconButton(
            tooltip: '取消下载',
            icon: SizedBox(
              width: 22,
              height: 22,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: task.fileSize > 0 ? task.progress : null,
                    strokeWidth: 2.5,
                  ),
                  Icon(Icons.close, size: 12, color: theme.colorScheme.primary),
                ],
              ),
            ),
            onPressed: () => downloads.remove(task),
          );
        case DownloadStatus.queued:
          return IconButton(
            tooltip: '取消排队',
            icon: const Icon(Icons.hourglass_top, size: 20),
            onPressed: () => downloads.remove(task),
          );
        case DownloadStatus.paused:
          return IconButton(
            tooltip: '继续下载',
            icon: Icon(
              Icons.download,
              color: theme.colorScheme.primary,
              size: 22,
            ),
            onPressed: () => downloads.resume(task),
          );
        case DownloadStatus.failed:
          return IconButton(
            tooltip: '下载失败，点击重试',
            icon: Icon(Icons.refresh, color: theme.colorScheme.error),
            onPressed: () => downloads.retry(task),
          );
      }
    }

    return IconButton(
      tooltip: '下载',
      icon: const Icon(Icons.download_outlined, size: 22),
      onPressed: () async {
        final err = await downloads.enqueueTrack(
          track,
          albumTitle: albumTitle,
          index: index,
        );
        if (err != null && context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(err)));
        }
      },
    );
  }
}
