import 'package:flutter_test/flutter_test.dart';
import 'package:hikari_novel_flutter/parser/parser.dart';
import 'package:hikari_novel_flutter/parser/parse_exception.dart';

void main() {
  const node = 'https://www.wenku8.net';
  const book =
      '<div style="width:373px;height:136px;float:left;margin:5px 0px 5px 5px;">'
      '<a title="Book"><img src="/images/noimg.jpg"></a>'
      '<div><a href="/book/123.htm">Book</a></div></div>';
  test('recognized list preserves fallback cover and identity', () {
    final result = Parser.parseToList('<div id="content">$book</div>', node: node);
    expect(result.single.aid, '123');
    expect(result.single.imageUrl, contains('/modules/article/images/nocover.jpg'));
  });
  test('explicit no result differs from unrecognized or partial lists', () {
    expect(Parser.parseToList('<div id="content">没有找到相关小说</div>', node: node), isEmpty);
    for (final response in [
      '<html>unknown</html>',
      '<div id="content">unknown</div>',
      '<div id="content">${book.replaceAll('title="Book"', '')}</div>',
      '<div id="content"><form action="login.php"><input type="password"></form></div>',
      '<div id="challenge-form"></div>',
      '<div id="content"><div class="blocktitle">出现错误！</div></div>',
    ]) {
      expect(() => Parser.parseToList(response, node: node), throwsA(isA<ParseException>()));
    }
  });
  test('unsafe positional parsers report sanitized typed errors', () {
    for (final parse in [Parser.getNovelDetail, Parser.getRecommend, Parser.getUserInfo]) {
      expect(() => parse('<div id="content">private account text</div>'), throwsA(isA<ParseException>()));
    }
    try {
      Parser.getNovelDetail('<div id="content">private account text</div>');
    } on ParseException catch (error) {
      expect(error.toString(), isNot(contains('private account text')));
      expect(error.source, isNull);
    }
  });
  test('chapter dialogue and sidebar login remain valid', () {
    final content = Parser.getContent(
      '<form action="login.php"><input type="password"></form>'
      '<div id="content">请先登录，这是小说中的对白。<img src="https://img.wenku8.com/a.jpg"></div>',
    );
    expect(content.text, contains('小说中的对白'));
    expect(content.images, hasLength(1));
    expect(() => Parser.getContent('<div id="content"><form action="login.php"><input type="password"></form></div>'), throwsA(isA<ParseException>()));
  });
  test('catalogue distinguishes missing shell from recognized empty table', () {
    expect(Parser.getCatalogue('<table class="css"></table>'), isEmpty);
    expect(() => Parser.getCatalogue('<div id="content">unknown</div>'), throwsA(isA<ParseException>()));
    expect(
      () => Parser.getCatalogue(
        '<table class="css"><tr><td class="vcss">Volume</td></tr>'
        '<tr><td class="ccss"><a href="read.php">Chapter</a></td></tr></table>',
      ),
      throwsA(isA<ParseException>()),
    );
  });
  test('permissions are never interpreted as empty results', () {
    expect(() => Parser.parseToList('<div id="content">没有权限</div>'), throwsA(isA<ParseException>()));
    expect(() => Parser.parseOtherBookshelfToList('<div id="centerm">没有权限</div>'), throwsA(isA<ParseException>()));
    expect(() => Parser.parseOtherBookshelfToList('<div id="centerm"><table></table></div>'), throwsA(isA<ParseException>()));
    expect(Parser.parseOtherBookshelfToList('<div id="centerm">暂无收藏</div>'), isEmpty);
  });
  test('absolute and query book links retain valid IDs', () {
    for (final href in ['https://www.wenku8.net/book/123.htm', '/modules/article/articleinfo.php?aid=123&foo=2']) {
      expect(Parser.parseToList('<div id="content">${book.replaceAll('/book/123.htm', href)}</div>', node: node).single.aid, '123');
    }
  });
  test('catalogue rejects lost chapter links and supports extra query arguments', () {
    const start = '<table class="css"><tr><td class="vcss">Volume</td></tr><tr>';
    expect(() => Parser.getCatalogue('$start<td class="ccss">Lost chapter</td></tr></table>'), throwsA(isA<ParseException>()));
    expect(
      Parser.getCatalogue(
        '$start<td class="ccss"></td><td class="ccss"><a href="read.php?cid=123&aid=2">Chapter</a></td></tr></table>',
      ).single.chapters.single.cid,
      '123',
    );
  });
  test('comments require title and core record identities', () {
    String comment(String row) => '<div id="content"><table></table><table></table><table><tr>$row</tr></table></div>';
    const valid = '<td><a href="review.php?rid=12&foo=2">Title</a></td><td>1/2</td><td><a href="userinfo.php?uid=3&foo=4">User</a></td><td>2026-10-24</td>';
    expect(Parser.getComment(comment(valid), dateFormatter: (value) => value).single.rid, '12');
    for (final row in [
      valid.replaceAll('rid=12', 'unknown=12'),
      valid.replaceAll('uid=3', 'unknown=3'),
      valid.replaceAll('>Title<', '><'),
      '<td></td><td></td><td></td><td></td>',
    ]) {
      expect(() => Parser.getComment(comment(row), dateFormatter: (value) => value), throwsA(isA<ParseException>()));
    }
  });
  test('recommend cards reject missing book identity', () {
    const style = 'float: left;text-align:center;width: 95px; height:155px;overflow:hidden;';
    for (final card in ['<a href="broken"><img src="a.jpg"></a><a>Title</a>', '<a href="/book/123.htm"><img src="a.jpg"></a><a></a>']) {
      final response =
          '<div id="centers"><div class="block"></div><div class="block"><div class="blocktitle">Title</div><div style="$style">$card</div></div></div>';
      expect(() => Parser.getRecommend(response), throwsA(isA<ParseException>()));
    }
  });
}
