import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:PingRoute/main.dart';
import 'package:PingRoute/shared_widgets.dart';
import 'package:PingRoute/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Desktop Interactions & Micro-Animations Tests', () {
    testWidgets('StatTile renders properly with label and value', (tester) async {
      await tester.pumpWidget(
        FluentApp(
          home: ScaffoldPage(
            content: StatTile(
              icon: FluentIcons.speed_high,
              label: 'Max latency',
              value: '42ms',
              colors: AppColors.dark,
              type: AppTypography.of(Colors.white, Colors.grey),
            ),
          ),
        ),
      );

      expect(find.text('Max latency'), findsOneWidget);
      expect(find.text('42ms'), findsOneWidget);
    });

    testWidgets('StatTable renders rows properly', (tester) async {
      await tester.pumpWidget(
        FluentApp(
          home: ScaffoldPage(
            content: StatTable(
              colors: AppColors.dark,
              type: AppTypography.of(Colors.white, Colors.grey),
              rows: const [('IP Address', '1.1.1.1')],
            ),
          ),
        ),
      );

      expect(find.text('IP Address'), findsOneWidget);
      expect(find.text('1.1.1.1'), findsOneWidget);
    });

    testWidgets('MainApp responds to desktop keyboard shortcut Cmd+T to add tabs', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(const PingRouteApp());
      await tester.pumpAndSettle();

      expect(find.byType(Tab), findsNWidgets(1));

      // Simulate Cmd+T (meta+T)
      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await tester.pumpAndSettle();

      expect(find.byType(Tab), findsNWidgets(2));
    });
  });
}
