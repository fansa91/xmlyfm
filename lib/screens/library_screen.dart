import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/utils.dart';
import '../models/models.dart';
import '../services/library_service.dart';
import '../services/player_service.dart';
import '../widgets/cover_image.dart';
import 'album_screen.dart';

/// 我的：收藏专辑 + 收藏声音 + 播放历史（本地存储，shared_preferences）。
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryService>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).pushNamed('/settings'),
          ),
        ],
      ),
      body: ListView(
        children: [
          _sectionTitle(context, '收藏的专辑'),
          if (library.favorites.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text('还没有收藏的专辑，在专辑页点爱心即可收藏'),
            )
          else
            for (final fav in library.favorites)
              ListTile(
                leading: CoverImage(url: fav.cover, size: 48, radius: 8),
                title: Text(fav.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(fav.nickname,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  icon: const Icon(Icons.favorite),
                  color: Theme.of(context).colorScheme.primary,
                  onPressed: () => library.toggleFavorite(AlbumInfo(
                    albumId: fav.albumId,
                    title: fav.title,
                    nickname: fav.nickname,
                    cover: fav.cover,
                    intro: '',
                    uid: 0,
                    isPaid: fav.isPaid,
                    isVipFree: false,
                    categoryId: 0,
                    categoryName: '',
                    playTimes: 0,
                  )),
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => AlbumScreen(albumId: fav.albumId)),
                ),
              ),
          const Divider(height: 24),
          _sectionTitle(context, '收藏的声音'),
          if (library.favoriteTracks.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text('还没有收藏的声音，在播放页点爱心即可收藏'),
            )
          else
            for (final t in library.favoriteTracks)
              ListTile(
                leading: CoverImage(url: t.cover, size: 48, radius: 8),
                title: Text(t.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(t.nickname,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  icon: const Icon(Icons.favorite),
                  color: Theme.of(context).colorScheme.primary,
                  onPressed: () => library.toggleFavoriteTrack(t),
                ),
                onTap: () => context.read<PlayerService>().playTrack(t),
              ),
          const Divider(height: 24),
          Row(
            children: [
              Expanded(child: _sectionTitle(context, '播放历史')),
              if (library.history.isNotEmpty)
                TextButton(
                  onPressed: () => library.clearHistory(),
                  child: const Text('清空'),
                ),
            ],
          ),
          if (library.history.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text('暂无播放记录'),
            )
          else
            for (final entry in library.history)
              ListTile(
                leading: CoverImage(url: entry.track.cover, size: 48, radius: 8),
                title: Text(entry.track.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  [
                    if (entry.albumTitle.isNotEmpty) entry.albumTitle,
                    formatDate(entry.playedAt),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.play_circle_outline),
                onTap: () =>
                    context.read<PlayerService>().playTrack(entry.track),
              ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        title,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
      ),
    );
  }
}
