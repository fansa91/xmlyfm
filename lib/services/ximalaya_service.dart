import 'dart:convert';
import 'dart:math' show Random;

import 'package:dio/dio.dart';

import '../models/models.dart';
import 'sign.dart';

/// 接口请求失败（HTTP 错误或上游 ret 非 0）。
class XmException implements Exception {
  final String message;
  final int? ret;

  const XmException(this.message, {this.ret});

  @override
  String toString() => 'XmException: $message';
}

/// 喜马拉雅访客态数据层：直连官方 App 接口（免登录、免签名居多），
/// 接口与参数见 XIMALAYA_API.md。UA 照官方 App 形态。
class XimalayaService {
  static const String userAgent = 'ting_9.4.74.3(Android,Android 13)';
  static const String appVersion = '9.4.74.3';
  static const String channel = 'and-d10';

  static const String _mobile = 'https://mobile.ximalaya.com';
  static const String _search = 'https://search.ximalaya.com';
  static const String _mpay = 'https://mpay.ximalaya.com';
  static const String _web = 'https://www.ximalaya.com';

  /// 未注入时的占位 deviceId（形态对齐官方的十六进制设备串）。
  /// 正常运行由 SettingsService 生成并持久化一台一号后经构造注入，
  /// 避免全员共用同一个写死值（服务端看来像同一台设备）。
  static const String _fallbackDeviceId = 'a1b2c3d4e5f6a1b2a1b2c3d4e5f6a1b2';

  /// 本机设备标识（推荐流等接口的必填公共参数）
  final String deviceId;

  final Dio _dio;

  XimalayaService({Dio? dio, String? deviceId})
      : deviceId = deviceId ?? _fallbackDeviceId,
        _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              responseType: ResponseType.json,
              headers: const {'User-Agent': userAgent},
            ));

  int get _ts => DateTime.now().millisecondsSinceEpoch;

  Future<Map<String, dynamic>> _getJson(
    String url, {
    Map<String, dynamic>? query,
  }) async {
    try {
      final resp = await _dio.get<dynamic>(url, queryParameters: query);
      return _asMap(resp.data, url);
    } on DioException catch (e) {
      throw XmException(_dioErrorMessage(e));
    }
  }

  Future<Map<String, dynamic>> _postJson(
    String url, {
    Map<String, dynamic>? query,
    Object? body,
  }) async {
    try {
      final resp = await _dio.post<dynamic>(
        url,
        queryParameters: query,
        data: body,
        options: Options(contentType: Headers.jsonContentType),
      );
      return _asMap(resp.data, url);
    } on DioException catch (e) {
      throw XmException(_dioErrorMessage(e));
    }
  }

  Map<String, dynamic> _asMap(dynamic data, String url) {
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String && data.isNotEmpty) {
      final decoded = jsonDecode(data);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    throw XmException('接口返回异常：$url');
  }

  String _dioErrorMessage(DioException e) {
    final code = e.response?.statusCode;
    if (code != null) return '网络请求失败（HTTP $code）';
    return '网络请求失败：${e.message ?? '未知错误'}';
  }

  // ---------------- 首页 ----------------

  /// 首页页签 + 全部分类（first=1 才给全量，文档 §2.1）
  Future<List<HomeTab>> fetchHomeTabs() async {
    final json = await _getJson(
      '$_mobile/discovery-category/customCategories/$_ts',
      query: {
        'device': 'android',
        'version': appVersion,
        'channel': channel,
        'first': '1',
      },
    );
    return HomeTab.parseHomeTabs(json);
  }

  /// 首页推荐流（POST 双 Map，文档 §2.2 的最小可用集）
  Future<FeedPage> fetchFeed({int pageNum = 1, int streamOffSet = 0}) async {
    final json = await _postJson(
      '$_mobile/discovery-feed/v4/mix',
      query: {
        'appid': '0',
        'deviceId': deviceId,
        'version': appVersion,
        'scale': '1',
        'categoryId': '-2',
        'device': 'android',
        'network': 'wifi',
        'xt': '$_ts',
        'channel': channel,
        'operator': '0',
      },
      body: {
        'pageNum': '$pageNum',
        'size': '18',
        if (pageNum == 1) 'is_mix': '1',
        'onlyBody': 'false',
        'refreshStatus': pageNum == 1 ? '1' : '0',
        'isFoldDevice': '1',
        if (streamOffSet > 0) 'streamOffSet': '$streamOffSet',
      },
    );
    return FeedPage.fromJson(json);
  }

  // ---------------- 分类 ----------------

  /// 分类内页签（categoryId 必填，文档 §2.1）
  Future<List<CategoryTab>> fetchCategoryTabs(int categoryId) async {
    final json = await _getJson(
      '$_mobile/discovery-category/tab/list',
      query: {
        'categoryId': '$categoryId',
        'device': 'android',
        'version': appVersion,
        'channel': channel,
        'deviceId': deviceId,
      },
    );
    if ('${json['code']}' != '0') {
      throw XmException('${json['message'] ?? '分类页签加载失败'}');
    }
    return CategoryTab.parseList(json);
  }

  /// 分类落地页卡片流（文档 §2.5）
  Future<CategoryPageData> fetchCategoryPage(int categoryId) async {
    final json = await _getJson(
      '$_mobile/mobile-category/v1/category/page/queryCategoryPageData',
      query: {
        'categoryId': '$categoryId',
        'device': 'android',
        'version': appVersion,
      },
    );
    return CategoryPageData.fromJson(json);
  }

  // ---------------- 搜索 ----------------

  /// 搜索首页热词（文档 §1.4）：返回热词字符串列表
  Future<List<String>> fetchHotWords() async {
    final json = await _postJson(
      '$_search/hub/hotWordV3/1.0',
      body: {
        'pageSize': '15',
        'page': '1',
        'device': 'android',
        'recmmdSize': '1',
      },
    );
    final words = <String>[];
    final list = json['hotWordList'];
    if (list is List) {
      for (final w in list) {
        if (w is Map) {
          final word = '${w['searchWord'] ?? ''}';
          if (word.isNotEmpty) words.add(word);
        }
      }
    }
    return words;
  }

  /// 热搜榜分类（文档 §1.6）
  Future<List<BillboardCategory>> fetchBillboardCategories() async {
    final json = await _getJson(
      '$_search/hub/hotWordBillboardCategory',
      query: {'layout': 'hotTab'},
    );
    return BillboardCategory.parseList(json);
  }

  /// 热搜榜单（list/3.2，文档 §1.6）
  Future<List<BillboardItem>> fetchBillboardList(String categoryId) async {
    final json = await _getJson(
      '$_search/hub/hotWordBillboard/list/3.2',
      query: {'categoryId': categoryId, 'size': '30'},
    );
    return BillboardItem.parseListJson(json);
  }

  /// 热搜榜卡片（card/1.2，文档 §1.6）
  Future<List<BillboardItem>> fetchBillboardCard(String categoryId) async {
    final json = await _getJson(
      '$_search/hub/hotWordBillboard/card/1.2',
      query: {'size': '10', 'paramCategoryId': categoryId, 'abVersion': 'b'},
    );
    return BillboardItem.parseCardJson(json);
  }

  /// 搜索联想（文档 §1.3）。kw 按实测可用的原样传（JSON body）。
  Future<SuggestResult> fetchSuggest(String kw) async {
    final json = await _postJson(
      '$_search/hub/suggest/v2/2.3',
      body: {'kw': kw, 'paidFilter': 'false'},
    );
    return SuggestResult.fromJson(json);
  }

  /// 搜索结果页签（文档 §1.2）
  Future<List<SearchCoreTab>> fetchSearchCores(String kw) async {
    final json = await _postJson(
      '$_search/hub/front/v1/coreList',
      body: {
        'kw': kw,
        'plan': 'c',
        'spellchecker': 'true',
        'search_version': '7.7',
        'core': 'all',
        'page': '1',
        'paidFilter': 'false',
        'live': 'true',
        'rows': '20',
        'categoryId': '-1',
        'condition': 'relation',
        'needSemantic': 'true',
        'voiceAsinput': 'false',
        'recall': 'tab',
      },
    );
    return SearchCoreTab.parseList(json);
  }

  /// 当前搜索会话 ID（官方 searchId）：page=1 时新生成，翻页复用。
  String _searchId = '';

  /// 上一页响应回传的 searchMeta（官方仅 page>1 时带，值来自响应，
  /// 响应没给就不带，不臆造）。
  String _searchMeta = '';

  static String _randomHex(int len) {
    final rnd = Random.secure();
    return List.generate(len, (_) => rnd.nextInt(16).toRadixString(16)).join();
  }

  /// 对齐官方 URLEncoder.encode 的编码（空格为 +，其余走百分号编码）
  static String _urlEncode(String s) =>
      Uri.encodeComponent(s).replaceAll('%20', '+');

  /// 主搜索（文档 §1.1）。参数按 APK 代码补齐（kw 编码、searchId 会话、
  /// sourceId、extraParam、newDevice、page>1 回传 searchMeta）。
  /// 风控 reason=risk:5 或结果为空时自动回落网页端搜索（文档 §1.10），
  /// 回落成功返回网页结果（fromFallback=true）；回落不可用/失败时
  /// 返回原始结果（保留 riskBlocked，UI 做空态兜底）。
  Future<SearchPage> search(
    String kw, {
    String core = 'chosen3',
    int page = 1,
  }) async {
    final isChosen = core == 'chosen3';
    if (page == 1) {
      _searchId = _randomHex(32);
      _searchMeta = '';
    } else if (_searchId.isEmpty) {
      _searchId = _randomHex(32);
    }
    final json = await _postJson(
      '$_search/hub/front/v1',
      body: {
        'kw': _urlEncode(kw),
        'plan': isChosen ? 'd' : 'c',
        'spellchecker': 'true',
        'search_version': '7.7',
        'core': core,
        'page': '$page',
        'paidFilter': 'false',
        'live': 'true',
        'condition': 'relation',
        'rows': '20',
        'recall': 'normal',
        'voiceAsinput': 'false',
        'needSemantic': isChosen ? 'false' : 'true',
        'newDevice': 'false',
        'searchId': _searchId,
        'sourceId': '0',
        'extraParam': <String, dynamic>{
          'intent': '',
          'queryLabels': <dynamic>[],
          'extendClickTimes': 0,
        },
        if (!isChosen) 'categoryId': '-1',
        if (page > 1 && _searchMeta.isNotEmpty)
          'searchMeta': _urlEncode(_searchMeta),
      },
    );
    final meta = json['searchMeta'];
    if (meta is String && meta.isNotEmpty) _searchMeta = meta;
    final result = SearchPage.fromJson(json, core: core);
    if (!result.riskBlocked && result.docs.isNotEmpty) return result;
    // 风控清空或无结果：回落网页端 revision/search
    try {
      final web = await _searchWeb(kw, core: core, page: page);
      if (web != null) return web;
    } catch (_) {
      // 回落失败不吞原始结果：返回 front/v1 的（可能带 risk 标记）
    }
    return result;
  }

  /// front/v1 的 core → 网页端 revision/search 的 core。
  /// 网页端只有 album/track/user/all，其余垂类（直播/电子书/视频等）
  /// 无对应通道，不回落。
  static const Map<String, String> _webCoreMap = {
    'chosen3': 'all',
    'album': 'album',
    'track': 'track',
    'user1': 'user',
    'user2': 'user',
  };

  /// 网页端搜索回落（文档 §1.10）：访客直通、无需 Cookie。
  /// 通道不支持该 core 或上游 ret 非 200 时返回 null。
  Future<SearchPage?> _searchWeb(
    String kw, {
    required String core,
    required int page,
  }) async {
    final webCore = _webCoreMap[core];
    if (webCore == null) return null;
    final json = await _getJson(
      '$_web/revision/search',
      query: {'kw': kw, 'core': webCore, 'page': '$page', 'rows': '20'},
    );
    if (json['ret'] != 200) return null;
    return SearchPage.fromWebJson(json, webCore: webCore);
  }

  // ---------------- 专辑 ----------------

  /// 专辑节目列表（路径式，文档 §5.1）
  Future<AlbumTracksPage> fetchAlbumTracks(
    int albumId, {
    bool asc = true,
    int page = 1,
    int count = 20,
  }) async {
    final json = await _getJson(
      '$_mobile/mobile/others/ca/album/track/$albumId/$asc/$page/$count',
      query: {'device': 'android'},
    );
    final ret = json['ret'];
    if (ret != null && ret != 0) {
      throw XmException('${json['msg'] ?? '专辑加载失败'}', ret: ret is int ? ret : null);
    }
    return AlbumTracksPage.fromJson(json);
  }

  // ---------------- 播放 ----------------

  /// 收费声音的 track pay 元数据（文档 §5.3）。
  /// 只取 isAuthorized/sampleDuration 等元数据，不拼最终播放 URL
  /// （fileId/ep 解密在官方 App 的 native 层，v1 不做）。
  Future<TrackPayInfo> fetchTrackPay(int trackId) async {
    final json = await _getJson(
      '$_mpay/mobile/track/pay/v2/$trackId/ts-$_ts',
      query: {'device': 'android'},
    );
    final ret = json['ret'];
    if (ret != null && ret != 0) {
      throw XmException('${json['msg'] ?? '付费信息获取失败'}',
          ret: ret is int ? ret : null);
    }
    return TrackPayInfo.fromJson(json);
  }

  /// baseInfo v3（无签名，文档 §5.2）
  Future<BaseInfoResult> fetchBaseInfoV3(int trackId, int quality) =>
      _fetchBaseInfo(trackId, quality, v4: false);

  /// baseInfo v4（带 sign，文档 §5.2）
  Future<BaseInfoResult> fetchBaseInfoV4(int trackId, int quality) =>
      _fetchBaseInfo(trackId, quality, v4: true);

  Future<BaseInfoResult> _fetchBaseInfo(
    int trackId,
    int quality, {
    required bool v4,
  }) async {
    final ts = _ts;
    final json = await _getJson(
      '$_mobile/mobile-playpage/track/${v4 ? 'v4' : 'v3'}/baseInfo/$ts',
      query: {
        'device': 'android',
        'trackId': '$trackId',
        'trackQualityLevel': '$quality',
        if (v4)
          'sign': baseInfoSign(trackId: trackId, timestampMs: ts),
      },
    );
    final ret = json['ret'];
    if (ret != null && ret != 0) {
      throw XmException(_baseInfoErrorMessage(ret, json), ret: ret);
    }
    return BaseInfoResult.fromJson(json);
  }

  String _baseInfoErrorMessage(dynamic ret, Map<String, dynamic> json) {
    final msg = '${json['msg'] ?? ''}';
    switch (ret) {
      case 927:
        return '该资源仅限中国大陆地区播放（版权限制）';
      case 302:
        return '播放签名校验失败';
      case 1001:
        return '播放信息获取失败，请稍后再试';
      default:
        return msg.isNotEmpty ? msg : '播放信息获取失败（ret=$ret）';
    }
  }
}
