import 'dart:async';

import '../../base/paged_list_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hikari_novel_flutter/models/novel_cover.dart';
import 'package:hikari_novel_flutter/models/page_state.dart';
import 'package:hikari_novel_flutter/models/resource.dart';
import 'package:hikari_novel_flutter/parser/parser.dart';

import '../../common/database/database.dart';
import '../../service/api_service.dart';

class SearchController extends PagedListController<NovelCover> {
  SearchController({required this.author}) : super(initialState: PageState.pleaseSelect, autoLoad: false);

  final String? author;

  final keywordController = TextEditingController();

  RxInt searchMode = 0.obs;
  RxList<String> searchHistory = RxList();

  StreamSubscription? _historySubscription;
  Worker? _modeWorker;

  @override
  void onInit() {
    super.onInit();
    var previousKeyword = keywordController.text;
    keywordController.addListener(() {
      if (previousKeyword != keywordController.text) {
        previousKeyword = keywordController.text;
        invalidateQuery();
      }
    });
    _modeWorker = ever(searchMode, (_) => invalidateQuery());
  }

  @override
  void onReady() {
    super.onReady();

    _historySubscription = AppDatabase.instance.getAllSearchHistory().listen((sh) => searchHistory.assignAll(sh.reversed.map((e) => e.keyword)));

    checkIsAuthorSearch(author);
  }

  void checkIsAuthorSearch(String? author) {
    if (author != null) {
      keywordController.text = author;
      searchMode.value = 1;
      getPage(false);
    }
  }

  void searchFromHistory(String keyword) {
    keywordController.text = keyword;
    keywordController.selection = TextSelection.fromPosition(TextPosition(offset: keywordController.text.length));
    getPage(false);
    Get.focusScope?.unfocus();
  }

  @override
  Object get queryKey => (keywordController.text, searchMode.value);

  @override
  Future<Resource> getData(int index) {
    _rateLimited = false;
    final keyword = keywordController.text;
    final mode = searchMode.value;
    if (index == 1) {
      // Search history is independent of the network request; catch write errors.
      AppDatabase.instance.upsertSearchHistory(SearchHistoryEntityData(keyword: keyword)).catchError((Object _) {});
    }
    return mode == 0
        ? ApiService.instance.searchNovelByTitle(title: keyword, index: index)
        : ApiService.instance.searchNovelByAuthor(author: keyword, index: index);
  }

  @override
  PageState get emptyState => PageState.empty;

  bool _rateLimited = false;

  @override
  PageState get failureState => _rateLimited ? PageState.inFiveSecond : PageState.error;

  @override
  List<NovelCover> getParser(String html) {
    _rateLimited = Parser.isError(html);
    if (_rateLimited) throw StateError('search_too_quickly_tip'.tr);
    final onlyOne = Parser.isSearchResultOnlyOne(html);
    return onlyOne != null ? [onlyOne] : Parser.parseToList(html);
  }

  @override
  int getMaxPage(String html) => Parser.isSearchResultOnlyOne(html) != null ? 1 : Parser.getMaxNum(html);

  @override
  void onClose() {
    _historySubscription?.cancel();
    _modeWorker?.dispose();
    keywordController.dispose();
    super.onClose();
  }
}
