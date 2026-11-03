import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xmlyfm/models/models.dart';
import 'package:xmlyfm/screens/album_screen.dart';
import 'package:xmlyfm/services/download_service.dart';
import 'package:xmlyfm/services/library_service.dart';
import 'package:xmlyfm/services/play_resolver.dart';
import 'package:xmlyfm/services/player_service.dart';
import 'package:xmlyfm/services/settings_service.dart';
import 'package:xmlyfm/services/ximalaya_service.dart';

CategoryAlbum _ca(int id, {String? title}) => CategoryAlbum(
  albumId: id,
  title: title ?? '专辑$id',
  cover: '',
  nickname: '主播$id',
);

/// 假数据服务：专辑 42（分类 3），同分类含自身 + 两本相关专辑，不走网络。
class FakeAlbumService extends XimalayaService {
  @override
  Future<AlbumTracksPage> fetchAlbumTracks(
    int albumId, {
    bool asc = true,
    int page = 1,
    int count = 20,
  }) async {
    return AlbumTracksPage(
      album: AlbumInfo(
        albumId: albumId,
        title: '测试专辑',
        nickname: '测试主播',
        cover: '',
        intro: '简介摘要',
        fullIntro: '这是完整简介的正文内容。',
        uid: 7,
        isPaid: false,
        isVipFree: false,
        categoryId: 3,
        categoryName: '小说',
        playTimes: 123456,
      ),
      tracks: [
        Track(trackId: 101, albumId: albumId, title: '第一集', duration: 600),
        Track(trackId: 102, albumId: albumId, title: '第二集', duration: 700),
      ],
      pageId: 1,
      maxPageId: 1,
      totalCount: 2,
    );
  }

  @override
  Future<CategoryPageData> fetchCategoryPage(int categoryId) async {
    return CategoryPageData(
      albums: [
        _ca(42, title: '测试专辑'),
        _ca(43, title: '相关专辑甲'),
        _ca(44, title: '相关专辑乙'),
      ],
      tags: const [],
    );
  }
}

void main() {
  group('pickRelatedAlbums 相关推荐选片', () {
    test('排除当前专辑、保序', () {
      final data = CategoryPageData(
        albums: [_ca(42), _ca(43), _ca(44)],
        tags: const [],
      );
      final picked = pickRelatedAlbums(data, currentAlbumId: 42);
      expect(picked.map((a) => a.albumId), [43, 44]);
    });

    test('默认上限 6 个，limit 可指定', () {
      final data = CategoryPageData(
        albums: [for (var i = 1; i <= 10; i++) _ca(i)],
        tags: const [],
      );
      expect(pickRelatedAlbums(data, currentAlbumId: 99).length, 6);
      expect(
        pickRelatedAlbums(data, currentAlbumId: 99, limit: 2).map(
          (a) => a.albumId,
        ),
        [1, 2],
      );
    });

    test('跳过 albumId 非正数的条目', () {
      final data = CategoryPageData(
        albums: [_ca(0), _ca(-1), _ca(5)],
        tags: const [],
      );
      expect(
        pickRelatedAlbums(data, currentAlbumId: 42).map((a) => a.albumId),
        [5],
      );
    });

    test('只有当前专辑时为空', () {
      final data = CategoryPageData(albums: [_ca(42)], tags: const []);
      expect(pickRelatedAlbums(data, currentAlbumId: 42), isEmpty);
    });
  });

  group('专辑页宽屏横幅布局', () {
    late SettingsService settings;
    late LibraryService library;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      settings = SettingsService();
      await settings.init();
      library = LibraryService();
      await library.init();
    });

    Future<void> pumpAlbum(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final XimalayaService service = FakeAlbumService();
      final resolver = PlayResolver(service);
      final downloads = DownloadService(resolver, settings);
      final player = PlayerService(resolver, settings, library);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: settings),
            ChangeNotifierProvider.value(value: library),
            ChangeNotifierProvider.value(value: downloads),
            Provider<XimalayaService>.value(value: service),
            Provider.value(value: resolver),
            ChangeNotifierProvider.value(value: player),
          ],
          child: const MaterialApp(home: AlbumScreen(albumId: 42)),
        ),
      );
      // 等首屏与相关推荐两段异步加载完成
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('宽屏（1400）：横幅 + 右栏三卡 + 相关推荐排除自身', (tester) async {
      await pumpAlbum(tester, const Size(1400, 900));
      // 横幅：标题只出现一次（顶栏不再重复），操作行在场
      expect(find.text('测试专辑'), findsOneWidget);
      expect(find.text('播放全部'), findsOneWidget);
      expect(find.text('测试主播 · 小说'), findsOneWidget);
      // 右栏三卡
      expect(find.text('专辑简介'), findsOneWidget);
      expect(find.text('主播'), findsOneWidget);
      expect(find.text('相关推荐'), findsOneWidget);
      expect(find.text('相关专辑甲'), findsOneWidget);
      expect(find.text('相关专辑乙'), findsOneWidget);
      // 左栏节目列表
      expect(find.text('第一集'), findsOneWidget);
      expect(find.text('第二集'), findsOneWidget);
    });

    testWidgets('紧凑（400）：无横幅右栏与相关推荐，移动布局照旧', (tester) async {
      await pumpAlbum(tester, const Size(400, 800));
      expect(find.text('相关推荐'), findsNothing);
      expect(find.text('相关专辑甲'), findsNothing);
      expect(find.text('播放全部'), findsOneWidget);
      expect(find.text('第一集'), findsOneWidget);
    });
  });
}
