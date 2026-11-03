import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xmlyfm/services/download_filename.dart';
import 'package:xmlyfm/services/download_service.dart';
import 'package:xmlyfm/services/settings_service.dart';

void main() {
  group('DownloadFileNameFormatter.render', () {
    test('默认模板：专辑 - 两位序号 - 标题', () {
      final out = DownloadFileNameFormatter.render(
        DownloadFileNameFormatter.defaultFormat,
        album: '暮色航行',
        title: '秋风信件',
        index: 3,
        trackId: 42,
        author: '拾光电台',
      );
      expect(out, '暮色航行 - 03 - 秋风信件');
    });

    test('全部变量替换，序号超过两位数不截断', () {
      final out = DownloadFileNameFormatter.render(
        '{author}_{album}_{index}_{title}_{trackId}',
        album: '专辑',
        title: '标题',
        index: 123,
        trackId: 987,
        author: '主播',
      );
      expect(out, '主播_专辑_123_标题_987');
    });

    test('标题中的非法字符清洗为 _', () {
      final out = DownloadFileNameFormatter.render(
        '{title}',
        album: '',
        title: 'a/b\\c:d*e?f"g<h>i|j',
        index: 1,
        trackId: 1,
        author: '',
      );
      expect(out, 'a_b_c_d_e_f_g_h_i_j');
    });

    test('渲染为空时回落到标题，再空回落 track_<id>', () {
      expect(
        DownloadFileNameFormatter.render(
          '{album}',
          album: '',
          title: '只有标题',
          index: 1,
          trackId: 7,
          author: '',
        ),
        '只有标题',
      );
      expect(
        DownloadFileNameFormatter.render(
          '{album}',
          album: '',
          title: '',
          index: 1,
          trackId: 7,
          author: '',
        ),
        'track_7',
      );
    });
  });

  group('DownloadFileNameFormatter.sanitize', () {
    test('去首尾空白与结尾点号', () {
      expect(DownloadFileNameFormatter.sanitize('  abc.  '), 'abc');
    });

    test('超长截断到 120', () {
      final out = DownloadFileNameFormatter.sanitize('x' * 200);
      expect(out.length, 120);
    });
  });

  group('DownloadFileNameFormatter.uniqueName', () {
    test('无冲突原样返回', () {
      expect(
        DownloadFileNameFormatter.uniqueName('a', '.mp3', (_) => false),
        'a.mp3',
      );
    });

    test('冲突依次追加 (1) (2)', () {
      final taken = {'a.mp3', 'a (1).mp3'};
      expect(
        DownloadFileNameFormatter.uniqueName(
          'a',
          '.mp3',
          (c) => taken.contains(c),
        ),
        'a (2).mp3',
      );
    });
  });

  group('DownloadFileNameFormatter.extensionForUrl', () {
    test('常见扩展名识别（带查询参数）', () {
      expect(
        DownloadFileNameFormatter.extensionForUrl(
          'https://cdn.example.com/x/y.m4a?sign=abc',
        ),
        '.m4a',
      );
      expect(
        DownloadFileNameFormatter.extensionForUrl('https://a.com/b.MP3'),
        '.mp3',
      );
    });

    test('未知/无扩展名回落 .mp3', () {
      expect(
        DownloadFileNameFormatter.extensionForUrl('https://a.com/b.xyz'),
        '.mp3',
      );
      expect(
        DownloadFileNameFormatter.extensionForUrl('https://a.com/play'),
        '.mp3',
      );
    });
  });

  group('DownloadTask 序列化', () {
    DownloadTask sample() => DownloadTask(
      trackId: 11,
      albumId: 22,
      albumTitle: '专辑名',
      title: '标题',
      nickname: '主播',
      cover: 'https://img.example.com/c.jpg',
      duration: 754,
      index: 3,
      trackJson: '{"trackId":11}',
      fileName: '专辑名 - 03 - 标题.mp3',
      filePath: '/data/downloads/x.mp3',
      fileSize: 2048,
      downloadedBytes: 1024,
      status: DownloadStatus.downloading,
      createdAt: 1700000000000,
    );

    test('JSON 往返字段一致', () {
      final restored = DownloadTask.fromJson(sample().toJson());
      expect(restored.trackId, 11);
      expect(restored.albumId, 22);
      expect(restored.albumTitle, '专辑名');
      expect(restored.title, '标题');
      expect(restored.fileName, '专辑名 - 03 - 标题.mp3');
      expect(restored.fileSize, 2048);
      expect(restored.downloadedBytes, 1024);
      expect(restored.status, DownloadStatus.downloading);
      expect(restored.trackJson, '{"trackId":11}');
      expect(restored.progress, 0.5);
    });

    test('未知状态回落 paused；toTrack 优先用 trackJson', () {
      final json = sample().toJson()..['status'] = 'whatever';
      final restored = DownloadTask.fromJson(json);
      expect(restored.status, DownloadStatus.paused);
      expect(restored.toTrack().trackId, 11);
    });
  });

  group('下载文件名格式 设置持久化', () {
    test('改后重启恢复；空值不保存', () async {
      SharedPreferences.setMockInitialValues({});
      final s1 = SettingsService();
      await s1.init();
      expect(
        s1.downloadFileNameFormat,
        DownloadFileNameFormatter.defaultFormat,
      );
      await s1.setDownloadFileNameFormat('{title}_{index}');
      await s1.setDownloadFileNameFormat('   ');

      final s2 = SettingsService();
      await s2.init();
      expect(s2.downloadFileNameFormat, '{title}_{index}');
    });
  });
}
