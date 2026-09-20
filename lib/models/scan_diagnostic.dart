import 'dart:convert';

class ScanSession {
  final String id;
  final DateTime startTime;
  DateTime? endTime;
  final String method; // MANUAL, AUTO, WORKER
  final String? triggerReason;
  int activeFiltersCount;
  final List<FilterDiagnostic> filters;
  String? exitReason;
  bool isLockBlocked;
  String? lockOwner;
  int? totalNewAds;
  int? durationMs;

  ScanSession({
    required this.id,
    required this.startTime,
    required this.method,
    this.triggerReason,
    this.activeFiltersCount = 0,
    List<FilterDiagnostic>? filters,
    this.isLockBlocked = false,
  }) : filters = filters ?? [];

  Map<String, dynamic> toJson() => {
    'id': id,
    'startTime': startTime.toIso8601String(),
    'endTime': endTime?.toIso8601String(),
    'method': method,
    'triggerReason': triggerReason,
    'activeFiltersCount': activeFiltersCount,
    'filters': filters.map((f) => f.toJson()).toList(),
    'exitReason': exitReason,
    'isLockBlocked': isLockBlocked,
    'lockOwner': lockOwner,
    'totalNewAds': totalNewAds,
    'durationMs': durationMs,
  };

  factory ScanSession.fromJson(Map<String, dynamic> json) {
    final session = ScanSession(
      id: json['id'],
      startTime: DateTime.parse(json['startTime']),
      method: json['method'],
      triggerReason: json['triggerReason'],
      activeFiltersCount: json['activeFiltersCount'] ?? 0,
      isLockBlocked: json['isLockBlocked'] ?? false,
    );
    session.endTime = json['endTime'] != null ? DateTime.parse(json['endTime']) : null;
    session.exitReason = json['exitReason'];
    session.lockOwner = json['lockOwner'];
    session.totalNewAds = json['totalNewAds'];
    session.durationMs = json['durationMs'];
    if (json['filters'] != null) {
      session.filters.addAll(
        (json['filters'] as List).map((f) => FilterDiagnostic.fromJson(f))
      );
    }
    return session;
  }
}

class FilterDiagnostic {
  final String filterName;
  final String brand;
  final String model;
  final String url;
  final Map<String, String> urlParams;
  DateTime? startTime;
  DateTime? endTime;
  String status; // SUCCESS, FAILURE, SKIPPED, LOCKED
  String? reason;
  int? httpStatus;
  bool usedWebView;
  bool usedHttpClientFallback;
  bool cloudflareDetected;
  int pagesChecked;
  int adsFound;
  int newAdsFound;
  int knownAdsFound;
  String? error;
  String? stackTrace;
  final List<PageDiagnostic> pages;

  FilterDiagnostic({
    required this.filterName,
    required this.brand,
    required this.model,
    required this.url,
    required this.urlParams,
    this.status = 'PENDING',
    this.usedWebView = false,
    this.usedHttpClientFallback = false,
    this.cloudflareDetected = false,
    this.pagesChecked = 0,
    this.adsFound = 0,
    this.newAdsFound = 0,
    this.knownAdsFound = 0,
  }) : pages = [];

  Map<String, dynamic> toJson() => {
    'filterName': filterName,
    'brand': brand,
    'model': model,
    'url': url,
    'urlParams': urlParams,
    'startTime': startTime?.toIso8601String(),
    'endTime': endTime?.toIso8601String(),
    'status': status,
    'reason': reason,
    'httpStatus': httpStatus,
    'usedWebView': usedWebView,
    'usedHttpClientFallback': usedHttpClientFallback,
    'cloudflareDetected': cloudflareDetected,
    'pagesChecked': pagesChecked,
    'adsFound': adsFound,
    'newAdsFound': newAdsFound,
    'knownAdsFound': knownAdsFound,
    'error': error,
    'stackTrace': stackTrace,
    'pages': pages.map((p) => p.toJson()).toList(),
  };

  factory FilterDiagnostic.fromJson(Map<String, dynamic> json) {
    final diag = FilterDiagnostic(
      filterName: json['filterName'],
      brand: json['brand'],
      model: json['model'],
      url: json['url'],
      urlParams: Map<String, String>.from(json['urlParams'] ?? {}),
      status: json['status'],
      usedWebView: json['usedWebView'] ?? false,
      usedHttpClientFallback: json['usedHttpClientFallback'] ?? false,
      cloudflareDetected: json['cloudflareDetected'] ?? false,
      pagesChecked: json['pagesChecked'] ?? 0,
      adsFound: json['adsFound'] ?? 0,
      newAdsFound: json['newAdsFound'] ?? 0,
      knownAdsFound: json['knownAdsFound'] ?? 0,
    );
    diag.startTime = json['startTime'] != null ? DateTime.parse(json['startTime']) : null;
    diag.endTime = json['endTime'] != null ? DateTime.parse(json['endTime']) : null;
    diag.reason = json['reason'];
    diag.httpStatus = json['httpStatus'];
    diag.error = json['error'];
    diag.stackTrace = json['stackTrace'];
    if (json['pages'] != null) {
      diag.pages.addAll(
        (json['pages'] as List).map((p) => PageDiagnostic.fromJson(p))
      );
    }
    return diag;
  }
}

class PageDiagnostic {
  final int pageNumber;
  final String url;
  final String method; // WebView, HttpClient
  final int? httpStatus;
  final int adsFound;
  final int newAdsFound;
  final int knownAdsFound;
  final bool hasNextPage;
  final String? error;
  final String? webViewError; // New: captures error if WebView failed before fallback

  PageDiagnostic({
    required this.pageNumber,
    required this.url,
    required this.method,
    this.httpStatus,
    required this.adsFound,
    required this.newAdsFound,
    required this.knownAdsFound,
    required this.hasNextPage,
    this.error,
    this.webViewError,
  });

  Map<String, dynamic> toJson() => {
    'pageNumber': pageNumber,
    'url': url,
    'method': method,
    'httpStatus': httpStatus,
    'adsFound': adsFound,
    'newAdsFound': newAdsFound,
    'knownAdsFound': knownAdsFound,
    'hasNextPage': hasNextPage,
    'error': error,
    'webViewError': webViewError,
  };

  factory PageDiagnostic.fromJson(Map<String, dynamic> json) {
    return PageDiagnostic(
      pageNumber: json['pageNumber'],
      url: json['url'],
      method: json['method'],
      httpStatus: json['httpStatus'],
      adsFound: json['adsFound'],
      newAdsFound: json['newAdsFound'],
      knownAdsFound: json['knownAdsFound'],
      hasNextPage: json['hasNextPage'] ?? false,
      error: json['error'],
      webViewError: json['webViewError'],
    );
  }
}
