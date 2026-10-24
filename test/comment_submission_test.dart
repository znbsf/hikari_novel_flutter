import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:hikari_novel_flutter/models/resource.dart';
import 'package:hikari_novel_flutter/pages/comment/controller.dart';
import 'package:hikari_novel_flutter/pages/reply/controller.dart';
import 'package:hikari_novel_flutter/service/api_service.dart';
import 'package:hikari_novel_flutter/service/local_storage_service.dart';
import 'package:hive_ce/hive.dart';

class _SubmissionAdapter implements HttpClientAdapter {
  _SubmissionAdapter(this.respond);
  final Future<ResponseBody> Function(RequestOptions) respond;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) => respond(options);

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late ApiService api;
  late CommentController comment;
  late ReplyController reply;
  var status = 200;
  var body = '<html>submitted</html>';
  var networkFailure = false;
  Completer<void>? responseGate;
  late Completer<void> requested;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('hikari-submit-test-');
    await Get.put(LocalStorageService()).init(hivePath: directory.path);
    api = Get.put(ApiService());
    comment = CommentController(aid: '1');
    reply = ReplyController(aid: '1', rid: '2');
    comment.commentTitleController.text = 'title';
    comment.commentContentController.text = 'original comment';
    reply.replyContentController.text = 'original reply';
    status = 200;
    body = '<html>submitted</html>';
    networkFailure = false;
    responseGate = null;
    requested = Completer<void>();
    api.dio.httpClientAdapter = _SubmissionAdapter((options) async {
      if (!requested.isCompleted) requested.complete();
      await responseGate?.future;
      if (networkFailure) {
        throw DioException(requestOptions: options, type: DioExceptionType.connectionError);
      }
      return ResponseBody.fromBytes(body.codeUnits, status);
    });
  });

  tearDown(() async {
    comment.commentTitleController.dispose();
    comment.commentContentController.dispose();
    reply.replyContentController.dispose();
    api.dio.close();
    Get.reset();
    await Hive.close();
    Hive.resetAdapters();
    await directory.delete(recursive: true);
  });

  for (final responseStatus in [401, 500, 302]) {
    test('HTTP $responseStatus fails without discarding either draft', () async {
      status = responseStatus;
      expect(await api.sendReply(aid: '1', rid: '2', content: 'test reply'), isA<Error>());
      expect(await comment.sendComment(), 'network_error');
      expect(await reply.sendReply(), 'network_error');
      expect(comment.commentContentController.text, 'original comment');
      expect(reply.replyContentController.text, 'original reply');
    });
  }

  test('200 login HTML is a failure and preserves drafts', () async {
    body = '<form action="login.php"><input type="password"></form>';
    expect(await comment.sendComment(), 'network_error');
    expect(await reply.sendReply(), 'network_error');
    expect(comment.commentContentController.text, 'original comment');
    expect(reply.replyContentController.text, 'original reply');
  });

  test('network failures preserve drafts', () async {
    networkFailure = true;
    expect(await comment.sendComment(), 'network_error');
    expect(await reply.sendReply(), 'network_error');
    expect(comment.commentContentController.text, 'original comment');
    expect(reply.replyContentController.text, 'original reply');
  });

  test('200 site rejection and challenge preserve drafts', () async {
    for (final page in ['<div class="blocktitle">&#20986;&#29616;&#38169;&#35823;&#65281;</div>', '<div id="challenge-form"></div>']) {
      body = page;
      expect(await comment.sendComment(), 'network_error');
      expect(await reply.sendReply(), 'network_error');
      expect(comment.commentContentController.text, 'original comment');
      expect(reply.replyContentController.text, 'original reply');
    }
  });

  test('success clears only the submitted unmodified draft', () async {
    expect(await comment.sendComment(), 'send_successfully');
    expect(await reply.sendReply(), 'reply_successfully');
    expect(comment.commentContentController.text, isEmpty);
    expect(reply.replyContentController.text, isEmpty);
  });

  test('successful late response preserves edited comment and reply', () async {
    responseGate = Completer<void>();
    final submittingComment = comment.sendComment();
    await requested.future;
    comment.commentContentController.text = 'new comment draft';
    responseGate!.complete();
    await submittingComment;
    responseGate = Completer<void>();
    requested = Completer<void>();
    final submittingReply = reply.sendReply();
    await requested.future;
    reply.replyContentController.text = 'new reply draft';
    responseGate!.complete();
    await submittingReply;
    expect(comment.commentContentController.text, 'new comment draft');
    expect(reply.replyContentController.text, 'new reply draft');
  });

  test('editing the title also preserves the comment draft', () async {
    responseGate = Completer<void>();
    final submitting = comment.sendComment();
    await requested.future;
    comment.commentTitleController.text = 'new title';
    responseGate!.complete();
    await submitting;
    expect(comment.commentContentController.text, 'original comment');
  });
}
