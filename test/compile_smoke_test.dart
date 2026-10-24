import 'package:flutter_test/flutter_test.dart';
// 导入应用入口，让整个 lib（含 *.g.dart）都参与编译；analyzer 排除了生成文件，单靠 analyze 发现不了其中的错误
import 'package:hikari_novel_flutter/main.dart' as app;

void main() {
  test('应用入口可以编译', () => expect(app.main, isNotNull));
}
