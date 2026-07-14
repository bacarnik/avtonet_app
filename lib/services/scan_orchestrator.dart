import 'package:flutter/foundation.dart';
import '../models/car_listing.dart';
import '../models/search_config.dart';
import 'avtonet_scraper_service.dart';
import 'filter_matcher.dart';
import 'log_service.dart';
import 'notification_service.dart';
import 'storage_service.dart';
import '../utils/logger.dart';

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

    AppLogger.info('[SCAN]', 'Started (owner: $method)');
    
    if (!await _storage.acquireScanLock(method)) {
      AppLogger.warn('[SCAN]', 'Blocked by lock ($method)');
      AppLogger.info('[SCAN]', 'Failed (Lock active)');
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

      String globalError = '';
      bool criticalFailure = false;

      for (var i = 0; i < slotsToScan.length; i++) {
        if (_cancelRequested) {
          AppLogger.info('[SCAN]', 'Cancelled by user');
          break;
        }

        final configIndex = slotsToScan[i];
        final config = updatedConfigs[configIndex];
        
        onProgress(i + 1, slotsToScan.length, config.name, 'Skeniranje...');
        AppLogger.info('[SCRAPER]', config.name);

        try {
          final result = await _scraper.scrapeSearchUrl(config, method: method, seenIds: seenIds.toList());

          if (result.ok) {
            successCount++;
            final parsed = result.listings;
            final matched = <CarListing>[];

            for (final rawListing in parsed) {
              final match = FilterMatcher.matches(rawListing, config);
              if (match.isMatch) {
                if (!seenIds.contains(rawListing.id)) {
                  matched.add(rawListing);
                  if (await _notifications.notifyNewAd(rawListing)) {
                    notificationsSent++;
                  }
                }
              }
            }

            totalNewFound += matched.length;
            AppLogger.info('[SCRAPER]', '${matched.length} new ads');
            
            updatedConfigs[configIndex] = updatedConfigs[configIndex].copyWith(
              lastChecked: DateTime.now(),
              lastStatus: matched.isNotEmpty ? 'Najdeno: ${matched.length} novih' : 'Brez novih',
              lastParsedCount: parsed.length,
              lastMatchedCount: matched.length,
            );

            await _storage.setLastSuccessfulScan(DateTime.now());

            if (matched.isNotEmpty) {
              final currentInStorage = await _storage.loadListings();
              final toAdd = <CarListing>[];
              final idsToAdd = <String>[];

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
            AppLogger.warn('[SCRAPER]', '${config.name} failed: ${result.status.name}');
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
          await _storage.saveSearches(updatedConfigs);
        } catch (e, stack) {
          AppLogger.error('[SCRAPER]', 'Loop exception for ${config.name}', e, stack);
          failCount++;
          updatedConfigs[configIndex] = updatedConfigs[configIndex].copyWith(
            lastChecked: DateTime.now(),
            lastStatus: 'Sistemska napaka',
          );
        }
      }

      stopwatch.stop();
      AppLogger.info('[NOTIFICATION]', '$notificationsSent notifications shown');
      AppLogger.info('[SCAN]', 'Finished in ${stopwatch.elapsed.inSeconds}s. Total new ads: $totalNewFound');

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
      AppLogger.error('[SCAN]', 'Critical error during scan', e, stack);
      AppLogger.info('[SCAN]', 'Failed (Exception)');
      rethrow;
    } finally {
      await _storage.releaseScanLock();
    }
  }
}
