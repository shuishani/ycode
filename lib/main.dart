import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_licenses.dart';
import 'chat/widgets/pixel_loader.dart';
import 'link/link_store.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'ui/home_shell.dart';
import 'ui/widgets/lucide_icon.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  registerAppLicenses();
  // The home screen's icons, read while the app starts behind its loader.
  unawaited(
    LucideIcon.precache(const [
      'message-circle',
      'bot',
      'folder',
      'settings',
      'list-filter',
      'circle-plus',
      'search',
      'chevron-down',
      'pin',
      'user-plus',
      'images',
      'camera',
      'at-sign',
    ]).catchError((Object _) {}),
  );
  const demo = bool.fromEnvironment('DEMO');
  runApp(
    MobileApp(
      state: AppState(
        demo: demo,
        store: demo ? MemoryLinkStore() : PlatformLinkStore(),
      ),
    ),
  );
}

class MobileApp extends StatefulWidget {
  const MobileApp({super.key, required this.state});
  final AppState state;
  @override
  State<MobileApp> createState() => _MobileAppState();
}

class _MobileAppState extends State<MobileApp> with WidgetsBindingObserver {
  final _themes = MobileThemeCache();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Paired already: the system is asked, once, to let the app notify.
    unawaited(
      widget.state.initialize().then(
        (_) => widget.state.askNotificationsOnce(),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.state.setForeground(state == AppLifecycleState.resumed);
    if (state == AppLifecycleState.resumed) unawaited(widget.state.resume());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.state,
    builder: (context, _) {
      final state = widget.state;
      final themes = _themes.of(
        accent: MobileAccent.parse(state.settings.accent),
        codeFontSize: state.settings.codeFontSize,
        messageScale: state.settings.textScale,
      );
      return MaterialApp(
        title: 'YCode',
        debugShowCheckedModeBanner: false,
        theme: themes.light,
        darkTheme: themes.dark,
        themeMode: state.settings.themeMode,
        locale: state.settings.language == 'system'
            ? null
            : Locale(state.settings.language),
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: state.ready
            ? HomeShell(state: state)
            : Scaffold(body: Center(child: const PixelLoader.agent(size: 32))),
      );
    },
  );
}
