import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/responsive.dart';
import 'core/theme.dart';
import 'screens/category_screen.dart';
import 'screens/downloads_screen.dart';
import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'screens/player_screen.dart';
import 'screens/search_screen.dart';
import 'screens/settings_screen.dart';
import 'services/download_service.dart';
import 'services/library_service.dart';
import 'services/play_resolver.dart';
import 'services/player_service.dart';
import 'services/settings_service.dart';
import 'services/ximalaya_service.dart';
import 'widgets/mini_player.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = SettingsService();
  await settings.init();
  final library = LibraryService();
  await library.init();
  final service = XimalayaService(deviceId: settings.deviceId);
  final resolver = PlayResolver(service);
  final downloads = DownloadService(resolver, settings);
  await downloads.init();
  runApp(
    XmlyFmApp(
      settings: settings,
      library: library,
      service: service,
      resolver: resolver,
      downloads: downloads,
    ),
  );
}

class XmlyFmApp extends StatelessWidget {
  final SettingsService settings;
  final LibraryService library;
  final XimalayaService service;
  final PlayResolver resolver;
  final DownloadService downloads;

  const XmlyFmApp({
    super.key,
    required this.settings,
    required this.library,
    required this.service,
    required this.resolver,
    required this.downloads,
  });

  PlayerService _newPlayer() {
    final player = PlayerService(resolver, settings, library);
    player.downloads = downloads;
    return player;
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: library),
        ChangeNotifierProvider.value(value: downloads),
        Provider.value(value: service),
        Provider.value(value: resolver),
        ChangeNotifierProxyProvider3<
          PlayResolver,
          SettingsService,
          LibraryService,
          PlayerService
        >(
          create: (_) => _newPlayer(),
          update: (_, _, st, _, player) {
            // 同步 baseInfo v4 开关到解析器
            resolver.useBaseInfoV4 = st.baseInfoV4;
            return player ?? _newPlayer();
          },
        ),
      ],
      child: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          return MaterialApp(
            title: 'xmlyfm',
            debugShowCheckedModeBanner: false,
            theme: buildTheme(
              brightness: Brightness.light,
              seedColor: settings.effectiveSeedColor,
            ),
            darkTheme: buildTheme(
              brightness: Brightness.dark,
              seedColor: settings.effectiveSeedColor,
              pureBlack: settings.pureBlack,
            ),
            themeMode: settings.themeMode,
            home: const AppShell(),
            routes: {
              '/player': (_) => const PlayerScreen(),
              '/settings': (_) => const SettingsScreen(),
            },
          );
        },
      ),
    );
  }
}

/// 主框架：导航（首页 / 分类 / 搜索 / 下载 / 我的）+ 迷你播放器。
/// 紧凑档（<600）底部 NavigationBar；中 / 宽屏档左侧 NavigationRail，
/// 迷你播放条横贯窗口底部通栏。
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;

  final _pages = const [
    HomeScreen(),
    CategoryScreen(),
    SearchScreen(),
    DownloadsScreen(embedded: true),
    LibraryScreen(),
  ];

  static const _railDestinations = [
    (icon: Icons.home_outlined, selectedIcon: Icons.home, label: '首页'),
    (icon: Icons.category_outlined, selectedIcon: Icons.category, label: '分类'),
    (icon: Icons.search, selectedIcon: Icons.search, label: '搜索'),
    (icon: Icons.download_outlined, selectedIcon: Icons.download, label: '下载'),
    (icon: Icons.person_outline, selectedIcon: Icons.person, label: '我的'),
  ];

  @override
  Widget build(BuildContext context) {
    if (isWide(context)) {
      // 中 / 宽屏：左侧 NavigationRail + 右侧内容，迷你播放条底部通栏
      return Scaffold(
        body: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  NavigationRail(
                    leading: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.asset(
                          'assets/icon.png',
                          width: 40,
                          height: 40,
                        ),
                      ),
                    ),
                    selectedIndex: _currentIndex,
                    onDestinationSelected: (i) =>
                        setState(() => _currentIndex = i),
                    labelType: NavigationRailLabelType.all,
                    destinations: [
                      for (final d in _railDestinations)
                        NavigationRailDestination(
                          icon: Icon(d.icon),
                          selectedIcon: Icon(d.selectedIcon),
                          label: Text(d.label),
                        ),
                    ],
                  ),
                  const VerticalDivider(thickness: 1, width: 1),
                  Expanded(
                    child: IndexedStack(index: _currentIndex, children: _pages),
                  ),
                ],
              ),
            ),
            const MiniPlayer(),
          ],
        ),
      );
    }
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: IndexedStack(index: _currentIndex, children: _pages),
          ),
          const MiniPlayer(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.category_outlined),
            selectedIcon: Icon(Icons.category),
            label: '分类',
          ),
          NavigationDestination(icon: Icon(Icons.search), label: '搜索'),
          NavigationDestination(
            icon: Icon(Icons.download_outlined),
            selectedIcon: Icon(Icons.download),
            label: '下载',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
