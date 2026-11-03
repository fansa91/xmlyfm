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

  /// 下载专用解析：在 [resolve] 的三路分流之上**优先取 MP3 直链**。
  ///
  /// 写文件标签（ID3）只支持 MP3，而播放按音质择优时常先命中 m4a
  /// （高清档 directUrlForQuality 是 playUrl64M4a 优先于 playUrl64），
  /// 下回来是 m4a 就写不进标签。故下载单独走这条优先级
  /// （XIMALAYA_API.md §5.7 实测口径：字段名不代表格式，playUrl64
  /// 才是 64k mp3；没有强制格式的参数）：
  /// 1. 列表直带 playUrl64（64k mp3）→ playUrl32（32k mp3）；
  /// 2. baseInfo 的 playUrlInfos 中 type 为 mp3_64 → mp3_32 的条目；
  /// 3. 回落到 [resolve] 的常规结果（m4a 等其他格式）。
  ///
  /// 收费集（isChargeTrack）不走 1/2：直接由 [resolve] 的 track pay
  /// 路径处理，试听拦截语义不变。播放路径不要用这个方法——
  /// 播放仍按用户音质设置走 [resolve]。
  Future<PlayResult> resolveForDownload(
    Track track, {
    required int quality,
  }) async {
    if (!track.isChargeTrack) {
      // 1. 列表直带 mp3
      for (final u in [track.playUrl64, track.playUrl32]) {
        if (u.isNotEmpty) return PlayResult(url: u);
      }
      // 2. baseInfo 里的 mp3 条目
      try {
        final info = useBaseInfoV4
            ? await service.fetchBaseInfoV4(track.trackId, quality)
            : await service.fetchBaseInfoV3(track.trackId, quality);
        for (final type in const ['mp3_64', 'mp3_32']) {
          for (final i in info.playUrlInfos) {
            if (i.type == type && i.url.isNotEmpty) {
              return PlayResult(
                url: i.url,
                sampleDuration: info.sampleDuration,
              );
            }
          }
        }
      } catch (_) {
        // baseInfo 拿不到不单独报错：回落常规分流，由它统一处理/抛错
      }
    }
    // 3. 常规分流（收费集试听拦截也在其中）
    return resolve(track, quality: quality);
  }
}
