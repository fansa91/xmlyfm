import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xmlyfm/models/models.dart';
import 'package:xmlyfm/screens/category_screen.dart';
import 'package:xmlyfm/screens/ranking_screen.dart';
import 'package:xmlyfm/services/download_service.dart';
import 'package:xmlyfm/services/library_service.dart';
import 'package:xmlyfm/services/play_resolver.dart';
import 'package:xmlyfm/services/player_service.dart';
import 'package:xmlyfm/services/settings_service.dart';
import 'package:xmlyfm/services/ximalaya_service.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

/// 按 URL 子串路由的假 HTTP 适配器（与 category_meta_test 同款）
class FakeAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  final Map<String, String> bodies;

  FakeAdapter(this.bodies);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final url = options.uri.toString();
    const headers = {
      Headers.contentTypeHeader: ['application/json'],
    };
    for (final e in bodies.entries) {
      if (url.contains(e.key)) {
        return ResponseBody.fromString(e.value, 200, headers: headers);
      }
    }
    throw StateError('未预设的请求：$url');
  }

  @override
  void close({bool force = false}) {}

  RequestOptions lastTo(String part) =>
      requests.lastWhere((r) => r.uri.toString().contains(part));
}

XimalayaService serviceWith(FakeAdapter adapter) {
  final dio = Dio();
  dio.httpClientAdapter = adapter;
  return XimalayaService(dio: dio);
}

List<RankAggregate> catalogFixture() => RankAggregate.parseCatalog(
      jsonDecode(fixture('rank_agg_tabs.json')) as Map<String, dynamic>,
    );

void main() {
  group('聚合榜目录解析（文档 §2.9）', () {
    test('目录含专辑榜与主播榜，各榜按 categoryId 给出 rankingListId',
        () async {
      final adapter = FakeAdapter({
        'AggregateRankListTabs': fixture('rank_agg_tabs.json'),
      });
      final catalog = await serviceWith(adapter).fetchRankCatalog();
      expect(catalog.length, 4);
      final hot = catalog.firstWhere((a) => a.name == '热播榜');
      expect(hot.clusterType, 12);
      expect(hot.groupForCategory(3)?.rankingListId, 432);
      expect(hot.groupForCategory(3)?.displayName, '有声书');
      final anchor = catalog.firstWhere((a) => a.anchorOrNot);
      expect(anchor.name, '实力主播');
      expect(anchor.groups.length, 4);
      expect(anchor.groups.first.displayName, '有声书主播');
      expect(anchor.groups.first.rankingListId, 479);
    });

    test('tabsForCategory：只列该分类有的专辑榜 + 实力主播榜', () {
      final catalog = catalogFixture();
      final tabs = RankAggregate.tabsForCategory(catalog, 3);
      final names = tabs.map((t) => t.name).toList();
      expect(names, ['热播榜', '畅销榜', '新品榜', '实力主播']);
      final hot = tabs.firstWhere((t) => t.name == '热播榜');
      expect(hot.isAnchor, isFalse);
      expect(hot.rankingListId, 432);
      expect(hot.clusterType, 12);
      final anchor = tabs.firstWhere((t) => t.isAnchor);
      expect(anchor.anchorGroups.length, 4);
      // 热播榜的 rankGroups 里没有儿童（6），该分类就不出现热播榜
      final kidsNames =
          RankAggregate.tabsForCategory(catalog, 6).map((t) => t.name);
      expect(kidsNames, isNot(contains('热播榜')));
      expect(kidsNames, containsAll(['畅销榜', '新品榜', '实力主播']));
    });

    test('tabsForCategory：无任何专辑榜的分类只剩主播榜', () {
      final tabs = RankAggregate.tabsForCategory(catalogFixture(), 9999);
      expect(tabs.length, 1);
      expect(tabs.single.isAnchor, isTrue);
    });
  });

  group('榜单明细接口', () {
    test('fetchRankAlbums：参数带 rankingListId/clusterType，翻页用 pageId',
        () async {
      final adapter = FakeAdapter({
        'concreteRankList': fixture('rank_agg_concrete.json'),
      });
      final service = serviceWith(adapter);
      final page = await service.fetchRankAlbums(
        rankingListId: 432,
        clusterType: 12,
        pageId: 2,
      );
      expect(page.albums.length, 3);
      expect(page.albums.first.albumId, 22963309);
      expect(page.albums.first.nickname, '君颜讲故事');
      expect(page.albums.first.playsCounts, greaterThan(0));
      expect(page.hasMore, isTrue); // maxPageId=5
      final req = adapter.lastTo('concreteRankList');
      expect(req.uri.queryParameters['rankingListId'], '432');
      expect(req.uri.queryParameters['clusterType'], '12');
      expect(req.uri.queryParameters['pageId'], '2');
      await service.fetchRankAlbums(rankingListId: 432, clusterType: 12);
      final first = adapter.lastTo('concreteRankList');
      expect(first.uri.queryParameters.containsKey('pageId'), isFalse);
    });

    test('fetchRankAnchors：解析主播条目与分组明细参数', () async {
      final adapter = FakeAdapter({
        'anchorRankList': fixture('rank_agg_anchor.json'),
      });
      final service = serviceWith(adapter);
      final page = await service.fetchRankAnchors(rankingListId: 479);
      expect(page.anchors.length, 3);
      expect(page.anchors.first.nickname, '有声的紫襟');
      expect(page.anchors.first.followersCounts, 27565209);
      expect(page.anchors.first.tracksCounts, 115016);
      expect(page.anchors.first.describe, contains('平台签约主播'));
      final req = adapter.lastTo('anchorRankList');
      expect(req.uri.queryParameters['rankingListId'], '479');
    });

    test('ret 非 0 抛 XmException', () async {
      final adapter = FakeAdapter({
        'AggregateRankListTabs': jsonEncode({'ret': 1, 'msg': '参数错误'}),
      });
      await expectLater(
        serviceWith(adapter).fetchRankCatalog(),
        throwsA(isA<XmException>()),
      );
    });
  });

  group('排行榜页与分类入口', () {
    late SettingsService settings;
    late LibraryService library;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      settings = SettingsService();
      await settings.init();
      library = LibraryService();
      await library.init();
    });

    Future<void> pumpPumps(WidgetTester tester) async {
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('排行榜页：专辑榜带名次，切到主播榜出分组与主播',
        (tester) async {
      final adapter = FakeAdapter({
        'concreteRankList': fixture('rank_agg_concrete.json'),
        'anchorRankList': fixture('rank_agg_anchor.json'),
      });
      final service = serviceWith(adapter);
      final tabs = RankAggregate.tabsForCategory(catalogFixture(), 3);
      final resolver = PlayResolver(service);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: settings),
            ChangeNotifierProvider.value(value: library),
            ChangeNotifierProvider.value(
              value: DownloadService(resolver, settings),
            ),
            Provider<XimalayaService>.value(value: service),
            Provider.value(value: resolver),
            ChangeNotifierProvider.value(
              value: PlayerService(resolver, settings, library),
            ),
          ],
          child: MaterialApp(
            home: RankingScreen(
              categoryId: 3,
              categoryName: '小说',
              tabs: tabs,
            ),
          ),
        ),
      );
      await pumpPumps(tester);
      // 页签：该分类有的榜 + 主播榜
      expect(find.text('热播榜'), findsOneWidget);
      expect(find.text('畅销榜'), findsOneWidget);
      expect(find.text('实力主播'), findsOneWidget);
      // 专辑榜首条带名次 1 与标题
      expect(find.text('1'), findsWidgets);
      expect(find.textContaining('重生八零'), findsWidgets);
      // 切到实力主播：分组 chips 与主播条目出现
      await tester.tap(find.text('实力主播'));
      await pumpPumps(tester);
      expect(find.text('有声书主播'), findsOneWidget);
      expect(find.text('直播红人'), findsOneWidget);
      expect(find.text('有声的紫襟'), findsOneWidget);
      expect(find.textContaining('粉丝'), findsWidgets);
    });

    testWidgets('分类页：目录里有榜时出现「排行榜」入口', (tester) async {
      final adapter = FakeAdapter({
        'customCategories': fixture('home_customCategories.json'),
        'tab/list': fixture('home_tab_list.json'),
        'queryCategoryPageData': fixture('home_categoryPage.json'),
        'AggregateRankListTabs': fixture('rank_agg_tabs.json'),
      });
      final service = serviceWith(adapter);
      await tester.pumpWidget(
        Provider<XimalayaService>.value(
          value: service,
          child: const MaterialApp(home: CategoryScreen()),
        ),
      );
      await pumpPumps(tester);
      // 入口是 ActionChip（落地页标签里也有个同名「排行榜」文本，用类型区分）
      expect(find.widgetWithText(ActionChip, '排行榜'), findsOneWidget);
    });
  });
}
