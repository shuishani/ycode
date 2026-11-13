import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/link/link_store.dart';
import 'package:baocode_mobile/link/phone_link.dart'
    show DesktopLinkStatus, KeptDesktop;
import 'package:baocode_mobile/state/app_state.dart';
import 'package:baocode_mobile/ui/files/files_tab.dart';
import 'package:baocode_mobile/ui/focus/focus_shell.dart';
import 'package:baocode_mobile/ui/home_shell.dart';
import 'package:baocode_mobile/ui/tasks/chat_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _State extends AppState {
  _State() : super(store: MemoryLinkStore()) {
    settings
      ..language = 'zh'
      ..layout = 'focus'
      ..desktop = '甲';
  }
  final calls = <(String, Map<String, Object?>)>[];
  final removed = <String>{};

  void remove(String id) {
    removed.add(id);
    notifyListeners();
  }

  @override
  List<KeptDesktop> get desktops => const [
    KeptDesktop(id: '甲', name: '电脑甲', publicKey: ''),
    KeptDesktop(id: '乙', name: '电脑乙', publicKey: ''),
  ];
  @override
  bool isOnline(String id) => true;
  @override
  DesktopLinkStatus linkStatus(String desktopId) => DesktopLinkStatus.online;
  @override
  List<ProjectRef> get projects => const [
    ProjectRef('甲', ProjectInfo(id: 'p', name: '项目一', path: '/p')),
    ProjectRef('甲', ProjectInfo(id: 'q', name: '项目二', path: '/q')),
    ProjectRef('乙', ProjectInfo(id: 'r', name: '项目三', path: '/r')),
  ];

  SessionRef _s(
    String desktop,
    String id,
    String project,
    int day, [
    LinkSessionStatus status = LinkSessionStatus.idle,
  ]) => SessionRef(
    desktop,
    SessionSummary(
      id: id,
      project: project,
      title: '对话$id',
      updatedAt: DateTime(2026, 11, day),
      status: status,
    ),
  );

  @override
  List<SessionRef> get sessions => [
    for (final ref in [
      _s('甲', '1', 'p', 10),
      _s('甲', '2', 'p', 8, LinkSessionStatus.needsInput),
      _s('甲', '3', 'q', 9),
      _s('乙', '4', 'r', 5),
    ])
      if (!removed.contains(ref.session.id)) ref,
  ];

  @override
  Future<Object?> request(
    String desktopId,
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    calls.add((method, params));
    if (method == LinkMethods.draft) {
      return {'session': 'draft-${params['project']}'};
    }
    return null;
  }

  @override
  Future<void> openSession(String desktopId, String sessionId) async {}
  @override
  Future<void> closeSession(String desktopId, String sessionId) async {}
}

Future<_State> _pump(WidgetTester tester) async {
  final state = _State();
  addTearDown(state.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: AnimatedBuilder(
        animation: state,
        builder: (_, _) => HomeShell(state: state),
      ),
    ),
  );
  await tester.pump();
  return state;
}

ChatPage _page(WidgetTester tester) =>
    tester.widget<ChatPage>(find.byType(ChatPage));

Finder _inPanel(String text) =>
    find.descendant(of: find.byType(Drawer), matching: find.text(text));

Future<void> _openPanel(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('open-side-panel')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('沉浸模式打开就是当前电脑最近的对话，没有底部标签栏', (tester) async {
    await _pump(tester);
    expect(find.byType(FocusShell), findsOneWidget);
    expect(_page(tester).sessionId, '1');
    expect(find.text('Bot'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('对话里按返回先打开侧边栏，侧边栏开着再按才退出应用', (tester) async {
    final exits = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        exits.add(call.method);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _pump(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsOneWidget);
    expect(_page(tester).sessionId, '1');
    expect(exits, isNot(contains('SystemNavigator.pop')));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(exits, contains('SystemNavigator.pop'));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('记住的上次对话优先，但只在当前电脑上才用', (tester) async {
    final state = _State()..settings.lastSession = ('甲', '3');
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedBuilder(
          animation: state,
          builder: (_, _) => HomeShell(state: state),
        ),
      ),
    );
    await tester.pump();
    expect(_page(tester).sessionId, '3');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('侧边栏按项目默认展开全部对话，点对话原地切换并记住', (tester) async {
    final state = await _pump(tester);
    await _openPanel(tester);
    for (final id in ['1', '2', '3']) {
      expect(find.byKey(ValueKey('side-session-甲-$id')), findsOneWidget);
    }
    expect(_inPanel('项目三'), findsNothing, reason: '只列当前电脑的项目');
    await tester.tap(find.byKey(const ValueKey('side-session-甲-3')));
    await tester.pumpAndSettle();
    expect(_page(tester).sessionId, '3');
    expect(state.settings.lastSession, ('甲', '3'));
    expect(find.byType(Drawer), findsNothing);
    expect(
      tester.state<NavigatorState>(find.byType(Navigator)).canPop(),
      isFalse,
      reason: '原地切换，不叠新页面',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('点项目标题折叠它的对话，再点展开', (tester) async {
    await _pump(tester);
    await _openPanel(tester);
    await tester.tap(_inPanel('项目一'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('side-session-甲-1')), findsNothing);
    expect(find.byKey(const ValueKey('side-session-甲-3')), findsOneWidget);
    await tester.tap(_inPanel('项目一'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('side-session-甲-1')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('项目展开时只有对话前的状态点，折叠后项目名旁合成一个同色的点', (tester) async {
    await _pump(tester);
    await _openPanel(tester);
    final error = Theme.of(tester.element(find.byType(Drawer)))
        .colorScheme
        .error;
    Finder dots(Finder of) => find.descendant(
      of: of,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration! as BoxDecoration).shape == BoxShape.circle &&
            (widget.decoration! as BoxDecoration).color == error,
      ),
    );
    final header = find.byKey(const ValueKey('side-project-甲-p'));
    expect(dots(header), findsNothing);
    expect(
      dots(find.byKey(const ValueKey('side-session-甲-2'))),
      findsOneWidget,
    );
    expect(
      find.descendant(of: header, matching: find.byType(Badge)),
      findsNothing,
    );
    await tester.tap(_inPanel('项目一'));
    await tester.pumpAndSettle();
    expect(dots(header), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('项目右边的加号在该项目开新对话，原地打开草稿', (tester) async {
    final state = await _pump(tester);
    await _openPanel(tester);
    await tester.tap(find.byKey(const ValueKey('side-new-甲-q')));
    await tester.pumpAndSettle();
    expect(state.calls.last.$1, LinkMethods.draft);
    expect(state.calls.last.$2, {'project': 'q'});
    expect(_page(tester).sessionId, 'draft-q');
    expect(_page(tester).projectId, 'q');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('对话页右上角新对话在当前项目原地开草稿', (tester) async {
    final state = await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('chat-new-conversation')));
    await tester.pumpAndSettle();
    expect(state.calls.last.$1, LinkMethods.draft);
    expect(state.calls.last.$2, {'project': 'p'});
    expect(_page(tester).sessionId, 'draft-p');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('切换电脑后侧边栏换成它的项目，并打开它最近的对话', (tester) async {
    final state = await _pump(tester);
    state.selectDesktop('乙');
    await tester.pumpAndSettle();
    expect(_page(tester).sessionId, '4');
    await _openPanel(tester);
    expect(_inPanel('项目三'), findsOneWidget);
    expect(_inPanel('项目一'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('开着的对话被删掉后换到最近的一段', (tester) async {
    final state = await _pump(tester);
    expect(_page(tester).sessionId, '1');
    state.remove('1');
    await tester.pumpAndSettle();
    expect(_page(tester).sessionId, '3');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('侧边栏里长按对话没有「放到首页」，其余菜单都在', (tester) async {
    await _pump(tester);
    await _openPanel(tester);
    await tester.longPress(find.byKey(const ValueKey('side-session-甲-2')));
    await tester.pumpAndSettle();
    expect(find.text('重命名'), findsOneWidget);
    expect(find.text('归档'), findsOneWidget);
    expect(find.text('放到首页'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('侧边栏顶部的 Bot 和文件入口打开原有页面', (tester) async {
    await _pump(tester);
    await _openPanel(tester);
    await tester.tap(find.byKey(const ValueKey('side-files')));
    await tester.pumpAndSettle();
    expect(find.byType(FilesTab), findsOneWidget);
    expect(
      tester.state<NavigatorState>(find.byType(Navigator)).canPop(),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('往上滑时入口滚走，项目标题吸在顶上', (tester) async {
    tester.view.physicalSize = const Size(360, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(tester);
    await _openPanel(tester);
    final list = find.descendant(
      of: find.byType(Drawer),
      matching: find.byType(CustomScrollView),
    );
    final top = tester.getTopLeft(list).dy;
    await tester.drag(list, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('side-panel-new')).hitTestable(),
      findsNothing,
      reason: '入口滚到了标题上面',
    );
    final header = find.byKey(const ValueKey('side-project-甲-p'));
    expect(header, findsOneWidget);
    expect(tester.getTopLeft(header).dy, closeTo(top, 1));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('界面模式和上次对话能存下来再读回', () {
    final settings = AppSettings()
      ..layout = 'focus'
      ..lastSession = ('甲', '1');
    final read = AppSettings.fromJson(settings.toJson());
    expect(read.focusLayout, isTrue);
    expect(read.lastSession, ('甲', '1'));
    expect(AppSettings.fromJson({'layout': '别的'}).layout, 'list');
    expect(AppSettings.fromJson({}).lastSession, isNull);
  });
}
