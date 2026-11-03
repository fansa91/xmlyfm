import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/utils.dart';
import '../services/download_service.dart';
import '../services/player_service.dart';
import '../widgets/cover_image.dart';
import '../widgets/detail_scaffold.dart';

/// 下载管理页：顶部总占用；「进行中」（排队/下载中/暂停/失败）与
/// 「已完成」两组。已完成点按直接本地播放，删除走确认弹窗（连文件删）。
class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final downloads = context.watch<DownloadService>();
    final active = downloads.activeTasks;
    final done = downloads.completedTasks;
    final hasPausable = active.any(
      (t) =>
          t.status == DownloadStatus.downloading ||
          t.status == DownloadStatus.queued,
    );
    final hasResumable = active.any(
      (t) =>
          t.status == DownloadStatus.paused ||
          t.status == DownloadStatus.failed,
    );

    return DetailScaffold(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('下载管理'),
          actions: [
            if (hasPausable)
              IconButton(
                icon: const Icon(Icons.pause_circle_outline),
                tooltip: '全部暂停',
                onPressed: downloads.pauseAll,
              ),
            if (hasResumable)
              IconButton(
                icon: const Icon(Icons.play_circle_outline),
                tooltip: '全部继续',
                onPressed: downloads.resumeAll,
              ),
          ],
        ),
        body: downloads.tasks.isEmpty
            ? const Center(child: Text('暂无下载，在专辑页点下载图标即可添加'))
            : ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text(
                      '共 ${done.length} 个文件 · 占用 ${formatBytes(downloads.totalBytes)}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (active.isNotEmpty) ...[
                    _sectionTitle(context, '进行中'),
                    for (final t in active) _buildActiveTile(context, t),
                  ],
                  if (done.isNotEmpty) ...[
                    _sectionTitle(context, '已完成'),
                    for (final t in done) _buildDoneTile(context, t),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        title,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildActiveTile(BuildContext context, DownloadTask task) {
    final downloads = context.read<DownloadService>();
    final theme = Theme.of(context);
    final (statusText, progressValue) = switch (task.status) {
      DownloadStatus.downloading => (
        task.fileSize > 0
            ? '下载中 ${(task.progress * 100).toStringAsFixed(0)}%'
            : '下载中 ${formatBytes(task.downloadedBytes)}',
        task.fileSize > 0 ? task.progress : null,
      ),
      DownloadStatus.queued => ('排队中', null),
      DownloadStatus.paused => ('已暂停', task.progress),
      DownloadStatus.failed => (task.errorMessage ?? '下载失败', task.progress),
      DownloadStatus.completed => ('已完成', 1.0),
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: CoverImage(url: task.cover, size: 48, radius: 8),
          title: Text(task.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            [
              if (task.albumTitle.isNotEmpty) task.albumTitle,
              statusText,
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: task.status == DownloadStatus.failed
                  ? theme.colorScheme.error
                  : null,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (task.status == DownloadStatus.downloading)
                IconButton(
                  icon: const Icon(Icons.pause),
                  tooltip: '暂停',
                  onPressed: () => downloads.pause(task),
                ),
              if (task.status == DownloadStatus.paused)
                IconButton(
                  icon: const Icon(Icons.play_arrow),
                  tooltip: '继续',
                  onPressed: () => downloads.resume(task),
                ),
              if (task.status == DownloadStatus.failed)
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: '重试',
                  onPressed: () => downloads.retry(task),
                ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: '取消并删除',
                onPressed: () => downloads.remove(task),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: LinearProgressIndicator(value: progressValue),
        ),
      ],
    );
  }

  Widget _buildDoneTile(BuildContext context, DownloadTask task) {
    return ListTile(
      leading: CoverImage(url: task.cover, size: 48, radius: 8),
      title: Text(task.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          if (task.albumTitle.isNotEmpty) task.albumTitle,
          formatBytes(task.fileSize),
          if (task.duration > 0) formatSeconds(task.duration),
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: '删除下载',
        onPressed: () => _confirmDelete(context, task),
      ),
      onTap: () => context.read<PlayerService>().playTrack(task.toTrack()),
    );
  }

  Future<void> _confirmDelete(BuildContext context, DownloadTask task) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除下载'),
        content: Text('删除《${task.title}》的本地文件？删除后需重新下载。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<DownloadService>().remove(task);
    }
  }
}
