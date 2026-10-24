import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../models/reader_direction.dart';
import '../../../models/page_state.dart';
import '../../../service/tts_service.dart';
import '../../../widgets/dialogs.dart';
import '../controller.dart';
import 'catalogue_sheet.dart';
import 'custom_slider.dart';
import 'reader_setting.dart';
import 'vertical_read_page.dart';

class ReaderBottomBar extends StatelessWidget {
  const ReaderBottomBar({super.key, required this.controller, required this.verticalReadPageKey});

  final ReaderController controller;
  final GlobalKey<VerticalReadPageState> verticalReadPageKey;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      //底栏
      double navigationBarHeight = MediaQuery.of(context).padding.bottom;
      int bottomBarHeight = 100;
      return AnimatedPositioned(
        left: 0,
        right: 0,
        bottom: controller.showBar.value ? 0 : -(navigationBarHeight + bottomBarHeight),
        duration: const Duration(milliseconds: 100),
        child: Container(
          height: navigationBarHeight + bottomBarHeight,
          color: Theme.of(context).colorScheme.secondaryContainer,
          alignment: Alignment.center,
          child: Obx(
            () => Column(
              children: [
                SizedBox(width: double.infinity, child: _buildProgressBar(context)),
                Row(
                  children: [
                    Expanded(
                      child: IconButton(
                        onPressed: () {
                          if (controller.preferences.state.value.direction == ReaderDirection.rightToLeft) {
                            controller.nextChapter();
                          } else {
                            controller.prevChapter();
                          }
                        },
                        icon: const Icon(Icons.arrow_back),
                      ),
                    ),
                    Expanded(
                      child: IconButton(onPressed: () => showReaderCatalogueSheet(context, controller), icon: const Icon(Icons.list_alt)),
                    ),
                    Expanded(
                      child: IconButton(
                        onPressed: () => showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          showDragHandle: true,
                          builder: (_) => Scaffold(
                            appBar: AppBar(
                              leading: IconButton(onPressed: Get.back, icon: const Icon(Icons.close)),
                              title: Text("setting".tr),
                            ),
                            body: ReaderSettingPage(),
                          ),
                        ),
                        icon: const Icon(Icons.settings_outlined),
                      ),
                    ),
                    TtsService.instance.enabled.value
                        ? Expanded(
                            child: IconButton(
                              tooltip: "listen_to_books".tr,
                              onPressed: () async {
                                final tts = TtsService.instance;
                                final text = controller.text.value;
                                final cleaned = text.replaceAll(RegExp(r'\s+'), ' ').trim();
                                if (cleaned.isEmpty) {
                                  showSnackBar(message: "chapter_content_loading_tip".tr, context: context);
                                  return;
                                }

                                if (tts.isPlaying.value) {
                                  await tts.stop();
                                  return;
                                }
                                if (tts.isPaused.value && tts.isSessionActive.value) {
                                  await tts.resumeSession();
                                  return;
                                }

                                await tts.startChapter(cleaned);
                              },
                              icon: Obx(() {
                                final tts = TtsService.instance;
                                if (tts.isPlaying.value) {
                                  return const Icon(Icons.stop_circle_outlined);
                                }
                                return const Icon(Icons.play_circle_outline);
                              }),
                            ),
                          )
                        : Container(),
                    Expanded(
                      child: IconButton(
                        onPressed: () {
                          if (controller.preferences.state.value.direction == ReaderDirection.rightToLeft) {
                            controller.prevChapter();
                          } else {
                            controller.nextChapter();
                          }
                        },
                        icon: const Icon(Icons.arrow_forward),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget _buildProgressBar(BuildContext context) {
    return Obx(() {
      if (controller.pageState.value != PageState.success) {
        return SizedBox(height: 48, child: Container());
      }
      if (controller.preferences.state.value.direction == ReaderDirection.upToDown) {
        int value = controller.verticalProgress.value;

        return SizedBox(
          height: 48,
          child: Row(
            children: [
              SizedBox(width: 60, child: Center(child: Text("$value%"))),
              Expanded(
                child: Slider(
                  activeColor: Theme.of(context).colorScheme.primary,
                  inactiveColor: Theme.of(context).colorScheme.surface,
                  value: value.toDouble(),
                  max: 100.0,
                  onChanged: (e) {
                    verticalReadPageKey.currentState!.jumpToProgress(e);
                  },
                  divisions: 99,
                ),
              ),
              SizedBox(width: 60, child: Center(child: Text("100%"))),
            ],
          ),
        );
      } else {
        int value = controller.currentIndex.value + 1;
        int max = controller.maxPage.value;

        if (value > max || max == 1) {
          return SizedBox(height: 48, child: Center(child: Text("only_one_page".tr)));
        }
        return SizedBox(
          height: 48,
          child: Row(
            children: [
              SizedBox(
                width: 60,
                child: Center(
                  child: controller.preferences.state.value.direction == ReaderDirection.leftToRight ? Text(value.toString()) : Text(max.toString()),
                ),
              ),
              Expanded(
                child: CustomSlider(
                  min: 1,
                  max: max.toDouble(),
                  value: value.toDouble(),
                  divisions: max - 1,
                  onChanged: (v) => controller.jumpToPage((v - 1).toInt()),
                  focusNode: null,
                  reversed: controller.preferences.state.value.direction != ReaderDirection.leftToRight,
                ),
              ),
              SizedBox(
                width: 60,
                child: Center(
                  child: controller.preferences.state.value.direction == ReaderDirection.leftToRight ? Text(max.toString()) : Text(value.toString()),
                ),
              ),
            ],
          ),
        );
      }
    });
  }
}
