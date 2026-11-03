import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:xmlyfm/models/models.dart';
import 'package:xmlyfm/screens/home_screen.dart';
import 'package:xmlyfm/services/ximalaya_service.dart';
import 'package:xmlyfm/widgets/home_sections.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

/// 按 URL 子串路由的假 HTTP 适配器（与 category_rank_test 同款）
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

List<HomeTab> homeTabsFixture() => HomeTab.parseHomeTabs(
      jsonDecode(fixture('home_customCategories.json'))
          as Map<String, dynamic>,
    );

List<RankAggregate> catalogFixture() => RankAggregate.parseCatalog(
      jsonDecode(fixture('rank_agg_tabs.json')) as Map<String, dynamic>,
    );

void main() {
  group('金刚区数据筛选（文档 §2.9）', () {
    test('只取 template_category 分类页签，排除推荐/H5/同城/播客等', () {
      final grid = HomeTab.gridCategories(homeTabsFixture(), limit: 50);
      expect(grid.length, 20);
      expect(grid.every((t) => t.itemType == 'template_category'), isTrue);
      expect(grid.map((t) => t.title), isNot(contains('推荐')));
      expect(grid.map((t) => t.title), isNot(contains('播客')));
      expect(grid.map((t) => t.title), isNot(contains('东莞')));
    });

    test('默认截前 7 个、保序、按 categoryId 去重', () {
      final grid = HomeTab.gridCategories(homeTabsFixture());
      expect(
        grid.map((t) => t.title).toList(),
        ['小说', '儿童', '资讯', '图书', '相声评书', '人文国学', '大师课'],
      );
      expect(grid.map((t) => t.categoryId).toSet().length, grid.length);
      final dup = [
        ...homeTabsFixture(),
        ...homeTabsFixture(),
      ];
      expect(HomeTab.gridCategories(dup, limit: 50).length, 20);
    });

    test('分类名图标映射：命中关键词与兜底', () {
      expect(iconForCategoryName('小说'), Icons.auto_stories);
      expect(iconForCategoryName('儿童故事'), Icons.child_care);
      expect(iconForCategoryName('相声评书'), Icons.theater_comedy);
      expect(iconForCategoryName('音乐'), Icons.music_note);
      expect(iconForCategoryName('不存在的分类'), Icons.category);
    });
  });

  group('全站榜单页签与热播预览', () {
    test('tabsForSite：全站组各榜 + 实力主播，热播榜取全站 rankingListId',
        () {
      final catalog = catalogFixture();
      final tabs = RankAggregate.tabsForSite(catalog);
      expect(
        tabs.map((t) => t.name),
        containsAll(['热播榜', '畅销榜', '新品榜', '实力主播']),
      );
      final hot = RankAggregate.siteHotTab(catalog);
      expect(hot, isNotNull);
      expect(hot!.rankingListId, 431); // 全站热播，与分类 3 的 432 不同
      expect(hot.clusterType, 12);
      expect(hot.isAnchor, isFalse);
    });

    test('排行榜预览取数链：目录 → 热播页签 → 明细前三', () async {
      final adapter = FakeAdapter({
        'AggregateRankListTabs': fixture('rank_agg_tabs.json'),
        'concreteRankList': fixture('rank_agg_concrete.json'),
      });
      final service = serviceWith(adapter);
      final catalog = await service.fetchRankCatalog();
      final hot = RankAggregate.siteHotTab(catalog)!;
      final page = await service.fetchRankAlbums(
        rankingListId: hot.rankingListId,
        clusterType: hot.clusterType,
      );
      final preview = page.albums.take(3).toList();
      expect(preview.length, 3);
      expect(preview.first.title, contains('重生八零'));
      expect(preview.first.playsCounts, greaterThan(0));
      final req = adapter.lastTo('concreteRankList');
      expect(req.queryParameters['rankingListId'], '431');
      expect(req.queryParameters['clusterType'], '12');
    });
  });

  group('板块组件渲染', () {
    testWidgets('金刚区：7 个分类 + 更多，点击回调带对分类', (tester) async {
      final grid = HomeTab.gridCategories(homeTabsFixture());
      HomeTab? tapped;
      var moreTapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CategoryGrid(
              categories: grid,
              crossAxisCount: 4,
              onCategoryTap: (t) => tapped = t,
              onMoreTap: () => moreTapped = true,
            ),
          ),
        ),
      );
      for (final name in ['小说', '儿童', '资讯', '图书', '相声评书', '人文国学', '大师课', '更多']) {
        expect(find.text(name), findsOneWidget, reason: name);
      }
      await tester.tap(find.text('儿童'));
      expect(tapped?.categoryId, 6);
      await tester.tap(find.text('更多'));
      expect(moreTapped, isTrue);
    });

    testWidgets('排行榜预览卡：前三行 + 更多回调', (tester) async {
      final page = RankAlbumsPage.fromJson(
        jsonDecode(fixture('rank_agg_concrete.json'))
            as Map<String, dynamic>,
        pageId: 1,
      );
      var moreTapped = false;
      RankAlbum? albumTapped;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RankPreviewCard(
              albums: page.albums.take(3).toList(),
              onMore: () => moreTapped = true,
              onAlbumTap: (a) => albumTapped = a,
            ),
          ),
        ),
      );
      expect(find.text('排行榜'), findsOneWidget);
      expect(find.textContaining('重生八零'), findsOneWidget);
      expect(find.textContaining('一剑独尊'), findsOneWidget);
      expect(find.textContaining('都市奇门医圣'), findsOneWidget);
      await tester.tap(find.textContaining('一剑独尊'));
      expect(albumTapped?.title, contains('一剑独尊'));
      await tester.tap(find.text('更多'));
      expect(moreTapped, isTrue);
    });
  });

  group('首页集成', () {
    testWidgets('推荐页签顶部出现金刚区与排行榜卡，推荐流在下', (tester) async {
      final adapter = FakeAdapter({
        'customCategories': fixture('home_customCategories.json'),
        'v4/mix': fixture('home_feed_v4mix.json'),
        'AggregateRankListTabs': fixture('rank_agg_tabs.json'),
        'concreteRankList': fixture('rank_agg_concrete.json'),
      });
      await tester.pumpWidget(
        Provider<XimalayaService>.value(
          value: serviceWith(adapter),
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      // 等页签/推荐流/榜单三段异步加载完成（不用 pumpAndSettle：
      // 封面占位有转圈动画，与 category_filter_widget_test 同口径）
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find.text('排行榜').evaluate().isNotEmpty) break;
      }
      // 金刚区（页签条里也有同名 chip，用 findsWidgets 容忍重复）
      expect(find.text('大师课'), findsWidgets);
      // 「更多」出现两处：金刚区格子 + 排行榜卡右上
      expect(find.text('更多'), findsNWidgets(2));
      // 排行榜卡与预览第一名
      expect(find.text('排行榜'), findsOneWidget);
      expect(find.textContaining('重生八零'), findsOneWidget);
      // 推荐流首条仍在
      expect(find.textContaining('谁与争锋'), findsOneWidget);
    });
  });
}
