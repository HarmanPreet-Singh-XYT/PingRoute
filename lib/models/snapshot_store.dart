import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../core/storage_helper.dart';
import 'snapshot.dart';

class SnapshotStore extends ChangeNotifier {
  static final SnapshotStore instance = SnapshotStore._internal();

  final bool _isTest;
  final String? _baseDirOverride;

  SnapshotStore._internal()
      : _isTest = false,
        _baseDirOverride = null {
    _loadFromDisk();
  }

  // Visible for testing. When [baseDirOverride] is provided, real file I/O
  // is exercised against that directory (e.g. a temp dir) instead of the
  // app's real storage location, so save/load/delete correctness is still
  // covered. Without it, disk I/O is skipped entirely and the store starts
  // empty (or seeded via [initial]).
  SnapshotStore.test({String? baseDirOverride, List<SnapshotMeta>? initial})
      : _isTest = baseDirOverride == null,
        _baseDirOverride = baseDirOverride {
    if (initial != null) _index.addAll(initial);
    if (baseDirOverride != null) _loadFromDisk();
  }

  static const int maxAutoSnapshots = 25;

  final List<SnapshotMeta> _index = [];

  /// Manually-saved snapshots only, newest first. Kept forever until the
  /// user deletes them.
  List<SnapshotMeta> get snapshots =>
      List.unmodifiable(_index.where((m) => !m.isAuto));

  /// Auto-captured snapshots only, newest first. Capped at
  /// [maxAutoSnapshots] distinct entries — each running flow keeps a single
  /// rolling entry that's overwritten in place every capture, so the cap
  /// only evicts once that many different flows have auto-saved.
  List<SnapshotMeta> get autoSnapshots =>
      List.unmodifiable(_index.where((m) => m.isAuto));

  String _resolvePath(String fileName) {
    if (_baseDirOverride != null) {
      return p.join(_baseDirOverride, fileName);
    }
    try {
      return StorageHelper.getFilePath(fileName);
    } catch (_) {
      return fileName;
    }
  }

  String _indexPath() => _resolvePath('snapshots/index.json');
  String _snapshotPath(String id) => _resolvePath('snapshots/$id.json');

  void _loadFromDisk() {
    if (_isTest) return;
    try {
      final file = File(_indexPath());
      if (file.existsSync()) {
        final content = file.readAsStringSync().trim();
        if (content.isNotEmpty) {
          final List<dynamic> data = jsonDecode(content);
          _index.clear();
          for (final item in data) {
            if (item is Map<String, dynamic>) {
              _index.add(SnapshotMeta.fromJson(item));
            } else if (item is Map) {
              _index.add(SnapshotMeta.fromJson(Map<String, dynamic>.from(item)));
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to load snapshot index from disk: $e');
    }
  }

  Future<void> _saveIndex() async {
    if (_isTest) return;
    try {
      final file = File(_indexPath());
      final dir = file.parent;
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      await file.writeAsString(
        jsonEncode(_index.map((m) => m.toJson()).toList()),
        flush: true,
      );
    } catch (e) {
      debugPrint('Failed to save snapshot index to disk: $e');
    }
  }

  Future<void> save(Snapshot snapshot) async {
    if (!await _writeSnapshotFile(snapshot)) return;
    _upsertIndexEntry(SnapshotMeta.fromSnapshot(snapshot));
    notifyListeners();
    await _saveIndex();
  }

  /// Saves or refreshes a flow's rolling auto-snapshot. [snapshot.id] should
  /// stay stable across calls for the same flow (e.g. `'auto_<flowId>'`) so
  /// each capture overwrites the same entry in place instead of appending a
  /// new one. Once [maxAutoSnapshots] distinct auto-saved ids exist, the
  /// oldest auto-saved entries are evicted (manual saves are never touched).
  Future<void> saveAuto(Snapshot snapshot) async {
    assert(snapshot.isAuto);
    if (!await _writeSnapshotFile(snapshot)) return;
    _upsertIndexEntry(SnapshotMeta.fromSnapshot(snapshot));

    final autoIds = _index.where((m) => m.isAuto).toList();
    if (autoIds.length > maxAutoSnapshots) {
      final overflow = autoIds.sublist(maxAutoSnapshots);
      for (final meta in overflow) {
        _index.removeWhere((m) => m.id == meta.id);
        if (!_isTest) {
          try {
            final file = File(_snapshotPath(meta.id));
            if (file.existsSync()) file.deleteSync();
          } catch (e) {
            debugPrint('Failed to delete evicted auto-snapshot ${meta.id}: $e');
          }
        }
      }
    }

    notifyListeners();
    await _saveIndex();
  }

  /// Returns false (and skips the index update) if the write itself failed.
  Future<bool> _writeSnapshotFile(Snapshot snapshot) async {
    if (_isTest) return true;
    try {
      final file = File(_snapshotPath(snapshot.id));
      final dir = file.parent;
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      await file.writeAsString(jsonEncode(snapshot.toJson()), flush: true);
      return true;
    } catch (e) {
      debugPrint('Failed to save snapshot to disk: $e');
      return false;
    }
  }

  void _upsertIndexEntry(SnapshotMeta meta) {
    final existingIndex = _index.indexWhere((m) => m.id == meta.id);
    if (existingIndex >= 0) {
      _index[existingIndex] = meta;
    } else {
      _index.insert(0, meta);
    }
  }

  Future<Snapshot?> load(String id) async {
    if (_isTest) return null;
    try {
      final file = File(_snapshotPath(id));
      if (!file.existsSync()) return null;
      final content = await file.readAsString();
      if (content.trim().isEmpty) return null;
      final Map<String, dynamic> data = jsonDecode(content);
      return Snapshot.fromJson(data);
    } catch (e) {
      debugPrint('Failed to load snapshot $id from disk: $e');
      return null;
    }
  }

  Future<void> delete(String id) async {
    if (!_isTest) {
      try {
        final file = File(_snapshotPath(id));
        if (file.existsSync()) {
          await file.delete();
        }
      } catch (e) {
        debugPrint('Failed to delete snapshot $id from disk: $e');
      }
    }

    _index.removeWhere((m) => m.id == id);
    notifyListeners();
    await _saveIndex();
  }
}
