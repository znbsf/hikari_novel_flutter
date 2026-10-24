import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hikari_novel_flutter/models/user_info.dart';
import 'package:hikari_novel_flutter/router/route_path.dart';

import '../../service/local_storage_service.dart';
import '../../service/account_session_service.dart';

class MyController extends GetxController {
  Rxn<UserInfo> userInfo = Rxn(LocalStorageService.instance.userInfo.value);

  final usernameController = TextEditingController();
  final passwordController = TextEditingController();

  final loggingOut = false.obs;
  Future<void> logout() async {
    if (loggingOut.value) return;
    loggingOut.value = true;
    userInfo.value = null;
    try {
      await AccountSessionService.production().clear();
      userInfo.value = null;
      Get.offAllNamed(RoutePath.welcome);
    } catch (_) {
      Get.snackbar('logout'.tr, '退出未完成，请重试');
    } finally {
      loggingOut.value = false;
    }
  }

  @override
  void onClose() {
    usernameController.dispose();
    passwordController.dispose();
    super.onClose();
  }
}
