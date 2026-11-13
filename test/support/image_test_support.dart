import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 有效的合成单像素 PNG，不包含用户图片。
const testImageBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=';
final _png = base64Decode(testImageBase64);

/// 每次返回独立字节；尾部序号用于区分翻页后复制或保存的是哪张图。
Uint8List testImageBytes([int? suffix]) =>
    Uint8List.fromList([..._png, ?suffix]);

Map<String, Object?> testImageWire(String name) => {
  'data': testImageBase64,
  'type': 'image/png',
  'name': name,
};

Future<void> swipeImageGallery(WidgetTester tester, Offset by) async {
  await tester.fling(find.byType(PageView), by, 1500);
  await tester.pumpAndSettle();
}
