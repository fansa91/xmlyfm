import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// 本地收藏的专辑（简版，只存展示与跳转需要的字段）
class FavoriteAlbum {
  final int albumId;
  final String title;
  final String nickname;
  final String cover;
  final bool isPaid;

  const FavoriteAlbum({
    required this.albumId,
    required this.title,
    required this.nickname,
    required this.cover,
    required this.isPaid,
  });

  factory FavoriteAlbum.fromAlbum(AlbumInfo a) => FavoriteAlbum(
        albumId: a.albumId,
        title: a.title,
        nickname: a.nickname,
        cover: a.cover,
        isPaid: a.isPaid,
      );

  factory FavoriteAlbum.fromJson(Map<String, dynamic> json) => FavoriteAlbum(
        albumId: json['albumId'] as int? ?? 0,
        title: json['title'] as String? ?? '',
        nickname: json['nickname'] as String? ?? '',
        cover: json['coverLarge'] as String? ?? '',
        isPaid: json['isPaid'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'albumId': albumId,
        'title': title,
        'nickname': nickname,
        'coverLarge': cover,
        'isPaid': isPaid,
      };
}

/// 一条播放历史
class HistoryEntry {
  final Track track;
  final String albumTitle;
  final int playedAt; // ms epoch

  const HistoryEntry({
    required this.track,
    required this.albumTitle,
    required this.playedAt,
  });

  Map<String, dynamic> toJson() => {
        'track': track.toJson(),
        'albumTitle': albumTitle,
        'playedAt': playedAt,
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
        track: Track.fromJson(
            Map<String, dynamic>.from(json['track'] as Map? ?? const {})),
        albumTitle: json['albumTitle'] as String? ?? '',
        playedAt: json['playedAt'] as int? ?? 0,
      );
}

/// 一条续播进度（每条声音最近一次的播放位置）
class ProgressEntry {
  final int trackId;
  final int positionSec;
  final int durationSec; // 0 表示未知
  final int updatedAt; // ms epoch

  const ProgressEntry({
    required this.trackId,
    required this.positionSec,
    required this.durationSec,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'trackId': trackId,
        'positionSec': positionSec,
        'durationSec': durationSec,
        'updatedAt': updatedAt,
      };

  factory ProgressEntry.fromJson(Map<String, dynamic> json) => ProgressEntry(
        trackId: json['trackId'] as int? ?? 0,
        positionSec: json['positionSec'] as int? ?? 0,
        durationSec: json['durationSec'] as int? ?? 0,
        updatedAt: json['updatedAt'] as int? ?? 0,
      );
}

/// 本地收藏（专辑 + 声音）+ 播放历史 + 续播进度
/// （SharedPreferences JSON 存储，无云端同步）。
class LibraryService extends ChangeNotifier {
  static const _keyFavorites = 'fav_albums';
  static const _keyFavTracks = 'fav_tracks';
  static const _keyHistory = 'play_history';
  static const _keyProgress = 'play_progress';
  static const _maxHistory = 100;
  static const _maxProgress = 200;

  late SharedPreferences _prefs;
  List<FavoriteAlbum> _favorites = [];
  List<Track> _favoriteTracks = [];
  List<HistoryEntry> _history = [];

  /// 续播进度表（最近更新在前，超出上限淘汰尾部最旧的）
  List<ProgressEntry> _progress = [];

  List<FavoriteAlbum> get favorites => List.unmodifiable(_favorites);
  List<Track> get favoriteTracks => List.unmodifiable(_favoriteTracks);
  List<HistoryEntry> get history => List.unmodifiable(_history);

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _favorites = _decodeList(_prefs.getString(_keyFavorites))
        .map(FavoriteAlbum.fromJson)
        .where((a) => a.albumId > 0)
        .toList();
    _favoriteTracks = _decodeList(_prefs.getString(_keyFavTracks))
        .map(Track.fromJson)
        .where((t) => t.trackId > 0)
        .toList();
    _history = _decodeList(_prefs.getString(_keyHistory))
        .map(HistoryEntry.fromJson)
        .where((h) => h.track.trackId > 0)
        .toList();
    _progress = _decodeList(_prefs.getString(_keyProgress))
        .map(ProgressEntry.fromJson)
        .where((e) => e.trackId > 0 && e.positionSec > 0)
        .toList();
  }

  List<Map<String, dynamic>> _decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  bool isFavorite(int albumId) => _favorites.any((a) => a.albumId == albumId);

  Future<void> toggleFavorite(AlbumInfo album) async {
    if (isFavorite(album.albumId)) {
      _favorites = _favorites.where((a) => a.albumId != album.albumId).toList();
    } else {
      _favorites = [FavoriteAlbum.fromAlbum(album), ..._favorites];
    }
    await _prefs.setString(
        _keyFavorites, jsonEncode(_favorites.map((e) => e.toJson()).toList()));
    notifyListeners();
  }

  Future<void> addHistory(Track track, {String albumTitle = ''}) async {
    final entry = HistoryEntry(
      track: track,
      albumTitle: albumTitle,
      playedAt: DateTime.now().millisecondsSinceEpoch,
    );
    _history = [
      entry,
      ..._history.where((h) => h.track.trackId != track.trackId),
    ];
    if (_history.length > _maxHistory) {
      _history = _history.sublist(0, _maxHistory);
    }
    await _prefs.setString(
        _keyHistory, jsonEncode(_history.map((e) => e.toJson()).toList()));
    notifyListeners();
  }

  Future<void> clearHistory() async {
    _history = [];
    await _prefs.remove(_keyHistory);
    notifyListeners();
  }

  // ---------- 收藏声音 ----------

  bool isFavoriteTrack(int trackId) =>
      _favoriteTracks.any((t) => t.trackId == trackId);

  Future<void> toggleFavoriteTrack(Track track) async {
    if (isFavoriteTrack(track.trackId)) {
      _favoriteTracks =
          _favoriteTracks.where((t) => t.trackId != track.trackId).toList();
    } else {
      _favoriteTracks = [track, ..._favoriteTracks];
    }
    await _prefs.setString(_keyFavTracks,
        jsonEncode(_favoriteTracks.map((e) => e.toJson()).toList()));
    notifyListeners();
  }

  // ---------- 续播进度 ----------

  /// 某条声音上次保存的续播位置；没有记录或已播完返回 null。
  Duration? savedPosition(int trackId) {
    for (final e in _progress) {
      if (e.trackId == trackId) {
        return e.positionSec > 0 ? Duration(seconds: e.positionSec) : null;
      }
    }
    return null;
  }

  /// 保存续播位置。position <= 0 或已到结尾（距总时长不足 5 秒）视为
  /// 无需续播，改为清除记录。不 notifyListeners：进度不在任何界面展示，
  /// 高频落盘时避免无谓重建。
  Future<void> saveProgress(int trackId, Duration position,
      {Duration? total}) async {
    final posSec = position.inSeconds;
    final totalSec = total?.inSeconds ?? 0;
    final finished = totalSec > 0 && posSec >= totalSec - 5;
    if (posSec <= 0 || finished) {
      await clearProgress(trackId);
      return;
    }
    final entry = ProgressEntry(
      trackId: trackId,
      positionSec: posSec,
      durationSec: totalSec,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    _progress = [
      entry,
      ..._progress.where((e) => e.trackId != trackId),
    ];
    if (_progress.length > _maxProgress) {
      _progress = _progress.sublist(0, _maxProgress);
    }
    await _prefs.setString(_keyProgress,
        jsonEncode(_progress.map((e) => e.toJson()).toList()));
  }

  Future<void> clearProgress(int trackId) async {
    if (!_progress.any((e) => e.trackId == trackId)) return;
    _progress = _progress.where((e) => e.trackId != trackId).toList();
    await _prefs.setString(_keyProgress,
        jsonEncode(_progress.map((e) => e.toJson()).toList()));
  }
}
