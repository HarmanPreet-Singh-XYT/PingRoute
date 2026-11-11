import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:PingRoute/models/app_mode_settings.dart';
import 'package:PingRoute/models/app_session.dart';
import 'package:PingRoute/models/flow_session.dart';
import 'package:PingRoute/screens/apps_screen.dart';
import 'package:PingRoute/services/app_connection_service.dart';

AppConnection _conn(int pid, String ip, {int port = 443}) => AppConnection(
  pid: pid,
  processName: 'app',
  protocol: 'TCP',
  state: 'ESTABLISHED',
  remoteIp: ip,
  remotePort: port,
);

AppSnapshot _app(String name, List<String> ips, {bool system = false}) =>
    AppSnapshot(
      id: name.toLowerCase(),
      name: name,
      pids: {1},
      connections: [for (final ip in ips) _conn(1, ip)],
      isSystem: system,
    );

class _FakeService extends AppConnectionService {
  _FakeService(this.apps);
  List<AppSnapshot> apps;
  @override
  Future<List<AppSnapshot>> poll({
    bool includePrivate = false,
    bool includeUdp = true,
  }) async => apps;
}

class _FakePinger implements EndpointPinger {
  _FakePinger(this.ip);
  final String ip;
  final controller = StreamController<int>.broadcast();
  bool disposed = false;
  @override
  Stream<int> get results => controller.stream;
  @override
  void dispose() {
    disposed = true;
    controller.close();
  }
}

class _Harness {
  _Harness(
    List<AppSnapshot> apps, {
    int maxPingers = 12,
    Duration idle = const Duration(seconds: 60),
  }) : service = _FakeService(apps) {
    controller = AppsController(
      service: service,
      pingerFactory: (ip, _) {
        final p = _FakePinger(ip);
        pingers[ip] = p;
        return p;
      },
      hostnameResolver: (ip) async =>
          ip == '1.1.1.1' ? 'one.one.one.one' : null,
      flowFactory: (ip) {
        final f = FlowSession(initialIp: ip);
        flows.add(f);
        return f;
      },
      settings: AppModeSettings.test(
        maxLivePingers: maxPingers,
        idleRetentionSec: idle.inSeconds,
      ),
      clock: () => now,
    );
  }

  final _FakeService service;
  late final AppsController controller;
  final pingers = <String, _FakePinger>{};
  final flows = <FlowSession>[];
  DateTime now = DateTime(2026, 1, 1, 12);
}

void main() {
  _manualStartTests();

  test('a re-seen IP gets its cached hostname back after expiring', () async {
    final h = _Harness([
      _app('A', ['1.1.1.1']),
    ], idle: const Duration(seconds: 10));
    h.controller.selectApp('a');
    await h.controller.refresh();
    await Future<void>.delayed(Duration.zero);

    h.service.apps = [_app('A', [])];
    h.now = h.now.add(const Duration(seconds: 30));
    await h.controller.refresh();
    expect(h.controller.endpointsFor('a'), isEmpty);

    h.service.apps = [
      _app('A', ['1.1.1.1']),
    ];
    await h.controller.refresh();
    expect(h.controller.endpointsFor('a').single.hostname, 'one.one.one.one');
    h.controller.dispose();
  });
  test('selecting an app lists one endpoint per distinct IP', () async {
    final h = _Harness([
      _app('Spotify', ['1.1.1.1', '8.8.8.8']),
    ]);
    h.controller.selectApp('spotify');
    await h.controller.refresh();

    final eps = h.controller.endpointsFor('spotify');
    expect(eps.map((e) => e.ip), unorderedEquals(['1.1.1.1', '8.8.8.8']));
    h.controller.dispose();
  });

  test(
    'only visible apps get endpoints; pinning keeps several visible',
    () async {
      final h = _Harness([
        _app('A', ['1.1.1.1']),
        _app('B', ['8.8.8.8']),
      ]);
      await h.controller.refresh();
      expect(h.controller.endpointsFor('a'), isEmpty);

      h.controller.togglePin('a');
      h.controller.selectApp('b');
      await h.controller.refresh();
      expect(h.controller.visibleAppIds, {'a', 'b'});
      expect(h.controller.endpointsFor('a'), hasLength(1));
      expect(h.controller.endpointsFor('b'), hasLength(1));
      h.controller.dispose();
    },
  );

  test('live pingers are capped at maxLivePingers, busiest first', () async {
    final ips = [for (var i = 1; i <= 5; i++) '8.8.8.$i'];
    final app = AppSnapshot(
      id: 'big',
      name: 'Big',
      pids: {1},
      // 8.8.8.5 has the most connections.
      connections: [
        for (final ip in ips) _conn(1, ip),
        _conn(1, '8.8.8.5', port: 444),
        _conn(1, '8.8.8.5', port: 445),
      ],
      isSystem: false,
    );
    final h = _Harness([app], maxPingers: 2);
    h.controller.start();
    h.controller.selectApp('big');
    await h.controller.refresh();

    expect(h.controller.livePingerCount, 2);
    expect(h.pingers.keys, contains('8.8.8.5'));
    final unpinged = h.controller
        .endpointsFor('big')
        .where((e) => !e.isPinging);
    expect(unpinged, hasLength(3));
    h.controller.dispose();
  });

  test('ping results feed history, loss and average', () async {
    final h = _Harness([
      _app('A', ['1.1.1.1']),
    ]);
    h.controller.start();
    h.controller.selectApp('a');
    await h.controller.refresh();

    final ep = h.controller.endpointsFor('a').single;
    final pinger = h.pingers['1.1.1.1']!;
    pinger.controller.add(20);
    pinger.controller.add(40);
    pinger.controller.add(-1);
    await Future<void>.delayed(Duration.zero);

    expect(ep.history, [20, 40, -1]);
    expect(ep.averageMs, 30);
    expect(ep.lossPercent, closeTo(33.3, 0.1));
    expect(ep.last, -1);
    h.controller.dispose();
  });

  test('history is bounded', () {
    final ep = EndpointState(appId: 'a', ip: '1.1.1.1');
    for (var i = 0; i < 200; i++) {
      ep.addSample(i);
    }
    expect(ep.history.length, EndpointState.historyLength);
    expect(ep.sent, 200);
  });

  test('closed connections go idle, stop pinging, then expire', () async {
    final h = _Harness([
      _app('A', ['1.1.1.1', '8.8.8.8']),
    ], idle: const Duration(seconds: 30));
    h.controller.start();
    h.controller.selectApp('a');
    await h.controller.refresh();
    expect(h.controller.livePingerCount, 2);

    // 8.8.8.8 disappears.
    h.service.apps = [
      _app('A', ['1.1.1.1']),
    ];
    h.now = h.now.add(const Duration(seconds: 3));
    await h.controller.refresh();

    final gone = h.controller
        .endpointsFor('a')
        .singleWhere((e) => e.ip == '8.8.8.8');
    expect(gone.isActive, isFalse);
    expect(h.pingers['8.8.8.8']!.disposed, isTrue);
    expect(h.controller.livePingerCount, 1);
    // Active endpoints sort before idle ones.
    expect(h.controller.endpointsFor('a').first.ip, '1.1.1.1');

    h.now = h.now.add(const Duration(seconds: 31));
    await h.controller.refresh();
    expect(h.controller.endpointsFor('a').map((e) => e.ip), ['1.1.1.1']);
    h.controller.dispose();
  });

  test('stop() disposes pingers but keeps history; start() resumes', () async {
    final h = _Harness([
      _app('A', ['1.1.1.1']),
    ]);
    h.controller.start();
    h.controller.selectApp('a');
    await h.controller.refresh();
    h.pingers['1.1.1.1']!.controller.add(10);
    await Future<void>.delayed(Duration.zero);

    h.controller.stop();
    expect(h.controller.livePingerCount, 0);
    expect(h.pingers['1.1.1.1']!.disposed, isTrue);
    expect(h.controller.endpointsFor('a').single.history, [10]);

    h.controller.start();
    await h.controller.refresh();
    expect(h.controller.livePingerCount, 1);
    h.controller.dispose();
  });

  test('hostnames resolve once and are shared by IP', () async {
    final h = _Harness([
      _app('A', ['1.1.1.1']),
    ]);
    h.controller.selectApp('a');
    await h.controller.refresh();
    await Future<void>.delayed(Duration.zero);
    expect(h.controller.endpointsFor('a').single.hostname, 'one.one.one.one');
    h.controller.dispose();
  });

  test(
    'expanding swaps the pinger for a traceroute flow; collapse restores it',
    () async {
      final h = _Harness([
        _app('A', ['1.1.1.1']),
      ]);
      h.controller.start();
      h.controller.selectApp('a');
      await h.controller.refresh();
      final ep = h.controller.endpointsFor('a').single;
      expect(ep.isPinging, isTrue);

      h.controller.toggleExpanded(ep);
      expect(ep.isExpanded, isTrue);
      expect(ep.isPinging, isFalse);
      expect(h.flows.single.ip, '1.1.1.1');

      h.controller.toggleExpanded(ep);
      expect(ep.isExpanded, isFalse);
      expect(h.flows.single.isDisposed, isTrue);
      expect(ep.isPinging, isTrue);
      h.controller.dispose();
    },
  );

  test('takeFlow hands the session over without disposing it', () async {
    final h = _Harness([
      _app('A', ['1.1.1.1']),
    ]);
    h.controller.selectApp('a');
    await h.controller.refresh();
    final ep = h.controller.endpointsFor('a').single;
    expect(h.controller.takeFlow(ep), isNull);

    h.controller.toggleExpanded(ep);
    final taken = h.controller.takeFlow(ep);
    expect(taken, same(h.flows.single));
    expect(ep.isExpanded, isFalse);
    h.controller.dispose();
    expect(taken!.isDisposed, isFalse); // now owned by the caller
    taken.dispose();
  });

  test('system apps are hidden unless selected', () async {
    final h = _Harness([
      _app('Safari', ['1.1.1.1']),
      _app('launchd', ['8.8.8.8'], system: true),
    ]);
    await h.controller.refresh();
    expect(h.controller.apps.map((a) => a.name), ['Safari']);
    h.controller.setHideSystem(false);
    expect(h.controller.apps, hasLength(2));
    h.controller.setHideSystem(true);
    h.controller.selectApp('launchd');
    expect(h.controller.apps.map((a) => a.name), contains('launchd'));
    h.controller.dispose();
  });

  test('search filters by name', () async {
    final h = _Harness([
      _app('Safari', ['1.1.1.1']),
      _app('Spotify', ['8.8.8.8']),
    ]);
    await h.controller.refresh();
    h.controller.setSearch('spo');
    expect(h.controller.apps.map((a) => a.name), ['Spotify']);
    h.controller.dispose();
  });

  testWidgets('Apps screen: pick app, see endpoints, expand, open as tab', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final h = _Harness([
      _app('Spotify', ['1.1.1.1', '8.8.8.8']),
    ]);
    String? openedIp;
    FlowSession? openedFlow;

    await tester.pumpWidget(
      FluentApp(
        home: ScaffoldPage(
          padding: EdgeInsets.zero,
          content: AppsScreen(
            controller: h.controller,
            onOpenAsTab: (ip, flow) {
              openedIp = ip;
              openedFlow = flow;
            },
          ),
        ),
      ),
    );
    await h.controller.refresh();
    await tester.pump();

    expect(find.text('Pick an app to monitor it'), findsOneWidget);
    expect(find.text('Spotify'), findsWidgets);

    await tester.tap(find.text('Spotify').first);
    await tester.pump();
    await tester.pump();
    expect(find.text('1.1.1.1'), findsOneWidget);
    expect(find.text('8.8.8.8'), findsOneWidget);

    await tester.tap(find.text('1.1.1.1'));
    await tester.pump();
    expect(find.text('Open as tab'), findsOneWidget);

    await tester.tap(find.text('Open as tab'));
    await tester.pump();
    expect(openedIp, '1.1.1.1');
    expect(openedFlow, same(h.flows.single));

    // Let button press/hover timers drain before the tree is torn down.
    await tester.pump(const Duration(milliseconds: 500));
    openedFlow!.dispose();
    h.controller.dispose();
  });
}

void _manualStartTests() {
  AppsController manual(_Harness h) => AppsController(
    service: h.service,
    pingerFactory: (ip, _) {
      final pg = _FakePinger(ip);
      h.pingers[ip] = pg;
      return pg;
    },
    hostnameResolver: (_) async => null,
    settings: AppModeSettings.test(autoStartTracking: false),
    clock: () => h.now,
  );

  test('selecting an app does not track it until Start is pressed', () async {
    final h = _Harness([
      _app('A', ['1.1.1.1', '8.8.8.8']),
    ]);
    final c = manual(h);
    c.start();
    c.selectApp('a');
    await c.refresh();

    expect(c.isTrackingActive('a'), isFalse);
    expect(c.endpointsFor('a'), isEmpty);
    expect(c.livePingerCount, 0);

    c.startTracking('a');
    await c.refresh();
    expect(c.endpointsFor('a'), hasLength(2));
    expect(c.livePingerCount, 2);

    c.stopTracking('a');
    expect(c.endpointsFor('a'), isEmpty);
    expect(c.livePingerCount, 0);
    expect(h.pingers['1.1.1.1']!.disposed, isTrue);
    c.dispose();
  });

  test('turning automatic start on tracks apps in view', () async {
    final h = _Harness([
      _app('A', ['1.1.1.1']),
    ]);
    final c = manual(h);
    c.start();
    c.selectApp('a');
    await c.refresh();
    expect(c.endpointsFor('a'), isEmpty);

    c.settings.setAutoStartTracking(true);
    await c.refresh();
    expect(c.endpointsFor('a'), hasLength(1));
    c.dispose();
  });
}
