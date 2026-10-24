import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' show Get, GetMaterialApp, Inst, GetResetExt;
import 'package:hikari_novel_flutter/models/cat_chapter.dart';
import 'package:hikari_novel_flutter/models/cat_volume.dart';
import 'package:hikari_novel_flutter/models/reader_direction.dart';
import 'package:hikari_novel_flutter/pages/reader/controller.dart';
import 'package:hikari_novel_flutter/pages/reader/reader_settings.dart';
import 'package:hikari_novel_flutter/pages/reader/widgets/catalogue_sheet.dart';
import 'package:hikari_novel_flutter/service/local_storage_service.dart';
import 'package:hive_ce/hive.dart';

class _ReaderController extends ReaderController {
  _ReaderController(super.args);

  List<int>? loadedPosition;

  @override
  Future<void> getContent() async {
    loadedPosition = [currentVolumeIndex, currentChapterIndex, initialHorizontalIndex, initialVerticalOffset];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late LocalStorageService storage;

  Future<void> openStorage() async {
    directory = await Directory.systemTemp.createTemp('hikari-reader-test-');
    storage = Get.put(LocalStorageService());
    await storage.init(hivePath: directory.path);
  }

  Future<void> closeStorage() async {
    Get.reset();
    await Hive.close();
    Hive.resetAdapters();
    directory.deleteSync(recursive: true);
  }

  group('阅读器设置', () {
    setUp(openStorage);
    tearDown(closeStorage);

    test('清空自定义字体时同步清空内存和 Pref，保留其他设置及旧快照', () {
      storage.readerTextFamily.value = '测试字体';
      storage.readerTextStyleFilePath.value = 'font/test.ttf';
      storage.readerFontSize.value = 24;
      final preferences = ReaderPreferences(storage);
      final previous = preferences.state.value;

      ReaderFields.textStyleFilePath.setIn(preferences, null);
      ReaderFields.textFamily.setIn(preferences, null);

      expect(preferences.state.value.textFamily, isNull);
      expect(preferences.state.value.textStyleFilePath, isNull);
      expect(storage.readerTextFamily.value, isNull);
      expect(storage.readerTextStyleFilePath.value, isNull);
      expect(ReaderSettings.load(storage).textFamily, isNull);
      expect(preferences.state.value.fontSize, 24);
      expect(previous.textFamily, '测试字体');
      expect(previous.textStyleFilePath, 'font/test.ttf');
    });

    test('日夜外观按进入模式选择，编辑对应值后立即生效且可清空', () {
      storage.readerDayTextColor.value = const Color(0xFFF44336);
      storage.readerNightTextColor.value = const Color(0xFF2196F3);
      storage.readerDayBgColor.value = const Color(0xFFFFFFFF);
      storage.readerNightBgColor.value = const Color(0xFF000000);
      storage.readerDayBgImage.value = 'day.png';
      storage.readerNightBgImage.value = 'night.png';
      final preferences = ReaderPreferences(storage)..initialize(Brightness.light);

      expect(preferences.textColor, const Color(0xFFF44336));
      expect(preferences.bgColor, const Color(0xFFFFFFFF));
      expect(preferences.bgImagePath, 'day.png');
      // 普通设置更新不会重新选择日夜外观。
      ReaderFields.fontSize.setIn(preferences, 20);
      expect(preferences.state.value.fontSize, isA<double>());
      expect(storage.readerFontSize.value, isA<double>());
      expect(storage.readerFontSize.value, 20);
      expect(ReaderSettings.load(storage).fontSize, 20);
      expect(preferences.textColor, const Color(0xFFF44336));
      ReaderFields.readerNightTextColor.setIn(preferences, const Color(0xFF4CAF50));
      expect(preferences.textColor, const Color(0xFF4CAF50));
      expect(storage.readerNightTextColor.value, const Color(0xFF4CAF50));
      expect(storage.readerDayTextColor.value, const Color(0xFFF44336));
      ReaderFields.readerNightTextColor.setIn(preferences, null);
      ReaderFields.readerNightBgColor.setIn(preferences, null);
      ReaderFields.readerNightBgImage.setIn(preferences, null);
      expect(preferences.textColor, isNull);
      expect(preferences.bgColor, isNull);
      expect(preferences.bgImagePath, isNull);
      expect(storage.readerNightTextColor.value, isNull);
      expect(storage.readerNightBgColor.value, isNull);
      expect(storage.readerNightBgImage.value, isNull);
    });
  });

  for (final direction in [ReaderDirection.leftToRight, ReaderDirection.upToDown]) {
    testWidgets('目录跳章节在加载前重置初始位置：${direction.name}', (tester) async {
      await tester.runAsync(() async {
        await openStorage();
        storage.readerDirection.value = direction;
        await Hive.box('reader').flush();
      });
      try {
        final catalogue = [
          CatVolume(
            title: '第一卷',
            chapters: [CatChapter(title: '第一章', cid: '101'), CatChapter(title: '第二章', cid: '102')],
          ),
        ];
        final controller = _ReaderController(ReaderArgs('1', catalogue, '101', 73));
        try {
          controller.currentVolumeIndex = 0;
          controller.currentChapterIndex = 0;
          controller.getInitLocation();
          expect(direction == ReaderDirection.upToDown ? controller.initialVerticalOffset : controller.initialHorizontalIndex, 73);

          await tester.pumpWidget(
            GetMaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(onPressed: () => showReaderCatalogueSheet(context, controller), child: const Text('打开目录')),
                ),
              ),
            ),
          );
          await tester.tap(find.text('打开目录'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('第一卷'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('第二章'));
          await tester.pumpAndSettle();

          expect(controller.cid, '102');
          expect(controller.loadedPosition, [0, 1, 0, 0]);
          expect(find.text('打开目录'), findsOneWidget);
          expect(find.text('第二章'), findsNothing);
        } finally {
          controller.pageController.dispose();
          await tester.pumpWidget(const SizedBox.shrink());
        }
      } finally {
        // Hive 的真实文件 IO 必须脱离 widget 测试的 FakeAsync 时钟。
        await tester.runAsync(closeStorage);
      }
    });
  }
}
