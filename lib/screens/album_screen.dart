import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/responsive.dart';
import '../core/utils.dart';
import '../models/models.dart';
import '../services/download_service.dart';
import '../services/library_service.dart';
import '../services/player_service.dart';
import '../services/ximalaya_service.dart';
import '../widgets/cover_image.dart';
import '../widgets/detail_scaffold.dart';
import '../widgets/download_button.dart';
import '../widgets/track_tile.dart';

/// 专辑页：M3 TopBar（SliverAppBar 钉顶）+ 头信息区 + 节目列表。
/// - TopBar 动作：多选、下载全部、更多菜单（收藏专辑 / 排序切换）。
/// - 列表分页加载，正序/倒序切换；点节目以当前已加载列表为队列播放。
/// - 每行带单集下载状态按钮；多选模式（TopBar 图标或长按进入）可批量下载，
///   已下载的集不可再选。
class AlbumScreen extends StatefulWidget {
  final int albumId;

  const AlbumScreen({super.key, required this.albumId});

  @override
  State<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends State<AlbumScreen> {
  AlbumInfo? _album;
  final List<Track> _tracks = [];
  int _page = 1;
  int _totalCount = 0;
  bool _hasMore = true;
  bool _loading = true;
  bool _loadingMore = false;
  bool _asc = true;
  String? _error;
  final _scrollController = ScrollController();

  bool _selectMode = false;
  final Set<int> _selected = {};

  XimalayaService get _service => context.read<XimalayaService>();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadFirst();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadFirst() async {
    setState(() {
      _loading = true;
      _error = null;
      _selectMode = false;
      _selected.clear();
    });
    try {
      final page = await _service.fetchAlbumTracks(
        widget.albumId,
        asc: _asc,
        page: 1,
        count: 30,
      );
      if (!mounted) return;
      setState(() {
        _album = page.album;
        _tracks
          ..clear()
          ..addAll(page.tracks);
        _page = 1;
        _totalCount = page.totalCount;
        _hasMore = page.hasMore;
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
      final page = await _service.fetchAlbumTracks(
        widget.albumId,
        asc: _asc,
        page: _page + 1,
        count: 30,
      );
      if (!mounted) return;
      setState(() {
        _tracks.addAll(page.tracks);
        _page += 1;
        _hasMore = page.hasMore;
        if (page.totalCount > 0) _totalCount = page.totalCount;
      });
    } on XmException {
      // 静默，下次滚动再试
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

  void _toggleOrder() {
    _asc = !_asc;
    _loadFirst();
  }

  void _playAt(int index) {
    context.read<PlayerService>().playQueue(_tracks, index);
  }

  /// 集序号（从 1 起）：倒序时按总集数反推，文件名 {index} 与行号共用
  int _episodeIndex(int i) {
    if (_asc) return i + 1;
    return (_totalCount > 0 ? _totalCount : _tracks.length) - i;
  }

  // ---------- 多选 / 批量下载 ----------

  void _enterSelectMode([Track? initial]) {
    setState(() {
      _selectMode = true;
      _selected.clear();
      if (initial != null &&
          !context.read<DownloadService>().isDownloaded(initial.trackId)) {
        _selected.add(initial.trackId);
      }
    });
  }

  void _exitSelectMode() {
    setState(() {
      _selectMode = false;
      _selected.clear();
    });
  }

  void _toggleSelected(Track track) {
    setState(() {
      if (_selected.contains(track.trackId)) {
        _selected.remove(track.trackId);
      } else {
        _selected.add(track.trackId);
      }
    });
  }

  void _toggleSelectAll() {
    final downloads = context.read<DownloadService>();
    final selectable = _tracks
        .where((t) => !downloads.isDownloaded(t.trackId))
        .map((t) => t.trackId)
        .toSet();
    setState(() {
      if (_selected.length >= selectable.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(selectable);
      }
    });
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _downloadAll() async {
    final downloads = context.read<DownloadService>();
    final targets = _tracks
        .where((t) => !downloads.isDownloaded(t.trackId))
        .toList();
    if (targets.isEmpty) {
      _snack('已全部下载');
      return;
    }
    final (ok, err) = await downloads.enqueueMany(
      targets,
      albumTitle: _album?.title ?? '',
      indexOf: (t) => _episodeIndex(_tracks.indexOf(t)),
      albumIntro: _album?.intro ?? '',
      albumCategory: _album?.categoryName ?? '',
      albumTotal: _totalCount,
    );
    _snack(ok > 0 ? '已加入下载队列 $ok 集' : (err ?? '无法下载'));
  }

  Future<void> _downloadSelected() async {
    final downloads = context.read<DownloadService>();
    final targets = _tracks
        .where((t) => _selected.contains(t.trackId))
        .toList();
    _exitSelectMode();
    if (targets.isEmpty) return;
    final (ok, err) = await downloads.enqueueMany(
      targets,
      albumTitle: _album?.title ?? '',
      indexOf: (t) => _episodeIndex(_tracks.indexOf(t)),
      albumIntro: _album?.intro ?? '',
      albumCategory: _album?.categoryName ?? '',
      albumTotal: _totalCount,
    );
    _snack(ok > 0 ? '已加入下载队列 $ok 集' : (err ?? '无法下载'));
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    // 宽屏（≥900）：顶栏换普通 AppBar、内容转左右双栏；
    // 紧凑 / 中等档保持 SliverAppBar + 单列形态不变。
    final wide = isExpanded(context);
    return DetailScaffold(
      child: Scaffold(
        appBar: wide ? _buildWideAppBar() : null,
        bottomNavigationBar: _selectMode ? _buildSelectBar() : null,
        body: _buildBody(wide: wide),
      ),
    );
  }

  Widget _buildBody({bool wide = false}) {
    final album = _album;
    if (wide && album != null && !_loading && _error == null) {
      return _buildWideBody(album);
    }
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        if (!wide) _buildTopBar(),
        if (_loading)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _loadFirst, child: const Text('重试')),
                ],
              ),
            ),
          )
        else if (album == null)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text('专辑不存在')),
          )
        else ...[
          if (_selectMode)
            SliverToBoxAdapter(child: _buildSelectHeader(album))
          else ...[
            SliverToBoxAdapter(child: _buildHeader(album)),
            SliverToBoxAdapter(child: _buildListHeader()),
          ],
          SliverList.builder(
            itemCount: _tracks.length + (_hasMore ? 1 : 0),
            itemBuilder: (context, i) => _buildTrackListItem(i),
          ),
        ],
      ],
    );
  }

  Widget _buildTrackListItem(int i) {
    if (i >= _tracks.length) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return _buildTrackRow(i);
  }

  /// 宽屏双栏：左栏专辑信息（独立滚动），右栏节目列表（独立滚动）。
  /// 多选底部操作栏仍挂在 Scaffold 上通栏显示。
  Widget _buildWideBody(AlbumInfo album) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 360,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: _selectMode
                ? _buildSelectHeader(album)
                : _buildHeaderWide(album),
          ),
        ),
        const VerticalDivider(thickness: 1, width: 1),
        Expanded(
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              if (!_selectMode)
                SliverToBoxAdapter(child: _buildListHeader()),
              SliverList.builder(
                itemCount: _tracks.length + (_hasMore ? 1 : 0),
                itemBuilder: (context, i) => _buildTrackListItem(i),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 顶栏内容（leading / 标题 / 动作）：SliverAppBar 与宽屏 AppBar 共用一份。
  /// 多选模式下切换为关闭键 + 已选计数。
  ({Widget? leading, Widget title, List<Widget> actions}) _barParts() {
    final album = _album;
    if (_selectMode) {
      return (
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: '退出多选',
          onPressed: _exitSelectMode,
        ),
        title: Text('已选择 ${_selected.length}'),
        actions: [
          TextButton(
            onPressed: _tracks.isEmpty ? null : _toggleSelectAll,
            child: const Text('全选'),
          ),
        ],
      );
    }
    final isFav =
        album != null &&
        context.watch<LibraryService>().isFavorite(widget.albumId);
    return (
      leading: null,
      title: Text(album?.title ?? '专辑'),
      actions: [
        IconButton(
          icon: const Icon(Icons.checklist),
          tooltip: '多选下载',
          onPressed: _tracks.isEmpty ? null : () => _enterSelectMode(),
        ),
        IconButton(
          icon: const Icon(Icons.download_outlined),
          tooltip: '下载全部（已加载）',
          onPressed: _tracks.isEmpty ? null : _downloadAll,
        ),
        PopupMenuButton<String>(
          tooltip: '更多',
          onSelected: (v) {
            if (v == 'fav' && album != null) {
              context.read<LibraryService>().toggleFavorite(album);
            } else if (v == 'sort') {
              _toggleOrder();
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'fav',
              enabled: album != null,
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(isFav ? Icons.favorite : Icons.favorite_border),
                title: Text(isFav ? '取消收藏' : '收藏专辑'),
              ),
            ),
            PopupMenuItem(
              value: 'sort',
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.swap_vert),
                title: Text(_asc ? '切换为倒序' : '切换为正序'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// M3 TopBar：原生 SliverAppBar 钉顶（紧凑 / 中等档）
  Widget _buildTopBar() {
    final parts = _barParts();
    return SliverAppBar(
      pinned: true,
      leading: parts.leading,
      title: parts.title,
      actions: parts.actions,
    );
  }

  /// 宽屏顶栏：与 SliverAppBar 同内容，换普通 AppBar 钉在双栏之上
  PreferredSizeWidget _buildWideAppBar() {
    final parts = _barParts();
    return AppBar(
      leading: parts.leading,
      title: parts.title,
      actions: parts.actions,
    );
  }

  Widget _buildHeader(AlbumInfo album) {
    final theme = Theme.of(context);
    final isFav = context.watch<LibraryService>().isFavorite(album.albumId);
    final total = _totalCount > 0 ? _totalCount : _tracks.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CoverImage(url: album.cover, size: 120, radius: 12),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      album.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      album.nickname,
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '共 $total 集${album.playTimes > 0 ? ' · ${formatPlayCount(album.playTimes)}次播放' : ''}',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _buildBadges(album),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildPlayFavRow(album, isFav),
          if (album.intro.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              album.intro,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 专辑徽章行（分类 / 付费 / 会员免费）：双栏与单列共用
  Widget _buildBadges(AlbumInfo album) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        if (album.categoryName.isNotEmpty)
          MiniBadge(album.categoryName, color: theme.colorScheme.secondary),
        if (album.isPaid) const MiniBadge('付费专辑'),
        if (album.isVipFree)
          MiniBadge('会员免费', color: theme.colorScheme.tertiary),
      ],
    );
  }

  /// 「全部播放 / 收藏」按钮行：双栏与单列共用
  Widget _buildPlayFavRow(AlbumInfo album, bool isFav) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: _tracks.isEmpty ? null : () => _playAt(0),
            icon: const Icon(Icons.play_arrow),
            label: const Text('全部播放'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed: () =>
                context.read<LibraryService>().toggleFavorite(album),
            icon: Icon(isFav ? Icons.favorite : Icons.favorite_border),
            label: Text(isFav ? '已收藏' : '收藏'),
          ),
        ),
      ],
    );
  }

  /// 宽屏左栏头信息：大封面 + 标题 / 主播 / 统计 + 按钮 + 简介（纵向排布）
  Widget _buildHeaderWide(AlbumInfo album) {
    final theme = Theme.of(context);
    final isFav = context.watch<LibraryService>().isFavorite(album.albumId);
    final total = _totalCount > 0 ? _totalCount : _tracks.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CoverImage(url: album.cover, size: 320, radius: 16),
        const SizedBox(height: 16),
        Text(
          album.title,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          album.nickname,
          style: TextStyle(
            fontSize: 13,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '共 $total 集${album.playTimes > 0 ? ' · ${formatPlayCount(album.playTimes)}次播放' : ''}',
          style: TextStyle(
            fontSize: 12.5,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        _buildBadges(album),
        const SizedBox(height: 14),
        _buildPlayFavRow(album, isFav),
        if (album.intro.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            album.intro,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSelectHeader(AlbumInfo album) {
    final total = _totalCount > 0 ? _totalCount : _tracks.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Card(
        child: ListTile(
          leading: CoverImage(url: album.cover, size: 52, radius: 8),
          title: Text(
            '${album.title} · ${album.nickname}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text('共 $total 集 · 已选 ${_selected.length}/$total'),
        ),
      ),
    );
  }

  Widget _buildListHeader() {
    final total = _totalCount > 0 ? _totalCount : _tracks.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: Row(
        children: [
          Text(
            '正片 · $total 集',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: _toggleOrder,
            icon: Icon(
              _asc ? Icons.arrow_upward : Icons.arrow_downward,
              size: 16,
            ),
            label: Text(_asc ? '正序' : '倒序'),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackRow(int i) {
    final track = _tracks[i];
    final downloads = context.watch<DownloadService>();
    final downloaded = downloads.isDownloaded(track.trackId);
    final albumTitle = _album?.title ?? '';
    final index = _episodeIndex(i);

    if (_selectMode) {
      return TrackTile(
        track: track,
        indexLabel: index,
        selected: _selected.contains(track.trackId),
        leading: Checkbox(
          value: downloaded ? true : _selected.contains(track.trackId),
          onChanged: downloaded ? null : (_) => _toggleSelected(track),
        ),
        trailing: downloaded
            ? Text(
                '已下载',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.primary,
                ),
              )
            : null,
        onTap: downloaded ? null : () => _toggleSelected(track),
      );
    }
    return TrackTile(
      track: track,
      indexLabel: index,
      onTap: () => _playAt(i),
      onLongPress: () => _enterSelectMode(track),
      trailing: TrackDownloadButton(
        track: track,
        albumTitle: albumTitle,
        index: index,
        albumIntro: _album?.intro ?? '',
        albumCategory: _album?.categoryName ?? '',
        albumTotal: _totalCount,
      ),
    );
  }

  /// 多选模式底部操作栏：原生 BottomAppBar + FilledButton
  Widget _buildSelectBar() {
    return BottomAppBar(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: FilledButton.icon(
          onPressed: _selected.isEmpty ? null : _downloadSelected,
          icon: const Icon(Icons.download),
          label: Text('下载所选 (${_selected.length})'),
        ),
      ),
    );
  }
}
