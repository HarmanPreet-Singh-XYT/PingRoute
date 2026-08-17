import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';
import 'package:validators/validators.dart';
import 'package:dart_ping/dart_ping.dart';
import '../services/network.dart';
import 'parse_result.dart';
import 'target_directory.dart';

final NetworkLib _networkLib = NetworkLib();

Future<List<String>> _runHeavyTaskWithIsolate(String ip) async {
  final ReceivePort receivePort = ReceivePort();
  List<String> result = [];
  try {
    await Isolate.spawn(_useIsolate, [receivePort.sendPort, ip]);
    result = await receivePort.first;
  } on Object catch (e, stackTrace) {
    debugPrint('Isolate Failed: $e');
    debugPrint('Stack Trace: $stackTrace');
    receivePort.close();
    result = await _networkLib.performTraceroute(ip);
  }
  return result;
}

void _useIsolate(List<dynamic> args) async {
  SendPort resultPort = args[0];
  final value = await _networkLib.performTraceroute(args[1]);
  resultPort.send(value);
}

double calculateCumulativeJitter(List<Map<String, dynamic>> hops, int targetIndex) {
  if (targetIndex < 0 || targetIndex >= hops.length) {
    return 0.0;
  }

  final dynamic rawPings = hops[targetIndex]['pings'];
  if (rawPings is! List || rawPings.length < 2) {
    return 0.0;
  }

  final validPings = <int>[];
  for (final ping in rawPings) {
    if (ping is Map && ping['value'] is num) {
      final int v = (ping['value'] as num).toInt();
      if (v >= 0) {
        validPings.add(v);
      }
    }
  }

  if (validPings.length < 2) {
    return 0.0;
  }

  int totalDelayVariation = 0;
  for (int i = 1; i < validPings.length; i++) {
    totalDelayVariation += (validPings[i] - validPings[i - 1]).abs();
  }

  final double jitter = totalDelayVariation / (validPings.length - 1);
  return double.parse(jitter.toStringAsFixed(2));
}

String getCurrentTime() {
  final now = DateTime.now();
  return DateFormat('mm:ss').format(now);
}

/// Keeps a single long-lived [Ping] stream open for one hop's target IP,
/// rather than spawning a fresh native pinger every round. On iOS each
/// [Ping] instance owns its own native socket + run-loop timer, so
/// recreating one per hop per round (multiplied across every flow in the
/// 4-flow grid) floods the main run loop and freezes the UI.
class _HopPinger {
  _HopPinger(this.targetIp, {required int timeoutMs}) {
    _ping = Ping(
      targetIp,
      interval: 1,
      timeout: (timeoutMs / 1000).ceil().clamp(1, 60),
    );
    _subscription = _ping.stream.listen((event) {
      if (event is PingResponse) {
        lastValue = event.time?.inMilliseconds ?? -1;
      } else if (event is PingError) {
        lastValue = -1;
      }
      hasResult = true;
    }, onError: (_) {
      lastValue = -1;
      hasResult = true;
    });
  }

  final String targetIp;
  late final Ping _ping;
  late final StreamSubscription<PingEvent> _subscription;
  int lastValue = -1;

  /// True once the native pinger has delivered its first reply/timeout.
  /// Sampling before this point (which can take longer on iOS than
  /// spawning a subprocess does on desktop) would otherwise record a false
  /// packet-loss sample for every round the round-loop got to first —
  /// baking artificial loss into the rolling history right from 0%.
  bool hasResult = false;

  void dispose() {
    _subscription.cancel();
    _ping.stop();
  }
}

enum TimelineEventType {
  packetLoss,
  latencySpike,
  routeChange,
  sessionStart,
  sessionPause,
}

class TimelineEvent {
  final DateTime timestamp;
  final String timeFormatted;
  final TimelineEventType type;
  final int hop;
  final String title;
  final String description;
  final dynamic value;

  TimelineEvent({
    DateTime? timestamp,
    required this.type,
    required this.hop,
    required this.title,
    required this.description,
    this.value,
  })  : timestamp = timestamp ?? DateTime.now(),
        timeFormatted = DateFormat('HH:mm:ss').format(timestamp ?? DateTime.now());

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'type': type.name,
        'hop': hop,
        'title': title,
        'description': description,
        'value': value,
      };

  factory TimelineEvent.fromJson(Map<String, dynamic> json) {
    return TimelineEvent(
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String)
          : null,
      type: TimelineEventType.values.byName(
          json['type'] as String? ?? TimelineEventType.packetLoss.name),
      hop: json['hop'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      value: json['value'],
    );
  }
}

class FlowSession extends ChangeNotifier {
  FlowSession({
    String? id,
    String initialIp = '1.1.1.1',
    String initialInterval = '1000',
  })  : id = id ?? DateTime.now().microsecondsSinceEpoch.toString() {
    ipController = TextEditingController(text: initialIp);
    intervalController = TextEditingController(text: initialInterval);
  }

  final String id;
  late final TextEditingController ipController;
  late final TextEditingController intervalController;

  int graphInterval = 1000;
  int packetsLimit = 25;
  int packetSent = 0;
  int totalPackets = 0;
  int packetSize = 56;
  int maxHops = 30;
  int timeoutMs = 1000;

  List<Map<String, dynamic>>? tracerouteResult;
  bool isLoading = false;
  bool success = false;
  bool isRunning = false;
  bool dataCollected = false;
  List<Map<String, dynamic>> ipStats = [];
  List<Map<String, dynamic>> deepStats = [];
  List<Map<String, dynamic>> dataTypes = [];
  List<List<Map<String, dynamic>>> timelineHistory = [];
  List<TimelineEvent> timelineEvents = [];

  bool showMetricCards = true;
  bool showControls = true;
  bool showGraphPills = true;
  String activeMetric = 'lt';
  int bottomViewMode = 0;
  int? bottomSelectedHop;
  String bottomDataType = 'pl';

  bool isStatisticsVisible = false;
  bool _isDisposed = false;

  bool get isDisposed => _isDisposed;

  /// True for a tab opened from a saved [Snapshot] to replay recorded
  /// telemetry rather than run a live probe. Guards [execTraceroute] and
  /// [reset] so pressing play/reset on a replay tab can't wipe the loaded
  /// snapshot data (it would otherwise always fail the `canResume` check
  /// and fall into the destructive re-trace path).
  bool isReplay = false;

  final List<_HopPinger?> _hopPingers = [];

  void setBottomViewMode(int mode) {
    if (bottomViewMode != mode) {
      bottomViewMode = mode;
      notifyListeners();
    }
  }

  void setBottomSelectedHop(int hop) {
    if (bottomSelectedHop != hop) {
      bottomSelectedHop = hop;
      notifyListeners();
    }
  }

  void setBottomDataType(String type) {
    if (bottomDataType != type) {
      bottomDataType = type;
      notifyListeners();
    }
  }

  void addTimelineEvent(TimelineEvent event, {bool notify = true}) {
    timelineEvents.insert(0, event);
    if (timelineEvents.length > 200) {
      timelineEvents.removeLast();
    }
    if (notify) {
      notifyListeners();
    }
  }

  void toggleMetricCards([bool? value]) {
    showMetricCards = value ?? !showMetricCards;
    notifyListeners();
  }

  void toggleControls([bool? value]) {
    showControls = value ?? !showControls;
    notifyListeners();
  }

  void toggleGraphPills([bool? value]) {
    showGraphPills = value ?? !showGraphPills;
    notifyListeners();
  }

  void setActiveMetric(String metric) {
    if (activeMetric != metric) {
      activeMetric = metric;
      notifyListeners();
    }
  }

  void copySettingsFrom(FlowSession source) {
    showMetricCards = source.showMetricCards;
    showControls = source.showControls;
    showGraphPills = source.showGraphPills;
    activeMetric = source.activeMetric;
    graphInterval = source.graphInterval;
    packetsLimit = source.packetsLimit;
    packetSize = source.packetSize;
    maxHops = source.maxHops;
    timeoutMs = source.timeoutMs;
    notifyListeners();
  }

  String get ip {
    var text = ipController.text.trim();
    if (text.contains('(') && text.contains(')')) {
      final match = RegExp(r'^([^\(\s]+)').firstMatch(text);
      if (match != null && match.group(1)!.isNotEmpty) {
        text = match.group(1)!.trim();
      }
    }
    if (text.startsWith('http://') || text.startsWith('https://')) {
      try {
        final uri = Uri.parse(text);
        if (uri.host.isNotEmpty) {
          text = uri.host;
        }
      } catch (_) {}
    }
    return text.isEmpty ? '1.1.1.1' : text;
  }

  int get interval {
    final val = int.tryParse(intervalController.text.trim());
    return (val != null && val > 0) ? val : 1000;
  }

  String get title {
    final text = ipController.text.trim();
    return text.isEmpty ? 'New Flow' : text;
  }

  void setText(String text, String type) {
    switch (type) {
      case 'ip':
        if (ipController.text != text) {
          ipController.value = TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
          );
        }
        break;
      case 'interval':
        if (intervalController.text != text) {
          intervalController.value = TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
          );
        }
        break;
    }
  }

  void changeSettingParams(String text, String type) {
    switch (type) {
      case 'graphInterval':
        if (isNumeric(text) && text != '' && text != '0') {
          final val = int.parse(text);
          if (val > 0) {
            graphInterval = val;
            notifyListeners();
          }
        }
        break;
      case 'packetsLimit':
        if (isNumeric(text) && text != '' && text != '0') {
          final val = int.parse(text);
          if (val > 15) {
            packetsLimit = val;
            notifyListeners();
          }
        }
        break;
      case 'packetSize':
        if (isNumeric(text)) {
          final val = int.parse(text);
          if (val >= 28 && val <= 65507) {
            packetSize = val;
            notifyListeners();
          }
        }
        break;
      case 'maxHops':
        if (isNumeric(text)) {
          final val = int.parse(text);
          if (val >= 1 && val <= 64) {
            maxHops = val;
            notifyListeners();
          }
        }
        break;
      case 'timeoutMs':
        if (isNumeric(text)) {
          final val = int.parse(text);
          if (val >= 100 && val <= 10000) {
            timeoutMs = val;
            notifyListeners();
          }
        }
        break;
    }
  }

  /// Exports an ASCII / Markdown formatted MTR report table
  String generateMtrReport() {
    final buffer = StringBuffer();
    final date = DateTime.now().toIso8601String().substring(0, 19).replaceAll('T', ' ');
    buffer.writeln('PingRoute MTR Report');
    buffer.writeln('Target: $ip ($title)');
    buffer.writeln('Date: $date');
    buffer.writeln('Packets: $packetSent Sent | Size: ${packetSize}B | Interval: ${interval}ms');
    buffer.writeln('-------------------------------------------------------------------------------');
    buffer.writeln('HOP  HOST / IP                        LOSS%  SNT   REC   BEST   AVG    WRST   LAST');
    buffer.writeln('-------------------------------------------------------------------------------');

    for (int i = 0; i < ipStats.length; i++) {
      final stat = ipStats[i];
      final hopNum = '${stat['hop'] ?? i + 1}'.padRight(4);
      final rawIp = stat['ip']?.toString() ?? '';
      final rawName = stat['name']?.toString() ?? '';
      final hostStr = (rawIp.isEmpty ? '???' : rawName.isNotEmpty ? '$rawIp ($rawName)' : rawIp).padRight(32);
      final lossStr = '${stat['pl'] ?? 0}%'.padLeft(5);
      final sntStr = '${stat['sentPackets'] ?? packetSent}'.padLeft(5);
      final recStr = '${stat['receivedPackets'] ?? 0}'.padLeft(5);
      final minStr = (stat['min'] == -1 || stat['min'] == null ? '-' : '${stat['min']}ms').padLeft(7);
      final avgStr = (stat['avg'] == -1 || stat['avg'] == null ? '-' : '${stat['avg']}ms').padLeft(7);
      final maxStr = (stat['max'] == -1 || stat['max'] == null ? '-' : '${stat['max']}ms').padLeft(7);
      final lastStr = (stat['last'] == -1 || stat['last'] == null ? '-' : '${stat['last']}ms').padLeft(7);

      buffer.writeln('$hopNum $hostStr $lossStr $sntStr $recStr $minStr $avgStr $maxStr $lastStr');
    }
    buffer.writeln('-------------------------------------------------------------------------------');
    return buffer.toString();
  }

  /// Exports a standard CSV format of the current flow
  String generateCsvReport() {
    final buffer = StringBuffer();
    buffer.writeln('Hop,IP,Hostname,LossPercent,Sent,Received,MinMs,AvgMs,MaxMs,LastMs');
    for (int i = 0; i < ipStats.length; i++) {
      final s = ipStats[i];
      buffer.writeln(
        '${s['hop'] ?? i + 1},'
        '"${s['ip'] ?? ''}",'
        '"${s['name'] ?? ''}",'
        '${s['pl'] ?? 0},'
        '${s['sentPackets'] ?? packetSent},'
        '${s['receivedPackets'] ?? 0},'
        '${s['min'] ?? -1},'
        '${s['avg'] ?? -1},'
        '${s['max'] ?? -1},'
        '${s['last'] ?? -1}',
      );
    }
    return buffer.toString();
  }

  /// Exports full session telemetry as JSON string
  String generateJsonReport() {
    final data = {
      'target': ip,
      'title': title,
      'timestamp': DateTime.now().toIso8601String(),
      'packetSent': packetSent,
      'packetSize': packetSize,
      'interval': interval,
      'graphInterval': graphInterval,
      'hops': ipStats,
      'deepStats': deepStats,
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  void setDataType(int index, String type) {
    if (index >= 0 && index < dataTypes.length) {
      dataTypes[index]['dataType'] = type;
      notifyListeners();
    }
  }

  void toggleStatistics() {
    isStatisticsVisible = !isStatisticsVisible;
    notifyListeners();
  }

  void setStatisticsVisible(bool visible) {
    if (isStatisticsVisible != visible) {
      isStatisticsVisible = visible;
      notifyListeners();
    }
  }

  String? _lastTracedIp;

  /// Fired whenever [stop] transitions this session from running to
  /// stopped, so callers can auto-save the session's telemetry the moment
  /// the user pauses/stops a live probe instead of only on a timer.
  VoidCallback? onStop;

  void stop() {
    final wasRunning = isRunning;
    isRunning = false;
    _disposeHopPingers();
    notifyListeners();
    if (wasRunning) onStop?.call();
  }

  void _disposeHopPingers() {
    for (final pinger in _hopPingers) {
      pinger?.dispose();
    }
    _hopPingers.clear();
  }

  void _startHopPingers() {
    _disposeHopPingers();
    for (final stat in ipStats) {
      final targetIp = stat['ip'] as String? ?? '';
      _hopPingers.add(
        targetIp.isEmpty ? null : _HopPinger(targetIp, timeoutMs: timeoutMs),
      );
    }
  }

  void reset() {
    if (isReplay) return;
    stop();
    isLoading = false;
    success = false;
    dataCollected = false;
    packetSent = 0;
    totalPackets = 0;
    ipStats = [];
    deepStats = [];
    dataTypes = [];
    timelineHistory = [];
    timelineEvents = [];
    tracerouteResult = null;
    _lastTracedIp = null;
    notifyListeners();
  }

  Future<void> execTraceroute({VoidCallback? onError, bool forceFresh = false}) async {
    if (isReplay) return;
    if (isRunning) {
      stop();
      return;
    }

    final currentIp = ip;
    final canResume = !forceFresh &&
        dataCollected &&
        ipStats.isNotEmpty &&
        _lastTracedIp == currentIp;

    if (canResume) {
      // Resume existing session directly without resetting packet counts or history
      isRunning = true;
      _startHopPingers();
      notifyListeners();
      runPingsWithDelay();
    } else {
      await performTraceroute(onError: onError);
      if (isRunning && !_isDisposed) {
        runPingsWithDelay();
      }
    }
  }

  Future<void> performTraceroute({VoidCallback? onError}) async {
    final currentIp = ip;
    if (isIP(currentIp) || isURL(currentIp)) {
      TargetDirectory.instance.addRecent(currentIp);
      _lastTracedIp = currentIp;
      isRunning = true;
      isLoading = true;
      success = false;
      packetSent = 0;
      dataCollected = false;
      ipStats = [];
      deepStats = [];
      dataTypes = [];
      timelineHistory = [];
      notifyListeners();

      final result = await _runHeavyTaskWithIsolate(currentIp);
      if (_isDisposed) return;

      if (result.isNotEmpty) {
        success = true;
      }

      final parsedList = parseArrayOfStrings(result);
      for (int x = 0; x < parsedList.length; x++) {
        ipStats.add({
          'hop': parsedList[x]['hop'],
          'ip': parsedList[x]['ip'],
          'name': parsedList[x]['name'],
          'max': -1,
          'min': -1,
          'last': -1,
          'avg': -1,
          'pl': 0,
          'receivedPackets': 0,
          'sentPackets': 0,
        });
        deepStats.add({
          'hop': parsedList[x]['hop'],
          'avg': <Map<String, dynamic>>[],
          'pl': <Map<String, dynamic>>[],
          'jitter': <Map<String, dynamic>>[],
          'pings': <Map<String, dynamic>>[],
        });
        timelineHistory.add(<Map<String, dynamic>>[]);
        dataTypes.add({'hop': parsedList[x]['hop'], 'dataType': 'lt'});
      }
      totalPackets = 0;

      if (success) {
        tracerouteResult = parsedList;
        dataCollected = true;
        _startHopPingers();
        _resolveHopNamesAsync();
      } else {
        isRunning = false;
        onError?.call();
      }
      isLoading = false;
      notifyListeners();
    }
  }

  /// Asynchronously performs reverse DNS resolution for all hop IPs in parallel
  /// after the traceroute layout is rendered. Updates `ipStats[x]['name']` live
  /// as hostnames arrive without blocking execution.
  void _resolveHopNamesAsync() {
    if (!Platform.isLinux) return;
    for (int i = 0; i < ipStats.length; i++) {
      final hopIp = ipStats[i]['ip'] as String? ?? '';
      if (hopIp.isNotEmpty && isIP(hopIp)) {
        InternetAddress(hopIp).reverse().timeout(const Duration(seconds: 3)).then((host) {
          if (_isDisposed) return;
          if (host.host.isNotEmpty && host.host != hopIp) {
            ipStats[i]['name'] = host.host;
            final res = tracerouteResult;
            if (res != null && i < res.length) {
              res[i]['name'] = host.host;
            }
            notifyListeners();
          }
        }).catchError((_) {});
      }
    }
  }

  Future<void> runPingsWithDelay() async {
    while (isRunning && ipStats.isNotEmpty && !_isDisposed) {
      final roundStart = DateTime.now();
      final String time = getCurrentTime();
      if (!isRunning || _isDisposed) break;

      // Sample the latest value from each hop's persistent pinger instead of
      // spawning a fresh native Ping per hop per round (see _HopPinger).
      // A hop with no pinger result yet is skipped rather than recorded as
      // loss — the pinger can take longer to deliver its first reply on iOS
      // than a round takes to come around, and recording -1 in that window
      // used to bake false 100% packet loss into the rolling history.
      final List<int?> tempPings = [
        for (int x = 0; x < ipStats.length; x++)
          x < _hopPingers.length
              ? (_hopPingers[x] == null
                  ? -1
                  : (_hopPingers[x]!.hasResult ? _hopPingers[x]!.lastValue : null))
              : -1,
      ];
      if (!isRunning || _isDisposed) break;

      if (deepStats.isNotEmpty) {
        for (int y = 0; y < tempPings.length; y++) {
          final int? val = tempPings[y];
          if (val == null) continue;
          packetSent++;
          ipStats[y]['sentPackets'] = (ipStats[y]['sentPackets'] as int) + 1;
          if (totalPackets < packetsLimit) totalPackets += 1;

          deepStats[y]['pings'].add({'time': time, 'value': val});
          if (val != -1) {
            ipStats[y]['receivedPackets'] = (ipStats[y]['receivedPackets'] as int) + 1;
            if (ipStats[y]['max'] == -1 || val > (ipStats[y]['max'] as int)) {
              ipStats[y]['max'] = val;
            }
            if (ipStats[y]['min'] == -1 || val < (ipStats[y]['min'] as int)) {
              ipStats[y]['min'] = val;
            }
            ipStats[y]['last'] = val;
          } else {
            ipStats[y]['last'] = -1;
          }

          int validPacketloss = 0;
          final List pingsList = deepStats[y]['pings'];
          for (final each in pingsList) {
            if (each['value'] == -1) {
              validPacketloss++;
            }
          }

          final int actualPingCount = pingsList.length;
          final int calculatedPL =
              actualPingCount > 0 ? (validPacketloss * 100 / actualPingCount).round() : 0;

          deepStats[y]['pl'].add({
            'time': time,
            'value': calculatedPL <= 100 ? calculatedPL : 100,
          });
          ipStats[y]['pl'] = calculatedPL <= 100 ? calculatedPL : 100;

          num totalAVG = 0;
          int count = 0;
          for (final each in pingsList) {
            if (each['value'] != -1) {
              totalAVG += (each['value'] as num);
              count++;
            }
          }

          final double jitter = calculateCumulativeJitter(deepStats, y);
          deepStats[y]['jitter'].add({'time': time, 'value': jitter});

          final num avgPing = count > 0 ? (totalAVG / count).round() : 0;
          deepStats[y]['avg'].add({'time': time, 'value': avgPing});
          ipStats[y]['avg'] = avgPing;

          // Record long-term timeline history point (retained up to 7200 points / 2 hours)
          if (y < timelineHistory.length) {
            timelineHistory[y].add({
              'time': time,
              'value': val,
              'jitter': jitter,
              'pl': calculatedPL,
              'avg': avgPing,
              'timestamp': roundStart,
            });
            if (timelineHistory[y].length > 7200) {
              timelineHistory[y].removeAt(0);
            }
          }

          // Event detection for notable incidents
          final hopNum = (ipStats[y]['hop'] as int?) ?? (y + 1);
          final hopName = ipStats[y]['name']?.toString().isNotEmpty == true
              ? ipStats[y]['name']
              : (ipStats[y]['ip'] ?? 'Hop $hopNum');

          if (val == -1 && (pingsList.length < 2 || pingsList[pingsList.length - 2]['value'] != -1)) {
            addTimelineEvent(
              TimelineEvent(
                type: TimelineEventType.packetLoss,
                hop: hopNum,
                title: 'Packet Loss on Hop $hopNum',
                description: 'Request timed out / packet dropped on $hopName',
                value: -1,
              ),
              notify: false,
            );
          } else if (val > 150 && avgPing > 0 && val > (avgPing * 2.2)) {
            addTimelineEvent(
              TimelineEvent(
                type: TimelineEventType.latencySpike,
                hop: hopNum,
                title: 'Latency Spike: ${val}ms',
                description: 'Surged from ${avgPing}ms avg to ${val}ms on Hop $hopNum ($hopName)',
                value: val,
              ),
              notify: false,
            );
          }

          if (deepStats[y]['pl'].length > packetsLimit) deepStats[y]['pl'].removeAt(0);
          if (deepStats[y]['jitter'].length > packetsLimit) deepStats[y]['jitter'].removeAt(0);
          if (deepStats[y]['pings'].length > packetsLimit) deepStats[y]['pings'].removeAt(0);
          if (deepStats[y]['avg'].length > packetsLimit) deepStats[y]['avg'].removeAt(0);
        }
      }

      notifyListeners();

      final elapsed = DateTime.now().difference(roundStart);
      final remaining = Duration(milliseconds: interval) - elapsed;
      if (remaining > Duration.zero) {
        await Future.delayed(remaining);
      }
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    isRunning = false;
    _disposeHopPingers();
    ipController.dispose();
    intervalController.dispose();
    super.dispose();
  }
}
