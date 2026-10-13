import 'dart:convert';

class SearchConfig {
  const SearchConfig({
    required this.id,
    required this.name,
    this.znamka = '',
    this.model = '',
    this.oblika = '0',
    this.kmMin,
    this.kmMax,
    this.letnikMin,
    this.letnikMax,
    this.cenaMin,
    this.cenaMax,
    this.ccmMin,
    this.ccmMax,
    this.mocMin,
    this.mocMax,
    this.powerUnit = 'kW',
    this.bencin = 0,
    this.menjalnik = '',
    this.createdAt,
    this.lastChecked,
    this.lastStatus = '',
    this.isEnabled = true,
    this.lastParsedCount = 0,
    this.lastMatchedCount = 0,
    this.lastDuplicateCount = 0,
    this.lastFoundIds = '',
    this.lastRejectionReason = '',
    this.lastGeneratedUrl = '',
    this.modelSearchValue = '',
    this.modelId,
    this.subModelGroup,
  });

  final String id;
  final String name;
  final String znamka;
  final String model;
  final String modelSearchValue;
  final String? modelId;
  final String? subModelGroup;
  final String oblika;
  final int? kmMin;
  final int? kmMax;
  final int? letnikMin;
  final int? letnikMax;
  final int? cenaMin;
  final int? cenaMax;
  final int? ccmMin;
  final int? ccmMax;
  final int? mocMin;
  final int? mocMax;
  final String powerUnit;
  final int bencin;
  final String menjalnik;
  final DateTime? createdAt;
  
  final DateTime? lastChecked;
  final String lastStatus;
  final bool isEnabled;

  final int lastParsedCount;
  final int lastMatchedCount;
  final int lastDuplicateCount;
  final String lastFoundIds;
  final String lastRejectionReason;
  final String lastGeneratedUrl;

  SearchConfig copyWith({
    DateTime? lastChecked,
    String? lastStatus,
    bool? isEnabled,
    int? lastParsedCount,
    int? lastMatchedCount,
    int? lastDuplicateCount,
    String? lastFoundIds,
    String? lastRejectionReason,
    String? lastGeneratedUrl,
    String? modelSearchValue,
    String? modelId,
    String? subModelGroup,
  }) {
    return SearchConfig(
      id: id,
      name: name,
      znamka: znamka,
      model: model,
      modelSearchValue: modelSearchValue ?? this.modelSearchValue,
      modelId: modelId ?? this.modelId,
      subModelGroup: subModelGroup ?? this.subModelGroup,
      oblika: oblika,
      kmMin: kmMin,
      kmMax: kmMax,
      letnikMin: letnikMin,
      letnikMax: letnikMax,
      cenaMin: cenaMin,
      cenaMax: cenaMax,
      ccmMin: ccmMin,
      ccmMax: ccmMax,
      mocMin: mocMin,
      mocMax: mocMax,
      powerUnit: powerUnit,
      bencin: bencin,
      menjalnik: menjalnik,
      createdAt: createdAt,
      lastChecked: lastChecked ?? this.lastChecked,
      lastStatus: lastStatus ?? this.lastStatus,
      isEnabled: isEnabled ?? this.isEnabled,
      lastParsedCount: lastParsedCount ?? this.lastParsedCount,
      lastMatchedCount: lastMatchedCount ?? this.lastMatchedCount,
      lastDuplicateCount: lastDuplicateCount ?? this.lastDuplicateCount,
      lastFoundIds: lastFoundIds ?? this.lastFoundIds,
      lastRejectionReason: lastRejectionReason ?? this.lastRejectionReason,
      lastGeneratedUrl: lastGeneratedUrl ?? this.lastGeneratedUrl,
    );
  }

  Map<String, dynamic> toJson() => {
      'id': id,
      'name': name,
      'znamka': znamka,
      'model': model,
      'oblika': oblika,
      'kmMin': kmMin,
      'kmMax': kmMax,
      'letnikMin': letnikMin,
      'letnikMax': letnikMax,
      'cenaMin': cenaMin,
      'cenaMax': cenaMax,
      'ccmMin': ccmMin,
      'ccmMax': ccmMax,
      'mocMin': mocMin,
      'mocMax': mocMax,
      'powerUnit': powerUnit,
      'bencin': bencin,
      'menjalnik': menjalnik,
      'createdAt': createdAt?.toIso8601String(),
      'lastChecked': lastChecked?.toIso8601String(),
      'lastStatus': lastStatus,
      'isEnabled': isEnabled,
      'lastParsedCount': lastParsedCount,
      'lastMatchedCount': lastMatchedCount,
      'lastDuplicateCount': lastDuplicateCount,
      'lastFoundIds': lastFoundIds,
      'lastRejectionReason': lastRejectionReason,
      'lastGeneratedUrl': lastGeneratedUrl,
      'modelSearchValue': modelSearchValue,
      'modelId': modelId,
      'subModelGroup': subModelGroup,
    };

  factory SearchConfig.fromJson(Map<String, dynamic> json) {
    final String legacyModel = json['model'] as String? ?? '';
    final String? mId = json['modelId'] as String?;
    final String? mSearch = json['modelSearchValue'] as String?;
    final String? subGroup = json['subModelGroup'] as String?;

    // 1. Detekcija skupine na podlagi subModelGroup (generično)
    final bool isGroup = subGroup != null && subGroup.isNotEmpty;

    String finalSearchValue = mSearch ?? '';
    String? finalModelId = mId;

    if (isGroup) {
      // Za skupine (vsi) modelId ne sme biti nastavljen, ker bi povozil searchValue
      finalModelId = null;
      // Če je searchValue prazna, jo rekonstruiramo iz subGroup
      if (finalSearchValue.isEmpty) {
        finalSearchValue = subGroup;
      }
    } else {
      // Če je searchValue prazna pri starem zapisu BMW serije (ki nima subGroup)
      if (finalSearchValue.isEmpty && legacyModel.endsWith(':')) {
        finalSearchValue = legacyModel;
      }

      // Za podmodele (ko je finalSearchValue ne-prazna in ni skupina), modelId NE SME biti nastavljen!
      if (finalSearchValue.isNotEmpty) {
        finalModelId = null;
      } else if (finalModelId == null && legacyModel.isNotEmpty) {
        // Za konkretne navadne modele brez ID (stari legacy zapis): vzamemo iz legacy polja
        finalModelId = legacyModel;
      }
    }

    // 2. VARNA MIGRACIJA: Odpravlja prejšnjo korupcijo podatkov (npr. modelId="33", modelSearchValue="33:")
    if (finalModelId != null && finalModelId.isNotEmpty && 
        finalSearchValue.toLowerCase() == '${finalModelId.toLowerCase()}:' &&
        !finalModelId.toLowerCase().contains('serija')) {
       finalSearchValue = '';
    }

    return SearchConfig(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Iskanje',
      znamka: json['znamka'] as String? ?? '',
      model: legacyModel,
      oblika: json['oblika']?.toString() ?? '0',
      kmMin: json['kmMin'] as int?,
      kmMax: json['kmMax'] as int?,
      letnikMin: json['letnikMin'] as int?,
      letnikMax: json['letnikMax'] as int?,
      cenaMin: json['cenaMin'] as int?,
      cenaMax: json['cenaMax'] as int?,
      ccmMin: json['ccmMin'] as int?,
      ccmMax: json['ccmMax'] as int?,
      mocMin: json['mocMin'] as int?,
      mocMax: json['mocMax'] as int?,
      powerUnit: json['powerUnit'] as String? ?? 'kW',
      bencin: json['bencin'] as int? ?? 0,
      menjalnik: json['menjalnik'] as String? ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
      lastChecked: json['lastChecked'] != null
          ? DateTime.tryParse(json['lastChecked'] as String)
          : null,
      lastStatus: json['lastStatus'] as String? ?? '',
      isEnabled: json['isEnabled'] as bool? ?? true,
      lastParsedCount: json['lastParsedCount'] as int? ?? 0,
      lastMatchedCount: json['lastMatchedCount'] as int? ?? 0,
      lastDuplicateCount: json['lastDuplicateCount'] as int? ?? 0,
      lastFoundIds: json['lastFoundIds'] as String? ?? '',
      lastRejectionReason: json['lastRejectionReason'] as String? ?? '',
      lastGeneratedUrl: json['lastGeneratedUrl'] as String? ?? '',
      modelSearchValue: finalSearchValue,
      modelId: finalModelId,
      subModelGroup: subGroup,
    );
  }

  static List<SearchConfig> listFromJsonString(String raw) {
    if (raw.isEmpty) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((e) => SearchConfig.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static String listToJsonString(List<SearchConfig> configs) {
    return jsonEncode(configs.map((e) => e.toJson()).toList());
  }
}
