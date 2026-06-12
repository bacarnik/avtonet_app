import 'package:shared_preferences/shared_preferences.dart';

import '../models/car_listing.dart';
import '../models/search_config.dart';
import '../models/history_filter.dart';
import '../models/scheduler_event.dart';

class StorageService {
  static const keySearches = 'saved_searches_v5';
  static const keyListings = 'saved_listings_v5';
  static const keySeenIds = 'seen_vehicle_ids_v1';
  static const keyLastSuccessfulScan = 'last_successful_scan_timestamp';
  static const keyPendingBackgroundScan = 'pending_background_scan';
  static const keyHistoryFilter = 'history_filter_v1';
  static const keyLastFailedScan = 'last_failed_scan_timestamp';
  static const keyLastScanError = 'last_scan_error_reason';
  static const keyLastScanNewCount = 'last_scan_new_ads_count';
  static const keySchedulerHistory = 'scheduler_history_v1';

  // Worker Diagnostics
  static const keyWorkerStartedAt = 'worker_started_at';
  static const keyWorkerFinishedAt = 'worker_finished_at';
  static const keyWorkerSucceeded = 'worker_succeeded';
  static const keyWorkerError = 'worker_error';
  static const keyWorkerTotalCount = 'worker_total_count_today';
  static const keyWorkerDetailLog = 'worker_detail_log_v1';
  static const keyWorkerFiltersScanned = 'worker_filters_scanned';
  static const keyWorkerAdsParsed = 'worker_ads_parsed';
  static const keyWorkerNewAdsFound = 'worker_new_ads_found';
  static const keyWorkerNotificationsSent = 'worker_notifications_sent';
  static const keyLastNotificationAt = 'last_notification_at';

  Future<List<SearchConfig>> loadSearches() async {
    final prefs = await SharedPreferences.getInstance();
    return SearchConfig.listFromJsonString(prefs.getString(keySearches) ?? '');
  }

  Future<void> saveSearches(List<SearchConfig> configs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keySearches, SearchConfig.listToJsonString(configs));
  }

  Future<List<CarListing>> loadListings() async {
    final prefs = await SharedPreferences.getInstance();
    return CarListing.listFromJsonString(prefs.getString(keyListings) ?? '');
  }

  Future<void> saveListings(List<CarListing> listings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyListings, CarListing.listToJsonString(listings));
  }

  Future<HistoryFilter> loadHistoryFilter() async {
    final prefs = await SharedPreferences.getInstance();
    return HistoryFilter.fromJsonString(prefs.getString(keyHistoryFilter) ?? '');
  }

  Future<void> saveHistoryFilter(HistoryFilter filter) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyHistoryFilter, HistoryFilter.toJsonString(filter));
  }

  Future<DateTime?> getLastFailedScan() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(keyLastFailedScan);
    return ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
  }

  Future<void> setLastFailedScan(DateTime time, String reason) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(keyLastFailedScan, time.millisecondsSinceEpoch);
    await prefs.setString(keyLastScanError, reason);
  }

  Future<String?> getLastScanError() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(keyLastScanError);
  }

  Future<int> getLastScanNewCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(keyLastScanNewCount) ?? 0;
  }

  Future<void> setLastScanNewCount(int count) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(keyLastScanNewCount, count);
  }

  Future<bool> acquireScanLock() async {
    final prefs = await SharedPreferences.getInstance();
    final isLocked = prefs.getBool('scan_lock_active') ?? false;
    if (isLocked) {
      final lockTime = prefs.getInt('scan_lock_time') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      // Stale lock protection: 10 minutes
      if (now - lockTime < 10 * 60 * 1000) {
        return false;
      }
    }
    await prefs.setBool('scan_lock_active', true);
    await prefs.setInt('scan_lock_time', DateTime.now().millisecondsSinceEpoch);
    return true;
  }

  Future<void> releaseScanLock() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('scan_lock_active', false);
    await prefs.remove('scan_lock_time');
  }

  Future<List<SchedulerEvent>> loadSchedulerHistory() async {
    final prefs = await SharedPreferences.getInstance();
    return SchedulerEvent.listFromJsonString(prefs.getString(keySchedulerHistory) ?? '');
  }

  Future<void> saveSchedulerHistory(List<SchedulerEvent> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keySchedulerHistory, SchedulerEvent.listToJsonString(list));
  }

  /// Delta Filtering: Persistent cache of seen vehicle IDs
  Future<List<String>> getSeenIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(keySeenIds) ?? [];
  }

  Future<void> addSeenIds(List<String> ids) async {
    if (ids.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(keySeenIds) ?? [];
    final updated = {...current, ...ids}.toList();
    // Cap at 2000 IDs to prevent storage bloat
    if (updated.length > 2000) {
      updated.removeRange(0, updated.length - 2000);
    }
    await prefs.setStringList(keySeenIds, updated);
  }

  Future<void> clearSeenIds() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keySeenIds);
  }

  Future<DateTime?> getLastSuccessfulScan() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(keyLastSuccessfulScan);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> setLastSuccessfulScan(DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(keyLastSuccessfulScan, time.millisecondsSinceEpoch);
  }

  Future<bool> consumePendingBackgroundScan() async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getBool(keyPendingBackgroundScan) ?? false;
    if (pending) {
      await prefs.setBool(keyPendingBackgroundScan, false);
    }
    return pending;
  }

  Future<void> recordWorkerStart(DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    
    // Get previous start to check for day change
    final previousStartMs = prefs.getInt(keyWorkerStartedAt);
    
    await prefs.setInt(keyWorkerStartedAt, time.millisecondsSinceEpoch);
    
    // Increment daily count
    if (previousStartMs != null) {
      final lastDate = DateTime.fromMillisecondsSinceEpoch(previousStartMs);
      if (lastDate.day != time.day || lastDate.month != time.month || lastDate.year != time.year) {
        await prefs.setInt(keyWorkerTotalCount, 1);
      } else {
        final currentCount = prefs.getInt(keyWorkerTotalCount) ?? 0;
        await prefs.setInt(keyWorkerTotalCount, currentCount + 1);
      }
    } else {
      await prefs.setInt(keyWorkerTotalCount, 1);
    }
  }

  Future<void> recordWorkerFinish(
    DateTime time, 
    bool success, {
    String? error,
    int? filtersScanned,
    int? adsParsed,
    int? newAdsFound,
    int? notificationsSent,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(keyWorkerFinishedAt, time.millisecondsSinceEpoch);
    await prefs.setBool(keyWorkerSucceeded, success);
    if (error != null) {
      await prefs.setString(keyWorkerError, error);
    } else {
      await prefs.remove(keyWorkerError);
    }
    if (filtersScanned != null) await prefs.setInt(keyWorkerFiltersScanned, filtersScanned);
    if (adsParsed != null) await prefs.setInt(keyWorkerAdsParsed, adsParsed);
    if (newAdsFound != null) await prefs.setInt(keyWorkerNewAdsFound, newAdsFound);
    if (notificationsSent != null) await prefs.setInt(keyWorkerNotificationsSent, notificationsSent);
  }

  Future<void> setWorkerDetailLog(String log) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyWorkerDetailLog, log);
  }

  Future<String?> getWorkerDetailLog() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(keyWorkerDetailLog);
  }

  Future<void> recordNotificationSent(DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(keyLastNotificationAt, time.millisecondsSinceEpoch);
  }

  Future<Map<String, dynamic>> getWorkerDiagnostics() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'startedAt': prefs.getInt(keyWorkerStartedAt),
      'finishedAt': prefs.getInt(keyWorkerFinishedAt),
      'succeeded': prefs.getBool(keyWorkerSucceeded),
      'error': prefs.getString(keyWorkerError),
      'totalToday': prefs.getInt(keyWorkerTotalCount) ?? 0,
      'detailLog': prefs.getString(keyWorkerDetailLog),
      'filtersScanned': prefs.getInt(keyWorkerFiltersScanned) ?? 0,
      'adsParsed': prefs.getInt(keyWorkerAdsParsed) ?? 0,
      'newAdsFound': prefs.getInt(keyWorkerNewAdsFound) ?? 0,
      'notificationsSent': prefs.getInt(keyWorkerNotificationsSent) ?? 0,
      'lastNotificationAt': prefs.getInt(keyLastNotificationAt),
    };
  }
}
