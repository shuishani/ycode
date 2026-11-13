part of 'message_view.dart';

/// 新 agent 的临时 id 不是给人看的，还没标题时也不露出来。
String _agentTitle(AppState state, SessionSummary? session, String id) {
  if (session == null) return id;
  final title = session.title.trim();
  return title.isEmpty ? state.tr('新对话', 'New chat') : session.title;
}

/// 和 Bot 聊天的样子：头像、带尖角的气泡、图片自成一条。
extension _BotMessage on MessageView {
  Widget _botParts(BuildContext context, List<(String, String)> parts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (tag, text) in parts)
          if (tag == ChatCodec.botCardTag)
            _BotAgentCard(
              state: state,
              desktopId: desktopId,
              bot: bot!,
              id: text,
              onOpen: onOpenSession,
            )
          else if (tag == ChatCodec.botNarrateTag)
            Padding(
              padding: botContentInsets.add(
                const EdgeInsets.symmetric(vertical: 4),
              ),
              child: _botPart(context, tag, text),
            )
          else
            MessageView(
              state: state,
              desktopId: desktopId,
              item: AssistantTextItem(text),
              bot: bot,
              projectId: projectId,
              sessionId: sessionId,
              onOpenSession: onOpenSession,
            ),
      ],
    );
  }

  Widget _botBubble(BuildContext context, ChatItem value) {
    final user = value is UserMessageItem;
    final text = user
        ? ChatCodec.withoutBotEvents(messageBody(value.text, value.images))
        : (value as AssistantTextItem).text;
    final scheme = Theme.of(context).colorScheme;
    final color = user
        ? botUserBubbleColor(context)
        : scheme.surfaceContainerLow;
    final avatar = user
        ? LetterAvatar(
            state.settings.name.isEmpty ? '我' : state.settings.name,
            image: state.settings.avatar,
            size: 40,
          )
        : BotAvatar(state: state, ref: bot!, size: 40);
    final sticker = ChatCodec.sticker(text);
    final body = sticker != null
        ? StickerView(sticker)
        : user
        ? Text(
            text,
            style: MobileTheme.messageStyleOf(context)
                .copyWith(color: const Color(0xFF111111)),
          )
        // 气泡是白的，里面的代码块要用白底上的浅灰。
        : MobileTheme.reading(context, child: _prose(text));
    void press(BuildContext anchor) => showBubbleMenu(anchor, [
      BubbleMenuAction(
        icon: 'copy',
        label: state.tr('复制', 'Copy'),
        onTap: () =>
            _copy(context, text, images: user ? value.images : const []),
      ),
      if (user && onEdit != null)
        BubbleMenuAction(
          icon: 'pencil',
          label: state.tr('编辑重发', 'Edit'),
          onTap: () => onEdit!(value),
        ),
    ]);
    final bubble = Flexible(
      child: Builder(
        builder: (anchor) => GestureDetector(
          onLongPress: () => press(anchor),
          child: Container(
            key: ValueKey(user ? 'bot-user-bubble' : 'bot-answer-bubble'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
            ),
            child: body,
          ),
        ),
      ),
    );
    final tail = Transform.translate(
      offset: Offset(user ? -1 : 1, 0),
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: CustomPaint(
          size: const Size(6, 10),
          painter: _BubbleTail(color, user),
        ),
      ),
    );
    final words = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisAlignment: user
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: user
            ? [
                const SizedBox(width: 44),
                bubble,
                tail,
                const SizedBox(width: 4),
                avatar,
              ]
            : [
                avatar,
                const SizedBox(width: 4),
                tail,
                bubble,
                const SizedBox(width: 44),
              ],
      ),
    );
    if (!user || value.images.isEmpty) return words;
    // 图片自成一条，不进气泡；只有图时也不留空气泡。
    return Column(
      children: [
        if (text.isNotEmpty) words,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Builder(
                    builder: (anchor) => ImageDeck(
                      key: const ValueKey('bot-user-images'),
                      images: value.images
                          .map(GalleryImage.fromAttachment)
                          .toList(),
                      tr: state.tr,
                      onLongPress: () => press(anchor),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              avatar,
            ],
          ),
        ),
      ],
    );
  }
}

/// Bot 发的对话卡片：标题、状态和项目，点开进那个对话。
class _BotAgentCard extends StatelessWidget {
  const _BotAgentCard({
    required this.state,
    required this.desktopId,
    required this.bot,
    required this.id,
    this.onOpen,
  });

  final AppState state;
  final String desktopId, id;
  final BotRef bot;
  final ValueChanged<String>? onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final session = state.sessions
        .where((ref) => ref.desktopId == desktopId && ref.session.id == id)
        .firstOrNull
        ?.session;
    final title = _agentTitle(state, session, id);
    final project = state.projects
        .where(
          (ref) =>
              ref.desktopId == desktopId && ref.project.id == session?.project,
        )
        .firstOrNull
        ?.project
        .name;
    final status = switch (session?.status) {
      LinkSessionStatus.running => state.tr('[运行中]', '[Running]'),
      LinkSessionStatus.needsInput => state.tr('[等你处理]', '[Needs you]'),
      _ => null,
    };
    final meta = MobileTheme.metaStyleOf(context);
    final card = Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('bot-agent-card'),
        onTap: onOpen == null ? null : () => onOpen!(id),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: MobileTheme.messageStyleOf(context),
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        style: meta,
                        children: [
                          if (status != null)
                            TextSpan(
                              text: '$status ',
                              style: TextStyle(
                                color: MobileTheme.statusColorsOf(context).info,
                              ),
                            ),
                          if (project != null) TextSpan(text: project),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  LetterAvatar(title, size: 40),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BotAvatar(state: state, ref: bot, size: 40),
          const SizedBox(width: 4),
          Transform.translate(
            offset: const Offset(1, 0),
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: CustomPaint(
                size: const Size(6, 10),
                painter: _BubbleTail(scheme.surfaceContainerLow, false),
              ),
            ),
          ),
          Expanded(child: card),
          const SizedBox(width: 44),
        ],
      ),
    );
  }
}

class _BubbleTail extends CustomPainter {
  const _BubbleTail(this.color, this.right);
  final Color color;
  final bool right;
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(right ? 0 : size.width, 0)
      ..lineTo(right ? size.width : 0, size.height / 2)
      ..lineTo(right ? 0 : size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_BubbleTail oldDelegate) =>
      color != oldDelegate.color || right != oldDelegate.right;
}
