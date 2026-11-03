import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xmlyfm/core/responsive.dart';
import 'package:xmlyfm/main.dart';
import 'package:xmlyfm/models/models.dart';
import 'package:xmlyfm/services/download_service.dart';
import 'package:xmlyfm/services/library_service.dart';
import 'package:xmlyfm/services/play_resolver.dart';
import 'package:xmlyfm/services/player_service.dart';
import 'package:xmlyfm/services/settings_service.dart';
import 'package:xmlyfm/services/ximalaya_service.dart';

/// 假数据服务：所有接口返回空数据，不走网络。
class FakeXimalayaService extends XimalayaService {
  @override
  Future<List<HomeTab>> fetchHomeTabs() async => const [];

  @override
  Future<FeedPage> fetchFeed({int pageNum = 1, int streamOffSet = 0}) async =>
      const FeedPage(items: [], offset: 0);

  @override
  Future<List<CategoryTab>> fetchCategoryTabs(int categoryId) async =>
      const [];

  @override
  Future<CategoryPageData> fetchCategoryPage(int categoryId) async =>
      const CategoryPageData(albums: [], tags: []);

  @override
  Future<List<String>> fetchHotWords() async => const [];

  @override
  Future<List<BillboardCategory>> fetchBillboardCategories() async =>
      const [];

  @override
  Future<List<BillboardItem>> fetchBillboardList(String categoryId) async =>
      const [];
}

void main() {
  group('断点判定', () {
    Future<WindowClass> probeClass(WidgetTester tester, double width) async {
      late WindowClass result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              result = windowClassOf(context);
              return const SizedBox();
            },
          ),
        ),
      );
      // pumpWidget 之后再改尺寸并重泵，确保 MediaQuery 已按目标宽度计算
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              result = windowClassOf(context);
              return const SizedBox();
            },
          ),
        ),
      );
      return result;
    }

    testWidgets('599 → compact，600/899 → medium，900 → expanded', (
      tester,
    ) async {
      expect(await probeClass(tester, 599), WindowClass.compact);
      expect(await probeClass(tester, 600), WindowClass.medium);
      expect(await probeClass(tester, 899), WindowClass.medium);
      expect(await probeClass(tester, 900), WindowClass.expanded);
      expect(await probeClass(tester, 1440), WindowClass.expanded);
    });
  });

  group('AppShell 导航形态', () {
    late SettingsService settings;
    late LibraryService library;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      settings = SettingsService();
      await settings.init();
      library = LibraryService();
      await library.init();
    });

    Future<void> pumpShell(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final XimalayaService service = FakeXimalayaService();
      final resolver = PlayResolver(service);
      final downloads = DownloadService(resolver, settings);
      final player = PlayerService(resolver, settings, library);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: settings),
            ChangeNotifierProvider.value(value: library),
            ChangeNotifierProvider.value(value: downloads),
            Provider.value(value: service),
            Provider.value(value: resolver),
            ChangeNotifierProvider.value(value: player),
          ],
          child: const MaterialApp(home: AppShell()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('宽屏（1400）：NavigationRail 出现、无底部 NavigationBar', (
      tester,
    ) async {
      await pumpShell(tester, const Size(1400, 900));
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      // 四个目的地标签都在
      for (final label in ['首页', '分类', '搜索', '我的']) {
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets('中等（700）：同样是 NavigationRail', (tester) async {
      await pumpShell(tester, const Size(700, 900));
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('紧凑（400）：底部 NavigationBar、无 NavigationRail', (
      tester,
    ) async {
      await pumpShell(tester, const Size(400, 800));
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      for (final label in ['首页', '分类', '搜索', '我的']) {
        expect(find.text(label), findsOneWidget);
      }
    });
  });
}
