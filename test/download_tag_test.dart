import 'dart:convert';
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
  return stripBom(String.fromCharCodes(units));
}

String stripBom(String s) => s.startsWith('\uFEFF') ? s.substring(1) : s;

/// 解析 COMM/TXXX 这类「多段 UTF-16 字符串」payload：跳过 [skip] 字节
/// 前缀（COMM 为 编码+语言 共 4 字节，TXXX 为编码 1 字节）后，
/// 按 0x0000 码元切分并去 BOM。COMM → ['', 正文]，TXXX → [键, 值]。
List<String> decodeUtf16Parts(Uint8List payload, {required int skip}) {
  final units = <int>[];
  for (var i = skip; i + 1 < payload.length; i += 2) {
    units.add(payload[i] | (payload[i + 1] << 8));
  }
  final parts = <String>[];
  var cur = <int>[];
  for (final u in units) {
    if (u == 0) {
      parts.add(stripBom(String.fromCharCodes(cur)));
      cur = [];
    } else {
      cur.add(u);
    }
  }
  if (cur.isNotEmpty) parts.add(stripBom(String.fromCharCodes(cur)));
  return parts;
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

    test('扩展帧往返：COMM/TCON/TDRC/TLEN/TRCK(序号/总集数)/TXXX', () {
      final tag = AudioTagWriter.buildTag(
        const AudioTagData(
          title: '标题',
          album: '专辑',
          artist: '主播',
          trackNumber: 3,
          totalTracks: 12,
          description: '这是一段专辑简介',
          genre: '有声书',
          releaseDate: '2023-11-14',
          durationMs: 754000,
          custom: [('trackId', '42'), ('source', 'ximalaya')],
        ),
      );
      final frames = AudioTagWriter.parseFrames(tag);
      expect(decodeTextFrame(frames['TRCK']!.single), '3/12');
      expect(decodeTextFrame(frames['TCON']!.single), '有声书');
      expect(decodeTextFrame(frames['TDRC']!.single), '2023-11-14');
      expect(decodeTextFrame(frames['TLEN']!.single), '754000');
      expect(decodeUtf16Parts(frames['COMM']!.single, skip: 4), [
        '',
        '这是一段专辑简介',
      ]);
      final txxx = frames['TXXX']!
          .map((p) => decodeUtf16Parts(p, skip: 1))
          .toList();
      expect(txxx, contains(equals(['trackId', '42'])));
      expect(txxx, contains(equals(['source', 'ximalaya'])));
    });

    test('可选字段全空时不写任何扩展帧', () {
      final tag = AudioTagWriter.buildTag(
        const AudioTagData(title: 't', album: 'a', artist: 'b'),
      );
      final frames = AudioTagWriter.parseFrames(tag);
      for (final id in ['COMM', 'TCON', 'TDRC', 'TLEN', 'TXXX']) {
        expect(frames.containsKey(id), isFalse, reason: id);
      }
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
      // 写标签是 iOS 逻辑：测试宿主非 iOS，显式打开门控走写标签路径
      svc.isIOS = () => true;
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
      String intro = '',
      String categoryName = '',
      int albumTotal = 0,
      String trackJson = '',
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
        intro: intro,
        categoryName: categoryName,
        albumTotal: albumTotal,
        trackJson: trackJson,
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

    test('平台门控：非 iOS 时 mp3 也不写标签，文件不动', () async {
      svc.isIOS = () => false;
      final audio = fakeAudio();
      final path = '${dir.path}/e.mp3';
      await File(path).writeAsBytes(audio);
      final task = completedTask('e.mp3', path);
      await svc.applyTagsForTest(task);
      expect(task.tagged, isFalse);
      expect(await File(path).readAsBytes(), audio);
    });

    test('平台门控：默认判定取 Platform.isIOS', () {
      final fresh = DownloadService(
        FakeResolver((_) => const PlayResult()),
        svc.settings,
      );
      expect(fresh.isIOS(), Platform.isIOS);
    });

    test('全量元信息写入：COMM/TCON/TDRC/TLEN/TRCK(序号/总)/TXXX', () async {
      final path = '${dir.path}/full.mp3';
      await File(path).writeAsBytes(fakeAudio());
      const createdMs = 1700000000000;
      final track = Track(
        trackId: 5,
        albumId: 9,
        title: '标题乙',
        nickname: '主播丙',
        duration: 60,
        playtimes: 12345,
        createdAt: createdMs,
        isPaid: true,
      );
      final task = completedTask(
        'full.mp3',
        path,
        intro: '简介文字',
        categoryName: '有声书',
        albumTotal: 24,
        trackJson: jsonEncode(track.toJson()),
      );
      await svc.applyTagsForTest(task);
      expect(task.tagged, isTrue);
      final frames = AudioTagWriter.parseFrames(await File(path).readAsBytes());
      expect(decodeTextFrame(frames['TRCK']!.single), '2/24');
      expect(decodeTextFrame(frames['TCON']!.single), '有声书');
      expect(decodeTextFrame(frames['TLEN']!.single), '60000');
      final d = DateTime.fromMillisecondsSinceEpoch(createdMs);
      final expectedDate =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      expect(decodeTextFrame(frames['TDRC']!.single), expectedDate);
      expect(decodeUtf16Parts(frames['COMM']!.single, skip: 4).last, '简介文字');
      final txxx = frames['TXXX']!
          .map((p) => decodeUtf16Parts(p, skip: 1))
          .toList();
      expect(txxx, contains(equals(['trackId', '5'])));
      expect(txxx, contains(equals(['albumId', '9'])));
      expect(txxx, contains(equals(['playtimes', '12345'])));
      expect(txxx, contains(equals(['source', 'ximalaya'])));
      expect(txxx, contains(equals(['isPaid', 'true'])));
    });

    test('拿不到的字段不写：无简介/分类/日期/播放量时相应帧缺省', () async {
      final path = '${dir.path}/bare.mp3';
      await File(path).writeAsBytes(fakeAudio());
      // completedTask 默认无 intro/category，trackJson 为空（发布日期/
      // 播放量/付费标记都拿不到）
      final task = completedTask('bare.mp3', path);
      await svc.applyTagsForTest(task);
      expect(task.tagged, isTrue);
      final frames = AudioTagWriter.parseFrames(await File(path).readAsBytes());
      expect(frames.containsKey('COMM'), isFalse);
      expect(frames.containsKey('TCON'), isFalse);
      expect(frames.containsKey('TDRC'), isFalse);
      expect(decodeTextFrame(frames['TRCK']!.single), '2'); // 无总集数
      final txxxKeys = frames['TXXX']!
          .map((p) => decodeUtf16Parts(p, skip: 1).first)
          .toSet();
      expect(txxxKeys, {'trackId', 'albumId', 'source'});
    });

    test('任务新字段（intro/categoryName/albumTotal）JSON 往返与旧数据缺省', () {
      final task = completedTask(
        'a.mp3',
        '/x/a.mp3',
        intro: '简介',
        categoryName: '分类',
        albumTotal: 24,
      );
      final restored = DownloadTask.fromJson(task.toJson());
      expect(restored.intro, '简介');
      expect(restored.categoryName, '分类');
      expect(restored.albumTotal, 24);
      final legacy = task.toJson()
        ..remove('intro')
        ..remove('categoryName')
        ..remove('albumTotal');
      final fromLegacy = DownloadTask.fromJson(legacy);
      expect(fromLegacy.intro, '');
      expect(fromLegacy.categoryName, '');
      expect(fromLegacy.albumTotal, 0);
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
