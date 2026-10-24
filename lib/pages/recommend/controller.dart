import 'package:easy_refresh/easy_refresh.dart';
import 'package:get/get.dart';
import 'package:hikari_novel_flutter/models/page_state.dart';

import '../../service/session_service.dart';
import '../../models/recommend_block.dart';
import '../../models/resource.dart';
import '../../service/api_service.dart';
import '../../parser/parser.dart';

class RecommendController extends GetxController {
  RecommendController({Future<Resource> Function()? fetch, SessionCoordinator? session})
    : _fetch = fetch ?? (() => ApiService.instance.getRecommend()),
      _session = session ?? SessionCoordinator.instance;
  final Future<Resource> Function() _fetch;
  final SessionCoordinator _session;
  int _generation = 0;
  final RxList<RecommendBlock> data = RxList();

  Rx<PageState> pageState = Rx(PageState.loading);
  String errorMsg = "";

  @override
  void onReady() {
    super.onReady();
    getRecommend();
  }

  Future<IndicatorResult> getRecommend() async {
    final generation = ++_generation;
    final session = _session.generation;
    bool current() => !isClosed && generation == _generation && _session.isCurrent(session);
    if (!current()) return IndicatorResult.fail;
    if (data.isEmpty) pageState.value = PageState.loading;
    try {
      final result = await _fetch();
      if (!current()) return IndicatorResult.fail;
      if (result case Error()) throw StateError('Recommendation request failed');
      final parsed = Parser.getRecommend(result.data as String);
      data.assignAll(parsed);
      errorMsg = '';
      pageState.value = PageState.success;
      return IndicatorResult.success;
    } catch (error) {
      if (current()) {
        errorMsg = error.toString();
        pageState.value = PageState.error;
      }
      return IndicatorResult.fail;
    }
  }
}
