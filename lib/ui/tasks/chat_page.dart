// YCode — GPL-3.0-only.
import 'dart:async';
import 'dart:math' as math;

import 'package:bao_link/bao_link.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:image_picker/image_picker.dart';

import '../../chat/chat_models.dart';
import '../../chat/chat_clipboard.dart';
import '../../chat/chat_output.dart';
import '../../chat/step_folds.dart';
import '../../chat/widgets/edits_fold_line.dart';
import '../../chat/widgets/fold_line.dart';
import '../../chat/widgets/notice_row.dart';
import '../../chat/message_view.dart';
import '../../chat/widgets/pixel_loader.dart';
import '../../link/chat_codec.dart';
import '../../models/user_facing_error.dart';
import '../../link/phone_link.dart' show DesktopLinkStatus;
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../state/conversation_binding.dart';
import '../../state/conversation_input.dart';
import '../../state/local_message_queue.dart';
import '../files/files_tab.dart';
import '../bots/bots_tab.dart';
import '../widgets/image_gallery.dart';
import '../widgets/lucide_icon.dart';
import '../widgets/dropdown_panel.dart';
import '../widgets/fold_row.dart';
import '../widgets/mobile_widgets.dart';
import '../widgets/model_icon.dart';
import 'changes_page.dart';
import 'goal_page.dart';
import 'interaction_panel.dart';
import 'bot_working_line.dart';
import 'emoji_panel.dart';
import 'model_settings_sheet.dart';
import 'chat_empty_state.dart';
import 'chat_composer_action.dart';
import 'task_stop_button.dart';
import 'composer_banners.dart';
import 'session_sync_notice.dart';
import 'slash_commands.dart';
import 'chat_activity_card.dart';
import 'context_usage.dart';
import 'rewind_files.dart';
import 'running_agents.dart';
import '../devices/device_menu.dart' show linkStatusLabel;
import '../conversations/chats_tab.dart' show newConversation;
import '../conversations/delete_conversation.dart';
import '../conversations/open_conversation.dart';
import 'task_page.dart';
import 'subagent_page.dart';
import '../user_message.dart';
import '../widgets/formats.dart';

part 'chat_page_choices.dart';
part 'chat_page_composer.dart';
part 'chat_page_history.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.state,
    required this.desktopId,
    required this.sessionId,
    required this.title,
    this.projectId,
    this.botId,
    this.projectUnavailable = false,
    this.onSwitchProject,
    this.leading,
    this.onLeave,
    this.onNewConversation,
    this.onBack,
  });
  final bool projectUnavailable;

  /// A new conversation, not begun yet, may go to another project: this
  /// picks it and opens it in this page's place.
  final Future<void> Function(BuildContext context)? onSwitchProject;

  /// 标题栏左边的按钮，换掉返回：沉浸模式里是打开侧边栏。
  final Widget? leading;

  /// 删除或归档后离开这段对话；不给就退回上一页。
  final VoidCallback? onLeave;

  /// 换成在原地开新对话，标题栏上也多一个按钮；不给就新开一页。
  final VoidCallback? onNewConversation;

  /// 返回键不离开这一页，换成做这件事：沉浸模式里是打开侧边栏。
  final VoidCallback? onBack;
  final AppState state;
  final String desktopId, sessionId, title;
  final String? projectId, botId;
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  late final TextEditingController _composer;
  final _scroll = ScrollController();
  final _historyListKey = GlobalKey();
  var _historyRowKeys = <(String, int), GlobalKey>{};
  List<ChatRow> _rows = const [];
  int _jumpTicket = 0;
  final _composerFocus = FocusNode();
  final _addRegion = Object();
  bool _addOpen = false;
  // 打开的是表情面板，不是加号面板；只有 Bot 有。
  bool _emojiPanel = false;
  bool get _pinned => widget.state.sessions.any(
    (ref) =>
        ref.desktopId == widget.desktopId &&
        ref.session.id == _sessionId &&
        ref.session.pinned,
  );
  final _images = <DraftImage>[];
  final _mentions = <String>{};
  Timer? _draftTimer;
  bool _sending = false, _commandBusy = false, _picking = false;

  /// The conversation has been asked for once: an empty one is empty, not
  /// still on its way.
  bool _opened = false;
  int? _editIndex;
  String? _beforeEdit;
  MessageEditAnchor? _editAnchor;
  bool _draftDirty = false,
      _imagesMissing = false,
      _beforeEditImagesMissing = false;
  final _beforeEditImages = <DraftImage>[];
  final _beforeEditMentions = <String>{};
  String? _error;
  bool _follow = true;

  /// 往回看时运行中的回合：它和之后的回合先不收起，否则内容一短位置就被顶到底部。
  int? _keepOpenFrom;

  /// 这一条及之后往下长，之前的往上长：往前加载时现有内容一动不动。
  int _centerItem = 0;
  String? _centerSession;

  /// 打开时列表已经到了底部才显示，看不到它从顶上滚下来。
  bool _placed = false, _placing = false;
  bool _userScrolling = false;
  bool _loadingEarlier = false;
  Future<void>? _earlierLoad;
  Object? _preloadedFrom;
  String? _earlierError;
  final _away = ValueNotifier<bool>(false);

  /// Bumped as the user starts to scroll: the tray over the composer folds.
  final _trayFold = ValueNotifier<int>(0);
  late final ConversationBinding _binding;
  bool _sawBot = false;
  int _lastRevision = -1;

  /// Which folds (a run of steps, a turn's work) stand open.
  final _foldsOpen = <(StepFoldKind, int), bool>{};

  /// 换上游的模型画在哪：行号（从 1 起）前面几条，和最后一行后面几条。
  final _marksBefore = <int, List<String>>{};
  final _marksAfter = <String>[];

  /// 电脑上这个项目的 `.claude/commands` 和能用的技能，打 `/` 时问；
  /// null 是还没拿到，过了 [_desktopCommandsDue] 再打 `/` 时重问。
  List<SlashCommand>? _projectCommands, _skills;
  DateTime _desktopCommandsDue = DateTime(0);

  /// Plans the desktop answered `notFound` to Start for: not pending any
  /// more, whatever the history says (see [pendingPlans]).
  final _lostPlans = <String>{};
  String get _draftSession =>
      widget.botId == null ? widget.sessionId : 'bot:${widget.botId}';
  bool get _editValid => _editAnchor?.matches(_buffer) ?? true;
  // 同步途中手机和电脑的序号可能对不上，等它完成再发。
  bool get _editReady => _editValid && !(_editIndex != null && _buffer.loading);
  InputDraft get _input => InputDraft(
    text: _composer.text,
    images: List.of(_images),
    mentions: Set.of(_mentions),
    imagesMissing: _imagesMissing,
  );
  String get _sessionId =>
      _binding.sessionId ??
      (widget.botId == null ? widget.sessionId : 'bot:${widget.botId}');
  bool get _hasSession => _binding.sessionId != null;
  SessionBuffer get _buffer =>
      widget.state.buffer(widget.desktopId, _sessionId);
  bool get _online =>
      _binding.available && widget.state.isOnline(widget.desktopId);
  ProjectRef? get _project => widget.state.projects
      .where(
        (ref) =>
            ref.desktopId == widget.desktopId &&
            ref.project.id == widget.projectId,
      )
      .firstOrNull;
  String tr(String zh, String en) => widget.state.tr(zh, en);

  @override
  void initState() {
    super.initState();
    _binding = ConversationBinding(
      // 首帧就用真实会话，已有的消息不必先闪一下加载中。
      sessionId: widget.botId == null
          ? (widget.sessionId.startsWith('bot:') ? null : widget.sessionId)
          : widget.state.bots
                .where(
                  (ref) =>
                      ref.desktopId == widget.desktopId &&
                      ref.bot.id == widget.botId,
                )
                .firstOrNull
                ?.bot
                .session,
      errorMessage: (error) => userMessage(widget.state, error),
      retain: (session) => widget.state.openSession(widget.desktopId, session),
      release: (session) =>
          widget.state.closeSession(widget.desktopId, session),
      refreshSession: (session) =>
          widget.state.refreshSession(widget.desktopId, session),
      verifyTarget: widget.botId == null
          ? null
          : () async {
              if (!widget.state.ready) {
                return ConversationTarget(sessionId: _binding.sessionId);
              }
              final snapshot = await widget.state.refreshDesktopState(
                widget.desktopId,
              );
              final bot = snapshot.bots
                  .where((bot) => bot.id == widget.botId)
                  .firstOrNull;
              return ConversationTarget(
                sessionId: bot?.session,
                available: bot != null,
              );
            },
    );
    final draft = widget.state.inputDraft(
      widget.desktopId,
      _draftSession,
      legacySessionId: widget.sessionId,
    );
    _images.addAll(draft.images);
    _mentions.addAll(draft.mentions);
    _imagesMissing = draft.imagesMissing;
    _composer = TextEditingController(
      text: draft.text.isNotEmpty
          ? draft.text
          : widget.state.draft(widget.desktopId, _draftSession),
    );
    _composer.addListener(_draftChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _binding.addListener(_bindingChanged);
      widget.state.addListener(_workspaceChanged);
      _workspaceChanged();
      unawaited(
        _binding.settled.whenComplete(() {
          if (mounted) setState(() => _opened = true);
        }),
      );
    });
  }

  void _bindingChanged() {
    if (mounted) setState(() {});
  }

  void _workspaceChanged() {
    if (!mounted) return;
    final botId = widget.botId;
    String? session = widget.sessionId.startsWith('bot:')
        ? null
        : widget.sessionId;
    var available = true;
    if (botId != null) {
      final bot = widget.state.bots
          .where(
            (ref) => ref.desktopId == widget.desktopId && ref.bot.id == botId,
          )
          .firstOrNull;
      if (bot != null) {
        _sawBot = true;
        session = bot.bot.session;
      } else {
        available =
            !_sawBot &&
            !(widget.state.ready &&
                widget.state.snapshots.containsKey(widget.desktopId));
        session = available ? (_binding.sessionId ?? session) : null;
      }
    }
    _binding.update(
      sessionId: session,
      online: widget.state.isOnline(widget.desktopId),
      available: available,
    );
    // A turn that ended lets the messages queued on the phone go out.
    if (_hasSession) {
      widget.state.localQueue.drain(widget.desktopId, _sessionId);
    }
  }

  Future<void> _open() => _binding.refresh();

  void _draftChanged() {
    if (mounted) setState(() {});
    if (_editIndex != null) return;
    _draftDirty = true;
    _draftTimer?.cancel();
    _draftTimer = Timer(
      const Duration(milliseconds: 350),
      () => _saveDraft(_composer.text),
    );
  }

  void _saveDraft(String text) {
    // 立即更新内存草稿；安全存储写入由 AppState 串行化，慢写不阻断跨页恢复。
    _draftTimer?.cancel();
    _draftDirty = false;
    final state = widget.state,
        desktop = widget.desktopId,
        session = _draftSession;
    final draft = InputDraft(
      text: text,
      images: List.of(_images),
      mentions: Set.of(_mentions),
      imagesMissing: _imagesMissing,
    );
    unawaited(
      state.saveInputDraft(desktop, session, draft).catchError((Object error) {
        if (mounted) setState(() => _error = userMessage(state, error));
      }),
    );
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _reserveTimer?.cancel();
    if (_editIndex == null && _draftDirty) _saveDraft(_composer.text);
    _composer.removeListener(_draftChanged);
    _composer.dispose();
    _composerFocus.dispose();
    _scroll.dispose();
    _away.dispose();
    _trayFold.dispose();
    widget.state.removeListener(_workspaceChanged);
    _binding.removeListener(_bindingChanged);
    _binding.dispose();
    super.dispose();
  }

  Future<void> _command(
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    if (_commandBusy || !_hasSession) return;
    setState(() {
      _commandBusy = true;
      _error = null;
    });
    try {
      await widget.state.request(widget.desktopId, method, {
        'session': _sessionId,
        ...params,
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = userMessage(widget.state, error));
      }
    } finally {
      if (mounted) setState(() => _commandBusy = false);
    }
  }

  /// Starts [raw], the plan [pendingPlans] found pending. The desktop has
  /// the last word: when it is not waiting on that plan after all
  /// (`notFound`), the plan reads expired and the button goes, and the
  /// composer offers the words to go on with instead of a dead end.
  Future<void> _startPlan(Object? raw) async {
    if (_commandBusy || !_hasSession) return;
    final plan = ChatCodec.decode(raw);
    setState(() {
      _commandBusy = true;
      _error = null;
    });
    try {
      await widget.state.request(widget.desktopId, LinkMethods.startPlan, {
        'session': _sessionId,
      });
    } catch (error) {
      if (!mounted) return;
      final gone =
          error is LinkRemoteException &&
          error.code == LinkErrors.notFound &&
          plan is PlanItem;
      setState(() {
        if (!gone) {
          _error = userMessage(widget.state, error);
          return;
        }
        _lostPlans.add(planKey(plan));
        if (_composer.text.trim().isEmpty) {
          _composer.text = tr('按计划开始执行', 'Go ahead with the plan');
        }
        _error = tr(
          '电脑上这个计划已经不在等你确认了。可以直接发消息让它按计划继续，输入框里已经填好。',
          'The desktop is no longer waiting on this plan. Send a message to go on with it; one is ready in the box.',
        );
      });
    } finally {
      if (mounted) setState(() => _commandBusy = false);
    }
  }

  /// The chat's ⋯ menu: browse the project's files, pin, rename, archive —
  /// the same session operations the list's long-press offers.
  Future<void> _sessionMenu(String action) async {
    final session = _sessionId;
    if (action == 'changes') {
      await openPage<void>(
        context,
        ChangesPage(
          state: widget.state,
          desktopId: widget.desktopId,
          sessionId: session,
          projectId: widget.projectId,
        ),
      );
      return;
    }
    if (action == 'tasks') {
      await openPage<void>(
        context,
        TasksPage(
          state: widget.state,
          desktopId: widget.desktopId,
          sessionId: session,
        ),
      );
      return;
    }
    if (!_online) return;
    switch (action) {
      case 'new':
        if (widget.onNewConversation case final start?) return start();
        final project = _project;
        if (project == null) return;
        await newConversation(context, widget.state, project: project);
      case 'files':
        final ref = widget.state.projects
            .where(
              (r) =>
                  r.desktopId == widget.desktopId &&
                  r.project.id == widget.projectId,
            )
            .firstOrNull;
        if (ref == null || !mounted) return;
        await openPage<void>(
          context,
          FilesPage(state: widget.state, project: ref),
        );
      case 'pin':
        await widget.state.request(widget.desktopId, LinkMethods.pin, {
          'session': session,
          'pinned': !_pinned,
        });
      case 'rename':
        if (!mounted) return;
        final controller = TextEditingController(text: widget.title);
        final title = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(tr('重命名', 'Rename')),
            content: TextField(controller: controller, autofocus: true),
            actions: dialogButtons([
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: Text(tr('取消', 'Cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, controller.text.trim()),
                child: Text(tr('保存', 'Save')),
              ),
            ]),
          ),
        );
        if (title == null || title.isEmpty) return;
        await widget.state.request(widget.desktopId, LinkMethods.rename, {
          'session': session,
          'title': title,
        });
      case 'delete':
        if (widget.botId != null) return;
        final deleted = await deleteConversation(
          context,
          widget.state,
          desktopId: widget.desktopId,
          sessionId: session,
          title: widget.title,
        );
        if (deleted && mounted) _leave();
      case 'archive':
        if (!mounted) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(tr('归档', 'Archive')),
            content: Text(tr('归档后对话从列表收起。', 'The chat moves out of the list.')),
            actions: dialogButtons([
              OutlinedButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(tr('取消', 'Cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(tr('归档', 'Archive')),
              ),
            ]),
          ),
        );
        if (confirmed != true) return;
        await widget.state.request(widget.desktopId, LinkMethods.archive, {
          'session': session,
        });
        if (!mounted) return;
        _leave();
    }
  }

  void _leave() =>
      widget.onLeave != null ? widget.onLeave!() : Navigator.of(context).pop();

  Future<void> _send() async {
    if (_sending ||
        !_online ||
        (_composer.text.trim().isEmpty && _images.isEmpty)) {
      return;
    }
    if (_imagesMissing) {
      setState(
        () => _error = tr(
          '部分图片未恢复，请重新添加或明确忽略丢失附件。',
          'Some images could not be restored. Reattach them or explicitly dismiss the missing attachments.',
        ),
      );
      return;
    }
    // The agent is at work (or earlier queued messages still wait): this one
    // waits on the phone with them, so order holds and nothing interrupts.
    if (_editIndex == null && _hasSession && _queueing) {
      _queueDraft();
      return;
    }
    // The notice above says so while editing; it is asked once, as it is sent,
    // with what becomes of the files the agent changed after the message.
    int? planIndex;
    var revertFiles = false;
    if (_editIndex != null) {
      planIndex = _editAnchor?.locate(_buffer);
      var plan = RewindPlan.none;
      if (planIndex != null && !_buffer.loading) {
        setState(() {
          _sending = true;
          _error = null;
        });
        try {
          plan = await loadRewindPlan(
            widget.state,
            widget.desktopId,
            session: _sessionId,
            index: planIndex,
          );
        } catch (error) {
          if (mounted) {
            setState(() => _error = userMessage(widget.state, error));
          }
          return;
        } finally {
          if (mounted) setState(() => _sending = false);
        }
        if (!mounted) return;
      }
      final answer = await askResend(
        context,
        widget.state,
        live: _buffer.live,
        plan: plan,
      );
      if (answer == null) return;
      revertFiles = answer;
    }
    if (!mounted || _sending) return;
    final editIndex = _editAnchor?.locate(_buffer);
    // What was asked of the files is for the message as it was then.
    final moved = revertFiles && editIndex != planIndex;
    if (_editIndex != null && (editIndex == null || moved || _buffer.loading)) {
      setState(
        () => _error = editIndex == null || moved
            ? tr(
                '编辑的消息已变化，请取消后重新选择。',
                'The message changed. Cancel and select it again.',
              )
            : tr(
                '正在同步对话，请稍后再发送。',
                'Syncing the conversation. Send again in a moment.',
              ),
      );
      return;
    }
    final submitted = _input;
    final operationGeneration = _binding.generation;
    final text = _composer.text;
    final images = [for (final image in _images) image.wire];
    final mentions = _mentions
        .where((path) => text.contains('@$path'))
        .toList();
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      if (editIndex != null) {
        await widget.state.request(widget.desktopId, LinkMethods.edit, {
          'session': _sessionId,
          'index': editIndex,
          'text': text,
          'images': images,
          'mentions': mentions,
          if (revertFiles) 'revertFiles': true,
        });
        if (!mounted) return;
        if (_binding.generation != operationGeneration) {
          throw StateError(
            tr(
              '编辑结果未确认，当前会话已变化',
              'Edit result unconfirmed; conversation changed',
            ),
          );
        }
      } else {
        final generation = operationGeneration;
        final actual = await widget.state.sendMessage(
          widget.desktopId,
          session: _hasSession ? _sessionId : null,
          project: widget.projectId,
          bot: widget.botId,
          text: text,
          images: images,
          mentions: mentions,
        );
        if (!mounted) return;
        if (actual == null || !_binding.acceptSent(actual, generation)) {
          throw StateError(tr('电脑返回的会话未确认', 'Conversation not confirmed'));
        }
      }
      if (!mounted) return;
      // Preserve a newer draft typed while the request was in flight.
      final wasEditing = _editIndex != null;
      final stillSentText = _composer.text == text;
      final remaining = _input.afterSending(submitted);
      _images
        ..clear()
        ..addAll(wasEditing ? _beforeEditImages : remaining.images);
      _mentions
        ..clear()
        ..addAll(wasEditing ? _beforeEditMentions : remaining.mentions);
      _imagesMissing = wasEditing
          ? _beforeEditImagesMissing
          : remaining.imagesMissing;
      if (stillSentText) {
        _composer.text = wasEditing ? (_beforeEdit ?? '') : remaining.text;
      }
      _editIndex = null;
      _editAnchor = null;
      _beforeEdit = null;
      _beforeEditImages.clear();
      _beforeEditMentions.clear();
      _saveDraft(_composer.text);
      _forceBottom();
    } catch (error) {
      if (mounted) {
        setState(
          () =>
              _error = error is LinkClosedException || error is TimeoutException
              ? tr(
                  '连接中断，不确定电脑是否收到。内容已保留，请看一下对话再决定是否重发。',
                  'The connection dropped; the desktop may not have received it. Content is kept; check the conversation before sending again.',
                )
              : tr(
                  '发送未确认；内容已保留，请先检查会话，避免重复发送。',
                  'Send was not confirmed. Content is kept; check the conversation before sending again.',
                ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  double? _viewport;

  Future<void> _edit(int index, UserMessageItem item) async {
    if (_sending || index < 0 || index >= _buffer.items.length) return;
    final anchor = MessageEditAnchor.capture(_buffer, index);
    if (!anchor.matches(_buffer)) {
      setState(
        () => _error = tr(
          '编辑的消息已变化，请取消后重新选择。',
          'The message changed. Cancel and select it again.',
        ),
      );
      return;
    }
    _draftTimer?.cancel();
    if (_editIndex == null) {
      _beforeEdit = _composer.text;
      _beforeEditImagesMissing = _imagesMissing;
      _beforeEditImages
        ..clear()
        ..addAll(_images);
      _beforeEditMentions
        ..clear()
        ..addAll(_mentions);
      _saveDraft(_composer.text);
    }
    if (index >= _buffer.items.length) return;
    setState(() {
      _editIndex = index;
      _editAnchor = anchor;
      _imagesMissing = false;
      _images.clear();
      _mentions.clear();
      for (final image in item.images) {
        _images.add(
          DraftImage(image.name ?? 'image', image.mediaType, image.bytes),
        );
      }
      _composer.text = messageBody(item.text, item.images);
    });
  }

  void _cancelEdit() {
    setState(() {
      // Set controller while still in editing mode so it cannot overwrite the saved draft.
      _composer.text = _beforeEdit ?? '';
      _images
        ..clear()
        ..addAll(_beforeEditImages);
      _mentions
        ..clear()
        ..addAll(_beforeEditMentions);
      _imagesMissing = _beforeEditImagesMissing;
      _editIndex = null;
      _editAnchor = null;
      _beforeEdit = null;
      _beforeEditImages.clear();
      _beforeEditMentions.clear();
    });
    _saveDraft(_composer.text);
  }

  bool _pasting = false;

  @override
  Widget build(BuildContext context) => PopScope(
    // The back gesture closes the add panel before it leaves the page.
    canPop: !_addOpen && widget.onBack == null,
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) return;
      if (_addOpen) {
        _closeAdd();
      } else {
        widget.onBack?.call();
      }
    },
    child: AnimatedBuilder(
      animation: widget.state,
      builder: (context, _) {
        final buffer = _buffer;
        if (_lastRevision != buffer.revision) {
          if (_follow && !buffer.loadingEarlier) _bottom();
          _lastRevision = buffer.revision;
        }
        final ready = _online && !_sending && !_picking;
        final error =
            _error ??
            (_binding.error == buffer.error ? null : _binding.error) ??
            (buffer.items.isEmpty ? buffer.error : null);
        // Display rows: consecutive quiet info tools collapse into one
        // aggregated line, the way the original app renders a stream.
        if (!_follow) _holdRunningTurn();
        // 哪条计划电脑真在等：按钮和计划卡片都看这一处。
        // 点了立即插入、电脑还没接上的消息：电脑那边排着，对话里先替它占一条。
        final items = [
          ...buffer.items,
          if (_hasSession)
            for (final message in widget.state.localQueue.inserting(
              widget.desktopId,
              _sessionId,
            ))
              ChatCodec.encode(
                UserMessageItem(
                  text: message.text,
                  queued: true,
                  images: [
                    for (final image in message.images)
                      ImageAttachment(
                        bytes: image.bytes,
                        mediaType: image.type,
                        name: image.name,
                      ),
                  ],
                ),
              ),
        ];
        final plans = pendingPlans(items, lost: _lostPlans);
        final rows = widget.botId != null
            ? botRows(items)
            : foldRows(
                    plans.items,
                    live: buffer.live == true,
                    keepOpenFrom: _keepOpenFrom,
                    isOpen: (fold) => _foldsOpen[fold.key] ?? false,
                  )
                  .where((row) => _online || row.shown is! LiveStatusItem)
                  .toList();
        _rows = rows;
        final bot = widget.state.bots
            .where(
              (ref) =>
                  ref.desktopId == widget.desktopId &&
                  ref.bot.id == widget.botId,
            )
            .firstOrNull;
        return Scaffold(
          appBar: _appBar(context, buffer, bot),
          // What was running is only last known once disconnected: nothing
          // animates as if it were still at work.
          body: TickerMode(
            enabled: _online,
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  if (buffer.items.isNotEmpty)
                    SessionSyncNotice(
                      key: ValueKey(('sync', widget.desktopId, _sessionId)),
                      state: widget.state,
                      online: _online,
                      loading: buffer.loading,
                      error: buffer.error,
                      onRetry: _open,
                      onLayoutChange: _preserveReadingPosition,
                    ),
                  // 和「内容未更新」一样一行小字，不再整块横幅挡住对话。
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 2, 8, 0),
                      child: ComposerNotice(
                        icon: 'triangle-alert',
                        title: error,
                        tone: Theme.of(context).colorScheme.error,
                        actionLabel:
                            buffer.error != null || _binding.error != null
                            ? tr('重新加载', 'Reload')
                            : tr('关闭', 'Dismiss'),
                        onAction: () {
                          setState(() => _error = null);
                          if (buffer.error != null || _binding.error != null) {
                            _open();
                          }
                        },
                      ),
                    ),
                  if (widget.projectUnavailable)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        tr(
                          '项目上下文暂不可用；可以读取会话，依赖项目的文件入口不提供。',
                          'Project context is unavailable. Conversation reads remain available; project-dependent file actions are hidden.',
                        ),
                      ),
                    ),
                  if (buffer.goal case final goal?) _goalTile(context, goal),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () {
                        _composerFocus.unfocus();
                        _closeAdd();
                      },
                      child: _historyArea(context, buffer, rows, bot, ready),
                    ),
                  ),
                  if (buffer.interaction case final request?)
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * .46,
                      ),
                      child: SingleChildScrollView(
                        child: IgnorePointer(
                          ignoring: !_online,
                          child: InteractionPanel(
                            key: ValueKey((
                              widget.desktopId,
                              _sessionId,
                              request['id'],
                            )),
                            state: widget.state,
                            desktopId: widget.desktopId,
                            sessionId: _sessionId,
                            projectId: widget.projectId,
                            request: request,
                          ),
                        ),
                      ),
                    ),
                  if (plans.pending case final pending?)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: FilledButton.icon(
                        style: MobileSizes.wideButton,
                        onPressed: !_online || buffer.live || _commandBusy
                            ? null
                            : () => _startPlan(buffer.items[pending]),
                        icon: const Icon(Icons.play_arrow),
                        label: Text(tr('开始执行计划', 'Start plan')),
                      ),
                    ),
                  if (_imagesMissing)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 2, 8, 0),
                      child: ComposerNotice(
                        icon: 'image',
                        title: tr('草稿里的图片没恢复', 'Draft images were lost'),
                        detail: tr('请重新添加', 'reattach them'),
                        tone: MobileTheme.statusColorsOf(context).warning,
                        actionLabel: tr('忽略', 'Dismiss'),
                        onAction: _sending
                            ? null
                            : () {
                                _imagesMissing = false;
                                _draftChanged();
                              },
                      ),
                    ),
                  _composerView(buffer, ready),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );

  PreferredSizeWidget _appBar(
    BuildContext context,
    SessionBuffer buffer,
    BotRef? bot,
  ) => AppBar(
    // A hairline under the bar, as messengers draw it.
    shape: Border(
      bottom: BorderSide(
        color: Theme.of(context).colorScheme.outlineVariant,
        width: .5,
      ),
    ),
    toolbarHeight:
        (MediaQuery.textScalerOf(context).scale(16) * 1.2 +
                MediaQuery.textScalerOf(context).scale(13) * 1.4 +
                12)
            .clamp(56, double.infinity)
            .toDouble(),
    centerTitle: widget.botId != null,
    titleSpacing: 4,
    leading:
        widget.leading ??
        (widget.botId == null
            ? null
            : IconButton(
                tooltip: tr('返回', 'Back'),
                onPressed: () => Navigator.maybePop(context),
                icon: const Icon(Icons.arrow_back_ios_new, size: 20),
              )),
    title: SessionSyncGate(
      online: _online,
      loading: buffer.loading,
      builder: (context, syncing) => widget.botId != null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  bot?.bot.status == BotStatus.typing
                      ? tr('对方正在输入…', 'Typing…')
                      : bot?.bot.name ?? widget.title,
                ),
                // 同步时不多出一行：标题一上一下就是在闪。
                if (_status != DesktopLinkStatus.online)
                  _connectionLine(context, syncing: syncing, center: true),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                _connectionLine(
                  context,
                  syncing: syncing,
                  // 空对话的项目卡片已经写着分支。
                  branch: buffer.items.isEmpty
                      ? null
                      : _project?.project.branch,
                ),
              ],
            ),
    ),
    actions: [
      if (bot == null && widget.onNewConversation != null)
        IconButton(
          key: const ValueKey('chat-new-conversation'),
          tooltip: tr('新对话', 'New conversation'),
          icon: const LucideIcon('square-pen', size: 22),
          onPressed: _online ? widget.onNewConversation : null,
        ),
      if (bot != null)
        IconButton(
          tooltip: tr('资料', 'Profile'),
          icon: const Icon(Icons.more_horiz),
          onPressed: () => openPage<void>(
            context,
            BotProfilePage(state: widget.state, ref: bot, fromChat: true),
          ),
        )
      else
        PopupMenuButton<String>(
          tooltip: tr('更多', 'More'),
          icon: Badge(
            isLabelVisible: buffer.tasks.any(
              (task) => task.status == 'running',
            ),
            child: const Icon(Icons.more_horiz),
          ),
          position: PopupMenuPosition.under,
          constraints: const BoxConstraints(minWidth: 200),
          onSelected: (action) => runUi(context, () => _sessionMenu(action)),
          itemBuilder: (context) {
            PopupMenuEntry<String> entry(
              String value,
              String label,
              String icon, {
              bool enabled = true,
            }) => PopupMenuItem(
              value: value,
              enabled: enabled,
              height: 52,
              child: Row(
                children: [
                  LucideIcon(icon, size: 22),
                  const SizedBox(width: MobileSpace.md),
                  Expanded(child: Text(label)),
                ],
              ),
            );
            return [
              if (_project != null)
                entry(
                  'new',
                  tr('新对话', 'New conversation'),
                  'square-pen',
                  enabled: _online,
                ),
              if (widget.projectId != null)
                entry('files', tr('浏览文件', 'Browse files'), 'folder'),
              entry('changes', tr('全部改动', 'All changes'), 'file-diff'),
              entry('tasks', tr('后台任务', 'Background tasks'), 'list-todo'),
              entry(
                'pin',
                _pinned ? tr('取消置顶', 'Unpin') : tr('置顶', 'Pin'),
                'pin',
              ),
              entry('rename', tr('重命名', 'Rename'), 'pencil'),
              entry('archive', tr('归档', 'Archive'), 'archive'),
              if (_hasSession && widget.botId == null)
                entry('delete', tr('删除对话', 'Delete conversation'), 'trash-2'),
            ];
          },
        ),
    ],
  );

  Widget _goalTile(BuildContext context, Map<String, Object?> goal) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: FoldRow(
      leading: const LucideIcon('flag', size: 18),
      title: Text(
        '${goal['condition'] ?? ''}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(goalStateLabel(widget.state, '${goal['state'] ?? ''}')),
      trailing: IconButton(
        tooltip: tr('目标详情', 'Goal details'),
        visualDensity: VisualDensity.compact,
        icon: const LucideIcon('square-arrow-out-up-right', size: 18),
        onPressed: () => openGoalPage(
          context,
          state: widget.state,
          desktopId: widget.desktopId,
          sessionId: _sessionId,
          goal: goal,
        ),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${goal['reason'] ?? ''}'),
              const SizedBox(height: MobileSpace.xs),
              Text(
                '${tr('检查次数', 'Checks')}: ${goal['checks'] ?? 0}  ·  ${goal['tokens'] ?? 0} tokens',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    ),
  );

  DesktopLinkStatus get _status => widget.state.linkStatus(widget.desktopId);

  /// Under the title: where the conversation is, and how the desktop is
  /// connected, in words as soon as it is not.
  Widget _connectionLine(
    BuildContext context, {
    bool center = false,
    bool syncing = false,
    String? branch,
  }) {
    final status = _status;
    final isSyncing = syncing && status == DesktopLinkStatus.online;
    final scheme = Theme.of(context).colorScheme;
    // 圆点：在线绿、离线灰、要重新配对红；连接中和同步中都是主题色的转圈，
    // 两件事都是「正在忙」，不各用一色。
    final Widget mark = switch (status) {
      DesktopLinkStatus.connecting => ConnectingSpinner(
        size: 10,
        color: scheme.primary,
      ),
      DesktopLinkStatus.online when isSyncing => ConnectingSpinner(
        size: 10,
        color: scheme.primary,
      ),
      DesktopLinkStatus.online => Icon(
        Icons.circle,
        size: 7,
        color: MobileTheme.statusColorsOf(context).success,
      ),
      DesktopLinkStatus.needsPairing => Icon(
        Icons.circle,
        size: 7,
        color: scheme.error,
      ),
      DesktopLinkStatus.offline => Icon(
        Icons.circle,
        size: 7,
        color: scheme.onSurfaceVariant,
      ),
    };
    final text = switch (status) {
      DesktopLinkStatus.online when isSyncing => tr('同步中…', 'Syncing…'),
      DesktopLinkStatus.online =>
        _project?.project.name ?? linkStatusLabel(widget.state, status),
      _ => linkStatusLabel(widget.state, status),
    };
    return Semantics(
      label: switch (status) {
        DesktopLinkStatus.online when isSyncing => tr(
          '正在同步最新消息',
          'Syncing latest messages',
        ),
        DesktopLinkStatus.online => tr('已连接电脑', 'Desktop connected'),
        DesktopLinkStatus.connecting => tr('正在连接电脑', 'Connecting to desktop'),
        _ => tr('电脑离线', 'Desktop offline'),
      },
      child: Row(
        mainAxisSize: center ? MainAxisSize.min : MainAxisSize.max,
        children: [
          mark,
          const SizedBox(width: 5),
          Flexible(
            // 同一段文字：放不下时只省略排在后面的分支名。
            child: Text.rich(
              TextSpan(
                text: text,
                children: [
                  if (status == DesktopLinkStatus.online &&
                      !isSyncing &&
                      branch != null &&
                      branch.isNotEmpty) ...[
                    const TextSpan(text: '  '),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: LucideIcon(
                        'git-branch',
                        key: const ValueKey('chat-branch-icon'),
                        size: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    TextSpan(text: ' $branch'),
                  ],
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // 只有真要处理的那种（需重新配对）用红字；离线是灰的，
              // 和左边的灰点一致。
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: status == DesktopLinkStatus.needsPairing
                    ? scheme.error
                    : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 这一轮开始的时刻：实时状态带着它，否则看最后一条用户消息。
  DateTime? _turnStart(SessionBuffer buffer) {
    final items = buffer.items;
    final recent = items.sublist(math.max(0, items.length - 8));
    for (final item in decodeItems(recent).reversed) {
      switch (item) {
        case LiveStatusItem(:final startedAt?):
          return startedAt.toLocal();
        case UserMessageItem(:final sentAt?):
          return sentAt.toLocal();
        default:
      }
    }
    return null;
  }

  /// The last keyboard height seen with the composer focused; the add panel
  /// takes its place.
  double? _seenKeyboard;

  /// The room the closed panel keeps while the keyboard rises in its place.
  double _reserve = 0;
  Timer? _reserveTimer;

  Future<void> _openRunningAgent(RunningAgent selected) async {
    if (!mounted) return;
    final agent = selected.item;
    // A subagent shows its own run (its steps, live), as on the desktop; a
    // command, or a subagent whose card is not in the history held, its task.
    if (agent == null) {
      final task = selected.task;
      if (task == null) return;
      await openPage<void>(
        context,
        TaskPage(
          state: widget.state,
          desktopId: widget.desktopId,
          sessionId: _sessionId,
          task: task,
        ),
      );
      return;
    }
    openSubagentPage(
      context,
      state: widget.state,
      desktopId: widget.desktopId,
      projectId: widget.projectId,
      sessionId: _sessionId,
      item: agent,
    );
  }
}
