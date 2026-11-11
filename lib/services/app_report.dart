import 'dart:convert';

import '../models/app_session.dart';

/// Plain-data export of what App Mode currently knows, for pasting into
/// tickets, spreadsheets or chat.
List<Map<String, Object?>> endpointRecords(
  Iterable<EndpointState> endpoints,
  String Function(String appId) appName,
  int lossAlertPercent,
) => [
  for (final e in endpoints)
    {
      'app': appName(e.appId),
      'ip': e.ip,
      'hostname': e.hostname,
      'service': e.primaryService,
      'protocols': e.protocols.toList()..sort(),
      'ports': e.ports.toList()..sort(),
      'connections': e.connectionCount,
      'health': e.health(lossAlertPercent).label,
      'probe': e.probe.name,
      'lastMs': e.last != null && e.last! >= 0 ? e.last : null,
      'avgMs': e.averageMs,
      'minMs': e.minMs,
      'maxMs': e.maxMs,
      'jitterMs': e.jitterMs == null
          ? null
          : double.parse(e.jitterMs!.toStringAsFixed(1)),
      'lossPercent': double.parse(e.lossPercent.toStringAsFixed(1)),
      'pingsSent': e.sent,
      'bytesIn': e.sessionIn,
      'bytesOut': e.sessionOut,
      'firstSeen': e.firstSeen.toIso8601String(),
      'lastSeen': e.lastSeen.toIso8601String(),
      'active': e.isActive,
    },
];

String endpointsToJson(List<Map<String, Object?>> records) =>
    const JsonEncoder.withIndent('  ').convert({
      'generatedAt': DateTime.now().toIso8601String(),
      'endpoints': records,
    });

String endpointsToCsv(List<Map<String, Object?>> records) {
  if (records.isEmpty) return '';
  String cell(Object? v) {
    final text = v is List ? v.join(' ') : (v?.toString() ?? '');
    return text.contains(RegExp(r'[",\n]'))
        ? '"${text.replaceAll('"', '""')}"'
        : text;
  }

  final headers = records.first.keys.toList();
  return [
    headers.join(','),
    for (final r in records) headers.map((h) => cell(r[h])).join(','),
  ].join('\n');
}
