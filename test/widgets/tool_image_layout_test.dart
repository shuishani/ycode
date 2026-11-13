import 'package:baocode_mobile/chat/chat_models.dart';
import 'package:baocode_mobile/chat/message_view.dart';
import 'package:baocode_mobile/chat/widgets/step_header.dart';
import 'package:baocode_mobile/chat/widgets/tool_call_row.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_test_state.dart';

import '../support/image_test_support.dart';

Widget _conversation(ChatTestState state) => MaterialApp(
  home: Scaffold(
    body: ListView(
      children: [
        for (var i = 0; i < state.history.items.length; i++)
          MessageView(
            state: state,
            desktopId: 'desktop',
            sessionId: 'session',
            item: state.history.items[i],
            index: i,
          ),
      ],
    ),
  ),
);

void main() {
  setUp(() => AppState.debugLanguage = 'zh');
  tearDown(() => AppState.debugLanguage = null);

  testWidgets('展开工具步骤只显示一份图片，标题不被缩略图撑高', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ToolCallRow(
            kind: ToolKind.read,
            target: '截图.png',
            expanded: true,
            images: [
              ImageAttachment(bytes: testImageBytes(), mediaType: 'image/png'),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(Image), findsOneWidget);
    expect(tester.getSize(find.byType(StepHeader)).height, lessThan(40));
  });

  testWidgets('收起的工具步骤标题保持文字行高，多图不挤压文件名', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ToolCallRow(
            kind: ToolKind.read,
            target: '一条很长但需要正常显示的截图文件名.png',
            images: [
              for (var i = 0; i < 8; i++)
                ImageAttachment(
                  bytes: testImageBytes(),
                  mediaType: 'image/png',
                ),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(StepHeader)).height, lessThan(40));
  });

  testWidgets('同一会话不同工具步骤的图片可在预览中左右切换', (tester) async {
    final state = ChatTestState(zh: true);
    addTearDown(state.dispose);
    state.history.items.addAll([
      for (var i = 0; i < 2; i++)
        {
          't': 'tool',
          'kind': 'read',
          'target': '截图$i.png',
          'images': [testImageWire('截图$i.png')],
        },
    ]);
    await tester.pumpWidget(_conversation(state));
    await tester.tap(find.byType(Image).first);
    await tester.pumpAndSettle();
    expect(find.text('1 / 2'), findsOneWidget);
    await swipeImageGallery(tester, const Offset(-400, 0));
    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.text('截图1.png'), findsOneWidget);
    await swipeImageGallery(tester, const Offset(400, 0));
    expect(find.text('1 / 2'), findsOneWidget);
  });

  testWidgets('跨步骤重复附加同名同内容图片时，从被点的那次出现打开', (tester) async {
    final state = ChatTestState(zh: true);
    addTearDown(state.dispose);
    state.history.items.addAll([
      for (var i = 0; i < 2; i++)
        {
          't': 'tool',
          'kind': 'read',
          'target': '重复截图.png',
          'images': [testImageWire('重复截图.png')],
        },
    ]);
    await tester.pumpWidget(_conversation(state));
    await tester.tap(find.byType(Image).last);
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('工具截图按会话顺序翻看，不混入用户附件且损坏图不阻断', (tester) async {
    final state = ChatTestState(zh: true);
    addTearDown(state.dispose);
    state.history.items.addAll([
      {
        't': 'user',
        'images': [testImageWire('用户附件.png')],
      },
      {
        't': 'tool',
        'kind': 'read',
        'images': [testImageWire('工具截图.png')],
      },
      {
        't': 'tool',
        'kind': 'read',
        'images': [
          {'data': '*损坏的图片*', 'type': 'image/png', 'name': '损坏截图.png'},
        ],
      },
      {
        't': 'tool',
        'kind': 'read',
        'images': [testImageWire('后续截图.png')],
      },
    ]);
    // 只构建当前工具步骤，其余图片在进入对应预览页时才解码。
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageView(
            state: state,
            desktopId: 'desktop',
            sessionId: 'session',
            index: 1,
            item: state.history.items[1],
          ),
        ),
      ),
    );
    await tester.tap(find.byType(Image).first);
    await tester.pumpAndSettle();
    expect(find.text('1 / 3'), findsOneWidget);
    expect(find.text('工具截图.png'), findsOneWidget);
    expect(find.text('用户附件.png'), findsNothing);
    expect(tester.takeException(), isNull);
    await swipeImageGallery(tester, const Offset(-400, 0));
    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.text('图片无法显示'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('保存到相册'));
    await tester.pumpAndSettle();
    expect(find.text('无法保存图片，请重试。'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await swipeImageGallery(tester, const Offset(-400, 0));
    expect(find.text('3 / 3'), findsOneWidget);
    expect(find.text('后续截图.png'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
