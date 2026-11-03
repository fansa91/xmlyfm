import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:xmlyfm/screens/category_screen.dart';
import 'package:xmlyfm/services/ximalaya_service.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

/// 按 URL 子串路由的假 HTTP 适配器，记录全部请求
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
}

void main() {
  testWidgets('分类页筛选：选元数据值后列表按 metadatas 参数过滤',
      (tester) async {
    final adapter = FakeAdapter({
      'customCategories': fixture('home_customCategories.json'),
      'tab/list': fixture('home_tab_list.json'),
      'queryCategoryPageData': fixture('home_categoryPage.json'),
      'v2/category/metadatas': fixture('category_v2_metadatas.json'),
      'v2/category/metadata/albums':
          fixture('category_v2_metadata_albums.json'),
    });
    final dio = Dio();
    dio.httpClientAdapter = adapter;
    final service = XimalayaService(dio: dio);

    await tester.pumpWidget(
      Provider<XimalayaService>.value(
        value: service,
        child: const MaterialApp(home: CategoryScreen()),
      ),
    );
    // 等分类与落地页加载完成（不用 pumpAndSettle：封面占位有转圈动画）
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('筛选'), findsOneWidget);

    await tester.tap(find.text('筛选'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    // 元数据维度组与值出现
    expect(find.text('小说分类'), findsWidgets);
    expect(find.text('男频'), findsOneWidget);
    // 未选任何维度时已拉全量列表（第一页不带 metadatas）
    final firstReq = adapter.requests.lastWhere(
      (r) => r.uri.toString().contains('v2/category/metadata/albums'),
    );
    expect(firstReq.uri.queryParameters.containsKey('metadatas'), isFalse);
    expect(find.textContaining('蛊真人'), findsWidgets);

    // 选「男频」→ 带出题材子组，且重新以 metadatas=11510:5162 拉列表
    await tester.tap(find.text('男频'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final filteredReq = adapter.requests.lastWhere(
      (r) => r.uri.toString().contains('v2/category/metadata/albums'),
    );
    expect(filteredReq.uri.queryParameters['metadatas'], '11510:5162');
    // 子组（题材，组名在样本里是「男频」组 id=11486）的值可见
    expect(find.text('玄幻'), findsWidgets);
  });
}
