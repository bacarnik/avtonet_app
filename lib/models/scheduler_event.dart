import 'dart:convert';

class SchedulerEvent {
  const SchedulerEvent({
    required this.timestamp,
    required this.status,
    this.message = '',
  });

  final DateTime timestamp;
  final String status; // SUCCESS, FAIL
  final String message;

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'status': status,
    'message': message,
  };

  factory SchedulerEvent.fromJson(Map<String, dynamic> json) {
    return SchedulerEvent(
      timestamp: DateTime.parse(json['timestamp'] as String),
      status: json['status'] as String,
      message: json['message'] as String? ?? '',
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
