import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:PingRoute/screens/apps_screen.dart';
import 'package:PingRoute/core/format.dart';
import 'package:PingRoute/core/port_services.dart';
import 'package:PingRoute/models/app_metrics.dart';
import 'package:PingRoute/models/app_mode_settings.dart';
import 'package:PingRoute/models/app_session.dart';
import 'package:PingRoute/models/flow_session.dart';
import 'package:PingRoute/services/app_connection_service.dart';
import 'package:PingRoute/services/app_report.dart';

const _nettop = '''
,bytes_in,bytes_out,
Comet Helper.1496,23713279,2634848,
tcp4 10.0.0.5:59936<->172.64.146.215:443,487546,633482,
udp4 10.0.0.5:58518<->17.250.102.167:443,21367,1437,
udp4 *:5353<->*:*,10111501,12771197,
udp6 fe80::1%en0.5353<->ff02::fb%en0.5353,10,20,
tcp6 2001:db8::1.50000<->2606:4700::6810:84e5.443,300,400,
mDNSResponder.684,18639187,19255369,
''';

AppConnection _tcp(int pid, String ip, {int local = 5000, int port = 443}) =>
    AppConnection(
      pid: pid,
      processName: 'app',
      protocol: 'TCP',
      state: 'ESTABLISHED',
      remoteIp: ip,
      remotePort: port,
      localPort: local,
    );

class _Service extends AppConnectionService {
  _Service(this.apps);
  List<AppSnapshot> apps;
  @override
  Future<List<AppSnapshot>> poll({
    bool includePrivate = false,
    bool includeUdp = true,
  }) async => apps;
}

class _Pinger implements EndpointPinger {
  final c = StreamController<int>.broadcast();
  @override
  Stream<int> get results => c.stream;
  @override
  void dispose() => c.close();
}

AppSnapshot _snap(String name, List<AppConnection> conns) => AppSnapshot(
  id: name.toLowerCase(),
  name: name,
  pids: {1},
  connections: conns,
  isSystem: false,
  trafficAvailable: true,
);

void main() {
  group('parseNettop', () {
    final flows = parseNettop(_nettop);

    test('maps sockets to their process and skips unconnected ones', () {
      expect(flows.length, 4); // wildcard 5353 flow dropped
      final tcp = flows.first;
      expect(tcp.process, 'Comet Helper');
      expect(tcp.pid, 1496);
      expect(tcp.protocol, 'TCP');
      expect(tcp.localPort, 59936);
      expect(tcp.remoteIp, '172.64.146.215');
      expect(tcp.bytesIn, 487546);
      expect(tcp.bytesOut, 633482);
    });

    test('parses UDP flows and IPv6 with dot-separated ports', () {
      expect(flows.where((f) => f.protocol == 'UDP').length, 2);
      final v6 = flows.singleWhere((f) => f.remoteIp.startsWith('2606'));
      expect(v6.remotePort, 443);
      expect(v6.localPort, 50000);
      final scoped = flows.singleWhere((f) => f.remoteIp == 'ff02::fb');
      expect(scoped.remotePort, 5353);
    });
  });

  group('parseElapsed / ps stats', () {
    test('parses all etime forms', () {
      expect(
        parseElapsed('05-13:59:27'),
        const Duration(days: 5, hours: 13, minutes: 59, seconds: 27),
      );
      expect(
        parseElapsed('13:59:27'),
        const Duration(hours: 13, minutes: 59, seconds: 27),
      );
      expect(parseElapsed('59:27'), const Duration(minutes: 59, seconds: 27));
      expect(parseElapsed('nonsense'), isNull);
    });

    test('reads cpu, memory and uptime from ps', () {
      final p = parsePsOutput(
        '  200     1   1.5 529888 05-13:57:43 /Applications/Comet.app/Contents/MacOS/Comet',
      ).single;
      expect(p.cpuPercent, 1.5);
      expect(p.rssKb, 529888);
      expect(p.elapsed!.inDays, 5);
      expect(p.path, endsWith('/Comet'));
    });
  });

  group('grouping with traffic', () {
    final lsof = [_tcp(1496, '172.64.146.215', local: 59936)];
    final procs = parsePsOutput(
      '1496 200 2.0 1000 10:00 /Applications/Comet.app/Contents/Helpers/Comet Helper.app/Contents/MacOS/Comet Helper\n'
      '200 1 1.0 3000 20:00 /Applications/Comet.app/Contents/MacOS/Comet\n',
    );

    test(
      'joins bytes onto TCP sockets, adds UDP flows, sums process stats',
      () {
        final app = groupConnectionsByApp(
          lsof,
          procs,
          traffic: parseNettop(_nettop),
        ).single;
        expect(app.name, 'Comet');
        expect(app.trafficAvailable, isTrue);
        expect(app.connections.where((c) => !c.isUdp).single.bytesIn, 487546);
        expect(app.connections.where((c) => c.isUdp).length, 2);
        expect(app.processCount, 2);
        expect(app.cpuPercent, 3.0);
        expect(app.rssKb, 4000);
        expect(app.uptime, const Duration(minutes: 20));
      },
    );

    test('includeUdp=false drops UDP flows', () {
      final app = groupConnectionsByApp(
        lsof,
        procs,
        traffic: parseNettop(_nettop),
        includeUdp: false,
      ).single;
      expect(app.connections.every((c) => !c.isUdp), isTrue);
    });

    test('includePrivate keeps LAN peers', () {
      final lan = [_tcp(200, '192.168.1.9')];
      expect(groupConnectionsByApp(lan, procs), isEmpty);
      expect(
        groupConnectionsByApp(lan, procs, includePrivate: true),
        hasLength(1),
      );
    });
  });

  group('helpers', () {
    test('service names', () {
      expect(serviceNameForPort(443), 'HTTPS');
      expect(serviceNameForPort(443, protocol: 'UDP'), 'QUIC');
      expect(serviceLabel(9999), 'port 9999');
    });

    test('formatting', () {
      expect(formatBytes(999), '999 B');
      expect(formatBytes(1500), '1.50 KB');
      expect(formatRate(2500000), '2.50 MB/s');
      expect(formatDuration(const Duration(days: 5, hours: 13)), '5d 13h');
      expect(formatDuration(const Duration(minutes: 3, seconds: 5)), '3m 05s');
    });
  });

  group('EndpointState', () {
    EndpointState ep() => EndpointState(appId: 'a', ip: '1.1.1.1');

    test('health: measuring, good, degraded, poor, no reply, idle', () {
      final e = ep()..isPinging = true;
      expect(e.health(5), EndpointHealth.measuring);
      for (var i = 0; i < 5; i++) {
        e.addSample(20);
      }
      expect(e.health(5), EndpointHealth.good);
      e.addSample(150); // avg of window rises above 100? no: still low
      expect(e.health(5), EndpointHealth.good);
      for (var i = 0; i < 15; i++) {
        e.addSample(150);
      }
      expect(e.health(5), EndpointHealth.degraded);
      for (var i = 0; i < 20; i++) {
        e.addSample(300);
      }
      expect(e.health(5), EndpointHealth.poor);
      e.markIdle();
      expect(e.health(5), EndpointHealth.idle);
    });

    test('never-answering host is "no reply", not "poor"', () {
      final e = ep()..isPinging = true;
      for (var i = 0; i < 4; i++) {
        e.addSample(-1);
      }
      expect(e.health(5), EndpointHealth.noReply);
    });

    test('loss threshold is configurable and recovers over the window', () {
      final e = ep();
      e.addSample(20);
      e.addSample(-1); // 50% recent loss
      expect(e.health(5), EndpointHealth.poor);
      expect(e.health(75), EndpointHealth.degraded);
      for (var i = 0; i < 25; i++) {
        e.addSample(20);
      }
      expect(e.health(5), EndpointHealth.good);
      expect(e.lossPercent, greaterThan(0)); // session loss remembers it
    });

    test('min, max, jitter, session average', () {
      final e = ep();
      for (final v in [10, 30, 20, -1]) {
        e.addSample(v);
      }
      expect(e.minMs, 10);
      expect(e.maxMs, 30);
      expect(e.averageMs, 20);
      expect(e.jitterMs, 15); // |30-10|, |20-30| -> mean 15
    });

    test('applyConnections derives service, states, protocols, rates', () {
      final e = ep();
      e.applyConnections(
        [
          _tcp(1, '1.1.1.1').withTraffic(100, 50),
          _tcp(1, '1.1.1.1', local: 5001).withTraffic(10, 5),
        ],
        now: DateTime(2026),
        deltaIn: 2000,
        deltaOut: 500,
        seconds: 2,
      );
      expect(e.primaryService, 'HTTPS');
      expect(e.states, {'ESTABLISHED': 2});
      expect(e.protocols, {'TCP'});
      expect(e.bytesIn, 110);
      expect(e.inRate, 1000);
      expect(e.outRate, 250);
      expect(e.sessionIn, 2000);
    });
  });

  group('AppsController', () {
    late DateTime now;
    late _Service service;
    late AppsController c;
    final pingers = <String, _Pinger>{};

    AppsController build(List<AppSnapshot> apps, {AppModeSettings? settings}) {
      now = DateTime(2026, 1, 1, 12);
      service = _Service(apps);
      return c = AppsController(
        service: service,
        settings: settings ?? AppModeSettings.test(),
        pingerFactory: (ip, _) => pingers[ip] = _Pinger(),
        hostnameResolver: (_) async => null,
        flowFactory: (ip) => FlowSession(initialIp: ip),
        clock: () => now,
      );
    }

    tearDown(() => c.dispose());

    test('computes per-app traffic rates from cumulative counters', () async {
      build([
        _snap('A', [_tcp(1, '8.8.8.8').withTraffic(1000, 100)]),
      ]);
      c.selectApp('a');
      await c.refresh(); // baseline: no rate yet
      expect(c.rateFor('a').inBps, 0);

      now = now.add(const Duration(seconds: 2));
      service.apps = [
        _snap('A', [_tcp(1, '8.8.8.8').withTraffic(5000, 500)]),
      ];
      await c.refresh();
      expect(c.rateFor('a').inBps, 2000);
      expect(c.rateFor('a').outBps, 200);
      final ep = c.endpointsFor('a').single;
      expect(ep.inRate, 2000);
      expect(ep.sessionIn, 4000);
      expect(c.summaryFor('a').sessionIn, 4000);
      expect(c.rateHistoryFor('a'), hasLength(1));
    });

    test('counter resets never produce negative rates', () async {
      build([
        _snap('A', [_tcp(1, '8.8.8.8').withTraffic(9000, 900)]),
      ]);
      c.selectApp('a');
      await c.refresh();
      now = now.add(const Duration(seconds: 1));
      service.apps = [
        _snap('A', [_tcp(1, '8.8.8.8').withTraffic(10, 1)]),
      ];
      await c.refresh();
      expect(c.rateFor('a').inBps, 0);
    });

    test(
      'activity log: baseline is one "tracking" event, then connect/close',
      () async {
        build([
          _snap('A', [_tcp(1, '1.1.1.1'), _tcp(1, '8.8.8.8', local: 6)]),
        ]);
        c.selectApp('a');
        await c.refresh();
        expect(c.eventsFor('a').map((e) => e.kind), [ActivityKind.started]);

        now = now.add(const Duration(seconds: 3));
        service.apps = [
          _snap('A', [_tcp(1, '1.1.1.1'), _tcp(1, '9.9.9.9', local: 7)]),
        ];
        await c.refresh();
        final kinds = c.eventsFor('a').map((e) => e.kind).toList();
        expect(kinds, contains(ActivityKind.connected));
        expect(kinds, contains(ActivityKind.closed));
        expect(c.summaryFor('a').newLastMinute, 1);
      },
    );

    test('degraded and recovered events fire on health transitions', () async {
      build([
        _snap('A', [_tcp(1, '1.1.1.1')]),
      ]);
      c.start();
      c.selectApp('a');
      await c.refresh();
      final p = pingers['1.1.1.1']!;
      for (var i = 0; i < 5; i++) {
        p.c.add(20);
      }
      for (var i = 0; i < 15; i++) {
        p.c.add(-1);
      }
      await Future<void>.delayed(Duration.zero);
      expect(
        c.eventsFor('a').map((e) => e.kind),
        contains(ActivityKind.degraded),
      );
      for (var i = 0; i < 25; i++) {
        p.c.add(20);
      }
      await Future<void>.delayed(Duration.zero);
      expect(
        c.eventsFor('a').map((e) => e.kind),
        contains(ActivityKind.recovered),
      );
      expect(c.problemEndpoints(), isEmpty);
    });

    test('sorting, filtering and search', () async {
      build([
        _snap('A', [
          _tcp(1, '1.1.1.1'),
          _tcp(1, '2.2.2.2', local: 6, port: 22),
          _tcp(1, '3.3.3.3', local: 7),
          _tcp(1, '3.3.3.3', local: 8),
        ]),
      ]);
      c.selectApp('a');
      await c.refresh();
      final eps = {for (final e in c.endpointsFor('a')) e.ip: e};
      eps['1.1.1.1']!.addSample(300);
      eps['2.2.2.2']!.addSample(20);

      c.updateView('a', (v) => v.sort = EndpointSort.latency);
      expect(c.filteredEndpointsFor('a').map((e) => e.ip).take(2), [
        '1.1.1.1',
        '2.2.2.2',
      ]);

      c.updateView('a', (v) => v.sort = EndpointSort.connections);
      expect(c.filteredEndpointsFor('a').first.ip, '3.3.3.3');

      c.updateView('a', (v) => v.sort = EndpointSort.address);
      expect(c.filteredEndpointsFor('a').first.ip, '1.1.1.1');

      c.updateView('a', (v) => v.query = 'ssh');
      expect(c.filteredEndpointsFor('a').map((e) => e.ip), ['2.2.2.2']);
      c.updateView('a', (v) => v.query = '');

      c.updateView('a', (v) => v.problemsOnly = true);
      expect(c.filteredEndpointsFor('a').map((e) => e.ip), ['1.1.1.1']);
    });

    test('summary aggregates latency, loss, services and families', () async {
      build([
        _snap('A', [
          _tcp(1, '1.1.1.1'),
          _tcp(1, '2606:4700::1', local: 6, port: 22),
        ]),
      ]);
      c.selectApp('a');
      await c.refresh();
      final eps = c.endpointsFor('a');
      eps.firstWhere((e) => e.ip == '1.1.1.1').addSample(10);
      eps.firstWhere((e) => e.ip == '1.1.1.1').addSample(-1);
      eps.firstWhere((e) => e.ip != '1.1.1.1').addSample(50);

      final s = c.summaryFor('a');
      expect(s.avgMs, 30);
      expect(s.fastestIp, '1.1.1.1');
      expect(s.slowestMs, 50);
      expect(s.lossPercent, closeTo(33.3, 0.1));
      expect(s.ipv4Count, 1);
      expect(s.ipv6Count, 1);
      expect(s.serviceCounts.map((e) => e.key), containsAll(['HTTPS', 'SSH']));
      expect(s.stateCounts['ESTABLISHED'], 2);
      expect(s.trafficAvailable, isTrue);
    });

    test('overview totals and top talkers order', () async {
      build([
        _snap('Quiet', [_tcp(1, '1.1.1.1')]),
        _snap('Busy', [_tcp(2, '2.2.2.2').withTraffic(0, 0)]),
      ]);
      await c.refresh();
      now = now.add(const Duration(seconds: 1));
      service.apps = [
        _snap('Quiet', [_tcp(1, '1.1.1.1')]),
        _snap('Busy', [_tcp(2, '2.2.2.2').withTraffic(8000, 0)]),
      ];
      await c.refresh();
      final o = c.overview;
      expect(o.appCount, 2);
      expect(o.endpointCount, 2);
      expect(o.connectionCount, 2);
      expect(o.talkers.first.app.name, 'Busy');
      expect(o.inRate, 8000);
    });

    test('pause keeps the controller idle until resume', () async {
      build([
        _snap('A', [_tcp(1, '1.1.1.1')]),
      ]);
      c.start();
      expect(c.isRunning, isTrue);
      c.pause();
      expect(c.isPaused, isTrue);
      expect(c.isRunning, isFalse);
      c.start(); // screen re-entered while paused
      expect(c.isRunning, isFalse);
      c.resume();
      expect(c.isRunning, isTrue);
    });

    test('settings changes apply live', () async {
      final s = AppModeSettings.test(maxLivePingers: 1);
      build([
        _snap('A', [_tcp(1, '1.1.1.1'), _tcp(1, '2.2.2.2', local: 6)]),
      ], settings: s);
      c.start();
      c.selectApp('a');
      await c.refresh();
      expect(c.livePingerCount, 1);
      s.setMaxLivePingers(5);
      expect(c.livePingerCount, 2);
    });

    test('collapseAll closes every expanded row', () async {
      build([
        _snap('A', [_tcp(1, '1.1.1.1'), _tcp(1, '2.2.2.2', local: 6)]),
      ]);
      c.selectApp('a');
      await c.refresh();
      for (final e in c.endpointsFor('a')) {
        c.toggleExpanded(e);
      }
      c.collapseAll('a');
      expect(c.endpointsFor('a').any((e) => e.isExpanded), isFalse);
    });
  });

  group('AppModeSettings', () {
    test('clamps and validates values', () {
      final s = AppModeSettings.test();
      s.setMaxLivePingers(999);
      expect(s.maxLivePingers, AppModeSettings.maxPingersLimit);
      s.setMaxLivePingers(0);
      expect(s.maxLivePingers, AppModeSettings.minPingers);
      s.setPollIntervalSec(4); // not an allowed choice
      expect(s.pollIntervalSec, 3);
      s.setPollIntervalSec(5);
      expect(s.pollInterval, const Duration(seconds: 5));
    });

    test('reset restores defaults and notifies', () {
      final s = AppModeSettings.test();
      var notified = 0;
      s.addListener(() => notified++);
      s.setIncludePrivate(true);
      s.setDensity(RowDensity.compact);
      s.resetToDefaults();
      expect(s.includePrivate, isFalse);
      expect(s.density, RowDensity.comfortable);
      expect(notified, 3);
    });

    test('remembered apps are cleared when remembering is turned off', () {
      final s = AppModeSettings.test();
      s.rememberApps(pinned: ['a'], selected: ['b']);
      expect(s.pinnedAppIds, ['a']);
      s.setRememberSelection(false);
      expect(s.pinnedAppIds, isEmpty);
      s.rememberApps(pinned: ['x'], selected: []);
      expect(s.pinnedAppIds, isEmpty);
    });
  });

  group('export', () {
    test('CSV quotes commas and JSON carries the fields', () {
      final e = EndpointState(appId: 'a', ip: '1.1.1.1')
        ..hostname = 'one, one'
        ..addSample(20);
      final records = endpointRecords([e], (_) => 'My App', 5);
      final csv = endpointsToCsv(records);
      expect(csv.split('\n').first, startsWith('app,ip,hostname'));
      expect(csv, contains('"one, one"'));
      expect(endpointsToJson(records), contains('"avgMs": 20'));
      expect(endpointsToCsv([]), isEmpty);
    });
  });

  group('Linux traffic (ss -i)', () {
    const ss =
        'ESTAB 0 0 10.0.0.2:44444 142.250.1.1:443 users:(("firefox",pid=123,fd=40))\n'
        '\t cubic wscale:7,7 rto:204 bytes_sent:1500 bytes_acked:1500 bytes_received:98765 segs_out:10\n'
        'ESTAB 0 0 10.0.0.2:44445 8.8.8.8:443 users:(("firefox",pid=123,fd=41))\n'
        '\t cubic wscale:7,7 rto:204 segs_out:1\n';

    test('reads per-socket byte counters from the continuation line', () {
      final flows = parseSsTraffic(ss);
      expect(flows, hasLength(1)); // second socket reports no counters
      expect(flows.single.bytesIn, 98765);
      expect(flows.single.bytesOut, 1500);
      expect(flows.single.localPort, 44444);
      expect(flows.single.remoteIp, '142.250.1.1');
    });

    test('connection parser ignores the info lines', () {
      expect(parseSsOutput(ss), hasLength(2));
    });

    test('poll on linux joins the counters onto connections', () async {
      final service = AppConnectionService(
        platform: 'linux',
        runner: (exe, args) async =>
            exe == 'ss' ? ss : '123 1 0.5 2048 01:00 firefox\n',
      );
      final app = (await service.poll()).single;
      expect(app.trafficAvailable, isTrue);
      expect(app.connections.first.bytesIn, 98765);
    });
  });

  group('TCP connect fallback', () {
    late AppsController c;
    final icmp = <String, _Pinger>{};
    final tcp = <(String, int), _Pinger>{};

    AppsController build({bool fallback = true}) {
      icmp.clear();
      tcp.clear();
      return c = AppsController(
        service: _Service([
          _snap('A', [_tcp(1, '1.1.1.1')]),
        ]),
        settings: AppModeSettings.test(tcpFallback: fallback),
        pingerFactory: (ip, _) => icmp[ip] = _Pinger(),
        tcpPingerFactory: (ip, port, _) => tcp[(ip, port)] = _Pinger(),
        hostnameResolver: (_) async => null,
      );
    }

    tearDown(() => c.dispose());

    test('silent host switches to TCP timing and gets real numbers', () async {
      build();
      c.start();
      c.selectApp('a');
      await c.refresh();
      final ep = c.endpointsFor('a').single;
      expect(ep.probe, ProbeMethod.icmp);

      for (var i = 0; i < 3; i++) {
        icmp['1.1.1.1']!.c.add(-1);
      }
      await Future<void>.delayed(Duration.zero);

      expect(ep.probe, ProbeMethod.tcp);
      expect(ep.history, isEmpty); // old failures forgotten
      expect(tcp.keys, contains(('1.1.1.1', 443)));
      expect(c.livePingerCount, 1);

      tcp[('1.1.1.1', 443)]!.c.add(25);
      await Future<void>.delayed(Duration.zero);
      expect(ep.health(5), EndpointHealth.good);
      expect(ep.averageMs, 25);
      expect(c.eventsFor('a').first.message, contains('ignores ping'));
    });

    test('disabled setting keeps ICMP and reports no reply', () async {
      build(fallback: false);
      c.start();
      c.selectApp('a');
      await c.refresh();
      for (var i = 0; i < 3; i++) {
        icmp['1.1.1.1']!.c.add(-1);
      }
      await Future<void>.delayed(Duration.zero);
      final ep = c.endpointsFor('a').single;
      expect(ep.probe, ProbeMethod.icmp);
      expect(ep.health(5), EndpointHealth.noReply);
      expect(tcp, isEmpty);
    });

    test('UDP-only endpoints never use the TCP probe', () async {
      build();
      c.dispose();
      c = AppsController(
        service: _Service([
          _snap('A', [
            const AppConnection(
              pid: 1,
              processName: 'a',
              protocol: 'UDP',
              state: '',
              remoteIp: '1.1.1.1',
              remotePort: 443,
              localPort: 9,
            ),
          ]),
        ]),
        settings: AppModeSettings.test(),
        pingerFactory: (ip, _) => icmp[ip] = _Pinger(),
        tcpPingerFactory: (ip, port, _) => tcp[(ip, port)] = _Pinger(),
        hostnameResolver: (_) async => null,
      );
      c.start();
      c.selectApp('a');
      await c.refresh();
      for (var i = 0; i < 3; i++) {
        icmp['1.1.1.1']!.c.add(-1);
      }
      await Future<void>.delayed(Duration.zero);
      expect(c.endpointsFor('a').single.probe, ProbeMethod.icmp);
      expect(tcp, isEmpty);
    });
  });

  group('latency trend', () {
    test('records one point per poll once endpoints are measured', () async {
      final c = AppsController(
        service: _Service([
          _snap('A', [_tcp(1, '1.1.1.1')]),
        ]),
        settings: AppModeSettings.test(),
        hostnameResolver: (_) async => null,
      );
      c.selectApp('a');
      await c.refresh();
      expect(c.latencyTrendFor('a'), isEmpty);
      c.endpointsFor('a').single.addSample(40);
      await c.refresh();
      await c.refresh();
      expect(c.latencyTrendFor('a'), [40, 40]);
      c.dispose();
    });
  });

  group('layout', () {
    for (final size in const [
      Size(620, 600),
      Size(800, 600),
      Size(1000, 700),
      Size(1400, 900),
    ]) {
      testWidgets('renders without overflow at ${size.width.toInt()}px', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final c = AppsController(
          service: _Service([
            _snap('Spotify', [
              _tcp(1, '104.18.26.48').withTraffic(1000, 200),
              _tcp(1, '104.18.26.48', local: 6).withTraffic(10, 20),
              _tcp(1, '2606:4700::6810:84e5', local: 7, port: 22),
              _tcp(1, '8.8.8.8', local: 8),
            ]),
            _snap('Other', [_tcp(2, '9.9.9.9', local: 9)]),
          ]),
          settings: AppModeSettings.test(),
          pingerFactory: (ip, _) => _Pinger(),
          hostnameResolver: (ip) async => 'host-$ip.example.com',
          flowFactory: (ip) => FlowSession(initialIp: ip),
        );
        await tester.pumpWidget(
          FluentApp(
            home: ScaffoldPage(
              padding: EdgeInsets.zero,
              content: AppsScreen(controller: c, onOpenAsTab: (_, _) {}),
            ),
          ),
        );
        await c.refresh();
        await tester.pump();

        // Overview, then an app with a slow, lossy and an expanded endpoint.
        expect(find.text('Overview'), findsWidgets);
        c.selectApp('spotify');
        await tester.pump();
        final eps = c.endpointsFor('spotify');
        for (final v in [20, 40, -1, 300, 250, 260]) {
          eps.first.addSample(v);
        }
        eps[1].addSample(30);
        c.toggleExpanded(eps.first);
        c.togglePin('other');
        c.updateView('spotify', (v) => v.activityOpen = true);
        await tester.pump();

        expect(find.text('Endpoints'), findsWidgets);
        expect(find.text('Avg latency'), findsOneWidget);
        expect(find.text('Open as tab'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Compact density and the empty/filter states.
        c.settings.setDensity(RowDensity.compact);
        c.updateView('spotify', (v) => v.query = 'zzz');
        await tester.pump();
        expect(find.text('No endpoints match these filters.'), findsOneWidget);
        expect(tester.takeException(), isNull);

        c.collapseAll('spotify');
        c.dispose();
        await tester.pumpWidget(const SizedBox());
      });
    }
  });

  group('choose-only tracking mode', () {
    late AppsController c;
    late AppModeSettings settings;
    late _Service service;
    final pingers = <String>[];

    AppsController build({TrackingMode mode = TrackingMode.selected}) {
      pingers.clear();
      settings = AppModeSettings.test(trackingMode: mode);
      service = _Service([
        _snap('A', [_tcp(1, '1.1.1.1').withTraffic(0, 0)]),
        _snap('B', [_tcp(2, '2.2.2.2').withTraffic(0, 0)]),
        _snap('C', [_tcp(3, '3.3.3.3').withTraffic(0, 0)]),
      ]);
      return c = AppsController(
        service: service,
        settings: settings,
        pingerFactory: (ip, _) {
          pingers.add(ip);
          return _Pinger();
        },
        hostnameResolver: (_) async => null,
      );
    }

    tearDown(() => c.dispose());

    test('nothing is tracked until the user ticks apps', () async {
      build();
      c.start();
      await c.refresh();
      expect(c.visibleAppIds, isEmpty);
      expect(c.showOverview, isTrue);
      expect(c.livePingerCount, 0);
      expect(pingers, isEmpty);
      expect(c.overview.appCount, 0);
      expect(c.overview.trackedApps, 0);
      // The rail can still offer every app to choose from.
      expect(c.apps.map((a) => a.name), containsAll(['A', 'B', 'C']));
    });

    test('several apps can be ticked and unticked', () async {
      build();
      c.start();
      await c.refresh();
      c.selectApp('a'); // selecting toggles in this mode
      c.toggleTracked('b');
      expect(c.visibleAppIds, {'a', 'b'});
      expect(c.selectedIds, isEmpty);
      expect(c.showOverview, isFalse);

      await c.refresh();
      expect(c.endpointsFor('a'), hasLength(1));
      expect(c.endpointsFor('b'), hasLength(1));
      expect(c.endpointsFor('c'), isEmpty);
      expect(c.livePingerCount, 2);

      c.toggleTracked('a');
      expect(c.visibleAppIds, {'b'});
      expect(c.livePingerCount, 1);
      c.toggleTracked('b');
      expect(c.visibleAppIds, isEmpty);
      expect(c.showOverview, isTrue);
    });

    test('overview and traffic only cover ticked apps', () async {
      build();
      await c.refresh();
      c.toggleTracked('a');
      await c.refresh();

      service.apps = [
        _snap('A', [_tcp(1, '1.1.1.1').withTraffic(4000, 0)]),
        _snap('B', [_tcp(2, '2.2.2.2').withTraffic(9000, 0)]),
        _snap('C', [_tcp(3, '3.3.3.3').withTraffic(9000, 0)]),
      ];
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await c.refresh();

      final o = c.overview;
      expect(o.appCount, 1);
      expect(o.talkers.single.app.name, 'A');
      expect(o.endpointCount, 1);
      expect(c.rateFor('b').inBps, 0); // untracked: never measured
      expect(c.rateFor('c').inBps, 0);
      expect(c.rateFor('a').inBps, greaterThan(0));
    });

    test('tick all shown / clear', () async {
      build();
      await c.refresh();
      c.trackAll(['a', 'b', 'c']);
      expect(c.visibleAppIds, hasLength(3));
      c.clearTracked();
      expect(c.visibleAppIds, isEmpty);
      expect(c.showOverview, isTrue);
    });

    test('openApp tracks an untracked app and shows its details', () async {
      build();
      await c.refresh();
      c.openApp('b');
      expect(c.isTracked('b'), isTrue);
      expect(c.showOverview, isFalse);
      c.openOverview();
      expect(c.showOverview, isTrue);
      c.openApp('b'); // already tracked: just navigates, never unticks
      expect(c.isTracked('b'), isTrue);
      expect(c.showOverview, isFalse);
    });

    test('switching modes at runtime resets what is in view', () async {
      build(mode: TrackingMode.everything);
      c.start();
      c.selectApp('a');
      c.togglePin('b');
      await c.refresh();
      expect(c.visibleAppIds, {'a', 'b'});

      settings.setTrackingMode(TrackingMode.selected);
      expect(c.visibleAppIds, {'b'}); // only the ticked/pinned one remains
      expect(c.selectedIds, isEmpty);
      expect(c.showOverview, isTrue);

      settings.setTrackingMode(TrackingMode.everything);
      c.selectApp('c');
      expect(c.visibleAppIds, {'b', 'c'});
    });

    test('remembers only the ticked apps in this mode', () async {
      build();
      await c.refresh();
      c.toggleTracked('a');
      c.toggleTracked('b');
      expect(settings.pinnedAppIds.toSet(), {'a', 'b'});
      expect(settings.selectedAppIds, isEmpty);
    });

    test('default mode is unchanged', () async {
      build(mode: TrackingMode.everything);
      await c.refresh();
      expect(c.overview.appCount, 3); // everything is listed
      c.selectApp('a');
      c.selectApp('b'); // exclusive selection in this mode
      expect(c.selectedIds, {'b'});
    });
  });

  group('choose-only mode UI', () {
    for (final width in const [620.0, 1100.0]) {
      testWidgets('rail checkboxes at ${width.toInt()}px', (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final c = AppsController(
          service: _Service([
            _snap('Spotify', [_tcp(1, '104.18.26.48')]),
            _snap('Firefox', [_tcp(2, '8.8.8.8', local: 7)]),
          ]),
          settings: AppModeSettings.test(trackingMode: TrackingMode.selected),
          pingerFactory: (ip, _) => _Pinger(),
          hostnameResolver: (_) async => null,
        );
        await tester.pumpWidget(
          FluentApp(
            home: ScaffoldPage(
              padding: EdgeInsets.zero,
              content: AppsScreen(controller: c, onOpenAsTab: (_, _) {}),
            ),
          ),
        );
        await c.refresh();
        await tester.pump();

        expect(find.text('No apps are being tracked'), findsOneWidget);
        expect(find.text('AVAILABLE APPS'), findsOneWidget);
        // Hide-system box + one per app.
        expect(find.byType(Checkbox), findsNWidgets(3));

        await tester.tap(find.text('Spotify').first);
        await tester.pump();
        expect(c.visibleAppIds, {'spotify'});
        expect(find.text('TRACKED (1)'), findsOneWidget);

        await tester.tap(find.text('Firefox').first);
        await tester.pump();
        expect(c.visibleAppIds, {'spotify', 'firefox'});
        expect(find.text('TRACKED (2)'), findsOneWidget);
        // Both apps now show their detail sections together.
        expect(find.text('Avg latency'), findsWidgets); // sections shown
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Clear'));
        await tester.pump();
        expect(c.visibleAppIds, isEmpty);
        expect(find.text('No apps are being tracked'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.pump(const Duration(milliseconds: 500));
        c.dispose();
        await tester.pumpWidget(const SizedBox());
      });
    }
  });
}
