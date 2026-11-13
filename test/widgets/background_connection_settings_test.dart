import 'package:baocode_mobile/state/background_connection.dart';
import 'package:baocode_mobile/ui/settings/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_test_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ChatTestState state;
  var permission = true;
  var running = false;
  var reject = false;
  var battery = true;
  final calls = <String>[];
  final platformCalls = <String>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const platform = MethodChannel('local.baocode.mobile/platform');

  setUp(() {
    state = ChatTestState(zh: true);
    permission = true;
    running = false;
    reject = false;
    battery = true;
    calls.clear();
    platformCalls.clear();
    messenger.setMockMethodCallHandler(platform, (call) async {
      platformCalls.add(call.method);
      return switch (call.method) {
        'notificationPermission' ||
        'requestNotificationPermission' => permission,
        'batteryUnrestricted' => battery,
        _ => null,
      };
    });
    messenger.setMockMethodCallHandler(BackgroundConnection.channel, (
      call,
    ) async {
      calls.add(call.method);
      if (call.method == 'start') {
        if (reject) {
          throw PlatformException(code: 'start_failed', message: '不应显示的原始错误');
        }
        running = true;
      } else if (call.method == 'stop') {
        running = false;
      }
      return {'running': running};
    });
  });
  tearDown(() {
    state.dispose();
    messenger.setMockMethodCallHandler(platform, null);
    messenger.setMockMethodCallHandler(BackgroundConnection.channel, null);
  });

  testWidgets('后台连接默认关闭，原生确认后开启，关闭后实际停止', (tester) async {
    await tester.pumpWidget(MaterialApp(home: NotificationsPage(state: state)));
    await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('background-connection'));
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(calls, ['start']);
    expect(state.settings.keepBackgroundConnection, isTrue);
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(calls, ['start', 'stop']);
    expect(state.settings.keepBackgroundConnection, isFalse);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
  });

  testWidgets('系统还在省电时，开启后台连接会请求允许后台运行并留下入口', (tester) async {
    battery = false;
    await tester.pumpWidget(MaterialApp(home: NotificationsPage(state: state)));
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('battery-unrestricted'));
    expect(row, findsNothing, reason: '没开后台连接时不打扰');
    await tester.tap(find.byKey(const ValueKey('background-connection')));
    await tester.pumpAndSettle();
    expect(platformCalls, contains('requestBatteryUnrestricted'));
    expect(row, findsOneWidget);
    platformCalls.clear();
    await tester.tap(find.text('去允许'));
    await tester.pumpAndSettle();
    expect(platformCalls, ['requestBatteryUnrestricted']);
  });

  testWidgets('已经允许后台运行就不弹也不显示', (tester) async {
    await tester.pumpWidget(MaterialApp(home: NotificationsPage(state: state)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('background-connection')));
    await tester.pumpAndSettle();
    expect(platformCalls, isNot(contains('requestBatteryUnrestricted')));
    expect(find.byKey(const ValueKey('battery-unrestricted')), findsNothing);
  });

  testWidgets('通知未授权时不能悄悄启动后台连接', (tester) async {
    permission = false;
    await tester.pumpWidget(MaterialApp(home: NotificationsPage(state: state)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('background-connection')));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    expect(state.settings.keepBackgroundConnection, isFalse);
  });

  testWidgets('服务启动失败保持关闭并显示归类错误，不泄露异常原文', (tester) async {
    reject = true;
    await tester.pumpWidget(MaterialApp(home: NotificationsPage(state: state)));
    await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('background-connection'));
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    expect(state.settings.keepBackgroundConnection, isFalse);
    expect(find.textContaining('不应显示的原始错误'), findsNothing);
    expect(find.text('手机系统没能完成这个操作，请稍后重试。'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
