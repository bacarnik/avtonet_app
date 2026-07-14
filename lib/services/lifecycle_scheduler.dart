import 'dart:async';
import '../utils/logger.dart';

typedef ScanTrigger = Future<void> Function();

/// Handles periodic foreground scanning and lifecycle transitions.
class LifecycleScheduler {
  Timer? _timer;
  ScanTrigger? _onTick;
  bool _isRunning = false;

  void bind(ScanTrigger onTick) {
    _onTick = onTick;
  }

  void start() {
    if (_isRunning) return;
    _isRunning = true;
    AppLogger.info('[SCHEDULER]', 'Started');
    
    // Check every minute if we need to scan
    _timer = Timer.periodic(const Duration(minutes: 1), (timer) {
      AppLogger.info('[SCHEDULER]', 'Tick');
      if (_onTick != null) {
        _onTick!();
      }
    });
  }

  void stop() {
    _isRunning = false;
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    stop();
  }
}
