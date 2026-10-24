import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hikari_novel_flutter/models/common/language.dart';
import 'package:hikari_novel_flutter/models/common/wenku8_node.dart';

import '../../service/local_storage_service.dart';

class SettingController extends GetxController {
  RxBool isAutoCheckUpdate = LocalStorageService.instance.isAutoCheckUpdate.value.obs;
  Rx<Language> language = Rx(LocalStorageService.instance.language.value);
  RxBool isRelativeTime = LocalStorageService.instance.isRelativeTime.value.obs;
  Rx<Wenku8Node> wenku8Node = Rx(LocalStorageService.instance.wenku8Node.value);
  Rx<ThemeMode> themeMode = Rx(LocalStorageService.instance.themeMode.value);
  RxBool isDynamicColor = LocalStorageService.instance.isDynamicColor.value.obs;
  Rx<Color> customColor = Rx(LocalStorageService.instance.customColor.value);

  void changeIsAutoCheckUpdate(bool enabled) {
    isAutoCheckUpdate.value = enabled;
    LocalStorageService.instance.isAutoCheckUpdate.value = enabled;
  }

  void changeIsRelativeTime(bool enabled) {
    isRelativeTime.value = enabled;
    LocalStorageService.instance.isRelativeTime.value = enabled;
  }

  void changeLanguage(Language l) async {
    switch (l) {
      case Language.simplifiedChinese:
        Get.updateLocale(Locale("zh", "CN"));
      case Language.traditionalChinese:
        Get.updateLocale(Locale("zh", "TW"));
      case Language.followSystem:
        {
          if (Get.deviceLocale! != Locale("zh", "CN") && Get.deviceLocale! != Locale("zh", "CN")) {
            Get.updateLocale(Locale("zh", "CN"));
          } else {
            Get.updateLocale(Get.deviceLocale!);
          }
        }
    }
    language.value = l;
    LocalStorageService.instance.language.value = l;
  }

  void changeWenku8Node(Wenku8Node n) {
    wenku8Node.value = n;
    LocalStorageService.instance.wenku8Node.value = n;
  }

  void changeCustomColor(Color color) {
    customColor.value = color;
    LocalStorageService.instance.customColor.value = color;
    Get.forceAppUpdate();
  }

  void changeIsDynamicColor(bool enabled) {
    isDynamicColor.value = enabled;
    LocalStorageService.instance.isDynamicColor.value = enabled;
    Get.forceAppUpdate();
  }

  void changeThemeMode(ThemeMode mode) {
    themeMode.value = mode;
    LocalStorageService.instance.themeMode.value = mode;
    Get.forceAppUpdate();
  }
}
