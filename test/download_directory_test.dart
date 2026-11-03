import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xmlyfm/models/models.dart';
import 'package:xmlyfm/services/download_service.dart';
import 'package:xmlyfm/services/play_resolver.dart';
import 'package:xmlyfm/services/settings_service.dart';
import 'package:xmlyfm/services/ximalaya_service.dart';

/// 可编程的假解析器：不走网络（本文件用例不触发解析，仅满足构造）。
class FakeResolver extends PlayResolver {
  FakeResolver() : super(XimalayaService());

  @override
  Future<PlayResult> resolve(Track track, {required int quality}) async =>
      const PlayResult();
}

void main() {
  group('SettingsService 下载目录设置', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('默认未设置（空串），设置后持久化、重初始化可读回', () async {
      final s1 = SettingsService();
      await s1.init();
      expect(s1.downloadDirectory, '');
      await s1.setDownloadDirectory('  /data/music  ');
      expect(s1.downloadDirectory, '/data/music'); // 两端空白被裁掉

      final s2 = SettingsService();
      await s2.init();
      expect(s2.downloadDirectory, '/data/music');

      await s2.setDownloadDirectory('');
      expect(s2.downloadDirectory, '');
    });

    test('「默认下载路径」设置项显隐：iOS 隐藏、非 iOS 显示', () async {
      final s = SettingsService();
      await s.init();
      s.isIOS = () => true;
      expect(s.showDownloadDirectorySetting, isFalse);
      s.isIOS = () => false;
      expect(s.showDownloadDirectorySetting, isTrue);
    });
  });

  group('DownloadService 生效目录解析', () {
    late Directory base;
    late Directory defaultDir;

    setUp(() async {
      base = await Directory.systemTemp.createTemp('dl_dir');
      defaultDir = Directory('${base.path}/downloads');
    });

    tearDown(() async {
      if (await base.exists()) await base.delete(recursive: true);
    });

    test('prepareDirectory：新建目录可写且探针文件清理干净', () async {
      final dir = Directory('${base.path}/a/b');
      expect(await DownloadService.prepareDirectory(dir), isTrue);
      expect(await dir.exists(), isTrue);
      expect(File('${dir.path}/.xmlyfm_probe').existsSync(), isFalse);
    });

    test('prepareDirectory：路径是普通文件时失败', () async {
      final f = File('${base.path}/afile');
      await f.writeAsString('x');
      expect(
        await DownloadService.prepareDirectory(Directory(f.path)),
        isFalse,
      );
    });

    test('未设置自定义 → 默认目录', () async {
      final dir = await DownloadService.resolveDownloadDirectory(
        customPath: '',
        defaultDir: defaultDir,
        ios: false,
      );
      expect(dir.path, defaultDir.path);
      expect(await defaultDir.exists(), isTrue);
    });

    test('自定义目录可用 → 用自定义（不存在自动创建）', () async {
      final custom = Directory('${base.path}/custom/sub');
      final dir = await DownloadService.resolveDownloadDirectory(
        customPath: custom.path,
        defaultDir: defaultDir,
        ios: false,
      );
      expect(dir.path, custom.path);
      expect(await custom.exists(), isTrue);
    });

    test('自定义目录不可用（路径是文件）→ 回落默认目录', () async {
      final f = File('${base.path}/afile');
      await f.writeAsString('x');
      final dir = await DownloadService.resolveDownloadDirectory(
        customPath: f.path,
        defaultDir: defaultDir,
        ios: false,
      );
      expect(dir.path, defaultDir.path);
    });

    test('iOS 忽略自定义目录：用默认且不创建自定义目录', () async {
      final custom = Directory('${base.path}/custom');
      final dir = await DownloadService.resolveDownloadDirectory(
        customPath: custom.path,
        defaultDir: defaultDir,
        ios: true,
      );
      expect(dir.path, defaultDir.path);
      expect(await custom.exists(), isFalse);
    });
  });

  group('任务文件路径持久化（换目录不影响已完成记录）', () {
    late Directory dir;
    late DownloadService svc;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('dl_tasks');
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    Map<String, dynamic> completedTaskJson({
      required String fileName,
      String? filePath,
    }) {
      final task = DownloadTask(
        trackId: 7,
        albumId: 3,
        albumTitle: '专辑',
        title: '标题',
        nickname: '主播',
        cover: '',
        duration: 10,
        index: 1,
        fileName: fileName,
        filePath: filePath ?? '',
        status: DownloadStatus.completed,
        createdAt: 1,
      );
      final json = task.toJson();
      if (filePath == null) json.remove('filePath'); // 模拟旧版本记录
      return json;
    }

    Future<void> seedAndInit(List<Map<String, dynamic>> tasks) async {
      SharedPreferences.setMockInitialValues({
        'download_tasks': jsonEncode(tasks),
      });
      final settings = SettingsService();
      await settings.init();
      svc = DownloadService(FakeResolver(), settings);
      await svc.initForTest(dir);
    }

    test('filePath 随任务 JSON 往返保存', () {
      final json = completedTaskJson(
        fileName: 'a.mp3',
        filePath: '/somewhere/a.mp3',
      );
      expect(json['filePath'], '/somewhere/a.mp3');
      final restored = DownloadTask.fromJson(json);
      expect(restored.filePath, '/somewhere/a.mp3');
    });

    test('旧记录无 filePath：按默认目录重建，已完成记录保留', () async {
      await File('${dir.path}/a.mp3').writeAsBytes([1, 2, 3]);
      await seedAndInit([completedTaskJson(fileName: 'a.mp3')]);
      expect(svc.tasks.length, 1);
      expect(svc.tasks.single.filePath, '${dir.path}/a.mp3');
      expect(svc.localPathFor(7), '${dir.path}/a.mp3');
      expect(svc.defaultDirPath, dir.path);
      expect(svc.downloadDirPath, dir.path);
    });

    test('已存绝对路径指向别处：换默认目录后记录仍指向原文件', () async {
      final other = await Directory.systemTemp.createTemp('dl_other');
      try {
        await File('${other.path}/b.mp3').writeAsBytes([9]);
        await seedAndInit([
          completedTaskJson(
            fileName: 'b.mp3',
            filePath: '${other.path}/b.mp3',
          ),
        ]);
        expect(svc.tasks.length, 1);
        expect(svc.tasks.single.filePath, '${other.path}/b.mp3');
        expect(svc.localPathFor(7), '${other.path}/b.mp3');
      } finally {
        if (await other.exists()) await other.delete(recursive: true);
      }
    });
  });
}
