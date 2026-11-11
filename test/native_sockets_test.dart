import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:PingRoute/services/app_connection_service.dart';
import 'package:PingRoute/services/native_sockets.dart';

class _FakeInventory implements SocketInventory {
  _FakeInventory(this.snapshots);
  final List<InventorySnapshot?> snapshots;
  int _i = 0;
  @override
  Future<InventorySnapshot?> read() async =>
      snapshots[_i < snapshots.length ? _i++ : snapshots.length - 1];
}

NativeProcess _proc(int pid, String path, {int cpuNs = 0, int rssKb = 100}) =>
    NativeProcess(
      pid: pid,
      ppid: 1,
      name: path.split('/').last,
      path: path,
      rssKb: rssKb,
      cpuTimeNs: cpuNs,
      startUnixMs: 0,
    );

AppConnection _conn(int pid, String ip, {String protocol = 'TCP'}) =>
    AppConnection(
      pid: pid,
      processName: 'app',
      protocol: protocol,
      state: protocol == 'TCP' ? 'ESTABLISHED' : '',
      remoteIp: ip,
      remotePort: 443,
      localPort: 50000,
    );

InventorySnapshot _snap(
  DateTime at,
  List<AppConnection> conns,
  List<NativeProcess> procs, {
  int caps = 3,
}) => InventorySnapshot(
  connections: conns,
  processes: procs,
  capabilities: NativeCapabilities(caps),
  takenAt: at,
);

void main() {
  test('formatAddress handles v4, v6 and v4-mapped', () {
    expect(formatAddress(Uint8List.fromList([8, 8, 4, 4])), '8.8.4.4');
    final mapped = Uint8List(16)
      ..[10] = 0xff
      ..[11] = 0xff
      ..setAll(12, [1, 1, 1, 1]);
    expect(formatAddress(mapped), '1.1.1.1');
    final v6 = Uint8List(16)
      ..[0] = 0x26
      ..[1] = 0x06
      ..[2] = 0x47
      ..[3] = 0x00
      ..[15] = 0x11;
    expect(formatAddress(v6), startsWith('2606:4700'));
  });

  test('native snapshot is grouped; CPU% comes from cpu-time deltas', () async {
    final t0 = DateTime(2026, 1, 1, 12);
    final inv = _FakeInventory([
      _snap(
        t0,
        [_conn(10, '1.1.1.1')],
        [
          _proc(
            10,
            '/Applications/Foo.app/Contents/MacOS/foo',
            cpuNs: 1000000000,
          ),
          _proc(11, '/Applications/Foo.app/Contents/Helper', cpuNs: 0),
        ],
      ),
      _snap(
        t0.add(const Duration(seconds: 2)),
        [_conn(10, '1.1.1.1')],
        [
          _proc(
            10,
            '/Applications/Foo.app/Contents/MacOS/foo',
            cpuNs: 2000000000,
          ),
          _proc(11, '/Applications/Foo.app/Contents/Helper', cpuNs: 1000000000),
        ],
      ),
    ]);
    final svc = AppConnectionService(
      platform: 'linux',
      runner: (_, _) async => '',
      inventory: inv,
    );

    final first = await svc.poll();
    expect(first.single.name, 'Foo');
    expect(first.single.cpuPercent, 0);
    expect(first.single.processCount, 2);

    final second = await svc.poll();
    // 1s + 1s of cpu over 2s of wall time across two processes = 100%.
    expect(second.single.cpuPercent, closeTo(100, 0.5));
  });

  test('falls back to command-line tools when native is unavailable', () async {
    var ran = false;
    final svc = AppConnectionService(
      platform: 'linux',
      runner: (exe, args) async {
        ran = true;
        return '';
      },
      inventory: _FakeInventory([null]),
    );
    expect(await svc.poll(), isEmpty);
    expect(ran, isTrue);
  });

  test('native UDP flows are not duplicated by nettop traffic', () async {
    final t0 = DateTime(2026, 1, 1);
    final svc = AppConnectionService(
      platform: 'macos',
      runner: (exe, args) async => exe == 'nettop'
          ? ',bytes_in,bytes_out,\n'
                'udp4 10.0.0.2:50000<->8.8.8.8:443,100,200,\n'
          : '',
      inventory: _FakeInventory([
        _snap(
          t0,
          [_conn(10, '8.8.8.8', protocol: 'UDP')],
          [_proc(10, '/Applications/Foo.app/Contents/MacOS/foo')],
          caps: 6,
        ),
      ]),
    );
    final apps = await svc.poll();
    expect(apps.single.connections, hasLength(1));
  });

  final canLive = Platform.isMacOS || Platform.isLinux;
  test('live: compiled C library lists this process\'s sockets', () async {
    final dir = Directory.systemTemp.createTempSync('pr_native_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final src = Platform.isMacOS
        ? 'macos/network_library/sockets_macos.c'
        : 'linux/network_library/sockets_linux.c';
    final lib = '${dir.path}/libpr.${Platform.isMacOS ? 'dylib' : 'so'}';
    final cc = await Process.run('cc', [
      Platform.isMacOS ? '-dynamiclib' : '-shared',
      '-fPIC',
      '-o',
      lib,
      src,
    ]);
    expect(cc.exitCode, 0, reason: '${cc.stderr}');

    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final client = await Socket.connect(
      InternetAddress.loopbackIPv4,
      server.port,
    );
    final accepted = await server.first;
    addTearDown(() async {
      client.destroy();
      accepted.destroy();
      await server.close();
    });

    final snap = await FfiSocketInventory(libraryPath: lib).read();
    expect(snap, isNotNull);
    final mine = snap!.connections.where(
      (c) =>
          c.pid == pid &&
          c.remoteIp == '127.0.0.1' &&
          c.remotePort == server.port,
    );
    expect(mine, isNotEmpty);
    expect(mine.first.state, 'ESTABLISHED');
    final self = snap.processes.where((p) => p.pid == pid);
    expect(self, hasLength(1));
    expect(self.single.rssKb, greaterThan(0));
    expect(self.single.path, isNotEmpty);
  }, skip: canLive ? false : 'needs macOS or Linux');
}
