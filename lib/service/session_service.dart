import 'dart:async';

class SessionChanged implements Exception {
  const SessionChanged();
}

/// Shares only short local commits; network work must stay outside this queue.
class SessionCoordinator {
  static final instance = SessionCoordinator();
  int generation = 0;
  bool blocked = false;
  Future<void> _tail = Future.value();
  int invalidate() {
    blocked = true;
    return ++generation;
  }

  void release() {
    blocked = false;
  }

  bool isCurrent(int token) => !blocked && token == generation;
  Future<T> serialize<T>(Future<T> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }
}

/// Ownership is captured before async work; a retry cannot adopt an older callback.
class LoginAttemptGate {
  LoginAttemptGate(this.session);
  final SessionCoordinator session;
  int generation = -1;
  int? _savingGeneration;
  void adopt(int token) {
    generation = token;
    _savingGeneration = null;
  }

  bool owns(int token) => token == generation && session.isCurrent(token);
  bool beginSave(int token) {
    if (!owns(token) || _savingGeneration == token) return false;
    _savingGeneration = token;
    return true;
  }

  void finishSave(int token) {
    if (_savingGeneration == token) _savingGeneration = null;
  }
}
