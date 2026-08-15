import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class StorageHelper {
  static String? _cachedBaseDir;

  static Future<void> initialize() async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        final dir = await getApplicationDocumentsDirectory();
        _cachedBaseDir = dir.path;
      }
    } catch (_) {}
  }

  static String getBaseDir() {
    if (_cachedBaseDir != null && _cachedBaseDir!.isNotEmpty) {
      return _cachedBaseDir!;
    }
    try {
      if (Platform.isWindows) {
        return Platform.environment['APPDATA'] ??
            Platform.environment['USERPROFILE'] ??
            '.';
      }
      if (Platform.isMacOS || Platform.isLinux) {
        return Platform.environment['HOME'] ?? '.';
      }
    } catch (_) {}
    return '.';
  }

  static String getFilePath(String fileName) {
    final base = getBaseDir();
    if (Platform.isWindows) {
      return p.join(base, 'PingRoute', fileName);
    }
    if (Platform.isAndroid || Platform.isIOS) {
      return p.join(base, fileName);
    }
    return p.join(base, '.pingroute', fileName);
  }
}
