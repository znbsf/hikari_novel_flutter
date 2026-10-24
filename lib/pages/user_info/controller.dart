import 'package:get/get.dart';
import 'package:hikari_novel_flutter/models/resource.dart';
import 'package:hikari_novel_flutter/models/user_info.dart';
import 'package:hikari_novel_flutter/parser/parser.dart';

import '../../models/page_state.dart';
import '../../service/api_service.dart';
import '../../service/local_storage_service.dart';
import '../../service/session_service.dart';

class UserInfoController extends GetxController {
  UserInfoController({Future<Resource> Function()? fetchUser, SessionCoordinator? session})
    : _fetchUser = fetchUser ?? (() => ApiService.instance.getUserInfo()),
      _session = session ?? SessionCoordinator.instance;
  final Future<Resource> Function() _fetchUser;
  final SessionCoordinator _session;
  Rx<PageState> pageState = Rx(PageState.loading);
  String errorMsg = "";
  Rxn<UserInfo> userInfo = Rxn();

  @override
  void onReady() {
    super.onReady();

    userInfo.value = LocalStorageService.instance.userInfo.value;
    pageState.value = PageState.success;
  }

  Future<void> getPage() async {
    final token = _session.generation;
    if (!_session.isCurrent(token) || isClosed) return;
    try {
      final data = await _fetchUser();
      if (!_session.isCurrent(token) || isClosed) return;
      switch (data) {
        case Success():
          {
            final user = Parser.getUserInfo(data.data);
            await _session.serialize(() async {
              if (!_session.isCurrent(token) || isClosed) return;
              await LocalStorageService.instance.userInfo.write(user);
              if (!_session.isCurrent(token) || isClosed) return;
              userInfo.value = user;
              pageState.value = PageState.success;
            });
          }
        case Error():
          {
            errorMsg = data.error;
            pageState.value = PageState.error;
          }
      }
    } catch (_) {
      if (!_session.isCurrent(token) || isClosed) return;
      errorMsg = '用户资料加载失败，请重试';
      pageState.value = PageState.error;
    }
  }
}
