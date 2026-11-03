import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xmlyfm/models/models.dart';
import 'package:xmlyfm/services/settings_service.dart';
import 'package:xmlyfm/services/ximalaya_service.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

Map<String, dynamic> fixtureJson(String name) =>
    jsonDecode(fixture(name)) as Map<String, dynamic>;

/// 按 URL 子串路由的假 HTTP 适配器：记录全部请求，可指定某些 URL 返回 500。
class FakeAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  final Map<String, String> bodies;
  final Set<String> failUrls;

  FakeAdapter(this.bodies, {this.failUrls = const {}});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final url = options.uri.toString();
    const headers = {
      Headers.contentTypeHeader: ['application/json'],
    };
    if (failUrls.any(url.contains)) {
      return ResponseBody.fromString('server error', 500, headers: headers);
    }
    for (final e in bodies.entries) {
      if (url.contains(e.key)) {
        return ResponseBody.fromString(e.value, 200, headers: headers);
      }
    }
    throw StateError('未预设的请求：$url');
  }

  @override
  void close({bool force = false}) {}

  bool hit(String part) => requests.any((r) => r.uri.toString().contains(part));

  RequestOptions lastTo(String part) =>
      requests.lastWhere((r) => r.uri.toString().contains(part));
}

XimalayaService serviceWith(FakeAdapter adapter, {String? deviceId}) {
  final dio = Dio();
  dio.httpClientAdapter = adapter;
  return XimalayaService(dio: dio, deviceId: deviceId);
}

/// front/v1 正常返回一条专辑（合成最小样本）
const frontOkAlbum =
    '{"response":{"docs":[{"id":424242,"title":"前端直出专辑",'
    '"nickname":"某主播","coverLarge":"https://img.example.com/a.jpg",'
    '"playtimes":99}]}}';

const frontEmpty = '{"response":{"docs":[]}}';

void main() {
  group('网页回落映射（真实样本 fixture）', () {
    test('album：id/封面补 https/播放量映射', () {
      final page = SearchPage.fromWebJson(
        fixtureJson('search_web_album.json'),
        webCore: 'album',
      );
      expect(page.fromFallback, isTrue);
      expect(page.riskBlocked, isFalse);
      expect(page.docs.length, 20);
      final d = page.docs.first;
      expect(d.albumId, 40121646);
      expect(d.trackId, 0);
      expect(d.title, startsWith('三体'));
      expect(d.nickname, '三体宇宙');
      expect(d.cover, startsWith('https://imagev2.xmcdn.com'));
      expect(d.playtimes, 745616034);
    });

    test('track：trackId/album_id/浮点时长/播放量映射', () {
      final page = SearchPage.fromWebJson(
        fixtureJson('search_web_track.json'),
        webCore: 'track',
      );
      expect(page.docs.length, 20);
      final d = page.docs.first;
      expect(d.trackId, 240998122);
      expect(d.albumId, 30816438);
      expect(d.duration, 1893); // 样本里是 1893.0 秒
      expect(d.playtimes, 4080185);
      expect(d.cover, startsWith('https://'));
    });

    test('user：昵称作标题、pTtitle 作副标题、无 ID 只展示', () {
      final page = SearchPage.fromWebJson(
        fixtureJson('search_web_user.json'),
        webCore: 'user',
      );
      expect(page.docs.length, 20);
      final d = page.docs.first;
      expect(d.title, '三体宇宙');
      expect(d.nickname, '有声图书月度优质主播');
      expect(d.albumId, 0);
      expect(d.trackId, 0);
      expect(d.cover, startsWith('https://'));
    });

    test('all：专辑/声音/主播三组合并（10+5+5）', () {
      final page = SearchPage.fromWebJson(
        fixtureJson('search_web_all.json'),
        webCore: 'all',
      );
      expect(page.docs.length, 20);
      expect(page.docs[0].isAlbum, isTrue);
      expect(page.docs[10].trackId, greaterThan(0)); // 第 11 条起是声音
      expect(page.fromFallback, isTrue);
    });

    test('front/v1 风控样本：riskBlocked 且无结果', () {
      final page = SearchPage.fromJson(fixtureJson('search_front_risk.json'));
      expect(page.riskBlocked, isTrue);
      expect(page.docs, isEmpty);
      expect(page.fromFallback, isFalse);
    });
  });

  group('search() 回落行为', () {
    test('risk:5 时自动回落网页端并返回结果', () async {
      final adapter = FakeAdapter({
        'hub/front/v1': fixture('search_front_risk.json'),
        'revision/search': fixture('search_web_album.json'),
      });
      final page = await serviceWith(adapter).search('三体', core: 'album');
      expect(page.docs.length, 20);
      expect(page.fromFallback, isTrue);
      expect(page.riskBlocked, isFalse);
      expect(adapter.hit('hub/front/v1'), isTrue);
      expect(adapter.hit('revision/search'), isTrue);
    });

    test('front/v1 有结果时不走回落', () async {
      final adapter = FakeAdapter({'hub/front/v1': frontOkAlbum});
      final page = await serviceWith(adapter).search('三体', core: 'album');
      expect(page.docs.single.albumId, 424242);
      expect(page.fromFallback, isFalse);
      expect(adapter.hit('revision/search'), isFalse);
    });

    test('front/v1 空结果（非风控）同样回落', () async {
      final adapter = FakeAdapter({
        'hub/front/v1': frontEmpty,
        'revision/search': fixture('search_web_track.json'),
      });
      final page = await serviceWith(adapter).search('三体', core: 'track');
      expect(page.docs.length, 20);
      expect(page.fromFallback, isTrue);
    });

    test('chosen3 回落到网页 all 并合并三组', () async {
      final adapter = FakeAdapter({
        'hub/front/v1': fixture('search_front_risk.json'),
        'revision/search': fixture('search_web_all.json'),
      });
      final page = await serviceWith(adapter).search('三体');
      expect(page.docs.length, 20);
      expect(page.fromFallback, isTrue);
      final q = adapter.lastTo('revision/search').queryParameters;
      expect(q['core'], 'all');
    });

    test('网页端无对应通道的 core（live）不回落，保留风控结果', () async {
      final adapter = FakeAdapter({
        'hub/front/v1': fixture('search_front_risk.json'),
      });
      final page = await serviceWith(adapter).search('三体', core: 'live');
      expect(page.riskBlocked, isTrue);
      expect(page.docs, isEmpty);
      expect(adapter.hit('revision/search'), isFalse);
    });

    test('回落接口失败时返回原始风控结果（不抛异常）', () async {
      final adapter = FakeAdapter(
        {'hub/front/v1': fixture('search_front_risk.json')},
        failUrls: {'revision/search'},
      );
      final page = await serviceWith(adapter).search('三体', core: 'album');
      expect(page.riskBlocked, isTrue);
      expect(page.docs, isEmpty);
    });

    test('front/v1 请求体已补齐官方参数（kw 编码/searchId/extraParam 等）',
        () async {
      final adapter = FakeAdapter({'hub/front/v1': frontOkAlbum});
      await serviceWith(adapter).search('三体', core: 'album');
      final data = adapter.lastTo('hub/front/v1').data as Map;
      expect(data['kw'], '%E4%B8%89%E4%BD%93'); // URLEncoder 形态
      expect(data['searchId'], isA<String>());
      expect((data['searchId'] as String).length, 32);
      expect(data['sourceId'], '0');
      expect(data['newDevice'], 'false');
      expect(data['extraParam'], isA<Map>());
      expect((data['extraParam'] as Map)['intent'], '');
      // 第一页响应没给 searchMeta，翻页也不臆造
      await serviceWith(adapter).search('三体', core: 'album', page: 2);
      final data2 = adapter.lastTo('hub/front/v1').data as Map;
      expect(data2.containsKey('searchMeta'), isFalse);
    });
  });

  group('deviceId 持久化与注入', () {
    test('SettingsService 首启生成 32 位十六进制并持久化（重启不变）', () async {
      SharedPreferences.setMockInitialValues({});
      final s1 = SettingsService();
      await s1.init();
      expect(s1.deviceId, matches(RegExp(r'^[0-9a-f]{32}$')));
      final s2 = SettingsService();
      await s2.init();
      expect(s2.deviceId, s1.deviceId);
    });

    test('注入的 deviceId 出现在推荐流公共参数里；缺省用占位值', () async {
      final adapter = FakeAdapter({'discovery-feed/v4/mix': '{}'});
      const myId = 'fedcba9876543210fedcba9876543210';
      final service = serviceWith(adapter, deviceId: myId);
      await service.fetchFeed();
      expect(
        adapter.lastTo('discovery-feed').queryParameters['deviceId'],
        myId,
      );
      expect(serviceWith(FakeAdapter({})).deviceId.length, 32);
    });
  });
}
