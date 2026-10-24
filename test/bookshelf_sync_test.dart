import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hikari_novel_flutter/common/database/database.dart';
import 'package:hikari_novel_flutter/parser/parser.dart';
import 'package:hikari_novel_flutter/service/bookshelf_sync_service.dart';
import 'package:hikari_novel_flutter/service/session_service.dart';

String shelf([String? aid]) =>
    '<div id="content"><form action="bookcase.php"><table>'
    '<tr align="center"><td>书名</td></tr>'
    '${aid == null ? '' : '<tr><td><input type="checkbox" name="checkid[]" value="$aid"></td><td><a href="book.php?aid=$aid">Book $aid</a></td></tr>'}'
    '</table></form></div>';

BookshelfEntityData row(String aid, String shelf) => BookshelfEntityData(aid: aid, bid: aid, url: 'book.php?aid=$aid', title: aid, img: '', classId: shelf);

void main() {
  late AppDatabase db;
  late SessionCoordinator session;
  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    session = SessionCoordinator();
    await db.insertAllBookshelf([row('99', '0')]);
  });
  tearDown(() => db.close());

  test('login, error and malformed pages cannot become empty shelves', () {
    for (final html in [
      '<div id="content">login</div>',
      '<div id="content"><form action="login.php"><input type="password"></form></div>',
      shelf('1').replaceAll('aid=1', 'aid=bad'),
      shelf().replaceAll('</table>', '<tr><td>Damaged book</td><td>Unknown row</td></tr></table>'),
      shelf('1').replaceAll('<input type="checkbox" name="checkid[]" value="1">', '').replaceAll('aid=1', 'broken=1'),
    ]) {
      expect(() => Parser.getBookshelf(html, 0), throwsA(anything));
    }
    expect(Parser.getBookshelf(shelf(), 0).list, isEmpty);
    expect(Parser.getBookshelf(shelf('12345'), 0).list.single.img, contains('/12/12345/'));
  });

  test('one failed request preserves the complete previous mirror', () async {
    final sync = BookshelfSyncService(
      database: db,
      session: session,
      fetch: (index) async {
        if (index == 4) throw StateError('offline');
        return shelf('${index + 1}');
      },
    );
    await expectLater(sync.refreshAll(), throwsStateError);
    expect((await db.getAllBookshelf()).map((book) => book.aid), ['99']);
  });

  test('malformed nonempty response preserves existing mirror', () async {
    final sync = BookshelfSyncService(
      database: db,
      session: session,
      fetch: (_) async => shelf().replaceAll('</table>', '<tr><td>Damaged book</td></tr></table>'),
    );
    await expectLater(sync.refreshShelf(0), throwsFormatException);
    expect((await db.getAllBookshelf()).map((book) => book.aid), ['99']);
  });

  test('complete six-shelf snapshot replaces old rows, including empty shelves', () async {
    final sync = BookshelfSyncService(database: db, session: session, fetch: (index) async => index.isEven ? shelf('${index + 1}') : shelf());
    await sync.refreshAll();
    expect((await db.getAllBookshelf()).map((book) => book.aid).toSet(), {'1', '3', '5'});
  });

  test('valid empty shelf clears only that shelf', () async {
    await db.insertAllBookshelf([row('88', '1')]);
    await BookshelfSyncService(database: db, session: session, fetch: (_) async => shelf()).refreshShelf(0);
    expect((await db.getAllBookshelf()).map((book) => book.aid), ['88']);
  });

  test('insert failure rolls back deletion', () async {
    await expectLater(db.replaceBookshelf([row('1', '0'), row('1', '1')]), throwsA(anything));
    expect((await db.getAllBookshelf()).map((book) => book.aid), ['99']);
  });

  test('newer overlapping request wins over a delayed full snapshot', () async {
    final delayed = Completer<String>();
    var calls = 0;
    final sync = BookshelfSyncService(
      database: db,
      session: session,
      fetch: (index) async {
        if (index == 0 && calls++ == 0) return delayed.future;
        return shelf('${index + 1}');
      },
    );
    final full = sync.refreshAll();
    final rejected = expectLater(full, throwsStateError);
    await sync.refreshShelf(0);
    delayed.complete(shelf('77'));
    await rejected;
    expect((await db.getAllBookshelf()).map((book) => book.aid), ['1']);
  });

  test('session invalidation prevents late requests from repopulating cleared mirror', () async {
    final delayed = Completer<String>();
    final sync = BookshelfSyncService(database: db, session: session, fetch: (_) => delayed.future);
    final refresh = sync.refreshShelf(0);
    final rejected = expectLater(refresh, throwsA(isA<SessionChanged>()));
    session.invalidate();
    await session.serialize(db.deleteAllBookshelf);
    delayed.complete(shelf('1'));
    await rejected;
    expect(await db.getAllBookshelf(), isEmpty);
  });
}
