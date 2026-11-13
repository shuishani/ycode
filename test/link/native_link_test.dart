import 'package:bao_link/bao_link_io.dart';
import 'package:baocode_mobile/link/phone_link.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/fixture_desktop.dart';

void main() {
  test('真实 iroh 本机直连完成配对、消息与重连，不连接共享中继', () async {
    final identity = LinkIdentity.generate();
    final desktopNode = await IrohLinkNode.bind(
      identity: identity,
      relays: [],
      accept: true,
    );
    final fixture = await FixtureDesktop.start(
      identity: identity,
      node: desktopNode,
    );
    final phone = PhoneLink(
      store: MemoryLinkStore(),
      nodeFactory: (identity, relays) async => _LoopbackNode(
        await IrohLinkNode.bind(identity: identity, relays: []),
      ),
    );
    addTearDown(() async {
      phone.dispose();
      await fixture.close();
    });
    final attempt = await phone.pair(fixture.offer.uri);
    await phone.confirmPairing(attempt);
    expect(phone.onlineIds, {identity.id});
    final hellos = fixture.calls
        .where((method) => method == LinkMethods.hello)
        .length;
    await phone.verifyConnections();
    expect(phone.onlineIds, {identity.id});
    expect(
      fixture.calls.where((method) => method == LinkMethods.hello),
      hasLength(hellos),
      reason: '真实 iroh 独立流探测成功，不应重连',
    );
    final events = phone.events.firstWhere(
      (event) => event.name == LinkEvents.session,
    );
    await phone.call(identity.id, LinkMethods.open, {
      'session': 'fixture-session',
    });
    expect((await events).desktopId, identity.id);
    await phone.call(identity.id, LinkMethods.send, {
      'session': 'fixture-session',
      'text': '仅本机合成测试',
    });
    final state = await phone.call(identity.id, LinkMethods.open, {
      'session': 'fixture-session',
    }) as Map;
    expect((state['items'] as List).last, {
      't': 'text',
      'text': '已收到本地测试消息：仅本机合成测试。没有调用模型或执行代码。',
    });
    await phone.reconnect(identity.id);
    expect(phone.onlineIds, {identity.id});
    expect(
      fixture.calls.where((method) => method == LinkMethods.send),
      hasLength(1),
    );
  });
}

/// 测试只允许环回 UDP 提示，不允许把运行时默认中继带到外部网络。
class _LoopbackNode implements LinkNode {
  _LoopbackNode(this.delegate);
  final LinkNode delegate;
  @override
  String get id => delegate.id;
  @override
  Stream<LinkConnection> get incoming => delegate.incoming;
  @override
  Stream<LinkNodeInfo> get changes => delegate.changes;
  @override
  Future<LinkConnection> connect(
    LinkAddress address, {
    Duration timeout = const Duration(seconds: 15),
  }) {
    final local = address.addrs
        .where((addr) => addr.startsWith('127.0.0.1:'))
        .toList();
    if (local.isEmpty) throw StateError('本机测试拒绝非环回地址');
    return delegate.connect(
      LinkAddress(address.id, addrs: local),
      timeout: timeout,
    );
  }

  @override
  Future<LinkNodeInfo> info() => delegate.info();
  @override
  void networkChanged() => delegate.networkChanged();
  @override
  Future<void> close() => delegate.close();
}
