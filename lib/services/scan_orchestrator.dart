import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/car_listing.dart';
import '../models/search_config.dart';
import 'avtonet_scraper_service.dart';
import 'filter_matcher.dart';
import 'log_service.dart';
import 'notification_service.dart';
import 'storage_service.dart';

class ScanEngineResult {
  const ScanEngineResult({
    required this.ok,
    required this.successCount,
    required this.failCount,
    required this.newListings,
    required this.notificationsSent,
    required this.updatedConfigs,
    this.error = '',
  });

  final bool ok;
  final int successCount;
  final int failCount;
  final int newListings;
  final int notificationsSent;
  final List<SearchConfig> updatedConfigs;
  final String error;
}

class ScanEngine {
  ScanEngine({
    required StorageService storage,
    required LogService log,
    required AvtonetScraperService scraper,
    required NotificationService notifications,
  })  : _storage = storage,
        _log = log,
        _scraper = scraper,
        _notifications = notifications;

  final StorageService _storage;
  final LogService _log;
  final AvtonetScraperService _scraper;
  final NotificationService _notifications;

  bool _cancelRequested = false;

  void requestCancel() => _cancelRequested = true;

  Future<ScanEngineResult> scan({
    required List<SearchConfig> searches,
    required List<CarListing> currentListings,
    required void Function(int index, int total, String label, String status) onProgress,
    void Function(String)? logger, 
    bool isAuto = false,
    bool forceAll = false,
    String? singleId,
  }) async {
    _cancelRequested = false;
    debugPrint('[SCAN ORCHESTRATOR START] isAuto=$isAuto forceAll=$forceAll singleId=$singleId');
    
    // SCAN LOCK PROTECTION
    // Manual scan must ALWAYS execute. Skip lock logic if not auto.
    if (isAuto) {
      if (!await _storage.acquireScanLock()) {
        final prefs = await SharedPreferences.getInstance();
        final lockTime = prefs.getInt('scan_lock_time') ?? 0;
        debugPrint('[SCAN BLOCKED BY LOCK] owner=AUTO');
        return ScanEngineResult(
          ok: false,
          successCount: 0,
          failCount: 0,
          newListings: 0,
          notificationsSent: 0,
          updatedConfigs: searches,
          error: 'Scan already in progress',
        );
      }
    } else {
      // Manual scan: Ensure no lock prevents execution
      await _storage.releaseScanLock();
      debugPrint('[SCAN PROCEEDING] owner=MANUAL (Lock Bypassed)');
    }

    debugPrint('[SCAN START]');
    final method = isAuto ? 'AUTO' : 'MANUAL';
    
    var successCount = 0;
    var failCount = 0;
    var totalNewFound = 0;
    var notificationsSent = 0;
    
    if (isAuto) {
      debugPrint('[AUTO SCAN]');
    } else {
      debugPrint('[MANUAL SCAN]');
    }

    final updatedConfigs = List<SearchConfig>.from(searches);
    
    debugPrint('[DB LOADED]');
    final seenIds = await _storage.getSeenIds();
    debugPrint('[DB LISTINGS COUNT] ${currentListings.length}');
    debugPrint('[DB SEEN COUNT] ${seenIds.length}');

    final newMatchesForThisCycle = <CarListing>[];

    List<int> slotsToScan;
    if (singleId != null) {
      final idx = updatedConfigs.indexWhere((s) => s.id == singleId);
      slotsToScan = idx != -1 ? [idx] : [];
    } else if (forceAll) {
      slotsToScan = List.generate(updatedConfigs.length, (i) => i);
    } else {
      slotsToScan = updatedConfigs.asMap().entries
          .where((e) => e.value.isEnabled)
          .map((e) => e.key)
          .toList();
    }
    
    debugPrint('[DB FILTER COUNT] ${slotsToScan.length}');

    String globalError = '';
    bool criticalFailure = false;

    try {
      for (var i = 0; i < slotsToScan.length; i++) {
        if (_cancelRequested) break;

        final configIndex = slotsToScan[i];
        final config = updatedConfigs[configIndex];
        
        debugPrint('[FILTER SCAN START] index=${i + 1}/${slotsToScan.length} name=${config.name}');
        onProgress(i + 1, slotsToScan.length, config.name, 'Skeniranje...');

        try {
          debugPrint('[SCRAPER START] id=${config.id}');
          final result = await _scraper.scrapeSearchUrl(config, method: method, seenIds: seenIds);

          if (result.ok) {
            successCount++;
            
            final parsed = result.listings;
            final matched = <CarListing>[];

            for (final rawListing in parsed) {
              CarListing l = rawListing;
              
              final match = FilterMatcher.matches(l, config);
              debugPrint('[FILTER MATCHES] id=${l.id} filter=${config.name} match=${match.isMatch}');

              if (match.isMatch) {
                if (!seenIds.contains(l.id)) {
                  matched.add(l);
                  debugPrint('[NEW ID] ${l.id}');
                  
                  bool success = await _notifications.notifyNewAd(l);
                  if (success) {
                    notificationsSent++;
                    debugPrint('[NOTIFICATION SENT] id=${l.id}');
                  }
                } else {
                  debugPrint('[DUPLICATE ID] ${l.id}');
                }
              }
            }

            newMatchesForThisCycle.addAll(matched);
            totalNewFound += matched.length;
            
            updatedConfigs[configIndex] = updatedConfigs[configIndex].copyWith(
              lastChecked: DateTime.now(),
              lastStatus: matched.isNotEmpty ? 'Najdeno: ${matched.length} novih' : 'Brez novih',
              lastParsedCount: parsed.length,
              lastMatchedCount: matched.length,
            );
          } else {
            failCount++;
            updatedConfigs[configIndex] = updatedConfigs[configIndex].copyWith(
              lastChecked: DateTime.now(),
              lastStatus: 'Napaka: ${result.status.name}',
            );
            if (result.status == ScrapeStatus.cloudflareBlocked) {
               debugPrint('[BLOCK DETECTION] Cloudflare');
               await _notifications.notifyError('Zaznan Cloudflare block (403)');
               if (i == 0) criticalFailure = true; 
            } else if (result.status == ScrapeStatus.networkError) {
               debugPrint('[TIMEOUT/NETWORK ERROR]');
               await _notifications.notifyError('Napaka v omrežju ali Timeout');
            }
          }
        } catch (e) {
          failCount++;
          updatedConfigs[configIndex] = updatedConfigs[configIndex].copyWith(
            lastChecked: DateTime.now(),
            lastStatus: 'Sistemska napaka',
          );
          debugPrint('[CRITICAL SCAN FAILURE] $e');
          await _notifications.notifyError('Kritična napaka: $e');
        }
      }

      if (newMatchesForThisCycle.isNotEmpty) {
        debugPrint('[BACKGROUND DB START]');
        final List<CarListing> updatedListings = List.from(currentListings);
        final List<String> idsToSave = [];
        for (var newList in newMatchesForThisCycle) {
          if (!updatedListings.any((l) => l.id == newList.id)) {
            updatedListings.add(newList);
            idsToSave.add(newList.id);
            debugPrint('[SAVED ID] ${newList.id}');
          }
        }

        await _storage.saveListings(updatedListings);
        await _storage.addSeenIds(idsToSave);
        debugPrint('[BACKGROUND DB END]');
      }

      if (successCount > 0) {
        await _storage.setLastSuccessfulScan(DateTime.now());
      }
    } finally {
      await _storage.releaseScanLock();
      debugPrint('[SCAN LOCK RELEASED]');
    }

    debugPrint('[SCAN END]');
    debugPrint('[NOTIFICATIONS SENT] $notificationsSent');

    return ScanEngineResult(
      ok: !criticalFailure && failCount < slotsToScan.length,
      successCount: successCount,
      failCount: failCount,
      newListings: totalNewFound,
      notificationsSent: notificationsSent,
      updatedConfigs: updatedConfigs,
      error: globalError,
    );
  }
}
