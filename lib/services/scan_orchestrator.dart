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
    String? ownerOverride,
  }) async {
    _cancelRequested = false;
    
    final method = ownerOverride ?? (isAuto ? 'AUTO' : 'MANUAL');
    debugPrint('[TRACE 6] ScanEngine.scan starting for owner: $method');
    
    // SCAN LOCK PROTECTION
    if (!await _storage.acquireScanLock(method)) {
      debugPrint('[TRACE 7] ScanEngine.scan: Lock acquisition failed for owner: $method');
      return ScanEngineResult(
        ok: false,
        successCount: 0,
        failCount: 0,
        newListings: 0,
        notificationsSent: 0,
        updatedConfigs: searches,
        error: 'Skeniranje že poteka (aktivna ključavnica).',
      );
    }
    
    try {
      void log(String msg) {
        if (logger != null) logger(msg);
      }

      var successCount = 0;
      var failCount = 0;
      var totalNewFound = 0;
      var notificationsSent = 0;
      
      final updatedConfigs = List<SearchConfig>.from(searches);
      
      final List<String> seenIdsList = await _storage.getSeenIds();
      final Set<String> seenIds = Set<String>.from(seenIdsList);
      
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
      
      log('[FILTER COUNT] total=${slotsToScan.length}');
      debugPrint('[TRACE 8] ScanEngine.scan: slotsToScan count=${slotsToScan.length}');

      String globalError = '';
      bool criticalFailure = false;

      for (var i = 0; i < slotsToScan.length; i++) {
        if (_cancelRequested) {
          debugPrint('[TRACE 9] ScanEngine.scan: Cancellation requested');
          break;
        }

        final configIndex = slotsToScan[i];
        final config = updatedConfigs[configIndex];
        
        onProgress(i + 1, slotsToScan.length, config.name, 'Skeniranje...');

        try {
          debugPrint('[TRACE 10] ScanEngine.scan: calling scraper.scrapeSearchUrl for config: ${config.id}');
          final result = await _scraper.scrapeSearchUrl(config, method: method, seenIds: seenIds.toList());
          debugPrint('[TRACE 11] ScanEngine.scan: scraper returned. result.ok=${result.ok} result.status=${result.status} result.error="${result.error}" listings.length=${result.listings.length}');

          if (result.ok) {
            successCount++;
            
            final parsed = result.listings;
            final matched = <CarListing>[];

            for (final rawListing in parsed) {
              CarListing l = rawListing;
              
              final match = FilterMatcher.matches(l, config);

              if (match.isMatch) {
                final alreadySeenGlobal = seenIds.contains(l.id);

                if (!alreadySeenGlobal) {
                  matched.add(l);
                  
                  bool success = await _notifications.notifyNewAd(l);
                  if (success) {
                    notificationsSent++;
                  }
                }
              }
            }

            totalNewFound += matched.length;
            
            updatedConfigs[configIndex] = updatedConfigs[configIndex].copyWith(
              lastChecked: DateTime.now(),
              lastStatus: matched.isNotEmpty ? 'Najdeno: ${matched.length} novih' : 'Brez novih',
              lastParsedCount: parsed.length,
              lastMatchedCount: matched.length,
            );

            // Update successful scan timestamp as soon as at least one filter succeeds
            await _storage.setLastSuccessfulScan(DateTime.now());

            // INCREMENTAL SAVE: Save results after each successful filter
            if (matched.isNotEmpty) {
              final List<CarListing> currentInStorage = await _storage.loadListings();
              final List<CarListing> toAdd = [];
              final List<String> idsToAdd = [];

              for (var l in matched) {
                if (!currentInStorage.any((existing) => existing.id == l.id)) {
                  toAdd.add(l);
                }
                if (!seenIds.contains(l.id)) {
                  idsToAdd.add(l.id);
                }
              }

              if (toAdd.isNotEmpty) {
                await _storage.saveListings([...currentInStorage, ...toAdd]);
              }
              if (idsToAdd.isNotEmpty) {
                await _storage.addSeenIds(idsToAdd);
                seenIds.addAll(idsToAdd);
              }
            }
          } else {
            failCount++;
            updatedConfigs[configIndex] = updatedConfigs[configIndex].copyWith(
              lastChecked: DateTime.now(),
              lastStatus: 'Napaka: ${result.status.name}',
            );
            
            if (result.status == ScrapeStatus.cloudflareBlocked) {
               log('[BLOCK DETECTION] Cloudflare');
               globalError = 'Cloudflare Blocked';
               // ONLY notify user if this is a MANUAL or CATCHUP scan. 
               // Background (WORKER) scans will be handled via catch-up.
               if (method != 'WORKER') {
                 await _notifications.notifyError('Zaznan Cloudflare block (403)');
               }
               if (i == 0) criticalFailure = true; 
            } else if (result.status == ScrapeStatus.networkError) {
               log('[TIMEOUT/NETWORK ERROR]');
               await _notifications.notifyError('Napaka v omrežju ali Timeout');
            }
          }
          // Always save search config status after each filter
          await _storage.saveSearches(updatedConfigs);
        } catch (e) {
          debugPrint('[TRACE 10-E] ScanEngine.scan: Inner loop caught exception: $e');
          failCount++;
          updatedConfigs[configIndex] = updatedConfigs[configIndex].copyWith(
            lastChecked: DateTime.now(),
            lastStatus: 'Sistemska napaka',
          );
          await _notifications.notifyError('Kritična napaka: $e');
        }
      }

      final scanResult = ScanEngineResult(
        ok: !criticalFailure && failCount < slotsToScan.length,
        successCount: successCount,
        failCount: failCount,
        newListings: totalNewFound,
        notificationsSent: notificationsSent,
        updatedConfigs: updatedConfigs,
        error: globalError,
      );
      debugPrint('[TRACE 11-F] ScanEngine.scan: Preparing to return. result.ok=${scanResult.ok} result.error="${scanResult.error}" successCount=${scanResult.successCount} failCount=${scanResult.failCount}');
      return scanResult;
    } finally {
      await _storage.releaseScanLock();
      debugPrint('[SCAN LOCK RELEASED]');
    }
  }
}
