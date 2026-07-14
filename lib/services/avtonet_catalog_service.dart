import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' show parse;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/avtonet_catalog_models.dart';
import 'webview_stealth_config.dart';
import '../utils/logger.dart';

class AvtonetCatalogService {
  static const String _keyCatalog = 'avtonet_catalog_v3';
  static const String _searchUrl = 'https://www.avto.net/Ads/search.asp?SID=10000';

  AvtonetCatalogData? _cachedCatalog;

  Future<AvtonetCatalogData?> getCatalog({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedCatalog != null) return _cachedCatalog;

    if (!forceRefresh) {
      final local = await _loadFromLocal();
      if (local != null) {
        final age = DateTime.now().difference(local.lastUpdated);
        if (age.inDays < 7) {
          _cachedCatalog = local;
          return local;
        }
      }
    }

    try {
      final html = await _fetchSearchPage();
      if (html == null) throw Exception('Failed to fetch search page');

      final data = await compute(_parseCatalogInBackground, html);
      if (data.brands.isNotEmpty) {
        await _saveToLocal(data);
        _cachedCatalog = data;
        AppLogger.info('[CATALOG]', 'Catalog updated (${data.brands.length} brands)');
        return data;
      }
    } catch (e) {
      AppLogger.warn('[CATALOG]', 'Failed to refresh catalog: $e');
      final fallback = _cachedCatalog ?? await _loadFromLocal();
      return fallback;
    }
    return null;
  }

  Future<String?> _fetchSearchPage() async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(Uri.parse(_searchUrl));
      WebviewStealthConfig.navigationHeaders().forEach((k, v) => request.headers.set(k, v));
      
      final response = await request.close().timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return null;

      final html = await response.transform(utf8.decoder).join();
      return html;
    } catch (e) {
      return null;
    } finally {
      client.close();
    }
  }

  Future<void> _saveToLocal(AvtonetCatalogData data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCatalog, jsonEncode(data.toJson()));
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
  final makeSelect = doc.querySelector('select[name="znamka"]');
  if (makeSelect != null) {
    final options = makeSelect.querySelectorAll('option');
    for (final opt in options) {
      final value = opt.attributes['value'] ?? '';
      final displayName = opt.text.trim();
      if (value.isEmpty || opt.attributes.containsKey('disabled') || displayName.startsWith('-')) continue;
      if (brands.any((b) => b.value == value)) continue;
      
      brands.add(AvtonetBrand(
        displayName: displayName,
        value: value,
        id: opt.attributes['foo'],
      ));
    }
  }

  final Map<String, List<AvtonetModel>> modelsByBrand = {};
  final modelSelect = doc.querySelector('select[id="model"]');
  if (modelSelect != null) {
    final options = modelSelect.querySelectorAll('option');
    for (final opt in options) {
      final value = opt.attributes['value'] ?? '';
      final className = opt.attributes['class'] ?? '';
      if (value.isEmpty || className.isEmpty || value == 'modela ni na seznamu') continue;

      final brandKey = className.replaceAll(' vsi', '').trim();
      
      final rawText = opt.text;
      final isIndented = rawText.startsWith('\u00A0') || rawText.startsWith(' ');
      final isGroup = className.contains('vsi') || value.endsWith(' (vsi)');

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
      
      final fooId = opt.attributes['foo'];
      if (fooId != null && fooId.isNotEmpty) {
        modelId = fooId;
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

  return AvtonetCatalogData(
    brands: brands,
    modelsByBrand: modelsByBrand,
    lastUpdated: DateTime.now(),
  );
}
