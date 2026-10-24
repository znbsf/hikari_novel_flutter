import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hikari_novel_flutter/models/novel_detail.dart';
import 'package:hikari_novel_flutter/models/novel_cover.dart';
import 'package:hikari_novel_flutter/models/page_state.dart';
import 'package:hikari_novel_flutter/models/recommend_block.dart';
import 'package:hikari_novel_flutter/models/resource.dart';
import 'package:hikari_novel_flutter/pages/novel_detail/controller.dart';
import 'package:hikari_novel_flutter/pages/recommend/controller.dart';
import 'package:hikari_novel_flutter/pages/user_bookshelf/controller.dart';
import 'package:hikari_novel_flutter/pages/reader/reader_content.dart';
import 'package:hikari_novel_flutter/parser/parse_exception.dart';
import 'package:hikari_novel_flutter/service/session_service.dart';

NovelDetail detail(String title) => NovelDetail(title, 'author', '', '', '', '', [], '', '', false);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('detail parse failure uses previous cached detail without writing', () async {
    var writes = 0;
    final controller = NovelDetailController(
      aid: '1',
      session: SessionCoordinator(),
      fetchDetail: (_) async => throw const ParseException('catalogue', 'table missing'),
      readCache: (_) async => detail('cached').toString(),
      saveDetail: (_, _) async {
        writes++;
      },
      checkShelf: (_) async => false,
    );
    await controller.getNovelDetail();
    expect(controller.novelDetail.value!.title, 'cached');
    expect(controller.pageState.value, PageState.success);
    expect(writes, 0);
    controller.onClose();
  });

  test('damaged detail cache produces retryable error without deletion or write', () async {
    var writes = 0;
    final controller = NovelDetailController(
      aid: '1',
      session: SessionCoordinator(),
      fetchDetail: (_) async => throw const FormatException('invalid response'),
      readCache: (_) async => '{broken',
      saveDetail: (_, _) async {
        writes++;
      },
      checkShelf: (_) async => false,
    );
    await controller.getNovelDetail();
    expect(controller.pageState.value, PageState.error);
    expect(writes, 0);
    controller.onClose();
  });

  test('out of order detail refresh cannot publish or cache old result', () async {
    final requests = <Completer<NovelDetail>>[];
    final saved = <String>[];
    final controller = NovelDetailController(
      aid: '1',
      session: SessionCoordinator(),
      fetchDetail: (_) {
        final next = Completer<NovelDetail>();
        requests.add(next);
        return next.future;
      },
      readCache: (_) async => null,
      saveDetail: (_, value) async {
        saved.add(value.title);
      },
      checkShelf: (_) async => true,
    );
    final old = controller.getNovelDetail();
    final current = controller.getNovelDetail();
    requests.last.complete(detail('current'));
    await current;
    requests.first.complete(detail('old'));
    await old;
    expect(controller.novelDetail.value!.title, 'current');
    expect(saved, ['current']);
    controller.onClose();
  });

  test('detail persistence failure retains existing good state', () async {
    final controller = NovelDetailController(
      aid: '1',
      session: SessionCoordinator(),
      fetchDetail: (_) async => detail('new'),
      readCache: (_) async => null,
      saveDetail: (_, _) async => throw StateError('disk full'),
      checkShelf: (_) async => false,
    );
    controller.novelDetail.value = detail('old');
    await controller.getNovelDetail();
    expect(controller.novelDetail.value!.title, 'old');
    expect(controller.pageState.value, PageState.error);
    controller.onClose();
  });

  test('closed detail controller ignores pending data and cannot persist', () async {
    final response = Completer<NovelDetail>();
    var writes = 0;
    final controller = NovelDetailController(
      aid: '1',
      session: SessionCoordinator(),
      fetchDetail: (_) => response.future,
      readCache: (_) async => null,
      saveDetail: (_, _) async {
        writes++;
      },
      checkShelf: (_) async => false,
    );
    final loading = controller.getNovelDetail();
    controller.onClose();
    response.complete(detail('late'));
    await loading;
    expect(controller.novelDetail.value, isNull);
    expect(writes, 0);
  });

  test('recommendation parser error preserves existing cards', () async {
    final controller = RecommendController(fetch: () async => Success('<div>invalid</div>'), session: SessionCoordinator());
    controller.data.add(RecommendBlock('old', [NovelCover('book', '', '1')]));
    await controller.getRecommend();
    expect(controller.data.single.title, 'old');
    expect(controller.pageState.value, PageState.error);
  });

  test('user bookshelf parser error preserves old list', () async {
    final controller = UserBookshelfController(uid: '1', fetch: (_) async => Success('<div>invalid</div>'), session: SessionCoordinator());
    controller.list.value = [NovelCover('old', '', '1')];
    await controller.getPage();
    expect(controller.list.value!.single.title, 'old');
    expect(controller.pageState.value, PageState.error);
  });

  test('invalid legacy chapter tries network but retains local file', () async {
    final dir = await Directory.systemTemp.createTemp('hikari-parse-cache-');
    try {
      final file = File('${dir.path}/1_2.txt');
      await file.writeAsString('<div>old incompatible format</div>');
      final result = await readReaderChapter('1', '2', cachedFile: file, fetchContent: () async => Success('<div id="content">current chapter</div>'));
      expect(result.text, 'current chapter');
      expect(await file.readAsString(), '<div>old incompatible format</div>');
      await expectLater(readReaderChapter('1', '2', cachedFile: file, fetchContent: () async => const Error('offline')), throwsA(anything));
      expect(await file.exists(), true);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
