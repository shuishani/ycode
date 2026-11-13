import 'dart:async';
import 'dart:math' as math;

import 'package:bao_link/bao_link.dart';

import '../models/session_buffer.dart';

typedef SessionRequest = Future<Object?> Function(
  String desktopId,
  String method,
  Map<String, Object?> params,
);
typedef SessionKey = (String, String);
typedef SessionTr = String Function(String zh, String en);

/// Owns subscriptions, wire indexes and reads that can outlive a connection.
/// Only reads are retried. A second page shares the existing server subscription.
class SessionSubscriptions {
  SessionSubscriptions({
    required this.request,
    required this.onChanged,
    required this.tr,
  });

  final SessionRequest request;
  final void Function() onChanged;
  final SessionTr tr;
  final _buffers = <SessionKey, SessionBuffer>{};
  final _references = <SessionKey, int>{};
  final _operations = <SessionKey, _ReadOperation>{};
  final _baselines = <SessionKey>{};
  bool _disposed = false;

  SessionBuffer buffer(String desktop, String session) => _buffers.putIfAbsent((
    desktop,
    session,
  ), () => SessionBuffer(desktop, session));

  SessionBuffer? peek(String desktop, String session) =>
      _buffers[(desktop, session)];

  bool follows(String desktop, String session) =>
      _references.containsKey((desktop, session));

  Future<void> retain(String desktop, String session) {
    if (_disposed) throw StateError('Session subscriptions are disposed');
    final key = (desktop, session);
    _references.update(key, (count) => count + 1, ifAbsent: () => 1);
    if (_references[key]! > 1) {
      return _operations[key]?.done.future ?? Future<void>.value();
    }
    return refresh(desktop, session);
  }

  Future<void> release(
    String desktop,
    String session, {
    required bool online,
  }) async {
    final key = (desktop, session);
    final count = _references[key];
    if (count == null) return;
    if (count > 1) {
      _references[key] = count - 1;
      return;
    }
    _references.remove(key);
    _invalidate(key);
    if (online && !_disposed) {
      try {
        await request(desktop, LinkMethods.close, {'session': session});
      } on Object {
        /* A disconnected peer has already released the server subscription. */
      }
    }
  }

  Future<void> refresh(String desktop, String session) {
    final key = (desktop, session);
    if (_disposed || !_references.containsKey(key)) return Future<void>.value();
    final previous = _operations[key];
    if (previous != null && !previous.history) return previous.done.future;
    // A reconnect or explicit refresh supersedes an unfinished history page.
    _invalidate(key);
    final operation = _ReadOperation(history: false);
    _operations[key] = operation;
    final target = buffer(desktop, session)..loading = true;
    target.error = null;
    onChanged();
    _complete(operation, () async {
      try {
        final result = await request(desktop, LinkMethods.open, {
          'session': session,
          // 已经翻出来的不缩回去：序号和正在看的位置都靠它。
          'window': math.max(60, target.items.length),
        });
        if (!_current(key, operation)) return;
        target.apply(
          LinkSessionUpdate.fromJson(objectMap(result)),
          snapshot: true,
        );
        for (final update in operation.updates) {
          target.apply(update);
        }
        _baselines.add(key);
      } on Object {
        if (!_current(key, operation)) return;
        target.error = tr('内容没有更新，请重试', 'Could not refresh. Try again.');
        rethrow;
      } finally {
        if (_current(key, operation)) {
          _operations.remove(key);
          target.loading = false;
          onChanged();
        }
      }
    });
    return operation.done.future;
  }

  /// 回前台仅核对仍有页面订阅的会话，沿用 refresh 的并发去重和旧响应隔离。
  Future<void> refreshRetained(
    bool Function(String desktop) isOnline, {
    bool Function(String desktop, String session)? keepCurrent,
  }) async {
    await Future.wait([
      for (final key in _references.keys.toList())
        if (isOnline(key.$1) &&
            !(keepCurrent?.call(key.$1, key.$2) == true &&
                _baselines.contains(key) &&
                !_operations.containsKey(key) &&
                _buffers[key]?.error == null))
          () async {
            try {
              await refresh(key.$1, key.$2);
            } on Object {
              // refresh 已把失败保存在 buffer.error 并通知页面，不能伪装成已同步。
            }
          }(),
    ]);
  }

  Future<void> earlier(String desktop, String session) async {
    final key = (desktop, session);
    final target = buffer(desktop, session);
    if (_disposed ||
        !_references.containsKey(key) ||
        _operations.containsKey(key) ||
        target.earlier != true) {
      return;
    }
    final operation = _ReadOperation(history: true);
    _operations[key] = operation;
    target.loadingEarlier = true;
    target.error = null;
    onChanged();
    (Object, StackTrace)? failure;
    try {
      final result = await request(desktop, LinkMethods.earlier, {
        'session': session,
        'count': 50,
      });
      if (!_current(key, operation)) return;
      target.prepend(objectMap(result));
      for (final update in operation.updates) {
        target.apply(update);
      }
    } on Object catch (error, stack) {
      if (!_current(key, operation)) return;
      target.error = tr('内容没有更新，请重试', 'Could not refresh. Try again.');
      failure = (error, stack);
    } finally {
      if (_current(key, operation)) {
        _operations.remove(key);
        target.loadingEarlier = false;
        onChanged();
      }
      operation.done.complete();
    }
    if (failure case (final error, final stack)) {
      await refresh(desktop, session);
      Error.throwWithStackTrace(error, stack);
    }
  }

  void accept(String desktop, Object? json) {
    if (_disposed) return;
    final map = objectMap(json);
    final session = map['session'];
    if (session is! String || !_references.containsKey((desktop, session))) {
      return;
    }
    final key = (desktop, session);
    try {
      final update = LinkSessionUpdate.fromJson(map);
      final operation = _operations[key];
      if (operation != null) {
        operation.updates.add(update);
      } else {
        buffer(desktop, session).apply(update);
      }
    } on Object {
      unawaited(refresh(desktop, session).catchError((Object _) {}));
    }
    onChanged();
  }

  void connectionChanged(String desktop, {required bool online}) {
    for (final key
        in _references.keys.where((key) => key.$1 == desktop).toList()) {
      _invalidate(key);
      if (online) unawaited(refresh(key.$1, key.$2).catchError((Object _) {}));
    }
  }

  void forget(String desktop) {
    for (final key
        in _buffers.keys.where((key) => key.$1 == desktop).toList()) {
      _invalidate(key);
      _references.remove(key);
      _buffers.remove(key);
    }
  }

  bool _current(SessionKey key, _ReadOperation operation) =>
      !_disposed &&
      _references.containsKey(key) &&
      identical(_operations[key], operation);

  void _invalidate(SessionKey key) {
    _baselines.remove(key);
    _operations.remove(key);
    final target = _buffers[key];
    if (target != null) {
      target.loading = false;
      target.loadingEarlier = false;
    }
  }

  void _complete(_ReadOperation operation, Future<void> Function() body) {
    unawaited(
      body().then(
        (_) => operation.done.complete(),
        onError: (Object error, StackTrace trace) =>
            operation.done.completeError(error, trace),
      ),
    );
  }

  void dispose() {
    _disposed = true;
    _operations.clear();
    _baselines.clear();
    _references.clear();
    _buffers.clear();
  }
}

class _ReadOperation {
  _ReadOperation({required this.history});
  final bool history;
  final updates = <LinkSessionUpdate>[];
  final done = Completer<void>();
}
