import 'package:fluent_ui/fluent_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum EndpointSort {
  firstSeen('First seen'),
  latency('Latency'),
  loss('Packet loss'),
  connections('Connections'),
  traffic('Traffic'),
  address('Address');

  const EndpointSort(this.label);
  final String label;
}

enum TrackingMode {
  everything(
    'All apps',
    'Every app with network activity is listed with its totals. Pick one '
        'to monitor its servers.',
  ),
  selected(
    'Only apps I choose',
    'Nothing is monitored until you tick an app. Overview totals and pings '
        'cover just the apps you tick; you can tick several.',
  );

  const TrackingMode(this.label, this.description);
  final String label;
  final String description;
}

enum RowDensity {
  comfortable('Comfortable'),
  compact('Compact');

  const RowDensity(this.label);
  final String label;
}

/// User preferences for App Mode, persisted with SharedPreferences.
class AppModeSettings extends ChangeNotifier {
  AppModeSettings._() : _persist = true;

  /// In-memory instance for tests; never touches disk.
  AppModeSettings.test({
    int pollIntervalSec = 3,
    int maxLivePingers = 12,
    int pingIntervalSec = 1,
    int idleRetentionSec = 60,
    bool hideSystemApps = true,
    bool includePrivate = false,
    bool includeUdp = true,
    bool tcpFallback = true,
    TrackingMode trackingMode = TrackingMode.everything,
    int lossAlertPercent = 5,
    RowDensity density = RowDensity.comfortable,
    EndpointSort defaultSort = EndpointSort.firstSeen,
    bool rememberSelection = true,
  }) : _persist = false,
       _pollIntervalSec = pollIntervalSec,
       _maxLivePingers = maxLivePingers,
       _pingIntervalSec = pingIntervalSec,
       _idleRetentionSec = idleRetentionSec,
       _hideSystemApps = hideSystemApps,
       _includePrivate = includePrivate,
       _includeUdp = includeUdp,
       _tcpFallback = tcpFallback,
       _trackingMode = trackingMode,
       _lossAlertPercent = lossAlertPercent,
       _density = density,
       _defaultSort = defaultSort,
       _rememberSelection = rememberSelection;

  static final AppModeSettings instance = AppModeSettings._();

  static const pollIntervalChoices = [1, 2, 3, 5, 10];
  static const pingIntervalChoices = [1, 2, 5];
  static const idleRetentionChoices = [15, 30, 60, 120, 300];
  static const lossAlertChoices = [1, 2, 5, 10, 25];
  static const minPingers = 2;
  static const maxPingersLimit = 40;

  final bool _persist;
  bool _loaded = false;

  int _pollIntervalSec = 3;
  int _maxLivePingers = 12;
  int _pingIntervalSec = 1;
  int _idleRetentionSec = 60;
  bool _hideSystemApps = true;
  bool _includePrivate = false;
  bool _includeUdp = true;
  bool _tcpFallback = true;
  TrackingMode _trackingMode = TrackingMode.everything;
  int _lossAlertPercent = 5;
  RowDensity _density = RowDensity.comfortable;
  EndpointSort _defaultSort = EndpointSort.firstSeen;
  bool _rememberSelection = true;
  List<String> _pinnedAppIds = const [];
  List<String> _selectedAppIds = const [];

  int get pollIntervalSec => _pollIntervalSec;
  Duration get pollInterval => Duration(seconds: _pollIntervalSec);
  int get maxLivePingers => _maxLivePingers;
  int get pingIntervalSec => _pingIntervalSec;
  int get idleRetentionSec => _idleRetentionSec;
  Duration get idleRetention => Duration(seconds: _idleRetentionSec);
  bool get hideSystemApps => _hideSystemApps;

  /// Include LAN, loopback and link-local peers (hidden by default).
  bool get includePrivate => _includePrivate;

  /// Include UDP flows such as QUIC / HTTP3 (macOS only).
  bool get includeUdp => _includeUdp;

  /// For hosts that ignore ping, time a TCP connection instead.
  bool get tcpFallback => _tcpFallback;

  TrackingMode get trackingMode => _trackingMode;

  /// Packet-loss percentage at which an endpoint is flagged as poor.
  int get lossAlertPercent => _lossAlertPercent;
  RowDensity get density => _density;
  EndpointSort get defaultSort => _defaultSort;
  bool get rememberSelection => _rememberSelection;
  List<String> get pinnedAppIds => _pinnedAppIds;
  List<String> get selectedAppIds => _selectedAppIds;

  Future<void> load() async {
    if (!_persist || _loaded) return;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      _pollIntervalSec = _pick(
        p.getInt('appmode_poll'),
        pollIntervalChoices,
        _pollIntervalSec,
      );
      _maxLivePingers = (p.getInt('appmode_max_pings') ?? _maxLivePingers)
          .clamp(minPingers, maxPingersLimit);
      _pingIntervalSec = _pick(
        p.getInt('appmode_ping_interval'),
        pingIntervalChoices,
        _pingIntervalSec,
      );
      _idleRetentionSec = _pick(
        p.getInt('appmode_idle'),
        idleRetentionChoices,
        _idleRetentionSec,
      );
      _hideSystemApps = p.getBool('appmode_hide_system') ?? _hideSystemApps;
      _includePrivate = p.getBool('appmode_private') ?? _includePrivate;
      _includeUdp = p.getBool('appmode_udp') ?? _includeUdp;
      _tcpFallback = p.getBool('appmode_tcp') ?? _tcpFallback;
      _trackingMode =
          TrackingMode.values.asNameMap()[p.getString('appmode_tracking')] ??
          _trackingMode;
      _lossAlertPercent = _pick(
        p.getInt('appmode_loss'),
        lossAlertChoices,
        _lossAlertPercent,
      );
      _density =
          RowDensity.values.asNameMap()[p.getString('appmode_density')] ??
          _density;
      _defaultSort =
          EndpointSort.values.asNameMap()[p.getString('appmode_sort')] ??
          _defaultSort;
      _rememberSelection = p.getBool('appmode_remember') ?? _rememberSelection;
      _pinnedAppIds = p.getStringList('appmode_pinned') ?? _pinnedAppIds;
      _selectedAppIds = p.getStringList('appmode_selected') ?? _selectedAppIds;
      notifyListeners();
    } on Object {
      // Preferences unavailable: keep defaults.
    }
  }

  static int _pick(int? value, List<int> allowed, int fallback) =>
      value != null && allowed.contains(value) ? value : fallback;

  Future<void> _save(Future<bool> Function(SharedPreferences p) write) async {
    if (!_persist) return;
    try {
      await write(await SharedPreferences.getInstance());
    } on Object {
      // Best effort.
    }
  }

  void setPollIntervalSec(int v) {
    if (!pollIntervalChoices.contains(v) || v == _pollIntervalSec) return;
    _pollIntervalSec = v;
    _save((p) => p.setInt('appmode_poll', v));
    notifyListeners();
  }

  void setMaxLivePingers(int v) {
    final clamped = v.clamp(minPingers, maxPingersLimit);
    if (clamped == _maxLivePingers) return;
    _maxLivePingers = clamped;
    _save((p) => p.setInt('appmode_max_pings', clamped));
    notifyListeners();
  }

  void setPingIntervalSec(int v) {
    if (!pingIntervalChoices.contains(v) || v == _pingIntervalSec) return;
    _pingIntervalSec = v;
    _save((p) => p.setInt('appmode_ping_interval', v));
    notifyListeners();
  }

  void setIdleRetentionSec(int v) {
    if (!idleRetentionChoices.contains(v) || v == _idleRetentionSec) return;
    _idleRetentionSec = v;
    _save((p) => p.setInt('appmode_idle', v));
    notifyListeners();
  }

  void setHideSystemApps(bool v) {
    if (v == _hideSystemApps) return;
    _hideSystemApps = v;
    _save((p) => p.setBool('appmode_hide_system', v));
    notifyListeners();
  }

  void setIncludePrivate(bool v) {
    if (v == _includePrivate) return;
    _includePrivate = v;
    _save((p) => p.setBool('appmode_private', v));
    notifyListeners();
  }

  void setIncludeUdp(bool v) {
    if (v == _includeUdp) return;
    _includeUdp = v;
    _save((p) => p.setBool('appmode_udp', v));
    notifyListeners();
  }

  void setTcpFallback(bool v) {
    if (v == _tcpFallback) return;
    _tcpFallback = v;
    _save((p) => p.setBool('appmode_tcp', v));
    notifyListeners();
  }

  void setTrackingMode(TrackingMode v) {
    if (v == _trackingMode) return;
    _trackingMode = v;
    _save((p) => p.setString('appmode_tracking', v.name));
    notifyListeners();
  }

  void setLossAlertPercent(int v) {
    if (!lossAlertChoices.contains(v) || v == _lossAlertPercent) return;
    _lossAlertPercent = v;
    _save((p) => p.setInt('appmode_loss', v));
    notifyListeners();
  }

  void setDensity(RowDensity v) {
    if (v == _density) return;
    _density = v;
    _save((p) => p.setString('appmode_density', v.name));
    notifyListeners();
  }

  void setDefaultSort(EndpointSort v) {
    if (v == _defaultSort) return;
    _defaultSort = v;
    _save((p) => p.setString('appmode_sort', v.name));
    notifyListeners();
  }

  void setRememberSelection(bool v) {
    if (v == _rememberSelection) return;
    _rememberSelection = v;
    _save((p) => p.setBool('appmode_remember', v));
    if (!v) {
      _pinnedAppIds = const [];
      _selectedAppIds = const [];
      _save((p) => p.remove('appmode_pinned'));
      _save((p) => p.remove('appmode_selected'));
    }
    notifyListeners();
  }

  /// Stores the current pins and selection (no-op unless remembering).
  void rememberApps({
    required Iterable<String> pinned,
    required Iterable<String> selected,
  }) {
    if (!_rememberSelection) return;
    _pinnedAppIds = pinned.toList();
    _selectedAppIds = selected.toList();
    _save((p) => p.setStringList('appmode_pinned', _pinnedAppIds));
    _save((p) => p.setStringList('appmode_selected', _selectedAppIds));
  }

  void resetToDefaults() {
    _pollIntervalSec = 3;
    _maxLivePingers = 12;
    _pingIntervalSec = 1;
    _idleRetentionSec = 60;
    _hideSystemApps = true;
    _includePrivate = false;
    _includeUdp = true;
    _tcpFallback = true;
    _trackingMode = TrackingMode.everything;
    _lossAlertPercent = 5;
    _density = RowDensity.comfortable;
    _defaultSort = EndpointSort.firstSeen;
    _rememberSelection = true;
    _save((p) async {
      for (final key in p.getKeys().where((k) => k.startsWith('appmode_'))) {
        if (key == 'appmode_pinned' || key == 'appmode_selected') continue;
        await p.remove(key);
      }
      return true;
    });
    notifyListeners();
  }
}
