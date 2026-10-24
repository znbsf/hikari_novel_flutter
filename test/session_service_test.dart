import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:hikari_novel_flutter/service/api_service.dart';
import 'package:hikari_novel_flutter/pages/user_info/controller.dart';
import 'package:hikari_novel_flutter/models/resource.dart';
import 'package:hikari_novel_flutter/models/page_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hikari_novel_flutter/service/account_session_service.dart';
import 'package:hikari_novel_flutter/service/session_service.dart';
import 'package:hikari_novel_flutter/service/local_storage_service.dart';
import 'package:hive_ce/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('retry cannot let an old login callback adopt the new generation', () async {
    final session = SessionCoordinator();
    final gate = LoginAttemptGate(session);
    gate.adopt(session.generation);
    final oldToken = gate.generation;
    expect(gate.beginSave(oldToken), true);
    final response = Completer<void>();
    var writes = 0;
    final oldCallback = (() async {
      await response.future;
      if (gate.owns(oldToken)) writes++;
      gate.finishSave(oldToken);
    })();
    session.invalidate();
    gate.adopt(session.generation);
    session.release();
    final newToken = gate.generation;
    expect(gate.beginSave(newToken), true);
    response.complete();
    await oldCallback;
    expect(writes, 0);
    expect(gate.beginSave(newToken), false, reason: 'Old finally must not unlock the new login');
    gate.finishSave(newToken);
    expect(gate.beginSave(newToken), true);
  });
  test('user fetch errors produce retryable error state', () async {
    final controller = UserInfoController(fetchUser: () async => throw StateError('transport'), session: SessionCoordinator());
    await controller.getPage();
    expect(controller.pageState.value, PageState.error);
    expect(controller.errorMsg, isNotEmpty);
  });
  test('late user response cannot restore identity after invalidation', () async {
    final session = SessionCoordinator();
    final response = Completer<Resource>();
    final controller = UserInfoController(fetchUser: () => response.future, session: session);
    final pending = controller.getPage();
    session.invalidate();
    response.complete(Success('malformed response must never be parsed'));
    await pending;
    expect(controller.userInfo.value, isNull);
  });
  test('late set-cookie stays in retired jar after logout', () async {
    final api = ApiService();
    final adapter = _CookieAdapter();
    api.dio.httpClientAdapter = adapter;
    final old = api.dio.get('https://www.wenku8.cc/old');
    await adapter.started.future;
    await api.deleteCookie();
    adapter.response.complete(
      ResponseBody.fromString(
        'ok',
        200,
        headers: {
          'set-cookie': ['jieqiUserInfo=retired; Path=/'],
        },
      ),
    );
    await old;
    await api.dio.get('https://www.wenku8.cc/new');
    expect(adapter.lastCookie, isNull);
  });
  test('invalidation rejects old work and queue recovers after failed commit', () async {
    final session = SessionCoordinator();
    final old = session.generation;
    session.invalidate();
    expect(session.isCurrent(old), false);
    session.release();
    expect(session.isCurrent(old), false);
    await expectLater(session.serialize(() async => throw StateError('failed')), throwsStateError);
    expect(await session.serialize(() async => 42), 42);
  });
  test('cleanup blocks immediately, waits for commits and attempts all backends', () async {
    final session = SessionCoordinator();
    final barrier = Completer<void>();
    final active = session.serialize(() => barrier.future);
    final calls = <String>[];
    var fail = true;
    final cleanup = AccountSessionService(
      coordinator: session,
      clearJar: () async {
        calls.add('jar');
      },
      clearCookie: () async {
        calls.add('cookie');
        if (fail) throw StateError('disk');
      },
      clearUser: () async {
        calls.add('user');
      },
      clearWeb: () async {
        calls.add('web');
      },
      clearShelf: () async {
        calls.add('shelf');
      },
    );
    final first = cleanup.clear();
    final assertion = expectLater(first, throwsStateError);
    expect(session.blocked, true);
    barrier.complete();
    await active;
    await assertion;
    expect(calls, ['jar', 'cookie', 'user', 'web', 'shelf']);
    fail = false;
    await cleanup.clear();
    expect(session.blocked, true);
  });
  test('awaited cleanup persists logout while preserving unrelated preferences', () async {
    final dir = await Directory.systemTemp.createTemp('hikari-session-');
    try {
      final storage = LocalStorageService();
      await storage.init(hivePath: dir.path);
      await storage.cookie.write('synthetic=test');
      await storage.readerFontSize.write(27);
      final cleanup = AccountSessionService(
        coordinator: SessionCoordinator(),
        clearCookie: () => storage.cookie.write(null),
        clearUser: () => storage.userInfo.write(null),
        clearJar: () async {},
        clearWeb: () async {},
        clearShelf: () async {},
      );
      await cleanup.clear();
      await Hive.close();
      Hive.resetAdapters();
      final reopened = LocalStorageService();
      await reopened.init(hivePath: dir.path);
      expect(reopened.cookie.value, isNull);
      expect(reopened.userInfo.value, isNull);
      expect(reopened.readerFontSize.value, 27);
    } finally {
      await Hive.close();
      Hive.resetAdapters();
      await dir.delete(recursive: true);
    }
  });
}

class _CookieAdapter implements HttpClientAdapter {
  final started = Completer<void>();
  final response = Completer<ResponseBody>();
  String? lastCookie;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    if (options.path.endsWith('/old')) {
      started.complete();
      return response.future;
    }
    lastCookie = options.headers['cookie'] as String?;
    return ResponseBody.fromString('ok', 200);
  }

  @override
  void close({bool force = false}) {}
}
