import 'package:easy_refresh/easy_refresh.dart';
import 'package:get/get.dart';
import 'package:hikari_novel_flutter/models/page_state.dart';
import 'package:hikari_novel_flutter/models/resource.dart';

import '../../base/paged_list_controller.dart';
import '../../models/novel_cover.dart';
import '../../parser/parser.dart';
import '../../service/api_service.dart';

class CategoryController extends PagedListController<NovelCover> {
  CategoryController() : super(initialState: PageState.pleaseSelect, autoLoad: false);

  final EasyRefreshController easyRefreshController = EasyRefreshController();

  RxString category = "please_select".tr.obs;
  RxString sortText = "please_select".tr.obs;
  String sortValue = "";

  Worker? _filterWorker;

  @override
  void onClose() {
    _filterWorker?.dispose();
    easyRefreshController.dispose();
    super.onClose();
  }

  @override
  void onInit() {
    super.onInit();

    //监听参数变化
    _filterWorker = everAll([category, sortText], (_) {
      invalidateQuery();
      if (category.value != "please_select".tr && sortText.value != "please_select".tr) {
        easyRefreshController.callRefresh(force: true);
      }
    });
  }

  @override
  Object get queryKey => (category.value, sortText.value, sortValue);

  @override
  Future<Resource> getData(int index) => ApiService.instance.getNovelByCategory(category: category.value, sort: sortValue, index: index);

  @override
  List<NovelCover> getParser(String html) => Parser.parseToList(html);
}
