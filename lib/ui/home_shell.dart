import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../state/update_check.dart';
import 'bots/bots_tab.dart';
import 'conversations/chats_tab.dart';
import 'files/files_tab.dart';
import 'focus/focus_shell.dart';
import 'settings/settings_page.dart';
import 'widgets/lucide_icon.dart';
import '../theme/app_theme.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.state, this.updateChecker});
  final AppState state;

  /// 打开应用时的自动检查；测试里换成不联网的。
  final AutoUpdateChecker? updateChecker;
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  static const _settingsTab = 3;

  final _pages = PageController();
  int _tab = 0;
  late final _updates =
      widget.updateChecker ?? AutoUpdateChecker(currentVersion: appVersion);

  @override
  void initState() {
    super.initState();
    if (widget.state.demo) return;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdates());
  }

  /// 冷启动之外，从后台回到应用也算一次打开。
  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.resumed) _checkForUpdates();
  }

  /// 有可下载的新版本才弹窗；没有或失败都不打扰。更新窗口已经开着时
  /// （比如去系统设置允许安装后回来）不再弹第二个。
  Future<void> _checkForUpdates() async {
    if (UpdateDialog.isOpen) return;
    final check = await _updates.check();
    if (check == null || !mounted || UpdateDialog.isOpen) return;
    await showDialog<void>(
      context: context,
      builder: (_) => UpdateDialog(state: widget.state, release: check.latest),
    );
  }

  void _select(int index) {
    widget.state.haptic();
    setState(() => _tab = index);
    if (index != _settingsTab) _pages.jumpToPage(index);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    if (state.settings.focusLayout) return FocusShell(state: state);
    final entries = [
      ('message-circle', state.tr('对话', 'Chats')),
      ('bot', 'Bot'),
      ('folder', state.tr('文件', 'Files')),
      ('settings', state.tr('设置', 'Settings')),
    ];
    // 只算当前这台电脑的，列表里也只有它的对话——别的电脑的在切换电脑那里标。
    final desktopId = state.selectedDesktopId;
    final unread =
        state.awaitingOn(desktopId).waiting +
        state.bots
            .where((ref) => ref.desktopId == desktopId)
            .fold(0, (sum, ref) => sum + ref.bot.unread);
    return Scaffold(
      body: Column(
        children: [
          if (state.demo)
            SafeArea(
              bottom: false,
              child: ColoredBox(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: SizedBox(
                  width: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: Text(
                      state.tr(
                        '演示模式 · 不会执行命令',
                        'Demo mode · no commands are executed',
                      ),
                      textAlign: TextAlign.center,
                      style: MobileTheme.metaStyleOf(
                        context,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (state.startupError != null)
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  state.startupError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          Expanded(
            child: IndexedStack(
              index: _tab == _settingsTab ? 1 : 0,
              children: [
                PageView(
                  controller: _pages,
                  allowImplicitScrolling: true,
                  onPageChanged: (index) => setState(() => _tab = index),
                  children: [
                    _KeptPage(child: ChatsTab(state: state)),
                    _KeptPage(child: BotsTab(state: state)),
                    _KeptPage(child: FilesTab(state: state)),
                  ],
                ),
                SettingsPage(state: state),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceBright,
          border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor, width: .5),
          ),
        ),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Row(
              children: [
                for (var index = 0; index < entries.length; index++)
                  Expanded(
                    child: Semantics(
                      selected: index == _tab,
                      button: true,
                      label: entries[index].$2,
                      child: InkResponse(
                        onTap: () => _select(index),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Badge(
                                key: ValueKey('tab-badge-$index'),
                                isLabelVisible: index == 0 && unread > 0,
                                label: Text('$unread'),
                                // bot 的图形矮，放大一点才和别的图标看着一样大；占位不变。
                                child: Transform.scale(
                                  scale: entries[index].$1 == 'bot'
                                      ? 26 / 24
                                      : 1,
                                  child: LucideIcon(
                                    entries[index].$1,
                                    size: 24,
                                    color: index == _tab
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(context).hintColor,
                                  ),
                                ),
                              ),
                              const SizedBox(height: MobileSpace.xs),
                              Text(
                                entries[index].$2,
                                style: MobileTheme.metaStyleOf(context)
                                    .copyWith(
                                      fontWeight: index == _tab
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                      color: index == _tab
                                          ? Theme.of(context)
                                                .colorScheme
                                                .primary
                                          : Theme.of(context).hintColor,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 滑走后保留页面状态，回来时滚动位置不变。
class _KeptPage extends StatefulWidget {
  const _KeptPage({required this.child});
  final Widget child;

  @override
  State<_KeptPage> createState() => _KeptPageState();
}

class _KeptPageState extends State<_KeptPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
