import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hikari_novel_flutter/common/database/database.dart';
// Use Drift's existing SQLite runtime to create historical files before open.
// ignore: depend_on_referenced_packages
import 'package:sqlite3/sqlite3.dart';

// Historical sources: acb07f6 entity.dart (v1); 1cbdadc (v2 removes
// volume/chapter); ae65b16 (v3 changes cookies only). The original v1->v2
// handwritten SQL also produced nullable columns, so test both v2 shapes.
void fixture(File file, int version, {bool nullable = false}) {
  final sql = sqlite3.open(file.path);
  final required = nullable ? '' : ' NOT NULL';
  sql.execute('''CREATE TABLE read_history_entity (
    cid TEXT$required PRIMARY KEY, aid TEXT$required,
    ${version == 1 ? 'volume INTEGER NOT NULL, chapter INTEGER NOT NULL,' : ''}
    reader_mode INTEGER$required,
    is_dual_page INTEGER$required ${nullable ? '' : 'CHECK (is_dual_page IN (0, 1))'},
    location INTEGER$required, progress INTEGER$required,
    is_latest INTEGER$required ${nullable ? '' : 'CHECK (is_latest IN (0, 1))'}
  )''');
  sql.execute('''INSERT INTO read_history_entity VALUES
    ('c1','a1',${version == 1 ? '2,3,' : ''}1,0,77,35,1),
    ('c2','a1',${version == 1 ? '2,4,' : ''}2,1,9,80,0)''');
  sql.execute('CREATE TABLE search_history_entity (keyword TEXT NOT NULL PRIMARY KEY)');
  sql.execute("INSERT INTO search_history_entity VALUES ('retained query')");
  sql.execute('''CREATE TABLE bookshelf_entity (
    aid TEXT NOT NULL PRIMARY KEY, bid TEXT NOT NULL, url TEXT NOT NULL,
    title TEXT NOT NULL, img TEXT NOT NULL, class_id TEXT NOT NULL)''');
  sql.execute("INSERT INTO bookshelf_entity VALUES ('b1','delete1','book.php?aid=b1','kept book','cover.jpg','2')");
  sql.execute('''CREATE TABLE browsing_history_entity (
    aid TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, img TEXT NOT NULL, time INTEGER NOT NULL)''');
  sql.execute("INSERT INTO browsing_history_entity VALUES ('view1','kept browsing','view.jpg',1700000000)");
  sql.execute('CREATE TABLE novel_detail_entity (aid TEXT NOT NULL PRIMARY KEY, json TEXT NOT NULL)');
  sql.execute('INSERT INTO novel_detail_entity VALUES (?, ?)', ['detail1', '{"title":"kept detail"}']);
  sql.execute('PRAGMA user_version = $version');
  sql.dispose();
}

const preservedTables = ['bookshelf_entity', 'browsing_history_entity', 'search_history_entity', 'novel_detail_entity'];

Map<String, List<List<Object?>>> snapshot(Database sql) => {
  for (final table in preservedTables) table: sql.select('SELECT * FROM $table').map((r) => r.values.toList()).toList(),
};

Future<void> checkOtherTables(AppDatabase db) async {
  expect((await db.select(db.bookshelfEntity).get()).single.title, 'kept book');
  expect((await db.select(db.browsingHistoryEntity).get()).single.time, DateTime.fromMillisecondsSinceEpoch(1700000000000));
  expect((await db.select(db.searchHistoryEntity).get()).single.keyword, 'retained query');
  expect((await db.select(db.novelDetailEntity).get()).single.json, '{"title":"kept detail"}');
}

class FailingDatabase extends AppDatabase {
  FailingDatabase(File file) : super.forTesting(NativeDatabase(file));

  @override
  Future<void> customStatement(String statement, [List<Object?>? args]) {
    // Fail after DDL and copy of the v1 step, before committing the target version.
    if (statement.contains('PRAGMA user_version = 4')) {
      throw StateError('injected migration failure');
    }
    return super.customStatement(statement, args);
  }
}

void main() {
  for (final version in [1, 2, 3]) {
    for (final nullable in [false, if (version > 1) true]) {
      test('v$version nullable=$nullable upgrades without losing original rows', () async {
        final dir = await Directory.systemTemp.createTemp('hikari-migration-');
        final file = File('${dir.path}/fixture.sqlite');
        fixture(file, version, nullable: nullable);
        final baseline = sqlite3.open(file.path);
        final others = snapshot(baseline);
        baseline.dispose();
        final cache = File('${dir.path}/cached_chapter/old.txt');
        await cache.parent.create();
        await cache.writeAsString('downloaded chapter');
        final db = AppDatabase.forTesting(NativeDatabase(file));
        try {
          await checkOtherTables(db);
          final history = await db.select(db.readHistoryEntity).get();
          expect(history.map((r) => r.cid), ['c1', 'c2']);
          expect(history.map((r) => r.location), [77, 9]);
          expect(history.map((r) => r.progress), [35, 80]);
          expect(history.map((r) => r.readerMode), [1, 2]);
          expect(history.map((r) => r.isLatest), [true, false]);
          if (version == 1) {
            final v1 = await db.customSelect('SELECT * FROM read_history_entity_legacy_v1 ORDER BY cid').get();
            expect(v1.map((r) => r.read<int>('volume')), [2, 2]);
            expect(v1.map((r) => r.read<int>('chapter')), [3, 4]);
          }
          expect((await db.customSelect('SELECT * FROM search_history_entity').get()).single.read<String>('keyword'), 'retained query');
        } finally {
          await db.close();
        }
        expect(await cache.readAsString(), 'downloaded chapter');
        final raw = sqlite3.open(file.path);
        expect(snapshot(raw), others);
        expect(raw.select('PRAGMA user_version').single.values.single, 4);
        raw.dispose();
        final reopened = AppDatabase.forTesting(NativeDatabase(file));
        try {
          await reopened.customStatement('UPDATE read_history_entity SET location = 11 WHERE cid = \'c1\'');
        } finally {
          await reopened.close();
        }
        final unchanged = AppDatabase.forTesting(NativeDatabase(file));
        expect((await unchanged.getReadHistoryByCid('c1'))!.location, 11);
        await unchanged.close();
        await dir.delete(recursive: true);
      });
    }
  }

  test('failed cross-version upgrade rolls back DDL, rows and version and can retry', () async {
    final dir = await Directory.systemTemp.createTemp('hikari-migration-failure-');
    final file = File('${dir.path}/fixture.sqlite');
    fixture(file, 1);
    final baseline = sqlite3.open(file.path);
    final others = snapshot(baseline);
    baseline.dispose();
    final failed = FailingDatabase(file);
    await expectLater(failed.select(failed.readHistoryEntity).get(), throwsStateError);
    await failed.close();
    final raw = sqlite3.open(file.path);
    expect(snapshot(raw), others);
    expect(raw.select('PRAGMA user_version').single.values.single, 1);
    expect(raw.select('SELECT volume, location FROM read_history_entity WHERE cid = ?', ['c1']).single.values, [2, 77]);
    expect(raw.select("SELECT name FROM sqlite_master WHERE name LIKE '%legacy%'").isEmpty, true);
    raw.dispose();
    final retry = AppDatabase.forTesting(NativeDatabase(file));
    expect((await retry.getReadHistoryByCid('c1'))!.location, 77);
    await checkOtherTables(retry);
    await retry.close();
    await dir.delete(recursive: true);
  });

  // 无法识别的旧阅读记录：与上游 v3->v4 的清空规则结果一致（阅读记录为空），
  // 但数据库必须能打开，原始行完整归档，其它表不受影响。
  for (final (version, corruption) in [
    (2, 'UPDATE read_history_entity SET aid = NULL WHERE cid = \'c1\''),
    (2, 'UPDATE read_history_entity SET is_latest = 1'),
    (3, 'UPDATE read_history_entity SET location = NULL'),
    (2, 'ALTER TABLE read_history_entity ADD COLUMN unexpected TEXT'),
    (1, 'UPDATE read_history_entity SET reader_mode = 9'),
    (
      2,
      '''DELETE FROM read_history_entity;
      ALTER TABLE read_history_entity RENAME TO old_shape;
      CREATE TABLE read_history_entity (
        cid TEXT PRIMARY KEY, aid TEXT, reader_mode TEXT, is_dual_page INTEGER,
        location INTEGER, progress INTEGER, is_latest INTEGER);
      DROP TABLE old_shape;''',
    ),
  ]) {
    test('v$version unrecognized old data is archived and reading history reset: $corruption', () async {
      final dir = await Directory.systemTemp.createTemp('hikari-migration-invalid-');
      final file = File('${dir.path}/fixture.sqlite');
      fixture(file, version, nullable: version > 1);
      var raw = sqlite3.open(file.path);
      raw.execute(corruption);
      final before = raw.select('SELECT * FROM read_history_entity').map((r) => r.values.toList()).toList();
      final others = snapshot(raw);
      raw.dispose();
      final db = AppDatabase.forTesting(NativeDatabase(file));
      try {
        expect(await db.select(db.readHistoryEntity).get(), isEmpty);
        await checkOtherTables(db);
        // 新表可以正常写入
        await db.upsertReadHistory(
          const ReadHistoryEntityData(cid: 'n1', aid: 'a1', readerMode: 1, isDualPage: false, location: 5, progress: 10, isLatest: true),
        );
        expect((await db.getReadHistoryByCid('n1'))!.location, 5);
      } finally {
        await db.close();
      }
      raw = sqlite3.open(file.path);
      expect(raw.select('PRAGMA user_version').single.values.single, 4);
      expect(raw.select('SELECT * FROM read_history_entity_legacy_v$version').map((r) => r.values.toList()).toList(), before);
      expect(snapshot(raw), others);
      raw.dispose();
      await dir.delete(recursive: true);
    });
  }

  test('missing reading-history table is recreated instead of blocking the upgrade', () async {
    final dir = await Directory.systemTemp.createTemp('hikari-migration-missing-');
    final file = File('${dir.path}/fixture.sqlite');
    fixture(file, 3);
    var raw = sqlite3.open(file.path);
    raw.execute('DROP TABLE read_history_entity');
    raw.dispose();
    final db = AppDatabase.forTesting(NativeDatabase(file));
    try {
      expect(await db.select(db.readHistoryEntity).get(), isEmpty);
      await checkOtherTables(db);
    } finally {
      await db.close();
    }
    raw = sqlite3.open(file.path);
    expect(raw.select('PRAGMA user_version').single.values.single, 4);
    raw.dispose();
    await dir.delete(recursive: true);
  });

  test('v1 upgrade never overwrites an existing archive table', () async {
    final dir = await Directory.systemTemp.createTemp('hikari-migration-archive-');
    final file = File('${dir.path}/fixture.sqlite');
    fixture(file, 1);
    var raw = sqlite3.open(file.path);
    raw.execute('CREATE TABLE read_history_entity_legacy_v1 (marker TEXT)');
    raw.execute("INSERT INTO read_history_entity_legacy_v1 VALUES ('older archive')");
    raw.dispose();
    final db = AppDatabase.forTesting(NativeDatabase(file));
    try {
      expect((await db.select(db.readHistoryEntity).get()).map((r) => r.location), [77, 9]);
    } finally {
      await db.close();
    }
    raw = sqlite3.open(file.path);
    expect(raw.select('SELECT marker FROM read_history_entity_legacy_v1').single.values, ['older archive']);
    expect(raw.select('SELECT volume FROM read_history_entity_legacy_v1_2 ORDER BY cid').map((r) => r.values.single), [2, 2]);
    raw.dispose();
    await dir.delete(recursive: true);
  });
}
