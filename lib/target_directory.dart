import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'storage_helper.dart';

class SavedTarget {
  final String id;
  final String name;
  final String target;
  final String note;
  final DateTime createdAt;

  SavedTarget({
    String? id,
    required this.name,
    required this.target,
    this.note = '',
    DateTime? createdAt,
  })  : id = id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        createdAt = createdAt ?? DateTime.now();

  SavedTarget copyWith({
    String? name,
    String? target,
    String? note,
  }) {
    return SavedTarget(
      id: id,
      name: name ?? this.name,
      target: target ?? this.target,
      note: note ?? this.note,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'target': target,
        'note': note,
        'createdAt': createdAt.toIso8601String(),
      };

  factory SavedTarget.fromJson(Map<String, dynamic> json) {
    return SavedTarget(
      id: json['id'] as String?,
      name: json['name'] as String? ?? '',
      target: json['target'] as String? ?? '',
      note: json['note'] as String? ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

class TargetDirectory extends ChangeNotifier {
  static final TargetDirectory instance = TargetDirectory._internal();

  final bool _isTest;

  TargetDirectory._internal() : _isTest = false {
    _loadFromDisk();
  }

  // Visible for testing in-memory without disk I/O side effects
  TargetDirectory.test({List<String>? initialRecent, List<SavedTarget>? initialSaved})
      : _isTest = true {
    if (initialRecent != null) _recentIps.addAll(initialRecent);
    if (initialSaved != null) _savedTargets.addAll(initialSaved);
  }

  final List<String> _recentIps = [];
  final List<SavedTarget> _savedTargets = [];

  List<String> get recentIps => List.unmodifiable(_recentIps);
  List<SavedTarget> get savedTargets => List.unmodifiable(_savedTargets);

  static const int maxRecentCount = 5;

  static String _resolveStoragePath() {
    try {
      return StorageHelper.getFilePath('targets.json');
    } catch (_) {
      return 'targets.json';
    }
  }

  void _loadFromDisk() {
    if (_isTest) return;
    try {
      final file = File(_resolveStoragePath());
      if (file.existsSync()) {
        final content = file.readAsStringSync().trim();
        if (content.isNotEmpty) {
          final Map<String, dynamic> data = jsonDecode(content);

          if (data['recentIps'] is List) {
            _recentIps.clear();
            for (final item in data['recentIps']) {
              if (item is String && item.trim().isNotEmpty) {
                _recentIps.add(item.trim());
              }
            }
          }

          if (data['savedTargets'] is List) {
            _savedTargets.clear();
            for (final item in data['savedTargets']) {
              if (item is Map<String, dynamic>) {
                _savedTargets.add(SavedTarget.fromJson(item));
              }
            }
          }
          return;
        }
      }
      _seedDefaults();
    } catch (e) {
      debugPrint('Failed to load targets from disk: $e');
      _seedDefaults();
      saveToDisk();
    }
  }

  void _seedDefaults() {
    _recentIps.clear();
    _recentIps.addAll(['1.1.1.1', '8.8.8.8', '1.0.0.1']);

    _savedTargets.clear();
    _savedTargets.addAll([
      SavedTarget(
        id: '1',
        name: 'Cloudflare DNS',
        target: '1.1.1.1',
        note: 'Fast, privacy-first public DNS resolver',
      ),
      SavedTarget(
        id: '2',
        name: 'Google Public DNS',
        target: '8.8.8.8',
        note: 'Primary Google DNS server',
      ),
      SavedTarget(
        id: '3',
        name: 'Quad9 DNS',
        target: '9.9.9.9',
        note: 'Security & malware-blocking public DNS',
      ),
    ]);
  }

  void saveToDisk() {
    if (_isTest) return;
    try {
      final file = File(_resolveStoragePath());
      final dir = file.parent;
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }

      final data = {
        'recentIps': _recentIps,
        'savedTargets': _savedTargets.map((t) => t.toJson()).toList(),
      };

      file.writeAsStringSync(jsonEncode(data), flush: true);
    } catch (e) {
      debugPrint('Failed to save targets to disk: $e');
    }
  }

  void addRecent(String rawTarget) {
    final target = rawTarget.trim();
    if (target.isEmpty) return;

    _recentIps.removeWhere((item) => item.toLowerCase() == target.toLowerCase());
    _recentIps.insert(0, target);

    while (_recentIps.length > maxRecentCount) {
      _recentIps.removeLast();
    }

    notifyListeners();
    saveToDisk();
  }

  void clearRecent() {
    _recentIps.clear();
    notifyListeners();
    saveToDisk();
  }

  bool isSaved(String rawTarget) {
    final target = rawTarget.trim().toLowerCase();
    if (target.isEmpty) return false;
    return _savedTargets.any((t) => t.target.trim().toLowerCase() == target);
  }

  SavedTarget? getSavedTarget(String rawTarget) {
    final target = rawTarget.trim().toLowerCase();
    if (target.isEmpty) return null;
    try {
      return _savedTargets.firstWhere((t) => t.target.trim().toLowerCase() == target);
    } catch (_) {
      return null;
    }
  }

  void saveTarget(String target, {String? name, String? note}) {
    final trimmedTarget = target.trim();
    if (trimmedTarget.isEmpty) return;

    final existingIndex = _savedTargets.indexWhere(
        (t) => t.target.trim().toLowerCase() == trimmedTarget.toLowerCase());

    final fallbackName = name?.trim().isNotEmpty == true
        ? name!.trim()
        : trimmedTarget;

    if (existingIndex >= 0) {
      _savedTargets[existingIndex] = _savedTargets[existingIndex].copyWith(
        name: fallbackName,
        note: note?.trim(),
      );
    } else {
      _savedTargets.insert(
        0,
        SavedTarget(
          name: fallbackName,
          target: trimmedTarget,
          note: note?.trim() ?? '',
        ),
      );
    }

    notifyListeners();
    saveToDisk();
  }

  void updateTarget(SavedTarget target) {
    final index = _savedTargets.indexWhere((t) => t.id == target.id);
    if (index >= 0) {
      _savedTargets[index] = target;
      notifyListeners();
      saveToDisk();
    }
  }

  void deleteTarget(String id) {
    _savedTargets.removeWhere((t) => t.id == id);
    notifyListeners();
    saveToDisk();
  }

  void toggleFavorite(String target, {String? defaultName}) {
    final trimmed = target.trim();
    if (trimmed.isEmpty) return;

    if (isSaved(trimmed)) {
      _savedTargets.removeWhere(
          (t) => t.target.trim().toLowerCase() == trimmed.toLowerCase());
    } else {
      saveTarget(trimmed, name: defaultName);
    }

    notifyListeners();
    saveToDisk();
  }
}
