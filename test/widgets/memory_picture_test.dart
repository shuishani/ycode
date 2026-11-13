import 'dart:convert';
import 'dart:typed_data';

import 'package:baocode_mobile/chat/chat_models.dart';
import 'package:baocode_mobile/chat/message_view.dart';
import 'package:baocode_mobile/link/chat_codec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/image_test_support.dart';

Map<String, Object?> _wire() => {
  't': 'user',
  'text': '附图要求',
  'images': [testImageWire('example.png')],
};

void main() {
  test('无关文本和工具更新不重复解码同一条历史附件', () {
    final row = _wire();
    final first =
        (ChatCodec.decode(row) as UserMessageItem).images.single.bytes;
    for (var i = 0; i < 50; i++) {
      row['text'] = '附图要求 $i';
      final decoded = ChatCodec.decode(row) as UserMessageItem;
      expect(decoded.text, '附图要求 $i');
      expect(identical(decoded.images.single.bytes, first), isTrue);
    }
    final image = (row['images']! as List).single as Map;
    image['data'] = base64Encode([1, 2, 3]);
    expect((ChatCodec.decode(row) as UserMessageItem).images.single.bytes, [
      1,
      2,
      3,
    ]);
  });

  testWidgets('快照返回相同图片的新字节数组时复用已显示帧，不闪白', (tester) async {
    final first = testImageBytes();
    Widget page(Uint8List bytes) => MaterialApp(
      home: Scaffold(
        body: MemoryPicture(bytes: bytes, name: 'example.png'),
      ),
    );
    await tester.pumpWidget(page(first));
    await tester.runAsync(
      () => precacheImage(
        tester.widget<Image>(find.byType(Image)).image,
        tester.element(find.byType(MemoryPicture)),
      ),
    );
    await tester.pump();
    final provider = tester.widget<Image>(find.byType(Image)).image;
    final frame = tester.widget<RawImage>(find.byType(RawImage)).image;
    expect(frame, isNotNull);
    for (var i = 0; i < 10; i++) {
      await tester.pumpWidget(page(Uint8List.fromList(first)));
      expect(
        identical(tester.widget<Image>(find.byType(Image)).image, provider),
        isTrue,
      );
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, same(frame));
    }
    await tester.pumpWidget(page(Uint8List.fromList([...first, 0])));
    expect(
      identical(tester.widget<Image>(find.byType(Image)).image, provider),
      isFalse,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
