import '../../service/session_service.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hikari_novel_flutter/common/app_paths.dart';
import 'package:hikari_novel_flutter/common/constants.dart';
import 'package:hikari_novel_flutter/common/extension.dart';
import 'package:hikari_novel_flutter/models/chapter_cache_task.dart';
import 'package:hikari_novel_flutter/models/common/wenku8_node.dart';
import 'package:hikari_novel_flutter/models/novel_detail.dart';
import 'package:hikari_novel_flutter/models/reader_direction.dart';
import 'package:hikari_novel_flutter/pages/bookshelf/controller.dart';
import 'package:hikari_novel_flutter/pages/cache_queue/controller.dart';
import 'package:hikari_novel_flutter/parser/parser.dart';
import 'package:hikari_novel_flutter/widgets/dialogs.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../common/database/database.dart';
import '../../models/cat_chapter.dart';
import '../../models/dual_page_mode.dart';
import '../../models/page_state.dart';
import '../../models/resource.dart';
import '../../service/api_service.dart';
import '../../service/local_storage_service.dart';

T _findOrPut<T>(T Function() creator) {
  try {
    return Get.find<T>();
  } catch (_) {
    final instance = creator();
    Get.put<T>(instance);
    return instance;
  }
}

class NovelDetailController extends GetxController with GetSingleTickerProviderStateMixin {
  final String aid;

  NovelDetailController({
    required this.aid,
    Future<NovelDetail> Function(String)? fetchDetail,
    Future<String?> Function(String)? readCache,
    Future<void> Function(String, NovelDetail)? saveDetail,
    Future<bool> Function(String)? checkShelf,
    SessionCoordinator? session,
  }) : _fetchDetail = fetchDetail ?? _fetchRemote,
       _readCache = readCache ?? ((aid) async => (await AppDatabase.instance.getNovelDetail(aid))?.json),
       _saveDetail = saveDetail ?? _persistDetail,
       _checkShelf = checkShelf ?? ((aid) async => (await AppDatabase.instance.getAllBookshelf()).any((book) => book.aid == aid)),
       _session = session ?? SessionCoordinator.instance;

  final Future<NovelDetail> Function(String) _fetchDetail;
  final Future<String?> Function(String) _readCache;
  final Future<void> Function(String, NovelDetail) _saveDetail;
  final Future<bool> Function(String) _checkShelf;
  final SessionCoordinator _session;
  int _loadGeneration = 0;
  bool _closed = false;
  bool _animationInitialized = false;
  Future<void> _detailWrites = Future.value();

  static Future<NovelDetail> _fetchRemote(String aid) async {
    final detailResult = await ApiService.instance.getNovelDetail(aid: aid);
    if (detailResult case Error()) throw StateError('Novel detail request failed');
    final detail = Parser.getNovelDetail(detailResult.data as String);
    final catalogueResult = await ApiService.instance.getCatalogue(aid: aid);
    if (catalogueResult case Error()) throw StateError('Catalogue request failed');
    detail.catalogue.addAll(Parser.getCatalogue(catalogueResult.data as String));
    return detail;
  }

  static Future<void> _persistDetail(String aid, NovelDetail detail) => AppDatabase.instance.transaction(() async {
    await AppDatabase.instance.upsertNovelDetail(NovelDetailEntityData(aid: aid, json: detail.toString()));
    await AppDatabase.instance.upsertBrowsingHistory(BrowsingHistoryEntityData(aid: aid, title: detail.title, img: detail.imgUrl, time: DateTime.now()));
  });

  Rx<PageState> pageState = PageState.loading.obs;
  String errorMsg = "";
  Rxn<NovelDetail> novelDetail = Rxn();

  RxSet<String> cachedChapter = RxSet();

  RxBool isInBookshelf = false.obs;

  RxBool isChapterOrderReversed = false.obs;

  RxBool isSelectionMode = false.obs;

  bool _isFabVisible = true;
  late final AnimationController _fabAnimationCtr;
  late final Animation<Offset> animation;

  late final bookshelfController = Get.find<BookshelfController>();
  late final cacheQueueController = _findOrPut(() => CacheQueueController());

  @override
  void onInit() {
    super.onInit();
    _fabAnimationCtr = AnimationController(vsync: this, duration: const Duration(milliseconds: 100))..forward();
    _animationInitialized = true;
    animation = _fabAnimationCtr.drive(Tween<Offset>(begin: const Offset(0.0, 2.0), end: Offset.zero).chain(CurveTween(curve: Curves.easeInOut)));
  }

  @override
  void onReady() {
    super.onReady();
    getNovelDetail();
  }

  @override
  void onClose() {
    _closed = true;
    _loadGeneration++;
    if (_animationInitialized) _fabAnimationCtr.dispose();
    super.onClose();
  }

  void showFab() {
    if (!_isFabVisible) {
      _isFabVisible = true;
      _fabAnimationCtr.forward();
    }
  }

  void hideFab() {
    if (_isFabVisible) {
      _isFabVisible = false;
      _fabAnimationCtr.reverse();
    }
  }

  void enterSelectionMode() => isSelectionMode.value = true;

  void exitSelectionMode() {
    isSelectionMode.value = false;
    deselect();
  }

  //切换某个章节的选中状态（假设 chapter.isSelected 是 RxBool）
  void toggleChapterSelection(int volumeIndex, int chapterIndex) {
    final chapter = novelDetail.value!.catalogue[volumeIndex].chapters[chapterIndex];
    chapter.isSelected.toggle();
    _syncVolumeSelection(volumeIndex);
  }

  //切换某卷（全部选中或全部取消）
  void toggleVolumeSelection(int volumeIndex) {
    final volume = novelDetail.value!.catalogue[volumeIndex];
    final allSelected = volume.chapters.every((c) => c.isSelected.value);
    for (final c in volume.chapters) {
      c.isSelected.value = !allSelected;
    }
    volume.isSelected.value = !allSelected;
  }

  //根据章节选中数同步卷状态
  void _syncVolumeSelection(int volumeIndex) {
    final volume = novelDetail.value!.catalogue[volumeIndex];
    final total = volume.chapters.length;
    final selected = volume.chapters.where((c) => c.isSelected.value).length;
    if (selected == 0) {
      volume.isSelected.value = false;
    } else if (selected == total) {
      volume.isSelected.value = true;
    } else {
      //部分选中：你可以用单独字段或在 UI 用 selected数判断
      volume.isSelected.value = false;
    }
  }

  //获取选中的章节列表
  List<CatChapter> getSelectedChapters() {
    final out = <CatChapter>[];
    final detail = novelDetail.value;
    if (detail == null) return out;
    for (final vol in detail.catalogue) {
      for (final ch in vol.chapters) {
        if (ch.isSelected.value) out.add(ch);
      }
    }
    return out;
  }

  int getSelectedCount() => getSelectedChapters().length;

  void deselect() {
    final detail = novelDetail.value;
    if (detail == null) return;
    for (final vol in detail.catalogue) {
      vol.isSelected.value = false;
      for (final ch in vol.chapters) {
        ch.isSelected.value = false;
      }
    }
  }

  void selectAll() {
    final detail = novelDetail.value;
    if (detail == null) return;
    for (final vol in detail.catalogue) {
      vol.isSelected.value = true;
      for (final ch in vol.chapters) {
        ch.isSelected.value = true;
      }
    }
  }

  Future<void> startCache() async {
    for (var chap in getSelectedChapters()) {
      await cacheQueueController.addTask(
        ChapterCacheTask(
          uuid: "${aid}_${chap.cid}",
          aid: aid,
          cid: chap.cid,
          title: chap.title,
          onCompleted: (cid) {
            cachedChapter.add(cid);
          },
        ),
      );
    }
  }

  Future<void> deleteCache() async {
    final dir = AppPaths.cachedChapterDir;

    if (!await dir.exists()) {
      return;
    }

    await for (var entity in dir.list()) {
      if (entity is File) {
        final fileName = entity.uri.pathSegments.last;

        if (fileName.contains("_")) {
          final prefix = fileName.split("_").first;
          final last = fileName.split("_").last;

          final number = int.tryParse(prefix);
          if (number != null && number == int.parse(aid)) {
            try {
              await entity.delete();
            } catch (e) {
              null;
            }
          }
          cachedChapter.remove(last);
        }
      }
    }
  }

  void checkIsChapterCached(String cid) async {
    if (await AppPaths.cachedChapterFile(aid, cid).exists()) {
      cachedChapter.add(cid);
    } else {
      cachedChapter.remove(cid);
    }
  }

  Future<void> getNovelDetail() async {
    final generation = ++_loadGeneration;
    final session = _session.generation;
    bool current() => !_closed && generation == _loadGeneration && _session.isCurrent(session);
    if (!current()) return;
    if (novelDetail.value == null) pageState.value = PageState.loading;
    errorMsg = '';
    try {
      final detail = await _fetchDetail(aid);
      if (!current()) return;
      final onShelf = await _checkShelf(aid);
      if (!current()) return;
      // A stale completion cannot write after a newer local commit.
      final write = _detailWrites.then((_) async {
        if (current()) await _saveDetail(aid, detail);
      });
      _detailWrites = write.then<void>((_) {}, onError: (Object _, StackTrace _) {});
      await write;
      if (!current()) return;
      novelDetail.value = detail;
      isInBookshelf.value = onShelf;
      pageState.value = PageState.success;
    } catch (error) {
      if (!current()) return;
      // Parsing failures follow the same fallback as network failures. Never
      // replace a known-good cache with partially parsed detail/catalogue data.
      errorMsg = error.toString();
      if (novelDetail.value != null) {
        pageState.value = PageState.error;
        return;
      }
      try {
        final cached = await _readCache(aid);
        if (!current()) return;
        if (cached != null) {
          final detail = NovelDetail.fromString(cached);
          if (detail.title.trim().isEmpty) throw const FormatException('Invalid cached detail');
          novelDetail.value = detail;
          pageState.value = PageState.success;
          return;
        }
      } catch (_) {
        // Preserve an unreadable cache for later recovery; surface a retry.
      }
      if (current()) pageState.value = PageState.error;
    }
  }

  bool _isAdding = false; //防抖
  Future<void> addToBookshelf() async {
    if (_isAdding) return;
    _isAdding = true;
    final session = SessionCoordinator.instance;
    final generation = session.generation;
    bool current() => !isClosed && session.isCurrent(generation);
    try {
      if (!current()) return;
      final result = await ApiService.instance.addNovel(aid: aid);
      if (!current()) return;
      switch (result) {
        case Success():
          if (Parser.isError(result.data)) {
            showMessageDialog(title: "warning".tr, content: "add_to_bookshelf_failed_tip".tr, icon: const Icon(Icons.warning_amber_outlined));
            isInBookshelf.value = false;
          } else {
            // The remote addition succeeded even if synchronizing its local mirror fails.
            isInBookshelf.value = true;
            try {
              await bookshelfController.refreshDefaultBookshelf();
            } catch (_) {
              if (!current()) return;
              showErrorDialog("update_failed".tr, [TextButton(onPressed: Get.back, child: Text("confirm".tr))]);
            }
          }
        case Error():
          showErrorDialog(result.error.toString(), [TextButton(onPressed: Get.back, child: Text("confirm".tr))]);
      }
    } catch (error) {
      if (!current()) return;
      showErrorDialog(error.toString(), [TextButton(onPressed: Get.back, child: Text("confirm".tr))]);
    } finally {
      _isAdding = false;
    }
  }

  bool _isRemoving = false; //防抖
  void removeFromBookshelf() async {
    if (_isRemoving) return;
    _isRemoving = true;
    final bs = await AppDatabase.instance.getAllBookshelf();
    final delId = bs.firstWhere((i) => i.aid == aid).bid;
    final result = await ApiService.instance.removeNovel(delid: delId);
    switch (result) {
      case Success():
        {
          isInBookshelf.value = false;
        }
      case Error():
        {
          showErrorDialog(result.error.toString(), [TextButton(onPressed: Get.back, child: Text("confirm".tr))]);
        }
    }
    _isRemoving = false;
  }

  Future<void> recommendThisNovel() async {
    final generation = _session.generation;
    String message;
    try {
      final result = await ApiService.instance.novelVote(aid: aid);
      message = switch (result) {
        Success() => Parser.novelVote(result.data),
        Error() => result.error.toString(),
      };
    } catch (error) {
      message = error.toString();
    }
    if (_closed || !_session.isCurrent(generation)) return;
    final context = Get.context;
    if (context != null && context.mounted) showSnackBar(message: message, context: context);
  }

  Future<void> openWithBrowser() async {
    if (!await launchUrl(Uri.parse("${ApiService.instance.wenku8Node.node}/book/$aid.htm"))) {
      showSnackBar(message: "unable_to_open_external_browser".tr, context: Get.context!);
    }
  }

  ///检测阅读记录是否适用于当前设置（是否双页，阅读方向）
  bool isValidReadHistory(ReadHistoryEntityData? data) {
    if (data == null) {
      return false;
    } else {
      bool isDualPage = switch (LocalStorageService.instance.readerDualPageMode.value) {
        DualPageMode.auto => Get.context!.shouldAutoUseDualPage(),
        DualPageMode.enabled => true,
        DualPageMode.disabled => false,
      };
      bool isSameReaderMode = switch (LocalStorageService.instance.readerDirection.value) {
        ReaderDirection.leftToRight => data.readerMode == kPageReadMode,
        ReaderDirection.rightToLeft => data.readerMode == kPageReadMode,
        ReaderDirection.upToDown => data.readerMode == kScrollReadMode,
      };
      return data.isDualPage == isDualPage && isSameReaderMode;
    }
  }

  String getReadHistoryProgressByCid(ReadHistoryEntityData? result) {
    if (result == null) {
      return "unread".tr;
    }

    bool isDualPage = switch (LocalStorageService.instance.readerDualPageMode.value) {
      DualPageMode.auto => Get.context!.shouldAutoUseDualPage(),
      DualPageMode.enabled => true,
      DualPageMode.disabled => false,
    };

    final currDirection = LocalStorageService.instance.readerDirection.value;
    if (result.isDualPage == isDualPage) {
      if ((result.readerMode == kScrollReadMode && currDirection == ReaderDirection.upToDown) ||
          (result.readerMode == kPageReadMode && (currDirection == ReaderDirection.leftToRight || currDirection == ReaderDirection.rightToLeft))) {
        return "${result.progress}%";
      }
    }
    return "unable_to_use_read_history_tip".tr;
  }

  String getReadHistoryProgressByVolume(List<ReadHistoryEntityData> list, int totalNum) {
    int readCompletedNum = 0;
    int readPartiallyNum = 0;

    if (list.isEmpty) {
      return "unread".tr;
    }

    bool isDualPage = switch (LocalStorageService.instance.readerDualPageMode.value) {
      DualPageMode.auto => Get.context!.shouldAutoUseDualPage(),
      DualPageMode.enabled => true,
      DualPageMode.disabled => false,
    };
    final currDirection = LocalStorageService.instance.readerDirection.value;
    for (ReadHistoryEntityData d in list) {
      if (d.isDualPage == isDualPage) {
        if ((d.readerMode == kScrollReadMode && currDirection == ReaderDirection.upToDown) ||
            (d.readerMode == kPageReadMode && (currDirection == ReaderDirection.leftToRight || currDirection == ReaderDirection.rightToLeft))) {
          if (d.progress == 100) {
            readCompletedNum++;
          } else {
            readPartiallyNum++;
          }
        }
      }
    }

    if (readCompletedNum == totalNum) {
      return "all_reading_completed".tr;
    } else if (readPartiallyNum > 0 || (readCompletedNum > 0 && readCompletedNum < totalNum)) {
      return "partially_read".tr;
    } else {
      return "unread".tr;
    }
  }

  void deleteAllReadHistory() async => AppDatabase.instance.deleteAllReadHistory();

  Future<void> markAsUnRead() async {
    for (var chapter in getSelectedChapters()) {
      await AppDatabase.instance.deleteReadHistoryByCid(chapter.cid);
    }
  }

  Future<void> markAsRead() async {
    // 1为滚动模式，2为翻页模式，翻页模式的左右方向不影响阅读记录的使用
    final readerMode = LocalStorageService.instance.readerDirection.value == ReaderDirection.upToDown ? kScrollReadMode : kPageReadMode;
    bool isDualPage = switch (LocalStorageService.instance.readerDualPageMode.value) {
      DualPageMode.auto => Get.context!.shouldAutoUseDualPage(),
      DualPageMode.enabled => true,
      DualPageMode.disabled => false,
    };

    for (var chapter in getSelectedChapters()) {
      final data = await AppDatabase.instance.getReadHistoryByCid(chapter.cid);

      if (data == null) {
        AppDatabase.instance.upsertReadHistoryDirectly(
          ReadHistoryEntityData(cid: chapter.cid, aid: aid, readerMode: readerMode, isDualPage: isDualPage, location: 0, progress: 100, isLatest: false),
        );
      } else {
        AppDatabase.instance.upsertReadHistoryDirectly(
          ReadHistoryEntityData(
            cid: data.cid,
            aid: data.aid,
            readerMode: data.readerMode,
            isDualPage: data.isDualPage,
            location: data.location,
            progress: 100,
            isLatest: data.isLatest,
          ),
        );
      }
    }
  }
}
