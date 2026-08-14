import 'package:flutter_test/flutter_test.dart';
import 'package:PingRoute/network_info_dialog.dart';

void main() {
  group('Network Diagnostics Unit Tests', () {
    test('NetworkDiagnosticsData markdown report format', () {
      final data = NetworkDiagnosticsData(
        hostname: 'macbook-pro.local',
        osVersion: 'macos 14.5',
        interfaces: [
          NetworkInterfaceInfo(
            name: 'en0',
            ipv4Addresses: ['192.168.1.50'],
            ipv6Addresses: ['fe80::1'],
          ),
          NetworkInterfaceInfo(
            name: 'lo0',
            ipv4Addresses: ['127.0.0.1'],
            ipv6Addresses: ['::1'],
          ),
        ],
        defaultGateway: '192.168.1.1',
        dnsServers: ['1.1.1.1', '8.8.8.8'],
        publicIp: '203.0.113.195',
        publicIsp: 'Cloudflare Inc',
        publicLocation: 'San Francisco, US',
        isFromCache: true,
        scannedAt: DateTime.parse('2026-08-14T20:00:00Z'),
      );

      final md = data.toMarkdown();
      expect(md, contains('# 🌐 PingRoute System Network Diagnostics'));
      expect(md, contains('Hostname: macbook-pro.local'));
      expect(md, contains('Public IP: 203.0.113.195 (Cached)'));
      expect(md, contains('ISP / ASN: Cloudflare Inc'));
      expect(md, contains('Location: San Francisco, US'));
      expect(md, contains('Default Gateway: 192.168.1.1'));
      expect(md, contains('DNS Servers: 1.1.1.1, 8.8.8.8'));
      expect(md, contains('### Interface `en0`'));
      expect(md, contains('192.168.1.50'));
    });

    test('NetworkDiagnosticsService scan returns structured system data in test mode', () async {
      final data = await NetworkDiagnosticsService.scan(isTest: true);
      expect(data.hostname, isNotEmpty);
      expect(data.osVersion, isNotEmpty);
      expect(data.scannedAt, isNotNull);
      expect(data.interfaces, isA<List<NetworkInterfaceInfo>>());
    });
  });
}
