import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart' show Get, Inst, GetxController, Rx, RxBool, RxInt, RxString, RxList, BoolExtension, IntExtension, StringExtension, Trans;
import 'package:hikari_novel_flutter/common/constants.dart';
import 'package:hikari_novel_flutter/models/dual_page_mode.dart';
import 'package:hikari_novel_flutter/models/reader_direction.dart';
import 'package:hikari_novel_flutter/service/tts_service.dart';
import 'package:hikari_novel_flutter/widgets/dialogs.dart';

import '../../common/database/database.dart';
import '../../models/cat_volume.dart';
import '../../models/page_state.dart';
import '../../service/local_storage_service.dart';
import 'reader_content.dart';
import 'reader_platform.dart';
import 'reader_settings.dart';
import 'widgets/catalogue_sheet.dart' show findIndexPositionInCatalogue;
import 'widgets/paper_curl_pager.dart';

export 'widgets/catalogue_sheet.dart' show findIndexPositionInCatalogue;

typedef ReaderHistoryWriter = Future<void> Function(ReadHistoryEntityData history);

class ReaderArgs {
  const ReaderArgs(this.aid, this.catalogue, this.cid, this.location);

  final String aid;
  final List<CatVolume> catalogue;
  final String cid;
  final int location;
}

/// Identity of the rendered chapter and reading mode that produced a layout event.
class ReaderProgressIdentity {
  const ReaderProgressIdentity(this.contentGeneration, this.layoutGeneration, this.direction, this.isDualPage);
  final int contentGeneration;
  final int layoutGeneration;
  final ReaderDirection direction;
  final bool isDualPage;
}

class ReaderController extends GetxController {
  ReaderController(this.args, {ChapterReader? readChapter, ReaderHistoryWriter? writeHistory, this._platform})
    : _readChapter = readChapter ?? readReaderChapter,
      _writeHistory = writeHistory ?? ((history) => AppDatabase.instance.upsertReadHistory(history)) {
    _locateInitialChapter();
  }

  final ReaderArgs args;
  final ChapterReader _readChapter;
  final ReaderHistoryWriter _writeHistory;
  final ReaderPlatform? _platform;
  List<CatVolume> get catalogue => args.catalogue;
  String get aid => args.aid;
  final preferences = ReaderPreferences(LocalStorageService.instance);
  late final platform = _platform ?? ReaderPlatform(settings: () => preferences.state.value, prevPage: prevPage, nextPage: nextPage);

  int currentVolumeIndex = -1;
  int currentChapterIndex = -1;
  bool get _hasChapter =>
      currentVolumeIndex >= 0 &&
      currentVolumeIndex < catalogue.length &&
      currentChapterIndex >= 0 &&
      currentChapterIndex < catalogue[currentVolumeIndex].chapters.length;
  String get cid => _hasChapter ? catalogue[currentVolumeIndex].chapters[currentChapterIndex].cid : args.cid;
  int get currentChapterTotal => _hasChapter ? catalogue[currentVolumeIndex].chapters.length : 0;
  int get currentVolumeTotal => catalogue.length;

  final pageController = PageController();
  final paperCurlController = PaperCurlPagerController();
  Rx<PageState> pageState = Rx(PageState.loading);
  RxBool showBar = false.obs;
  // Supplied by the view; saving history never needs a BuildContext.
  bool _autoDualPage = false;
  bool get autoDualPage => _autoDualPage;
  set autoDualPage(bool value) {
    if (_autoDualPage == value) return;
    _autoDualPage = value;
    _layoutGeneration++;
  }

  bool get isDualPage => switch (preferences.state.value.dualPageMode) {
    DualPageMode.auto => autoDualPage,
    DualPageMode.enabled => true,
    DualPageMode.disabled => false,
  };
  RxString chapterTitle = ''.obs;
  RxInt currentIndex = 0.obs;
  int initialHorizontalIndex = 0;
  RxInt horizontalProgress = 0.obs;
  RxInt maxPage = 0.obs;
  RxInt currentLocation = 0.obs;
  int initialVerticalOffset = 0;
  RxInt verticalProgress = 0.obs;
  RxString text = ''.obs;
  RxList<String> images = RxList();
  String errorMsg = '';

  bool _closed = false;
  int _generation = 0;
  String? _displayedCid;
  Timer? _historyTimer;
  int _layoutGeneration = 0;
  ReadHistoryEntityData? _lastProgress;
  Future<void> _historyWrites = Future.value();
  Object? historyError;
  int get contentGeneration => _generation;
  ReaderProgressIdentity get progressIdentity => ReaderProgressIdentity(_generation, _layoutGeneration, preferences.state.value.direction, isDualPage);

  void _locateInitialChapter() {
    final ids = catalogue.map((volume) => volume.chapters.map((chapter) => chapter.cid).toList()).toList();
    final position = findIndexPositionInCatalogue({'catalogue': ids, 'cid': args.cid});
    if (position != null) {
      currentVolumeIndex = position[0];
      currentChapterIndex = position[1];
      return;
    }
    for (var volume = 0; volume < catalogue.length; volume++) {
      if (catalogue[volume].chapters.isNotEmpty) {
        currentVolumeIndex = volume;
        currentChapterIndex = 0;
        return;
      }
    }
  }

  @override
  void onInit() {
    super.onInit();
    preferences.onChanged = (previous, next) {
      if (previous.direction != next.direction || previous.dualPageMode != next.dualPageMode || previous.pageTurningAnimation != next.pageTurningAnimation) {
        _layoutGeneration++;
      }
      platform.settingsChanged(previous, next);
    };
    platform.onInit();
    if (cid == args.cid) getInitLocation();
  }

  @override
  void onReady() {
    super.onReady();
    if (_closed) return;
    platform.onReady();
    getContent();
  }

  @override
  void onClose() {
    if (_closed) return;
    final last = _lastProgress;
    _closed = true;
    _generation++;
    _historyTimer?.cancel();
    preferences.close();
    if (last != null) _enqueueHistory(last);
    if (Get.isRegistered<TtsService>()) TtsService.instance.stop();
    platform.onClose();
    pageController.dispose();
    super.onClose();
  }

  int getInitLocation() {
    final value = args.location;
    if (preferences.state.value.direction == ReaderDirection.upToDown) {
      currentLocation.value = value;
      initialVerticalOffset = value;
    } else {
      currentIndex.value = value;
      initialHorizontalIndex = value;
    }
    return value;
  }

  void clearInitLocation() {
    initialHorizontalIndex = 0;
    initialVerticalOffset = 0;
  }

  void selectChapter(int volumeIndex, int chapterIndex) {
    if (_closed || volumeIndex < 0 || volumeIndex >= catalogue.length || chapterIndex < 0 || chapterIndex >= catalogue[volumeIndex].chapters.length) {
      return;
    }
    currentVolumeIndex = volumeIndex;
    currentChapterIndex = chapterIndex;
    clearInitLocation();
    getContent();
  }

  Future<void> getContent() async {
    if (_closed) return;
    final last = _lastProgress;
    if (last != null) _enqueueHistory(last);
    _historyTimer?.cancel();
    final generation = ++_generation;
    _displayedCid = null;
    _lastProgress = null;
    pageState.value = PageState.loading;
    chapterTitle.value = '';
    if (!_hasChapter) {
      errorMsg = 'No chapters available';
      pageState.value = PageState.error;
      return;
    }
    final chapter = catalogue[currentVolumeIndex].chapters[currentChapterIndex];
    try {
      final content = await _readChapter(aid, chapter.cid);
      if (_closed || generation != _generation) return;
      images.value = content.images;
      chapterTitle.value = chapter.title;
      text.value = content.text;
      currentIndex.value = initialHorizontalIndex;
      currentLocation.value = initialVerticalOffset;
      horizontalProgress.value = 0;
      verticalProgress.value = 0;
      maxPage.value = 0;
      _displayedCid = chapter.cid;
      pageState.value = PageState.success;
    } catch (error) {
      if (_closed || generation != _generation) return;
      errorMsg = error.toString();
      pageState.value = PageState.error;
    }
  }

  /// A callback is valid only for the chapter and mode that it rendered.
  bool _acceptProgress(ReaderProgressIdentity identity) =>
      !_closed &&
      identity.contentGeneration == _generation &&
      identity.layoutGeneration == _layoutGeneration &&
      identity.direction == preferences.state.value.direction &&
      identity.isDualPage == isDualPage &&
      _displayedCid != null &&
      pageState.value == PageState.success;

  void _recordProgress(ReaderProgressIdentity identity, int location, int progress) {
    _lastProgress = ReadHistoryEntityData(
      cid: _displayedCid!,
      aid: aid,
      readerMode: identity.direction == ReaderDirection.upToDown ? kScrollReadMode : kPageReadMode,
      isDualPage: identity.isDualPage,
      location: location,
      progress: progress,
      isLatest: true,
    );
  }

  void updateHorizontalProgress(ReaderProgressIdentity identity, int index, int max) {
    if (!_acceptProgress(identity) || identity.direction == ReaderDirection.upToDown || max <= 0) return;
    currentIndex.value = index;
    maxPage.value = max;
    horizontalProgress.value = int.parse(((index + 1) / max * 100.0).toStringAsFixed(0)).clamp(0, 100);
    _recordProgress(identity, index, horizontalProgress.value);
    if (max == 1 && index == 0) {
      setReadHistory();
    } else {
      _scheduleHistory();
    }
  }

  void updateVerticalProgress(ReaderProgressIdentity identity, double position, double max) {
    if (!_acceptProgress(identity) || identity.direction != ReaderDirection.upToDown) return;
    if (max == 0 && position == 0) {
      currentLocation.value = 0;
      verticalProgress.value = 100;
      _recordProgress(identity, 0, 100);
      setReadHistory();
    } else if (max > 0) {
      currentLocation.value = position.toInt();
      verticalProgress.value = ((position / max) * 100).clamp(0, 100).toInt();
      _recordProgress(identity, currentLocation.value, verticalProgress.value);
      _scheduleHistory();
    }
  }

  void nextPage() {
    if (_closed || pageState.value != PageState.success) return;
    currentIndex.value >= maxPage.value - 1 ? nextChapter() : jumpToPage(currentIndex.value + 1);
  }

  void prevPage() {
    if (_closed || pageState.value != PageState.success) return;
    currentIndex.value == 0 ? prevChapter() : jumpToPage(currentIndex.value - 1);
  }

  void jumpToPage(int page) {
    if (_closed || pageState.value != PageState.success) return;
    if (preferences.state.value.direction != ReaderDirection.upToDown && preferences.state.value.pageTurningAnimation) {
      paperCurlController.jumpToPage(page);
      return;
    }
    if (!pageController.hasClients) return;
    preferences.state.value.pageTurningAnimation
        ? pageController.animateToPage(page, duration: const Duration(milliseconds: 200), curve: Curves.linear)
        : pageController.jumpToPage(page);
  }

  void _adjacentChapter(int direction) {
    if (_closed || !_hasChapter) return;
    var volume = currentVolumeIndex;
    var chapter = currentChapterIndex + direction;
    while (volume >= 0 && volume < catalogue.length) {
      if (chapter >= 0 && chapter < catalogue[volume].chapters.length) {
        selectChapter(volume, chapter);
        return;
      }
      volume += direction;
      if (volume >= 0 && volume < catalogue.length) {
        chapter = direction > 0 ? 0 : catalogue[volume].chapters.length - 1;
      }
    }
    showMessageDialog(title: 'warning'.tr, content: (direction > 0 ? 'no_next_chapter' : 'no_previous_chapter').tr, icon: const Icon(Icons.warning_amber));
  }

  void nextChapter() => _adjacentChapter(1);
  void prevChapter() => _adjacentChapter(-1);

  void _scheduleHistory() {
    final snapshot = _lastProgress;
    if (_closed || snapshot == null) return;
    _historyTimer?.cancel();
    final generation = _generation;
    _historyTimer = Timer(const Duration(milliseconds: 150), () {
      if (!_closed && generation == _generation) _enqueueHistory(snapshot);
    });
  }

  /// Serial writes preserve latest-chapter ordering even if the database is slow.
  void _enqueueHistory(ReadHistoryEntityData snapshot) {
    _historyWrites = _historyWrites.then((_) async {
      try {
        await _writeHistory(snapshot);
        historyError = null;
      } catch (error) {
        historyError = error;
      }
    });
  }

  Future<void> setReadHistory() {
    if (_closed) return _historyWrites;
    _historyTimer?.cancel();
    final snapshot = _lastProgress;
    if (snapshot != null) _enqueueHistory(snapshot);
    return _historyWrites;
  }

  /// Lets an owner wait for the final snapshot already queued by onClose.
  Future<void> get historySettled => _historyWrites;
}
