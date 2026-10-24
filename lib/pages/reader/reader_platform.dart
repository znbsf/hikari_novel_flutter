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
  ReaderPlatform({required this.settings, required this.prevPage, required this.nextPage});

  static const _volumeKeyChannel = MethodChannel('hikari/reader_volume_keys');
  final ReaderSettings Function() settings;
  final VoidCallback prevPage;
  final VoidCallback nextPage;
  final _battery = Battery();
  StreamSubscription<BatteryState>? _batterySubscription;
  Timer? _clockTimer;
  final RxInt batteryLevel = 0.obs;
  final Rx<DateTime> currentTime = Rx(DateTime.now());
  bool _closed = false;

  void onInit() {
    _volumeKeyChannel.setMethodCallHandler(_handleVolumeKey);
    _setVolumeKeyHandlingEnabled(_volumeKeysEnabled(settings()));
    _battery.batteryLevel.then((l) => batteryLevel.value = l);
    _batterySubscription = _battery.onBatteryStateChanged.listen((_) async {
      batteryLevel.value = await _battery.batteryLevel;
    });
    _scheduleClock();
  }

  void _scheduleClock() {
    final now = DateTime.now();
    final nextMinute = DateTime(now.year, now.month, now.day, now.hour, now.minute + 1);
    _clockTimer = Timer(nextMinute.difference(now), () {
      currentTime.value = DateTime.now();
      _scheduleClock();
    });
  }

  void onReady() {
    if (settings().wakeLock) WakelockPlus.toggle(enable: true);
    _applyReaderSystemUi(settings().immersionMode);
  }

  void settingsChanged(ReaderSettings previous, ReaderSettings next) {
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
    _closed = true;
    _volumeKeyChannel.setMethodCallHandler(null);
    _setVolumeKeyHandlingEnabled(false);
    _batterySubscription?.cancel();
    _clockTimer?.cancel();
    if (settings().wakeLock) WakelockPlus.toggle(enable: false);
    _applyReaderSystemUi(false);
  }
}
