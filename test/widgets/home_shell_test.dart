import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/link/link_store.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:baocode_mobile/ui/home_shell.dart';
import 'package:baocode_mobile/ui/settings/settings_page.dart';
import 'package:baocode_mobile/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Unread extends AppState {
  _Unread() : super(demo: true, store: MemoryLinkStore());
  @override
  List<SessionRef> get sessions => [
    SessionRef(
      'demo-desktop',
      SessionSummary(
        id: 'a',
        project: 'p',
        title: '未读',
        updatedAt: DateTime(2026),
        unread: true,
      ),
    ),
    SessionRef(
      'demo-desktop',
      SessionSummary(
        id: 'b',
        project: 'p',
        title: '已读',
        updatedAt: DateTime(2026),
      ),
    ),
    SessionRef(
      'demo-desktop',
      SessionSummary(
        id: 'c',
        project: 'p',
        title: '后台还在跑',
        updatedAt: DateTime(2026),
        status: LinkSessionStatus.running,
        unread: true,
      ),
    ),
    SessionRef(
      'demo-desktop',
      SessionSummary(
        id: 'd',
        project: 'p',
        title: '在等你',
        updatedAt: DateTime(2026),
        status: LinkSessionStatus.needsInput,
      ),
    ),
  ];
  @override
  List<BotRef> get bots => const [
    BotRef('demo-desktop', LinkBot(id: 'x', name: '小宝', unread: 2)),
  ];
}

void main() {
  testWidgets('左右滑动切换对话、Bot、文件，不会滑进设置', (tester) async {
    final state = AppState(demo: true, store: MemoryLinkStore());
    addTearDown(state.dispose);
    await state.initialize();
    state.settings.language = 'zh';
    await tester.pumpWidget(MaterialApp(home: HomeShell(state: state)));
    await tester.pumpAndSettle();
    Future<void> swipe(double dx) async {
      await tester.fling(find.byType(PageView), Offset(dx, 0), 1200);
      await tester.pumpAndSettle();
    }

    bool selected(String label) => tester
        .widget<Semantics>(
          find
              .byWidgetPredicate(
                (widget) =>
                    widget is Semantics &&
                    widget.properties.button == true &&
                    widget.properties.label == label,
              )
              .first,
        )
        .properties
        .selected!;

    expect(selected('对话'), isTrue);
    await swipe(-300);
    expect(selected('Bot'), isTrue);
    await swipe(-300);
    expect(selected('文件'), isTrue);
    await swipe(-300);
    expect(selected('文件'), isTrue);
    expect(selected('设置'), isFalse);
    await swipe(300);
    expect(selected('Bot'), isTrue);

    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    expect(selected('设置'), isTrue);
    expect(find.byType(PageView), findsNothing);
    await tester.tap(find.text('对话').last);
    await tester.pumpAndSettle();
    expect(find.byType(PageView), findsOneWidget);
    expect(selected('对话'), isTrue);
    await swipe(300);
    expect(selected('对话'), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('底部对话标签只数做完没看、等你处理和 Bot 未读，运行中不算', (tester) async {
    final state = _Unread();
    addTearDown(state.dispose);
    await state.initialize();
    await tester.pumpWidget(
      MaterialApp(
        theme: MobileTheme.build(Brightness.light),
        home: HomeShell(state: state),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('tab-badge-0')),
        matching: find.text('4'),
      ),
      findsOneWidget,
    );
    final other = tester.widget<Badge>(
      find.byKey(const ValueKey('tab-badge-1')),
    );
    expect(other.isLabelVisible, isFalse);
  });

  testWidgets('对话新增菜单只保留新对话与 Bot，不放配对入口', (tester) async {
    final state = AppState(demo: true, store: MemoryLinkStore());
    addTearDown(state.dispose);
    await state.initialize();
    state.settings.language = 'zh';
    await tester.pumpWidget(
      MaterialApp(
        theme: MobileTheme.build(Brightness.light),
        home: HomeShell(state: state),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新建'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('dropdown-panel')), findsOneWidget);
    expect(find.text('新对话'), findsOneWidget);
    expect(find.text('添加 Bot'), findsWidgets);
    expect(find.text('配对新电脑'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('四项导航：对话、Bot、文件、设置', (tester) async {
    final state = AppState(demo: true, store: MemoryLinkStore());
    addTearDown(state.dispose);
    await state.initialize();
    state.settings.language = 'zh';
    await tester.pumpWidget(MaterialApp(home: HomeShell(state: state)));
    await tester.pumpAndSettle();
    expect(find.text('演示模式 · 不会执行命令'), findsOneWidget);
    expect(find.text('对话'), findsWidgets);
    expect(find.text('Bot'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('文件'), findsOneWidget);
    await tester.tap(find.text('文件').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Bot').last);
    await tester.pumpAndSettle();
    expect(find.text('已配对的电脑'), findsNothing);
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('当前版本'), 250);
    expect(find.text(appVersion), findsOneWidget);
    await tester.scrollUntilVisible(find.text('关于 YCode').hitTestable(), 100);
    await tester.tap(find.text('关于 YCode'));
    await tester.pumpAndSettle();
    expect(find.text('YCode'), findsWidgets);
    expect(find.text('版本 $appVersion'), findsOneWidget);
    expect(find.text('更新日志'), findsOneWidget);
    await tester.tap(find.text('开源许可'));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
    expect(find.text(appVersion), findsWidgets);
    Navigator.of(tester.element(find.byType(LicensePage))).pop();
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.text('版本 $appVersion'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('当前版本'));
    await tester.pumpAndSettle();
    expect(find.text('YCode $appVersion'), findsOneWidget);
    expect(find.text('检查更新'), findsOneWidget);
    Navigator.of(tester.element(find.text('YCode $appVersion'))).pop();
    await tester.pumpAndSettle();
    // 检查更新只在版本页出现，设置列表里不重复放一遍。
    expect(find.text('检查更新'), findsNothing);
  });
}
