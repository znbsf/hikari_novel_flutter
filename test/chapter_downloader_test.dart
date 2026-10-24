import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:enough_convert/enough_convert.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hikari_novel_flutter/models/common/charset_type.dart';
import 'package:hikari_novel_flutter/service/chapter_downloader_service.dart';
import 'package:hikari_novel_flutter/service/site_response.dart';

const chapter = '<html><div id="content">章节正文</div></html>';

void main() {
  late Directory directory;
  late Dio dio;
  late ChapterDownloaderService downloader;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('chapter-test-');
    dio = Dio();
    downloader = ChapterDownloaderService(dio: dio, cacheDirectory: directory, node: () => 'https://example.test', charset: () => CharsetType.gbk);
  });
  tearDown(() async {
    dio.close(force: true);
    await directory.delete(recursive: true);
  });

  void respond(String body, {int status = 200, Map<String, List<String>>? headers}) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response<List<int>>(requestOptions: options, data: GbkEncoder().convert(body), statusCode: status, headers: Headers.fromMap(headers ?? {})),
          );
        },
      ),
    );
  }

  test('replaces existing HTML cache and cleans staging', () async {
    final file = File('${directory.path}/1_2.txt');
    await file.writeAsString('old');
    respond(chapter);
    expect(await downloader.download(taskId: 't', aid: '1', cid: '2'), file.path);
    expect(await file.readAsString(), chapter);
    expect(await directory.list().length, 1);
    expect(downloader.isDownloading('t'), false);
  });

  for (final body in [
    '<div>error</div>',
    '<div id="content"></div>',
    '<form action="login.php"><input type="password"></form>',
    '<div id="content"><form>Error</form></div>',
    '<div id="content"><div class="error">章节不存在</div></div>',
    '<title>Just a moment...</title>',
  ]) {
    test('invalid response preserves old cache: $body', () async {
      final file = File('${directory.path}/1_2.txt');
      await file.writeAsString(chapter);
      respond(body);
      await expectLater(downloader.download(taskId: 't', aid: '1', cid: '2'), throwsFormatException);
      expect(await file.readAsString(), chapter);
      expect(await directory.list().length, 1);
    });
  }

  test('HTTP errors never overwrite cache', () async {
    final file = File('${directory.path}/1_2.txt');
    await file.writeAsString(chapter);
    respond(chapter, status: 500);
    await expectLater(downloader.download(taskId: 't', aid: '1', cid: '2'), throwsStateError);
    expect(await file.readAsString(), chapter);
  });

  test('captures charset and node while request waits', () async {
    var charset = CharsetType.gbk;
    var node = 'https://example.test';
    downloader = ChapterDownloaderService(dio: dio, cacheDirectory: directory, node: () => node, charset: () => charset);
    final entered = Completer<void>();
    final release = Completer<void>();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          entered.complete();
          await release.future;
          expect(options.uri.host, 'example.test');
          expect(options.uri.queryParameters['charset'], 'gbk');
          handler.resolve(Response<List<int>>(requestOptions: options, data: GbkEncoder().convert(chapter), statusCode: 200));
        },
      ),
    );
    final result = downloader.download(taskId: 't', aid: '1', cid: '2');
    await entered.future;
    charset = CharsetType.big5Hkscs;
    node = 'https://other.test';
    release.complete();
    expect(await File(await result).readAsString(), chapter);
  });

  test('cancel keeps active ownership, rejects collisions, then permits retry', () async {
    final old = File('${directory.path}/1_2.txt');
    await old.writeAsString('<div id="content">old valid chapter</div>');
    final entered = Completer<void>();
    final release = Completer<void>();
    var requests = 0;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          requests++;
          if (requests == 1) {
            entered.complete();
            await release.future;
          }
          handler.resolve(Response<List<int>>(requestOptions: options, data: GbkEncoder().convert(chapter), statusCode: 200));
        },
      ),
    );
    final first = downloader.download(taskId: 't', aid: '1', cid: '2');
    final failure = expectLater(first, throwsA(isA<Exception>()));
    await entered.future;
    downloader.clearCancel('t');
    await expectLater(downloader.download(taskId: 't', aid: '1', cid: '3'), throwsStateError);
    await expectLater(downloader.download(taskId: 'other', aid: '1', cid: '2'), throwsStateError);
    downloader.cancel('t');
    release.complete();
    await failure;
    expect(await old.readAsString(), '<div id="content">old valid chapter</div>');
    expect(await directory.list().length, 1);
    expect(await File(await downloader.download(taskId: 't', aid: '1', cid: '2')).readAsString(), chapter);
    expect(requests, 2);
  });

  test('rejects path traversal before creating files', () async {
    await expectLater(downloader.download(taskId: 't', aid: '../1', cid: '2'), throwsArgumentError);
    expect(await directory.list().length, 0);
  });

  test('redirects resolve relative to fixed URI and retain charset', () async {
    final seen = <Uri>[];
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          seen.add(options.uri);
          handler.resolve(
            Response<List<int>>(
              requestOptions: options,
              data: GbkEncoder().convert(chapter),
              statusCode: seen.length == 1 ? 302 : 200,
              headers: Headers.fromMap(
                seen.length == 1
                    ? {
                        'location': ['next.php?aid=1&cid=2'],
                      }
                    : {},
              ),
            ),
          );
        },
      ),
    );
    await downloader.download(taskId: 't', aid: '1', cid: '2');
    expect(seen.last.path, '/modules/article/next.php');
    expect(seen.last.queryParameters['charset'], 'gbk');
  });

  test('cross origin redirect and missing location fail closed', () async {
    respond(
      '',
      status: 302,
      headers: {
        'location': ['https://other.test/login'],
      },
    );
    await expectLater(downloader.download(taskId: 't', aid: '1', cid: '2'), throwsFormatException);
    dio.interceptors.clear();
    respond('', status: 302);
    await expectLater(downloader.download(taskId: 't', aid: '1', cid: '2'), throwsFormatException);
  });

  for (final title in ['出现错误！', '出現錯誤！']) {
    test('explicit site error block is rejected: $title', () {
      expect(() => SiteResponse.validateChapter('<div id="content"><div class="blocktitle">$title</div>章节不存在</div>'), throwsFormatException);
    });
  }

  test('cancel during candidate write preserves old cache and clears staging', () async {
    final old = File('${directory.path}/1_2.txt');
    await old.writeAsString(chapter);
    final writing = Completer<void>();
    final release = Completer<void>();
    downloader = ChapterDownloaderService(
      dio: dio,
      cacheDirectory: directory,
      node: () => 'https://example.test',
      charset: () => CharsetType.gbk,
      writeCandidate: (file, content) async {
        await file.writeAsString(content, flush: true);
        writing.complete();
        await release.future;
      },
    );
    respond('<div id="content">new chapter</div>');
    final result = downloader.download(taskId: 't', aid: '1', cid: '2');
    final failure = expectLater(result, throwsA(isA<Exception>()));
    await writing.future;
    downloader.cancel('t');
    release.complete();
    await failure;
    expect(await old.readAsString(), chapter);
    expect(await directory.list().length, 1);
    expect(downloader.isDownloading('t'), false);
  });

  for (final charset in CharsetType.values) {
    test('redirect preserves raw query bytes for $charset', () async {
      final seen = <Uri>[];
      const raw = '%B7%A2%B1%ED%6C%61';
      final paths = <String>[];
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            seen.add(options.uri);
            paths.add(options.path);
            final data = charset == CharsetType.gbk ? GbkEncoder().convert(chapter) : Big5Encoder().convert('<div id="content">正文</div>');
            handler.resolve(
              Response<List<int>>(
                requestOptions: options,
                data: data,
                statusCode: seen.length == 1 ? 302 : 200,
                headers: Headers.fromMap(
                  seen.length == 1
                      ? {
                          'location': ['next.php?searchkey=$raw'],
                        }
                      : {},
                ),
              ),
            );
          },
        ),
      );
      await SiteResponse.get(dio, SiteResponse.withCharset('https://example.test/start', charset), charset, chapter: true);
      expect(paths.last, 'https://example.test/next.php?searchkey=$raw&charset=${charset == CharsetType.gbk ? 'gbk' : 'big5'}');
    });
  }

  test('normal dialogue and sidebar login do not reject a chapter', () {
    expect(
      () => SiteResponse.validateChapter('<aside><form action="login.php"><input type="password"></form></aside><div id="content">对不起，我来迟了。错误只是一次意外。</div>'),
      returnsNormally,
    );
  });

  for (final phase in ['write', 'rename']) {
    test('$phase failure preserves old cache and removes staging', () async {
      final file = File('${directory.path}/1_2.txt');
      await file.writeAsString(chapter);
      downloader = ChapterDownloaderService(
        dio: dio,
        cacheDirectory: directory,
        node: () => 'https://example.test',
        charset: () => CharsetType.gbk,
        writeCandidate: phase == 'write'
            ? (candidate, content) async {
                await candidate.writeAsString('partial');
                throw const FileSystemException('write failed');
              }
            : null,
        commitCandidate: phase == 'rename'
            ? (candidate, destination) {
                throw const FileSystemException('rename failed');
              }
            : null,
      );
      respond(chapter);
      await expectLater(downloader.download(taskId: 't', aid: '1', cid: '2'), throwsA(isA<FileSystemException>()));
      expect(await file.readAsString(), chapter);
      expect(await directory.list().length, 1);
    });
  }

  test('cleanup failure does not change successful commit into failure', () async {
    downloader = ChapterDownloaderService(
      dio: dio,
      cacheDirectory: directory,
      node: () => 'https://example.test',
      charset: () => CharsetType.gbk,
      cleanStaging: (_) async {
        throw const FileSystemException('cleanup failed');
      },
    );
    respond(chapter);
    final path = await downloader.download(taskId: 't', aid: '1', cid: '2');
    expect(await File(path).readAsString(), chapter);
    expect(downloader.isDownloading('t'), false);
  });

  test('initial GET keeps percent-encoded ASCII in request path', () async {
    String? path;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          path = options.path;
          handler.resolve(Response<List<int>>(requestOptions: options, data: GbkEncoder().convert(chapter), statusCode: 200));
        },
      ),
    );
    await SiteResponse.get(dio, SiteResponse.withCharset('https://example.test/search.php?searchkey=%61%62%63%20%6C', CharsetType.gbk), CharsetType.gbk);
    expect(path, 'https://example.test/search.php?searchkey=%61%62%63%20%6C&charset=gbk');
  });

  test('charset addition preserves non UTF-8 query escapes', () {
    final uri = SiteResponse.withCharset('https://example.test/search.php?searchkey=%B7%A2%B1%ED', CharsetType.gbk);
    expect(uri, 'https://example.test/search.php?searchkey=%B7%A2%B1%ED&charset=gbk');
  });

  test('illustration-only chapter is valid', () {
    expect(() => SiteResponse.validateChapter('<div id="content"><img src="image.jpg"></div>'), returnsNormally);
  });
}
