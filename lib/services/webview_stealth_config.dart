/// Stealth HTTP glave in konstante za obhod Cloudflare / ORB na Android 14.
abstract final class WebviewStealthConfig {
  static const List<String> userAgents = [
    'Mozilla/5.0 (Linux; Android 14; Redmi Note 14 Pro+ 5G) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36',
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1',
  ];

  static String get randomUserAgent => (List.from(userAgents)..shuffle()).first;

  static const String userAgent = 'Mozilla/5.0 (Linux; Android 14; Redmi Note 14 Pro+ 5G) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

  static const Duration cloudflareSettleDelay = Duration(seconds: 5);
  static const Duration pageLoadTimeout = Duration(seconds: 45);
  static const int maxFetchAttempts = 3;

  static const int errorCodeOrb = -1;
  static const int errorCodeConnectionClosed = -6;

  /// Avtentične glave za navigacijo (Chrome 124, sl-SI).
  static Map<String, String> navigationHeaders({String? referer}) {
    final headers = <String, String>{
      'User-Agent': userAgent,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
      'Accept-Language': 'sl-SI,sl;q=0.9,en-GB;q=0.8,en;q=0.7',
      'Connection': 'keep-alive',
      'Cache-Control': 'max-age=0',
      'Upgrade-Insecure-Requests': '1',
      'Sec-Fetch-Site': 'none',
      'Sec-Fetch-Mode': 'navigate',
      'Sec-Fetch-User': '?1',
      'Sec-Fetch-Dest': 'document',
    };
    // Note: Accept-Encoding is omitted to let HttpClient handle gzip/deflate automatically.
    // Adding 'br' manually would cause decoding errors in Dart HttpClient.
    if (referer != null && referer.isNotEmpty) {
      headers['Referer'] = referer;
      headers['Sec-Fetch-Site'] = 'same-origin';
    }
    return headers;
  }

  /// JavaScript: potrdi localStorage/sessionStorage pred ekstrakcijo HTML.
  static const String storageProbeScript = '''
(function() {
  try {
    localStorage.setItem('_avtonet_probe', '1');
    sessionStorage.setItem('_avtonet_probe', '1');
    return 'ok';
  } catch (e) {
    return 'err:' + e;
  }
})();
''';

  static const String extractHtmlScript =
      'document.documentElement.outerHTML';
}
