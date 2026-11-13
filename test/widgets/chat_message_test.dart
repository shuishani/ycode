// YCode — GPL-3.0-only.
import 'dart:async';

import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/chat/widgets/turn_footer.dart';
import 'package:baocode_mobile/chat/markdown/code_citation.dart';
import 'package:baocode_mobile/link/phone_link.dart' show DesktopLinkStatus;
import 'package:baocode_mobile/ui/tasks/chat_empty_state.dart';
import 'package:baocode_mobile/ui/widgets/lucide_icon.dart';
import 'package:baocode_mobile/ui/tasks/interaction_panel.dart';
import 'package:baocode_mobile/ui/tasks/model_settings_sheet.dart';
import 'package:baocode_mobile/ui/tasks/task_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_page_harness.dart';

void main() {
  testWidgets('模式中文说明和图标不改变option id', (tester) async {
    final state = ChineseChatPageState();
    addTearDown(state.dispose);
    state.history.choices = [
      const LinkChoice(
        kind: 'mode',
        selected: 'agent',
        options: [
          LinkOption(
            id: 'agent',
            label: 'Agent',
            description: 'Plan, edit and run code',
          ),
          LinkOption(
            id: 'ask',
            label: 'Ask',
            description: 'Talk it through, suggest changes',
          ),
          LinkOption(
            id: 'plan',
            label: 'Plan',
            description: 'Research and plan, then build',
          ),
        ],
      ),
    ];
    await tester.pumpWidget(chatHost(state));
    await tester.pumpAndSettle();
    // 底部按钮同宽才间距一致；∞ 略放大补偿它扁平的形状。
    expect(
      tester.getSize(find.byTooltip('添加附件')).width,
      tester.getSize(find.byTooltip('模式: Agent')).width,
    );
    LucideIcon icon(Finder scope, String name) => tester.widget<LucideIcon>(
      find.descendant(
        of: scope,
        matching: find.byWidgetPredicate(
          (widget) => widget is LucideIcon && widget.name == name,
        ),
      ),
    );
    expect(icon(find.byTooltip('模式: Agent'), 'infinity').size, 22);
    await tester.tap(find.byTooltip('模式: Agent'));
    await tester.pumpAndSettle();
    final panel = find.byKey(const ValueKey('dropdown-panel'));
    expect(icon(panel, 'infinity').size, 24);
    expect(icon(panel, 'message-circle').size, 22);
    expect(find.text('规划、编辑并运行代码'), findsOneWidget);
    expect(find.text('只讨论和解答，给出改动建议'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('dropdown-panel')),
        matching: find.byWidgetPredicate(
          (widget) => widget is LucideIcon && widget.name == 'infinity',
        ),
      ),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(ListTile, 'Ask'));
    await tester.pumpAndSettle();
    expect(state.calls.single.$2, {
      'session': 'session',
      'kind': 'mode',
      'option': 'ask',
    });
  });

  testWidgets('批准策略中文展示，完全访问直接切换并保留wire原ID', (tester) async {
    final state = ChineseChatPageState();
    addTearDown(state.dispose);
    state.history.choices = [
      const LinkChoice(
        kind: 'permission',
        selected: 'default',
        options: [
          LinkOption(id: 'default', label: 'Ask for approval'),
          LinkOption(
            id: 'bypassPermissions',
            label: 'Full access',
            description: 'No checks',
            caution: true,
          ),
        ],
      ),
    ];
    await tester.pumpWidget(chatHost(state));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('权限: 逐项批准'));
    await tester.pumpAndSettle();
    expect(find.text('应如何获得批准？'), findsOneWidget);
    // 选完全访问不再弹确认框，直接切换。
    await tester.tap(find.widgetWithText(ListTile, '完全访问'));
    await tester.pumpAndSettle();
    expect(find.text('开启完全访问'), findsNothing);
    expect(state.calls.single.$2, {
      'session': 'session',
      'kind': 'permission',
      'option': 'bypassPermissions',
    });
  });

  testWidgets('手机宽度下选中的完全访问描述不折行', (tester) async {
    tester.view.physicalSize = const Size(391, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.1;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final state = ChineseChatPageState();
    addTearDown(state.dispose);
    state.history.choices = [
      const LinkChoice(
        kind: 'permission',
        selected: 'bypassPermissions',
        options: [
          LinkOption(id: 'default', label: 'Ask for approval'),
          LinkOption(
            id: 'bypassPermissions',
            label: 'Full access',
            description: 'No checks',
            caution: true,
          ),
        ],
      ),
    ];
    await tester.pumpWidget(chatHost(state));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('权限: 完全访问'));
    await tester.pumpAndSettle();
    final detail = find.text('不做任何检查，编辑和命令直接执行');
    final style = tester.widget<Text>(detail).style;
    final line = tester.getSize(find.text('编辑和命令前都先询问')).height;
    expect(tester.getSize(detail).height, line, reason: '$style');
    expect(
      find.byWidgetPredicate(
        (w) => w is LucideIcon && w.name == 'triangle-alert',
      ),
      findsNothing,
    );
  });

  testWidgets('真实wire历史经过页面接线显示一次完整回合统计', (tester) async {
    final state = ChatPageState();
    addTearDown(state.dispose);
    state.history.items.addAll([
      {
        't': 'user',
        'text': '统计测试',
        'worked': 9000,
        'usage': {'in': 100, 'out': 20, 'speed': 28.59, 'cost': .072},
      },
      {'t': 'text', 'text': '实际回答'},
    ]);
    await tester.pumpWidget(chatHost(state));
    await tester.pumpAndSettle();
    expect(find.byType(TurnFooter), findsOneWidget);
    expect(find.text('29 tok/s'), findsOneWidget);
    expect(find.text('\$0.072'), findsOneWidget);
    expect(find.byTooltip('Copy answer'), findsOneWidget);
    // 用户消息的复制和编辑在气泡下方直接可点。
    expect(find.byTooltip('Copy'), findsOneWidget);
    expect(find.byTooltip('Edit and resend'), findsOneWidget);
  });

  testWidgets('隐藏实时状态经页面仍呈现统计，结束后销毁计时器', (tester) async {
    final state = ChatPageState();
    addTearDown(state.dispose);
    state.history.live = true;
    state.history.items.addAll([
      {'t': 'user', 'text': '实时统计'},
      {
        't': 'live',
        'label': '',
        'visible': false,
        'tokens': 50,
        'speed': 10.5,
        'startedAt': DateTime.now().millisecondsSinceEpoch,
      },
    ]);
    await tester.pumpWidget(chatHost(state));
    await tester.pump();
    expect(find.byType(TurnFooter), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'model sheet searches real options and preserves selection payload',
    (tester) async {
      final state = ChatPageState();
      addTearDown(state.dispose);
      state.history.choices = [
        const LinkChoice(
          kind: 'model',
          selected: 'a',
          options: [
            LinkOption(
              id: 'a',
              label: '模型甲',
              group: 'provider',
              groupLabel: '提供方',
            ),
            LinkOption(
              id: 'b',
              label: '模型乙',
              group: 'provider',
              groupLabel: '提供方',
            ),
          ],
        ),
      ];
      await tester.pumpWidget(chatHost(state));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Model: 模型甲'));
      await tester.pumpAndSettle();
      expect(find.text('提供方'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Search models'),
        '模型乙',
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('模型甲'),
        ),
        findsNothing,
      );
      await tester.tap(find.widgetWithText(ListTile, '模型乙'));
      await tester.pump();
      state.history.choices = [
        LinkChoice(
          kind: 'model',
          selected: 'b',
          options: state.history.choices.first.options,
        ),
      ];
      state.update();
      await tester.pumpAndSettle();
      expect(state.calls.last.$1, LinkMethods.choose);
      expect(state.calls.last.$2, {
        'session': 'session',
        'kind': 'model',
        'option': 'b',
      });
    },
  );

  testWidgets('raw agent and authoritative changes drive composer status', (
    tester,
  ) async {
    final state = ChatPageState();
    addTearDown(state.dispose);
    state.history.items.addAll([
      {
        't': 'agent',
        'id': 'worker',
        'description': '检查文件',
        'status': 'running',
      },
      {
        't': 'diff',
        'fileName': '联调.txt',
        'directory': '',
        'added': 2,
        'removed': 1,
        'lines': <Object?>[],
      },
    ]);
    await tester.pumpWidget(chatHost(state));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('activity-tasks-expand')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('chat-activity-card')),
        matching: find.text('检查文件'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('activity-changes-toggle')), findsNothing);
    state.history.changes = [
      {'path': '联调.txt', 'added': 2, 'removed': 1},
    ];
    state.update();
    await tester.pump();
    final bar = find.byKey(const ValueKey('activity-changes-toggle'));
    expect(
      find.descendant(of: bar, matching: find.text('1 file')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: bar, matching: find.text('+2 −1')),
      findsOneWidget,
    );
    // Undo removes the authoritative changes, but retains the historical diff.
    state.history.changes = [];
    state.update();
    await tester.pump();
    expect(bar, findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'live response has one button: stop until a draft makes it send',
    (tester) async {
      final state = ChatPageState()..stopping = Completer<void>();
      state.history.live = true;
      addTearDown(state.dispose);
      await tester.pumpWidget(chatHost(state));
      await tester.pump();
      final stopButton = find.byTooltip('Stop generation');
      expect(stopButton, findsOneWidget);
      expect(find.byKey(const ValueKey('hollow-stop')), findsOneWidget);
      expect(find.byTooltip('Send'), findsNothing);
      final slot = tester.getCenter(stopButton);
      await tester.enterText(find.byType(TextField).first, 'hello');
      await tester.pump();
      expect(stopButton, findsNothing);
      expect(find.byKey(const ValueKey('hollow-stop')), findsNothing);
      expect(tester.getCenter(find.byTooltip('Send')), slot);
      await tester.enterText(find.byType(TextField).first, '');
      await tester.pump();
      await tester.tap(find.byTooltip('Stop generation'));
      await tester.pump();
      expect(find.byTooltip('Stopping…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      final stop = tester.widget<IconButton>(
        find
            .ancestor(
              of: find.byTooltip('Stopping…'),
              matching: find.byType(IconButton),
            )
            .first,
      );
      expect(stop.onPressed, isNull);
      await tester.enterText(find.byType(TextField).first, '保留这条草稿');
      await tester.pump();
      // 停止请求没回来时写了东西，按钮也是发送，草稿不丢。
      expect(find.byTooltip('Send').hitTestable(), findsOneWidget);
      expect(find.byTooltip('Stopping…'), findsNothing);
      expect(find.text('保留这条草稿'), findsOneWidget);
      expect(
        state.calls.where((call) => call.$1 == LinkMethods.stop),
        hasLength(1),
      );
      expect(state.calls.single.$2, {'session': 'session'});
      state.stopping!.complete();
      state.history.live = false;
      state.update();
      await tester.pump();
      expect(find.byTooltip('Send'), findsOneWidget);
      expect(find.text('保留这条草稿'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets('长消息和五张有效图片在直播增量期间尺寸与元素保持稳定', (tester) async {
    final state = ChatPageState();
    addTearDown(state.dispose);
    state.history.items.add({
      't': 'user',
      'text': '很长的用户消息，'.padRight(400, '用于测量高度变化。'),
      'images': [
        for (var i = 0; i < 5; i++)
          {
            'name': 'image-$i.png',
            'type': 'image/png',
            'data': 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=',
          },
      ],
    });
    state.history.live = true;
    await tester.pumpWidget(chatHost(state));
    await tester.pump();
    final bubble = find.byKey(const ValueKey('user-message-bubble'));
    final firstSize = tester.getSize(bubble);
    final firstElement = tester.element(bubble);
    await tester.runAsync(() async {
      await precacheImage(
        tester.widget<Image>(find.byType(Image).first).image,
        tester.element(bubble),
        onError: (error, _) => fail('测试图片必须成功解码：$error'),
      );
    });
    await tester.pump();
    expect(tester.getSize(bubble), firstSize);
    state.history.items.add({'t': 'text', 'text': '第一段流式内容'});
    state.update();
    await tester.pump();
    final secondSize = tester.getSize(bubble);
    final secondElement = tester.element(bubble);
    state.history.items.add({'t': 'text', 'text': '第二段流式内容'});
    state.update();
    await tester.pump();
    expect(tester.getSize(bubble), secondSize);
    expect(identical(firstElement, secondElement), isTrue);
    expect(tester.getSize(bubble), firstSize);
    expect(find.byType(Image), findsNWidgets(2), reason: '多图叠成一摞，只建当前和相邻的');
    await tester.tap(find.byKey(const ValueKey('image-deck-expand')));
    await tester.pump();
    expect(find.byType(Image), findsNWidgets(5), reason: '展开后每张都有');
  });

  testWidgets('仅由后台任务协议上报的子代理也能打开详情', (tester) async {
    final state = ChatPageState();
    addTearDown(state.dispose);
    state.history.tasks = [
      LinkTask(
        id: 'task-1',
        kind: 'agent',
        description: '后台检查布局',
        status: 'running',
        startedAt: DateTime(2026),
        toolUseId: 'tool-1',
        summary: '正在对比用户消息尺寸',
        output: true,
      ),
    ];
    await tester.pumpWidget(chatHost(state));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('activity-tasks-expand')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('后台检查布局'), findsWidgets);
    expect(find.text('正在对比用户消息尺寸'), findsOneWidget);
    expect(state.calls.where((call) => call.$1 == LinkMethods.output), isEmpty);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('chat-activity-card')),
        matching: find.text('后台检查布局'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      state.calls.where((call) => call.$1 == LinkMethods.output),
      hasLength(1),
    );
    expect(
      state.calls.singleWhere((call) => call.$1 == LinkMethods.output).$2,
      {'session': 'session', 'task': 'task-1'},
    );
    expect(find.text('output 1'), findsOneWidget);
  });

  testWidgets('运行中子代理徽标可选择指定代理并打开详情', (tester) async {
    final state = ChatPageState();
    addTearDown(state.dispose);
    state.history.items.addAll([
      {
        't': 'agent',
        'id': 'worker-1',
        'description': '检查图片布局',
        'activity': '检查行高度',
        'status': 'running',
        'prompt': '保持图片布局稳定',
      },
      {
        't': 'agent',
        'id': 'worker-2',
        'description': '检查任务队列',
        'activity': '验证追加消息',
        'status': 'running',
        'prompt': '确认消息排队语义',
      },
    ]);
    await tester.pumpWidget(chatHost(state));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('activity-tasks-expand')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('检查图片布局'), findsWidgets);
    expect(find.text('检查任务队列'), findsWidgets);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('chat-activity-card')),
        matching: find.text('检查任务队列'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('确认消息排队语义'), findsOneWidget);
    expect(find.text('检查任务队列'), findsWidgets);
  });

  testWidgets('点击子代理消息行可打开只读详情页', (tester) async {
    final state = ChatPageState();
    addTearDown(state.dispose);
    await tester.pumpWidget(chatHost(state));
    state.history.items.add({
      't': 'agent',
      'id': 'worker-1',
      'description': '检查图片布局',
      'status': 'running',
      'prompt': '保持消息高度稳定',
      'result': '目前正在测量',
    });
    state.update();
    await tester.pump(const Duration(milliseconds: 16));
    // 托盘折叠成胶囊，任务标题只在消息行里。
    expect(find.text('检查图片布局'), findsOneWidget);
    await tester.tap(find.text('检查图片布局'));
    // The live status spinner is intentionally perpetual; advance the route
    // animation without waiting for every ticker to settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('保持消息高度稳定'), findsOneWidget);
    expect(find.text('目前正在测量'), findsOneWidget);
    expect(find.text('检查图片布局'), findsWidgets);
  });

  for (final typedBefore in [true, false]) {
    testWidgets('切换模型后发送键可用：${typedBefore ? '切换前已输入' : '切换后才输入'}', (
      tester,
    ) async {
      final state = ChineseChatPageState();
      addTearDown(state.dispose);
      LinkChoice models(String selected) => LinkChoice(
        kind: 'model',
        selected: selected,
        options: const [
          LinkOption(id: 'a', label: '模型甲', group: 'p', groupLabel: '来源'),
          LinkOption(id: 'b', label: '模型乙', group: 'p', groupLabel: '来源'),
        ],
      );
      state.history
        ..choices = [models('a')]
        ..items.add({'t': 'user', 'text': '你好'});
      await tester.pumpWidget(chatHost(state));
      await tester.pumpAndSettle();
      bool sendable() {
        final button = tester.widget<IconButton>(
          find
              .ancestor(
                of: find.byTooltip('发送'),
                matching: find.byType(IconButton),
              )
              .first,
        );
        return button.onPressed != null;
      }

      final composer = find.byType(TextField).first;
      if (typedBefore) {
        await tester.enterText(composer, '切换前的话');
        await tester.pump();
        expect(sendable(), isTrue);
      }
      await tester.tap(find.byTooltip('模型: 模型甲'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, '模型乙'));
      await tester.pump();
      expect(state.calls.last.$1, LinkMethods.choose);
      expect(state.calls.last.$2['option'], 'b');
      // 电脑端发回新选中项。
      state.history.choices = [models('b')];
      state.update();
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byType(ModelSettingsSheet), findsNothing);
      if (!typedBefore) {
        expect(sendable(), isFalse, reason: '输入框为空');
        await tester.enterText(composer, '切换后的话');
        await tester.pump();
      }
      expect(sendable(), isTrue, reason: '切换模型后不该变灰');
      await tester.tap(find.byTooltip('发送'));
      await tester.pump();
      expect(state.calls.last.$1, LinkMethods.send);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('顶栏说清连接状态：已连接、连接中、离线', (tester) async {
    final state = ChineseChatPageState();
    addTearDown(state.dispose);
    state.history.items.add({'t': 'user', 'text': '你好'});
    await tester.pumpWidget(chatHost(state));
    await tester.pump();
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == '已连接电脑',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('连接中'), findsNothing);

    state
      ..online = false
      ..status = DesktopLinkStatus.connecting;
    state.update();
    await tester.pump();
    expect(find.textContaining('连接中'), findsOneWidget);
    expect(find.text('离线'), findsNothing);

    state.status = DesktopLinkStatus.offline;
    state.update();
    await tester.pump();
    // 和设备列表、切换电脑面板同一个词。
    expect(find.text('离线'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('没连上时有草稿：发送键灰，输入框上方说明原因并可重试，草稿保留', (tester) async {
    final state = ChineseChatPageState()
      ..online = false
      ..savedDraft = '还没发出去的话';
    addTearDown(state.dispose);
    state.history.items.add({'t': 'user', 'text': '你好'});
    await tester.pumpWidget(chatHost(state));
    await tester.pump();
    final notice = find.byKey(const ValueKey('offline-notice'));
    expect(notice, findsOneWidget);
    expect(
      tester.getBottomLeft(notice).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.byType(TextField).first).dy),
    );
    final send = tester.widget<IconButton>(
      find
          .ancestor(of: find.byTooltip('发送'), matching: find.byType(IconButton))
          .first,
    );
    expect(send.onPressed, isNull);
    await tester.tap(find.descendant(of: notice, matching: find.text('重试')));
    await tester.pump();
    expect(state.retried, 1);
    expect(find.text('还没发出去的话'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('对话里的目标卡片显示中文状态，不露出电脑端的原词', (tester) async {
    final state = ChineseChatPageState();
    addTearDown(state.dispose);
    state.history.goal = {'condition': '把测试跑绿', 'state': 'active'};
    await tester.pumpWidget(chatHost(state));
    await tester.pump();
    expect(find.text('进行中'), findsOneWidget);
    expect(find.text('active'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('断线后不再显示运行中：动画和计时停住，也没有停止键', (tester) async {
    final state = ChineseChatPageState();
    addTearDown(state.dispose);
    state.history
      ..items.addAll([
        {'t': 'user', 'text': '你好'},
        {
          't': 'live',
          'label': '思考中',
          'startedAt': DateTime(2026).millisecondsSinceEpoch,
        },
      ])
      ..live = true;
    await tester.pumpWidget(chatHost(state));
    await tester.pump();
    expect(find.byTooltip('停止生成'), findsOneWidget);
    expect(find.textContaining('思考中'), findsWidgets);

    state.online = false;
    state.update();
    await tester.pump();
    expect(find.byTooltip('停止生成'), findsNothing);
    expect(find.textContaining('思考中'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('打开对话时第一帧不闪空状态，加载完才判断是否为空', (tester) async {
    final state = ChineseChatPageState()..opening = Completer<void>();
    addTearDown(state.dispose);
    await tester.pumpWidget(chatHost(state));
    expect(find.byType(ChatEmptyState), findsNothing, reason: '第一帧');
    await tester.pump();
    await tester.pump();
    expect(find.byType(ChatEmptyState), findsNothing, reason: '加载中');
    state.opening!.complete();
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(find.byType(ChatEmptyState), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('发送请求等待期间的新文本草稿会保留', (tester) async {
    final state = ChatPageState()..sending = Completer<void>();
    addTearDown(state.dispose);
    await tester.pumpWidget(chatHost(state));
    await tester.pump();
    final composer = find.byType(TextField).first;
    await tester.enterText(composer, '本次发送');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    expect(tester.widget<TextField>(composer).enabled, isNot(isFalse));
    expect(
      state.calls.where((call) => call.$1 == LinkMethods.send),
      hasLength(1),
    );
    await tester.enterText(composer, '下一条草稿');
    await tester.pump();
    state.sending!.complete();
    await tester.pump();
    await tester.pump();
    expect(find.text('下一条草稿'), findsOneWidget);
    expect(find.text('本次发送'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'failed stop keeps the visible stop action and reports the error',
    (tester) async {
      final state = ChatPageState()..failStop = true;
      state.history.live = true;
      addTearDown(state.dispose);
      await tester.pumpWidget(chatHost(state));
      await tester.pump();
      await tester.tap(find.byTooltip('Stop generation'));
      await tester.pump();
      expect(find.textContaining('stop rejected'), findsOneWidget);
      expect(state.history.live, isTrue);
      expect(find.byTooltip('Stop generation'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'unknown and malformed wire messages remain visible with their wire index',
    (tester) async {
      final state = ChatPageState();
      await tester.pumpWidget(
        messageHost(state, {'t': 'future-kind', 'text': 'preserved'}),
      );
      expect(find.text('Unrecognized message'), findsOneWidget);
      expect(find.text('#7'), findsOneWidget);
      await tester.tap(find.text('Unrecognized message'));
      await tester.pumpAndSettle();
      expect(find.textContaining('preserved'), findsOneWidget);
      await tester.pumpWidget(
        messageHost(state, {
          't': 'user',
          'images': [
            {'data': '*invalid*', 'type': 'image/png'},
          ],
        }),
      );
      expect(find.text('Unrecognized message'), findsOneWidget);
    },
  );

  testWidgets('延后解码的损坏工具图片仍保留可展开的原始消息行', (tester) async {
    final state = ChatPageState();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      messageHost(state, {
        't': 'tool',
        'tool': '合成截图工具',
        'images': [
          {'data': '*invalid*', 'type': 'image/png'},
        ],
      }),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Unrecognized message'), findsOneWidget);
    expect(find.text('#7'), findsOneWidget);
    await tester.tap(find.text('Unrecognized message'));
    await tester.pumpAndSettle();
    expect(find.textContaining('合成截图工具'), findsOneWidget);
  });

  testWidgets(
    'a finished thought shows the desktop row, closed until opened by hand',
    (tester) async {
      final state = ChatPageState();
      await tester.pumpWidget(
        messageHost(state, {
          't': 'thinking',
          'text': 'private thought',
          'tokens': 42,
          'seconds': 3,
        }),
      );
      // The desktop header: how long it took, no token tally.
      expect(find.text('Thought 3s'), findsOneWidget);
      expect(find.text('private thought').hitTestable(), findsNothing);
      await tester.tap(find.text('Thought 3s'));
      await tester.pumpAndSettle();
      expect(find.text('private thought').hitTestable(), findsOneWidget);
      // Closed again by hand: a step stays where the user leaves it.
      await tester.tap(find.text('Thought 3s'));
      await tester.pumpAndSettle();
      expect(find.text('private thought').hitTestable(), findsNothing);
    },
  );

  testWidgets('remote markdown images never make an implicit image request', (
    tester,
  ) async {
    final state = ChatPageState();
    await tester.pumpWidget(
      messageHost(state, {
        't': 'text',
        'text': '![remote](https://example.com/a.png)',
      }),
    );
    expect(find.byType(Image), findsNothing);
    expect(state.calls, isEmpty);
    await tester.tap(find.textContaining('remote'));
    await tester.pumpAndSettle();
    expect(find.text('Open in browser?'), findsOneWidget);
    expect(state.calls, isEmpty);
  });

  testWidgets(
    'project images request image with both project and path only after a tap',
    (tester) async {
      final state = ChatPageState();
      await tester.pumpWidget(
        messageHost(state, {
          't': 'text',
          'text': '![diagram](assets/chart.png)',
        }),
      );
      expect(state.calls, isEmpty);
      await tester.tap(find.text('Load image: diagram'));
      await tester.pumpAndSettle();
      // matcher's deep equality does not decompose records, so compare the fields.
      expect(state.calls.single.$1, LinkMethods.image);
      expect(state.calls.single.$2, {
        'project': 'project',
        'path': 'assets/chart.png',
      });
    },
  );

  testWidgets(
    'send failure preserves composer and never retries automatically',
    (tester) async {
      final state = ChatPageState()..failSend = true;
      await tester.pumpWidget(chatHost(state));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'keep this message');
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();
      expect(find.text('keep this message'), findsOneWidget);
      expect(
        state.calls.where((call) => call.$1 == LinkMethods.send).length,
        1,
      );
      await tester.pump(const Duration(seconds: 3));
      expect(
        state.calls.where((call) => call.$1 == LinkMethods.send).length,
        1,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(state.savedDraft, 'keep this message');
      expect(state.closed, ['session']);
    },
  );

  testWidgets(
    'edit sends the actual wire index including unknown preceding rows',
    (tester) async {
      final state = ChatPageState();
      state.history.items.addAll([
        {'t': 'future-kind'},
        {'t': 'user', 'text': 'original'},
      ]);
      await tester.pumpWidget(chatHost(state));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit and resend'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'edited');
      await tester.tap(find.byTooltip('Resend'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Discard and send'));
      await tester.pumpAndSettle();
      final edit = state.calls
          .singleWhere((call) => call.$1 == LinkMethods.edit)
          .$2;
      expect(edit['index'], 1);
      expect(edit['text'], 'edited');
      expect(edit['session'], 'session');
    },
  );

  testWidgets(
    'new bot draft is not opened and switches to returned real session after send',
    (tester) async {
      final state = ChatPageState();
      await tester.pumpWidget(
        chatHost(state, session: 'bot:assistant', bot: 'assistant'),
      );
      await tester.pumpAndSettle();
      expect(state.opened, isEmpty);
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();
      final send = state.calls.single.$2;
      expect(send['session'], isNull);
      expect(send['bot'], 'assistant');
      expect(state.opened, ['real-bot-session']);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(state.closed, ['real-bot-session']);
    },
  );

  testWidgets(
    'leaving while open is pending closes only once opening finishes',
    (tester) async {
      final state = ChatPageState()..opening = Completer<void>();
      await tester.pumpWidget(chatHost(state));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      expect(state.closed, isEmpty);
      state.opening!.complete();
      await tester.pump();
      expect(state.closed, ['session']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('approval uses decodeAnswer decision wire, not display labels', (
    tester,
  ) async {
    final state = ChatPageState();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InteractionPanel(
            state: state,
            desktopId: 'desktop',
            sessionId: 'session',
            request: {
              't': 'approval',
              'id': 'request-9',
              'title': 'Allow command?',
              'tool': 'Bash',
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Allow once'));
    await tester.pump();
    // matcher's deep equality does not decompose records, so compare the fields.
    expect(state.calls.single.$1, LinkMethods.answer);
    expect(state.calls.single.$2, {
      'session': 'session',
      'request': 'request-9',
      'answer': {'t': 'approval', 'decision': 'allowOnce'},
    });
    // A successful write remains disabled pending the next authoritative update.
    await tester.tap(find.text('Allow once'));
    await tester.pump();
    expect(state.calls.length, 1);
  });

  testWidgets('question answers use ordered lists of selected option labels', (
    tester,
  ) async {
    final state = ChatPageState();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: InteractionPanel(
              state: state,
              desktopId: 'desktop',
              sessionId: 'session',
              request: {
                't': 'question',
                'id': 'q',
                'title': 'Choose',
                'questions': [
                  {
                    'prompt': 'Which?',
                    'multiple': true,
                    'options': [
                      {'label': 'A'},
                      {'label': 'B'},
                    ],
                  },
                ],
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('A'));
    await tester.pump();
    await tester.tap(find.text('B'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Answer'));
    await tester.pump();
    expect(state.calls.single.$2['answer'], {
      't': 'question',
      'picks': [
        ['A', 'B'],
      ],
    });
  });

  testWidgets(
    'known wire kinds remain readable and unsupported diagrams expose source',
    (tester) async {
      final state = ChatPageState();
      for (final item in <Map<String, Object?>>[
        {
          't': 'tool',
          'kind': 'read',
          'target': 'main.dart',
          'status': 'succeeded',
          'output': 'contents',
        },
        {
          't': 'agent',
          'description': 'Review files',
          'status': 'succeeded',
          'result': 'Done',
        },
        {
          't': 'terminal',
          'command': 'dart test',
          'output': 'Passed',
          'status': 'succeeded',
        },
        {
          't': 'diff',
          'fileName': 'a.dart',
          'directory': 'lib',
          'lines': [
            [0, 1, 'new line'],
            [1, 1, 'old line'],
          ],
        },
        {
          't': 'plan',
          'path': 'plan.md',
          'round': 1,
          'status': 'awaiting',
          'text': 'Plan content',
        },
        {'t': 'notice', 'kind': 'warning', 'text': 'Check this'},
        {'t': 'live', 'label': 'Working', 'tokens': 4},
      ]) {
        await tester.pumpWidget(messageHost(state, item));
        await tester.pump();
        expect(
          find.text('Unrecognized message'),
          findsNothing,
          reason: '${item['t']}',
        );
        expect(tester.takeException(), isNull, reason: '${item['t']}');
      }
      await tester.pumpWidget(
        messageHost(state, {
          't': 'text',
          'text': '```mermaid\nunsupported-diagram\n```',
        }),
      );
      await tester.pumpAndSettle();
      final source = tester.widget<MarkdownCodeBlock>(
        find.byType(MarkdownCodeBlock),
      );
      expect(source.code, 'unsupported-diagram');
    },
  );

  testWidgets('task output polls once per second and stops on dispose', (
    tester,
  ) async {
    final state = ChatPageState();
    final task = LinkTask(
      id: 'task',
      kind: 'command',
      description: 'Build',
      status: 'running',
      startedAt: DateTime(2026),
      output: true,
    );
    state.history.tasks = [task];
    await tester.pumpWidget(
      MaterialApp(
        home: TaskPage(
          state: state,
          desktopId: 'desktop',
          sessionId: 'session',
          task: task,
        ),
      ),
    );
    await tester.pump();
    expect(state.outputReads, 1);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(state.outputReads, 2);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    expect(state.outputReads, 2);
  });

  testWidgets('model setting chips read Effort, Context and the fast toggle', (
    tester,
  ) async {
    final state = ChatPageState();
    addTearDown(state.dispose);
    state.history.choices = [
      const LinkChoice(
        kind: 'model',
        selected: 'gpt-5.6-terra',
        options: [LinkOption(id: 'gpt-5.6-terra', label: 'acme-gpt-5.6-Terra')],
      ),
      const LinkChoice(
        kind: 'effort',
        selected: 'high',
        options: [
          LinkOption(id: 'low', label: 'Low'),
          LinkOption(id: 'medium', label: 'Medium'),
          LinkOption(id: 'high', label: 'High'),
        ],
      ),
      const LinkChoice(
        kind: 'context',
        selected: '1m',
        options: [
          LinkOption(id: '272k', label: '272K'),
          LinkOption(id: '1m', label: '1M'),
        ],
      ),
      const LinkChoice(
        kind: 'fast',
        options: [LinkOption(id: 'fast', label: 'Fast')],
      ),
    ];
    state.update();
    await tester.pumpWidget(chatHost(state));
    await tester.pump();
    expect(find.text('Effort: High'), findsNothing);
    expect(find.text('Context: 1M'), findsNothing);
    await tester.tap(find.byTooltip('Model: acme-gpt-5.6-Terra · Context 1M'));
    await tester.pumpAndSettle();
    expect(find.text('Effort'), findsNothing);
    await tester.tap(find.widgetWithText(ListTile, 'acme-gpt-5.6-Terra'));
    await tester.pumpAndSettle();
    expect(find.text('Effort'), findsOneWidget);
    // 当前档写在标题右边，轨道两端是首尾两档（末档与当前档同名时就出现两次）。
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('effort:value'))).data,
      'High',
    );
    expect(find.text('Context'), findsOneWidget);
    // 当前档写在标题右边；1M 也是轨道的末档，所以出现两次。
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('context:value'))).data,
      '1M',
    );
    expect(find.text('Fast'), findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
    expect(find.textContaining('—'), findsNothing);
  });

  testWidgets('the fast chip toggles directly without a menu', (tester) async {
    final state = ChatPageState();
    addTearDown(state.dispose);
    final fast = const LinkChoice(
      kind: 'fast',
      options: [LinkOption(id: 'fast', label: 'Fast')],
    );
    state.history.choices = [fast];
    state.update();
    await tester.pumpWidget(chatHost(state));
    await tester.pump();
    await tester.tap(find.byTooltip('Fast: Off'));
    await tester.pumpAndSettle();
    expect(state.calls.single.$1, 'choose');
    expect(state.calls.single.$2, {
      'session': 'session',
      'kind': 'fast',
      'option': 'fast',
    });
    state.history.choices = [
      const LinkChoice(
        kind: 'fast',
        selected: 'fast',
        options: [LinkOption(id: 'fast', label: 'Fast')],
      ),
    ];
    state.update();
    await tester.pump();
    expect(find.byTooltip('Fast: On'), findsOneWidget);
  });

  testWidgets('the effort chip opens its menu and picks an effort', (
    tester,
  ) async {
    final state = ChatPageState();
    addTearDown(state.dispose);
    state.history.choices = [
      const LinkChoice(
        kind: 'effort',
        selected: 'high',
        options: [
          LinkOption(id: 'low', label: 'Low', description: 'Fastest'),
          LinkOption(id: 'medium', label: 'Medium'),
          LinkOption(id: 'high', label: 'High'),
        ],
      ),
    ];
    state.update();
    await tester.pumpWidget(chatHost(state));
    await tester.pump();
    await tester.tap(find.byTooltip('Effort: High'));
    await tester.pumpAndSettle();
    expect(find.text('Effort', skipOffstage: false), findsWidgets);
    await tester.tap(find.text('Low', skipOffstage: false));
    await tester.pumpAndSettle();
    expect(state.calls.single.$1, 'choose');
    expect(state.calls.single.$2, {
      'session': 'session',
      'kind': 'effort',
      'option': 'low',
    });
  });
}
