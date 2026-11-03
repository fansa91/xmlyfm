import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/ximalaya_service.dart';
import '../widgets/album_card.dart';
import '../widgets/detail_scaffold.dart';
import 'album_screen.dart';

/// 分类页：分类 chips（来自首页页签里带 categoryId 的项）+
/// 分类内页签（tab/list）+ 分类落地页卡片（queryCategoryPageData）。
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

  XimalayaService get _service => context.read<XimalayaService>();

  @override
  void initState() {
    super.initState();
    _selectedCategoryId = widget.initialCategoryId;
    _loadCategories();
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
        if (_subTabs.isNotEmpty) _buildSubTabChips(),
        Expanded(child: _buildPageContent()),
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

  Widget _buildSubTabChips() {
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        itemCount: _subTabs.length,
        itemBuilder: (context, i) {
          final tab = _subTabs[i];
          final selected = tab.name == _selectedSubTab;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(tab.name),
              selected: selected,
              onSelected: (v) =>
                  setState(() => _selectedSubTab = v ? tab.name : null),
            ),
          );
        },
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
