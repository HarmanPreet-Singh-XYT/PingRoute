import 'package:flutter_test/flutter_test.dart';
import 'package:PingRoute/models/snapshot.dart';
import 'package:PingRoute/models/flow_session.dart';

void main() {
  group('TimelineEvent JSON roundtrip', () {
    for (final type in TimelineEventType.values) {
      test('roundtrips for type ${type.name}', () {
        final event = TimelineEvent(
          type: type,
          hop: 3,
          title: 'Test Event',
          description: 'Something happened',
          value: 42,
        );

        final json = event.toJson();
        final restored = TimelineEvent.fromJson(json);

        expect(restored.type, event.type);
        expect(restored.hop, event.hop);
        expect(restored.title, event.title);
        expect(restored.description, event.description);
        expect(restored.value, event.value);
        expect(restored.timestamp.toIso8601String(), event.timestamp.toIso8601String());
      });
    }
  });

  group('Snapshot JSON roundtrip', () {
    test('roundtrips basic fields', () {
      final snapshot = Snapshot(
        id: 'snap-123',
        name: 'My Snapshot',
        target: '8.8.8.8',
        title: '8.8.8.8',
        durationMs: 60000,
        interval: 1000,
        ipStats: [
          {
            'hop': 1,
            'ip': '192.168.1.1',
            'name': 'router',
            'max': 10,
            'min': 1,
            'last': 5,
            'avg': 4.5,
            'pl': 0,
            'receivedPackets': 10,
            'sentPackets': 10,
          },
        ],
      );

      final json = snapshot.toJson();
      final restored = Snapshot.fromJson(json);

      expect(restored.id, snapshot.id);
      expect(restored.name, snapshot.name);
      expect(restored.target, snapshot.target);
      expect(restored.title, snapshot.title);
      expect(restored.durationMs, snapshot.durationMs);
      expect(restored.interval, snapshot.interval);
      expect(restored.ipStats, snapshot.ipStats);
      expect(json['version'], 1);
    });

    test('roundtrips timelineHistory with DateTime conversion', () {
      final timestamp = DateTime.utc(2026, 8, 15, 12, 30, 0);
      final snapshot = Snapshot(
        name: 'History Snapshot',
        target: '1.1.1.1',
        title: '1.1.1.1',
        timelineHistory: [
          [
            {
              'time': '00:05',
              'value': 12,
              'jitter': 1.2,
              'pl': 0,
              'avg': 11.5,
              'timestamp': timestamp.toIso8601String(),
            },
          ],
        ],
      );

      final json = snapshot.toJson();
      final restored = Snapshot.fromJson(json);

      expect(restored.timelineHistory.length, 1);
      expect(restored.timelineHistory[0].length, 1);
      final point = restored.timelineHistory[0][0];
      expect(point['value'], 12);
      expect(point['jitter'], 1.2);
      expect(DateTime.parse(point['timestamp'] as String), timestamp);
    });

    test('roundtrips timelineEvents', () {
      final snapshot = Snapshot(
        name: 'Events Snapshot',
        target: '1.1.1.1',
        title: '1.1.1.1',
        timelineEvents: [
          TimelineEvent(
            type: TimelineEventType.latencySpike,
            hop: 2,
            title: 'Spike',
            description: 'Latency spike detected',
            value: 250,
          ),
        ],
      );

      final json = snapshot.toJson();
      final restored = Snapshot.fromJson(json);

      expect(restored.timelineEvents.length, 1);
      expect(restored.timelineEvents[0].type, TimelineEventType.latencySpike);
      expect(restored.timelineEvents[0].hop, 2);
      expect(restored.timelineEvents[0].title, 'Spike');
    });

    test('fromFlowSession builds a snapshot from a live session without mutating it', () {
      final flow = FlowSession(initialIp: '9.9.9.9');
      flow.ipStats = [
        {
          'hop': 1,
          'ip': '9.9.9.9',
          'name': 'quad9',
          'max': 10,
          'min': 1,
          'last': 5,
          'avg': 4.5,
          'pl': 0,
          'receivedPackets': 5,
          'sentPackets': 5,
        },
      ];
      final ts1 = DateTime.utc(2026, 8, 15, 12, 0, 0);
      final ts2 = DateTime.utc(2026, 8, 15, 12, 0, 5);
      flow.timelineHistory = [
        [
          {'time': '00:00', 'value': 5, 'jitter': 0.1, 'pl': 0, 'avg': 5, 'timestamp': ts1},
          {'time': '00:05', 'value': 6, 'jitter': 0.2, 'pl': 0, 'avg': 5.5, 'timestamp': ts2},
        ],
      ];

      final snapshot = Snapshot.fromFlowSession(flow, name: 'From Flow');

      expect(snapshot.target, '9.9.9.9');
      expect(snapshot.interval, 1000);
      expect(snapshot.durationMs, 5000);
      expect(snapshot.timelineHistory[0].length, 2);
      expect(snapshot.timelineHistory[0][0]['timestamp'], ts1.toIso8601String());

      // Original flow data must remain untouched (still raw DateTime).
      expect(flow.timelineHistory[0][0]['timestamp'], isA<DateTime>());

      flow.dispose();
    });

    test('toFlowSession builds a replay-ready FlowSession with populated telemetry', () {
      final ts1 = DateTime.utc(2026, 8, 15, 12, 0, 0);
      final ts2 = DateTime.utc(2026, 8, 15, 12, 0, 1);

      final snapshot = Snapshot(
        name: 'Replay Fixture',
        target: '4.4.4.4',
        title: '4.4.4.4',
        interval: 1000,
        ipStats: [
          {
            'hop': 1,
            'ip': '4.4.4.4',
            'name': 'level3',
            'max': 12,
            'min': 8,
            'last': 10,
            'avg': 10,
            'pl': 0,
            'receivedPackets': 2,
            'sentPackets': 2,
          },
        ],
        timelineHistory: [
          [
            {
              'time': '00:00',
              'value': 8,
              'jitter': 0.1,
              'pl': 0,
              'avg': 8,
              'timestamp': ts1.toIso8601String(),
            },
            {
              'time': '00:01',
              'value': 12,
              'jitter': 0.3,
              'pl': 0,
              'avg': 10,
              'timestamp': ts2.toIso8601String(),
            },
          ],
        ],
      );

      final flow = snapshot.toFlowSession();

      expect(flow.isReplay, isTrue);
      expect(flow.dataCollected, isTrue);
      expect(flow.success, isTrue);
      expect(flow.isRunning, isFalse);
      expect(flow.ipStats, hasLength(1));
      expect(flow.deepStats, hasLength(1));
      expect(flow.deepStats[0]['pings'], hasLength(2));
      expect(flow.deepStats[0]['pings'][1]['value'], 12);
      expect(flow.dataTypes, hasLength(1));
      expect(flow.timelineHistory[0], hasLength(2));
      expect(flow.timelineHistory[0][0]['timestamp'], isA<DateTime>());
      expect(flow.timelineHistory[0][0]['timestamp'], ts1);

      flow.dispose();
    });

    test('replay FlowSession ignores execTraceroute and reset (data preserved)', () async {
      final snapshot = Snapshot(
        name: 'Guard Fixture',
        target: '5.5.5.5',
        title: '5.5.5.5',
        ipStats: [
          {
            'hop': 1,
            'ip': '5.5.5.5',
            'name': '',
            'max': 5,
            'min': 5,
            'last': 5,
            'avg': 5,
            'pl': 0,
            'receivedPackets': 1,
            'sentPackets': 1,
          },
        ],
        timelineHistory: [
          [
            {
              'time': '00:00',
              'value': 5,
              'jitter': 0.0,
              'pl': 0,
              'avg': 5,
              'timestamp': DateTime.utc(2026, 8, 15, 12, 0, 0).toIso8601String(),
            },
          ],
        ],
      );

      final flow = snapshot.toFlowSession();

      await flow.execTraceroute();
      expect(flow.ipStats, hasLength(1));
      expect(flow.dataCollected, isTrue);

      flow.reset();
      expect(flow.ipStats, hasLength(1));
      expect(flow.dataCollected, isTrue);

      flow.dispose();
    });
  });

  group('FlowSession.onStop', () {
    test('fires when stop() transitions from running to stopped', () {
      final flow = FlowSession(initialIp: '1.1.1.1');
      int callCount = 0;
      flow.onStop = () => callCount++;

      flow.isRunning = true;
      flow.stop();
      expect(callCount, 1);

      flow.dispose();
    });

    test('does not fire when stop() is called while already stopped', () {
      final flow = FlowSession(initialIp: '1.1.1.1');
      int callCount = 0;
      flow.onStop = () => callCount++;

      flow.stop(); // never was running
      expect(callCount, 0);

      flow.dispose();
    });
  });
}
