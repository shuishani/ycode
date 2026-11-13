import 'dart:async';

import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/link/phone_link.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:baocode_mobile/theme/app_theme.dart';
import 'package:baocode_mobile/ui/devices/device_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Link extends PhoneLink {
  _Link() : super(store: MemoryLinkStore());
  final reconnects = <(String, bool)>[];
  Completer<void>? pending;

  @override
  Future<void> reconnect(
    String desktopId, {
    bool reportFailure = false,
    bool background = false,
  }) async {
    reconnects.add((desktopId, reportFailure));
    await pending?.future;
  }
}

class _State extends AppState {
  _State(_Link link) : super(store: MemoryLinkStore(), link: link) {
    settings.language = 'zh';
  }
  final requests = <String>[];
  bool needsPairing = false;

  /// What the test puts in place of the live session list.
  List<SessionRef>? sessionsOverride;
  @override
  List<SessionRef> get sessions => sessionsOverride ?? super.sessions;

  @override
  List<KeptDesktop> get desktops => const [
    KeptDesktop(id: 'online', name: '在线电脑', publicKey: ''),
    KeptDesktop(id: 'offline', name: '离线电脑', publicKey: ''),
  ];
  @override
  bool isOnline(String desktopId) => desktopId == 'online';
  @override
  DesktopLinkStatus linkStatus(String desktopId) => desktopId == 'online'
      ? DesktopLinkStatus.online
      : needsPairing
      ? DesktopLinkStatus.needsPairing
      : DesktopLinkStatus.offline;
  @override
  List<ProjectRef> get projects => [
    for (var i = 0; i < 30; i++)
      ProjectRef(
        'online',
        ProjectInfo(id: '/p$i', name: '项目 $i', path: '/p$i'),
      ),
    const ProjectRef(
      'online',
      ProjectInfo(id: 'ssh://devbox/home/app', name: '远程项目', path: '/home/app'),
    ),
  ];
  @override
  Future<Object?> request(
    String desktopId,
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    requests.add(method);
    return null;
  }
}

Finder get panel => find.byKey(const ValueKey('dropdown-panel'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const platform = MethodChannel('local.baocode.mobile/platform');
  const events = MethodChannel('local.baocode.mobile/discovery');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late _Link link;
  late _State state;
  late List<String> discoveryCalls;
  Completer<void>? discoveryPending;
  bool discoveryFails = false;

  setUp(() {
    link = _Link();
    state = _State(link);
    discoveryCalls = [];
    discoveryPending = null;
    discoveryFails = false;
    messenger.setMockMethodCallHandler(events, (_) async => null);
    messenger.setMockMethodCallHandler(platform, (call) async {
      discoveryCalls.add(call.method);
      if (call.method == 'discoveryRefresh') {
        if (discoveryFails) {
          throw PlatformException(code: 'scan', message: '局域网不可用');
        }
        await discoveryPending?.future;
      }
      return null;
    });
  });

  tearDown(() async {
    state.dispose();
    await Future<void>.delayed(Duration.zero);
    messenger.setMockMethodCallHandler(platform, null);
    messenger.setMockMethodCallHandler(events, null);
  });

  Future<void> openDevices(WidgetTester tester) async {
    await state.discovery.start();
    await tester.pumpWidget(
      MaterialApp(
        theme: MobileTheme.build(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showDeviceMenu(context, state, selectedId: 'online'),
              child: const Text('打开设备'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开设备'));
    await tester.pumpAndSettle();
  }

  testWidgets('设备列表贴着按钮弹出，点外面关闭，当前设备高亮', (tester) async {
    await openDevices(tester);
    expect(find.byType(BottomSheet), findsNothing);
    expect(
      tester.getTopLeft(panel).dy,
      greaterThan(tester.getBottomLeft(find.byType(TextButton).first).dy),
    );
    final row = find.byKey(const ValueKey('device-online'));
    final material = tester.widget<Material>(
      find.descendant(of: row, matching: find.byType(Material)).first,
    );
    expect(material.color, isNot(Colors.transparent));
    expect(link.reconnects, isEmpty);
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    expect(state.selectedDesktopId, 'online');
    expect(link.reconnects, isEmpty);
  });

  Future<Badge> openWithSessions(
    WidgetTester tester,
    List<SessionRef> sessions,
  ) async {
    state.sessionsOverride = sessions;
    await openDevices(tester);
    return tester.widget<Badge>(
      find.descendant(
        of: find.byKey(const ValueKey('device-offline')),
        matching: find.byType(Badge),
      ),
    );
  }

  SessionRef session(
    String desktop,
    String id, {
    LinkSessionStatus status = LinkSessionStatus.idle,
    bool unread = false,
  }) => SessionRef(
    desktop,
    SessionSummary(
      id: id,
      project: 'p',
      title: id,
      updatedAt: DateTime(2026),
      status: status,
      unread: unread,
    ),
  );

  testWidgets('别的电脑上做完没看的对话标在它那一行，在跑的不算', (tester) async {
    final badge = await openWithSessions(tester, [
      session('online', 'a', unread: true),
      session('offline', 'b', unread: true),
      session('offline', 'c', status: LinkSessionStatus.running, unread: true),
    ]);
    expect(badge.isLabelVisible, isTrue);
    // 一个点，不写条数。
    expect(badge.label, isNull);
    // 正看着的这台：不在切换面板里重复标，红点在底部对话标签上。
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('device-online')),
        matching: find.byType(Badge),
      ),
      findsNothing,
    );
  });

  testWidgets('等着你看的时候只点一个红点，不写数字', (tester) async {
    final badge = await openWithSessions(tester, [
      session('offline', 'b', status: LinkSessionStatus.needsInput),
      session('offline', 'c', unread: true),
    ]);
    expect(badge.isLabelVisible, isTrue);
    expect(badge.label, isNull);
  });

  testWidgets('设备列表在窄屏大字号下不溢出，重连和关闭仍可点', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 28, bottom: 24);
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await openDevices(tester);
    expect(tester.takeException(), isNull);
    final scroll = find.descendant(
      of: panel,
      matching: find.byType(SingleChildScrollView),
    );
    expect(tester.getBottomLeft(scroll).dy, lessThanOrEqualTo(616));
    await tester.tap(find.text('重连'));
    await tester.pumpAndSettle();
    expect(link.reconnects, [('offline', true)]);
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('重新检测刷新发现并重连离线电脑，不打断在线电脑，检测状态看得见', (tester) async {
    await openDevices(tester);
    expect(link.reconnects, isEmpty);
    final before = discoveryCalls
        .where((call) => call == 'discoveryRefresh')
        .length;
    discoveryPending = Completer<void>();
    await tester.tap(find.text('重新检测'));
    await tester.pump();
    expect(find.text('检测中…'), findsOneWidget);
    await tester.tap(find.text('检测中…'));
    await tester.pump();
    expect(
      discoveryCalls.where((call) => call == 'discoveryRefresh').length,
      before + 1,
    );
    // 只重连离线的那台，在线的不动。
    expect(link.reconnects, [('offline', true)]);
    discoveryPending!.complete();
    await tester.pump(const Duration(milliseconds: 300));
    // 原生刷新立即返回时，检测状态也至少停留片刻，不会一闪而过。
    expect(find.text('检测中…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('重新检测'), findsOneWidget);
    expect(find.text('已检测，未发现其他电脑'), findsOneWidget);
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
  });

  testWidgets('重新检测失败明确显示错误并保留重试入口', (tester) async {
    await openDevices(tester);
    discoveryFails = true;
    await tester.tap(find.text('重新检测'));
    await tester.pumpAndSettle();
    expect(find.textContaining('局域网发现不可用'), findsOneWidget);
    expect(find.text('重新检测'), findsOneWidget);
    discoveryFails = false;
    await tester.tap(find.text('重新检测'));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.textContaining('局域网发现不可用'), findsNothing);
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
  });

  testWidgets('仅离线设备可手动重连，防重复点击且不切换设备，失败可见', (tester) async {
    await openDevices(tester);
    link.pending = Completer<void>();
    expect(find.text('重连'), findsOneWidget);
    await tester.tap(find.text('重连'));
    await tester.pump();
    expect(link.reconnects, [('offline', true)]);
    expect(find.text('重连中…'), findsOneWidget);
    await tester.tap(find.text('重连中…'));
    await tester.pump();
    expect(link.reconnects, hasLength(1));
    expect(panel, findsOneWidget);
    expect(state.selectedDesktopId, 'online');
    link.pending!.completeError(StateError('连接失败示例'));
    await tester.pumpAndSettle();
    // 原始异常（可能带系统错误码）不铺到界面上，只给一句能行动的话。
    expect(find.textContaining('连接失败示例'), findsNothing);
    expect(find.textContaining('操作没有成功'), findsOneWidget);
    expect(find.text('重连'), findsOneWidget);
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
  });

  testWidgets('需要重新配对的设备不提供无效重连', (tester) async {
    state.needsPairing = true;
    await openDevices(tester);
    expect(find.text('重连'), findsNothing);
    expect(find.text('重新配对'), findsOneWidget);
    expect(link.reconnects, isEmpty);
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
  });

  testWidgets('重连等待中关闭弹层，异步结束不访问已销毁页面', (tester) async {
    await openDevices(tester);
    link.pending = Completer<void>();
    await tester.tap(find.text('重连'));
    await tester.pump();
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    link.pending!.completeError(StateError('关闭后失败'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
