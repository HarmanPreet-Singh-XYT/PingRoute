import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:PingRoute/models/flow_session.dart';
import 'package:PingRoute/widgets/mobile_shell.dart';

void main() {
  testWidgets('MobileShell renders 4 tabs: Overview, Hops, Graph, Timeline', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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

    bool exportCalled = false;
    bool statsCalled = false;

    await tester.pumpWidget(
      FluentApp(
        home: ScaffoldPage(
          padding: EdgeInsets.zero,
          content: MobileShell(
            flows: [flow],
            currentFlowIndex: 0,
            onFlowSelected: (_) {},
            onAddFlow: () {},
            onCloseFlow: (_) {},
            showSettings: () {},
            onExport: (_) => exportCalled = true,
            onToggleStatistics: () => statsCalled = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify all 4 tabs exist
    expect(find.text('Overview'), findsWidgets);
    expect(find.text('Hops'), findsWidgets);
    expect(find.text('Graph'), findsWidgets);
    expect(find.text('Timeline'), findsWidgets);

    // Switch to Hops Tab
    await tester.tap(find.text('Hops').last);
    await tester.pumpAndSettle();

    // Switch to Graph Tab and verify final hop (one.one.one.one) is selected by default
    await tester.tap(find.text('Graph').last);
    await tester.pumpAndSettle();
    expect(find.text('one.one.one.one'), findsWidgets);

    // Switch to Timeline Tab
    await tester.tap(find.text('Timeline').last);
    await tester.pumpAndSettle();

    expect(find.text('Timeline Chart'), findsOneWidget);
    expect(find.textContaining('Incidents'), findsOneWidget);
  });
}
