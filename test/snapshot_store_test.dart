import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:PingRoute/models/snapshot.dart';
import 'package:PingRoute/models/snapshot_store.dart';

void main() {
  group('SnapshotStore', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('snapshot_store_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('save writes an index entry and a snapshot file', () async {
      final store = SnapshotStore.test(baseDirOverride: tempDir.path);
      final snapshot = Snapshot(
        name: 'Test Run',
        target: '1.1.1.1',
        title: '1.1.1.1',
      );

      await store.save(snapshot);

      expect(store.snapshots.length, 1);
      expect(store.snapshots.first.id, snapshot.id);
      expect(store.snapshots.first.name, 'Test Run');

      final snapshotFile = File('${tempDir.path}/snapshots/${snapshot.id}.json');
      final indexFile = File('${tempDir.path}/snapshots/index.json');
      expect(snapshotFile.existsSync(), isTrue);
      expect(indexFile.existsSync(), isTrue);
    });

    test('load reads back a saved snapshot with full data', () async {
      final store = SnapshotStore.test(baseDirOverride: tempDir.path);
      final snapshot = Snapshot(
        name: 'Loadable',
        target: '8.8.8.8',
        title: '8.8.8.8',
        ipStats: [
          {
            'hop': 1,
            'ip': '8.8.8.8',
            'name': 'dns',
            'max': 10,
            'min': 1,
            'last': 5,
            'avg': 4.5,
            'pl': 0,
            'receivedPackets': 5,
            'sentPackets': 5,
          },
        ],
      );
      await store.save(snapshot);

      final loaded = await store.load(snapshot.id);

      expect(loaded, isNotNull);
      expect(loaded!.name, 'Loadable');
      expect(loaded.target, '8.8.8.8');
      expect(loaded.ipStats, snapshot.ipStats);
    });

    test('load returns null for a missing id', () async {
      final store = SnapshotStore.test(baseDirOverride: tempDir.path);
      final result = await store.load('does-not-exist');
      expect(result, isNull);
    });

    test('delete removes both the index entry and the file', () async {
      final store = SnapshotStore.test(baseDirOverride: tempDir.path);
      final snapshot = Snapshot(name: 'Delete Me', target: '1.1.1.1', title: '1.1.1.1');
      await store.save(snapshot);
      expect(store.snapshots.length, 1);

      await store.delete(snapshot.id);

      expect(store.snapshots.length, 0);
      final snapshotFile = File('${tempDir.path}/snapshots/${snapshot.id}.json');
      expect(snapshotFile.existsSync(), isFalse);
    });

    test('index persists across store instances pointed at the same dir', () async {
      final store1 = SnapshotStore.test(baseDirOverride: tempDir.path);
      final snapshot = Snapshot(name: 'Persisted', target: '1.1.1.1', title: '1.1.1.1');
      await store1.save(snapshot);

      final store2 = SnapshotStore.test(baseDirOverride: tempDir.path);

      expect(store2.snapshots.length, 1);
      expect(store2.snapshots.first.name, 'Persisted');
    });

    test('fully in-memory test constructor (no baseDirOverride) skips disk I/O', () async {
      final store = SnapshotStore.test(initial: [
        SnapshotMeta(
          id: '1',
          name: 'Seeded',
          target: '1.1.1.1',
          title: '1.1.1.1',
          createdAt: DateTime.now(),
        ),
      ]);

      expect(store.snapshots.length, 1);
      expect(store.snapshots.first.name, 'Seeded');

      final loaded = await store.load('1');
      expect(loaded, isNull); // no disk I/O happened, nothing to load
    });

    test('saveAuto upserts the same id in place instead of appending', () async {
      final store = SnapshotStore.test(baseDirOverride: tempDir.path);
      final first = Snapshot(
        id: 'auto_flow1',
        name: 'Flow 1 (auto)',
        target: '1.1.1.1',
        title: '1.1.1.1',
        isAuto: true,
        durationMs: 1000,
      );
      await store.saveAuto(first);
      expect(store.autoSnapshots.length, 1);

      final refreshed = Snapshot(
        id: 'auto_flow1',
        name: 'Flow 1 (auto)',
        target: '1.1.1.1',
        title: '1.1.1.1',
        isAuto: true,
        durationMs: 5000,
      );
      await store.saveAuto(refreshed);

      expect(store.autoSnapshots.length, 1);
      expect(store.autoSnapshots.first.durationMs, 5000);
    });

    test('saveAuto evicts the oldest auto entry once maxAutoSnapshots distinct flows exist', () async {
      final store = SnapshotStore.test(baseDirOverride: tempDir.path);

      for (int i = 0; i < SnapshotStore.maxAutoSnapshots; i++) {
        await store.saveAuto(Snapshot(
          id: 'auto_flow$i',
          name: 'Flow $i (auto)',
          target: '1.1.1.1',
          title: '1.1.1.1',
          isAuto: true,
        ));
      }
      expect(store.autoSnapshots.length, SnapshotStore.maxAutoSnapshots);
      expect(store.autoSnapshots.any((m) => m.id == 'auto_flow0'), isTrue);

      // One more distinct flow should evict the oldest (auto_flow0).
      await store.saveAuto(Snapshot(
        id: 'auto_flowNEW',
        name: 'New Flow (auto)',
        target: '2.2.2.2',
        title: '2.2.2.2',
        isAuto: true,
      ));

      expect(store.autoSnapshots.length, SnapshotStore.maxAutoSnapshots);
      expect(store.autoSnapshots.any((m) => m.id == 'auto_flow0'), isFalse);
      expect(store.autoSnapshots.any((m) => m.id == 'auto_flowNEW'), isTrue);

      final evictedFile = File('${tempDir.path}/snapshots/auto_flow0.json');
      expect(evictedFile.existsSync(), isFalse);
    });

    test('manual saves are never evicted by auto-save FIFO and stay in a separate list', () async {
      final store = SnapshotStore.test(baseDirOverride: tempDir.path);

      await store.save(Snapshot(name: 'Manual', target: '9.9.9.9', title: '9.9.9.9'));

      for (int i = 0; i < SnapshotStore.maxAutoSnapshots + 5; i++) {
        await store.saveAuto(Snapshot(
          id: 'auto_flow$i',
          name: 'Flow $i (auto)',
          target: '1.1.1.1',
          title: '1.1.1.1',
          isAuto: true,
        ));
      }

      expect(store.snapshots.length, 1);
      expect(store.snapshots.first.name, 'Manual');
      expect(store.autoSnapshots.length, SnapshotStore.maxAutoSnapshots);
    });
  });
}
