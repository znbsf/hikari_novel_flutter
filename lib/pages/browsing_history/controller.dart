import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hikari_novel_flutter/common/database/database.dart';
import 'package:hikari_novel_flutter/models/browsing_history.dart';
import 'package:hikari_novel_flutter/models/page_state.dart';
import 'package:hikari_novel_flutter/widgets/dialogs.dart';

class BrowsingHistoryController extends GetxController {
  Rx<PageState> pageState = Rx(PageState.loading);
  String errorMsg = "";
  RxList<BrowsingHistory> list = RxList();

  @override
  void onReady() {
    super.onReady();
    _sync();
  }

  void _sync() async {
    AppDatabase.instance.getWatchableAllBrowsingHistory().listen((history) {
      if (history.isEmpty) {
        pageState.value = PageState.empty;
        return;
      }
      list
        ..clear()
        ..addAll((history.map((e) => BrowsingHistory(aid: e.aid, title: e.title, img: e.img, time: e.time))))
        ..sort((a, b) => b.time.compareTo(a.time)); //按从新到旧的顺序进行排序
      pageState.value = PageState.success;
    });
  }

  void deleteAllBrowsingHistory() {
    showConfirmDialog(
      icon: Icon(Icons.delete_forever_outlined),
      title: "delete".tr,
      content: "delete_all_browsing_history_tip".tr,
      onConfirm: () => AppDatabase.instance.deleteAllBrowsingHistory(),
    );
  }
}
