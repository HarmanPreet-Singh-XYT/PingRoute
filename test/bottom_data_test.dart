import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:PingRoute/models/flow_session.dart';
import 'package:PingRoute/widgets/bottom_data.dart';

void main() {
  testWidgets('BottomData wide/landscape layout scrolls without ScrollController conflicts on iOS', (WidgetTester tester) async {
    // Wide enough to trip BottomData's isWide (>= 800) row layout, which
    // renders the stat table and actions column as sibling scrollables —
    // the same layout an iPad in landscape hits on the single-flow view.
    tester.view.physicalSize = const Size(1180, 820);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    // A vertical ScrollView with no explicit controller only falls back to
    // the ambient PrimaryScrollController on mobile platforms, which is how
    // the real "ScrollController attached to more than one ScrollPosition"
    // crash surfaces on iPad but never on a macOS run.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    final flow = FlowSession(initialIp: '1.1.1.1');
    flow.tracerouteResult = [
      {'hop': 1, 'ip': '192.168.1.1', 'name': 'router.local'},
      {'hop': 2, 'ip': '1.1.1.1', 'name': 'one.one.one.one'},
    ];
    flow.ipStats = [
      {'hop': 1, 'ip': '192.168.1.1', 'name': 'router.local', 'min': 2, 'max': 5, 'avg': 3, 'last': 3, 'pl': 0, 'sentPackets': 10, 'receivedPackets': 10},
      {'hop': 2, 'ip': '1.1.1.1', 'name': 'one.one.one.one', 'min': 12, 'max': 18, 'avg': 14, 'last': 13, 'pl': 0, 'sentPackets': 10, 'receivedPackets': 10},
    ];
    flow.deepStats = [
      {
        'hop': 1,
        'pings': [{'time': '12:00:00', 'value': 3}],
        'pl': [{'time': '12:00:00', 'value': 0}],
        'jitter': [{'time': '12:00:00', 'value': 1}],
      },
      {
        'hop': 2,
        'pings': [{'time': '12:00:00', 'value': 14}],
        'pl': [{'time': '12:00:00', 'value': 0}],
        'jitter': [{'time': '12:00:00', 'value': 2}],
      },
    ];
    flow.dataCollected = true;
    flow.success = true;

    await tester.pumpWidget(
      FluentApp(
        home: ScaffoldPage(
          padding: EdgeInsets.zero,
          content: BottomData(
            IPStats: flow.ipStats,
            deepStats: flow.deepStats,
            interval: flow.interval,
            isRunning: flow.isRunning,
            graphInterval: flow.graphInterval,
            isLoading: flow.isLoading,
            totalPackets: flow.packetSent,
            dataCollected: flow.dataCollected,
            success: flow.success,
            toggleStatistics: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Drag both sibling scrollables (stat table, actions column) vertically
    // the way a finger-scroll on iPad would.
    final scrollViews = find.byType(SingleChildScrollView);
    expect(scrollViews, findsWidgets);

    for (final finder in [scrollViews.first, scrollViews.last]) {
      await tester.drag(finder, const Offset(0, -100));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.drag(finder, const Offset(0, 100));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    debugDefaultTargetPlatformOverride = null;
    flow.dispose();
  });
}
