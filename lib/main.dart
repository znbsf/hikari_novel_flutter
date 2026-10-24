import 'package:dynamic_color/dynamic_color.dart';
import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:get/get.dart';
import 'package:hikari_novel_flutter/common/app_translations.dart';
import 'package:hikari_novel_flutter/common/constants.dart';
import 'package:hikari_novel_flutter/common/database/database.dart';
import 'package:hikari_novel_flutter/common/locale.dart';
import 'package:hikari_novel_flutter/router/app_pages.dart';
import 'package:hikari_novel_flutter/router/route_path.dart';
import 'package:hikari_novel_flutter/service/api_service.dart';
import 'package:hikari_novel_flutter/service/chapter_downloader_service.dart';
import 'package:hikari_novel_flutter/service/local_storage_service.dart';
import 'package:hikari_novel_flutter/service/tts_service.dart';
import 'package:jiffy/jiffy.dart';

import 'common/app_paths.dart';
import 'common/system_ui.dart';

final localhostServer = InAppLocalhostServer(documentRoot: 'assets');
WebViewEnvironment? webViewEnvironment;

bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

bool get _isWindows => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  await AppPaths.init();
  await Get.put(LocalStorageService()).init();
  Get.put(ApiService());
  Get.put(ChapterDownloaderService());
  Get.put(AppDatabase());
  Get.put(TtsService()).init();

  if (_isWindows) {
    final availableVersion = await WebViewEnvironment.getAvailableVersion();
    assert(availableVersion != null, 'Failed to find an installed WebView2 runtime or non-stable Microsoft Edge installation.');
    webViewEnvironment = await WebViewEnvironment.create(settings: WebViewEnvironmentSettings(userDataFolder: 'custom_path'));
  } else if (_isAndroid) {
    await InAppWebViewController.setWebContentsDebuggingEnabled(kDebugMode);
  }

  _init();
  await Jiffy.setLocale(resolveAppLocale().toString());
  await ApiService.instance.initCookie(); //初始化cookie

  FlutterNativeSplash.remove();

  runApp(const App());
  TtsService.instance.warmUpInBackground(); //首屏之后再预热 TTS 引擎
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    // 自定义颜色、深浅模式和动态取色
    final storage = LocalStorageService.instance;
    final brandColor = storage.customColor.value;
    final currentThemeValue = storage.themeMode.value;
    final isDynamicColor = storage.isDynamicColor.value;

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        final useDynamic = _isAndroid && lightDynamic != null && darkDynamic != null && isDynamicColor;
        final lightColorScheme = useDynamic ? lightDynamic.harmonized() : ColorScheme.fromSeed(seedColor: brandColor, brightness: Brightness.light);
        final darkColorScheme = useDynamic ? darkDynamic.harmonized() : ColorScheme.fromSeed(seedColor: brandColor, brightness: Brightness.dark);
        return GetMaterialApp(
          title: kAppName,
          theme: buildTheme(lightColorScheme),
          darkTheme: buildTheme(darkColorScheme),
          themeMode: currentThemeValue,
          translations: AppTranslations(),
          locale: resolveAppLocale(),
          fallbackLocale: Locale("zh", "CN"),
          getPages: AppRoutes.mainRoutePages,
          initialRoute: storage.cookie.value != null ? RoutePath.main : RoutePath.welcome, //初始页面
        );
      },
    );
  }
}

ThemeData buildTheme(ColorScheme scheme) => ThemeData(
  useMaterial3: true,
  colorScheme: scheme,
  snackBarTheme: SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    actionTextColor: scheme.primary,
    backgroundColor: scheme.onSurface,
    closeIconColor: scheme.surface,
    contentTextStyle: TextStyle(color: scheme.surface),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    showCloseIcon: true,
  ),
  pageTransitionsTheme: const PageTransitionsTheme(
    builders: <TargetPlatform, PageTransitionsBuilder>{TargetPlatform.android: ZoomPageTransitionsBuilder(allowEnterRouteSnapshotting: false)},
  ),
  // 页面切换动画
  fontFamily: _isWindows ? "Microsoft YaHei" : null,
);

void _init() {
  // 小白条、导航栏沉浸
  if (_isAndroid) {
    SystemUi.edgeToEdge();
  }

  EasyRefresh.defaultHeaderBuilder = () => MaterialHeader();
  EasyRefresh.defaultFooterBuilder = () => ClassicFooter(
    dragText: "drag_text_load".tr,
    armedText: "armed_text_load".tr,
    readyText: "ready_text_load".tr,
    processingText: "processing_text_load".tr,
    processedText: "processed_text_load".tr,
    noMoreText: "no_more_text".tr,
    failedText: "failed_text_load".tr,
    messageText: "message_text".tr,
  );
}
