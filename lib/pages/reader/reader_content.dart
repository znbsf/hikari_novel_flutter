import 'package:flutter/foundation.dart';

import '../../common/app_paths.dart';
import '../../models/content.dart';
import '../../models/resource.dart';
import '../../parser/parser.dart';
import '../../service/api_service.dart';

/// Reads one fixed chapter identity, independent of navigation state.
typedef ChapterReader = Future<Content> Function(String aid, String cid);

Future<Content> readReaderChapter(String aid, String cid) async {
  final file = AppPaths.cachedChapterFile(aid, cid);
  if (await file.exists()) {
    return compute(Parser.getContent, await file.readAsString());
  }
  final result = await ApiService.instance.getNovelContent(aid: aid, cid: cid);
  switch (result) {
    case Success():
      return compute(Parser.getContent, result.data as String);
    case Error():
      throw result.error ?? StateError('Chapter request failed');
  }
}
