import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:PingRoute/dialogs/settings.dart';
import 'package:PingRoute/main.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'has_completed_onboarding': true});
    await AppSettings.instance.setHasCompletedOnboarding(true);
  });

  testWidgets('MainApp renders ViewMode switcher and toggles modes without auto-creating tabs', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const PingRouteApp());
    await tester.pumpAndSettle();

    // Check mode selector pills exist
    expect(find.text('Tabs'), findsOneWidget);
    expect(find.text('2-Flow Split'), findsOneWidget);
    expect(find.text('4-Flow Grid'), findsOneWidget);

    // Initial flow is 1
    // Tap 2-Flow Split
    await tester.tap(find.text('2-Flow Split'));
    await tester.pumpAndSettle();

    // Verify 2-Flow Split view is rendered without auto-creating tabs
    expect(find.byType(TabView), findsNothing);
    expect(find.text('Slot 2 (Unassigned)'), findsOneWidget);

    // Switch to 4-Flow Grid
    await tester.tap(find.text('4-Flow Grid'));
    await tester.pumpAndSettle();

    expect(find.text('Slot 2 (Unassigned)'), findsOneWidget);
    expect(find.text('Slot 3 (Unassigned)'), findsOneWidget);
    expect(find.text('Slot 4 (Unassigned)'), findsOneWidget);

    // Switch back to Tabs mode
    await tester.tap(find.text('Tabs'));
    await tester.pumpAndSettle();

    // Only original single tab exists
    expect(find.byType(TabView), findsOneWidget);
    expect(find.byType(Tab), findsNWidgets(1));
  });

  testWidgets('Split view allows picking any arbitrary tab from 6+ open tabs', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const PingRouteApp());
    await tester.pumpAndSettle();

    // Create 5 more tabs so we have 6 tabs total
    for (int i = 0; i < 5; i++) {
      await tester.tap(find.text('New Flow (⌘T)'));
      await tester.pumpAndSettle();
    }

    expect(find.byType(Tab), findsNWidgets(6));

    // Switch to 2-Flow Split
    await tester.tap(find.text('2-Flow Split'));
    await tester.pumpAndSettle();

    // Only Slot 1 is auto-populated; Slot 2 starts genuinely unassigned
    // (empty slots must never silently alias another flow by list position).
    expect(find.textContaining('Slot 1:'), findsOneWidget);
    expect(find.text('Slot 2 (Unassigned)'), findsOneWidget);

    // Assign Tab 2 into Slot 2 via its "Select Open Tab" dropdown.
    await tester.tap(find.text('Select Open Tab'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Tab 2:').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('Slot 2:'), findsOneWidget);

    // Tap on Slot 1 DropDownButton to choose Tab 6
    await tester.tap(find.textContaining('Slot 1:'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Tab 6:'), findsOneWidget);
    await tester.tap(find.textContaining('Tab 6:'));
    await tester.pumpAndSettle();

    // Verify Slot 1 now displays Tab 6
    expect(find.textContaining('Slot 1: Tab 6'), findsOneWidget);
  });

  testWidgets('4-Flow Grid: filling slot 4 then slot 2 does not alias flows across empty slots', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const PingRouteApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('4-Flow Grid'));
    await tester.pumpAndSettle();

    // Only Slot 1 is auto-populated; slots 2-4 start genuinely unassigned.
    expect(find.text('Slot 2 (Unassigned)'), findsOneWidget);
    expect(find.text('Slot 3 (Unassigned)'), findsOneWidget);
    expect(find.text('Slot 4 (Unassigned)'), findsOneWidget);

    // Create a brand new flow directly in Slot 4, leaving Slot 2 and 3 empty.
    final slot4NewFlow = find.descendant(
      of: find.ancestor(
        of: find.text('Slot 4 (Unassigned)'),
        matching: find.byType(Container),
      ).first,
      matching: find.text('New Flow'),
    );
    await tester.tap(slot4NewFlow);
    await tester.pumpAndSettle();

    // Slot 2 must still show as unassigned, not silently alias Slot 4's flow.
    expect(find.text('Slot 2 (Unassigned)'), findsOneWidget);
    expect(find.text('Slot 3 (Unassigned)'), findsOneWidget);
    expect(find.textContaining('Slot 4:'), findsOneWidget);

    // Now create a new flow directly in Slot 2.
    final slot2NewFlow = find.descendant(
      of: find.ancestor(
        of: find.text('Slot 2 (Unassigned)'),
        matching: find.byType(Container),
      ).first,
      matching: find.text('New Flow'),
    );
    await tester.tap(slot2NewFlow);
    await tester.pumpAndSettle();

    // Slot 2 and Slot 4 must reference distinct flows (different tab numbers).
    expect(find.textContaining('Slot 2: Tab 3'), findsOneWidget);
    expect(find.textContaining('Slot 4: Tab 2'), findsOneWidget);
    // Slot 3 remains untouched and empty.
    expect(find.text('Slot 3 (Unassigned)'), findsOneWidget);
  });

  testWidgets('4-Flow Grid at iPad-compact width scrolls without layout errors', (WidgetTester tester) async {
    // Narrow enough to trip kTabletBreakpoint and force the vertical pane
    // stack (the layout path where a nested hop-table ListView used to
    // fight the outer SingleChildScrollView over vertical drags on iOS).
    tester.view.physicalSize = const Size(820, 1180);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    // A vertical ScrollView with no explicit controller only falls back to
    // the ambient PrimaryScrollController on mobile platforms, which is
    // exactly how the real "ScrollController attached to more than one
    // ScrollPosition" crash surfaced on iPad but never on a macOS run.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    await tester.pumpWidget(const PingRouteApp());
    await tester.pumpAndSettle();

    // Create 3 more tabs so all 4 grid slots have a flow assigned.
    for (int i = 0; i < 3; i++) {
      await tester.tap(find.text('New Flow (⌘T)'));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('4-Flow Grid'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Drag vertically across the grid the way a finger-scroll on iPad would.
    await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    debugDefaultTargetPlatformOverride = null;
  });
}



