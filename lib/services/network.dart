import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

typedef GetTracerouteArrayC = Pointer<Pointer<Utf8>> Function(Pointer<Utf8>, Pointer<Int32>);
typedef GetTracerouteArrayDart = Pointer<Pointer<Utf8>> Function(Pointer<Utf8>, Pointer<Int32>);

typedef FreeTracerouteArrayC = Void Function(Pointer<Pointer<Utf8>>, Int32);
typedef FreeTracerouteArrayDart = void Function(Pointer<Pointer<Utf8>>, int);

class NetworkLib {
  DynamicLibrary? _lib;
  GetTracerouteArrayDart? getTracerouteArray;
  FreeTracerouteArrayDart? freeTracerouteArray;
  bool _isNativeAvailable = false;

  bool get isNativeAvailable => _isNativeAvailable;

  static DynamicLibrary _loadLibrary() {
    if (Platform.isIOS) {
      // On iOS, native C functions are compiled directly into the Runner executable
      return DynamicLibrary.process();
    }
    if (Platform.isAndroid) {
      // On Android, the NDK CMake builds libnetwork.so into the APK
      return DynamicLibrary.open('libnetwork.so');
    }
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    if (Platform.isWindows) {
      return DynamicLibrary.open(p.join(exeDir, 'network.dll'));
    }
    if (Platform.isLinux) {
      return DynamicLibrary.open(p.join(exeDir, 'lib', 'libnetwork.so'));
    }
    if (Platform.isMacOS) {
      return DynamicLibrary.open(p.join(exeDir, '..', 'Frameworks', 'libnetwork.dylib'));
    }
    return DynamicLibrary.process();
  }

  NetworkLib() {
    try {
      _lib = _loadLibrary();
      getTracerouteArray = _lib!
          .lookupFunction<GetTracerouteArrayC, GetTracerouteArrayDart>('get_traceroute_array');
      freeTracerouteArray = _lib!
          .lookupFunction<FreeTracerouteArrayC, FreeTracerouteArrayDart>('free_traceroute_array');
      _isNativeAvailable = true;
    } catch (_) {
      _isNativeAvailable = false;
    }
  }

  Future<List<String>> performTraceroute(String destination) async {
    if (_isNativeAvailable && getTracerouteArray != null && freeTracerouteArray != null) {
      try {
        final destPtr = destination.toNativeUtf8();
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

        if (results.isNotEmpty) {
          return results;
        }
      } catch (_) {}
    }

    // Fallback traceroute for restricted mobile/sandbox environments
    return _fallbackTraceroute(destination);
  }

  Future<List<String>> _fallbackTraceroute(String destination) async {
    try {
      final sanitized = destination
          .trim()
          .replaceFirst(RegExp(r'^https?:\/\/'), '')
          .split('/')[0]
          .split(':')[0];
      if (sanitized.isEmpty) return [];

      final addresses = await InternetAddress.lookup(sanitized);
      if (addresses.isNotEmpty) {
        final ip = addresses.first.address;
        final host = addresses.first.host;
        return [
          '{hop:1, ip:$ip, name:$host, ping:-1}',
        ];
      }
    } catch (_) {}
    return <String>[];
  }
}
