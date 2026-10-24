import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hikari_novel_flutter/models/common/language.dart';
import 'package:hikari_novel_flutter/models/common/wenku8_node.dart';
import 'package:hikari_novel_flutter/models/dual_page_mode.dart';
import 'package:hikari_novel_flutter/models/reader_direction.dart';
import 'package:hikari_novel_flutter/models/user_info.dart';
import 'package:hikari_novel_flutter/service/local_storage_service.dart';
import 'package:hive_ce/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late LocalStorageService storage;

  Future<void> reopen() async {
    await Hive.close();
    Hive.resetAdapters();
    storage = LocalStorageService();
    await storage.init(hivePath: directory.path);
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('hikari-storage-test-');
    storage = LocalStorageService();
    await storage.init(hivePath: directory.path);
  });

  tearDown(() async {
    await Hive.close();
    Hive.resetAdapters();
    await directory.delete(recursive: true);
  });

  void checkPreference<T>(
    String boxName,
    String key,
    T Function(LocalStorageService) get,
    void Function(LocalStorageService, T) set,
    T defaultValue,
    T value,
    Object? rawValue, {
    bool clearToNull = false,
  }) {
    test('$boxName/$key 默认值、原始 key 和读写往返', () async {
      expect(Hive.box(boxName).containsKey(key), false);
      expect(get(storage), defaultValue);
      set(storage, value);
      expect(get(storage), value);
      expect(Hive.box(boxName).containsKey(key), true);
      expect(Hive.box(boxName).get(key), rawValue);

      await Hive.box(boxName).flush();
      await reopen();
      expect(get(storage), value);
      expect(Hive.box(boxName).get(key), rawValue);

      if (clearToNull) {
        set(storage, null as T);
        expect(get(storage), null);
        expect(Hive.box(boxName).containsKey(key), true);
        expect(Hive.box(boxName).get(key), null);
        await Hive.box(boxName).flush();
        await reopen();
        expect(get(storage), null);
      }
    });
  }

  checkPreference<String?>(
    'loginInfo',
    'cookie',
    (s) => s.getCookie(),
    (s, value) => s.setCookie(value),
    null,
    'session=test-cookie',
    'session=test-cookie',
    clearToNull: true,
  );

  checkPreference<bool>('setting', 'isAutoCheckUpdate', (s) => s.getIsAutoCheckUpdate(), (s, value) => s.setIsAutoCheckUpdate(value), true, false, false);

  checkPreference<ThemeMode>('setting', 'themeMode', (s) => s.getThemeMode(), (s, value) => s.setThemeMode(value), ThemeMode.system, ThemeMode.dark, 2);

  checkPreference<Color>(
    'setting',
    'customColor',
    (s) => s.getCustomColor(),
    (s, value) => s.setCustomColor(value),
    const Color(0xFF2196F3),
    const Color(0xFF123456),
    0xFF123456,
  );

  checkPreference<bool>('setting', 'isDynamicColor', (s) => s.getIsDynamicColor(), (s, value) => s.setIsDynamicColor(value), true, false, false);

  checkPreference<bool>('setting', 'isRelativeTime', (s) => s.getIsRelativeTime(), (s, value) => s.setIsRelativeTime(value), false, true, true);

  checkPreference<Language>(
    'setting',
    'language',
    (s) => s.getLanguage(),
    (s, value) => s.setLanguage(value),
    Language.followSystem,
    Language.traditionalChinese,
    1,
  );

  checkPreference<Wenku8Node>(
    'setting',
    'wenku8Node',
    (s) => s.getWenku8Node(),
    (s, value) => s.setWenku8Node(value),
    Wenku8Node.wwwWenku8Cc,
    Wenku8Node.wwwWenku8Net,
    0,
  );

  checkPreference<ReaderDirection>(
    'reader',
    'readerDirection',
    (s) => s.getReaderDirection(),
    (s, value) => s.setReaderDirection(value),
    ReaderDirection.upToDown,
    ReaderDirection.rightToLeft,
    1,
  );

  checkPreference<double>('reader', 'readerFontSize', (s) => s.getReaderFontSize(), (s, value) => s.setReaderFontSize(value), 16.0, 22.0, 22.0);

  checkPreference<double>('reader', 'readerLineSpacing', (s) => s.getReaderLineSpacing(), (s, value) => s.setReaderLineSpacing(value), 1.5, 1.8, 1.8);

  checkPreference<bool>('reader', 'readerWakeLock', (s) => s.getReaderWakeLock(), (s, value) => s.setReaderWakeLock(value), false, true, true);

  checkPreference<double>('reader', 'readerLeftMargin', (s) => s.getReaderLeftMargin(), (s, value) => s.setReaderLeftMargin(value), 20.0, 12.0, 12.0);

  checkPreference<double>('reader', 'readerTopMargin', (s) => s.getReaderTopMargin(), (s, value) => s.setReaderTopMargin(value), 20.0, 13.0, 13.0);

  checkPreference<double>('reader', 'readerRightMargin', (s) => s.getReaderRightMargin(), (s, value) => s.setReaderRightMargin(value), 20.0, 14.0, 14.0);

  checkPreference<double>('reader', 'readerBottomMargin', (s) => s.getReaderBottomMargin(), (s, value) => s.setReaderBottomMargin(value), 20.0, 15.0, 15.0);

  checkPreference<DualPageMode>(
    'reader',
    'readerDualPageMode',
    (s) => s.getReaderDualPageMode(),
    (s, value) => s.setReaderDualPageMode(value),
    DualPageMode.auto,
    DualPageMode.disabled,
    2,
  );

  checkPreference<double>(
    'reader',
    'readerDualPageSpacing',
    (s) => s.getReaderDualPageSpacing(),
    (s, value) => s.setReaderDualPageSpacing(value),
    20.0,
    30.0,
    30.0,
  );

  checkPreference<bool>('reader', 'readerImmersionMode', (s) => s.getReaderImmersionMode(), (s, value) => s.setReaderImmersionMode(value), false, true, true);

  checkPreference<bool>('reader', 'readerStatusBar', (s) => s.getReaderStatusBar(), (s, value) => s.setReaderStatusBar(value), true, false, false);

  checkPreference<String?>(
    'reader',
    'readerTextFamily',
    (s) => s.getReaderTextFamily(),
    (s, value) => s.setReaderTextFamily(value),
    null,
    '测试字体',
    '测试字体',
    clearToNull: true,
  );

  checkPreference<String?>(
    'reader',
    'readerTextStyleFilePath',
    (s) => s.getReaderTextStyleFilePath(),
    (s, value) => s.setReaderTextStyleFilePath(value),
    null,
    'font/test.ttf',
    'font/test.ttf',
    clearToNull: true,
  );

  checkPreference<bool>(
    'reader',
    'readerPageTurningAnimation',
    (s) => s.getReaderPageTurningAnimation(),
    (s, value) => s.setReaderPageTurningAnimation(value),
    true,
    false,
    false,
  );

  checkPreference<bool>(
    'reader',
    'readerVolumeKeyPageTurning',
    (s) => s.getReaderVolumeKeyPageTurning(),
    (s, value) => s.setReaderVolumeKeyPageTurning(value),
    false,
    true,
    true,
  );

  checkPreference<Color?>(
    'reader',
    'readerDayBgColor',
    (s) => s.getReaderDayBgColor(),
    (s, value) => s.setReaderDayBgColor(value),
    null,
    const Color(0xFF123456),
    0xFF123456,
    clearToNull: true,
  );

  checkPreference<Color?>(
    'reader',
    'readerDayTextColor',
    (s) => s.getReaderDayTextColor(),
    (s, value) => s.setReaderDayTextColor(value),
    null,
    const Color(0xFF234567),
    0xFF234567,
    clearToNull: true,
  );

  checkPreference<Color?>(
    'reader',
    'readerNightBgColor',
    (s) => s.getReaderNightBgColor(),
    (s, value) => s.setReaderNightBgColor(value),
    null,
    const Color(0xFF345678),
    0xFF345678,
    clearToNull: true,
  );

  checkPreference<Color?>(
    'reader',
    'readerNightTextColor',
    (s) => s.getReaderNightTextColor(),
    (s, value) => s.setReaderNightTextColor(value),
    null,
    const Color(0xFF456789),
    0xFF456789,
    clearToNull: true,
  );

  checkPreference<String?>(
    'reader',
    'readerDayBgImage',
    (s) => s.getReaderDayBgImage(),
    (s, value) => s.setReaderDayBgImage(value),
    null,
    'bgImage/day.png',
    'bgImage/day.png',
    clearToNull: true,
  );

  checkPreference<String?>(
    'reader',
    'readerNightBgImage',
    (s) => s.getReaderNightBgImage(),
    (s, value) => s.setReaderNightBgImage(value),
    null,
    'bgImage/night.png',
    'bgImage/night.png',
    clearToNull: true,
  );

  checkPreference<bool>('reader', 'readerTtsEnabled', (s) => s.getReaderTtsEnabled(), (s, value) => s.setReaderTtsEnabled(value), false, true, true);

  checkPreference<String?>(
    'reader',
    'readerTtsEngine',
    (s) => s.getReaderTtsEngine(),
    (s, value) => s.setReaderTtsEngine(value),
    null,
    'test.tts.engine',
    'test.tts.engine',
    clearToNull: true,
  );

  checkPreference<Map<String, String>?>(
    'reader',
    'readerTtsVoice',
    (s) => s.getReaderTtsVoice(),
    (s, value) => s.setReaderTtsVoice(value),
    null,
    {'name': '测试声音', 'locale': 'zh-CN'},
    {'name': '测试声音', 'locale': 'zh-CN'},
    clearToNull: true,
  );

  checkPreference<double>('reader', 'readerTtsRate', (s) => s.getReaderTtsRate(), (s, value) => s.setReaderTtsRate(value), 0.5, 0.8, 0.8);

  checkPreference<double>('reader', 'readerTtsPitch', (s) => s.getReaderTtsPitch(), (s, value) => s.setReaderTtsPitch(value), 1.0, 1.2, 1.2);

  checkPreference<double>('reader', 'readerTtsVolume', (s) => s.getReaderTtsVolume(), (s, value) => s.setReaderTtsVolume(value), 1.0, 0.7, 0.7);

  checkPreference<bool>('setting', 'devModeEnabled', (s) => s.getDevModeEnabled(), (s, value) => s.setDevModeEnabled(value), false, true, true);

  checkPreference<int>('reader', 'readerParaIndent', (s) => s.getReaderParaIndent(), (s, value) => s.setReaderParaIndent(value), 1, 2, 2);

  checkPreference<int>('reader', 'readerParaSpacing', (s) => s.getReaderParaSpacing(), (s, value) => s.setReaderParaSpacing(value), 25, 18, 18);

  checkPreference<int>(
    'reader',
    'readerBottomStatusBarHorizontalSpacing',
    (s) => s.getReaderBottomStatusBarHorizontalSpacing(),
    (s, value) => s.setReaderBottomStatusBarHorizontalSpacing(value),
    25,
    32,
    32,
  );

  test('setting/user_info 默认值、adapter 和读写往返', () async {
    expect(Hive.box('setting').containsKey('user_info'), false);
    expect(storage.getUserInfo(), null);
    final user = UserInfo(
      avatar: 'avatar.png',
      uid: '42',
      username: '测试用户',
      userLevel: '普通会员',
      email: 'reader@example.com',
      registerDate: '2026-10-24',
      contribution: '1',
      experience: '2',
      point: '3',
      maxBookshelfNum: '4',
      maxRecommendNum: '5',
    );
    final matcher = isA<UserInfo>()
        .having((u) => u.avatar, 'avatar', 'avatar.png')
        .having((u) => u.uid, 'uid', '42')
        .having((u) => u.username, 'username', '测试用户')
        .having((u) => u.userLevel, 'userLevel', '普通会员')
        .having((u) => u.email, 'email', 'reader@example.com')
        .having((u) => u.registerDate, 'registerDate', '2026-10-24')
        .having((u) => u.contribution, 'contribution', '1')
        .having((u) => u.experience, 'experience', '2')
        .having((u) => u.point, 'point', '3')
        .having((u) => u.maxBookshelfNum, 'maxBookshelfNum', '4')
        .having((u) => u.maxRecommendNum, 'maxRecommendNum', '5');

    storage.setUserInfo(user);
    expect(storage.getUserInfo(), matcher);
    expect(Hive.box('setting').containsKey('user_info'), true);
    expect(Hive.box('setting').get('user_info'), matcher);
    await Hive.box('setting').flush();
    await reopen();
    expect(storage.getUserInfo(), matcher);
    expect(Hive.box('setting').get('user_info'), matcher);
  });
}
