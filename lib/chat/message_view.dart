// YCode — conversation UI. GPL-3.0-only.
// Reuses BaoCode's GPL chat models and wire codec.
import 'dart:convert';

import 'package:bao_link/bao_link.dart';
import 'package:flutter/material.dart';

import '../ui/widgets/lucide_icon.dart';
import '../ui/bots/bots_tab.dart';
import 'widgets/image_deck.dart';

import '../state/app_state.dart';
import '../link/chat_codec.dart';
import '../ui/tasks/subagent_page.dart';
import '../ui/widgets/bubble_menu.dart';
import '../ui/widgets/image_gallery.dart';
import '../ui/widgets/mobile_widgets.dart';
import 'chat_links.dart';
import 'chat_markdown.dart';
import 'widgets/message_pictures.dart';
import 'stickers.dart';
import 'widgets/chat_item_view.dart';
import 'widgets/notice_row.dart';
import '../theme/app_theme.dart';
import 'chat_output.dart';
import 'widgets/turn_footer.dart';
import 'chat_models.dart';
import 'chat_clipboard.dart';

export 'chat_links.dart';
export 'chat_markdown.dart';
export 'widgets/message_pictures.dart';

part 'message_view_bot.dart';

/// Bot 对话里气泡的左右边界：12 边距 + 40 头像 + 4 间隔 + 6 气泡尖角，
/// 右侧留出对面头像的位置。卡片和旁白都对齐到这里。
const botContentInsets = EdgeInsets.fromLTRB(62, 0, 56, 0);

/// 自己发的气泡：绿底配深色字，夜间也是，不随主题强调色变。
Color botUserBubbleColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFF3EB575)
    : const Color(0xFF95EC69);

class MessageView extends StatelessWidget {
  const MessageView({
    super.key,
    required this.state,
    required this.desktopId,
    required this.item,
    this.index,
    this.sessionId,
    this.projectId,
    this.onEdit,
    this.showMineJump = false,
    this.onPreviousMine,
    this.onNextMine,
    this.onOpenSession,
    this.footer,
    this.showItem = true,
    this.bot,
  });
  final AppState state;
  final String desktopId;
  final Object? item;
  final int? index;
  final String? sessionId, projectId;
  final ValueChanged<UserMessageItem>? onEdit;

  /// 在自己发的消息下面显示跳到上一条、下一条；没有可跳的那边不能点。
  final bool showMineJump;
  final VoidCallback? onPreviousMine, onNextMine;
  final ValueChanged<String>? onOpenSession;
  final TurnFooterData? footer;
  final bool showItem;
  final BotRef? bot;

  Widget _footer() => TurnFooter(
    answer: footer?.answer,
    worked: footer?.worked,
    usage: footer?.usage,
    live: footer?.live,
    since: footer?.since,
    zh: state.tr('中', 'en') == '中',
  );

  Future<void> _copy(
    BuildContext context,
    String text, {
    List<ImageAttachment> images = const [],
  }) async {
    final String message;
    try {
      await ChatClipboard.copyMessage(text, images);
      message = state.tr('已复制', 'Copied');
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            state.tr('复制失败，请重试。', 'Copy failed. Please try again.'),
          ),
        ),
      );
      return;
    }
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = _build(context);
    return sessionId == null || index == null
        ? content
        : ImageGalleryScope(resolve: _gallerySelection, child: content);
  }

  GallerySelection _gallerySelection(GallerySelection selected) {
    final session = sessionId;
    final source = index;
    if (session == null || source == null) return selected;
    final items = state.buffer(desktopId, session).items;
    if (source < 0 || source >= items.length) return selected;
    final ChatItem? sourceItem;
    try {
      sourceItem = items[source] is ChatItem
          ? items[source] as ChatItem
          : ChatCodec.decode(items[source]);
    } on Object {
      return selected;
    }
    // 用户消息和待发附件保留原分组；只有分散在步骤里的工具截图按会话串联。
    if (sourceItem is! ToolCallItem) return selected;
    final images = <GalleryImage>[];
    int? initialIndex;
    for (var i = 0; i < items.length; i++) {
      final ChatItem? decoded;
      try {
        decoded = items[i] is ChatItem
            ? items[i] as ChatItem
            : ChatCodec.decode(items[i]);
      } on Object {
        // 无法识别的消息仍由原消息行展示，不把它当成图片。
        continue;
      }
      final attachments = switch (decoded) {
        ToolCallItem(:final images, :final status)
            when status != ToolStatus.failed =>
          images,
        _ => const <ImageAttachment>[],
      };
      if (i == source &&
          selected.index >= 0 &&
          selected.index < attachments.length) {
        initialIndex = images.length + selected.index;
      }
      images.addAll(attachments.map(GalleryImage.fromAttachment));
    }
    // 不提前解码整段历史的图片，也不跨会话寻找相同字节；重复附件保留各自位置。
    return initialIndex == null
        ? selected
        : (images: images, index: initialIndex);
  }

  Widget _build(BuildContext context) {
    if (!showItem) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: footer == null || bot != null
            ? const SizedBox.shrink()
            : _footer(),
      );
    }
    ChatItem? decoded;
    try {
      decoded = item is ChatItem ? item as ChatItem : ChatCodec.decode(item);
      final images = switch (decoded) {
        UserMessageItem(:final images) || ToolCallItem(:final images) => images,
        _ => const <ImageAttachment>[],
      };
      for (final image in images) {
        image.load();
      }
    } catch (_) {
      decoded = null;
      /* Malformed or newer wire items still occupy a visible row. */
    }
    final value = decoded;
    if (bot != null && value is AssistantTextItem) {
      final parts = ChatCodec.botParts(value.text);
      if (parts.isNotEmpty) return _botParts(context, parts);
    }
    if (bot != null &&
        (value is UserMessageItem || value is AssistantTextItem)) {
      return _botBubble(context, value!);
    }
    final Widget content;
    if (value is UserMessageItem) {
      content = _userMessage(context, value);
    } else if (value is AssistantTextItem) {
      final parts = ChatCodec.botParts(value.text);
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (parts.isEmpty)
            _prose(value.text)
          else
            for (final (tag, text) in parts) _botPart(context, tag, text),
        ],
      );
    } else if (value is ToolCallItem && value.input['sticker'] is String) {
      // A bot's sticker arrives as a tool item carrying the sticker id.
      // Align gives the sticker loose constraints; the message row's tight
      // width would otherwise stretch the 96px picture across the stream.
      content = Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: StickerView(value.input['sticker'] as String),
        ),
      );
    } else if (value is ToolCallItem && ChatCodec.botImageUrl(value) != null) {
      // A bot picture that travels as a URL: confirmed before fetching.
      content = _fold(
        context,
        '${value.label ?? value.tool ?? value.kind.name} · ${value.target}',
        [
          if (value.output != null) CodePanel(code: value.output!),
          TextButton.icon(
            onPressed: () => confirmExternalLink(
              context,
              state,
              ChatCodec.botImageUrl(value)!,
            ),
            icon: const Icon(Icons.open_in_new),
            label: Text(state.tr('打开外部图片', 'Open external image')),
          ),
        ],
        subtitle: value.status.name,
      );
    } else if (value != null && handledByChatItemView(value)) {
      // The desktop's step rows: thought, tool call, subagent,
      // command, diff, plan and live wait, one line each, opening to more.
      content = _StepRow(
        item: value,
        zh: state.tr('中', 'en') == '中',
        onOpen: value is AgentItem
            ? () => openSubagentPage(
                context,
                state: state,
                desktopId: desktopId,
                projectId: projectId,
                sessionId: sessionId,
                item: value,
              )
            : null,
        onOpenFile: projectId == null && bot == null
            ? null
            : (context, path) => showLinkedFile(
                context,
                state,
                desktopId,
                projectId,
                path,
                botId: bot?.bot.id,
              ),
      );
    } else if (value is NoticeItem) {
      // The desktop's notice row: compaction dividers, command
      // output cards, retry/error/warning/info lines.
      content = NoticeRow(item: value, zh: state.tr('中', 'en') == '中');
    } else {
      content = _fold(context, state.tr('无法识别的消息', 'Unrecognized message'), [
        CodePanel(code: _raw(item)),
      ], subtitle: '#${index ?? '—'}');
    }
    // Tight within a turn, so the gap between turns reads as the boundary.
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        value is UserMessageItem ? 12 : 2,
        16,
        footer != null ? 4 : 2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [content, if (footer != null) _footer()],
      ),
    );
  }

  Widget _prose(String text) => ChatMarkdown(
    state: state,
    desktopId: desktopId,
    projectId: projectId,
    botId: bot?.bot.id,
    text: text,
  );

  Widget _fold(
    BuildContext context,
    String title,
    List<Widget> children, {
    String? subtitle,
    Widget? trailing,
  }) => ExpansionTile(
    tilePadding: const EdgeInsets.symmetric(horizontal: 4),
    trailing: trailing,
    title: Text(title, style: Theme.of(context).textTheme.bodyMedium),
    subtitle: subtitle == null
        ? null
        : Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
    childrenPadding: const EdgeInsets.only(bottom: 12),
    children: children,
  );

  Widget _images(List<ImageAttachment> attachments) {
    // 同一条消息的图片共用一个画廊，点开后可左右翻看。
    final group = attachments.map(GalleryImage.fromAttachment).toList();
    if (group.length > 1) return ImageDeck(images: group, tr: state.tr);
    // 尺寸先占好：解码完才知道比例的话，整段消息会在解码后变高。
    return MemoryPicture(
      bytes: group.single.bytes,
      name: group.single.name,
      width: ImageDeck.pictureWidth,
      height: ImageDeck.heightFor(group.single.bytes, ImageDeck.pictureWidth),
    );
  }

  Widget _botPart(BuildContext context, String tag, String text) {
    if (tag == ChatCodec.botCardTag) {
      final session = state.sessions
          .where((ref) => ref.desktopId == desktopId && ref.session.id == text)
          .firstOrNull
          ?.session;
      final title = _agentTitle(state, session, text);
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        tileColor: Theme.of(context).colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        horizontalTitleGap: 8,
        leading: const Icon(Icons.chat_bubble_outline, size: 20),
        title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: onOpenSession == null
            ? null
            : const Icon(Icons.chevron_right),
        onTap: onOpenSession == null ? null : () => onOpenSession!(text),
      );
    }
    if (tag == ChatCodec.botNarrateTag) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: DefaultTextStyle.merge(
          style: Theme.of(context).textTheme.bodySmall,
          child: _prose(text),
        ),
      );
    }
    return _prose(text);
  }

  Widget _userMessage(BuildContext context, UserMessageItem value) {
    final text = messageBody(value.text, value.images);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    Widget action(String icon, String tooltip, VoidCallback? onTap) => Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 36,
          height: 32,
          child: Center(
            child: LucideIcon(
              icon,
              size: FooterIconButton.iconSize,
              color: onTap == null ? muted.withValues(alpha: .35) : muted,
            ),
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: Container(
                key: const ValueKey('user-message-bubble'),
                constraints: BoxConstraints(
                  maxWidth: ((MediaQuery.sizeOf(context).width - 32) * .82)
                      .clamp(0, 560)
                      .toDouble(),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (ChatCodec.sticker(text) case final stickerId?)
                      StickerView(stickerId)
                    else if (text.isNotEmpty)
                      SelectableText(
                        text,
                        style: MobileTheme.messageStyleOf(context),
                      ),
                    if (value.images.isNotEmpty) _images(value.images),
                    if (value.queued)
                      Text(
                        state.tr('排队中', 'Queued'),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showMineJump) ...[
              action(
                'chevron-up',
                state.tr('上一条我发的消息', 'My previous message'),
                onPreviousMine,
              ),
              action(
                'chevron-down',
                state.tr('下一条我发的消息', 'My next message'),
                onNextMine,
              ),
            ],
            action(
              'copy',
              state.tr('复制', 'Copy'),
              () => _copy(context, value.text, images: value.images),
            ),
            if (onEdit != null)
              action(
                'pencil',
                state.tr('编辑并重新发送', 'Edit and resend'),
                () => onEdit!(value),
              ),
          ],
        ),
      ],
    );
  }
}

/// One step row, as the desktop history shows it: open by default while
/// its thought streams ([defaultExpanded]), opened or closed by hand
/// after. Lives here so the manual state survives the stream rebuilding
/// the row around it.
class _StepRow extends StatefulWidget {
  const _StepRow({
    required this.item,
    required this.zh,
    this.onOpen,
    this.onOpenFile,
  });

  final ChatItem item;
  final bool zh;
  final VoidCallback? onOpen;
  final Future<void> Function(BuildContext context, String path)? onOpenFile;

  @override
  State<_StepRow> createState() => _StepRowState();
}

class _StepRowState extends State<_StepRow> {
  /// The user's own open/closed pick; null, [defaultExpanded] decides.
  bool? _manual;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final expanded = _manual ?? defaultExpanded(item);
    return ChatItemView(
      item: item,
      zh: widget.zh,
      expanded: expanded,
      onToggle: () => setState(() => _manual = !expanded),
      onOpen: widget.onOpen,
      onOpenFile: widget.onOpenFile == null
          ? null
          : (path) => widget.onOpenFile!(context, path),
    );
  }
}

String _raw(Object? value) {
  try {
    return const JsonEncoder.withIndent('  ').convert(value);
  } catch (_) {
    return '$value';
  }
}
