import 'dart:convert';

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

  /// 占位 deviceId：推荐流等接口的必填公共参数（非真实设备标识，
  /// 访客实测用同形态值可正常返回）。
  static const String _deviceId = 'a1b2c3d4e5f6a1b2';

  final Dio _dio;

  XimalayaService([Dio? dio])
      : _dio = dio ??
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
        'deviceId': _deviceId,
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
        'deviceId': _deviceId,
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

  /// 主搜索（文档 §1.1）。风控 reason=risk:5 时返回空 docs 并标 riskBlocked，
  /// 不抛异常，UI 做空态兜底。
  Future<SearchPage> search(
    String kw, {
    String core = 'chosen3',
    int page = 1,
  }) async {
    final isChosen = core == 'chosen3';
    final json = await _postJson(
      '$_search/hub/front/v1',
      body: {
        'kw': kw,
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
        if (!isChosen) 'categoryId': '-1',
      },
    );
    return SearchPage.fromJson(json, core: core);
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
