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

/// 本地收藏 + 播放历史（SharedPreferences JSON 存储，无云端同步）。
class LibraryService extends ChangeNotifier {
  static const _keyFavorites = 'fav_albums';
  static const _keyHistory = 'play_history';
  static const _maxHistory = 100;

  late SharedPreferences _prefs;
  List<FavoriteAlbum> _favorites = [];
  List<HistoryEntry> _history = [];

  List<FavoriteAlbum> get favorites => List.unmodifiable(_favorites);
  List<HistoryEntry> get history => List.unmodifiable(_history);

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _favorites = _decodeList(_prefs.getString(_keyFavorites))
        .map(FavoriteAlbum.fromJson)
        .where((a) => a.albumId > 0)
        .toList();
    _history = _decodeList(_prefs.getString(_keyHistory))
        .map(HistoryEntry.fromJson)
        .where((h) => h.track.trackId > 0)
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
}
