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

/// REFACTORED: Uses CP1250 encoding for Avto.net parameters.
String buildAvtonetResultsUrl(SearchConfig config) {
  final String eq7 = _eq7ForTransmission(config.menjalnik) ?? '1110100120';
  final int? powerMinKw = _normalizePower(config.mocMin, config.powerUnit);
  final int? powerMaxKw = _normalizePower(config.mocMax, config.powerUnit);

  // Use the raw values from config, but we will encode them later.
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

String _buildFromMap(Map<String, String> params) {
  // Use a custom builder that implements CP1250 encoding
  final List<String> parts = [];
  params.forEach((key, value) {
    parts.add('${_encodeCP1250(key)}=${_encodeCP1250(value)}');
  });
  
  return 'https://www.avto.net/Ads/results.asp?${parts.join('&')}';
}

/// Helper to encode Slovenian characters in CP1250 (Windows-1250).
String _encodeCP1250(String text) {
  // CP1250 mapping for URL encoding
  final Map<String, String> mapping = {
    'Š': '%8A', 'š': '%9A',
    'Č': '%C8', 'č': '%E8',
    'Ž': '%8E', 'ž': '%9E',
    'Ć': '%C6', 'ć': '%E6',
    'Đ': '%D0', 'đ': '%F0',
    ' ': '%20',
  };
  
  final sb = StringBuffer();
  for (int i = 0; i < text.length; i++) {
    final char = text[i];
    if (mapping.containsKey(char)) {
      sb.write(mapping[char]);
    } else {
      // Standard alphanumeric characters don't need encoding
      if (RegExp(r'[a-zA-Z0-9\-\._~]').hasMatch(char)) {
        sb.write(char);
      } else {
        // Fallback to Uri encoding for other special characters
        sb.write(Uri.encodeQueryComponent(char));
      }
    }
  }
  return sb.toString();
}
