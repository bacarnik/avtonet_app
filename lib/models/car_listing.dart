import 'dart:convert';

class CarListing {
  const CarListing({
    required this.id,
    required this.title,
    required this.price,
    required this.link,
    this.imageUrl = '',
    this.year = '',
    this.mileage = '',
    this.fuel = '',
    this.searchConfigId = '',
    this.foundAt,
    this.bodyType = 0,
    this.powerKw = 0,
    this.powerHp = 0,
    this.isTopOffer = false, // ADDED: Support for TOP PONUDBA detection
  });

  final String id;
  final String title;
  final String price;
  final String link;
  final String imageUrl;
  final String year;
  final String mileage;
  final String fuel;
  final String searchConfigId;
  final DateTime? foundAt;
  final int bodyType;
  final int powerKw;
  final int powerHp;
  final bool isTopOffer;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'price': price,
        'link': link,
        'imageUrl': imageUrl,
        'year': year,
        'mileage': mileage,
        'fuel': fuel,
        'searchConfigId': searchConfigId,
        'foundAt': foundAt?.toIso8601String(),
        'bodyType': bodyType,
        'powerKw': powerKw,
        'powerHp': powerHp,
        'isTopOffer': isTopOffer,
      };

  factory CarListing.fromJson(Map<String, dynamic> json) {
    return CarListing(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      price: json['price'] as String? ?? '',
      link: json['link'] as String? ?? '',
      imageUrl: json['imageUrl'] as String? ?? '',
      year: json['year'] as String? ?? '',
      mileage: json['mileage'] as String? ?? '',
      fuel: json['fuel'] as String? ?? '',
      searchConfigId: json['searchConfigId'] as String? ?? '',
      foundAt: json['foundAt'] != null
          ? DateTime.tryParse(json['foundAt'] as String)
          : null,
      bodyType: json['bodyType'] as int? ?? 0,
      powerKw: json['powerKw'] as int? ?? 0,
      powerHp: json['powerHp'] as int? ?? 0,
      isTopOffer: json['isTopOffer'] as bool? ?? false,
    );
  }

  static List<CarListing> listFromJsonString(String raw) {
    if (raw.isEmpty) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((e) => CarListing.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static String listToJsonString(List<CarListing> listings) {
    return jsonEncode(listings.map((e) => e.toJson()).toList());
  }
}
