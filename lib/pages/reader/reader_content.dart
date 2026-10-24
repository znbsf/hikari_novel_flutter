import 'dart:io';
import 'package:flutter/foundation.dart';

import '../../common/app_paths.dart';
import '../../models/content.dart';
import '../../models/resource.dart';
import '../../parser/parser.dart';
import '../../service/api_service.dart';

/// Reads one fixed chapter identity, independent of navigation state.
typedef ChapterReader = Future<Content> Function(String aid, String cid);

Future<Content> readReaderChapter(String aid, String cid, {File? cachedFile, Future<Resource> Function()? fetchContent}) async {
  final file = cachedFile ?? AppPaths.cachedChapterFile(aid, cid);
  try {
    if (await file.exists()) return await compute(Parser.getContent, await file.readAsString());
  } on FormatException {
    // Keep incompatible legacy cache files for recovery; try the current source.
  } on FileSystemException {
    // An unreadable local file must not prevent an otherwise valid network read.
  }
  final result = await (fetchContent?.call() ?? ApiService.instance.getNovelContent(aid: aid, cid: cid));
  switch (result) {
    case Success():
      return compute(Parser.getContent, result.data as String);
    case Error():
      throw result.error ?? StateError('Chapter request failed');
  }
}
