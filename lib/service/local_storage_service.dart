import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hikari_novel_flutter/common/app_paths.dart';
import 'package:hikari_novel_flutter/hive_registrar.g.dart';
import 'package:hive_ce/hive.dart';

import '../models/common/language.dart';
import '../models/common/wenku8_node.dart';
import '../models/dual_page_mode.dart';
import '../models/reader_direction.dart';
import '../models/user_info.dart';

class Pref<T> {
  Pref(this._box, this.key, this.defaultValue, {this.decode, this.encode});

  final Box<dynamic> _box;
  final String key;
  final T defaultValue;
  final T Function(dynamic)? decode;
  final dynamic Function(T)? encode;

  T get value {
    final raw = _box.get(key, defaultValue: encode == null ? defaultValue : encode!(defaultValue));
    return decode == null ? raw as T : decode!(raw);
  }

  set value(T v) => _box.put(key, encode == null ? v : encode!(v));

  static Pref<E> enumOf<E extends Enum>(List<E> values, Box<dynamic> box, String key, E defaultValue) =>
      Pref<E>(box, key, defaultValue, decode: (v) => values[v as int], encode: (v) => v.index);

  static Pref<T> color<T extends Color?>(Box<dynamic> box, String key, T defaultValue) =>
      Pref<T>(box, key, defaultValue, decode: (v) => (v == null ? null : Color(v as int)) as T, encode: (v) => v?.toARGB32());
}

class LocalStorageService extends GetxService {
  static LocalStorageService get instance => Get.find<LocalStorageService>();

  late final Box<dynamic> _setting;
  late final Box<dynamic> _loginInfo;
  late final Box<dynamic> _reader;

  late final cookie = Pref<String?>(_loginInfo, "cookie", null);

  late final userInfo = Pref<UserInfo?>(_setting, "user_info", null);

  late final isAutoCheckUpdate = Pref<bool>(_setting, "isAutoCheckUpdate", true);

  late final themeMode = Pref.enumOf(ThemeMode.values, _setting, "themeMode", ThemeMode.system);

  late final customColor = Pref.color<Color>(_setting, "customColor", Colors.blue);

  late final isDynamicColor = Pref<bool>(_setting, "isDynamicColor", true);

  late final isRelativeTime = Pref<bool>(_setting, "isRelativeTime", false);

  late final language = Pref.enumOf(Language.values, _setting, "language", Language.followSystem);

  late final wenku8Node = Pref.enumOf(Wenku8Node.values, _setting, "wenku8Node", Wenku8Node.wwwWenku8Cc);

  late final readerDirection = Pref.enumOf(ReaderDirection.values, _reader, "readerDirection", ReaderDirection.upToDown);

  late final readerFontSize = Pref<double>(_reader, "readerFontSize", 16.0);

  late final readerLineSpacing = Pref<double>(_reader, "readerLineSpacing", 1.5);

  late final readerWakeLock = Pref<bool>(_reader, "readerWakeLock", false);

  late final readerLeftMargin = Pref<double>(_reader, "readerLeftMargin", 20.0);

  late final readerTopMargin = Pref<double>(_reader, "readerTopMargin", 20.0);

  late final readerRightMargin = Pref<double>(_reader, "readerRightMargin", 20.0);

  late final readerBottomMargin = Pref<double>(_reader, "readerBottomMargin", 20.0);

  late final readerDualPageMode = Pref.enumOf(DualPageMode.values, _reader, "readerDualPageMode", DualPageMode.auto);

  late final readerDualPageSpacing = Pref<double>(_reader, "readerDualPageSpacing", 20.0);

  late final readerImmersionMode = Pref<bool>(_reader, "readerImmersionMode", false);

  late final readerStatusBar = Pref<bool>(_reader, "readerStatusBar", true);

  late final readerTextFamily = Pref<String?>(_reader, "readerTextFamily", null);

  late final readerTextStyleFilePath = Pref<String?>(_reader, "readerTextStyleFilePath", null);

  late final readerPageTurningAnimation = Pref<bool>(_reader, "readerPageTurningAnimation", true);

  late final readerVolumeKeyPageTurning = Pref<bool>(_reader, "readerVolumeKeyPageTurning", false);

  late final readerDayBgColor = Pref.color<Color?>(_reader, "readerDayBgColor", null);

  late final readerDayTextColor = Pref.color<Color?>(_reader, "readerDayTextColor", null);

  late final readerNightBgColor = Pref.color<Color?>(_reader, "readerNightBgColor", null);

  late final readerNightTextColor = Pref.color<Color?>(_reader, "readerNightTextColor", null);

  late final readerDayBgImage = Pref<String?>(_reader, "readerDayBgImage", null);

  late final readerNightBgImage = Pref<String?>(_reader, "readerNightBgImage", null);

  late final readerTtsEnabled = Pref<bool>(_reader, "readerTtsEnabled", false);

  late final readerTtsEngine = Pref<String?>(_reader, "readerTtsEngine", null);

  late final readerTtsVoice = Pref<Map<String, String>?>(
    _reader,
    "readerTtsVoice",
    null,
    decode: (v) => v is Map ? v.map((k, val) => MapEntry(k.toString(), val.toString())) : null,
  );

  late final readerTtsRate = Pref<double>(_reader, "readerTtsRate", 0.5);

  late final readerTtsPitch = Pref<double>(_reader, "readerTtsPitch", 1.0);

  late final readerTtsVolume = Pref<double>(_reader, "readerTtsVolume", 1.0);

  late final devModeEnabled = Pref<bool>(_setting, "devModeEnabled", false);

  late final readerParaIndent = Pref<int>(_reader, "readerParaIndent", 1);

  late final readerParaSpacing = Pref<int>(_reader, "readerParaSpacing", 25);

  late final readerBottomStatusBarHorizontalSpacing = Pref<int>(_reader, "readerBottomStatusBarHorizontalSpacing", 25);

  Future<void> init({String? hivePath}) async {
    final String path = hivePath ?? "${AppPaths.supportDir.path}/hive";
    Hive.init(path);
    Hive.registerAdapters();
    _setting = await Hive.openBox("setting");
    _loginInfo = await Hive.openBox("loginInfo");
    _reader = await Hive.openBox("reader");
  }
}
