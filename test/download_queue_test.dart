import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xmlyfm/models/models.dart';
import 'package:xmlyfm/services/download_service.dart';
import 'package:xmlyfm/services/play_resolver.dart';
import 'package:xmlyfm/services/settings_service.dart';
import 'package:xmlyfm/services/ximalaya_service.dart';

/// 假解析器：每条声音给一个假 CDN 地址（.m4a 后缀，免写标签干扰队列用例）。
/// 下载服务走的是 resolveForDownload，两个入口都覆盖，避免落到真实
/// baseInfo 网络请求。
class FakeResolver extends PlayResolver {
  FakeResolver() : super(XimalayaService());

  @override
  Future<PlayResult> resolve(Track track, {required int quality}) async =>
      PlayResult(url: 'https://cdn.test/${track.trackId}.m4a');

  @override
  Future<PlayResult> resolveForDownload(
    Track track, {
    required int quality,
  }) async => PlayResult(url: 'https://cdn.test/${track.trackId}.m4a');
}

/// 可控门的假网络层：请求进来先登记并挂起，测试用 [release] 放行；
/// [failing] 里的地址直接抛网络异常；[empty] 里的地址返回 0 字节。
/// 取消（cancelFuture）会让挂起的请求以 cancel 异常结束，与真实 dio 一致。
class FakeAdapter implements HttpClientAdapter {
  final List<String> started = [];
  final Set<String> failing = {};
  final Set<String> empty = {};
  final Map<String, Completer<void>> _gates = {};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final url = options.uri.toString();
    started.add(url);
    if (failing.contains(url)) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        message: 'network down',
      );
    }
    if (!empty.contains(url)) {
      final gate = Completer<void>();
      _gates[url] = gate;
      cancelFuture?.whenComplete(() {
        if (!gate.isCompleted) {
          gate.completeError(
            DioException(
              requestOptions: options,
              type: DioExceptionType.cancel,
              message: 'cancelled',
            ),
          );
        }
      });
      await gate.future;
    }
    final bytes = empty.contains(url) ? <int>[] : 'audio-$url'.codeUnits;
    return ResponseBody.fromBytes(
      bytes,
      200,
      headers: {
        Headers.contentLengthHeader: ['${bytes.length}'],
      },
    );
  }

  void release(String url) {
    final gate = _gates[url];
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  @override
  void close({bool force = false}) {}
}

String urlOf(int trackId) => 'https://cdn.test/$trackId.m4a';

Track trackOf(int id) =>
    Track(trackId: id, albumId: 1, title: '第$id集', nickname: '主播');

Future<void> until(bool Function() cond, String what) async {
  for (var i = 0; i < 400; i++) {
    if (cond()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('等待超时：$what');
}

void main() {
  group('DownloadService 严格串行队列', () {
    late Directory dir;
    late FakeAdapter adapter;
    late DownloadService svc;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      dir = await Directory.systemTemp.createTemp('dl_queue');
      adapter = FakeAdapter();
      final settings = SettingsService();
      await settings.init();
      final dio = Dio()..httpClientAdapter = adapter;
      svc = DownloadService(FakeResolver(), settings, dio);
      await svc.initForTest(dir);
    });

    tearDown(() async {
      svc.pauseAll();
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    Future<void> enqueue(int id) async {
      final err = await svc.enqueueTrack(
        trackOf(id),
        albumTitle: 'A',
        index: id,
      );
      expect(err, isNull);
    }

    test('maxConcurrent 恒为 1（串行）', () {
      expect(DownloadService.maxConcurrent, 1);
    });

    test('FIFO：同时只下 1 个，严格按入队顺序推进', () async {
      await enqueue(1);
      await enqueue(2);
      await enqueue(3);
      await until(() => adapter.started.isNotEmpty, '第一个开跑');
      expect(adapter.started, [urlOf(1)]);
      expect(svc.taskFor(1)!.status, DownloadStatus.downloading);
      expect(svc.taskFor(2)!.status, DownloadStatus.queued);
      expect(svc.taskFor(3)!.status, DownloadStatus.queued);

      adapter.release(urlOf(1));
      await until(
        () => svc.taskFor(1)!.status == DownloadStatus.completed,
        '第 1 个完成',
      );
      await until(() => adapter.started.length == 2, '第 2 个开跑');
      expect(adapter.started, [urlOf(1), urlOf(2)]);

      adapter.release(urlOf(2));
      await until(() => adapter.started.length == 3, '第 3 个开跑');
      adapter.release(urlOf(3));
      await until(
        () => svc.tasks.every((t) => t.status == DownloadStatus.completed),
        '全部完成',
      );
      expect(adapter.started, [urlOf(1), urlOf(2), urlOf(3)]);
      for (final t in svc.tasks) {
        expect(File(t.filePath).existsSync(), isTrue);
        expect(t.fileSize, greaterThan(0));
      }
    });

    test('失败不阻塞队列：失败任务置 failed，后续照常下载', () async {
      adapter.failing.add(urlOf(1));
      await enqueue(1);
      await enqueue(2);
      await until(
        () => svc.taskFor(1)!.status == DownloadStatus.failed,
        '第 1 个失败',
      );
      await until(() => adapter.started.contains(urlOf(2)), '第 2 个开跑');
      adapter.release(urlOf(2));
      await until(
        () => svc.taskFor(2)!.status == DownloadStatus.completed,
        '第 2 个完成',
      );
      expect(svc.taskFor(1)!.errorMessage, isNotNull);
    });

    test('空文件不置完成：置 failed 且不阻塞后续', () async {
      adapter.empty.add(urlOf(1));
      await enqueue(1);
      await enqueue(2);
      await until(
        () => svc.taskFor(1)!.status == DownloadStatus.failed,
        '空文件任务失败',
      );
      await until(() => adapter.started.contains(urlOf(2)), '第 2 个开跑');
      adapter.release(urlOf(2));
      await until(
        () => svc.taskFor(2)!.status == DownloadStatus.completed,
        '第 2 个完成',
      );
    });

    test('暂停排队中任务：轮到时跳过，继续后补上', () async {
      await enqueue(1);
      await enqueue(2);
      await enqueue(3);
      await until(() => adapter.started.isNotEmpty, '第 1 个开跑');
      svc.pause(svc.taskFor(2)!);
      expect(svc.taskFor(2)!.status, DownloadStatus.paused);

      adapter.release(urlOf(1));
      await until(() => adapter.started.contains(urlOf(3)), '跳过 2 直接下 3');
      expect(adapter.started, isNot(contains(urlOf(2))));

      adapter.release(urlOf(3));
      await until(
        () => svc.taskFor(3)!.status == DownloadStatus.completed,
        '第 3 个完成',
      );
      expect(svc.taskFor(2)!.status, DownloadStatus.paused);

      svc.resume(svc.taskFor(2)!);
      await until(() => adapter.started.contains(urlOf(2)), '继续后 2 开跑');
      adapter.release(urlOf(2));
      await until(
        () => svc.taskFor(2)!.status == DownloadStatus.completed,
        '第 2 个完成',
      );
    });

    test('暂停正在下的任务：中断它并推进下一个', () async {
      await enqueue(1);
      await enqueue(2);
      await until(() => adapter.started.isNotEmpty, '第 1 个开跑');
      svc.pause(svc.taskFor(1)!);
      await until(
        () => svc.taskFor(1)!.status == DownloadStatus.paused,
        '第 1 个落为暂停',
      );
      await until(() => adapter.started.contains(urlOf(2)), '第 2 个接上');
      adapter.release(urlOf(2));
      await until(
        () => svc.taskFor(2)!.status == DownloadStatus.completed,
        '第 2 个完成',
      );
      // 被暂停的半截文件已清除
      expect(File(svc.taskFor(1)!.filePath).existsSync(), isFalse);
    });
  });
}
