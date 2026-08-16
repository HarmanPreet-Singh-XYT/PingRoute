import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:PingRoute/dialogs/snapshot_dialog.dart';
import 'package:PingRoute/models/flow_session.dart';

void main() {
  group('Save Snapshot dialog', () {
    testWidgets('renders a prefilled name field and Save/Cancel actions',
        (WidgetTester tester) async {
      final flow = FlowSession(initialIp: '8.8.8.8');

      await tester.pumpWidget(
        FluentApp(
          home: Builder(
            builder: (context) => Button(
              onPressed: () => showSaveSnapshotDialog(context, flow),
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Save Snapshot'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(
        find.textContaining('This flow has no recorded ping history yet'),
        findsOneWidget,
      );

      flow.dispose();
    });

    testWidgets('Cancel closes the dialog without saving',
        (WidgetTester tester) async {
      final flow = FlowSession(initialIp: '1.1.1.1');

      await tester.pumpWidget(
        FluentApp(
          home: Builder(
            builder: (context) => Button(
              onPressed: () => showSaveSnapshotDialog(context, flow),
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Save Snapshot'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Save Snapshot'), findsNothing);

      flow.dispose();
    });
  });
}
