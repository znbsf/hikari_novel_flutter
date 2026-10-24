import '../common/database/database.dart';
import '../models/resource.dart';
import '../parser/parser.dart';
import 'api_service.dart';
import 'session_service.dart';

/// Fetch first, validate every requested shelf, then publish one atomic snapshot.
class BookshelfSyncService {
  static final instance = BookshelfSyncService();

  BookshelfSyncService({Future<String> Function(int)? fetch, this._database, SessionCoordinator? session})
    : _fetch = fetch ?? _fetchRemote,
      _session = session ?? SessionCoordinator.instance;

  final Future<String> Function(int) _fetch;
  final AppDatabase? _database;
  final SessionCoordinator _session;
  final List<int> _revisions = List.filled(6, 0);

  static Future<String> _fetchRemote(int shelf) async {
    final result = await ApiService.instance.getBookshelf(classId: shelf);
    switch (result) {
      case Success():
        return result.data;
      case Error():
        throw StateError('Bookshelf request failed: ${result.error}');
    }
  }

  Future<void> refreshAll() => _refresh(List.generate(6, (index) => index));

  Future<void> refreshShelf(int shelf) {
    RangeError.checkValidIndex(shelf, _revisions);
    return _refresh([shelf]);
  }

  Future<void> _refresh(List<int> shelves) async {
    final generation = _session.generation;
    if (!_session.isCurrent(generation)) throw const SessionChanged();
    final revisions = {for (final shelf in shelves) shelf: ++_revisions[shelf]};
    final snapshots = await Future.wait(shelves.map((shelf) async => Parser.getBookshelf(await _fetch(shelf), shelf)));
    final rows = snapshots
        .expand(
          (snapshot) => snapshot.list.map(
            (book) => BookshelfEntityData(aid: book.aid, bid: book.bid, url: book.url, title: book.title, img: book.img, classId: snapshot.classId),
          ),
        )
        .toList();
    if (rows.map((row) => row.aid).toSet().length != rows.length) {
      throw const FormatException('Duplicate novel across shelves');
    }
    await _session.serialize(() async {
      if (!_session.isCurrent(generation)) throw const SessionChanged();
      // A newer overlapping request makes this complete snapshot obsolete.
      if (shelves.any((shelf) => revisions[shelf] != _revisions[shelf])) {
        throw StateError('Bookshelf refresh superseded');
      }
      await (_database ?? AppDatabase.instance).replaceBookshelf(rows, classId: shelves.length == 1 ? shelves.single.toString() : null);
    });
  }
}
