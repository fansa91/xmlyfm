/// 下载文件名模板渲染与清洗（纯逻辑，无 Flutter 依赖，便于单测）。
///
/// 模板变量：
/// - {album} 专辑名
/// - {title} 声音标题
/// - {index} 集序号（至少两位数补零，如 03）
/// - {trackId} 声音 ID
/// - {author} 主播名
class DownloadFileNameFormatter {
  static const String defaultFormat = '{album} - {index} - {title}';

  /// 变量名 → 中文说明（设置页变量 chips 用）
  static const Map<String, String> variables = {
    '{album}': '专辑名',
    '{title}': '标题',
    '{index}': '集序号',
    '{trackId}': '声音ID',
    '{author}': '主播',
  };

  /// 渲染模板并清洗非法字符；结果为空时依次回落到标题、track_ID 形式。
  static String render(
    String format, {
    required String album,
    required String title,
    required int index,
    required int trackId,
    required String author,
  }) {
    final raw = format
        .replaceAll('{album}', album)
        .replaceAll('{title}', title)
        .replaceAll('{index}', index.toString().padLeft(2, '0'))
        .replaceAll('{trackId}', '$trackId')
        .replaceAll('{author}', author);
    var out = sanitize(raw);
    if (out.isEmpty) out = sanitize(title);
    if (out.isEmpty) out = 'track_$trackId';
    return out;
  }

  /// 清洗文件名非法字符：/ \ : * ? " < > | 与控制字符替换为 _，
  /// 去首尾空白与结尾的点，长度上限 120。
  static String sanitize(String name) {
    var out = name.replaceAll(RegExp('[\\\\/:*?"<>|\u0000-\u001F]'), '_');
    out = out.trim();
    out = out.replaceAll(RegExp(r'[.\s]+$'), '');
    if (out.length > 120) out = out.substring(0, 120).trim();
    return out;
  }

  /// 同名去重：base.ext 已存在时依次尝试 base (1).ext、base (2).ext …
  static String uniqueName(
    String base,
    String ext,
    bool Function(String candidate) exists,
  ) {
    var candidate = '$base$ext';
    var n = 1;
    while (exists(candidate)) {
      candidate = '$base ($n)$ext';
      n++;
    }
    return candidate;
  }

  /// 从音频 URL 推断扩展名（白名单），推断不出时回落 .mp3。
  static String extensionForUrl(String url) {
    final path = Uri.tryParse(url)?.path ?? url;
    final dot = path.lastIndexOf('.');
    if (dot >= 0 && dot > path.lastIndexOf('/')) {
      final ext = path.substring(dot).toLowerCase();
      const known = {'.mp3', '.m4a', '.aac', '.mp4', '.wav', '.flac', '.ogg'};
      if (known.contains(ext)) return ext;
    }
    return '.mp3';
  }
}
