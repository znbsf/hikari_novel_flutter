import 'dart:async';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' show Get, Inst, GetResetExt;
import 'package:hikari_novel_flutter/common/database/database.dart';
import 'package:hikari_novel_flutter/models/cat_chapter.dart';
import 'package:hikari_novel_flutter/models/cat_volume.dart';
import 'package:hikari_novel_flutter/models/content.dart';
import 'package:hikari_novel_flutter/models/page_state.dart';
import 'package:hikari_novel_flutter/models/reader_direction.dart';
import 'package:hikari_novel_flutter/pages/reader/controller.dart';
import 'package:hikari_novel_flutter/pages/reader/reader_platform.dart';
import 'package:hikari_novel_flutter/pages/reader/reader_settings.dart';
import 'package:hikari_novel_flutter/service/local_storage_service.dart';
import 'package:hive_ce/hive.dart';

class _Platform extends ReaderPlatform {
  _Platform(LocalStorageService storage) : super(settings: () => ReaderSettings.load(storage), prevPage: () {}, nextPage: () {});
  int closes = 0;
  @override
  void onInit() {}
  @override
  void onReady() {}
  @override
  void onClose() {
    closes++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late LocalStorageService storage;
  final controllers = <ReaderController>[];
  final catalogue = [
    CatVolume(
      title: 'volume',
      chapters: [
        CatChapter(title: 'A title', cid: 'A'),
        CatChapter(title: 'B title', cid: 'B'),
      ],
    ),
  ];

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('hikari-reader-lifecycle-');
    storage = Get.put(LocalStorageService());
    await storage.init(hivePath: directory.path);
    // Horizontal cases must not depend on the application's default scroll mode.
    storage.readerDirection.value = ReaderDirection.leftToRight;
    await Hive.box('reader').flush();
  });
  tearDown(() async {
    for (final controller in controllers) {
      controller.onClose();
      await controller.historySettled;
    }
    controllers.clear();
    Get.reset();
    await Hive.close();
    Hive.resetAdapters();
    directory.deleteSync(recursive: true);
  });

  ReaderController create({ReaderArgs? args, Future<Content> Function(String aid, String cid)? read, ReaderHistoryWriter? write, ReaderPlatform? platform}) {
    final controller = ReaderController(
      args ?? ReaderArgs('book', catalogue, 'A', 0),
      readChapter: read ?? (_, cid) async => Content(text: cid, images: []),
      writeHistory: write ?? (_) async {},
      platform: platform ?? _Platform(storage),
    );
    controllers.add(controller);
    // Run the same initialization hook Get.put invokes in the reader page.
    controller.onInit();
    return controller;
  }

  test('late A response cannot overwrite B, including title and images', () async {
    final a = Completer<Content>();
    final b = Completer<Content>();
    final controller = create(read: (_, cid) => cid == 'A' ? a.future : b.future);
    final first = controller.getContent();
    controller.selectChapter(0, 1);
    b.complete(Content(text: 'B text', images: ['B image']));
    await Future<void>.delayed(Duration.zero);
    a.complete(Content(text: 'A text', images: ['A image']));
    await first;
    expect(controller.text.value, 'B text');
    expect(controller.chapterTitle.value, 'B title');
    expect(controller.images, ['B image']);
    expect(controller.pageState.value, PageState.success);
  });

  test('late load failure cannot replace a newer success', () async {
    final a = Completer<Content>();
    final controller = create(
      read: (_, cid) => cid == 'A' ? a.future : Future.value(Content(text: cid, images: [])),
    );
    final first = controller.getContent();
    controller.selectChapter(0, 1);
    await Future<void>.delayed(Duration.zero);
    a.completeError(StateError('stale failure'));
    await first;
    expect(controller.pageState.value, PageState.success);
    expect(controller.text.value, 'B');
  });

  test('closing after content load before layout preserves existing history and initial position', () async {
    final written = <ReadHistoryEntityData>[];
    final controller = create(
      args: ReaderArgs('book', catalogue, 'A', 73),
      write: (snapshot) async {
        written.add(snapshot);
      },
    );
    await controller.getContent();
    expect(controller.pageState.value, PageState.success);
    expect(controller.currentIndex.value, 73);
    expect(controller.initialHorizontalIndex, 73);
    controller.onClose();
    await controller.historySettled;
    await Future<void>.delayed(const Duration(milliseconds: 180));
    expect(written, isEmpty);
  });

  test('mode changes preserve the event snapshot and reject callbacks from obsolete layouts', () async {
    final written = <ReadHistoryEntityData>[];
    final controller = create(
      write: (snapshot) async {
        written.add(snapshot);
      },
    );
    await controller.getContent();
    final horizontal = controller.progressIdentity;
    controller.updateHorizontalProgress(horizontal, 3, 10);
    ReaderFields.direction.setIn(controller.preferences, ReaderDirection.upToDown);
    controller.updateHorizontalProgress(horizontal, 9, 10);
    await controller.setReadHistory();
    expect(written.single.readerMode, 2);
    expect(written.single.location, 3);
    expect(written.single.progress, 40);
    expect(controller.currentIndex.value, 3);

    final vertical = controller.progressIdentity;
    controller.updateVerticalProgress(vertical, 420, 1000);
    ReaderFields.direction.setIn(controller.preferences, ReaderDirection.leftToRight);
    // Returning to the original direction must not revalidate its old callback.
    controller.updateHorizontalProgress(horizontal, 8, 10);
    controller.autoDualPage = true;
    controller.updateVerticalProgress(vertical, 900, 1000);
    controller.onClose();
    await controller.historySettled;
    expect(written.last.readerMode, 1);
    expect(written.last.location, 420);
    expect(written.last.progress, 42);
    expect(written.last.isDualPage, isFalse);
    expect(controller.currentIndex.value, 3);
  });

  test('chapter switch flushes A snapshot and rejects A layout callback after B', () async {
    final written = <ReadHistoryEntityData>[];
    final controller = create(
      write: (snapshot) async {
        written.add(snapshot);
      },
    );
    await controller.getContent();
    final aGeneration = controller.progressIdentity;
    controller.updateHorizontalProgress(aGeneration, 3, 10);
    controller.selectChapter(0, 1);
    await Future<void>.delayed(Duration.zero);
    final bGeneration = controller.progressIdentity;
    controller.updateHorizontalProgress(bGeneration, 1, 4);
    controller.updateHorizontalProgress(aGeneration, 9, 10);
    controller.updateVerticalProgress(aGeneration, 999, 1000);
    await controller.setReadHistory();
    expect(written.map((snapshot) => snapshot.cid), ['A', 'B']);
    expect(written.first.location, 3);
    expect(written.first.progress, 40);
    expect(written.last.location, 1);
    expect(written.last.progress, 50);
    expect(controller.currentLocation.value, 0);
  });

  test('close flushes once, cancels pending timer and ignores in-flight chapter', () async {
    final pending = Completer<Content>();
    final written = <ReadHistoryEntityData>[];
    final platform = _Platform(storage);
    final controller = create(
      read: (_, cid) => cid == 'B' ? pending.future : Future.value(Content(text: cid, images: [])),
      write: (snapshot) async {
        written.add(snapshot);
      },
      platform: platform,
    );
    await controller.getContent();
    controller.updateHorizontalProgress(controller.progressIdentity, 2, 5);
    controller.onClose();
    controller.onClose();
    await controller.historySettled;
    await Future<void>.delayed(const Duration(milliseconds: 180));
    expect(written.length, 1);
    expect(written.single.cid, 'A');
    expect(written.single.location, 2);
    expect(platform.closes, 1);
    expect(() => controller.pageController.addListener(() {}), throwsFlutterError);

    final loading = create(read: (_, _) => pending.future);
    final future = loading.getContent();
    loading.onClose();
    pending.complete(Content(text: 'late', images: ['late']));
    await future;
    expect(loading.text.value, isEmpty);
    expect(loading.images, isEmpty);
  });

  test('vertical snapshot survives a switch and exit while next chapter is loading', () async {
    storage.readerDirection.value = ReaderDirection.upToDown;
    final pending = Completer<Content>();
    final written = <ReadHistoryEntityData>[];
    final controller = create(
      read: (_, cid) => cid == 'B' ? pending.future : Future.value(Content(text: cid, images: [])),
      write: (snapshot) async {
        written.add(snapshot);
      },
    );
    await controller.getContent();
    final generation = controller.progressIdentity;
    controller.updateVerticalProgress(generation, 420, 1000);
    controller.selectChapter(0, 1);
    controller.updateVerticalProgress(generation, 800, 1000);
    controller.onClose();
    pending.complete(Content(text: 'late B', images: []));
    await controller.historySettled;
    await Future<void>.delayed(const Duration(milliseconds: 180));
    expect(written.length, 1);
    expect(written.single.cid, 'A');
    expect(written.single.location, 420);
    expect(written.single.progress, 42);
    expect(controller.text.value, 'A');
  });

  test('writes serialize; a failed write does not prevent later progress', () async {
    final gate = Completer<void>();
    final started = <ReadHistoryEntityData>[];
    final controller = create(
      write: (snapshot) async {
        started.add(snapshot);
        if (started.length == 1) {
          await gate.future;
          throw StateError('disk failure');
        }
      },
    );
    await controller.getContent();
    controller.updateHorizontalProgress(controller.progressIdentity, 2, 10);
    final first = controller.setReadHistory();
    controller.selectChapter(0, 1);
    await Future<void>.delayed(Duration.zero);
    controller.updateHorizontalProgress(controller.progressIdentity, 4, 10);
    final last = controller.setReadHistory();
    expect(started.length, 1);
    gate.complete();
    await first;
    await last;
    expect(started.first.cid, 'A');
    expect(started.last.cid, 'B');
    expect(started.last.location, 4);
    expect(controller.historyError, isNull);
  });

  test('read failure is recoverable by retry', () async {
    var attempts = 0;
    final controller = create(
      read: (_, _) async {
        if (++attempts == 1) throw StateError('unreadable chapter');
        return Content(text: 'recovered', images: []);
      },
    );
    await controller.getContent();
    expect(controller.pageState.value, PageState.error);
    await controller.getContent();
    expect(controller.pageState.value, PageState.success);
    expect(controller.text.value, 'recovered');
  });

  test('missing cid starts first available chapter without restoring unrelated position', () async {
    final controller = create(
      args: ReaderArgs('book', [CatVolume(title: 'empty', chapters: []), ...catalogue], 'missing', 73),
    );
    await controller.getContent();
    expect(controller.cid, 'A');
    expect(controller.currentVolumeIndex, 1);
    expect(controller.initialHorizontalIndex, 0);
    expect(controller.currentIndex.value, 0);
  });

  test('empty catalogue produces recoverable error without attempting IO', () async {
    var reads = 0;
    final controller = create(
      args: ReaderArgs('book', [], 'missing', 73),
      read: (_, _) async {
        reads++;
        return Content(text: '', images: []);
      },
    );
    await controller.getContent();
    expect(controller.pageState.value, PageState.error);
    expect(controller.errorMsg, isNotEmpty);
    expect(reads, 0);
    controller.catalogue.addAll(catalogue);
    controller.selectChapter(0, 0);
    await Future<void>.delayed(Duration.zero);
    expect(controller.pageState.value, PageState.success);
    expect(reads, 1);
  });

  test('battery reads finishing after close cannot publish or resubscribe', () async {
    final initial = Completer<int>();
    final eventRead = Completer<int>();
    final changes = StreamController<BatteryState>(sync: true);
    var reads = 0;
    final platform = ReaderPlatform(
      settings: () => ReaderSettings.load(storage),
      prevPage: () {},
      nextPage: () {},
      batteryChanges: changes.stream,
      readBatteryLevel: () => ++reads == 1 ? initial.future : eventRead.future,
    );
    platform.onInit();
    changes.add(BatteryState.charging);
    platform.onClose();
    initial.complete(50);
    eventRead.complete(80);
    await Future<void>.delayed(Duration.zero);
    changes.add(BatteryState.full);
    expect(platform.batteryLevel.value, 0);
    expect(reads, 2);
    platform.onInit();
    expect(reads, 2);
    await changes.close();
  });
}
