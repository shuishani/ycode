import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../chat/chat_clipboard.dart';
import '../../chat/chat_models.dart';
import '../../state/app_state.dart';
import 'mobile_widgets.dart';

/// 画廊里的一张图。
class GalleryImage {
  const GalleryImage(Uint8List this._bytes, {this.name}) : _loadBytes = null;
  GalleryImage.lazy({required Uint8List Function() this._loadBytes, this.name})
    : _bytes = null;

  /// 统一附件转换，保留按需读取字节，避免预览前解码整段历史。
  factory GalleryImage.fromAttachment(ImageAttachment attachment) =>
      GalleryImage.lazy(
        loadBytes: () => attachment.bytes,
        name: attachment.name,
      );

  final Uint8List? _bytes;
  final Uint8List Function()? _loadBytes;
  Uint8List get bytes => _bytes ?? _loadBytes!();
  final String? name;
}

typedef GallerySelection = ({List<GalleryImage> images, int index});

/// 在点击时才收集当前对话的图片；附件编辑区没有此作用域，仍只预览待发附件。
class ImageGalleryScope extends InheritedWidget {
  const ImageGalleryScope({
    super.key,
    required this.resolve,
    required super.child,
  });

  final GallerySelection Function(GallerySelection selection) resolve;

  static ImageGalleryScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ImageGalleryScope>();

  @override
  bool updateShouldNotify(ImageGalleryScope oldWidget) =>
      resolve != oldWidget.resolve;
}

/// 保存当前图片；默认写入系统相册，测试可替换为平台边界的 fake。
typedef GallerySaver = Future<void> Function(
  BuildContext context,
  Uint8List bytes,
);

Future<void> _saveToGallery(BuildContext context, Uint8List bytes) =>
    saveImageToGallery(context, bytes, album: 'YCode');

/// 全屏打开同组图片，从 [initialIndex] 开始，左右滑动切换。
Future<void> showImageGallery(
  BuildContext context,
  List<GalleryImage> images, {
  int initialIndex = 0,
  GallerySaver? saver,
}) {
  // 先放掉输入焦点：否则关闭路由时焦点会回到输入框并再次弹出键盘。
  // 只是失焦，控制器里的草稿与光标不变；用户再点输入框即可正常聚焦。
  FocusManager.instance.primaryFocus?.unfocus();
  final selected = ImageGalleryScope.maybeOf(context)
      ?.resolve((images: images, index: initialIndex));
  return showDialog<void>(
    context: context,
    builder: (_) => Dialog.fullscreen(
      child: ScaffoldMessenger(
        child: ImageGalleryPage(
          images: selected?.images ?? images,
          initialIndex: selected?.index ?? initialIndex,
          saver: saver,
        ),
      ),
    ),
  );
}

/// 同组图片的全屏查看页：n / total 计数、双指缩放、保存当前页。
class ImageGalleryPage extends StatefulWidget {
  const ImageGalleryPage({
    super.key,
    required this.images,
    this.initialIndex = 0,
    this.saver,
  }) : assert(images.length > 0);

  final List<GalleryImage> images;
  final int initialIndex;
  final GallerySaver? saver;

  @override
  State<ImageGalleryPage> createState() => _ImageGalleryPageState();
}

class _ImageGalleryPageState extends State<ImageGalleryPage> {
  late final PageController _pages;
  late int _index;
  // 当前页已放大时锁住翻页，让横向拖动只用于平移图片。
  bool _zoomed = false;
  bool _copying = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.images.length - 1);
    _pages = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _setZoomed(bool zoomed) {
    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
  }

  Future<void> _copy() async {
    final image = widget.images[_index];
    setState(() => _copying = true);
    try {
      await ChatClipboard.copyImage(image.bytes, name: image.name);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppState.phrase('图片已复制', 'Image copied'))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppState.phrase(
                '无法复制图片，请重试。',
                'Could not copy the image. Try again.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  Future<void> _save() async {
    try {
      await (widget.saver ?? _saveToGallery)(
        context,
        widget.images[_index].bytes,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppState.phrase(
                '无法保存图片，请重试。',
                'Could not save the image. Try again.',
              ),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.images;
    final current = images[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (images.length > 1) Text('${_index + 1} / ${images.length}'),
            if (current.name != null)
              Text(
                current.name!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: Colors.white70),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: AppState.phrase('复制图片', 'Copy image'),
            icon: const Icon(Icons.copy),
            onPressed: _copying ? null : _copy,
          ),
          IconButton(
            tooltip: AppState.phrase('保存到相册', 'Save to gallery'),
            icon: const Icon(Icons.save_alt),
            onPressed: _save,
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pages,
        itemCount: images.length,
        physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
        onPageChanged: (index) => setState(() {
          _index = index;
          _zoomed = false;
        }),
        itemBuilder: (_, i) => _GalleryPage(
          // 含索引：同一份字节被重复附加时各页仍有独立身份。
          key: ValueKey((i, images[i])),
          image: images[i],
          onZoomed: (zoomed) {
            if (i == _index) _setZoomed(zoomed);
          },
        ),
      ),
    );
  }
}

class _GalleryPage extends StatefulWidget {
  const _GalleryPage({super.key, required this.image, required this.onZoomed});
  final GalleryImage image;
  final ValueChanged<bool> onZoomed;

  @override
  State<_GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<_GalleryPage> {
  final _controller = TransformationController();
  MemoryImage? _provider;
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    try {
      _provider = MemoryImage(widget.image.bytes);
    } on FormatException {
      // 损坏的附件显示错误占位，但不阻止继续翻看其他图片。
    }
    _controller.addListener(_scaled);
  }

  void _scaled() {
    final zoomed = _controller.value.getMaxScaleOnAxis() > 1.01;
    if (_zoomed == zoomed) return;
    setState(() => _zoomed = zoomed);
    widget.onZoomed(zoomed);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_scaled)
      ..dispose();
    // 关闭后不让大图继续占用全局图片缓存。
    _provider?.evict();
    super.dispose();
  }

  Widget _invalidImage() => Center(
    child: Text(
      AppState.phrase('图片无法显示', 'Unable to display image'),
      style: const TextStyle(color: Colors.white),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final provider = _provider;
    if (provider == null) return _invalidImage();
    return InteractiveViewer(
      transformationController: _controller,
      panEnabled: _zoomed,
      minScale: 1,
      maxScale: 8,
      child: SizedBox.expand(
        child: Image(
          image: provider,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _invalidImage(),
        ),
      ),
    );
  }
}
