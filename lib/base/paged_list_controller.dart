import 'dart:async';

import 'package:easy_refresh/easy_refresh.dart';
import 'package:get/get.dart';

import '../models/page_state.dart';
import '../models/resource.dart';
import '../parser/parser.dart';
import '../service/session_service.dart';

abstract class PagedListController<T> extends GetxController {
  PagedListController({PageState initialState = PageState.loading, this.autoLoad = true, SessionCoordinator? session})
    : pageState = Rx(initialState),
      session = session ?? SessionCoordinator.instance;

  final Rx<PageState> pageState;
  final bool autoLoad;
  final SessionCoordinator session;
  String errorMsg = '';
  int _maxNum = 1;
  int _index = 0;
  int _generation = 0;
  bool _closed = false;
  Object? _query;
  Object? _committedQuery;
  bool _hasPage = false;
  Future<IndicatorResult>? _active;
  int? _activeSession;
  final RxList<T> data = RxList();

  /// Value equality must describe every mutable request filter.
  Object? get queryKey => null;

  @override
  void onReady() {
    super.onReady();
    if (autoLoad) getPage(false);
  }

  Future<Resource> getData(int index);
  List<T> getParser(String html);
  int getMaxPage(String html) => Parser.getMaxNum(html);
  PageState get failureState => PageState.error;
  PageState get emptyState => PageState.success;

  /// Hide retained results immediately when the controls describe a new query.
  void invalidateQuery() {
    ++_generation;
    _active = null;
    pageState.value = PageState.pleaseSelect;
  }

  Future<IndicatorResult> getPage(bool loadMore) {
    if (_closed || session.blocked) return Future.value(IndicatorResult.fail);
    final key = queryKey;
    if (loadMore && _query == key && _active != null && _activeSession == session.generation) return _active!;
    if (loadMore && (!_hasPage || _query != key || _committedQuery != key)) loadMore = false;
    if (loadMore && _index >= _maxNum) return Future.value(IndicatorResult.noMore);
    final token = loadMore ? _generation : ++_generation;
    final sessionToken = session.generation;
    final index = loadMore ? _index + 1 : 1;
    if (!loadMore) {
      _query = key;
      pageState.value = PageState.loading;
    }
    final completer = Completer<IndicatorResult>();
    _active = completer.future;
    _activeSession = sessionToken;
    bool owns() => !_closed && token == _generation && key == queryKey && session.isCurrent(sessionToken);
    () async {
      try {
        final result = await getData(index);
        if (!owns()) return IndicatorResult.fail;
        switch (result) {
          case Error():
            throw StateError(result.error);
          case Success():
            final parsed = getParser(result.data);
            final max = loadMore ? _maxNum : getMaxPage(result.data);
            if (!owns()) return IndicatorResult.fail;
            // Commit only after transport and all parsing have succeeded.
            _index = index;
            _committedQuery = key;
            _hasPage = true;
            _maxNum = parsed.isEmpty ? index : (max < 1 ? 1 : max);
            if (loadMore) {
              data.addAll(parsed);
            } else {
              data.assignAll(parsed);
            }
            errorMsg = '';
            pageState.value = data.isEmpty ? emptyState : PageState.success;
            return parsed.isEmpty || index >= _maxNum ? IndicatorResult.noMore : IndicatorResult.success;
        }
      } catch (error) {
        if (owns()) {
          errorMsg = error.toString();
          pageState.value = failureState;
        }
        return IndicatorResult.fail;
      } finally {
        if (identical(_active, completer.future)) _active = null;
      }
    }().then(completer.complete);
    return completer.future;
  }

  @override
  void onClose() {
    _closed = true;
    ++_generation;
    _active = null;
    super.onClose();
  }
}
