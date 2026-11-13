import 'package:flutter/material.dart';

class AppSettings {
  AppSettings();

  String language = 'system';
  ThemeMode themeMode = ThemeMode.system;

  /// [MobileAccent]'s name.
  String accent = 'green';
  String? desktop;
  double textScale = 1.0;
  double codeFontSize = 14;

  /// `chat.agentLoadingStyle` and the like, by the desktop's keys.
  Map<String, Object?> loaders = {};

  /// What the phone tells of, as the desktop's own notification settings:
  /// an agent waiting on you, an agent done, a bot's message.
  bool notifyNeedsInput = true, notifyDone = true, notifyBots = true;

  /// Any of them; setting it sets all three.
  bool get notifications => notifyNeedsInput || notifyDone || notifyBots;
  set notifications(bool value) =>
      notifyNeedsInput = notifyDone = notifyBots = value;

  /// The system was asked once to let the app notify; not again unasked.
  bool notificationsAsked = false;
  bool keepBackgroundConnection = false;
  bool haptics = true;

  /// Keeps an agent's changes as each of its turns ends, for every
  /// conversation: the phone's own, sent as the desktop's Keep.
  bool autoKeep = false;

  /// The conversations shown on the home list beside the projects, as
  /// (desktop, session): the phone's own choice, the desktop knows nothing
  /// of it.
  Set<(String, String)> homeSessions = {};

  /// The bots pinned on the lists, as (desktop, bot): the phone's own choice,
  /// the desktop keeps no pin for a bot.
  Set<(String, String)> pinnedBots = {};

  /// 界面模式：`list` 是对话列表，`focus` 打开就是对话、列表收在侧边栏。
  String layout = 'list';
  bool get focusLayout => layout == 'focus';

  /// 沉浸模式下次打开时回到的对话，as (desktop, session).
  (String, String)? lastSession;
  String name = '';
  String gender = '';
  String signature = '';
  String? avatar;

  factory AppSettings.fromJson(Map<String, Object?> json) {
    final settings = AppSettings();
    settings.language = switch (json['language']) {
      'zh' => 'zh',
      'en' => 'en',
      _ => 'system',
    };
    settings.themeMode =
        ThemeMode.values.asNameMap()[json['theme']] ?? ThemeMode.system;
    // 'accent' held only the first default (blue), never a choice: read anew.
    settings.accent = json['accentColor'] as String? ?? 'green';
    settings.desktop = json['desktop'] as String?;
    settings.textScale = ((json['textScale'] as num?)?.toDouble() ?? 1.0)
        .clamp(0.6, 1.4)
        .toDouble();
    settings.codeFontSize = ((json['codeFontSize'] as num?)?.toDouble() ?? 14)
        .clamp(10, 18)
        .toDouble();
    if (json['loaders'] case final Map<dynamic, dynamic> loaders) {
      settings.loaders = loaders.cast<String, Object?>();
    } else if (const {'dots': 'dots', 'ring': 'circle'}[json['loader']]
        case final style?) {
      settings.loaders = {'chat.agentLoadingStyle': style};
    }
    // One switch before: each kind starts as it was.
    final all = json['notifications'] != false;
    settings.notifyNeedsInput = json['notifyNeedsInput'] as bool? ?? all;
    settings.notifyDone = json['notifyDone'] as bool? ?? all;
    settings.notifyBots = json['notifyBots'] as bool? ?? all;
    settings.notificationsAsked = json['notificationsAsked'] == true;
    settings.keepBackgroundConnection =
        json['keepBackgroundConnection'] == true;
    settings.haptics = json['haptics'] != false;
    settings.autoKeep = json['autoKeepChanges'] == true;
    settings.homeSessions = {
      for (final entry in (json['homeSessions'] as List?) ?? const [])
        if (entry case [final String desktop, final String session])
          (desktop, session),
    };
    settings.pinnedBots = {
      for (final entry in (json['pinnedBots'] as List?) ?? const [])
        if (entry case [final String desktop, final String bot]) (desktop, bot),
    };
    settings.layout = json['layout'] == 'focus' ? 'focus' : 'list';
    if (json['lastSession'] case [final String desktop, final String session]) {
      settings.lastSession = (desktop, session);
    }
    settings.name = json['name'] as String? ?? '';
    settings.gender = json['gender'] as String? ?? '';
    settings.signature = json['signature'] as String? ?? '';
    settings.avatar = json['avatar'] as String?;
    return settings;
  }

  Map<String, Object?> toJson() => {
    'language': language,
    'theme': themeMode.name,
    'accentColor': accent,
    'desktop': desktop,
    'textScale': textScale,
    'codeFontSize': codeFontSize,
    'loaders': loaders,
    'notifyNeedsInput': notifyNeedsInput,
    'notifyDone': notifyDone,
    'notifyBots': notifyBots,
    'notificationsAsked': notificationsAsked,
    'keepBackgroundConnection': keepBackgroundConnection,
    'haptics': haptics,
    'autoKeepChanges': autoKeep,
    'homeSessions': [
      for (final (desktop, session) in homeSessions) [desktop, session],
    ],
    'pinnedBots': [
      for (final (desktop, bot) in pinnedBots) [desktop, bot],
    ],
    'layout': layout,
    'lastSession': switch (lastSession) {
      (final desktop, final session) => [desktop, session],
      null => null,
    },
    'name': name,
    'gender': gender,
    'signature': signature,
    'avatar': avatar,
  };
}
