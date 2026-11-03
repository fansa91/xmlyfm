import 'package:flutter_test/flutter_test.dart';
import 'package:xmlyfm/models/models.dart';
import 'package:xmlyfm/services/play_resolver.dart';
import 'package:xmlyfm/services/ximalaya_service.dart';

/// 可编程的假服务：不发网络请求，只按预设返回/抛错。
class FakeService extends XimalayaService {
  TrackPayInfo? payInfo;
  BaseInfoResult? baseInfo;
  bool throwOnPay = false;
  bool v4Used = false;

  @override
  Future<TrackPayInfo> fetchTrackPay(int trackId) async {
    if (throwOnPay) throw const XmException('付费信息获取失败');
    return payInfo!;
  }

  @override
  Future<BaseInfoResult> fetchBaseInfoV3(int trackId, int quality) async =>
      baseInfo!;

  @override
  Future<BaseInfoResult> fetchBaseInfoV4(int trackId, int quality) async {
    v4Used = true;
    return baseInfo!;
  }
}

const _payInfo = TrackPayInfo(
  isAuthorized: false,
  sampleDuration: 180,
  sampleLength: 100,
  totalLength: 1000,
  duration: 600,
);

const _baseInfo = BaseInfoResult(
  playUrlInfos: [
    PlayUrlInfo(url: 'https://cdn.example.com/a.mp3', type: 'mp3_64', qualityLevel: 1, fileSize: 10),
  ],
  sampleDuration: 0,
);

void main() {
  group('PlayResolver 三路分流', () {
    test('路线 1：列表直带 URL 直接用', () async {
      final resolver = PlayResolver(FakeService());
      const track = Track(
        trackId: 1,
        albumId: 1,
        title: '免费集',
        playUrl64: 'https://cdn.example.com/direct.mp3',
      );
      final result = await resolver.resolve(track, quality: 1);
      expect(result.url, 'https://cdn.example.com/direct.mp3');
      expect(result.isSample, isFalse);
    });

    test('路线 1 优先于路线 2：付费专辑的免费集带 URL 直接播', () async {
      final service = FakeService()..payInfo = _payInfo;
      final resolver = PlayResolver(service);
      const track = Track(
        trackId: 2,
        albumId: 1,
        title: '免费集',
        isPaid: true,
        isFree: true,
        playUrl64: 'https://cdn.example.com/free-ep.mp3',
      );
      final result = await resolver.resolve(track, quality: 1);
      expect(result.url, 'https://cdn.example.com/free-ep.mp3');
      expect(result.isSample, isFalse);
    });

    test('路线 2：收费集返回 url=null + 试听标记，不拼最终 URL', () async {
      final service = FakeService()..payInfo = _payInfo;
      final resolver = PlayResolver(service);
      const track = Track(
        trackId: 16936452,
        albumId: 4310087,
        title: '收费集',
        isPaid: true,
        isFree: false,
        sampleDuration: 180,
      );
      final result = await resolver.resolve(track, quality: 1);
      expect(result.url, isNull);
      expect(result.isSample, isTrue);
      expect(result.sampleDuration, 180);
      expect(result.notice, isNotNull);
      expect(result.notice, contains('试听'));
    });

    test('路线 2：track pay 请求失败也返回试听提示而非抛错', () async {
      final service = FakeService()..throwOnPay = true;
      final resolver = PlayResolver(service);
      const track = Track(
        trackId: 3,
        albumId: 1,
        title: '收费集',
        isPaid: true,
        isFree: false,
        sampleDuration: 120,
      );
      final result = await resolver.resolve(track, quality: 1);
      expect(result.url, isNull);
      expect(result.isSample, isTrue);
      expect(result.sampleDuration, 120);
      expect(result.notice, contains('付费集暂不能播放'));
    });

    test('路线 3：普通声音走 baseInfo', () async {
      final service = FakeService()..baseInfo = _baseInfo;
      final resolver = PlayResolver(service);
      const track = Track(trackId: 4, albumId: 1, title: '普通声音');
      final result = await resolver.resolve(track, quality: 1);
      expect(result.url, 'https://cdn.example.com/a.mp3');
      expect(service.v4Used, isFalse);
    });

    test('路线 3：useBaseInfoV4 开关切到 v4', () async {
      final service = FakeService()..baseInfo = _baseInfo;
      final resolver = PlayResolver(service)..useBaseInfoV4 = true;
      const track = Track(trackId: 5, albumId: 1, title: '普通声音');
      final result = await resolver.resolve(track, quality: 1);
      expect(result.url, 'https://cdn.example.com/a.mp3');
      expect(service.v4Used, isTrue);
    });

    test('路线 3：baseInfo 无可用 URL 时抛 XmException', () async {
      final service = FakeService()
        ..baseInfo = const BaseInfoResult(playUrlInfos: [], sampleDuration: 0);
      final resolver = PlayResolver(service);
      const track = Track(trackId: 6, albumId: 1, title: '无地址');
      expect(
        () => resolver.resolve(track, quality: 1),
        throwsA(isA<XmException>()),
      );
    });
  });
}
