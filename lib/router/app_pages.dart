import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hikari_novel_flutter/pages/about/view.dart';
import 'package:hikari_novel_flutter/pages/cache_queue/view.dart';
import 'package:hikari_novel_flutter/pages/comment/view.dart';
import 'package:hikari_novel_flutter/pages/home/view.dart';
import 'package:hikari_novel_flutter/pages/login/view.dart';
import 'package:hikari_novel_flutter/pages/main/view.dart';
import 'package:hikari_novel_flutter/pages/novel_detail/view.dart';
import 'package:hikari_novel_flutter/pages/photo/view.dart';
import 'package:hikari_novel_flutter/pages/reader/view.dart';
import 'package:hikari_novel_flutter/pages/reply/view.dart';
import 'package:hikari_novel_flutter/pages/search/view.dart';
import 'package:hikari_novel_flutter/pages/setting/view.dart';
import 'package:hikari_novel_flutter/pages/user_bookshelf/view.dart';
import 'package:hikari_novel_flutter/pages/user_info/view.dart';
import 'package:hikari_novel_flutter/pages/welcome/view.dart';
import 'package:hikari_novel_flutter/router/route_path.dart';

import '../pages/browsing_history/view.dart';
import '../widgets/state_page.dart';

class AppRoutes {
  static final List<GetPage<dynamic>> mainRoutePages = [
    CustomGetPage(name: RoutePath.main, page: () => MainPage()),
    CustomGetPage(name: RoutePath.home, page: () => HomePage()),
    CustomGetPage(name: RoutePath.login, page: () => LoginPage()),
    CustomGetPage(name: RoutePath.photo, page: () => PhotoPage()),
    CustomGetPage(name: RoutePath.reader, page: () => ReaderPage()),
    CustomGetPage(name: RoutePath.welcome, page: () => WelcomePage()),
  ];

  static final Map<String, Widget Function(Object?)> _subPages = {
    RoutePath.logo: (_) => LogoPage(),
    RoutePath.novelDetail: (args) => NovelDetailPage(aid: args as String),
    RoutePath.comment: (args) => CommentPage(aid: args as String),
    RoutePath.reply: (args) {
      final values = args as List<String>;
      return ReplyPage(aid: values[0], rid: values[1]);
    },
    RoutePath.userBookshelf: (args) => UserBookshelfPage(uid: args as String),
    RoutePath.browsingHistory: (_) => BrowsingHistoryPage(),
    RoutePath.userInfo: (_) => UserInfoPage(),
    RoutePath.about: (_) => AboutPage(),
    RoutePath.setting: (_) => SettingPage(),
    RoutePath.search: (args) => SearchPage(author: args as String?),
    RoutePath.cacheQueue: (_) => CacheQueuePage(),
  };

  static Route<dynamic>? subRoutePages(RouteSettings settings) {
    final builder = _subPages[settings.name];
    return builder == null ? null : GetPageRoute(settings: settings, page: () => builder(settings.arguments));
  }
}

class CustomGetPage extends GetPage<dynamic> {
  CustomGetPage({required super.name, required super.page, super.transitionDuration})
    : super(
        curve: Curves.linear,
        transition: Transition.native,
        showCupertinoParallax: false,
        popGesture: false,
      );
}
