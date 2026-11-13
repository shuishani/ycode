import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:bao_link/bao_link.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../link/desktop_discovery.dart';
import '../link/phone_link.dart';
import '../models/app_settings.dart';
import '../models/session_buffer.dart';
import 'demo_workspace.dart';
import 'icon_cache.dart';
import 'local_message_queue.dart';
import 'session_subscriptions.dart';
import 'task_output_subscriptions.dart';
import 'conversation_input.dart';
import 'bot_settings.dart';
import 'desktop_notifications.dart';
import 'background_connection.dart';

export '../models/app_settings.dart';
export '../models/session_buffer.dart';

class ProjectRef {
  const ProjectRef(this.desktopId, this.project);
  final String desktopId;
  final ProjectInfo project;
}

/// The model a conversation runs on: its option [id], as shown ([label]),
/// and the upstream it is listed under, for its logo.
typedef SessionModel = ({
  String id,
  String label,
  String? provider,
  String? providerLabel,
});

class SessionRef {
  const SessionRef(this.desktopId, this.session);
  final String desktopId;
  final SessionSummary session;
}

class BotRef {
  const BotRef(this.desktopId, this.bot);
  final String desktopId;
  final LinkBot bot;
}

class AppState extends ChangeNotifier {
  AppState({
    LinkStore? store,
    PhoneLink? link,
    this.demo = false,
    IconCache? icons,
    BackgroundConnection? background,
  }) : _store = store ?? PlatformLinkStore(),
       icons = icons ?? IconCache(),
       background = background ?? BackgroundConnection() {
    this.link = link ?? PhoneLink(store: _store);
    this.background
      ..onNetworkChanged = networkChanged
      ..onStopped = _backgroundStopped
      ..addListener(_notify);
    _subscriptions = SessionSubscriptions(
      request: (desktop, method, params) => request(desktop, method, params),
      onChanged: _sessionsChanged,
      tr: tr,
    );
    localQueue = LocalMessageQueue(
      isOnline: isOnline,
      bufferOf: buffer,
      send: sendMessage,
      onChanged: _notify,
      tr: tr,
    );
    taskOutputs = TaskOutputSubscriptions(
      request: (desktop, method, params) => request(desktop, method, params),
      isOnline: isOnline,
      onChanged: _notify,
      tr: tr,
    );
    notifications = DesktopNotifications(
      channel: _platform,
      settings: () => settings,
      tr: tr,
    );
    if (demo) _demo = DemoWorkspace();
  }

  final LinkStore _store;
  late final PhoneLink link;
  final bool demo;

  /// Memory cache for small pictures (project icons, bot avatars) so list
  /// pages do not re-request them on every navigation.
  final IconCache icons;
  DemoWorkspace? _demo;
  AppSettings settings = AppSettings();
  final DesktopDiscovery discovery = DesktopDiscovery();
  final _discoveredAddresses = <String, String>{};
  bool foreground = true;
  final BackgroundConnection background;
  Map<String, int> _backgroundGenerations = {};
  bool _resumeMayReuse = false;
  int _networkRevision = 0;
  Future<void>? _checkingConnections;

  void _discoveryChanged() {
    for (final advert in discovery.desktops) {
      if (isOnline(advert.id) ||
          !desktops.any(
            (desktop) => desktop.id == advert.id && !desktop.needsPairing,
          )) {
        continue;
      }
      final addresses = advert.addrs;
      if (addresses.isEmpty ||
          _discoveredAddresses[advert.id] == addresses.join(',')) {
        continue;
      }
      _discoveredAddresses[advert.id] = addresses.join(',');
      final existing = desktops.firstWhere(
        (desktop) => desktop.id == advert.id,
      );
      unawaited(
        link
            .updateAddresses(
              advert.id,
              {...addresses, ...existing.addresses}.toList(),
            )
            .then((_) => link.reconnect(advert.id))
            .catchError((Object _) {}),
      );
    }
    _notify();
  }

  bool ready = false;
  String? startupError;
  bool _disposed = false;

  /// 手机上看过的对话和看时的更新时间。电脑端不一定知道手机看过，不能只信它的未读。
  final _seenSessions = <String, int>{};

  /// 开在屏幕上的对话，键同 [_seenSessions]，值是开着它的页面数。
  final _viewing = <String, int>{};
  Future<void> _seenWrites = Future.value();

  /// 对话最近用的模型，手机自己记着：电脑只说它开着的对话用什么模型，别的
  /// 对话、App 重启以后就靠这份。键同 [_seenSessions]，最多记 [_modelsKept] 条。
  final _sessionModels = <String, SessionModel>{};
  Future<void> _modelWrites = Future.value();
  static const _modelsKept = 500;

  /// 换到别的上游的模型时，Claude Code 整个重启，对话里不留「Set model to」
  /// 那一行；手机看到换了就自己记下何时换成了什么，画在那之后的第一条消息前。
  final _modelMarks = <String, List<({DateTime at, String label})>>{};
  static const _marksKept = 20;

  /// 这次运行里跟着的对话最后用的模型：换了才知道是从哪个上游换过来的。
  final _followedModels = <String, SessionModel>{};
  StreamSubscription<DesktopEvent>? _events;
  late final SessionSubscriptions _subscriptions;
  late final TaskOutputSubscriptions taskOutputs;

  /// What the user sent while an agent worked, waiting on the phone for the
  /// turn to end.
  late final LocalMessageQueue localQueue;
  Set<String> _knownDesktopIds = {};
  final _drafts = <String, Object?>{};
  final _inputDrafts = <String, InputDraft>{};
  final _botCreations = <String, BotProfileSaver>{};
  Future<void> _draftWrites = Future.value();
  Set<String> _lastOnline = {};
  final _sessionStatuses = <(String, String), SessionSummary>{};
  late final DesktopNotifications notifications;

  static const _platform = MethodChannel('local.baocode.mobile/platform');

  /// Asks the system, once, to let the app notify: a newly installed app may
  /// not, and the setting reads on all the same. Only with the app in front
  /// (the system shows a dialog); after that the notifications page does.
  Future<void> askNotificationsOnce() async {
    if (demo ||
        _disposed ||
        !settings.notifications ||
        settings.notificationsAsked ||
        desktops.isEmpty) {
      return;
    }
    settings.notificationsAsked = true;
    await saveSettings();
    try {
      await _platform.invokeMethod<bool>('requestNotificationPermission');
    } on PlatformException {
      /* Refused or unavailable: the notifications page tells. */
    } on MissingPluginException {
      /* Not available in host-free tests. */
    }
  }

  final _autoKeeping = <(String, String)>{};

  /// A turn ended: its changes kept, when the phone is set to. The desktop
  /// keeps nothing when none are left; a failure leaves them listed, to keep
  /// or undo by hand.
  void _autoKeep(String desktopId, String sessionId) {
    if (!settings.autoKeep || !isOnline(desktopId)) return;
    final key = (desktopId, sessionId);
    if (!_autoKeeping.add(key)) return;
    unawaited(
      request(desktopId, LinkMethods.keep, {'session': sessionId})
          .then((_) {}, onError: (Object _) {})
          .whenComplete(() => _autoKeeping.remove(key)),
    );
  }

  String tr(String zh, String en) {
    final language = settings.language == 'system'
        ? ui.PlatformDispatcher.instance.locale.languageCode
        : settings.language;
    return language == 'zh' ? zh : en;
  }

  /// 不经过界面实例地说一句双语：给底层（状态、平台）拼错误用，
  /// 跟着用户选的语言，不把中英混排塞给用户。
  static String phrase(String zh, String en) {
    final saved = _languageFromStore;
    final language = saved == null || saved == 'system'
        ? ui.PlatformDispatcher.instance.locale.languageCode
        : saved;
    return language == 'zh' ? zh : en;
  }

  /// 最近一次读到的界面语言：底层没有 [AppState] 实例时也说得对。
  static String? _languageFromStore;

  /// Pins [phrase]'s language in a test ('zh', 'en', or null to follow the
  /// store again): the test binding's locale does not reach it.
  @visibleForTesting
  static set debugLanguage(String? language) => _languageFromStore = language;

  List<KeptDesktop> get desktops => demo ? _demo!.desktops : link.desktops;
  bool isOnline(String desktopId) => demo || link.onlineIds.contains(desktopId);
  DesktopLinkStatus linkStatus(String desktopId) {
    final status = demo ? DesktopLinkStatus.online : link.statusOf(desktopId);
    return status == DesktopLinkStatus.offline && isOnline(desktopId)
        ? DesktopLinkStatus.online
        : status;
  }

  /// Tries an offline desktop now instead of waiting out the backoff.
  void retryConnection(String desktopId) {
    if (demo || isOnline(desktopId)) return;
    unawaited(link.retryNow(desktopId).catchError((Object _) {}));
  }

  LinkPath pathOf(String desktopId) =>
      demo ? LinkPath.none : link.pathOf(desktopId);

  DateTime? lastSeenOf(String desktopId) =>
      demo ? null : link.lastSeenOf(desktopId);

  /// The desktop the 对话 / Bot / 文件 tabs show: the one picked last (kept
  /// across restarts, so a reconnect shows it rather than another desktop),
  /// else the first online one.
  String? get selectedDesktopId {
    final kept = desktops;
    if (kept.any((desktop) => desktop.id == settings.desktop)) {
      return settings.desktop;
    }
    final online = kept.where((desktop) => isOnline(desktop.id)).firstOrNull;
    if (online != null) return online.id;
    final seen = [
      for (final desktop in kept)
        if (lastSeenOf(desktop.id) case final at?) (desktop.id, at),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    return seen.firstOrNull?.$1 ?? kept.firstOrNull?.id;
  }

  void selectDesktop(String desktopId) {
    if (settings.desktop == desktopId) return;
    settings.desktop = desktopId;
    _notify();
    unawaited(saveSettings().catchError((Object _) {}));
  }

  Map<String, LinkState> get snapshots => {
    for (final entry in (demo ? _demo!.states : link.states).entries)
      entry.key: LinkState.fromJson(entry.value),
  };
  List<ProjectRef> get projects {
    final projects = [
      for (final desktop in snapshots.entries)
        for (final project in desktop.value.projects)
          ProjectRef(desktop.key, project),
    ];
    return [
      for (final ref in projects)
        if (ref.project.pinned == true) ref,
      for (final ref in projects)
        if (ref.project.pinned != true) ref,
    ];
  }

  List<SessionRef> get sessions {
    final list = [
      for (final desktop in snapshots.entries)
        for (final session in desktop.value.sessions)
          SessionRef(desktop.key, session),
    ];
    list.sort((a, b) {
      if (a.session.pinned != b.session.pinned) {
        return a.session.pinned ? -1 : 1;
      }
      return b.session.updatedAt.compareTo(a.session.updatedAt);
    });
    return list;
  }

  List<BotRef> get bots => [
    for (final desktop in snapshots.entries)
      for (final bot in desktop.value.bots) BotRef(desktop.key, bot),
  ];
  String desktopName(String id) {
    for (final desktop in desktops) {
      if (desktop.id == id) return desktop.name;
    }
    return id;
  }

  Future<void> initialize() async {
    try {
      // 读存储失败才算启动失败；某一份内容坏了只丢这一份，不影响连接电脑。
      if (await _readLocalJson('settings') case final saved?) {
        try {
          settings = AppSettings.fromJson(objectMap(saved));
          _languageFromStore = settings.language;
        } on Object catch (error) {
          debugPrint('Ignoring unreadable settings: $error');
        }
      }
      if (await _readLocalJson('drafts') case final drafts?) {
        objectMap(drafts).forEach((key, value) {
          if (value is String || value is Map) _drafts[key] = value;
        });
      }
      if (await _readLocalJson('seen_sessions') case final seen?) {
        objectMap(seen).forEach((key, value) {
          if (value is int) _seenSessions[key] = value;
        });
      }
      if (await _readLocalJson('model_marks') case final marks?) {
        objectMap(marks).forEach((key, value) {
          _modelMarks[key] = [
            for (final mark in value is List ? value : const [])
              if (mark case [final int at, final String label])
                (at: DateTime.fromMillisecondsSinceEpoch(at), label: label),
          ];
        });
      }
      if (await _readLocalJson('session_models') case final models?) {
        objectMap(models).forEach((key, value) {
          if (value case {'id': final String id, 'label': final String label}) {
            _sessionModels[key] = (
              id: id,
              label: label,
              provider: value['provider'] as String?,
              providerLabel: value['providerLabel'] as String?,
            );
          }
        });
      }
      if (!demo) {
        link.addListener(_linkChanged);
        _events = link.events.listen(_event);
        await link.initialize();
        await background.initialize();
        if (settings.keepBackgroundConnection &&
            !background.running &&
            background.error == null) {
          // 冷启动不擅自重开已停止的服务，以原生实际状态为准。
          settings.keepBackgroundConnection = false;
          await saveSettings();
        }
        discovery.addListener(_discoveryChanged);
        unawaited(discovery.start().catchError((Object _) {}));
      }
    } on Object {
      startupError = tr(
        '本地安全存储或连接初始化失败，请重试。',
        'Secure storage or connection initialization failed. Please retry.',
      );
    }
    ready = true;
    _notify();
  }

  Future<Object?> _readLocalJson(String key) async {
    final raw = await _store.read(key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } on FormatException catch (error) {
      debugPrint('Ignoring unreadable $key: $error');
      return null;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// A followed session changed: a turn that ended lets the phone's queue go.
  void _sessionsChanged() {
    _rememberModels();
    localQueue.drainAll();
    _notify();
  }

  void _linkChanged() {
    final current = Set<String>.of(link.onlineIds);
    for (final id in _lastOnline.difference(current)) {
      _subscriptions.connectionChanged(id, online: false);
      taskOutputs.connectionChanged(id, online: false);
    }
    for (final id in current.difference(_lastOnline)) {
      _subscriptions.connectionChanged(id, online: true);
      taskOutputs.connectionChanged(id, online: true);
      localQueue.reconnected(id);
    }
    final known = desktops.map((desktop) => desktop.id).toSet();
    for (final id in _knownDesktopIds.difference(known)) {
      _subscriptions.forget(id);
      taskOutputs.forget(id);
      localQueue.forget(id);
      icons.invalidateDesktop(id);
      _botCreations.remove(id);
      _discoveredAddresses.remove(id);
      _sessionStatuses.removeWhere((key, _) => key.$1 == id);
      notifications.forgetDesktop(id);
      bool belongs(String key) {
        final parts = jsonDecode(key);
        return parts is List && parts.firstOrNull == id;
      }

      _drafts.removeWhere((key, _) => belongs(key));
      _inputDrafts.removeWhere((key, _) => belongs(key));
      unawaited(_persistDrafts().catchError((Object _) {}));
      _sessionModels.removeWhere((key, _) => key.startsWith('$id/'));
      _modelMarks.removeWhere((key, _) => key.startsWith('$id/'));
      _followedModels.removeWhere((key, _) => key.startsWith('$id/'));
      _persistModels();
    }
    _knownDesktopIds = known;
    _lastOnline = current;
    for (final ref in sessions) {
      final key = (ref.desktopId, ref.session.id);
      final previous = _sessionStatuses[key];
      final next = ref.session;
      if (DesktopNotifications.turnNotice(previous, next)
          case final needsInput?) {
        unawaited(
          notifications.notifyTurn(
            desktopId: ref.desktopId,
            sessionId: next.id,
            sessionTitle: next.title,
            needsInput: needsInput,
            foreground: foreground,
            demo: demo,
            desktopName: desktopName(ref.desktopId),
          ),
        );
      }
      if (previous?.status == LinkSessionStatus.running &&
          next.status == LinkSessionStatus.idle) {
        _autoKeep(ref.desktopId, next.id);
      }
      _sessionStatuses[key] = next;
    }
    for (final ref in bots) {
      unawaited(
        notifications.notifyBot(
          ref.desktopId,
          ref.bot,
          foreground: foreground,
          demo: demo,
        ),
      );
    }
    _rememberModels();
    localQueue.drainAll();
    _notify();
  }

  SessionBuffer buffer(String desktopId, String sessionId) =>
      _subscriptions.buffer(desktopId, sessionId);

  /// The cached buffer of a session, or null; never creates or subscribes.
  SessionBuffer? peekBuffer(String desktopId, String sessionId) =>
      _subscriptions.peek(desktopId, sessionId);

  void _event(DesktopEvent event) {
    if (_disposed) return;
    if (event.name == LinkEvents.session) {
      _subscriptions.accept(event.desktopId, event.params);
    } else if (event.name == LinkEvents.output) {
      taskOutputs.accept(event.desktopId, event.params);
    } else if (event.name == LinkEvents.resync) {
      if (event.params case {'session': final String session}) {
        unawaited(_subscriptions.refresh(event.desktopId, session));
      }
    }
  }

  Future<Object?> request(
    String desktopId,
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    if (demo) {
      final result = await _demo!.call(desktopId, method, params);
      _notify();
      return result;
    }
    if (!isOnline(desktopId)) {
      throw StateError(
        tr('电脑不在线；操作未发送。', 'Desktop is offline; the operation was not sent.'),
      );
    }
    return link.call(desktopId, method, params);
  }

  BotProfileSaver botProfileSaver(String desktopId, {LinkBot? bot}) {
    if (bot != null) {
      return BotProfileSaver(request: request, desktopId: desktopId, bot: bot);
    }
    final existing = _botCreations[desktopId];
    if (existing != null &&
        (existing.botId == null ||
            existing.busy ||
            existing.creationUnconfirmed)) {
      return existing;
    }
    return _botCreations[desktopId] = BotProfileSaver(
      request: request,
      desktopId: desktopId,
    );
  }

  Future<LinkState> refreshDesktopState(String desktopId) async {
    final Object? result = demo
        ? await request(desktopId, LinkMethods.state)
        : await link.refreshState(desktopId);
    if (result is! Map || result['bots'] is! List) {
      throw const FormatException('电脑状态响应无效');
    }
    return LinkState.fromJson(Map<String, Object?>.from(result));
  }

  Future<void> openSession(String desktopId, String sessionId) {
    // 先记下看过，再算正在看：正在看的不算未读，就不会再写进存储。
    _markSessionSeen(desktopId, sessionId);
    final key = '$desktopId/$sessionId';
    _viewing[key] = (_viewing[key] ?? 0) + 1;
    return _subscriptions.retain(desktopId, sessionId);
  }

  Future<void> refreshSession(String desktopId, String sessionId) =>
      _subscriptions.refresh(desktopId, sessionId);

  Future<void> closeSession(String desktopId, String sessionId) {
    final key = '$desktopId/$sessionId';
    if ((_viewing[key] ?? 0) <= 1) {
      _viewing.remove(key);
    } else {
      _viewing[key] = _viewing[key]! - 1;
    }
    // 开着的时候做完的，关掉时也算看过了。
    _markSessionSeen(desktopId, sessionId);
    return _subscriptions.release(
      desktopId,
      sessionId,
      online: isOnline(desktopId),
    );
  }

  /// 做完还没看：手机上看过之后，要它再有更新才算。
  bool sessionUnread(SessionRef ref) {
    if (!ref.session.unread) return false;
    final key = '${ref.desktopId}/${ref.session.id}';
    // 正开在前台屏幕上的，做完时就看着，不算没看；沉浸模式下它一直开着。
    if (foreground && _viewing.containsKey(key)) return false;
    final seen = _seenSessions[key];
    return seen == null || ref.session.updatedAt.millisecondsSinceEpoch > seen;
  }

  /// [refs] 里各状态的条数：还在跑、卡在要批准或回答、做完没看。
  /// 列表上的「运行中 · 待处理 · 已完成」和底下的红点数都从这里取：
  /// 什么算做完、什么算没看，只有这里一处。
  ({int running, int needsInput, int done}) countByStatus(
    Iterable<SessionRef> refs,
  ) {
    var running = 0, needsInput = 0, done = 0;
    for (final ref in refs) {
      switch (ref.session.status) {
        case LinkSessionStatus.running:
          running++;
        case LinkSessionStatus.needsInput:
          needsInput++;
        case LinkSessionStatus.idle:
          if (sessionUnread(ref)) done++;
      }
    }
    return (running: running, needsInput: needsInput, done: done);
  }

  /// [desktopId] 上等着用户的对话：一共几条，其中几条卡在要批准或回答。
  /// 底部标签和切换电脑面板都按这个数，两处不会各说各的。
  ({int waiting, int needsInput}) awaitingOn(String? desktopId) {
    final counts = countByStatus(
      sessions.where((ref) => ref.desktopId == desktopId),
    );
    // 卡在要批准的，加上做完没看的；还在跑的不算。
    return (
      waiting: counts.needsInput + counts.done,
      needsInput: counts.needsInput,
    );
  }

  /// The model [ref] runs on: as the phone follows it, else as the desktop
  /// lists it, else as last seen; null when never known.
  SessionModel? sessionModel(SessionRef ref) {
    final live = _liveModel(ref);
    final kept = _sessionModels['${ref.desktopId}/${ref.session.id}'];
    // 只知道 id 时，用记下的那份同一个模型的名字。
    if (live == null || (live.label == live.id && kept?.id == live.id)) {
      return kept;
    }
    return live;
  }

  SessionModel? _liveModel(SessionRef ref) =>
      _followedModel(ref) ??
      switch (ref.session.model) {
        final String id when id.isNotEmpty => _modelOption(ref.desktopId, id),
        _ => null,
      };

  /// The model [ref]'s model menu has picked, while the phone follows it.
  SessionModel? _followedModel(SessionRef ref) {
    final buffer = peekBuffer(ref.desktopId, ref.session.id);
    for (final choice in buffer?.choices ?? const <LinkChoice>[]) {
      if (choice.kind == 'model' && choice.selected != null) {
        return _modelOption(ref.desktopId, choice.selected!, [choice]);
      }
    }
    return null;
  }

  /// When [desktopId]'s [sessionId] was switched to a model on another
  /// upstream, and to which; oldest first.
  List<({DateTime at, String label})> modelMarks(
    String desktopId,
    String sessionId,
  ) => _modelMarks['$desktopId/$sessionId'] ?? const [];

  /// Model [id] as [desktopId] lists it in its model menus ([choices], else
  /// those of its conversations the phone follows): its name and upstream.
  /// The list only sends the id; one not listed keeps it as its name.
  SessionModel _modelOption(
    String desktopId,
    String id, [
    Iterable<LinkChoice>? choices,
  ]) {
    choices ??= [
      for (final ref in sessions)
        if (ref.desktopId == desktopId)
          ...?peekBuffer(desktopId, ref.session.id)?.choices,
    ];
    for (final choice in choices) {
      if (choice.kind != 'model') continue;
      for (final option in choice.options) {
        if (option.id == id) {
          return (
            id: id,
            label: option.label,
            provider: option.group,
            providerLabel: option.groupLabel,
          );
        }
      }
    }
    return (id: id, label: id, provider: null, providerLabel: null);
  }

  /// Keeps the models known now for when they no longer are.
  void _rememberModels() {
    var changed = false;
    for (final ref in sessions) {
      final key = '${ref.desktopId}/${ref.session.id}';
      if (_followedModel(ref) case final now?) {
        final before = _followedModels[key];
        _followedModels[key] = now;
        // 同一个上游里换，Claude Code 自己会说；换了上游才要手机记。
        if (before != null &&
            before.id != now.id &&
            before.provider != null &&
            now.provider != null &&
            before.provider != now.provider) {
          final marks = _modelMarks[key] ??= [];
          marks.add((at: DateTime.now(), label: now.label));
          if (marks.length > _marksKept) marks.removeAt(0);
          changed = true;
        }
      }
      final model = _liveModel(ref);
      if (model == null || _sessionModels[key] == model) continue;
      // 电脑只给了 id 时，别盖掉以前记下的带名字和上游的那份。
      if (model.label == model.id && _sessionModels[key]?.id == model.id) {
        continue;
      }
      _sessionModels
        ..remove(key)
        ..[key] = model;
      changed = true;
    }
    if (!changed) return;
    while (_sessionModels.length > _modelsKept) {
      _sessionModels.remove(_sessionModels.keys.first);
    }
    _modelMarks.removeWhere((key, _) => !_sessionModels.containsKey(key));
    _persistModels();
  }

  void _persistModels() {
    final snapshot = jsonEncode({
      for (final MapEntry(:key, :value) in _sessionModels.entries)
        key: {
          'id': value.id,
          'label': value.label,
          'provider': ?value.provider,
          'providerLabel': ?value.providerLabel,
        },
    });
    final marks = jsonEncode({
      for (final MapEntry(:key, :value) in _modelMarks.entries)
        key: [
          for (final mark in value)
            [mark.at.millisecondsSinceEpoch, mark.label],
        ],
    });
    // 依次写，晚记的不会被早记的盖掉；写失败只影响重启后的记忆。
    _modelWrites = _modelWrites
        .then((_) => _store.write('model_marks', marks))
        .then((_) => _store.write('session_models', snapshot))
        .catchError((Object error) {
          debugPrint('Could not save session models: $error');
        });
  }

  void _markSessionSeen(String desktopId, String sessionId) {
    final current = sessions;
    final ref = current
        .where(
          (ref) => ref.desktopId == desktopId && ref.session.id == sessionId,
        )
        .firstOrNull;
    if (ref == null || !sessionUnread(ref)) return;
    _seenSessions['$desktopId/$sessionId'] =
        ref.session.updatedAt.millisecondsSinceEpoch;
    final stillUnread = {
      for (final other in current)
        if (other.session.unread) '${other.desktopId}/${other.session.id}',
    };
    _seenSessions.removeWhere((key, _) => !stillUnread.contains(key));
    final snapshot = jsonEncode(_seenSessions);
    // 依次写，晚记的不会被早记的盖掉；写失败只影响重启后的记忆。
    _seenWrites = _seenWrites
        .then((_) => _store.write('seen_sessions', snapshot))
        .catchError((Object error) {
          debugPrint('Could not save seen sessions: $error');
        });
    // 打开页面时正在构建，等这一帧建完再通知列表。
    scheduleMicrotask(_notify);
  }

  Future<void> loadEarlier(String desktopId, String sessionId) =>
      _subscriptions.earlier(desktopId, sessionId);

  Future<String?> sendMessage(
    String desktopId, {
    String? session,
    String? project,
    String? bot,
    required String text,
    List<Map<String, Object?>> images = const [],
    List<String> mentions = const [],
    bool now = false,
    String? id,
  }) async {
    final result = objectMap(
      await request(desktopId, LinkMethods.send, {
        'bot': ?bot,
        if (session != null && bot == null) 'session': session,
        'project': ?project,
        'text': text,
        if (images.isNotEmpty) 'images': images,
        if (mentions.isNotEmpty) 'mentions': mentions,
        if (now) 'now': true,
        'id': ?id,
      }),
    );
    final actual = result['session'];
    if (actual is String) {
      if (demo) await refreshSession(desktopId, actual);
      return actual;
    }
    return null;
  }

  String _draftKey(String desktopId, String sessionId) =>
      jsonEncode([desktopId, sessionId]);
  InputDraft inputDraft(
    String desktopId,
    String sessionId, {
    String? legacySessionId,
  }) {
    final key = _draftKey(desktopId, sessionId);
    if (_inputDrafts.containsKey(key)) return _inputDrafts[key]!;
    if (_drafts.containsKey(key)) return InputDraft.fromStored(_drafts[key]);
    if (legacySessionId != null && legacySessionId != sessionId) {
      return inputDraft(desktopId, legacySessionId);
    }
    return const InputDraft();
  }

  String draft(String desktopId, String sessionId) =>
      inputDraft(desktopId, sessionId).text;

  Future<void> saveInputDraft(
    String desktopId,
    String sessionId,
    InputDraft draft,
  ) {
    _inputDrafts[_draftKey(desktopId, sessionId)] = draft;
    return setDraft(desktopId, sessionId, draft.text);
  }

  Future<void> setDraft(String desktopId, String sessionId, String text) async {
    final key = _draftKey(desktopId, sessionId);
    final current = _inputDrafts[key];
    final draft = current?.text == text ? current! : InputDraft(text: text);
    _inputDrafts[key] = draft;
    if (draft.isEmpty && !sessionId.startsWith('bot:')) {
      _drafts.remove(key);
    } else {
      // Bot 的空值是用户已清空的标记，不能回退旧会话而复活内容。
      _drafts[key] = draft.toStored();
    }
    await _persistDrafts();
  }

  Future<void> _persistDrafts() {
    final snapshot = jsonEncode(_drafts);
    final write = _draftWrites.then((_) => _store.write('drafts', snapshot));
    // 链可继续，调用者仍收到本次写入错误。
    _draftWrites = write.catchError((Object _) {});
    return write;
  }

  /// Whether [ref] is shown on the home list, beside the projects.
  bool onHome(SessionRef ref) =>
      settings.homeSessions.contains((ref.desktopId, ref.session.id));

  /// Shows [ref] on the home list, or no longer.
  Future<void> setOnHome(SessionRef ref, bool shown) async {
    final key = (ref.desktopId, ref.session.id);
    if (shown) {
      settings.homeSessions.add(key);
    } else {
      settings.homeSessions.remove(key);
    }
    _notify();
    await saveSettings();
  }

  bool botPinned(BotRef ref) =>
      settings.pinnedBots.contains((ref.desktopId, ref.bot.id));

  Future<void> setBotPinned(BotRef ref, bool pinned) async {
    final key = (ref.desktopId, ref.bot.id);
    if (pinned) {
      settings.pinnedBots.add(key);
    } else {
      settings.pinnedBots.remove(key);
    }
    _notify();
    await saveSettings();
  }

  Future<void> saveSettings() async {
    _languageFromStore = settings.language;
    await _store.write('settings', jsonEncode(settings.toJson()));
    _notify();
  }

  Future<void> syncProfile() async {
    await saveSettings();
    for (final desktop in desktops.where((d) => isOnline(d.id))) {
      await request(desktop.id, LinkMethods.setMe, {
        'name': settings.name,
        'gender': settings.gender,
        'signature': settings.signature,
        if (settings.avatar case final image?)
          'picture': {'data': image, 'type': 'image/jpeg'},
      });
    }
  }

  void setForeground(bool value) {
    if (_disposed || foreground == value) return;
    foreground = value;
    if (!value) {
      _backgroundGenerations = {
        for (final desktop in desktops)
          desktop.id: link.connectionGenerationOf(desktop.id),
      };
      background.beginBackground();
    }
  }

  Future<void> _startBackgroundConnection() => background.start(
    title: tr('YCode 后台连接', 'YCode background connection'),
    body: tr(
      '保持电脑连接，接收任务更新。点按返回，或停止后台连接。',
      'Keeping the desktop connection for task updates. Tap to return, or stop background connection.',
    ),
    stopLabel: tr('停止', 'Stop'),
  );

  Future<void> setBackgroundConnection(bool enabled) async {
    if (!demo) {
      if (enabled) {
        await _startBackgroundConnection();
      } else {
        await background.stop();
      }
    }
    settings.keepBackgroundConnection = enabled;
    await saveSettings();
  }

  void _backgroundStopped() {
    if (_disposed || !settings.keepBackgroundConnection) return;
    settings.keepBackgroundConnection = false;
    unawaited(saveSettings().catchError(background.reportError));
  }

  /// 系统报告切网时先让 iroh 更新路径；保持同一连接，不盲目重开会话。
  void networkChanged() {
    if (demo || _disposed) return;
    _networkRevision++;
    _resumeMayReuse = false;
    background.invalidate();
    link.networkChanged();
    unawaited(_checkConnections());
    for (final desktop in desktops.where((d) => !isOnline(d.id))) {
      unawaited(link.retryNow(desktop.id).catchError((Object _) {}));
    }
  }

  Future<void> resume() {
    if (demo || _disposed) return Future<void>.value();
    link.networkChanged();
    final generations = {
      for (final desktop in desktops)
        desktop.id: link.connectionGenerationOf(desktop.id),
    };
    for (final desktop in desktops.where((d) => !isOnline(d.id))) {
      unawaited(link.retryNow(desktop.id).catchError((Object _) {}));
    }
    final continuous = background.finishBackground();
    if (_checkingConnections == null) {
      _resumeMayReuse = continuous;
      unawaited(discovery.refresh().catchError((Object _) {}));
    }
    return _resume(
      _checkConnections(),
      generations,
      reusable: _resumeMayReuse ? Map.of(_backgroundGenerations) : const {},
      networkRevision: _networkRevision,
    );
  }

  Future<void> _checkConnections() => _checkingConnections ??= link
      .verifyConnections()
      .catchError((Object _) {})
      .whenComplete(() => _checkingConnections = null);

  Future<void> _resume(
    Future<void> checking,
    Map<String, int> generations, {
    required Map<String, int> reusable,
    required int networkRevision,
  }) async {
    await checking;
    if (_disposed) return;
    // 重连已恢复的订阅不再重开；仍在同步的会话由订阅层合并请求。
    await _subscriptions.refreshRetained(
      (id) =>
          isOnline(id) &&
          (generations[id] ?? 0) == link.connectionGenerationOf(id),
      keepCurrent: (id, _) =>
          networkRevision == _networkRevision &&
          reusable[id] != null &&
          reusable[id] == link.connectionGenerationOf(id),
    );
  }

  Future<void> haptic([String kind = 'tap']) async {
    if (!settings.haptics || demo) return;
    try {
      await const MethodChannel('local.baocode.mobile/platform')
          .invokeMethod<void>('haptic', {'kind': kind});
    } on MissingPluginException {
      /* Widget tests have no platform host. */
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _events?.cancel();
    background.removeListener(_notify);
    background.dispose();
    _subscriptions.dispose();
    taskOutputs.dispose();
    localQueue.dispose();
    link.removeListener(_linkChanged);
    discovery.removeListener(_discoveryChanged);
    discovery.dispose();
    link.dispose();
    super.dispose();
  }
}
