import 'dart:async';

import 'package:baocode_mobile/state/background_connection.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  var running = false;
  var rejectStart = false;
  setUp(() {
    running = false;
    rejectStart = false;
    messenger.setMockMethodCallHandler(BackgroundConnection.channel, (
      call,
    ) async {
      if (call.method == 'start') {
        if (rejectStart) {
          throw PlatformException(code: 'notification_permission_denied');
        }
        running = true;
      } else if (call.method == 'stop') {
        running = false;
      }
      return {'running': running};
    });
  });
  tearDown(
    () =>
        messenger.setMockMethodCallHandler(BackgroundConnection.channel, null),
  );

  Future<void> nativeEvent(String method, [Object? arguments]) async {
    final done = Completer<void>();
    ServicesBinding.instance.channelBuffers.push(
      BackgroundConnection.channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall(method, arguments),
      ),
      (_) => done.complete(),
    );
    await done.future;
  }

  test('原生停止更新真实状态，切网使后台连续性失效', () async {
    final background = BackgroundConnection();
    addTearDown(background.dispose);
    var stopped = 0, networks = 0;
    background.onStopped = () => stopped++;
    background.onNetworkChanged = () => networks++;
    await background.initialize();
    await background.start(title: '后台连接', body: '接收更新', stopLabel: '停止');
    background.beginBackground();
    await nativeEvent('networkChanged');
    expect(networks, 1);
    expect(background.finishBackground(), isFalse);
    await nativeEvent('statusChanged', {
      'running': false,
      'networkWatching': true,
    });
    expect(background.running, isFalse);
    expect(stopped, 1);
    await nativeEvent('statusChanged', {
      'running': false,
      'networkWatching': true,
    });
    expect(stopped, 1);
  });

  test('默认关闭，只有原生确认启动后才显示运行，关闭后停止', () async {
    final background = BackgroundConnection();
    addTearDown(background.dispose);
    await background.initialize();
    expect(background.running, isFalse);
    await background.start(title: '后台连接', body: '接收更新', stopLabel: '停止');
    expect(background.running, isTrue);
    await background.stop();
    expect(background.running, isFalse);
  });

  test('启动被拒不伪装运行，并保留可展示的失败', () async {
    rejectStart = true;
    final background = BackgroundConnection();
    addTearDown(background.dispose);
    await background.initialize();
    await expectLater(
      background.start(title: '后台连接', body: '接收更新', stopLabel: '停止'),
      throwsA(isA<PlatformException>()),
    );
    expect(background.running, isFalse);
    expect(background.error, isA<PlatformException>());
  });

  test('短暂切换可复用，但未知时长或切网后必须核对快照', () {
    var now = DateTime(2026);
    final background = BackgroundConnection(now: () => now);
    addTearDown(background.dispose);
    expect(background.finishBackground(), isFalse);
    background.beginBackground();
    now = now.add(const Duration(seconds: 2));
    expect(background.finishBackground(), isTrue);
    background.beginBackground();
    now = now.add(const Duration(minutes: 1));
    expect(background.finishBackground(), isFalse);
    background.beginBackground();
    background.invalidate();
    expect(background.finishBackground(), isFalse);
  });

  testWidgets('服务持续运行且事件循环连续时，长后台不必重拉；停顿后不能跳过', (tester) async {
    var now = DateTime(2026);
    final background = BackgroundConnection(now: () => now);
    addTearDown(background.dispose);
    await background.initialize();
    await background.start(title: '后台连接', body: '接收更新', stopLabel: '停止');
    background.beginBackground();
    for (var i = 0; i < 6; i++) {
      now = now.add(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 5));
    }
    expect(background.finishBackground(), isTrue);
    background.beginBackground();
    now = now.add(const Duration(minutes: 2));
    await tester.pump(const Duration(seconds: 5));
    expect(background.finishBackground(), isFalse);
  });
}
