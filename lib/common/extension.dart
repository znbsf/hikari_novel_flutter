import 'package:flutter/material.dart';

extension ScreenInfo on BuildContext {
  bool isLargeScreen() => MediaQuery.of(this).size.width > MediaQuery.of(this).size.height;

  bool shouldAutoUseDualPage() {
    final size = MediaQuery.of(this).size;
    return size.shortestSide >= 600 && size.width > size.height;
  }
}
