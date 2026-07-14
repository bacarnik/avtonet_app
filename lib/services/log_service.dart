import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/log_entry.dart';

class LogService extends ChangeNotifier {
  static const _storageKey = 'error_log_v2';
  static const maxEntries = 500;

  final List<LogEntry> _entries = [];

  List<LogEntry> get entries => List.unmodifiable(_entries);

  Future<void> loadPersisted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) return;
      final list = jsonDecode(raw) as List<dynamic>;
      _entries
        ..clear()
        ..addAll(
          list.map((e) {
            final m = e as Map<String, dynamic>;
            return LogEntry(
              message: m['message'] as String,
              timestamp: DateTime.parse(m['timestamp'] as String),
              level: LogLevel.values[m['level'] as int? ?? 0],
            );
          }),
        );
      notifyListeners();
    } catch (e) {
      debugPrint('Nalaganje dnevnika ni uspelo: $e');
    }
  }

  void info(String message) => add(message, LogLevel.info);
  void warning(String message) => add(message, LogLevel.warning);
  void error(String message) => add(message, LogLevel.error);

  void add(String message, LogLevel level, {bool quiet = false}) {
    _entries.insert(
      0,
      LogEntry(message: message, timestamp: DateTime.now(), level: level),
    );
    if (_entries.length > maxEntries) {
      _entries.removeRange(maxEntries, _entries.length);
    }
    if (!quiet) {
      debugPrint('[${level.name.toUpperCase()}] $message');
    }
    notifyListeners();
    _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = _entries
          .map(
            (e) => {
              'message': e.message,
              'timestamp': e.timestamp.toIso8601String(),
              'level': e.level.index,
            },
          )
          .toList();
      await prefs.setString(_storageKey, jsonEncode(data));
    } catch (e) {
      debugPrint('Shranjevanje dnevnika ni uspelo: $e');
    }
  }

  Future<void> clear() async {
    _entries.clear();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}
