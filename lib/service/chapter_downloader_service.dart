import 'dart:io';

import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;

import '../common/app_paths.dart';
import '../common/log.dart';
import '../models/common/charset_type.dart';
import '../models/common/wenku8_node.dart';
import 'api_service.dart';
import 'site_response.dart';

class ChapterDownloaderService extends GetxService {
  ChapterDownloaderService({
    Dio? dio,
    this._cacheDirectory,
    String Function()? node,
    CharsetType Function()? charset,
    Future<void> Function(File, String)? writeCandidate,
    void Function(File, String)? commitCandidate,
    Future<void> Function(Directory)? cleanStaging,
  }) : _dio = dio ?? ApiService.instance.dio,
       _node = node ?? (() => ApiService.instance.wenku8Node.node),
       _charset = charset ?? (() => ApiService.instance.charsetType),
       _writeCandidate =
           writeCandidate ??
           ((file, content) async {
             await file.writeAsString(content, flush: true);
           }),
       _commitCandidate =
           commitCandidate ??
           ((file, path) {
             file.renameSync(path);
           }),
       _cleanStaging =
           cleanStaging ??
           ((directory) async {
             await directory.delete(recursive: true);
           });

  final Future<void> Function(File, String) _writeCandidate;
  final void Function(File, String) _commitCandidate;
  final Future<void> Function(Directory) _cleanStaging;
  final Dio _dio;
  final Directory? _cacheDirectory;
  final String Function() _node;
  final CharsetType Function() _charset;
  final Map<String, CancelToken> _tasks = {};
  final Set<String> _chapters = {};

  void cancel(String taskId) => _tasks[taskId]?.cancel('用户主动取消下载');
  // An active operation owns its state until its finally has completed.
  void clearCancel(String taskId) {
    if (!isDownloading(taskId)) _tasks.remove(taskId);
  }

  bool isDownloading(String taskId) => _tasks.containsKey(taskId);
  bool isCanceled(String taskId) => _tasks[taskId]?.isCancelled ?? false;

  Future<String> download({required String taskId, required String aid, required String cid, Function(int received, int total)? onProgress}) async {
    if (!RegExp(r'^\d+$').hasMatch(aid) || !RegExp(r'^\d+$').hasMatch(cid)) throw ArgumentError('Invalid chapter identity');
    final key = '${aid}_$cid';
    if (_tasks.containsKey(taskId) || _chapters.contains(key)) throw StateError('Chapter or task is already downloading');
    // Capture preferences before publishing task state or the first await.
    final charset = _charset();
    final uri = SiteResponse.withCharset('${_node()}/modules/article/reader.php?aid=$aid&cid=$cid', charset);
    final token = CancelToken();
    _tasks[taskId] = token;
    _chapters.add(key);
    Directory? staging;
    try {
      final directory = _cacheDirectory ?? AppPaths.cachedChapterDir;
      await directory.create(recursive: true);
      if (token.isCancelled) throw token.cancelError!;
      final content = await SiteResponse.get(
        _dio,
        uri,
        charset,
        cancelToken: token,
        onReceiveProgress: (received, total) {
          if (total > 0) onProgress?.call(received, total);
        },
        chapter: true,
      );
      if (token.isCancelled) throw token.cancelError!;
      // Unique staging lives on the same filesystem. Never delete the old cache.
      staging = await directory.createTemp('.chapter-');
      final candidate = File('${staging.path}/$key.tmp');
      await _writeCandidate(candidate, content);
      SiteResponse.validateChapter(await candidate.readAsString());
      if (token.isCancelled) throw token.cancelError!;
      final destination = File('${directory.path}/$key.txt');
      // Synchronous commit has no await at which a cancellation can interleave.
      // File.rename replaces an existing file; failure preserves the destination.
      _commitCandidate(candidate, destination.path);
      return destination.path;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) throw Exception('canceled');
      rethrow;
    } finally {
      try {
        if (staging != null && await staging.exists()) await _cleanStaging(staging);
      } catch (e) {
        Log.e('Chapter temporary cleanup failed: $e');
      } finally {
        if (identical(_tasks[taskId], token)) _tasks.remove(taskId);
        _chapters.remove(key);
      }
    }
  }

  void cancelAll() {
    for (final token in _tasks.values) {
      token.cancel('用户主动取消下载');
    }
  }

  void dispose() => cancelAll();
}
