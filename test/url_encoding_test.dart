import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:hikari_novel_flutter/models/common/language.dart';
import 'package:hikari_novel_flutter/models/resource.dart';
import 'package:hikari_novel_flutter/service/api_service.dart';
import 'package:hikari_novel_flutter/service/local_storage_service.dart';
import 'package:hive_ce/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late LocalStorageService storage;
  late ApiService api;
  late RequestOptions request;
  late Uint8List responseBytes;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('hikari-encoding-test-');
    storage = Get.put(LocalStorageService());
    await storage.init(hivePath: directory.path);
    responseBytes = Uint8List(0);
    api = ApiService();
    api.dio.interceptors.insert(
      0,
      InterceptorsWrapper(onRequest: (options, handler) {
        request = options;
        handler.resolve(Response(requestOptions: options, data: responseBytes, statusCode: 200));
      }),
    );
  });

  tearDown(() async {
    api.dio.close();
    Get.reset();
    await Hive.close();
    Hive.resetAdapters();
    await directory.delete(recursive: true);
  });

  Future<String> encode(String text, {bool big5 = false, bool asciiPassthrough = false}) async {
    storage.language.value = big5 ? Language.traditionalChinese : Language.simplifiedChinese;
    if (asciiPassthrough) {
      await api.sendReply(aid: '1', rid: '2', content: text);
      final body = request.data as String;
      return body.substring('pcontent='.length, body.indexOf('&Submit='));
    }
    await api.searchNovelByTitle(title: text, index: 1);
    return request.path.split('searchkey=')[1].split('&page=')[0];
  }

  for (final sample in <({String text, String extension, String inline})>[
    (text: '发表书评', extension: '%B7%A2%B1%ED%CA%E9%C6%C0', inline: '%B7%A2%B1%ED%CA%E9%C6%C0'),
    (text: '發表書評', extension: '%B0l%B1%ED%95%F8%D4u', inline: '%B0%6C%B1%ED%95%F8%D4%75'),
    (text: 'abc 测试 123', extension: 'abc %B2%E2%CA%D4 123', inline: '%61%62%63%20%B2%E2%CA%D4%20%31%32%33'),
  ]) {
    test('GBK：${sample.text}', () async {
      expect(await encode(sample.text, asciiPassthrough: true), sample.extension);
      expect(await encode(sample.text), sample.inline);
    });
  }

  test('Big5：發表書評', () async {
    expect(await encode('發表書評', big5: true, asciiPassthrough: true), '%B5o%AA%ED%AE%D1%B5%FB');
    expect(await encode('發表書評', big5: true), '%B5%6F%AA%ED%AE%D1%B5%FB');
  });

  for (final text in ['发表书评', 'abc 测试 123']) {
    test('Big5 不支持的简体字符：$text', () {
      expect(() => encode(text, big5: true, asciiPassthrough: true), throwsFormatException);
      expect(() => encode(text, big5: true), throwsFormatException);
    });
  }

  for (final sample in [
    (
      language: Language.simplifiedChinese,
      submit: '%B7%A2%B1%ED%CA%E9%C6%C0',
      content: '%B7%A2%B1%ED%CA%E9%C6%C0',
      text: '发表书评',
      bytes: [0xB7, 0xA2, 0xB1, 0xED, 0xCA, 0xE9, 0xC6, 0xC0],
    ),
    (
      language: Language.traditionalChinese,
      submit: '%B5%6F%AA%ED%AE%D1%B5%FB',
      content: '%B5o%AA%ED%AE%D1%B5%FB',
      text: '發表書評',
      bytes: [0xB5, 0x6F, 0xAA, 0xED, 0xAE, 0xD1, 0xB5, 0xFB],
    ),
  ]) {
    test('书评和回复保留字段顺序、ASCII 和提交文字：${sample.language}', () async {
      storage.language.value = sample.language;
      responseBytes = Uint8List.fromList(sample.bytes);
      final comment = await api.sendComment(aid: '1', title: 'ASCII +&=', content: sample.text);
      expect(request.path, endsWith('/modules/article/reviews.php?aid=1'));
      expect(request.data, 'ptitle=ASCII +&=&pcontent=${sample.content}&Submit=+${sample.submit}+');
      expect((comment as Success).data, sample.text);

      final reply = await api.sendReply(aid: '1', rid: '2', content: 'ASCII +&=');
      expect(request.path, endsWith('/modules/article/reviewshow.php?rid=2&aid=1'));
      expect(request.data, 'pcontent=ASCII +&=&Submit=+${sample.submit}+');
      expect((reply as Success).data, sample.text);

      final page = await api.searchNovelByAuthor(author: sample.text, index: 1);
      expect((page as Success).data, sample.text);
    });
  }
}
