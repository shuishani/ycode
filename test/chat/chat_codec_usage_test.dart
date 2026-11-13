import 'dart:typed_data';

import 'package:baocode_mobile/chat/chat_models.dart';
import 'package:baocode_mobile/link/chat_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('整理历史消息不提前解码折叠或屏幕外的图片', () {
    final item = ChatCodec.decode({
      't': 'user',
      'text': '含图片的合成历史',
      'images': [
        {'data': '不是有效的 base64', 'type': 'image/png'},
      ],
    }) as UserMessageItem;
    expect(item.images.single.mediaType, 'image/png');
    // 只有实际取图片时才解码；解码失败仍如实抛出，不吞错误。
    expect(() => item.images.single.bytes, throwsFormatException);
  });

  test('重新同步送来相同图片时用同一份字节，内容不同才换', () {
    Map<String, Object?> message(String data) => {
      't': 'user',
      'text': '图',
      'images': [
        {'data': data, 'type': 'image/png'},
      ],
    };
    Uint8List bytes(String data) => (ChatCodec.decode(
      message(data),
    ) as UserMessageItem).images.single.bytes;
    final first = bytes('AQIDBA==');
    expect(identical(bytes('AQIDBA=='), first), isTrue);
    expect(bytes('BQYHCA=='), [5, 6, 7, 8]);
  });

  test('回合速度保留 wire 数值，缺失时不使用总耗时估算', () {
    for (final speed in <double?>[37.16, null]) {
      final item = ChatCodec.decode({
        't': 'user',
        'text': '问题',
        'worked': 32000,
        'usage': {'in': 200000, 'out': 2070, 'cost': .15, 'speed': ?speed},
      }) as UserMessageItem;
      expect(item.usage!.tokensPerSecond, speed);
      expect(item.usage!.totalTokens, 202070);
      expect((ChatCodec.encode(item)['usage'] as Map)['speed'], speed);
    }
  });
}
