import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/link/phone_link.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _ProbePhone extends PhoneLink {
  _ProbePhone({
    required MemoryLinkStore store,
    required MemoryLinkNetwork network,
  }) : super(
         store: store,
         nodeFactory: (identity, _) async => network.node(identity.id),
       );

  int networkChecks = 0, checks = 0;

  @override
  void networkChanged() {
    networkChecks++;
    super.networkChanged();
  }

  @override
  Future<void> verifyConnections({
    Duration timeout = const Duration(milliseconds: 60),
    Duration quietFor = const Duration(milliseconds: 5),
  }) {
    checks++;
    return super.verifyConnections(timeout: timeout, quietFor: quietFor);
  }
}

class _OfflinePhone extends PhoneLink {
  _OfflinePhone() : super(store: MemoryLinkStore());

  final checking = Completer<void>();
  final retried = <String>[];

  @override
  List<KeptDesktop> get desktops => const [
    KeptDesktop(id: 'online', name: '合成在线电脑', publicKey: ''),
    KeptDesktop(id: 'offline', name: '合成离线电脑', publicKey: ''),
  ];

  @override
  Set<String> get onlineIds => {'online'};

  @override
  Future<void> verifyConnections({
    Duration timeout = const Duration(seconds: 4),
    Duration quietFor = const Duration(milliseconds: 800),
  }) => checking.future;

  @override
  Future<void> retryNow(String desktopId) async {
    retried.add(desktopId);
  }
}

class _Harness {
  _Harness({LinkConnection Function(LinkConnection)? wrap}) {
    node = network.node(identity.id);
    node.incoming.listen((connection) {
      final number = ++connections;
      unawaited(
        LinkPeer.accept(
          wrap?.call(connection) ?? connection,
          onRequest: (method, params) => _handle(number, method, params),
        ).then(peers.add),
      );
    });
    phone = _ProbePhone(store: store, network: network);
    state = AppState(store: store, link: phone);
  }

  final network = MemoryLinkNetwork();
  final store = MemoryLinkStore();
  final identity = LinkIdentity.generate();
  late final MemoryLinkNode node;
  late final _ProbePhone phone;
  late final AppState state;
  final peers = <LinkPeer>[];
  final calls = <String>[];
  final windows = <int>[];
  final payloadBytes = <int>[];
  final history = [
    for (var i = 0; i < 600; i++)
      {'t': 'text', 'text': '合成消息 $i ${List.filled(128, '测').join()}'},
  ];
  int connections = 0, from = 0;
  bool trusted = false;
  Completer<void>? holdState, holdOpen;
  Completer<void>? stateStarted, openStarted;

  Map<String, Object?> get device => {
    'name': '仅内存合成电脑',
    'direct': true,
    'relays': <String>[],
    'addrs': ['127.0.0.1:47100'],
  };

  Map<String, Object?> snapshot() => {
    'session': 'synthetic-session',
    'start': 0,
    'count': history.length - from,
    'items': history.sublist(from),
    'earlier': from > 0,
    'live': false,
  };

  Future<Object?> _handle(
    int connection,
    String method,
    Map<String, Object?> params,
  ) async {
    calls.add('$connection:$method');
    switch (method) {
      case LinkMethods.hello:
        return {'device': device, if (!trusted) 'pairing': true};
      case LinkMethods.confirm:
        trusted = true;
        return null;
      case LinkMethods.state:
        final gate = holdState;
        holdState = null;
        if (gate != null) {
          stateStarted?.complete();
          await gate.future;
        }
        return {'device': device, 'projects': [], 'bots': []};
      case LinkMethods.open:
        final gate = holdOpen;
        holdOpen = null;
        if (gate != null) {
          openStarted?.complete();
          await gate.future;
        }
        final window = params['window'] as int;
        windows.add(window);
        from = math.max(0, history.length - window);
        final result = snapshot();
        payloadBytes.add(utf8.encode(jsonEncode(result)).length);
        return result;
      case LinkMethods.earlier:
        final before = from;
        from = math.max(0, from - (params['count'] as int));
        return {'items': history.sublist(from, before), 'earlier': from > 0};
      case LinkMethods.close:
        return null;
      default:
        throw StateError('诊断只允许合成配对和只读请求：$method');
    }
  }

  Future<void> start() async {
    await state.initialize();
    final attempt = await phone.pair(
      PairingOffer(
        name: '仅内存合成电脑',
        key: identity.publicKey,
        token: randomBytes(16),
        expires: DateTime.now().add(const Duration(minutes: 1)),
        addrs: ['127.0.0.1:47100'],
        direct: true,
      ).uri,
    );
    await phone.confirmPairing(attempt);
    await state.openSession(identity.id, 'synthetic-session');
    await pumpEventQueue();
  }

  Future<void> close() async {
    state.dispose();
    for (final peer in peers) {
      await peer.close();
    }
    await node.close();
  }
}

// 模拟真实 QUIC 同一条流的串行写入：大响应未写完，小响应不能插队。
class _SlowControl {
  bool enabled = false;
  final started = Completer<void>();
  final release = Completer<void>();
}

class _SerialConnection implements LinkConnection {
  _SerialConnection(this.delegate, this.slow);
  final LinkConnection delegate;
  final _SlowControl slow;
  bool first = true;

  @override
  Stream<LinkStream> get incoming => delegate.incoming.map((stream) {
    if (!first) return stream;
    first = false;
    return _SerialStream(stream, slow);
  });
  @override
  Future<LinkStream> open() => delegate.open();
  @override
  String get remote => delegate.remote;
  @override
  Future<String> get closed => delegate.closed;
  @override
  bool get isClosed => delegate.isClosed;
  @override
  Future<LinkPath> path() => delegate.path();
  @override
  Stream<LinkPath> get paths => delegate.paths;
  @override
  void close([int code = 0]) => delegate.close(code);
}

class _SerialStream implements LinkStream {
  _SerialStream(this.delegate, this.slow);
  final LinkStream delegate;
  final _SlowControl slow;
  Future<void> tail = Future.value();

  @override
  Future<void> send(Uint8List message) {
    return tail = tail.then((_) async {
      if (slow.enabled && message.length > 10000) {
        if (!slow.started.isCompleted) slow.started.complete();
        await slow.release.future;
      }
      await delegate.send(message);
    });
  }

  @override
  Stream<Uint8List> get messages => delegate.messages;
  @override
  Future<void> finish() => delegate.finish();
  @override
  void reset() => delegate.reset();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channels = [
    MethodChannel('local.baocode.mobile/platform'),
    MethodChannel('local.baocode.mobile/discovery'),
  ];
  setUp(() {
    for (final channel in channels) {
      messenger.setMockMethodCallHandler(channel, (_) async => null);
    }
  });
  tearDown(() {
    for (final channel in channels) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });

  test('后台收到的会话更新立即进入缓存，短暂返回不重复拉取', () async {
    final h = _Harness();
    addTearDown(h.close);
    await h.start();
    final before = h.windows.length;
    h.state.setForeground(false);
    h.history.last['text'] = '后台已收到的新内容';
    h.peers.last.emit(LinkEvents.session, h.snapshot());
    await pumpEventQueue();
    expect(h.state.buffer(h.identity.id, 'synthetic-session').items.last, {
      't': 'text',
      'text': '后台已收到的新内容',
    });
    h.state.setForeground(true);
    await h.state.resume();
    expect(h.windows, hasLength(before));
    expect(h.connections, 1);
    expect(h.state.buffer(h.identity.id, 'synthetic-session').loading, isFalse);
  });

  test('大历史响应堵住控制流时，连接探测不误重连或重复打开', () async {
    final slow = _SlowControl();
    final h = _Harness(
      wrap: (connection) => _SerialConnection(connection, slow),
    );
    addTearDown(h.close);
    await h.start();
    h.calls.clear();
    slow.enabled = true;
    Object? refreshError;
    final refreshing = h.state
        .refreshSession(h.identity.id, 'synthetic-session')
        .catchError((Object error) {
          refreshError = error;
        });
    await slow.started.future;
    try {
      await h.phone.verifyConnections();
      expect(h.connections, 1);
      expect(h.calls.where((call) => call.endsWith(':open')), hasLength(1));
    } finally {
      slow.release.complete();
      await refreshing;
    }
    expect(refreshError, isNull);
    expect(h.state.buffer(h.identity.id, 'synthetic-session').loading, isFalse);
  });

  test('回前台先检查连接，失效后只在新连接打开一次订阅', () async {
    final h = _Harness();
    addTearDown(h.close);
    await h.start();
    final oldState = h.holdState = Completer<void>();
    h.stateStarted = Completer<void>();
    h.calls.clear();

    final resumed = h.state.resume();
    await h.stateStarted!.future;
    await pumpEventQueue();
    expect(h.connections, 1);
    expect(h.calls, ['1:state']);
    expect(h.state.buffer(h.identity.id, 'synthetic-session').loading, isFalse);

    await resumed.timeout(const Duration(seconds: 2));
    await pumpEventQueue();
    expect(h.connections, 2);
    expect(h.calls, contains('2:hello'));
    expect(h.calls.where((call) => call == '2:open'), hasLength(1));
    expect(h.state.buffer(h.identity.id, 'synthetic-session').loading, isFalse);
    expect(h.state.buffer(h.identity.id, 'synthetic-session').error, isNull);
    oldState.complete();
    await pumpEventQueue();
    expect(h.connections, 2);
  });

  test('同连接其他请求已成功时，单次探测超时不拆掉活连接', () async {
    final h = _Harness();
    addTearDown(h.close);
    await h.start();
    final gate = h.holdState = Completer<void>();
    h.stateStarted = Completer<void>();
    h.calls.clear();
    final before = h.windows.length;

    final resumed = h.state.resume();
    await h.stateStarted!.future;
    await h.state.refreshSession(h.identity.id, 'synthetic-session');
    expect(h.connections, 1);
    expect(h.windows, hasLength(before + 1));
    expect(h.state.buffer(h.identity.id, 'synthetic-session').loading, isFalse);
    expect(h.state.buffer(h.identity.id, 'synthetic-session').error, isNull);
    expect(h.phone.onlineIds, contains(h.identity.id));

    await resumed.timeout(const Duration(seconds: 2));
    await pumpEventQueue();
    expect(h.connections, 1);
    expect(h.calls, isNot(contains('2:hello')));
    gate.complete();
    await pumpEventQueue();
  });

  test('慢同步中再次唤醒会通知网络并重新检查，仍复用当前快照请求', () async {
    final h = _Harness();
    addTearDown(h.close);
    await h.start();
    final gate = h.holdOpen = Completer<void>();
    h.openStarted = Completer<void>();
    final first = h.state.resume();
    await h.openStarted!.future;
    await pumpEventQueue();
    final notifications = h.phone.networkChecks;
    final checks = h.phone.checks;
    final opens = h.calls.where((call) => call == '1:open').length;

    final second = h.state.resume();
    await pumpEventQueue();
    expect(h.phone.networkChecks, notifications + 1);
    expect(h.phone.checks, checks + 1);
    expect(h.calls.where((call) => call == '1:open'), hasLength(opens));
    expect(h.state.buffer(h.identity.id, 'synthetic-session').loading, isTrue);

    gate.complete();
    await Future.wait([first, second]);
    expect(h.state.buffer(h.identity.id, 'synthetic-session').loading, isFalse);
  });

  test('一台电脑的检查未完成时，其他离线电脑仍立即开始重试', () async {
    final phone = _OfflinePhone();
    final state = AppState(store: MemoryLinkStore(), link: phone);
    final resumed = state.resume();
    await pumpEventQueue();
    try {
      expect(phone.retried, ['offline']);
    } finally {
      phone.checking.complete();
      await resumed;
      state.dispose();
    }
  });

  test('探测开始前发出的请求迟到回复不能掩盖当前请求方向失效', () async {
    final h = _Harness();
    addTearDown(h.close);
    await h.start();
    final oldOpen = h.holdOpen = Completer<void>();
    h.openStarted = Completer<void>();
    final oldRefresh = h.state.refreshSession(
      h.identity.id,
      'synthetic-session',
    );
    await h.openStarted!.future;
    final gate = h.holdState = Completer<void>();
    h.stateStarted = Completer<void>();
    final resumed = h.state.resume();
    await h.stateStarted!.future;
    oldOpen.complete();
    await oldRefresh;
    await resumed.timeout(const Duration(seconds: 2));
    expect(h.connections, 2);
    gate.complete();
    await pumpEventQueue();
  });

  test('明确的远端拒绝同样证明往返可用，不因另一个探测超时重连', () async {
    final h = _Harness();
    addTearDown(h.close);
    await h.start();
    final gate = h.holdState = Completer<void>();
    h.stateStarted = Completer<void>();
    final resumed = h.state.resume();
    await h.stateStarted!.future;
    await expectLater(
      h.state.request(h.identity.id, '只读合成拒绝'),
      throwsA(isA<LinkRemoteException>()),
    );
    await resumed.timeout(const Duration(seconds: 2));
    expect(h.connections, 1);
    gate.complete();
    await pumpEventQueue();
  });

  test('只有单向事件不能证明请求能送达，探测超时仍重连', () async {
    final h = _Harness();
    addTearDown(h.close);
    await h.start();
    final gate = h.holdState = Completer<void>();
    h.stateStarted = Completer<void>();
    final received = h.phone.events.firstWhere(
      (event) => event.name == '合成单向事件',
    );
    final resumed = h.state.resume();
    await h.stateStarted!.future;
    h.peers.single.emit('合成单向事件');
    await received.timeout(const Duration(seconds: 1));
    await resumed.timeout(const Duration(seconds: 2));
    expect(h.connections, 2);
    gate.complete();
    await pumpEventQueue();
  });

  test('同时核对同一连接时只发送一次探测', () async {
    final h = _Harness();
    addTearDown(h.close);
    await h.start();
    final gate = h.holdState = Completer<void>();
    h.stateStarted = Completer<void>();
    h.calls.clear();
    final first = h.phone.verifyConnections();
    final second = h.phone.verifyConnections();
    await h.stateStarted!.future;
    await pumpEventQueue();
    expect(h.calls, ['1:state']);
    gate.complete();
    await Future.wait([first, second]);
    expect(h.connections, 1);
  });

  test('连续唤醒合并连接检查和快照请求', () async {
    final h = _Harness();
    addTearDown(h.close);
    await h.start();
    h.calls.clear();
    final first = h.state.resume();
    final second = h.state.resume();
    await Future.wait([first, second]);
    expect(h.calls.where((call) => call == '1:state'), hasLength(1));
    expect(h.calls.where((call) => call == '1:open'), hasLength(1));
    expect(h.connections, 1);
  });

  test('回前台保留已展开的600条历史窗口和索引', () async {
    final h = _Harness();
    addTearDown(h.close);
    await h.start();
    expect(h.windows.last, 60);
    final shortBytes = h.payloadBytes.last;
    while (h.state.buffer(h.identity.id, 'synthetic-session').earlier == true) {
      await h.state.loadEarlier(h.identity.id, 'synthetic-session');
    }
    expect(
      h.state.buffer(h.identity.id, 'synthetic-session').items,
      hasLength(600),
    );

    await h.state.resume();
    expect(h.windows.last, 600);
    expect(h.payloadBytes.last, greaterThan(shortBytes * 9));
    expect(
      h.state.buffer(h.identity.id, 'synthetic-session').items,
      hasLength(600),
    );
    debugPrint(
      '合成快照 JSON：60条=$shortBytes 字节，600条=${h.payloadBytes.last} 字节；不代表公网耗时',
    );
  });
}
