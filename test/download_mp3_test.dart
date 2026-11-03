import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xmlyfm/models/models.dart';
import 'package:xmlyfm/screens/downloads_screen.dart';
import 'package:xmlyfm/services/audio_tag.dart';
import 'package:xmlyfm/services/download_service.dart';
import 'package:xmlyfm/services/library_service.dart';
import 'package:xmlyfm/services/play_resolver.dart';
import 'package:xmlyfm/services/player_service.dart';
import 'package:xmlyfm/services/settings_service.dart';
import 'package:xmlyfm/services/ximalaya_service.dart';

/// 假服务：baseInfo / track pay 按预设返回，记录 baseInfo 调用次数。
class FakeService extends XimalayaService {
  BaseInfoResult? baseInfo;
  TrackPayInfo? payInfo;
  bool throwOnBaseInfo = false;
  int baseInfoCalls = 0;

  @override
  Future<BaseInfoResult> fetchBaseInfoV3(int trackId, int quality) async {
    baseInfoCalls++;
    if (throwOnBaseInfo) throw const XmException('baseInfo 失败');
    return baseInfo!;
  }

  @override
  Future<BaseInfoResult> fetchBaseInfoV4(int trackId, int quality) =>
      fetchBaseInfoV3(trackId, quality);

  @override
  Future<TrackPayInfo> fetchTrackPay(int trackId) async => payInfo!;
}

/// 立即返回字节的假网络层：按 URL 后缀给 mp3 / m4a 假音频。
class BytesAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final bytes = options.uri.toString().endsWith('.mp3')
        ? fakeMp3()
        : fakeM4a();
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

/// 假 MP3 音频字节（帧头 + 填充），不以 ID3 开头。
Uint8List fakeMp3() => Uint8List.fromList([
  0xFF,
  0xFB,
  0x90,
  0x00,
  ...List.generate(200, (i) => (i * 7) % 251),
]);

Uint8List fakeM4a() => Uint8List.fromList('fake-m4a-audio-bytes'.codeUnits);

const _m4aOnlyBaseInfo = BaseInfoResult(
  playUrlInfos: [
    PlayUrlInfo(
      url: 'https://cdn.test/8-base.m4a',
      type: 'm4a_64',
      qualityLevel: 1,
      fileSize: 10,
    ),
  ],
  sampleDuration: 0,
);

const _mp3Track = Track(
  trackId: 7,
  albumId: 3,
  title: '第七集',
  nickname: '主播',
  duration: 120,
  playUrl64: 'https://cdn.test/7.mp3',
  playUrl64M4a: 'https://cdn.test/7.m4a',
);

const _m4aTrack = Track(
  trackId: 8,
  albumId: 3,
  title: '第八集',
  nickname: '主播',
  duration: 90,
  playUrl64M4a: 'https://cdn.test/8.m4a',
);

void main() {
  group('PlayResolver.resolveForDownload（mp3 优先）', () {
    test('双格式直带：下载取 playUrl64(mp3)，播放仍取 m4a（行为不变）', () async {
      final resolver = PlayResolver(FakeService());
      const track = Track(
        trackId: 1,
        albumId: 1,
        title: 't',
        playUrl64: 'https://cdn.test/a.mp3',
        playUrl64M4a: 'https://cdn.test/a.m4a',
      );
      final dl = await resolver.resolveForDownload(track, quality: 1);
      expect(dl.url, 'https://cdn.test/a.mp3');
      // 播放走 resolve：高清档原优先级先命中 m4a，不受下载解析影响
      final play = await resolver.resolve(track, quality: 1);
      expect(play.url, 'https://cdn.test/a.m4a');
    });

    test('playUrl64 为空时次选 playUrl32，且不调 baseInfo', () async {
      final service = FakeService();
      final resolver = PlayResolver(service);
      const track = Track(
        trackId: 2,
        albumId: 1,
        title: 't',
        playUrl32: 'https://cdn.test/b32.mp3',
        playUrl64M4a: 'https://cdn.test/b.m4a',
      );
      final dl = await resolver.resolveForDownload(track, quality: 1);
      expect(dl.url, 'https://cdn.test/b32.mp3');
      expect(service.baseInfoCalls, 0);
    });

    test('直带只有 m4a：baseInfo 里 mp3_64 优先于同档 m4a', () async {
      final service = FakeService()
        ..baseInfo = const BaseInfoResult(
          playUrlInfos: [
            PlayUrlInfo(
              url: 'https://cdn.test/c-base.m4a',
              type: 'm4a_64',
              qualityLevel: 1,
              fileSize: 10,
            ),
            PlayUrlInfo(
              url: 'https://cdn.test/c-base.mp3',
              type: 'mp3_64',
              qualityLevel: 1,
              fileSize: 10,
            ),
          ],
          sampleDuration: 0,
        );
      final resolver = PlayResolver(service);
      const track = Track(
        trackId: 3,
        albumId: 1,
        title: 't',
        playUrl64M4a: 'https://cdn.test/c.m4a',
      );
      final dl = await resolver.resolveForDownload(track, quality: 1);
      expect(dl.url, 'https://cdn.test/c-base.mp3');
      // 播放仍是直带优先的 m4a
      final play = await resolver.resolve(track, quality: 1);
      expect(play.url, 'https://cdn.test/c.m4a');
    });

    test('全是 m4a：回落常规解析（直带 m4a）', () async {
      final service = FakeService()..baseInfo = _m4aOnlyBaseInfo;
      final resolver = PlayResolver(service);
      const track = Track(
        trackId: 4,
        albumId: 1,
        title: 't',
        playUrl64M4a: 'https://cdn.test/d.m4a',
      );
      final dl = await resolver.resolveForDownload(track, quality: 1);
      expect(dl.url, 'https://cdn.test/d.m4a');
    });

    test('baseInfo 抛错时回落直带 m4a，不单独报错', () async {
      final service = FakeService()..throwOnBaseInfo = true;
      final resolver = PlayResolver(service);
      const track = Track(
        trackId: 5,
        albumId: 1,
        title: 't',
        playUrl64M4a: 'https://cdn.test/e.m4a',
      );
      final dl = await resolver.resolveForDownload(track, quality: 1);
      expect(dl.url, 'https://cdn.test/e.m4a');
    });

    test('收费集仍走试听拦截，且不进 mp3 优先分支', () async {
      final service = FakeService()
        ..payInfo = const TrackPayInfo(
          isAuthorized: false,
          sampleDuration: 180,
          sampleLength: 100,
          totalLength: 1000,
          duration: 600,
        );
      final resolver = PlayResolver(service);
      const track = Track(
        trackId: 6,
        albumId: 1,
        title: 't',
        isPaid: true,
        isFree: false,
        sampleDuration: 180,
      );
      final dl = await resolver.resolveForDownload(track, quality: 1);
      expect(dl.isSample, isTrue);
      expect(dl.url, isNull);
      expect(service.baseInfoCalls, 0);
    });
  });

  group('DownloadService 下载 mp3 优先（端到端）', () {
    late Directory dir;
    late DownloadService svc;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService();
      await settings.init();
      final service = FakeService()..baseInfo = _m4aOnlyBaseInfo;
      final dio = Dio()..httpClientAdapter = BytesAdapter();
      svc = DownloadService(PlayResolver(service), settings, dio);
      dir = await Directory.systemTemp.createTemp('dl_mp3');
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

    test('双字段 Track：落盘 .mp3、开头是 ID3 头、tagged=true', () async {
      final err = await svc.enqueueTrack(_mp3Track, albumTitle: '专辑', index: 7);
      expect(err, isNull);
      await untilCompleted(7);
      final task = svc.taskFor(7)!;
      expect(task.fileName.endsWith('.mp3'), isTrue);
      expect(task.tagged, isTrue);
      final bytes = await File(task.filePath).readAsBytes();
      expect(bytes.sublist(0, 3), [0x49, 0x44, 0x33]); // "ID3"
      final frames = AudioTagWriter.parseFrames(bytes);
      expect(frames.containsKey('TIT2'), isTrue);
    });

    test('只有 m4a 的 Track：落盘 .m4a、tagged=false、文件原样', () async {
      final err = await svc.enqueueTrack(_m4aTrack, albumTitle: '专辑', index: 8);
      expect(err, isNull);
      await untilCompleted(8);
      final task = svc.taskFor(8)!;
      expect(task.fileName.endsWith('.m4a'), isTrue);
      expect(task.tagged, isFalse);
      final bytes = await File(task.filePath).readAsBytes();
      expect(bytes, fakeM4a()); // 容器不支持写标签，字节与源一致
    });
  });

  group('下载管理页徽标', () {
    testWidgets('已完成项显示格式徽标与标签状态', (tester) async {
      late DownloadService svc;
      late PlayResolver resolver;
      late SettingsService settings;
      late LibraryService library;
      late Directory dir;
      // 真实异步（文件 IO / 下载队列）在 runAsync 里跑完，再 pump 界面
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        settings = SettingsService();
        await settings.init();
        library = LibraryService();
        await library.init();
        final service = FakeService()..baseInfo = _m4aOnlyBaseInfo;
        resolver = PlayResolver(service);
        final dio = Dio()..httpClientAdapter = BytesAdapter();
        svc = DownloadService(resolver, settings, dio);
        dir = await Directory.systemTemp.createTemp('dl_badge');
        await svc.initForTest(dir);
        await svc.enqueueTrack(_mp3Track, albumTitle: '专辑', index: 7);
        await svc.enqueueTrack(_m4aTrack, albumTitle: '专辑', index: 8);
        for (var i = 0; i < 400 && svc.completedTasks.length < 2; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(svc.completedTasks.length, 2);
      });
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: svc),
            // PlayerService 只在点按已完成项时才被 read，构建本页用不到；
            // 用懒创建避免在测试环境构造它（其构造会激活 audioplayers
            // 平台通道，测试环境无插件实现会抛 MissingPluginException）
            ChangeNotifierProvider<PlayerService>(
              create: (_) => PlayerService(resolver, settings, library),
            ),
          ],
          child: const MaterialApp(home: DownloadsScreen(embedded: true)),
        ),
      );
      await tester.pump();

      expect(find.text('MP3'), findsOneWidget);
      expect(find.text('已写标签'), findsOneWidget);
      expect(find.text('M4A'), findsOneWidget);
      expect(find.text('未写标签 · 格式不支持'), findsOneWidget);
    });
  });
}
