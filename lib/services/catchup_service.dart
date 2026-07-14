import '../models/car_listing.dart';
import '../models/search_config.dart';
import 'scan_orchestrator.dart';
import 'storage_service.dart';
import '../utils/logger.dart';

class CatchUpService {
  CatchUpService({
    required StorageService storage,
    required ScanEngine orchestrator,
  })  : _storage = storage,
        _orchestrator = orchestrator;

  final StorageService _storage;
  final ScanEngine _orchestrator;

  static const scanIntervalMinutes = 30;

  Future<bool> shouldRunCatchUp() async {
    final last = await _storage.getLastSuccessfulScan();
    if (last == null) return false;
    return DateTime.now().difference(last).inMinutes >= scanIntervalMinutes;
  }

  Future<int> offlineGapMinutes() async {
    final last = await _storage.getLastSuccessfulScan();
    if (last == null) return 0;
    return DateTime.now().difference(last).inMinutes;
  }

  Future<ScanEngineResult?> runCatchUpIfNeeded({
    required List<SearchConfig> searches,
    required List<CarListing> listings,
    required void Function(int index, int total, String label, String status) onProgress,
  }) async {
    final gapMin = await offlineGapMinutes();
    if (gapMin < scanIntervalMinutes) return null;

    AppLogger.info('[SCAN]', 'Offline gap detected: ${gapMin ~/ 60} h ${gapMin % 60} min. Triggering catch-up.');

    return _orchestrator.scan(
      searches: searches,
      currentListings: listings,
      onProgress: onProgress,
      isAuto: false, 
      ownerOverride: 'CATCHUP',
    );
  }
}
