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
  late List<Completer<int>> utterances;
  late bool holdSpeech;
  late bool failRate;
  late Completer<void>? stopGate;

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  Future<void> waitForUtterances(int count) async {
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (utterances.length < count && DateTime.now().isBefore(deadline)) {
      await flush();
    }
    expect(utterances.length, greaterThanOrEqualTo(count));
  }

  Future<void> emit(String event) async {
    final done = Completer<void>();
    binding.channelBuffers.push(channel.name, const StandardMethodCodec().encodeMethodCall(MethodCall(event)), (_) => done.complete());
    await done.future;
  }

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
    utterances = [];
    holdSpeech = false;
    failRate = false;
    stopGate = null;
    warmUpStarted = Completer<void>();
    warmUpGate = Completer<void>();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'awaitSpeakCompletion':
          if (!warmUpStarted.isCompleted) warmUpStarted.complete();
          await warmUpGate.future;
          return 1;
        case 'stop':
          await stopGate?.future;
          return 1;
        case 'speak':
          if (!holdSpeech) return 1;
          final result = Completer<int>();
          utterances.add(result);
          return result.future;
        case 'setSpeechRate':
          if (failRate) throw PlatformException(code: 'initialization_failed');
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
      expect(calls.map((call) => call.method), [if (entry != 'resumeSession') 'stop', 'awaitSpeakCompletion']);

      warmUpGate.complete();
      await playback;

      final methods = calls.map((call) => call.method).toList();
      expect(methods.where((method) => method == 'awaitSpeakCompletion'), hasLength(1));
      expect(methods.where((method) => method == 'speak'), hasLength(1));
      expect(methods.indexOf('getVoices'), lessThan(methods.indexOf('speak')));
      expect(methods.indexOf('setVoice'), lessThan(methods.indexOf('speak')));
    });
  }

  for (final entry in ['speak', 'startChapter', 'resumeSession']) {
    for (final cancel in ['stop', 'disable']) {
      test('$entry 初始化等待期间 $cancel 后不再播放', () async {
        tts.lastSpokenText.value = '继续阅读';
        final playback = switch (entry) {
          'speak' => tts.speak('旧播放'),
          'startChapter' => tts.startChapter('旧章节'),
          _ => tts.resumeSession(),
        };
        await warmUpStarted.future;
        if (cancel == 'stop') {
          await tts.stop();
        } else {
          await tts.setEnabled(false);
        }
        warmUpGate.complete();
        await playback;
        expect(calls.where((call) => call.method == 'speak'), isEmpty);
        expect(tts.isPlaying.value, false);
        expect(tts.isSessionActive.value, false);
      });
    }
  }

  test('初始化失败可观察且下次重试成功，后台预热自行处理错误', () async {
    failRate = true;
    final failed = tts.ensureReady();
    final assertion = expectLater(failed, throwsA(isA<PlatformException>()));
    warmUpGate.complete();
    await assertion;
    await tts.warmUpInBackground();
    expect(calls.where((call) => call.method == 'awaitSpeakCompletion'), hasLength(2));
    failRate = false;
    await tts.ensureReady();
    expect(calls.where((call) => call.method == 'awaitSpeakCompletion'), hasLength(3));
    expect(tts.voices, [savedVoice]);
  });

  test('用户播放初始化失败不发声且允许随后重试', () async {
    failRate = true;
    warmUpGate.complete();
    await tts.startChapter('失败章节');
    expect(calls.where((call) => call.method == 'speak'), isEmpty);
    expect(tts.isSessionActive.value, false);
    failRate = false;
    await tts.startChapter('成功章节');
    expect(calls.where((call) => call.method == 'speak'), hasLength(1));
  });

  test('快速连续播放只启动最后一个等待初始化的意图', () async {
    final first = tts.startChapter('旧章节');
    await warmUpStarted.future;
    final second = tts.startChapter('新章节', title: '新标题');
    warmUpGate.complete();
    await Future.wait([first, second]);
    final spoken = calls.where((call) => call.method == 'speak').toList();
    expect(spoken, hasLength(1));
    expect(tts.lastSpokenText.value, '新章节');
    expect(tts.sessionTitle.value, '新标题');
  });

  test('stop 不等待在途 speak，旧 Future 和全局回调不推进新会话', () async {
    holdSpeech = true;
    warmUpGate.complete();
    final old = tts.startChapter('旧章节');
    await waitForUtterances(1);
    await tts.stop();
    expect(tts.isSessionActive.value, false);
    final current = tts.startChapter('新章节', title: 'new');
    await waitForUtterances(2);
    utterances.first.complete(1);
    await old;
    await emit('speak.onComplete');
    await emit('speak.onCancel');
    expect(tts.isSessionActive.value, true);
    expect(tts.isPlaying.value, true);
    expect(tts.sessionTitle.value, 'new');
    expect(utterances, hasLength(2));
    utterances.last.complete(1);
    await current;
    expect(tts.isPlaying.value, false);
  });

  test('原生 stop 屏障结束前不启动新 speak，晚到 stop 不清除新状态', () async {
    warmUpGate.complete();
    await tts.ensureReady();
    stopGate = Completer<void>();
    final stopped = tts.stop();
    final playback = tts.startChapter('新章节');
    await flush();
    expect(calls.where((call) => call.method == 'speak'), isEmpty);
    stopGate!.complete();
    await Future.wait([stopped, playback]);
    expect(calls.where((call) => call.method == 'speak'), hasLength(1));
    expect(tts.lastSpokenText.value, '新章节');
  });

  test('分段仅由本次 speak Future 推进，暂停恢复不调用 stop', () async {
    warmUpGate.complete();
    holdSpeech = true;
    final text = List.filled(150, '字').join();
    final first = tts.startChapter(text);
    await waitForUtterances(1);
    await tts.pauseSession();
    expect(tts.isPaused.value, true);
    final stops = calls.where((call) => call.method == 'stop').length;
    final resumed = tts.resumeSession();
    await waitForUtterances(2);
    expect(calls.where((call) => call.method == 'stop'), hasLength(stops));
    final spoken = calls.where((call) => call.method == 'speak').map((call) {
      final arguments = call.arguments;
      return arguments is Map ? arguments['text'] : arguments;
    });
    expect(spoken.toSet(), hasLength(1));
    utterances[0].complete(0);
    await first;
    expect(tts.isPlaying.value, true);
    utterances[1].complete(1);
    await waitForUtterances(3);
    expect(tts.sessionProgress.value, 0.5);
    utterances[2].complete(1);
    await resumed;
    expect(tts.isSessionActive.value, false);
  });

  test('引擎错误结束当前播放，后续播放可恢复', () async {
    warmUpGate.complete();
    holdSpeech = true;
    final first = tts.startChapter('出错章节');
    await waitForUtterances(1);
    await emit('speak.onError');
    await first;
    expect(tts.isSessionActive.value, false);
    expect(tts.isPlaying.value, false);
    final next = tts.startChapter('恢复章节');
    await waitForUtterances(2);
    utterances[0].complete(0);
    await flush();
    expect(tts.isSessionActive.value, true);
    utterances[1].complete(1);
    await next;
    expect(tts.isPlaying.value, false);
  });

  test('旧 speak Future 失败不结束新会话', () async {
    warmUpGate.complete();
    holdSpeech = true;
    final old = tts.startChapter('旧章节');
    await waitForUtterances(1);
    final current = tts.startChapter('新章节');
    await waitForUtterances(2);
    utterances[0].completeError(PlatformException(code: 'old_failure'));
    await old;
    await flush();
    expect(tts.isSessionActive.value, true);
    expect(tts.lastSpokenText.value, '新章节');
    utterances[1].complete(1);
    await current;
  });
}
