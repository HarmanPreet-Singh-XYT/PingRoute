import 'package:fluent_ui/fluent_ui.dart';

import '../core/theme.dart';
import '../services/app_connection_service.dart';

/// Latency above these (ms) is flagged, matching the rest of the app.
const int kWarnLatencyMs = 100;
const int kBadLatencyMs = 200;

/// How an endpoint is doing, from its recent ping history.
enum EndpointHealth {
  good('Good', 'Replies are fast and stable.'),
  degraded(
    'Degraded',
    'Some packet loss or latency above $kWarnLatencyMs ms recently.',
  ),
  poor(
    'Poor',
    'Heavy packet loss or latency above $kBadLatencyMs ms recently.',
  ),
  noReply(
    'No ping reply',
    "This host doesn't answer ping. That is common for servers that block "
        'ICMP; the connection itself is still open.',
  ),
  measuring('Measuring', 'Waiting for the first ping replies.'),
  notPinged(
    'Not pinged',
    'Live pings are capped to keep the app light. Raise the limit in '
        'settings or expand the row to trace it.',
  ),
  idle('Closed', 'The app is no longer connected to this address.');

  const EndpointHealth(this.label, this.description);
  final String label;
  final String description;

  /// True for states worth drawing the user's attention to.
  bool get isProblem => this == poor || this == degraded;

  Color color(AppColors colors) => switch (this) {
    good => colors.latencyGood,
    degraded => colors.latencyWarn,
    poor => colors.latencyBad,
    _ => colors.textSecondary,
  };
}

enum ActivityKind {
  connected('Connected'),
  closed('Closed'),
  degraded('Degraded'),
  recovered('Recovered'),
  started('Tracking');

  const ActivityKind(this.label);
  final String label;
}

class ActivityEvent {
  ActivityEvent({
    required this.time,
    required this.kind,
    required this.appId,
    required this.appName,
    required this.message,
    this.ip,
  });

  final DateTime time;
  final ActivityKind kind;
  final String appId;
  final String appName;
  final String message;
  final String? ip;
}

/// A single throughput sample (bytes per second).
typedef RateSample = ({double inBps, double outBps});

/// Aggregated numbers for one tracked application.
class AppSummary {
  const AppSummary({
    required this.endpointCount,
    required this.activeCount,
    required this.connectionCount,
    required this.newLastMinute,
    required this.pingedCount,
    required this.avgMs,
    required this.fastestIp,
    required this.fastestMs,
    required this.slowestIp,
    required this.slowestMs,
    required this.lossPercent,
    required this.jitterMs,
    required this.problemCount,
    required this.stateCounts,
    required this.serviceCounts,
    required this.ipv4Count,
    required this.ipv6Count,
    required this.tcpConnections,
    required this.udpConnections,
    required this.inRate,
    required this.outRate,
    required this.sessionIn,
    required this.sessionOut,
    required this.trafficAvailable,
    required this.processCount,
    required this.cpuPercent,
    required this.rssKb,
    required this.uptime,
  });

  final int endpointCount;
  final int activeCount;
  final int connectionCount;
  final int newLastMinute;
  final int pingedCount;
  final int? avgMs;
  final String? fastestIp;
  final int? fastestMs;
  final String? slowestIp;
  final int? slowestMs;
  final double lossPercent;
  final double? jitterMs;
  final int problemCount;
  final Map<String, int> stateCounts;
  final List<MapEntry<String, int>> serviceCounts;
  final int ipv4Count;
  final int ipv6Count;
  final int tcpConnections;
  final int udpConnections;
  final double inRate;
  final double outRate;
  final int sessionIn;
  final int sessionOut;
  final bool trafficAvailable;
  final int processCount;
  final double cpuPercent;
  final int rssKb;
  final Duration? uptime;
}

/// One row of the "top talkers" table.
class TalkerRow {
  const TalkerRow({
    required this.app,
    required this.endpoints,
    required this.connections,
    required this.inRate,
    required this.outRate,
  });

  final AppSnapshot app;
  final int endpoints;
  final int connections;
  final double inRate;
  final double outRate;

  double get rate => inRate + outRate;
}

/// Numbers across every app on the machine.
class OverviewSummary {
  const OverviewSummary({
    required this.appCount,
    required this.endpointCount,
    required this.connectionCount,
    required this.trackedApps,
    required this.stateCounts,
    required this.serviceCounts,
    required this.inRate,
    required this.outRate,
    required this.trafficAvailable,
    required this.talkers,
  });

  final int appCount;
  final int endpointCount;
  final int connectionCount;
  final int trackedApps;
  final Map<String, int> stateCounts;
  final List<MapEntry<String, int>> serviceCounts;
  final double inRate;
  final double outRate;
  final bool trafficAvailable;
  final List<TalkerRow> talkers;
}

List<MapEntry<String, int>> sortedCounts(Map<String, int> counts) =>
    counts.entries.toList()..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      return byCount != 0 ? byCount : a.key.compareTo(b.key);
    });
