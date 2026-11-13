import 'dart:async';
import 'dart:typed_data';

import 'package:bao_link/bao_link.dart';
import 'package:flutter_test/flutter_test.dart';

class _FailingStream implements LinkStream {
  _FailingStream(this._inner, this._owner);

  final LinkStream _inner;
  final _FailingConnection _owner;

  @override
  Stream<Uint8List> get messages => _inner.messages;

  @override
  Future<void> send(Uint8List message) async {
    final delayed = _owner.delayedWrite;
    if (delayed != null) {
      _owner.delayedWrite = null;
      if (_owner.forwardBeforeDelay) await _inner.send(message);
      await delayed.future;
      return;
    }
    if (_owner.failSends) {
      _owner.failedSends++;
      throw _owner.error;
    }
    await _inner.send(message);
  }

  @override
  Future<void> finish() => _inner.finish();

  @override
  void reset() {
    _owner.resets++;
    _inner.reset();
  }
}

class _FailingConnection implements LinkConnection {
  _FailingConnection(this._inner);

  final LinkConnection _inner;
  final error = const LinkClosedException('合成写入失败');
  bool failSends = false, forwardBeforeDelay = false;
  int failedSends = 0, resets = 0;
  Completer<void>? delayedWrite, delayedOpen;

  @override
  String get remote => _inner.remote;

  @override
  Future<LinkStream> open() async {
    final stream = _FailingStream(await _inner.open(), this);
    final gate = delayedOpen;
    delayedOpen = null;
    await gate?.future;
    return stream;
  }

  @override
  Stream<LinkStream> get incoming =>
      _inner.incoming.map((stream) => _FailingStream(stream, this));

  @override
  Future<String> get closed => _inner.closed;

  @override
  bool get isClosed => _inner.isClosed;

  @override
  Future<LinkPath> path() => _inner.path();

  @override
  Stream<LinkPath> get paths => _inner.paths;

  @override
  void close([int code = 0]) => _inner.close(code);
}

const _timeout = Duration(milliseconds: 80);

void main() {
  Future<(LinkPeer, LinkPeer, _FailingConnection)> pair({
    bool failDesktop = false,
  }) async {
    final (phoneEnd, desktopEnd) = MemoryLinkConnection.pair(
      a: 'phone',
      b: 'desktop',
    );
    final failing = _FailingConnection(failDesktop ? desktopEnd : phoneEnd);
    final accepting = LinkPeer.accept(
      failDesktop ? failing : desktopEnd,
      onRequest: (method, params) => '合成应答:$method',
    );
    final phone = await LinkPeer.connect(failDesktop ? phoneEnd : failing);
    expect(await phone.call('ping'), '合成应答:ping');
    final desktop = await accepting;
    addTearDown(() async {
      await phone.close();
      await desktop.close();
    });
    return (phone, desktop, failing);
  }

  Future<Object> failure(Future<Object?> call) async {
    try {
      await call;
    } on Object catch (error) {
      return error;
    }
    fail('合成请求不应成功');
  }

  test('控制请求写失败立即返回原始错误，不等待超时且不重放消息', () async {
    final (phone, desktop, failing) = await pair();
    failing.failSends = true;
    final error = await failure(
      phone.call(LinkMethods.send, {'text': '仅合成消息'}, _timeout),
    );
    expect(error, same(failing.error));
    expect(failing.failedSends, 1);
    expect(phone.isClosed, isFalse);
    expect(desktop.isClosed, isFalse);
  });

  test('独立大消息流写失败返回原始错误，而不是依赖对端空流复位', () async {
    final (phone, _, failing) = await pair();
    failing.failSends = true;
    final error = await failure(phone.call(LinkMethods.read, {}, _timeout));
    expect(error, same(failing.error));
    expect(failing.failedSends, 1);
    expect(phone.isClosed, isFalse);
  });

  test('独立探测的超时包含开流等待，迟到的流复位且不发送请求', () async {
    final (phone, desktop, failing) = await pair();
    var stateCalls = 0;
    desktop.onRequest = (method, params) {
      if (method == LinkMethods.state) stateCalls++;
      return null;
    };
    final gate = failing.delayedOpen = Completer<void>();
    final error = await failure(
      phone.probe(_timeout).timeout(const Duration(milliseconds: 500)),
    );
    gate.complete();
    await pumpEventQueue();
    expect((error as TimeoutException).duration, _timeout);
    expect(failing.resets, 1);
    expect(stateCalls, 0);
    expect(phone.isClosed, isFalse);
  });

  test('一次写失败不会破坏恢复后的后续请求', () async {
    final (phone, _, failing) = await pair();
    failing.failSends = true;
    expect(
      await failure(phone.call('ping', {}, _timeout)),
      same(failing.error),
    );
    failing.failSends = false;
    expect(await phone.call('ping', {}, _timeout), '合成应答:ping');
  });

  test('请求超时后迟到的写失败不会影响下一次请求', () async {
    final (phone, _, failing) = await pair();
    final delayed = failing.delayedWrite = Completer<void>();
    expect(
      await failure(phone.call('ping', {}, _timeout)),
      isA<TimeoutException>(),
    );
    delayed.completeError(failing.error);
    await pumpEventQueue();
    expect(await phone.call('ping', {}, _timeout), '合成应答:ping');
    expect(phone.isClosed, isFalse);
  });

  test('应答先到时迟到的写失败不会重复结束请求或误关连接', () async {
    final (phone, _, failing) = await pair();
    final delayed = failing.delayedWrite = Completer<void>();
    failing.forwardBeforeDelay = true;
    expect(await phone.call('ping', {}, _timeout), '合成应答:ping');
    delayed.completeError(failing.error);
    await pumpEventQueue();
    expect(await phone.call('ping', {}, _timeout), '合成应答:ping');
    expect(phone.isClosed, isFalse);
  });

  test('无请求调用方接收错误的控制事件写失败会结束连接', () async {
    final (phone, _, failing) = await pair();
    failing.failSends = true;
    phone.emit('合成事件');
    await phone.done.timeout(_timeout);
    expect(phone.isClosed, isTrue);
    expect(failing.failedSends, 1);
  });

  test('控制应答写失败会结束连接并通知等待中的请求', () async {
    final (phone, desktop, failing) = await pair(failDesktop: true);
    failing.failSends = true;
    final error = await failure(phone.call('ping', {}, _timeout));
    expect(error, isA<LinkClosedException>());
    expect(desktop.isClosed, isTrue);
  });

  test('独立流已收到明确远端拒绝时不额外复位完整应答', () async {
    final (phone, desktop, failing) = await pair();
    desktop.onRequest = (method, params) =>
        throw const LinkRemoteException('notFound', '合成只读拒绝');
    final error = await failure(phone.call(LinkMethods.read, {}, _timeout));
    expect(error, isA<LinkRemoteException>());
    expect(failing.resets, 0);
    expect(phone.isClosed, isFalse);
  });

  test('独立大消息流应答写失败仅复位该流，不破坏控制通道', () async {
    final (phone, desktop, failing) = await pair(failDesktop: true);
    failing.failSends = true;
    final error = await failure(phone.call(LinkMethods.read, {}, _timeout));
    expect(error, isA<LinkClosedException>());
    expect(phone.isClosed, isFalse);
    expect(desktop.isClosed, isFalse);
    failing.failSends = false;
    expect(await phone.call('ping', {}, _timeout), '合成应答:ping');
  });
}
