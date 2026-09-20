import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:html/parser.dart' show parse;

import '../models/car_listing.dart';
import '../models/search_config.dart';
import '../models/scan_diagnostic.dart';
import '../parsers/avtonet_html_parser.dart';
import '../utils/url_builder.dart';
import 'log_service.dart';
import 'webview_stealth_config.dart';

enum ScrapeStatus {
  idle,
  working,
  success,
  noAdsFound,
  cloudflareBlocked,
  networkError,
  emptyResults,
  parsingError,
}

class ScrapeResult {
  final bool ok;
  final List<CarListing> listings;
  final String error;
  final ScrapeStatus status;
  final int pages;
  final int totalFound;
  final int? httpStatus;
  final bool usedWebView;
  final bool usedHttpClient;

  ScrapeResult.success(this.listings, {
    this.status = ScrapeStatus.success, 
    this.pages = 0, 
    this.totalFound = 0,
    this.httpStatus = 200,
    this.usedWebView = false,
    this.usedHttpClient = false,
  }) : ok = true, error = '';
  
  ScrapeResult.failure(this.error, {
    this.status = ScrapeStatus.networkError,
    this.httpStatus,
    this.usedWebView = false,
    this.usedHttpClient = false,
  }) : ok = false, listings = [], pages = 0, totalFound = 0;
}

class CloudflareBlockedException implements Exception {
  final String message;
  CloudflareBlockedException(this.message);
  @override
  String toString() => message;
}

class AvtonetScraperService {
  AvtonetScraperService(this._log, {this.useWebView = true}) {
    if (useWebView) {
      _initController();
    }
  }

  final LogService _log;
  final bool useWebView;
  late final WebViewController controller;
  bool _ready = false;
  bool get isReady => _ready;
  Completer<void>? _pageLoadCompleter;

  void _initController() {
    if (kIsWeb) return;
    try {
      controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setUserAgent(WebviewStealthConfig.userAgent)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (url) {
              _pageLoadCompleter?.complete();
            },
            onWebResourceError: (error) {
              debugPrint('[SCRAPER] [ERROR] WebView resource error: ${error.description}');
            },
          ),
        );
      _ready = true;
      debugPrint('[SCRAPER] WebView initialized successfully, _ready=true');
    } catch (e) {
      debugPrint('[SCRAPER] [ERROR] WebView initialization failed: $e');
      _ready = false;
    }
  }

  Future<void> _resetSession() async {
    if (!_ready) return;
    await controller.clearCache();
    await controller.clearLocalStorage();
    final cookieManager = WebViewCookieManager();
    await cookieManager.clearCookies();
  }

  Future<String> fetchHtml(String url, {Duration? timeout}) async {
    return (await _fetch(url, method: 'GET', timeout: timeout)).html;
  }

  Future<({String html, int? statusCode, bool webView, String? webViewError})> _fetch(String url, {required String method, Duration? timeout}) async {
    final effectiveTimeout = timeout ?? 
      (method == 'WORKER' ? const Duration(seconds: 30) : WebviewStealthConfig.pageLoadTimeout);

    String? webViewError;
    if (useWebView) {
      if (!_ready) {
        _initController();
      }

      if (_ready) {
        try {
          if (method == 'WORKER') debugPrint('[SCAN_FILTER] FETCH START (WebView)');
          final html = await _fetchWithWebView(url, timeout: effectiveTimeout);
          return (html: html, statusCode: 200, webView: true, webViewError: null);
        } catch (e) {
          webViewError = e.toString();
          if (method == 'WORKER') {
            final err = webViewError.toLowerCase();
            if (err.contains('timeout')) {
              debugPrint('[SCAN_FILTER] WEBVIEW TIMEOUT url=$url');
            } else if (err.contains('cloudflare') || err.contains('challenge')) {
              debugPrint('[SCAN_FILTER] CLOUDFLARE url=$url');
            }
          }
        }
      }
    }
    
    if (method == 'WORKER') debugPrint('[SCAN_FILTER] FETCH START (HttpClient)');
    try {
      final res = await _fetchSimple(url, timeout: effectiveTimeout);
      return (html: res.html, statusCode: res.statusCode, webView: false, webViewError: webViewError);
    } catch (e) {
      if (method == 'WORKER') {
        final err = e.toString().toLowerCase();
        if (err.contains('cloudflare') || err.contains('403')) {
          debugPrint('[SCAN_FILTER] CLOUDFLARE url=$url (HttpClient)');
        }
      }
      // Re-wrap error if we have WebView context
      if (webViewError != null) {
        throw Exception('HttpClient error after WebView failed ($webViewError): $e');
      }
      rethrow;
    }
  }

  Future<({String html, int statusCode})> _fetchSimple(String url, {Duration? timeout}) async {
    final effectiveTimeout = timeout ?? WebviewStealthConfig.pageLoadTimeout;
    final client = HttpClient();
    client.connectionTimeout = effectiveTimeout;
    
    try {
      final request = await client.getUrl(Uri.parse(url));
      WebviewStealthConfig.navigationHeaders(referer: 'https://www.avto.net/').forEach((k, v) => request.headers.set(k, v));
      
      final response = await request.close().timeout(effectiveTimeout);
      final statusCode = response.statusCode;

      if (statusCode == 301 || statusCode == 302) {
        final location = response.headers.value('location');
        debugPrint('[SCRAPER] [WARN] HTTP Redirect to: $location');
      }

      final html = await response.transform(utf8.decoder).join();

      if (AvtonetHtmlParser.isCloudflareChallenge(html)) {
        throw CloudflareBlockedException('Cloudflare Challenge Detected');
      }

      if (statusCode != 200) {
        if (statusCode == 403) {
           throw CloudflareBlockedException('HTTP 403 Forbidden (Cloudflare)');
        }
        throw Exception('HTTP $statusCode');
      }

      client.close();
      return (html: html, statusCode: statusCode);
    } catch (e) {
      client.close();
      rethrow;
    }
  }

  Future<String> _fetchWithWebView(String url, {Duration? timeout}) async {
    if (!_ready) throw Exception('WebView not initialized');
    _pageLoadCompleter = Completer<void>();
    
    final effectiveTimeout = timeout ?? WebviewStealthConfig.pageLoadTimeout;
    
    await controller.loadRequest(Uri.parse(url), headers: WebviewStealthConfig.navigationHeaders(referer: 'https://www.avto.net/'));
    
    try {
      await _pageLoadCompleter!.future.timeout(effectiveTimeout);
      
      final startTime = DateTime.now();
      if (url.contains('search.asp')) {
        for (int i = 0; i < 20; i++) {
          if (DateTime.now().difference(startTime) > effectiveTimeout) break;
          try {
            final result = await controller.runJavaScriptReturningResult(
              "document.querySelectorAll('#model option').length"
            );
            final count = int.tryParse(result.toString()) ?? 0;
            if (count > 1) break;
          } catch (_) {}
          await Future.delayed(const Duration(milliseconds: 500));
        }
      } else {
        for (int i = 0; i < 10; i++) {
          if (DateTime.now().difference(startTime) > effectiveTimeout) break;
          final check = await controller.runJavaScriptReturningResult(
            "document.querySelectorAll('div.GO-Results-Row, div.GO-Results-Top-Ponudba, .GO-Results-Main').length > 0"
          );
          if (check == true) break;
          await Future.delayed(const Duration(seconds: 1));
        }
      }

      final html = await controller.runJavaScriptReturningResult('document.documentElement.outerHTML') as String;
      String decodedHtml = _decodeWebViewHtml(html);
      
      if (AvtonetHtmlParser.isCloudflareChallenge(decodedHtml)) {
        throw CloudflareBlockedException('Cloudflare Challenge');
      }

      return decodedHtml;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> dispose() async {
    if (_ready) {
      try {
        // Clear delegates to avoid Pigeon errors after disposal
        await controller.setNavigationDelegate(NavigationDelegate());
        await controller.setJavaScriptMode(JavaScriptMode.disabled);
      } catch (_) {}
    }
  }

  String _decodeWebViewHtml(String html) {
    if (html.startsWith('"') && html.endsWith('"')) {
      html = html.substring(1, html.length - 1);
    }
    return html.replaceAll('\\u003C', '<')
               .replaceAll('\\u003E', '>')
               .replaceAll('\\u0022', '"')
               .replaceAll('\\u0027', "'")
               .replaceAll('\\/', '/')
               .replaceAll('\\n', '\n')
               .replaceAll('\\r', '\r')
               .replaceAll('\\"', '"');
  }

  Future<ScrapeResult> scrapeSearchUrl(
    SearchConfig config, {
    required String method, 
    List<String> seenIds = const [],
    void Function(PageDiagnostic)? onPageLog,
  }) async {
    final List<CarListing> allNewListings = [];
    int totalChecked = 0;
    int totalPages = 0;
    final Set<String> seenInThisScan = {};
    
    int consecutiveEmptyPages = 0;
    const int earlyStopPageThreshold = 3;

    bool usedWebView = false;
    bool usedHttpClient = false;

    try {
      final String baseUrl = buildAvtonetResultsUrl(config);
      if (method == 'WORKER') debugPrint('[SCAN_FILTER] URL=$baseUrl');

      pageLoop:
      for (int page = 1; page <= 21; page++) {
        String pageUrl = baseUrl;
        if (pageUrl.contains('stran=')) {
          pageUrl = pageUrl.replaceFirst(RegExp(r'stran=\d+'), 'stran=$page');
        } else {
          pageUrl = '$pageUrl&stran=$page';
        }
        
        if (method == 'WORKER') debugPrint('[SCAN_FILTER] PAGE $page START');
        final pageStopwatch = Stopwatch()..start();
        
        String? html;
        int? httpStatus;
        bool isWebView = false;
        String? wvError;

        final maxRetries = (method == 'WORKER') ? 1 : 2;
        
        for (int retry = 0; retry <= maxRetries; retry++) {
          try {
            final fetchRes = await _fetch(pageUrl, method: method);
            html = fetchRes.html;
            httpStatus = fetchRes.statusCode;
            isWebView = fetchRes.webView;
            wvError = fetchRes.webViewError;
            if (isWebView) usedWebView = true; else usedHttpClient = true;
            break; 
          } on CloudflareBlockedException catch (e) {
            String errorMsg = 'CLOUDFLARE: ${e.message}';
            if (usedHttpClient && wvError != null) {
              errorMsg = 'HTTPCLIENT_CLOUDFLARE_AFTER_WEBVIEW_FAILURE (WV Error: $wvError)';
            }

            if (onPageLog != null) {
              onPageLog(PageDiagnostic(
                pageNumber: page,
                url: pageUrl,
                method: isWebView ? 'WebView' : 'HttpClient',
                httpStatus: 403,
                adsFound: 0, newAdsFound: 0, knownAdsFound: 0,
                hasNextPage: false,
                error: errorMsg,
                webViewError: wvError,
              ));
            }
            return ScrapeResult.failure(errorMsg, status: ScrapeStatus.cloudflareBlocked, httpStatus: 403, usedWebView: usedWebView, usedHttpClient: usedHttpClient);
          } catch (e) {
            if (retry == maxRetries) {
              if (onPageLog != null) {
                onPageLog(PageDiagnostic(
                  pageNumber: page,
                  url: pageUrl,
                  method: usedHttpClient ? 'HttpClient' : 'WebView',
                  httpStatus: httpStatus,
                  adsFound: 0, newAdsFound: 0, knownAdsFound: 0,
                  hasNextPage: false,
                  error: e.toString(),
                  webViewError: wvError,
                ));
              }
              return ScrapeResult.failure('Network error: $e', status: ScrapeStatus.networkError, usedWebView: usedWebView, usedHttpClient: usedHttpClient);
            }
            await Future.delayed(Duration(seconds: 2 * (retry + 1)));
          }
        }

        if (html == null || html.isEmpty) {
          break pageLoop;
        }

        final List<CarListing> pageListings = await compute(_parseListingsInBackground, {
          'html': html,
          'configId': config.id,
          'seenIds': seenIds,
        });

        final pagination = await compute(_parsePaginationInBackground, html);
        
        int pageNew = 0;
        int pageKnown = 0;
        bool foundNewAdOnThisPage = false;

        for (var listing in pageListings) {
          if (!seenInThisScan.add(listing.id)) continue;
          totalChecked++;

          if (!seenIds.contains(listing.id)) {
            allNewListings.add(listing);
            pageNew++;
            foundNewAdOnThisPage = true;
          } else {
            pageKnown++;
          }
        }

        if (onPageLog != null) {
          onPageLog(PageDiagnostic(
            pageNumber: page,
            url: pageUrl,
            method: isWebView ? 'WebView' : 'HttpClient',
            httpStatus: httpStatus,
            adsFound: pageListings.length,
            newAdsFound: pageNew,
            knownAdsFound: pageKnown,
            hasNextPage: pagination.hasNext,
          ));
        }

        if (method == 'WORKER') {
          debugPrint('[SCAN_FILTER] PAGE $page RESULTS=${pageListings.length} NEW=$pageNew duration=${pageStopwatch.elapsed.inSeconds}s');
        }
        
        if (pageListings.isEmpty) {
          break pageLoop;
        }

        totalPages++;

        // Early stop logic at PAGE level
        if (foundNewAdOnThisPage) {
          consecutiveEmptyPages = 0;
        } else {
          // If no new ads found on this page, increment counter
          consecutiveEmptyPages++;
        }

        if (consecutiveEmptyPages >= earlyStopPageThreshold) {
          if (method == 'WORKER') debugPrint('[SCAN_FILTER] Early stop reached after $earlyStopPageThreshold empty pages');
          break pageLoop;
        }

        if (pageListings.length < 10) { 
          break pageLoop;
        }

        if (!pagination.hasNext) {
          break pageLoop;
        }

        if (pagination.totalPages > 1 && page >= pagination.totalPages) {
          break pageLoop;
        }
      }

      return ScrapeResult.success(
        allNewListings, 
        pages: totalPages, 
        totalFound: totalChecked, 
        usedWebView: usedWebView,
        usedHttpClient: usedHttpClient,
      );

    } catch (e, stack) {
      if (stack != null) debugPrint(stack.toString());
      return ScrapeResult.failure(e.toString(), usedWebView: usedWebView, usedHttpClient: usedHttpClient);
    }
  }
}

/// Helper for compute()
List<CarListing> _parseListingsInBackground(Map<String, dynamic> data) {
  return AvtonetHtmlParser.parseListings(
    data['html'],
    searchConfigId: data['configId'],
    seenIds: data['seenIds'],
  );
}

PaginationInfo _parsePaginationInBackground(String html) {
  return AvtonetHtmlParser.parsePagination(parse(html));
}
