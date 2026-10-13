import 'package:flutter/foundation.dart';
import '../models/car_listing.dart';
import '../models/search_config.dart';
import '../models/scan_diagnostic.dart';
import '../utils/url_builder.dart';
import 'avtonet_scraper_service.dart';
import 'log_service.dart';
import 'notification_service.dart';
import 'storage_service.dart';
import 'dart:async';

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
    final stopwatch = Stopwatch()..start();
    
    // Create a unique owner ID for this specific scan session
    final String lockOwnerId = '$method:${DateTime.now().millisecondsSinceEpoch}';

    final session = ScanSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      startTime: DateTime.now(),
      method: method,
    );
    await _storage.addScanSession(session);

    debugPrint('[SCAN] Started (owner: $lockOwnerId)');
    
    if (!await _storage.acquireScanLock(lockOwnerId)) {
      final lockInfo = await _storage.getCurrentLockInfo();
      final currentOwner = lockInfo['owner'] ?? 'unknown';
      
      debugPrint('[SCAN_FILTER] BLOCKED_BY_LOCK currentOwner=$currentOwner');
      debugPrint('[SCAN] Failed (Lock active)');
      
      session.endTime = DateTime.now();
      session.isLockBlocked = true;
      session.lockOwner = currentOwner;
      session.exitReason = 'LOCKED';
      session.durationMs = stopwatch.elapsedMilliseconds;
      await _storage.updateScanSession(session);

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

    Timer? lockHeartbeatTimer;

    lockHeartbeatTimer = Timer.periodic(
      const Duration(seconds: 30),
          (_) {
        _storage.heartbeatScanLock(lockOwnerId);
      },
    );

    try {
      var successCount = 0;
      var failCount = 0;
      var totalNewFound = 0;
      var notificationsSent = 0;
      
      final updatedConfigs = List<SearchConfig>.from(searches);
      final List<String> seenIdsList = await _storage.getSeenIds();
      final Set<String> seenIds = Set<String>.from(seenIdsList);

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

      session.activeFiltersCount = slotsToScan.length;
      await _storage.updateScanSession(session);

      String globalError = '';
      bool criticalFailure = false;

      for (var i = 0; i < slotsToScan.length; i++) {
        if (_cancelRequested) {
          debugPrint('[SCAN] Cancelled by user');
          session.exitReason = 'CANCELLED';
          break;
        }

        final configIndex = slotsToScan[i];
        final config = updatedConfigs[configIndex];
        final filterStopwatch = Stopwatch()..start();
        
        final filterDiag = FilterDiagnostic(
          filterName: config.name,
          brand: config.znamka,
          model: config.model,
          url: buildAvtonetResultsUrl(config),
          urlParams: buildAvtonetUrlParams(config),
        );
        filterDiag.startTime = DateTime.now();
        session.filters.add(filterDiag);
        await _storage.updateScanSession(session);

        onProgress(i + 1, slotsToScan.length, config.name, 'Skeniranje...');
        debugPrint('[SCAN_FILTER] START filter=${config.name}');

        try {
          final result = await _scraper.scrapeSearchUrl(
            config, 
            method: method, 
            seenIds: seenIds.toList(),
            onPageLog: (p) {
              filterDiag.pages.add(p);
              _storage.updateScanSession(session);
            },
          );

          filterDiag.usedWebView = result.usedWebView;
          filterDiag.usedHttpClientFallback = result.usedHttpClient;
          filterDiag.httpStatus = result.httpStatus;
          filterDiag.pagesChecked = result.pages;

          if (result.ok) {
            successCount++;

            // scrapeSearchUrl() already returns only new ads found
            // under the exact Avto.net URL.
            //
            // The URL is the source of truth for all filters.
            // DO NOT use FilterMatcher here.
            final parsed = result.listings;
            final matched = <CarListing>[];

            debugPrint(
              '[SCAN_FILTER] URL_RESULTS filter=${config.name} '
              'newListingsFromUrl=${parsed.length}',
            );

            for (final rawListing in parsed) {
              // Additional protection against race/duplicate situations.
              // Scraper already filters against seenIds, but checking here
              // prevents duplicate notifications if state changes during scan.
              if (seenIds.contains(rawListing.id)) {
                debugPrint(
                  '[SCAN_FILTER] SKIP_ALREADY_SEEN '
                  'id=${rawListing.id} '
                  'title="${rawListing.title}"',
                );
                continue;
              }

              matched.add(rawListing);

              debugPrint(
                '[SCAN_FILTER] NEW_URL_RESULT '
                'id=${rawListing.id} '
                'title="${rawListing.title}"',
              );

              final notified = await _notifications.notifyNewAd(rawListing);
              if (notified) {
                notificationsSent++;
              }
            }

            totalNewFound += matched.length;

            filterDiag.status = 'SUCCESS';
            filterDiag.adsFound = result.totalFound;
            filterDiag.newAdsFound = matched.length;
            filterDiag.knownAdsFound = result.totalFound - matched.length;

            updatedConfigs[configIndex] = updatedConfigs[configIndex].copyWith(
              lastChecked: DateTime.now(),
              lastStatus: matched.isNotEmpty
                  ? 'Najdeno: ${matched.length} novih'
                  : 'Brez novih',
              lastParsedCount: result.totalFound,
              lastMatchedCount: matched.length,
            );

            await _storage.setLastSuccessfulScan(DateTime.now());

            if (matched.isNotEmpty) {
              final currentInStorage = await _storage.loadListings();
              final toAdd = <CarListing>[];
              final idsToAdd = <String>[];

              for (final listing in matched) {
                if (!currentInStorage.any((existing) => existing.id == listing.id)) {
                  toAdd.add(listing);
                }
                if (!seenIds.contains(listing.id)) {
                  idsToAdd.add(listing.id);
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
            debugPrint(
              '[SCAN_FILTER] COMPLETE '
              'filter=${config.name} '
              'duration=${filterStopwatch.elapsed.inSeconds}s '
              'new=${matched.length}',
            );
          } else {
            failCount++;
            filterDiag.status = 'FAILURE';
            filterDiag.reason = result.status.name;
            filterDiag.error = result.error;
            filterDiag.cloudflareDetected = result.status == ScrapeStatus.cloudflareBlocked;

            debugPrint('[SCAN_FILTER] FAILED filter=${config.name} duration=${filterStopwatch.elapsed.inSeconds}s error=${result.status.name}');
            updatedConfigs[configIndex] = updatedConfigs[configIndex].copyWith(
              lastChecked: DateTime.now(),
              lastStatus: 'Napaka: ${result.status.name}',
            );
            
            if (result.status == ScrapeStatus.cloudflareBlocked) {
               globalError = 'Cloudflare Blocked';
               if (method != 'WORKER') {
                 await _notifications.notifyError('Zaznan Cloudflare block (403)');
               }
               if (i == 0) criticalFailure = true; 
            } else if (result.status == ScrapeStatus.networkError) {
               await _notifications.notifyError('Napaka v omrežju ali Timeout');
            }
          }
        } catch (e, stack) {
          debugPrint('[SCAN_FILTER] FAILED filter=${config.name} duration=${filterStopwatch.elapsed.inSeconds}s error=EXCEPTION: $e');
          failCount++;
          filterDiag.status = 'FAILURE';
          filterDiag.reason = 'EXCEPTION';
          filterDiag.error = e.toString();
          filterDiag.stackTrace = stack.toString();

          updatedConfigs[configIndex] = updatedConfigs[configIndex].copyWith(
            lastChecked: DateTime.now(),
            lastStatus: 'Sistemska napaka',
          );
        } finally {
          filterDiag.endTime = DateTime.now();
          await _storage.updateScanSession(session);
        }
      }

      stopwatch.stop();
      debugPrint('[NOTIFICATION] $notificationsSent notifications shown');
      debugPrint('[SCAN] Finished in ${stopwatch.elapsed.inSeconds}s. Total new ads: $totalNewFound');

      session.endTime = DateTime.now();
      session.durationMs = stopwatch.elapsedMilliseconds;
      session.totalNewAds = totalNewFound;
      session.exitReason = criticalFailure ? 'CRITICAL_FAILURE' : (failCount > 0 ? 'PARTIAL_FAILURE' : 'SUCCESS');
      await _storage.updateScanSession(session);

      return ScanEngineResult(
        ok: !criticalFailure && failCount < slotsToScan.length,
        successCount: successCount,
        failCount: failCount,
        newListings: totalNewFound,
        notificationsSent: notificationsSent,
        updatedConfigs: updatedConfigs,
        error: globalError,
      );
    } catch (e, stack) {
      debugPrint('[SCAN] [ERROR] Critical error during scan: $e');
      session.endTime = DateTime.now();
      session.exitReason = 'EXCEPTION';
      session.durationMs = stopwatch.elapsedMilliseconds;
      await _storage.updateScanSession(session);
      if (stack != null) debugPrint(stack.toString());
      debugPrint('[SCAN] Failed (Exception)');
      rethrow;
    } finally {
      lockHeartbeatTimer?.cancel();
      await _storage.releaseScanLock(lockOwnerId);
    }
  }
}
