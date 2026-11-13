import 'dart:async';

import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/state/session_subscriptions.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> snapshot(List<Object?> items, {bool earlier = true}) => {
  'session': 'session',
  'start': 0,
  'count': items.length,
  'items': items,
  'earlier': earlier,
};

class Harness {
  Harness() {
    subscriptions = SessionSubscriptions(
      request: request,
      onChanged: () => changes++,
      tr: (zh, _) => zh,
    );
  }
  late final SessionSubscriptions subscriptions;
  final opens = <Completer<Object?>>[];
  final windows = <Object?>[];
  final pages = <Completer<Object?>>[];
  int closes = 0, changes = 0;
  Future<Object?> request(
    String desktop,
    String method,
    Map<String, Object?> params,
  ) {
    switch (method) {
      case LinkMethods.open:
        windows.add(params['window']);
        final pending = Completer<Object?>();
        opens.add(pending);
        return pending.future;
      case LinkMethods.earlier:
        final pending = Completer<Object?>();
        pages.add(pending);
        return pending.future;
      case LinkMethods.close:
        closes++;
        return Future.value();
      default:
        throw StateError('A subscription must never write: $method');
    }
  }

  Future<void> follow([List<Object?> items = const [1, 2]]) async {
    final ready = subscriptions.retain('desktop', 'session');
    opens.last.complete(snapshot(items));
    await ready;
  }
}

void main() {
  test('连续连接恢复时复用完整基线，不再打开快照', () async {
    final h = Harness();
    addTearDown(h.subscriptions.dispose);
    await h.follow();
    h.subscriptions.accept('desktop', {
      'session': 'session',
      'start': 1,
      'count': 2,
      'items': [3],
    });
    await h.subscriptions.refreshRetained(
      (_) => true,
      keepCurrent: (_, _) => true,
    );
    expect(h.opens, hasLength(1));
    expect(h.subscriptions.buffer('desktop', 'session').items, [1, 3]);
    expect(h.subscriptions.buffer('desktop', 'session').loading, isFalse);
  });

  test('断线后即使保留旧内容，也必须重建基线', () async {
    final h = Harness();
    addTearDown(h.subscriptions.dispose);
    await h.follow();
    h.subscriptions.connectionChanged('desktop', online: false);
    final resumed = h.subscriptions.refreshRetained(
      (_) => true,
      keepCurrent: (_, _) => true,
    );
    expect(h.opens, hasLength(2));
    expect(h.subscriptions.buffer('desktop', 'session').items, [1, 2]);
    h.opens.last.complete(snapshot([3, 4]));
    await resumed;
    expect(h.subscriptions.buffer('desktop', 'session').items, [3, 4]);
  });

  test('two pages share a subscription until the last page closes', () async {
    final h = Harness();
    addTearDown(h.subscriptions.dispose);
    await h.follow();
    await h.subscriptions.retain('desktop', 'session');
    expect(h.opens.length, 1);
    await h.subscriptions.release('desktop', 'session', online: true);
    expect(h.closes, 0);
    h.subscriptions.accept('desktop', {
      'session': 'session',
      'start': 1,
      'count': 2,
      'items': [3],
    });
    expect(h.subscriptions.buffer('desktop', 'session').items, [1, 3]);
    await h.subscriptions.release('desktop', 'session', online: true);
    expect(h.closes, 1);
  });

  test(
    'updates during snapshot loading are applied after the snapshot',
    () async {
      final h = Harness();
      addTearDown(h.subscriptions.dispose);
      final ready = h.subscriptions.retain('desktop', 'session');
      h.subscriptions.accept('desktop', {
        'session': 'session',
        'start': 1,
        'count': 2,
        'items': [3],
      });
      h.opens.single.complete(snapshot([1, 2]));
      await ready;
      expect(h.subscriptions.buffer('desktop', 'session').items, [1, 3]);
    },
  );

  test('重新同步不缩回已经翻出来的窗口，少于 60 条时仍取 60 条', () async {
    final h = Harness();
    addTearDown(h.subscriptions.dispose);
    final loaded = [for (var i = 0; i < 90; i++) i];
    await h.follow(loaded);
    Future<void> resync() async {
      final refreshing = h.subscriptions.refresh('desktop', 'session');
      h.opens.last.complete(snapshot(loaded));
      await refreshing;
    }

    await resync();
    expect(h.windows, [60, 90]);
    h.subscriptions.buffer('desktop', 'session').items.removeRange(10, 90);
    final refreshing = h.subscriptions.refresh('desktop', 'session');
    h.opens.last.complete(snapshot(loaded.sublist(0, 10)));
    await refreshing;
    expect(h.windows.last, 60);
  });

  test('a history page is prepended before applying queued deltas', () async {
    final h = Harness();
    addTearDown(h.subscriptions.dispose);
    await h.follow([3, 4]);
    final page = h.subscriptions.earlier('desktop', 'session');
    h.subscriptions.accept('desktop', {
      'session': 'session',
      'start': 3,
      'count': 4,
      'items': [5],
    });
    h.pages.single.complete({
      'items': [1, 2],
      'earlier': false,
    });
    await page;
    expect(h.subscriptions.buffer('desktop', 'session').items, [1, 2, 3, 5]);
  });

  test('历史分页失败后重新同步索引，但仍向页面报告失败以便手动重试', () async {
    final h = Harness();
    addTearDown(h.subscriptions.dispose);
    await h.follow([3, 4]);
    final failure = StateError('历史分页失败');
    final page = h.subscriptions.earlier('desktop', 'session');
    final checked = expectLater(page, throwsA(same(failure)));
    h.pages.single.completeError(failure);
    await Future<void>.delayed(Duration.zero);
    expect(h.opens, hasLength(2));
    h.opens.last.complete(snapshot([3, 4]));
    await checked;
    final buffer = h.subscriptions.buffer('desktop', 'session');
    expect(buffer.items, [3, 4]);
    expect(buffer.loadingEarlier, false);
    expect(buffer.loading, false);
  });

  test('reconnect discards a stale history result instead of corrupting new indexes', () async {
    final h = Harness();
    addTearDown(h.subscriptions.dispose);
    await h.follow([3, 4]);
    final oldPage = h.subscriptions.earlier('desktop', 'session');
    h.subscriptions.connectionChanged('desktop', online: false);
    h.subscriptions.connectionChanged('desktop', online: true);
    final refreshed = h.subscriptions.refresh('desktop', 'session');
    h.opens.last.complete(snapshot([8, 9], earlier: false));
    await refreshed;
    h.pages.single.complete({
      'items': [1, 2],
      'earlier': false,
    });
    await oldPage;
    expect(h.subscriptions.buffer('desktop', 'session').items, [8, 9]);
    expect(h.subscriptions.buffer('desktop', 'session').loadingEarlier, false);
  });

  test(
    'late snapshot cannot overwrite the snapshot of a new connection',
    () async {
      final h = Harness();
      addTearDown(h.subscriptions.dispose);
      final old = h.subscriptions.retain('desktop', 'session');
      h.subscriptions.connectionChanged('desktop', online: false);
      h.subscriptions.connectionChanged('desktop', online: true);
      final refreshed = h.subscriptions.refresh('desktop', 'session');
      h.opens.last.complete(snapshot(['new']));
      await refreshed;
      h.opens.first.complete(snapshot(['old']));
      await old;
      expect(h.subscriptions.buffer('desktop', 'session').items, ['new']);
    },
  );

  test(
    'closing while a snapshot is pending never resurrects the closed history',
    () async {
      final h = Harness();
      addTearDown(h.subscriptions.dispose);
      final pending = h.subscriptions.retain('desktop', 'session');
      await h.subscriptions.release('desktop', 'session', online: true);
      h.opens.single.complete(snapshot(['late']));
      await pending;
      expect(h.subscriptions.buffer('desktop', 'session').items, isEmpty);
      expect(h.subscriptions.follows('desktop', 'session'), false);
    },
  );

  test('forgetting drops private history and ignores late events', () async {
    final h = Harness();
    addTearDown(h.subscriptions.dispose);
    await h.follow(['private']);
    h.subscriptions.forget('desktop');
    h.subscriptions.accept('desktop', snapshot(['late']));
    expect(h.subscriptions.buffer('desktop', 'session').items, isEmpty);
    expect(h.subscriptions.follows('desktop', 'session'), false);
  });

  test('invalid delta triggers a read-only resnapshot', () async {
    final h = Harness();
    addTearDown(h.subscriptions.dispose);
    await h.follow();
    h.subscriptions.accept('desktop', {
      'session': 'session',
      'start': 99,
      'count': 100,
      'items': [1],
    });
    expect(h.opens.length, 2);
    final refreshed = h.subscriptions.refresh('desktop', 'session');
    h.opens.last.complete(snapshot(['fresh']));
    await refreshed;
    expect(h.subscriptions.buffer('desktop', 'session').items, ['fresh']);
  });
}
