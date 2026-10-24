import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hikari_novel_flutter/models/reader_direction.dart';
import 'package:hikari_novel_flutter/pages/reader/controller.dart';
import 'package:hikari_novel_flutter/pages/reader/widgets/horizontal_read_page.dart';
import 'package:hikari_novel_flutter/pages/reader/widgets/reader_background.dart';
import 'package:hikari_novel_flutter/pages/reader/widgets/tts_floating_controller.dart';
import 'package:hikari_novel_flutter/pages/reader/widgets/vertical_read_page.dart';
import 'package:hikari_novel_flutter/widgets/state_page.dart';

import '../../common/constants.dart';
import '../../models/page_state.dart';
import 'widgets/reader_bottom_bar.dart';
import 'widgets/reader_status_bar.dart';

class ReaderPage extends StatefulWidget {
  const ReaderPage({super.key});

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  final controller = Get.put(ReaderController(Get.arguments as ReaderArgs));

  final GlobalKey<VerticalReadPageState> _verticalReadPageKey = GlobalKey();

  EdgeInsets _contentPadding(BuildContext context, {required bool inPageStatusBar}) => EdgeInsets.fromLTRB(
    controller.preferences.state.value.leftMargin,
    controller.preferences.state.value.topMargin,
    controller.preferences.state.value.rightMargin,
    controller.preferences.state.value.showStatusBar
        ? controller.preferences.state.value.bottomMargin + kStatusBarPadding + (inPageStatusBar ? MediaQuery.of(context).padding.bottom : 0)
        : controller.preferences.state.value.bottomMargin,
  );

  TextStyle get textStyle => TextStyle(
    fontFamily: controller.preferences.state.value.textFamily,
    height: controller.preferences.state.value.lineSpacing,
    fontSize: controller.preferences.state.value.fontSize,
    color: controller.preferences.textColor ?? Theme.of(Get.context!).colorScheme.onSurface,
  );

  bool _useOverlayBottomStatusBar() {
    final settings = controller.preferences.state.value;
    return settings.showStatusBar && settings.direction == ReaderDirection.upToDown;
  }

  bool _useInPageBottomStatusBar() {
    final settings = controller.preferences.state.value;
    return settings.showStatusBar && settings.direction != ReaderDirection.upToDown;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Obx(
            () => controller.pageState.value == PageState.success
                ? ReaderBackground(
                    child: Obx(
                      () => Padding(
                        padding: EdgeInsets.only(bottom: _useOverlayBottomStatusBar() ? kStatusBarPadding + MediaQuery.of(context).padding.bottom : 0),
                        child: _buildReadPage(context),
                      ),
                    ),
                  )
                : Container(),
          ),
          Obx(() => Offstage(offstage: controller.pageState.value != PageState.loading, child: const LoadingPage())),
          Obx(
            () => Offstage(
              offstage: controller.pageState.value != PageState.error,
              child: ErrorMessage(msg: controller.errorMsg, action: controller.getContent),
            ),
          ),
          ReaderStatusBar(controller: controller),
          const TtsFloatingController(),
          Obx(() {
            //顶栏
            double statusBarHeight = MediaQuery.of(context).padding.top;
            return AnimatedPositioned(
              top: controller.showBar.value ? 0 : -(kToolbarHeight + statusBarHeight),
              left: 0,
              right: 0,
              duration: Duration(milliseconds: 100),
              child: AppBar(backgroundColor: Theme.of(context).colorScheme.secondaryContainer, title: Text(controller.chapterTitle.value), titleSpacing: 0),
            );
          }),
          ReaderBottomBar(controller: controller, verticalReadPageKey: _verticalReadPageKey),
        ],
      ),
    );
  }

  Widget _buildReadPage(BuildContext context) {
    return Obx(() {
      if (controller.pageState.value != PageState.success) return Container();
      if (controller.preferences.state.value.direction == ReaderDirection.upToDown) {
        return VerticalReader(
          controller: controller,
          verticalReadPageKey: _verticalReadPageKey,
          padding: _contentPadding(context, inPageStatusBar: false),
          style: textStyle,
        );
      }
      return HorizontalReader(
        controller: controller,
        padding: _contentPadding(context, inPageStatusBar: _useInPageBottomStatusBar()),
        style: textStyle,
        footer: _useInPageBottomStatusBar() ? ReaderStatusBar(controller: controller, inPage: true) : null,
      );
    });
  }
}
