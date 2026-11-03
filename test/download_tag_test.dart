import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xmlyfm/models/models.dart';
import 'package:xmlyfm/services/audio_tag.dart';
import 'package:xmlyfm/services/download_service.dart';
import 'package:xmlyfm/services/play_resolver.dart';
import 'package:xmlyfm/services/settings_service.dart';
import 'package:xmlyfm/services/ximalaya_service.dart';

/// 可编程的假解析器：按 handler 返回结果，不走网络。
class FakeResolver extends PlayResolver {
  FakeResolver(this.handler) : super(XimalayaService());

  final PlayResult Function(Track track) handler;

  @override
  Future<PlayResult> resolve(Track track, {required int quality}) async =>
      handler(track);
}

/// 一段假 MP3 音频字节（帧头 + 填充），不以 ID3 开头。
Uint8List fakeAudio() => Uint8List.fromList([
  0xFF,
  0xFB,
  0x90,
  0x00,
  ...List.generate(300, (i) => (i * 7) % 251),
]);

/// 解码我们写入的 UTF-16LE+BOM 文本帧 payload。
String decodeTextFrame(Uint8List payload) {
  expect(payload[0], 0x01);
  final units = <int>[];
  for (var i = 1; i + 1 < payload.length; i += 2) {
    units.add(payload[i] | (payload[i + 1] << 8));
  }
  var s = String.fromCharCodes(units);
  if (s.startsWith('\uFEFF')) s = s.substring(1);
  return s;
}

void main() {
  group('AudioTagWriter.buildTag / parseFrames 往返', () {
    test('文本帧与 APIC 都能解析回来', () {
      final cover = Uint8List.fromList([9, 8, 7, 6, 5, 4]);
      final tag = AudioTagWriter.buildTag(
        AudioTagData(
          title: '秋风信件',
          album: '暮色航行',
          artist: '拾光电台',
          trackNumber: 3,
          coverBytes: cover,
          coverMime: 'image/png',
        ),
      );
      expect(tag[0], 0x49); // I
      expect(tag[1], 0x44); // D
      expect(tag[2], 0x33); // 3
      expect(tag[3], 0x03); // v2.3
      expect(AudioTagWriter.existingTagLength(tag), tag.length);

      final frames = AudioTagWriter.parseFrames(tag);
      expect(decodeTextFrame(frames['TIT2']!.single), '秋风信件');
      expect(decodeTextFrame(frames['TALB']!.single), '暮色航行');
      expect(decodeTextFrame(frames['TPE1']!.single), '拾光电台');
      expect(decodeTextFrame(frames['TRCK']!.single), '3');

      final apic = frames['APIC']!.single;
      expect(apic[0], 0x00);
      final mimeEnd = apic.indexOf(0, 1);
      expect(String.fromCharCodes(apic.sublist(1, mimeEnd)), 'image/png');
      expect(apic.sublist(apic.length - cover.length), cover);
    });

    test('序号<=0 不写 TRCK，无封面不写 APIC', () {
      final tag = AudioTagWriter.buildTag(
        const AudioTagData(title: 't', album: '', artist: ''),
      );
      final frames = AudioTagWriter.parseFrames(tag);
      expect(frames.containsKey('TRCK'), isFalse);
      expect(frames.containsKey('APIC'), isFalse);
      expect(frames.containsKey('TALB'), isFalse); // 空专辑名不写空帧
    });

    test('supportsTagging 仅 mp3', () {
      expect(AudioTagWriter.supportsTagging('a/b.MP3'), isTrue);
      expect(AudioTagWriter.supportsTagging('x.m4a'), isFalse);
      expect(AudioTagWriter.supportsTagging('x.mp4'), isFalse);
      expect(AudioTagWriter.supportsTagging('x.aac'), isFalse);
    });
  });

  group('AudioTagWriter.writeToFile', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('tag_test');
    });
    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('写入后音频部分原样保留，标签可解析', () async {
      final audio = fakeAudio();
      final f = File('${dir.path}/a.mp3');
      await f.writeAsBytes(audio);
      const data = AudioTagData(
        title: '标题',
        album: '专辑',
        artist: '主播',
        trackNumber: 2,
      );
      expect(await AudioTagWriter.writeToFile(f, data), isTrue);
      final out = await f.readAsBytes();
      final tagLen = AudioTagWriter.existingTagLength(out);
      expect(tagLen, greaterThan(10));
      expect(out.sublist(tagLen), audio);
      final frames = AudioTagWriter.parseFrames(out);
      expect(decodeTextFrame(frames['TIT2']!.single), '标题');
      expect(File('${f.path}.tagging').existsSync(), isFalse);
    });

    test('二次写入替换旧标签：只有一个 TIT2，音频不膨胀', () async {
      final audio = fakeAudio();
      final f = File('${dir.path}/b.mp3');
      await f.writeAsBytes(audio);
      await AudioTagWriter.writeToFile(
        f,
        const AudioTagData(title: '很长很长的旧标题需要被替换掉', album: 'A', artist: 'B'),
      );
      await AudioTagWriter.writeToFile(
        f,
        const AudioTagData(title: '新', album: 'A', artist: 'B'),
      );
      final out = await f.readAsBytes();
      final tagLen = AudioTagWriter.existingTagLength(out);
      expect(out.sublist(tagLen), audio); // 音频尾巴仍是原始字节
      final frames = AudioTagWriter.parseFrames(out);
      expect(frames['TIT2']!.length, 1); // 没有叠两个标签头
      expect(decodeTextFrame(frames['TIT2']!.single), '新');
    });
  });

  group('DownloadService 写标签（applyTagsForTest）', () {
    late Directory dir;
    late DownloadService svc;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService();
      await settings.init();
      svc = DownloadService(FakeResolver((_) => const PlayResult()), settings);
      dir = await Directory.systemTemp.createTemp('svc_tag');
      await svc.initForTest(dir);
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    DownloadTask completedTask(
      String fileName,
      String path, {
      String cover = '',
    }) {
      return DownloadTask(
        trackId: 5,
        albumId: 9,
        albumTitle: '专辑甲',
        title: '标题乙',
        nickname: '主播丙',
        cover: cover,
        duration: 60,
        index: 2,
        fileName: fileName,
        filePath: path,
        fileSize: 0,
        status: DownloadStatus.completed,
        createdAt: 1,
      );
    }

    test('mp3 写 ID3 成功：tagged=true 且 fileSize 回填', () async {
      final audio = fakeAudio();
      final path = '${dir.path}/a.mp3';
      await File(path).writeAsBytes(audio);
      final task = completedTask('a.mp3', path);
      await svc.applyTagsForTest(task);
      expect(task.tagged, isTrue);
      final out = await File(path).readAsBytes();
      expect(task.fileSize, out.length);
      expect(out.length, greaterThan(audio.length));
      final frames = AudioTagWriter.parseFrames(out);
      expect(decodeTextFrame(frames['TIT2']!.single), '标题乙');
      expect(decodeTextFrame(frames['TALB']!.single), '专辑甲');
      expect(decodeTextFrame(frames['TPE1']!.single), '主播丙');
      expect(decodeTextFrame(frames['TRCK']!.single), '2');
      expect(frames.containsKey('APIC'), isFalse); // 无封面地址
    });

    test('m4a 跳过本体标签：tagged=false 且文件不动', () async {
      final audio = fakeAudio();
      final path = '${dir.path}/a.m4a';
      await File(path).writeAsBytes(audio);
      final task = completedTask('a.m4a', path);
      await svc.applyTagsForTest(task);
      expect(task.tagged, isFalse);
      expect(await File(path).readAsBytes(), audio);
    });

    test('封面拉取成功则嵌入 APIC', () async {
      final coverBytes = Uint8List.fromList([1, 2, 3, 250, 251, 252]);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) {
        req.response.headers.contentType = ContentType('image', 'png');
        req.response.add(coverBytes);
        req.response.close();
      });
      try {
        final path = '${dir.path}/c.mp3';
        await File(path).writeAsBytes(fakeAudio());
        final task = completedTask(
          'c.mp3',
          path,
          cover: 'http://127.0.0.1:${server.port}/cover.png',
        );
        await svc.applyTagsForTest(task);
        expect(task.tagged, isTrue);
        final frames = AudioTagWriter.parseFrames(
          await File(path).readAsBytes(),
        );
        final apic = frames['APIC']!.single;
        final mimeEnd = apic.indexOf(0, 1);
        expect(String.fromCharCodes(apic.sublist(1, mimeEnd)), 'image/png');
        expect(apic.sublist(apic.length - coverBytes.length), coverBytes);
      } finally {
        await server.close(force: true);
      }
    });

    test('封面拉取失败仍写无图标签', () async {
      final path = '${dir.path}/d.mp3';
      await File(path).writeAsBytes(fakeAudio());
      final task = completedTask(
        'd.mp3',
        path,
        cover: 'http://127.0.0.1:9/x.jpg', // 端口 9 无人监听，立即拒绝
      );
      await svc.applyTagsForTest(task);
      expect(task.tagged, isTrue);
      final frames = AudioTagWriter.parseFrames(await File(path).readAsBytes());
      expect(frames.containsKey('TIT2'), isTrue);
      expect(frames.containsKey('APIC'), isFalse);
    });

    test('tagged 标记随任务 JSON 往返持久化', () {
      final task = completedTask('a.mp3', '/x/a.mp3')..tagged = true;
      final restored = DownloadTask.fromJson(task.toJson());
      expect(restored.tagged, isTrue);
      final legacy = task.toJson()..remove('tagged');
      expect(DownloadTask.fromJson(legacy).tagged, isFalse);
    });
  });
}
