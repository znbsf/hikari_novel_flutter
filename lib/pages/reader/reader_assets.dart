import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:ttf_metadata/ttf_metadata.dart';

import '../../common/app_paths.dart';

Future<({String path, String family})?> pickTextStyleFile() async {
  final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['ttf', 'otf']);
  if (file == null) return null; // 用户取消

  final tempPath = file.path!;
  await deleteFontDir();

  final srcFile = File(tempPath);
  final ext = path.extension(tempPath);
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final fileName = "font_$timestamp$ext";
  final destDir = AppPaths.fontDir;
  await destDir.create(recursive: true);
  final destPath = '${destDir.path}/$fileName';
  final destFile = await srcFile.copy(destPath);

  final bytes = await File(tempPath).readAsBytes();
  final family = TtfMetadata(TtfDataSource(byteData: bytes)).fontName;
  await loadFont(destFile.path);
  return (path: destPath, family: family);
}

Future<String?> loadFont(String filePath) async {
  final bytes = await File(filePath).readAsBytes();
  final family = TtfMetadata(TtfDataSource(byteData: bytes)).fontName;
  final loader = FontLoader(family)..addFont(Future.value(ByteData.view(bytes.buffer)));
  await loader.load();
  return family;
}

Future<bool> fontFileExists(String filePath) => File(filePath).exists();

Future<void> deleteFontDir() async {
  final fontsDir = AppPaths.fontDir;
  if (await fontsDir.exists()) {
    await fontsDir.delete(recursive: true);
  }
}

Future<String?> pickBgImageFile(bool isDark) async {
  final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['jpg', 'png', 'jpeg']);
  if (file == null) return null; // 用户取消

  final tempPath = file.path!;
  final srcFile = File(tempPath);
  final ext = path.extension(tempPath);
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final fileName = isDark ? "night_$timestamp$ext" : "day_$timestamp$ext";
  final destDir = AppPaths.bgImageDir;
  if (!await destDir.exists()) {
    await destDir.create(recursive: true);
  }
  final destPath = '${destDir.path}/$fileName';
  await srcFile.copy(destPath);
  return destPath;
}

Future<void> deleteStoredBgImageFile(String? filePath) async {
  if (filePath == null || filePath.isEmpty) return;

  final bgDirPath = path.normalize(AppPaths.bgImageDir.path);
  final targetPath = path.normalize(filePath);
  if (!path.isWithin(bgDirPath, targetPath)) return;

  final file = File(targetPath);
  if (await file.exists()) {
    await file.delete();
  }
}

Future<void> deleteBgImageDir() async {
  final fontsDir = AppPaths.bgImageDir;
  if (await fontsDir.exists()) {
    await fontsDir.delete(recursive: true);
  }
}
