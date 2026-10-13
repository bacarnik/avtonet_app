import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' show parse;
import '../models/car_listing.dart';

class PaginationInfo {
  const PaginationInfo({
    required this.hasNext,
    required this.currentPage,
    required this.totalPages,
    required this.totalItems,
  });
  final bool hasNext;
  final int currentPage;
  final int totalPages;
  final int totalItems;

  @override
  String toString() => 'hasNext=$hasNext current=$currentPage totalPages=$totalPages totalItems=$totalItems';
}

class AvtonetHtmlParser {
  static PaginationInfo parsePagination(dom.Document doc) {
    bool hasNext = false;
    int current = 1;
    int totalP = 1;
    int totalI = 0;

    try {
      // 1. Detect Next Page Button - excluding disabled links
      final nextLinks = doc.querySelectorAll('a.page-link:not(.disabled)');
      for (final link in nextLinks) {
        // Double check parent <li> for 'disabled' class (Bootstrap standard)
        final bool isParentDisabled = link.parent?.classes.contains('disabled') ?? false;
        if (isParentDisabled) continue;

        final ariaLabel = link.attributes['aria-label']?.toLowerCase() ?? '';
        final text = link.text.toLowerCase();

        if (ariaLabel == 'next' ||
            text.contains('naslednja') ||
            link.querySelector('i.fa-chevron-right') != null) {
          hasNext = true;
          break;
        }
      }

      // 2. Detect Current and Total Pages from pagination text "Stran 1 od 10"
      // Added support for \u00A0 (&nbsp;) which often appears in Release APK HTML
      final paginationText = doc.querySelector('.pagination, .pagination-container')?.text ?? '';
      final pageMatch = RegExp(r'Stran[\s\u00A0]+(\d+)[\s\u00A0]+od[\s\u00A0]+(\d+)', caseSensitive: false).firstMatch(paginationText);
      if (pageMatch != null) {
        current = int.tryParse(pageMatch.group(1)!) ?? 1;
        totalP = int.tryParse(pageMatch.group(2)!) ?? 1;
      }

      // 3. Detect total items "Število najdenih oglasov: 123"
      final itemsMatch = RegExp(r'najdenih oglasov:[\s\u00A0]*(\d+)', caseSensitive: false).firstMatch(doc.body?.text ?? '');
      if (itemsMatch != null) {
        totalI = int.tryParse(itemsMatch.group(1)!) ?? 0;
      }
    } catch (e) {
      debugPrint('[PARSER PAGINATION ERROR] $e');
    }

    return PaginationInfo(
      hasNext: hasNext,
      currentPage: current,
      totalPages: totalP,
      totalItems: totalI,
    );
  }

  static bool isCloudflareChallenge(String html) {
    final lower = html.toLowerCase();
    return lower.contains('cf-browser-verification') ||
        lower.contains('challenge-platform') ||
        lower.contains('just a moment') ||
        lower.contains('checking your browser') ||
        (lower.contains('attention required') && lower.contains('cloudflare'));
  }

  static List<dom.Element> findListingRows(dom.Document doc) {
    // RESTORED: Multi-layered row detection for stability.
    return doc.querySelectorAll('div.GO-Results-Row, div.GO-Results-Top-Ponudba').toList();
  }

  static List<CarListing> parseListings(
    String html, {
    String searchConfigId = '',
    String brand = '',
    String model = '',
    String url = '',
    List<String> seenIds = const [],
  }) {
    if (isCloudflareChallenge(html)) return [];

    final doc = parse(html);
    final rows = findListingRows(doc);

    final results = <CarListing>[];
    final seenIdsInBatch = <String>{};

    for (int i = 0; i < rows.length; i++) {
      final element = rows[i];
      String currentIdForError = 'unknown';
      try {
        final titleEl = element.querySelector('div.GO-Results-Naziv');
        final anchorEl = element.querySelector('a.stretched-link');
        final bool isTopOffer = element.attributes['class']?.contains('Top-Ponudba') ??
                                element.querySelector('.GO-Results-Top-Ponudba') != null;

        String title = titleEl?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
        String href = anchorEl?.attributes['href'] ?? '';

        if (href.isEmpty) {
          final fallbackAnchor = element.querySelector('a[href*="details.asp"]');
          href = fallbackAnchor?.attributes['href'] ?? '';
          if (title.isEmpty) {
            title = fallbackAnchor?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
          }
        }

        if (href.isEmpty) continue;

        String link = href.startsWith('http')
            ? href
            : 'https://www.avto.net${href.startsWith('/') ? '' : '/'}$href';

        final idMatch = RegExp(r'id=(\d+)').firstMatch(link);
        final id = idMatch?.group(1);

        if (id == null) continue;
        currentIdForError = id;

        if (title.isEmpty || title.toLowerCase() == 'oglas') {
          final uri = Uri.tryParse(link);
          if (uri != null && uri.queryParameters.containsKey('display')) {
            title = Uri.decodeComponent(uri.queryParameters['display']!).split(':')[0].trim();
          }
        }

        if (title.isEmpty) title = 'Vozilo $id';

        if (seenIdsInBatch.contains(id)) continue;
        seenIdsInBatch.add(id);

        final priceEl = element.querySelector('.GO-Results-Row-PRICE, .Price, .price, .ResultRowPrice');
        String price = priceEl?.text.trim() ?? '';
        if (price.isEmpty) {
          final priceMatch = RegExp(r'[\d.]+\s*€').firstMatch(element.text);
          price = priceMatch?.group(0) ?? 'Po dogovoru';
        }

        final attrEl = element.querySelector('.GO-Results-Row-Data-Data, .GO-Results-Row-ATTRIBUTES, .GO-Results-Row-Data-Top');
        final scopeText = attrEl?.text ?? element.text;

        final year = _extractYear(scopeText);
        final mileage = _extractMileage(scopeText, element, year);
        final fuel = _extractFuel(scopeText);
        final bodyType = _detectBodyType(title, scopeText);
        final power = _extractPower(scopeText);
        final imageUrl = _extractImageUrl(element);

        results.add(CarListing(
          id: id,
          title: title,
          price: price,
          link: link,
          imageUrl: imageUrl,
          year: year,
          mileage: mileage,
          fuel: fuel,
          searchConfigId: searchConfigId,
          foundAt: DateTime.now(),
          bodyType: bodyType,
          powerKw: power.kw,
          powerHp: power.hp,
          isTopOffer: isTopOffer,
        ));
      } catch (e) {
        debugPrint('[PARSER ERROR] $currentIdForError error: $e');
        continue;
      }
    }

    return results;
  }

  static String _extractYear(String text) {
    try {
      final reg = RegExp(r'(?:letnik|1\.registracija|registracija)[^\d]*(\d{4})', caseSensitive: false);
      final m = reg.firstMatch(text);
      if (m != null) return m.group(1)!;
      final yearOnly = RegExp(r'\b(19|20)\d{2}\b').firstMatch(text);
      return yearOnly?.group(0) ?? '';
    } catch (_) { return ''; }
  }

  static String _extractMileage(String text, dom.Element element, String year) {
    try {
      final kmMatch = RegExp(r'(\d[\d\s.]*)\s*km', caseSensitive: true).firstMatch(text);
      String matchedKm = kmMatch?.group(1) ?? '';
      if (kmMatch != null) {
        final String matchSegment = kmMatch.group(0)!;
        if (matchSegment.contains('KM') || matchSegment.contains('PS') || matchSegment.contains('HP') || matchSegment.toLowerCase().contains('kw')) {
           return '';
        }
        final rawValue = matchedKm.replaceAll(RegExp(r'[\s.]'), '');
        final int kmValue = int.tryParse(rawValue) ?? 0;
        final int carYear = int.tryParse(year) ?? DateTime.now().year;
        final int age = DateTime.now().year - carYear;
        if (age > 2 && kmValue < 500 && kmValue > 0) return '';
        return '$rawValue km';
      }
      return '';
    } catch (e) { return ''; }
  }

  static String _extractFuel(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('diesel') || lower.contains('dizel')) return 'Diesel';
    if (lower.contains('bencin')) return 'Bencin';
    if (lower.contains('hibrid')) return 'Hibrid';
    if (lower.contains('elektro') || lower.contains('električni')) return 'Elektro';
    if (lower.contains('lpg')) return 'LPG';
    return '';
  }

  static ({int kw, int hp}) _extractPower(String text) {
    try {
      final kwMatch = RegExp(r'(\d+)\s*kW', caseSensitive: false).firstMatch(text);
      int kw = kwMatch != null ? (int.tryParse(kwMatch.group(1)!) ?? 0) : 0;
      final hpMatch = RegExp(r'(\d+)\s*(?:KM|PS|HP)', caseSensitive: true).firstMatch(text);
      int hp = hpMatch != null ? (int.tryParse(hpMatch.group(1)!) ?? 0) : 0;
      if (kw == 0 && hp > 0) kw = (hp / 1.341).round();
      if (hp == 0 && kw > 0) hp = (kw * 1.341).round();
      return (kw: kw, hp: hp);
    } catch (_) { return (kw: 0, hp: 0); }
  }

  static String _extractImageUrl(dom.Element element) {
    final imgEl = element.querySelector('.GO-Results-Photo img, .ResultsPhoto img, img');
    if (imgEl == null) return '';

    final candidates = <String?>[
      imgEl.attributes['data-src'],
      imgEl.attributes['data-original'],
      imgEl.attributes['srcset']?.split(' ').first,
      imgEl.attributes['src'],
    ];

    for (final raw in candidates) {
      if (raw == null) continue;
      final trimmed = raw.trim();
      if (trimmed.isEmpty) continue;

      final lower = trimmed.toLowerCase();
      if (lower.contains('blank') ||
          lower.contains('placeholder') ||
          lower.startsWith('data:image') ||
          lower.contains('no_photo') ||
          lower.contains('no-photo') ||
          lower.contains('clear.gif') ||
          lower.contains('spacer.gif')) {
        continue;
      }

      return _normalizeImageUrl(trimmed);
    }

    return '';
  }

  static String _normalizeImageUrl(String url) {
    if (url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    if (url.startsWith('//')) {
      return 'https:$url';
    }
    if (url.startsWith('/')) {
      return 'https://www.avto.net$url';
    }
    return 'https://www.avto.net/$url';
  }

  static int _detectBodyType(String title, String scope) {
    final titleLower = title.toLowerCase();
    final text = '$title $scope'.toLowerCase();

    // 1. Explicit body type keywords in title have highest priority
    if (titleLower.contains('coupe') || titleLower.contains('coupé')) return 16;
    if (titleLower.contains('cabrio') || titleLower.contains('kabriolet') ||
        titleLower.contains('spider') || titleLower.contains('roadster') ||
        titleLower.contains('convertible')) return 17;
    if (titleLower.contains('suv') || titleLower.contains('terensko') ||
        titleLower.contains('crossover') || titleLower.contains('off-road')) return 15;
    if (titleLower.contains('karavan') || titleLower.contains('touring') ||
        titleLower.contains('variant') || titleLower.contains('avant') ||
        titleLower.contains('shooting brake') || titleLower.contains('wagon')) return 13;
    if (titleLower.contains('limuzina') || titleLower.contains('sedan') ||
        titleLower.contains('saloon')) return 11;
    if (titleLower.contains('enoprostorec') || titleLower.contains('mpv') ||
        titleLower.contains('monovolumen') || titleLower.contains('minivan')) return 14;
    if (titleLower.contains('pick-up') || titleLower.contains('pickup') ||
        titleLower.contains('poltovornjak')) return 18;

    // 2. Specific body types checked on combined text
    // Coupe
    if (text.contains('coupe') || text.contains('coupé')) return 16;

    // Cabrio / Kabriolet / Spider / Roadster
    if (text.contains('cabrio') || text.contains('kabriolet') || text.contains('spider') ||
        text.contains('convertible') || text.contains('roadster')) return 17;

    // SUV / Terensko / Crossover / 4x4
    if (text.contains('suv') || text.contains('terensko') || text.contains('cross') ||
        text.contains('off-road') || text.contains('4x4') || text.contains('allroad') ||
        text.contains('crossover') || text.contains('stirikolesni')) return 15;

    // Karavan / Station Wagon
    if (text.contains('karavan') || text.contains('touring') || text.contains('variant') ||
        text.contains('avant') || text.contains('wagon') ||
        text.contains('shooting brake') || (text.contains('kombi') && !text.contains('kombilimuzina'))) return 13;

    // Limuzina / Sedan / Saloon
    if (text.contains('limuzina') || text.contains('sedan') || text.contains('saloon') ||
        text.contains('stopenjska') || text.contains('tridelna')) return 11;

    // Enoprostorec / MPV / Van / Minivan
    if (text.contains('enoprostorec') || text.contains('mpv') || text.contains('monovolumen') ||
        text.contains('grand') || text.contains('space') || text.contains('minivan')) return 14;

    // Pick-up / Poltovornjak
    if (text.contains('pick-up') || text.contains('poltovornjak') || text.contains('pickup')) return 18;

    // Delivery / Cargo / Furgon
    if (text.contains('tovorno') || text.contains('furgon')) return 14;

    // Hatchback / Kombilimuzina / Compact (checked last as generic fallback)
    if (text.contains('hatchback') || text.contains('kombilimuzina') || text.contains('compact') ||
        text.contains('sportback') || text.contains(' 3 vrat') || text.contains(' 5 vrat') ||
        text.contains('berlina') || text.contains('clio') || text.contains('megane') ||
        text.contains('golf') || text.contains('polo') || text.contains('astra') ||
        text.contains('corsa') || text.contains('fiesta') || text.contains('focus') ||
        text.contains('i20') || text.contains('i30') || text.contains('a3') ||
        text.contains('yaris') || text.contains('auris')) return 12;

    return 0;
  }

  static String _bodyTypeToLabel(int code) {
    switch (code) {
      case 11: return 'Limuzina';
      case 12: return 'Hatchback';
      case 13: return 'Karavan';
      case 14: return 'Enoprostorec';
      case 15: return 'SUV';
      case 16: return 'Coupe';
      case 17: return 'Cabrio';
      case 18: return 'Pick-up';
      default: return 'Neznano';
    }
  }
}
