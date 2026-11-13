// YCode — GPL-3.0-only.
import 'dart:async';

import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/link/link_store.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

class _Seen extends AppState {
  _Seen(LinkStore store, this.current) : super(demo: true, store: store);
  SessionSummary current;
  @override
  List<SessionRef> get sessions => [SessionRef('demo-desktop', current)];
}

/// 跟着一个对话，模型菜单由测试来换。
class _Switching extends _Seen {
  _Switching(super.store, super.current);
  final followed = SessionBuffer('demo-desktop', 'a');
  void pick(String id, String provider) => followed.choices = [
    LinkChoice(
      kind: 'model',
      selected: id,
      options: [LinkOption(id: id, label: id.split('/').last, group: provider)],
    ),
  ];
  @override
  SessionBuffer? peekBuffer(String desktopId, String sessionId) => followed;
}

class _FailingStore extends MemoryLinkStore {
  _FailingStore({this.failRead = false});
  final bool failRead;
  int writes = 0;

  @override
  Future<String?> read(String key) async {
    if (failRead) throw StateError('secure storage is locked');
    return super.read(key);
  }

  @override
  Future<void> write(String key, String value) async {
    // 只数看过记录的写入：打开对话时记下的模型也会写。
    if (key == 'seen_sessions') writes++;
    throw StateError('secure storage is full');
  }
}

class _SlowStore extends MemoryLinkStore {
  final pending = <Completer<void>>[];

  @override
  Future<void> write(String key, String value) async {
    if (key != 'seen_sessions') return super.write(key, value);
    final turn = Completer<void>();
    pending.add(turn);
    await turn.future;
    await super.write(key, value);
  }
}

SessionSummary _session(String id, DateTime updatedAt) => SessionSummary(
  id: id,
  project: 'p',
  title: id,
  updatedAt: updatedAt,
  unread: true,
);

void main() {
  test('换到别的上游的模型时记下何时换成了什么，同一个上游里换不记', () async {
    final store = MemoryLinkStore();
    final state = _Switching(store, _session('a', DateTime(2026)));
    addTearDown(state.dispose);
    await state.initialize();
    // 开一次对话，手机就看一眼它的模型菜单。
    Future<void> seen() async {
      await state.openSession('demo-desktop', 'a');
      await pumpEventQueue();
      await state.closeSession('demo-desktop', 'a');
      await pumpEventQueue();
    }

    state.pick('@acme/claude-sonnet-5-5', 'acme');
    await seen();
    state.pick('@acme/claude-opus-5-5', 'acme');
    await seen();
    expect(state.modelMarks('demo-desktop', 'a'), isEmpty);
    state.pick('@buddy/deepseek-v4.1-flash', 'buddy');
    await seen();
    expect(state.modelMarks('demo-desktop', 'a').map((mark) => mark.label), [
      'deepseek-v4.1-flash',
    ]);

    final again = _Seen(store, _session('a', DateTime(2026)));
    addTearDown(again.dispose);
    await again.initialize();
    expect(again.modelMarks('demo-desktop', 'a'), hasLength(1));
  });

  test('对话的模型重启后还记得；电脑正在说的优先', () async {
    final store = MemoryLinkStore();
    await store.write(
      'session_models',
      '{"demo-desktop/s": {"id": "@acme/deepseek-v4.1-flash", '
          '"label": "DeepSeek V4.1 Flash", "provider": "acme"}}',
    );
    final state = _Seen(store, _session('s', DateTime(2026)));
    addTearDown(state.dispose);
    await state.initialize();
    final ref = state.sessions.single;
    expect(state.sessionModel(ref)?.label, 'DeepSeek V4.1 Flash');
    expect(state.sessionModel(ref)?.provider, 'acme');

    state.current = SessionSummary(
      id: 's',
      project: 'p',
      title: 's',
      updatedAt: DateTime(2026),
      model: 'claude-opus-5-5',
    );
    expect(state.sessionModel(state.sessions.single)?.id, 'claude-opus-5-5');
  });

  group('本地内容损坏不影响启动', () {
    for (final key in [
      'settings',
      'drafts',
      'seen_sessions',
      'session_models',
    ]) {
      test('$key 不是 JSON', () async {
        final store = MemoryLinkStore();
        await store.write(key, '{坏掉的内容');
        final state = AppState(demo: true, store: store);
        addTearDown(state.dispose);
        await state.initialize();
        expect(state.ready, isTrue);
        expect(state.startupError, isNull);
      });
    }

    test('settings 字段类型不对', () async {
      final store = MemoryLinkStore();
      await store.write('settings', '{"language": 1, "name": []}');
      final state = AppState(demo: true, store: store);
      addTearDown(state.dispose);
      await state.initialize();
      expect(state.startupError, isNull);
    });

    test('读不了存储仍然报启动失败，可以重试', () async {
      final state = AppState(demo: true, store: _FailingStore(failRead: true));
      addTearDown(state.dispose);
      await state.initialize();
      expect(state.startupError, isNotNull);
    });
  });

  group('做完的对话看过一次就不再算未读', () {
    final session = _session('a', DateTime(2026));

    test('打开后不再未读，退出重进也记得；有新结果才再算', () async {
      final store = MemoryLinkStore();
      final state = _Seen(store, session);
      addTearDown(state.dispose);
      await state.initialize();
      expect(state.sessionUnread(state.sessions.single), isTrue);

      await state.openSession('demo-desktop', 'a');
      expect(state.sessionUnread(state.sessions.single), isFalse);

      final again = _Seen(store, session);
      addTearDown(again.dispose);
      await again.initialize();
      expect(again.sessionUnread(again.sessions.single), isFalse);

      again.current = _session('a', DateTime(2026, 2));
      expect(again.sessionUnread(again.sessions.single), isTrue);
    });

    test('开在前台屏幕上时做完不算未读，退到后台才算，关掉也算看过', () async {
      final state = _Seen(MemoryLinkStore(), session);
      addTearDown(state.dispose);
      await state.initialize();
      await state.openSession('demo-desktop', 'a');
      state.current = _session('a', DateTime(2026, 2));
      expect(state.sessionUnread(state.sessions.single), isFalse);
      state.foreground = false;
      expect(state.sessionUnread(state.sessions.single), isTrue);
      state.foreground = true;
      await state.closeSession('demo-desktop', 'a');
      expect(state.sessionUnread(state.sessions.single), isFalse);
    });

    test('同一段对话开着两页，关掉一页仍算正在看', () async {
      final state = _Seen(MemoryLinkStore(), session);
      addTearDown(state.dispose);
      await state.initialize();
      await state.openSession('demo-desktop', 'a');
      await state.openSession('demo-desktop', 'a');
      await state.closeSession('demo-desktop', 'a');
      state.current = _session('a', DateTime(2026, 2));
      expect(state.sessionUnread(state.sessions.single), isFalse);
      await state.closeSession('demo-desktop', 'a');
      state.current = _session('a', DateTime(2026, 3));
      expect(state.sessionUnread(state.sessions.single), isTrue);
    });

    test('写不进存储也不抛错，这次运行里仍然算看过', () async {
      final store = _FailingStore();
      final state = _Seen(store, session);
      addTearDown(state.dispose);
      await state.initialize();
      await state.openSession('demo-desktop', 'a');
      await pumpEventQueue();
      expect(store.writes, 1);
      expect(state.sessionUnread(state.sessions.single), isFalse);
    });

    test('连续看过时依次写入，晚记的不会被早记的盖掉', () async {
      final store = _SlowStore();
      final state = _Seen(store, session);
      addTearDown(state.dispose);
      await state.initialize();
      await state.openSession('demo-desktop', 'a');
      state.current = _session('a', DateTime(2026, 2));
      await state.closeSession('demo-desktop', 'a');
      await pumpEventQueue();
      expect(store.pending, hasLength(1), reason: '前一次写完才开始下一次');
      store.pending.first.complete();
      await pumpEventQueue();
      expect(store.pending, hasLength(2));
      store.pending.last.complete();
      await pumpEventQueue();

      final again = _Seen(store, state.current);
      addTearDown(again.dispose);
      await again.initialize();
      expect(again.sessionUnread(again.sessions.single), isFalse);
    });
  });
}
