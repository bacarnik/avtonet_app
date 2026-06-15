import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

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

class AvtonetScraperService {
  AvtonetScraperService(this._log) {
    _initController();
  }

  final LogService _log;
  late final WebViewController controller;
  bool _ready = false;
  bool get isReady => _ready;
  Completer<void>? _pageLoadCompleter;
  
  // Persistent Cookie Storage
  final List<Cookie> _cookieJar = [];

  void _initController() {
    if (kIsWeb) return;
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(WebviewStealthConfig.userAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            _pageLoadCompleter?.complete();
          },
          onWebResourceError: (error) {
            debugPrint('[WEBVIEW ERROR] ${error.description}');
          },
        ),
      );
    _ready = true;
  }

  Future<void> _resetSession() async {
    if (!_ready) return;
    await controller.clearCache();
    await controller.clearLocalStorage();
    final cookieManager = WebViewCookieManager();
    await cookieManager.clearCookies();
  }

  /// Simplified Fetch: Prefer WebView for stability as requested.
  Future<String> _fetch(String url, {required String method, Duration? timeout}) async {
    debugPrint('[SCAN URL] $url');
    
    // Attempt WebView fetch primarily for stability against 403
    try {
      final html = await _fetchWithWebView(url);
      debugPrint('[HTML RECEIVED] length=${html.length}');
      return html;
    } catch (e) {
      debugPrint('[WEBVIEW FETCH FAILED] $e');
      // Fallback to simple HttpClient if WebView fails, but keep it minimal
      final html = await _fetchSimple(url, timeout: timeout);
      debugPrint('[HTML RECEIVED] length=${html.length}');
      return html;
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
      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');

      final html = await response.transform(utf8.decoder).join();
      client.close();
      return html;
    } catch (e) {
      client.close();
      rethrow;
    }
  }

  Future<String> _fetchWithWebView(String url) async {
    if (!_ready) throw Exception('WebView not initialized');
    
    debugPrint('[SCAN URL] $url');
    _pageLoadCompleter = Completer<void>();
    
    await controller.loadRequest(Uri.parse(url), headers: WebviewStealthConfig.navigationHeaders(referer: 'https://www.avto.net/'));
    
    try {
      await _pageLoadCompleter!.future.timeout(WebviewStealthConfig.pageLoadTimeout);
      
      // WAIT CONDITION: Wait for listing containers to appear
      bool containersFound = false;
      for (int i = 0; i < 10; i++) {
        final check = await controller.runJavaScriptReturningResult(
          "document.querySelectorAll('div.GO-Results-Row, div.GO-Results-Top-Ponudba, .GO-Results-Main').length > 0"
        );
        if (check == true) {
          containersFound = true;
          debugPrint('[WEBVIEW] Listing containers detected after ${i + 1}s');
          break;
        }
        await Future.delayed(const Duration(seconds: 1));
      }

      if (!containersFound) {
        debugPrint('[WEBVIEW WARNING] No listing containers detected after 10s wait.');
      }
      
      final finalUrl = await controller.currentUrl();
      final pageTitle = await controller.getTitle();
      final jsLocation = await controller.runJavaScriptReturningResult('window.location.href');
      
      debugPrint('[FINAL URL] $finalUrl');
      debugPrint('[PAGE TITLE] $pageTitle');
      debugPrint('[JS LOCATION] $jsLocation');
      
      final html = await controller.runJavaScriptReturningResult('document.documentElement.outerHTML') as String;
      String decodedHtml = _decodeWebViewHtml(html);
      
      final bodyLength = decodedHtml.length;
      debugPrint('[HTML RECEIVED] length=$bodyLength');

      // Extract title for logging
      final titleMatch = RegExp(r'<title>(.*?)</title>', caseSensitive: false).firstMatch(decodedHtml);
      final htmlTitle = titleMatch?.group(1) ?? 'No title found';
      debugPrint('[HTML TITLE] $htmlTitle');

      debugPrint('[HTML PREVIEW] ${decodedHtml.substring(0, decodedHtml.length > 5000 ? 5000 : decodedHtml.length)}');
      
      if (AvtonetHtmlParser.isCloudflareChallenge(decodedHtml)) {
        debugPrint('[CLOUDFLARE DETECTED]');
        throw Exception('Cloudflare Challenge');
      }

      return decodedHtml;
    } catch (e) {
      debugPrint('[WEBVIEW ERROR] $e');
      rethrow;
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
    int consecutivePageFailures = 0;
    const int maxConsecutivePageFailures = 3;
    final Set<String> seenInThisScan = {};
    
    int consecutiveKnownPages = 0;
    const int maxPageLimit = 25;
    const int maxKnownPagesLimit = 2; // Stop after 2 pages of ONLY known ads

    try {
      final String baseUrl = buildAvtonetResultsUrl(config);
      debugPrint('[URL BUILDER SOURCE] url_builder.dart');
      debugPrint('[GENERATED URL] $baseUrl');

      pageLoop:
      for (int page = 1; page <= maxPageLimit; page++) {
        String pageUrl = baseUrl;
        if (pageUrl.contains('stran=')) {
          pageUrl = pageUrl.replaceFirst(RegExp(r'stran=\d+'), 'stran=$page');
        } else {
          pageUrl = '$pageUrl&stran=$page';
        }
        
        String? html;
        if (page == 1) {
          // Special handling for page 1: retry up to 3 times
          for (int retry = 0; retry <= 3; retry++) {
            try {
              debugPrint('[PAGE START] page=1 attempt=${retry + 1} url=$pageUrl');
              html = await _fetch(pageUrl, method: method);
              debugPrint('[PAGE SUCCESS] page=1');
              consecutivePageFailures = 0;
              break;
            } catch (e) {
              debugPrint('[PAGE FAILED] page=1 attempt=${retry + 1} error=$e');
              if (retry == 3) {
                debugPrint('[PAGINATION ABORTED] Page 1 failed after retries.');
                return ScrapeResult.failure('Page 1 failure: $e');
              }
              debugPrint('[PAGE RETRY] page=1 in 2s...');
              await Future.delayed(const Duration(seconds: 2));
            }
          }
        } else {
          try {
            debugPrint('[PAGE START] page=$page url=$pageUrl');
            html = await _fetch(pageUrl, method: method);
            debugPrint('[PAGE SUCCESS] page=$page');
            consecutivePageFailures = 0;
          } catch (e) {
            consecutivePageFailures++;
            debugPrint('[PAGE FAILED] page=$page consecutiveFailures=$consecutivePageFailures error=$e');
            if (consecutivePageFailures >= maxConsecutivePageFailures) {
              debugPrint('[PAGINATION ABORTED] Too many consecutive failures at page $page');
              break pageLoop;
            }
            debugPrint('[PAGE SKIPPED] Continuing to next page...');
            continue pageLoop;
          }
        }

        if (html == null) continue; // Should not happen due to logic above

        final List<CarListing> pageListings = await compute(_parseListingsInBackground, {
          'html': html,
          'configId': config.id,
          'seenIds': seenIds,
        });

        final int topAdsOnPage = pageListings.where((l) => l.isTopOffer).length;
        final int normalAdsOnPage = pageListings.length - topAdsOnPage;
        
        debugPrint('[PAGE RESULT] page=$page listings=${pageListings.length} (Normal: $normalAdsOnPage, Top: $topAdsOnPage)');
        
        if (pageListings.isEmpty) {
          if (html.length > 10000) {
            debugPrint('[PARSER FAILURE] HTML received but no listings found.');
          }
          break;
        }

        int newListingsOnPage = 0;
        int newNormalListingsOnPage = 0;
        
        for (var listing in pageListings) {
          if (totalChecked < 200) {
            debugPrint('[ID TRACE] id=${listing.id} page=$page count=$totalChecked');
          }
          debugPrint('[LISTING] id=${listing.id} title=${listing.title} isTop=${listing.isTopOffer}');
          if (!seenInThisScan.add(listing.id)) {
            debugPrint('[DUPLICATE IN CURRENT SCAN] id=${listing.id}');
            continue;
          }
          totalChecked++;

          final alreadySeen = seenIds.contains(listing.id);
          debugPrint('[DUPLICATE CHECK] id=${listing.id} existsInSeenIds=$alreadySeen');

          if (!alreadySeen) {
            allNewListings.add(listing);
            newListingsOnPage++;
            if (!listing.isTopOffer) {
              newNormalListingsOnPage++;
            }
            debugPrint('[NEW ID ADDED TO RESULTS] ${listing.id}');
          }
        }

        totalPages++;
        
        // P PAGINATION STOP LOGIC REFACTORED:
        // 1. Ignore TOP PONUDBA ads for caught-up calculations.
        // 2. Require minimum depth (4 pages AND 150 normal listings) before stopping.
        
        bool canTriggerStop = page >= 4 && totalChecked >= 150;
        
        if (newNormalListingsOnPage == 0 && normalAdsOnPage > 0) {
          consecutiveKnownPages++;
          debugPrint('[KNOWN PAGE COUNTER] page=$page consecutiveKnown=$consecutiveKnownPages (Stop triggerable: $canTriggerStop)');
          
          if (canTriggerStop && consecutiveKnownPages >= maxKnownPagesLimit) {
            debugPrint('[STOP REASON] Multiple pages with only known NORMAL ads. Caught up at page $page.');
            break pageLoop;
          }
        } else if (newNormalListingsOnPage > 0) {
          debugPrint('[PAGINATION DEBUG] Resetting known page counter (Found $newNormalListingsOnPage new normal ads)');
          consecutiveKnownPages = 0;
        }

        debugPrint('[PAGINATION DEBUG] page=$page totalNormalChecked=$totalChecked stopTriggerable=$canTriggerStop');
      }

      debugPrint('[SCAN SUMMARY] pages=$totalPages checked=$totalChecked new=${allNewListings.length}');
      return ScrapeResult.success(allNewListings, pages: totalPages, totalFound: totalChecked);

    } catch (e) {
      debugPrint('[SCAN ERROR] $e');
      return ScrapeResult.failure(e.toString());
    }
  }

/*
  String buildAvtonetResultsUrl_LOCAL(SearchConfig config) {
    const String baseSearchUrl = 'https://www.avto.net/Ads/results.asp?SID=3&KATEGORIJA=100';
    debugPrint('[BASE SEARCH URL] $baseSearchUrl');

    final sb = StringBuffer('$baseSearchUrl&znamka=${config.znamka}');
    if (config.model.isNotEmpty) sb.write('&model=${config.model}');
    if (config.oblika != '0') sb.write('&oblika=${config.oblika}');
    if (config.letnikMin != null) sb.write('&letnikMin=${config.letnikMin}');
    if (config.letnikMax != null) sb.write('&letnikMax=${config.letnikMax}');
    if (config.cenaMin != null) sb.write('&cenaMin=${config.cenaMin}');
    if (config.cenaMax != null) sb.write('&cenaMax=${config.cenaMax}');
    if (config.bencin != 0) sb.write('&bencin=${config.bencin}');
    if (config.menjalnik.isNotEmpty) sb.write('&menjalnik=${config.menjalnik}');
    if (config.kmMin != null) sb.write('&kmMin=${config.kmMin}');
    if (config.kmMax != null) sb.write('&kmMax=${config.kmMax}');
    if (config.mocMin != null) sb.write('&mocMin=${config.mocMin}');
    if (config.mocMax != null) sb.write('&mocMax=${config.mocMax}');
    
    sb.write('&SEARCH_ORDER=2&stran=1');
    final String url = sb.toString();
    debugPrint('[GENERATED URL] $url');
    return url;
  }
*/
}

/// Helper for compute()
List<CarListing> _parseListingsInBackground(Map<String, dynamic> data) {
  return AvtonetHtmlParser.parseListings(
    data['html'],
    searchConfigId: data['configId'],
    seenIds: data['seenIds'],
  );
}
