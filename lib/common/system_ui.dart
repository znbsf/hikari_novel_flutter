import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SystemUi {
  static void edgeToEdge() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        statusBarColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ),
    );
  }

  static void immersive() => SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
}
