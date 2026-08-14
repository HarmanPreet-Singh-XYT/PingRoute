import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:PingRoute/flow_session.dart';

void main() {
  group('Export & Telemetry Reports Tests', () {
    test('generateMtrReport produces valid formatted ASCII MTR table', () {
      final session = FlowSession(initialIp: '1.1.1.1');
      session.ipStats = [
        {
          'hop': 1,
          'ip': '192.168.1.1',
          'name': 'gateway.local',
          'pl': 0,
          'sentPackets': 10,
          'receivedPackets': 10,
          'min': 1,
          'avg': 2,
          'max': 5,
          'last': 2,
        },
        {
          'hop': 2,
          'ip': '1.1.1.1',
          'name': 'one.one.one.one',
          'pl': 0,
          'sentPackets': 10,
          'receivedPackets': 10,
          'min': 12,
          'avg': 14,
          'max': 18,
          'last': 13,
        },
      ];
      session.packetSent = 10;

      final mtr = session.generateMtrReport();
      expect(mtr, contains('PingRoute MTR Report'));
      expect(mtr, contains('Target: 1.1.1.1'));
      expect(mtr, contains('192.168.1.1'));
      expect(mtr, contains('one.one.one.one'));
      expect(mtr, contains('HOP  HOST / IP'));
      expect(mtr, contains('BEST   AVG    WRST   LAST'));
    });

    test('generateCsvReport produces valid CSV headers and data rows', () {
      final session = FlowSession(initialIp: '8.8.8.8');
      session.ipStats = [
        {
          'hop': 1,
          'ip': '10.0.0.1',
          'name': 'router',
          'pl': 0,
          'sentPackets': 5,
          'receivedPackets': 5,
          'min': 2,
          'avg': 3,
          'max': 6,
          'last': 3,
        }
      ];

      final csv = session.generateCsvReport();
      final lines = csv.trim().split('\n');
      expect(lines.length, 2);
      expect(lines[0], 'Hop,IP,Hostname,LossPercent,Sent,Received,MinMs,AvgMs,MaxMs,LastMs');
      expect(lines[1], '1,"10.0.0.1","router",0,5,5,2,3,6,3');
    });

    test('generateJsonReport produces valid JSON with full telemetry', () {
      final session = FlowSession(initialIp: '9.9.9.9');
      session.packetSize = 1472;
      session.ipStats = [
        {
          'hop': 1,
          'ip': '9.9.9.9',
          'name': 'dns.quad9.net',
          'pl': 0,
          'sentPackets': 20,
          'receivedPackets': 20,
          'min': 15,
          'avg': 16,
          'max': 22,
          'last': 15,
        }
      ];

      final jsonStr = session.generateJsonReport();
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      expect(decoded['target'], '9.9.9.9');
      expect(decoded['packetSize'], 1472);
      expect(decoded['hops'], isNotEmpty);
    });

    test('Advanced probing parameters mutate and validate correctly', () {
      final session = FlowSession(initialIp: '1.1.1.1');
      session.changeSettingParams('1472', 'packetSize');
      expect(session.packetSize, 1472);

      session.changeSettingParams('45', 'maxHops');
      expect(session.maxHops, 45);

      session.changeSettingParams('2500', 'timeoutMs');
      expect(session.timeoutMs, 2500);

      // Disallow invalid sizes
      session.changeSettingParams('10', 'packetSize');
      expect(session.packetSize, 1472); // unchanged
    });
  });
}
