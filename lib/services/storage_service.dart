import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/car_listing.dart';
import '../models/search_config.dart';
import '../models/history_filter.dart';
import '../models/scheduler_event.dart';
import '../models/scan_diagnostic.dart';

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
  static const keyScanDiagnostics = 'scan_diagnostics_v1';

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
  static const keyLastWorkerRegistration = 'last_worker_registration_at';
  static const keyLastWorkerResult = 'last_worker_result_status';
  static const keyAppForeground = 'app_is_in_foreground_v1';
  static const keyForegroundHeartbeat = 'foreground_heartbeat_ts';

  // Extended Diagnostics
  static const keyWorkerLastSuccessAt = 'worker_last_success_at';
  static const keyWorkerLastFailureAt = 'worker_last_failure_at';
  static const keyWorkerDurationMs = 'worker_last_duration_ms';
  static const keyWorkerActiveFilters = 'worker_active_filters_count';
  static const keyWorkerSuccessFilters = 'worker_success_filters_count';
  static const keyWorkerFailedFilters = 'worker_failed_filters_count';
  static const keyWorkerUsedHttpClient = 'worker_used_http_client';
  static const keyWorkerUsedWebView = 'worker_used_webview';

  Future<List<SearchConfig>> loadSearches() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // Ensure fresh data across isolates
    return SearchConfig.listFromJsonString(prefs.getString(keySearches) ?? '');
  }

  Future<void> saveSearches(List<SearchConfig> configs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keySearches, SearchConfig.listToJsonString(configs));
  }

  Future<List<CarListing>> loadListings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // Ensure fresh data across isolates
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

  Future<Map<String, dynamic>> getCurrentLockInfo() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return {
      'active': prefs.getBool('scan_lock_active') ?? false,
      'owner': prefs.getString('scan_lock_owner') ?? 'unknown',
      'lockTime': prefs.getInt('scan_lock_time') ?? 0,
    };
  }

  Future<bool> acquireScanLock(String owner) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // Critical for Background Isolate to see released lock
    final isLocked = prefs.getBool('scan_lock_active') ?? false;
    final lockOwner = prefs.getString('scan_lock_owner') ?? 'unknown';
    final lockTime = prefs.getInt('scan_lock_time') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final ageSeconds = (now - lockTime) ~/ 1000;

    debugPrint('[SCAN_LOCK] CHECK requester=$owner active=$isLocked owner=$lockOwner age=${ageSeconds}s');

    if (isLocked) {
      // Stale lock: 20 minutes is enough for background scan
      if (now - lockTime < 20 * 60 * 1000) {
        debugPrint('[SCAN_LOCK] DENIED requester=$owner owner=$lockOwner age=${ageSeconds}s');
        return false;
      } else {
        debugPrint('[SCAN] [WARN] Stale lock detected, overriding (Current: $lockOwner, New: $owner)');
      }
    }
    
    await prefs.setBool('scan_lock_active', true);
    await prefs.setInt('scan_lock_time', now);
    await prefs.setString('scan_lock_owner', owner);
    debugPrint('[SCAN_LOCK] ACQUIRED owner=$owner');
    return true;
  }

  Future<void> releaseScanLock(String owner) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final currentOwner = prefs.getString('scan_lock_owner') ?? 'unknown';
    final isLocked = prefs.getBool('scan_lock_active') ?? false;

    if (!isLocked) {
      debugPrint('[SCAN_LOCK] RELEASE SKIPPED: Not locked');
      return;
    }

    if (currentOwner != owner) {
      debugPrint('[SCAN_LOCK] RELEASE DENIED: Owner mismatch (Current: $currentOwner, Requester: $owner)');
      await addWorkerHistoryEvent(
        status: 'LOCK_RELEASE_DENIED',
        message: 'Owner mismatch. Current: $currentOwner, Requester: $owner',
      );
      return;
    }

    debugPrint('[SCAN_LOCK] RELEASE START owner=$owner');

    await prefs.setBool('scan_lock_active', false);
    await prefs.remove('scan_lock_time');
    await prefs.remove('scan_lock_owner');

    debugPrint('[SCAN_LOCK] RELEASE COMPLETE owner=$owner');
  }

  Future<List<SchedulerEvent>> loadSchedulerHistory() async {
    final prefs = await SharedPreferences.getInstance();
    return SchedulerEvent.listFromJsonString(prefs.getString(keySchedulerHistory) ?? '');
  }

  Future<void> saveSchedulerHistory(List<SchedulerEvent> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keySchedulerHistory, SchedulerEvent.listToJsonString(list));
  }

  Future<void> addWorkerHistoryEvent({
    required String status,
    String? message,
    int? durationMs,
    String? exitReason,
  }) async {
    try {
      final history = await loadSchedulerHistory();
      final newEvent = SchedulerEvent(
        timestamp: DateTime.now(),
        status: status,
        message: message ?? '',
        durationMs: durationMs,
        exitReason: exitReason,
      );
      
      final updatedHistory = [newEvent, ...history];
      if (updatedHistory.length > 50) {
        updatedHistory.removeRange(50, updatedHistory.length);
      }
      
      await saveSchedulerHistory(updatedHistory);
    } catch (e) {
      debugPrint('[STORAGE] Failed to add worker history event: $e');
    }
  }

  Future<List<ScanSession>> loadScanDiagnostics() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keyScanDiagnostics);
    if (raw == null || raw.isEmpty) return [];
    try {
      final List<dynamic> decoded = jsonDecode(raw);
      return decoded.map((e) => ScanSession.fromJson(e)).toList();
    } catch (e) {
      debugPrint('[STORAGE] Failed to load scan diagnostics: $e');
      return [];
    }
  }

  Future<void> saveScanDiagnostics(List<ScanSession> sessions) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyScanDiagnostics, jsonEncode(sessions.map((s) => s.toJson()).toList()));
  }

  Future<void> addScanSession(ScanSession session) async {
    final sessions = await loadScanDiagnostics();
    sessions.insert(0, session);
    if (sessions.length > 100) {
      sessions.removeRange(100, sessions.length);
    }
    await saveScanDiagnostics(sessions);
  }

  Future<void> updateScanSession(ScanSession session) async {
    final sessions = await loadScanDiagnostics();
    final idx = sessions.indexWhere((s) => s.id == session.id);
    if (idx != -1) {
      sessions[idx] = session;
      await saveScanDiagnostics(sessions);
    } else {
      await addScanSession(session);
    }
  }

  Future<List<String>> getSeenIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(keySeenIds) ?? [];
  }

  Future<void> addSeenIds(List<String> ids) async {
    if (ids.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(keySeenIds) ?? [];
    final updated = {...current, ...ids}.toList();
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

  Future<void> setPendingBackgroundScan(bool pending) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyPendingBackgroundScan, pending);
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
    final previousStartMs = prefs.getInt(keyWorkerStartedAt);
    await prefs.setInt(keyWorkerStartedAt, time.millisecondsSinceEpoch);
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
    String? resultStatus,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final finishVal = time.millisecondsSinceEpoch;
    await prefs.setInt(keyWorkerFinishedAt, finishVal);
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
    if (resultStatus != null) await prefs.setString(keyLastWorkerResult, resultStatus);
    if (success) {
      await prefs.setInt(keyWorkerLastSuccessAt, finishVal);
    } else {
      await prefs.setInt(keyWorkerLastFailureAt, finishVal);
    }
  }

  Future<void> recordWorkerStats({
    required int durationMs,
    required int activeFilters,
    required int successFilters,
    required int failedFilters,
    required bool usedHttpClient,
    required bool usedWebView,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(keyWorkerDurationMs, durationMs);
    await prefs.setInt(keyWorkerActiveFilters, activeFilters);
    await prefs.setInt(keyWorkerSuccessFilters, successFilters);
    await prefs.setInt(keyWorkerFailedFilters, failedFilters);
    await prefs.setBool(keyWorkerUsedHttpClient, usedHttpClient);
    await prefs.setBool(keyWorkerUsedWebView, usedWebView);
  }

  Future<void> recordWorkerRegistration(DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(keyLastWorkerRegistration, time.millisecondsSinceEpoch);
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

  Future<void> setAppForeground(bool foreground) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyAppForeground, foreground);
    if (foreground) {
      await prefs.setInt(keyForegroundHeartbeat, DateTime.now().millisecondsSinceEpoch);
    }
  }

  Future<void> updateForegroundHeartbeat() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(keyForegroundHeartbeat, DateTime.now().millisecondsSinceEpoch);
  }

  Future<bool> isAppForeground() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final isFlagTrue = prefs.getBool(keyAppForeground) ?? false;
    if (!isFlagTrue) return false;

    // Double check with heartbeat to handle process crashes
    final lastHeartbeat = prefs.getInt(keyForegroundHeartbeat) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    // If heartbeat is older than 2 minutes, the app probably crashed/was killed
    final isHeartbeatFresh = (now - lastHeartbeat) < 2 * 60 * 1000;
    
    return isHeartbeatFresh;
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
      'lastRegistration': prefs.getInt(keyLastWorkerRegistration),
      'lastResult': prefs.getString(keyLastWorkerResult),
      'lastSuccessAt': prefs.getInt(keyWorkerLastSuccessAt),
      'lastFailureAt': prefs.getInt(keyWorkerLastFailureAt),
      'durationMs': prefs.getInt(keyWorkerDurationMs),
      'activeFilters': prefs.getInt(keyWorkerActiveFilters),
      'successFilters': prefs.getInt(keyWorkerSuccessFilters),
      'failedFilters': prefs.getInt(keyWorkerFailedFilters),
      'usedHttpClient': prefs.getBool(keyWorkerUsedHttpClient),
      'usedWebView': prefs.getBool(keyWorkerUsedWebView),
    };
  }
}
