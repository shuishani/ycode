import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bao_link/bao_link_io.dart';
import 'package:flutter/foundation.dart';

import 'link_store.dart';
import 'desktop_address.dart';
import '../state/app_state.dart';

export 'link_store.dart';

class PairingStorageException implements Exception {
  const PairingStorageException();

  @override
  String toString() => '取消配对未完成：信任记录回滚失败，请检查已配对的电脑。';
}

/// What the user is told of a desktop's connection.
enum DesktopLinkStatus { online, connecting, offline, needsPairing }

class KeptDesktop {
  const KeptDesktop({
    required this.id,
    required this.name,
    required this.publicKey,
    this.addresses = const [],
    this.relays = const [],
    this.direct = false,
    this.relaysPublished = false,
    this.needsPairing = false,
    this.renamed = false,
    this.system,
    this.kind,
    this.laptop,
    this.pairedAt,
  });

  final String id;
  final String name;

  /// [name] 是用户在手机上改的：电脑重连时公布的名字不再盖掉它。
  final bool renamed;

  /// 电脑自己怎么说：它的系统（Windows 11 Home China 这样），和它的型号。
  /// 只有连上过才知道，所以跟着保存。改过名也不影响这两个。
  final String? system;
  final String? kind;

  /// 电脑自己报的是不是笔记本；还没连上过时为 null。
  final bool? laptop;

  /// 这台是什么时候和手机配上对的；旧记录没有这一天。
  final DateTime? pairedAt;
  final String publicKey;
  final List<String> addresses;

  /// 电脑公布的中继，或电脑尚未公布策略时旧版本留下的提示。
  final List<String> relays;

  /// 电脑只走直连：无条件忽略 [relays]，拨号与端点绑定都不使用中继。
  final bool direct;

  /// [relays] 来自电脑的明确公布。此时空列表表示电脑没有中继，不能补内置列表。
  final bool relaysPublished;
  final bool needsPairing;

  /// 拨号与共享端点实际使用的中继；只有完全没有策略信息时才回退内置列表。
  List<String> get dialRelays => direct
      ? const []
      : relays.isNotEmpty || relaysPublished
      ? relays
      : defaultLinkRelays;

  LinkAddress get address =>
      LinkAddress(id, relays: dialRelays, addrs: addresses);

  factory KeptDesktop.fromJson(Map<String, Object?> json) {
    final key = json['publicKey'] as String;
    final bytes = decodeKey(key);
    final id = json['id'] as String;
    final legacy = json['kind'] != LinkIdentity.kind;
    if (bytes.length != 32 || (!legacy && deviceIdOf(bytes) != id)) {
      throw const FormatException('Desktop identity does not match its key');
    }
    return KeptDesktop(
      id: id,
      name: json['name'] as String,
      publicKey: key,
      addresses: List<String>.unmodifiable(
        (json['addresses'] as List? ?? const []).cast<String>(),
      ),
      relays: List<String>.unmodifiable(
        (json['relays'] as List? ?? const []).cast<String>(),
      ),
      direct: json['direct'] == true,
      relaysPublished: json['relaysPublished'] == true,
      needsPairing: legacy || json['needsPairing'] == true,
      renamed: json['renamed'] == true,
      system: json['system'] as String?,
      // `kind` here is the record's format, not the desktop's: its own is kept
      // as `desktopKind`.
      kind: json['desktopKind'] as String?,
      laptop: json['laptop'] is bool ? json['laptop'] as bool : null,
      pairedAt: switch (json['pairedAt']) {
        final int at => DateTime.fromMillisecondsSinceEpoch(at),
        _ => null,
      },
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'publicKey': publicKey,
    'addresses': addresses,
    'relays': relays,
    'direct': direct,
    'relaysPublished': relaysPublished,
    'kind': needsPairing ? 'legacy' : LinkIdentity.kind,
    'needsPairing': needsPairing,
    if (renamed) 'renamed': true,
    'system': ?system,
    'desktopKind': ?kind,
    'laptop': ?laptop,
    'pairedAt': ?pairedAt?.millisecondsSinceEpoch,
  };

  KeptDesktop copyWith({
    String? name,
    List<String>? addresses,
    List<String>? relays,
    bool? direct,
    bool? relaysPublished,
    bool? needsPairing,
    bool? renamed,
    String? system,
    String? kind,
    bool? laptop,
    DateTime? pairedAt,
  }) => KeptDesktop(
    id: id,
    name: name ?? this.name,
    publicKey: publicKey,
    addresses: List.unmodifiable(addresses ?? this.addresses),
    relays: List.unmodifiable(relays ?? this.relays),
    direct: direct ?? this.direct,
    relaysPublished: relaysPublished ?? this.relaysPublished,
    needsPairing: needsPairing ?? this.needsPairing,
    renamed: renamed ?? this.renamed,
    system: system ?? this.system,
    kind: kind ?? this.kind,
    laptop: laptop ?? this.laptop,
    pairedAt: pairedAt ?? this.pairedAt,
  );
}

/// 按官方 DeviceInfo 的序列化约定解析电脑公布的中继策略：direct 只在为 true
/// 时输出，relays 始终输出。字段缺失表示旧端，沿用手机已有的策略。
KeptDesktop _followPolicy(KeptDesktop desktop, Map<String, Object?> device) {
  final direct = device['direct'];
  final relays = device['relays'];
  if (direct == true) {
    return desktop.copyWith(
      direct: true,
      relays: const [],
      relaysPublished: false,
    );
  }
  if (relays is List) {
    return desktop.copyWith(
      direct: false,
      relays: relays.whereType<String>().toList(),
      relaysPublished: true,
    );
  }
  return direct == false ? desktop.copyWith(direct: false) : desktop;
}

class DesktopEvent {
  const DesktopEvent(this.desktopId, this.name, this.params);
  final String desktopId;
  final String name;
  final Object? params;
}

class PairingAttempt {
  PairingAttempt._(
    this._owner,
    this._peer,
    this._dialed,
    KeptDesktop desktop,
    this.safetyCode,
    this._needsConfirmation,
  ) : _desktop = desktop,
      desktopId = desktop.id,
      name = desktop.name;

  final PhoneLink _owner;
  final LinkPeer _peer;
  final KeptDesktop _dialed;
  final KeptDesktop _desktop;
  final bool _needsConfirmation;
  bool _confirming = false;
  bool _rollbackFailed = false;
  final _settled = Completer<void>();
  final String desktopId;
  final String name;
  final List<String> safetyCode;
}

/// 测试注入内存网络，运行时使用官方 iroh 传输；RPC 与配对流程共用。
typedef PhoneLinkNodeFactory = Future<LinkNode> Function(
  LinkIdentity identity,
  List<String> relays,
);

class PhoneLink extends ChangeNotifier {
  PhoneLink({
    required this._store,
    PhoneLinkNodeFactory? nodeFactory,
    DesktopAddressLookup? addressLookup,
  }) : _nodeFactory = nodeFactory ?? _bindNode,
       _addressLookup = addressLookup ?? InternetAddress.lookup;

  static Future<LinkNode> _bindNode(
    LinkIdentity identity,
    List<String> relays,
  ) => IrohLinkNode.bind(identity: identity, relays: relays);

  final LinkStore _store;
  final PhoneLinkNodeFactory _nodeFactory;
  final DesktopAddressLookup _addressLookup;
  LinkNode? _node;
  List<String> _nodeRelays = const [];
  Future<void> _nodeQueue = Future.value();
  final _inflight = <KeptDesktop>[];
  final _desktops = <String, KeptDesktop>{};
  final _peers = <String, LinkPeer>{};
  final _replies = <LinkPeer, int>{};
  final _verifying = <LinkPeer, Future<void>>{};
  int _requestSerial = 0;
  final _paths = <String, LinkPath>{};
  final _pathSubscriptions = <String, StreamSubscription<LinkPath>>{};
  final _opening = <LinkPeer>{};
  final _states = <String, Map<String, Object?>>{};
  final _attempts = <PairingAttempt>{};
  final _timers = <String, Timer>{};
  final _dialing = <String>{};
  final _seen = <String, int>{};
  final _delays = <String, int>{};
  final _generations = <String, int>{};
  final _unsavedAddresses = <String>{};
  final _connecting = <String>{};
  final _events = StreamController<DesktopEvent>.broadcast();
  LinkIdentity? _identity;
  Future<void>? _initializing;
  Future<void> _writes = Future.value();
  bool _disposed = false;

  List<KeptDesktop> get desktops => List.unmodifiable(_desktops.values);
  Set<String> get onlineIds => Set.unmodifiable(_peers.keys);

  /// 本地拨号代次：恢复期间已重建连接的订阅不必再次打开。
  int connectionGenerationOf(String desktopId) => _generations[desktopId] ?? 0;

  /// The way the connection to [desktopId] runs now; [LinkPath.none] when
  /// it is not connected or the path is not known yet.
  LinkPath pathOf(String desktopId) => _paths[desktopId] ?? LinkPath.none;

  Map<String, Map<String, Object?>> get states => Map.unmodifiable(_states);
  Stream<DesktopEvent> get events => _events.stream;

  /// Automatic retries still read as connecting until they have failed a
  /// few times ([_retry] doubles the delay from 2 seconds each time).
  static const _offlineAfterDelay = 16;

  DesktopLinkStatus statusOf(String desktopId) {
    final desktop = _desktops[desktopId];
    if (desktop == null) return DesktopLinkStatus.offline;
    if (desktop.needsPairing) return DesktopLinkStatus.needsPairing;
    if (_connecting.contains(desktopId)) return DesktopLinkStatus.connecting;
    if (_peers.containsKey(desktopId)) return DesktopLinkStatus.online;
    final retrying =
        _timers.containsKey(desktopId) &&
        (_delays[desktopId] ?? 0) < _offlineAfterDelay;
    return retrying ? DesktopLinkStatus.connecting : DesktopLinkStatus.offline;
  }

  /// Back from the background a connection may be dead without anyone having
  /// noticed yet (the idle timeout is 20 seconds): asks each desktop, and
  /// connects anew to one that does not answer in [timeout]. Shows as
  /// connecting only past [quietFor], so a healthy check does not flicker.
  Future<void> verifyConnections({
    Duration timeout = const Duration(seconds: 4),
    Duration quietFor = const Duration(milliseconds: 800),
  }) async {
    await Future.wait([
      for (final MapEntry(key: id, value: peer) in _peers.entries.toList())
        _verifying.putIfAbsent(
          peer,
          () => _verify(id, peer, timeout, quietFor).whenComplete(() {
            _verifying.remove(peer);
          }),
        ),
    ]);
  }

  Future<void> _verify(
    String id,
    LinkPeer peer,
    Duration timeout,
    Duration quietFor,
  ) async {
    bool current() => !_disposed && _peers[id] == peer;
    final request = ++_requestSerial;
    final showing = Timer(quietFor, () {
      if (current() && _connecting.add(id)) _changed();
    });
    var alive = true;
    try {
      final state = _map(await peer.probe(timeout));
      _replied(id, peer, request);
      if (current()) {
        _states[id] = Map.unmodifiable(state);
        _adoptPolicy(id, state);
      }
    } on LinkRemoteException {
      // It answered, whatever it answered: the connection is alive.
      _replied(id, peer, request);
    } on TimeoutException {
      // 只认探测后发起的往返，不能用旧请求的迟到回复保活。
      alive = (_replies[peer] ?? 0) > request;
    } on Object {
      alive = false;
    } finally {
      showing.cancel();
    }
    if (!current()) return;
    if (alive) {
      _connecting.remove(id);
      _changed();
      return;
    }
    await reconnect(id);
  }

  bool hasUnsavedAddress(String desktopId) =>
      _unsavedAddresses.contains(desktopId);

  void _checkAlive() {
    if (_disposed) throw StateError('PhoneLink is disposed');
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() {
    _checkAlive();
    return _initializing ??= _load();
  }

  Future<void> _load() async {
    final storedIdentity = await _store.read('identity');
    final keptIdentity = storedIdentity == null
        ? null
        : LinkIdentity.fromJson(
            Map<String, Object?>.from(jsonDecode(storedIdentity) as Map),
          );
    final identity = keptIdentity ?? LinkIdentity.generate();
    final saved = await _store.read('desktops');
    try {
      final seen = await _store.read('seen');
      if (seen != null) {
        for (final MapEntry(:key, :value)
            in (jsonDecode(seen) as Map).entries) {
          if (key is String && value is int) _seen[key] = value;
        }
      }
    } on Object {
      /* A lost or corrupt last-seen record only hides 「已离线 N 分钟」. */
    }
    final loaded = <KeptDesktop>[
      if (saved != null)
        for (final entry in jsonDecode(saved) as List)
          KeptDesktop.fromJson(Map<String, Object?>.from(entry as Map)),
    ];
    if (keptIdentity == null) {
      // 先持久化失效的信任，再更换身份，进程中断后也不能自动信任旧记录。
      for (var i = 0; i < loaded.length; i++) {
        loaded[i] = loaded[i].copyWith(needsPairing: true);
      }
      if (loaded.isNotEmpty) {
        await _store.write(
          'desktops',
          jsonEncode(loaded.map((d) => d.toJson()).toList()),
        );
      }
      await _store.write('identity', jsonEncode(identity.toJson()));
    }
    if (_disposed) return;
    _identity = identity;
    for (final desktop in loaded) {
      _desktops[desktop.id] = desktop;
    }
    _changed();
    for (final id in _desktops.keys.toList()) {
      unawaited(reconnect(id));
    }
  }

  Map<String, Object?> get _hello => {
    'name': 'YCode',
    'system': Platform.operatingSystem,
  };

  /// 共享端点的中继 = 所有已信任电脑与待确认配对中非 direct 者的中继并集；
  /// 全部 direct 时为空，没有任何成员时返回 null（无需端点）。
  List<String>? _desiredRelays() {
    final members = <String, KeptDesktop>{
      for (final desktop in _desktops.values)
        if (!desktop.needsPairing) desktop.id: desktop,
      for (final desktop in _inflight) desktop.id: desktop,
      for (final attempt in _attempts) attempt._dialed.id: attempt._dialed,
    };
    if (members.isEmpty) return null;
    return {
      for (final desktop in members.values)
        if (!desktop.direct) ...desktop.dialRelays,
    }.toList();
  }

  static bool _sameRelays(List<String> a, List<String> b) =>
      a.length == b.length && a.toSet().containsAll(b);

  Future<T> _serialized<T>(Future<T> Function() action) {
    final run = _nodeQueue.then((_) => action());
    _nodeQueue = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  Future<LinkNode> _getNode() async {
    final node = await _serialized(_ensureNode);
    if (node != null) return node;
    _checkAlive();
    throw const LinkClosedException('没有需要连接的电脑');
  }

  /// 在串行队列内使端点与当前策略一致：配置变化时先关闭旧端点再绑定新的，
  /// 迟到的节点若已被更新的策略取代则立即关闭。被替换端点上的电脑会重新
  /// 连接并认证，进行中的写请求随旧连接失败，绝不重放。
  Future<LinkNode?> _ensureNode() async {
    final replaced = <String>{};
    while (true) {
      _checkAlive();
      final want = _desiredRelays();
      final current = _node;
      if (want == null) {
        await _dropNode();
        return null;
      }
      if (current != null && _sameRelays(_nodeRelays, want)) return current;
      if (current != null) replaced.addAll(_peers.keys);
      await _dropNode();
      _checkAlive();
      final node = await _nodeFactory(_identity!, want);
      if (_disposed) {
        await node.close();
        _checkAlive();
      }
      final latest = _desiredRelays();
      if (latest == null || !_sameRelays(want, latest)) {
        await node.close();
        continue;
      }
      _node = node;
      _nodeRelays = want;
      for (final id in replaced) {
        unawaited(reconnect(id));
      }
      return node;
    }
  }

  Future<void> _dropNode() async {
    final node = _node;
    if (node == null) return;
    _node = null;
    await node.close();
  }

  /// 策略输入（已保存电脑、待确认配对）变化后，让已存在的端点跟上。
  void _syncNode() {
    if (_disposed || _node == null) return;
    unawaited(
      _serialized(_ensureNode).then<void>((_) {}, onError: (Object _) {}),
    );
  }

  void networkChanged() => _node?.networkChanged();

  Future<LinkPeer> _open(LinkAddress address) async {
    final node = await _getNode();
    _checkAlive();
    final addresses = await resolveDesktopAddresses(
      address.addrs,
      lookup: _addressLookup,
      allowEmpty: address.relays.isNotEmpty,
    );
    _checkAlive();
    final connection = await node.connect(
      LinkAddress(address.id, relays: address.relays, addrs: addresses),
    );
    if (_disposed || connection.remote != address.id) {
      connection.close();
      _checkAlive();
      throw const LinkClosedException('设备公钥与配对记录不匹配');
    }
    final LinkPeer peer;
    try {
      peer = await LinkPeer.connect(connection, mirror: LinkSessionMirror());
    } catch (_) {
      connection.close();
      rethrow;
    }
    if (_disposed) {
      await peer.close();
      _checkAlive();
    }
    _opening.add(peer);
    unawaited(peer.done.then((_) => _opening.remove(peer)));
    return peer;
  }

  KeptDesktop _introduced(KeptDesktop desktop, Map<String, Object?> hello) {
    final device = hello['device'] is Map
        ? _map(hello['device'])
        : const <String, Object?>{};
    return _followPolicy(
      desktop.copyWith(
        // 用户自己起的名不动。
        name: desktop.renamed
            ? desktop.name
            : device['name'] as String? ?? desktop.name,
        system: switch (device['system']) {
          final String value when value.isNotEmpty => value,
          _ => desktop.system,
        },
        kind: switch (device['kind']) {
          final String value when value.isNotEmpty => value,
          _ => desktop.kind,
        },
        laptop: device['laptop'] is bool
            ? device['laptop'] as bool
            : desktop.laptop,
        addresses: {
          ...?(device['addrs'] as List?)?.whereType<String>(),
          ...desktop.addresses,
        }.toList(),
      ),
      device,
    );
  }

  void _adoptPolicy(String id, Map<String, Object?> state) {
    final desktop = _desktops[id];
    final device = state['device'];
    if (desktop == null || device is! Map) return;
    final next = _followPolicy(desktop, _map(device));
    if (jsonEncode(next.toJson()) == jsonEncode(desktop.toJson())) return;
    _desktops[id] = next;
    _changed();
    void settle({required bool saved}) {
      if (_disposed || !identical(_desktops[id], next)) return;
      if (saved) {
        _unsavedAddresses.remove(id);
      } else {
        _unsavedAddresses.add(id);
      }
      _changed();
    }

    unawaited(
      _save().then<void>(
        (_) => settle(saved: true),
        onError: (Object _) => settle(saved: false),
      ),
    );
    _syncNode();
  }

  Future<PairingAttempt> pair(String uri) async {
    await initialize();
    _checkAlive();
    final offer = PairingOffer.parse(uri);
    if (offer.expiredAt(DateTime.now())) {
      throw const FormatException('Pairing code has expired');
    }
    if (offer.key.length != 32 || offer.token.isEmpty) {
      throw const FormatException('Invalid pairing key or token');
    }
    final dialed = KeptDesktop(
      id: offer.id,
      name: offer.name,
      publicKey: encodeKey(offer.key),
      addresses: List.unmodifiable(offer.addrs),
      relays: offer.direct ? const [] : List.unmodifiable(offer.relays),
      direct: offer.direct,
    );
    final peer = await _dial(dialed);
    try {
      if (offer.expiredAt(DateTime.now())) {
        throw const FormatException('Pairing code has expired');
      }
      final reply = await peer.call(LinkMethods.hello, {
        ..._hello,
        'token': encodeKey(offer.token),
      });
      _checkAlive();
      final hello = _map(reply);
      final attempt = PairingAttempt._(
        this,
        peer,
        dialed,
        _introduced(dialed, hello),
        List.unmodifiable(safetyCode(offer.key, _identity!.publicKey)),
        hello['pairing'] == true,
      );
      _attempts.add(attempt);
      _inflight.remove(dialed);
      _opening.remove(peer);
      return attempt;
    } catch (_) {
      _inflight.remove(dialed);
      await peer.close();
      _syncNode();
      rethrow;
    }
  }

  /// 候选配对在拨号前就计入端点策略，避免先按默认中继绑定再改。
  Future<LinkPeer> _dial(KeptDesktop dialed) async {
    _inflight.add(dialed);
    try {
      return await _open(dialed.address);
    } catch (_) {
      _inflight.remove(dialed);
      _syncNode();
      rethrow;
    }
  }

  Future<PairingAttempt> pairNearby(LinkAdvert advert) async {
    await initialize();
    _checkAlive();
    // The advert's pairing flag can be stale (phones miss multicast updates):
    // the desktop's hello is what refuses when pairing is not open.
    if (advert.key.length != 32) {
      throw const FormatException('Invalid desktop key');
    }
    // 广播不带中继策略：已保存且策略已知的电脑沿用其策略；未知电脑，以及
    // 待重新配对或尚无任何策略的旧记录，在 hello 之前只走局域网地址，不猜
    // 内置中继。`dialed` 仅用于拨号与端点计算，从不持久化。
    final saved = _desktops[advert.id];
    final base = KeptDesktop(
      id: advert.id,
      name: advert.name,
      publicKey: encodeKey(advert.key),
      addresses: List.unmodifiable(advert.addrs),
      relays: saved?.relays ?? const [],
      direct: saved?.direct ?? false,
      relaysPublished: saved?.relaysPublished ?? false,
    );
    final knownPolicy =
        saved != null &&
        !saved.needsPairing &&
        (saved.direct || saved.relays.isNotEmpty || saved.relaysPublished);
    final dialed = knownPolicy
        ? base
        : base.copyWith(relays: const [], direct: false, relaysPublished: true);
    final peer = await _dial(dialed);
    try {
      final hello = _map(
        await peer.call(LinkMethods.hello, {..._hello, 'request': true}),
      );
      _checkAlive();
      final attempt = PairingAttempt._(
        this,
        peer,
        dialed,
        _introduced(base, hello),
        List.unmodifiable(safetyCode(advert.key, _identity!.publicKey)),
        hello['pairing'] == true,
      );
      _attempts.add(attempt);
      _inflight.remove(dialed);
      _opening.remove(peer);
      return attempt;
    } catch (_) {
      _inflight.remove(dialed);
      await peer.close();
      _syncNode();
      rethrow;
    }
  }

  Future<void> confirmPairing(PairingAttempt attempt) async {
    _checkAlive();
    if (attempt._owner != this ||
        !_attempts.contains(attempt) ||
        attempt._confirming) {
      throw StateError('Pairing attempt is no longer available');
    }
    attempt._confirming = true;
    try {
      // Nearby pairing can wait on desktop approval. UI keeps the attempt
      // visible during this bounded wait, and may cancel it at any point.
      if (attempt._needsConfirmation) {
        await attempt._peer.call(
          LinkMethods.confirm,
          const {},
          const Duration(minutes: 2),
        );
      }
      _checkAlive();
      if (!_attempts.contains(attempt)) {
        throw StateError('Pairing was cancelled');
      }
      final previous = _desktops[attempt.desktopId];
      // 重新配对不改最初配对的那一天。
      final paired = attempt._desktop.pairedAt == null
          ? attempt._desktop.copyWith(pairedAt: DateTime.now())
          : attempt._desktop;
      _desktops[attempt.desktopId] = paired;
      try {
        await _save();
      } catch (_) {
        if (identical(_desktops[attempt.desktopId], paired)) {
          if (previous == null) {
            _desktops.remove(attempt.desktopId);
          } else {
            _desktops[attempt.desktopId] = previous;
          }
        }
        rethrow;
      }
      if (_disposed || !_attempts.remove(attempt)) {
        // Cancellation can race a slow keychain write; do not leave trust behind.
        if (identical(_desktops[attempt.desktopId], paired)) {
          if (previous == null) {
            _desktops.remove(attempt.desktopId);
          } else {
            _desktops[attempt.desktopId] = previous;
          }
          try {
            await _save();
          } catch (_) {
            attempt._rollbackFailed = true;
            throw const PairingStorageException();
          }
        }
        await attempt._peer.close();
        throw StateError('Pairing was cancelled');
      }
      final wanted = _desiredRelays();
      if (wanted != null && !_sameRelays(_nodeRelays, wanted)) {
        // 电脑公布的策略与拨号时的临时策略不同：旧端点上的连接不能保留，
        // 关闭后经 reconnect 在新端点上重新认证，不重放任何请求。
        _changed();
        await attempt._peer.close();
        await reconnect(attempt.desktopId);
        return;
      }
      _attach(attempt.desktopId, attempt._peer);
      _changed();
      try {
        await _refreshState(attempt.desktopId, attempt._peer);
      } catch (_) {
        // Trust was confirmed and durably saved. A lost initial snapshot is
        // a connection failure, not a failed pairing; done schedules a retry.
        await attempt._peer.close();
      }
    } catch (_) {
      _attempts.remove(attempt);
      await attempt._peer.close();
      _syncNode();
      rethrow;
    } finally {
      attempt._settled.complete();
    }
  }

  Future<void> cancelPairing(PairingAttempt attempt) async {
    if (attempt._owner != this) return;
    if (_attempts.remove(attempt)) {
      await attempt._peer.close();
      _syncNode();
    }
    if (attempt._confirming) {
      // 取消必须等已开始的写入和回滚结束，不能提前宣称信任已撤销。
      await attempt._settled.future;
      if (attempt._rollbackFailed) throw const PairingStorageException();
    }
  }

  Future<Object?> call(
    String desktopId,
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    _checkAlive();
    final peer = _peers[desktopId];
    if (peer == null) throw const LinkClosedException();
    // Never replay RPCs: a lost answer does not mean a write did not happen.
    final request = ++_requestSerial;
    try {
      final result = await peer.call(method, params);
      _replied(desktopId, peer, request);
      return result;
    } on LinkRemoteException {
      _replied(desktopId, peer, request);
      rethrow;
    }
  }

  void _replied(String id, LinkPeer peer, int request) {
    if (!_disposed && _peers[id] == peer && request > (_replies[peer] ?? 0)) {
      _replies[peer] = request;
    }
  }

  /// 在线时复用既有认证连接；另开 hello 会让桌面关闭当前连接。
  Future<void> checkConnection(String desktopId) async {
    await initialize();
    _checkAlive();
    final desktop = _desktops[desktopId];
    if (desktop == null) {
      throw StateError(AppState.phrase('设备已移除', 'Device removed'));
    }
    if (desktop.needsPairing) {
      throw const LinkRemoteException(LinkErrors.unpaired, '请先重新配对');
    }
    if (!_peers.containsKey(desktopId)) {
      await reconnect(desktopId, reportFailure: true);
    }
    _checkAlive();
    final peer = _peers[desktopId];
    if (peer == null) throw const LinkClosedException();
    final request = ++_requestSerial;
    final reply = await peer.call(
      LinkMethods.state,
      const {},
      const Duration(seconds: 8),
    );
    _checkAlive();
    if (_peers[desktopId] != peer) throw const LinkClosedException();
    _replied(desktopId, peer, request);
    final state = _map(reply);
    if (state['projects'] is! List) {
      throw const FormatException('电脑状态响应无效');
    }
    _states[desktopId] = Map.unmodifiable(state);
    _changed();
    _adoptPolicy(desktopId, state);
  }

  /// [background]: one of [_retry]'s, which once it has failed a few times
  /// goes on unseen rather than flip the status every 30 seconds.
  Future<void> reconnect(
    String desktopId, {
    bool reportFailure = false,
    bool background = false,
  }) async {
    if (_disposed) return;
    await initialize();
    if (_disposed ||
        !_desktops.containsKey(desktopId) ||
        _desktops[desktopId]!.needsPairing) {
      return;
    }
    _timers.remove(desktopId)?.cancel();
    final generation = (_generations[desktopId] ?? 0) + 1;
    _generations[desktopId] = generation;
    bool current() =>
        !_disposed &&
        _desktops.containsKey(desktopId) &&
        _generations[desktopId] == generation;
    if (!background || (_delays[desktopId] ?? 0) < _offlineAfterDelay) {
      _connecting.add(desktopId);
    }
    final old = _peers.remove(desktopId);
    _dropPath(desktopId);
    if (old != null) {
      _markSeen(desktopId);
      await old.close();
    }
    _changed();
    LinkPeer? peer;
    _dialing.add(desktopId);
    try {
      final desktop = _desktops[desktopId]!;
      peer = await _open(desktop.address);
      if (!current()) {
        await peer.close();
        return;
      }
      final hello = _map(await peer.call(LinkMethods.hello, _hello));
      if (hello['pairing'] == true) {
        throw const LinkRemoteException(
          'unpaired',
          'Desktop no longer trusts this phone',
        );
      }
      if (!current()) {
        await peer.close();
        return;
      }
      final introduced = _introduced(desktop, hello);
      final changed =
          jsonEncode(introduced.toJson()) != jsonEncode(desktop.toJson());
      _desktops[desktopId] = introduced;
      if (changed || _unsavedAddresses.contains(desktopId)) {
        try {
          await _save();
          if (current()) _unsavedAddresses.remove(desktopId);
        } catch (_) {
          // 信任已持久化，地址提示写失败不能中断已认证连接；界面明确提示。
          if (current()) _unsavedAddresses.add(desktopId);
        }
      }
      if (!current()) {
        await peer.close();
        return;
      }
      _attach(desktopId, peer);
      _delays.remove(desktopId);
      _connecting.remove(desktopId);
      _changed();
      _syncNode();
      await _refreshState(desktopId, peer);
    } catch (_) {
      if (peer != null) await peer.close();
      if (current()) {
        _connecting.remove(desktopId);
        _retry(desktopId);
        _changed();
      }
      if (reportFailure) rethrow;
    } finally {
      if (current()) _dialing.remove(desktopId);
    }
  }

  void _attach(String id, LinkPeer peer) {
    _opening.remove(peer);
    final old = _peers[id];
    _peers[id] = peer;
    if (old != null && old != peer) unawaited(old.close());
    _trackPath(id, peer);
    _markSeen(id);
    peer.events.listen((event) {
      if (_disposed || _peers[id] != peer) return;
      if (event.name == LinkEvents.state && event.data is Map) {
        _states[id] = Map.unmodifiable(_map(event.data));
        _changed();
        _adoptPolicy(id, _states[id]!);
      }
      if (_disposed) return;
      _events.add(DesktopEvent(id, event.name, event.data));
      if (event.name == LinkEvents.unpaired) {
        unawaited(_forget(id, tellDesktop: false).catchError((Object _) {}));
      }
    });
    unawaited(
      peer.done.then((_) {
        _replies.remove(peer);
        if (_disposed || _peers[id] != peer) return;
        _peers.remove(id);
        _dropPath(id);
        _markSeen(id);
        _changed();
        _retry(id);
      }),
    );
  }

  Future<Map<String, Object?>> refreshState(String desktopId) async {
    _checkAlive();
    final peer = _peers[desktopId];
    if (peer == null) throw const LinkClosedException();
    await _refreshState(desktopId, peer);
    _checkAlive();
    if (_peers[desktopId] != peer || _states[desktopId] == null) {
      throw const LinkClosedException();
    }
    return _states[desktopId]!;
  }

  void _trackPath(String id, LinkPeer peer) {
    _dropPath(id);
    void set(LinkPath path) {
      if (_disposed || _peers[id] != peer) return;
      if (_paths[id] == path) return;
      _paths[id] = path;
      _changed();
    }

    try {
      _pathSubscriptions[id] = peer.connection.paths.listen(
        set,
        onError: (Object _) {},
      );
      unawaited(peer.connection.path().then(set, onError: (Object _) {}));
    } on Object {
      /* A connection without path reporting just shows no path. */
    }
  }

  void _dropPath(String id) {
    _paths.remove(id);
    final subscription = _pathSubscriptions.remove(id);
    if (subscription != null) unawaited(subscription.cancel());
  }

  Future<void> _refreshState(String id, LinkPeer peer) async {
    final before = _states[id];
    final request = ++_requestSerial;
    final state = _map(await peer.call(LinkMethods.state));
    _replied(id, peer, request);
    if (_disposed || _peers[id] != peer || !identical(_states[id], before)) {
      return;
    }
    _states[id] = Map.unmodifiable(state);
    _changed();
    _adoptPolicy(id, state);
  }

  /// When the phone last had a live connection to [desktopId]; kept under
  /// its own key so it never rides on the trusted desktops' writes.
  DateTime? lastSeenOf(String desktopId) => switch (_seen[desktopId]) {
    final int ms => DateTime.fromMillisecondsSinceEpoch(ms),
    _ => null,
  };

  void _markSeen(String id) {
    if (!_desktops.containsKey(id)) return;
    _seen[id] = DateTime.now().millisecondsSinceEpoch;
    final data = jsonEncode(_seen);
    unawaited(_store.write('seen', data).catchError((Object _) {}));
  }

  /// Tries an offline desktop now instead of waiting out the backoff.
  Future<void> retryNow(String desktopId) {
    if (_peers.containsKey(desktopId)) return Future.value();
    if (_dialing.contains(desktopId)) {
      // A quiet background dial: let the asker see it under way.
      if (_connecting.add(desktopId)) _changed();
      return Future.value();
    }
    _delays.remove(desktopId);
    return reconnect(desktopId);
  }

  void _retry(String id) {
    if (_disposed || !_desktops.containsKey(id) || _timers.containsKey(id)) {
      return;
    }
    final seconds = _delays[id] ?? 2;
    _delays[id] = (seconds * 2).clamp(2, 30).toInt();
    _timers[id] = Timer(Duration(seconds: seconds), () {
      _timers.remove(id);
      unawaited(reconnect(id, background: true));
    });
  }

  Future<void> forget(String desktopId) =>
      _forget(desktopId, tellDesktop: true);

  Future<void> _forget(String id, {required bool tellDesktop}) async {
    _checkAlive();
    _generations[id] = (_generations[id] ?? 0) + 1;
    _timers.remove(id)?.cancel();
    _delays.remove(id);
    _connecting.remove(id);
    _desktops.remove(id);
    _states.remove(id);
    _unsavedAddresses.remove(id);
    final peer = _peers.remove(id);
    _dropPath(id);
    for (final attempt in _attempts.toList()) {
      if (attempt.desktopId == id) await cancelPairing(attempt);
    }
    _changed();
    // Persist local removal even if the remote is offline or unpair fails.
    // Attach an error handler immediately while remote cleanup is in flight.
    Object? saveError;
    StackTrace? saveStack;
    final saved = _save().catchError((Object error, StackTrace stack) {
      saveError = error;
      saveStack = stack;
    });
    if (peer != null) {
      try {
        if (tellDesktop) {
          await peer.call(
            LinkMethods.unpair,
            const {},
            const Duration(seconds: 2),
          );
        }
      } catch (_) {
        // Best effort, never reconnect just to unpair.
      } finally {
        await peer.close();
      }
    }
    _syncNode();
    await saved;
    if (saveError != null) Error.throwWithStackTrace(saveError!, saveStack!);
  }

  /// 给这台电脑起个本地名字：只存手机上，电脑那边不知道，重连也不会被它
  /// 公布的设备名盖掉（[KeptDesktop.renamed]）。
  Future<void> renameDesktop(String desktopId, String name) async {
    _checkAlive();
    final desktop = _desktops[desktopId];
    if (desktop == null) throw StateError('Unknown desktop: $desktopId');
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError.value(name, 'name', 'Empty');
    final updated = desktop.copyWith(name: trimmed, renamed: true);
    _desktops[desktopId] = updated;
    try {
      await _save();
    } catch (_) {
      if (identical(_desktops[desktopId], updated)) {
        _desktops[desktopId] = desktop;
      }
      rethrow;
    }
    _changed();
  }

  Future<void> updateAddresses(String desktopId, List<String> addresses) async {
    _checkAlive();
    final desktop = _desktops[desktopId];
    if (desktop == null) throw StateError('Unknown desktop: $desktopId');
    final cleaned = addresses.map(normalizeAddress).toSet().toList();
    final updated = desktop.copyWith(addresses: cleaned);
    _desktops[desktopId] = updated;
    try {
      await _save();
    } catch (_) {
      if (identical(_desktops[desktopId], updated)) {
        _desktops[desktopId] = desktop;
      }
      rethrow;
    }
    _changed();
  }

  static String normalizeAddress(String text) =>
      DesktopAddress.parse(text).normalized;

  /// This phone's key as the desktops show it; null until loaded.
  String? get fingerprint => _identity?.fingerprint;

  /// A new key for this phone. Every desktop knew the old one, so each is
  /// to be paired again; those connected are told to forget this phone
  /// first (best effort). Trust is withdrawn before the key changes, so an
  /// interrupted reset leaves nothing trusted on the old key.
  Future<void> resetIdentity() async {
    await initialize();
    _checkAlive();
    for (final attempt in _attempts.toList()) {
      await cancelPairing(attempt);
    }
    final peers = <LinkPeer>[];
    for (final id in _desktops.keys.toList()) {
      _generations[id] = (_generations[id] ?? 0) + 1;
      _timers.remove(id)?.cancel();
      _delays.remove(id);
      _connecting.remove(id);
      _desktops[id] = _desktops[id]!.copyWith(needsPairing: true);
      if (_peers.remove(id) case final peer?) peers.add(peer);
      _dropPath(id);
    }
    await _save();
    _changed();
    await Future.wait([
      for (final peer in peers)
        () async {
          try {
            await peer.call(
              LinkMethods.unpair,
              const {},
              const Duration(seconds: 2),
            );
          } catch (_) {
            // Best effort: the desktop also learns of it at the next pairing.
          } finally {
            await peer.close();
          }
        }(),
    ]);
    final identity = LinkIdentity.generate();
    await _store.write('identity', jsonEncode(identity.toJson()));
    _identity = identity;
    await _serialized(_dropNode);
    _changed();
  }

  Future<void> _save() {
    final data = jsonEncode(_desktops.values.map((d) => d.toJson()).toList());
    final write = _writes.then((_) => _store.write('desktops', data));
    _writes = write.catchError((Object _) {});
    return write;
  }

  static Map<String, Object?> _map(Object? value) {
    if (value is! Map) throw const FormatException('Expected protocol object');
    return Map<String, Object?>.from(value);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    for (final attempt in _attempts) {
      unawaited(attempt._peer.close());
    }
    _attempts.clear();
    for (final peer in _opening) {
      unawaited(peer.close());
    }
    _opening.clear();
    for (final peer in _peers.values) {
      unawaited(peer.close());
    }
    _peers.clear();
    _replies.clear();
    _verifying.clear();
    for (final subscription in _pathSubscriptions.values) {
      unawaited(subscription.cancel());
    }
    _pathSubscriptions.clear();
    _paths.clear();
    final node = _node;
    if (node != null) unawaited(node.close());
    unawaited(_events.close());
    super.dispose();
  }
}
