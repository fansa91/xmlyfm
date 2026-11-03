import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/responsive.dart';
import '../core/utils.dart';
import '../models/models.dart';
import '../services/ximalaya_service.dart';
import '../widgets/cover_image.dart';
import '../widgets/detail_scaffold.dart';
import 'album_screen.dart';

/// 分类排行榜页（文档 §2.9：discovery-category/aggregateRankList 系）：
/// 顶部榜单页签来自聚合榜目录按当前分类过滤的结果——专辑榜
/// （热播/畅销/新品/口碑等，带名次、滚动分页、点进专辑）与
/// 实力主播榜（按主播分组切换，纯展示、无主播主页可跳）。
class RankingScreen extends StatefulWidget {
  final int categoryId;
  final String categoryName;
  final List<CategoryRankTab> tabs;

  const RankingScreen({
    super.key,
    required this.categoryId,
    required this.categoryName,
    required this.tabs,
  });

  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends State<RankingScreen> {
  int _tabIndex = 0;
  int _anchorGroupIndex = 0;

  List<RankAlbum> _albums = [];
  List<RankAnchor> _anchors = [];
  int _page = 0;
  bool _hasMore = true;
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  int _loadSeq = 0;
  final _scrollController = ScrollController();

  XimalayaService get _service => context.read<XimalayaService>();

  CategoryRankTab? get _tab =>
      widget.tabs.isEmpty ? null : widget.tabs[_tabIndex];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >
        _scrollController.position.maxScrollExtent - 400) {
      _load();
    }
  }

  Future<void> _load({bool reset = false}) async {
    final tab = _tab;
    if (tab == null) return;
    if (!reset && (_loading || _loadingMore || !_hasMore)) return;
    final seq = ++_loadSeq;
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _albums = [];
        _anchors = [];
        _page = 0;
        _hasMore = true;
      });
    } else {
      _loadingMore = true;
    }
    try {
      final nextPage = reset ? 1 : _page + 1;
      if (tab.isAnchor) {
        final group = tab.anchorGroups[_anchorGroupIndex];
        final page = await _service.fetchRankAnchors(
          rankingListId: group.rankingListId,
          pageId: nextPage,
        );
        if (!mounted || seq != _loadSeq) return;
        setState(() {
          _anchors = reset ? page.anchors : [..._anchors, ...page.anchors];
          _page = page.pageId;
          _hasMore = page.hasMore;
          _loading = false;
        });
      } else {
        final page = await _service.fetchRankAlbums(
          rankingListId: tab.rankingListId,
          clusterType: tab.clusterType,
          pageId: nextPage,
        );
        if (!mounted || seq != _loadSeq) return;
        setState(() {
          _albums = reset ? page.albums : [..._albums, ...page.albums];
          _page = page.pageId;
          _hasMore = page.hasMore;
          _loading = false;
        });
      }
    } on XmException catch (e) {
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _loading = false;
        if (reset) _error = e.message;
      });
    } finally {
      _loadingMore = false;
    }
  }

  void _selectTab(int index) {
    if (index == _tabIndex) return;
    setState(() {
      _tabIndex = index;
      _anchorGroupIndex = 0;
    });
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    _load(reset: true);
  }

  void _selectAnchorGroup(int index) {
    if (index == _anchorGroupIndex) return;
    setState(() => _anchorGroupIndex = index);
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    _load(reset: true);
  }

  void _openAlbum(int albumId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AlbumScreen(albumId: albumId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.categoryName.isEmpty
        ? '排行榜'
        : '${widget.categoryName} · 排行榜';
    return DetailScaffold(
      child: Scaffold(
        appBar: AppBar(title: Text(title)),
        body: widget.tabs.isEmpty
            ? const Center(child: Text('该分类暂无榜单'))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTabRow(),
                  if (_tab?.isAnchor ?? false) _buildAnchorGroupRow(),
                  Expanded(child: _buildContent()),
                ],
              ),
      ),
    );
  }

  Widget _buildTabRow() {
    return SizedBox(
      height: 48,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: widget.tabs.length,
        itemBuilder: (context, i) {
          final tab = widget.tabs[i];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              avatar: Icon(
                tab.isAnchor ? Icons.mic : Icons.emoji_events,
                size: 18,
              ),
              label: Text(tab.name),
              selected: i == _tabIndex,
              onSelected: (_) => _selectTab(i),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAnchorGroupRow() {
    final groups = _tab?.anchorGroups ?? const <RankGroupRef>[];
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        itemCount: groups.length,
        itemBuilder: (context, i) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(groups[i].displayName),
              selected: i == _anchorGroupIndex,
              onSelected: (_) => _selectAnchorGroup(i),
            ),
          );
        },
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final tab = _tab;
    if (tab == null) return const SizedBox.shrink();
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => _load(reset: true),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (tab.isAnchor) {
      if (_anchors.isEmpty) {
        return const Center(child: Text('暂无主播上榜'));
      }
      return _buildAnchorList();
    }
    if (_albums.isEmpty) {
      return const Center(child: Text('暂无专辑上榜'));
    }
    return _buildAlbumList();
  }

  Widget _buildAlbumList() {
    final wide = isWide(context);
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      itemCount: _albums.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= _albums.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final album = _albums[i];
        final card = _RankAlbumRow(
          rank: i + 1,
          album: album,
          onTap: () => _openAlbum(album.albumId),
        );
        if (!wide) return Padding(padding: const EdgeInsets.only(bottom: 10), child: card);
        // 宽屏居中限宽，与分类页网格同上限口径
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: card,
            ),
          ),
        );
      },
    );
  }

  Widget _buildAnchorList() {
    final wide = isWide(context);
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      itemCount: _anchors.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= _anchors.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final row = _RankAnchorRow(rank: i + 1, anchor: _anchors[i]);
        if (!wide) {
          return Padding(padding: const EdgeInsets.only(bottom: 10), child: row);
        }
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: row,
            ),
          ),
        );
      },
    );
  }
}

/// 名次徽标：前三名用主题色填充，其余用中性容器色
class _RankBadge extends StatelessWidget {
  final int rank;

  const _RankBadge({required this.rank});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (rank) {
      1 => (scheme.primary, scheme.onPrimary),
      2 => (scheme.secondary, scheme.onSecondary),
      3 => (scheme.tertiary, scheme.onTertiary),
      _ => (scheme.surfaceContainerHigh, scheme.onSurfaceVariant),
    };
    return CircleAvatar(
      radius: 14,
      backgroundColor: bg,
      child: Text(
        '$rank',
        style: Theme.of(context)
            .textTheme
            .labelMedium
            ?.copyWith(color: fg, fontWeight: FontWeight.bold),
      ),
    );
  }
}

/// 榜单专辑行：名次 + 封面 + 标题/主播/播放量·集数，点击进专辑页
class _RankAlbumRow extends StatelessWidget {
  final int rank;
  final RankAlbum album;
  final VoidCallback? onTap;

  const _RankAlbumRow({required this.rank, required this.album, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = [
      if (album.playsCounts > 0) '播放 ${formatPlayCount(album.playsCounts)}',
      if (album.tracks > 0) '共 ${album.tracks} 集',
    ].join(' · ');
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _RankBadge(rank: rank),
              const SizedBox(width: 12),
              CoverImage(url: album.cover, size: 56, radius: 8),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      album.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      album.nickname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (album.isPaid) ...[
                const SizedBox(width: 8),
                Chip(
                  label: const Text('付费'),
                  visualDensity: VisualDensity.compact,
                  labelStyle: theme.textTheme.labelSmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 主播榜行：名次 + 头像 + 昵称/简介/粉丝·作品，纯展示不跳转
class _RankAnchorRow extends StatelessWidget {
  final int rank;
  final RankAnchor anchor;

  const _RankAnchorRow({required this.rank, required this.anchor});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = [
      if (anchor.followersCounts > 0)
        '粉丝 ${formatPlayCount(anchor.followersCounts)}',
      if (anchor.tracksCounts > 0) '作品 ${anchor.tracksCounts}',
    ].join(' · ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _RankBadge(rank: rank),
            const SizedBox(width: 12),
            CircleAvatar(
              radius: 28,
              backgroundColor: theme.colorScheme.primaryContainer,
              backgroundImage: anchor.avatar.isNotEmpty
                  ? CachedNetworkImageProvider(anchor.avatar)
                  : null,
              onBackgroundImageError:
                  anchor.avatar.isNotEmpty ? (_, _) {} : null,
              child: anchor.avatar.isEmpty
                  ? Text(
                      anchor.nickname.isNotEmpty
                          ? anchor.nickname.characters.first
                          : '?',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    anchor.nickname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (anchor.describe.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      anchor.describe,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
