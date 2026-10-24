import 'package:get/get.dart';
import 'package:hikari_novel_flutter/models/novel_cover.dart';
import 'package:hikari_novel_flutter/models/page_state.dart';
import 'package:hikari_novel_flutter/models/resource.dart';
import 'package:hikari_novel_flutter/parser/parser.dart';

import '../../service/api_service.dart';
import '../../service/session_service.dart';

class UserBookshelfController extends GetxController {
  final String uid;
  final Rxn<List<NovelCover>> list = Rxn();
  final Rx<PageState> pageState = Rx(PageState.loading);
  String errorMsg = "";

  UserBookshelfController({required this.uid, Future<Resource> Function(String)? fetch, SessionCoordinator? session})
    : _fetch = fetch ?? ((uid) => ApiService.instance.getBookshelfFromUser(uid: uid)),
      _session = session ?? SessionCoordinator.instance;
  final Future<Resource> Function(String) _fetch;
  final SessionCoordinator _session;
  int _generation = 0;

  @override
  void onReady() {
    super.onReady();
    getPage();
  }

  Future<void> getPage() async {
    final generation = ++_generation;
    final session = _session.generation;
    bool current() => !isClosed && generation == _generation && _session.isCurrent(session);
    if (!current()) return;
    try {
      final result = await _fetch(uid);
      if (!current()) return;
      if (result case Error()) throw StateError('User bookshelf request failed');
      final parsed = Parser.parseOtherBookshelfToList(result.data as String);
      list.value = parsed;
      errorMsg = '';
      pageState.value = PageState.success;
    } catch (error) {
      if (current()) {
        errorMsg = error.toString();
        pageState.value = PageState.error;
      }
    }
  }
}
