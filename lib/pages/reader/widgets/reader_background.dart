import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controller.dart';

class ReaderBackground extends StatelessWidget {
  final Widget child;

  final ReaderController controller = Get.find();

  ReaderBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      Decoration decoration;

      final bgImage = controller.preferences.bgImagePath;
      final bgImageFile = bgImage == null || bgImage.isEmpty ? null : File(bgImage);
      if (bgImageFile != null && bgImageFile.existsSync()) {
        decoration = BoxDecoration(
          image: DecorationImage(image: FileImage(bgImageFile), fit: BoxFit.cover),
        );
      } else {
        decoration = BoxDecoration(color: controller.preferences.bgColor ?? Theme.of(context).colorScheme.surface);
      }

      return Container(decoration: decoration, child: child);
    });
  }
}
