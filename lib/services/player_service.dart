import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'download_service.dart';
import 'library_service.dart';
import 'play_resolver.dart';
import 'settings_service.dart';
import 'ximalaya_service.dart';

enum PlayMode { sequence, loop, single, shuffle }

/// 播放器：Track 队列、播放模式、倍速、定时关闭、音质切换。
///
/// - 播放地址统一经 [PlayResolver] 三路分流解析（列表直带 / track pay
///   元数据 / baseInfo），结果按 trackId+音质缓存。
/// - 付费集解析返回 url=null + notice：不自动连环跳歌，直接停下并提示。
/// - 试听（isSample）：进度到 sampleDuration 自动暂停，UI 进度上限截断。
class PlayerService extends ChangeNotifier {
  final PlayResolver resolver;
  final SettingsService settings;
  final LibraryService library;

  /// 下载服务（main 接线时注入）：起播时已下载完成的集优先播本地文件
  DownloadService? downloads;

  final AudioPlayer _player = AudioPlayer();
  final Random _random = Random();

  bool _playing = false;
  Duration _position = Duration.zero;
  Duration? _duration;

  List<Track> queue = [];
  int index = -1;
  PlayMode mode = PlayMode.loop;

  double _speed = 1.0;
  double get speed => _speed;

  /// 当前音质档位（0 标准 / 1 高清 / 2 臻品 / 3 无损）
  int get quality => settings.defaultQuality;

  String? errorMessage;

  /// 当前曲目的解析结果（试听标记等）
  PlayResult? currentResult;

  /// 试听已到上限（暂停在 sampleDuration 处）
  bool sampleEnded = false;

  final Set<int> _failed = {};
  final Map<String, PlayResult> _resolved = {};
  bool _busy = false;

  /// 续播进度节流落盘：播放中每 5 秒最多存一次
  DateTime _lastProgressSave = DateTime.fromMillisecondsSinceEpoch(0);
  static const _progressSaveInterval = Duration(seconds: 5);

  Timer? _sleepTimer;
  DateTime? _sleepAt;

  /// 定时关闭的触发时刻（null 表示未设置）
  DateTime? get sleepAt => _sleepAt;

  PlayerService(this.resolver, this.settings, this.library) {
    _player.onPlayerStateChanged.listen((state) {
      _playing = state == PlayerState.playing;
      // 暂停时立即落盘续播进度（播完走 onPlayerComplete 清除，不在这里存）
      if (state == PlayerState.paused) _saveProgressNow();
      notifyListeners();
    });
    _player.onPlayerComplete.listen((_) => _onCompleted());
    _player.onDurationChanged.listen((d) {
      _duration = d;
      notifyListeners();
    });
    _player.onPositionChanged.listen((pos) {
      _position = pos;
      // 试听上限：到点自动暂停
      final r = currentResult;
      if (_playing &&
          r != null &&
          r.isSample &&
          r.sampleDuration > 0 &&
          pos.inSeconds >= r.sampleDuration) {
        sampleEnded = true;
        _player.pause();
      }
      // 续播进度节流落盘
      final t = current;
      if (_playing && t != null && pos.inSeconds > 0) {
        final now = DateTime.now();
        if (now.difference(_lastProgressSave) >= _progressSaveInterval) {
          _lastProgressSave = now;
          unawaited(library.saveProgress(t.trackId, pos, total: _duration));
        }
      }
      notifyListeners();
    });
    _loadSpeed();
  }

  Future<void> _loadSpeed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final s = prefs.getDouble('play_speed') ?? 1.0;
      if (s >= 0.5 && s <= 3.0) {
        _speed = s;
        await _player.setPlaybackRate(s);
        notifyListeners();
      }
    } catch (_) {}
  }

  Track? get current =>
      (index >= 0 && index < queue.length) ? queue[index] : null;

  bool get hasQueue => queue.isNotEmpty;
  bool get playing => _playing;
  Duration get position => _position;
  Duration? get duration => _duration;

  /// 进度上限：试听时截断到 sampleDuration
  Duration? get effectiveDuration {
    final r = currentResult;
    if (r != null && r.isSample && r.sampleDuration > 0) {
      return Duration(seconds: r.sampleDuration);
    }
    return _duration;
  }

  bool get isSample => currentResult?.isSample ?? false;

  Stream<Duration> get positionStream => _player.onPositionChanged;

  String get modeLabel => switch (mode) {
    PlayMode.sequence => '顺序播放',
    PlayMode.loop => '列表循环',
    PlayMode.single => '单集循环',
    PlayMode.shuffle => '随机播放',
  };

  // ---------- 队列控制 ----------

  Future<void> playQueue(List<Track> tracks, int startIndex) async {
    if (tracks.isEmpty) return;
    queue = List.of(tracks);
    _failed.clear();
    await _playAt(startIndex.clamp(0, queue.length - 1));
  }

  Future<void> playTrack(Track t) => playQueue([t], 0);

  Future<void> jumpTo(int i) async {
    if (i < 0 || i >= queue.length) return;
    await _playAt(i);
  }

  void clearQueue() {
    _saveProgressNow();
    queue = [];
    index = -1;
    currentResult = null;
    _player.stop();
    notifyListeners();
  }

  /// 立即把当前曲目的播放位置落盘（暂停/切歌/退出时调用）。
  void _saveProgressNow() {
    final t = current;
    if (t == null || _position.inSeconds <= 0) return;
    _lastProgressSave = DateTime.now();
    unawaited(library.saveProgress(t.trackId, _position, total: _duration));
  }

  // ---------- 播放实现 ----------

  Future<void> _playAt(int i) async {
    if (queue.isEmpty || _busy) return;
    // 切歌前先把上一首的进度立即落盘
    final prevTrackId = current?.trackId;
    _saveProgressNow();
    _busy = true;
    errorMessage = null;
    sampleEnded = false;
    try {
      int n = i;
      int attempts = 0;
      while (attempts < queue.length) {
        final track = queue[n];
        if (_failed.contains(track.trackId)) {
          n = _nextIndex(n);
          attempts++;
          continue;
        }
        index = n;
        if (track.trackId != prevTrackId) {
          // 换了曲目：清掉上一首的时长/位置，避免界面与续播钳制用到旧值
          _duration = null;
          _position = Duration.zero;
        }
        notifyListeners();

        // 本地优先：已下载完成的集直接播本地文件（断网可播）
        final localPath = downloads?.localPathFor(track.trackId);
        if (localPath != null) {
          const localResult = PlayResult();
          currentResult = localResult;
          try {
            await _player.setPlaybackRate(_speed);
            await _player.play(DeviceFileSource(localPath));
            await _resumeSavedPosition(track, localResult);
            errorMessage = null;
            notifyListeners();
            library.addHistory(track);
            _prefetchNext(n);
            return;
          } catch (_) {
            // 本地文件损坏等：回落到下面的网络解析
          }
        }

        PlayResult result;
        try {
          result = await _resolveTrack(track);
        } on XmException catch (e) {
          _failed.add(track.trackId);
          errorMessage = '《${track.title}》$e';
          notifyListeners();
          n = _nextIndex(n);
          attempts++;
          continue;
        }

        if (result.url == null) {
          // 付费集等不可播：停下并明确提示，不连环跳歌
          currentResult = result;
          errorMessage = result.notice ?? '该集暂不能播放';
          await _player.stop();
          notifyListeners();
          return;
        }

        currentResult = result;
        try {
          await _player.setPlaybackRate(_speed);
          await _player.play(UrlSource(result.url!));
          await _resumeSavedPosition(track, result);
          errorMessage = null;
          notifyListeners();
          library.addHistory(track);
          _prefetchNext(n);
          return;
        } catch (e) {
          _failed.add(track.trackId);
          errorMessage = '《${track.title}》播放器加载失败：$e';
          notifyListeners();
        }
        n = _nextIndex(n);
        attempts++;
      }
      errorMessage = '队列中没有可播放的声音';
      notifyListeners();
    } finally {
      _busy = false;
    }
  }

  /// 续播：跳回上次保存的位置（开头 5 秒内、贴近结尾、试听已达
  /// 上限时不跳，避免刚播完的又被拉回去）
  Future<void> _resumeSavedPosition(Track track, PlayResult result) async {
    final saved = library.savedPosition(track.trackId);
    if (saved == null || saved.inSeconds <= 5) return;
    final beyondSample =
        result.isSample &&
        result.sampleDuration > 0 &&
        saved.inSeconds >= result.sampleDuration;
    final nearEnd =
        track.duration > 0 && saved.inSeconds >= track.duration - 10;
    if (beyondSample || nearEnd) return;
    await _player.seek(saved);
    _position = saved;
  }

  Future<PlayResult> _resolveTrack(Track track) async {
    final key = '${track.trackId}_$quality';
    final cached = _resolved[key];
    if (cached != null) return cached;
    final result = await resolver.resolve(track, quality: quality);
    _resolved[key] = result;
    return result;
  }

  void _prefetchNext(int currentIndex) {
    if (queue.isEmpty) return;
    final nextIdx = _nextIndex(currentIndex);
    if (nextIdx == currentIndex) return;
    final track = queue[nextIdx];
    if (_failed.contains(track.trackId)) return;
    _resolveTrack(track).catchError((_) => const PlayResult());
  }

  int _nextIndex(int from) {
    if (queue.isEmpty) return 0;
    if (mode == PlayMode.shuffle) return _random.nextInt(queue.length);
    final n = from + 1;
    return n >= queue.length ? 0 : n;
  }

  int _prevIndex(int from) {
    if (queue.isEmpty) return 0;
    if (mode == PlayMode.shuffle) return _random.nextInt(queue.length);
    final n = from - 1;
    return n < 0 ? queue.length - 1 : n;
  }

  Future<void> _onCompleted() async {
    // 播完清除该集的续播进度，下次从头播
    final done = current;
    if (done != null) unawaited(library.clearProgress(done.trackId));
    if (mode == PlayMode.single && current != null) {
      await _player.seek(Duration.zero);
      await _player.resume();
    } else if (mode == PlayMode.sequence &&
        index >= 0 &&
        index == queue.length - 1) {
      await _player.stop();
    } else {
      await next();
    }
  }

  // ---------- 播放控制 ----------

  Future<void> toggle() async {
    if (_playing) {
      await _player.pause();
    } else {
      if (sampleEnded) return; // 试听已结束，不允许继续
      if (index < 0 && queue.isNotEmpty) {
        await _playAt(0);
      } else {
        await _player.resume();
      }
    }
    notifyListeners();
  }

  Future<void> next() async {
    if (queue.isEmpty) return;
    await _playAt(_nextIndex(index));
  }

  Future<void> prev() async {
    if (queue.isEmpty) return;
    if (_position.inSeconds > 3) {
      await _player.seek(Duration.zero);
      return;
    }
    await _playAt(_prevIndex(index));
  }

  Future<void> seek(Duration position) async {
    final cap = effectiveDuration;
    if (cap != null && position > cap) position = cap;
    sampleEnded = false;
    await _player.seek(position);
  }

  Future<void> setVolume(double v) => _player.setVolume(v.clamp(0.0, 1.0));

  /// 倍速 0.5x ~ 3.0x，持久化。
  Future<void> setSpeed(double s) async {
    s = s.clamp(0.5, 3.0);
    _speed = s;
    await _player.setPlaybackRate(s);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('play_speed', s);
    } catch (_) {}
    notifyListeners();
  }

  /// 切换音质：持久化为默认音质，并对当前曲目按新档位重新解析续播。
  Future<void> setQuality(int level) async {
    if (level == quality) return;
    final track = current;
    final wasPlaying = _playing;
    final pos = _position;
    await settings.setDefaultQuality(level);
    // 当前曲目播的是本地下载文件：音质切换不影响本地播放
    if (track != null && downloads?.localPathFor(track.trackId) != null) {
      notifyListeners();
      return;
    }
    if (track == null) {
      notifyListeners();
      return;
    }
    try {
      final result = await _resolveTrack(track);
      currentResult = result;
      if (result.url != null) {
        await _player.play(UrlSource(result.url!));
        if (pos > Duration.zero) await _player.seek(pos);
        if (!wasPlaying) await _player.pause();
      }
    } on XmException catch (e) {
      errorMessage = '切换音质失败：${e.message}';
    }
    notifyListeners();
  }

  /// 定时关闭：到点暂停。传 null 取消。
  void setSleepTimer(Duration? duration) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepAt = null;
    if (duration != null && duration > Duration.zero) {
      _sleepAt = DateTime.now().add(duration);
      _sleepTimer = Timer(duration, () {
        _player.pause();
        _sleepAt = null;
        _sleepTimer = null;
        notifyListeners();
      });
    }
    notifyListeners();
  }

  void cycleMode() {
    mode = switch (mode) {
      PlayMode.sequence => PlayMode.loop,
      PlayMode.loop => PlayMode.single,
      PlayMode.single => PlayMode.shuffle,
      PlayMode.shuffle => PlayMode.sequence,
    };
    notifyListeners();
  }

  @override
  void dispose() {
    _saveProgressNow();
    _sleepTimer?.cancel();
    _player.dispose();
    super.dispose();
  }
}
