import 'dart:async';

import 'package:flutter/foundation.dart';

import 'app_state.dart';

class ConversationTarget {
  const ConversationTarget({this.sessionId, this.available = true});
  final String? sessionId;
  final bool available;
}

/// 身份与执行会话分离：普通会话固定，Bot 的当前会话可以更换。
class ConversationBinding extends ChangeNotifier {
  ConversationBinding({
    required this.retain,
    required this.release,
    required this.refreshSession,
    this.verifyTarget,
    this.errorMessage,
    this._sessionId,
  });

  final Future<void> Function(String session) retain, release, refreshSession;
  final Future<ConversationTarget> Function()? verifyTarget;
  final String Function(Object error)? errorMessage;

  String _message(Object error) =>
      errorMessage?.call(error) ??
      AppState.phrase('内容没有更新，请重试', 'Could not refresh. Try again.');
  String? _sessionId, _active, _provisional;
  bool _online = false,
      _available = true,
      _disposed = false,
      _verifying = false;
  int _generation = 0, _identity = 0;
  Future<void> _work = Future.value();
  String? error;

  String? get sessionId => _sessionId;
  bool get available => _available;

  /// 每一次读写（发送、编辑、校验）的版本：任何变化都会推进，用来丢弃过期的结果。
  int get generation => _generation;

  /// 会话身份：只有换了会话或它变得不可用时才推进。断线重连期间还是同一个
  /// 会话，打开的设置弹层因此不用关掉重开。
  int get identity => _identity;
  Future<void> get settled => _work;

  void update({
    required String? sessionId,
    required bool online,
    bool available = true,
    bool verified = false,
  }) {
    if (_disposed) return;
    if (available &&
        online &&
        !verified &&
        _provisional != null &&
        sessionId != _provisional) {
      error = AppState.phrase(
        '会话切换待核对',
        'Conversation change needs confirmation',
      );
      _verify();
      _notify();
      return;
    }
    if (verified || sessionId == _provisional || !online || !available) {
      _provisional = null;
    }
    if (_sessionId == sessionId &&
        _online == online &&
        _available == available) {
      if (verified) {
        error = null;
        _notify();
      }
      return;
    }
    _generation++;
    // 只换连接状态时身份不变：重连的是同一个会话，不算换了一个。
    if (sessionId != _sessionId || available != _available) _identity++;
    _sessionId = sessionId;
    _online = online;
    _available = available;
    error = null;
    _schedule();
    _notify();
  }

  bool acceptSent(String actual, int sentGeneration) {
    if (_disposed || !_available || !_online || actual.isEmpty) return false;
    if (sentGeneration != _generation && actual != _sessionId) {
      error = AppState.phrase(
        '发送结果未确认，当前会话已变化',
        'Send result unconfirmed; conversation changed',
      );
      _notify();
      return false;
    }
    if (actual != _sessionId) {
      if (verifyTarget == null && _sessionId != null) {
        error = AppState.phrase(
          '发送返回了其他会话，结果未确认',
          'Send returned a different conversation',
        );
        _notify();
        return false;
      }
      update(sessionId: actual, online: true, verified: true);
      if (verifyTarget != null) {
        _provisional = actual;
        _verify();
      }
    }
    return true;
  }

  void _verify() {
    final verify = verifyTarget;
    if (_disposed || _verifying || verify == null) return;
    _verifying = true;
    final generation = _generation;
    unawaited(() async {
      try {
        final target = await verify();
        if (_disposed || generation != _generation) return;
        update(
          sessionId: target.sessionId,
          online: _online,
          available: target.available,
          verified: true,
        );
      } on Object {
        if (!_disposed && generation == _generation) {
          error = AppState.phrase(
            '无法确认 Bot 当前会话，请刷新核对',
            'Cannot confirm the current bot conversation. Refresh and check.',
          );
          _notify();
        }
      } finally {
        _verifying = false;
        if (!_disposed && generation != _generation && _provisional != null) {
          _verify();
        }
      }
    }());
  }

  Future<void> refresh() async {
    if (_disposed) return;
    if (_provisional != null) _verify();
    await settled;
    final active = _active;
    final generation = _generation;
    if (active == null || !_online || !_available) return;
    try {
      await refreshSession(active);
      if (!_disposed && generation == _generation && _provisional == null) {
        error = null;
      }
    } on Object catch (failure) {
      if (!_disposed && generation == _generation) error = _message(failure);
    }
    _notify();
  }

  void _schedule() {
    _work = _work.then((_) => _reconcile());
  }

  Future<void> _reconcile() async {
    while (true) {
      final desired = !_disposed && _online && _available ? _sessionId : null;
      if (_active == desired) return;
      final old = _active;
      if (old != null) {
        _active = null;
        try {
          await release(old);
        } on Object catch (failure) {
          if (!_disposed) error = _message(failure);
        }
        continue;
      }
      if (desired == null) return;
      _active = desired;
      final generation = _generation;
      try {
        await retain(desired);
      } on Object catch (failure) {
        if (!_disposed && generation == _generation) error = _message(failure);
      }
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _schedule();
    super.dispose();
  }
}
