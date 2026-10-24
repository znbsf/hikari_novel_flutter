import 'package:dio/dio.dart';
import 'package:enough_convert/enough_convert.dart';
import 'package:html/parser.dart' as html;

import '../models/common/charset_type.dart';

/// A request keeps its origin and charset even when app preferences change.
class SiteResponse {
  static String withCharset(String url, CharsetType charset) {
    // Uri normalizes percent-encoded ASCII (e.g. %6C to l), so retain raw text.
    final fragment = url.indexOf('#');
    final address = fragment < 0 ? url : url.substring(0, fragment);
    final question = address.indexOf('?');
    final path = question < 0 ? address : address.substring(0, question);
    final query = (question < 0 ? '' : address.substring(question + 1)).split('&').where((part) => part.isNotEmpty && !part.startsWith('charset=')).join('&');
    final value = charset == CharsetType.gbk ? 'gbk' : 'big5';
    return '$path?${query.isEmpty ? '' : '$query&'}charset=$value';
  }

  static String _rawQuery(String url) {
    final address = url.split('#').first;
    final question = address.indexOf('?');
    return question < 0 ? '' : address.substring(question + 1);
  }

  static Future<String> get(
    Dio dio,
    String url,
    CharsetType charset, {
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
    bool chapter = false,
  }) async {
    final origin = Uri.parse(url);
    final visited = <Uri>{};
    for (var hop = 0; hop < 6; hop++) {
      final uri = Uri.parse(url);
      if (!visited.add(uri)) throw const FormatException('Redirect loop');
      if (cancelToken?.isCancelled ?? false) throw cancelToken!.cancelError!;
      final response = await dio.get<List<int>>(
        url,
        cancelToken: cancelToken,
        onReceiveProgress: onReceiveProgress,
        options: Options(responseType: ResponseType.bytes, followRedirects: false, validateStatus: (_) => true),
      );
      if (cancelToken?.isCancelled ?? false) throw cancelToken!.cancelError!;
      final status = response.statusCode ?? 0;
      if (status >= 300 && status < 400) {
        final location = response.headers.value('location');
        if (location == null) throw const FormatException('Missing redirect location');
        final next = uri.resolve(location);
        if (next.scheme != origin.scheme || next.host != origin.host || next.port != origin.port || next.userInfo.isNotEmpty) {
          throw const FormatException('Cross-origin redirect refused');
        }
        // Resolve the path/origin using Uri, but preserve the location query text.
        final reference = location.split('#').first;
        final query = reference.contains('?') ? _rawQuery(location) : (reference.isEmpty ? _rawQuery(url) : '');
        final path = next.toString().split('#').first.split('?').first;
        url = withCharset('$path${query.isEmpty ? '' : '?$query'}', charset);
        continue;
      }
      if (status < 200 || status >= 300) throw StateError('HTTP $status');
      if (response.headers['cf-mitigated']?.contains('challenge') ?? false) throw const FormatException('Challenge response');
      final data = response.data;
      if (data == null) throw const FormatException('Empty response');
      final content = decode(data, charset);
      validatePage(content);
      if (chapter) validateChapter(content);
      return content;
    }
    throw const FormatException('Too many redirects');
  }

  static String decode(List<int> bytes, CharsetType charset) => switch (charset) {
    CharsetType.gbk => GbkDecoder().convert(bytes),
    CharsetType.big5Hkscs => Big5Decoder().convert(bytes),
  };

  static void validatePage(String content) {
    final document = html.parse(content);
    final body = document.getElementById('content');
    if (document.querySelectorAll('.blocktitle').any((element) => const {'出现错误！', '出現錯誤！'}.contains(element.text.trim()))) {
      throw const FormatException('Site error response');
    }
    // A sidebar login form does not turn a real chapter into a login page.
    final login = document.querySelector('form[action*="login"], input[type="password"]');
    final hasChapter =
        body != null &&
        body.querySelector('form[action*="login"], input[type="password"]') == null &&
        (body.text.trim().isNotEmpty || body.querySelector('img[src]') != null);
    if ((!hasChapter && login != null) ||
        document.querySelector('#challenge-form, script[src*="/cdn-cgi/challenge-platform/"]') != null ||
        (document.querySelector('title')?.text ?? '').toLowerCase().contains('just a moment')) {
      throw const FormatException('Login or challenge page');
    }
  }

  static void validateChapter(String content) {
    validatePage(content);
    final document = html.parse(content);
    final body = document.getElementById('content');
    if (body == null) throw const FormatException('Chapter content missing');
    body.querySelectorAll('script, style, #contentdp').forEach((e) => e.remove());
    final hasErrorTitle = body.querySelectorAll('.blocktitle').any((element) => const {'出现错误！', '出現錯誤！'}.contains(element.text.trim()));
    if (hasErrorTitle ||
        body.querySelector('form, table, .error, .errormsg, #error') != null ||
        (body.text.trim().isEmpty && body.querySelector('img[src]') == null)) {
      throw const FormatException('Invalid chapter content');
    }
  }
}
