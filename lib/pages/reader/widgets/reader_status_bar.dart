import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../common/constants.dart';
import '../../../models/reader_direction.dart';
import '../../../models/page_state.dart';
import '../controller.dart';

class ReaderStatusBar extends StatelessWidget {
  const ReaderStatusBar({super.key, required this.controller, this.inPage = false});

  final ReaderController controller;
  final bool inPage;

  bool _useOverlayBottomStatusBar() {
    final settings = controller.preferences.state.value;
    return settings.showStatusBar && settings.direction == ReaderDirection.upToDown;
  }

  @override
  Widget build(BuildContext context) => inPage ? _buildInPageStatusBar(context) : _buildBottomStatusBar(context);

  Widget _buildBottomStatusBar(BuildContext context) {
    final spacing = controller.preferences.state.value.readerBottomStatusBarHorizontalSpacing.toDouble();
    return Positioned(
      right: 8,
      left: 8,
      bottom: 4,
      child: Obx(
        () => Offstage(
          offstage: !(_useOverlayBottomStatusBar() && controller.pageState.value == PageState.success),
          child: Padding(padding: EdgeInsets.fromLTRB(spacing, 0, spacing, MediaQuery.of(context).padding.bottom), child: _buildStatusBarContent(context)),
        ),
      ),
    );
  }

  Widget _buildInPageStatusBar(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final spacing = controller.preferences.state.value.readerBottomStatusBarHorizontalSpacing.toDouble();
    return SizedBox(
      width: double.infinity,
      height: kStatusBarPadding.toDouble() + bottomInset,
      child: Padding(padding: EdgeInsets.fromLTRB(spacing, 0, spacing, bottomInset), child: _buildStatusBarContent(context)),
    );
  }

  Widget _buildStatusBarContent(BuildContext context) {
    return Obx(() {
      final textColor = controller.preferences.textColor ?? Theme.of(context).colorScheme.onSurface;
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(DateFormat('HH:mm').format(controller.platform.currentTime.value), style: TextStyle(fontSize: 13, color: textColor)),
          const SizedBox(width: 8),
          IconTheme(
            data: IconThemeData(color: textColor),
            child: _buildBattery(context, controller.platform.batteryLevel.value),
          ),
          Text("${controller.platform.batteryLevel.value}%", style: TextStyle(fontSize: 13, color: textColor)),
          const Spacer(),
          controller.preferences.state.value.direction == ReaderDirection.upToDown
              ? Text("${controller.verticalProgress.value} %", style: TextStyle(fontSize: 13, color: textColor))
              : Text("${controller.currentIndex.value + 1} / ${controller.maxPage.value}", style: TextStyle(fontSize: 13, color: textColor)),
        ],
      );
    });
  }

  Widget _buildBattery(BuildContext context, int value) {
    if (value >= 95) {
      return const Icon(Icons.battery_full, size: kSmallIconSize);
    } else if (value >= 85) {
      return const Icon(Icons.battery_6_bar, size: kSmallIconSize); // ~90%
    } else if (value >= 65) {
      return const Icon(Icons.battery_5_bar, size: kSmallIconSize); // ~80%
    } else if (value >= 45) {
      return const Icon(Icons.battery_4_bar, size: kSmallIconSize); // ~60%
    } else if (value >= 35) {
      return const Icon(Icons.battery_3_bar, size: kSmallIconSize); // ~50%
    } else if (value >= 25) {
      return const Icon(Icons.battery_2_bar, size: kSmallIconSize); // ~30%
    } else if (value >= 15) {
      return const Icon(Icons.battery_1_bar, size: kSmallIconSize); // ~20%
    } else {
      return const Icon(Icons.battery_0_bar, size: kSmallIconSize); // <15%
    }
  }
}
