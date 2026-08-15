import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:PingRoute/widgets/middle_data.dart';

void main() {
  final sampleHops = [
    {'hop': 1, 'ip': '192.168.1.1', 'name': 'router.local'},
    {'hop': 2, 'ip': '10.0.0.1', 'name': 'gateway.isp'},
    {'hop': 3, 'ip': '172.16.0.1', 'name': 'core.isp'},
    {'hop': 4, 'ip': '8.8.8.8', 'name': 'dns.google'},
  ];

  final sampleStats = [
    {'min': 2, 'max': 5, 'avg': 3, 'last': 2, 'pl': 0, 'sentPackets': 10, 'receivedPackets': 10},
    {'min': 12, 'max': 25, 'avg': 18, 'last': 15, 'pl': 10, 'sentPackets': 10, 'receivedPackets': 9},
    {'min': 5, 'max': 10, 'avg': 7, 'last': 6, 'pl': 0, 'sentPackets': 10, 'receivedPackets': 10},
    {'min': 20, 'max': 40, 'avg': 28, 'last': 22, 'pl': 5, 'sentPackets': 10, 'receivedPackets': 9},
  ];

  Widget buildTestWidget() {
    return FluentApp(
      home: ScaffoldPage(
        content: SizedBox(
          width: 800,
          height: 600,
          child: LeftData(
            data: sampleHops,
            isLoading: false,
            IPStats: sampleStats,
            deepStats: const [],
            interval: 1000,
            isRunning: false,
            isSuccess: true,
          ),
        ),
      ),
    );
  }

  testWidgets('LeftData renders header columns and allows sorting by IP ascending and descending', (tester) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    // Verify initial table renders with hops
    expect(find.text('192.168.1.1'), findsOneWidget);
    expect(find.text('8.8.8.8'), findsOneWidget);

    // Tap on 'IP' header to sort ascending (8.8.8.8, 10.0.0.1, 172.16.0.1, 192.168.1.1)
    await tester.tap(find.text('IP'));
    await tester.pumpAndSettle();

    expect(find.byIcon(FluentIcons.chevron_up), findsOneWidget);

    // Tap on 'IP' header again for descending sort
    await tester.tap(find.text('IP'));
    await tester.pumpAndSettle();

    expect(find.byIcon(FluentIcons.chevron_down), findsOneWidget);

    // Tap on 'IP' header third time to reset
    await tester.tap(find.text('IP'));
    await tester.pumpAndSettle();

    expect(find.byIcon(FluentIcons.chevron_up), findsNothing);
    expect(find.byIcon(FluentIcons.chevron_down), findsNothing);
  });

  testWidgets('LeftData opens search from right-click context menu on header column', (tester) async {
    await tester.pumpWidget(buildTestWidget());
    await tester.pumpAndSettle();

    // Initially search box is closed to save vertical space
    expect(find.byType(TextBox), findsNothing);

    // Right-click (secondary tap) on 'IP' column header to open context menu
    await tester.tap(find.text('IP'), buttons: 2);
    await tester.pumpAndSettle();

    expect(find.text('Search / Filter Hops...'), findsOneWidget);

    // Click Search / Filter Hops...
    await tester.tap(find.text('Search / Filter Hops...'));
    await tester.pumpAndSettle();

    // Verify search box appears
    expect(find.byType(TextBox), findsOneWidget);

    // Enter filter text
    await tester.enterText(find.byType(TextBox).first, 'google');
    await tester.pumpAndSettle();

    expect(find.text('8.8.8.8'), findsOneWidget);
    expect(find.text('192.168.1.1'), findsNothing);
    expect(find.text('10.0.0.1'), findsNothing);

    // Close search box
    await tester.tap(find.byIcon(FluentIcons.chrome_close));
    await tester.pumpAndSettle();

    expect(find.byType(TextBox), findsNothing);
    expect(find.text('192.168.1.1'), findsOneWidget);
    expect(find.text('8.8.8.8'), findsOneWidget);
  });
}
