enum LogLevel { info, warning, error }

class LogEntry {
  const LogEntry({
    required this.message,
    required this.timestamp,
    this.level = LogLevel.info,
  });

  final String message;
  final DateTime timestamp;
  final LogLevel level;

  String get formattedTime {
    final t = timestamp;
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    final s = t.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
