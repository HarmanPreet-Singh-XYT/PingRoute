import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import 'app_connection_service.dart';

/// A process as reported by the native inventory.
class NativeProcess {
  const NativeProcess({
    required this.pid,
    required this.ppid,
    required this.name,
    required this.path,
    required this.rssKb,
    required this.cpuTimeNs,
    required this.startUnixMs,
  });

  final int pid;
  final int ppid;
  final String name;
  final String path;
  final int rssKb;

  /// Cumulative user+system CPU time; 0 when unknown.
  final int cpuTimeNs;

  /// Process start, unix epoch milliseconds; 0 when unknown.
  final int startUnixMs;
}

/// Capability bits mirrored from `native/pr_sockets.h`.
class NativeCapabilities {
  const NativeCapabilities(this.bits);
  final int bits;

  bool get connectionBytes => bits & 0x1 != 0;
  bool get processCpu => bits & 0x2 != 0;
  bool get udpFlows => bits & 0x4 != 0;
}

/// One point-in-time reading of the machine's sockets and processes.
class InventorySnapshot {
  const InventorySnapshot({
    required this.connections,
    required this.processes,
    required this.capabilities,
    required this.takenAt,
  });

  final List<AppConnection> connections;
  final List<NativeProcess> processes;
  final NativeCapabilities capabilities;
  final DateTime takenAt;
}

/// Source of socket/process data. The FFI implementation is the real one;
/// tests supply fakes.
abstract class SocketInventory {
  /// Returns null when the native library is unavailable or failed.
  Future<InventorySnapshot?> read();
}

/// Reads the inventory from the bundled C library (`pr_sockets.h`).
///
/// Reads run on one long-lived worker isolate. Spawning an isolate per poll
/// measurably grows the process over hours; the C calls themselves do not.
class FfiSocketInventory implements SocketInventory {
  FfiSocketInventory({String? libraryPath}) : _libraryPath = libraryPath;

  final String? _libraryPath;
  bool _broken = false;
  Isolate? _worker;
  SendPort? _requests;
  Future<void>? _starting;

  /// Whether a previous attempt showed the library cannot be used.
  bool get isBroken => _broken;

  @override
  Future<InventorySnapshot?> read() async {
    if (_broken) return null;
    try {
      await (_starting ??= _spawn());
      final requests = _requests;
      if (requests == null) return null;
      final reply = ReceivePort();
      requests.send(reply.sendPort);
      final result = await reply.first;
      reply.close();
      if (result is InventorySnapshot) return result;
      _broken = true; // library missing or layout mismatch
      dispose();
      return null;
    } on Object {
      _broken = true;
      dispose();
      return null;
    }
  }

  Future<void> _spawn() async {
    final path = _libraryPath ?? defaultLibraryPath();
    final ready = ReceivePort();
    _worker = await Isolate.spawn(_workerMain, (ready.sendPort, path));
    _requests = await ready.first as SendPort;
    ready.close();
  }

  /// Stops the worker isolate. A later [read] starts a fresh one.
  void dispose() {
    _worker?.kill(priority: Isolate.immediate);
    _worker = null;
    _requests = null;
    _starting = null;
  }

  static void _workerMain((SendPort, String?) args) {
    final (ready, path) = args;
    final inbox = ReceivePort();
    ready.send(inbox.sendPort);
    inbox.listen((message) {
      final reply = message as SendPort;
      reply.send(readInventory(path));
    });
  }

  /// Where the platform build puts the native library.
  static String? defaultLibraryPath() {
    final env = Platform.environment['PINGROUTE_NATIVE_LIB'];
    if (env != null && env.isNotEmpty) return env;
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    if (Platform.isMacOS) {
      return p.join(exeDir, '..', 'Frameworks', 'libnetwork.dylib');
    }
    if (Platform.isWindows) return p.join(exeDir, 'network.dll');
    if (Platform.isLinux) {
      final bundled = p.join(exeDir, 'lib', 'libnetwork.so');
      return File(bundled).existsSync() ? bundled : 'libnetwork.so';
    }
    return null;
  }
}

const _connectionSize = 72;
const _processSize = 1184;
const _bytesUnknown = -1; // 0xFFFF... read as a signed 64-bit value

typedef _ListC = Int32 Function(Pointer<Pointer<Uint8>>);
typedef _ListDart = int Function(Pointer<Pointer<Uint8>>);
typedef _FreeC = Void Function(Pointer<Void>);
typedef _FreeDart = void Function(Pointer<Void>);
typedef _U32C = Uint32 Function();
typedef _U32Dart = int Function();
typedef _I32C = Int32 Function();
typedef _I32Dart = int Function();

const _stateNames = <int, String>{
  1: 'ESTABLISHED',
  2: 'SYN_SENT',
  3: 'SYN_RECV',
  4: 'FIN_WAIT1',
  5: 'FIN_WAIT2',
  6: 'TIME_WAIT',
  7: 'CLOSE',
  8: 'CLOSE_WAIT',
  9: 'LAST_ACK',
  10: 'LISTEN',
  11: 'CLOSING',
};

/// Synchronous native read; runs inside a worker isolate. Null if the library
/// cannot be loaded or its struct layout differs from what we expect.
InventorySnapshot? readInventory(String? libraryPath) {
  if (libraryPath == null) return null;
  final DynamicLibrary lib;
  try {
    lib = DynamicLibrary.open(libraryPath);
  } on Object {
    return null;
  }

  final listConnections = lib.lookupFunction<_ListC, _ListDart>(
    'pr_list_connections',
  );
  final listProcesses = lib.lookupFunction<_ListC, _ListDart>(
    'pr_list_processes',
  );
  final free = lib.lookupFunction<_FreeC, _FreeDart>('pr_free');
  final caps = lib.lookupFunction<_U32C, _U32Dart>('pr_capabilities');
  final connSize = lib.lookupFunction<_I32C, _I32Dart>('pr_connection_size');
  final procSize = lib.lookupFunction<_I32C, _I32Dart>('pr_process_size');
  if (connSize() != _connectionSize || procSize() != _processSize) return null;

  final processes = _readProcesses(listProcesses, free);
  if (processes == null) return null;
  final nameByPid = {for (final pr in processes) pr.pid: pr.name};
  final connections = _readConnections(listConnections, free, nameByPid);
  if (connections == null) return null;

  return InventorySnapshot(
    connections: connections,
    processes: processes,
    capabilities: NativeCapabilities(caps()),
    takenAt: DateTime.now(),
  );
}

List<NativeProcess>? _readProcesses(_ListDart list, _FreeDart free) {
  final out = calloc<Pointer<Uint8>>();
  try {
    final n = list(out);
    if (n < 0) return null;
    if (n == 0) return const [];
    final base = out.value;
    try {
      final data = ByteData.sublistView(base.asTypedList(n * _processSize));
      final bytes = base.asTypedList(n * _processSize);
      return [
        for (var i = 0; i < n; i++)
          () {
            final o = i * _processSize;
            return NativeProcess(
              pid: data.getInt32(o, Endian.host),
              ppid: data.getInt32(o + 4, Endian.host),
              rssKb: data.getUint64(o + 8, Endian.host),
              cpuTimeNs: data.getUint64(o + 16, Endian.host),
              startUnixMs: data.getInt64(o + 24, Endian.host),
              name: _cString(bytes, o + 32, 128),
              path: _cString(bytes, o + 160, 1024),
            );
          }(),
      ];
    } finally {
      free(base.cast());
    }
  } finally {
    calloc.free(out);
  }
}

List<AppConnection>? _readConnections(
  _ListDart list,
  _FreeDart free,
  Map<int, String> nameByPid,
) {
  final out = calloc<Pointer<Uint8>>();
  try {
    final n = list(out);
    if (n < 0) return null;
    if (n == 0) return const [];
    final base = out.value;
    try {
      final bytes = base.asTypedList(n * _connectionSize);
      final data = ByteData.sublistView(bytes);
      final result = <AppConnection>[];
      for (var i = 0; i < n; i++) {
        final o = i * _connectionSize;
        final pid = data.getInt32(o, Endian.host);
        final proto = data.getInt32(o + 4, Endian.host);
        final family = data.getInt32(o + 8, Endian.host);
        final state = data.getInt32(o + 12, Endian.host);
        final alen = family == 4 ? 4 : 16;
        final remoteIp = formatAddress(
          Uint8List.fromList(bytes.sublist(o + 32, o + 32 + alen)),
        );
        final bytesIn = data.getInt64(o + 56, Endian.host);
        final bytesOut = data.getInt64(o + 64, Endian.host);
        result.add(
          AppConnection(
            pid: pid,
            processName: nameByPid[pid] ?? '',
            protocol: proto == 17 ? 'UDP' : 'TCP',
            state: proto == 17 ? '' : (_stateNames[state] ?? 'UNKNOWN'),
            remoteIp: remoteIp,
            remotePort: data.getUint16(o + 50, Endian.host),
            localPort: data.getUint16(o + 48, Endian.host),
            bytesIn: bytesIn == _bytesUnknown ? 0 : bytesIn,
            bytesOut: bytesOut == _bytesUnknown ? 0 : bytesOut,
          ),
        );
      }
      return result;
    } finally {
      free(base.cast());
    }
  } finally {
    calloc.free(out);
  }
}

String _cString(Uint8List bytes, int offset, int max) {
  var end = offset;
  while (end < offset + max && bytes[end] != 0) {
    end++;
  }
  return utf8.decode(bytes.sublist(offset, end), allowMalformed: true);
}

/// Formats a raw 4- or 16-byte address; IPv4-mapped IPv6 becomes plain IPv4.
String formatAddress(Uint8List raw) {
  if (raw.length == 16) {
    var mapped = raw[10] == 0xff && raw[11] == 0xff;
    for (var i = 0; i < 10 && mapped; i++) {
      if (raw[i] != 0) mapped = false;
    }
    if (mapped) return formatAddress(Uint8List.sublistView(raw, 12));
  }
  return InternetAddress.fromRawAddress(raw).address;
}
