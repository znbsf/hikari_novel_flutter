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
    (s) => s.cookie.value,
    (s, value) => s.cookie.value = value,
    null,
    'session=test-cookie',
    'session=test-cookie',
    clearToNull: true,
  );

  checkPreference<bool>('setting', 'isAutoCheckUpdate', (s) => s.isAutoCheckUpdate.value, (s, value) => s.isAutoCheckUpdate.value = value, true, false, false);

  checkPreference<ThemeMode>('setting', 'themeMode', (s) => s.themeMode.value, (s, value) => s.themeMode.value = value, ThemeMode.system, ThemeMode.dark, 2);

  checkPreference<Color>(
    'setting',
    'customColor',
    (s) => s.customColor.value,
    (s, value) => s.customColor.value = value,
    const Color(0xFF2196F3),
    const Color(0xFF123456),
    0xFF123456,
  );

  checkPreference<bool>('setting', 'isDynamicColor', (s) => s.isDynamicColor.value, (s, value) => s.isDynamicColor.value = value, true, false, false);

  checkPreference<bool>('setting', 'isRelativeTime', (s) => s.isRelativeTime.value, (s, value) => s.isRelativeTime.value = value, false, true, true);

  checkPreference<Language>(
    'setting',
    'language',
    (s) => s.language.value,
    (s, value) => s.language.value = value,
    Language.followSystem,
    Language.traditionalChinese,
    1,
  );

  checkPreference<Wenku8Node>(
    'setting',
    'wenku8Node',
    (s) => s.wenku8Node.value,
    (s, value) => s.wenku8Node.value = value,
    Wenku8Node.wwwWenku8Cc,
    Wenku8Node.wwwWenku8Net,
    0,
  );

  checkPreference<ReaderDirection>(
    'reader',
    'readerDirection',
    (s) => s.readerDirection.value,
    (s, value) => s.readerDirection.value = value,
    ReaderDirection.upToDown,
    ReaderDirection.rightToLeft,
    1,
  );

  checkPreference<double>('reader', 'readerFontSize', (s) => s.readerFontSize.value, (s, value) => s.readerFontSize.value = value, 16.0, 22.0, 22.0);

  checkPreference<double>('reader', 'readerLineSpacing', (s) => s.readerLineSpacing.value, (s, value) => s.readerLineSpacing.value = value, 1.5, 1.8, 1.8);

  checkPreference<bool>('reader', 'readerWakeLock', (s) => s.readerWakeLock.value, (s, value) => s.readerWakeLock.value = value, false, true, true);

  checkPreference<double>('reader', 'readerLeftMargin', (s) => s.readerLeftMargin.value, (s, value) => s.readerLeftMargin.value = value, 20.0, 12.0, 12.0);

  checkPreference<double>('reader', 'readerTopMargin', (s) => s.readerTopMargin.value, (s, value) => s.readerTopMargin.value = value, 20.0, 13.0, 13.0);

  checkPreference<double>('reader', 'readerRightMargin', (s) => s.readerRightMargin.value, (s, value) => s.readerRightMargin.value = value, 20.0, 14.0, 14.0);

  checkPreference<double>(
    'reader',
    'readerBottomMargin',
    (s) => s.readerBottomMargin.value,
    (s, value) => s.readerBottomMargin.value = value,
    20.0,
    15.0,
    15.0,
  );

  checkPreference<DualPageMode>(
    'reader',
    'readerDualPageMode',
    (s) => s.readerDualPageMode.value,
    (s, value) => s.readerDualPageMode.value = value,
    DualPageMode.auto,
    DualPageMode.disabled,
    2,
  );

  checkPreference<double>(
    'reader',
    'readerDualPageSpacing',
    (s) => s.readerDualPageSpacing.value,
    (s, value) => s.readerDualPageSpacing.value = value,
    20.0,
    30.0,
    30.0,
  );

  checkPreference<bool>(
    'reader',
    'readerImmersionMode',
    (s) => s.readerImmersionMode.value,
    (s, value) => s.readerImmersionMode.value = value,
    false,
    true,
    true,
  );

  checkPreference<bool>('reader', 'readerStatusBar', (s) => s.readerStatusBar.value, (s, value) => s.readerStatusBar.value = value, true, false, false);

  checkPreference<String?>(
    'reader',
    'readerTextFamily',
    (s) => s.readerTextFamily.value,
    (s, value) => s.readerTextFamily.value = value,
    null,
    '测试字体',
    '测试字体',
    clearToNull: true,
  );

  checkPreference<String?>(
    'reader',
    'readerTextStyleFilePath',
    (s) => s.readerTextStyleFilePath.value,
    (s, value) => s.readerTextStyleFilePath.value = value,
    null,
    'font/test.ttf',
    'font/test.ttf',
    clearToNull: true,
  );

  checkPreference<bool>(
    'reader',
    'readerPageTurningAnimation',
    (s) => s.readerPageTurningAnimation.value,
    (s, value) => s.readerPageTurningAnimation.value = value,
    true,
    false,
    false,
  );

  checkPreference<bool>(
    'reader',
    'readerVolumeKeyPageTurning',
    (s) => s.readerVolumeKeyPageTurning.value,
    (s, value) => s.readerVolumeKeyPageTurning.value = value,
    false,
    true,
    true,
  );

  checkPreference<Color?>(
    'reader',
    'readerDayBgColor',
    (s) => s.readerDayBgColor.value,
    (s, value) => s.readerDayBgColor.value = value,
    null,
    const Color(0xFF123456),
    0xFF123456,
    clearToNull: true,
  );

  checkPreference<Color?>(
    'reader',
    'readerDayTextColor',
    (s) => s.readerDayTextColor.value,
    (s, value) => s.readerDayTextColor.value = value,
    null,
    const Color(0xFF234567),
    0xFF234567,
    clearToNull: true,
  );

  checkPreference<Color?>(
    'reader',
    'readerNightBgColor',
    (s) => s.readerNightBgColor.value,
    (s, value) => s.readerNightBgColor.value = value,
    null,
    const Color(0xFF345678),
    0xFF345678,
    clearToNull: true,
  );

  checkPreference<Color?>(
    'reader',
    'readerNightTextColor',
    (s) => s.readerNightTextColor.value,
    (s, value) => s.readerNightTextColor.value = value,
    null,
    const Color(0xFF456789),
    0xFF456789,
    clearToNull: true,
  );

  checkPreference<String?>(
    'reader',
    'readerDayBgImage',
    (s) => s.readerDayBgImage.value,
    (s, value) => s.readerDayBgImage.value = value,
    null,
    'bgImage/day.png',
    'bgImage/day.png',
    clearToNull: true,
  );

  checkPreference<String?>(
    'reader',
    'readerNightBgImage',
    (s) => s.readerNightBgImage.value,
    (s, value) => s.readerNightBgImage.value = value,
    null,
    'bgImage/night.png',
    'bgImage/night.png',
    clearToNull: true,
  );

  checkPreference<bool>('reader', 'readerTtsEnabled', (s) => s.readerTtsEnabled.value, (s, value) => s.readerTtsEnabled.value = value, false, true, true);

  checkPreference<String?>(
    'reader',
    'readerTtsEngine',
    (s) => s.readerTtsEngine.value,
    (s, value) => s.readerTtsEngine.value = value,
    null,
    'test.tts.engine',
    'test.tts.engine',
    clearToNull: true,
  );

  checkPreference<Map<String, String>?>(
    'reader',
    'readerTtsVoice',
    (s) => s.readerTtsVoice.value,
    (s, value) => s.readerTtsVoice.value = value,
    null,
    {'name': '测试声音', 'locale': 'zh-CN'},
    {'name': '测试声音', 'locale': 'zh-CN'},
    clearToNull: true,
  );

  checkPreference<double>('reader', 'readerTtsRate', (s) => s.readerTtsRate.value, (s, value) => s.readerTtsRate.value = value, 0.5, 0.8, 0.8);

  checkPreference<double>('reader', 'readerTtsPitch', (s) => s.readerTtsPitch.value, (s, value) => s.readerTtsPitch.value = value, 1.0, 1.2, 1.2);

  checkPreference<double>('reader', 'readerTtsVolume', (s) => s.readerTtsVolume.value, (s, value) => s.readerTtsVolume.value = value, 1.0, 0.7, 0.7);

  checkPreference<bool>('setting', 'devModeEnabled', (s) => s.devModeEnabled.value, (s, value) => s.devModeEnabled.value = value, false, true, true);

  checkPreference<int>('reader', 'readerParaIndent', (s) => s.readerParaIndent.value, (s, value) => s.readerParaIndent.value = value, 1, 2, 2);

  checkPreference<int>('reader', 'readerParaSpacing', (s) => s.readerParaSpacing.value, (s, value) => s.readerParaSpacing.value = value, 25, 18, 18);

  checkPreference<int>(
    'reader',
    'readerBottomStatusBarHorizontalSpacing',
    (s) => s.readerBottomStatusBarHorizontalSpacing.value,
    (s, value) => s.readerBottomStatusBarHorizontalSpacing.value = value,
    25,
    32,
    32,
  );

  test('setting/user_info 默认值、adapter 和读写往返', () async {
    expect(Hive.box('setting').containsKey('user_info'), false);
    expect(storage.userInfo.value, null);
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

    storage.userInfo.value = user;
    expect(storage.userInfo.value, matcher);
    expect(Hive.box('setting').containsKey('user_info'), true);
    expect(Hive.box('setting').get('user_info'), matcher);
    await Hive.box('setting').flush();
    await reopen();
    expect(storage.userInfo.value, matcher);
    expect(Hive.box('setting').get('user_info'), matcher);
  });

  test('reader/readerTtsVoice 非 Map 旧值仍返回 null', () async {
    await Hive.box('reader').put('readerTtsVoice', 'invalid');
    expect(storage.readerTtsVoice.value, null);
  });

  test('reader/readerTtsVoice 旧 Map 的键和值转换为字符串', () async {
    await Hive.box('reader').put('readerTtsVoice', {1: 2, 'locale': 'zh-CN'});
    expect(storage.readerTtsVoice.value, {'1': '2', 'locale': 'zh-CN'});
  });
}
