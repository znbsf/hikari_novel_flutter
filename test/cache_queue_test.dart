import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hikari_novel_flutter/models/cache_status.dart';
import 'package:hikari_novel_flutter/models/chapter_cache_task.dart';
import 'package:hikari_novel_flutter/pages/cache_queue/controller.dart';
import 'package:hikari_novel_flutter/service/chapter_downloader_service.dart';

class _Downloader extends ChapterDownloaderService {
  _Downloader() : super(dio: Dio());
  final calls = <Completer<String>>[];
  final ids = <String>[];
  final canceled = <String>[];

  @override
  Future<String> download({required String taskId, required String aid, required String cid, Function(int, int)? onProgress}) {
    ids.add(taskId);
    final result = Completer<String>();
    calls.add(result);
    return result.future;
  }

  @override
  void cancel(String taskId) => canceled.add(taskId);
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);
ChapterCacheTask _task(String id, {void Function(String)? onCompleted}) => ChapterCacheTask(uuid: id, aid: '1', cid: id, title: id, onCompleted: onCompleted);

void main() {
  late _Downloader downloader;
  late CacheQueueController queue;
  setUp(() {
    downloader = _Downloader();
    queue = CacheQueueController(downloader: downloader);
  });
  tearDown(() async {
    queue.onClose();
    for (final call in downloader.calls) {
      if (!call.isCompleted) call.completeError(Exception('canceled'));
    }
    await _settle();
  });

  test('pause survives a late cancellation failure', () async {
    final task = _task('1');
    await queue.addTask(task);
    await queue.pauseTask('1');
    downloader.calls.single.completeError(Exception('canceled'));
    await _settle();
    expect(task.status, CacheStatus.paused);
    expect(downloader.ids, ['1']);
  });

  test('immediate resume waits for canceled run and ignores its result', () async {
    var completed = 0;
    final task = _task('1', onCompleted: (_) => completed++);
    await queue.addTask(task);
    await queue.pauseTask('1');
    await queue.resumeTask('1');
    expect(downloader.calls, hasLength(1));
    expect(task.status, CacheStatus.pending);
    downloader.calls.first.complete('old result');
    await _settle();
    expect(completed, 0);
    expect(downloader.calls, hasLength(2));
    expect(task.status, CacheStatus.downloading);
    downloader.calls.last.complete('new result');
    await _settle();
    expect(completed, 1);
    expect(queue.tasks, isEmpty);
  });

  test('clear cancels running work and suppresses its completion callback', () async {
    var completed = 0;
    await queue.addTask(_task('1', onCompleted: (_) => completed++));
    await queue.addTask(_task('2'));
    await queue.clearAll();
    expect(downloader.canceled, contains('1'));
    downloader.calls.single.complete('late file');
    await _settle();
    expect(completed, 0);
    expect(queue.tasks, isEmpty);
    expect(downloader.ids, ['1']);
  });

  test('removed task cannot affect replacement with the same ID', () async {
    var completed = 0;
    await queue.addTask(_task('1'));
    await queue.removeTask('1');
    final replacement = _task('1', onCompleted: (_) => completed++);
    await queue.addTask(replacement);
    expect(downloader.calls, hasLength(1));
    downloader.calls.first.completeError(Exception('old failed'));
    await _settle();
    expect(queue.tasks.single, same(replacement));
    expect(replacement.status, CacheStatus.downloading);
    expect(downloader.calls, hasLength(2));
    downloader.calls.last.complete('new file');
    await _settle();
    expect(completed, 1);
  });

  test('start all does not restart running tasks', () async {
    await queue.addTask(_task('1'));
    await queue.addTask(_task('2'));
    await queue.startAll();
    await queue.startAll();
    expect(downloader.ids, ['1']);
    downloader.calls.first.complete('first file');
    await _settle();
    expect(downloader.ids, ['1', '2']);
  });

  test('pause all stops pending tasks and start all resumes after settlement', () async {
    final first = _task('1');
    final second = _task('2');
    await queue.addTask(first);
    await queue.addTask(second);
    await queue.pauseAll();
    expect([first.status, second.status], [CacheStatus.paused, CacheStatus.paused]);
    downloader.calls.first.completeError(Exception('canceled'));
    await _settle();
    expect(downloader.ids, ['1']);
    await queue.startAll();
    expect(downloader.ids, ['1', '1']);
  });

  test('completion immediately fills the next slot after failure', () async {
    final first = _task('1');
    await queue.addTask(first);
    await queue.addTask(_task('2'));
    downloader.calls.first.completeError(Exception('network failed'));
    await _settle();
    expect(first.status, CacheStatus.failed);
    expect(downloader.ids, ['1', '2']);
  });

  test('closed queue ignores late success and starts no more tasks', () async {
    var completed = 0;
    await queue.addTask(_task('1', onCompleted: (_) => completed++));
    await queue.addTask(_task('2'));
    queue.onClose();
    downloader.calls.first.complete('late file');
    await _settle();
    expect(completed, 0);
    expect(downloader.ids, ['1']);
  });

  test('parallel slots wait for actual completion before reuse', () async {
    queue.onClose();
    queue = CacheQueueController(concurrency: 2, downloader: downloader);
    await queue.addTask(_task('1'));
    await queue.addTask(_task('2'));
    await queue.addTask(_task('3'));
    expect(downloader.ids, ['1', '2']);
    await queue.cancelTask('1');
    expect(downloader.ids, ['1', '2']);
    downloader.calls.first.completeError(Exception('canceled'));
    await _settle();
    expect(downloader.ids, ['1', '2', '3']);
  });
}
