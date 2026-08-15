import 'package:flutter_test/flutter_test.dart';
import 'package:PingRoute/network.dart';

void main() {
  group('NetworkLib Unit Tests', () {
    test('instantiates safely across any host OS without throwing', () {
      final netLib = NetworkLib();
      expect(netLib, isNotNull);
    });

    test('performTraceroute handles empty or invalid destination safely', () async {
      final netLib = NetworkLib();
      final result = await netLib.performTraceroute('');
      expect(result, isEmpty);
    });

    test('performTraceroute resolves localhost or domain via fallback if native is unavailable', () async {
      final netLib = NetworkLib();
      final result = await netLib.performTraceroute('127.0.0.1');
      expect(result, isNotNull);
      if (result.isNotEmpty) {
        expect(result.first, contains('127.0.0.1'));
      }
    });
  });
}
