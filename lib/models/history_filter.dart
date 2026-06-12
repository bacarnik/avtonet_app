import 'dart:convert';

class HistoryFilter {
  const HistoryFilter({
    this.make = '',
    this.model = '',
    this.bodyCode = 0,
    this.fuelCode = 0,
    this.priceMin,
    this.priceMax,
    this.yearMin,
    this.yearMax,
    this.sortType = 'date', // price, year, km, date
    this.sortAscending = false,
  });

  final String make;
  final String model;
  final int bodyCode;
  final int fuelCode;
  final int? priceMin;
  final int? priceMax;
  final int? yearMin;
  final int? yearMax;
  final String sortType;
  final bool sortAscending;

  Map<String, dynamic> toJson() => {
    'make': make,
    'model': model,
    'bodyCode': bodyCode,
    'fuelCode': fuelCode,
    'priceMin': priceMin,
    'priceMax': priceMax,
    'yearMin': yearMin,
    'yearMax': yearMax,
    'sortType': sortType,
    'sortAscending': sortAscending,
  };

  factory HistoryFilter.fromJson(Map<String, dynamic> json) {
    return HistoryFilter(
      make: json['make'] as String? ?? '',
      model: json['model'] as String? ?? '',
      bodyCode: json['bodyCode'] as int? ?? 0,
      fuelCode: json['fuelCode'] as int? ?? 0,
      priceMin: json['priceMin'] as int?,
      priceMax: json['priceMax'] as int?,
      yearMin: json['yearMin'] as int?,
      yearMax: json['yearMax'] as int?,
      sortType: json['sortType'] as String? ?? 'date',
      sortAscending: json['sortAscending'] as bool? ?? false,
    );
  }

  static String toJsonString(HistoryFilter filter) => jsonEncode(filter.toJson());
  
  static HistoryFilter fromJsonString(String raw) {
    if (raw.isEmpty) return const HistoryFilter();
    try {
      return HistoryFilter.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const HistoryFilter();
    }
  }

  HistoryFilter copyWith({
    String? make,
    String? model,
    int? bodyCode,
    int? fuelCode,
    int? priceMin,
    int? priceMax,
    int? yearMin,
    int? yearMax,
    String? sortType,
    bool? sortAscending,
  }) {
    return HistoryFilter(
      make: make ?? this.make,
      model: model ?? this.model,
      bodyCode: bodyCode ?? this.bodyCode,
      fuelCode: fuelCode ?? this.fuelCode,
      priceMin: priceMin ?? this.priceMin,
      priceMax: priceMax ?? this.priceMax,
      yearMin: yearMin ?? this.yearMin,
      yearMax: yearMax ?? this.yearMax,
      sortType: sortType ?? this.sortType,
      sortAscending: sortAscending ?? this.sortAscending,
    );
  }

  @override
  String toString() => 'HistoryFilter(make: $make, model: $model, fuel: $fuelCode, pMin: $priceMin, pMax: $priceMax)';
}
