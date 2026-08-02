import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:html/parser.dart' show parse;

import '../models/car_listing.dart';
import '../models/search_config.dart';
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

  ScrapeResult.success(this.listings, {this.status = ScrapeStatus.success, this.pages = 0, this.totalFound = 0})
      : ok = true, error = '';
  ScrapeResult.failure(this.error, {this.status = ScrapeStatus.networkError})
      : ok = false, listings = [], pages = 0, totalFound = 0;
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
    return _fetch(url, method: 'GET', timeout: timeout);
  }

  Future<String> _fetch(String url, {required String method, Duration? timeout}) async {
    if (method == 'WORKER') {
      debugPrint('[PAGE HEADLESS] useWebView=$useWebView ready=$_ready');
    }

    if (useWebView) {
      if (!_ready) {
        if (method == 'WORKER') debugPrint('[WORKER FETCH] Re-initializing WebView');
        _initController();
      }

      if (_ready) {
        try {
          if (method == 'WORKER') debugPrint('[WORKER FETCH START] WebView');
          return await _fetchWithWebView(url);
        } catch (e) {
          if (method == 'WORKER') {
            debugPrint('[WORKER FETCH FAILED] WebView error: $e');
          } else {
            debugPrint('[SCRAPER] [WARN] WebView fetch failed, falling back to HttpClient: $e');
          }
        }
      } else {
        if (method == 'WORKER') debugPrint('[WORKER FETCH] WebView NOT READY after init');
      }
    }
    
    if (method == 'WORKER') debugPrint('[WORKER FETCH START] HttpClient');
    try {
      final html = await _fetchSimple(url, timeout: timeout);
      if (method == 'WORKER') debugPrint('[WORKER FETCH SUCCESS] HttpClient');
      return html;
    } catch (e) {
      if (method == 'WORKER') debugPrint('[WORKER FETCH FAILED] HttpClient: $e');
      rethrow;
    }
  }

  Future<String> _fetchSimple(String url, {Duration? timeout}) async {
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
      return html;
    } catch (e) {
      client.close();
      rethrow;
    }
  }

  Future<String> _fetchWithWebView(String url) async {
    if (!_ready) throw Exception('WebView not initialized');
    _pageLoadCompleter = Completer<void>();
    
    await controller.loadRequest(Uri.parse(url), headers: WebviewStealthConfig.navigationHeaders(referer: 'https://www.avto.net/'));
    
    try {
      await _pageLoadCompleter!.future.timeout(WebviewStealthConfig.pageLoadTimeout);
      
      if (url.contains('search.asp')) {
        // Robust wait for models to populate (jQuery.chained)
        for (int i = 0; i < 20; i++) {
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
        bool containersFound = false;
        for (int i = 0; i < 10; i++) {
          final check = await controller.runJavaScriptReturningResult(
            "document.querySelectorAll('div.GO-Results-Row, div.GO-Results-Top-Ponudba, .GO-Results-Main').length > 0"
          );
          if (check == true) {
            containersFound = true;
            break;
          }
          await Future.delayed(const Duration(seconds: 1));
        }
      }

      final html = await controller.runJavaScriptReturningResult('document.documentElement.outerHTML') as String;
      String decodedHtml = _decodeWebViewHtml(html);
      
      if (AvtonetHtmlParser.isCloudflareChallenge(decodedHtml)) {
        throw Exception('Cloudflare Challenge');
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

  Future<ScrapeResult> scrapeSearchUrl(SearchConfig config, {required String method, List<String> seenIds = const []}) async {
    final List<CarListing> allNewListings = [];
    int totalChecked = 0;
    int totalPages = 0;
    final Set<String> seenInThisScan = {};
    
    int consecutiveSeen = 0;
    const int earlyStopThreshold = 15;
    String stopReason = 'Unknown';

    try {
      final String baseUrl = buildAvtonetResultsUrl(config);
      debugPrint('[SCRAPER] Starting forensic scan for: ${config.name}');
      debugPrint('[SCRAPER] URL: $baseUrl');

      pageLoop:
      for (int page = 1; page <= 21; page++) {
        String pageUrl = baseUrl;
        if (pageUrl.contains('stran=')) {
          pageUrl = pageUrl.replaceFirst(RegExp(r'stran=\d+'), 'stran=$page');
        } else {
          pageUrl = '$pageUrl&stran=$page';
        }
        
        debugPrint('[SCRAPER] Fetching Page $page: $pageUrl');
        
        String? html;
        // Retry logic for any page
        for (int retry = 0; retry <= 2; retry++) {
          try {
            html = await _fetch(pageUrl, method: method);
            break; // Success
          } on CloudflareBlockedException {
            debugPrint('[SCRAPER] [ERROR] Cloudflare blocked Page $page');
            return ScrapeResult.failure('Cloudflare Blocked', status: ScrapeStatus.cloudflareBlocked);
          } catch (e) {
            final errStr = e.toString().toLowerCase();
            if (errStr.contains('403') || errStr.contains('cloudflare')) {
              debugPrint('[SCRAPER] [ERROR] 403/Cloudflare Page $page');
              return ScrapeResult.failure('Cloudflare Blocked', status: ScrapeStatus.cloudflareBlocked);
            }
            if (retry == 2) {
              debugPrint('[SCRAPER] [ERROR] Network error Page $page: $e');
              return ScrapeResult.failure('Network error: $e', status: ScrapeStatus.networkError);
            }
            debugPrint('[SCRAPER] [WARN] Page $page retry $retry/2: $e');
            await Future.delayed(Duration(seconds: 2 * (retry + 1)));
          }
        }

        if (html == null || html.isEmpty) {
          debugPrint('[SCRAPER] Page $page returned empty HTML');
          stopReason = 'Empty HTML on page $page';
          break pageLoop;
        }

        final List<CarListing> pageListings = await compute(_parseListingsInBackground, {
          'html': html,
          'configId': config.id,
          'seenIds': seenIds,
        });

        final pagination = await compute(_parsePaginationInBackground, html);
        debugPrint('[SCRAPER] Page $page results: ${pageListings.length} items. Pagination: $pagination');
        
        if (pageListings.isEmpty) {
          debugPrint('[SCRAPER] Stop: No listings on Page $page');
          stopReason = 'Zero listings on page $page';
          break pageLoop;
        }

        for (var listing in pageListings) {
          if (!seenInThisScan.add(listing.id)) continue;
          totalChecked++;

          if (!seenIds.contains(listing.id)) {
            allNewListings.add(listing);
            consecutiveSeen = 0;
          } else {
            if (!listing.isTopOffer) {
              consecutiveSeen++;
            }
          }

          if (consecutiveSeen >= earlyStopThreshold) {
            debugPrint('[SCRAPER] Stop: Reached early-stop threshold (known ads)');
            stopReason = 'Early stop (known ads)';
            break pageLoop;
          }
        }

        totalPages++;

        if (pageListings.length < 10) { 
          debugPrint('[SCRAPER] Stop: Page $page has < 10 items, assuming last page.');
          stopReason = 'Last page reached (small count)';
          break pageLoop;
        }

        if (!pagination.hasNext) {
          debugPrint('[SCRAPER] Stop: Pagination hasNext = false');
          stopReason = 'No next page';
          break pageLoop;
        }

        if (pagination.totalPages > 1 && page >= pagination.totalPages) {
          debugPrint('[SCRAPER] Stop: Reached pagination limit ($page/${pagination.totalPages})');
          stopReason = 'Reached pagination limit';
          break pageLoop;
        }
      }

      debugPrint('[SCRAPER] Forensic scan finished. Total pages: $totalPages, Total items: $totalChecked, Reason: $stopReason');
      return ScrapeResult.success(allNewListings, pages: totalPages, totalFound: totalChecked);

    } catch (e, stack) {
      debugPrint('[SCRAPER] [ERROR] Scrape exception for config ${config.name}: $e');
      if (stack != null) debugPrint(stack.toString());
      return ScrapeResult.failure(e.toString());
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
