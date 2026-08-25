import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

typedef GetTracerouteArrayC = Pointer<Pointer<Utf8>> Function(Pointer<Utf8>, Pointer<Int32>);
typedef GetTracerouteArrayDart = Pointer<Pointer<Utf8>> Function(Pointer<Utf8>, Pointer<Int32>);

typedef FreeTracerouteArrayC = Void Function(Pointer<Pointer<Utf8>>, Int32);
typedef FreeTracerouteArrayDart = void Function(Pointer<Pointer<Utf8>>, int);

typedef PingHostC = Int32 Function(Pointer<Utf8>, Int32);
typedef PingHostDart = int Function(Pointer<Utf8>, int);

typedef PingAllHopsC = Void Function(Pointer<Utf8>, Pointer<Pointer<Utf8>>, Int32, Int32, Pointer<Int32>);
typedef PingAllHopsDart = void Function(Pointer<Utf8>, Pointer<Pointer<Utf8>>, int, int, Pointer<Int32>);

class NetworkLib {
  DynamicLibrary? _lib;
  GetTracerouteArrayDart? getTracerouteArray;
  FreeTracerouteArrayDart? freeTracerouteArray;
  PingHostDart? pingHost;
  PingAllHopsDart? pingAllHops;
  bool _isNativeAvailable = false;

  bool get isNativeAvailable => _isNativeAvailable;

  /// Absolute path to the pingroute-net helper executable, or null if not found.
  final String? _helperPath;

  static DynamicLibrary _loadLibrary() {
    if (Platform.isIOS) {
      return DynamicLibrary.process();
    }
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libnetwork.so');
    }
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    if (Platform.isWindows) {
      return DynamicLibrary.open(p.join(exeDir, 'network.dll'));
    }
    if (Platform.isMacOS) {
      return DynamicLibrary.open(p.join(exeDir, '..', 'Frameworks', 'libnetwork.dylib'));
    }
    // Linux uses the helper-executable path instead of FFI (see _helperPath).
    return DynamicLibrary.process();
  }

  /// Finds the pingroute-net helper binary relative to the running executable.
  ///
  /// During `flutter run` (debug) the bundle layout is:
  ///   build/linux/`<arch>`/debug/bundle/pingroute          ← main exe
  ///   build/linux/`<arch>`/debug/bundle/pingroute-net      ← helper
  ///
  /// After `flutter build linux --release` (install bundle):
  ///   bundle/pingroute
  ///   bundle/pingroute-net
  static String? _findHelper() {
    if (!Platform.isLinux) return null;
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final candidate = p.join(exeDir, 'pingroute-net');
    if (File(candidate).existsSync()) return candidate;
    return null;
  }

  NetworkLib() : _helperPath = _findHelper() {
    // On Linux we use the helper subprocess; skip FFI loading entirely.
    if (Platform.isLinux) {
      _isNativeAvailable = _helperPath != null;
      return;
    }
    try {
      _lib = _loadLibrary();
      getTracerouteArray = _lib!
          .lookupFunction<GetTracerouteArrayC, GetTracerouteArrayDart>('get_traceroute_array');
      freeTracerouteArray = _lib!
          .lookupFunction<FreeTracerouteArrayC, FreeTracerouteArrayDart>('free_traceroute_array');
      try {
        pingHost = _lib!.lookupFunction<PingHostC, PingHostDart>('ping_host');
      } catch (_) {}
      try {
        pingAllHops = _lib!.lookupFunction<PingAllHopsC, PingAllHopsDart>('ping_all_hops');
      } catch (_) {}
      _isNativeAvailable = true;
    } catch (_) {
      _isNativeAvailable = false;
    }
  }

  int pingHostDirect(String destination, {int timeoutMs = 1000}) {
    if (destination.isEmpty || destination == '*' || destination == '?') return -1;
    if (pingHost != null) {
      final destPtr = destination.toNativeUtf8();
      try {
        return pingHost!(destPtr, timeoutMs);
      } catch (_) {
        return -1;
      } finally {
        calloc.free(destPtr);
      }
    }
    return -1;
  }

  List<int> pingAllHopsDirect(String targetDestination, List<String> destinations, {int timeoutMs = 800}) {
    if (destinations.isEmpty || targetDestination.isEmpty) return [];
    if (pingAllHops != null) {
      final count = destinations.length;
      final targetPtr = targetDestination.toNativeUtf8();
      final destPointers = calloc<Pointer<Utf8>>(count);
      final resultsPtr = calloc<Int32>(count);
      try {
        for (int i = 0; i < count; i++) {
          destPointers[i] = destinations[i].toNativeUtf8();
        }
        pingAllHops!(targetPtr, destPointers, count, timeoutMs, resultsPtr);
        return [for (int i = 0; i < count; i++) resultsPtr[i]];
      } catch (_) {
        return List.filled(count, -1);
      } finally {
        calloc.free(targetPtr);
        for (int i = 0; i < count; i++) {
          if (destPointers[i] != nullptr) {
            calloc.free(destPointers[i]);
          }
        }
        calloc.free(destPointers);
        calloc.free(resultsPtr);
      }
    }
    return List.filled(destinations.length, -1);
  }

  Future<List<String>> performTraceroute(String destination) async {
    final sanitized = _sanitize(destination);
    if (sanitized.isEmpty) return [];

    // ── Linux: spawn the privileged helper subprocess ──────────────────────
    // pingroute-net has CAP_NET_RAW set on it (by packaging / one-time setcap).
    // The main Flutter process itself needs zero privileges.
    if (Platform.isLinux && _helperPath != null) {
      final result = await _runHelper(sanitized);
      if (result.isNotEmpty) return result;
    }

    // ── Other platforms: call the native shared library via FFI ────────────
    if (!Platform.isLinux &&
        _isNativeAvailable &&
        getTracerouteArray != null &&
        freeTracerouteArray != null) {
      try {
        final destPtr = sanitized.toNativeUtf8();
        final hopCountPtr = calloc<Int32>();

        final resultPtr = getTracerouteArray!(destPtr, hopCountPtr);
        final hopCount = hopCountPtr.value;

        final results = <String>[];
        if (resultPtr != nullptr && hopCount > 0) {
          for (int i = 0; i < hopCount; i++) {
            results.add(resultPtr[i].toDartString());
          }
          freeTracerouteArray!(resultPtr, hopCount);
        }

        calloc.free(hopCountPtr);
        calloc.free(destPtr);

        if (results.isNotEmpty) return results;
      } catch (_) {}
    }

    // ── Final fallback: system CLI tools (tracepath / traceroute) ──────────
    // Works without any special privileges. Used when:
    //   • Linux: helper not found or not yet setcap'd
    //   • Other platforms: FFI library missing
    return _cliTraceroute(sanitized);
  }

  // ── Helper subprocess (Linux) ──────────────────────────────────────────────

  Future<List<String>> _runHelper(String destination) async {
    try {
      final proc = await Process.run(_helperPath!, [destination], runInShell: false);
      if (proc.exitCode != 0) return [];
      final lines = (proc.stdout as String)
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.startsWith('{hop:'))
          .toList();
      return lines;
    } catch (_) {
      return [];
    }
  }

  // ── CLI fallback (tracepath / traceroute) ──────────────────────────────────

  Future<List<String>> _cliTraceroute(String destination) async {
    if (!Platform.isLinux && !Platform.isMacOS) {
      return _dnsOnlyFallback(destination);
    }

    // Traceroute with UDP probes (-n -q 1 -w 1) completes in ~1s and bypasses
    // ISP ICMP filtering. tracepath uses ICMP and hangs on filtered networks.
    const candidates = [
      ['traceroute', '-q', '1', '-w', '1'],
      ['tracepath', '-n', '-b'],
    ];

    for (final cmd in candidates) {
      try {
        final proc = await Process.run(
          cmd[0],
          [...cmd.sublist(1), destination],
          runInShell: false,
        );
        final hops = _parseCliOutput(proc.stdout as String, cmd[0]);
        // Only accept result if we got valid responding hops
        final validHops = hops.where((h) => !h.contains('name:Unknown, ping:-1'));
        if (validHops.isNotEmpty) return hops;
      } catch (_) {}
    }

    return _dnsOnlyFallback(destination);
  }

  Future<List<String>> _dnsOnlyFallback(String destination) async {
    try {
      final addresses = await InternetAddress.lookup(destination);
      if (addresses.isNotEmpty) {
        final ip = addresses.first.address;
        final host = addresses.first.host;
        return ['{hop:1, ip:$ip, name:$host, ping:-1}'];
      }
    } catch (_) {}
    return [];
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static String _sanitize(String destination) => destination
      .trim()
      .replaceFirst(RegExp(r'^https?://'), '')
      .split('/')[0]
      .split(':')[0];

  /// Parses `tracepath -n -b` or `traceroute -n` stdout into hop strings.
  List<String> _parseCliOutput(String output, String tool) {
    final lines = output.split('\n');
    final results = <String>[];
    final seenHops = <int>{}; // tracepath probes each hop twice; keep first only.

    // tracepath line:  " 1:  192.168.1.1 (host.name)  3.540ms"
    // tracepath miss:  " 2:  no reply"
    // traceroute line: " 1  192.168.1.1   3.540 ms"
    // traceroute miss: " 2  * * *"
    final tracepathHop = RegExp(
        r'^\s*(\d+):\s+(\d+\.\d+\.\d+\.\d+)(?:\s+\(([^)]+)\))?\s+([\d.]+)ms');
    final tracepathNoReply = RegExp(r'^\s*(\d+):\s+no reply');
    final tracerouteHop = RegExp(
        r'^\s*(\d+)\s+([^\s()]+)(?:\s+\(([^)]+)\))?\s+([\d.]+)\s*ms');
    final tracerouteNoReply = RegExp(r'^\s*(\d+)\s+\*');

    for (final line in lines) {
      if (line.contains('[LOCALHOST]') ||
          line.contains('pmtu') ||
          line.contains('Resume:') ||
          line.contains('Too many hops')) {
        continue;
      }

      RegExpMatch? m;
      if (tool == 'tracepath') {
        m = tracepathHop.firstMatch(line);
        if (m != null) {
          final hop = int.parse(m.group(1)!);
          if (seenHops.add(hop)) {
            final ip = m.group(2)!;
            final name = m.group(3) ?? ip;
            final ping = double.parse(m.group(4)!).round();
            results.add('{hop:$hop, ip:$ip, name:$name, ping:$ping}');
          }
          continue;
        }
        m = tracepathNoReply.firstMatch(line);
        if (m != null) {
          final hop = int.parse(m.group(1)!);
          if (seenHops.add(hop)) {
            results.add('{hop:$hop, ip:, name:Unknown, ping:-1}');
          }
          continue;
        }
      } else {
        m = tracerouteHop.firstMatch(line);
        if (m != null) {
          final hop = int.parse(m.group(1)!);
          if (seenHops.add(hop)) {
            final String ip;
            final String name;
            if (m.group(3) != null) {
              ip = m.group(3)!;
              name = m.group(2)!;
            } else {
              ip = m.group(2)!;
              name = m.group(2)!;
            }
            final ping = double.parse(m.group(4)!).round();
            results.add('{hop:$hop, ip:$ip, name:$name, ping:$ping}');
          }
          continue;
        }
        m = tracerouteNoReply.firstMatch(line);
        if (m != null) {
          final hop = int.parse(m.group(1)!);
          if (seenHops.add(hop)) {
            results.add('{hop:$hop, ip:, name:Unknown, ping:-1}');
          }
          continue;
        }
      }
    }

    return results;
  }
}
