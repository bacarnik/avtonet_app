import '../models/search_config.dart';
import '../data/filter_options.dart';

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

/// REFACTORED: Uses exact values from Avto.net catalog.
String buildAvtonetResultsUrl(SearchConfig config) {
  final String eq7 = _eq7ForTransmission(config.menjalnik) ?? '1110100120';
  final int? powerMinKw = _normalizePower(config.mocMin, config.powerUnit);
  final int? powerMaxKw = _normalizePower(config.mocMax, config.powerUnit);

  final params = <String, String>{
    'znamka': config.znamka,
    'model': config.modelSearchValue.isNotEmpty ? '' : (config.modelId ?? ''), 
    'SUBmodelsearch': config.modelSearchValue,
    'SUBmodgrp1': config.subModelGroup ?? '0',
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
    'mocMin': '', 
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

  if (params['SUBmodelsearch']!.isNotEmpty) {
    params['model'] = '';
  }

  if (params['model'] == '' && params['SUBmodelsearch'] == '') {
    params.remove('model');
  }
  if (params['SUBmodelsearch'] == '') params.remove('SUBmodelsearch');
  if (params['SUBmodgrp1'] == '0') params.remove('SUBmodgrp1');

  return _buildFromMap(params);
}

/// Builds a minimal URL for diagnostics.
String buildMinimalAvtonetUrl(SearchConfig config) {
  final int? powerMinKw = _normalizePower(config.mocMin, config.powerUnit);
  final int? powerMaxKw = _normalizePower(config.mocMax, config.powerUnit);

  final params = <String, String>{
    'znamka': config.znamka,
    'model': config.modelSearchValue.isNotEmpty ? '' : (config.modelId ?? ''),
    'SUBmodelsearch': config.modelSearchValue,
    'SUBmodgrp1': config.subModelGroup ?? '0',
    'cenaMin': '${config.cenaMin ?? 0}',
    'cenaMax': '${config.cenaMax ?? 999999}',
    'kmMin': '${config.kmMin ?? 0}',
    'kmMax': '${config.kmMax ?? 9999999}',
    'kwMin': powerMinKw != null ? '$powerMinKw' : '0',
    'kwMax': powerMaxKw != null ? '$powerMaxKw' : '999',
    'oblika': config.oblika,
    'stran': '1',
  };

  if (params['model'] == '' && (params['SUBmodelsearch']?.isEmpty ?? true)) {
    params.remove('model');
  }
  if (params['SUBmodelsearch'] == '') params.remove('SUBmodelsearch');
  if (params['SUBmodgrp1'] == '0') params.remove('SUBmodgrp1');

  return _buildFromMap(params);
}

String _buildFromMap(Map<String, String> params) {
  final queryString = params.entries
      .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
      .join('&');
  
  return 'https://www.avto.net/Ads/results.asp?$queryString';
}
