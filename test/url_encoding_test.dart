import 'package:enough_convert/enough_convert.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hikari_novel_flutter/common/extension.dart';

void main() {
  for (final sample in <({String text, String extension, String inline})>[
    (text: '发表书评', extension: '%B7%A2%B1%ED%CA%E9%C6%C0', inline: '%B7%A2%B1%ED%CA%E9%C6%C0'),
    (text: '發表書評', extension: '%B0l%B1%ED%95%F8%D4u', inline: '%B0%6C%B1%ED%95%F8%D4%75'),
    (text: 'abc 测试 123', extension: 'abc %B2%E2%CA%D4 123', inline: '%61%62%63%20%B2%E2%CA%D4%20%31%32%33'),
  ]) {
    test('GBK：${sample.text}', () {
      expect(sample.text.gbkUrlEncodingIfNotAscii(), sample.extension);
      expect(GbkEncoder().convert(sample.text).map((b) => '%${b.toRadixString(16).padLeft(2, '0').toUpperCase()}').join(), sample.inline);
    });
  }

  test('Big5：發表書評', () {
    expect('發表書評'.big5UrlEncodingIfNotAscii(), '%B5o%AA%ED%AE%D1%B5%FB');
    expect(Big5Encoder().convert('發表書評').map((b) => '%${b.toRadixString(16).padLeft(2, '0').toUpperCase()}').join(), '%B5%6F%AA%ED%AE%D1%B5%FB');
  });

  for (final text in ['发表书评', 'abc 测试 123']) {
    test('Big5 不支持的简体字符：$text', () {
      expect(() => text.big5UrlEncodingIfNotAscii(), throwsFormatException);
      expect(() => Big5Encoder().convert(text).map((b) => '%${b.toRadixString(16).padLeft(2, '0').toUpperCase()}').join(), throwsFormatException);
    });
  }
}
