import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../main.dart';
import '../common/database/database.dart';
import '../models/common/wenku8_node.dart';
import 'api_service.dart';
import 'local_storage_service.dart';
import 'session_service.dart';

Future<void> clearSiteCookies() async {
  final manager = CookieManager.instance(webViewEnvironment: webViewEnvironment);
  for (final node in Wenku8Node.values) {
    final uri = WebUri(node.node);
    final root = uri.host.replaceFirst('www.', '');
    for (final domain in [uri.host, root, '.$root']) {
      await manager.deleteCookies(url: uri, domain: domain);
    }
    for (final host in [uri.host, root]) {
      final remaining = await manager.getCookies(url: WebUri('https://$host'));
      if (remaining.any((cookie) => cookie.name == 'jieqiUserInfo' || cookie.name == 'jieqiVisitInfo')) {
        throw StateError('Could not clear site login cookies');
      }
    }
  }
}

/// Tries every cleanup even when one backend fails, and leaves the session blocked.
class AccountSessionService {
  AccountSessionService({
    required this.clearCookie,
    required this.clearUser,
    required this.clearJar,
    required this.clearWeb,
    required this.clearShelf,
    SessionCoordinator? coordinator,
  }) : coordinator = coordinator ?? SessionCoordinator.instance;
  factory AccountSessionService.production() => AccountSessionService(
    clearCookie: () => LocalStorageService.instance.cookie.write(null),
    clearUser: () => LocalStorageService.instance.userInfo.write(null),
    clearJar: () => ApiService.instance.deleteCookie(),
    clearWeb: clearSiteCookies,
    clearShelf: () async {
      await AppDatabase.instance.deleteAllBookshelf();
    },
  );
  final Future<void> Function() clearCookie, clearUser, clearJar, clearWeb, clearShelf;
  final SessionCoordinator coordinator;
  Future<void> clear() {
    coordinator.invalidate();
    return coordinator.serialize(() async {
      var failed = false;
      for (final action in [clearJar, clearCookie, clearUser, clearWeb, clearShelf]) {
        try {
          await action();
        } catch (_) {
          failed = true;
        }
      }
      if (failed) throw StateError('Session cleanup failed; please retry');
    });
  }
}
