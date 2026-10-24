import 'dart:async';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart' show Rx, RxInt, IntExtension;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../common/system_ui.dart';
import '../../models/reader_direction.dart';
import 'reader_settings.dart';

class ReaderPlatform {
  ReaderPlatform({required this.settings, required this.prevPage, required this.nextPage, this._readBatteryLevel, this._batteryChanges});

  static const _volumeKeyChannel = MethodChannel('hikari/reader_volume_keys');
  final ReaderSettings Function() settings;
  final VoidCallback prevPage;
  final VoidCallback nextPage;
  final _battery = Battery();
  final Future<int> Function()? _readBatteryLevel;
  final Stream<BatteryState>? _batteryChanges;
  bool _initialized = false;
  int _batteryGeneration = 0;
  StreamSubscription<BatteryState>? _batterySubscription;
  Timer? _clockTimer;
  final RxInt batteryLevel = 0.obs;
  final Rx<DateTime> currentTime = Rx(DateTime.now());
  bool _closed = false;

  void onInit() {
    if (_closed || _initialized) return;
    _initialized = true;
    _volumeKeyChannel.setMethodCallHandler(_handleVolumeKey);
    _setVolumeKeyHandlingEnabled(_volumeKeysEnabled(settings()));
    _refreshBattery();
    _batterySubscription = (_batteryChanges ?? _battery.onBatteryStateChanged).listen((_) => _refreshBattery());
    _scheduleClock();
  }

  Future<void> _refreshBattery() async {
    final generation = ++_batteryGeneration;
    try {
      final level = await (_readBatteryLevel?.call() ?? _battery.batteryLevel);
      if (!_closed && generation == _batteryGeneration) batteryLevel.value = level;
    } catch (_) {
      // Battery support may be unavailable; retain the last observed level.
    }
  }

  void _scheduleClock() {
    if (_closed) return;
    final now = DateTime.now();
    final nextMinute = DateTime(now.year, now.month, now.day, now.hour, now.minute + 1);
    _clockTimer = Timer(nextMinute.difference(now), () {
      if (_closed) return;
      currentTime.value = DateTime.now();
      _scheduleClock();
    });
  }

  void onReady() {
    if (_closed) return;
    if (settings().wakeLock) WakelockPlus.toggle(enable: true);
    _applyReaderSystemUi(settings().immersionMode);
  }

  void settingsChanged(ReaderSettings previous, ReaderSettings next) {
    if (_closed) return;
    if (previous.direction != next.direction || previous.volumeKeyPageTurning != next.volumeKeyPageTurning) {
      _setVolumeKeyHandlingEnabled(_volumeKeysEnabled(next));
    }
    if (previous.wakeLock != next.wakeLock) WakelockPlus.toggle(enable: next.wakeLock);
    if (previous.immersionMode != next.immersionMode) _applyReaderSystemUi(next.immersionMode);
  }

  bool _volumeKeysEnabled(ReaderSettings value) => value.volumeKeyPageTurning && value.direction != ReaderDirection.upToDown;

  Future<void> _handleVolumeKey(MethodCall call) async {
    if (_closed || !_volumeKeysEnabled(settings())) return;
    switch (call.method) {
      case 'volumeUp':
        prevPage();
      case 'volumeDown':
        nextPage();
    }
  }

  Future<void> _setVolumeKeyHandlingEnabled(bool enabled) async {
    if (!Platform.isAndroid) return;
    try {
      await _volumeKeyChannel.invokeMethod('setEnabled', {'enabled': enabled});
    } on MissingPluginException {
      // Optional native implementation.
    } on PlatformException {
      // 非 Android 平台可以不提供原生音量键支持。
    }
  }

  void _applyReaderSystemUi(bool immersive) {
    if (!(Platform.isAndroid || Platform.isIOS)) return;
    if (immersive) {
      SystemUi.immersive();
      return;
    }
    SystemUi.edgeToEdge();
  }

  void onClose() {
    if (_closed) return;
    _closed = true;
    _batteryGeneration++;
    _volumeKeyChannel.setMethodCallHandler(null);
    _setVolumeKeyHandlingEnabled(false);
    _batterySubscription?.cancel();
    _clockTimer?.cancel();
    if (settings().wakeLock) WakelockPlus.toggle(enable: false);
    _applyReaderSystemUi(false);
  }
}
