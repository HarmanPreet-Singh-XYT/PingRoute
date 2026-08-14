// Responsive-layout smoke test: renders the app shell at representative
// phone/tablet/desktop widths and confirms nothing throws a layout
// exception (e.g. RenderFlex overflow), since the app has no automated
// visual regression coverage.
import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_ui/fluent_ui.dart';

import 'package:PingRoute/main.dart';

void main() {
  final widths = <String, double>{
    'phone': 375,
    'tablet': 800,
    'desktop': 1400,
  };

  for (final entry in widths.entries) {
    testWidgets('renders at ${entry.key} width (${entry.value}px) without layout errors', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(Size(entry.value, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const PingRouteApp());
      await tester.pumpAndSettle();

      // A render overflow throws during the pump above; reaching here with
      // no exception means the tree laid out successfully. Also assert the
      // navbar's target field is present as a baseline sanity check.
      expect(find.byType(TextBox), findsWidgets);
    });
  }
}
