import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hikari_novel_flutter/service/local_storage_service.dart';
import 'package:hikari_novel_flutter/service/tts_service.dart';
import 'package:hive_ce/hive.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_tts');
  const savedVoice = {'name': '测试语音', 'locale': 'zh-CN'};

  late Directory directory;
  late LocalStorageService storage;
  late TtsService tts;
  late List<MethodCall> calls;
  late Completer<void> warmUpStarted;
  late Completer<void> warmUpGate;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('hikari-tts-test-');
    storage = Get.put(LocalStorageService());
    await storage.init(hivePath: directory.path);
    storage.readerTtsEnabled.value = true;
    storage.readerTtsEngine.value = TtsService.multiTtsEnginePackage;
    storage.readerTtsVoice.value = savedVoice;
    storage.readerTtsRate.value = 0.7;
    storage.readerTtsPitch.value = 1.2;
    storage.readerTtsVolume.value = 0.8;

    calls = [];
    warmUpStarted = Completer<void>();
    warmUpGate = Completer<void>();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'awaitSpeakCompletion':
          warmUpStarted.complete();
          await warmUpGate.future;
          return 1;
        case 'getEngines':
          return [TtsService.multiTtsEnginePackage];
        case 'getVoices':
          return [savedVoice];
        case 'isLanguageAvailable':
          return true;
        default:
          return 1;
      }
    });
    tts = TtsService();
    tts.init();
  });

  tearDown(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    channel.setMethodCallHandler(null);
    Get.reset();
    await Hive.close();
    Hive.resetAdapters();
    await directory.delete(recursive: true);
  });

  test('同步初始化立即恢复设置，不等待平台调用', () {
    expect(tts.enabled.value, true);
    expect(tts.engine.value, TtsService.multiTtsEnginePackage);
    expect(tts.voice.value, savedVoice);
    expect(tts.rate.value, 0.7);
    expect(tts.pitch.value, 1.2);
    expect(tts.volume.value, 0.8);
    expect(calls, isEmpty);
  });

  test('并发就绪请求共用一次预热并恢复已保存的语音', () async {
    final first = tts.ensureReady();
    final second = tts.ensureReady();
    expect(identical(first, second), true);
    await warmUpStarted.future;
    expect(calls.map((call) => call.method), ['awaitSpeakCompletion']);

    warmUpGate.complete();
    await Future.wait([first, second]);

    expect(identical(first, tts.ensureReady()), true);
    expect(calls.where((call) => call.method == 'awaitSpeakCompletion'), hasLength(1));
    expect(calls.where((call) => call.method == 'getVoices'), hasLength(1));
    expect(calls.singleWhere((call) => call.method == 'setSpeechRate').arguments, 0.7);
    expect(calls.singleWhere((call) => call.method == 'setPitch').arguments, 1.2);
    expect(calls.singleWhere((call) => call.method == 'setVolume').arguments, 0.8);
    expect(calls.singleWhere((call) => call.method == 'setVoice').arguments, savedVoice);
    expect(tts.voices, [savedVoice]);
    expect(tts.voice.value, savedVoice);
    expect(storage.readerTtsVoice.value, savedVoice);
  });

  for (final entry in ['speak', 'startChapter', 'resumeSession']) {
    test('$entry 等待预热完成后才播放', () async {
      tts.lastSpokenText.value = '继续阅读';
      final playback = switch (entry) {
        'speak' => tts.speak('测试朗读'),
        'startChapter' => tts.startChapter('测试章节'),
        _ => tts.resumeSession(),
      };
      await warmUpStarted.future;
      expect(calls.map((call) => call.method), ['awaitSpeakCompletion']);

      warmUpGate.complete();
      await playback;

      final methods = calls.map((call) => call.method).toList();
      expect(methods.where((method) => method == 'awaitSpeakCompletion'), hasLength(1));
      expect(methods.where((method) => method == 'speak'), hasLength(1));
      expect(methods.indexOf('getVoices'), lessThan(methods.indexOf('speak')));
      expect(methods.indexOf('setVoice'), lessThan(methods.indexOf('speak')));
    });
  }
}
