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
  
  // Persistent Cookie Storage
  final List<Cookie> _cookieJar = [];

  void _initController() {
    if (kIsWeb) return;
    debugPrint('[WEBVIEW CREATED]');
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
    // Attempt WebView fetch primarily for stability against 403.
    // In background mode, this ensures session/cookies are used even if fallback is needed.
    if (useWebView && _ready) {
      try {
        final html = await _fetchWithWebView(url);
        return html;
      } catch (e) {
        debugPrint('[SCRAPER] WebView fetch failed, falling back to HttpClient: $e');
      }
    }
    
    // Fallback or Direct fetch using simple HttpClient
    return await _fetchSimple(url, timeout: timeout);
  }

  Future<String> _fetchSimple(String url, {Duration? timeout}) async {
    final effectiveTimeout = timeout ?? WebviewStealthConfig.pageLoadTimeout;
    final client = HttpClient();
    client.connectionTimeout = effectiveTimeout;
    
    debugPrint('[HTTP CLIENT] Fetching: $url');
    try {
      final request = await client.getUrl(Uri.parse(url));
      WebviewStealthConfig.navigationHeaders(referer: 'https://www.avto.net/').forEach((k, v) => request.headers.set(k, v));
      
      final response = await request.close().timeout(effectiveTimeout);
      
      final contentType = response.headers.contentType?.toString() ?? 'unknown';
      final statusCode = response.statusCode;
      
      debugPrint('[HTTP CLIENT] Status: $statusCode');
      debugPrint('[HTTP CLIENT] Content-Type: $contentType');

      if (statusCode == 301 || statusCode == 302) {
        final location = response.headers.value('location');
        debugPrint('[HTTP CLIENT] Redirect detected to: $location');
      }

      final html = await response.transform(utf8.decoder).join();
      debugPrint('[HTTP CLIENT] Body Length: ${html.length}');
      debugPrint('[HTTP CLIENT] Body Start (300 chars): ${html.substring(0, html.length > 300 ? 300 : html.length)}');

      if (AvtonetHtmlParser.isCloudflareChallenge(html)) {
        debugPrint('[HTTP CLIENT] CLOUDFLARE CHALLENGE DETECTED IN BODY');
        throw CloudflareBlockedException('Cloudflare Challenge Detected');
      }

      if (statusCode != 200) {
        debugPrint('[HTTP CLIENT] Non-200 status code: $statusCode');
        if (statusCode == 403) {
           debugPrint('[HTTP CLIENT] 403 FORBIDDEN - Likely Cloudflare or IP block');
           throw CloudflareBlockedException('HTTP 403 Forbidden (Cloudflare)');
        }
        throw Exception('HTTP $statusCode');
      }

      client.close();
      return html;
    } catch (e) {
      debugPrint('[HTTP CLIENT ERROR] $e');
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
      debugPrint('[WEBVIEW PAGE LOADED] url=$url');
      
      // WAIT CONDITION: Wait for listing containers to appear
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

      final html = await controller.runJavaScriptReturningResult('document.documentElement.outerHTML') as String;
      String decodedHtml = _decodeWebViewHtml(html);
      
      if (AvtonetHtmlParser.isCloudflareChallenge(decodedHtml)) {
        debugPrint('[CLOUDFLARE DETECTED]');
        throw Exception('Cloudflare Challenge');
      }

      return decodedHtml;
    } catch (e) {
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
    if (useWebView) {
      debugPrint('[WEBVIEW SCRAPE START] configId=${config.id}');
    }
    debugPrint('[TRACE 10-A] scrapeSearchUrl starting. method=$method configId=${config.id} useWebView=$useWebView');
    final List<CarListing> allNewListings = [];
    int totalChecked = 0;
    int totalPages = 0;
    int consecutivePageFailures = 0;
    const int maxConsecutivePageFailures = 3;
    final Set<String> seenInThisScan = {};
    
    String stopReason = 'Unknown';

    try {
      final String baseUrl = buildAvtonetResultsUrl(config);
      debugPrint('[TRACE 10-B] scrapeSearchUrl: baseUrl generated: $baseUrl');

      pageLoop:
      for (int page = 1; page <= 50; page++) { // Hard cap at 50 to prevent infinite loops
        String pageUrl = baseUrl;
        if (pageUrl.contains('stran=')) {
          pageUrl = pageUrl.replaceFirst(RegExp(r'stran=\d+'), 'stran=$page');
        } else {
          pageUrl = '$pageUrl&stran=$page';
        }
        
        String? html;
        try {
          if (page == 1) {
            // Special handling for page 1: retry up to 3 times ONLY for non-Cloudflare errors
            for (int retry = 0; retry <= 3; retry++) {
              try {
                debugPrint('[TRACE 10-C] scrapeSearchUrl: fetching page $page, attempt $retry');
                html = await _fetch(pageUrl, method: method);
                consecutivePageFailures = 0;
                break;
              } on CloudflareBlockedException {
                debugPrint('[TRACE 10-D] scrapeSearchUrl: CloudflareBlockedException caught during fetch');
                rethrow;
              } catch (e) {
                if (retry == 3) throw e;
                debugPrint('[SCRAPER] Page 1 retry $retry due to error: $e');
                await Future.delayed(const Duration(seconds: 2));
              }
            }
          } else {
            html = await _fetch(pageUrl, method: method);
            consecutivePageFailures = 0;
          }
        } on CloudflareBlockedException {
          debugPrint('[TRACE 10-F] scrapeSearchUrl: returning CloudflareBlocked failure');
          return ScrapeResult.failure('Cloudflare Blocked', status: ScrapeStatus.cloudflareBlocked);
        } catch (e) {
          debugPrint('[TRACE 10-G] scrapeSearchUrl: caught exception during fetch: $e');
          consecutivePageFailures++;
          final errStr = e.toString().toLowerCase();
          
          if (errStr.contains('403') || errStr.contains('cloudflare')) {
            return ScrapeResult.failure('Cloudflare Blocked', status: ScrapeStatus.cloudflareBlocked);
          }
          
          if (page == 1) {
             return ScrapeResult.failure('Page 1 network error: $e', status: ScrapeStatus.networkError);
          }

          if (consecutivePageFailures >= maxConsecutivePageFailures) {
            stopReason = 'Too many consecutive page failures';
            break pageLoop;
          }
          continue pageLoop;
        }

        if (html == null) {
          debugPrint('[TRACE 10-H] scrapeSearchUrl: html is null for page $page');
          continue;
        }

        final List<CarListing> pageListings = await compute(_parseListingsInBackground, {
          'html': html,
          'configId': config.id,
          'seenIds': seenIds,
        });

        final pagination = await compute(_parsePaginationInBackground, html);
        // debugPrint('[PAGINATION] page=$page currentPage=${pagination.currentPage} totalPages=${pagination.totalPages} hasNext=${pagination.hasNext}');
        
        if (pageListings.isEmpty) {
          debugPrint('[TRACE 10-I] scrapeSearchUrl: pageListings empty for page $page');
          stopReason = 'Zero listings on page $page';
          break pageLoop;
        }

        int consecutiveSeen = 0;
        const int earlyStopThreshold = 15; // Stop scan after 15 consecutive already known ads

        for (var listing in pageListings) {
          if (!seenInThisScan.add(listing.id)) continue;
          totalChecked++;

          if (!seenIds.contains(listing.id)) {
            allNewListings.add(listing);
            consecutiveSeen = 0;
          } else {
            // Only increment consecutive counter if NOT a top offer, 
            // because top offers can appear anywhere regardless of age.
            if (!listing.isTopOffer) {
              consecutiveSeen++;
            }
          }

          if (consecutiveSeen >= earlyStopThreshold) {
            stopReason = 'Early stop: Found $consecutiveSeen consecutive known ads';
            break pageLoop;
          }
        }

        totalPages++;

        if (pageListings.length < 48) {
          stopReason = 'Last page detected (count=${pageListings.length} < 48)';
          break pageLoop;
        }

        if (!pagination.hasNext) {
          stopReason = 'End of results reached (no next page)';
          break pageLoop;
        }

        // Safety cap: Only use totalPages if it's greater than 1 and we've reached it.
        // If totalPages is 1 but hasNext is true, we trust hasNext (parser error).
        if (pagination.totalPages > 1 && page >= pagination.totalPages) {
          stopReason = 'Reached pagination limit (${pagination.totalPages})';
          break pageLoop;
        }
      }

      debugPrint('[PAGINATION SUMMARY]');
      debugPrint('pagesVisited=$totalPages');
      debugPrint('totalListings=$totalChecked');
      debugPrint('stopReason=$stopReason');
      
      if (useWebView) {
        debugPrint('[WEBVIEW SCRAPE FINISHED] configId=${config.id}');
      }

      final successResult = ScrapeResult.success(allNewListings, pages: totalPages, totalFound: totalChecked);
      debugPrint('[TRACE 10-J] scrapeSearchUrl success. totalFound=$totalChecked newListings=${allNewListings.length}');
      return successResult;

    } catch (e) {
      debugPrint('[TRACE 10-K] scrapeSearchUrl outer catch error: $e');
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

PaginationInfo _parsePaginationInBackground(String html) {
  return AvtonetHtmlParser.parsePagination(parse(html));
}
