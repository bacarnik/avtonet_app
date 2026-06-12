import '../models/car_listing.dart';
import '../models/search_config.dart';
import '../utils/string_utils.dart';
import '../data/body_types.dart';
import 'package:flutter/foundation.dart';

class FilterMatchResult {
  const FilterMatchResult({required this.isMatch, this.reason = ''});
  final bool isMatch;
  final String reason;
}

class FilterMatcher {
  static FilterMatchResult matches(CarListing listing, SearchConfig config) {
    // 1. Brand matching
    if (config.znamka.isNotEmpty) {
      if (!StringUtils.contains(listing.title, config.znamka)) {
        debugPrint('[FILTER MISMATCH] Expected=${config.znamka} Got=${listing.title}');
        return FilterMatchResult(isMatch: false, reason: 'Znamka mismatch: ${listing.title} vs ${config.znamka}');
      }
    }

    // 2. Model matching
    if (config.model.isNotEmpty) {
      bool modelMatch = StringUtils.contains(listing.title, config.model);
      
      // LENIENT MATCHING for BMW (Serija 3 -> "320", "318", " 3 ")
      if (!modelMatch && config.znamka.toLowerCase() == 'bmw' && config.model.toLowerCase().contains('serija')) {
        final parts = config.model.split(' ');
        if (parts.length >= 2) {
          final seriesNum = parts.last;
          // Matches "320", "330", or " 3 "
          final reg = RegExp(' $seriesNum\\d*\\b|\\b$seriesNum\\d* ');
          modelMatch = listing.title.contains(reg) || listing.title.contains(' $seriesNum ');
        }
      }

      // LENIENT MATCHING for Mercedes-Benz (Razred C -> " C ", "CLA", etc. is harder, but let's try)
      if (!modelMatch && config.znamka.toLowerCase() == 'mercedes-benz' && config.model.toLowerCase().contains('razred')) {
        final seriesChar = config.model.split(' ').last;
        modelMatch = listing.title.contains(' $seriesChar ') || listing.title.startsWith('$seriesChar ');
      }

      if (!modelMatch) {
        debugPrint('[FILTER MISMATCH] Model mismatch. Expected=${config.znamka} ${config.model} Got=${listing.title}');
        return FilterMatchResult(isMatch: false, reason: 'Model mismatch: ${listing.title} vs ${config.model}');
      }
    }

    // 3. Price matching
    final priceInt = _extractPrice(listing.price);
    if (priceInt != null) {
      if (config.cenaMin != null && priceInt < config.cenaMin!) {
        return FilterMatchResult(isMatch: false, reason: 'Cena prenizka: $priceInt < ${config.cenaMin}');
      }
      if (config.cenaMax != null && priceInt > config.cenaMax!) {
        return FilterMatchResult(isMatch: false, reason: 'Cena previsoka: $priceInt > ${config.cenaMax}');
      }
    }

    // 4. Year matching
    final yearInt = int.tryParse(listing.year);
    if (yearInt != null) {
      if (config.letnikMin != null && yearInt < config.letnikMin!) {
        return FilterMatchResult(isMatch: false, reason: 'Letnik premalo: $yearInt < ${config.letnikMin}');
      }
      if (config.letnikMax != null && yearInt > config.letnikMax!) {
        return FilterMatchResult(isMatch: false, reason: 'Letnik preveč: $yearInt > ${config.letnikMax}');
      }
    }

    // 5. Fuel matching
    if (config.bencin != 0) {
      if (listing.fuel.isNotEmpty) {
        final fuelNorm = StringUtils.normalize(listing.fuel);
        if (config.bencin == 1 && !fuelNorm.contains('bencin')) return FilterMatchResult(isMatch: false, reason: 'Gorivo ni bencin');
        if (config.bencin == 2 && !(fuelNorm.contains('diesel') || fuelNorm.contains('dizel'))) return FilterMatchResult(isMatch: false, reason: 'Gorivo ni diesel');
        if (config.bencin == 3 && !fuelNorm.contains('lpg')) return FilterMatchResult(isMatch: false, reason: 'Gorivo ni lpg');
        if (config.bencin == 4 && !fuelNorm.contains('hibrid')) return FilterMatchResult(isMatch: false, reason: 'Gorivo ni hibrid');
        if (config.bencin == 5 && !(fuelNorm.contains('elektro') || fuelNorm.contains('elektricni'))) return FilterMatchResult(isMatch: false, reason: 'Gorivo ni elektro');
      }
    }
    
    // 6. POWER FILTERING
    final powerMatch = _matchesPower(listing, config);
    if (!powerMatch.isMatch) return powerMatch;

    // 7. SECONDARY BODY-TYPE VALIDATOR (STRICT)
    final secondaryRes = _validateSecondaryBodyTypeStrict(listing, config);
    if (!secondaryRes.isMatch) {
      debugPrint('[FILTER MISMATCH] Expected (Code)=${config.oblika} Detected=${listing.bodyType} Listing=${listing.title}');
      return secondaryRes;
    }

    return const FilterMatchResult(isMatch: true);
  }

  static FilterMatchResult _matchesPower(CarListing listing, SearchConfig config) {
    // If filter units is KM, we might want to compare with powerHp, but usually filters are in kW
    // config.mocMin and mocMax are in powerUnit ('kW' or 'KM').
    
    int minVal = config.mocMin ?? 0;
    int maxVal = config.mocMax ?? 9999;
    
    int listingVal = (config.powerUnit == 'KM') ? listing.powerHp : listing.powerKw;

    // Fallback if one value is missing on listing
    if (listingVal == 0) {
      if (config.powerUnit == 'KM' && listing.powerKw > 0) {
        listingVal = (listing.powerKw * 1.341).round();
      } else if (config.powerUnit == 'kW' && listing.powerHp > 0) {
        listingVal = (listing.powerHp / 1.341).round();
      }
    }

    bool isMatch = true;
    if (listingVal > 0) {
       if (minVal > 0 && listingVal < minVal) isMatch = false;
       if (maxVal < 9999 && listingVal > maxVal) isMatch = false;
    }
    
    debugPrint('[POWER FILTER] listingPowerKw=${listing.powerKw} listingPowerHp=${listing.powerHp} filterMin=$minVal filterMax=$maxVal match=$isMatch');

    if (!isMatch) {
      return FilterMatchResult(isMatch: false, reason: 'Power mismatch: $listingVal ${config.powerUnit} not in range $minVal - $maxVal');
    }

    return const FilterMatchResult(isMatch: true);
  }

  static FilterMatchResult _validateSecondaryBodyTypeStrict(CarListing listing, SearchConfig config) {
    if (config.oblika == '0' || config.oblika.isEmpty) return const FilterMatchResult(isMatch: true);

    final title = listing.title.toLowerCase();
    final selectedCodes = config.oblika.split(',').map((e) => int.tryParse(e)).whereType<int>().toList();

    if (listing.bodyType != 0 && !selectedCodes.contains(listing.bodyType)) {
       return FilterMatchResult(isMatch: false, reason: 'Strict body type mismatch: Detected ${listing.bodyType}, Expected one of ${config.oblika}');
    }

    for (final code in selectedCodes) {
      if (code == 16) { // COUPE
        if (title.contains('coupe') || title.contains('coupé')) continue; 
        if (title.contains('limuzina') || title.contains('sedan') || title.contains('karavan') || 
            title.contains('touring') || title.contains('avant') || title.contains('variant') || 
            title.contains('hatchback')) {
          return FilterMatchResult(isMatch: false, reason: 'Keyword blocked non-coupe: $title');
        }
      }
      if (code == 13) { // KARAVAN
        if (title.contains('sedan') || title.contains('coupe') || title.contains('coupé') || title.contains('cabrio')) {
          return FilterMatchResult(isMatch: false, reason: 'Keyword blocked non-karavan: $title');
        }
      }
      if (code == 12) { // HATCHBACK
        if (title.contains('touring') || title.contains('avant') || title.contains('variant') || title.contains('karavan')) {
          return FilterMatchResult(isMatch: false, reason: 'Keyword blocked non-hatchback: $title');
        }
      }
    }

    return const FilterMatchResult(isMatch: true);
  }

  static int? _extractPrice(String text) {
    final digits = text.replaceAll(RegExp(r'\D'), '');
    return int.tryParse(digits);
  }
}
