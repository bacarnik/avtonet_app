import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' show parse;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/avtonet_catalog_models.dart';
import 'avtonet_scraper_service.dart';

class AvtonetCatalogService {
  AvtonetCatalogService(this._scraper);

  final AvtonetScraperService _scraper;

  static const String _keyCatalog = 'avtonet_catalog_v3';
  static const String _searchUrl = 'https://www.avto.net/Ads/search.asp?SID=10000';

  AvtonetCatalogData? _cachedCatalog;

  Future<AvtonetCatalogData?> getCatalog({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedCatalog != null) {
      return _cachedCatalog;
    }

    if (!forceRefresh) {
      final local = await _loadFromLocal();
      if (local != null) {
        final age = DateTime.now().difference(local.lastUpdated);
        if (age.inDays < 7 && local.brands.isNotEmpty) {
          _cachedCatalog = local;
          return local;
        }
      }
    }

    try {
      final html = await _fetchSearchPage();
      
      if (html != null && html.isNotEmpty) {
        final data = await compute(_parseCatalogInBackground, html);

        if (data.brands.isNotEmpty) {
          await _saveToLocal(data);
          _cachedCatalog = data;
          debugPrint('[INFO] Avtonet catalog updated from network (${data.brands.length} brands)');
          return data;
        }
      }
    } catch (e) {
      debugPrint('[ERROR] Catalog refresh failed: $e');
    }

    final fallback = _cachedCatalog ?? await _loadFromLocal();
    return fallback;
  }

  Future<String?> _fetchSearchPage() async {
    try {
      return await _scraper.fetchHtml(_searchUrl);
    } catch (e) {
      debugPrint('[ERROR] Catalog fetch failed: $e');
      return null;
    }
  }

  Future<void> _saveToLocal(AvtonetCatalogData data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyCatalog, jsonEncode(data.toJson()));
    } catch (e) {
      debugPrint('[ERROR] Failed to save catalog: $e');
    }
  }

  Future<AvtonetCatalogData?> _loadFromLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyCatalog);
      if (raw == null) return null;
      return AvtonetCatalogData.fromJson(jsonDecode(raw));
    } catch (e) {
      return null;
    }
  }
}

AvtonetCatalogData _parseCatalogInBackground(String html) {
  final doc = parse(html);

  final List<AvtonetBrand> brands = [];
  final makeSelect = doc.querySelector('select[name="znamka"]') ?? 
                     doc.querySelector('select#znamka') ??
                     doc.querySelector('select[name*="znamka"]');

  if (makeSelect != null) {
    final options = makeSelect.querySelectorAll('option');
    
    for (final opt in options) {
      final value = opt.attributes['value'] ?? '';
      final displayName = opt.text.replaceAll('\u00A0', ' ').trim();
      
      if (value.isEmpty || 
          opt.attributes.containsKey('disabled') || 
          displayName.startsWith('-') ||
          displayName.contains('izberi') ||
          displayName.toLowerCase().contains('vse znamke')) continue;
      
      if (brands.any((b) => b.value == value)) continue;
      
      brands.add(AvtonetBrand(
        displayName: displayName,
        value: value,
        id: opt.attributes['foo'],
      ));
    }
  }

  final Map<String, List<AvtonetModel>> modelsByBrand = {};
  // More robust selector for models
  final modelSelect = doc.querySelector('#model') ?? 
                      doc.querySelector('select[name="model"]');

  if (modelSelect != null) {
    final options = modelSelect.querySelectorAll('option');
    debugPrint('[MODELS] Found ${options.length} options in model select');

    for (final opt in options) {
      final value = opt.attributes['value'] ?? '';
      // Avto.net uses brand name in class attribute for model options
      final brandKeyRaw = opt.attributes['class'] ?? ''; 
      
      if (value.isEmpty || brandKeyRaw.isEmpty || 
          value == 'modela ni na seznamu' || 
          opt.text.toLowerCase().contains('izberite model')) continue;

      // Robust key normalization for cross-isolate matching
      final brandKey = _normalizeKey(brandKeyRaw);

      final rawText = opt.text;
      final isIndented = rawText.startsWith('\u00A0') || rawText.startsWith(' ');
      final isGroup = brandKeyRaw.toLowerCase().contains('vsi') || value.endsWith(' (vsi)');

      String displayName = rawText.replaceAll('\u00A0', '').trim();
      String searchValue = '';
      String? subModelGroup;
      String? modelId;

      if (isGroup) {
        subModelGroup = value.replaceAll(' (vsi)', '').trim();
        searchValue = subModelGroup.toLowerCase().contains('serija') 
            ? '$subModelGroup:' 
            : subModelGroup;
      } else if (isIndented) {
        searchValue = value;
      } else {
        if (value.toLowerCase().contains('serija')) {
          subModelGroup = value;
          searchValue = '$value:';
          modelId = null;
        } else {
          modelId = value;
        }
      }

      final model = AvtonetModel(
        displayName: displayName,
        searchValue: searchValue,
        modelId: modelId,
        subModelGroup: subModelGroup,
      );

      modelsByBrand.putIfAbsent(brandKey, () => []).add(model);
    }
  }

  debugPrint('[INFO] Parsed ${brands.length} brands and ${modelsByBrand.length} model groups');
  return AvtonetCatalogData(
    brands: brands,
    modelsByBrand: modelsByBrand,
    lastUpdated: DateTime.now(),
  );
}

/// Centralized key normalization for brand matching.
String _normalizeKey(String key) {
  return key.toLowerCase()
      .replaceAll('znamka_', '') // Handle "znamka_24" format if used
      .replaceAll('š', 's').replaceAll('č', 'c').replaceAll('ž', 'z')
      .replaceAll('ć', 'c').replaceAll('đ', 'd')
      .replaceAll(RegExp(r'[^a-z0-9]'), '')
      .trim();
}
