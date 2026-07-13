import 'dart:async';
import 'package:flutter/material.dart';

import '../models/avtonet_catalog_models.dart';
import '../models/car_listing.dart';
import '../models/search_config.dart';
import '../models/history_filter.dart';
import '../models/scheduler_event.dart';
import '../data/body_types.dart';
import '../services/avtonet_catalog_service.dart';
import '../services/avtonet_scraper_service.dart';
import '../services/catchup_service.dart';
import '../services/lifecycle_scheduler.dart';
import '../services/log_service.dart';
import '../services/scan_orchestrator.dart';
import '../services/storage_service.dart';
import '../background/workmanager_entrypoint.dart';

class AppController extends ChangeNotifier with WidgetsBindingObserver {
  AppController({
    required StorageService storage,
    required LogService log,
    required AvtonetScraperService scraper,
    required AvtonetCatalogService catalog,
    required ScanEngine orchestrator,
    required CatchUpService catchUp,
    required LifecycleScheduler lifecycleScheduler,
  })  : _storage = storage,
        _log = log,
        _scraper = scraper,
        _catalogService = catalog,
        _orchestrator = orchestrator,
        _catchUp = catchUp,
        _lifecycleScheduler = lifecycleScheduler;

  static const maxSavedSearches = 15;

  final StorageService _storage;
  final LogService _log;
  final AvtonetScraperService _scraper;
  final AvtonetCatalogService _catalogService;
  final ScanEngine _orchestrator;
  final CatchUpService _catchUp;
  final LifecycleScheduler _lifecycleScheduler;

  bool _initialized = false;
  bool _isScanning = false;
  int _scanIndex = 0;
  int _scanTotal = 0;
  String _scanLabel = '';
  Timer? _autoScanTimer;
  DateTime? _nextScanTime;
  AvtonetCatalogData? _catalog;

  List<SearchConfig> savedSearches = [];
  List<CarListing> savedListings = [];
  HistoryFilter historyFilter = const HistoryFilter();
  List<SchedulerEvent> schedulerHistory = [];
  Map<String, dynamic> workerDiagnostics = {};

  // Filter Draft State
  String? editingId;
  String selectedMake = '';
  String selectedModel = '';
  String selectedModelSearchValue = '';
  String? selectedModelId;
  String? selectedSubModelGroup;
  List<int> selectedBodyTypes = [];
  String powerUnit = 'kW';
  int selectedFuel = 0;
  String selectedTransmission = '';
  String draftSearchName = '';

  String? kmMinText;
  String? kmMaxText;
  String? letnikMinText;
  String? letnikMaxText;
  String? cenaMinText;
  String? cenaMaxText;
  String? ccmMinText;
  String? ccmMaxText;
  String? mocMinText;
  String? mocMaxText;

  List<AvtonetBrand> get allBrands => _catalog?.brands ?? [];
  List<String> get makes => allBrands.map((b) => b.displayName).toList();
  List<AvtonetModel> get availableModels => _catalog?.modelsByBrand[selectedMake] ?? [];
  List<String> get models => availableModels.map((m) => m.displayName).toList();
  bool get isModelDropdownEnabled => selectedMake.isNotEmpty;

  List<String> modelsForMake(String makeValue) {
    return _catalog?.modelsByBrand[makeValue]?.map((m) => m.displayName).toList() ?? [];
  }

  bool get initialized => _initialized;
  bool get isScanning => _isScanning;
  int get scanIndex => _scanIndex;
  int get scanTotal => _scanTotal;
  String get scanLabel => _scanLabel;
  LogService get log => _log;
  AvtonetScraperService get scraper => _scraper;
  DateTime? get nextScanTime => _nextScanTime;

  Future<void> initialize() async {
    if (_initialized) return;
    debugPrint('[TRACE 22-A] AppController.initialize starting');
    WidgetsBinding.instance.addObserver(this);
    await _log.loadPersisted();
    _catalog = await _catalogService.getCatalog();
    savedSearches = await _storage.loadSearches();
    savedListings = await _storage.loadListings();
    historyFilter = await _storage.loadHistoryFilter();
    schedulerHistory = await _storage.loadSchedulerHistory();
    workerDiagnostics = await _storage.getWorkerDiagnostics();
    
    _calculateNextScanTime();
    _autoScanTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _calculateNextScanTime();
    });

    _initialized = true;
    notifyListeners();
    debugPrint('[APP INITIALIZED]');
    
    // Check if background worker missed a scan due to Cloudflare
    debugPrint('[CHECKING PENDING SCANS] on initialization');
    final needsScan = await _storage.consumePendingBackgroundScan();
    debugPrint('[CHECK PENDING] value=$needsScan');
    if (needsScan) {
      debugPrint('[STARTING CATCHUP SCAN]');
      debugPrint('[STARTING FOREGROUND WEBVIEW SCAN]');
      runSequentialScan().then((_) {
        debugPrint('[CATCHUP COMPLETE]');
        debugPrint('[FOREGROUND SCAN FINISHED]');
      });
    }
  }

  void _calculateNextScanTime() {
    final now = DateTime.now();
    
    // Strict cutoff: No scans after 22:00
    if (now.hour >= 22) {
      debugPrint('[SCHEDULE BLOCKED AFTER 22:00]');
      _nextScanTime = DateTime(now.year, now.month, now.day + 1, 8, 0);
      notifyListeners();
      return;
    }

    // Find next 15-min mark: 00, 15, 30, 45
    int minute = now.minute;
    int nextMinute = ((minute ~/ 15) + 1) * 15;
    
    DateTime next;
    if (nextMinute >= 60) {
      next = DateTime(now.year, now.month, now.day, now.hour + 1, 0);
    } else {
      next = DateTime(now.year, now.month, now.day, now.hour, nextMinute);
    }
    
    // Apply window rules (08:00 - 21:45 is the last start)
    if (next.hour < 8) {
      next = DateTime(next.year, next.month, next.day, 8, 0);
    } else if (next.hour >= 22) {
      debugPrint('[SCHEDULE BLOCKED AFTER 22:00]');
      next = DateTime(next.year, next.month, next.day + 1, 8, 0);
    }
    
    _nextScanTime = next;
    debugPrint('[SCHEDULER] now=$now next=$_nextScanTime activeWindow=08:00-22:00 interval=15m');
    notifyListeners();
  }

  Future<void> _processStartupTasks() async {
    // REMOVED: Automatic catch-up scans on startup removed per user requirement.
    // The background worker will handle finding all new ads since its last run
    // because seen_vehicle_ids preserves state.
  }

  int _countMissedSlots(DateTime last, DateTime now) {
    int count = 0;
    DateTime current = last.add(const Duration(minutes: 15));
    while (current.isBefore(now)) {
      if (current.hour >= 8 && current.hour < 22) {
        count++;
      }
      current = current.add(const Duration(minutes: 15));
    }
    return count;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('[TRACE 25] didChangeAppLifecycleState: state=$state initialized=$_initialized isScanning=$_isScanning');
    if (state == AppLifecycleState.resumed) {
      debugPrint('[APP RESUMED]');
      _checkPendingScan();
    }
  }

  Future<void> _checkPendingScan() async {
    debugPrint('[TRACE 26] _checkPendingScan starting');
    final needsScan = await _storage.consumePendingBackgroundScan();
    debugPrint('[TRACE 27] _checkPendingScan: consumePendingBackgroundScan value=$needsScan');
    if (needsScan) {
      if (!_isScanning) {
        debugPrint('[STARTING CATCHUP SCAN]');
        debugPrint('[STARTING FOREGROUND WEBVIEW SCAN]');
        runSequentialScan().then((_) {
          debugPrint('[CATCHUP COMPLETE]');
          debugPrint('[FOREGROUND SCAN FINISHED]');
        });
      } else {
        debugPrint('[TRACE 28] _checkPendingScan: already scanning, re-queuing pending scan');
        await _storage.setPendingBackgroundScan(true);
      }
    }
  }

  void prepareNewSearch() {
    editingId = null; selectedMake = ''; selectedModel = '';
    selectedModelSearchValue = ''; selectedModelId = null; selectedSubModelGroup = null;
    selectedBodyTypes = []; powerUnit = 'kW'; selectedFuel = 0;
    selectedTransmission = ''; draftSearchName = '';
    kmMinText = null; kmMaxText = null; letnikMinText = null;
    letnikMaxText = null; cenaMinText = null; cenaMaxText = null;
    ccmMinText = null; ccmMaxText = null; mocMinText = null; mocMaxText = null;
    notifyListeners();
  }

  void loadSearchForEditing(SearchConfig config) {
    editingId = config.id; selectedMake = config.znamka; selectedModel = config.model;
    selectedModelSearchValue = config.modelSearchValue;
    selectedModelId = config.modelId;
    selectedSubModelGroup = config.subModelGroup;
    selectedBodyTypes = config.oblika.split(',').map((e) => int.tryParse(e)).where((e) => e != null && e != 0).cast<int>().toList();
    powerUnit = config.powerUnit; selectedFuel = config.bencin; selectedTransmission = config.menjalnik;
    draftSearchName = config.name; kmMinText = config.kmMin?.toString(); kmMaxText = config.kmMax?.toString();
    letnikMinText = config.letnikMin?.toString(); letnikMaxText = config.letnikMax?.toString();
    cenaMinText = config.cenaMin?.toString(); cenaMaxText = config.cenaMax?.toString();
    ccmMinText = config.ccmMin?.toString(); ccmMaxText = config.ccmMax?.toString();
    mocMinText = config.mocMin?.toString(); mocMaxText = config.mocMax?.toString();
    notifyListeners();
  }

  void onMakeChanged(String? makeValue) { 
    selectedMake = makeValue ?? '';
    selectedModel = ''; 
    selectedModelSearchValue = '';
    selectedModelId = null;
    selectedSubModelGroup = null;
    notifyListeners(); 
  }

  void onModelChanged(String? modelName) { 
    selectedModel = modelName ?? '';
    final modelData = availableModels.firstWhere(
      (m) => m.displayName == modelName,
      orElse: () => AvtonetModel(displayName: '', searchValue: ''),
    );
    selectedModelSearchValue = modelData.searchValue;
    selectedModelId = modelData.modelId;
    selectedSubModelGroup = modelData.subModelGroup;

    debugPrint('[UI SELECTION AUDIT] modelName="$selectedModel" modelId="$selectedModelId" searchValue="$selectedModelSearchValue"');
    notifyListeners(); 
  }
  void toggleBodyType(int code) {
    if (code == 0) selectedBodyTypes = [];
    else selectedBodyTypes.contains(code) ? selectedBodyTypes.remove(code) : selectedBodyTypes.add(code);
    notifyListeners();
  }
  void setPowerUnit(String unit) { powerUnit = unit; notifyListeners(); }
  void onFuelChanged(int? code) { selectedFuel = code ?? 0; notifyListeners(); }
  void onTransmissionChanged(String? id) { selectedTransmission = id ?? ''; notifyListeners(); }
  void setDraftSearchName(String v) { draftSearchName = v; notifyListeners(); }
  void setKmMin(String v) { kmMinText = v; notifyListeners(); }
  void setKmMax(String v) { kmMaxText = v; notifyListeners(); }
  void setLetnikMin(String v) { letnikMinText = v; notifyListeners(); }
  void setLetnikMax(String v) { letnikMaxText = v; notifyListeners(); }
  void setCenaMin(String v) { cenaMinText = v; notifyListeners(); }
  void setCenaMax(String v) { cenaMaxText = v; notifyListeners(); }
  void setCcmMin(String v) { ccmMinText = v; notifyListeners(); }
  void setCcmMax(String v) { ccmMaxText = v; notifyListeners(); }
  void setMocMin(String v) { mocMinText = v; notifyListeners(); }
  void setMocMax(String v) { mocMaxText = v; notifyListeners(); }

  Future<bool> saveCurrentSearch() async {
    final name = draftSearchName.trim().isEmpty ? _defaultSearchName() : draftSearchName.trim();
    String oblikaCsv = selectedBodyTypes.isEmpty ? '0' : selectedBodyTypes.join(',');
    final config = SearchConfig(
      id: editingId ?? DateTime.now().millisecondsSinceEpoch.toString(), 
      name: name, 
      znamka: selectedMake, 
      model: selectedModel,
      modelSearchValue: selectedModelSearchValue,
      modelId: selectedModelId,
      subModelGroup: selectedSubModelGroup,
      oblika: oblikaCsv, kmMin: _parseInt(kmMinText), kmMax: _parseInt(kmMaxText), letnikMin: _parseInt(letnikMinText),
      letnikMax: _parseInt(letnikMaxText), cenaMin: _parseInt(cenaMinText), cenaMax: _parseInt(cenaMaxText),
      ccmMin: _parseInt(ccmMinText), ccmMax: _parseInt(ccmMaxText), mocMin: _parseInt(mocMinText), mocMax: _parseInt(mocMaxText),
      powerUnit: powerUnit, bencin: selectedFuel, menjalnik: selectedTransmission, createdAt: DateTime.now(),
    );
    if (editingId != null) {
      final idx = savedSearches.indexWhere((s) => s.id == editingId);
      if (idx != -1) savedSearches[idx] = config.copyWith(lastChecked: savedSearches[idx].lastChecked, lastStatus: savedSearches[idx].lastStatus);
    } else {
      if (savedSearches.length >= maxSavedSearches) return false;
      savedSearches = [...savedSearches, config];
    }
    await _storage.saveSearches(savedSearches);
    editingId = null; notifyListeners();
    return true;
  }

  int? _parseInt(String? t) => (t == null || t.trim().isEmpty) ? null : int.tryParse(t.trim());

  Future<void> runSequentialScan({bool forceAll = false, String? singleId}) async {
    debugPrint('[STARTING WEBVIEW SCAN] forceAll=$forceAll singleId=$singleId');
    if (_isScanning) {
      debugPrint('[SCAN] Already scanning. Ignoring request.');
      return;
    }
    
    // Identification of items to scan
    List<SearchConfig> configsToPass;
    if (singleId != null) {
      configsToPass = savedSearches.where((s) => s.id == singleId).toList();
    } else if (forceAll) {
      configsToPass = savedSearches;
    } else {
      configsToPass = savedSearches.where((s) => s.isEnabled).toList();
    }
    
    if (configsToPass.isEmpty) {
      debugPrint('[SCAN] No filters to scan.');
      return;
    }
    
    _isScanning = true; _scanTotal = configsToPass.length; _scanIndex = 0; notifyListeners();
    
    try {
      final result = await _orchestrator.scan(
        searches: savedSearches, 
        currentListings: savedListings,
        onProgress: (idx, total, lbl, st) { 
          _scanIndex = idx; 
          _scanTotal = total; 
          _scanLabel = lbl; 
          notifyListeners(); 
        },
        isAuto: false,
        forceAll: forceAll,
        singleId: singleId,
      );
      debugPrint('[WEBVIEW SCAN COMPLETE] success=${result.successCount} new=${result.newListings}');
      
      if (result.successCount > 0) {
        await _storage.setLastScanNewCount(result.newListings);
      } else if (result.failCount > 0) {
        await _storage.setLastFailedScan(DateTime.now(), 'Scan failed');
      }

      savedSearches = result.updatedConfigs; 
      await _storage.saveSearches(savedSearches);
      savedListings = await _storage.loadListings();
    } finally {
      _isScanning = false; 
      notifyListeners();
    }
  }

  void cancelScan() {
    if (!_isScanning) return;
    _orchestrator.requestCancel();
    _isScanning = false;
    notifyListeners();
  }

  Future<void> _recordSchedulerEvent(String status, {String message = ''}) async {
    final event = SchedulerEvent(timestamp: DateTime.now(), status: status, message: message);
    schedulerHistory.insert(0, event);
    if (schedulerHistory.length > 20) {
      schedulerHistory.removeRange(20, schedulerHistory.length);
    }
    await _storage.saveSchedulerHistory(schedulerHistory);
    notifyListeners();
  }

  Future<void> toggleSearch(String id, bool enabled) async {
    final idx = savedSearches.indexWhere((s) => s.id == id);
    if (idx != -1) { savedSearches[idx] = savedSearches[idx].copyWith(isEnabled: enabled); await _storage.saveSearches(savedSearches); notifyListeners(); }
  }

  Future<void> deleteSearch(String id) async { savedSearches = savedSearches.where((s) => s.id != id).toList(); await _storage.saveSearches(savedSearches); notifyListeners(); }
  Future<void> removeListing(String id) async { savedListings = savedListings.where((l) => l.id != id).toList(); await _storage.saveListings(savedListings); notifyListeners(); }
  Future<void> clearListings() async { savedListings = []; await _storage.saveListings(savedListings); notifyListeners(); }
  Future<void> resetSeenDatabase() async { await _storage.clearSeenIds(); notifyListeners(); }

  Future<void> refreshDiagnostics() async {
    workerDiagnostics = await _storage.getWorkerDiagnostics();
    schedulerHistory = await _storage.loadSchedulerHistory();
    notifyListeners();
  }

  Future<void> runWorkerNow() async {
    await runTestBackgroundTask();
    // Give it a moment then refresh
    Future.delayed(const Duration(seconds: 5), () => refreshDiagnostics());
  }

  Future<void> fullClearDatabase() async {
    savedListings = [];
    await _storage.saveListings([]);
    await _storage.clearSeenIds();
    await _storage.saveSchedulerHistory([]);
    schedulerHistory = [];
    await _storage.setLastScanNewCount(0);
    notifyListeners();
  }

  Future<void> updateHistoryFilter(HistoryFilter newFilter) async {
    final oldFilter = historyFilter;
    historyFilter = newFilter;
    await _storage.saveHistoryFilter(historyFilter);
    notifyListeners();
  }

  Future<void> resetHistoryFilter() async {
    historyFilter = const HistoryFilter();
    await _storage.saveHistoryFilter(historyFilter);
    notifyListeners();
  }

  void _compareHistoryFilters(HistoryFilter old, HistoryFilter updated) {
    final lostFields = <String>[];
    if (old.priceMin != null && updated.priceMin == null) lostFields.add('priceMin');
    if (old.priceMax != null && updated.priceMax == null) lostFields.add('priceMax');
    if (old.fuelCode != 0 && updated.fuelCode == 0) lostFields.add('fuelCode');
    if (old.make.isNotEmpty && updated.make.isEmpty) lostFields.add('make');
    
    if (lostFields.isNotEmpty) {
      debugPrint('[COMPARISON WARNING] Lost/Changed fields: ${lostFields.join(', ')}');
    } else {
      debugPrint('[COMPARISON] No critical fields lost during save/load cycle.');
    }
  }

  String _defaultSearchName() {
    final make = selectedMake.isEmpty ? 'Vse znamke' : selectedMake;
    return '$make ${selectedModel.isEmpty ? "" : selectedModel}';
  }

  String bodyTypeLabel(String csv) {
    if (csv == '0') return 'Vse oblike';
    return csv.split(',').map((e) => int.tryParse(e)).where((e) => e != null).map((c) => kBodyTypes.firstWhere((b) => b.code == c, orElse: () => kBodyTypes.first).label).join(', ');
  }

  @override void dispose() { _autoScanTimer?.cancel(); WidgetsBinding.instance.removeObserver(this); _lifecycleScheduler.dispose(); super.dispose(); }
}
