import 'package:workmanager/workmanager.dart';
import 'package:flutter/foundation.dart';

import '../services/storage_service.dart';
import '../models/scheduler_event.dart';
import '../services/log_service.dart';
import '../services/notification_service.dart';
import '../services/avtonet_scraper_service.dart';
import '../services/scan_orchestrator.dart';

const String kPeriodicScanTask = 'avtonet_periodic_scan_v3';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    final String workerId = DateTime.now().millisecondsSinceEpoch.toString().substring(7);
    debugPrint('[WORKER ID] $workerId');
    debugPrint('[WORKER START] task=$taskName');
    
    final now = DateTime.now();
    final stopwatch = Stopwatch()..start();
    final StringBuffer detailLog = StringBuffer();
    
    void log(String msg) {
      final line = '[${DateTime.now().toString().split(' ').last.substring(0, 8)}] $msg';
      debugPrint('[WORKER ID $workerId] $line');
      detailLog.writeln(line);
    }

    final storage = StorageService();
    await storage.recordWorkerStart(now);

    // REMOVED: Redundant lock check here. ScanEngine.scan handles locking.
    // This was causing the worker to block itself.
    log('[WORKER EXECUTION START]');

    try {
      if (now.hour < 8 || now.hour >= 22) {
        log('Night pause active (22-08). Skipping scan.');
        await storage.releaseScanLock();
        debugPrint('[WORKER END] ID=$workerId (night pause)');
        return Future.value(true);
      }

      final searches = await storage.loadSearches();
      final activeFilters = searches.where((s) => s.isEnabled).toList();
      
      if (activeFilters.isEmpty) {
        log('No active filters. Skipping scan.');
        await storage.releaseScanLock();
        debugPrint('[WORKER END] ID=$workerId (no active filters)');
        return Future.value(true);
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
      
      final result = await engine.scan(
        searches: searches,
        currentListings: currentListings,
        onProgress: (idx, total, lbl, st) {
          log('Filter $idx/$total: $lbl - $st');
        },
        logger: log, 
        isAuto: true,
      );

      log('========== SCAN RESULT ==========');
      log('ok=${result.ok}');
      log('successCount=${result.successCount}');
      log('failCount=${result.failCount}');
      log('newListings=${result.newListings}');
      log('notificationsSent=${result.notificationsSent}');
      log('error=${result.error}');
      log('=================================');

      stopwatch.stop();
      log('[WORKER FINISHED] - Duration: ${stopwatch.elapsed.inSeconds}s');
      debugPrint('[WORKER END] ID=$workerId Status=${result.ok ? 'SUCCESS' : 'FAILURE'}');

      await storage.recordWorkerFinish(
        DateTime.now(), 
        result.ok,
        filtersScanned: activeFilters.length,
        newAdsFound: result.newListings,
        notificationsSent: result.notificationsSent,
      );
      
      await storage.releaseScanLock();
      return Future.value(result.ok);
    } catch (e) {
      log('WORKER ERROR: $e');
      await storage.recordWorkerFinish(DateTime.now(), false, error: e.toString());
      await storage.releaseScanLock();
      debugPrint('[WORKER END] ID=$workerId Status=ERROR');
      return Future.value(false); 
    }
  });
}

Future<void> registerBackgroundTasks() async {
  try {
    debugPrint('[WORK REGISTER ATTEMPT]');
    // Set isInDebugMode to false to avoid debug notifications as requested
    await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
    
    await Workmanager().cancelAll();
    debugPrint('[WORKER CANCELLED PREVIOUS]');

    await Workmanager().registerPeriodicTask(
      kPeriodicScanTask,
      kPeriodicScanTask,
      frequency: const Duration(minutes: 15),
      initialDelay: const Duration(seconds: 10),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      existingWorkPolicy: ExistingWorkPolicy.keep,
    );
    
    debugPrint('[WORK REGISTER SUCCESS]');
    debugPrint('[WORKER REGISTERED]');
  } catch (e) {
    debugPrint('[SCHEDULER ERROR] Registration failed: $e');
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
