import 'package:flutter_test/flutter_test.dart';
import 'package:PingRoute/models/target_directory.dart';

void main() {
  group('TargetDirectory Unit Tests', () {
    test('maintains max 5 recent unique IPs in LIFO order', () {
      final dir = TargetDirectory.test(initialRecent: []);

      dir.addRecent('1.1.1.1');
      dir.addRecent('8.8.8.8');
      dir.addRecent('9.9.9.9');
      dir.addRecent('1.0.0.1');
      dir.addRecent('8.8.4.4');

      expect(dir.recentIps.length, 5);
      expect(dir.recentIps, ['8.8.4.4', '1.0.0.1', '9.9.9.9', '8.8.8.8', '1.1.1.1']);

      // Adding a 6th item drops the oldest ('1.1.1.1')
      dir.addRecent('208.67.222.222');
      expect(dir.recentIps.length, 5);
      expect(dir.recentIps.first, '208.67.222.222');
      expect(dir.recentIps.contains('1.1.1.1'), isFalse);

      // Re-adding an existing item moves it to the front without duplicates
      dir.addRecent('8.8.8.8');
      expect(dir.recentIps.length, 5);
      expect(dir.recentIps.first, '8.8.8.8');
      expect(dir.recentIps.where((ip) => ip == '8.8.8.8').length, 1);
    });

    test('saves, updates, and deletes targets in directory', () {
      final dir = TargetDirectory.test(initialSaved: []);

      dir.saveTarget('1.1.1.1', name: 'Cloudflare', note: 'Primary DNS');
      expect(dir.isSaved('1.1.1.1'), isTrue);
      expect(dir.isSaved('1.1.1.1 '), isTrue);
      expect(dir.isSaved('8.8.8.8'), isFalse);

      final saved = dir.getSavedTarget('1.1.1.1');
      expect(saved, isNotNull);
      expect(saved!.name, 'Cloudflare');
      expect(saved.note, 'Primary DNS');

      // Update target
      dir.updateTarget(saved.copyWith(name: 'Cloudflare Fast'));
      expect(dir.getSavedTarget('1.1.1.1')?.name, 'Cloudflare Fast');

      // Delete target
      dir.deleteTarget(saved.id);
      expect(dir.isSaved('1.1.1.1'), isFalse);
      expect(dir.savedTargets.isEmpty, isTrue);
    });

    test('toggleFavorite adds and removes target', () {
      final dir = TargetDirectory.test(initialSaved: []);

      dir.toggleFavorite('192.168.1.1', defaultName: 'Router');
      expect(dir.isSaved('192.168.1.1'), isTrue);
      expect(dir.getSavedTarget('192.168.1.1')?.name, 'Router');

      // Toggle again removes it
      dir.toggleFavorite('192.168.1.1');
      expect(dir.isSaved('192.168.1.1'), isFalse);
    });

    test('SavedTarget JSON serialization roundtrip', () {
      final target = SavedTarget(
        id: 'test-123',
        name: 'Google DNS',
        target: '8.8.8.8',
        note: 'DNS server',
      );

      final json = target.toJson();
      final restored = SavedTarget.fromJson(json);

      expect(restored.id, target.id);
      expect(restored.name, target.name);
      expect(restored.target, target.target);
      expect(restored.note, target.note);
    });
  });
}
