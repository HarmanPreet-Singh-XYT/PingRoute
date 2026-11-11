import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:dart_ping/dart_ping.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../core/port_services.dart';
import '../services/app_connection_service.dart';
import 'app_metrics.dart';
import 'app_mode_settings.dart';
import 'flow_session.dart';

/// A long-lived ping against one endpoint. Emits round-trip ms, or -1 on loss.
abstract class EndpointPinger {
  Stream<int> get results;
  void dispose();
}

typedef PingerFactory = EndpointPinger Function(String ip, int intervalSec);
typedef TcpPingerFactory =
    EndpointPinger Function(String ip, int port, int intervalSec);
typedef HostnameResolver = Future<String?> Function(String ip);
typedef FlowFactory = FlowSession Function(String ip);

class DartPingEndpointPinger implements EndpointPinger {
  DartPingEndpointPinger(String ip, int intervalSec)
    : _ping = Ping(
        ip,
        interval: intervalSec,
        timeout: 2,
        ipVersion: ip.contains(':') ? IpVersion.ipv6 : IpVersion.ipv4,
      ) {
    _sub = _ping.stream.listen((event) {
      if (event is PingResponse) {
        // Sub-millisecond replies report 0; clamp so 0 never reads as "lost".
        final ms = event.time?.inMilliseconds ?? 0;
        _controller.add(ms < 1 ? 1 : ms);
      } else if (event is PingError) {
        _controller.add(-1);
      }
    }, onError: (_) => _controller.add(-1));
  }

  final Ping _ping;
  final _controller = StreamController<int>.broadcast();
  StreamSubscription<PingEvent>? _sub;

  @override
  Stream<int> get results => _controller.stream;

  @override
  void dispose() {
    _sub?.cancel();
    _ping.stop();
    _controller.close();
  }
}

/// Times a TCP handshake instead of an ICMP echo. Used for servers that drop
/// ping but are clearly reachable because the app has a connection open.
class TcpConnectPinger implements EndpointPinger {
  TcpConnectPinger(this.ip, this.port, int intervalSec) {
    _timer = Timer.periodic(Duration(seconds: intervalSec), (_) => _probe());
    _probe();
  }

  final String ip;
  final int port;
  final _controller = StreamController<int>.broadcast();
  Timer? _timer;
  bool _busy = false;
  bool _closed = false;

  Future<void> _probe() async {
    if (_closed || _busy) return;
    _busy = true;
    final watch = Stopwatch()..start();
    int result;
    try {
      final socket = await Socket.connect(
        ip,
        port,
        timeout: const Duration(seconds: 2),
      );
      watch.stop();
      socket.destroy();
      result = watch.elapsedMilliseconds < 1 ? 1 : watch.elapsedMilliseconds;
    } on Object {
      result = -1;
    } finally {
      _busy = false;
    }
    if (!_closed) _controller.add(result);
  }

  @override
  Stream<int> get results => _controller.stream;

  @override
  void dispose() {
    _closed = true;
    _timer?.cancel();
    _controller.close();
  }
}

/// How an endpoint's latency is being measured.
enum ProbeMethod { icmp, tcp }

Future<String?> reverseDnsResolver(String ip) async {
  try {
    final address = await InternetAddress(
      ip,
    ).reverse().timeout(const Duration(seconds: 3));
    final host = address.host;
    return host == ip ? null : host;
  } on Object {
    return null;
  }
}

/// Live state for one remote IP an application is talking to.
class EndpointState extends ChangeNotifier {
  EndpointState({required this.appId, required this.ip, DateTime? now})
    : firstSeen = now ?? DateTime.now(),
      lastSeen = now ?? DateTime.now();

  static const historyLength = 60;

  /// Samples considered "recent" when judging health.
  static const recentWindow = 20;

  final String appId;
  final String ip;
  final DateTime firstSeen;
  DateTime lastSeen;

  int connectionCount = 0;
  Set<int> ports = {};
  Set<int> localPorts = {};
  Set<String> protocols = {};
  Map<String, int> states = {};
  String? primaryService;
  bool isIpv6 = false;
  bool isActive = true;
  String? hostname;

  // Traffic (macOS): current socket counters, live rate, and bytes moved
  // since this endpoint was first observed.
  int bytesIn = 0;
  int bytesOut = 0;
  double inRate = 0;
  double outRate = 0;
  int sessionIn = 0;
  int sessionOut = 0;

  // Latency.
  final List<int> history = [];
  int sent = 0;
  int lost = 0;
  int _okCount = 0;
  int _okSum = 0;
  int? minMs;
  int? maxMs;

  /// True while a ping stream is running for this endpoint.
  bool isPinging = false;

  ProbeMethod probe = ProbeMethod.icmp;

  /// Remote TCP port used by the TCP-connect probe, when there is one.
  int? tcpPort;

  /// Present while the row is expanded; owns a full traceroute session.
  FlowSession? flow;

  bool get isExpanded => flow != null;
  int? get last => history.isEmpty ? null : history.last;
  int? get averageMs => _okCount == 0 ? null : (_okSum / _okCount).round();
  double get lossPercent => sent == 0 ? 0 : lost * 100 / sent;
  Duration get observedFor => lastSeen.difference(firstSeen);
  double get rate => inRate + outRate;
  bool get hasReplies => _okCount > 0;

  Iterable<int> get _recent => history.length <= recentWindow
      ? history
      : history.sublist(history.length - recentWindow);

  /// Loss over the last [recentWindow] pings; recovers after a blip, unlike
  /// the session-wide [lossPercent].
  double get recentLossPercent {
    final samples = _recent.toList();
    if (samples.isEmpty) return 0;
    return samples.where((v) => v < 0).length * 100 / samples.length;
  }

  double? get recentAverageMs {
    final ok = _recent.where((v) => v >= 0).toList();
    if (ok.isEmpty) return null;
    return ok.reduce((a, b) => a + b) / ok.length;
  }

  /// Mean absolute difference between consecutive successful replies.
  double? get jitterMs {
    final ok = history.where((v) => v >= 0).toList();
    if (ok.length < 2) return null;
    var total = 0;
    for (var i = 1; i < ok.length; i++) {
      total += (ok[i] - ok[i - 1]).abs();
    }
    return total / (ok.length - 1);
  }

  EndpointHealth health(int lossAlertPercent) {
    if (!isActive) return EndpointHealth.idle;
    if (history.isEmpty) {
      return isPinging || isExpanded
          ? EndpointHealth.measuring
          : EndpointHealth.notPinged;
    }
    if (_okCount == 0) {
      return sent >= 3 ? EndpointHealth.noReply : EndpointHealth.measuring;
    }
    final loss = recentLossPercent;
    final avg = recentAverageMs ?? 0;
    if (loss >= lossAlertPercent || avg > kBadLatencyMs) {
      return EndpointHealth.poor;
    }
    if (loss > 0 || avg > kWarnLatencyMs) return EndpointHealth.degraded;
    return EndpointHealth.good;
  }

  /// Forgets latency samples (used when the probe method changes, so the
  /// old method's failures don't pollute the new one's health).
  void resetSamples() {
    history.clear();
    sent = 0;
    lost = 0;
    _okCount = 0;
    _okSum = 0;
    minMs = null;
    maxMs = null;
    notifyListeners();
  }

  void addSample(int ms) {
    sent++;
    if (ms < 0) {
      lost++;
    } else {
      _okCount++;
      _okSum += ms;
      minMs = minMs == null ? ms : math.min(minMs!, ms);
      maxMs = maxMs == null ? ms : math.max(maxMs!, ms);
    }
    history.add(ms);
    if (history.length > historyLength) history.removeAt(0);
    notifyListeners();
  }

  /// Refreshes this endpoint from the sockets currently open to it.
  void applyConnections(
    List<AppConnection> conns, {
    required DateTime now,
    int deltaIn = 0,
    int deltaOut = 0,
    double seconds = 1,
  }) {
    connectionCount = conns.length;
    ports = {for (final c in conns) c.remotePort};
    localPorts = {for (final c in conns) ?c.localPort};
    protocols = {for (final c in conns) c.protocol.toUpperCase()};
    states = {};
    for (final c in conns) {
      final key = c.isUdp ? 'UDP' : c.state;
      if (key.isEmpty) continue;
      states.update(key, (n) => n + 1, ifAbsent: () => 1);
    }
    isIpv6 = conns.isNotEmpty && conns.first.isIpv6;
    final tcpPorts = [
      for (final c in conns)
        if (!c.isUdp) c.remotePort,
    ];
    tcpPort = tcpPorts.isEmpty
        ? null
        : (tcpPorts.contains(443) ? 443 : tcpPorts.first);

    final labelCounts = <String, int>{};
    for (final c in conns) {
      labelCounts.update(
        serviceLabel(c.remotePort, protocol: c.protocol),
        (n) => n + 1,
        ifAbsent: () => 1,
      );
    }
    primaryService = labelCounts.isEmpty
        ? null
        : (labelCounts.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value)))
              .first
              .key;

    bytesIn = conns.fold(0, (s, c) => s + c.bytesIn);
    bytesOut = conns.fold(0, (s, c) => s + c.bytesOut);
    inRate = deltaIn / seconds;
    outRate = deltaOut / seconds;
    sessionIn += deltaIn;
    sessionOut += deltaOut;

    lastSeen = now;
    isActive = true;
    notifyListeners();
  }

  /// Returns true if this call changed the endpoint from active to closed.
  bool markIdle() {
    if (!isActive) return false;
    isActive = false;
    connectionCount = 0;
    inRate = 0;
    outRate = 0;
    notifyListeners();
    return true;
  }

  void setHostname(String? value) {
    if (hostname == value) return;
    hostname = value;
    notifyListeners();
  }

  void changed() => notifyListeners();
}

/// Per-application list controls (search, sort, filters).
class AppViewState {
  String query = '';
  EndpointSort? sort;
  bool activeOnly = false;
  bool problemsOnly = false;
  bool collapsed = false;
  bool activityOpen = false;
}

/// Drives App Mode: polls the OS for per-application connections, tracks
/// every remote endpoint over time and keeps a bounded set of live pingers.
class AppsController extends ChangeNotifier {
  AppsController({
    AppConnectionService? service,
    AppModeSettings? settings,
    PingerFactory? pingerFactory,
    TcpPingerFactory? tcpPingerFactory,
    HostnameResolver? hostnameResolver,
    FlowFactory? flowFactory,
    DateTime Function()? clock,
  }) : _service = service ?? AppConnectionService(),
       settings = settings ?? AppModeSettings.instance,
       _pingerFactory = pingerFactory ?? DartPingEndpointPinger.new,
       _tcpPingerFactory = tcpPingerFactory ?? TcpConnectPinger.new,
       _hostnameResolver = hostnameResolver ?? reverseDnsResolver,
       _flowFactory = flowFactory ?? _defaultFlowFactory,
       _clock = clock ?? DateTime.now {
    this.settings.addListener(_onSettingsChanged);
    _lastPollInterval = this.settings.pollInterval;
    _lastPingInterval = this.settings.pingIntervalSec;
    _lastIncludePrivate = this.settings.includePrivate;
    _lastIncludeUdp = this.settings.includeUdp;
    _lastTrackingMode = this.settings.trackingMode;
    _lastAutoStart = this.settings.autoStartTracking;
  }

  static FlowSession _defaultFlowFactory(String ip) =>
      FlowSession(initialIp: ip)..execTraceroute();

  static const maxEvents = 300;
  static const rateHistoryLength = 60;

  final AppConnectionService _service;
  final AppModeSettings settings;
  final PingerFactory _pingerFactory;
  final TcpPingerFactory _tcpPingerFactory;
  final HostnameResolver _hostnameResolver;
  final FlowFactory _flowFactory;
  final DateTime Function() _clock;

  List<AppSnapshot> _apps = const [];
  final Set<String> _selectedIds = {};
  final Set<String> _pinnedIds = {};
  final Map<String, Map<String, EndpointState>> _endpoints = {};
  final Map<EndpointState, _PingerHandle> _pingers = {};
  // ip -> resolved name (null: no name). Bounded; oldest entries drop first.
  static const _hostnameCacheLimit = 2000;
  final Map<String, String?> _hostnameCache = {};
  final Set<String> _hostnameInFlight = {};
  final Map<String, String> _appNames = {};
  final Map<String, AppViewState> _views = {};
  final List<ActivityEvent> _events = [];

  // Traffic accounting, keyed per socket so closed sockets drop out.
  final Map<String, (int, int)> _prevTraffic = {};
  final Map<String, Map<String, (int, int)>> _endpointDeltas = {};
  final Map<String, RateSample> _appRates = {};
  final Map<String, List<RateSample>> _rateHistory = {};
  final Map<String, List<double>> _latencyTrend = {};
  final Map<String, int> _sessionIn = {};
  final Map<String, int> _sessionOut = {};
  DateTime? _lastTrafficAt;
  double _deltaSeconds = 1;

  final Set<String> _syncedApps = {};
  final Set<String> _startedIds = {};
  late bool _lastAutoStart;
  final Map<String, DateTime> _trackedSince = {};

  late Duration _lastPollInterval;
  late int _lastPingInterval;
  late bool _lastIncludePrivate;
  late bool _lastIncludeUdp;
  late TrackingMode _lastTrackingMode;

  Timer? _timer;
  bool _polling = false;
  bool _disposed = false;
  bool _userPaused = false;
  bool _restored = false;
  bool _showOverview = true;

  String search = '';
  DateTime? lastPolled;

  bool get isRunning => _timer != null;
  bool get isPaused => _userPaused;
  bool get showOverview => _showOverview;
  bool get hideSystem => settings.hideSystemApps;

  /// True when nothing is monitored until the user ticks apps.
  bool get trackSelectedOnly => settings.trackingMode == TrackingMode.selected;
  int get maxLivePingers => settings.maxLivePingers;
  List<ActivityEvent> get events => List.unmodifiable(_events);

  /// Apps matching the search / system filter, selected or pinned ones
  /// always included so they never vanish from under the user.
  List<AppSnapshot> get apps {
    final query = search.trim().toLowerCase();
    return [
      for (final app in _apps)
        if ((!hideSystem || !app.isSystem || visibleAppIds.contains(app.id)) &&
            (query.isEmpty || app.name.toLowerCase().contains(query)))
          app,
    ];
  }

  Set<String> get selectedIds => Set.unmodifiable(_selectedIds);
  Set<String> get pinnedIds => Set.unmodifiable(_pinnedIds);
  Set<String> get visibleAppIds => trackSelectedOnly
      ? Set.unmodifiable(_pinnedIds)
      : {..._selectedIds, ..._pinnedIds};

  bool isTracked(String appId) => visibleAppIds.contains(appId);

  /// Apps whose endpoints, pings and stats are actually being collected:
  /// the ones in view that the user started (or all of them when automatic
  /// start is on).
  Set<String> get trackingIds => settings.autoStartTracking
      ? visibleAppIds
      : visibleAppIds.intersection(_startedIds);

  bool isTrackingActive(String appId) => trackingIds.contains(appId);

  /// Begins collecting endpoints, pings and stats for [appId].
  void startTracking(String appId) {
    if (!visibleAppIds.contains(appId) || !_startedIds.add(appId)) return;
    _resetAppStats(appId);
    _afterSelectionChange(remember: false);
  }

  /// Starts every app currently in view.
  void startAllTracking() {
    var any = false;
    for (final id in visibleAppIds) {
      if (_startedIds.add(id)) {
        _resetAppStats(id);
        any = true;
      }
    }
    if (any) _afterSelectionChange(remember: false);
  }

  /// Stops collecting for [appId] and discards what was gathered, so the next
  /// start begins from a clean slate.
  void stopTracking(String appId) {
    if (!_startedIds.remove(appId) && !settings.autoStartTracking) return;
    _discardEndpoints(appId);
    _resetAppStats(appId);
    _afterSelectionChange(remember: false);
  }

  void _discardEndpoints(String appId) {
    final map = _endpoints.remove(appId);
    if (map == null) return;
    for (final ep in map.values) {
      _stopPinger(ep);
      ep.flow?.dispose();
      ep.dispose();
    }
  }

  void _resetAppStats(String appId) {
    _syncedApps.remove(appId);
    _trackedSince.remove(appId);
    _sessionIn.remove(appId);
    _sessionOut.remove(appId);
    _rateHistory.remove(appId);
    _latencyTrend.remove(appId);
  }

  String nameFor(String appId) =>
      _appNames[appId] ??
      _apps.where((a) => a.id == appId).firstOrNull?.name ??
      appId;

  AppSnapshot? snapshotFor(String appId) =>
      _apps.where((a) => a.id == appId).firstOrNull;

  /// Endpoints for [appId]: active first, then by when they were first seen.
  List<EndpointState> endpointsFor(String appId) {
    final list = (_endpoints[appId]?.values ?? const <EndpointState>[])
        .toList();
    list.sort((a, b) {
      if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
      final byTime = a.firstSeen.compareTo(b.firstSeen);
      return byTime != 0 ? byTime : a.ip.compareTo(b.ip);
    });
    return list;
  }

  int get livePingerCount => _pingers.length;

  RateSample rateFor(String appId) =>
      _appRates[appId] ?? (inBps: 0.0, outBps: 0.0);

  /// Mean recent latency per poll, for the overview card's trend line.
  List<double> latencyTrendFor(String appId) =>
      _latencyTrend[appId] ?? const [];

  List<RateSample> rateHistoryFor(String appId) =>
      _rateHistory[appId] ?? const [];

  // ---- lifecycle ---------------------------------------------------------

  void start() {
    if (_timer != null || _disposed || _userPaused) return;
    _timer = Timer.periodic(settings.pollInterval, (_) => refresh());
    _restoreSelection();
    refresh();
  }

  /// Pauses polling and pinging (e.g. when the user leaves the Apps screen).
  /// Endpoint history is kept so returning resumes where they left off.
  void stop() {
    _timer?.cancel();
    _timer = null;
    for (final handle in _pingers.values) {
      handle.dispose();
    }
    _pingers.clear();
    for (final ep in _allEndpoints) {
      ep.isPinging = false;
    }
    // Rates computed across a pause would be meaningless.
    _lastTrafficAt = null;
  }

  /// User-initiated pause: stays paused even if the screen is re-entered.
  void pause() {
    if (_userPaused) return;
    _userPaused = true;
    stop();
    for (final ep in _allEndpoints) {
      ep.changed();
    }
    notifyListeners();
  }

  void resume() {
    if (!_userPaused) return;
    _userPaused = false;
    start();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    settings.removeListener(_onSettingsChanged);
    stop();
    for (final ep in _allEndpoints) {
      ep.flow?.dispose();
      ep.dispose();
    }
    _endpoints.clear();
    super.dispose();
  }

  Iterable<EndpointState> get _allEndpoints =>
      _endpoints.values.expand((m) => m.values);

  void _restoreSelection() {
    if (_restored) return;
    _restored = true;
    settings.load().then((_) {
      if (_disposed || !settings.rememberSelection) return;
      if (_selectedIds.isNotEmpty || _pinnedIds.isNotEmpty) return;
      _pinnedIds.addAll(settings.pinnedAppIds);
      if (!trackSelectedOnly) _selectedIds.addAll(settings.selectedAppIds);
      if (visibleAppIds.isNotEmpty) {
        _showOverview = false;
        _afterSelectionChange(remember: false);
      } else {
        notifyListeners();
      }
    });
  }

  void _onSettingsChanged() {
    if (_disposed) return;
    final pollChanged = settings.pollInterval != _lastPollInterval;
    final pingChanged = settings.pingIntervalSec != _lastPingInterval;
    final filterChanged =
        settings.includePrivate != _lastIncludePrivate ||
        settings.includeUdp != _lastIncludeUdp;
    _lastPollInterval = settings.pollInterval;
    _lastPingInterval = settings.pingIntervalSec;
    _lastIncludePrivate = settings.includePrivate;
    _lastIncludeUdp = settings.includeUdp;

    if (settings.autoStartTracking != _lastAutoStart) {
      _lastAutoStart = settings.autoStartTracking;
      // Turning automatic start off keeps what is already being tracked.
      if (!_lastAutoStart) _startedIds.addAll(visibleAppIds);
      _syncEndpoints(_clock());
      if (isRunning) refresh();
    }

    if (settings.trackingMode != _lastTrackingMode) {
      _lastTrackingMode = settings.trackingMode;
      // Switching modes starts from a clean slate of what is "in view".
      _selectedIds.clear();
      _appRates.clear();
      _prevTraffic.clear();
      _lastTrafficAt = null;
      _showOverview = visibleAppIds.isEmpty || trackSelectedOnly;
      _remember();
    }

    if (isRunning) {
      if (pollChanged) {
        _timer?.cancel();
        _timer = Timer.periodic(settings.pollInterval, (_) => refresh());
      }
      if (pingChanged) {
        for (final ep in _pingers.keys.toList()) {
          _stopPinger(ep);
        }
      }
      _reconcilePingers();
      if (filterChanged) refresh();
    }
    notifyListeners();
  }

  // ---- selection ---------------------------------------------------------

  void selectApp(String appId) {
    if (trackSelectedOnly) {
      toggleTracked(appId);
      return;
    }
    _selectedIds
      ..clear()
      ..add(appId);
    _showOverview = false;
    _afterSelectionChange();
  }

  /// "Only apps I choose" mode: tick or untick [appId]. Several can be
  /// ticked at once.
  void toggleTracked(String appId) {
    if (!_pinnedIds.remove(appId)) {
      _pinnedIds.add(appId);
      _showOverview = false;
    } else if (_pinnedIds.isEmpty) {
      _showOverview = true;
    }
    _afterSelectionChange();
  }

  void trackAll(Iterable<String> appIds) {
    _pinnedIds.addAll(appIds);
    if (_pinnedIds.isNotEmpty) _showOverview = false;
    _afterSelectionChange();
  }

  void clearTracked() {
    _pinnedIds.clear();
    _selectedIds.clear();
    _showOverview = true;
    _afterSelectionChange();
  }

  /// Jump to [appId]'s detail view (tracking it first in choose-only mode).
  void openApp(String appId) {
    if (trackSelectedOnly) {
      if (!_pinnedIds.contains(appId)) {
        toggleTracked(appId);
      } else {
        _showOverview = false;
        notifyListeners();
      }
    } else {
      selectApp(appId);
    }
  }

  /// Show the detail sections of every tracked app.
  void showTracked() {
    if (_pinnedIds.isEmpty) return;
    _showOverview = false;
    notifyListeners();
  }

  void togglePin(String appId) {
    if (!_pinnedIds.remove(appId)) _pinnedIds.add(appId);
    _afterSelectionChange();
  }

  /// Back to the all-apps overview without forgetting pins.
  void openOverview() {
    _showOverview = true;
    _selectedIds.clear();
    _remember();
    notifyListeners();
  }

  void setSearch(String value) {
    search = value;
    notifyListeners();
  }

  void setHideSystem(bool value) => settings.setHideSystemApps(value);

  void _remember() => settings.rememberApps(
    pinned: _pinnedIds,
    selected: trackSelectedOnly ? const [] : _selectedIds,
  );

  void _afterSelectionChange({bool remember = true}) {
    _syncEndpoints(_clock());
    if (isRunning) _reconcilePingers();
    if (remember) _remember();
    notifyListeners();
    if (isRunning) refresh();
  }

  // ---- per-app view ------------------------------------------------------

  AppViewState viewFor(String appId) =>
      _views.putIfAbsent(appId, AppViewState.new);

  EndpointSort sortFor(String appId) =>
      viewFor(appId).sort ?? settings.defaultSort;

  void updateView(String appId, void Function(AppViewState view) change) {
    change(viewFor(appId));
    notifyListeners();
  }

  /// [endpointsFor] with the app's search, filters and sort applied.
  List<EndpointState> filteredEndpointsFor(String appId) {
    final view = viewFor(appId);
    final query = view.query.trim().toLowerCase();
    final loss = settings.lossAlertPercent;

    final list = endpointsFor(appId).where((e) {
      if (view.activeOnly && !e.isActive) return false;
      if (view.problemsOnly && !e.health(loss).isProblem) return false;
      if (query.isEmpty) return true;
      return e.ip.contains(query) ||
          (e.hostname?.toLowerCase().contains(query) ?? false) ||
          (e.primaryService?.toLowerCase().contains(query) ?? false);
    }).toList();

    int byActive(EndpointState a, EndpointState b) =>
        a.isActive == b.isActive ? 0 : (a.isActive ? -1 : 1);
    // Nulls (not measured yet) always sort last.
    int desc(num? a, num? b) {
      if (a == null && b == null) return 0;
      if (a == null) return 1;
      if (b == null) return -1;
      return b.compareTo(a);
    }

    list.sort((a, b) {
      final active = byActive(a, b);
      if (active != 0) return active;
      final primary = switch (sortFor(appId)) {
        EndpointSort.firstSeen => a.firstSeen.compareTo(b.firstSeen),
        EndpointSort.latency => desc(a.averageMs, b.averageMs),
        EndpointSort.loss => desc(
          a.sent == 0 ? null : a.recentLossPercent,
          b.sent == 0 ? null : b.recentLossPercent,
        ),
        EndpointSort.connections => b.connectionCount.compareTo(
          a.connectionCount,
        ),
        EndpointSort.traffic => desc(
          a.rate + a.sessionIn + a.sessionOut,
          b.rate + b.sessionIn + b.sessionOut,
        ),
        EndpointSort.address => a.ip.compareTo(b.ip),
      };
      return primary != 0 ? primary : a.ip.compareTo(b.ip);
    });
    return list;
  }

  /// Active endpoints across tracked apps that currently need attention.
  List<EndpointState> problemEndpoints() {
    final loss = settings.lossAlertPercent;
    final list = [
      for (final id in trackingIds)
        for (final e in endpointsFor(id))
          if (e.health(loss).isProblem) e,
    ];
    list.sort((a, b) {
      final byHealth = b.health(loss).index.compareTo(a.health(loss).index);
      if (byHealth != 0) return byHealth;
      return (b.recentAverageMs ?? 0).compareTo(a.recentAverageMs ?? 0);
    });
    return list;
  }

  List<ActivityEvent> eventsFor(String appId) => [
    for (final e in _events)
      if (e.appId == appId) e,
  ];

  // ---- summaries ---------------------------------------------------------

  AppSummary summaryFor(String appId) {
    final snapshot = snapshotFor(appId);
    final eps = endpointsFor(appId);
    final active = eps.where((e) => e.isActive).toList();
    final loss = settings.lossAlertPercent;
    final now = _clock();
    final since = _trackedSince[appId];

    final measured = eps.where((e) => e.averageMs != null).toList();
    final avg = measured.isEmpty
        ? null
        : (measured.map((e) => e.averageMs!).reduce((a, b) => a + b) /
                  measured.length)
              .round();
    EndpointState? fastest;
    EndpointState? slowest;
    for (final e in measured) {
      if (fastest == null || e.averageMs! < fastest.averageMs!) fastest = e;
      if (slowest == null || e.averageMs! > slowest.averageMs!) slowest = e;
    }
    final totalSent = eps.fold<int>(0, (s, e) => s + e.sent);
    final totalLost = eps.fold<int>(0, (s, e) => s + e.lost);
    final jitters = [for (final e in eps) ?e.jitterMs];

    final states = <String, int>{};
    final services = <String, int>{};
    var tcp = 0;
    var udp = 0;
    for (final c in snapshot?.connections ?? const <AppConnection>[]) {
      if (c.isUdp) {
        udp++;
        states.update('UDP', (n) => n + 1, ifAbsent: () => 1);
      } else {
        tcp++;
        if (c.state.isNotEmpty) {
          states.update(c.state, (n) => n + 1, ifAbsent: () => 1);
        }
      }
      services.update(
        serviceLabel(c.remotePort, protocol: c.protocol),
        (n) => n + 1,
        ifAbsent: () => 1,
      );
    }

    final rate = rateFor(appId);
    return AppSummary(
      endpointCount: eps.length,
      activeCount: active.length,
      connectionCount: active.fold(0, (s, e) => s + e.connectionCount),
      newLastMinute: since == null
          ? 0
          : eps
                .where(
                  (e) =>
                      e.firstSeen.isAfter(since) &&
                      now.difference(e.firstSeen) < const Duration(minutes: 1),
                )
                .length,
      pingedCount: measured.length,
      avgMs: avg,
      fastestIp: fastest?.ip,
      fastestMs: fastest?.averageMs,
      slowestIp: slowest?.ip,
      slowestMs: slowest?.averageMs,
      lossPercent: totalSent == 0 ? 0 : totalLost * 100 / totalSent,
      jitterMs: jitters.isEmpty
          ? null
          : jitters.reduce((a, b) => a + b) / jitters.length,
      problemCount: active.where((e) => e.health(loss).isProblem).length,
      stateCounts: states,
      serviceCounts: sortedCounts(services),
      ipv4Count: active.where((e) => !e.isIpv6).length,
      ipv6Count: active.where((e) => e.isIpv6).length,
      tcpConnections: tcp,
      udpConnections: udp,
      inRate: rate.inBps,
      outRate: rate.outBps,
      sessionIn: _sessionIn[appId] ?? 0,
      sessionOut: _sessionOut[appId] ?? 0,
      trafficAvailable: snapshot?.trafficAvailable ?? false,
      processCount: snapshot?.processCount ?? 0,
      cpuPercent: snapshot?.cpuPercent ?? 0,
      rssKb: snapshot?.rssKb ?? 0,
      uptime: snapshot?.uptime,
    );
  }

  OverviewSummary get overview {
    final list = [
      for (final app in _apps)
        if (trackSelectedOnly
            ? _pinnedIds.contains(app.id)
            : (!hideSystem || !app.isSystem))
          app,
    ];
    final ips = <String>{};
    final states = <String, int>{};
    final services = <String, int>{};
    var connections = 0;
    var inRate = 0.0;
    var outRate = 0.0;
    final talkers = <TalkerRow>[];

    for (final app in list) {
      final counts = app.endpointCounts;
      ips.addAll(counts.keys);
      connections += app.connections.length;
      for (final c in app.connections) {
        final state = c.isUdp ? 'UDP' : c.state;
        if (state.isNotEmpty) {
          states.update(state, (n) => n + 1, ifAbsent: () => 1);
        }
        services.update(
          serviceLabel(c.remotePort, protocol: c.protocol),
          (n) => n + 1,
          ifAbsent: () => 1,
        );
      }
      final rate = rateFor(app.id);
      inRate += rate.inBps;
      outRate += rate.outBps;
      talkers.add(
        TalkerRow(
          app: app,
          endpoints: counts.length,
          connections: app.connections.length,
          inRate: rate.inBps,
          outRate: rate.outBps,
        ),
      );
    }
    talkers.sort((a, b) {
      final byRate = b.rate.compareTo(a.rate);
      if (byRate != 0) return byRate;
      return b.endpoints.compareTo(a.endpoints);
    });

    return OverviewSummary(
      appCount: list.length,
      endpointCount: ips.length,
      connectionCount: connections,
      trackedApps: trackingIds.length,
      stateCounts: states,
      serviceCounts: sortedCounts(services),
      inRate: inRate,
      outRate: outRate,
      trafficAvailable: list.any((a) => a.trafficAvailable),
      talkers: talkers,
    );
  }

  // ---- polling -----------------------------------------------------------

  Future<void> refresh() async {
    if (_polling || _disposed) return;
    _polling = true;
    try {
      final snapshot = await _service.poll(
        includePrivate: settings.includePrivate,
        includeUdp: settings.includeUdp,
      );
      if (_disposed) return;
      _apps = snapshot;
      for (final app in snapshot) {
        _appNames[app.id] = app.name;
      }
      final now = _clock();
      lastPolled = now;
      _trackTraffic(snapshot, now);
      _syncEndpoints(now);
      _recordLatencyTrend();
      if (isRunning) _reconcilePingers();
      notifyListeners();
    } finally {
      _polling = false;
    }
  }

  void _recordLatencyTrend() {
    for (final appId in trackingIds) {
      final values = [
        for (final e in endpointsFor(appId))
          if (e.isActive) ?e.recentAverageMs,
      ];
      if (values.isEmpty) continue;
      final trend = _latencyTrend.putIfAbsent(appId, () => []);
      trend.add(values.reduce((a, b) => a + b) / values.length);
      if (trend.length > rateHistoryLength) trend.removeAt(0);
    }
  }

  /// Turns cumulative socket counters into per-poll deltas and rates.
  void _trackTraffic(List<AppSnapshot> snapshot, DateTime now) {
    final last = _lastTrafficAt;
    final elapsed = last == null
        ? 0.0
        : now.difference(last).inMilliseconds / 1000;
    final usable = elapsed >= 0.25 && elapsed <= 30;
    _deltaSeconds = usable ? elapsed : 1;

    final next = <String, (int, int)>{};
    _endpointDeltas.clear();
    // Rates of apps that have quit must not linger.
    _appRates.removeWhere((id, _) => !snapshot.any((a) => a.id == id));
    for (final app in snapshot) {
      // Choose-only mode never computes anything for untracked apps.
      if (trackSelectedOnly && !_pinnedIds.contains(app.id)) continue;
      var appIn = 0;
      var appOut = 0;
      final perIp = _endpointDeltas.putIfAbsent(app.id, () => {});
      for (final c in app.connections) {
        final key = '${app.id}|${c.key}';
        next[key] = (c.bytesIn, c.bytesOut);
        final prev = _prevTraffic[key];
        if (prev == null || !usable) continue;
        final dIn = math.max(0, c.bytesIn - prev.$1);
        final dOut = math.max(0, c.bytesOut - prev.$2);
        appIn += dIn;
        appOut += dOut;
        final cur = perIp[c.remoteIp] ?? (0, 0);
        perIp[c.remoteIp] = (cur.$1 + dIn, cur.$2 + dOut);
      }
      final sample = (
        inBps: appIn / _deltaSeconds,
        outBps: appOut / _deltaSeconds,
      );
      _appRates[app.id] = sample;
      if (!isTrackingActive(app.id)) continue;
      _sessionIn.update(app.id, (v) => v + appIn, ifAbsent: () => appIn);
      _sessionOut.update(app.id, (v) => v + appOut, ifAbsent: () => appOut);
      if (app.trafficAvailable && usable) {
        final history = _rateHistory.putIfAbsent(app.id, () => []);
        history.add(sample);
        if (history.length > rateHistoryLength) history.removeAt(0);
      }
    }
    _prevTraffic
      ..clear()
      ..addAll(next);
    _lastTrafficAt = now;
  }

  void _addEvent(
    ActivityKind kind,
    String appId,
    String message, {
    String? ip,
    DateTime? at,
  }) {
    _events.insert(
      0,
      ActivityEvent(
        time: at ?? _clock(),
        kind: kind,
        appId: appId,
        appName: nameFor(appId),
        message: message,
        ip: ip,
      ),
    );
    if (_events.length > maxEvents)
      _events.removeRange(maxEvents, _events.length);
  }

  void _syncEndpoints(DateTime now) {
    for (final appId in trackingIds) {
      final app = snapshotFor(appId);
      final map = _endpoints.putIfAbsent(appId, () => {});

      final byIp = <String, List<AppConnection>>{};
      for (final c in app?.connections ?? const <AppConnection>[]) {
        byIp.putIfAbsent(c.remoteIp, () => []).add(c);
      }

      // Don't announce every pre-existing endpoint as "new" when tracking
      // starts: the first sync with real data is the baseline.
      final baseline = app != null && _syncedApps.add(appId);
      if (baseline) {
        _trackedSince[appId] = now;
        _addEvent(
          ActivityKind.started,
          appId,
          'Tracking ${byIp.length} endpoint${byIp.length == 1 ? '' : 's'}',
          at: now,
        );
      }

      for (final entry in byIp.entries) {
        final isNew = !map.containsKey(entry.key);
        final ep = map.putIfAbsent(entry.key, () {
          final created = EndpointState(appId: appId, ip: entry.key, now: now);
          _resolveHostname(created);
          return created;
        });
        final wasIdle = !ep.isActive && !isNew;
        final delta = _endpointDeltas[appId]?[entry.key] ?? (0, 0);
        ep.applyConnections(
          entry.value,
          now: now,
          deltaIn: delta.$1,
          deltaOut: delta.$2,
          seconds: _deltaSeconds,
        );
        if ((isNew && !baseline) || wasIdle) {
          _addEvent(
            ActivityKind.connected,
            appId,
            'Connected to ${ep.ip}'
            '${ep.primaryService == null ? '' : ' (${ep.primaryService})'}',
            ip: ep.ip,
            at: now,
          );
        }
      }

      final gone = <String>[];
      for (final ep in map.values) {
        if (byIp.containsKey(ep.ip)) continue;
        if (ep.markIdle()) {
          _addEvent(
            ActivityKind.closed,
            appId,
            'Connection to ${ep.ip} closed',
            ip: ep.ip,
            at: now,
          );
        }
        final expired = now.difference(ep.lastSeen) > settings.idleRetention;
        if (expired && !ep.isExpanded) gone.add(ep.ip);
      }
      for (final ip in gone) {
        final ep = map.remove(ip)!;
        _stopPinger(ep);
        ep.dispose();
      }
    }
  }

  void _resolveHostname(EndpointState ep) {
    if (_hostnameCache.containsKey(ep.ip)) {
      ep.setHostname(_hostnameCache[ep.ip]);
      return;
    }
    if (!_hostnameInFlight.add(ep.ip)) return;
    _hostnameResolver(ep.ip).then((name) {
      _hostnameInFlight.remove(ep.ip);
      if (_disposed) return;
      _hostnameCache[ep.ip] = name;
      if (_hostnameCache.length > _hostnameCacheLimit) {
        _hostnameCache.remove(_hostnameCache.keys.first);
      }
      // Share the result with every endpoint using the same IP.
      for (final other in _allEndpoints.where((e) => e.ip == ep.ip)) {
        other.setHostname(name);
      }
    });
  }

  // ---- pinging -----------------------------------------------------------

  /// Starts pingers for the busiest active endpoints (up to
  /// `settings.maxLivePingers`) and stops the rest.
  void _reconcilePingers() {
    final candidates =
        [
          for (final appId in trackingIds)
            for (final ep in endpointsFor(appId))
              if (ep.isActive && !ep.isExpanded) ep,
        ]..sort((a, b) {
          final byConns = b.connectionCount.compareTo(a.connectionCount);
          return byConns != 0 ? byConns : a.firstSeen.compareTo(b.firstSeen);
        });

    final wanted = candidates.take(settings.maxLivePingers).toSet();

    for (final ep in _pingers.keys.toList()) {
      if (!wanted.contains(ep)) _stopPinger(ep);
    }
    for (final ep in wanted) {
      if (!_pingers.containsKey(ep)) _startPinger(ep);
    }
  }

  void _startPinger(EndpointState ep) {
    final tcpPort = ep.tcpPort;
    final pinger = ep.probe == ProbeMethod.tcp && tcpPort != null
        ? _tcpPingerFactory(ep.ip, tcpPort, settings.pingIntervalSec)
        : _pingerFactory(ep.ip, settings.pingIntervalSec);
    final sub = pinger.results.listen((ms) {
      if (_disposed) return;
      final loss = settings.lossAlertPercent;
      final before = ep.health(loss);
      ep.addSample(ms);
      final after = ep.health(loss);
      if (ep.probe == ProbeMethod.icmp &&
          settings.tcpFallback &&
          after == EndpointHealth.noReply &&
          ep.tcpPort != null) {
        _switchToTcp(ep);
        return;
      }
      if (before != EndpointHealth.poor && after == EndpointHealth.poor) {
        _addEvent(
          ActivityKind.degraded,
          ep.appId,
          '${ep.ip} is struggling '
          '(${ep.recentLossPercent.round()}% loss, '
          '${ep.recentAverageMs?.round() ?? '–'} ms)',
          ip: ep.ip,
        );
        notifyListeners();
      } else if (before == EndpointHealth.poor &&
          after == EndpointHealth.good) {
        _addEvent(
          ActivityKind.recovered,
          ep.appId,
          '${ep.ip} recovered',
          ip: ep.ip,
        );
        notifyListeners();
      }
    });
    _pingers[ep] = _PingerHandle(pinger, sub);
    ep.isPinging = true;
    ep.changed();
  }

  /// The host ignores ping: measure TCP connect time to the port the app
  /// already uses instead.
  void _switchToTcp(EndpointState ep) {
    ep.probe = ProbeMethod.tcp;
    ep.resetSamples();
    _stopPinger(ep);
    _addEvent(
      ActivityKind.started,
      ep.appId,
      '${ep.ip} ignores ping — timing TCP connections to port ${ep.tcpPort} instead',
      ip: ep.ip,
    );
    if (isRunning && !ep.isExpanded) _startPinger(ep);
    notifyListeners();
  }

  void _stopPinger(EndpointState ep) {
    final handle = _pingers.remove(ep);
    if (handle == null) return;
    handle.dispose();
    ep.isPinging = false;
    ep.changed();
  }

  // ---- expand / promote --------------------------------------------------

  /// Expands [ep] into a full traceroute session, or collapses it again.
  void toggleExpanded(EndpointState ep) {
    final flow = ep.flow;
    if (flow == null) {
      _stopPinger(ep);
      ep.flow = _flowFactory(ep.ip);
    } else {
      ep.flow = null;
      flow.dispose();
      if (isRunning) _reconcilePingers();
    }
    ep.changed();
  }

  /// Collapses every expanded row of [appId].
  void collapseAll(String appId) {
    for (final ep in endpointsFor(appId).where((e) => e.isExpanded)) {
      toggleExpanded(ep);
    }
  }

  /// Hands the expanded session over (for opening as a tab) and detaches it
  /// so the controller no longer owns or disposes it. Returns null if the
  /// row was never expanded.
  FlowSession? takeFlow(EndpointState ep) {
    final flow = ep.flow;
    if (flow == null) return null;
    ep.flow = null;
    ep.changed();
    if (isRunning) _reconcilePingers();
    return flow;
  }
}

class _PingerHandle {
  _PingerHandle(this.pinger, this.subscription);
  final EndpointPinger pinger;
  final StreamSubscription<int> subscription;

  void dispose() {
    subscription.cancel();
    pinger.dispose();
  }
}
