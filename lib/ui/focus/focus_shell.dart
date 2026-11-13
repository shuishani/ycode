import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../link/phone_link.dart' show DesktopLinkStatus;
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../bots/bots_tab.dart';
import '../conversations/chats_tab.dart';
import '../conversations/conversation_filters.dart';
import '../conversations/project_actions.dart';
import '../conversations/session_press_row.dart';
import '../devices/device_menu.dart';
import '../devices/devices_page.dart';
import '../files/files_tab.dart';
import '../settings/settings_page.dart';
import '../tasks/chat_page.dart';
import '../widgets/lucide_icon.dart';
import '../widgets/mobile_widgets.dart';
import '../widgets/project_icon_view.dart';

/// The conversation on screen: a listed one, or a draft in [draftIn].
class _Open {
  const _Open(
    this.desktopId,
    this.sessionId,
    this.title, {
    this.projectId,
    this.draftIn,
  });
  final String desktopId, sessionId, title;
  final String? projectId;
  final ProjectRef? draftIn;
}

/// 沉浸模式：打开就是对话，项目和对话收在左边的侧边栏里，Bot、文件和设置
/// 在侧边栏底部。点下去的页面和列表模式是同一套。
class FocusShell extends StatefulWidget {
  const FocusShell({super.key, required this.state});
  final AppState state;

  @override
  State<FocusShell> createState() => _FocusShellState();
}

class _FocusShellState extends State<FocusShell> {
  final _scaffold = GlobalKey<ScaffoldState>();
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _scrolled = ValueNotifier(false);

  /// Projects folded in the side panel; all start unfolded.
  final _folded = <(String, String)>{};

  _Open? _open;

  AppState get state => widget.state;

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    _scrolled.dispose();
    super.dispose();
  }

  /// Until one is picked: the one open last time if on the chosen desktop,
  /// else that desktop's latest, as soon as the list knows it.
  _Open? _initial() {
    final desktopId = state.selectedDesktopId;
    final listed = state.sessions.where((ref) => ref.desktopId == desktopId);
    final last = state.settings.lastSession;
    final ref =
        listed
            .where((ref) => (ref.desktopId, ref.session.id) == last)
            .firstOrNull ??
        (listed.toList()..sort(
              (a, b) => b.session.updatedAt.compareTo(a.session.updatedAt),
            ))
            .firstOrNull;
    return ref == null ? null : _toOpen(ref);
  }

  _Open _toOpen(SessionRef ref) => _Open(
    ref.desktopId,
    ref.session.id,
    ref.session.title,
    projectId: ref.session.project,
  );

  void _select(SessionRef ref) {
    setState(() => _open = _toOpen(ref));
    state.settings.lastSession = (ref.desktopId, ref.session.id);
    unawaited(state.saveSettings().catchError((Object _) {}));
    _scaffold.currentState?.closeDrawer();
  }

  Future<void> _newConversation(BuildContext context, [ProjectRef? project]) {
    project ??= recentProject(state, state.selectedDesktopId);
    if (project == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            state.tr(
              '先在电脑中打开项目并连接。',
              'Connect a desktop with an open project first.',
            ),
          ),
        ),
      );
      return Future.value();
    }
    final target = project;
    return runUi(context, () async {
      final id = await requestDraft(state, target);
      if (!mounted) return;
      setState(
        () => _open = _Open(
          target.desktopId,
          id,
          state.tr('新对话', 'New conversation'),
          projectId: target.project.id,
          draftIn: target,
        ),
      );
      _scaffold.currentState?.closeDrawer();
    });
  }

  void _left() {
    state.settings.lastSession = null;
    unawaited(state.saveSettings().catchError((Object _) {}));
    setState(() => _open = null);
  }

  /// 返回键先打开侧边栏，侧边栏开着时才退出应用。
  void _back() {
    final scaffold = _scaffold.currentState;
    if (scaffold == null) return;
    if (scaffold.isDrawerOpen) {
      unawaited(SystemNavigator.pop());
    } else {
      scaffold.openDrawer();
    }
  }

  bool _listed(_Open open) => state.sessions.any(
    (ref) =>
        ref.desktopId == open.desktopId && ref.session.id == open.sessionId,
  );

  @override
  Widget build(BuildContext context) {
    // 换了电脑，或开着的对话在侧边栏里被删除、归档了：换到这台电脑最近的
    // 一段。草稿不在列表里，不算被删。
    if (_open case final open?
        when open.desktopId != state.selectedDesktopId ||
            (open.draftIn == null &&
                state.isOnline(open.desktopId) &&
                !_listed(open))) {
      _open = null;
    }
    final open = _open ?? _initial();
    final leading = _SidePanelButton(
      state: state,
      onPressed: () => _scaffold.currentState?.openDrawer(),
    );
    // 对话页处理自己的返回再交给 _back；没有对话时由这里交给它。
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && open == null) _back();
      },
      child: Scaffold(
        key: _scaffold,
        resizeToAvoidBottomInset: false,
        drawerEdgeDragWidth: 32,
        drawer: _SidePanel(
          state: state,
          open: open,
          search: _search,
          scroll: _scroll,
          scrolled: _scrolled,
          folded: _folded,
          onSearch: () => setState(() {}),
          onToggle: (key, set) => setState(
            () => set.contains(key) ? set.remove(key) : set.add(key),
          ),
          onFoldAll: (keys) => setState(() {
            if (keys.every(_folded.contains)) {
              _folded.removeAll(keys);
            } else {
              _folded.addAll(keys);
            }
          }),
          onSelect: _select,
          onNew: _newConversation,
        ),
        body: open == null
            ? _NoConversation(
                state: state,
                leading: leading,
                onNew: () => _newConversation(context),
              )
            : ChatPage(
                key: ValueKey('focus-${open.desktopId}-${open.sessionId}'),
                state: state,
                desktopId: open.desktopId,
                sessionId: open.sessionId,
                title: open.title,
                projectId: open.projectId,
                leading: leading,
                onLeave: _left,
                onBack: _back,
                onNewConversation: () => _newConversation(
                  context,
                  open.draftIn ??
                      state.projects
                          .where(
                            (ref) =>
                                ref.desktopId == open.desktopId &&
                                ref.project.id == open.projectId,
                          )
                          .firstOrNull,
                ),
                onSwitchProject: switch (open.draftIn) {
                  null => null,
                  final current => (pageContext) async {
                    final next = await pickProject(
                      pageContext,
                      state,
                      current: current,
                    );
                    if (next == null ||
                        (next.desktopId == current.desktopId &&
                            next.project.id == current.project.id) ||
                        !pageContext.mounted) {
                      return;
                    }
                    await _newConversation(pageContext, next);
                  },
                },
              ),
      ),
    );
  }
}

/// 标题栏左边打开侧边栏的按钮；有等着你的对话或 Bot 新消息时带个小点。
class _SidePanelButton extends StatelessWidget {
  const _SidePanelButton({required this.state, required this.onPressed});
  final AppState state;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final desktopId = state.selectedDesktopId;
    final waiting =
        state.awaitingOn(desktopId).waiting +
        state.bots
            .where((ref) => ref.desktopId == desktopId)
            .fold(0, (sum, ref) => sum + ref.bot.unread);
    return IconButton(
      key: const ValueKey('open-side-panel'),
      tooltip: state.tr('打开侧边栏', 'Open side panel'),
      onPressed: onPressed,
      icon: Badge(
        isLabelVisible: waiting > 0,
        smallSize: 7,
        child: const LucideIcon('panel-left', size: 22),
      ),
    );
  }
}

/// 还没有对话可开：电脑没配对、没连上，或者电脑上还没有对话。
class _NoConversation extends StatelessWidget {
  const _NoConversation({
    required this.state,
    required this.leading,
    required this.onNew,
  });
  final AppState state;
  final Widget leading;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: leading,
        centerTitle: true,
        title: DesktopSwitcherTitle(state: state),
      ),
      body: state.desktops.isEmpty
          ? EmptyPanel(
              state.tr(
                '连接电脑，继续你的对话。',
                'Connect a desktop to continue your conversations.',
              ),
              actionLabel: state.tr('配对新电脑', 'Pair a desktop'),
              onAction: () =>
                  openPage<void>(context, PairDevicePage(state: state)),
            )
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(MobileSpace.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SvgPicture.asset(
                      'assets/icons/ycode.svg',
                      width: 48,
                      height: 48,
                    ),
                    const SizedBox(height: MobileSpace.lg),
                    Text(
                      state.tr(
                        '从侧边栏选一段对话，或者开始新对话。',
                        'Pick a conversation from the side panel, or start a new one.',
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.hintColor),
                    ),
                    const SizedBox(height: MobileSpace.lg),
                    FilledButton.tonalIcon(
                      onPressed: onNew,
                      icon: const LucideIcon('square-pen', size: 18),
                      label: Text(state.tr('新对话', 'New conversation')),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _SidePanel extends StatelessWidget {
  const _SidePanel({
    required this.state,
    required this.open,
    required this.search,
    required this.scroll,
    required this.scrolled,
    required this.folded,
    required this.onSearch,
    required this.onToggle,
    required this.onFoldAll,
    required this.onSelect,
    required this.onNew,
  });
  final AppState state;
  final _Open? open;
  final TextEditingController search;
  final ScrollController scroll;

  /// Whether the list runs under the title, for the line beneath it.
  final ValueNotifier<bool> scrolled;
  final Set<(String, String)> folded;
  final VoidCallback onSearch;
  final void Function((String, String) key, Set<(String, String)> set) onToggle;
  final ValueChanged<List<(String, String)>> onFoldAll;
  final ValueChanged<SessionRef> onSelect;
  final Future<void> Function(BuildContext context, [ProjectRef? project])
  onNew;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: state,
    builder: (context, _) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      final desktopId = state.selectedDesktopId;
      final filters = ConversationFilters(query: search.text);
      final projects = filters.projects(
        state.projects.where((ref) => ref.desktopId == desktopId),
        state.sessions,
        state.desktopName,
      );
      final keys = [
        for (final item in projects)
          if (item.sessions.isNotEmpty)
            (item.ref.desktopId, item.ref.project.id),
      ];
      final botUnread = state.bots
          .where((ref) => ref.desktopId == desktopId)
          .fold(0, (sum, ref) => sum + ref.bot.unread);
      final width = math.min(MediaQuery.sizeOf(context).width * .86, 340.0);
      return Drawer(
        width: width,
        backgroundColor: scheme.surfaceContainerLow,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(right: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 列表滚到标题下面时，标题底下多一条细线，分出层次。
              ValueListenableBuilder<bool>(
                valueListenable: scrolled,
                builder: (context, under, child) => DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: under
                            ? scheme.outlineVariant
                            : Colors.transparent,
                        width: .5,
                      ),
                    ),
                  ),
                  child: child,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    MobileSpace.lg,
                    MobileSpace.md,
                    MobileSpace.sm,
                    MobileSpace.sm,
                  ),
                  child: Row(
                    children: [
                      SvgPicture.asset(
                        'assets/icons/ycode.svg',
                        width: 26,
                        height: 26,
                      ),
                      const SizedBox(width: MobileSpace.sm),
                      const Text(
                        'YCode',
                        style: TextStyle(
                          fontSize: MobileType.headline,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // 入口、搜索和项目一起滚：往上一滑，整屏都是项目和对话。
              Expanded(
                child: NotificationListener<Notification>(
                  onNotification: (note) {
                    final metrics = switch (note) {
                      ScrollNotification(:final metrics, depth: 0) => metrics,
                      ScrollMetricsNotification(:final metrics, depth: 0) =>
                        metrics,
                      _ => null,
                    };
                    if (metrics != null) {
                      scrolled.value = metrics.pixels > metrics.minScrollExtent;
                    }
                    return false;
                  },
                  child: CustomScrollView(
                    key: const PageStorageKey('side-panel-list'),
                    controller: scroll,
                    slivers: [
                      SliverToBoxAdapter(
                        child: _inset(
                          Column(
                            children: [
                              _Entry(
                                key: const ValueKey('side-panel-new'),
                                icon: 'square-pen',
                                label: state.tr('新对话', 'New conversation'),
                                onTap: () => onNew(context),
                              ),
                              _Entry(
                                key: const ValueKey('side-bots'),
                                icon: 'bot',
                                label: 'Bot',
                                count: botUnread,
                                onTap: () => openPage<void>(
                                  context,
                                  AnimatedBuilder(
                                    animation: state,
                                    builder: (_, _) => BotsTab(state: state),
                                  ),
                                ),
                              ),
                              _Entry(
                                key: const ValueKey('side-files'),
                                icon: 'folder',
                                label: state.tr('文件', 'Files'),
                                onTap: () => openPage<void>(
                                  context,
                                  AnimatedBuilder(
                                    animation: state,
                                    builder: (_, _) => FilesTab(state: state),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Divider(
                          height: MobileSpace.lg,
                          indent: MobileSpace.lg,
                          endIndent: MobileSpace.lg,
                          color: scheme.outlineVariant,
                        ),
                      ),
                      // 搜索框和全部折叠同一行，不再单占一行「项目」标题。
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.only(
                            left: MobileSpace.xs,
                            right: MobileSpace.xs,
                            bottom: MobileSpace.xs,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: SearchCapsule(
                                  state: state,
                                  controller: search,
                                  hint: state.tr(
                                    '搜索项目和对话',
                                    'Search projects and chats',
                                  ),
                                  onChanged: (_) => onSearch(),
                                ),
                              ),
                              if (keys.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: IconButton(
                                    key: const ValueKey('side-fold-all'),
                                    tooltip: keys.every(folded.contains)
                                        ? state.tr('全部展开', 'Unfold all')
                                        : state.tr('全部折叠', 'Fold all'),
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => onFoldAll(keys),
                                    icon: LucideIcon(
                                      'chevrons-up-down',
                                      size: 18,
                                      color: theme.hintColor,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (projects.isEmpty)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(MobileSpace.xl),
                            child: Text(
                              filters.searching
                                  ? state.tr(
                                      '没有匹配的项目或对话',
                                      'No matching projects or conversations',
                                    )
                                  : state.tr(
                                      '电脑上还没有打开的项目',
                                      'No projects open on this desktop',
                                    ),
                              textAlign: TextAlign.center,
                              style: TextStyle(color: theme.hintColor),
                            ),
                          ),
                        ),
                      // 每个项目一组：标题吸在顶上，直到下一个项目把它顶走。
                      for (final item in projects)
                        _group(context, item, searching: filters.searching),
                      const SliverToBoxAdapter(
                        child: SizedBox(height: MobileSpace.md),
                      ),
                    ],
                  ),
                ),
              ),
              _Footer(state: state),
            ],
          ),
        ),
      );
    },
  );

  static Widget _inset(Widget child) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: MobileSpace.sm),
    child: child,
  );

  Widget _group(
    BuildContext context,
    ConversationProject item, {
    required bool searching,
  }) {
    final ref = item.ref;
    final key = (ref.desktopId, ref.project.id);
    // 搜索时都摊开，搜到的对话不藏在折叠里。
    final isFolded = !searching && folded.contains(key);
    return SliverMainAxisGroup(
      key: ValueKey('side-group-${ref.desktopId}-${ref.project.id}'),
      slivers: [
        PinnedHeaderSliver(
          child: ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: _inset(
              _ProjectHeader(
                state: state,
                project: ref,
                sessions: item.sessions,
                folded: isFolded,
                onToggle: item.sessions.isEmpty
                    ? null
                    : () => onToggle(key, folded),
                onNew: () => onNew(context, ref),
              ),
            ),
          ),
        ),
        SliverList.list(
          children: [
            if (!isFolded)
              for (final session in item.sessions)
                _inset(
                  _SessionLine(
                    state: state,
                    session: session,
                    selected:
                        open?.desktopId == session.desktopId &&
                        open?.sessionId == session.session.id,
                    onTap: () => onSelect(session),
                  ),
                ),
            const SizedBox(height: MobileSpace.xs),
          ],
        ),
      ],
    );
  }
}

/// 项目分组的标题：小图标、名字、等你的条数，右边是新对话和折叠。
class _ProjectHeader extends StatelessWidget {
  const _ProjectHeader({
    required this.state,
    required this.project,
    required this.sessions,
    required this.folded,
    required this.onToggle,
    required this.onNew,
  });
  final AppState state;
  final ProjectRef project;
  final List<SessionRef> sessions;
  final bool folded;
  final VoidCallback? onToggle;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final hint = Theme.of(context).hintColor;
    // 展开时每段对话自己有点；折叠了才在项目上合成一个。
    final dot = folded ? _statusColor(context, state, sessions) : null;
    return ProjectActionRow(
      key: ValueKey('side-project-${project.desktopId}-${project.project.id}'),
      state: state,
      project: project,
      child: InkWell(
        borderRadius: BorderRadius.circular(MobileSizes.radius),
        onTap: onToggle ?? onNew,
        child: SizedBox(
          height: 40,
          child: Row(
            children: [
              const SizedBox(width: MobileSpace.sm),
              ProjectIconView(
                state: state,
                ref: project,
                size: 20,
                showBadge: false,
              ),
              const SizedBox(width: 10),
              // 名字和角标占满中间，右边两个按钮贴着行尾，和对话的时间对齐。
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        project.project.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: MobileType.secondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (project.project.pinned == true) ...[
                      const SizedBox(width: 6),
                      LucideIcon('pin', size: 13, color: hint),
                    ],
                    if (dot != null) ...[
                      const SizedBox(width: 8),
                      _StatusDot(dot),
                    ],
                  ],
                ),
              ),
              SizedBox.square(
                dimension: 32,
                child: IconButton(
                  key: ValueKey(
                    'side-new-${project.desktopId}-${project.project.id}',
                  ),
                  tooltip: state.tr('在此项目新对话', 'New conversation here'),
                  padding: EdgeInsets.zero,
                  onPressed: onNew,
                  icon: LucideIcon('plus', size: 18, color: hint),
                ),
              ),
              SizedBox.square(
                dimension: 32,
                child: onToggle == null
                    ? null
                    : AnimatedRotation(
                        turns: folded ? -.25 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: Center(
                          child: LucideIcon(
                            'chevron-down',
                            size: 16,
                            color: hint,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: MobileSpace.xs),
            ],
          ),
        ),
      ),
    );
  }
}

/// 侧边栏里的一段对话：一行标题，前面一个状态点，后面是时间。
class _SessionLine extends StatelessWidget {
  const _SessionLine({
    required this.state,
    required this.session,
    required this.selected,
    required this.onTap,
  });
  final AppState state;
  final SessionRef session;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ref = session;
    final dot = _statusColor(context, state, [ref]);
    return SessionPressRow(
      key: ValueKey('side-session-${ref.desktopId}-${ref.session.id}'),
      state: state,
      session: ref,
      showHome: false,
      child: Material(
        color: selected ? scheme.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(MobileSizes.radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(MobileSizes.radius),
          onTap: onTap,
          child: SizedBox(
            height: 38,
            child: Row(
              children: [
                SizedBox(
                  width: 38,
                  child: dot == null ? null : Center(child: _StatusDot(dot)),
                ),
                Expanded(
                  child: Text(
                    ref.session.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: MobileType.secondary,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: selected
                          ? scheme.onSecondaryContainer
                          : scheme.onSurface,
                    ),
                  ),
                ),
                if (ref.session.pinned) ...[
                  const SizedBox(width: 6),
                  LucideIcon('pin', size: 12, color: theme.hintColor),
                ],
                const SizedBox(width: MobileSpace.sm),
                Text(
                  sessionTime(state, ref.session.updatedAt),
                  style: MobileTheme.metaStyleOf(context),
                ),
                const SizedBox(width: MobileSpace.md),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 状态点颜色：等你回复红、运行中蓝、已完成绿；电脑离线时状态已过时，不标。
Color? _statusColor(
  BuildContext context,
  AppState state,
  Iterable<SessionRef> sessions,
) {
  final counts = state.countByStatus(
    sessions.where((ref) => state.isOnline(ref.desktopId)),
  );
  final status = MobileTheme.statusColorsOf(context);
  return counts.needsInput > 0
      ? Theme.of(context).colorScheme.error
      : counts.running > 0
      ? status.info
      : counts.done > 0
      ? status.success
      : null;
}

class _StatusDot extends StatelessWidget {
  const _StatusDot(this.color);
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 7,
    height: 7,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// 侧边栏顶部的一行入口：图标、名字，有新消息时右边一个数。
class _Entry extends StatelessWidget {
  const _Entry({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.count = 0,
  });
  final String icon, label;
  final VoidCallback onTap;
  final int count;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(MobileSizes.radius),
    onTap: onTap,
    child: SizedBox(
      height: 44,
      child: Row(
        children: [
          const SizedBox(width: MobileSpace.sm),
          // bot 的图形矮，放大一点才和别的图标看着一样大；占位不变。
          Transform.scale(
            scale: icon == 'bot' ? 24 / 22 : 1,
            child: LucideIcon(icon, size: 22),
          ),
          const SizedBox(width: MobileSpace.md),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: MobileType.body),
            ),
          ),
          if (count > 0) Badge(label: Text('$count')),
          const SizedBox(width: MobileSpace.md),
        ],
      ),
    ),
  );
}

/// 底部：当前电脑和连接状态，点开切换；右边是设置。
class _Footer extends StatelessWidget {
  const _Footer({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final desktopId = state.selectedDesktopId;
    final desktop = state.desktops
        .where((desktop) => desktop.id == desktopId)
        .firstOrNull;
    final status = desktopId == null ? null : state.linkStatus(desktopId);
    Widget page(Widget Function() build) =>
        AnimatedBuilder(animation: state, builder: (_, _) => build());
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant, width: .5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          MobileSpace.sm,
          MobileSpace.sm,
          MobileSpace.xs,
          MobileSpace.xs,
        ),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                key: const ValueKey('side-desktop'),
                borderRadius: BorderRadius.circular(MobileSizes.radius),
                onTap: () async {
                  final chosen = await showDeviceMenu(
                    context,
                    state,
                    selectedId: desktopId,
                  );
                  if (chosen == null || chosen == desktopId) return;
                  state.selectDesktop(chosen);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: MobileSpace.sm,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      DeviceIcon(status: status, laptop: desktop?.laptop),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              desktop?.name ??
                                  state.tr('选择电脑', 'Choose desktop'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: MobileType.secondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (desktopId != null && status != null)
                              Text(
                                linkStatusLabel(state, status),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: MobileTheme.metaStyleOf(
                                  context,
                                  color:
                                      status == DesktopLinkStatus.needsPairing
                                      ? theme.colorScheme.error
                                      : null,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: MobileSpace.xs),
                      LucideIcon(
                        'chevrons-up-down',
                        size: 14,
                        color: theme.hintColor,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('side-settings'),
              tooltip: state.tr('设置', 'Settings'),
              onPressed: () => openPage<void>(
                context,
                page(() => SettingsPage(state: state)),
              ),
              icon: const LucideIcon('settings', size: 22),
            ),
          ],
        ),
      ),
    );
  }
}
