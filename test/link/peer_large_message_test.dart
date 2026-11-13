import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bao_link/bao_link.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _encode(Map<String, Object?> message) =>
    Uint8List.fromList(utf8.encode(jsonEncode(message)));

void main() {
  test('解析大历史响应时让出界面事件循环', () async {
    final (client, server) = MemoryLinkConnection.pair();
    final accepting = LinkPeer.accept(server);
    final phone = await LinkPeer.connect(client);
    final desktop = await accepting;
    addTearDown(phone.close);
    addTearDown(desktop.close);
    final text = List.filled(1024 * 1024, '测').join();
    var yielded = false;
    desktop.onRequest = (method, params) {
      Timer.run(() => yielded = true);
      return {'text': text};
    };
    final result = await phone.call(LinkMethods.open, {'session': '合成会话'});
    expect((result as Map)['text'], text);
    expect(yielded, isTrue, reason: '大 JSON 不能占住界面直到解析和应答全部结束');
  });

  test('大响应后立即结束控制流，先交付最后的应答再结束连接', () async {
    final (client, server) = MemoryLinkConnection.pair();
    final phone = await LinkPeer.connect(client);
    final control = await server.incoming.first;
    addTearDown(phone.close);
    final text = List.filled(256 * 1024, '测').join();
    final completed = <String>[];
    final reply = phone.call('合成请求').then((answer) {
      completed.add('应答');
      return answer;
    });
    final closed = phone.done.then((_) => completed.add('结束'));
    await control.send(_encode({'id': 1, 'r': text}));
    await control.finish();
    expect(await reply, text);
    await closed;
    expect(completed, ['应答', '结束']);
  });

  test('大快照异步解析后仍先建立基线再应用后续增量', () async {
    final (client, server) = MemoryLinkConnection.pair();
    final phone = await LinkPeer.connect(client, mirror: LinkSessionMirror());
    final control = await server.incoming.first;
    addTearDown(phone.close);
    final received = <LinkEvent>[];
    final subscription = phone.events.listen(received.add);
    addTearDown(subscription.cancel);
    final text = List.filled(512 * 1024, '测').join();
    final opening = phone.call(LinkMethods.open, {'session': '合成会话'});
    await control.send(
      _encode({
        'id': 1,
        'r': {
          'session': '合成会话',
          'start': 0,
          'count': 1,
          'items': [
            {'t': 'text', 'text': text},
          ],
        },
      }),
    );
    final updated = phone.events.firstWhere(
      (event) =>
          event.name == LinkEvents.session &&
          ((event.data as Map)['items'] as List).isNotEmpty &&
          (((event.data as Map)['items'] as List).last as Map)['text'] ==
              '$text追加',
    );
    await control.send(
      _encode({
        'ev': LinkEvents.session,
        'p': {
          'session': '合成会话',
          'start': 1,
          'count': 1,
          'items': <Object?>[],
          'partial': true,
          'append': {
            'index': 0,
            'path': ['text'],
            'text': '追加',
          },
        },
      }),
    );
    await opening;
    await updated.timeout(const Duration(seconds: 5));
    expect(received.map((event) => event.name), [
      LinkEvents.session,
      LinkEvents.session,
    ]);
  });
}
