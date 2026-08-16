import 'flow_session.dart';

class Snapshot {
  final String id;
  final String name;
  final String target;
  final String title;
  final DateTime createdAt;
  final int durationMs;
  final int interval;
  final bool isAuto;
  final List<Map<String, dynamic>> ipStats;
  final List<List<Map<String, dynamic>>> timelineHistory;
  final List<TimelineEvent> timelineEvents;

  Snapshot({
    String? id,
    required this.name,
    required this.target,
    required this.title,
    DateTime? createdAt,
    this.durationMs = 0,
    this.interval = 1000,
    this.isAuto = false,
    List<Map<String, dynamic>>? ipStats,
    List<List<Map<String, dynamic>>>? timelineHistory,
    List<TimelineEvent>? timelineEvents,
  })  : id = id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        createdAt = createdAt ?? DateTime.now(),
        ipStats = ipStats ?? [],
        timelineHistory = timelineHistory ?? [],
        timelineEvents = timelineEvents ?? [];

  factory Snapshot.fromFlowSession(FlowSession flow,
      {required String name, bool isAuto = false, String? id}) {
    final timelineHistory = flow.timelineHistory
        .map((hopHistory) => hopHistory
            .map((point) => <String, dynamic>{
                  ...point,
                  'timestamp': (point['timestamp'] as DateTime).toIso8601String(),
                })
            .toList())
        .toList();

    DateTime? firstTimestamp;
    DateTime? lastTimestamp;
    for (final hopHistory in flow.timelineHistory) {
      for (final point in hopHistory) {
        final ts = point['timestamp'] as DateTime;
        if (firstTimestamp == null || ts.isBefore(firstTimestamp)) {
          firstTimestamp = ts;
        }
        if (lastTimestamp == null || ts.isAfter(lastTimestamp)) {
          lastTimestamp = ts;
        }
      }
    }
    final durationMs = (firstTimestamp != null && lastTimestamp != null)
        ? lastTimestamp.difference(firstTimestamp).inMilliseconds
        : 0;

    return Snapshot(
      id: id,
      name: name,
      target: flow.ip,
      title: flow.title,
      durationMs: durationMs,
      interval: flow.interval,
      isAuto: isAuto,
      ipStats: List<Map<String, dynamic>>.from(
          flow.ipStats.map((e) => Map<String, dynamic>.from(e))),
      timelineHistory: timelineHistory,
      timelineEvents: List<TimelineEvent>.from(flow.timelineEvents),
    );
  }

  /// Builds a read-only [FlowSession] pre-filled with this snapshot's
  /// recorded telemetry, for opening in a new tab via the existing live-flow
  /// UI (Navbar / LeftData / BottomData) instead of a bespoke viewer.
  FlowSession toFlowSession() {
    final flow = FlowSession(initialIp: target, initialInterval: '$interval');

    final rebuiltDeepStats = <Map<String, dynamic>>[];
    for (int i = 0; i < ipStats.length; i++) {
      final hopNum = ipStats[i]['hop'] as int? ?? (i + 1);
      final history = i < timelineHistory.length ? timelineHistory[i] : const [];

      rebuiltDeepStats.add({
        'hop': hopNum,
        'avg': [
          for (final p in history) {'time': p['time'], 'value': p['avg'] ?? 0}
        ],
        'pl': [
          for (final p in history) {'time': p['time'], 'value': p['pl'] ?? 0}
        ],
        'jitter': [
          for (final p in history)
            {'time': p['time'], 'value': p['jitter'] ?? 0.0}
        ],
        'pings': [
          for (final p in history) {'time': p['time'], 'value': p['value']}
        ],
      });
    }

    final rebuiltTimelineHistory = timelineHistory
        .map((hopHistory) => hopHistory
            .map((point) => <String, dynamic>{
                  ...point,
                  'timestamp':
                      DateTime.tryParse(point['timestamp'] as String? ?? '') ??
                          DateTime.now(),
                })
            .toList())
        .toList();

    flow.ipStats = List<Map<String, dynamic>>.from(
        ipStats.map((e) => Map<String, dynamic>.from(e)));
    flow.deepStats = rebuiltDeepStats;
    flow.dataTypes = [
      for (final stat in ipStats) {'hop': stat['hop'], 'dataType': 'lt'}
    ];
    flow.timelineHistory = rebuiltTimelineHistory;
    flow.timelineEvents = List<TimelineEvent>.from(timelineEvents);
    flow.tracerouteResult = List<Map<String, dynamic>>.from(
        ipStats.map((e) => Map<String, dynamic>.from(e)));
    flow.dataCollected = true;
    flow.success = true;
    flow.isRunning = false;
    flow.isLoading = false;
    flow.isReplay = true;

    return flow;
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'id': id,
        'name': name,
        'target': target,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'durationMs': durationMs,
        'interval': interval,
        'isAuto': isAuto,
        'ipStats': ipStats,
        'timelineHistory': timelineHistory,
        'timelineEvents': timelineEvents.map((e) => e.toJson()).toList(),
      };

  factory Snapshot.fromJson(Map<String, dynamic> json) {
    final ipStats = <Map<String, dynamic>>[];
    if (json['ipStats'] is List) {
      for (final item in json['ipStats']) {
        if (item is Map<String, dynamic>) {
          ipStats.add(item);
        } else if (item is Map) {
          ipStats.add(Map<String, dynamic>.from(item));
        }
      }
    }

    final timelineHistory = <List<Map<String, dynamic>>>[];
    if (json['timelineHistory'] is List) {
      for (final hopHistory in json['timelineHistory']) {
        final points = <Map<String, dynamic>>[];
        if (hopHistory is List) {
          for (final point in hopHistory) {
            if (point is Map) {
              points.add(Map<String, dynamic>.from(point));
            }
          }
        }
        timelineHistory.add(points);
      }
    }

    final timelineEvents = <TimelineEvent>[];
    if (json['timelineEvents'] is List) {
      for (final item in json['timelineEvents']) {
        if (item is Map<String, dynamic>) {
          timelineEvents.add(TimelineEvent.fromJson(item));
        } else if (item is Map) {
          timelineEvents.add(TimelineEvent.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    return Snapshot(
      id: json['id'] as String?,
      name: json['name'] as String? ?? '',
      target: json['target'] as String? ?? '',
      title: json['title'] as String? ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      durationMs: json['durationMs'] as int? ?? 0,
      interval: json['interval'] as int? ?? 1000,
      isAuto: json['isAuto'] as bool? ?? false,
      ipStats: ipStats,
      timelineHistory: timelineHistory,
      timelineEvents: timelineEvents,
    );
  }
}

class SnapshotMeta {
  final String id;
  final String name;
  final String target;
  final String title;
  final DateTime createdAt;
  final int durationMs;
  final bool isAuto;

  SnapshotMeta({
    required this.id,
    required this.name,
    required this.target,
    required this.title,
    required this.createdAt,
    this.durationMs = 0,
    this.isAuto = false,
  });

  factory SnapshotMeta.fromSnapshot(Snapshot snapshot) => SnapshotMeta(
        id: snapshot.id,
        name: snapshot.name,
        target: snapshot.target,
        title: snapshot.title,
        createdAt: snapshot.createdAt,
        durationMs: snapshot.durationMs,
        isAuto: snapshot.isAuto,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'target': target,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'durationMs': durationMs,
        'isAuto': isAuto,
      };

  factory SnapshotMeta.fromJson(Map<String, dynamic> json) {
    return SnapshotMeta(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      target: json['target'] as String? ?? '',
      title: json['title'] as String? ?? '',
      isAuto: json['isAuto'] as bool? ?? false,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      durationMs: json['durationMs'] as int? ?? 0,
    );
  }
}
