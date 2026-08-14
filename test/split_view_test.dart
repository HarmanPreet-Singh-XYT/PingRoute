import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:PingRoute/main.dart';

void main() {
  testWidgets('MainApp renders ViewMode switcher and toggles to 2-Flow Split', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const PingRouteApp());
    await tester.pumpAndSettle();

    // Check mode selector pills exist
    expect(find.text('Tabs'), findsOneWidget);
    expect(find.text('2-Flow Split'), findsOneWidget);
    expect(find.text('4-Flow Grid'), findsOneWidget);

    // Tap 2-Flow Split
    await tester.tap(find.text('2-Flow Split'));
    await tester.pumpAndSettle();

    // Verify 2-Flow Split view is rendered
    expect(find.byType(TabView), findsNothing);
  });
}
