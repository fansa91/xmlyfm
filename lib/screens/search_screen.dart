import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/ximalaya_service.dart';
import '../widgets/section_header.dart';
import 'album_screen.dart';
import 'search_results_screen.dart';

/// 搜索页：热词 chips + 热搜榜（分类切换）+ 输入联想。
/// 提交搜索进入结果页。
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  List<String> _hotWords = [];
  List<BillboardCategory> _bbCategories = [];
  String _bbCategoryId = '-1';
  List<BillboardItem> _bbItems = [];
  bool _bbLoading = false;

  SuggestResult? _suggest;
  Timer? _debounce;
  bool _searching = false;

  XimalayaService get _service => context.read<XimalayaService>();

  @override
  void initState() {
    super.initState();
    _loadHome();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadHome() async {
    try {
      final words = await _service.fetchHotWords();
      if (mounted) setState(() => _hotWords = words);
    } catch (_) {}
    try {
      final cats = await _service.fetchBillboardCategories();
      if (mounted) setState(() => _bbCategories = cats);
    } catch (_) {}
    _loadBillboard(_bbCategoryId);
  }

  Future<void> _loadBillboard(String categoryId) async {
    setState(() {
      _bbCategoryId = categoryId;
      _bbLoading = true;
    });
    try {
      final items = await _service.fetchBillboardList(categoryId);
      if (!mounted) return;
      setState(() {
        _bbItems = items;
        _bbLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _bbLoading = false);
    }
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final kw = value.trim();
    if (kw.isEmpty) {
      setState(() {
        _suggest = null;
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final result = await _service.fetchSuggest(kw);
        if (!mounted) return;
        if (_controller.text.trim() == kw) {
          setState(() => _suggest = result);
        }
      } catch (_) {}
    });
  }

  void _submit(String kw) {
    final q = kw.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SearchResultsScreen(keyword: q)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('搜索')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.search,
              onChanged: _onQueryChanged,
              onSubmitted: _submit,
              decoration: InputDecoration(
                hintText: '搜索专辑、声音、主播',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _controller.clear();
                          _onQueryChanged('');
                        },
                      ),
              ),
            ),
          ),
          Expanded(
            child: _searching && _controller.text.trim().isNotEmpty
                ? _buildSuggest()
                : _buildHome(),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggest() {
    final suggest = _suggest;
    if (suggest == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (suggest.words.isEmpty && suggest.albums.isEmpty) {
      return const Center(child: Text('暂无联想结果'));
    }
    return ListView(
      children: [
        for (final album in suggest.albums)
          ListTile(
            leading: const Icon(Icons.album_outlined),
            title: Text(album.title,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
                '${album.category}${album.tracks > 0 ? ' · ${album.tracks} 集' : ''}'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => AlbumScreen(albumId: album.id)),
            ),
          ),
        for (final word in suggest.words)
          ListTile(
            leading: const Icon(Icons.search),
            title: Text(word, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.north_west, size: 16),
            onTap: () => _submit(word),
          ),
      ],
    );
  }

  Widget _buildHome() {
    return ListView(
      children: [
        if (_hotWords.isNotEmpty) ...[
          const SectionHeader(title: '热门搜索'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _hotWords
                  .map((w) => ActionChip(
                        label: Text(w),
                        onPressed: () => _submit(w),
                      ))
                  .toList(),
            ),
          ),
        ],
        const SectionHeader(title: '热搜榜'),
        if (_bbCategories.isNotEmpty)
          SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _bbCategories.length,
              itemBuilder: (context, i) {
                final cat = _bbCategories[i];
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(cat.name, style: const TextStyle(fontSize: 12)),
                    selected: cat.categoryId == _bbCategoryId,
                    onSelected: (_) => _loadBillboard(cat.categoryId),
                  ),
                );
              },
            ),
          ),
        if (_bbLoading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          for (var i = 0; i < _bbItems.length; i++)
            ListTile(
              dense: true,
              leading: SizedBox(
                width: 28,
                child: Text(
                  '${i + 1}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: i < 3
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              title: Text(_bbItems[i].word,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: _bbItems[i].shift > 0
                  ? const Icon(Icons.whatshot, size: 16, color: Colors.orange)
                  : null,
              onTap: () => _submit(_bbItems[i].word),
            ),
      ],
    );
  }
}
