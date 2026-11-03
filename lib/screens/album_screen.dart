import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/utils.dart';
import '../models/models.dart';
import '../services/library_service.dart';
import '../services/player_service.dart';
import '../services/ximalaya_service.dart';
import '../widgets/cover_image.dart';
import '../widgets/detail_scaffold.dart';
import '../widgets/track_tile.dart';

/// 专辑页：头信息（封面/主播/付费与会员徽章/简介）+ 节目列表。
/// 列表分页加载，支持正序/倒序切换；点节目以当前已加载列表为队列播放。
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
  bool _hasMore = true;
  bool _loading = true;
  bool _loadingMore = false;
  bool _asc = true;
  String? _error;
  final _scrollController = ScrollController();

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

  @override
  Widget build(BuildContext context) {
    return DetailScaffold(
      child: Scaffold(
        appBar: AppBar(
          title: Text(_album?.title ?? '专辑'),
          actions: [
            if (_album != null)
              IconButton(
                icon: Icon(
                  context.watch<LibraryService>().isFavorite(widget.albumId)
                      ? Icons.favorite
                      : Icons.favorite_border,
                ),
                onPressed: () =>
                    context.read<LibraryService>().toggleFavorite(_album!),
              ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            FilledButton(onPressed: _loadFirst, child: const Text('重试')),
          ],
        ),
      );
    }
    final album = _album;
    if (album == null) return const Center(child: Text('专辑不存在'));
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverToBoxAdapter(child: _buildHeader(album)),
        SliverToBoxAdapter(child: _buildListHeader()),
        SliverList.builder(
          itemCount: _tracks.length + (_hasMore ? 1 : 0),
          itemBuilder: (context, i) {
            if (i >= _tracks.length) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final track = _tracks[i];
            return TrackTile(
              track: track,
              indexLabel: _asc ? i + 1 : _tracks.length - i,
              onTap: () => _playAt(i),
            );
          },
        ),
      ],
    );
  }

  Widget _buildHeader(AlbumInfo album) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CoverImage(url: album.cover, size: 110, radius: 12),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      album.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold, height: 1.3),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      album.nickname,
                      style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (album.categoryName.isNotEmpty)
                          MiniBadge(album.categoryName,
                              color: theme.colorScheme.secondary),
                        if (album.isPaid) const MiniBadge('付费专辑'),
                        if (album.isVipFree)
                          MiniBadge('会员免费',
                              color: theme.colorScheme.tertiary),
                        if (album.playTimes > 0)
                          MiniBadge(
                              '${formatPlayCount(album.playTimes)} 播放',
                              color: theme.colorScheme.secondary),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
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
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _tracks.isEmpty ? null : () => _playAt(0),
              icon: const Icon(Icons.play_arrow),
              label: const Text('播放全部'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListHeader() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: Row(
        children: [
          Text(
            '节目',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          Text(
            '共 ${_tracks.length} 集${_hasMore ? '+' : ''}',
            style: TextStyle(
                fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: _toggleOrder,
            icon: Icon(_asc ? Icons.arrow_upward : Icons.arrow_downward,
                size: 16),
            label: Text(_asc ? '正序' : '倒序'),
          ),
        ],
      ),
    );
  }
}
