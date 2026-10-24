import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart'
    show Get, GetNavigation, GetxController, Rx, RxBool, RxInt, RxString, RxList, BoolExtension, IntExtension, StringExtension, debounce, Trans;
import 'package:hikari_novel_flutter/common/app_paths.dart';
import 'package:hikari_novel_flutter/common/constants.dart';
import 'package:hikari_novel_flutter/common/extension.dart';
import 'package:hikari_novel_flutter/models/dual_page_mode.dart';
import 'package:hikari_novel_flutter/models/reader_direction.dart';
import 'package:hikari_novel_flutter/models/resource.dart';
import 'package:hikari_novel_flutter/parser/parser.dart';
import 'package:hikari_novel_flutter/service/tts_service.dart';
import 'package:hikari_novel_flutter/widgets/dialogs.dart';

import '../../common/database/database.dart';
import '../../common/log.dart';
import '../../models/cat_volume.dart';
import '../../models/page_state.dart';
import '../../service/api_service.dart';
import '../../service/local_storage_service.dart';
import 'reader_platform.dart';
import 'reader_settings.dart';
import 'widgets/catalogue_sheet.dart' show findIndexPositionInCatalogue;
import 'widgets/paper_curl_pager.dart';

export 'widgets/catalogue_sheet.dart' show findIndexPositionInCatalogue;

class ReaderArgs {
  const ReaderArgs(this.aid, this.catalogue, this.cid, this.location);

  final String aid;
  final List<CatVolume> catalogue;
  final String cid;
  final int location;
}

class ReaderController extends GetxController {
  ReaderController(this.args);

  final ReaderArgs args;
  List<CatVolume> get catalogue => args.catalogue;
  String get aid => args.aid;
  final preferences = ReaderPreferences(LocalStorageService.instance);
  late final platform = ReaderPlatform(settings: () => preferences.state.value, prevPage: prevPage, nextPage: nextPage);

  late int currentVolumeIndex;
  late int currentChapterIndex;

  String get cid => catalogue[currentVolumeIndex].chapters[currentChapterIndex].cid;

  int get currentChapterTotal => catalogue[currentVolumeIndex].chapters.length;

  int get currentVolumeTotal => catalogue.length;

  final pageController = PageController();
  final paperCurlController = PaperCurlPagerController();

  Rx<PageState> pageState = Rx(PageState.loading);

  ///阅读界面显示操作栏
  RxBool showBar = false.obs;

  bool get isDualPage => switch (preferences.state.value.dualPageMode) {
    DualPageMode.auto => Get.context!.shouldAutoUseDualPage(),
    DualPageMode.enabled => true,
    DualPageMode.disabled => false,
  };

  RxString chapterTitle = "".obs;

  ///当前页面，横向用
  RxInt currentIndex = 0.obs;
  int initialHorizontalIndex = 0;

  RxInt horizontalProgress = 0.obs;

  ///最大页面
  RxInt maxPage = 0.obs;

  ///阅读位置，竖向用
  RxInt currentLocation = 0.obs;
  int initialVerticalOffset = 0;

  ///竖向模式下，显示当前阅读进度的百分比
  RxInt verticalProgress = 0.obs;

  ///文本内容
  RxString text = "".obs;

  RxList<String> images = RxList();

  String errorMsg = "";

  @override
  void onInit() {
    super.onInit();
    preferences.onChanged = platform.settingsChanged;
    platform.onInit();
    preferences.initialize(Theme.of(Get.context!).brightness);

    getInitLocation(); //事先赋值一下对应的变量，防止在build过程中修改obx变量

    //延迟更新阅读记录
    //debounce / ever / interval 只能在 Controller 生命周期里创建一次
    //TODO 还需要优化
    debounce(currentLocation, (_) => setReadHistory(), time: const Duration(milliseconds: 150));
    debounce(currentIndex, (_) => setReadHistory(), time: const Duration(milliseconds: 150));
  }

  @override
  void onReady() async {
    super.onReady();
    platform.onReady();

    /*
     1) 至于这里的cid为什么不直接使用上面的<get cid>，是因为上面的<get cid>依赖currentVolumeIndex和currentChapterIndex。
        而我们想要currentVolumeIndex和currentChapterIndex的时候，需要根据cid，在catalogue中获取其对应的VolumeIndex和ChapterIndex。
     2) 因为getContent()函数依赖cid，所以我把初始化cid的过程放到了onReady而不是onInit中。
     */
    final listOnlyWithCid = catalogue.map((cat) => cat.chapters.map((chap) => chap.cid).toList()).toList(); //仅提取含有cid的list
    final targetCid = args.cid;
    final indexPosition = findIndexPositionInCatalogue({'catalogue': listOnlyWithCid, 'cid': targetCid})!;

    currentVolumeIndex = indexPosition[0];
    currentChapterIndex = indexPosition[1];

    chapterTitle.value = catalogue[currentVolumeIndex].chapters[currentChapterIndex].title;

    await getContent();
  }

  @override
  void onClose() {
    TtsService.instance.stop();
    platform.onClose();
    super.onClose();
  }

  //获取初始页面位置
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
    currentVolumeIndex = volumeIndex;
    currentChapterIndex = chapterIndex;
    clearInitLocation();
    getContent();
  }

  Future<void> getContent() async {
    pageState.value = PageState.loading;

    chapterTitle.value = "";
    final chapter = await _getChapterContentFromLocal();
    chapter == null ? await _getContentByNetwork() : await _getContentByLocal(chapter);
  }

  Future<String?> _getChapterContentFromLocal() async {
    final file = AppPaths.cachedChapterFile(aid, cid);
    if (!await file.exists()) return null;
    return await file.readAsString();
  }

  Future<void> _getContentByNetwork() async {
    final result = await ApiService.instance.getNovelContent(aid: aid, cid: cid);
    switch (result) {
      case Success():
        {
          final content = await compute(Parser.getContent, result.data as String);
          images.value = content.images;
          chapterTitle.value = catalogue[currentVolumeIndex].chapters[currentChapterIndex].title;
          text.value = content.text;

          pageState.value = PageState.success;
        }
      case Error():
        {
          errorMsg = result.error.toString();
          pageState.value = PageState.error;
        }
    }
  }

  Future<void> _getContentByLocal(String result) async {
    final content = await compute(Parser.getContent, result);
    images.value = content.images;
    chapterTitle.value = catalogue[currentVolumeIndex].chapters[currentChapterIndex].title;
    text.value = content.text;
    pageState.value = PageState.success;
  }

  /// 下一页
  void nextPage() {
    var value = currentIndex.value;
    var max = maxPage.value;
    if (value >= max - 1) {
      nextChapter();
    } else {
      jumpToPage(value + 1);
    }
  }

  /// 上一页
  void prevPage() {
    var value = currentIndex.value;
    if (value == 0) {
      prevChapter();
    } else {
      jumpToPage(value - 1);
    }
  }

  /// 跳转页数
  void jumpToPage(int page) {
    if (preferences.state.value.direction != ReaderDirection.upToDown && preferences.state.value.pageTurningAnimation) {
      paperCurlController.jumpToPage(page);
      return;
    }
    preferences.state.value.pageTurningAnimation
        ? pageController.animateToPage(page, duration: const Duration(milliseconds: 200), curve: Curves.linear)
        : pageController.jumpToPage(page);
  }

  void nextChapter() {
    if (currentVolumeIndex + 1 == currentVolumeTotal && currentChapterIndex + 1 == currentChapterTotal) {
      showMessageDialog(title: "warning".tr, content: "no_next_chapter".tr, icon: Icon(Icons.warning_amber));
    } else {
      if (currentVolumeIndex + 1 != currentVolumeTotal && currentChapterIndex + 1 == currentChapterTotal) {
        currentVolumeIndex++;
        currentChapterIndex = 0;
      } else {
        currentChapterIndex++;
      }

      clearInitLocation();
      getContent();
    }
  }

  void prevChapter() {
    if (currentVolumeIndex - 1 == -1 && currentChapterIndex - 1 == -1) {
      showMessageDialog(title: "warning".tr, content: "no_previous_chapter".tr, icon: Icon(Icons.warning_amber));
    } else {
      if (currentVolumeIndex - 1 != -1 && currentChapterIndex - 1 == -1) {
        currentVolumeIndex--;
        currentChapterIndex = currentChapterTotal - 1;
      } else {
        currentChapterIndex--;
      }

      clearInitLocation();
      getContent();
    }
  }

  void setReadHistory() async {
    Log.d("setReadHistory");
    await AppDatabase.instance.upsertReadHistory(
      ReadHistoryEntityData(
        cid: cid,
        aid: aid,
        readerMode: preferences.state.value.direction == ReaderDirection.upToDown ? kScrollReadMode : kPageReadMode,
        // 1为滚动模式，2为翻页模式，翻页模式的左右方向不影响阅读记录的使用
        isDualPage: isDualPage,
        location: preferences.state.value.direction == ReaderDirection.upToDown ? currentLocation.value : currentIndex.value,
        progress: preferences.state.value.direction == ReaderDirection.upToDown ? verticalProgress.value : horizontalProgress.value,
        isLatest: true,
      ),
    );
  }

}
