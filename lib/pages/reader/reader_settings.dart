import 'package:flutter/material.dart';
import 'package:get/get.dart' show Rx, RxBool, BoolExtension, Trans;

import '../../models/dual_page_mode.dart';
import '../../models/reader_direction.dart';
import '../../service/local_storage_service.dart';
import '../../widgets/dialogs.dart';
import 'reader_assets.dart' as assets;

class ReaderField<T> {
  const ReaderField(this.pref);

  final Pref<T> Function(LocalStorageService) pref;

  void setIn(ReaderPreferences preferences, T value) {
    preferences._selectAppearance(this);
    preferences.update((settings) => ReaderSettings._({...settings._values, this: value}));
  }
}

abstract final class ReaderFields {
  static final direction = ReaderField<ReaderDirection>((s) => s.readerDirection);
  static final pageTurningAnimation = ReaderField<bool>((s) => s.readerPageTurningAnimation);
  static final volumeKeyPageTurning = ReaderField<bool>((s) => s.readerVolumeKeyPageTurning);
  static final wakeLock = ReaderField<bool>((s) => s.readerWakeLock);
  static final dualPageMode = ReaderField<DualPageMode>((s) => s.readerDualPageMode);
  static final dualPageSpacing = ReaderField<double>((s) => s.readerDualPageSpacing);
  static final immersionMode = ReaderField<bool>((s) => s.readerImmersionMode);
  static final showStatusBar = ReaderField<bool>((s) => s.readerStatusBar);
  static final fontSize = ReaderField<double>((s) => s.readerFontSize);
  static final lineSpacing = ReaderField<double>((s) => s.readerLineSpacing);
  static final leftMargin = ReaderField<double>((s) => s.readerLeftMargin);
  static final topMargin = ReaderField<double>((s) => s.readerTopMargin);
  static final rightMargin = ReaderField<double>((s) => s.readerRightMargin);
  static final bottomMargin = ReaderField<double>((s) => s.readerBottomMargin);
  static final textStyleFilePath = ReaderField<String?>((s) => s.readerTextStyleFilePath);
  static final textFamily = ReaderField<String?>((s) => s.readerTextFamily);
  static final readerDayBgImage = ReaderField<String?>((s) => s.readerDayBgImage);
  static final readerNightBgImage = ReaderField<String?>((s) => s.readerNightBgImage);
  static final readerDayTextColor = ReaderField<Color?>((s) => s.readerDayTextColor);
  static final readerNightTextColor = ReaderField<Color?>((s) => s.readerNightTextColor);
  static final readerDayBgColor = ReaderField<Color?>((s) => s.readerDayBgColor);
  static final readerNightBgColor = ReaderField<Color?>((s) => s.readerNightBgColor);
  static final readerParaIndent = ReaderField<int>((s) => s.readerParaIndent);
  static final readerParaSpacing = ReaderField<int>((s) => s.readerParaSpacing);
  static final readerBottomStatusBarHorizontalSpacing = ReaderField<int>((s) => s.readerBottomStatusBarHorizontalSpacing);

  static final all = <ReaderField<dynamic>>[
    direction,
    pageTurningAnimation,
    volumeKeyPageTurning,
    wakeLock,
    dualPageMode,
    dualPageSpacing,
    immersionMode,
    showStatusBar,
    fontSize,
    lineSpacing,
    leftMargin,
    topMargin,
    rightMargin,
    bottomMargin,
    textStyleFilePath,
    textFamily,
    readerDayBgImage,
    readerNightBgImage,
    readerDayTextColor,
    readerNightTextColor,
    readerDayBgColor,
    readerNightBgColor,
    readerParaIndent,
    readerParaSpacing,
    readerBottomStatusBarHorizontalSpacing,
  ];
}

class ReaderSettings {
  ReaderSettings._(Map<ReaderField<dynamic>, dynamic> values) : _values = Map.unmodifiable(values);

  final Map<ReaderField<dynamic>, dynamic> _values;

  factory ReaderSettings.load(LocalStorageService storage) => ReaderSettings._({for (final field in ReaderFields.all) field: field.pref(storage).value});

  T get<T>(ReaderField<T> field) => _values[field] as T;

  void saveChanges(ReaderSettings previous, LocalStorageService storage) {
    for (final field in ReaderFields.all) {
      if (_values[field] != previous._values[field]) field.pref(storage).value = _values[field];
    }
  }

  ReaderDirection get direction => get(ReaderFields.direction);
  bool get pageTurningAnimation => get(ReaderFields.pageTurningAnimation);
  bool get volumeKeyPageTurning => get(ReaderFields.volumeKeyPageTurning);
  bool get wakeLock => get(ReaderFields.wakeLock);
  DualPageMode get dualPageMode => get(ReaderFields.dualPageMode);
  double get dualPageSpacing => get(ReaderFields.dualPageSpacing);
  bool get immersionMode => get(ReaderFields.immersionMode);
  bool get showStatusBar => get(ReaderFields.showStatusBar);
  double get fontSize => get(ReaderFields.fontSize);
  double get lineSpacing => get(ReaderFields.lineSpacing);
  double get leftMargin => get(ReaderFields.leftMargin);
  double get topMargin => get(ReaderFields.topMargin);
  double get rightMargin => get(ReaderFields.rightMargin);
  double get bottomMargin => get(ReaderFields.bottomMargin);
  String? get textStyleFilePath => get(ReaderFields.textStyleFilePath);
  String? get textFamily => get(ReaderFields.textFamily);
  String? get readerDayBgImage => get(ReaderFields.readerDayBgImage);
  String? get readerNightBgImage => get(ReaderFields.readerNightBgImage);
  Color? get readerDayTextColor => get(ReaderFields.readerDayTextColor);
  Color? get readerNightTextColor => get(ReaderFields.readerNightTextColor);
  Color? get readerDayBgColor => get(ReaderFields.readerDayBgColor);
  Color? get readerNightBgColor => get(ReaderFields.readerNightBgColor);
  int get readerParaIndent => get(ReaderFields.readerParaIndent);
  int get readerParaSpacing => get(ReaderFields.readerParaSpacing);
  int get readerBottomStatusBarHorizontalSpacing => get(ReaderFields.readerBottomStatusBarHorizontalSpacing);

  Color? textColorFor(Brightness brightness) => brightness == Brightness.dark ? readerNightTextColor : readerDayTextColor;
  Color? bgColorFor(Brightness brightness) => brightness == Brightness.dark ? readerNightBgColor : readerDayBgColor;
  String? bgImageFor(Brightness brightness) => brightness == Brightness.dark ? readerNightBgImage : readerDayBgImage;
}

class ReaderPreferences {
  ReaderPreferences(this.storage, {assets.ReaderAssets? assetStore, Future<void> Function(Map<Pref<dynamic>, dynamic>)? writePreferences})
    : assetStore = assetStore ?? assets.defaultReaderAssets,
      _writePreferences = writePreferences ?? Pref.writeAll,
      state = Rx(ReaderSettings.load(storage));

  final LocalStorageService storage;
  final assets.ReaderAssets assetStore;
  final Future<void> Function(Map<Pref<dynamic>, dynamic>) _writePreferences;
  Future<void> _resourceTail = Future.value();
  int _fontRevision = 0;
  bool _closed = false;
  final Rx<ReaderSettings> state;
  final RxBool isFontFileAvailable = false.obs;
  void Function(ReaderSettings previous, ReaderSettings next)? onChanged;
  Brightness _textBrightness = Brightness.light;
  Brightness _bgBrightness = Brightness.light;
  Brightness _imageBrightness = Brightness.light;

  Color? get textColor => state.value.textColorFor(_textBrightness);
  Color? get bgColor => state.value.bgColorFor(_bgBrightness);
  String? get bgImagePath => state.value.bgImageFor(_imageBrightness);

  void initialize(Brightness brightness) {
    _textBrightness = _bgBrightness = _imageBrightness = brightness;
    checkFontFile(true);
  }

  void update(ReaderSettings Function(ReaderSettings) transform) {
    final previous = state.value;
    final next = transform(previous);
    state.value = next;
    onChanged?.call(previous, next);
    next.saveChanges(previous, storage);
  }

  void _selectAppearance(ReaderField<dynamic> field) {
    if (field == ReaderFields.readerDayTextColor || field == ReaderFields.readerNightTextColor) {
      _textBrightness = field == ReaderFields.readerNightTextColor ? Brightness.dark : Brightness.light;
    } else if (field == ReaderFields.readerDayBgColor || field == ReaderFields.readerNightBgColor) {
      _bgBrightness = field == ReaderFields.readerNightBgColor ? Brightness.dark : Brightness.light;
    } else if (field == ReaderFields.readerDayBgImage || field == ReaderFields.readerNightBgImage) {
      _imageBrightness = field == ReaderFields.readerNightBgImage ? Brightness.dark : Brightness.light;
    }
  }

  // Serialize resource edits so each operation owns the reference it replaces.
  Future<T> _resourceOperation<T>(Future<T> Function() operation) {
    final result = _resourceTail.then((_) {
      if (_closed) throw StateError('Reader preferences are closed');
      return operation();
    });
    _resourceTail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void close() {
    _closed = true;
    ++_fontRevision;
    onChanged = null;
  }

  Future<void> _commitResources(Map<ReaderField<dynamic>, dynamic> values) async {
    if (_closed) throw StateError('Reader preferences are closed');
    await _writePreferences({for (final entry in values.entries) entry.key.pref(storage): entry.value});
    if (_closed) return;
    // Publish only after persistence succeeds, merging with any ordinary edits
    // made while the disk write was pending.
    final previous = state.value;
    final next = ReaderSettings._({...previous._values, ...values});
    state.value = next;
    for (final field in values.keys) {
      _selectAppearance(field);
    }
    if (!_closed) onChanged?.call(previous, next);
  }

  Future<bool?> pickTextStyleFile() => _resourceOperation(() async {
    ({String path, String family})? font;
    try {
      font = await assetStore.pickTextStyleFile();
      if (font == null) return null;
      final oldPath = state.value.textStyleFilePath;
      await _commitResources({ReaderFields.textStyleFilePath: font.path, ReaderFields.textFamily: font.family});
      ++_fontRevision;
      if (!_closed) isFontFileAvailable.value = true;
      await assetStore.deleteStoredFont(oldPath);
      return true;
    } catch (_) {
      if (font != null && storage.readerTextStyleFilePath.value != font.path) {
        await assetStore.deleteStoredFont(font.path);
      }
      return false;
    }
  }).catchError((Object _) => false);

  Future<void> clearTextStyleFile() => _resourceOperation(() async {
    final oldPath = state.value.textStyleFilePath;
    await _commitResources({ReaderFields.textStyleFilePath: null, ReaderFields.textFamily: null});
    ++_fontRevision;
    if (!_closed) isFontFileAvailable.value = false;
    await assetStore.deleteStoredFont(oldPath);
  });

  // Checking an old snapshot never clears settings. A missing/unloadable file
  // remains recoverable and a late check cannot overwrite a newer import.
  void checkFontFile(bool showDialog) async {
    final revision = ++_fontRevision;
    final snapshot = state.value;
    final filePath = snapshot.textStyleFilePath;
    var available = false;
    try {
      if (filePath != null && snapshot.textFamily != null && await assetStore.fontFileExists(filePath)) {
        available = await assetStore.loadStoredFont(filePath) != null;
      }
    } catch (_) {
      available = false;
    }
    if (_closed || revision != _fontRevision || state.value.textStyleFilePath != filePath || state.value.textFamily != snapshot.textFamily) return;
    isFontFileAvailable.value = available;
    if (!available && filePath != null && showDialog) {
      showMessageDialog(title: "warning".tr, content: "no_font_file_tip".tr, icon: const Icon(Icons.warning_amber_outlined));
    }
  }

  Future<bool?> pickBgImageFile(bool isDark) => _resourceOperation(() async {
    final field = isDark ? ReaderFields.readerNightBgImage : ReaderFields.readerDayBgImage;
    String? newPath;
    try {
      newPath = await assetStore.pickBgImageFile(isDark);
      if (newPath == null) return null;
      final oldPath = state.value.get(field);
      await _commitResources({field: newPath});
      await _deleteSupersededBackground(oldPath);
      return true;
    } catch (_) {
      if (newPath != null && field.pref(storage).value != newPath) {
        await assetStore.deleteStoredBackground(newPath);
      }
      return false;
    }
  }).catchError((Object _) => false);

  Future<void> _deleteSupersededBackground(String? filePath) async {
    if (filePath == storage.readerDayBgImage.value || filePath == storage.readerNightBgImage.value) return;
    await assetStore.deleteStoredBackground(filePath);
  }

  Future<void> clearReaderBgImage(bool isDark) => _resourceOperation(() async {
    final field = isDark ? ReaderFields.readerNightBgImage : ReaderFields.readerDayBgImage;
    final oldPath = state.value.get(field);
    await _commitResources({field: null});
    await _deleteSupersededBackground(oldPath);
  });
}
