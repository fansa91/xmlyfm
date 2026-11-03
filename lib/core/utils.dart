// 通用小工具：JSON 字段容错读取、数字/时长格式化。

int intOf(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  if (v is bool) return v ? 1 : 0;
  return 0;
}

double doubleOf(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

bool boolOf(dynamic v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v == 'true' || v == '1';
  return false;
}

String strOf(dynamic v) {
  if (v == null) return '';
  return '$v';
}

/// 播放量格式化：12345 -> 1.2万
String formatPlayCount(int count) {
  if (count >= 100000000) {
    return '${(count / 100000000).toStringAsFixed(1)}亿';
  }
  if (count >= 10000) {
    return '${(count / 10000).toStringAsFixed(1)}万';
  }
  return '$count';
}

/// 秒 -> m:ss / h:mm:ss
String formatSeconds(int seconds) {
  if (seconds <= 0) return '--:--';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  final ss = s.toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
  return '$m:$ss';
}

/// Duration -> m:ss / h:mm:ss
String formatDuration(Duration d) => formatSeconds(d.inSeconds);

/// 字节数格式化：1024 -> 1.0 KB
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(1)} ${units[unit]}';
}

String formatDate(int msEpoch) {
  if (msEpoch <= 0) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch(msEpoch);
  return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
      '${dt.day.toString().padLeft(2, '0')}';
}
