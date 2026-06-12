import 'dart:async';

typedef ScanTrigger = Future<void> Function();

/// REFACTORED: NO-OP. UI-driven automatic scans are disabled per requirements.
class LifecycleScheduler {
  void bind(ScanTrigger onTick) {}
  void start() {}
  void stop() {}
  void dispose() {}
}
