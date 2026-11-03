import '../core/utils.dart';

/// 数据模型：字段全部来自 XIMALAYA_API.md 文档与 samples 实测样本，
/// 解析做容错（缺字段给默认值），样本里没有的字段不臆造。

Map<String, dynamic> _mapOf(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<dynamic> _listOf(dynamic v) => v is List ? v : const [];

// ---------------- 首页 ----------------

/// 首页页签（customCategories 的 categoryList.itemList 一项）
class HomeTab {
  final String id;
  final String title;
  final String itemType;
  final int? categoryId;

  const HomeTab({
    required this.id,
    required this.title,
    required this.itemType,
    this.categoryId,
  });

  bool get isRecommend => itemType == 'recommend' || categoryId == null;

  factory HomeTab.fromJson(Map<String, dynamic> json) {
    final cid = json['categoryId'];
    return HomeTab(
      id: strOf(json['id']),
      title: strOf(json['title']),
      itemType: strOf(json['itemType']),
      categoryId: cid == null ? null : intOf(cid),
    );
  }

  /// 解析 customCategories 响应：categoryList[].itemList[]
  static List<HomeTab> parseHomeTabs(Map<String, dynamic> json) {
    final tabs = <HomeTab>[];
    for (final g in _listOf(json['categoryList'])) {
      for (final it in _listOf(_mapOf(g)['itemList'])) {
        final tab = HomeTab.fromJson(_mapOf(it));
        if (tab.title.isNotEmpty) tabs.add(tab);
      }
    }
    return tabs;
  }
}

/// 推荐流里的一张专辑卡（discovery-feed/v4/mix 的 body[].item）
class FeedAlbum {
  final int albumId;
  final String title;
  final String subTitle;
  final String nickname;
  final String cover;
  final int categoryId;

  const FeedAlbum({
    required this.albumId,
    required this.title,
    required this.subTitle,
    required this.nickname,
    required this.cover,
    required this.categoryId,
  });

  factory FeedAlbum.fromJson(Map<String, dynamic> json) {
    return FeedAlbum(
      albumId: intOf(json['albumId']),
      title: strOf(json['title']),
      subTitle: strOf(json['subTitle']),
      nickname: strOf(json['nickname']),
      cover: strOf(json['coverLarge']).isNotEmpty
          ? strOf(json['coverLarge'])
          : strOf(json['coverPath']),
      categoryId: intOf(json['categoryId']),
    );
  }
}

/// 推荐流一页：items + 下一页要回传的 offset
class FeedPage {
  final List<FeedAlbum> items;
  final int offset;

  const FeedPage({required this.items, required this.offset});

  factory FeedPage.fromJson(Map<String, dynamic> json) {
    final items = <FeedAlbum>[];
    for (final b in _listOf(json['body'])) {
      final item = _mapOf(_mapOf(b)['item']);
      if (item.isEmpty) continue;
      final album = FeedAlbum.fromJson(item);
      if (album.albumId > 0) items.add(album);
    }
    return FeedPage(items: items, offset: intOf(json['offset']));
  }
}

// ---------------- 分类 ----------------

/// 分类内页签（discovery-category/tab/list 的 data 一项）
class CategoryTab {
  final int id;
  final int categoryId;
  final String name;
  final int tabType;

  const CategoryTab({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.tabType,
  });

  factory CategoryTab.fromJson(Map<String, dynamic> json) {
    return CategoryTab(
      id: intOf(json['id']),
      categoryId: intOf(json['categoryId']),
      name: strOf(json['name']),
      tabType: intOf(json['tabType']),
    );
  }

  static List<CategoryTab> parseList(Map<String, dynamic> json) {
    return _listOf(json['data'])
        .map((e) => CategoryTab.fromJson(_mapOf(e)))
        .where((t) => t.name.isNotEmpty)
        .toList();
  }
}

/// 分类页里提取出的一张专辑卡（queryCategoryPageData 的 cards[].data.body[]）
class CategoryAlbum {
  final int albumId;
  final String title;
  final String cover;
  final String nickname;

  const CategoryAlbum({
    required this.albumId,
    required this.title,
    required this.cover,
    required this.nickname,
  });

  factory CategoryAlbum.fromJson(Map<String, dynamic> json) {
    var cover = strOf(json['coverLarge']);
    if (cover.isEmpty) cover = strOf(json['coverPath']);
    if (cover.isEmpty) cover = strOf(json['coverMiddle']);
    if (cover.isEmpty) cover = strOf(json['imgPath']);
    return CategoryAlbum(
      albumId: intOf(json['albumId']),
      title: strOf(json['title']),
      cover: cover,
      nickname: strOf(json['nickname']),
    );
  }
}

/// 分类页数据：从 heterogenous cards 里提取专辑卡与标签词
class CategoryPageData {
  final List<CategoryAlbum> albums;
  final List<String> tags;

  const CategoryPageData({required this.albums, required this.tags});

  factory CategoryPageData.fromJson(Map<String, dynamic> json) {
    final albums = <CategoryAlbum>[];
    final seenAlbums = <int>{};
    final tags = <String>[];
    final seenTags = <String>{};
    final cards = _listOf(_mapOf(json['data'])['cards']);
    for (final c in cards) {
      final body = _listOf(_mapOf(_mapOf(c)['data'])['body']);
      for (final b in body) {
        final item = _mapOf(b);
        if (item.isEmpty) continue;
        // 广告卡 body 带 ext 字段，跳过
        if (item.containsKey('ext')) continue;
        final album = CategoryAlbum.fromJson(item);
        if (album.albumId > 0 && album.title.isNotEmpty) {
          if (seenAlbums.add(album.albumId)) albums.add(album);
        } else if (album.title.isNotEmpty && intOf(item['trackId']) == 0) {
          // 纯标题项（如 card_classify 的标签）当作标签词
          if (seenTags.add(album.title) && tags.length < 16) {
            tags.add(album.title);
          }
        }
      }
    }
    return CategoryPageData(albums: albums, tags: tags);
  }
}

// ---------------- 搜索 ----------------

/// 热搜榜分类（hotWordBillboardCategory）
class BillboardCategory {
  final String categoryId;
  final String name;

  const BillboardCategory({required this.categoryId, required this.name});

  factory BillboardCategory.fromJson(Map<String, dynamic> json) {
    return BillboardCategory(
      categoryId: strOf(json['categoryId']),
      name: strOf(json['categoryName']),
    );
  }

  static List<BillboardCategory> parseList(Map<String, dynamic> json) {
    return _listOf(json['category'])
        .map((e) => BillboardCategory.fromJson(_mapOf(e)))
        .where((c) => c.name.isNotEmpty)
        .toList();
  }
}

/// 热搜榜词条（hotWordResultList 一项）
class BillboardItem {
  final String word;
  final int score;
  final int shift;

  const BillboardItem({
    required this.word,
    required this.score,
    required this.shift,
  });

  factory BillboardItem.fromJson(Map<String, dynamic> json) {
    final display = strOf(json['display_word']);
    return BillboardItem(
      word: display.isNotEmpty ? display : strOf(json['word']),
      score: intOf(json['score']),
      shift: intOf(json['shift']),
    );
  }

  /// list/3.2 版：顶层 hotWordResultList
  static List<BillboardItem> parseListJson(Map<String, dynamic> json) {
    return _listOf(json['hotWordResultList'])
        .map((e) => BillboardItem.fromJson(_mapOf(e)))
        .where((i) => i.word.isNotEmpty)
        .toList();
  }

  /// card/1.2 版：resultList[].hotWordResultList 分组
  static List<BillboardItem> parseCardJson(Map<String, dynamic> json) {
    final items = <BillboardItem>[];
    for (final g in _listOf(json['resultList'])) {
      for (final e in _listOf(_mapOf(g)['hotWordResultList'])) {
        final item = BillboardItem.fromJson(_mapOf(e));
        if (item.word.isNotEmpty) items.add(item);
      }
    }
    return items;
  }
}

/// 联想结果：联想词 + 命中的专辑
class SuggestResult {
  final List<String> words;
  final List<SuggestAlbum> albums;

  const SuggestResult({required this.words, required this.albums});

  factory SuggestResult.fromJson(Map<String, dynamic> json) {
    final words = <String>[];
    for (final w in _listOf(json['queryResultList'])) {
      final kw = strOf(_mapOf(w)['keyword']);
      if (kw.isNotEmpty) words.add(kw);
    }
    final albums = <SuggestAlbum>[];
    for (final a in _listOf(json['albumResultList'])) {
      final album = SuggestAlbum.fromJson(_mapOf(a));
      if (album.id > 0) albums.add(album);
    }
    return SuggestResult(words: words, albums: albums);
  }
}

class SuggestAlbum {
  final int id;
  final String title;
  final String imgPath;
  final int tracks;
  final String category;

  const SuggestAlbum({
    required this.id,
    required this.title,
    required this.imgPath,
    required this.tracks,
    required this.category,
  });

  factory SuggestAlbum.fromJson(Map<String, dynamic> json) {
    return SuggestAlbum(
      id: intOf(json['id']),
      title: strOf(json['keyword']),
      imgPath: strOf(json['imgPath']),
      tracks: intOf(json['tracks']),
      category: strOf(json['category']),
    );
  }
}

/// 搜索结果页签（front/v1/coreList 的 response.docs 一项）
class SearchCoreTab {
  final String typeValue;
  final String typeName;
  final bool selected;

  const SearchCoreTab({
    required this.typeValue,
    required this.typeName,
    required this.selected,
  });

  /// 调 front/v1 时用的 core 值：coreList 的 chosen 对应 chosen3
  String get core => typeValue == 'chosen' ? 'chosen3' : typeValue;

  factory SearchCoreTab.fromJson(Map<String, dynamic> json) {
    return SearchCoreTab(
      typeValue: strOf(json['typeValue']),
      typeName: strOf(json['typeName']),
      selected: boolOf(json['selected']),
    );
  }

  static List<SearchCoreTab> parseList(Map<String, dynamic> json) {
    final docs = _listOf(_mapOf(json['response'])['docs']);
    return docs
        .map((e) => SearchCoreTab.fromJson(_mapOf(e)))
        .where((t) => t.typeValue.isNotEmpty)
        .toList();
  }
}

/// 搜索结果一条（front/v1 的 response.docs 一项）。
/// 成功响应样本受风控未取得，字段只取在其它样本里出现过的键名做容错读取。
class SearchDoc {
  final int albumId;
  final int trackId;
  final String title;
  final String cover;
  final String nickname;
  final int duration;
  final int playtimes;

  const SearchDoc({
    required this.albumId,
    required this.trackId,
    required this.title,
    required this.cover,
    required this.nickname,
    required this.duration,
    required this.playtimes,
  });

  factory SearchDoc.fromJson(Map<String, dynamic> json, {String core = ''}) {
    var cover = strOf(json['coverLarge']);
    if (cover.isEmpty) cover = strOf(json['coverPath']);
    if (cover.isEmpty) cover = strOf(json['coverMiddle']);
    if (cover.isEmpty) cover = strOf(json['imgPath']);
    var albumId = intOf(json['albumId']);
    var trackId = intOf(json['trackId']);
    final id = intOf(json['id']);
    if (id > 0) {
      if (albumId == 0 && (core == 'album' || core == 'chosen3')) albumId = id;
      if (trackId == 0 && core == 'track') trackId = id;
    }
    return SearchDoc(
      albumId: albumId,
      trackId: trackId,
      title: strOf(json['title']),
      cover: cover,
      nickname: strOf(json['nickname']),
      duration: intOf(json['duration']),
      playtimes: intOf(json['playtimes']),
    );
  }

  /// 网页端 revision/search 的一条结果（文档 §1.10）。
  /// [webCore] 为网页端 core：album / track / user。
  /// 封面是协议相对地址（//imagev2...），补 https: 前缀；
  /// 主播条目无专辑/声音 ID（与 front/v1 的 user 结果一样只展示）。
  factory SearchDoc.fromWebJson(
    Map<String, dynamic> json, {
    required String webCore,
  }) {
    String coverOf(List<String> keys) {
      for (final k in keys) {
        final v = strOf(json[k]);
        if (v.isNotEmpty) return v.startsWith('//') ? 'https:$v' : v;
      }
      return '';
    }

    switch (webCore) {
      case 'album':
        return SearchDoc(
          albumId: intOf(json['id']),
          trackId: 0,
          title: strOf(json['title']),
          cover: coverOf(['cover_path']),
          nickname: strOf(json['nickname']),
          duration: 0,
          playtimes: intOf(json['play']),
        );
      case 'track':
        return SearchDoc(
          albumId: intOf(json['album_id']),
          trackId: intOf(json['id']),
          title: strOf(json['title']),
          cover: coverOf(['cover_path', 'album_cover_path']),
          nickname: strOf(json['nickname']),
          duration: doubleOf(json['duration']).round(),
          playtimes: intOf(json['count_play']),
        );
      case 'user':
        return SearchDoc(
          albumId: 0,
          trackId: 0,
          title: strOf(json['nickname']),
          cover: coverOf(['logoPic', 'smallPic']),
          nickname: strOf(json['pTtitle']),
          duration: 0,
          playtimes: 0,
        );
      default:
        return SearchDoc.fromJson(json);
    }
  }

  bool get isAlbum => albumId > 0 && trackId == 0;

  /// 转成可播放的 Track（无直带 URL，播放时由 PlayResolver 走 baseInfo）
  Track toTrack() {
    return Track(
      trackId: trackId,
      albumId: albumId,
      title: title,
      nickname: nickname,
      cover: cover,
      duration: duration,
      playtimes: playtimes,
    );
  }
}

/// 搜索结果一页
class SearchPage {
  final List<SearchDoc> docs;

  /// 服务端风控清空（reason=risk:5）时为 true，UI 做空态提示
  final bool riskBlocked;

  /// 结果来自网页端回落通道（revision/search）时为 true
  final bool fromFallback;

  const SearchPage({
    required this.docs,
    required this.riskBlocked,
    this.fromFallback = false,
  });

  factory SearchPage.fromJson(Map<String, dynamic> json, {String core = ''}) {
    final docs = _listOf(_mapOf(json['response'])['docs'])
        .map((e) => SearchDoc.fromJson(_mapOf(e), core: core))
        .where((d) => d.title.isNotEmpty || d.albumId > 0 || d.trackId > 0)
        .toList();
    return SearchPage(
      docs: docs,
      riskBlocked: strOf(json['reason']).startsWith('risk'),
    );
  }

  /// 网页端 revision/search 响应（文档 §1.10）。
  /// 单 core：data.result.response.docs；all：data.result 下
  /// album/track/user 三组分组返回，合并顺序为专辑 → 声音 → 主播。
  factory SearchPage.fromWebJson(
    Map<String, dynamic> json, {
    required String webCore,
  }) {
    final result = _mapOf(_mapOf(json['data'])['result']);
    List<SearchDoc> parseDocs(dynamic holder, String core) =>
        _listOf(_mapOf(holder)['docs'])
            .map((e) => SearchDoc.fromWebJson(_mapOf(e), webCore: core))
            .where((d) => d.title.isNotEmpty || d.albumId > 0 || d.trackId > 0)
            .toList();
    final docs = webCore == 'all'
        ? [
            ...parseDocs(result['album'], 'album'),
            ...parseDocs(result['track'], 'track'),
            ...parseDocs(result['user'], 'user'),
          ]
        : parseDocs(result['response'], webCore);
    return SearchPage(docs: docs, riskBlocked: false, fromFallback: true);
  }
}

// ---------------- 专辑与声音 ----------------

/// 专辑信息（album/track 列表接口里的 album 对象）
class AlbumInfo {
  final int albumId;
  final String title;
  final String nickname;
  final String cover;
  final String intro;
  final int uid;
  final bool isPaid;
  final bool isVipFree;
  final int categoryId;
  final String categoryName;
  final int playTimes;

  const AlbumInfo({
    required this.albumId,
    required this.title,
    required this.nickname,
    required this.cover,
    required this.intro,
    required this.uid,
    required this.isPaid,
    required this.isVipFree,
    required this.categoryId,
    required this.categoryName,
    required this.playTimes,
  });

  factory AlbumInfo.fromJson(Map<String, dynamic> json) {
    var intro = strOf(json['shortIntro']);
    if (intro.isEmpty) intro = strOf(json['intro']);
    return AlbumInfo(
      albumId: intOf(json['albumId']),
      title: strOf(json['title']),
      nickname: strOf(json['nickname']),
      cover: strOf(json['coverLarge']),
      intro: intro,
      uid: intOf(json['uid']),
      isPaid: boolOf(json['isPaid']),
      isVipFree: boolOf(json['isVipFree']),
      categoryId: intOf(json['categoryId']),
      categoryName: strOf(json['categoryName']),
      playTimes: intOf(json['playTimes']),
    );
  }

  Map<String, dynamic> toJson() => {
        'albumId': albumId,
        'title': title,
        'nickname': nickname,
        'coverLarge': cover,
        'isPaid': isPaid,
        'isVipFree': isVipFree,
      };
}

/// 一集声音（album/track 列表的 tracks.list 一项）
class Track {
  final int trackId;
  final int albumId;
  final String title;
  final String nickname;
  final String cover;
  final int duration; // 秒
  final int playtimes;
  final int createdAt;
  final bool isPaid;
  final bool isFree;
  final bool isAuthorized;
  final int sampleDuration; // 试听秒数
  final double price;
  final String playUrl32;
  final String playUrl64;
  final String playUrl64M4a;
  final String playPathAacv164;
  final String playPathAacv224;
  final String playPathHq;

  const Track({
    required this.trackId,
    required this.albumId,
    required this.title,
    this.nickname = '',
    this.cover = '',
    this.duration = 0,
    this.playtimes = 0,
    this.createdAt = 0,
    this.isPaid = false,
    this.isFree = false,
    this.isAuthorized = false,
    this.sampleDuration = 0,
    this.price = 0,
    this.playUrl32 = '',
    this.playUrl64 = '',
    this.playUrl64M4a = '',
    this.playPathAacv164 = '',
    this.playPathAacv224 = '',
    this.playPathHq = '',
  });

  /// 收费集：付费且不是免费集（文档 §5.5 口径）
  bool get isChargeTrack => isPaid && !isFree;

  factory Track.fromJson(Map<String, dynamic> json) {
    var cover = strOf(json['coverLarge']);
    if (cover.isEmpty) cover = strOf(json['coverMiddle']);
    if (cover.isEmpty) cover = strOf(json['coverSmall']);
    return Track(
      trackId: intOf(json['trackId']),
      albumId: intOf(json['albumId']),
      title: strOf(json['title']),
      nickname: strOf(json['nickname']),
      cover: cover,
      duration: intOf(json['duration']),
      playtimes: intOf(json['playtimes']),
      createdAt: intOf(json['createdAt']),
      isPaid: boolOf(json['isPaid']),
      isFree: boolOf(json['isFree']),
      isAuthorized: boolOf(json['isAuthorized']),
      sampleDuration: intOf(json['sampleDuration']),
      price: doubleOf(json['price']),
      playUrl32: strOf(json['playUrl32']),
      playUrl64: strOf(json['playUrl64']),
      playUrl64M4a: strOf(json['playUrl64M4a']),
      playPathAacv164: strOf(json['playPathAacv164']),
      playPathAacv224: strOf(json['playPathAacv224']),
      playPathHq: strOf(json['playPathHq']),
    );
  }

  /// 按音质档位从直带 URL 里择优（顺序参照官方 getTrackForPlayBase 的优先级）。
  /// quality: 0 标准 / 1 高清 / 2 臻品 / 3 无损
  String? directUrlForQuality(int quality) {
    final List<String> order;
    switch (quality) {
      case 0:
        order = [
          playUrl32,
          playPathAacv224,
          playUrl64,
          playPathAacv164,
          playPathHq,
        ];
      case 2:
      case 3:
        order = [
          playPathHq,
          playUrl64M4a,
          playPathAacv164,
          playUrl64,
          playUrl32,
        ];
      case 1:
      default:
        order = [
          playUrl64M4a,
          playPathAacv164,
          playUrl64,
          playUrl32,
          playPathHq,
        ];
    }
    for (final u in order) {
      if (u.isNotEmpty) return u;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'trackId': trackId,
        'albumId': albumId,
        'title': title,
        'nickname': nickname,
        'coverLarge': cover,
        'duration': duration,
        'playtimes': playtimes,
        'createdAt': createdAt,
        'isPaid': isPaid,
        'isFree': isFree,
        'isAuthorized': isAuthorized,
        'sampleDuration': sampleDuration,
        'price': price,
        'playUrl32': playUrl32,
        'playUrl64': playUrl64,
        'playUrl64M4a': playUrl64M4a,
        'playPathAacv164': playPathAacv164,
        'playPathAacv224': playPathAacv224,
        'playPathHq': playPathHq,
      };
}

/// 专辑节目列表一页
class AlbumTracksPage {
  final AlbumInfo album;
  final List<Track> tracks;
  final int pageId;
  final int maxPageId;
  final int totalCount;

  const AlbumTracksPage({
    required this.album,
    required this.tracks,
    required this.pageId,
    required this.maxPageId,
    required this.totalCount,
  });

  bool get hasMore => pageId < maxPageId;

  factory AlbumTracksPage.fromJson(Map<String, dynamic> json) {
    final tracksJson = _mapOf(json['tracks']);
    final tracks = _listOf(tracksJson['list'])
        .map((e) => Track.fromJson(_mapOf(e)))
        .where((t) => t.trackId > 0)
        .toList();
    return AlbumTracksPage(
      album: AlbumInfo.fromJson(_mapOf(json['album'])),
      tracks: tracks,
      pageId: intOf(tracksJson['pageId']),
      maxPageId: intOf(tracksJson['maxPageId']),
      totalCount: intOf(tracksJson['totalCount']),
    );
  }
}

// ---------------- 播放解析 ----------------

/// baseInfo 返回的一条播放地址（playUrlInfos / playUrlList 一项）
class PlayUrlInfo {
  final String url;
  final String type;
  final int qualityLevel;
  final int fileSize;

  const PlayUrlInfo({
    required this.url,
    required this.type,
    required this.qualityLevel,
    required this.fileSize,
  });

  factory PlayUrlInfo.fromJson(Map<String, dynamic> json) {
    return PlayUrlInfo(
      url: strOf(json['url']),
      type: strOf(json['type']),
      qualityLevel: intOf(json['qualityLevel']),
      fileSize: intOf(json['fileSize']),
    );
  }
}

/// baseInfo 解析结果（兼容 v4 顶层 playUrlInfos 与 v3 trackInfo.playUrlList）
class BaseInfoResult {
  final List<PlayUrlInfo> playUrlInfos;
  final int sampleDuration;

  const BaseInfoResult({required this.playUrlInfos, required this.sampleDuration});

  factory BaseInfoResult.fromJson(Map<String, dynamic> json) {
    var infos = <PlayUrlInfo>[];
    var sample = 0;
    final top = json['playUrlInfos'];
    if (top is List) {
      infos = top
          .map((e) => PlayUrlInfo.fromJson(_mapOf(e)))
          .where((i) => i.url.isNotEmpty)
          .toList();
    }
    // v4: trackBaseVO.trackInfo / v3: trackInfo
    Map<String, dynamic> trackInfo = _mapOf(json['trackInfo']);
    final baseVo = _mapOf(json['trackBaseVO']);
    if (baseVo.isNotEmpty && baseVo['trackInfo'] is Map) {
      trackInfo = _mapOf(baseVo['trackInfo']);
    }
    if (infos.isEmpty) {
      infos = _listOf(trackInfo['playUrlList'])
          .map((e) => PlayUrlInfo.fromJson(_mapOf(e)))
          .where((i) => i.url.isNotEmpty)
          .toList();
    }
    sample = intOf(trackInfo['sampleDuration']);
    if (sample == 0) sample = intOf(trackInfo['sample_duration']);
    return BaseInfoResult(playUrlInfos: infos, sampleDuration: sample);
  }

  /// 按音质档位挑 URL：先精确 qualityLevel，再按 type 对照表（文档 §5.4），
  /// 最后兜底取第一条。
  String? pickUrl(int quality) {
    if (playUrlInfos.isEmpty) return null;
    for (final info in playUrlInfos) {
      if (info.qualityLevel == quality) return info.url;
    }
    const typeByQuality = <int, List<String>>{
      0: ['mp3_32', 'm4a_24', 'aac_24'],
      1: ['mp3_64', 'm4a_64'],
      2: ['m4a_128'],
      3: ['fhq'],
    };
    for (final t in typeByQuality[quality] ?? const <String>[]) {
      for (final info in playUrlInfos) {
        if (info.type == t) return info.url;
      }
    }
    return playUrlInfos.first.url;
  }
}

/// track pay 响应（mpay charge JSON 的 fileInfo 一项）
class TrackPayInfo {
  final bool isAuthorized;
  final int sampleDuration;
  final int sampleLength;
  final int totalLength;
  final int duration;

  const TrackPayInfo({
    required this.isAuthorized,
    required this.sampleDuration,
    required this.sampleLength,
    required this.totalLength,
    required this.duration,
  });

  factory TrackPayInfo.fromJson(Map<String, dynamic> json) {
    var info = json;
    final fileInfo = json['fileInfo'];
    if (fileInfo is List && fileInfo.isNotEmpty) {
      info = _mapOf(fileInfo.first);
    }
    return TrackPayInfo(
      isAuthorized: boolOf(info['isAuthorized']),
      sampleDuration: intOf(info['sampleDuration']),
      sampleLength: intOf(info['sampleLength']),
      totalLength: intOf(info['totalLength']),
      duration: intOf(info['duration']),
    );
  }
}

/// 音质档位（trackQualityLevel，文档 §5.4）
class Quality {
  static const List<int> levels = [0, 1, 2, 3];
  static const Map<int, String> names = {
    0: '标准',
    1: '高清',
    2: '臻品',
    3: '无损',
  };

  static String nameOf(int level) => names[level] ?? '高清';
}
