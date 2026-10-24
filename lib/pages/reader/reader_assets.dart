import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:ttf_metadata/ttf_metadata.dart';

import '../../common/app_paths.dart';

/// File preparation never removes the previous resource. Its owner commits the
/// new reference first, then removes only the superseded file.
class ReaderAssets {
  ReaderAssets({
    this.fontDirectory,
    this.backgroundDirectory,
    Future<String?> Function(List<String>)? selectFile,
    Future<String?> Function(String)? fontLoader,
    Future<void> Function(String)? imageValidator,
    Future<File> Function(File, String)? copyFile,
  }) : _selectFile = selectFile ?? _pickFile,
       _fontLoader = fontLoader ?? loadFont,
       _imageValidator = imageValidator ?? _validateImage,
       _copyFile = copyFile ?? ((source, target) => source.copy(target));

  final Directory? fontDirectory;
  final Directory? backgroundDirectory;
  final Future<String?> Function(List<String>) _selectFile;
  final Future<String?> Function(String) _fontLoader;
  final Future<void> Function(String) _imageValidator;
  final Future<File> Function(File, String) _copyFile;
  static int _sequence = 0;

  Directory get _fontDirectory => fontDirectory ?? AppPaths.fontDir;
  Directory get _backgroundDirectory => backgroundDirectory ?? AppPaths.bgImageDir;

  static Future<String?> _pickFile(List<String> extensions) async {
    final selected = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: extensions);
    if (selected == null) return null;
    final selectedPath = selected.path;
    if (selectedPath == null || selectedPath.isEmpty) throw StateError('Selected file has no local path');
    return selectedPath;
  }

  static Future<void> _validateImage(String filePath) async {
    final codec = await ui.instantiateImageCodec(await File(filePath).readAsBytes());
    try {
      final frame = await codec.getNextFrame();
      frame.image.dispose();
    } finally {
      codec.dispose();
    }
  }

  Future<T?> _prepare<T>(Directory directory, List<String> extensions, String prefix, Future<T> Function(String) validate) async {
    final source = await _selectFile(extensions);
    if (source == null) return null;
    await directory.create(recursive: true);
    final name = '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${_sequence++}${path.extension(source)}';
    final target = path.join(directory.path, name);
    try {
      await _copyFile(File(source), target);
      return await validate(target);
    } catch (_) {
      // A failed copy can leave a partial target. Never delete its source or
      // any pre-existing directory contents.
      await _removeQuietly(directory, target);
      rethrow;
    }
  }

  Future<({String path, String family})?> pickTextStyleFile() => _prepare(_fontDirectory, ['ttf', 'otf'], 'font', (target) async {
    final family = await _fontLoader(target);
    if (family == null || family.trim().isEmpty) throw const FormatException('Font has no family name');
    return (path: target, family: family);
  });

  Future<String?> pickBgImageFile(bool isDark) => _prepare(_backgroundDirectory, ['jpg', 'png', 'jpeg'], isDark ? 'night' : 'day', (target) async {
    await _imageValidator(target);
    return target;
  });

  Future<String?> loadStoredFont(String filePath) => _fontLoader(filePath);
  Future<bool> fontFileExists(String filePath) => File(filePath).exists();
  Future<void> deleteStoredFont(String? filePath) => _removeQuietly(_fontDirectory, filePath);
  Future<void> deleteStoredBackground(String? filePath) => _removeQuietly(_backgroundDirectory, filePath);

  static Future<void> _removeQuietly(Directory directory, String? filePath) async {
    if (filePath == null || filePath.isEmpty) return;
    final root = path.normalize(path.absolute(directory.path));
    final target = path.normalize(path.absolute(filePath));
    if (!path.isWithin(root, target)) return;
    try {
      // Refuse symlink paths; cleanup is limited to owned regular files.
      if (await FileSystemEntity.type(target, followLinks: false) != FileSystemEntityType.file) return;
      final resolvedRoot = await directory.resolveSymbolicLinks();
      final resolvedTarget = await File(target).resolveSymbolicLinks();
      if (!path.isWithin(resolvedRoot, resolvedTarget)) return;
      await File(target).delete();
    } on FileSystemException {
      // Cleanup failure leaves an unreferenced file, never invalidates a commit.
    }
  }
}

final defaultReaderAssets = ReaderAssets();

Future<({String path, String family})?> pickTextStyleFile() => defaultReaderAssets.pickTextStyleFile();

Future<String?> loadFont(String filePath) async {
  final bytes = await File(filePath).readAsBytes();
  final family = TtfMetadata(TtfDataSource(byteData: bytes)).fontName;
  if (family.trim().isEmpty) throw const FormatException('Font has no family name');
  final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(bytes)));
  await loader.load();
  return family;
}

Future<bool> fontFileExists(String filePath) => defaultReaderAssets.fontFileExists(filePath);
Future<String?> pickBgImageFile(bool isDark) => defaultReaderAssets.pickBgImageFile(isDark);
Future<void> deleteStoredBgImageFile(String? filePath) => defaultReaderAssets.deleteStoredBackground(filePath);
