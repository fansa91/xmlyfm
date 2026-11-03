import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'audio_tag.dart';
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
  final String intro; // 专辑简介（入队时从专辑页带入，写 COMM 用；可空）
  final String categoryName; // 专辑分类名（写 TCON 用；可空）
  final int albumTotal; // 专辑总集数（TRCK 写「序号/总集数」用；0=未知）

  /// 入队时那条 Track 的完整 JSON：重下时据此重新走 PlayResolver
  /// （保住列表直带 URL 与付费标记，不因只存展示字段而丢）
  final String trackJson;

  /// 最终文件名（含扩展名），位于下载目录下
  String fileName;

  /// 完整路径，随任务记录持久化为绝对路径：改下载目录后，已完成记录
  /// 仍指向原文件（播放/删除不受影响）。旧版本记录无此字段，init 时
  /// 按默认目录（历史文件都在那里）重建。
  String filePath;

  /// 总字节数（0 = 未知）；已完成时为文件实际大小
  int fileSize;
  int downloadedBytes;
  DownloadStatus status;
  String? errorMessage;

  /// 是否已把标签（标题/专辑/主播/序号/封面）写进文件本体。
  /// 全平台下载完成后都写；仅 MP3 写 ID3v2，m4a 等容器跳过本体标签
  /// （元信息在任务记录里）恒为 false；写失败也为 false。
  bool tagged;
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
    this.intro = '',
    this.categoryName = '',
    this.albumTotal = 0,
    this.trackJson = '',
    required this.fileName,
    required this.filePath,
    this.fileSize = 0,
    this.downloadedBytes = 0,
    this.status = DownloadStatus.queued,
    this.errorMessage,
    this.tagged = false,
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
    'intro': intro,
    'categoryName': categoryName,
    'albumTotal': albumTotal,
    'trackJson': trackJson,
    'fileName': fileName,
    'filePath': filePath,
    'fileSize': fileSize,
    'downloadedBytes': downloadedBytes,
    'status': status.name,
    'errorMessage': errorMessage,
    'tagged': tagged,
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
      intro: json['intro'] as String? ?? '',
      categoryName: json['categoryName'] as String? ?? '',
      albumTotal: json['albumTotal'] as int? ?? 0,
      trackJson: json['trackJson'] as String? ?? '',
      fileName: json['fileName'] as String? ?? '',
      filePath: json['filePath'] as String? ?? '',
      fileSize: json['fileSize'] as int? ?? 0,
      downloadedBytes: json['downloadedBytes'] as int? ?? 0,
      status: status,
      errorMessage: json['errorMessage'] as String?,
      tagged: json['tagged'] as bool? ?? false,
      createdAt: json['createdAt'] as int? ?? 0,
    );
  }
}

/// 下载管理：经 PlayResolver 解析直链后用 dio 流式下载到生效下载目录
/// （设置里的自定义目录优先，iOS 除外；缺省为应用文档目录 downloads/）；
/// 任务列表以 SharedPreferences JSON 持久化。
///
/// - 严格 FIFO 串行队列：同一时刻只下载 1 个，按入队顺序推进；暂停的
///   排队任务轮到时跳过，正在下的被暂停/取消/失败后自动取下一个。
///   暂停/取消/重试均为单任务级，另有全部暂停/继续。
/// - 不做断点续传：暂停即删半截文件，继续时重新解析地址整文件重下。
/// - 重启恢复：已完成记录校验文件存在才保留；下载中/排队一律转暂停态。
class DownloadService extends ChangeNotifier {
  static const _keyTasks = 'download_tasks';

  /// 同时进行的下载数：串行队列恒为 1。
  static const maxConcurrent = 1;

  final PlayResolver resolver;
  final SettingsService settings;
  final Dio _dio;

  /// 是否 iOS 平台（自定义下载目录的判读用：iOS 恒用沙盒默认目录、
  /// 忽略自定义值；默认取 dart:io 的 Platform.isIOS，Web 等取不到
  /// 平台信息时按非 iOS 处理；测试可覆盖）。
  @visibleForTesting
  bool Function() isIOS = () {
    try {
      return Platform.isIOS;
    } catch (_) {
      return false;
    }
  };

  late SharedPreferences _prefs;
  Directory? _dir;

  /// 默认下载目录（应用文档目录 downloads/），自定义目录回落目标，
  /// 也是旧版本任务记录重建路径的基准。
  Directory? _defaultDir;
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

  /// 当前生效的下载目录路径（未初始化/不可用时为 null）
  String? get downloadDirPath => _dir?.path;

  /// 默认下载目录路径（应用文档目录 downloads/）
  String? get defaultDirPath => _defaultDir?.path;

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

  /// 准备目录：不存在则递归创建，并做可写性探针（写临时文件再删）。
  /// 目录就绪且可写返回 true。
  static Future<bool> prepareDirectory(Directory dir) async {
    try {
      if (!await dir.exists()) await dir.create(recursive: true);
      final probe = File(p.join(dir.path, '.xmlyfm_probe'));
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 生效下载目录解析：非 iOS 且自定义路径非空时优先用自定义目录，
  /// 其准备失败（建不出/不可写）则回落默认目录；iOS 恒用默认目录。
  static Future<Directory> resolveDownloadDirectory({
    required String customPath,
    required Directory defaultDir,
    required bool ios,
  }) async {
    final custom = customPath.trim();
    if (!ios && custom.isNotEmpty) {
      final dir = Directory(custom);
      if (await prepareDirectory(dir)) return dir;
    }
    await prepareDirectory(defaultDir);
    return defaultDir;
  }

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    try {
      final docs = await getApplicationDocumentsDirectory();
      _defaultDir = Directory(p.join(docs.path, 'downloads'));
      _dir = await resolveDownloadDirectory(
        customPath: settings.downloadDirectory,
        defaultDir: _defaultDir!,
        ios: isIOS(),
      );
    } catch (_) {
      // 文档目录不可用（如 Web）：下载功能整体降级，enqueue 会提示未就绪
      _dir = null;
      return;
    }
    await _loadTasks();
    await _save();
  }

  /// 测试用：跳过 path_provider，直接指定下载目录完成初始化
  /// （同时充当默认目录）。
  @visibleForTesting
  Future<void> initForTest(Directory dir) async {
    _prefs = await SharedPreferences.getInstance();
    _defaultDir = dir;
    _dir = dir;
    if (!await dir.exists()) await dir.create(recursive: true);
    await _loadTasks();
  }

  Future<void> _loadTasks() async {
    final raw = _prefs.getString(_keyTasks);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final e in decoded.whereType<Map>()) {
            final task = DownloadTask.fromJson(Map<String, dynamic>.from(e));
            if (task.trackId <= 0 || task.fileName.isEmpty) continue;
            if (task.filePath.isEmpty) {
              // 旧版本记录没有持久化路径：历史下载都在默认目录下，
              // 按默认目录重建（不能用当前生效目录，否则换过目录后
              // 已完成记录会全部对不上文件被丢弃）
              task.filePath = p.join(
                (_defaultDir ?? _dir)!.path,
                task.fileName,
              );
            }
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

  /// 按「下载格式」设置选解析路径：MP3 优先走下载专用解析
  /// [PlayResolver.resolveForDownload]（优先 MP3 直链，能写文件标签）；
  /// 音质优先走常规 [PlayResolver.resolve]（按默认音质取链，多为 M4A，
  /// 无法写入标签）。只在入队与每次开跑重解析时现读设置，已入队/
  /// 已完成任务不受之后改设置的影响。付费试听拦截两条路径都保持。
  Future<PlayResult> _resolveForDownload(Track track) {
    final quality = settings.defaultQuality;
    if (settings.downloadFormat == SettingsService.downloadFormatQuality) {
      return resolver.resolve(track, quality: quality);
    }
    return resolver.resolveForDownload(track, quality: quality);
  }

  /// 单集入队。返回 null 表示成功；返回字符串为失败原因（供 UI 弹提示）。
  Future<String?> enqueueTrack(
    Track track, {
    required String albumTitle,
    required int index,
    String albumIntro = '',
    String albumCategory = '',
    int albumTotal = 0,
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

    // 先按「下载格式」设置解析（默认 MP3 优先，下回来能写 ID3 标签；
    // 音质优先则按默认音质取链）：试听/无地址直接拒绝，不建任务
    final String url;
    try {
      final result = await _resolveForDownload(track);
      if (result.isSample) return '付费内容仅支持试听，无法下载';
      if (result.url == null || result.url!.isEmpty) {
        return result.notice ?? '无法获取下载地址';
      }
      url = result.url!;
    } on XmException catch (e) {
      return e.message;
    }

    final task = _buildTask(
      track,
      albumTitle: albumTitle,
      index: index,
      url: url,
      dir: dir,
      albumIntro: albumIntro,
      albumCategory: albumCategory,
      albumTotal: albumTotal,
    );
    _tasks.insert(0, task);
    await _save();
    notifyListeners();
    _pump();
    return null;
  }

  /// 下载落盘用的扩展名：以 [DownloadFileNameFormatter.extensionForUrl]
  /// 为准，但 `.fhq`（无损条目的非标准后缀）保留原后缀——
  /// extensionForUrl 对未知后缀回落 .mp3，会把无损文件误标成 mp3
  /// 还误触 ID3 写入。无损的真实容器以下载完成后的文件头嗅探为准
  /// （魔数 fLaC 才改名 .flac，见 [_sniffAndRenameFlac]）。
  static String _downloadExtensionForUrl(String url) {
    final path = Uri.tryParse(url)?.path ?? url;
    if (path.toLowerCase().endsWith('.fhq')) return '.fhq';
    return DownloadFileNameFormatter.extensionForUrl(url);
  }

  /// 按文件名模板与去重规则组装一个待下载任务。
  DownloadTask _buildTask(
    Track track, {
    required String albumTitle,
    required int index,
    required String url,
    required Directory dir,
    String albumIntro = '',
    String albumCategory = '',
    int albumTotal = 0,
  }) {
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
    final ext = _downloadExtensionForUrl(url);
    final taken = _tasks.map((t) => t.fileName).toSet();
    final fileName = DownloadFileNameFormatter.uniqueName(
      base,
      ext,
      (candidate) =>
          taken.contains(candidate) ||
          File(p.join(dir.path, candidate)).existsSync(),
    );
    return DownloadTask(
      trackId: track.trackId,
      albumId: track.albumId,
      albumTitle: albumTitle,
      title: track.title,
      nickname: track.nickname,
      cover: track.cover,
      duration: track.duration,
      index: index,
      intro: albumIntro,
      categoryName: albumCategory,
      albumTotal: albumTotal,
      trackJson: jsonEncode(track.toJson()),
      fileName: fileName,
      filePath: p.join(dir.path, fileName),
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// 开跑前按最终 URL 的真实扩展名校正任务文件名：入队解析与开跑
  /// 重解析可能给出不同格式的地址，而扩展名决定写标签分流
  /// （只有 .mp3 写 ID3）。扩展名变化时换名落盘；旧路径上未完成
  /// 任务只会留半截文件，一并清掉免成孤儿。
  Future<void> _alignFileExtension(DownloadTask task, String url) async {
    final ext = _downloadExtensionForUrl(url);
    if (p.extension(task.fileName).toLowerCase() == ext) return;
    final oldPath = task.filePath;
    final dirPath = p.dirname(oldPath);
    final taken = _tasks
        .where((t) => t.trackId != task.trackId)
        .map((t) => t.fileName)
        .toSet();
    task.fileName = DownloadFileNameFormatter.uniqueName(
      p.basenameWithoutExtension(task.fileName),
      ext,
      (candidate) =>
          taken.contains(candidate) ||
          File(p.join(dirPath, candidate)).existsSync(),
    );
    task.filePath = p.join(dirPath, task.fileName);
    if (oldPath != task.filePath) {
      final old = File(oldPath);
      if (await old.exists()) {
        try {
          await old.delete();
        } catch (_) {}
      }
    }
  }

  /// 批量入队。返回 (成功入队数, 第一条失败原因或 null)。
  Future<(int, String?)> enqueueMany(
    List<Track> tracks, {
    required String albumTitle,
    required int Function(Track) indexOf,
    String albumIntro = '',
    String albumCategory = '',
    int albumTotal = 0,
  }) async {
    var ok = 0;
    String? firstError;
    for (final t in tracks) {
      if (isDownloaded(t.trackId)) continue;
      final err = await enqueueTrack(
        t,
        albumTitle: albumTitle,
        index: indexOf(t),
        albumIntro: albumIntro,
        albumCategory: albumCategory,
        albumTotal: albumTotal,
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

  /// 队列推进：严格串行——已有任务在下时不动（其收尾会再调 _pump）；
  /// 否则按入队顺序取第一个排队态任务开跑。任务列表新入队在前，
  /// 故从尾部（最早入队）起扫描；已暂停的任务状态不是 queued，天然跳过，
  /// 失败/完成/取消也都在 _run 的 finally 里回到这里推进下一个。
  void _pump() {
    if (_tokens.isNotEmpty) return;
    for (var i = _tasks.length - 1; i >= 0; i--) {
      final t = _tasks[i];
      if (t.status == DownloadStatus.queued) {
        unawaited(_run(t));
        return;
      }
    }
  }

  Future<void> _run(DownloadTask task) async {
    final token = CancelToken();
    _tokens[task.trackId] = token;
    task.status = DownloadStatus.downloading;
    task.errorMessage = null;
    notifyListeners();

    var file = File(task.filePath);
    try {
      // 每次开跑都重新解析地址（直链可能过期；解析路径同样按
      // 「下载格式」设置选）；试听会在这里再次被拦
      final track = task.toTrack();
      final result = await _resolveForDownload(track);
      if (result.isSample) {
        throw const XmException('付费内容仅支持试听，无法下载');
      }
      final url = result.url;
      if (url == null || url.isEmpty) {
        throw XmException(result.notice ?? '无法获取下载地址');
      }
      // 以最终 URL 的真实扩展名校正文件名：入队时与开跑时解析出的
      // 格式可能不同，而扩展名决定写标签分流，只认 URL 后缀不信字段名
      await _alignFileExtension(task, url);
      file = File(task.filePath);

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
      // 完整性校验：落盘文件必须真实存在且非空，才继续往下走
      if (!await file.exists() || await file.length() <= 0) {
        throw const XmException('下载文件缺失或为空，请重试');
      }
      task.fileSize = await file.length();
      task.downloadedBytes = task.fileSize;
      // 无损嗅探：内容是 FLAC 时先按 .flac 改名落盘（不转码），且不写
      // 标签（ID3 写入器只认 mp3；FLAC 的 Vorbis Comment 本轮不做，
      // tagged 保持 false，下载管理按「未写标签 · 格式不支持」展示）
      final isFlac = await _sniffAndRenameFlac(task, file);
      file = File(task.filePath);
      if (isFlac) {
        task.tagged = false;
      } else {
        // 落盘后把标签写进文件本体（失败不影响完成状态，见 _tagCompletedFile）
        await _tagCompletedFile(task);
      }
      // 写标签走的是临时文件替换：期间任务可能被 remove（清孤儿文件），
      // 文件也可能被外部动过。复检通过才置完成，文件没了置失败可重试。
      if (!_tasks.any((t) => t.trackId == task.trackId)) {
        if (await file.exists()) await file.delete();
        return;
      }
      if (!await file.exists() || await file.length() <= 0) {
        throw const XmException('下载文件写入失败，请重试');
      }
      task.fileSize = await file.length();
      task.downloadedBytes = task.fileSize;
      task.status = DownloadStatus.completed;
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

  /// 嗅探已落盘文件的文件头：内容是 FLAC（魔数 `fLaC`）且当前扩展名
  /// 不是 .flac 时，把文件改名为 .flac（同步任务记录的 fileName/
  /// filePath，命名冲突走既有去重规则）。无损 URL 的后缀不可靠
  /// （§5.8：playPathHq 实测是 .m4a 容器、baseInfo fhq 条目后缀未取得
  /// 一手证据），故真实容器只认文件头；不做任何转码。
  ///
  /// 返回是否为 FLAC 内容（改名失败也算，调用方据此跳过写标签）；
  /// 读不到文件头/魔数不符返回 false，保留原后缀原样处理。
  Future<bool> _sniffAndRenameFlac(DownloadTask task, File file) async {
    try {
      final raf = await file.open();
      final head = await raf.read(4);
      await raf.close();
      if (head.length < 4 ||
          head[0] != 0x66 || // f
          head[1] != 0x4C || // L
          head[2] != 0x61 || // a
          head[3] != 0x43) {
        // C
        return false;
      }
    } catch (_) {
      return false;
    }
    if (p.extension(task.fileName).toLowerCase() == '.flac') return true;
    final dirPath = p.dirname(task.filePath);
    final taken = _tasks
        .where((t) => t.trackId != task.trackId)
        .map((t) => t.fileName)
        .toSet();
    final newName = DownloadFileNameFormatter.uniqueName(
      p.basenameWithoutExtension(task.fileName),
      '.flac',
      (candidate) =>
          taken.contains(candidate) ||
          File(p.join(dirPath, candidate)).existsSync(),
    );
    try {
      await file.rename(p.join(dirPath, newName));
      task.fileName = newName;
      task.filePath = p.join(dirPath, newName);
    } catch (_) {
      // 改名失败保留原路径；仍按 FLAC 内容对待（不写标签）
    }
    return true;
  }

  // ---------- 标签写入 ----------

  /// 测试用：直接对一个已完成任务执行写标签流程。
  @visibleForTesting
  Future<void> applyTagsForTest(DownloadTask task) => _tagCompletedFile(task);

  /// 下载完成后把标签写进文件本体：标题/专辑/主播/序号（带总集数）/封面，
  /// 以及简介（COMM）、分类（TCON）、发布日期（TDRC）、时长（TLEN）和
  /// TXXX 自定义项（声音/专辑 ID、播放量、来源、付费标记）——字段拿不到
  /// 的不写，不编造。
  ///
  /// - **全平台执行**：下载完成即写，与平台无关。
  /// - 仅 MP3 写 ID3v2（[AudioTagWriter]）；m4a/mp4 容器手写改 ilst 风险高，
  ///   跳过本体标签——元信息仍完整保存在任务记录里，tagged 保持 false。
  /// - 封面图拉取失败则写无图标签，不阻塞；写标签失败保留原文件，
  ///   任务照样算完成。成功后按新文件大小回填 fileSize。
  Future<void> _tagCompletedFile(DownloadTask task) async {
    if (!AudioTagWriter.supportsTagging(task.fileName)) {
      task.tagged = false;
      return;
    }
    try {
      Uint8List? coverBytes;
      var coverMime = 'image/jpeg';
      if (task.cover.isNotEmpty) {
        final fetched = await _fetchCover(task.cover);
        if (fetched != null) {
          coverBytes = fetched.$1;
          coverMime = fetched.$2;
        }
      }
      final track = task.toTrack();
      final durationSec = task.duration > 0 ? task.duration : track.duration;
      final ok = await AudioTagWriter.writeToFile(
        File(task.filePath),
        AudioTagData(
          title: task.title,
          album: task.albumTitle.isNotEmpty ? task.albumTitle : task.nickname,
          artist: task.nickname,
          trackNumber: task.index,
          totalTracks: task.albumTotal,
          coverBytes: coverBytes,
          coverMime: coverMime,
          description: task.intro,
          genre: task.categoryName,
          releaseDate: _releaseDateOf(track.createdAt),
          durationMs: durationSec > 0 ? durationSec * 1000 : 0,
          custom: [
            ('trackId', '${task.trackId}'),
            ('albumId', '${task.albumId}'),
            if (track.playtimes > 0) ('playtimes', '${track.playtimes}'),
            ('source', 'ximalaya'),
            if (track.isPaid) ('isPaid', 'true'),
          ],
        ),
      );
      task.tagged = ok;
      if (ok) {
        final f = File(task.filePath);
        if (await f.exists()) {
          task.fileSize = await f.length();
          task.downloadedBytes = task.fileSize;
        }
      }
    } catch (_) {
      task.tagged = false;
    } finally {
      // 写标签的临时文件无论成败都不许残留（writeToFile 内部已清，
      // 这里再兜底一次，防异常路径漏网）
      try {
        final leftover = File('${task.filePath}.tagging');
        if (await leftover.exists()) await leftover.delete();
      } catch (_) {}
    }
  }

  /// 拉封面图字节与 MIME（响应头优先，其次按 URL 后缀猜）；失败返回 null。
  Future<(Uint8List, String)?> _fetchCover(String url) async {
    try {
      final resp = await _dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      final data = resp.data;
      if (data == null || data.isEmpty) return null;
      var mime = resp.headers.value('content-type')?.split(';').first.trim();
      if (mime == null || !mime.startsWith('image/')) {
        mime = _mimeForCoverUrl(url);
      }
      return (Uint8List.fromList(data), mime);
    } catch (_) {
      return null;
    }
  }

  /// Track 发布时间（接口 createdAt）→ TDRC 的 yyyy-MM-dd。
  /// createdAt 为毫秒级时间戳（个别来源可能是秒级，做一次量级归一）；
  /// 无效值返回空串（不写 TDRC）。
  static String _releaseDateOf(int createdAt) {
    if (createdAt <= 0) return '';
    final ms = createdAt < 100000000000 ? createdAt * 1000 : createdAt;
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  static String _mimeForCoverUrl(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('.png')) return 'image/png';
    if (lower.contains('.webp')) return 'image/webp';
    return 'image/jpeg';
  }
}
