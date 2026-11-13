import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../widgets/image_gallery.dart';

final _imageFile = RegExp(r'\.(png|jpe?g|gif|webp)$', caseSensitive: false);

/// [file] 里 `![](src)` 指向的项目内图片路径；网址、data: 和跳出项目的都不读。
String? markdownImagePath(String file, String src) {
  var target = src.trim().split(RegExp('[?#]')).first;
  if (target.isEmpty ||
      target.startsWith('//') ||
      RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(target)) {
    return null;
  }
  try {
    target = Uri.decodeFull(target);
  } on ArgumentError {
    return null;
  }
  if (!_imageFile.hasMatch(target)) return null;
  // 以 / 开头按项目根算，和 GitHub 上一样；文件本身是绝对路径时不知道根在哪。
  if (target.startsWith('/') && file.startsWith('/')) return null;
  final parts = target.startsWith('/')
      ? <String>[]
      : (file.split('/')..removeLast());
  for (final part in target.split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (parts.where((p) => p.isNotEmpty).isEmpty) return null;
      parts.removeLast();
    } else {
      parts.add(part);
    }
  }
  return parts.join('/');
}

/// 文件预览里的一张图：按比例缩到屏宽内、最高六成屏高，点开全屏看。
class MarkdownFileImage extends StatelessWidget {
  const MarkdownFileImage({
    super.key,
    required this.bytes,
    required this.alt,
    this.width,
  });

  final Future<Uint8List> bytes;
  final String alt;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final colors = Theme.of(context).colorScheme;
    final fallback = Text('[${alt.isEmpty ? 'image' : alt}]');
    // 表格按内容定列宽：图片只报半屏宽，两张并排不用横向滚动；正文里照样铺满。
    return _NarrowIntrinsic(
      width: math.max(120, (screen.width - 40) / 2 - 24),
      child: FutureBuilder<Uint8List>(
        future: bytes,
        builder: (context, snapshot) {
          if (snapshot.hasError) return fallback;
          final data = snapshot.data;
          if (data == null) {
            return Container(
              height: 160,
              width: width ?? double.infinity,
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
            );
          }
          return GestureDetector(
            onTap: () => showImageGallery(context, [
              GalleryImage(data, name: alt.isEmpty ? null : alt),
            ]),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: width ?? double.infinity,
                maxHeight: screen.height * .6,
              ),
              child: Image.memory(data, errorBuilder: (_, _, _) => fallback),
            ),
          );
        },
      ),
    );
  }
}

/// 只把报给父级的固有宽度压到 [width]，实际排版仍按父级给的宽度。
class _NarrowIntrinsic extends SingleChildRenderObjectWidget {
  const _NarrowIntrinsic({required this.width, super.child});
  final double width;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderNarrowIntrinsic(width);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderNarrowIntrinsic renderObject,
  ) => renderObject.width = width;
}

class _RenderNarrowIntrinsic extends RenderProxyBox {
  _RenderNarrowIntrinsic(this._width);
  double _width;

  set width(double value) {
    if (value == _width) return;
    _width = value;
    markNeedsLayout();
  }

  double _narrow(double child) => child <= 0 ? _width : math.min(_width, child);

  @override
  double computeMinIntrinsicWidth(double height) =>
      _narrow(super.computeMinIntrinsicWidth(height));

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _narrow(super.computeMaxIntrinsicWidth(height));
}
