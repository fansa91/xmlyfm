import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xmlyfm/core/utils.dart';
import 'package:xmlyfm/models/models.dart';

Map<String, dynamic> fixture(String name) {
  final file = File('test/fixtures/$name');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  group('工具', () {
    test('htmlToPlainText：块级标签转行、剥标签、反转义', () {
      final text = htmlToPlainText(
          '<p style="x">第一段&nbsp;文字</p><p>第二段<br>换行 &amp; 符号</p>');
      expect(text, '第一段 文字\n第二段\n换行 & 符号');
      expect(htmlToPlainText(''), isEmpty);
    });
  });

  group('首页', () {
    test('customCategories 页签解析', () {
      final tabs = HomeTab.parseHomeTabs(fixture('home_customCategories.json'));
      expect(tabs, isNotEmpty);
      expect(tabs.first.title, '推荐');
      expect(tabs.first.isRecommend, isTrue);
      expect(tabs.any((t) => t.categoryId != null), isTrue);
    });

    test('推荐流解析：body 列表 item 取专辑', () {
      final page = FeedPage.fromJson(fixture('home_feed_v4mix.json'));
      expect(page.items.length, 3);
      expect(page.offset, 12);
      expect(page.items.first.albumId, greaterThan(0));
      expect(page.items.first.title, isNotEmpty);
    });
  });

  group('分类', () {
    test('tab/list 页签解析（顶层 data 列表）', () {
      final tabs = CategoryTab.parseList(fixture('home_tab_list.json'));
      expect(tabs.length, 51);
      expect(tabs.first.name, '全部');
      expect(tabs.first.categoryId, 3);
    });

    test('分类页卡片：广告卡跳过，标签词提取', () {
      final data = CategoryPageData.fromJson(fixture('home_categoryPage.json'));
      expect(data.tags, isNotEmpty);
      expect(data.tags, contains('都市'));
    });

    test('v2 元数据树解析：组 → 值 → 子组（文档 §2.8 样本）', () {
      final groups =
          CategoryMetaGroup.parseList(fixture('category_v2_metadatas.json'));
      expect(groups.length, 2);
      final novel = groups.firstWhere((g) => g.displayName == '小说分类');
      expect(novel.id, 11510);
      final male = novel.values.single;
      expect(male.displayName, '男频');
      expect(male.id, 5162);
      // 男频带出题材子组，含「玄幻」值
      final genre = male.subGroups.firstWhere((g) => g.id == 11486);
      expect(genre.values.map((v) => v.displayName), contains('玄幻'));
      final finished = groups.firstWhere((g) => g.displayName == '是否完本');
      expect(finished.values.length, 2);
    });

    test('v2 筛选专辑列表解析：分页口径 pageId/maxPageId', () {
      final page = MetaAlbumsPage.fromJson(
        fixture('category_v2_metadata_albums.json'),
        pageId: 1,
      );
      expect(page.albums.length, 3);
      expect(page.albums.first.albumId, 81519744);
      expect(page.albums.first.title, contains('蛊真人'));
      expect(page.maxPageId, 4279);
      expect(page.hasMore, isTrue);
    });
  });

  group('搜索', () {
    test('coreList 页签解析，chosen 映射 chosen3', () {
      final cores = SearchCoreTab.parseList(fixture('search_coreList.json'));
      expect(cores, isNotEmpty);
      final chosen = cores.firstWhere((c) => c.typeValue == 'chosen');
      expect(chosen.core, 'chosen3');
      expect(cores.any((c) => c.typeValue == 'album'), isTrue);
    });

    test('联想解析：联想词 + 专辑', () {
      final result = SuggestResult.fromJson(fixture('search_suggest.json'));
      expect(result.words, contains('三体广播剧'));
      expect(result.albums.length, 1);
      expect(result.albums.first.id, 40121646);
      expect(result.albums.first.tracks, 313);
    });

    test('热搜榜分类解析', () {
      final cats =
          BillboardCategory.parseList(fixture('search_billboardCategory.json'));
      expect(cats.first.categoryId, '-1');
      expect(cats.first.name, '热搜');
    });

    test('热搜榜单解析', () {
      final items =
          BillboardItem.parseListJson(fixture('search_billboardList.json'));
      expect(items, isNotEmpty);
      expect(items.first.word, '头陀渊');
    });

    test('front/v1 风控 risk:5 按空结果处理', () {
      final page = SearchPage.fromJson(fixture('search_front_chosen.json'),
          core: 'chosen3');
      expect(page.docs, isEmpty);
      expect(page.riskBlocked, isTrue);
    });
  });

  group('专辑与声音', () {
    test('免费专辑：直带 URL 可用', () {
      final page =
          AlbumTracksPage.fromJson(fixture('play_album_tracks_freealbum.json'));
      expect(page.tracks.length, 2);
      final first = page.tracks.first;
      expect(first.trackId, 25202);
      expect(first.isChargeTrack, isFalse);
      final url = first.directUrlForQuality(1);
      expect(url, isNotNull);
      expect(url, startsWith('http'));
    });

    test('付费专辑后段：收费集识别 + 无直带 URL', () {
      final page =
          AlbumTracksPage.fromJson(fixture('play_album_tracks_paid_late.json'));
      expect(page.tracks, isNotEmpty);
      for (final t in page.tracks) {
        expect(t.isChargeTrack, isTrue);
        expect(t.sampleDuration, 180);
        expect(t.directUrlForQuality(1), isNull);
      }
      expect(page.totalCount, greaterThan(0));
      expect(page.hasMore, isTrue);
    });

    test('每集发行日期 createdAt 为毫秒时间戳（样本实测）', () {
      final page =
          AlbumTracksPage.fromJson(fixture('play_album_tracks_freealbum.json'));
      final first = page.tracks.first;
      expect(first.createdAt, 1352451581000);
      expect(formatDate(first.createdAt), '2012-11-09');
      expect(formatDate(0), isEmpty);
    });

    test('完整简介取自 introRich 剥 HTML，纯文本 intro 是截断版', () {
      final page =
          AlbumTracksPage.fromJson(fixture('play_album_tracks_freealbum.json'));
      final album = page.album;
      // shortIntro 以「...」截断，fullIntro 是全文且不含 HTML 标签
      expect(album.intro, endsWith('...'));
      expect(album.fullIntro, isNot(contains('<')));
      expect(album.fullIntro, endsWith('不朽功勋。'));
      expect(album.fullIntro.length, greaterThan(album.intro.length));
    });

    test('付费专辑免费集：带防盗链 URL 直播', () {
      final page =
          AlbumTracksPage.fromJson(fixture('play_album_tracks_paidalbum.json'));
      final freeEps = page.tracks.where((t) => !t.isChargeTrack).toList();
      expect(freeEps, isNotEmpty);
      expect(freeEps.first.directUrlForQuality(1), isNotNull);
      expect(page.album.title, contains('谁与争锋'));
      // 样本实测：标题写了会员免费，但 isPaid=true / isVipFree=false，以字段为准
      expect(page.album.isPaid, isTrue);
      expect(page.album.isVipFree, isFalse);
    });
  });

  group('播放解析模型', () {
    test('track pay 元数据解析（fileInfo 列表）', () {
      final info = TrackPayInfo.fromJson(fixture('play_trackpay_paid.json'));
      expect(info.isAuthorized, isFalse);
      expect(info.sampleDuration, 180);
      expect(info.totalLength, greaterThan(0));
    });

    test('baseInfo 按 qualityLevel 选 URL', () {
      final result = BaseInfoResult.fromJson({
        'trackBaseVO': {
          'trackInfo': {'sampleDuration': 0},
        },
        'playUrlInfos': [
          {'url': 'u-hq', 'type': 'm4a_128', 'qualityLevel': 2, 'fileSize': 3},
          {'url': 'u-std', 'type': 'mp3_64', 'qualityLevel': 1, 'fileSize': 1},
        ],
      });
      expect(result.pickUrl(1), 'u-std');
      expect(result.pickUrl(2), 'u-hq');
      // 无精确档位时按 type 对照/首条兜底，不返回 null
      expect(result.pickUrl(0), isNotNull);
    });

    test('Track 直带 URL 音质优先级', () {
      const t = Track(
        trackId: 1,
        albumId: 1,
        title: 't',
        playUrl32: 'u32',
        playUrl64: 'u64',
        playUrl64M4a: 'm4a64',
        playPathAacv164: 'aac64',
        playPathHq: 'hq',
      );
      expect(t.directUrlForQuality(1), 'm4a64'); // 高清优先 m4a
      expect(t.directUrlForQuality(0), 'u32'); // 标准优先 32k
      expect(t.directUrlForQuality(2), 'hq'); // 臻品优先 HQ
      const empty = Track(trackId: 2, albumId: 1, title: 'e');
      expect(empty.directUrlForQuality(1), isNull);
    });
  });
}
