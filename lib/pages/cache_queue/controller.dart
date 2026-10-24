import 'package:get/get.dart';

import '../../models/cache_status.dart';
import '../../models/chapter_cache_task.dart';
import '../../service/chapter_downloader_service.dart';

class CacheQueueController extends GetxService {
  CacheQueueController({this.concurrency = 1, ChapterDownloaderService? downloader}) : downloader = downloader ?? Get.find<ChapterDownloaderService>() {
    if (concurrency < 1) throw ArgumentError.value(concurrency, 'concurrency');
  }

  final ChapterDownloaderService downloader;
  final RxList<ChapterCacheTask> tasks = <ChapterCacheTask>[].obs;
  final int concurrency;
  final Map<String, _QueueRun> _running = {};
  bool _closed = false;

  Future<void> addTask(ChapterCacheTask task) async {
    if (_closed) return;
    final index = tasks.indexWhere((existing) => existing.uuid == task.uuid);
    if (index == -1) {
      tasks.add(task);
    } else {
      tasks[index].title = task.title;
      tasks.refresh();
    }
    _pump();
  }

  Future<void> removeTask(String uuid) async {
    _cancelRun(uuid);
    tasks.removeWhere((task) => task.uuid == uuid);
  }

  Future<void> startProcessing() async => _pump();

  // Reserve a slot before starting any async work. A canceled run retains its
  // slot until the downloader has released its files and cancellation token.
  void _pump() {
    if (_closed) return;
    for (final task in tasks.toList()) {
      if (_running.length >= concurrency) break;
      if (task.status != CacheStatus.pending || _running.containsKey(task.uuid)) continue;
      final run = _QueueRun(task);
      _running[task.uuid] = run;
      task.status = CacheStatus.downloading;
      task.progress = 0;
      tasks.refresh();
      _runTask(run);
    }
  }

  bool _accepts(_QueueRun run) => !_closed && run.valid && tasks.contains(run.task) && run.task.status == CacheStatus.downloading;

  Future<void> _runTask(_QueueRun run) async {
    final task = run.task;
    try {
      await downloader.download(taskId: task.uuid, aid: task.aid, cid: task.cid);
      if (_accepts(run)) {
        tasks.remove(task);
        task.status = CacheStatus.completed;
        task.progress = 1;
        task.onCompleted?.call(task.cid);
      }
    } catch (error) {
      if (_accepts(run)) {
        task.status = error.toString().contains('canceled') ? CacheStatus.canceled : CacheStatus.failed;
        tasks.refresh();
      }
    } finally {
      if (identical(_running[task.uuid], run)) _running.remove(task.uuid);
      _pump();
    }
  }

  void _cancelRun(String uuid) {
    _running[uuid]?.valid = false;
    downloader.cancel(uuid);
  }

  Future<void> pauseTask(String uuid) async {
    _cancelRun(uuid);
    for (final task in tasks.where((task) => task.uuid == uuid)) {
      task.status = CacheStatus.paused;
    }
    tasks.refresh();
  }

  Future<void> resumeTask(String uuid) async {
    for (final task in tasks.where((task) => task.uuid == uuid)) {
      if (task.status == CacheStatus.paused || task.status == CacheStatus.failed || task.status == CacheStatus.canceled) {
        task.status = CacheStatus.pending;
      }
    }
    tasks.refresh();
    _pump();
  }

  Future<void> cancelTask(String uuid) async {
    _cancelRun(uuid);
    for (final task in tasks.where((task) => task.uuid == uuid)) {
      task.status = CacheStatus.canceled;
    }
    tasks.refresh();
  }

  Future<void> startAll() async {
    for (final task in tasks) {
      if (task.status != CacheStatus.completed && task.status != CacheStatus.downloading) task.status = CacheStatus.pending;
    }
    tasks.refresh();
    _pump();
  }

  Future<void> pauseAll() async {
    for (final uuid in _running.keys.toList()) {
      _cancelRun(uuid);
    }
    for (final task in tasks) {
      if (task.status == CacheStatus.downloading || task.status == CacheStatus.pending) task.status = CacheStatus.paused;
    }
    tasks.refresh();
  }

  Future<void> clearAll() async {
    for (final uuid in _running.keys.toList()) {
      _cancelRun(uuid);
    }
    tasks.clear();
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    final list = tasks.toList();
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    tasks.assignAll(list);
  }

  @override
  void onClose() {
    _closed = true;
    for (final uuid in _running.keys.toList()) {
      _cancelRun(uuid);
    }
    super.onClose();
  }
}

class _QueueRun {
  _QueueRun(this.task);
  final ChapterCacheTask task;
  bool valid = true;
}
