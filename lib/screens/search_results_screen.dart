import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/responsive.dart';
import '../core/utils.dart';
import '../models/models.dart';
import '../services/player_service.dart';
import '../services/ximalaya_service.dart';
import '../widgets/cover_image.dart';
import '../widgets/detail_scaffold.dart';
import 'album_screen.dart';

/// 搜索结果页：coreList 页签 + front/v1 结果列表。
/// front/v1 风控（risk:5）时服务端返回空 docs，页面做空态兜底提示。
class SearchResultsScreen extends StatefulWidget {
  final String keyword;

  const SearchResultsScreen({super.key, required this.keyword});

  @override
  State<SearchResultsScreen> createState() => _SearchResultsScreenState();
}

class _SearchResultsScreenState extends State<SearchResultsScreen>
    with SingleTickerProviderStateMixin {
  List<SearchCoreTab> _cores = [];
  TabController? _tabController;
  final Map<String, _CoreResults> _cache = {};
  bool _loadingCores = true;
  String? _error;

  XimalayaService get _service => context.read<XimalayaService>();

  @override
  void initState() {
    super.initState();
    _loadCores();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _loadCores() async {
    try {
      var cores = await _service.fetchSearchCores(widget.keyword);
      if (cores.isEmpty) {
        cores = const [
          SearchCoreTab(typeValue: 'chosen', typeName: '精选', selected: true),
          SearchCoreTab(typeValue: 'album', typeName: '专辑', selected: false),
          SearchCoreTab(typeValue: 'track', typeName: '声音', selected: false),
        ];
      }
      if (!mounted) return;
      setState(() {
        _cores = cores;
        _loadingCores = false;
        _tabController = TabController(length: cores.length, vsync: this);
      });
      if (cores.isNotEmpty) _loadCore(cores.first.core);
    } on XmException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loadingCores = false;
      });
    }
  }

  Future<void> _loadCore(String core) async {
    if (_cache.containsKey(core)) return;
    final state = _CoreResults(loading: true);
    setState(() => _cache[core] = state);
    try {
      final page = await _service.search(widget.keyword, core: core);
      if (!mounted) return;
      setState(() {
        _cache[core] = _CoreResults(
          docs: page.docs,
          riskBlocked: page.riskBlocked,
        );
      });
    } on XmException catch (e) {
      if (!mounted) return;
      setState(() => _cache[core] = _CoreResults(error: e.message));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DetailScaffold(
      child: Scaffold(
        appBar: AppBar(
          title: Text('“${widget.keyword}”的搜索结果'),
          bottom: _cores.isEmpty
              ? null
              : TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: _cores.map((c) => Tab(text: c.typeName)).toList(),
                  onTap: (i) => _loadCore(_cores[i].core),
                ),
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loadingCores) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    if (_cores.isEmpty || _tabController == null) {
      return const Center(child: Text('暂无结果'));
    }
    return TabBarView(
      controller: _tabController,
      children: _cores.map((c) => _buildCoreList(c.core)).toList(),
    );
  }

  Widget _buildCoreList(String core) {
    final state = _cache[core];
    if (state == null || state.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null) {
      return Center(child: Text(state.error!));
    }
    if (state.docs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            state.riskBlocked
                ? '搜索结果暂时不可用（服务端风控限制），\n可以试试热搜榜里的词，或直接浏览分类。'
                : '没有找到相关结果',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (isWide(context)) {
      // 中 / 宽屏：结果行转多列（行宽约 560，宽屏下双列）
      return GridView.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 560,
          mainAxisExtent: 76,
          crossAxisSpacing: 8,
        ),
        itemCount: state.docs.length,
        itemBuilder: (context, i) => _DocTile(doc: state.docs[i]),
      );
    }
    return ListView.builder(
      itemCount: state.docs.length,
      itemBuilder: (context, i) => _DocTile(doc: state.docs[i]),
    );
  }
}

class _CoreResults {
  final List<SearchDoc> docs;
  final bool loading;
  final bool riskBlocked;
  final String? error;

  const _CoreResults({
    this.docs = const [],
    this.loading = false,
    this.riskBlocked = false,
    this.error,
  });
}

class _DocTile extends StatelessWidget {
  final SearchDoc doc;

  const _DocTile({required this.doc});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: CoverImage(url: doc.cover, size: 48, radius: 8),
      title: Text(doc.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          if (doc.nickname.isNotEmpty) doc.nickname,
          if (doc.duration > 0) formatSeconds(doc.duration),
          if (doc.playtimes > 0) '${formatPlayCount(doc.playtimes)} 播放',
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
      ),
      trailing: doc.isAlbum
          ? const Icon(Icons.album_outlined)
          : const Icon(Icons.play_circle_outline),
      onTap: () {
        if (doc.isAlbum) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => AlbumScreen(albumId: doc.albumId)),
          );
        } else if (doc.trackId > 0) {
          context.read<PlayerService>().playTrack(doc.toTrack());
        }
      },
    );
  }
}
