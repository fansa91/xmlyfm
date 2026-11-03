import '../models/models.dart';
import 'ximalaya_service.dart';

/// 播放解析结果。
/// - [url] 可直接播放的地址；为 null 时不能播放，看 [notice]。
/// - [isSample] 是否试听（付费集）：试听时长上限 [sampleDuration] 秒。
class PlayResult {
  final String? url;
  final bool isSample;
  final int sampleDuration;
  final String? notice;

  const PlayResult({
    this.url,
    this.isSample = false,
    this.sampleDuration = 0,
    this.notice,
  });
}

/// 播放链接三路分流（XIMALAYA_API.md §5）：
/// 1. 列表自带 URL 非空 → 按音质择优直接用；
/// 2. 收费集（isPaid && !isFree）→ track pay 只取元数据：最终 URL 需要
///    官方 App native 层解密 fileId/ep，v1 不拼，返回 url=null + 试听标记；
/// 3. 普通声音 → baseInfo（v3 无签名 / v4 带 sign，[useBaseInfoV4] 可切换）。
class PlayResolver {
  final XimalayaService service;

  /// baseInfo 是否走 v4（带 sign）。默认 v3。
  bool useBaseInfoV4 = false;

  PlayResolver(this.service);

  Future<PlayResult> resolve(Track track, {required int quality}) async {
    // 1. 列表直带 URL
    final direct = track.directUrlForQuality(quality);
    if (direct != null && direct.isNotEmpty) {
      return PlayResult(url: direct);
    }

    // 2. 收费集 → track pay 元数据
    if (track.isChargeTrack) {
      try {
        final pay = await service.fetchTrackPay(track.trackId);
        final sample = pay.sampleDuration > 0
            ? pay.sampleDuration
            : track.sampleDuration;
        return PlayResult(
          url: null,
          isSample: true,
          sampleDuration: sample,
          notice: pay.isAuthorized
              ? '该付费集的完整播放地址需官方客户端解密，xmlyfm 暂不支持播放'
              : '付费集仅支持在官方客户端试听（可试听 $sample 秒）或购买，xmlyfm 暂不能播放',
        );
      } on XmException catch (e) {
        return PlayResult(
          url: null,
          isSample: true,
          sampleDuration: track.sampleDuration,
          notice: '付费集暂不能播放：${e.message}',
        );
      }
    }

    // 3. 普通声音 → baseInfo
    final info = useBaseInfoV4
        ? await service.fetchBaseInfoV4(track.trackId, quality)
        : await service.fetchBaseInfoV3(track.trackId, quality);
    final url = info.pickUrl(quality);
    if (url == null) {
      throw const XmException('未获取到可播放地址');
    }
    return PlayResult(url: url, sampleDuration: info.sampleDuration);
  }
}
