import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bao_link/bao_link.dart';
import 'package:baocode_mobile/link/link_store.dart';
import 'package:baocode_mobile/state/app_state.dart';
import 'package:baocode_mobile/theme/app_theme.dart';
import 'package:baocode_mobile/ui/files/files_tab.dart';
import 'package:baocode_mobile/ui/files/markdown_image.dart';
import 'package:baocode_mobile/ui/widgets/image_gallery.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _State extends AppState {
  _State(this.text, this.picture) : super(store: MemoryLinkStore()) {
    settings.language = 'zh';
  }
  final String text;
  final Uint8List picture;
  final images = <String>[];

  @override
  bool isOnline(String desktop) => true;

  @override
  Future<Object?> request(
    String desktop,
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    if (method == LinkMethods.image) {
      images.add(params['path']! as String);
      if (params['path'] == 'docs/missing.png') {
        throw const LinkRemoteException('not_found', 'missing');
      }
      return {'data': base64Encode(picture)};
    }
    return {'text': text};
  }
}

/// 手机截图那样的竖长图。
Future<Uint8List> _tallPng() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 400, 860),
    Paint()..color = const Color(0xFF3366AA),
  );
  final image = await recorder.endRecording().toImage(400, 860);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

Future<_State> _open(WidgetTester tester, String text) async {
  final picture = (await tester.runAsync(_tallPng))!;
  final state = _State(text, picture);
  addTearDown(state.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: MobileTheme.build(Brightness.light),
      home: FileViewerPage(
        state: state,
        project: const ProjectRef(
          'd',
          ProjectInfo(id: 'p', name: '项目', path: '/workspace'),
        ),
        path: 'README.md',
      ),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  return state;
}

void main() {
  test('图片路径按文件所在目录解析，网址和跳出项目的不读', () {
    expect(markdownImagePath('README.md', 'docs/a.jpg'), 'docs/a.jpg');
    expect(markdownImagePath('docs/x/guide.md', '../a.png'), 'docs/a.png');
    expect(
      markdownImagePath('docs/guide.md', './img/a%20b.png'),
      'docs/img/a b.png',
    );
    expect(
      markdownImagePath('docs/guide.md', '/shots/a.webp?raw=1'),
      'shots/a.webp',
    );
    expect(markdownImagePath('README.md', '../outside.png'), isNull);
    expect(markdownImagePath('README.md', 'https://example.com/a.png'), isNull);
    expect(markdownImagePath('README.md', '//example.com/a.png'), isNull);
    expect(
      markdownImagePath('README.md', 'data:image/png;base64,AAAA'),
      isNull,
    );
    expect(markdownImagePath('README.md', 'docs/notes.txt'), isNull);
    expect(
      markdownImagePath('/home/u/app/README.md', 'docs/a.png'),
      '/home/u/app/docs/a.png',
    );
    expect(markdownImagePath('/home/u/app/README.md', '/a.png'), isNull);
  });

  testWidgets('README 里的项目图片直接显示，按比例缩在屏幕里，点开全屏', (tester) async {
    final state = await _open(tester, '# 标题\n\n![对话](docs/chat.jpg)\n');
    expect(state.images, ['docs/chat.jpg']);
    final image = find.byType(Image);
    expect(image, findsOneWidget);
    final size = tester.getSize(image);
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(size.width, lessThanOrEqualTo(screen.width - 40 + .5));
    expect(size.height, lessThanOrEqualTo(screen.height * .6 + .5));
    expect(size.height / size.width, closeTo(860 / 400, .02), reason: '保持比例');
    await tester.tap(image);
    await tester.pumpAndSettle();
    expect(find.byType(ImageGalleryPage), findsOneWidget);
  });

  testWidgets('表格里两张图并排，不撑出屏幕', (tester) async {
    await _open(
      tester,
      '| 首页 | 对话 |\n| :---: | :---: |\n| ![首页](docs/a.jpg) | ![对话](docs/b.jpg) |\n',
    );
    final images = find.byType(Image);
    expect(images, findsNWidgets(2));
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(tester.getRect(images.at(1)).right, lessThanOrEqualTo(screen.width));
    expect(tester.takeException(), isNull);
  });

  testWidgets('网址图片不联网，读不到的图片退回说明文字', (tester) async {
    final state = await _open(
      tester,
      '![徽章](https://example.com/badge.png)\n\n![丢了](docs/missing.png)\n',
    );
    expect(state.images, ['docs/missing.png']);
    expect(find.text('[徽章]'), findsOneWidget);
    expect(find.text('[丢了]'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}
