import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hikari_novel_flutter/common/database/database.dart';
import 'package:hikari_novel_flutter/models/novel_detail.dart';
import 'package:hikari_novel_flutter/pages/novel_detail/controller.dart';
import 'package:hikari_novel_flutter/pages/novel_detail/view.dart';
import 'package:hikari_novel_flutter/service/session_service.dart';

class _DetailController extends NovelDetailController {
  _DetailController(String aid, void Function() requested)
    : super(
        aid: aid,
        session: SessionCoordinator(),
        fetchDetail: (_) async {
          requested();
          throw StateError('Controlled offline response');
        },
        readCache: (_) async => null,
        saveDetail: (_, _) async {},
        checkShelf: (_) async => false,
      );

  int closeCount = 0;

  @override
  void onClose() {
    closeCount++;
    super.onClose();
  }
}

class _SuccessfulDetailController extends NovelDetailController {
  _SuccessfulDetailController(String aid, Future<NovelDetail> Function(String) fetch) : super(aid: aid, session: SessionCoordinator(), fetchDetail: fetch);

  int closeCount = 0;

  @override
  void onClose() {
    closeCount++;
    super.onClose();
  }
}

// Hidden loading pages intentionally keep their progress ticker alive. Pump
// enough bounded frames for navigation and async completions without settling.
Future<void> pumpRoute(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

void main() {
  tearDown(Get.reset);

  for (final secondAid in ['2', '1']) {
    testWidgets('nested detail routes retain independent lifetimes (second aid $secondAid)', (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      final controllers = <_DetailController>[];
      final requests = <int>[];
      NovelDetailController createController(String aid) {
        final index = controllers.length;
        requests.add(0);
        final controller = _DetailController(aid, () => requests[index]++);
        controllers.add(controller);
        return controller;
      }

      await tester.pumpWidget(
        GetMaterialApp(
          home: Navigator(
            key: navigatorKey,
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              settings: const RouteSettings(name: '/novel-detail'),
              builder: (_) => NovelDetailPage(aid: '1', controllerFactory: createController),
            ),
          ),
        ),
      );
      await pumpRoute(tester);
      final first = controllers.single;
      expect(requests, [1]);
      expect(first.isClosed, false);

      // This is the author's search route above A in the nested navigator.
      navigatorKey.currentState!.push<void>(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/search'),
          builder: (_) => const Scaffold(body: Text('Author search')),
        ),
      );
      await pumpRoute(tester);
      first.enterSelectionMode();
      expect(NovelDetailPage.exitCurrentSelectionMode(), false);
      expect(first.isSelectionMode.value, true);

      navigatorKey.currentState!.push<void>(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/novel-detail'),
          builder: (_) => NovelDetailPage(aid: secondAid, controllerFactory: createController),
        ),
      );
      await pumpRoute(tester);
      final second = controllers.last;
      expect(identical(first, second), false);
      expect(first.isClosed, false);
      expect(first.closeCount, 0);
      expect(requests, [1, 1]);
      second.enterSelectionMode();
      expect(NovelDetailPage.exitCurrentSelectionMode(), true);
      expect(second.isSelectionMode.value, false);
      expect(first.isSelectionMode.value, true);

      navigatorKey.currentState!.pop();
      await pumpRoute(tester);
      expect(second.isClosed, true);
      expect(second.closeCount, 1);
      expect(first.isClosed, false);
      expect(NovelDetailPage.exitCurrentSelectionMode(), false);
      navigatorKey.currentState!.pop();
      await pumpRoute(tester);
      expect(NovelDetailPage.exitCurrentSelectionMode(), true);
      expect(first.isSelectionMode.value, false);

      // A is the original mounted page again: refresh must still fetch, and
      // scrolling's animation commands must still use a live ticker.
      final beforeRefresh = requests.first;
      await first.getNovelDetail();
      expect(requests.first, beforeRefresh + 1);
      first.hideFab();
      await pumpRoute(tester);
      first.showFab();
      await pumpRoute(tester);
      expect(tester.takeException(), isNull);
      expect(first.closeCount, 0);

      await tester.pumpWidget(const SizedBox.shrink());
      await pumpRoute(tester);
      expect(first.isClosed, true);
      expect(first.closeCount, 1);
      expect(second.closeCount, 1);
      expect(NovelDetailPage.exitCurrentSelectionMode(), false);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('successful nested details keep local GetBuilders and persist refresh after returning', (tester) async {
    final database = Get.put(AppDatabase.forTesting(NativeDatabase.memory()));
    final navigatorKey = GlobalKey<NavigatorState>();
    final controllers = <_SuccessfulDetailController>[];
    final requests = <int>[];
    NovelDetailController createController(String aid) {
      final index = controllers.length;
      requests.add(0);
      final controller = _SuccessfulDetailController(aid, (_) async {
        requests[index]++;
        return NovelDetail('Detail $aid revision ${requests[index]}', 'Author', 'Complete', '2026-10-25', '', 'Fixture synopsis', [], '1', '1', false);
      });
      controllers.add(controller);
      return controller;
    }

    Finder builders() => find.byWidgetPredicate((widget) => widget is GetBuilder<NovelDetailController>, skipOffstage: false);

    try {
      await tester.pumpWidget(
        GetMaterialApp(
          home: Navigator(
            key: navigatorKey,
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              settings: const RouteSettings(name: '/novel-detail'),
              builder: (_) => NovelDetailPage(aid: '1', controllerFactory: createController),
            ),
          ),
        ),
      );
      await pumpRoute(tester);
      final first = controllers.single;
      // Await the real in-memory write before observing the published page.
      await first.getNovelDetail();
      await pumpRoute(tester);
      expect(builders(), findsOneWidget);
      final firstBuilder = tester.widget<GetBuilder<NovelDetailController>>(builders());
      expect(firstBuilder.init, same(first));
      expect(firstBuilder.global, false);
      expect(firstBuilder.autoRemove, false);
      expect((await database.getNovelDetail('1'))!.json, contains(first.novelDetail.value!.title));

      navigatorKey.currentState!.push<void>(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/search'),
          builder: (_) => const Scaffold(body: Text('Author search')),
        ),
      );
      await pumpRoute(tester);
      navigatorKey.currentState!.push<void>(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/novel-detail'),
          builder: (_) => NovelDetailPage(aid: '2', controllerFactory: createController),
        ),
      );
      await pumpRoute(tester);
      final second = controllers.last;
      await second.getNovelDetail();
      await pumpRoute(tester);
      expect(builders(), findsNWidgets(2));
      expect(tester.widgetList<GetBuilder<NovelDetailController>>(builders()).map((widget) => widget.init), containsAll([first, second]));
      expect(first.isClosed, false);
      expect((await database.getNovelDetail('2'))!.json, contains(second.novelDetail.value!.title));

      // Exercise the actual local GetBuilder subscription while A is covered.
      first.isChapterOrderReversed.value = true;
      first.update(['customScrollView']);
      await pumpRoute(tester);
      expect(second.isChapterOrderReversed.value, false);
      navigatorKey.currentState!.pop();
      await pumpRoute(tester);
      expect(second.closeCount, 1);
      expect(first.closeCount, 0);
      navigatorKey.currentState!.pop();
      await pumpRoute(tester);
      expect(builders(), findsOneWidget);
      expect(tester.widget<GetBuilder<NovelDetailController>>(builders()).init, same(first));

      final beforeRefresh = requests.first;
      await first.getNovelDetail();
      await pumpRoute(tester);
      expect(requests.first, beforeRefresh + 1);
      expect((await database.getNovelDetail('1'))!.json, contains('Detail 1 revision ${requests.first}'));
      expect(find.text(first.novelDetail.value!.title), findsWidgets);
      first.hideFab();
      await pumpRoute(tester);
      first.showFab();
      await pumpRoute(tester);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpRoute(tester);
      await database.close();
    }
    expect(controllers.map((controller) => controller.closeCount), [1, 1]);
    expect(tester.takeException(), isNull);
  });
}
