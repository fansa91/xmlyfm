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

/// 记录两个解析入口各被调了几次的假解析器：
/// resolve 给 .m4a 地址（模拟按音质取链），resolveForDownload 给 .mp3；
/// 收费集两个入口都回试听结果（与真实解析器的拦截语义一致）。
class RecordingResolver extends PlayResolver {
  RecordingResolver() : super(XimalayaService());

  final List<String> calls = [];

  /// resolve 给出的地址后缀（可切换模拟无损 .fhq 地址）
  String resolveSuffix = '.m4a';

  int get resolveCalls => calls.where((c) => c == 'resolve').length;
  int get resolveForDownloadCalls =>
      calls.where((c) => c == 'resolveForDownload').length;

  @override
  Future<PlayResult> resolve(Track track, {required int quality}) async {
    calls.add('resolve');
    if (track.isChargeTrack) {
      return const PlayResult(isSample: true, sampleDuration: 180);
    }
    return PlayResult(url: 'https://cdn.test/${track.trackId}$resolveSuffix');
  }

  @override
  Future<PlayResult> resolveForDownload(
    Track track, {
    required int quality,
  }) async {
    calls.add('resolveForDownload');
    if (track.isChargeTrack) {
      return const PlayResult(isSample: true, sampleDuration: 180);
    }
    return PlayResult(url: 'https://cdn.test/${track.trackId}.mp3');
  }
}

/// 立即返回字节的假网络层：按 URL 后缀给假音频；
/// .fhq 地址默认回 FLAC 内容（魔数 fLaC），[fhqIsFlac] 关掉则回 m4a 内容。
class BytesAdapter implements HttpClientAdapter {
  bool fhqIsFlac = true;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final url = options.uri.toString();
    final Uint8List bytes;
    if (url.endsWith('.mp3')) {
      bytes = Uint8List.fromList([
        0xFF,
        0xFB,
        0x90,
        0x00,
        ...List.generate(200, (i) => (i * 7) % 251),
      ]);
    } else if (url.endsWith('.fhq') && fhqIsFlac) {
      bytes = Uint8List.fromList([
        0x66, 0x4C, 0x61, 0x43, // fLaC
        ...List.generate(200, (i) => (i * 5) % 251),
      ]);
    } else {
      bytes = Uint8List.fromList('fake-m4a-audio-bytes'.codeUnits);
    }
    return ResponseBody.fromBytes(
      bytes,
      200,
      headers: {
        Headers.contentLengthHeader: ['${bytes.length}'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const _track = Track(
  trackId: 11,
  albumId: 1,
  title: '第十一集',
  nickname: '主播',
  duration: 60,
);

const _chargeTrack = Track(
  trackId: 12,
  albumId: 1,
  title: '收费集',
  nickname: '主播',
  duration: 60,
  isPaid: true,
  isFree: false,
  sampleDuration: 180,
);

void main() {
  group('SettingsService.downloadFormat', () {
    test('缺省为 MP3 优先（mp3）', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService();
      await settings.init();
      expect(settings.downloadFormat, SettingsService.downloadFormatMp3);
    });

    test('写入音质优先后持久化，重新 init 读回', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService();
      await settings.init();
      await settings.setDownloadFormat(SettingsService.downloadFormatQuality);
      expect(settings.downloadFormat, SettingsService.downloadFormatQuality);

      final reloaded = SettingsService();
      await reloaded.init();
      expect(reloaded.downloadFormat, SettingsService.downloadFormatQuality);
    });

    test('持久化了非法值时 init 回落默认 mp3', () async {
      SharedPreferences.setMockInitialValues({'download_format': 'aac'});
      final settings = SettingsService();
      await settings.init();
      expect(settings.downloadFormat, SettingsService.downloadFormatMp3);
    });

    test('setDownloadFormat 传非法值回落默认 mp3', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService();
      await settings.init();
      await settings.setDownloadFormat(SettingsService.downloadFormatQuality);
      await settings.setDownloadFormat('bogus');
      expect(settings.downloadFormat, SettingsService.downloadFormatMp3);
    });
  });

  group('DownloadService 按下载格式选解析路径', () {
    late Directory dir;
    late SettingsService settings;
    late RecordingResolver resolver;
    late BytesAdapter adapter;
    late DownloadService svc;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      settings = SettingsService();
      await settings.init();
      resolver = RecordingResolver();
      adapter = BytesAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      svc = DownloadService(resolver, settings, dio);
      dir = await Directory.systemTemp.createTemp('dl_format');
      await svc.initForTest(dir);
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    Future<void> untilCompleted(int trackId) async {
      for (var i = 0; i < 400; i++) {
        final t = svc.taskFor(trackId);
        if (t != null && t.status == DownloadStatus.completed) return;
        if (t != null && t.status == DownloadStatus.failed) {
          fail('下载失败：${t.errorMessage}');
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      fail('等待下载完成超时');
    }

    test('MP3 优先（默认）：入队与开跑都走 resolveForDownload，落盘 .mp3', () async {
      final err = await svc.enqueueTrack(_track, albumTitle: '专辑', index: 11);
      expect(err, isNull);
      await untilCompleted(11);
      // 入队解析 1 次 + 开跑重解析 1 次，全走下载专用解析
      expect(resolver.resolveForDownloadCalls, 2);
      expect(resolver.resolveCalls, 0);
      expect(svc.taskFor(11)!.fileName.endsWith('.mp3'), isTrue);
    });

    test('音质优先：入队与开跑都走 resolve，落盘 .m4a、不写标签', () async {
      await settings.setDownloadFormat(SettingsService.downloadFormatQuality);
      final err = await svc.enqueueTrack(_track, albumTitle: '专辑', index: 11);
      expect(err, isNull);
      await untilCompleted(11);
      expect(resolver.resolveCalls, 2);
      expect(resolver.resolveForDownloadCalls, 0);
      final task = svc.taskFor(11)!;
      expect(task.fileName.endsWith('.m4a'), isTrue);
      expect(task.tagged, isFalse);
    });

    test('音质优先下付费试听拦截保持：入队被拒且不建任务', () async {
      await settings.setDownloadFormat(SettingsService.downloadFormatQuality);
      final err = await svc.enqueueTrack(
        _chargeTrack,
        albumTitle: '专辑',
        index: 12,
      );
      expect(err, '付费内容仅支持试听，无法下载');
      expect(svc.taskFor(12), isNull);
      expect(resolver.resolveCalls, 1);
      expect(resolver.resolveForDownloadCalls, 0);
    });

    test('无损：.fhq 地址 + FLAC 内容 → 改名 .flac 落盘、不写标签', () async {
      await settings.setDownloadFormat(SettingsService.downloadFormatQuality);
      resolver.resolveSuffix = '.fhq';
      final err = await svc.enqueueTrack(_track, albumTitle: '专辑', index: 11);
      expect(err, isNull);
      await untilCompleted(11);
      final task = svc.taskFor(11)!;
      // 后缀先保留 .fhq、内容嗅探为 fLaC 后改名 .flac，任务记录同步
      expect(task.fileName.endsWith('.flac'), isTrue);
      expect(task.tagged, isFalse);
      final bytes = await File(task.filePath).readAsBytes();
      expect(bytes.sublist(0, 4), [0x66, 0x4C, 0x61, 0x43]); // fLaC 原样
      expect(bytes.sublist(0, 3), isNot([0x49, 0x44, 0x33])); // 没有 ID3 头
    });

    test('无损：.fhq 地址但内容非 FLAC → 保留 .fhq 后缀、不写标签', () async {
      await settings.setDownloadFormat(SettingsService.downloadFormatQuality);
      resolver.resolveSuffix = '.fhq';
      adapter.fhqIsFlac = false;
      final err = await svc.enqueueTrack(_track, albumTitle: '专辑', index: 11);
      expect(err, isNull);
      await untilCompleted(11);
      final task = svc.taskFor(11)!;
      // 魔数不可知/不符：不回落 .mp3 误标，保留 URL 的真实后缀
      expect(task.fileName.endsWith('.fhq'), isTrue);
      expect(task.tagged, isFalse);
    });
  });
}
