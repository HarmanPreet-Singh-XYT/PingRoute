import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:PingRoute/dialogs/settings.dart';
import 'package:PingRoute/models/flow_session.dart';
import 'package:PingRoute/main.dart';

void main() {
  group('FlowSession Unit Tests', () {
    test('initializes with default IP and interval', () {
      final session = FlowSession(initialIp: '8.8.8.8', initialInterval: '500');
      expect(session.ip, '8.8.8.8');
      expect(session.interval, 500);
      expect(session.title, '8.8.8.8');
      expect(session.isRunning, isFalse);
      expect(session.isLoading, isFalse);
      session.dispose();
    });

    test('updates target IP and interval via controllers', () {
      final session = FlowSession();
      expect(session.ip, '1.1.1.1');
      session.setText('1.0.0.1', 'ip');
      expect(session.ip, '1.0.0.1');
      expect(session.title, '1.0.0.1');

      session.setText('2000', 'interval');
      expect(session.interval, 2000);
      session.dispose();
    });

    test('sanitizes bracketed names or url prefixes in target IP', () {
      final session = FlowSession(initialIp: '9.9.9.9 (Quad9 DNS)');
      expect(session.ip, '9.9.9.9');

      session.setText('https://cloudflare.com/path', 'ip');
      expect(session.ip, 'cloudflare.com');
      session.dispose();
    });

    test('calculateCumulativeJitter calculates true per-hop packet delay variation', () {
      final hops = [
        {
          'pings': [
            {'value': 2},
            {'value': 4},
            {'value': 3},
            {'value': 5},
          ]
        },
        {
          'pings': [
            {'value': 10},
            {'value': -1}, // timeout should be ignored in delay variation
            {'value': 14},
            {'value': 12},
          ]
        }
      ];

      // Hop 0: |4-2| + |3-4| + |5-3| = 2 + 1 + 2 = 5 / 3 = 1.67
      final jitter0 = calculateCumulativeJitter(hops, 0);
      expect(jitter0, 1.67);

      // Hop 1: valid pings [10, 14, 12]: |14-10| + |12-14| = 4 + 2 = 6 / 2 = 3.0
      final jitter1 = calculateCumulativeJitter(hops, 1);
      expect(jitter1, 3.0);

      // Out of bounds or insufficient pings return 0.0
      expect(calculateCumulativeJitter(hops, -1), 0.0);
      expect(calculateCumulativeJitter(hops, 99), 0.0);
      expect(calculateCumulativeJitter([{'pings': [{'value': 10}]}], 0), 0.0);
    });

    test('reset clears all telemetry and session state', () {
      final session = FlowSession();
      session.dataCollected = true;
      session.packetSent = 50;
      session.ipStats = [
        {'hop': 1, 'ip': '192.168.1.1', 'avg': 5}
      ];
      session.deepStats = [
        {
          'hop': 1,
          'pings': [
            {'time': '12:00:00', 'value': 5}
          ]
        }
      ];

      expect(session.dataCollected, isTrue);
      expect(session.packetSent, 50);

      session.reset();

      expect(session.isRunning, isFalse);
      expect(session.dataCollected, isFalse);
      expect(session.packetSent, 0);
      expect(session.ipStats, isEmpty);
      expect(session.deepStats, isEmpty);
      session.dispose();
    });
  });

  group('TabView Multi-Flow UI Tests', () {
    setUp(() async {
      await AppSettings.instance.setHasCompletedOnboarding(true);
    });

    testWidgets('supports adding new tabs and switching between them', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const PingRouteApp());
      await tester.pumpAndSettle();

      // Initially 1 tab
      expect(find.byType(Tab), findsOneWidget);

      // Find the add flow button
      final addTabButton = find.text('New Flow (⌘T)');
      expect(addTabButton, findsOneWidget);
      await tester.tap(addTabButton);
      await tester.pumpAndSettle();

      // Now 2 tabs exist
      expect(find.byType(Tab), findsNWidgets(2));
    });
  });
}
