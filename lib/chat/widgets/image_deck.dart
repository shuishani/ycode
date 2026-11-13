import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../ui/widgets/image_gallery.dart';
import 'image_aspect.dart';

/// 一条消息里的图片：一张直接显示；多张叠成一摞，左右滑动翻看，
/// 旁边的“展开”把它们一张张竖着排开。点图片进全屏画廊。
class ImageDeck extends StatefulWidget {
  const ImageDeck({
    super.key,
    required this.images,
    required this.tr,
    this.onLongPress,
  });

  final List<GalleryImage> images;
  final String Function(String zh, String en) tr;
  final VoidCallback? onLongPress;

  @override
  State<ImageDeck> createState() => _ImageDeckState();

  /// 消息里一张图的宽度。
  static const pictureWidth = 136.0;

  /// 按图片自身比例的高度，最高 2.2 倍宽：手机长截图只露上面一截，
  /// 点开全屏再看全，免得一张图占掉半屏。
  static double heightFor(Uint8List bytes, double width) =>
      width * (imageAspect(bytes) ?? 1.3).clamp(.5, 2.2);
}

class _ImageDeckState extends State<ImageDeck> {
  static const _radius = 8.0;

  /// 后面的图从前一张两侧露出来的宽度。
  static const _peek = 20.0;

  final _pages = PageController();
  bool _open = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  double _heightOf(int index, double width) =>
      ImageDeck.heightFor(widget.images[index].bytes, width);

  void _view(int index) =>
      showImageGallery(context, widget.images, initialIndex: index);

  /// 边线和阴影让和页面同色的截图也有边界；[dim] 压暗后面的图，只留层次。
  Widget _picture(int index, double width, double height, {double dim = 0}) {
    final radius = BorderRadius.circular(_radius);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .18),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      foregroundDecoration: BoxDecoration(
        color: Colors.black.withValues(alpha: dim),
        borderRadius: radius,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Image.memory(
          widget.images[index].bytes,
          width: width,
          height: height,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          gaplessPlayback: true,
          semanticLabel: widget.images[index].name,
        ),
      ),
    );
  }

  Widget _tappable(int index, Widget child) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => _view(index),
    onLongPress: widget.onLongPress,
    child: child,
  );

  // 半透明灰：白气泡、灰页面和绿气泡上都看得见。
  Widget _pill(String key, String label, VoidCallback onTap) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    shape: const StadiumBorder(),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      key: ValueKey(key),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(label, style: MobileTheme.metaStyleOf(context)),
      ),
    ),
  );

  Widget _deck(double width) => SizedBox(
    key: const ValueKey('image-deck'),
    width: width + 2 * _peek,
    height: [for (var i = 0; i < widget.images.length; i++) _heightOf(i, width)]
        .reduce(math.max),
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedBuilder(
          animation: _pages,
          builder: (context, _) {
            final page = _pages.hasClients && _pages.position.haveDimensions
                ? _pages.page ?? 0.0
                : 0.0;
            // 离当前页远的先画，当前这张压在最上面。
            final near = [
              for (var i = 0; i < widget.images.length; i++)
                if ((i - page).abs() < 2) i,
            ]..sort((a, b) => (b - page).abs().compareTo((a - page).abs()));
            return Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                for (final i in near)
                  Builder(
                    builder: (context) {
                      final distance = i - page;
                      final away = math.min(distance.abs(), 1.0);
                      return Transform.translate(
                        offset: Offset(distance.clamp(-1.0, 1.0) * _peek, 0),
                        child: Transform.scale(
                          scale: 1 - .1 * away,
                          child: Opacity(
                            opacity: (2 - distance.abs()).clamp(0.0, 1.0),
                            child: _picture(
                              i,
                              width,
                              _heightOf(i, width),
                              dim: .25 * away,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            );
          },
        ),
        PageView.builder(
          controller: _pages,
          itemCount: widget.images.length,
          itemBuilder: (context, index) =>
              _tappable(index, const SizedBox.expand()),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final images = widget.images;
    Widget whole(int i) => _tappable(
      i,
      _picture(i, ImageDeck.pictureWidth, _heightOf(i, ImageDeck.pictureWidth)),
    );
    if (images.length == 1) return whole(0);
    if (_open) {
      Widget fold(String key) => _pill(
        key,
        widget.tr('折叠', 'Collapse'),
        () => setState(() => _open = false),
      );
      // 一张张竖着排，和分开发的一样；“折叠”在第一张旁边，图多时最后一张旁边也有。
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < images.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (i == 0)
                    fold('image-deck-collapse')
                  else if (i == images.length - 1 && images.length >= 3)
                    fold('image-deck-collapse-end'),
                  if (i == 0 || (i == images.length - 1 && images.length >= 3))
                    const SizedBox(width: 8),
                  whole(i),
                ],
              ),
            ),
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        // 窄屏让图片缩一点，“展开”不被挤掉。
        final width = math.min(128.0, box.maxWidth - 2 * _peek - 96);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _pill(
              'image-deck-expand',
              widget.tr('展开 ${images.length}', 'Show ${images.length}'),
              () => setState(() => _open = true),
            ),
            // 后面那张往左探出 [_peek]，留宽一点才不贴着按钮。
            const SizedBox(width: 24),
            _deck(width),
          ],
        );
      },
    );
  }
}
