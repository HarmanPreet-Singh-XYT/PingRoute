import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:PingRoute/flow_session.dart';
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

    test('calculateCumulativeJitter calculates properly', () {
      final hops = [
        {
          'pings': [
            {'value': 10},
          ]
        },
        {
          'pings': [
            {'value': 20},
            {'value': 30},
          ]
        }
      ];
      final jitter = calculateCumulativeJitter(hops, 1);
      // values: [10, 20, 30], delays: |20-10| = 10, |30-20| = 10 -> avg = 10.0
      expect(jitter, 10.0);
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
