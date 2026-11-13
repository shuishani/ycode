import 'package:baocode_mobile/chat/chat_models.dart';
import 'package:baocode_mobile/chat/markdown/markdown_view.dart';
import 'package:baocode_mobile/chat/widgets/chat_item_view.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => AppState.debugLanguage = 'zh');
  tearDown(() => AppState.debugLanguage = null);

  Future<void> showPlan(
    WidgetTester tester, {
    required PlanItem plan,
    void Function(String)? onOpenFile,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ChatItemView(item: plan, zh: true, onOpenFile: onOpenFile),
      ),
    ),
  );

  testWidgets('有正文的计划展开对话记录，不依赖已删除的电脑文件', (tester) async {
    final opened = <String>[];
    await showPlan(
      tester,
      plan: const PlanItem(
        path: 'docs/已删除的计划.md',
        round: 1,
        title: '连接恢复计划',
        text: '# 连接恢复计划\n\n先验证写入错误，再检查恢复。\n\n最后核对完整结果。',
      ),
      onOpenFile: opened.add,
    );
    await tester.tap(find.text('连接恢复计划'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is MarkdownView && widget.data.contains('# 连接恢复计划'),
      ),
      findsOneWidget,
    );
    expect(find.text('显示对话中记录的版本，可能不是电脑文件的最新内容。'), findsOneWidget);
    expect(opened, isEmpty);
  });

  testWidgets('没有路径的计划仍可展开已记录的正文', (tester) async {
    await showPlan(
      tester,
      plan: const PlanItem(
        path: '',
        round: 1,
        title: '直接给出的计划',
        text: '直接给出的完整内容',
      ),
    );
    await tester.tap(find.text('直接给出的计划'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('直接给出的完整内容'), findsWidgets);
  });

  testWidgets('没有正文的旧计划仍按原路径打开文件', (tester) async {
    final opened = <String>[];
    await showPlan(
      tester,
      plan: const PlanItem(path: 'plan.md', title: '旧计划', round: 1),
      onOpenFile: opened.add,
    );
    await tester.tap(find.text('旧计划'));
    await tester.pumpAndSettle();
    expect(opened, ['plan.md']);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('被退回的计划也可查看对话中的版本', (tester) async {
    await showPlan(
      tester,
      plan: const PlanItem(
        path: '旧计划.md',
        round: 2,
        text: '退回前的计划内容',
        status: PlanStatus.sentBack,
      ),
    );
    await tester.tap(find.textContaining('已退回'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('退回前的计划内容'), findsOneWidget);
  });
}
