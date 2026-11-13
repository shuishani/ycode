import 'package:baocode_mobile/link/phone_link.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:baocode_mobile/ui/settings/settings_page.dart';
import 'package:baocode_mobile/theme/app_theme.dart';
import 'package:baocode_mobile/ui/widgets/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Link extends PhoneLink {
  _Link() : super(store: MemoryLinkStore());
  int resets = 0;
  String? shown = '9C55 8DD3 6DA5 7FA7 7779 2F3B F9CC 90FC';

  @override
  String? get fingerprint => shown;

  @override
  Future<void> resetIdentity() async {
    resets++;
    shown = '1111 2222 3333 4444 5555 6666 7777 8888';
    notifyListeners();
  }
}

class _State extends AppState {
  _State(_Link link) : super(store: MemoryLinkStore(), link: link) {
    settings.language = 'zh';
  }
  final asked = <String>[];
  Object? Function(String desktopId)? answer;

  @override
  List<KeptDesktop> get desktops => const [
    KeptDesktop(id: 'developer', name: 'developer', publicKey: ''),
  ];
  @override
  String? get selectedDesktopId => 'developer';
  @override
  bool isOnline(String desktopId) => true;
  @override
  DesktopLinkStatus linkStatus(String desktopId) => DesktopLinkStatus.online;
  @override
  Future<Object?> request(
    String desktopId,
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    asked.add(method);
    return answer?.call(desktopId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Link link;
  late _State state;
  bool? permission;

  setUp(() {
    link = _Link();
    state = _State(link);
    permission = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('local.baocode.mobile/platform'),
          (call) async => switch (call.method) {
            'notificationPermission' => permission,
            'requestNotificationPermission' => permission,
            _ => null,
          },
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('local.baocode.mobile/platform'),
          null,
        );
    state.dispose();
  });

  for (final name in ['', '这是一个比较长的个人昵称']) {
    testWidgets('窄屏大字号下资料卡可打开资料：$name', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      state.settings.name = name;
      await tester.pumpWidget(
        MaterialApp(
          theme: MobileTheme.build(Brightness.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.4)),
            child: child!,
          ),
          home: SettingsPage(state: state),
        ),
      );
      final avatar = find.byType(LetterAvatar);
      final tile = find.ancestor(of: avatar, matching: find.byType(ListTile));
      expect(tester.takeException(), isNull);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(find.byType(MyProfilePage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('技能页按电脑显示四类扩展数量，有内容的可点进列表', (tester) async {
    state.answer = (_) => {
      'items': [
        for (var i = 0; i < 3; i++)
          {'kind': 'skill', 'name': 'skill-$i', 'scope': 'user'},
        {'kind': 'mcp', 'name': 'github', 'scope': 'user', 'description': '仓库'},
      ],
    };
    await tester.pumpWidget(MaterialApp(home: ExtensionsPage(state: state)));
    await tester.pumpAndSettle();
    expect(find.text('技能'), findsWidgets);
    expect(
      find.byKey(const ValueKey('desktop-switcher-button')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('extensions-skill')),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('extensions-plugin')),
        matching: find.text('0'),
      ),
      findsOneWidget,
    );
    expect(find.text('developer 上 Claude Code 的扩展。'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('extensions-mcp')));
    await tester.pumpAndSettle();
    // 列表按范围分组，只列名字；说明在详情页。
    expect(find.text('全局'), findsOneWidget);
    expect(find.text('github'), findsOneWidget);
    expect(find.text('仓库'), findsNothing);
    await tester.tap(find.text('github'));
    await tester.pumpAndSettle();
    expect(find.text('MCP'), findsOneWidget);
    expect(find.text('全局'), findsOneWidget);
    expect(find.text('说明'), findsOneWidget);
    expect(find.text('仓库'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    // 技能、插件、子代理用同一套列表与详情。
    await tester.tap(find.byKey(const ValueKey('extensions-skill')));
    await tester.pumpAndSettle();
    expect(find.text('全局'), findsOneWidget);
    await tester.tap(find.text('skill-0'));
    await tester.pumpAndSettle();
    expect(find.text('没有说明'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('安全页显示本机密钥指纹，重置需确认，确认后换新指纹', (tester) async {
    await tester.pumpWidget(MaterialApp(home: SecurityPage(state: state)));
    expect(find.text('密钥只在你的设备上'), findsOneWidget);
    expect(find.text('9C55  8DD3  6DA5  7FA7'), findsOneWidget);
    expect(find.text('7779  2F3B  F9CC  90FC'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('security-reset')));
    await tester.tap(find.byKey(const ValueKey('security-reset')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(link.resets, 0);

    await tester.tap(find.byKey(const ValueKey('security-reset')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '重置'));
    await tester.pumpAndSettle();
    expect(link.resets, 1);
    expect(find.text('1111  2222  3333  4444'), findsOneWidget);
  });

  testWidgets('系统未授权通知时开关显示关闭，并给出去开启入口', (tester) async {
    expect(state.settings.notifications, isTrue);
    await tester.pumpWidget(MaterialApp(home: NotificationsPage(state: state)));
    await tester.pumpAndSettle();
    expect(find.byType(SwitchListTile), findsNWidgets(4));
    for (final tile in tester.widgetList<SwitchListTile>(
      find.byType(SwitchListTile),
    )) {
      expect(tile.value, isFalse);
    }
    expect(find.byKey(const ValueKey('notifications-blocked')), findsOneWidget);

    permission = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    for (final key in ['notify-needs-input', 'notify-done', 'notify-bots']) {
      expect(
        tester.widget<SwitchListTile>(find.byKey(ValueKey(key))).value,
        isTrue,
      );
    }
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('background-connection')),
          )
          .value,
      isFalse,
    );
    expect(find.text('智能体需要我处理时'), findsOneWidget);
    expect(find.text('智能体完成时'), findsOneWidget);
    expect(find.text('Bot 发来消息时'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('notify-done')));
    await tester.pumpAndSettle();
    expect(state.settings.notifyDone, isFalse);
    expect(state.settings.notifyNeedsInput, isTrue);
    expect(find.byKey(const ValueKey('notifications-blocked')), findsNothing);
  });

  test('已配对时只主动申请一次通知权限', () async {
    final requested = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('local.baocode.mobile/platform'),
          (call) async {
            requested.add(call.method);
            return true;
          },
        );
    await state.askNotificationsOnce();
    await state.askNotificationsOnce();
    expect(
      requested.where((m) => m == 'requestNotificationPermission'),
      hasLength(1),
    );
    expect(state.settings.notificationsAsked, isTrue);
  });
}
