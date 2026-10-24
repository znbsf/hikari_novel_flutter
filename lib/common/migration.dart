import 'package:drift/drift.dart' show Variable;

import 'database/database.dart';
import 'log.dart';

/// SQL-only upgrades. Original rows stay in legacy tables for recovery; no
/// cache, account or filesystem mutation belongs in this transaction.
class Migration {
  static Future<void> upgrade(AppDatabase db, int from, int to) async {
    if (from < 1 || from > 3 || to != 4) {
      throw StateError('Unsupported database upgrade: $from -> $to');
    }
    await db.transaction(() async {
      if (await _isRecognized(db, versionOne: from < 2)) {
        // v2/v3 and v4 share the same SQL schema and reading-mode values; v2->v3 only changed cookies.
        if (from < 2) await _archiveAndCreate(db, 'read_history_entity_legacy_v1', copyRows: true);
      } else {
        // Same outcome as upstream's v3->v4 rule (all reading history cleared), but the app still
        // opens and the unrecognized rows stay archived instead of blocking every database access.
        Log.e('Unrecognized legacy reading history (v$from); archived and reset');
        await _archiveAndCreate(db, 'read_history_entity_legacy_v$from', copyRows: false);
      }
      // Drift writes this again after beforeOpen. Include it here as well so a
      // process interruption cannot leave committed DDL with the old version.
      await db.customStatement('PRAGMA user_version = 4');
    });
  }

  static Future<bool> _isRecognized(AppDatabase db, {required bool versionOne}) async {
    final columns = await db.customSelect('PRAGMA table_info(read_history_entity)').get();
    final names = columns.map((r) => r.read<String>('name')).toSet();
    final expected = {'cid', 'aid', 'reader_mode', 'is_dual_page', 'location', 'progress', 'is_latest', if (versionOne) 'volume', if (versionOne) 'chapter'};
    if (names.length != expected.length ||
        !names.containsAll(expected) ||
        columns.singleWhere((r) => r.read<String>('name') == 'cid').read<int>('pk') != 1 ||
        columns.where((r) => r.read<int>('pk') != 0).length != 1 ||
        columns.any((r) => r.read<String>('type').toUpperCase() != ({'cid', 'aid'}.contains(r.read<String>('name')) ? 'TEXT' : 'INTEGER'))) {
      return false;
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
    return invalid.isEmpty && ambiguous.isEmpty;
  }

  /// Moves the current table (if any) to a free archive name and creates the v4 table.
  static Future<void> _archiveAndCreate(AppDatabase db, String archiveBase, {required bool copyRows}) async {
    final archive = await _tableExists(db, 'read_history_entity') ? await _freeTableName(db, archiveBase) : null;
    // ALTER preserves every original field, even the removed volume/chapter.
    if (archive != null) await db.customStatement('ALTER TABLE read_history_entity RENAME TO $archive');
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
    if (copyRows && archive != null) {
      // Preserve every position exactly.
      await db.customStatement('''
        INSERT INTO read_history_entity
          (cid, aid, reader_mode, is_dual_page, location, progress, is_latest)
        SELECT cid, aid, reader_mode, is_dual_page,
          location, progress, is_latest FROM $archive
      ''');
    }
  }

  static Future<bool> _tableExists(AppDatabase db, String name) async =>
      (await db.customSelect("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", variables: [Variable<String>(name)]).get()).isNotEmpty;

  /// An existing archive is never overwritten; a numbered suffix is used instead.
  static Future<String> _freeTableName(AppDatabase db, String base) async {
    var name = base;
    for (var i = 2; await _tableExists(db, name); i++) {
      name = '${base}_$i';
    }
    return name;
  }
}
