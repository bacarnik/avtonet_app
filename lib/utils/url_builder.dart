import 'package:flutter/foundation.dart';
import '../data/filter_options.dart';
import '../models/search_config.dart';

String? _eq7ForTransmission(String menjalnik) {
  for (final t in kTransmissionOptions) {
    if (t.id == menjalnik && t.eq7 != null) return t.eq7;
  }
  return null;
}

int? _normalizePower(int? value, String unit) {
  if (value == null) return null;
  if (unit == 'KM') {
    return (value / 1.341).round();
  }
  return value;
}

/// REFACTORED: Fixed brand/model mapping, power parameters, and query construction.
String buildAvtonetResultsUrl(SearchConfig config) {
  final String eq7 = _eq7ForTransmission(config.menjalnik) ?? '1110100120';
  final int? powerMinKw = _normalizePower(config.mocMin, config.powerUnit);
  final int? powerMaxKw = _normalizePower(config.mocMax, config.powerUnit);

  final String znamka = config.znamka.toLowerCase();
  
  // Use SUBmodelsearch to bypass the generation selection page which causes 0 results in app.
  final String subModelSearch = config.model;

  final params = <String, String>{
    'znamka': znamka,
    'model': '', // Leave empty when using SUBmodelsearch for better reliability
    'SUBmodelsearch': subModelSearch,
    'tip': 'katerikoli tip',
    'cenaMin': '${config.cenaMin ?? 0}',
    'cenaMax': '${config.cenaMax ?? 999999}',
    'letnikMin': '${config.letnikMin ?? 0}',
    'letnikMax': '${config.letnikMax ?? 2090}',
    'bencin': '${config.bencin}',
    'starost2': '999',
    'oblika': config.oblika,
    'ccmMin': '${config.ccmMin ?? 0}',
    'ccmMax': '${config.ccmMax ?? 99999}',
    'mocMin': '', // Avto.net uses kwMin/kwMax for power filtering
    'mocMax': '',
    'kmMin': '${config.kmMin ?? 0}',
    'kmMax': '${config.kmMax ?? 9999999}',
    'kwMin': powerMinKw != null ? '$powerMinKw' : '0',
    'kwMax': powerMaxKw != null ? '$powerMaxKw' : '999',
    'lokacija': '0',
    'EQ1': '1000000000',
    'EQ2': '1000000000',
    'EQ3': '1000000000',
    'EQ4': '1000000000',
    'EQ5': '1000000000',
    'EQ6': '1000000000',
    'EQ7': eq7,
    'EQ9': '100000000',
    'KAT': '1010000000',
    'stran': '1',
  };

  return _buildFromMap(params);
}

/// Builds a minimal URL for diagnostics.
String buildMinimalAvtonetUrl(SearchConfig config) {
  final int? powerMinKw = _normalizePower(config.mocMin, config.powerUnit);
  final int? powerMaxKw = _normalizePower(config.mocMax, config.powerUnit);

  final String znamka = config.znamka.toLowerCase();

  final params = <String, String>{
    'znamka': znamka,
    'SUBmodelsearch': config.model,
    'cenaMin': '${config.cenaMin ?? 0}',
    'cenaMax': '${config.cenaMax ?? 999999}',
    'kmMin': '${config.kmMin ?? 0}',
    'kmMax': '${config.kmMax ?? 9999999}',
    'kwMin': powerMinKw != null ? '$powerMinKw' : '0',
    'kwMax': powerMaxKw != null ? '$powerMaxKw' : '999',
    'oblika': config.oblika,
    'stran': '1',
  };

  return _buildFromMap(params);
}

String _buildFromMap(Map<String, String> params) {
  params.remove('EQ8');

  // Standard Uri construction in Dart removes '=' for empty values.
  // Manual construction preserves them.
  final queryString = params.entries
      .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
      .join('&');
  
  final url = 'https://www.avto.net/Ads/results.asp?$queryString';
  
  debugPrint('================================');
  debugPrint('[AVTONET URL BUILD]');
  debugPrint('URL: $url');
  debugPrint('================================');
  
  return url;
}
