import 'package:workmanager/workmanager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'dart:ui';

import '../services/storage_service.dart';
import '../services/log_service.dart';
import '../services/notification_service.dart';
import '../services/avtonet_scraper_service.dart';
import '../services/scan_orchestrator.dart';

const String kPeriodicScanTask = 'avtonet_periodic_scan_v3';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      DartPluginRegistrant.ensureInitialized();
    } catch (_) {}
    
    WidgetsFlutterBinding.ensureInitialized();
    final logService = LogService();
    final now = DateTime.now();
    final storage = StorageService();
    final stopwatch = Stopwatch()..start();
    
    await storage.recordWorkerStart(now);
    await storage.addWorkerHistoryEvent(
      status: 'WORKER_STARTED',
      message: 'Task: $taskName, Time: ${now.toIso8601String()}',
    );

    final isForeground = await storage.isAppForeground();
    final isInWindow = now.hour >= 6 && now.hour < 22;

    await storage.addWorkerHistoryEvent(
      status: 'WORKER_STATE',
      message: 'Foreground: $isForeground, InWindow: $isInWindow',
    );

    String exitReason = 'UNKNOWN';
    int activeCount = 0;
    int successCount = 0;
    int failedCount = 0;

    try {
      if (isForeground) {
        exitReason = 'FOREGROUND_SKIP';
        await storage.addWorkerHistoryEvent(status: exitReason);
        await storage.recordWorkerFinish(now, false, resultStatus: exitReason);
        await storage.addWorkerHistoryEvent(status: 'WORKER_FINISHED', exitReason: exitReason);
        return true; 
      }

      if (!isInWindow) {
        exitReason = 'NIGHT_PAUSE';
        await storage.addWorkerHistoryEvent(status: exitReason, exitReason: exitReason);
        await storage.recordWorkerFinish(now, false, resultStatus: exitReason);
        await storage.addWorkerHistoryEvent(status: 'WORKER_FINISHED', exitReason: exitReason);
        return true;
      }

      final searches = await storage.loadSearches();
      final activeFilters = searches.where((s) => s.isEnabled).toList();
      activeCount = activeFilters.length;
      
      if (activeFilters.isEmpty) {
        exitReason = 'NO_FILTERS';
        await storage.addWorkerHistoryEvent(status: exitReason, exitReason: exitReason);
        await storage.recordWorkerFinish(now, false, resultStatus: 'NO_FILTERS');
        return true;
      }

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
        
        await storage.addWorkerHistoryEvent(status: 'SCAN_STARTED');
        debugPrint('[WORKER_TRACE] engine.scan() START');
        result = await engine.scan(
          searches: searches,
          currentListings: currentListings,
          onProgress: (idx, total, lbl, st) {},
          isAuto: true,
          ownerOverride: 'WORKER',
        );
        debugPrint('[WORKER_TRACE] engine.scan() RETURN (ok=${result.ok}, new=${result.newListings})');
        await storage.addWorkerHistoryEvent(status: 'SCAN_FINISHED');

        successCount = result.successCount;
        failedCount = result.failCount;

        if (result.ok || result.successCount > 0) {
          await storage.saveSearches(result.updatedConfigs);
        }

        exitReason = 'SCAN_SUCCESS';
        if (!result.ok) {
          final err = result.error.toLowerCase();
          if (err.contains('ključavnica')) {
            exitReason = 'LOCK_ACTIVE';
          } else if (err.contains('cloudflare') || err.contains('403')) {
            exitReason = 'CLOUDFLARE';
            await storage.setPendingBackgroundScan(true);
          } else {
            exitReason = 'SCAN_FAILURE';
          }
        }
      } finally {
        await scraper.dispose().timeout(const Duration(seconds: 5), onTimeout: () {});
      }

      debugPrint('[WORKER_TRACE] recordWorkerFinish() START');
      await storage.recordWorkerFinish(
        DateTime.now(), 
        exitReason == 'SCAN_SUCCESS',
        filtersScanned: activeCount,
        newAdsFound: result?.newListings ?? 0,
        notificationsSent: result?.notificationsSent ?? 0,
        resultStatus: exitReason,
      );
      debugPrint('[WORKER_TRACE] recordWorkerFinish() END');
      
      debugPrint('[WORKER_TRACE] recordWorkerStats() START');
      await storage.recordWorkerStats(
        durationMs: stopwatch.elapsedMilliseconds,
        activeFilters: activeCount,
        successFilters: successCount,
        failedFilters: failedCount,
        usedHttpClient: true,
        usedWebView: true,
      );
      debugPrint('[WORKER_TRACE] recordWorkerStats() END');

      debugPrint('[WORKER_TRACE] final addWorkerHistoryEvent() START');
      await storage.addWorkerHistoryEvent(
        status: exitReason, 
        durationMs: stopwatch.elapsedMilliseconds,
        exitReason: exitReason,
      );

      await storage.addWorkerHistoryEvent(status: 'WORKER_FINISHED', exitReason: exitReason);
      debugPrint('[WORKER_TRACE] final addWorkerHistoryEvent() END');

      debugPrint('[WORKER_TRACE] return true START');
      return true;
    } catch (e, stack) {
      if (stack != null) debugPrint(stack.toString());
      exitReason = 'EXCEPTION';
      await storage.recordWorkerFinish(
        DateTime.now(), 
        false, 
        error: e.toString(), 
        resultStatus: exitReason
      );
      await storage.addWorkerHistoryEvent(
        status: exitReason,
        message: e.toString(),
        durationMs: stopwatch.elapsedMilliseconds,
        exitReason: exitReason,
      );
      await storage.addWorkerHistoryEvent(status: 'WORKER_FINISHED', exitReason: exitReason);
      return false;
    }
  });
}

Future<void> registerBackgroundTasks() async {
  final storage = StorageService();

  try {
    await storage.addWorkerHistoryEvent(
      status: 'WM_INIT_START',
    );

    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false,
    );

    await storage.addWorkerHistoryEvent(
      status: 'WM_INIT_OK',
    );

    await storage.addWorkerHistoryEvent(
      status: 'WM_PERIODIC_REGISTER_START',
      message: kPeriodicScanTask,
    );

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

    await storage.addWorkerHistoryEvent(
      status: 'WM_PERIODIC_REGISTER_OK',
      message: kPeriodicScanTask,
    );

    try {
      const channel =
          MethodChannel('com.example.avtonet_app/forensics');

      await channel.invokeMethod('runForensicCheck');

      await storage.addWorkerHistoryEvent(
        status: 'WM_FORENSIC_REQUESTED',
      );
    } catch (e) {
      await storage.addWorkerHistoryEvent(
        status: 'WM_FORENSIC_ERROR',
        message: e.toString(),
      );
    }

    await storage.recordWorkerRegistration(DateTime.now());

    await storage.addWorkerHistoryEvent(
      status: 'WM_REGISTRATION_COMPLETE',
    );
  } catch (e, stack) {
    await storage.addWorkerHistoryEvent(
      status: 'WM_REGISTRATION_ERROR',
      message: '$e\n$stack',
    );

    debugPrint('[BACKGROUND] REGISTRATION ERROR: $e');
    debugPrint(stack.toString());
  }
}

Future<void> runTestBackgroundTask() async {
  final storage = StorageService();

  final id =
      'test_background_scan_${DateTime.now().millisecondsSinceEpoch}';

  try {
    await storage.addWorkerHistoryEvent(
      status: 'WM_TEST_REGISTER_START',
      message: id,
    );

    await Workmanager().registerOneOffTask(
      id,
      kPeriodicScanTask,
      initialDelay: const Duration(seconds: 1),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );

    await storage.addWorkerHistoryEvent(
      status: 'WM_TEST_REGISTER_OK',
      message: id,
    );
  } catch (e, stack) {
    await storage.addWorkerHistoryEvent(
      status: 'WM_TEST_REGISTER_ERROR',
      message: '$e\n$stack',
    );

    debugPrint('[BACKGROUND] TEST REGISTER ERROR: $e');
    debugPrint(stack.toString());
  }
}
