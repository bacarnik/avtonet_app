import 'package:flutter/foundation.dart';
import '../services/log_service.dart';
import '../models/log_entry.dart';

/// Centralized logger for the Avtonet app.
/// Filter Logcat with: adb logcat Flutter:I flutter:I *:S
class AppLogger {
  /// Global switch for info logging. 
  /// Usually true in debug, false in release.
  static const bool _kInfoEnabled = kDebugMode;

  static LogService? _logService;

  /// Initialize with LogService to persist logs to the UI.
  static void init(LogService service) {
    _logService = service;
  }

  /// [INFO] - Standard flow monitoring (Scan start, Scheduler, etc.)
  static void info(String tag, String message) {
    if (_kInfoEnabled) {
      debugPrint('$tag $message');
      _logService?.add('$tag $message', LogLevel.info, quiet: true);
    }
  }

  /// [WARN] - Unexpected but non-critical issues (Retries, Timeouts)
  static void warn(String tag, String message) {
    debugPrint('[WARN] $tag $message');
    _logService?.add('$tag $message', LogLevel.warning, quiet: true);
  }

  /// [ERROR] - Critical failures and exceptions
  static void error(String tag, String message, [dynamic error, StackTrace? stackTrace]) {
    String fullMessage = message;
    if (error != null) fullMessage += ' | $error';
    debugPrint('[ERROR] $tag $fullMessage');
    if (stackTrace != null) debugPrint(stackTrace.toString());
    _logService?.add('$tag $fullMessage', LogLevel.error, quiet: true);
  }
}
