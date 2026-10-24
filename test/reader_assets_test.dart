import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hikari_novel_flutter/pages/reader/reader_assets.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Directory fonts;
  late Directory backgrounds;
  late File source;
  late File oldFont;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('hikari-assets-test-');
    fonts = await Directory('${root.path}/font').create();
    backgrounds = await Directory('${root.path}/bgImage').create();
    source = await File('${root.path}/selected.ttf').writeAsString('font input');
    oldFont = await File('${fonts.path}/old.ttf').writeAsString('old usable font');
  });
  tearDown(() async => root.delete(recursive: true));

  ReaderAssets store({Future<String?> Function(String)? loader, Future<File> Function(File, String)? copy, Future<void> Function(String)? validateImage}) =>
      ReaderAssets(
        fontDirectory: fonts,
        backgroundDirectory: backgrounds,
        selectFile: (_) async => source.path,
        fontLoader: loader ?? (_) async => 'New family',
        copyFile: copy,
        imageValidator: validateImage ?? (_) async {},
      );

  test('preparing a new font loads the copied file and leaves the old file untouched', () async {
    String? loaded;
    final prepared = await store(
      loader: (target) async {
        loaded = target;
        expect(await File(target).readAsString(), 'font input');
        return 'New family';
      },
    ).pickTextStyleFile();
    expect(prepared!.path, loaded);
    expect(prepared.family, 'New family');
    expect(await oldFont.readAsString(), 'old usable font');
    expect(await source.exists(), isTrue);
  });

  test('invalid font and loader failure remove only this import', () async {
    for (final loader in <Future<String?> Function(String)>[(_) async => '', (_) async => throw const FormatException('bad font')]) {
      await expectLater(store(loader: loader).pickTextStyleFile(), throwsFormatException);
      expect((await fonts.list().toList()).map((f) => path.normalize(f.path)), [path.normalize(oldFont.path)]);
      expect(await source.exists(), isTrue);
    }
  });

  test('partial copy failure removes target and keeps source and old font', () async {
    await expectLater(
      store(
        copy: (_, target) async {
          await File(target).writeAsString('partial');
          throw const FileSystemException('copy failed');
        },
      ).pickTextStyleFile(),
      throwsA(isA<FileSystemException>()),
    );
    expect((await fonts.list().toList()).map((f) => path.normalize(f.path)), [path.normalize(oldFont.path)]);
    expect(await source.exists(), isTrue);
  });

  test('invalid background never replaces or removes the existing image', () async {
    final oldImage = await File('${backgrounds.path}/old.png').writeAsString('old');
    await expectLater(store(validateImage: (_) async => throw const FormatException('bad image')).pickBgImageFile(false), throwsFormatException);
    expect((await backgrounds.list().toList()).map((f) => path.normalize(f.path)), [path.normalize(oldImage.path)]);
  });

  test('cancel does not create imports and cleanup refuses files outside cache', () async {
    final assets = ReaderAssets(fontDirectory: fonts, backgroundDirectory: backgrounds, selectFile: (_) async => null);
    expect(await assets.pickTextStyleFile(), isNull);
    await assets.deleteStoredFont(source.path);
    await assets.deleteStoredBackground(oldFont.path);
    expect(await source.exists(), isTrue);
    expect(await oldFont.exists(), isTrue);
  });
}
