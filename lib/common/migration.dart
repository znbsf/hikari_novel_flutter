import 'database/database.dart';

/// SQL-only upgrades. Original rows stay in legacy tables for recovery; no
/// cache, account or filesystem mutation belongs in this transaction.
class Migration {
  static Future<void> upgrade(AppDatabase db, int from, int to) async {
    if (from < 1 || from > 3 || to != 4) {
      throw StateError('Unsupported database upgrade: $from -> $to');
    }
    await db.transaction(() async {
      if (from < 2) await fromOneToTwo(db);
      if (from < 3) await fromTwoToThree();
      await fromThreeToFour(db);
      // Drift writes this again after beforeOpen. Include it here as well so a
      // process interruption cannot leave committed DDL with the old version.
      await db.customStatement('PRAGMA user_version = 4');
    });
  }

  static Future<void> fromOneToTwo(AppDatabase db) async {
    await _checkColumns(db, true);
    await _rebuild(db, 'read_history_entity_legacy_v1');
  }

  // The original change only cleared external cookies, with no SQL change.
  static Future<void> fromTwoToThree() async {}

  static Future<void> fromThreeToFour(AppDatabase db) async {
    await _checkColumns(db, false);
    // v3 and v4 have the same SQL schema and reading-mode values.
    // No evidence justifies deleting or resetting old reading positions.
  }

  static Future<void> _checkColumns(AppDatabase db, bool versionOne) async {
    final columns = await db.customSelect('PRAGMA table_info(read_history_entity)').get();
    final names = columns.map((r) => r.read<String>('name')).toSet();
    final expected = {'cid', 'aid', 'reader_mode', 'is_dual_page', 'location', 'progress', 'is_latest', if (versionOne) 'volume', if (versionOne) 'chapter'};
    if (names.length != expected.length ||
        !names.containsAll(expected) ||
        columns.singleWhere((r) => r.read<String>('name') == 'cid').read<int>('pk') != 1 ||
        columns.where((r) => r.read<int>('pk') != 0).length != 1 ||
        columns.any((r) => r.read<String>('type').toUpperCase() != ({'cid', 'aid'}.contains(r.read<String>('name')) ? 'TEXT' : 'INTEGER'))) {
      throw StateError('Unrecognized legacy reading-history schema; original database retained');
    }
    final invalid = await db.customSelect('''
      SELECT 1 FROM read_history_entity WHERE
        typeof(cid) != 'text' OR typeof(aid) != 'text' OR
        typeof(reader_mode) != 'integer' OR reader_mode NOT IN (1, 2) OR
        typeof(is_dual_page) != 'integer' OR is_dual_page NOT IN (0, 1) OR
        typeof(is_latest) != 'integer' OR is_latest NOT IN (0, 1) OR
        typeof(location) != 'integer' OR typeof(progress) != 'integer'
      LIMIT 1
    ''').get();
    final ambiguous = await db.customSelect('''
      SELECT aid FROM read_history_entity WHERE is_latest = 1
      GROUP BY aid HAVING COUNT(*) > 1 LIMIT 1
    ''').get();
    if (invalid.isNotEmpty || ambiguous.isNotEmpty) {
      throw StateError('Invalid or ambiguous legacy reading history; original database retained');
    }
  }

  static Future<void> _rebuild(AppDatabase db, String archive) async {
    // ALTER preserves every original field, even the removed volume/chapter.
    // A pre-existing archive causes a failure, never an overwrite.
    await db.customStatement('ALTER TABLE read_history_entity RENAME TO $archive');
    await db.customStatement('''
      CREATE TABLE read_history_entity (
        cid TEXT NOT NULL PRIMARY KEY,
        aid TEXT NOT NULL,
        reader_mode INTEGER NOT NULL,
        is_dual_page INTEGER NOT NULL CHECK (is_dual_page IN (0, 1)),
        location INTEGER NOT NULL,
        progress INTEGER NOT NULL,
        is_latest INTEGER NOT NULL CHECK (is_latest IN (0, 1))
      )
    ''');
    // Preserve every position exactly.
    await db.customStatement('''
      INSERT INTO read_history_entity
        (cid, aid, reader_mode, is_dual_page, location, progress, is_latest)
      SELECT cid, aid, reader_mode, is_dual_page,
        location, progress, is_latest FROM $archive
    ''');
  }
}
