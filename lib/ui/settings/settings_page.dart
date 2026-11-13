import 'dart:convert';

import 'package:bao_link/bao_link.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/services.dart';

import '../../chat/chat_links.dart' show confirmExternalLink;
import '../../chat/message_view.dart' show CodePanel;
import '../../state/app_state.dart';
import '../../state/update_check.dart';
import '../../theme/app_theme.dart';
import '../devices/device_menu.dart';
import '../devices/devices_page.dart';
import '../widgets/dropdown_panel.dart';
import '../widgets/lucide_icon.dart';
import '../widgets/mobile_widgets.dart';
import '../widgets/scale_slider.dart';
import '../user_message.dart';
import 'changelog_page.dart';
import 'update_dialog.dart';

export 'update_dialog.dart' show UpdateDialog;

/// 这一版的版本名，如 `0.2.0`：打包时带进来（`tool/build_android.sh`）；
/// 不经打包脚本的构建（调试、测试）是 `dev`。
const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: 'dev');

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.state});
  final AppState state;
  @override
  Widget build(BuildContext context) {
    final online = state.desktops
        .where((desktop) => state.isOnline(desktop.id))
        .length;
    return Scaffold(
      appBar: AppBar(title: Text(state.tr('设置', 'Settings'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
        children: [
          GroupCard(
            children: [
              ListTile(
                minTileHeight: 76,
                minVerticalPadding: 12,
                leading: LetterAvatar(
                  state.settings.name.isEmpty
                      ? state.tr('我', 'Me')
                      : state.settings.name,
                  size: 52,
                  image: state.settings.avatar,
                ),
                title: Text(
                  state.settings.name.isEmpty
                      ? state.tr('我的资料', 'My profile')
                      : state.settings.name,
                ),
                subtitle: state.settings.name.isEmpty
                    ? null
                    : Text(state.tr('我的资料', 'My profile')),
                trailing: LucideIcon(
                  'chevron-right',
                  size: 18,
                  color: Theme.of(context).hintColor,
                ),
                onTap: () =>
                    openPage<void>(context, MyProfilePage(state: state)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          GroupCard(
            children: [
              SettingsRow(
                state.tr('已配对的电脑', 'Paired desktops'),
                icon: 'laptop',
                value: state.tr(
                  '$online/${state.desktops.length} 在线',
                  '$online/${state.desktops.length} online',
                ),
                onTap: () => openPage<void>(context, DevicesPage(state: state)),
              ),
              SettingsRow(
                state.tr('配对新电脑', 'Pair a desktop'),
                icon: 'qr-code',
                onTap: () =>
                    openPage<void>(context, PairDevicePage(state: state)),
              ),
              SettingsRow(
                state.tr('技能', 'Skills'),
                icon: 'plug',
                onTap: () =>
                    openPage<void>(context, ExtensionsPage(state: state)),
              ),
              SettingsRow(
                state.tr('安全', 'Security'),
                icon: 'lock',
                value: state.tr('端到端加密', 'End-to-end encrypted'),
                onTap: () =>
                    openPage<void>(context, SecurityPage(state: state)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          GroupCard(
            children: [
              SettingsRow(
                state.tr('主题', 'Theme'),
                icon: 'palette',
                value:
                    '${switch (state.settings.themeMode) {
                      ThemeMode.system => state.tr('跟随系统', 'System'),
                      ThemeMode.light => state.tr('浅色', 'Light'),
                      ThemeMode.dark => state.tr('深色', 'Dark'),
                    }} · ${() {
                      final accent = MobileAccent.parse(state.settings.accent);
                      return state.tr(accent.zh, accent.en);
                    }()}',
                onTap: () => openPage<void>(context, ThemePage(state: state)),
              ),
              Builder(
                builder: (anchor) => SettingsRow(
                  state.tr('界面模式', 'Layout'),
                  key: const ValueKey('settings-layout'),
                  icon: 'panel-left',
                  value: _layoutLabel(state.settings.layout),
                  onTap: () => _layout(anchor),
                ),
              ),
              Builder(
                builder: (anchor) => SettingsRow(
                  state.tr('语言', 'Language'),
                  icon: 'languages',
                  value: switch (state.settings.language) {
                    'zh' => '简体中文',
                    'en' => 'English',
                    _ => state.tr('跟随系统', 'System'),
                  },
                  onTap: () => _language(anchor),
                ),
              ),
              SettingsRow(
                state.tr('字号', 'Text size'),
                icon: 'a-large-small',
                value:
                    '${(state.settings.textScale * 100).round()}% · ${state.settings.codeFontSize.round()}',
                onTap: () =>
                    openPage<void>(context, TextSizePage(state: state)),
              ),
              SettingsRow(
                state.tr('通知', 'Notifications'),
                icon: 'bell',
                onTap: () =>
                    openPage<void>(context, NotificationsPage(state: state)),
              ),
              SwitchListTile(
                secondary: LucideIcon(
                  'vibrate',
                  size: 22,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                title: Text(state.tr('触感反馈', 'Haptic feedback')),
                value: state.settings.haptics,
                onChanged: (value) => runUi(context, () async {
                  state.settings.haptics = value;
                  await state.saveSettings();
                  await state.haptic();
                }),
              ),
            ],
          ),
          const SizedBox(height: 16),
          GroupCard(
            children: [
              SettingsRow(
                state.tr('关于 YCode', 'About YCode'),
                icon: 'info',
                onTap: () => openPage<void>(
                  context,
                  AboutPage(state: state, appVersion: appVersion),
                ),
              ),
              SettingsRow(
                state.tr('当前版本', 'Current version'),
                icon: 'tag',
                value: appVersion,
                onTap: () => openPage<void>(
                  context,
                  VersionPage(state: state, appVersion: appVersion),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _layoutLabel(String layout) =>
      layout == 'focus' ? state.tr('沉浸', 'Focus') : state.tr('列表', 'List');

  /// 列表：先看项目和对话列表；沉浸：打开就是对话，列表收进侧边栏。
  Future<void> _layout(BuildContext context) async {
    final selected = await showMenuPanel<String>(context, [
      for (final layout in const ['list', 'focus'])
        MenuPanelItem(
          layout,
          _layoutLabel(layout),
          key: ValueKey('layout-$layout'),
          selected: layout == state.settings.layout,
        ),
    ], width: 180);
    if (selected == null || !context.mounted) return;
    await runUi(context, () async {
      state.settings.layout = selected;
      await state.saveSettings();
    });
  }

  Future<void> _language(BuildContext context) async {
    final selected = await showMenuPanel<String>(context, [
      for (final entry in {
        'system': state.tr('跟随系统', 'System'),
        'zh': '简体中文',
        'en': 'English',
      }.entries)
        MenuPanelItem(
          entry.key,
          entry.value,
          selected: entry.key == state.settings.language,
        ),
    ], width: 180);
    if (selected == null || !context.mounted) return;
    await runUi(context, () async {
      state.settings.language = selected;
      await state.saveSettings();
    });
  }
}

class MyProfilePage extends StatefulWidget {
  const MyProfilePage({super.key, required this.state});
  final AppState state;
  @override
  State<MyProfilePage> createState() => _MyProfilePageState();
}

class _MyProfilePageState extends State<MyProfilePage> {
  late final TextEditingController _name, _gender, _signature;
  String? _avatar;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.state.settings.name);
    _gender = TextEditingController(text: widget.state.settings.gender);
    _signature = TextEditingController(text: widget.state.settings.signature);
    _avatar = widget.state.settings.avatar;
  }

  @override
  void dispose() {
    _name.dispose();
    _gender.dispose();
    _signature.dispose();
    super.dispose();
  }

  Future<void> _picture() async {
    final picked = await pickAvatar(context, widget.state);
    if (picked == null || !mounted) return;
    setState(() => _avatar = base64Encode(picked.bytes));
    await _save();
  }

  /// Each change is kept as it is made: there is nothing left to lose on back.
  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    await runUi(context, () async {
      final settings = widget.state.settings;
      settings.name = _name.text.trim();
      settings.gender = _gender.text.trim();
      settings.signature = _signature.text.trim();
      settings.avatar = _avatar;
      await widget.state.syncProfile();
    });
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _chooseAvatar(BuildContext anchor) async {
    final state = widget.state;
    final choice = await showMenuPanel<String>(anchor, [
      MenuPanelItem(
        'photo',
        state.tr('从相册选择', 'Choose from photos'),
        key: const ValueKey('my-avatar-photo'),
        leading: const LucideIcon('image', size: 22),
      ),
      if (_avatar != null)
        MenuPanelItem(
          'none',
          state.tr('不用头像', 'No avatar'),
          key: const ValueKey('my-avatar-none'),
          leading: LucideIcon(
            'trash-2',
            size: 22,
            color: Theme.of(context).colorScheme.error,
          ),
          color: Theme.of(context).colorScheme.error,
        ),
    ], align: DropdownAlign.center);
    if (!mounted) return;
    switch (choice) {
      case 'photo':
        await _picture();
      case 'none':
        setState(() => _avatar = null);
        await _save();
    }
  }

  Widget _field(TextEditingController controller, String title) =>
      EditableSettingsRow(
        state: widget.state,
        controller: controller,
        title: title,
        enabled: !_saving,
        onChanged: (_) {
          setState(() {});
          _save();
        },
      );

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return Scaffold(
      appBar: AppBar(
        title: Text(state.tr('我的资料', 'My profile')),
        bottom: _saving
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Center(
            child: Builder(
              builder: (anchor) => InkWell(
                key: const ValueKey('my-avatar'),
                borderRadius: BorderRadius.circular(
                  80 * MobileSizes.avatarCorner,
                ),
                onTap: _saving ? null : () => _chooseAvatar(anchor),
                child: LetterAvatar(_name.text, size: 80, image: _avatar),
              ),
            ),
          ),
          const SizedBox(height: 20),
          GroupCard(
            children: [
              _field(_name, state.tr('名字', 'Name')),
              Builder(
                builder: (anchor) => SettingsRow(
                  state.tr('头像', 'Avatar'),
                  value: _avatar == null
                      ? state.tr('未填', 'Not filled')
                      : state.tr('图片', 'Picture'),
                  onTap: _saving ? null : () => _chooseAvatar(anchor),
                ),
              ),
              _field(_gender, state.tr('性别', 'Gender')),
              _field(_signature, state.tr('个性签名', 'Signature')),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              state.tr(
                '你的 Bot 能看到这些和你的头像，知道你是谁。',
                'Your bots can see this and your picture, so they know who you are.',
              ),
              style: MobileTheme.hintStyleOf(context),
            ),
          ),
        ],
      ),
    );
  }
}

class ThemePage extends StatelessWidget {
  const ThemePage({super.key, required this.state});
  final AppState state;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: state,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: Text(state.tr('主题', 'Theme'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GroupCard(
            children: [
              for (final mode in ThemeMode.values)
                PickRow(
                  switch (mode) {
                    ThemeMode.system => state.tr('跟随系统', 'System'),
                    ThemeMode.light => state.tr('浅色', 'Light'),
                    ThemeMode.dark => state.tr('深色', 'Dark'),
                  },
                  leading: LucideIcon(switch (mode) {
                    ThemeMode.system => 'smartphone',
                    ThemeMode.light => 'sun',
                    ThemeMode.dark => 'moon',
                  }, size: 22),
                  selected: state.settings.themeMode == mode,
                  onTap: () => runUi(context, () async {
                    state.settings.themeMode = mode;
                    await state.saveSettings();
                  }),
                ),
            ],
          ),
          SectionLabel(state.tr('主题色', 'Accent color')),
          GroupCard(
            children: [
              for (final accent in MobileAccent.values)
                PickRow(
                  state.tr(accent.zh, accent.en),
                  key: ValueKey('accent-${accent.name}'),
                  leading: _AccentSwatch(accent),
                  selected: MobileAccent.parse(state.settings.accent) == accent,
                  onTap: () => runUi(context, () async {
                    state.settings.accent = accent.name;
                    await state.saveSettings();
                  }),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              state.tr(
                '用于按钮、链接和选中状态；浅色与深色各有适配的色调。',
                'Used for buttons, links and what is selected, toned for light and dark.',
              ),
              style: MobileTheme.hintStyleOf(context),
            ),
          ),
        ],
      ),
    ),
  );
}

/// An accent as a dot: its light tone, its dark one in the lower half.
class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch(this.accent);
  final MobileAccent accent;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 24,
    child: DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [accent.light, accent.light, accent.dark, accent.dark],
          stops: const [0, .5, .5, 1],
        ),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    ),
  );
}

class TextSizePage extends StatelessWidget {
  const TextSizePage({super.key, required this.state});
  final AppState state;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: state,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: Text(state.tr('字号', 'Text size'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(MobileSizes.bubbleRadius),
              ),
              child: Text(
                state.tr('这段代码做什么？', 'What does this code do?'),
                style: MobileTheme.messageStyleOf(context),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            state.tr(
              '你好，这是对话的文字大小。拖动下面的滑块试试。',
              'This is how conversation text appears. Drag the sliders below.',
            ),
            style: MobileTheme.messageStyleOf(context),
          ),
          const SizedBox(height: 16),
          GroupCard(
            children: [
              _sizeRow(
                context,
                state.tr('消息阅读', 'Message reading'),
                '${(state.settings.textScale * 100).round()}%',
                ScaleSlider(
                  value: state.settings.textScale,
                  min: 0.6,
                  max: 1.4,
                  divisions: 8,
                  marks: const [1.0],
                  onChanged: (value) => runUi(context, () async {
                    state.settings.textScale = value;
                    await state.saveSettings();
                  }),
                ),
              ),
              _sizeRow(
                context,
                state.tr('代码', 'Code'),
                '${state.settings.codeFontSize.round()}',
                ScaleSlider(
                  value: state.settings.codeFontSize,
                  min: 10,
                  max: 18,
                  divisions: 8,
                  marks: const [14],
                  onChanged: (value) => runUi(context, () async {
                    state.settings.codeFontSize = value;
                    await state.saveSettings();
                  }),
                ),
              ),
            ],
          ),
          // 代码块在滑块下面：拖动时它就在眼前变，不用往上翻。
          const SizedBox(height: 12),
          const CodePanelPreview(),
          const SizedBox(height: 12),
          Text(
            state.tr(
              '消息阅读只调整消息与思考正文，不改变菜单和输入框。代码字号独立，所有界面仍遵循系统字体设置。',
              'Message reading changes messages and expanded reasoning, not menus or the composer. Code size is separate. System text settings still apply everywhere.',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => runUi(context, () async {
              state.settings.textScale = 1.0;
              state.settings.codeFontSize = 14;
              await state.saveSettings();
            }),
            child: Text(state.tr('恢复默认', 'Reset')),
          ),
        ],
      ),
    ),
  );

  Widget _sizeRow(
    BuildContext context,
    String label,
    String value,
    Widget slider,
  ) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(value, style: TextStyle(color: Theme.of(context).hintColor)),
          ],
        ),
      ),
      slider,
    ],
  );
}

/// The real code block, at the code size being chosen.
class CodePanelPreview extends StatelessWidget {
  const CodePanelPreview({super.key});
  @override
  Widget build(BuildContext context) => const CodePanel(
    code: 'void main() {\n  print("Hello");\n}',
    language: 'dart',
  );
}

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key, required this.state});
  final AppState state;
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage>
    with WidgetsBindingObserver {
  static const _platform = MethodChannel('local.baocode.mobile/platform');
  bool? _permission;
  bool _battery = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.state.addListener(_changed);
    _check();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.state.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Back from the system's settings: see what was chosen there.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    if (widget.state.demo) {
      setState(() => _permission = true);
      return;
    }
    try {
      final permission = await _platform.invokeMethod<bool>(
        'notificationPermission',
      );
      if (mounted) setState(() => _permission = permission ?? false);
    } on PlatformException {
      if (mounted) setState(() => _permission = false);
    } on MissingPluginException {
      if (mounted) setState(() => _permission = false);
    }
    try {
      final battery = await _platform.invokeMethod<bool>('batteryUnrestricted');
      if (mounted) setState(() => _battery = battery ?? true);
    } on PlatformException {
      // 读不到就不提示，不影响通知开关。
    } on MissingPluginException {
      // 同上。
    }
  }

  /// Asks the system; once it has been refused for good it no longer asks,
  /// so its settings open instead.
  Future<bool> _allow() async {
    final granted =
        await _platform.invokeMethod<bool>('requestNotificationPermission') ??
        false;
    if (mounted) setState(() => _permission = granted);
    if (!granted) await _platform.invokeMethod<void>('openAppSettings');
    return granted;
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final theme = Theme.of(context);
    final blocked = _permission == false;
    return Scaffold(
      appBar: AppBar(title: Text(state.tr('通知', 'Notifications'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GroupCard(
            children: [
              SwitchListTile(
                key: const ValueKey('background-connection'),
                title: Text(
                  state.tr('后台保持电脑连接', 'Keep desktop connection in background'),
                ),
                subtitle: Text(
                  state.tr(
                    '开启后显示常驻通知并增加耗电；系统仍可能限制后台运行。',
                    'Uses a persistent notification and more battery. The system may still limit background activity.',
                  ),
                ),
                value: state.demo
                    ? state.settings.keepBackgroundConnection
                    : state.background.running,
                onChanged: _permission == null
                    ? null
                    : (value) => runUi(context, () async {
                        if (value && blocked && !await _allow()) return;
                        await state.setBackgroundConnection(value);
                        if (value && !_battery) {
                          await _platform.invokeMethod<void>(
                            'requestBatteryUnrestricted',
                          );
                        }
                      }),
              ),
              if (state.background.error case final error?)
                ListTile(title: Text(userMessage(state, error))),
              if (!_battery &&
                  (state.demo
                      ? state.settings.keepBackgroundConnection
                      : state.background.running))
                ListTile(
                  key: const ValueKey('battery-unrestricted'),
                  title: Text(state.tr('允许后台运行', 'Allow background activity')),
                  subtitle: Text(
                    state.tr(
                      '系统仍在为 YCode 省电，锁屏久了可能断开。部分手机还要在应用设置里允许自启动和后台运行。',
                      'The system still saves battery for YCode and may disconnect it after a while locked. Some phones also need auto-start and background activity allowed in app settings.',
                    ),
                  ),
                  trailing: TextButton(
                    onPressed: () => runUi(context, () async {
                      await _platform.invokeMethod<void>(
                        'requestBatteryUnrestricted',
                      );
                    }),
                    child: Text(state.tr('去允许', 'Allow')),
                  ),
                ),
            ],
          ),
          const SizedBox(height: MobileSpace.md),
          GroupCard(
            children: [
              for (final (key, zh, en, on, set) in [
                (
                  'needs-input',
                  '智能体需要我处理时',
                  'When an agent needs me',
                  state.settings.notifyNeedsInput,
                  (bool value) => state.settings.notifyNeedsInput = value,
                ),
                (
                  'done',
                  '智能体完成时',
                  'When an agent finishes',
                  state.settings.notifyDone,
                  (bool value) => state.settings.notifyDone = value,
                ),
                (
                  'bots',
                  'Bot 发来消息时',
                  'When a bot messages me',
                  state.settings.notifyBots,
                  (bool value) => state.settings.notifyBots = value,
                ),
              ])
                SwitchListTile(
                  key: ValueKey('notify-$key'),
                  title: Text(state.tr(zh, en)),
                  // Off as long as the system does not let the app notify.
                  value: on && !blocked,
                  onChanged: _permission == null
                      ? null
                      : (value) => runUi(context, () async {
                          if (value && blocked && !await _allow()) return;
                          set(value);
                          await state.saveSettings();
                          if (mounted) setState(() {});
                        }),
                ),
            ],
          ),
          if (blocked)
            Padding(
              padding: const EdgeInsets.only(top: MobileSpace.md),
              child: GroupCard(
                children: [
                  ListTile(
                    key: const ValueKey('notifications-blocked'),
                    leading: LucideIcon(
                      'bell-off',
                      size: 22,
                      color: theme.colorScheme.error,
                    ),
                    title: Text(
                      state.tr(
                        '系统已关闭 BaoCode 的通知',
                        'The system blocks BaoCode notifications',
                      ),
                    ),
                    trailing: TextButton(
                      onPressed: () => runUi(context, () async {
                        await _allow();
                      }),
                      child: Text(state.tr('去开启', 'Allow')),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              state.tr(
                '收到电脑更新后由手机提醒，不依赖推送服务器。可在系统应用设置中允许后台活动；进程被结束后需重新打开 App，并重新开启后台模式；返回时会核对并恢复内容。',
                'The phone notifies after receiving desktop updates, without a push server. Allow background activity in system app settings if needed. Reopen the app and enable background mode again after its process is ended; returning checks and restores content.',
              ),
              style: MobileTheme.hintStyleOf(context),
            ),
          ),
        ],
      ),
    );
  }
}

class SecurityPage extends StatelessWidget {
  const SecurityPage({super.key, required this.state});
  final AppState state;

  Widget _point(BuildContext context, String icon, String title, String body) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: MobileSpace.md),
      child: GroupCard(
        children: [
          Padding(
            padding: const EdgeInsets.all(MobileSpace.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LucideIcon(icon, size: 24, color: theme.colorScheme.primary),
                const SizedBox(width: MobileSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: MobileSpace.xs),
                      Text(body, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _reset(BuildContext context) async {
    final colors = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(state.tr('重置本机密钥？', 'Reset this phone\'s key?')),
        content: Text(
          state.tr(
            '会为这台手机生成新的密钥，所有电脑都需要重新配对，旧密钥无法恢复。',
            'This phone gets a new key. Every desktop has to be paired again; the old key cannot be restored.',
          ),
        ),
        actions: dialogButtons([
          OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(state.tr('取消', 'Cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: colors.error,
              foregroundColor: colors.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(state.tr('重置', 'Reset')),
          ),
        ]),
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await runUi(context, () async {
      await state.link.resetIdentity();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              state.tr('已重置，请重新配对电脑', 'Reset. Pair your desktops again.'),
            ),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(state.tr('安全', 'Security'))),
      body: ListenableBuilder(
        listenable: Listenable.merge([state, state.link]),
        builder: (context, _) {
          final fingerprint = state.demo ? null : state.link.fingerprint;
          final groups = fingerprint?.split(' ') ?? const <String>[];
          return ListView(
            padding: const EdgeInsets.all(MobileSpace.lg),
            children: [
              _point(
                context,
                'lock',
                state.tr('密钥只在你的设备上', 'Keys stay on your devices'),
                state.tr(
                  '手机和每台电脑各自生成密钥对，私钥从不离开设备。',
                  'The phone and each desktop make their own key pair; private keys never leave the device.',
                ),
              ),
              _point(
                context,
                'route',
                state.tr('途经的网络无法读取', 'Networks in between cannot read it'),
                state.tr(
                  '消息、代码和文件在发出前就已加密，无论经过局域网、公网，还是以后的中转服务。',
                  'Messages, code and files are encrypted before they leave, over the LAN, the internet, or a relay later on.',
                ),
              ),
              _point(
                context,
                'shield-check',
                state.tr('配对时当面核对', 'Checked face to face when pairing'),
                state.tr(
                  '配对时核对安全码，确保中间没有人截获。',
                  'Comparing safety codes when pairing makes sure nobody is in between.',
                ),
              ),
              SectionLabel(state.tr('本机密钥', 'This phone\'s key')),
              GroupCard(
                children: [
                  Padding(
                    key: const ValueKey('security-fingerprint'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: MobileSpace.lg,
                      vertical: MobileSpace.lg,
                    ),
                    child: groups.isEmpty
                        ? Text(
                            state.tr('密钥尚未生成', 'No key yet'),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall,
                          )
                        : Column(
                            children: [
                              for (var row = 0; row < groups.length; row += 4)
                                SelectableText(
                                  groups.skip(row).take(4).join('  '),
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontFamily: 'monospace',
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                    height: 1.6,
                                  ),
                                ),
                            ],
                          ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  state.tr(
                    '已配对的电脑上会显示这台手机的这个指纹。',
                    'Paired desktops show this fingerprint for this phone.',
                  ),
                  style: MobileTheme.hintStyleOf(context),
                ),
              ),
              const SizedBox(height: MobileSpace.lg),
              GroupCard(
                children: [
                  ListTile(
                    key: const ValueKey('security-reset'),
                    enabled: !state.demo && fingerprint != null,
                    title: Text(
                      state.tr('重置密钥', 'Reset key'),
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    onTap: () => _reset(context),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  state.tr(
                    '为这台手机生成新的密钥，所有电脑都需要重新配对。',
                    'Gives this phone a new key; every desktop has to be paired again.',
                  ),
                  style: MobileTheme.hintStyleOf(context),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Claude Code's skills, MCP servers, plugins and subagents on one desktop,
/// counted by kind as the desktop's own settings show them; a kind opens
/// its list. Read only: they are set up on the desktop.
class ExtensionsPage extends StatefulWidget {
  const ExtensionsPage({super.key, required this.state});
  final AppState state;
  @override
  State<ExtensionsPage> createState() => _ExtensionsPageState();
}

typedef _Kind = ({String id, String icon, String zh, String en});

const List<_Kind> _extensionKinds = [
  (id: 'skill', icon: 'book-open-text', zh: '技能', en: 'Skills'),
  (id: 'mcp', icon: 'plug', zh: 'MCP', en: 'MCP'),
  (id: 'plugin', icon: 'puzzle', zh: '插件', en: 'Plugins'),
  (id: 'agent', icon: 'bot', zh: '子代理', en: 'Subagents'),
];

class _ExtensionsPageState extends State<ExtensionsPage> {
  Future<List<Map<String, Object?>>>? _items;
  String? _loadedFor;

  AppState get state => widget.state;

  void _load() {
    final desktopId = state.selectedDesktopId;
    _loadedFor = desktopId;
    _items = desktopId == null || !state.isOnline(desktopId)
        ? null
        : state
              .request(desktopId, LinkMethods.extensions)
              .then(
                (result) => [
                  for (final item
                      in (objectMap(result)['items'] as List?) ?? [])
                    objectMap(item),
                ],
              );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) {
      // Another desktop chosen, or the one shown came online: ask it.
      final desktopId = state.selectedDesktopId;
      if (desktopId != _loadedFor ||
          (_items == null && desktopId != null && state.isOnline(desktopId))) {
        _load();
      }
      final name = state.desktops
          .where((desktop) => desktop.id == desktopId)
          .firstOrNull
          ?.name;
      return Scaffold(
        appBar: AppBar(
          title: Text(state.tr('技能', 'Skills')),
          actions: [
            if (state.desktops.isNotEmpty)
              DesktopSwitcherButton(
                state: state,
                onChanged: () => setState(_load),
              ),
          ],
        ),
        body: _items == null
            ? EmptyPanel(
                desktopId == null
                    ? state.tr('还没有配对电脑。', 'No desktop paired yet.')
                    : state.tr(
                        '电脑未连接，连上后显示它的扩展。',
                        'The desktop is not connected; its extensions show once it is.',
                      ),
              )
            : FutureBuilder<List<Map<String, Object?>>>(
                future: _items,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    final error = snapshot.error;
                    return EmptyPanel(
                      error is LinkRemoteException &&
                              (error.code == LinkErrors.unknown ||
                                  error.code == LinkErrors.unsupported)
                          ? state.tr(
                              '这台电脑上的 BaoCode 版本不支持查看扩展。',
                              'The BaoCode on this desktop cannot list extensions.',
                            )
                          : userMessage(state, error),
                      actionLabel: state.tr('重试', 'Retry'),
                      onAction: () => setState(_load),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final items = snapshot.data!;
                  return RefreshIndicator(
                    onRefresh: () async {
                      setState(_load);
                      await _items;
                    },
                    child: ListView(
                      padding: const EdgeInsets.all(MobileSpace.lg),
                      children: [
                        GroupCard(
                          children: [
                            for (final kind in _extensionKinds)
                              _kindRow(context, kind, [
                                for (final item in items)
                                  if (item['kind'] == kind.id) item,
                              ]),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          child: Text(
                            state.tr(
                              '${name ?? ''} 上 Claude Code 的扩展。',
                              "Claude Code's extensions on ${name ?? 'the desktop'}.",
                            ),
                            style: MobileTheme.hintStyleOf(context),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      );
    },
  );

  Widget _kindRow(
    BuildContext context,
    _Kind kind,
    List<Map<String, Object?>> items,
  ) {
    final title = state.tr(kind.zh, kind.en);
    return SettingsRow(
      title,
      key: ValueKey('extensions-${kind.id}'),
      icon: kind.icon,
      value: '${items.length}',
      onTap: items.isEmpty
          ? null
          : () => openPage<void>(
              context,
              _ExtensionListPage(state: state, kind: kind, items: items),
            ),
    );
  }
}

/// Where an extension comes from, as the list groups them: the user's are
/// global, a project's go under its folder.
String _extensionScope(AppState state, Map<String, Object?> item) {
  final project = (item['project'] as String?)
      ?.split(RegExp(r'[/\\]'))
      .where((part) => part.isNotEmpty)
      .lastOrNull;
  return switch (item['scope']) {
    'user' => state.tr('全局', 'Global'),
    'project' || 'local' => project ?? state.tr('项目', 'Project'),
    'plugin' => state.tr('插件', 'Plugin'),
    'managed' => state.tr('托管', 'Managed'),
    final Object other => '$other',
    null => state.tr('全局', 'Global'),
  };
}

/// One kind's extensions by where they come from; each opens its detail.
class _ExtensionListPage extends StatefulWidget {
  const _ExtensionListPage({
    required this.state,
    required this.kind,
    required this.items,
  });
  final AppState state;
  final _Kind kind;
  final List<Map<String, Object?>> items;
  @override
  State<_ExtensionListPage> createState() => _ExtensionListPageState();
}

class _ExtensionListPageState extends State<_ExtensionListPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final theme = Theme.of(context);
    final needle = _query.trim().toLowerCase();
    final groups = <String, List<Map<String, Object?>>>{};
    for (final item in widget.items) {
      if (!'${item['name']} ${item['description'] ?? ''}'
          .toLowerCase()
          .contains(needle)) {
        continue;
      }
      (groups[_extensionScope(state, item)] ??= []).add(item);
    }
    for (final list in groups.values) {
      list.sort(
        (a, b) => '${a['name']}'.toLowerCase().compareTo(
          '${b['name']}'.toLowerCase(),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(state.tr(widget.kind.zh, widget.kind.en))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          MobileSpace.lg,
          0,
          MobileSpace.lg,
          MobileSpace.lg,
        ),
        children: [
          if (widget.items.length > 8)
            SearchCapsule(
              state: state,
              onChanged: (value) => setState(() => _query = value),
            ),
          for (final MapEntry(key: scope, value: items) in groups.entries) ...[
            SectionLabel(scope),
            GroupCard(
              children: [
                for (final item in items)
                  SettingsRow(
                    '${item['name'] ?? ''}',
                    value: item['enabled'] == false
                        ? state.tr('已关闭', 'Disabled')
                        : null,
                    onTap: () => openPage<void>(
                      context,
                      _ExtensionDetailPage(
                        state: state,
                        kind: widget.kind,
                        item: item,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (groups.isEmpty)
            Padding(
              padding: const EdgeInsets.all(MobileSpace.lg),
              child: Text(
                state.tr('没有匹配的项', 'Nothing matches'),
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

/// One extension: its kind and where it comes from, then what it does.
class _ExtensionDetailPage extends StatelessWidget {
  const _ExtensionDetailPage({
    required this.state,
    required this.kind,
    required this.item,
  });
  final AppState state;
  final _Kind kind;
  final Map<String, Object?> item;

  @override
  Widget build(BuildContext context) {
    final description = (item['description'] as String?)?.trim() ?? '';
    return Scaffold(
      appBar: AppBar(title: Text('${item['name'] ?? ''}')),
      body: ListView(
        padding: const EdgeInsets.all(MobileSpace.lg),
        children: [
          GroupCard(
            children: [
              SettingsRow(
                state.tr(kind.zh, kind.en),
                icon: kind.icon,
                value: [
                  _extensionScope(state, item),
                  if (item['enabled'] == false) state.tr('已关闭', 'Disabled'),
                ].join(' · '),
              ),
            ],
          ),
          SectionLabel(state.tr('说明', 'Description')),
          GroupCard(
            children: [
              Container(
                // The card's column centres what is narrower than it.
                width: double.infinity,
                padding: const EdgeInsets.all(MobileSpace.lg),
                child: SelectableText(
                  description.isEmpty
                      ? state.tr('没有说明', 'No description')
                      : description,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 设置页里的「检查更新」：点一下问 GitHub 有没有新版本，问的同时转圈，
/// 连点只算一次。结果按版本情况说，打开 release 前先问一句。
class UpdateCheckRow extends StatefulWidget {
  const UpdateCheckRow({
    super.key,
    required this.state,
    required this.currentVersion,
    this.fetcher = fetchLatestRelease,
  });
  final AppState state;
  final String currentVersion;
  final ReleaseFetcher fetcher;
  @override
  State<UpdateCheckRow> createState() => _UpdateCheckRowState();
}

class _UpdateCheckRowState extends State<UpdateCheckRow> {
  bool _checking = false;

  Future<void> _check() async {
    if (_checking) return;
    setState(() => _checking = true);
    UpdateCheck? result;
    await runUi(context, () async {
      result = await checkForUpdate(
        currentVersion: widget.currentVersion,
        fetcher: widget.fetcher,
      );
    }, errorMessage: (error) => userMessage(widget.state, error));
    if (!mounted) return;
    setState(() => _checking = false);
    final found = result;
    if (found == null) return;
    if (!found.comparable) {
      await _noVersion(found);
    } else if (found.newer) {
      await _newer(found);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.state.tr(
              '已是最新版本（${found.latest.version}）',
              'You are up to date (${found.latest.version})',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _newer(UpdateCheck result) async {
    await showDialog<void>(
      context: context,
      builder: (context) =>
          UpdateDialog(state: widget.state, release: result.latest),
    );
  }

  /// 调试或测试构建没有版本号可比较，只说最新的版本是哪个。
  Future<void> _noVersion(UpdateCheck result) async {
    final state = widget.state;
    final latest = result.latest;
    final open = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(state.tr('这个构建没有版本号', 'This build has no version')),
        content: Text(
          state.tr(
            '当前不是正式发布的构建，没法比较版本。最新版本是 ${latest.version}。',
            'This is not a release build, so there is nothing to compare. The latest version is ${latest.version}.',
          ),
        ),
        actions: dialogButtons([
          OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(state.tr('关闭', 'Close')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(state.tr('查看版本', 'View release')),
          ),
        ]),
      ),
    );
    if (open == true && mounted) {
      await confirmExternalLink(context, state, latest.url);
    }
  }

  @override
  Widget build(BuildContext context) => SettingsRow(
    widget.state.tr('检查更新', 'Check for updates'),
    icon: 'refresh-cw',
    value: _checking
        ? null
        : widget.state.tr('看看有没有新版本', 'Look for a new version'),
    trailing: _checking ? const ConnectingSpinner(size: 18) : null,
    onTap: _checking ? null : _check,
  );
}

/// 版本更新页：图标、版本名，一个检查更新的按钮。
class VersionPage extends StatelessWidget {
  const VersionPage({super.key, required this.state, required this.appVersion});
  final AppState state;
  final String appVersion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(state.tr('版本更新', 'Update'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          MobileSpace.lg,
          MobileSpace.xl,
          MobileSpace.lg,
          MobileSpace.xl,
        ),
        children: [
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: SvgPicture.asset(
                'assets/icons/ycode.svg',
                width: 96,
                height: 96,
              ),
            ),
          ),
          const SizedBox(height: MobileSpace.xl),
          Text(
            'YCode $appVersion',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: MobileSpace.lg),
          GroupCard(
            children: [
              UpdateCheckRow(state: state, currentVersion: appVersion),
            ],
          ),
        ],
      ),
    );
  }
}

/// 关于：图标、版本和一句话说明，下面是官网、更新日志、开源许可。
class AboutPage extends StatelessWidget {
  const AboutPage({super.key, required this.state, required this.appVersion});
  final AppState state;
  final String appVersion;

  static const _site = projectUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(state.tr('关于 YCode', 'About YCode'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          MobileSpace.lg,
          MobileSpace.xl,
          MobileSpace.lg,
          MobileSpace.xl,
        ),
        children: [
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: SvgPicture.asset(
                'assets/icons/ycode.svg',
                width: 96,
                height: 96,
              ),
            ),
          ),
          const SizedBox(height: MobileSpace.lg),
          Text(
            'YCode',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: MobileSpace.xs),
          Text(
            state.tr('版本 $appVersion', 'Version $appVersion'),
            textAlign: TextAlign.center,
            style: MobileTheme.hintStyleOf(context),
          ),
          const SizedBox(height: MobileSpace.lg),
          Text(
            state.tr(
              '把电脑上的 Claude Code 装进口袋：随时查看对话进展、回答提问、发起新任务，全程端到端加密。',
              'Claude Code from your desktop, in your pocket: follow work as it happens, answer questions, start new tasks, all end-to-end encrypted.',
            ),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: MobileSpace.xl),
          GroupCard(
            children: [
              SettingsRow(
                state.tr('官网', 'Website'),
                value: Uri.parse(_site).host,
                onTap: () => confirmExternalLink(context, state, _site),
              ),
              SettingsRow(
                state.tr('更新日志', 'Changelog'),
                onTap: () =>
                    openPage<void>(context, ChangelogPage(state: state)),
              ),
              SettingsRow(
                state.tr('开源许可', 'Open-source licenses'),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'YCode',
                  applicationVersion: appVersion,
                ),
              ),
            ],
          ),
          const SizedBox(height: MobileSpace.xl),
          Text(
            '© ${DateTime.now().year} YCode',
            textAlign: TextAlign.center,
            style: MobileTheme.hintStyleOf(context),
          ),
        ],
      ),
    );
  }
}
