import 'dart:convert';

class SchedulerEvent {
  const SchedulerEvent({
    required this.timestamp,
    required this.status,
    this.message = '',
    this.durationMs,
    this.exitReason,
  });

  final DateTime timestamp;
  final String status; 
  final String message;
  final int? durationMs;
  final String? exitReason;

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'status': status,
    'message': message,
    'durationMs': durationMs,
    'exitReason': exitReason,
  };

  factory SchedulerEvent.fromJson(Map<String, dynamic> json) {
    return SchedulerEvent(
      timestamp: DateTime.parse(json['timestamp'] as String),
      status: json['status'] as String,
      message: json['message'] as String? ?? '',
      durationMs: json['durationMs'] as int?,
      exitReason: json['exitReason'] as String?,
    );
  }

  static List<SchedulerEvent> listFromJsonString(String raw) {
    if (raw.isEmpty) return [];
    try {
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.map((e) => SchedulerEvent.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  static String listToJsonString(List<SchedulerEvent> list) {
    return jsonEncode(list.map((e) => e.toJson()).toList());
  }
}
