import 'dart:io' show Platform;
import 'dart:math' show Random;

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'download_filename.dart';

/// 应用设置：主题模式 / 主题色 / 默认音质 / baseInfo 版本，
/// 持久化到 SharedPreferences。访客态应用，无账号相关设置。
class SettingsService extends ChangeNotifier {
  static const _keyDynamicColor = 'dynamic_color';
  static const _keyThemeSeed = 'theme_seed';
  static const _keyThemeMode = 'theme_mode';
  static const _keyPureBlack = 'pure_black';
  static const _keyCustomColors = 'custom_colors';
  static const _keyDefaultQuality = 'default_quality';
  static const _keyBaseInfoV4 = 'baseinfo_v4';
  static const _keyDownloadFileNameFormat = 'download_filename_format';
  static const _keyDownloadFormat = 'download_format';
  static const _keyDownloadDirectory = 'download_directory';
  static const _keyDeviceId = 'device_id';

  /// 预设主题色
  static const List<ThemePreset> themePresets = [
    ThemePreset('喜马拉雅橙', 0xFFF94D1C),
    ThemePreset('网易云红', 0xFFD33A31),
    ThemePreset('琥珀黄', 0xFFFFB300),
    ThemePreset('草原绿', 0xFF4CAF50),
    ThemePreset('湖水青', 0xFF00BCD4),
    ThemePreset('天空蓝', 0xFF2196F3),
    ThemePreset('靛蓝', 0xFF3F51B5),
    ThemePreset('葡萄紫', 0xFF9C27B0),
    ThemePreset('樱花粉', 0xFFE91E63),
  ];
  static const int defaultThemeSeed = 0xFFF94D1C;

  late SharedPreferences _prefs;

  /// 主题模式：跟随系统 / 浅色 / 深色
  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  /// 纯黑模式（深色下背景全黑，AMOLED 省电）
  bool _pureBlack = false;
  bool get pureBlack => _pureBlack;

  /// 用户自定义主题色（ARGB int 列表）
  List<int> _customColors = [];
  List<int> get customColors => List.unmodifiable(_customColors);

  /// M3 动态取色（跟随系统壁纸，Android 12+ 有效），默认开启
  bool _dynamicColor = true;
  bool get dynamicColor => _dynamicColor;

  /// 从系统取到的动态种子色；不支持或未取到时为 null
  Color? _systemSeedColor;
  Color? get systemSeedColor => _systemSeedColor;

  /// 当前生效的种子色：动态取色开且系统支持时用系统色，否则用用户选的主题色
  Color get effectiveSeedColor {
    if (_dynamicColor && _systemSeedColor != null) return _systemSeedColor!;
    return Color(_themeSeed);
  }

  /// 主题色（ARGB int），默认喜马拉雅橙
  int _themeSeed = defaultThemeSeed;
  int get themeSeed => _themeSeed;
  String get themeName {
    for (final p in themePresets) {
      if (p.value == _themeSeed) return p.name;
    }
    if (_customColors.contains(_themeSeed)) return '自定义';
    return '喜马拉雅橙';
  }

  /// 默认音质档位（trackQualityLevel：0 标准 / 1 高清 / 2 臻品 / 3 无损）
  int _defaultQuality = 1;
  int get defaultQuality => _defaultQuality;

  /// baseInfo 走 v4（带 sign）；默认 v3
  bool _baseInfoV4 = false;
  bool get baseInfoV4 => _baseInfoV4;

  /// 下载文件名模板（变量见 DownloadFileNameFormatter），只影响新下载
  String _downloadFileNameFormat = DownloadFileNameFormatter.defaultFormat;
  String get downloadFileNameFormat => _downloadFileNameFormat;

  /// 下载格式取值：MP3 优先（可写入文件标签）
  static const String downloadFormatMp3 = 'mp3';

  /// 下载格式取值：音质优先（按默认音质取链，多为 M4A，无法写入标签）
  static const String downloadFormatQuality = 'quality';

  /// 下载格式（见 [downloadFormatMp3] / [downloadFormatQuality]），
  /// 默认 MP3 优先；只影响之后新入队与重跑的解析，已入队/已完成任务不变。
  String _downloadFormat = downloadFormatMp3;
  String get downloadFormat => _downloadFormat;

  /// 存量/外部写入的非法格式值一律回落到默认（MP3 优先）
  static String sanitizeDownloadFormat(String? value) =>
      value == downloadFormatQuality ? downloadFormatQuality : downloadFormatMp3;

  /// 自定义下载目录（空 = 用默认的应用文档目录 downloads/）。
  /// 只影响之后的新下载，不搬移已下载文件；iOS 不开放此设置（见下）。
  String _downloadDirectory = '';
  String get downloadDirectory => _downloadDirectory;

  /// 是否 iOS 平台（默认取 dart:io 的 Platform.isIOS，Web 等取不到
  /// 平台信息时按非 iOS 处理；测试可覆盖）。
  @visibleForTesting
  bool Function() isIOS = () {
    try {
      return Platform.isIOS;
    } catch (_) {
      return false;
    }
  };

  /// 「默认下载路径」设置项是否显示：iOS 固定使用应用沙盒目录，
  /// 不提供自定义下载路径，故隐藏。
  bool get showDownloadDirectorySetting => !isIOS();

  SettingsService();

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _themeSeed = _prefs.getInt(_keyThemeSeed) ?? defaultThemeSeed;
    _dynamicColor = _prefs.getBool(_keyDynamicColor) ?? true;
    if (_dynamicColor) await _loadSystemScheme();
    final modeIndex = _prefs.getInt(_keyThemeMode) ?? ThemeMode.system.index;
    _themeMode = ThemeMode.values[modeIndex.clamp(0, 2)];
    _pureBlack = _prefs.getBool(_keyPureBlack) ?? false;
    _customColors =
        _prefs.getStringList(_keyCustomColors)?.map(int.parse).toList() ?? [];
    _defaultQuality = (_prefs.getInt(_keyDefaultQuality) ?? 1).clamp(0, 3);
    _baseInfoV4 = _prefs.getBool(_keyBaseInfoV4) ?? false;
    _downloadFileNameFormat =
        _prefs.getString(_keyDownloadFileNameFormat) ??
        DownloadFileNameFormatter.defaultFormat;
    _downloadFormat = sanitizeDownloadFormat(
      _prefs.getString(_keyDownloadFormat),
    );
    _downloadDirectory = _prefs.getString(_keyDownloadDirectory) ?? '';
    _deviceId = _prefs.getString(_keyDeviceId) ?? '';
    if (_deviceId.isEmpty) {
      _deviceId = generateDeviceId();
      await _prefs.setString(_keyDeviceId, _deviceId);
    }
  }

  /// 本机设备标识：首启随机生成一次并持久化，之后保持稳定
  /// （接口公共参数 deviceId 用；全员共用同一个写死值会让所有安装
  /// 在服务端看来是同一台设备）。
  String _deviceId = '';
  String get deviceId => _deviceId;

  /// 生成 32 位十六进制设备标识（形态对齐官方 deviceId 的十六进制串）
  static String generateDeviceId() {
    final rnd = Random.secure();
    return List.generate(
      32,
      (_) => rnd.nextInt(16).toRadixString(16),
    ).join();
  }

  /// 通过系统 CorePalette 取种子色，M3 明暗主题分别用 fromSeed 生成
  Future<void> _loadSystemScheme() async {
    try {
      final palette = await DynamicColorPlugin.getCorePalette();
      if (palette != null) {
        _systemSeedColor = Color(palette.primary.get(40));
      }
    } catch (_) {
      _systemSeedColor = null;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == _themeMode) return;
    _themeMode = mode;
    await _prefs.setInt(_keyThemeMode, mode.index);
    notifyListeners();
  }

  Future<void> setPureBlack(bool value) async {
    if (value == _pureBlack) return;
    _pureBlack = value;
    await _prefs.setBool(_keyPureBlack, value);
    notifyListeners();
  }

  Future<void> addCustomColor(int value) async {
    if (_customColors.contains(value)) return;
    _customColors = [..._customColors, value];
    await _prefs.setStringList(
      _keyCustomColors,
      _customColors.map((e) => e.toString()).toList(),
    );
    notifyListeners();
  }

  Future<void> removeCustomColor(int value) async {
    if (!_customColors.contains(value)) return;
    _customColors = _customColors.where((e) => e != value).toList();
    await _prefs.setStringList(
      _keyCustomColors,
      _customColors.map((e) => e.toString()).toList(),
    );
    if (_themeSeed == value) {
      await setThemeSeed(defaultThemeSeed);
      return;
    }
    notifyListeners();
  }

  Future<void> setDefaultQuality(int value) async {
    value = value.clamp(0, 3);
    if (value == _defaultQuality) return;
    _defaultQuality = value;
    await _prefs.setInt(_keyDefaultQuality, value);
    notifyListeners();
  }

  /// 设置自定义下载目录（空字符串 = 恢复默认）。
  Future<void> setDownloadDirectory(String value) async {
    value = value.trim();
    if (value == _downloadDirectory) return;
    _downloadDirectory = value;
    await _prefs.setString(_keyDownloadDirectory, value);
    notifyListeners();
  }

  Future<void> setDownloadFileNameFormat(String value) async {
    value = value.trim();
    if (value.isEmpty || value == _downloadFileNameFormat) return;
    _downloadFileNameFormat = value;
    await _prefs.setString(_keyDownloadFileNameFormat, value);
    notifyListeners();
  }

  /// 设置下载格式（[downloadFormatMp3] / [downloadFormatQuality]，
  /// 非法值回落默认 MP3 优先）。
  Future<void> setDownloadFormat(String value) async {
    value = sanitizeDownloadFormat(value);
    if (value == _downloadFormat) return;
    _downloadFormat = value;
    await _prefs.setString(_keyDownloadFormat, value);
    notifyListeners();
  }

  Future<void> setBaseInfoV4(bool value) async {
    if (value == _baseInfoV4) return;
    _baseInfoV4 = value;
    await _prefs.setBool(_keyBaseInfoV4, value);
    notifyListeners();
  }

  Future<void> resetTheme() async {
    _themeSeed = defaultThemeSeed;
    _dynamicColor = true;
    _themeMode = ThemeMode.system;
    _pureBlack = false;
    _customColors = [];
    await _prefs.setInt(_keyThemeSeed, _themeSeed);
    await _prefs.setBool(_keyDynamicColor, true);
    await _prefs.setInt(_keyThemeMode, _themeMode.index);
    await _prefs.setBool(_keyPureBlack, false);
    await _prefs.setStringList(_keyCustomColors, []);
    await _loadSystemScheme();
    notifyListeners();
  }

  Future<void> setDynamicColor(bool value) async {
    if (value == _dynamicColor) return;
    _dynamicColor = value;
    await _prefs.setBool(_keyDynamicColor, value);
    if (value && _systemSeedColor == null) await _loadSystemScheme();
    notifyListeners();
  }

  /// 选择预设主题色：同时关闭动态取色（手动选色优先）
  Future<void> setThemeSeed(int value) async {
    if (value == _themeSeed) return;
    _themeSeed = value;
    await _prefs.setInt(_keyThemeSeed, value);
    if (_dynamicColor) {
      _dynamicColor = false;
      await _prefs.setBool(_keyDynamicColor, false);
    }
    notifyListeners();
  }
}

/// 主题预设
class ThemePreset {
  final String name;
  final int value;
  const ThemePreset(this.name, this.value);
}
