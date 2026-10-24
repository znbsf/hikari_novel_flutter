import 'package:hikari_novel_flutter/base/paged_list_controller.dart';

import '../../models/novel_cover.dart';
import '../../models/resource.dart';
import '../../parser/parser.dart';
import '../../service/api_service.dart';

class CompletionController extends PagedListController<NovelCover> {
  @override
  Future<Resource> getData(int index) {
    return ApiService.instance.getCompletionNovel(index: index);
  }

  @override
  List<NovelCover> getParser(String html) {
    return Parser.parseToList(html);
  }
}
