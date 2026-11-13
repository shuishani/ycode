import 'package:bao_link/bao_link.dart';
import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../widgets/mobile_widgets.dart';
import '../widgets/press_menu.dart';
import 'delete_conversation.dart';

/// 首页独立对话与项目内对话共用的长按菜单。
class SessionPressRow extends StatefulWidget {
  const SessionPressRow({
    super.key,
    required this.state,
    required this.session,
    required this.child,
    this.showHome = true,
  });
  final AppState state;
  final SessionRef session;
  final Widget child;

  /// 「放到首页」只对列表首页有意义。
  final bool showHome;

  @override
  State<SessionPressRow> createState() => _SessionPressRowState();
}

class _SessionPressRowState extends State<SessionPressRow> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await runUi(context, action);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final ref = widget.session;
    final session = ref.session;
    final online = state.isOnline(ref.desktopId);
    return PressMenuRow(
      enabled: !_busy,
      items: [
        if (online) ...[
          PressMenuItem(
            session.pinned ? state.tr('取消置顶', 'Unpin') : state.tr('置顶', 'Pin'),
            () => _run(
              () async => state.request(ref.desktopId, LinkMethods.pin, {
                'session': session.id,
                'pinned': !session.pinned,
              }),
            ),
          ),
          PressMenuItem(
            state.tr('重命名', 'Rename'),
            () => _run(() async {
              final title = await askText(
                context,
                state,
                state.tr('重命名', 'Rename'),
                value: session.title,
              );
              if (title == null || title.isEmpty) return;
              await state.request(ref.desktopId, LinkMethods.rename, {
                'session': session.id,
                'title': title,
              });
            }),
          ),
        ],
        // 只是手机自己的选择，离线也能改。
        if (widget.showHome)
          PressMenuItem(
            state.onHome(ref)
                ? state.tr('从首页移除', 'Remove from home')
                : state.tr('放到首页', 'Show on home'),
            () => _run(() => state.setOnHome(ref, !state.onHome(ref))),
          ),
        if (online) ...[
          PressMenuItem(
            state.tr('归档', 'Archive'),
            () => _run(() async {
              if (!await confirmAction(
                context,
                state,
                state.tr('归档对话？', 'Archive conversation?'),
                session.title,
                action: state.tr('归档', 'Archive'),
              )) {
                return;
              }
              await state.request(ref.desktopId, LinkMethods.archive, {
                'session': session.id,
              });
            }),
          ),
          PressMenuItem(
            state.tr('删除该聊天', 'Delete chat'),
            () => _run(
              () => deleteConversation(
                context,
                state,
                desktopId: ref.desktopId,
                sessionId: session.id,
                title: session.title,
              ),
            ),
          ),
        ],
      ],
      child: widget.child,
    );
  }
}
