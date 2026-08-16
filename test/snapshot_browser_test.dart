import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:PingRoute/dialogs/snapshot_dialog.dart';
import 'package:PingRoute/models/snapshot.dart';
import 'package:PingRoute/models/snapshot_store.dart';

void main() {
  group('SnapshotsListView', () {
    // Note: SnapshotsListView reads the real SnapshotStore.instance
    // singleton (persisted to disk), not an injectable test store, so these
    // tests can't assume a pristine/empty store — a dev machine that has
    // actually saved snapshots would otherwise fail this suite spuriously.
    testWidgets('renders without error whether or not snapshots exist',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        FluentApp(
          home: ScaffoldPage(
            content: SnapshotsListView(onOpenSnapshot: (_) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final hasSnapshots = SnapshotStore.instance.snapshots.isNotEmpty;
      expect(
        find.text('No snapshots yet'),
        hasSnapshots ? findsNothing : findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows Snapshots dialog title and Close action',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        FluentApp(
          home: Builder(
            builder: (context) => Button(
              onPressed: () => showSnapshotsDialog(
                context,
                onOpenSnapshot: (_) {},
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Snapshots'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
    });
  });

  group('Snapshot model with fixture data', () {
    test('SnapshotMeta.fromSnapshot copies the summary fields', () {
      final snapshot = Snapshot(
        name: 'Fixture Run',
        target: '4.4.4.4',
        title: '4.4.4.4',
        durationMs: 12000,
      );

      final meta = SnapshotMeta.fromSnapshot(snapshot);

      expect(meta.id, snapshot.id);
      expect(meta.name, 'Fixture Run');
      expect(meta.target, '4.4.4.4');
      expect(meta.durationMs, 12000);
    });
  });
}
