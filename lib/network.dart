import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;

typedef GetTracerouteArrayC = Pointer<Pointer<Utf8>> Function(Pointer<Utf8>, Pointer<Int32>);
typedef GetTracerouteArrayDart = Pointer<Pointer<Utf8>> Function(Pointer<Utf8>, Pointer<Int32>);

typedef FreeTracerouteArrayC = Void Function(Pointer<Pointer<Utf8>>, Int32);
typedef FreeTracerouteArrayDart = void Function(Pointer<Pointer<Utf8>>, int);

typedef PingC = Int32 Function(Pointer<Utf8>);
typedef PingDart = int Function(Pointer<Utf8>);

class NetworkLib {
  late DynamicLibrary _lib;
  late GetTracerouteArrayDart getTracerouteArray;
  late FreeTracerouteArrayDart freeTracerouteArray;
  late PingDart ping;

  NetworkLib() {
    var libraryPath =
      path.join(Directory.current.path, 'network_library', 'libnetwork.so');

      if (Platform.isMacOS) {
        libraryPath =
            path.join(Directory.current.path, 'network_library', 'libnetwork.dylib');
      }

      if (Platform.isWindows) {
        libraryPath = 'network.dll';
      }
    _lib = Platform.isWindows
        ? DynamicLibrary.open(libraryPath)
        : throw UnsupportedError('Unsupported platform');

    getTracerouteArray = _lib
        .lookupFunction<GetTracerouteArrayC, GetTracerouteArrayDart>('get_traceroute_array');
    freeTracerouteArray = _lib
        .lookupFunction<FreeTracerouteArrayC, FreeTracerouteArrayDart>('free_traceroute_array');
    ping = _lib.lookupFunction<PingC, PingDart>('ping');
  }

  List<String> performTraceroute(String destination) {
    final destPtr = destination.toNativeUtf8();
    final hopCountPtr = calloc<Int32>();

    final resultPtr = getTracerouteArray(destPtr, hopCountPtr);
    final hopCount = hopCountPtr.value;

    final results = <String>[];
    for (int i = 0; i < hopCount; i++) {
      results.add(resultPtr[i].toDartString());
    }

    // Clean up native memory
    freeTracerouteArray(resultPtr, hopCount);
    calloc.free(hopCountPtr);
    calloc.free(destPtr);

    return results;
  }

  int performPing(String target) {
    final targetPtr = target.toNativeUtf8();
    final pingResult = ping(targetPtr);

    calloc.free(targetPtr); // Free the native memory

    return pingResult; // Return the ping result
  }
}
