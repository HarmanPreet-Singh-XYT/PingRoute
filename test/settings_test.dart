import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:PingRoute/settings.dart';

void main() {
  group('AppSettings Unit Tests', () {
    test('initializes with default system theme and defaults', () {
      final settings = AppSettings.test();
      expect(settings.themeMode, ThemeMode.system);
      expect(settings.defaultInterval, 1000);
      expect(settings.defaultGraphInterval, 1000);
      expect(settings.defaultPacketsLimit, 25);
    });

    test('sets and updates theme mode', () {
      final settings = AppSettings.test();
      settings.setThemeMode(ThemeMode.light);
      expect(settings.themeMode, ThemeMode.light);

      settings.setThemeMode(ThemeMode.dark);
      expect(settings.themeMode, ThemeMode.dark);

      settings.setThemeMode(ThemeMode.system);
      expect(settings.themeMode, ThemeMode.system);
    });

    test('sets default parameters with validation bounds', () {
      final settings = AppSettings.test();
      settings.setDefaults(interval: 500, graphInterval: 250, packetsLimit: 50);

      expect(settings.defaultInterval, 500);
      expect(settings.defaultGraphInterval, 250);
      expect(settings.defaultPacketsLimit, 50);

      // Ignore invalid negative or under-limit values
      settings.setDefaults(interval: -1, graphInterval: 0, packetsLimit: 5);
      expect(settings.defaultInterval, 500);
      expect(settings.defaultGraphInterval, 250);
      expect(settings.defaultPacketsLimit, 50);
    });

    test('sets and clamps UI scaling', () {
      final settings = AppSettings.test();
      expect(settings.uiScale, 1.0);

      settings.setUiScale(0.85);
      expect(settings.uiScale, 0.85);

      settings.setUiScale(1.30);
      expect(settings.uiScale, 1.30);

      // Clamp out-of-bounds scale
      settings.setUiScale(0.20);
      expect(settings.uiScale, 0.75);

      settings.setUiScale(2.50);
      expect(settings.uiScale, 1.50);
    });
  });
}
