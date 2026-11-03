import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'download_filename.dart';
import 'play_resolver.dart';
import 'settings_service.dart';
import 'ximalaya_service.dart';

/// 下载任务状态
enum DownloadStatus { queued, downloading, paused, completed, failed }

/// 一条下载任务。只下完整音频：试听（付费集）由 [DownloadService] 拒绝入队。
class DownloadTask {
  final int trackId;
  final int albumId;
  final String albumTitle;
  final String title;
  final String nickname; // 主播
  final String cover;
  final int duration; // 秒
  final int index; // 专辑内集序号（从 1 起）

  /// 入队时那条 Track 的完整 JSON：重下时据此重新走 PlayResolver
  /// （保住列表直带 URL 与付费标记，不因只存展示字段而丢）
  final String trackJson;

  /// 最终文件名（含扩展名），位于 downloads 目录下
  String fileName;

  /// 完整路径（init 时按当前文档目录重建，兼容文档目录迁移）
  String filePath;

  /// 总字节数（0 = 未知）；已完成时为文件实际大小
  int fileSize;
  int downloadedBytes;
  DownloadStatus status;
  String? errorMessage;
  final int createdAt;

  DownloadTask({
    required this.trackId,
    required this.albumId,
    required this.albumTitle,
    required this.title,
    required this.nickname,
    required this.cover,
    required this.duration,
    required this.index,
    this.trackJson = '',
    required this.fileName,
    required this.filePath,
    this.fileSize = 0,
    this.downloadedBytes = 0,
    this.status = DownloadStatus.queued,
    this.errorMessage,
    required this.createdAt,
  });

  double get progress =>
      fileSize > 0 ? (downloadedBytes / fileSize).clamp(0.0, 1.0) : 0.0;

  bool get isFinished => status == DownloadStatus.completed;

  /// 还原成可播放的 Track（下载管理页点按播放、播放器本地优先都靠它）。
  /// 有完整 trackJson 时优先用它（带直带 URL/付费标记）。
  Track toTrack() {
    if (trackJson.isNotEmpty) {
      try {
        return Track.fromJson(
          Map<String, dynamic>.from(jsonDecode(trackJson) as Map),
        );
      } catch (_) {}
    }
    return Track(
      trackId: trackId,
      albumId: albumId,
      title: title,
      nickname: nickname,
      cover: cover,
      duration: duration,
    );
  }

  Map<String, dynamic> toJson() => {
    'trackId': trackId,
    'albumId': albumId,
    'albumTitle': albumTitle,
    'title': title,
    'nickname': nickname,
    'cover': cover,
    'duration': duration,
    'index': index,
    'trackJson': trackJson,
    'fileName': fileName,
    'fileSize': fileSize,
    'downloadedBytes': downloadedBytes,
    'status': status.name,
    'errorMessage': errorMessage,
    'createdAt': createdAt,
  };

  factory DownloadTask.fromJson(Map<String, dynamic> json) {
    var status = DownloadStatus.paused;
    for (final s in DownloadStatus.values) {
      if (s.name == json['status']) status = s;
    }
    return DownloadTask(
      trackId: json['trackId'] as int? ?? 0,
      albumId: json['albumId'] as int? ?? 0,
      albumTitle: json['albumTitle'] as String? ?? '',
      title: json['title'] as String? ?? '',
      nickname: json['nickname'] as String? ?? '',
      cover: json['cover'] as String? ?? '',
      duration: json['duration'] as int? ?? 0,
      index: json['index'] as int? ?? 0,
      trackJson: json['trackJson'] as String? ?? '',
      fileName: json['fileName'] as String? ?? '',
      filePath: '',
      fileSize: json['fileSize'] as int? ?? 0,
      downloadedBytes: json['downloadedBytes'] as int? ?? 0,
      status: status,
      errorMessage: json['errorMessage'] as String?,
      createdAt: json['createdAt'] as int? ?? 0,
    );
  }
}

/// 下载管理：经 PlayResolver 解析直链后用 dio 流式下载到
/// 应用文档目录 downloads/；任务列表以 SharedPreferences JSON 持久化。
///
/// - 并发上限 2，其余排队；暂停/取消/重试均为单任务级，另有全部暂停/继续。
/// - 不做断点续传：暂停即删半截文件，继续时重新解析地址整文件重下。
/// - 重启恢复：已完成记录校验文件存在才保留；下载中/排队一律转暂停态。
class DownloadService extends ChangeNotifier {
  static const _keyTasks = 'download_tasks';
  static const maxConcurrent = 2;

  final PlayResolver resolver;
  final SettingsService settings;
  final Dio _dio;

  late SharedPreferences _prefs;
  Directory? _dir;
  final List<DownloadTask> _tasks = [];
  final Map<int, CancelToken> _tokens = {};
  final Set<int> _pauseRequested = {};

  DownloadService(this.resolver, this.settings, [Dio? dio])
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(minutes: 5),
              headers: const {'User-Agent': XimalayaService.userAgent},
            ),
          );

  List<DownloadTask> get tasks => List.unmodifiable(_tasks);
  List<DownloadTask> get completedTasks =>
      _tasks.where((t) => t.status == DownloadStatus.completed).toList();
  List<DownloadTask> get activeTasks =>
      _tasks.where((t) => t.status != DownloadStatus.completed).toList();

  /// 已完成文件的总占用字节
  int get totalBytes => completedTasks.fold(0, (sum, t) => sum + t.fileSize);

  DownloadTask? taskFor(int trackId) {
    for (final t in _tasks) {
      if (t.trackId == trackId) return t;
    }
    return null;
  }

  bool isDownloaded(int trackId) =>
      taskFor(trackId)?.status == DownloadStatus.completed;

  /// 已下载完成且文件存在的本地路径（播放器本地优先用）；否则 null。
  String? localPathFor(int trackId) {
    final t = taskFor(trackId);
    if (t == null || t.status != DownloadStatus.completed) return null;
    return File(t.filePath).existsSync() ? t.filePath : null;
  }

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    try {
      final docs = await getApplicationDocumentsDirectory();
      _dir = Directory('${docs.path}/downloads');
      if (!await _dir!.exists()) await _dir!.create(recursive: true);
    } catch (_) {
      // 文档目录不可用（如 Web）：下载功能整体降级，enqueue 会提示未就绪
      _dir = null;
      return;
    }

    final raw = _prefs.getString(_keyTasks);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final e in decoded.whereType<Map>()) {
            final task = DownloadTask.fromJson(Map<String, dynamic>.from(e));
            if (task.trackId <= 0 || task.fileName.isEmpty) continue;
            task.filePath = '${_dir!.path}/${task.fileName}';
            if (task.status == DownloadStatus.completed) {
              // 已完成记录必须文件还在，否则丢弃记录
              final f = File(task.filePath);
              if (!f.existsSync()) continue;
              task.fileSize = f.lengthSync();
              task.downloadedBytes = task.fileSize;
            } else {
              // 未完成任务重启后统一暂停（不做续传，恢复时整文件重下）
              if (task.status == DownloadStatus.downloading ||
                  task.status == DownloadStatus.queued) {
                task.status = DownloadStatus.paused;
              }
              task.downloadedBytes = 0;
            }
            _tasks.add(task);
          }
        }
      } catch (_) {}
    }
    await _save();
  }

  Future<void> _save() async {
    await _prefs.setString(
      _keyTasks,
      jsonEncode(_tasks.map((e) => e.toJson()).toList()),
    );
  }

  // ---------- 入队 ----------

  /// 单集入队。返回 null 表示成功；返回字符串为失败原因（供 UI 弹提示）。
  Future<String?> enqueueTrack(
    Track track, {
    required String albumTitle,
    required int index,
  }) async {
    final existing = taskFor(track.trackId);
    if (existing != null) {
      switch (existing.status) {
        case DownloadStatus.completed:
          return '已下载';
        case DownloadStatus.queued:
        case DownloadStatus.downloading:
          return '已在下载队列中';
        case DownloadStatus.paused:
          resume(existing);
          return null;
        case DownloadStatus.failed:
          retry(existing);
          return null;
      }
    }
    final dir = _dir;
    if (dir == null) return '下载目录未就绪';

    // 先解析：试听/无地址直接拒绝，不建任务
    final String url;
    try {
      final result = await resolver.resolve(
        track,
        quality: settings.defaultQuality,
      );
      if (result.isSample) return '付费内容仅支持试听，无法下载';
      if (result.url == null || result.url!.isEmpty) {
        return result.notice ?? '无法获取下载地址';
      }
      url = result.url!;
    } on XmException catch (e) {
      return e.message;
    }

    final albumName = albumTitle.isNotEmpty
        ? albumTitle
        : (track.nickname.isNotEmpty ? track.nickname : '未知专辑');
    final base = DownloadFileNameFormatter.render(
      settings.downloadFileNameFormat,
      album: albumName,
      title: track.title,
      index: index,
      trackId: track.trackId,
      author: track.nickname,
    );
    final ext = DownloadFileNameFormatter.extensionForUrl(url);
    final taken = _tasks.map((t) => t.fileName).toSet();
    final fileName = DownloadFileNameFormatter.uniqueName(
      base,
      ext,
      (candidate) =>
          taken.contains(candidate) ||
          File('${dir.path}/$candidate').existsSync(),
    );

    final task = DownloadTask(
      trackId: track.trackId,
      albumId: track.albumId,
      albumTitle: albumTitle,
      title: track.title,
      nickname: track.nickname,
      cover: track.cover,
      duration: track.duration,
      index: index,
      trackJson: jsonEncode(track.toJson()),
      fileName: fileName,
      filePath: '${dir.path}/$fileName',
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    _tasks.insert(0, task);
    await _save();
    notifyListeners();
    _pump();
    return null;
  }

  /// 批量入队。返回 (成功入队数, 第一条失败原因或 null)。
  Future<(int, String?)> enqueueMany(
    List<Track> tracks, {
    required String albumTitle,
    required int Function(Track) indexOf,
  }) async {
    var ok = 0;
    String? firstError;
    for (final t in tracks) {
      if (isDownloaded(t.trackId)) continue;
      final err = await enqueueTrack(
        t,
        albumTitle: albumTitle,
        index: indexOf(t),
      );
      if (err == null) {
        ok++;
      } else {
        firstError ??= err;
      }
    }
    return (ok, firstError);
  }

  // ---------- 任务控制 ----------

  void pause(DownloadTask task) {
    if (task.status == DownloadStatus.downloading) {
      _pauseRequested.add(task.trackId);
      _tokens[task.trackId]?.cancel('paused');
      // 状态在 _run 的 catch/finally 中落为 paused
    } else if (task.status == DownloadStatus.queued) {
      task.status = DownloadStatus.paused;
      unawaited(_save());
      notifyListeners();
    }
  }

  void resume(DownloadTask task) {
    if (task.status != DownloadStatus.paused &&
        task.status != DownloadStatus.failed) {
      return;
    }
    task.status = DownloadStatus.queued;
    task.errorMessage = null;
    task.downloadedBytes = 0;
    notifyListeners();
    unawaited(_save());
    _pump();
  }

  void retry(DownloadTask task) => resume(task);

  /// 取消任务并删除（连半截/完整文件一起删）。
  Future<void> remove(DownloadTask task) async {
    _pauseRequested.remove(task.trackId);
    _tokens[task.trackId]?.cancel('removed');
    _tokens.remove(task.trackId);
    _tasks.removeWhere((t) => t.trackId == task.trackId);
    final f = File(task.filePath);
    if (await f.exists()) await f.delete();
    await _save();
    notifyListeners();
    _pump();
  }

  void pauseAll() {
    for (final t in List.of(_tasks)) {
      if (t.status == DownloadStatus.downloading ||
          t.status == DownloadStatus.queued) {
        pause(t);
      }
    }
  }

  void resumeAll() {
    var changed = false;
    for (final t in _tasks) {
      if (t.status == DownloadStatus.paused ||
          t.status == DownloadStatus.failed) {
        t.status = DownloadStatus.queued;
        t.errorMessage = null;
        t.downloadedBytes = 0;
        changed = true;
      }
    }
    if (changed) {
      notifyListeners();
      unawaited(_save());
      _pump();
    }
  }

  // ---------- 执行 ----------

  void _pump() {
    final running = _tokens.length;
    if (running >= maxConcurrent) return;
    for (final t in _tasks) {
      if (_tokens.length >= maxConcurrent) break;
      if (t.status == DownloadStatus.queued &&
          !_tokens.containsKey(t.trackId)) {
        unawaited(_run(t));
      }
    }
  }

  Future<void> _run(DownloadTask task) async {
    final token = CancelToken();
    _tokens[task.trackId] = token;
    task.status = DownloadStatus.downloading;
    task.errorMessage = null;
    notifyListeners();

    final file = File(task.filePath);
    try {
      // 每次开跑都重新解析地址（直链可能过期）；试听会在这里再次被拦
      final track = task.toTrack();
      final result = await resolver.resolve(
        track,
        quality: settings.defaultQuality,
      );
      if (result.isSample) {
        throw const XmException('付费内容仅支持试听，无法下载');
      }
      final url = result.url;
      if (url == null || url.isEmpty) {
        throw XmException(result.notice ?? '无法获取下载地址');
      }

      var lastPercent = -1;
      await _dio.download(
        url,
        task.filePath,
        cancelToken: token,
        deleteOnError: true,
        onReceiveProgress: (received, total) {
          task.downloadedBytes = received;
          if (total > 0) task.fileSize = total;
          final percent = total > 0
              ? (received * 100 ~/ total)
              : received ~/ 65536;
          if (percent != lastPercent) {
            lastPercent = percent;
            notifyListeners();
          }
        },
      );

      // 下载期间可能已被 remove（任务列表里已不存在）：清理孤儿文件
      if (!_tasks.any((t) => t.trackId == task.trackId)) {
        if (await file.exists()) await file.delete();
        return;
      }
      task.status = DownloadStatus.completed;
      task.fileSize = await file.length();
      task.downloadedBytes = task.fileSize;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel ||
          _pauseRequested.contains(task.trackId)) {
        if (_tasks.any((t) => t.trackId == task.trackId)) {
          task.status = DownloadStatus.paused;
          task.downloadedBytes = 0;
          if (await file.exists()) await file.delete();
        }
      } else {
        task.status = DownloadStatus.failed;
        task.errorMessage = '下载失败：${e.message ?? e.type.name}';
      }
    } on XmException catch (e) {
      task.status = DownloadStatus.failed;
      task.errorMessage = e.message;
    } catch (e) {
      task.status = DownloadStatus.failed;
      task.errorMessage = '下载失败：$e';
    } finally {
      _pauseRequested.remove(task.trackId);
      _tokens.remove(task.trackId);
      await _save();
      notifyListeners();
      _pump();
    }
  }
}
