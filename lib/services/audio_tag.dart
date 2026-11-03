import 'dart:io';
import 'dart:typed_data';

/// 要写入音频文件的标签数据（下载完成时由 DownloadTask/Track 字段组装）。
/// 可选字段为空/0 时不写对应帧——拿不到的元信息宁可缺省，不编造。
class AudioTagData {
  final String title; // TIT2 声音标题
  final String album; // TALB 专辑名
  final String artist; // TPE1 主播名
  final int trackNumber; // TRCK 集序号（<=0 时不写）
  final int totalTracks; // TRCK 总集数（>0 时写成「序号/总集数」）
  final Uint8List? coverBytes; // APIC 封面图字节（null 时不写封面）
  final String coverMime; // 封面 MIME，如 image/jpeg
  final String description; // COMM 专辑简介
  final String genre; // TCON 分类名
  final String releaseDate; // TDRC 发布日期（yyyy-MM-dd，已格式化）
  final int durationMs; // TLEN 时长（毫秒，<=0 时不写）

  /// TXXX 自定义帧（键→值）：标准帧没有对应项的元信息，如声音/专辑 ID、
  /// 播放量、来源标记、付费标记。空列表不写。
  final List<(String, String)> custom;

  const AudioTagData({
    required this.title,
    required this.album,
    required this.artist,
    this.trackNumber = 0,
    this.totalTracks = 0,
    this.coverBytes,
    this.coverMime = 'image/jpeg',
    this.description = '',
    this.genre = '',
    this.releaseDate = '',
    this.durationMs = 0,
    this.custom = const [],
  });
}

/// MP3 的 ID3v2.3 标签最小写入器（纯 Dart 手写，无第三方依赖）。
///
/// 选型说明：pub.dev 的 id3tag 包只读且 SDK 约束 <3.0 与本工程不兼容，
/// 其余候选或年久失修或走原生通道，故按 ID3v2.3 规格手写：
/// - 文本帧 TIT2/TALB/TPE1/TRCK/TCON/TDRC/TLEN 用 UTF-16LE+BOM
///   （编码 0x01），中文安全；COMM 写简介、TXXX 写标准帧没有的元信息；
/// - APIC 帧写封面（picture type 0x03 主封面）；
/// - 文件已有 ID3v2 标签时按头里的 syncsafe 尺寸整段剥离后重写，
///   只保留一个标签头，不叠加；
/// - 落盘走「写 .tagging 临时文件 → 校验长度/头/音频首字节 → rename 替换」，
///   任何失败都保留原文件并返回 false。
///
/// 非 MP3（m4a/mp4 等 MP4 容器）不在这里处理：ilst 位于容器 box 结构内，
/// 手写改容器风险高，[supportsTagging] 对其返回 false，由调用方跳过。
class AudioTagWriter {
  static const int _padding = 512;

  /// 是否支持给该文件写本体标签（目前仅 .mp3）。
  static bool supportsTagging(String fileName) =>
      fileName.toLowerCase().endsWith('.mp3');

  /// 文件开头已有 ID3v2 标签的总长度（含 10 字节头与可能的 10 字节脚），
  /// 没有返回 0。
  static int existingTagLength(Uint8List bytes) {
    if (bytes.length < 10) return 0;
    if (bytes[0] != 0x49 || bytes[1] != 0x44 || bytes[2] != 0x33) return 0;
    final size =
        ((bytes[6] & 0x7F) << 21) |
        ((bytes[7] & 0x7F) << 14) |
        ((bytes[8] & 0x7F) << 7) |
        (bytes[9] & 0x7F);
    var total = 10 + size;
    if ((bytes[5] & 0x10) != 0) total += 10; // v2.4 footer
    return total;
  }

  /// 构造完整 ID3v2.3 标签字节（含头与尾部 padding）。
  static Uint8List buildTag(AudioTagData data) {
    final frames = BytesBuilder(copy: false);
    void textFrame(String id, String text) {
      if (text.isEmpty) return;
      frames.add(_frame(id, _encodeText(text)));
    }

    textFrame('TIT2', data.title);
    textFrame('TALB', data.album);
    textFrame('TPE1', data.artist);
    if (data.trackNumber > 0) {
      textFrame(
        'TRCK',
        data.totalTracks > 0
            ? '${data.trackNumber}/${data.totalTracks}'
            : '${data.trackNumber}',
      );
    }
    textFrame('TCON', data.genre);
    textFrame('TDRC', data.releaseDate);
    if (data.durationMs > 0) {
      textFrame('TLEN', '${data.durationMs}');
    }
    if (data.description.isNotEmpty) {
      // COMM：编码(0x01) + 语言(eng) + 描述（空，UTF-16 BOM + 终止符）+ 正文
      final payload = BytesBuilder(copy: false)
        ..addByte(0x01)
        ..add(_latin1('eng'))
        ..add(_utf16WithBom(''))
        ..add([0x00, 0x00])
        ..add(_utf16WithBom(data.description));
      frames.add(_frame('COMM', payload.toBytes()));
    }
    for (final (key, value) in data.custom) {
      if (key.isEmpty || value.isEmpty) continue;
      // TXXX：编码(0x01) + 键（UTF-16 BOM + 终止符）+ 值
      final payload = BytesBuilder(copy: false)
        ..addByte(0x01)
        ..add(_utf16WithBom(key))
        ..add([0x00, 0x00])
        ..add(_utf16WithBom(value));
      frames.add(_frame('TXXX', payload.toBytes()));
    }
    final cover = data.coverBytes;
    if (cover != null && cover.isNotEmpty) {
      final payload = BytesBuilder(copy: false)
        ..addByte(0x00) // 描述文本编码：ISO-8859-1
        ..add(_latin1(data.coverMime))
        ..addByte(0x00)
        ..addByte(0x03) // picture type: front cover
        ..addByte(0x00) // 描述为空，仅终止符
        ..add(cover);
      frames.add(_frame('APIC', payload.toBytes()));
    }

    final body = frames.toBytes();
    final tagSize = body.length + _padding;
    final header = Uint8List(10)
      ..[0] =
          0x49 // I
      ..[1] =
          0x44 // D
      ..[2] =
          0x33 // 3
      ..[3] =
          0x03 // version 2.3
      ..[4] = 0x00
      ..[5] =
          0x00 // flags
      ..[6] = (tagSize >> 21) & 0x7F
      ..[7] = (tagSize >> 14) & 0x7F
      ..[8] = (tagSize >> 7) & 0x7F
      ..[9] = tagSize & 0x7F;
    return (BytesBuilder(copy: false)
          ..add(header)
          ..add(body)
          ..add(Uint8List(_padding)))
        .toBytes();
  }

  /// 把标签写进 [file] 本体：剥离旧 ID3v2 → 拼新标签 + 原音频 →
  /// 临时文件校验通过后替换原文件。失败返回 false 且原文件不动。
  static Future<bool> writeToFile(File file, AudioTagData data) async {
    File? tmp;
    try {
      final bytes = await file.readAsBytes();
      final strip = existingTagLength(bytes);
      if (strip > bytes.length) return false; // 旧标签头损坏，不冒险
      final tag = buildTag(data);
      final out =
          (BytesBuilder(copy: false)
                ..add(tag)
                ..add(Uint8List.sublistView(bytes, strip)))
              .toBytes();

      tmp = File('${file.path}.tagging');
      await tmp.writeAsBytes(out, flush: true);

      // 校验：总长度一致、头是 ID3、标签后紧跟的音频字节与原文一致
      final raf = await tmp.open();
      try {
        final len = await raf.length();
        if (len != out.length) return false;
        final head = await raf.read(3);
        if (head.length < 3 || head[0] != 0x49 || head[1] != 0x44) {
          return false;
        }
        if (bytes.length > strip) {
          await raf.setPosition(tag.length);
          final audioHead = await raf.read(4);
          for (var i = 0; i < audioHead.length; i++) {
            if (audioHead[i] != bytes[strip + i]) return false;
          }
        }
      } finally {
        await raf.close();
      }

      try {
        await tmp.rename(file.path);
      } catch (_) {
        // Windows 等平台 rename 不能覆盖已存在文件：回落到复制覆盖
        await tmp.copy(file.path);
        await tmp.delete();
      }
      tmp = null;
      return true;
    } catch (_) {
      return false;
    } finally {
      if (tmp != null && await tmp.exists()) {
        try {
          await tmp.delete();
        } catch (_) {}
      }
    }
  }

  /// 解析文件开头 ID3v2 标签的帧（供校验与测试用）：
  /// 返回 frameId → payload 列表；没有合法标签时返回空 map。
  static Map<String, List<Uint8List>> parseFrames(Uint8List bytes) {
    final result = <String, List<Uint8List>>{};
    if (existingTagLength(bytes) == 0) return result;
    final version = bytes[3];
    final tagEnd =
        existingTagLength(bytes) -
        ((bytes[5] & 0x10) != 0 ? 10 : 0); // 帧区不含 footer
    var pos = 10;
    while (pos + 10 <= tagEnd && pos + 10 <= bytes.length) {
      final idBytes = bytes.sublist(pos, pos + 4);
      if (idBytes.every((b) => b == 0)) break; // 进入 padding
      final id = String.fromCharCodes(idBytes);
      final int size;
      if (version >= 4) {
        size =
            ((bytes[pos + 4] & 0x7F) << 21) |
            ((bytes[pos + 5] & 0x7F) << 14) |
            ((bytes[pos + 6] & 0x7F) << 7) |
            (bytes[pos + 7] & 0x7F);
      } else {
        size =
            (bytes[pos + 4] << 24) |
            (bytes[pos + 5] << 16) |
            (bytes[pos + 6] << 8) |
            bytes[pos + 7];
      }
      if (size < 0 || pos + 10 + size > bytes.length) break;
      result
          .putIfAbsent(id, () => [])
          .add(Uint8List.sublistView(bytes, pos + 10, pos + 10 + size));
      pos += 10 + size;
    }
    return result;
  }

  // ---------- 内部 ----------

  static Uint8List _frame(String id, Uint8List payload) {
    final out = Uint8List(10 + payload.length);
    out.setRange(0, 4, id.codeUnits);
    out[4] = (payload.length >> 24) & 0xFF;
    out[5] = (payload.length >> 16) & 0xFF;
    out[6] = (payload.length >> 8) & 0xFF;
    out[7] = payload.length & 0xFF;
    // out[8], out[9] flags = 0
    out.setRange(10, out.length, payload);
    return out;
  }

  /// UTF-16LE 带 BOM 的原始字节（不含编码前缀字节）。
  static Uint8List _utf16WithBom(String text) {
    final units = text.codeUnits;
    final out = Uint8List(2 + units.length * 2);
    out[0] = 0xFF; // BOM LE
    out[1] = 0xFE;
    for (var i = 0; i < units.length; i++) {
      out[2 + i * 2] = units[i] & 0xFF;
      out[3 + i * 2] = (units[i] >> 8) & 0xFF;
    }
    return out;
  }

  /// ID3v2.3 文本帧 payload：编码字节 0x01 + BOM + UTF-16LE 码元。
  static Uint8List _encodeText(String text) {
    final body = _utf16WithBom(text);
    final out = Uint8List(1 + body.length);
    out[0] = 0x01;
    out.setRange(1, out.length, body);
    return out;
  }

  static Uint8List _latin1(String s) =>
      Uint8List.fromList(s.codeUnits.map((c) => c & 0xFF).toList());
}
