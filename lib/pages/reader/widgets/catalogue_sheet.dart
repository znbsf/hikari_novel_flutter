import 'package:flutter/material.dart';
import 'package:get/get.dart' show Get, GetNavigation;

import '../controller.dart';

void showReaderCatalogueSheet(BuildContext context, ReaderController controller) {
  showModalBottomSheet(
    context: context,
    enableDrag: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => SafeArea(
      child: BottomSheet(
        onClosing: () {},
        builder: (_) => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListView.builder(
                shrinkWrap: true,
                physics: NeverScrollableScrollPhysics(),
                itemCount: controller.catalogue.length,
                itemBuilder: (context, volumeIndex) {
                  final volume = controller.catalogue[volumeIndex];

                  return ExpansionTile(
                    shape: const Border(),
                    title: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(volume.title, style: const TextStyle(fontSize: 15)),
                    ),
                    children: volume.chapters.asMap().entries.map((entry) {
                      final chapterIndex = entry.key;
                      final chapter = entry.value;

                      return ListTile(
                        title: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            volumeIndex == controller.currentVolumeIndex && chapterIndex == controller.currentChapterIndex
                                ? Row(
                                    children: [
                                      SizedBox(height: 22, child: Icon(Icons.arrow_circle_right, color: Theme.of(context).colorScheme.primary)),
                                      const SizedBox(width: 10),
                                    ],
                                  )
                                : Container(),
                            Text(
                              chapter.title,
                              style: volumeIndex == controller.currentVolumeIndex && chapterIndex == controller.currentChapterIndex
                                  ? TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)
                                  : const TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                        contentPadding: const EdgeInsets.only(left: 50.0, right: 10.0),
                        onTap: () {
                          controller.selectChapter(volumeIndex, chapterIndex);
                          Get.back();
                        },
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

///查找目标字符串在二维列表中出现的位置
///返回格式：[外层索引, 内层索引]，未找到则返回 null
List<int>? findIndexPositionInCatalogue(Map<String, dynamic> args) {
  final catalogue = args['catalogue'] as List<List<String>>;
  final targetCid = args['cid'] as String;

  // 遍历外层列表，同时获取索引和子列表
  for (int outerIndex = 0; outerIndex < catalogue.length; outerIndex++) {
    List<String> innerList = catalogue[outerIndex];
    // 查找目标字符串在当前子列表中的索引
    int innerIndex = innerList.indexOf(targetCid);
    // 如果找到（索引不为 -1），返回位置
    if (innerIndex != -1) {
      return [outerIndex, innerIndex];
      // return IndexPosition(volumeIndex: outerIndex, chapterIndex: innerIndex);
    }
  }
  return null;
}

