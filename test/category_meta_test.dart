import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xmlyfm/services/ximalaya_service.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

/// 按 URL 子串路由的假 HTTP 适配器（与 search_fallback_test 同款）
class FakeAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  final Map<String, String> bodies;

  FakeAdapter(this.bodies);

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
    for (final e in bodies.entries) {
      if (url.contains(e.key)) {
        return ResponseBody.fromString(e.value, 200, headers: headers);
      }
    }
    throw StateError('未预设的请求：$url');
  }

  @override
  void close({bool force = false}) {}

  RequestOptions lastTo(String part) =>
      requests.lastWhere((r) => r.uri.toString().contains(part));
}

XimalayaService serviceWith(FakeAdapter adapter) {
  final dio = Dio();
  dio.httpClientAdapter = adapter;
  return XimalayaService(dio: dio);
}

void main() {
  group('分类筛选接口（文档 §2.8）', () {
    test('fetchCategoryMetadatas 解析元数据树', () async {
      final adapter = FakeAdapter({
        'v2/category/metadatas': fixture('category_v2_metadatas.json'),
      });
      final service = serviceWith(adapter);
      final groups = await service.fetchCategoryMetadatas(3);
      expect(groups.length, 2);
      expect(groups.first.displayName, '小说分类');
      final req = adapter.lastTo('v2/category/metadatas');
      expect(req.uri.queryParameters['categoryId'], '3');
      expect(req.uri.queryParameters['version'], XimalayaService.appVersion);
    });

    test('fetchMetaAlbums：多组选择拼 metadatas 参数，翻页用 pageId',
        () async {
      final adapter = FakeAdapter({
        'v2/category/metadata/albums':
            fixture('category_v2_metadata_albums.json'),
      });
      final service = serviceWith(adapter);
      final page = await service.fetchMetaAlbums(
        3,
        selection: const {11510: 5162, 11486: 1274},
        pageId: 2,
      );
      expect(page.albums.length, 3);
      expect(page.pageId, 2);
      expect(page.hasMore, isTrue);
      final req = adapter.lastTo('v2/category/metadata/albums');
      expect(
        req.uri.queryParameters['metadatas'],
        '11510:5162,11486:1274',
      );
      expect(req.uri.queryParameters['pageId'], '2');
      // 分页参数是 pageId，绝不能出现 page
      expect(req.uri.queryParameters.containsKey('page'), isFalse);
    });

    test('fetchMetaAlbums：无选择时不带 metadatas，第一页不带 pageId',
        () async {
      final adapter = FakeAdapter({
        'v2/category/metadata/albums':
            fixture('category_v2_metadata_albums.json'),
      });
      final service = serviceWith(adapter);
      await service.fetchMetaAlbums(3);
      final req = adapter.lastTo('v2/category/metadata/albums');
      expect(req.uri.queryParameters.containsKey('metadatas'), isFalse);
      expect(req.uri.queryParameters.containsKey('pageId'), isFalse);
    });

    test('ret 非 0 抛 XmException', () async {
      final adapter = FakeAdapter({
        'v2/category/metadatas': jsonEncode({'ret': 1, 'msg': '参数错误'}),
      });
      final service = serviceWith(adapter);
      await expectLater(
        service.fetchCategoryMetadatas(3),
        throwsA(isA<XmException>()),
      );
    });
  });
}
