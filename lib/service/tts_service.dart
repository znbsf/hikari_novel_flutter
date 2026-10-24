import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:get/get.dart';
import 'package:hikari_novel_flutter/widgets/dialogs.dart';
import 'package:url_launcher/url_launcher.dart';

import '../common/log.dart';
import 'local_storage_service.dart';

class TtsService extends GetxService {
  static const MethodChannel _intentChannel = MethodChannel('hikari/system_intents');

  static TtsService get instance => Get.find<TtsService>();

  final FlutterTts _tts = FlutterTts();
  Future<void>? _ready;

  final enabled = false.obs;
  final engine = RxnString();
  final voice = Rxn<Map<String, String>>();
  final rate = 0.5.obs;
  final pitch = 1.0.obs;
  final volume = 1.0.obs;

  final engines = <String>[].obs;
  final voices = <Map<String, String>>[].obs;

  final isPlaying = false.obs;
  final isPaused = false.obs;
  final lastSpokenText = ''.obs;

  int _session = 0;
  Completer<dynamic>? _utteranceSignal;
  Future<void> _controls = Future<void>.value();

  int _invalidatePlayback() {
    final session = ++_session;
    final signal = _utteranceSignal;
    _utteranceSignal = null;
    if (signal != null && !signal.isCompleted) signal.complete(0);
    return session;
  }

  bool _isCurrent(int session) => session == _session && enabled.value;

  // Control calls never wait for a speak Future: stop/pause must interrupt it.
  Future<void> _control(Future<dynamic> Function() action) {
    final operation = _controls.then((_) async {
      await action();
    });
    _controls = operation.catchError((Object _) {});
    return operation;
  }

  final isSessionActive = false.obs;
  final sessionTitle = ''.obs;
  final sessionProgress = 0.0.obs;

  List<String> _chunks = const [];
  int _chunkIndex = 0;

  static const int _maxChunkLen = 140;

  static const String multiTtsEnginePackage = 'org.nobody.multitts';

  static const List<String> _preferredLocales = <String>['zh-CN', 'zh-TW', 'zh-HK', 'en-US'];

  void init() {
    // flutter_tts global callbacks carry no utterance identity. In particular,
    // a delayed onCancel/onComplete cannot safely change the current session.
    // Use the awaited speak call to advance chunks instead. The native plugin
    // itself stores a global result, so arbitrarily late native delivery still
    // requires utterance IDs in the plugin for a complete guarantee.
    // External native cancellations that never settle speak are likewise not
    // distinguishable from a delayed cancellation of an earlier utterance.
    // Android does not complete that Future on engine errors, so retain its
    // error event as a fallback. The plugin gives this event no utterance ID:
    // an extremely late native error cannot be attributed perfectly in Dart.
    _tts.setErrorHandler((message) {
      final signal = _utteranceSignal;
      if (signal != null && !signal.isCompleted) {
        signal.completeError(StateError('TTS engine error: $message'));
      }
    });
    enabled.value = LocalStorageService.instance.readerTtsEnabled.value;
    engine.value = LocalStorageService.instance.readerTtsEngine.value;
    voice.value = LocalStorageService.instance.readerTtsVoice.value;
    rate.value = LocalStorageService.instance.readerTtsRate.value;
    pitch.value = LocalStorageService.instance.readerTtsPitch.value;
    volume.value = LocalStorageService.instance.readerTtsVolume.value;
  }

  /// Concurrent callers share initialization; failure stays observable and retryable.
  Future<void> ensureReady() => _ready ??= _initialize();

  Future<void> _initialize() async {
    try {
      await _warmUp();
    } catch (_) {
      _ready = null;
      rethrow;
    }
  }

  Future<void> warmUpInBackground() async {
    try {
      await ensureReady();
    } catch (error) {
      Log.e("TTS 初始化失败: $error");
    }
  }

  Future<void> _warmUp() async {
    await _tts.awaitSpeakCompletion(true);

    await _tts.setSpeechRate(rate.value);
    await _tts.setPitch(pitch.value);
    await _tts.setVolume(volume.value);

    await _applyBestLanguage();

    await refreshEngines();

    final savedEngine = engine.value;
    final hasSaved = savedEngine != null && savedEngine.isNotEmpty && engines.contains(savedEngine);
    if (hasSaved) {
      await applyEngine(savedEngine);
    } else {
      await applyEngine(null);
    }

    await _applyBestLanguage();

    await refreshVoices();
    final savedVoice = voice.value;
    if (savedVoice != null && voices.any((v) => v["name"] == savedVoice["name"] && v["locale"] == savedVoice["locale"])) {
      await applyVoice(savedVoice);
    } else {
      voice.value = null;
      LocalStorageService.instance.readerTtsVoice.value = null;
    }
  }

  String displayEngineName(String enginePackage) {
    if (enginePackage == multiTtsEnginePackage) return "MultiTTS";
    return "system_tts".tr;
  }

  Future<void> refreshEngines() async {
    if (!Platform.isAndroid) return;
    try {
      final result = await _tts.getEngines;
      final list = (result as List?)?.cast<String>() ?? <String>[];
      list.sort((a, b) {
        if (a == multiTtsEnginePackage && b != multiTtsEnginePackage) return -1;
        if (b == multiTtsEnginePackage && a != multiTtsEnginePackage) return 1;
        return a.compareTo(b);
      });
      engines.assignAll(list);
    } catch (e) {
      Log.d("[TtsService] getEngines failed: $e");

      engines.clear();
    }
  }

  Future<void> refreshVoices() async {
    try {
      final result = await _tts.getVoices;
      final list = <Map<String, String>>[];
      if (result is List) {
        for (final v in result) {
          if (v is Map) {
            final name = v["name"]?.toString();
            final locale = v["locale"]?.toString();
            if (name != null && locale != null) {
              list.add({"name": name, "locale": locale});
            }
          }
        }
      }
      voices.assignAll(list);
    } catch (e) {
      Log.d("[TtsService] getVoices failed: $e");

      voices.clear();
    }
  }

  Future<void> setEnabled(bool v) async {
    enabled.value = v;
    LocalStorageService.instance.readerTtsEnabled.value = v;
    if (!v) await stop();
  }

  Future<void> applyEngine(String? e) async {
    engine.value = e;
    LocalStorageService.instance.readerTtsEngine.value = e;
    if (Platform.isAndroid && e != null && e.isNotEmpty) {
      try {
        await _tts.setEngine(e);
      } catch (err) {
        Log.d("[TtsService] setEngine failed: $err");
      }
    }
    await _applyBestLanguage();
  }

  Future<void> applyVoice(Map<String, String>? v) async {
    voice.value = v;
    LocalStorageService.instance.readerTtsVoice.value = v;
    if (v == null) return;
    try {
      await _tts.setVoice(v);
    } catch (err) {
      Log.d("[TtsService] setVoice failed: $err");
    }
  }

  Future<void> setRate(double v) async {
    rate.value = v;
    LocalStorageService.instance.readerTtsRate.value = v;
    await _tts.setSpeechRate(v);
  }

  Future<void> setPitch(double v) async {
    pitch.value = v;
    LocalStorageService.instance.readerTtsPitch.value = v;
    await _tts.setPitch(v);
  }

  Future<void> setVolume(double v) async {
    volume.value = v;
    LocalStorageService.instance.readerTtsVolume.value = v;
    await _tts.setVolume(v);
  }

  Future<void> refreshSettings({bool restartIfPlaying = true}) async {
    if (!enabled.value) return;

    if (restartIfPlaying && (isPlaying.value || isPaused.value || isSessionActive.value)) {
      final paused = pauseSession();
      final session = _session;
      await paused;
      await _prepareForSpeak();
      if (_isCurrent(session)) await resumeSession();
      return;
    }

    await _prepareForSpeak();
  }

  Future<void> openAndroidTtsSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _intentChannel.invokeMethod('openTtsSettings');
    } catch (e) {
      Log.d("[TtsService] openTtsSettings failed: $e");
      showSnackBar(message: "${"unable_to_open_system_setting".tr}: $e", context: Get.context!);
    }
  }

  Future<void> openAndroidApp(String packageName) async {
    if (!Platform.isAndroid) return;
    try {
      await _intentChannel.invokeMethod('openApp', {'package': packageName});
    } catch (e) {
      Log.d("[TtsService] openApp failed: $e");
    }
  }

  Future<void> openMultiTtsStore() async {
    final pkg = multiTtsEnginePackage;
    final market = Uri.parse('market://details?id=$pkg');
    final web = Uri.parse('https://play.google.com/store/apps/details?id=$pkg');
    if (await canLaunchUrl(market)) {
      await launchUrl(market, mode: LaunchMode.externalApplication);
    } else if (await canLaunchUrl(web)) {
      await launchUrl(web, mode: LaunchMode.externalApplication);
    }
  }

  bool get isMultiTtsInstalled => engines.contains(multiTtsEnginePackage);

  Future<void> speak(String text) => _start(text, chapter: false);

  Future<void> startChapter(String fullText, {String title = ''}) => _start(fullText, chapter: true, title: title);

  Future<void> _start(String text, {required bool chapter, String title = ''}) async {
    if (!enabled.value) return;
    final session = _invalidatePlayback();
    _endSession();
    // Queue interruption immediately, including while initialization is pending.
    final stopped = _control(_tts.stop);
    try {
      await stopped;
      await _prepareForSpeak();
      if (!_isCurrent(session)) return;
      final cleaned = chapter ? text.replaceAll(RegExp(r'\s+'), ' ').trim() : text;
      if (cleaned.trim().isEmpty) return;
      sessionTitle.value = title;
      lastSpokenText.value = cleaned;
      isSessionActive.value = chapter;
      _chunks = chapter ? _splitToChunks(cleaned) : [cleaned];
      _chunkIndex = 0;
      await _play(session);
    } catch (error) {
      _playbackFailed(session, error);
    }
  }

  Future<void> resumeSession() async {
    if (!enabled.value || isPlaying.value) return;
    final session = _invalidatePlayback();
    try {
      await _controls;
      await _prepareForSpeak();
      if (!_isCurrent(session)) return;
      if (_chunks.isEmpty) {
        if (lastSpokenText.value.trim().isNotEmpty) await speak(lastSpokenText.value);
        return;
      }
      // flutter_tts 4.2.5 resumes Android/iOS pause through speak(same text).
      // Do not stop here: stop clears the native pause position.
      isPaused.value = false;
      await _play(session);
    } catch (error) {
      _playbackFailed(session, error);
    }
  }

  Future<void> pauseSession() async {
    if (!enabled.value) return;
    final session = _invalidatePlayback();
    isPlaying.value = false;
    isPaused.value = true;
    try {
      await _control(_tts.pause);
    } catch (_) {
      if (!_isCurrent(session)) return;
      try {
        await _control(_tts.stop);
      } catch (_) {}
    }
  }

  Future<void> pause() => pauseSession();

  Future<void> stop() async {
    _invalidatePlayback();
    _endSession();
    try {
      await _control(_tts.stop);
    } catch (error) {
      Log.e("TTS 停止失败: $error");
    }
  }

  Future<void> _play(int session) async {
    while (_isCurrent(session) && !isPaused.value && _chunkIndex < _chunks.length) {
      final index = _chunkIndex;
      isPlaying.value = true;
      final signal = Completer<dynamic>();
      _utteranceSignal = signal;
      dynamic result;
      try {
        result = await Future.any<dynamic>([_tts.speak(_chunks[index]), signal.future]);
      } finally {
        if (identical(_utteranceSignal, signal)) _utteranceSignal = null;
      }
      if (!_isCurrent(session)) return;
      if (result is int && result == 0) {
        _playbackFailed(session, StateError('TTS speak failed'));
        return;
      }
      _chunkIndex = index + 1;
      sessionProgress.value = (_chunkIndex / _chunks.length).clamp(0.0, 1.0);
    }
    if (_isCurrent(session)) _endSession();
  }

  void _playbackFailed(int session, Object error) {
    if (!_isCurrent(session)) return;
    _endSession();
    Log.e("TTS 播放失败: $error");
    final context = Get.context;
    if (context != null) showSnackBar(message: "listen_to_books_failed_tip".tr, context: context);
  }

  Future<void> _prepareForSpeak() async {
    await ensureReady();
    await _tts.setSpeechRate(rate.value);
    await _tts.setPitch(pitch.value);
    await _tts.setVolume(volume.value);
    await _applyBestLanguage();
  }

  Future<void> _applyBestLanguage() async {
    final fromVoice = voice.value?['locale'];
    final deviceLocale = WidgetsBinding.instance.platformDispatcher.locale.toLanguageTag();

    final candidates = <String>{if (fromVoice != null && fromVoice.trim().isNotEmpty) fromVoice, deviceLocale, ..._preferredLocales}.toList();

    for (final loc in candidates) {
      if (await _trySetLanguage(loc)) {
        return;
      }
    }
  }

  Future<bool> _trySetLanguage(String locale) async {
    try {
      final available = await _tts.isLanguageAvailable(locale);
      if (available == null) {
        await _tts.setLanguage(locale);
        return true;
      }
      if (available is bool && !available) return false;
      await _tts.setLanguage(locale);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _endSession() {
    isSessionActive.value = false;
    isPlaying.value = false;
    isPaused.value = false;
    _chunks = const [];
    _chunkIndex = 0;
    sessionProgress.value = 0.0;
  }

  List<String> _splitToChunks(String text) {
    final parts = text.split(RegExp(r'(?<=[。！？!?；;])')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    final chunks = <String>[];
    final buf = StringBuffer();
    for (final p in parts.isEmpty ? [text] : parts) {
      if (buf.length + p.length <= _maxChunkLen) {
        buf.write(p);
      } else {
        if (buf.isNotEmpty) {
          chunks.add(buf.toString());
          buf.clear();
        }
        if (p.length <= _maxChunkLen) {
          buf.write(p);
        } else {
          for (var i = 0; i < p.length; i += _maxChunkLen) {
            chunks.add(p.substring(i, (i + _maxChunkLen).clamp(0, p.length)));
          }
        }
      }
    }
    if (buf.isNotEmpty) chunks.add(buf.toString());
    return chunks;
  }
}
