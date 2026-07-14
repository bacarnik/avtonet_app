import 'dart:convert';

class AvtonetBrand {
  final String displayName;
  final String value;
  final String? id; // From 'foo' attribute if available

  AvtonetBrand({required this.displayName, required this.value, this.id});

  Map<String, dynamic> toJson() => {
        'displayName': displayName,
        'value': value,
        'id': id,
      };

  factory AvtonetBrand.fromJson(Map<String, dynamic> json) => AvtonetBrand(
        displayName: json['displayName'],
        value: json['value'],
        id: json['id'],
      );
}

class AvtonetModel {
  final String displayName;
  final String searchValue;
  final String? modelId;
  final String? subModelGroup;

  AvtonetModel({
    required this.displayName,
    required this.searchValue,
    this.modelId,
    this.subModelGroup,
  });

  Map<String, dynamic> toJson() => {
        'displayName': displayName,
        'searchValue': searchValue,
        'modelId': modelId,
        'subModelGroup': subModelGroup,
      };

  factory AvtonetModel.fromJson(Map<String, dynamic> json) => AvtonetModel(
        displayName: json['displayName'],
        searchValue: json['searchValue'],
        modelId: json['modelId'],
        subModelGroup: json['subModelGroup'],
      );
}

class AvtonetCatalogData {
  final List<AvtonetBrand> brands;
  final Map<String, List<AvtonetModel>> modelsByBrand;
  final DateTime lastUpdated;

  AvtonetCatalogData({
    required this.brands,
    required this.modelsByBrand,
    required this.lastUpdated,
  });

  Map<String, dynamic> toJson() => {
        'brands': brands.map((e) => e.toJson()).toList(),
        'modelsByBrand': modelsByBrand.map(
            (k, v) => MapEntry(k, v.map((e) => e.toJson()).toList())),
        'lastUpdated': lastUpdated.toIso8601String(),
      };

  factory AvtonetCatalogData.fromJson(Map<String, dynamic> json) {
    final brandsRaw = json['brands'] as List;
    final modelsByBrandRaw = json['modelsByBrand'] as Map<String, dynamic>;

    return AvtonetCatalogData(
      brands: brandsRaw.map((e) => AvtonetBrand.fromJson(e)).toList(),
      modelsByBrand: modelsByBrandRaw.map((k, v) => MapEntry(
          k, (v as List).map((e) => AvtonetModel.fromJson(e)).toList())),
      lastUpdated: DateTime.parse(json['lastUpdated']),
    );
  }
}
