import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' show parse;
import '../models/car_listing.dart';

class AvtonetHtmlParser {
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
    // Log candidate selectors found in the page.
    final hasMain = doc.querySelector('.GO-Results-Main') != null;
    final hasFormAds = doc.querySelector('form#Ads') != null;
    final rowCount = doc.querySelectorAll('div.GO-Results-Row').length;
    final topPonudbaCount = doc.querySelectorAll('div.GO-Results-Top-Ponudba').length;
    
    debugPrint('[PARSER] Candidates: hasMain=$hasMain hasFormAds=$hasFormAds rowCount=$rowCount topPonudbaCount=$topPonudbaCount');

    final rows = doc.querySelectorAll('div.GO-Results-Row, div.GO-Results-Top-Ponudba');
    
    if (rows.isEmpty) {
      debugPrint('[PARSER FAILURE] HTML structure mismatch. Zero listing rows found.');
      
      if (doc.body == null) {
        debugPrint('[PARSER] BODY IS NULL');
      } else {
        debugPrint(
          '[PARSER BODY PREVIEW] ${doc.body!.outerHtml.substring(0, min(5000, doc.body!.outerHtml.length))}',
        );
      }
    } else {
      debugPrint('[PARSER] Found ${rows.length} listing nodes');
    }

    return rows.toList();
  }

  static List<CarListing> parseListings(
    String html, {
    String searchConfigId = '',
    String brand = '',
    String model = '',
    String url = '',
    List<String> seenIds = const [], // ADDED: For dynamic "new" detection logging
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

        debugPrint('[PARSER] Extracted title=$title');
        debugPrint('[PARSER] Extracted url=$link');
        debugPrint('[PARSER] Extracted id=$id');

        if (title.isEmpty || title.toLowerCase() == 'oglas') {
          final uri = Uri.tryParse(link);
          if (uri != null && uri.queryParameters.containsKey('display')) {
            title = Uri.decodeComponent(uri.queryParameters['display']!).split(':')[0].trim();
          }
        }

        if (title.isEmpty) title = 'Vozilo $id';

        if (seenIdsInBatch.contains(id)) continue;
        seenIdsInBatch.add(id);

        final bool isNewListing = !seenIds.contains(id);

        // LOGGING AS REQUESTED: [LISTING] id=xxxxx new=true topOffer=true
        debugPrint('[LISTING] id=$id new=$isNewListing topOffer=$isTopOffer title=$title');

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

        if (bodyType == 0) {
          final String snippet = element.text.replaceAll(RegExp(r'\s+'), ' ').trim();
          final String limitedSnippet = snippet.length > 300 ? snippet.substring(0, 300) : snippet;
          debugPrint('[BODY TYPE PARSE FAILED] listing=$title id=$id content=$limitedSnippet');
        }

        var imageUrl = '';
        final imgEl = element.querySelector('.GO-Results-Photo img, .ResultsPhoto img, img');
        if (imgEl != null) {
          imageUrl = imgEl.attributes['src'] ?? 
                     imgEl.attributes['data-src'] ?? 
                     imgEl.attributes['data-original'] ?? 
                     imgEl.attributes['srcset']?.split(' ').first ??
                     '';
          if (imageUrl.isNotEmpty && !imageUrl.startsWith('http')) {
            imageUrl = 'https://www.avto.net${imageUrl.startsWith('/') ? '' : '/'}$imageUrl';
          }
        }

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

  static int _detectBodyType(String title, String scope) {
    final text = '$title $scope'.toLowerCase();
    
    // 1. Karavan / Station Wagon
    if (text.contains('karavan') || text.contains('touring') || text.contains('variant') || 
        text.contains('avant') || text.contains('sw') || text.contains('wagon') || 
        text.contains('shooting brake') || (text.contains('kombi') && !text.contains('kombilimuzina'))) return 13;
    
    // 2. Hatchback / Kombilimuzina / Compact
    if (text.contains('hatchback') || text.contains('kombilimuzina') || text.contains('compact') || 
        text.contains('sportback') || text.contains(' 3 vrat') || text.contains(' 5 vrat') || 
        text.contains('berlina')) return 12;
    
    // 3. Limuzina / Sedan / Saloon
    if (text.contains('limuzina') || text.contains('sedan') || text.contains('saloon') || 
        text.contains('stopenjska') || text.contains('tridelna')) return 11;
    
    // 4. SUV / Terensko / Crossover / 4x4
    if (text.contains('suv') || text.contains('terensko') || text.contains('cross') || 
        text.contains('off-road') || text.contains('4x4') || text.contains('allroad') ||
        text.contains('crossover') || text.contains('stirikolesni')) return 15;
    
    // 5. Coupe
    if (text.contains('coupe') || text.contains('coupé')) return 16;
    
    // 6. Cabrio / Kabriolet / Spider / Roadster
    if (text.contains('cabrio') || text.contains('kabriolet') || text.contains('spider') || 
        text.contains('convertible') || text.contains('roadster')) return 17;
    
    // 7. Enoprostorec / MPV / Van / Minivan
    if (text.contains('enoprostorec') || text.contains('mpv') || text.contains('monovolumen') || 
        text.contains('grand') || text.contains('space') || text.contains('minivan')) return 14;
    
    // 8. Pick-up / Poltovornjak
    if (text.contains('pick-up') || text.contains('poltovornjak') || text.contains('pickup')) return 18;

    // 9. Delivery / Cargo / Furgon
    if (text.contains('tovorno') || text.contains('furgon') || text.contains('van')) return 14;

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
