import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:baocode_mobile/link/link_store.dart';
import 'package:baocode_mobile/link/phone_link.dart'
    show DesktopLinkStatus, KeptDesktop;
import 'package:baocode_mobile/ui/conversations/chats_tab.dart';
import 'package:baocode_mobile/ui/files/files_tab.dart';
import 'package:baocode_mobile/ui/tasks/chat_page.dart';
import 'package:baocode_mobile/chat/widgets/pixel_loader.dart';
import 'package:baocode_mobile/ui/widgets/lucide_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _State extends AppState {
  _State() : super(store: MemoryLinkStore()) {
    settings.language = 'zh';
  }
  bool pinned = true;
  bool withBot = false;
  LinkSessionStatus status = LinkSessionStatus.idle;
  final calls = <Map<String, Object?>>[];
  @override
  List<KeptDesktop> get desktops => const [
    KeptDesktop(id: '在线', name: '在线电脑', publicKey: ''),
    KeptDesktop(id: '离线', name: '离线设备', publicKey: ''),
  ];
  @override
  bool isOnline(String id) => id == '在线';
  @override
  List<ProjectRef> get projects => [
    const ProjectRef('在线', ProjectInfo(id: 'p', name: '项目甲', path: '/p')),
    if (withBot)
      const ProjectRef('在线', ProjectInfo(id: 'e', name: '空项目', path: '/e')),
  ];
  @override
  List<BotRef> get bots => [
    if (withBot) ...[
      BotRef(
        '在线',
        LinkBot(
          id: 'b',
          name: '小宝',
          assistant: true,
          updatedAt: DateTime(2026, 6),
        ),
      ),
      // 自己加的 Bot 也要在首页有一行。
      BotRef(
        '在线',
        LinkBot(id: 'c', name: '审稿 Bot', updatedAt: DateTime(2026, 3)),
      ),
    ],
  ];
  @override
  List<SessionRef> get sessions => [
    SessionRef(
      '在线',
      SessionSummary(
        id: '会话甲',
        project: 'p',
        title: '置顶任务',
        updatedAt: DateTime(2026),
        pinned: pinned,
        status: status,
      ),
    ),
    SessionRef(
      '在线',
      SessionSummary(
        id: '会话乙',
        project: 'p',
        title: '审批任务',
        updatedAt: DateTime(2025),
        status: LinkSessionStatus.needsInput,
      ),
    ),
  ];
  @override
  LinkPath pathOf(String desktopId) => desktopId == '在线'
      ? const LinkPath(LinkPathKind.relay, rtt: Duration(milliseconds: 399))
      : LinkPath.none;
  @override
  DesktopLinkStatus linkStatus(String desktopId) => isOnline(desktopId)
      ? DesktopLinkStatus.online
      : DesktopLinkStatus.offline;
  @override
  void retryConnection(String desktopId) {}
  @override
  Future<Object?> request(
    String desktopId,
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    calls.add(params);
    if (method == LinkMethods.draft) {
      return {'session': 'draft-${params['project']}'};
    }
    if (method == LinkMethods.pin) {
      pinned = params['pinned'] as bool;
      notifyListeners();
    }
    return null;
  }

  @override
  Future<void> openSession(String desktopId, String sessionId) async {}
  @override
  Future<void> closeSession(String desktopId, String sessionId) async {}
}

class _EmptyState extends _State {
  DesktopLinkStatus linkState = DesktopLinkStatus.connecting;
  final retries = <String>[];
  @override
  bool isOnline(String id) => false;
  @override
  List<ProjectRef> get projects => const [];
  @override
  List<SessionRef> get sessions => const [];
  @override
  DesktopLinkStatus linkStatus(String desktopId) => linkState;
  @override
  void retryConnection(String desktopId) => retries.add(desktopId);
}

class _OfflineState extends _State {
  DesktopLinkStatus linkState = DesktopLinkStatus.connecting;
  @override
  bool isOnline(String id) => false;
  @override
  DesktopLinkStatus linkStatus(String desktopId) => linkState;
}

class _PinnedProject extends _State {
  @override
  List<ProjectRef> get projects => const [
    ProjectRef(
      '在线',
      ProjectInfo(id: '置顶', name: '置顶项目', path: '/pinned', pinned: true),
    ),
  ];
}

void main() {
  testWidgets('顶栏标题是所选电脑和它的连接状态', (tester) async {
    final state = _OfflineState();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedBuilder(
          animation: state,
          builder: (_, _) => ChatsTab(state: state),
        ),
      ),
    );
    expect(find.text('在线电脑'), findsOneWidget);
    expect(find.text('连接中…'), findsOneWidget);
    state.linkState = DesktopLinkStatus.offline;
    state.notifyListeners();
    await tester.pump();
    expect(find.text('离线 · 正在重连'), findsOneWidget);
    expect(find.text('连接中…'), findsNothing);
  });

  testWidgets('项目和对话用统一的状态文字，不再放运行动画', (tester) async {
    final state = _State()..status = LinkSessionStatus.running;
    state.settings.homeSessions.add(('在线', '会话甲'));
    addTearDown(state.dispose);
    await tester.pumpWidget(MaterialApp(home: ChatsTab(state: state)));
    expect(find.byType(PixelLoader), findsNothing);
    // 会话甲放到了首页，只在首页自己那行标；项目行只算没上首页的会话乙。
    final line = find.textContaining('1 个待处理');
    expect(line, findsOneWidget);
    expect(find.textContaining('1 个运行中'), findsNothing);
    final spans = (tester.widget<Text>(line).textSpan! as TextSpan).children!;
    final context = tester.element(line);
    expect(
      (spans[0] as TextSpan).style!.color,
      Theme.of(context).colorScheme.error,
    );
    // 首页上的对话行只标自己的状态。
    expect(find.textContaining('运行中 · 项目甲'), findsOneWidget);
    // 等着用户的数挂在头像上：项目行 1（会话乙待处理），还在跑的会话甲不挂。
    final marks = tester
        .widgetList<Badge>(find.byType(Badge))
        .where((badge) => badge.isLabelVisible && badge.label != null)
        .map((badge) => (badge.label! as Text).data)
        .toList();
    expect(marks, ['1']);
    // 点进项目：会话甲标着「首页」，状态灰着、头像不挂数（它还在跑，
    // 没等着用户，也就没有灰点）。
    await tester.tap(find.textContaining('项目甲（'));
    await tester.pumpAndSettle();
    expect(find.text('首页'), findsOneWidget);
    expect(
      tester
          .widget<Badge>(find.byKey(const ValueKey('home-waiting-dot-在线-会话甲')))
          .isLabelVisible,
      isFalse,
    );
    final running = find.textContaining('运行中');
    expect(
      ((tester.widget<Text>(running).textSpan! as TextSpan).children!.first
              as TextSpan)
          .style!
          .color,
      Theme.of(tester.element(running)).hintColor,
    );
  });

  testWidgets('放到首页的对话在项目里只挂灰点，红数只出现在首页那行', (tester) async {
    final state = _State();
    state.settings.homeSessions.add(('在线', '会话乙'));
    addTearDown(state.dispose);
    await tester.pumpWidget(MaterialApp(home: ChatsTab(state: state)));
    // 首页那行：红色的数，要用户处理。
    final homeRow = find.byKey(const ValueKey('home-在线-会话乙'));
    final homeBadge = tester.widget<Badge>(
      find.descendant(of: homeRow, matching: find.byType(Badge)),
    );
    expect(homeBadge.isLabelVisible, isTrue);
    expect((homeBadge.label! as Text).data, '1');
    // 项目行不再数它：没有别的会话在等。
    final projectRow = find.byKey(const ValueKey('project-在线-p'));
    expect(
      tester
          .widgetList<Badge>(
            find.descendant(of: projectRow, matching: find.byType(Badge)),
          )
          .where((badge) => badge.isLabelVisible),
      isEmpty,
    );
    // 点进项目：它只有个灰点，没有数。
    await tester.tap(find.textContaining('项目甲（'));
    await tester.pumpAndSettle();
    final dot = tester.widget<Badge>(
      find.byKey(const ValueKey('home-waiting-dot-在线-会话乙')),
    );
    expect(dot.isLabelVisible, isTrue);
    expect(dot.label, isNull);
  });

  testWidgets('点标题弹出电脑列表，显示连接方式与断线，切换后只显示那台电脑', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedBuilder(
          animation: state,
          builder: (_, _) => ChatsTab(state: state),
        ),
      ),
    );
    expect(find.text('在线 · 经中继 · 399 毫秒'), findsOneWidget);
    await tester.tap(find.byTooltip('切换电脑'));
    await tester.pumpAndSettle();
    expect(find.text('在线 · 经中继 · 399 毫秒'), findsNWidgets(2));
    expect(find.text('离线 · 正在重连'), findsOneWidget);
    expect(find.text('配对新电脑'), findsOneWidget);
    await tester.tap(find.text('离线设备'));
    await tester.pumpAndSettle();
    expect(state.selectedDesktopId, '离线');
    expect(find.textContaining('项目甲'), findsNothing);
    expect(find.text('离线 · 正在重连'), findsOneWidget);
  });

  testWidgets('列表为空时说明原因：连接中、未连接可重试', (tester) async {
    final state = _EmptyState();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedBuilder(
          animation: state,
          builder: (_, _) => ChatsTab(state: state),
        ),
      ),
    );
    expect(find.text('正在连接 在线电脑…'), findsOneWidget);
    expect(find.text('没有匹配的项目或会话'), findsNothing);
    state.linkState = DesktopLinkStatus.offline;
    state.notifyListeners();
    await tester.pump();
    expect(find.text('在线电脑 离线'), findsOneWidget);
    await tester.tap(find.text('重试'));
    expect(state.retries, ['在线']);
  });

  testWidgets('项目和 Bot 按最近时间混排，没有时间的在最后', (tester) async {
    final state = _State()..withBot = true;
    addTearDown(state.dispose);
    await tester.pumpWidget(MaterialApp(home: ChatsTab(state: state)));
    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(top('小宝'), lessThan(top('项目甲（2）')));
    expect(top('项目甲（2）'), lessThan(top('空项目')));
    // 自己加的 Bot 不是助理，也一样列在首页，按时间排。
    expect(top('小宝'), lessThan(top('审稿 Bot')));
    expect(top('审稿 Bot'), lessThan(top('空项目')));
  });

  testWidgets('只置顶的对话留在项目里；放到首页后与项目同层，置顶的排在最顶', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedBuilder(
          animation: state,
          builder: (_, _) => ChatsTab(state: state),
        ),
      ),
    );
    final row = find.byKey(const ValueKey('home-在线-会话甲'));
    // 会话甲已置顶，但没放到首页：首页只有项目。
    expect(row, findsNothing);

    await state.setOnHome(
      state.sessions.firstWhere((ref) => ref.session.id == '会话甲'),
      true,
    );
    await tester.pump();
    expect(row, findsOneWidget);
    expect(
      tester.getTopLeft(row).dy,
      lessThan(tester.getTopLeft(find.text('项目甲（2）')).dy),
    );
    expect(find.textContaining('在线电脑 ·'), findsNothing);

    await tester.longPress(row);
    await tester.pumpAndSettle();
    expect(find.text('取消置顶'), findsOneWidget);
    await tester.tap(find.text('从首页移除'));
    await tester.pumpAndSettle();
    expect(row, findsNothing);
    // 放到首页只是手机自己的选择，不发请求。
    expect(state.calls, isEmpty);
    expect(find.text('项目甲（2）'), findsOneWidget);
  });
  testWidgets('首页没有筛选按钮，搜索项目名只留下该项目，清除后恢复', (tester) async {
    final state = _State()..withBot = true;
    addTearDown(state.dispose);
    await tester.pumpWidget(MaterialApp(home: ChatsTab(state: state)));
    expect(find.byTooltip('筛选对话'), findsNothing);
    expect(find.text('空项目'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '项目甲');
    await tester.pumpAndSettle();
    expect(find.text('项目甲（2）'), findsOneWidget);
    expect(find.text('空项目'), findsNothing);
    await tester.tap(find.text('清除'));
    await tester.pumpAndSettle();
    expect(find.text('空项目'), findsOneWidget);
    expect(state.calls, isEmpty);
  });
  testWidgets('点击首页上的对话直接打开正确会话', (tester) async {
    final state = _State();
    state.settings.homeSessions.add(('在线', '会话甲'));
    addTearDown(state.dispose);
    await tester.pumpWidget(MaterialApp(home: ChatsTab(state: state)));
    await tester.tap(find.byKey(const ValueKey('home-在线-会话甲')));
    await tester.pumpAndSettle();
    expect(tester.widget<ChatPage>(find.byType(ChatPage)).sessionId, '会话甲');
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('文件页只列所选电脑的项目，不显示对话状态', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedBuilder(
          animation: state,
          builder: (_, _) => FilesTab(state: state),
        ),
      ),
    );
    expect(find.text('项目甲'), findsOneWidget);
    expect(find.textContaining('待处理'), findsNothing);
    state.selectDesktop('离线');
    await tester.pump();
    expect(find.text('项目甲'), findsNothing);
    expect(find.text('电脑离线'), findsOneWidget);
  });

  testWidgets('右上角新建贴着按钮展开；新对话直接打开最近的项目，可在页内切换项目', (tester) async {
    final state = _State()..withBot = true;
    addTearDown(state.dispose);
    await tester.pumpWidget(MaterialApp(home: ChatsTab(state: state)));
    await tester.tap(find.byTooltip('新建'));
    await tester.pumpAndSettle();
    final menu = find.byKey(const ValueKey('dropdown-panel'));
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('添加 Bot'), findsOneWidget);
    expect(find.text('配对新电脑'), findsNothing);
    // 只有两行操作，从按钮下方展开，高度贴合内容。
    expect(find.text('新建'), findsNothing);
    expect(
      tester.getTopLeft(menu).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(find.byTooltip('新建')).dy),
    );

    await tester.tap(find.text('新对话'));
    await tester.pumpAndSettle();
    // 不先弹项目选择，直接进入最近用过的项目。
    expect(state.calls.last, {'project': 'p'});
    expect(tester.widget<ChatPage>(find.byType(ChatPage)).projectId, 'p');

    final card = find.byKey(const ValueKey('new-chat-project'));
    await tester.tap(card);
    await tester.pumpAndSettle();
    // 贴着项目卡片弹出，不是从屏幕底部升起。
    expect(find.byType(BottomSheet), findsNothing);
    final picker = tester.getRect(find.byKey(const ValueKey('dropdown-panel')));
    final anchor = tester.getRect(card);
    expect(picker.top >= anchor.bottom || picker.bottom <= anchor.top, isTrue);
    await tester.tap(find.byKey(const ValueKey('pick-project-e')));
    await tester.pumpAndSettle();
    expect(state.calls.last, {'project': 'e'});
    final page = tester.widget<ChatPage>(find.byType(ChatPage));
    expect(page.projectId, 'e');
    expect(page.sessionId, 'draft-e');
    // 换项目是替换当前页，返回直接回首页。
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(ChatPage), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('置顶的项目和对话、Bot 一样，行尾有图钉', (tester) async {
    final state = _PinnedProject();
    addTearDown(state.dispose);
    await tester.pumpWidget(MaterialApp(home: ChatsTab(state: state)));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('project-在线-置顶')),
        matching: find.byIcon(Icons.push_pin_outlined),
      ),
      findsNothing,
    );
    final pin = find.descendant(
      of: find.byKey(const ValueKey('project-在线-置顶')),
      matching: find.byWidgetPredicate(
        (widget) => widget is LucideIcon && widget.name == 'pin',
      ),
    );
    expect(pin, findsOneWidget);
  });

  testWidgets('点项目行尾的箭头在首页展开它的对话，再点收起，不进入项目', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    await tester.pumpWidget(MaterialApp(home: ChatsTab(state: state)));
    expect(find.byKey(const ValueKey('session-在线-会话乙')), findsNothing);
    expect(find.bySemanticsLabel('展开对话'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('unfold-在线-p')));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('收起对话'), findsOneWidget);
    expect(find.byType(ProjectChatsPage), findsNothing);
    expect(find.text('项目甲（2）'), findsOneWidget);
    expect(find.byKey(const ValueKey('session-在线-会话甲')), findsOneWidget);
    expect(find.byKey(const ValueKey('session-在线-会话乙')), findsOneWidget);
    // 右下角一整块都算点箭头：离图标远一点也只收起，不进项目。
    final corner = tester.getBottomRight(
      find.byKey(const ValueKey('project-在线-p')),
    );
    await tester.tapAt(corner - const Offset(64, 6));
    await tester.pumpAndSettle();
    expect(find.byType(ProjectChatsPage), findsNothing);
    expect(find.byKey(const ValueKey('session-在线-会话乙')), findsNothing);
  });
}
