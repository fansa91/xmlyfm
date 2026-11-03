import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xmlyfm/models/models.dart';
import 'package:xmlyfm/services/library_service.dart';
import 'package:xmlyfm/services/settings_service.dart';

Track track(int id) => Track(trackId: id, albumId: 100, title: '声音$id');

AlbumInfo album(int id) => AlbumInfo(
      albumId: id,
      title: '专辑$id',
      nickname: '主播$id',
      cover: 'https://example.com/$id.jpg',
      intro: '',
      uid: 1,
      isPaid: false,
      isVipFree: false,
      categoryId: 0,
      categoryName: '',
      playTimes: 0,
    );

/// 模拟重启：新建一个实例从同一份 SharedPreferences 读回。
Future<LibraryService> reopenLibrary() async {
  final s = LibraryService();
  await s.init();
  return s;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('收藏专辑', () {
    test('收藏后重启恢复，取消收藏后落盘', () async {
      final lib = await reopenLibrary();
      await lib.toggleFavorite(album(7));
      expect(lib.isFavorite(7), isTrue);

      final lib2 = await reopenLibrary();
      expect(lib2.isFavorite(7), isTrue);
      expect(lib2.favorites.single.title, '专辑7');

      await lib2.toggleFavorite(album(7));
      final lib3 = await reopenLibrary();
      expect(lib3.isFavorite(7), isFalse);
    });
  });

  group('收藏声音', () {
    test('往返序列化：收藏重启后恢复且字段完整', () async {
      final lib = await reopenLibrary();
      await lib.toggleFavoriteTrack(track(42));
      expect(lib.isFavoriteTrack(42), isTrue);

      final lib2 = await reopenLibrary();
      expect(lib2.favoriteTracks.length, 1);
      expect(lib2.favoriteTracks.single.trackId, 42);
      expect(lib2.favoriteTracks.single.title, '声音42');
      expect(lib2.favoriteTracks.single.albumId, 100);
    });

    test('重复收藏同一声音只保留一条，再点取消', () async {
      final lib = await reopenLibrary();
      await lib.toggleFavoriteTrack(track(1));
      await lib.toggleFavoriteTrack(track(2));
      expect(lib.favoriteTracks.map((t) => t.trackId), [2, 1]);
      await lib.toggleFavoriteTrack(track(1));
      expect(lib.favoriteTracks.map((t) => t.trackId), [2]);
    });
  });

  group('播放历史', () {
    test('去重：同一声音重复播放只留一条且时间刷新', () async {
      final lib = await reopenLibrary();
      await lib.addHistory(track(5));
      final firstAt = lib.history.single.playedAt;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await lib.addHistory(track(5));
      expect(lib.history.length, 1);
      expect(lib.history.single.playedAt, greaterThanOrEqualTo(firstAt));
    });

    test('上限截断：超过 100 条保留最新 100 条', () async {
      final lib = await reopenLibrary();
      for (var i = 1; i <= 105; i++) {
        await lib.addHistory(track(i));
      }
      expect(lib.history.length, 100);
      expect(lib.history.first.track.trackId, 105);
      expect(lib.history.last.track.trackId, 6);
    });

    test('历史重启恢复 + 清空落盘', () async {
      final lib = await reopenLibrary();
      await lib.addHistory(track(9), albumTitle: '专辑9');
      final lib2 = await reopenLibrary();
      expect(lib2.history.single.track.trackId, 9);
      expect(lib2.history.single.albumTitle, '专辑9');

      await lib2.clearHistory();
      final lib3 = await reopenLibrary();
      expect(lib3.history, isEmpty);
    });
  });

  group('续播进度', () {
    test('保存后可读回，重启仍在', () async {
      final lib = await reopenLibrary();
      await lib.saveProgress(11, const Duration(seconds: 83),
          total: const Duration(seconds: 600));
      expect(lib.savedPosition(11), const Duration(seconds: 83));

      final lib2 = await reopenLibrary();
      expect(lib2.savedPosition(11), const Duration(seconds: 83));
    });

    test('位置为 0 或贴近结尾时视为无进度并清除旧记录', () async {
      final lib = await reopenLibrary();
      await lib.saveProgress(3, const Duration(seconds: 100),
          total: const Duration(seconds: 300));
      expect(lib.savedPosition(3), isNotNull);
      // 距结尾不足 5 秒 → 播完口径，清除
      await lib.saveProgress(3, const Duration(seconds: 297),
          total: const Duration(seconds: 300));
      expect(lib.savedPosition(3), isNull);

      await lib.saveProgress(4, const Duration(seconds: 50));
      await lib.saveProgress(4, Duration.zero);
      expect(lib.savedPosition(4), isNull);
    });

    test('更新同一声音只留最新一条', () async {
      final lib = await reopenLibrary();
      await lib.saveProgress(8, const Duration(seconds: 10));
      await lib.saveProgress(8, const Duration(seconds: 99));
      expect(lib.savedPosition(8), const Duration(seconds: 99));
    });

    test('clearProgress 清除指定声音', () async {
      final lib = await reopenLibrary();
      await lib.saveProgress(6, const Duration(seconds: 30));
      await lib.clearProgress(6);
      expect(lib.savedPosition(6), isNull);
      final lib2 = await reopenLibrary();
      expect(lib2.savedPosition(6), isNull);
    });

    test('上限 200 条：最旧的被淘汰', () async {
      final lib = await reopenLibrary();
      for (var i = 1; i <= 205; i++) {
        await lib.saveProgress(i, const Duration(seconds: 10));
      }
      expect(lib.savedPosition(1), isNull);
      expect(lib.savedPosition(5), isNull);
      expect(lib.savedPosition(6), const Duration(seconds: 10));
      expect(lib.savedPosition(205), const Duration(seconds: 10));
    });

    test('ProgressEntry JSON 往返', () {
      const e = ProgressEntry(
          trackId: 1, positionSec: 12, durationSec: 300, updatedAt: 999);
      final back = ProgressEntry.fromJson(e.toJson());
      expect(back.trackId, 1);
      expect(back.positionSec, 12);
      expect(back.durationSec, 300);
      expect(back.updatedAt, 999);
    });
  });

  group('设置持久化', () {
    test('音质 / baseInfo v4 / 主题模式改后重启恢复', () async {
      SharedPreferences.setMockInitialValues({});
      final s = SettingsService();
      await s.init();
      await s.setDefaultQuality(3);
      await s.setBaseInfoV4(true);
      await s.setPureBlack(true);

      final s2 = SettingsService();
      await s2.init();
      expect(s2.defaultQuality, 3);
      expect(s2.baseInfoV4, isTrue);
      expect(s2.pureBlack, isTrue);
    });
  });
}
