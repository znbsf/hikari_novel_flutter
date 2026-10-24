import 'dart:async';

import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hikari_novel_flutter/base/paged_list_controller.dart';
import 'package:hikari_novel_flutter/models/page_state.dart';
import 'package:hikari_novel_flutter/models/resource.dart';
import 'package:hikari_novel_flutter/service/session_service.dart';

class ControlledPages extends PagedListController<String> {
  ControlledPages({super.session}) : super(autoLoad: false);
  String filter = 'a';
  bool throwFetch = false;
  bool throwParse = false;
  int maxPage = 3;
  final requests = <({String filter, int page, Completer<Resource> response})>[];
  @override
  Object get queryKey => filter;
  @override
  Future<Resource> getData(int index) {
    if (throwFetch) throw StateError('fetch');
    final response = Completer<Resource>();
    requests.add((filter: filter, page: index, response: response));
    return response.future;
  }

  @override
  List<String> getParser(String html) {
    if (throwParse) throw StateError('parse');
    return [html];
  }

  @override
  int getMaxPage(String html) => maxPage;
}

void main() {
  test('stale success and failure cannot replace a newer refresh or rewind its page', () async {
    final c = ControlledPages();
    final old = c.getPage(false);
    final current = c.getPage(false);
    c.requests[1].response.complete(const Success('new'));
    await current;
    c.requests[0].response.complete(const Error('old error'));
    await old;
    expect(c.data, ['new']);
    expect(c.pageState.value, PageState.success);
    final more = c.getPage(true);
    expect(c.requests.last.page, 2);
    final newer = c.getPage(false);
    c.requests.last.response.complete(const Success('newest'));
    await newer;
    c.requests[2].response.complete(const Success('old page two'));
    await more;
    expect(c.data, ['newest']);
  });

  test('concurrent load more shares a request and a failure retries the same page', () async {
    final c = ControlledPages();
    final initial = c.getPage(false);
    c.requests.last.response.complete(const Success('one'));
    await initial;
    final first = c.getPage(true);
    final second = c.getPage(true);
    expect(identical(first, second), true);
    expect(c.requests.length, 2);
    c.requests.last.response.complete(const Error('failure'));
    expect(await first, IndicatorResult.fail);
    final retry = c.getPage(true);
    expect(c.requests.last.page, 2);
    c.requests.last.response.complete(const Success('two'));
    await retry;
    expect(c.data, ['one', 'two']);
  });

  test('refresh failures retain old data and thrown transport and parser errors recover', () async {
    final c = ControlledPages();
    final initial = c.getPage(false);
    c.requests.last.response.complete(const Success('old'));
    await initial;
    c.throwFetch = true;
    expect(await c.getPage(false), IndicatorResult.fail);
    expect(c.data, ['old']);
    expect(c.pageState.value, PageState.error);
    c.throwFetch = false;
    c.throwParse = true;
    final badParse = c.getPage(false);
    c.requests.last.response.complete(const Success('invalid'));
    expect(await badParse, IndicatorResult.fail);
    expect(c.data, ['old']);
    c.throwParse = false;
    final retry = c.getPage(false);
    c.requests.last.response.complete(const Success('recovered'));
    await retry;
    expect(c.data, ['recovered']);
  });

  test('filter changes, close and session invalidation suppress late callbacks', () async {
    for (final invalidate in <void Function(ControlledPages)>[
      (c) {
        c.filter = 'b';
        c.invalidateQuery();
      },
      (c) => c.onClose(),
      (c) => c.session.invalidate(),
    ]) {
      final c = ControlledPages(session: SessionCoordinator());
      final pending = c.getPage(false);
      invalidate(c);
      final state = c.pageState.value;
      c.requests.last.response.complete(const Success('late'));
      expect(await pending, IndicatorResult.fail);
      expect(c.data, isEmpty);
      expect(c.pageState.value, state);
    }
  });

  test('failed changed query cannot append a new page to retained old-query data', () async {
    final c = ControlledPages();
    final old = c.getPage(false);
    c.requests.last.response.complete(const Success('old filter'));
    await old;
    c.filter = 'b';
    final refresh = c.getPage(false);
    c.requests.last.response.complete(const Error('new query failed'));
    await refresh;
    final retry = c.getPage(true);
    expect(c.requests.last.page, 1);
    expect(c.requests.last.filter, 'b');
    c.requests.last.response.complete(const Success('new filter'));
    await retry;
    expect(c.data, ['new filter']);
  });

  test('pages without pagination are a single page', () async {
    final c = ControlledPages()..maxPage = 0;
    final request = c.getPage(false);
    c.requests.last.response.complete(const Success('single'));
    expect(await request, IndicatorResult.noMore);
    expect(await c.getPage(true), IndicatorResult.noMore);
    expect(c.requests.length, 1);
  });
}
