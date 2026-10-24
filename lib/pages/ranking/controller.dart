import 'package:easy_refresh/easy_refresh.dart';
import 'package:get/get.dart';
import 'package:hikari_novel_flutter/base/paged_list_controller.dart';
import 'package:hikari_novel_flutter/models/page_state.dart';

import '../../models/novel_cover.dart';
import '../../models/resource.dart';
import '../../parser/parser.dart';
import '../../service/api_service.dart';

class RankingController extends PagedListController<NovelCover> {
  RankingController() : super(initialState: PageState.pleaseSelect, autoLoad: false);

  final EasyRefreshController easyRefreshController = EasyRefreshController();

  RxString ranking = "please_select".tr.obs;
  RxString arg = "".obs;

  @override
  void onInit() {
    super.onInit();
    //监听参数变化
    ever(arg, (value) {
      easyRefreshController.callRefresh(force: true);
    });
  }

  @override
  Future<Resource> getData(int index) => ApiService.instance.getNovelByRanking(ranking: arg.value, index: index);

  @override
  List<NovelCover> getParser(String html) => Parser.parseToList(html);
}
