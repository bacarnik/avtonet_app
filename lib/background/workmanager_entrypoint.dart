import 'package:workmanager/workmanager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../services/storage_service.dart';
import '../services/log_service.dart';
import '../services/notification_service.dart';
import '../services/avtonet_scraper_service.dart';
import '../services/scan_orchestrator.dart';

const String kPeriodicScanTask = 'avtonet_periodic_scan_v3';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    final logService = LogService();
    final now = DateTime.now();
    debugPrint('[BACKGROUND] executeTask triggered: $taskName at $now');

    final storage = StorageService();
    final stopwatch = Stopwatch()..start();
    
    // Log start to storage
    await storage.recordWorkerStart(now);

    String exitReason = 'UNKNOWN';
    int activeCount = 0;
    int successCount = 0;
    int failedCount = 0;

    try {
      // 1. Time restriction check (Night Pause)
      if (now.hour < 8 || now.hour >= 22) {
        debugPrint('[BACKGROUND] Night pause active (8-22), exiting.');
        exitReason = 'NIGHT_PAUSE';
        await storage.recordWorkerFinish(now, true, resultStatus: exitReason);
        return true;
      }

      // 2. Load searches
      final searches = await storage.loadSearches();
      final activeFilters = searches.where((s) => s.isEnabled).toList();
      activeCount = activeFilters.length;
      
      if (activeFilters.isEmpty) {
        debugPrint('[BACKGROUND] No active filters, exiting.');
        exitReason = 'NO_FILTERS';
        await storage.recordWorkerFinish(now, true, resultStatus: 'NO_FILTERS');
        return true;
      }

      debugPrint('[BACKGROUND] Starting scan engine for $activeCount filters');

      // 3. Initialize Services
      final notificationService = NotificationService.instance;
      await notificationService.initialize();
      
      final scraper = AvtonetScraperService(logService);
      ScanEngineResult? result;
      try {
        final engine = ScanEngine(
          storage: storage,
          log: logService,
          scraper: scraper,
          notifications: notificationService,
        );

        final currentListings = await storage.loadListings();
        
        // 4. Run Scan
        result = await engine.scan(
          searches: searches,
          currentListings: currentListings,
          onProgress: (idx, total, lbl, st) {},
          isAuto: true,
          ownerOverride: 'WORKER',
        );

        successCount = result.successCount;
        failedCount = result.failCount;
        debugPrint('[BACKGROUND] Scan finished. Success: $successCount, Failed: $failedCount, New: ${result.newListings}');

        exitReason = 'SUCCESS';
        if (!result.ok) {
          final err = result.error.toLowerCase();
          if (err.contains('ključavnica')) {
            exitReason = 'LOCK_ACTIVE';
          } else if (err.contains('cloudflare') || err.contains('403')) {
            exitReason = 'CLOUDFLARE';
            await storage.setPendingBackgroundScan(true);
          } else if (err.contains('webview') && err.contains('timeout')) {
            exitReason = 'WEBVIEW_TIMEOUT';
          } else if (err.contains('timeout') || err.contains('network')) {
            exitReason = 'HTTP_TIMEOUT';
          } else {
            exitReason = 'ERROR';
          }
        }
      } finally {
        await scraper.dispose(); // CRITICAL: Prevent memory leaks and detached JNI errors
      }

      // 5. Record Result
      await storage.recordWorkerFinish(
        DateTime.now(), 
        true, 
        filtersScanned: activeCount,
        newAdsFound: result?.newListings ?? 0,
        notificationsSent: result?.notificationsSent ?? 0,
        resultStatus: exitReason,
      );
      
      await storage.recordWorkerStats(
        durationMs: stopwatch.elapsedMilliseconds,
        activeFilters: activeCount,
        successFilters: successCount,
        failedFilters: failedCount,
        usedHttpClient: true,
        usedWebView: true,
      );

      debugPrint('[BACKGROUND] Worker task completed successfully: $exitReason');
      return true;
    } catch (e, stack) {
      debugPrint('[BACKGROUND] [ERROR] Worker exception: $e');
      if (stack != null) debugPrint(stack.toString());
      await storage.recordWorkerFinish(
        DateTime.now(), 
        false, 
        error: e.toString(), 
        resultStatus: 'EXCEPTION'
      );
      return false;
    }
  });
}

Future<void> registerBackgroundTasks() async {
  try {
    debugPrint('[BACKGROUND] registerBackgroundTasks called');
    final storage = StorageService();
    
    // Initialize Workmanager
    await Workmanager().initialize(
      callbackDispatcher, 
      isInDebugMode: false
    );
    debugPrint('[BACKGROUND] Workmanager initialized');

    // Use KEEP to avoid resetting the periodic timer on every app start
    await Workmanager().registerPeriodicTask(
      kPeriodicScanTask,
      kPeriodicScanTask,
      frequency: const Duration(minutes: 15),
      initialDelay: const Duration(seconds: 10),
      existingWorkPolicy: ExistingWorkPolicy.keep,
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );
    
    debugPrint('[BACKGROUND] Periodic task registered: $kPeriodicScanTask (Policy: REPLACE)');
    await storage.recordWorkerRegistration(DateTime.now());
  } catch (e, stack) {
    debugPrint('[BACKGROUND] [ERROR] Workmanager registration failed: $e');
    if (stack != null) debugPrint(stack.toString());
  }
}

Future<void> runTestBackgroundTask() async {
  await Workmanager().registerOneOffTask(
    'test_background_scan_${DateTime.now().millisecondsSinceEpoch}',
    kPeriodicScanTask,
    initialDelay: const Duration(seconds: 1),
    constraints: Constraints(
      networkType: NetworkType.connected,
    ),
  );
}
