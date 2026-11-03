import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/responsive.dart';
import '../models/models.dart';
import '../services/ximalaya_service.dart';
import '../widgets/album_card.dart';
import '../widgets/detail_scaffold.dart';
import 'album_screen.dart';

/// 分类页：分类 chips（来自首页页签里带 categoryId 的项）+
/// 分类内页签（tab/list）+ 分类落地页卡片（queryCategoryPageData）。
/// 另有「筛选」模式：元数据树（discovery/v2/category/metadatas）出
/// 维度 chips（选中带出下级子组），专辑列表走 metadata/albums 按
/// 已选维度过滤 + pageId 分页（文档 §2.8 实测链路）。
/// 作为底部 tab 使用时不传 initialCategoryId；从首页页签跳入时带初始分类。
class CategoryScreen extends StatefulWidget {
  final int? initialCategoryId;

  const CategoryScreen({super.key, this.initialCategoryId});

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  List<HomeTab> _categories = [];
  int? _selectedCategoryId;
  List<CategoryTab> _subTabs = [];
  String? _selectedSubTab;
  CategoryPageData? _pageData;
  bool _loadingTabs = true;
  bool _loadingPage = false;
  String? _error;

  // ---------- 筛选模式 ----------
  bool _filterMode = false;
  List<CategoryMetaGroup>? _metaGroups;
  final Map<int, int> _selection = {}; // metadataId -> valueId
  final Set<int> _expandedGroups = {}; // 值很多时展开全部的组
  List<CategoryAlbum> _metaAlbums = [];
  int _metaPage = 0;
  bool _metaHasMore = true;
  bool _metaLoading = false;
  bool _metaLoadingMore = false;
  String? _metaError;
  int _metaLoadSeq = 0;
  final _filterScrollController = ScrollController();

  XimalayaService get _service => context.read<XimalayaService>();

  @override
  void initState() {
    super.initState();
    _selectedCategoryId = widget.initialCategoryId;
    _filterScrollController.addListener(_onFilterScroll);
    _loadCategories();
  }

  @override
  void dispose() {
    _filterScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final tabs = await _service.fetchHomeTabs();
      final cats = tabs.where((t) => t.categoryId != null).toList();
      if (!mounted) return;
      setState(() {
        _categories = cats;
        _loadingTabs = false;
        _selectedCategoryId ??=
            cats.isNotEmpty ? cats.first.categoryId : null;
      });
      if (_selectedCategoryId != null) _loadCategory(_selectedCategoryId!);
    } on XmException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loadingTabs = false;
      });
    }
  }

  Future<void> _loadCategory(int categoryId) async {
    setState(() {
      _loadingPage = true;
      _selectedSubTab = null;
      _pageData = null;
      // 换分类即退出筛选并清空筛选状态
      _filterMode = false;
      _metaGroups = null;
      _selection.clear();
      _expandedGroups.clear();
      _metaAlbums = [];
      _metaError = null;
      _metaLoadSeq++;
    });
    try {
      final results = await Future.wait([
        _service.fetchCategoryTabs(categoryId),
        _service.fetchCategoryPage(categoryId),
      ]);
      if (!mounted) return;
      setState(() {
        _subTabs = results[0] as List<CategoryTab>;
        _pageData = results[1] as CategoryPageData;
        _loadingPage = false;
      });
    } on XmException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loadingPage = false;
      });
    }
  }

  void _openAlbum(int albumId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AlbumScreen(albumId: albumId)),
    );
  }

  // ---------- 筛选模式逻辑 ----------

  /// 当前可见的元数据组：顶层组 + 已选值带出的子组（按父组顺序插入）
  List<CategoryMetaGroup> _visibleMetaGroups() {
    final result = <CategoryMetaGroup>[];
    void visit(CategoryMetaGroup g) {
      result.add(g);
      final sel = _selection[g.id];
      if (sel == null) return;
      for (final v in g.values) {
        if (v.id == sel) {
          for (final sub in v.subGroups) {
            visit(sub);
          }
        }
      }
    }

    for (final g in _metaGroups ?? const <CategoryMetaGroup>[]) {
      visit(g);
    }
    return result;
  }

  /// 剪掉已不可见组的残留选择（如改选父值后旧子组的选择）
  void _pruneSelection() {
    final visibleIds = _visibleMetaGroups().map((g) => g.id).toSet();
    _selection.removeWhere((k, _) => !visibleIds.contains(k));
  }

  Future<void> _enterFilter() async {
    final categoryId = _selectedCategoryId;
    if (categoryId == null) return;
    setState(() => _filterMode = true);
    if (_metaGroups == null) {
      setState(() => _metaLoading = true);
      try {
        final groups = await _service.fetchCategoryMetadatas(categoryId);
        if (!mounted) return;
        setState(() => _metaGroups = groups);
      } on XmException catch (e) {
        if (!mounted) return;
        setState(() {
          _metaError = e.message;
          _metaLoading = false;
        });
        return;
      }
    }
    _loadMetaAlbums(reset: true);
  }

  void _exitFilter() {
    setState(() {
      _filterMode = false;
      _metaLoadSeq++;
    });
  }

  void _onMetaSelect(CategoryMetaGroup group, CategoryMetaValue value,
      bool selected) {
    setState(() {
      if (selected) {
        _selection[group.id] = value.id;
      } else {
        _selection.remove(group.id);
      }
      _pruneSelection();
    });
    _loadMetaAlbums(reset: true);
  }

  void _clearSelection() {
    setState(() {
      _selection.clear();
      _expandedGroups.clear();
    });
    _loadMetaAlbums(reset: true);
  }

  Future<void> _loadMetaAlbums({bool reset = false}) async {
    final categoryId = _selectedCategoryId;
    if (categoryId == null) return;
    if (!reset && (_metaLoadingMore || !_metaHasMore || _metaLoading)) {
      return;
    }
    final seq = ++_metaLoadSeq;
    if (reset) {
      setState(() {
        _metaLoading = true;
        _metaError = null;
        _metaAlbums = [];
        _metaPage = 0;
        _metaHasMore = true;
      });
    } else {
      _metaLoadingMore = true;
    }
    try {
      final page = await _service.fetchMetaAlbums(
        categoryId,
        selection: Map.of(_selection),
        pageId: reset ? 1 : _metaPage + 1,
      );
      if (!mounted || seq != _metaLoadSeq) return;
      setState(() {
        _metaAlbums = reset
            ? page.albums
            : [..._metaAlbums, ...page.albums];
        _metaPage = page.pageId;
        _metaHasMore = page.hasMore;
        _metaLoading = false;
      });
    } on XmException catch (e) {
      if (!mounted || seq != _metaLoadSeq) return;
      setState(() {
        _metaLoading = false;
        if (reset) _metaError = e.message;
      });
    } finally {
      _metaLoadingMore = false;
    }
  }

  void _onFilterScroll() {
    if (_filterScrollController.position.pixels >
        _filterScrollController.position.maxScrollExtent - 400) {
      _loadMetaAlbums();
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = Scaffold(
      appBar: AppBar(title: const Text('分类')),
      body: _buildBody(),
    );
    // 从首页跳入时包一层 DetailScaffold，保证迷你播放器可见
    if (widget.initialCategoryId != null) {
      return DetailScaffold(child: content);
    }
    return content;
  }

  Widget _buildBody() {
    if (_loadingTabs) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_categories.isEmpty) {
      return Center(child: Text(_error ?? '暂无分类数据'));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCategoryChips(),
        _buildSubTabRow(),
        Expanded(child: _filterMode ? _buildFilterContent() : _buildPageContent()),
      ],
    );
  }

  Widget _buildCategoryChips() {
    return SizedBox(
      height: 48,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: _categories.length,
        itemBuilder: (context, i) {
          final cat = _categories[i];
          final selected = cat.categoryId == _selectedCategoryId;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(cat.title),
              selected: selected,
              onSelected: (_) {
                if (cat.categoryId == null) return;
                setState(() => _selectedCategoryId = cat.categoryId);
                _loadCategory(cat.categoryId!);
              },
            ),
          );
        },
      ),
    );
  }

  /// 第二行 chips：「筛选」开关恒在首位；筛选模式下换成「清除筛选」，
  /// 落地模式下跟分类内页签（tab/list）。
  Widget _buildSubTabRow() {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: [
          FilterChip(
            avatar: const Icon(Icons.tune, size: 18),
            label: const Text('筛选'),
            selected: _filterMode,
            onSelected: (v) => v ? _enterFilter() : _exitFilter(),
          ),
          if (_filterMode && _selection.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: ActionChip(
                avatar: const Icon(Icons.clear, size: 18),
                label: const Text('清除筛选'),
                onPressed: _clearSelection,
              ),
            ),
          if (!_filterMode)
            for (final tab in _subTabs)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: FilterChip(
                  label: Text(tab.name),
                  selected: tab.name == _selectedSubTab,
                  onSelected: (v) =>
                      setState(() => _selectedSubTab = v ? tab.name : null),
                ),
              ),
        ],
      ),
    );
  }

  /// 筛选模式内容：元数据维度组（每组单选 ChoiceChip）+ 过滤后专辑列表
  /// （与落地页同一套卡片渲染，列表滚动到底分页加载）。
  Widget _buildFilterContent() {
    if (_metaLoading && _metaGroups == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_metaGroups == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_metaError ?? '筛选加载失败'),
            const SizedBox(height: 12),
            FilledButton(onPressed: _enterFilter, child: const Text('重试')),
          ],
        ),
      );
    }
    final wide = isWide(context);
    return ListView(
      controller: _filterScrollController,
      padding: const EdgeInsets.only(bottom: 12),
      children: [
        for (final g in _visibleMetaGroups()) _buildMetaGroup(g),
        const Divider(height: 16),
        if (_metaLoading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_metaError != null && _metaAlbums.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_metaError!),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => _loadMetaAlbums(reset: true),
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          )
        else if (_metaAlbums.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('没有符合条件的专辑')),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: wide
                ? GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 380,
                      mainAxisExtent: 132,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: _metaAlbums.length,
                    itemBuilder: (context, i) =>
                        _buildAlbumCard(_metaAlbums[i]),
                  )
                : Column(
                    children: [
                      for (final album in _metaAlbums)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _buildAlbumCard(album),
                        ),
                    ],
                  ),
          ),
          if (_metaHasMore)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ],
    );
  }

  Widget _buildAlbumCard(CategoryAlbum album) {
    return AlbumCard(
      title: album.title,
      subtitle: album.nickname,
      cover: album.cover,
      onTap: () => _openAlbum(album.albumId),
    );
  }

  /// 一个元数据维度组：组名 + 值 chips（单选，再点取消）；
  /// 值超过 24 个时默认折叠，可展开全部。
  Widget _buildMetaGroup(CategoryMetaGroup group) {
    const foldLimit = 24;
    final expanded = _expandedGroups.contains(group.id);
    final values = expanded || group.values.length <= foldLimit
        ? group.values
        : group.values.sublist(0, foldLimit);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            group.displayName,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final v in values)
                ChoiceChip(
                  label: Text(v.displayName),
                  selected: _selection[group.id] == v.id,
                  onSelected: (sel) => _onMetaSelect(group, v, sel),
                ),
              if (group.values.length > foldLimit)
                ActionChip(
                  label: Text(expanded ? '收起' : '展开全部'),
                  onPressed: () => setState(() {
                    if (expanded) {
                      _expandedGroups.remove(group.id);
                    } else {
                      _expandedGroups.add(group.id);
                    }
                  }),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPageContent() {
    if (_loadingPage) {
      return const Center(child: CircularProgressIndicator());
    }
    final data = _pageData;
    if (data == null) {
      return Center(child: Text(_error ?? '暂无数据'));
    }
    if (data.albums.isEmpty && data.tags.isEmpty) {
      return const Center(child: Text('该分类暂无内容'));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      children: [
        if (_selectedSubTab != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _selectedSubTab!,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
        if (data.tags.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: data.tags
                .map((t) => Chip(
                      label: Text(t),
                      visualDensity: VisualDensity.compact,
                    ))
                .toList(),
          ),
          const SizedBox(height: 12),
        ],
        if (isWide(context) && data.albums.isNotEmpty)
          // 中 / 宽屏：专辑卡片转网格（嵌在同一滚动区内，不单独滚动）
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 380,
              mainAxisExtent: 132,
              crossAxisSpacing: 12,
              mainAxisSpacing: 10,
            ),
            itemCount: data.albums.length,
            itemBuilder: (context, i) {
              final album = data.albums[i];
              return AlbumCard(
                title: album.title,
                subtitle: album.nickname,
                cover: album.cover,
                onTap: () => _openAlbum(album.albumId),
              );
            },
          )
        else
          for (final album in data.albums)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AlbumCard(
                title: album.title,
                subtitle: album.nickname,
                cover: album.cover,
                onTap: () => _openAlbum(album.albumId),
              ),
            ),
      ],
    );
  }
}
