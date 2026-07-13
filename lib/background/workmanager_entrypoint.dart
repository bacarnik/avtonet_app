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
    debugPrint('[TRACE 1] callbackDispatcher starting task: $taskName');
    
    final storage = StorageService();
    final now = DateTime.now();
    final stopwatch = Stopwatch()..start();
    await storage.recordWorkerStart(now);

    String exitReason = 'UNKNOWN';
    int activeCount = 0;
    int successCount = 0;
    int failedCount = 0;

    try {
      // 1. NIGHT PAUSE (22:00 - 08:00)
      if (now.hour < 8 || now.hour >= 22) {
        debugPrint('[TRACE 2] callbackDispatcher: Night pause active');
        exitReason = 'NIGHT_PAUSE';
        await storage.recordWorkerFinish(now, true, resultStatus: exitReason);
        return true;
      }

      final searches = await storage.loadSearches();
      final activeFilters = searches.where((s) => s.isEnabled).toList();
      activeCount = activeFilters.length;
      debugPrint('[TRACE 3] callbackDispatcher: activeFilters count=$activeCount');
      
      // 2. NO FILTERS
      if (activeFilters.isEmpty) {
        debugPrint('[TRACE 4] callbackDispatcher: No active filters');
        exitReason = 'NO_FILTERS';
        await storage.recordWorkerFinish(now, true, resultStatus: 'NO_FILTERS');
        return true;
      }

      final logService = LogService();
      final notificationService = NotificationService.instance;
      await notificationService.initialize();
      
      final scraper = AvtonetScraperService(logService);
      final engine = ScanEngine(
        storage: storage,
        log: logService,
        scraper: scraper,
        notifications: notificationService,
      );

      final currentListings = await storage.loadListings();
      
      debugPrint('[TRACE 5] callbackDispatcher: calling engine.scan');
      final result = await engine.scan(
        searches: searches,
        currentListings: currentListings,
        onProgress: (idx, total, lbl, st) {},
        isAuto: true,
        ownerOverride: 'WORKER',
      );
      debugPrint('[TRACE 12] callbackDispatcher: engine.scan returned. result.ok=${result.ok} result.error="${result.error}" successCount=${result.successCount} failCount=${result.failCount}');

      successCount = result.successCount;
      failedCount = result.failCount;

      // 3. EVALUATE RESULT
      exitReason = 'SUCCESS';
      if (!result.ok) {
        final err = result.error.toLowerCase();
        debugPrint('[TRACE 13] callbackDispatcher: result not ok. error context: "$err"');
        if (err.contains('ključavnica')) {
          debugPrint('[TRACE 14] callbackDispatcher: Lock active detected');
          exitReason = 'LOCK_ACTIVE';
        } else if (err.contains('cloudflare') || err.contains('403')) {
          debugPrint('[TRACE 15] callbackDispatcher: Cloudflare/403 detected. Calling setPendingBackgroundScan(true)');
          exitReason = 'CLOUDFLARE';
          await storage.setPendingBackgroundScan(true);
        } else if (err.contains('webview') && err.contains('timeout')) {
          debugPrint('[TRACE 16] callbackDispatcher: Webview timeout detected');
          exitReason = 'WEBVIEW_TIMEOUT';
        } else if (err.contains('timeout') || err.contains('network')) {
          debugPrint('[TRACE 17] callbackDispatcher: Network timeout detected');
          exitReason = 'HTTP_TIMEOUT';
        } else {
          debugPrint('[TRACE 18] callbackDispatcher: Generic error branch');
          exitReason = 'ERROR';
        }
      } else {
        debugPrint('[TRACE 19] callbackDispatcher: result ok branch');
      }

      await storage.recordWorkerFinish(
        DateTime.now(), 
        true, 
        filtersScanned: activeCount,
        newAdsFound: result.newListings,
        notificationsSent: result.notificationsSent,
        resultStatus: exitReason,
      );
      
      await storage.recordWorkerStats(
        durationMs: stopwatch.elapsedMilliseconds,
        activeFilters: activeCount,
        successFilters: successCount,
        failedFilters: failedCount,
        usedHttpClient: true,
        usedWebView: false,
      );

      debugPrint('[TRACE 20] callbackDispatcher task finished successfully with exitReason=$exitReason');
      return true;
    } catch (e) {
      debugPrint('[TRACE 21] callbackDispatcher caught exception: $e');
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
    final storage = StorageService();
    await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
    
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
    
    await storage.recordWorkerRegistration(DateTime.now());
    debugPrint('[WORKER REGISTERED]');
  } catch (e) {
    debugPrint('[WORKER FAILURE] Registration failed: $e');
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
