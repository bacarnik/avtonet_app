import 'package:workmanager/workmanager.dart';
import 'package:flutter/widgets.dart';

import '../services/storage_service.dart';
import '../services/log_service.dart';
import '../services/notification_service.dart';
import '../services/avtonet_scraper_service.dart';
import '../services/scan_orchestrator.dart';
import '../utils/logger.dart';

const String kPeriodicScanTask = 'avtonet_periodic_scan_v3';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    final logService = LogService();
    AppLogger.init(logService);
    
    final storage = StorageService();
    final now = DateTime.now();
    final stopwatch = Stopwatch()..start();
    await storage.recordWorkerStart(now);

    String exitReason = 'UNKNOWN';
    int activeCount = 0;
    int successCount = 0;
    int failedCount = 0;

    try {
      if (now.hour < 8 || now.hour >= 22) {
        exitReason = 'NIGHT_PAUSE';
        await storage.recordWorkerFinish(now, true, resultStatus: exitReason);
        return true;
      }

      final searches = await storage.loadSearches();
      final activeFilters = searches.where((s) => s.isEnabled).toList();
      activeCount = activeFilters.length;
      
      if (activeFilters.isEmpty) {
        exitReason = 'NO_FILTERS';
        await storage.recordWorkerFinish(now, true, resultStatus: 'NO_FILTERS');
        return true;
      }

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
      
      final result = await engine.scan(
        searches: searches,
        currentListings: currentListings,
        onProgress: (idx, total, lbl, st) {},
        isAuto: true,
        ownerOverride: 'WORKER',
      );

      successCount = result.successCount;
      failedCount = result.failCount;

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
        usedWebView: true,
      );

      return true;
    } catch (e, stack) {
      AppLogger.error('[BACKGROUND]', 'Worker exception', e, stack);
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
  } catch (e, stack) {
    AppLogger.error('[BACKGROUND]', 'Workmanager registration failed', e, stack);
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
