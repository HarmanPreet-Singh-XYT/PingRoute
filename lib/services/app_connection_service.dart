import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/ip_geolocation.dart' show isPrivateIp;
import 'native_sockets.dart';

/// A single socket owned by a process, as reported by the OS.
class AppConnection {
  const AppConnection({
    required this.pid,
    required this.processName,
    required this.protocol,
    required this.state,
    required this.remoteIp,
    required this.remotePort,
    this.localPort,
    this.bytesIn = 0,
    this.bytesOut = 0,
  });

  final int pid;
  final String processName;

  /// `TCP` or `UDP`.
  final String protocol;

  /// TCP state such as `ESTABLISHED`; empty for UDP flows.
  final String state;
  final String remoteIp;
  final int remotePort;
  final int? localPort;

  /// Cumulative bytes since the socket opened, when the OS reports them.
  final int bytesIn;
  final int bytesOut;

  bool get isUdp => protocol.toUpperCase() == 'UDP';
  bool get isIpv6 => remoteIp.contains(':');

  AppConnection withTraffic(int bytesIn, int bytesOut) => AppConnection(
    pid: pid,
    processName: processName,
    protocol: protocol,
    state: state,
    remoteIp: remoteIp,
    remotePort: remotePort,
    localPort: localPort,
    bytesIn: bytesIn,
    bytesOut: bytesOut,
  );

  /// Identity of this socket across polls.
  String get key => '$protocol|$localPort|$remoteIp|$remotePort';
}

/// A running process, used to map helper processes back to their parent app.
class RunningProcess {
  const RunningProcess({
    required this.pid,
    required this.ppid,
    required this.path,
    this.cpuPercent = 0,
    this.rssKb = 0,
    this.elapsed,
  });

  final int pid;
  final int ppid;

  /// Executable path (macOS/Windows) or bare command name (Linux).
  final String path;
  final double cpuPercent;

  /// Resident memory in KiB.
  final int rssKb;

  /// How long the process has been running.
  final Duration? elapsed;
}

/// Per-socket byte counters from `nettop` (macOS).
class TrafficFlow {
  const TrafficFlow({
    required this.pid,
    required this.process,
    required this.protocol,
    required this.localPort,
    required this.remoteIp,
    required this.remotePort,
    required this.bytesIn,
    required this.bytesOut,
  });

  final int pid;
  final String process;
  final String protocol;
  final int localPort;
  final String remoteIp;
  final int remotePort;
  final int bytesIn;
  final int bytesOut;

  String get key => '$protocol|$localPort|$remoteIp|$remotePort';
}

/// One application and every remote endpoint it currently talks to.
class AppSnapshot {
  const AppSnapshot({
    required this.id,
    required this.name,
    required this.pids,
    required this.connections,
    required this.isSystem,
    this.processCount = 0,
    this.cpuPercent = 0,
    this.rssKb = 0,
    this.uptime,
    this.trafficAvailable = false,
  });

  /// Stable key, e.g. `/Applications/Comet.app` or `firefox`.
  final String id;
  final String name;

  /// Processes that currently own a tracked connection.
  final Set<int> pids;
  final List<AppConnection> connections;
  final bool isSystem;

  /// Every process belonging to the app, connected or not.
  final int processCount;
  final double cpuPercent;
  final int rssKb;
  final Duration? uptime;

  /// False on platforms where per-socket byte counters aren't available.
  final bool trafficAvailable;

  /// Connection count per distinct remote IP.
  Map<String, int> get endpointCounts {
    final counts = <String, int>{};
    for (final c in connections) {
      counts.update(c.remoteIp, (n) => n + 1, ifAbsent: () => 1);
    }
    return counts;
  }

  int get bytesIn => connections.fold(0, (sum, c) => sum + c.bytesIn);
  int get bytesOut => connections.fold(0, (sum, c) => sum + c.bytesOut);
}

/// True for loopback / LAN / link-local / CGNAT addresses.
bool isNonPublicAddress(String ip) => isPrivateIp(ip);

/// Splits `host:port` or `[v6]:port` on the final colon.
({String host, int port})? splitHostPort(String value, {String sep = ':'}) {
  final idx = value.lastIndexOf(sep);
  if (idx <= 0) return null;
  var host = value.substring(0, idx);
  final port = int.tryParse(value.substring(idx + 1));
  if (port == null) return null;
  if (host.startsWith('[') && host.endsWith(']')) {
    host = host.substring(1, host.length - 1);
  }
  return (host: host, port: port);
}

/// Parses `lsof +c 0 -i TCP -n -P -F pcnTP` output (macOS / Linux with lsof).
List<AppConnection> parseLsofFields(String output) {
  final result = <AppConnection>[];
  var pid = 0;
  var cmd = '';
  var proto = '';
  var state = '';
  ({String host, int port})? remote;
  int? localPort;

  // The `TST=` state line follows the `n` line, so a record is only complete
  // when the next file (`f`) or process (`p`) starts, or the output ends.
  void flush() {
    final r = remote;
    if (r != null) {
      result.add(
        AppConnection(
          pid: pid,
          processName: cmd,
          protocol: proto.isEmpty ? 'TCP' : proto,
          state: state,
          remoteIp: r.host,
          remotePort: r.port,
          localPort: localPort,
        ),
      );
    }
    remote = null;
    localPort = null;
    proto = '';
    state = '';
  }

  for (final line in const LineSplitter().convert(output)) {
    if (line.isEmpty) continue;
    final tag = line[0];
    final value = line.substring(1);
    switch (tag) {
      case 'p':
        flush();
        pid = int.tryParse(value) ?? 0;
        cmd = '';
      case 'c':
        cmd = _unescapeLsof(value);
      case 'f':
        flush();
      case 'P':
        proto = value;
      case 'T':
        if (value.startsWith('ST=')) state = value.substring(3);
      case 'n':
        final arrow = value.indexOf('->');
        // Listening / unconnected sockets have no peer.
        if (arrow < 0) {
          remote = null;
        } else {
          remote = splitHostPort(value.substring(arrow + 2));
          localPort = splitHostPort(value.substring(0, arrow))?.port;
        }
    }
  }
  flush();
  return result;
}

/// lsof escapes spaces etc. in names as `\x20`.
String _unescapeLsof(String s) => s.replaceAllMapped(
  RegExp(r'\\x([0-9a-fA-F]{2})'),
  (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)),
);

/// Parses `ps` elapsed time: `[[dd-]hh:]mm:ss`.
Duration? parseElapsed(String value) {
  final m = RegExp(r'^(?:(\d+)-)?(?:(\d+):)?(\d+):(\d+)$').firstMatch(value);
  if (m == null) return null;
  return Duration(
    days: int.tryParse(m.group(1) ?? '') ?? 0,
    hours: int.tryParse(m.group(2) ?? '') ?? 0,
    minutes: int.parse(m.group(3)!),
    seconds: int.parse(m.group(4)!),
  );
}

/// Parses `ps -axo pid=,ppid=,pcpu=,rss=,etime=,comm=` output. The older
/// three-column `pid ppid comm` form is still accepted.
List<RunningProcess> parsePsOutput(String output) {
  final result = <RunningProcess>[];
  final full = RegExp(
    r'^\s*(\d+)\s+(\d+)\s+(\d+(?:\.\d+)?)\s+(\d+)\s+([\d:-]+)\s+(.+?)\s*$',
  );
  final basic = RegExp(r'^\s*(\d+)\s+(\d+)\s+(.+?)\s*$');
  for (final line in const LineSplitter().convert(output)) {
    final f = full.firstMatch(line);
    if (f != null) {
      result.add(
        RunningProcess(
          pid: int.parse(f.group(1)!),
          ppid: int.parse(f.group(2)!),
          cpuPercent: double.parse(f.group(3)!),
          rssKb: int.parse(f.group(4)!),
          elapsed: parseElapsed(f.group(5)!),
          path: f.group(6)!,
        ),
      );
      continue;
    }
    final b = basic.firstMatch(line);
    if (b == null) continue;
    result.add(
      RunningProcess(
        pid: int.parse(b.group(1)!),
        ppid: int.parse(b.group(2)!),
        path: b.group(3)!,
      ),
    );
  }
  return result;
}

/// Parses `nettop -n -x -L 1 -J bytes_in,bytes_out` output (macOS).
///
/// Process rows look like `Comet Helper.1496,in,out,` and are followed by
/// their sockets: `tcp4 10.0.0.5:59936<->1.2.3.4:443,in,out,`. IPv6 sockets
/// separate the port with `.` instead of `:`.
List<TrafficFlow> parseNettop(String output) {
  final flows = <TrafficFlow>[];
  var pid = 0;
  var process = '';
  final sockRe = RegExp(r'^(tcp|udp)([46])\s+(.+?)<->(.+)$');

  for (final line in const LineSplitter().convert(output)) {
    if (line.isEmpty || line.startsWith(',')) continue;
    final cols = line.split(',');
    if (cols.length < 3) continue;
    final label = cols[0];
    final bytesIn = int.tryParse(cols[1]) ?? 0;
    final bytesOut = int.tryParse(cols[2]) ?? 0;

    final sock = sockRe.firstMatch(label);
    if (sock == null) {
      final dot = label.lastIndexOf('.');
      if (dot > 0) {
        process = label.substring(0, dot);
        pid = int.tryParse(label.substring(dot + 1)) ?? 0;
      }
      continue;
    }

    final sep = sock.group(2) == '6' ? '.' : ':';
    String strip(String addr) {
      final scope = addr.indexOf('%');
      if (scope < 0) return addr;
      // `fe80::1%en0.5353` — drop the zone id but keep the port suffix.
      final portDot = addr.lastIndexOf('.');
      return portDot > scope
          ? addr.substring(0, scope) + addr.substring(portDot)
          : addr.substring(0, scope);
    }

    final local = splitHostPort(strip(sock.group(3)!), sep: sep);
    final remote = splitHostPort(strip(sock.group(4)!), sep: sep);
    if (local == null || remote == null) continue;
    if (remote.host == '*' || remote.host.isEmpty) continue;
    flows.add(
      TrafficFlow(
        pid: pid,
        process: process,
        protocol: sock.group(1)!.toUpperCase(),
        localPort: local.port,
        remoteIp: remote.host,
        remotePort: remote.port,
        bytesIn: bytesIn,
        bytesOut: bytesOut,
      ),
    );
  }
  return flows;
}

/// Parses `ss -tnpH` output (Linux). Only established sockets carry a peer.
List<AppConnection> parseSsOutput(String output) {
  final result = <AppConnection>[];
  final proc = RegExp(r'\("([^"]*)",pid=(\d+)');
  for (final line in const LineSplitter().convert(output)) {
    final cols = line.trim().split(RegExp(r'\s+'));
    if (cols.length < 5) continue;
    final remote = splitHostPort(cols[4]);
    if (remote == null) continue;
    final m = proc.firstMatch(line);
    if (m == null) continue;
    result.add(
      AppConnection(
        pid: int.parse(m.group(2)!),
        processName: m.group(1)!,
        protocol: 'TCP',
        state: cols[0] == 'ESTAB' ? 'ESTABLISHED' : cols[0],
        remoteIp: remote.host,
        remotePort: remote.port,
        localPort: splitHostPort(cols[3])?.port,
      ),
    );
  }
  return result;
}

/// Parses the `bytes_sent:` / `bytes_received:` counters that `ss -tnpi`
/// prints on the line after each socket (Linux).
List<TrafficFlow> parseSsTraffic(String output) {
  final flows = <TrafficFlow>[];
  final proc = RegExp(r'\("([^"]*)",pid=(\d+)');
  AppConnection? current;
  String name = '';
  for (final line in const LineSplitter().convert(output)) {
    if (line.isEmpty) continue;
    if (!line.startsWith(RegExp(r'\s'))) {
      final conn = parseSsOutput(line);
      current = conn.isEmpty ? null : conn.first;
      name = proc.firstMatch(line)?.group(1) ?? '';
      continue;
    }
    final c = current;
    if (c == null || c.localPort == null) continue;
    final sent = int.tryParse(
      RegExp(r'bytes_sent:(\d+)').firstMatch(line)?.group(1) ??
          RegExp(r'bytes_acked:(\d+)').firstMatch(line)?.group(1) ??
          '',
    );
    final received = int.tryParse(
      RegExp(r'bytes_received:(\d+)').firstMatch(line)?.group(1) ?? '',
    );
    if (sent == null && received == null) continue;
    flows.add(
      TrafficFlow(
        pid: c.pid,
        process: name,
        protocol: 'TCP',
        localPort: c.localPort!,
        remoteIp: c.remoteIp,
        remotePort: c.remotePort,
        bytesIn: received ?? 0,
        bytesOut: sent ?? 0,
      ),
    );
    current = null;
  }
  return flows;
}

/// Parses `Get-NetTCPConnection ... | ConvertTo-Json` output (Windows).
List<AppConnection> parseWindowsConnections(
  String json,
  Map<int, String> namesByPid,
) {
  final decoded = _decodeJsonList(json);
  final result = <AppConnection>[];
  for (final item in decoded) {
    final ip = item['RemoteAddress']?.toString() ?? '';
    final port = item['RemotePort'];
    final pid = item['OwningProcess'];
    if (ip.isEmpty || port is! int || pid is! int) continue;
    final local = item['LocalPort'];
    result.add(
      AppConnection(
        pid: pid,
        processName: namesByPid[pid] ?? '',
        protocol: 'TCP',
        state: 'ESTABLISHED',
        remoteIp: ip,
        remotePort: port,
        localPort: local is int ? local : null,
      ),
    );
  }
  return result;
}

/// Parses `Get-CimInstance Win32_Process | ConvertTo-Json` output.
List<RunningProcess> parseWindowsProcesses(String json, {DateTime? now}) {
  final clock = now ?? DateTime.now();
  final result = <RunningProcess>[];
  for (final item in _decodeJsonList(json)) {
    final pid = item['ProcessId'];
    final ppid = item['ParentProcessId'];
    if (pid is! int || ppid is! int) continue;
    final path = (item['ExecutablePath'] ?? item['Name'] ?? '').toString();

    final workingSet = item['WorkingSetSize'];
    // PowerShell 5 serialises dates as `/Date(1699999999999)/`.
    final created = RegExp(
      r'Date\((\d+)\)',
    ).firstMatch(item['CreationDate']?.toString() ?? '');
    result.add(
      RunningProcess(
        pid: pid,
        ppid: ppid,
        path: path,
        rssKb: workingSet is num ? workingSet ~/ 1024 : 0,
        elapsed: created == null
            ? null
            : clock.difference(
                DateTime.fromMillisecondsSinceEpoch(
                  int.parse(created.group(1)!),
                ),
              ),
      ),
    );
  }
  return result;
}

/// PowerShell's ConvertTo-Json emits a bare object for a single item.
List<Map<String, dynamic>> _decodeJsonList(String json) {
  if (json.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(json);
    if (decoded is List) {
      return decoded.whereType<Map<String, dynamic>>().toList();
    }
    if (decoded is Map<String, dynamic>) return [decoded];
  } on FormatException {
    // fall through
  }
  return const [];
}

/// Display name and grouping key for an executable path.
///
/// Helper processes live inside their parent's `.app` bundle on macOS, so
/// grouping by the outermost bundle merges `Comet`, `Comet Helper` and
/// `Comet Helper (Renderer)` into one app. Elsewhere we group by executable
/// file name.
({String id, String name}) appIdentity(String path, String fallbackName) {
  final bundle = RegExp(r'^(.*?/([^/]+)\.app)(?:/|$)').firstMatch(path);
  if (bundle != null) {
    return (id: bundle.group(1)!, name: bundle.group(2)!);
  }
  final normalized = path.replaceAll('\\', '/');
  var base = normalized.contains('/')
      ? normalized.substring(normalized.lastIndexOf('/') + 1)
      : normalized;
  if (base.isEmpty) base = fallbackName;
  if (base.isEmpty) return (id: 'unknown', name: 'Unknown');
  final name = base.toLowerCase().endsWith('.exe')
      ? base.substring(0, base.length - 4)
      : base;
  return (id: name.toLowerCase(), name: name);
}

/// Heuristic for OS-owned processes the user usually wants hidden.
bool isSystemProcessPath(String path) {
  final p = path.replaceAll('\\', '/').toLowerCase();
  return p.startsWith('/system/') ||
      p.startsWith('/usr/') ||
      p.startsWith('/sbin/') ||
      p.startsWith('/bin/') ||
      p.startsWith('/library/apple/') ||
      p.startsWith('c:/windows/');
}

/// Groups raw connections into per-application snapshots.
///
/// TCP connections must be established. Public addresses only, unless
/// [includePrivate]. UDP flows (from [traffic]) are added when [includeUdp].
/// Apps are ordered by number of distinct endpoints, then name.
List<AppSnapshot> groupConnectionsByApp(
  List<AppConnection> connections,
  List<RunningProcess> processes, {
  List<TrafficFlow>? traffic,
  bool includePrivate = false,
  bool includeUdp = true,
  bool addUdpFromTraffic = true,
  bool? trafficAvailable,
}) {
  final pathByPid = {for (final p in processes) p.pid: p.path};
  final trafficByKey = {
    for (final f in traffic ?? const <TrafficFlow>[]) f.key: f,
  };

  final all = <AppConnection>[
    for (final c in connections)
      if (c.state.isEmpty || c.state == 'ESTABLISHED')
        if (trafficByKey[c.key] case final f?)
          c.withTraffic(f.bytesIn, f.bytesOut)
        else
          c,
    if (includeUdp && addUdpFromTraffic)
      for (final f in traffic ?? const <TrafficFlow>[])
        if (f.protocol == 'UDP')
          AppConnection(
            pid: f.pid,
            processName: f.process,
            protocol: 'UDP',
            state: '',
            remoteIp: f.remoteIp,
            remotePort: f.remotePort,
            localPort: f.localPort,
            bytesIn: f.bytesIn,
            bytesOut: f.bytesOut,
          ),
  ];

  final byId = <String, _AppBuilder>{};
  for (final c in all) {
    if (!includePrivate && isNonPublicAddress(c.remoteIp)) continue;
    final path = pathByPid[c.pid] ?? '';
    final identity = appIdentity(path, c.processName);
    final builder = byId.putIfAbsent(
      identity.id,
      () => _AppBuilder(identity.id, identity.name, isSystemProcessPath(path)),
    );
    builder.pids.add(c.pid);
    builder.connections.add(c);
  }

  // Resource usage covers every process of the app, not only the ones that
  // currently own a socket (e.g. a browser's renderer processes).
  for (final p in processes) {
    final id = appIdentity(p.path, '').id;
    final builder = byId[id];
    if (builder == null) continue;
    builder.processCount++;
    builder.cpu += p.cpuPercent;
    builder.rssKb += p.rssKb;
    final e = p.elapsed;
    if (e != null && (builder.uptime == null || e > builder.uptime!)) {
      builder.uptime = e;
    }
  }

  final hasTraffic =
      trafficAvailable ?? (traffic != null && traffic.isNotEmpty);
  final apps = [
    for (final b in byId.values)
      AppSnapshot(
        id: b.id,
        name: b.name,
        pids: b.pids,
        connections: b.connections,
        isSystem: b.isSystem,
        processCount: b.processCount,
        cpuPercent: b.cpu,
        rssKb: b.rssKb,
        uptime: b.uptime,
        trafficAvailable: hasTraffic,
      ),
  ];
  apps.sort((a, b) {
    final byCount = b.endpointCounts.length.compareTo(a.endpointCounts.length);
    return byCount != 0
        ? byCount
        : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return apps;
}

class _AppBuilder {
  _AppBuilder(this.id, this.name, this.isSystem);
  final String id;
  final String name;
  final bool isSystem;
  final Set<int> pids = {};
  final List<AppConnection> connections = [];
  int processCount = 0;
  double cpu = 0;
  int rssKb = 0;
  Duration? uptime;
}

/// Runs a command and returns stdout, or an empty string on any failure.
typedef CommandRunner =
    Future<String> Function(String executable, List<String> args);

Future<String> _defaultRunner(String executable, List<String> args) async {
  try {
    final result = await Process.run(
      executable,
      args,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    ).timeout(const Duration(seconds: 8));
    return result.stdout as String;
  } on Object {
    return '';
  }
}

/// Polls the OS for per-application connections.
class AppConnectionService {
  /// Uses the bundled native library when it loads, and falls back to the
  /// platform's command-line tools otherwise. Injecting a [runner] or
  /// [platform] (tests) selects the command-line path unless [inventory] is
  /// also given.
  AppConnectionService({
    CommandRunner? runner,
    String? platform,
    SocketInventory? inventory,
  }) : _run = runner ?? _defaultRunner,
       _platform = platform ?? Platform.operatingSystem,
       _inventory =
           inventory ??
           (runner == null && platform == null ? FfiSocketInventory() : null);

  final CommandRunner _run;
  final String _platform;
  final SocketInventory? _inventory;

  // Cumulative CPU time per pid at the previous native poll.
  Map<int, int> _prevCpuNs = {};
  DateTime? _prevAt;

  /// Desktop operating systems this service can inspect.
  static bool get isSupported =>
      Platform.isMacOS || Platform.isLinux || Platform.isWindows;

  Future<List<AppSnapshot>> poll({
    bool includePrivate = false,
    bool includeUdp = true,
  }) async {
    final native = await _pollNative(
      includePrivate: includePrivate,
      includeUdp: includeUdp,
    );
    if (native != null) return native;
    switch (_platform) {
      case 'macos':
        return _pollUnix(
          useLsof: true,
          includePrivate: includePrivate,
          includeUdp: includeUdp,
        );
      case 'linux':
        return _pollUnix(
          useLsof: false,
          includePrivate: includePrivate,
          includeUdp: includeUdp,
        );
      case 'windows':
        return _pollWindows(includePrivate: includePrivate);
      default:
        return const [];
    }
  }

  Future<List<AppSnapshot>?> _pollNative({
    required bool includePrivate,
    required bool includeUdp,
  }) async {
    final inventory = _inventory;
    if (inventory == null) return null;
    // macOS has no public per-socket byte counters; nettop still supplies
    // them, in parallel with the native read.
    final nettop = _platform == 'macos'
        ? _run('nettop', [
            '-n',
            '-x',
            '-L',
            '1',
            '-t',
            includePrivate ? 'all' : 'external',
            '-J',
            'bytes_in,bytes_out',
          ])
        : Future.value('');
    final snap = await inventory.read();
    final nettopOut = await nettop;
    if (snap == null) return null;

    final now = snap.takenAt;
    final elapsedSec = _prevAt == null
        ? 0.0
        : now.difference(_prevAt!).inMicroseconds / 1e6;
    final nextCpu = <int, int>{};
    final processes = <RunningProcess>[];
    for (final p in snap.processes) {
      nextCpu[p.pid] = p.cpuTimeNs;
      final prev = _prevCpuNs[p.pid];
      var cpu = 0.0;
      if (prev != null && elapsedSec > 0 && p.cpuTimeNs >= prev) {
        cpu = (p.cpuTimeNs - prev) / 1e9 / elapsedSec * 100;
      }
      processes.add(
        RunningProcess(
          pid: p.pid,
          ppid: p.ppid,
          path: p.path.isNotEmpty ? p.path : p.name,
          cpuPercent: cpu,
          rssKb: p.rssKb,
          elapsed: p.startUnixMs > 0
              ? now.difference(
                  DateTime.fromMillisecondsSinceEpoch(p.startUnixMs),
                )
              : null,
        ),
      );
    }
    _prevCpuNs = nextCpu;
    _prevAt = now;

    final traffic = parseNettop(nettopOut);
    return groupConnectionsByApp(
      snap.connections,
      processes,
      traffic: traffic,
      includePrivate: includePrivate,
      includeUdp: includeUdp,
      // The native list already contains connected UDP sockets; nettop only
      // adds their byte counts.
      addUdpFromTraffic: !snap.capabilities.udpFlows,
      trafficAvailable: snap.capabilities.connectionBytes || traffic.isNotEmpty,
    );
  }

  Future<List<AppSnapshot>> _pollUnix({
    required bool useLsof,
    required bool includePrivate,
    required bool includeUdp,
  }) async {
    final results = await Future.wait([
      useLsof
          ? _run('lsof', ['+c', '0', '-i', 'TCP', '-n', '-P', '-F', 'pcnTP'])
          : _run('ss', ['-tnpiH']),
      _run('ps', ['-axo', 'pid=,ppid=,pcpu=,rss=,etime=,comm=']),
      // Per-socket byte counters and UDP flows; macOS only.
      useLsof
          ? _run('nettop', [
              '-n',
              '-x',
              '-L',
              '1',
              '-t',
              includePrivate ? 'all' : 'external',
              '-J',
              'bytes_in,bytes_out',
            ])
          : Future.value(''),
    ]);
    final connections = useLsof
        ? parseLsofFields(results[0])
        : parseSsOutput(results[0]);
    return groupConnectionsByApp(
      connections,
      parsePsOutput(results[1]),
      traffic: useLsof ? parseNettop(results[2]) : parseSsTraffic(results[0]),
      includePrivate: includePrivate,
      includeUdp: includeUdp,
    );
  }

  Future<List<AppSnapshot>> _pollWindows({required bool includePrivate}) async {
    const connCmd =
        'Get-NetTCPConnection -State Established | '
        'Select-Object LocalPort,RemoteAddress,RemotePort,OwningProcess | '
        'ConvertTo-Json';
    const procCmd =
        'Get-CimInstance Win32_Process | '
        'Select-Object ProcessId,ParentProcessId,Name,ExecutablePath,'
        'WorkingSetSize,CreationDate | ConvertTo-Json';
    final results = await Future.wait([
      _run('powershell', ['-NoProfile', '-Command', connCmd]),
      _run('powershell', ['-NoProfile', '-Command', procCmd]),
    ]);
    final processes = parseWindowsProcesses(results[1]);
    final names = {
      for (final p in processes)
        p.pid: p.path.replaceAll('\\', '/').split('/').last,
    };
    final connections = parseWindowsConnections(results[0], names);
    return groupConnectionsByApp(
      connections,
      processes,
      includePrivate: includePrivate,
    );
  }
}
