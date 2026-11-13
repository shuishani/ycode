import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../../ui/widgets/image_gallery.dart';
import '../chat_models.dart';
import 'image_deck.dart';

/// 工具返回的图片只在标题下显示一份，复用消息图片的比例和预览。
class ToolImages extends StatelessWidget {
  const ToolImages({super.key, required this.images});

  final List<ImageAttachment> images;

  @override
  Widget build(BuildContext context) => images.isEmpty
      ? const SizedBox.shrink()
      : Align(
          alignment: Alignment.centerLeft,
          child: ImageDeck(
            images: images.map(GalleryImage.fromAttachment).toList(),
            tr: AppState.phrase,
          ),
        );
}
