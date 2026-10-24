import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'state_page.dart';

Future<void> showMessageDialog({required String title, required String content, Widget? icon}) async {
  await Get.dialog<void>(
    AlertDialog(
      icon: icon,
      title: Text(title),
      content: Text(content),
      actions: [TextButton(onPressed: Get.back, child: Text("confirm".tr))],
    ),
  );
}

Future<bool> showConfirmDialog({required String title, required String content, Widget? icon, VoidCallback? onConfirm}) async {
  return await Get.dialog<bool>(
        AlertDialog(
          icon: icon,
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(onPressed: Get.back, child: Text("cancel".tr)),
            TextButton(
              onPressed: () {
                onConfirm?.call();
                Get.back(result: true);
              },
              child: Text("confirm".tr),
            ),
          ],
        ),
      ) ??
      false;
}

Future showErrorDialog(String msg, List<Widget> actions) {
  late Widget content;
  if (isSpecificMessage(msg)) {
    content = buildCommonErrorInfoView(msg);
  } else {
    content = SingleChildScrollView(child: Text(msg));
  }

  return Get.dialog(AlertDialog(title: Text("error".tr), content: content, actions: actions));
}

// 参考 https://pub.dev/packages/floating_snackbar
void showSnackBar({
  required String message, // 提示内容
  required BuildContext context, // 显示提示的上下文
  Duration? duration, // 可选显示时长
  TextStyle? textStyle, // 可选文字样式
}) {
  // 创建提示
  var snack = SnackBar(
    margin: const EdgeInsets.symmetric(vertical: 20, horizontal: 10), // 提示外边距
    duration: duration ?? const Duration(milliseconds: 4000), // 默认显示时长
    content: Text(
      message, // 提示文字
      style: textStyle ?? TextStyle(), // 应用文字样式
    ),
  );

  // 隐藏当前提示
  ScaffoldMessenger.of(context).hideCurrentSnackBar();

  // 显示新提示
  ScaffoldMessenger.of(context).showSnackBar(snack);
}
