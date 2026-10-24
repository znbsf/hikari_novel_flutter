import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:hikari_novel_flutter/common/constants.dart';
import 'package:hikari_novel_flutter/main.dart';
import 'package:hikari_novel_flutter/models/common/wenku8_node.dart';
import 'package:hikari_novel_flutter/models/page_state.dart';
import 'package:hikari_novel_flutter/router/route_path.dart';
import 'package:hikari_novel_flutter/service/api_service.dart';

import '../../service/account_session_service.dart';
import '../../service/session_service.dart';
import '../../service/bookshelf_sync_service.dart';
import '../../models/resource.dart';
import '../../parser/parser.dart';
import '../../service/local_storage_service.dart';

class LoginController extends GetxController {
  RxBool showLoading = true.obs;
  RxInt loadingProgress = 0.obs;
  final CookieManager cookieManager = CookieManager.instance(webViewEnvironment: webViewEnvironment);
  InAppWebViewController? inAppWebViewController;
  GlobalKey webViewKey = GlobalKey();
  final InAppWebViewSettings settings = InAppWebViewSettings(isInspectable: kDebugMode, userAgent: kUserAgent["User-Agent"], javaScriptEnabled: true);
  RxString currentUrl = "".obs;

  Rx<PageState> pageState = PageState.success.obs;
  String errorMsg = "";

  String get url => "${ApiService.instance.wenku8Node.node}/login.php";

  final ready = false.obs;
  bool _completed = false;
  late final _attempt = LoginAttemptGate(_session);
  Object? _preparation;
  final _session = SessionCoordinator.instance;

  @override
  void onInit() {
    super.onInit();
    prepare();
  }

  Future<void> prepare() async {
    ready.value = false;
    webViewKey = GlobalKey();
    inAppWebViewController = null;
    pageState.value = PageState.success;
    final preparation = Object();
    _preparation = preparation;
    try {
      final cleanup = AccountSessionService.production().clear();
      final token = _session.generation;
      _attempt.adopt(token);
      await cleanup;
      if (isClosed || !identical(_preparation, preparation) || token != _session.generation) return;
      _session.release();
      ready.value = true;
    } catch (_) {
      if (isClosed || !identical(_preparation, preparation) || _attempt.generation != _session.generation) return;
      errorMsg = '登录初始化失败，请重试';
      pageState.value = PageState.error;
    }
  }

  bool get canUseWebView => ready.value && _current;

  bool get _current => !isClosed && _attempt.owns(_attempt.generation);

  Future<void> saveCookie(WebUri uri) async {
    showLoading.value = false;
    if (!ready.value || !_current) return;
    final token = _attempt.generation;
    bool current() => !isClosed && _attempt.owns(token);
    final host = uri.host;
    if (host != 'wenku8.net' && host != 'wenku8.cc' && host != 'www.wenku8.net' && host != 'www.wenku8.cc') return;
    if (!_attempt.beginSave(token)) return;
    try {
      final cookies = await cookieManager.getCookies(url: uri);
      if (!current()) return;
      if (!['jieqiUserInfo', 'jieqiVisitInfo'].every((name) => cookies.any((cookie) => cookie.name == name))) return;
      final cookie = ['jieqiUserInfo', 'jieqiVisitInfo'].map((name) => '$name=${cookies.firstWhere((c) => c.name == name).value}').join(';');
      await _session.serialize(() async {
        if (!current()) throw const SessionChanged();
        await LocalStorageService.instance.cookie.write(cookie);
        if (!current()) throw const SessionChanged();
        await ApiService.instance.initCookie();
      });
      if (!current()) return;
      final result = await ApiService.instance.getUserInfo();
      if (!current()) return;
      switch (result) {
        case Success():
          final user = Parser.getUserInfo(result.data);
          await _session.serialize(() async {
            if (!current()) throw const SessionChanged();
            await LocalStorageService.instance.userInfo.write(user);
          });
        case Error():
          throw StateError('Login verification failed');
      }
      if (!current()) return;
      await BookshelfSyncService.instance.refreshAll();
      if (!current()) return;
      _completed = true;
      Get.offAllNamed(RoutePath.main);
    } catch (_) {
      if (!current()) return;
      final cleanup = AccountSessionService.production().clear();
      final cleanupToken = _session.generation;
      _attempt.adopt(cleanupToken);
      try {
        await cleanup;
      } catch (_) {}
      if (isClosed || _attempt.generation != cleanupToken || _session.generation != cleanupToken) return;
      ready.value = false;
      errorMsg = '登录未完成，请重试';
      pageState.value = PageState.error;
    } finally {
      _attempt.finishSave(token);
    }
  }

  @override
  void onClose() {
    if (!_completed && _attempt.generation == _session.generation) {
      AccountSessionService.production().clear().catchError((Object _) {});
    }
    super.onClose();
  }
}
