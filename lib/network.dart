import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

typedef GetTracerouteArrayC = Pointer<Pointer<Utf8>> Function(Pointer<Utf8>, Pointer<Int32>);
typedef GetTracerouteArrayDart = Pointer<Pointer<Utf8>> Function(Pointer<Utf8>, Pointer<Int32>);

typedef FreeTracerouteArrayC = Void Function(Pointer<Pointer<Utf8>>, Int32);
typedef FreeTracerouteArrayDart = void Function(Pointer<Pointer<Utf8>>, int);

class NetworkLib {
  late DynamicLibrary _lib;
  late GetTracerouteArrayDart getTracerouteArray;
  late FreeTracerouteArrayDart freeTracerouteArray;

  // Resolves the native library relative to the running executable rather
  // than the process's current working directory, so it's found regardless
  // of how/where the app was launched from.
  static String _resolveLibraryPath() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    if (Platform.isWindows) {
      return p.join(exeDir, 'network.dll');
    }
    if (Platform.isLinux) {
      return p.join(exeDir, 'lib', 'libnetwork.so');
    }
    if (Platform.isMacOS) {
      return p.join(exeDir, '..', 'Frameworks', 'libnetwork.dylib');
    }
    throw UnsupportedError('Unsupported platform');
  }

  NetworkLib() {
    _lib = DynamicLibrary.open(_resolveLibraryPath());

    getTracerouteArray = _lib
        .lookupFunction<GetTracerouteArrayC, GetTracerouteArrayDart>('get_traceroute_array');
    freeTracerouteArray = _lib
        .lookupFunction<FreeTracerouteArrayC, FreeTracerouteArrayDart>('free_traceroute_array');
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
}
