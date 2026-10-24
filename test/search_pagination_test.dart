import 'dart:async';

import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hikari_novel_flutter/models/resource.dart';
import 'package:hikari_novel_flutter/pages/search/controller.dart';

class ControlledSearch extends SearchController {
  ControlledSearch() : super(author: null);
  final pending = <Completer<Resource>>[];
  @override
  Future<Resource> getData(int index) {
    final response = Completer<Resource>();
    pending.add(response);
    return response.future;
  }
}

const singleBook = '''
<div id="content"><div><div style="margin:0px auto;overflow:hidden;">
<span>book</span><span><a href="?bid=42">read</a></span>
</div></div><table><tr><td><span><b>One book</b></span></td></tr></table>
<img src="https://example.com/42.jpg"></div>
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('actual search single-book parsing commits once and stale failures are ignored', () async {
    final c = ControlledSearch();
    final old = c.getPage(false);
    c.keywordController.text = 'new';
    final current = c.getPage(false);
    c.pending[1].complete(const Success(singleBook));
    expect(await current, IndicatorResult.noMore);
    expect(c.data.single.title, 'One book');
    expect(c.data.single.aid, '42');
    c.pending[0].complete(const Error('late'));
    await old;
    expect(c.errorMsg, isEmpty);
    expect(await c.getPage(true), IndicatorResult.noMore);
    c.onClose();
  });

  test('actual search parser failure keeps the existing single-book result', () async {
    final c = ControlledSearch();
    final initial = c.getPage(false);
    c.pending.last.complete(const Success(singleBook));
    await initial;
    final malformed = c.getPage(false);
    c.pending.last.complete(const Success('<html>unrecognized page</html>'));
    expect(await malformed, IndicatorResult.fail);
    expect(c.data.single.aid, '42');
    expect(c.errorMsg, isNotEmpty);
    c.onClose();
  });
}
