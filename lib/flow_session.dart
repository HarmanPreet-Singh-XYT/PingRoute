import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';
import 'package:validators/validators.dart';
import 'package:dart_ping/dart_ping.dart';
import 'network.dart';
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

  bool isStatisticsVisible = false;
  bool _isDisposed = false;

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

  void stop() {
    isRunning = false;
    notifyListeners();
  }

  void reset() {
    stop();
    isLoading = false;
    success = false;
    dataCollected = false;
    packetSent = 0;
    totalPackets = 0;
    ipStats = [];
    deepStats = [];
    dataTypes = [];
    tracerouteResult = null;
    _lastTracedIp = null;
    notifyListeners();
  }

  Future<void> execTraceroute({VoidCallback? onError, bool forceFresh = false}) async {
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
        dataTypes.add({'hop': parsedList[x]['hop'], 'dataType': 'lt'});
      }
      totalPackets = 0;

      if (success) {
        tracerouteResult = parsedList;
        dataCollected = true;
      } else {
        isRunning = false;
        onError?.call();
      }
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> runPingsWithDelay() async {
    while (isRunning && ipStats.isNotEmpty && !_isDisposed) {
      final roundStart = DateTime.now();
      final String time = getCurrentTime();
      if (!isRunning || _isDisposed) break;

      final List<Future<int>> pingFutures = [];

      for (int x = 0; x < ipStats.length; x++) {
        final String targetIp = ipStats[x]['ip'] ?? '';
        if (targetIp.isEmpty) {
          pingFutures.add(Future.value(-1));
          continue;
        }
        pingFutures.add(
          Ping(targetIp, count: 1, interval: 1).stream.first.then((result) {
            try {
              return result.response?.time?.inMilliseconds ?? -1;
            } catch (e) {
              return -1;
            }
          }).catchError((e) => -1),
        );
      }

      final List<int> tempPings = await Future.wait(pingFutures);
      if (!isRunning || _isDisposed) break;

      if (deepStats.isNotEmpty) {
        for (int y = 0; y < tempPings.length; y++) {
          final int val = tempPings[y];
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
    ipController.dispose();
    intervalController.dispose();
    super.dispose();
  }
}
