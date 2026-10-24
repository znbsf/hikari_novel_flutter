import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hikari_novel_flutter/pages/reader/reader_assets.dart';
import 'package:hikari_novel_flutter/pages/reader/reader_settings.dart';
import 'package:hikari_novel_flutter/service/local_storage_service.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as path;

class _WriteFailureBox extends Fake implements Box<dynamic> {
  _WriteFailureBox(this.records, {this.commitBeforeFailure = false});
  final Map<dynamic, dynamic> records;
  final bool commitBeforeFailure;

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => records.containsKey(key) ? records[key] : defaultValue;

  @override
  Future<void> putAll(Map<dynamic, dynamic> entries) async {
    if (commitBeforeFailure) records.addAll(entries);
    throw StateError('simulated backend or post-commit compaction failure');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Directory fonts;
  late Directory backgrounds;
  late LocalStorageService storage;
  late File oldFont;
  late File oldImage;
  late File source;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('hikari-preferences-test-');
    fonts = await Directory('${root.path}/font').create();
    backgrounds = await Directory('${root.path}/bgImage').create();
    oldFont = await File('${fonts.path}/old.ttf').writeAsString('old font');
    oldImage = await File('${backgrounds.path}/old.png').writeAsString('old image');
    source = await File('${root.path}/new.ttf').writeAsString('new asset');
    storage = LocalStorageService();
    await storage.init(hivePath: '${root.path}/hive');
    await Pref.writeAll({storage.readerTextStyleFilePath: oldFont.path, storage.readerTextFamily: 'Old family', storage.readerDayBgImage: oldImage.path});
  });
  tearDown(() async {
    await Hive.close();
    Hive.resetAdapters();
    await root.delete(recursive: true);
  });

  ReaderAssets assets({Future<String?> Function(String)? loader}) => ReaderAssets(
    fontDirectory: fonts,
    backgroundDirectory: backgrounds,
    selectFile: (_) async => source.path,
    fontLoader: loader ?? (_) async => 'New family',
    imageValidator: (_) async {},
  );

  test('font pair publishes together after awaited persistence, preserving concurrent ordinary edits', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final preferences = ReaderPreferences(
      storage,
      assetStore: assets(),
      writePreferences: (values) async {
        expect(values.length, 2);
        entered.complete();
        await release.future;
        expect(await oldFont.exists(), isTrue);
        await Pref.writeAll(values);
      },
    );
    final original = preferences.state.value;
    final pending = preferences.pickTextStyleFile();
    await entered.future;
    expect(preferences.state.value.textFamily, 'Old family');
    ReaderFields.fontSize.setIn(preferences, 22);
    release.complete();
    expect(await pending, isTrue);
    final saved = preferences.state.value;
    expect(saved.textFamily, 'New family');
    expect(saved.fontSize, 22);
    expect(original.textFamily, 'Old family');
    expect(await oldFont.exists(), isFalse);
    expect(await File(saved.textStyleFilePath!).exists(), isTrue);
    await Hive.close();
    Hive.resetAdapters();
    storage = LocalStorageService();
    await storage.init(hivePath: '${root.path}/hive');
    expect(ReaderSettings.load(storage).textStyleFilePath, saved.textStyleFilePath);
    expect(ReaderSettings.load(storage).textFamily, 'New family');
  });

  test('failed import write retains settings and old font and removes only prepared file', () async {
    final preferences = ReaderPreferences(storage, assetStore: assets(), writePreferences: (_) async => throw StateError('disk failure'));
    expect(await preferences.pickTextStyleFile(), isFalse);
    expect(preferences.state.value.textFamily, 'Old family');
    expect(storage.readerTextStyleFilePath.value, oldFont.path);
    expect((await fonts.list().toList()).map((file) => path.normalize(file.path)), [path.normalize(oldFont.path)]);
    expect(await source.exists(), isTrue);
  });

  test('failed font and background clears leave references and files intact', () async {
    final preferences = ReaderPreferences(storage, assetStore: assets(), writePreferences: (_) async => throw StateError('disk failure'));
    await expectLater(preferences.clearTextStyleFile(), throwsStateError);
    await expectLater(preferences.clearReaderBgImage(false), throwsStateError);
    expect(preferences.state.value.textStyleFilePath, oldFont.path);
    expect(preferences.state.value.readerDayBgImage, oldImage.path);
    expect(storage.readerTextFamily.value, 'Old family');
    expect(await oldFont.exists(), isTrue);
    expect(await oldImage.exists(), isTrue);
  });

  test('background saves before deleting old file, and failed writes clean new image', () async {
    var fail = true;
    final preferences = ReaderPreferences(
      storage,
      assetStore: assets(),
      writePreferences: (values) async {
        expect(await File(storage.readerDayBgImage.value!).exists(), isTrue);
        if (fail) throw StateError('disk failure');
        await Pref.writeAll(values);
      },
    );
    expect(await preferences.pickBgImageFile(false), isFalse);
    expect((await backgrounds.list().toList()).map((file) => path.normalize(file.path)), [path.normalize(oldImage.path)]);
    fail = false;
    expect(await preferences.pickBgImageFile(false), isTrue);
    final saved = preferences.state.value.readerDayBgImage!;
    expect(storage.readerDayBgImage.value, saved);
    expect(await File(saved).exists(), isTrue);
    expect(await oldImage.exists(), isFalse);
    await preferences.clearReaderBgImage(false);
    expect(storage.readerDayBgImage.value, isNull);
    expect(await File(saved).exists(), isFalse);
  });

  test('clearing one appearance preserves a background still referenced by the other', () async {
    await storage.readerNightBgImage.write(oldImage.path);
    final preferences = ReaderPreferences(storage, assetStore: assets());
    await preferences.clearReaderBgImage(false);
    expect(storage.readerDayBgImage.value, isNull);
    expect(storage.readerNightBgImage.value, oldImage.path);
    expect(await oldImage.exists(), isTrue);
    await preferences.clearReaderBgImage(true);
    expect(await oldImage.exists(), isFalse);
  });

  test('late failed initial font load cannot invalidate a newer successful import', () async {
    final entered = Completer<void>();
    final oldLoad = Completer<String?>();
    final preferences = ReaderPreferences(
      storage,
      assetStore: assets(
        loader: (filePath) {
          if (filePath == oldFont.path) {
            entered.complete();
            return oldLoad.future;
          }
          return Future.value('New family');
        },
      ),
    );
    preferences.checkFontFile(false);
    await entered.future;
    expect(await preferences.pickTextStyleFile(), isTrue);
    oldLoad.completeError(const FormatException('old font failed'));
    await Future<void>.delayed(Duration.zero);
    expect(preferences.state.value.textFamily, 'New family');
    expect(preferences.isFontFileAvailable.value, isTrue);
  });

  test('closing while loading an import prevents its commit and cleans prepared file', () async {
    final entered = Completer<void>();
    final release = Completer<String?>();
    final preferences = ReaderPreferences(
      storage,
      assetStore: assets(
        loader: (_) {
          entered.complete();
          return release.future;
        },
      ),
    );
    final pending = preferences.pickTextStyleFile();
    await entered.future;
    preferences.close();
    release.complete('New family');
    expect(await pending, isFalse);
    expect(storage.readerTextFamily.value, 'Old family');
    expect((await fonts.list().toList()).map((file) => path.normalize(file.path)), [path.normalize(oldFont.path)]);
  });

  test('grouped preferences reject cross-box writes before mutating either box', () async {
    await expectLater(Pref.writeAll({storage.cookie: 'new cookie', storage.readerTextFamily: 'new family'}), throwsArgumentError);
    expect(storage.cookie.value, isNull);
    expect(storage.readerTextFamily.value, 'Old family');
  });

  test('grouped backend failure reports failure while preserving both old values', () async {
    final box = _WriteFailureBox({'path': 'old.ttf', 'family': 'Old'});
    final file = Pref<String?>(box, 'path', null);
    final family = Pref<String?>(box, 'family', null);
    await expectLater(Pref.writeAll({file: 'new.ttf', family: 'New'}), throwsStateError);
    expect(file.value, 'old.ttf');
    expect(family.value, 'Old');
  });

  test('post-commit compaction failure does not misreport committed references as rolled back', () async {
    final box = _WriteFailureBox({'path': 'old.ttf', 'family': 'Old'}, commitBeforeFailure: true);
    final file = Pref<String?>(box, 'path', null);
    final family = Pref<String?>(box, 'family', null);
    await Pref.writeAll({file: 'new.ttf', family: 'New'});
    expect(file.value, 'new.ttf');
    expect(family.value, 'New');
  });

  test('close during an already started write keeps committed file and suppresses callbacks', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    Map<Pref<dynamic>, dynamic>? committed;
    var callbacks = 0;
    final preferences = ReaderPreferences(
      storage,
      assetStore: assets(),
      writePreferences: (values) async {
        entered.complete();
        await release.future;
        await Pref.writeAll(values);
        committed = values;
      },
    )..onChanged = (_, _) => callbacks++;
    final pending = preferences.pickTextStyleFile();
    await entered.future;
    preferences.close();
    release.complete();
    expect(await pending, isTrue);
    expect(committed, isNotNull);
    expect(callbacks, 0);
    expect(storage.readerTextFamily.value, 'New family');
    expect(await File(storage.readerTextStyleFilePath.value!).exists(), isTrue);
    expect(await oldFont.exists(), isFalse);
  });
}
