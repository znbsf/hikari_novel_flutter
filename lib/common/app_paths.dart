import 'dart:io';

import 'package:path_provider/path_provider.dart';

class AppPaths {
  static late final Directory supportDir;

  static Future<void> init() async {
    supportDir = await getApplicationSupportDirectory();
  }

  static Directory get cachedChapterDir => Directory("${supportDir.path}/cached_chapter");

  static File cachedChapterFile(String aid, String cid) => File("${cachedChapterDir.path}/${aid}_$cid.txt");

  static Directory get fontDir => Directory("${supportDir.path}/font");

  static Directory get bgImageDir => Directory("${supportDir.path}/bgImage");
}
