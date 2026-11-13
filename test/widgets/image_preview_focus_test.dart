import 'package:baocode_mobile/chat/message_view.dart';
import 'package:baocode_mobile/ui/tasks/chat_page.dart';
import 'package:baocode_mobile/ui/widgets/image_gallery.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_test_state.dart';
import '../support/image_test_support.dart';

typedef _State = ChatTestState;

void main() {
  testWidgets('真实聊天页预览图片后保留草稿、光标和阅读位置，不恢复键盘', (tester) async {
    final state = _State();
    addTearDown(state.dispose);
    state.history.items.addAll([
      {
        't': 'user',
        'text': '图片说明',
        'images': [testImageWire('preview.png')],
      },
      for (var i = 0; i < 25; i++) {'t': 'text', 'text': '历史消息 $i\n第二行\n第三行'},
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: ChatPage(
          state: state,
          desktopId: 'desktop',
          sessionId: 'session',
          title: '图片预览测试',
        ),
      ),
    );
    await tester.pumpAndSettle();
    final list = tester.widget<CustomScrollView>(find.byType(CustomScrollView));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 10000));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final image = tester.widget<Image>(
        find.descendant(
          of: find.byType(MemoryPicture),
          matching: find.byType(Image),
        ),
      );
      await precacheImage(
        image.image,
        tester.element(find.byType(MemoryPicture)),
      );
    });
    await tester.pumpAndSettle();
    expect(find.byType(MemoryPicture).hitTestable(), findsOneWidget);

    final field = find.byType(TextField);
    await tester.tap(field);
    await tester.enterText(field, '保留这段草稿');
    final input = tester.widget<TextField>(field);
    input.controller!.selection = const TextSelection.collapsed(offset: 3);
    await tester.pump();
    final offset = list.controller!.offset;
    expect(input.focusNode!.hasFocus, isTrue);
    await tester.tap(find.byType(MemoryPicture));
    await tester.pumpAndSettle();
    expect(find.byType(ImageGalleryPage), findsOneWidget);
    expect(input.focusNode!.hasFocus, isFalse);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(input.focusNode!.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
    expect(input.controller!.text, '保留这段草稿');
    expect(
      input.controller!.selection,
      const TextSelection.collapsed(offset: 3),
    );
    expect(list.controller!.offset, closeTo(offset, 1));
    await tester.tap(field);
    await tester.pump();
    expect(input.focusNode!.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
