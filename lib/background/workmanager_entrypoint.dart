import 'package:workmanager/workmanager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

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
    debugPrint('[WORKER_FORENSIC] WORKER START: $taskName at $now');

    final storage = StorageService();
    final stopwatch = Stopwatch()..start();
    
    // Log start to storage
    await storage.recordWorkerStart(now);

    String exitReason = 'UNKNOWN';
    int activeCount = 0;
    int successCount = 0;
    int failedCount = 0;

    try {
      debugPrint('[WORKER] Milestone 1: Check Foreground');
      // 0. Check if App is in Foreground
      if (await storage.isAppForeground()) {
        debugPrint('[WORKER_FORENSIC] WORKER SKIPPED (App in foreground)');
        return true; 
      }

      debugPrint('[WORKER] Milestone 2: Night Pause Check');
      // 1. Time restriction check (Night Pause)
      if (now.hour < 8 || now.hour >= 22) {
        debugPrint('[BACKGROUND] Night pause active (8-22), exiting.');
        exitReason = 'NIGHT_PAUSE';
        await storage.recordWorkerFinish(now, true, resultStatus: exitReason);
        return true;
      }

      debugPrint('[WORKER] Milestone 3: Load Searches');
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

      debugPrint('[WORKER] Milestone 4: Init Services');
      // 3. Initialize Services
      final notificationService = NotificationService.instance;
      await notificationService.initialize();
      
      // IMPORTANT: Disable WebView in background isolate to avoid JNI/Context crashes
      final scraper = AvtonetScraperService(logService, useWebView: false);
      ScanEngineResult? result;
      try {
        final engine = ScanEngine(
          storage: storage,
          log: logService,
          scraper: scraper,
          notifications: notificationService,
        );

        final currentListings = await storage.loadListings();
        
        debugPrint('[WORKER] Milestone 5: Starting Engine Scan');
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

        // CRITICAL: Save updated configs back to storage (Single Source of Truth)
        if (result.ok || result.successCount > 0) {
          await storage.saveSearches(result.updatedConfigs);
        }

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
        debugPrint('[WORKER] Milestone 7: Disposing Scraper');
        // Preprečimo neskončno čakanje na WebView v ozadju
        await scraper.dispose().timeout(const Duration(seconds: 5), onTimeout: () {
          debugPrint('[WORKER] WARNING: Scraper dispose timed out after 5s');
        });
      }

      debugPrint('[WORKER] Milestone 8: Recording Result');
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

      debugPrint('[WORKER_FORENSIC] WORKER FINISH. RESULT = $exitReason');
      return true;
    } catch (e, stack) {
      debugPrint('[WORKER_FORENSIC] WORKER FINISH. RESULT = EXCEPTION: $e');
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
    debugPrint('[FORENSIC] registerBackgroundTasks START');
    final storage = StorageService();
    
    debugPrint('[FORENSIC] Calling Workmanager().initialize...');
    // Initialize Workmanager
    await Workmanager().initialize(
      callbackDispatcher, 
      isInDebugMode: false
    );
    debugPrint('[FORENSIC] Workmanager().initialize COMPLETED');

    debugPrint('[FORENSIC] registerPeriodicTask START');
    debugPrint('[FORENSIC] UniqueName: $kPeriodicScanTask');
    debugPrint('[FORENSIC] Frequency: 15m');
    debugPrint('[FORENSIC] InitialDelay: 10s');
    debugPrint('[FORENSIC] Policy: KEEP');

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
    
    debugPrint('[FORENSIC] registerPeriodicTask RETURNED SUCCESS');
    
    // Trigger native forensic check
    try {
      const MethodChannel forensicsChannel = MethodChannel('com.example.avtonet_app/forensics');
      await forensicsChannel.invokeMethod('runForensicCheck');
    } catch (e) {
      debugPrint('[FORENSIC] Could not trigger native diagnostic: $e');
    }

    await storage.recordWorkerRegistration(DateTime.now());
    debugPrint('[FORENSIC] Worker registration timestamp recorded in storage');
  } catch (e, stack) {
    debugPrint('[FORENSIC] [ERROR] registerBackgroundTasks failed!');
    debugPrint('[FORENSIC] Error: $e');
    if (stack != null) {
      debugPrint('[FORENSIC] Stacktrace: $stack');
    }
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
