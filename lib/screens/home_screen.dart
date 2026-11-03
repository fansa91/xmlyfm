import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/responsive.dart';
import '../models/models.dart';
import '../services/ximalaya_service.dart';
import '../widgets/album_card.dart';
import 'album_screen.dart';
import 'category_screen.dart';

/// 首页（发现）：顶部页签（customCategories）+ 推荐流（v4/mix）。
/// 推荐页签显示信息流；分类页签点击进入分类页。
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<HomeTab> _tabs = [];
  final List<FeedAlbum> _feed = [];
  int _offset = 0;
  int _pageNum = 1;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  final _scrollController = ScrollController();

  XimalayaService get _service => context.read<XimalayaService>();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadInitial();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tabs = await _service.fetchHomeTabs();
      final page = await _service.fetchFeed(pageNum: 1);
      if (!mounted) return;
      setState(() {
        _tabs = tabs;
        _feed
          ..clear()
          ..addAll(page.items);
        _offset = page.offset;
        _pageNum = 1;
        _hasMore = page.items.isNotEmpty;
        _loading = false;
      });
    } on XmException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    _loadingMore = true;
    try {
      final page = await _service.fetchFeed(
        pageNum: _pageNum + 1,
        streamOffSet: _offset,
      );
      if (!mounted) return;
      setState(() {
        _feed.addAll(page.items);
        _offset = page.offset;
        _pageNum += 1;
        _hasMore = page.items.isNotEmpty;
      });
    } on XmException {
      // 分页失败静默，下拉刷新可重试
    } finally {
      _loadingMore = false;
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >
        _scrollController.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  void _openAlbum(int albumId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AlbumScreen(albumId: albumId)),
    );
  }

  void _onTabTap(HomeTab tab) {
    if (tab.isRecommend) return;
    final cid = tab.categoryId;
    if (cid == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CategoryScreen(initialCategoryId: cid),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('xmlyfm'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _feed.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48),
            const SizedBox(height: 12),
            Text(_error!),
            const SizedBox(height: 12),
            FilledButton(onPressed: _loadInitial, child: const Text('重试')),
          ],
        ),
      );
    }
    return Column(
      children: [
        if (_tabs.isNotEmpty) _buildTabBar(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadInitial,
            child: isWide(context) ? _buildFeedGrid() : _buildFeedList(),
          ),
        ),
      ],
    );
  }

  Widget _buildFeedItem(int i) {
    if (i >= _feed.length) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final album = _feed[i];
    return AlbumCard(
      title: album.title,
      subtitle: album.subTitle.isNotEmpty ? album.subTitle : album.nickname,
      cover: album.cover,
      onTap: () => _openAlbum(album.albumId),
    );
  }

  /// 紧凑档：单列列表（原形态）
  Widget _buildFeedList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      itemCount: _feed.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _buildFeedItem(i),
      ),
    );
  }

  /// 中 / 宽屏：专辑卡片网格，列数随可用宽度自动增减（约 2–5 列）
  Widget _buildFeedGrid() {
    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 380,
        mainAxisExtent: 132,
        crossAxisSpacing: 12,
        mainAxisSpacing: 10,
      ),
      itemCount: _feed.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, i) => _buildFeedItem(i),
    );
  }

  Widget _buildTabBar() {
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: _tabs.length,
        itemBuilder: (context, i) {
          final tab = _tabs[i];
          final selected = tab.isRecommend;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(tab.title),
              selected: selected,
              onSelected: (_) => _onTabTap(tab),
            ),
          );
        },
      ),
    );
  }
}
