import 'dart:async';

import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/link/phone_link.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:baocode_mobile/state/background_connection.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Link extends PhoneLink {
  _Link() : super(store: MemoryLinkStore());
  int checks = 0, generation = 0;
  @override
  Future<void> initialize() async {}
  @override
  int connectionGenerationOf(String desktopId) => generation;
  @override
  List<KeptDesktop> get desktops => const [
    KeptDesktop(id: 'desk', name: '合成电脑', publicKey: ''),
  ];
  @override
  void networkChanged() {}
  @override
  Future<void> verifyConnections({
    Duration timeout = const Duration(seconds: 4),
    Duration quietFor = const Duration(milliseconds: 800),
  }) async {
    checks++;
  }
}

class _State extends AppState {
  _State(_Link link, {super.background})
    : super(store: MemoryLinkStore(), link: link);
  final opens = <String>[];
  Completer<void>? pending;
  bool fail = false;
  String text = '旧内容';
  @override
  bool isOnline(String desktopId) => true;
  @override
  Future<Object?> request(
    String desktopId,
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    if (method == LinkMethods.close) return null;
    if (method != LinkMethods.open) throw StateError('这里只允许同步读取：$method');
    opens.add(params['session']! as String);
    await pending?.future;
    if (fail) throw StateError('会话同步失败');
    return {
      'session': params['session'],
      'start': 0,
      'count': 1,
      'items': [
        {'t': 'text', 'text': text},
      ],
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const platform = MethodChannel('local.baocode.mobile/platform');
  const discovery = MethodChannel('local.baocode.mobile/discovery');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    messenger.setMockMethodCallHandler(platform, (_) async => null);
    messenger.setMockMethodCallHandler(discovery, (_) async => null);
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(platform, null);
    messenger.setMockMethodCallHandler(discovery, null);
  });

  test('冷启动以原生实际状态为准，不擅自重开已停止的后台服务', () async {
    final nativeCalls = <String>[];
    messenger.setMockMethodCallHandler(BackgroundConnection.channel, (
      call,
    ) async {
      nativeCalls.add(call.method);
      return {'running': false, 'networkWatching': true};
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        BackgroundConnection.channel,
        null,
      ),
    );
    final state = _State(_Link())..settings.keepBackgroundConnection = true;
    addTearDown(state.dispose);
    await state.initialize();
    expect(state.startupError, isNull);
    expect(nativeCalls, ['status']);
    expect(state.settings.keepBackgroundConnection, isFalse);
  });

  test('短暂切应用且同一连接基线完整时，合并探测但不重复拉快照', () async {
    final link = _Link();
    final state = _State(link);
    addTearDown(state.dispose);
    await state.openSession('desk', 'active');
    state.opens.clear();
    state.setForeground(false);
    state.setForeground(true);
    await Future.wait([state.resume(), state.resume()]);
    expect(state.opens, isEmpty);
    expect(link.checks, 1);
    expect(state.buffer('desk', 'active').items.single, {
      't': 'text',
      'text': '旧内容',
    });
    expect(state.buffer('desk', 'active').loading, isFalse);
  });

  test('后台间隔不确定或连接代次变化时仍拉快照，不能只信在线状态', () async {
    var now = DateTime(2026);
    final link = _Link();
    final state = _State(
      link,
      background: BackgroundConnection(now: () => now),
    );
    addTearDown(state.dispose);
    await state.openSession('desk', 'active');
    state.opens.clear();
    state.setForeground(false);
    now = now.add(const Duration(minutes: 2));
    state.setForeground(true);
    await state.resume();
    expect(state.opens, ['active']);
    state.opens.clear();
    state.setForeground(false);
    link.generation++;
    state.setForeground(true);
    await state.resume();
    expect(state.opens, ['active']);
  });

  test('切网后即使连接代次没有变化，也不能跳过内容核对', () async {
    final state = _State(_Link());
    addTearDown(state.dispose);
    await state.openSession('desk', 'active');
    state.opens.clear();
    state.setForeground(false);
    state.networkChanged();
    state.setForeground(true);
    await state.resume();
    expect(state.opens, ['active']);
  });

  test('未建立完整基线时，短暂切换也会重试，不把旧缓存当成已同步', () async {
    final state = _State(_Link())..fail = true;
    addTearDown(state.dispose);
    await expectLater(state.openSession('desk', 'active'), throwsStateError);
    state.opens.clear();
    state.fail = false;
    state.setForeground(false);
    state.setForeground(true);
    await state.resume();
    expect(state.opens, ['active']);
    expect(state.buffer('desk', 'active').error, isNull);
  });

  test('没有连续性依据时仍同步活跃会话，重复唤醒合并且不拉无订阅缓存', () async {
    final link = _Link();
    final state = _State(link);
    addTearDown(state.dispose);
    await state.openSession('desk', 'active');
    state.buffer('desk', 'closed').items.add({'t': 'text', 'text': '旧缓存'});
    state.opens.clear();
    state.text = '最新内容';
    state.pending = Completer<void>();
    final first = state.resume();
    final second = state.resume();
    await Future<void>.delayed(Duration.zero);
    expect(state.opens, ['active']);
    expect(link.checks, 1);
    expect(state.buffer('desk', 'active').loading, isTrue);
    expect(state.buffer('desk', 'active').items.single, {
      't': 'text',
      'text': '旧内容',
    });
    state.pending!.complete();
    await Future.wait([first, second]);
    expect(state.buffer('desk', 'active').items.single, {
      't': 'text',
      'text': '最新内容',
    });
    expect(state.buffer('desk', 'active').loading, isFalse);
    expect(state.buffer('desk', 'closed').items.single, {
      't': 'text',
      'text': '旧缓存',
    });
  });

  test('回前台同步失败保留旧内容与错误，不自动重放请求', () async {
    final state = _State(_Link());
    addTearDown(state.dispose);
    await state.openSession('desk', 'active');
    state.opens.clear();
    state.fail = true;
    await state.resume();
    final buffer = state.buffer('desk', 'active');
    expect(state.opens, ['active']);
    expect(buffer.items.single, {'t': 'text', 'text': '旧内容'});
    expect(buffer.loading, isFalse);
    // 界面显示归类后的一句话，原始异常不再直接铺在界面上。
    expect(buffer.error, isNotEmpty);
    expect(buffer.error, isNot(contains('会话同步失败')));
  });
}
