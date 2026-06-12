import 'package:flutter/material.dart';

class BodyTypeOption {
  const BodyTypeOption({
    required this.code,
    required this.label,
    required this.slug, // Added slug for mapping
    required this.icon,
  });

  final int code;
  final String label;
  final String slug;
  final IconData icon;
}

/// OFFICIAL AVTO.NET CODES as requested by user.
/// Note: These codes will be mapped via bodyTypeMap for URL generation.
const List<BodyTypeOption> kBodyTypes = [
  BodyTypeOption(code: 0, label: 'Katerikoli', slug: 'any', icon: Icons.apps),
  BodyTypeOption(code: 11, label: 'Limuzina', slug: 'limuzina', icon: Icons.directions_car),
  BodyTypeOption(code: 12, label: 'Hatchback', slug: 'hatchback', icon: Icons.beach_access),
  BodyTypeOption(code: 13, label: 'Karavan', slug: 'karavan', icon: Icons.airport_shuttle),
  BodyTypeOption(code: 14, label: 'Enoprostorec', slug: 'enoprostorec', icon: Icons.groups_outlined),
  BodyTypeOption(code: 15, label: 'SUV', slug: 'suv', icon: Icons.terrain),
  BodyTypeOption(code: 16, label: 'Coupe', slug: 'coupe', icon: Icons.directions_car_outlined),
  BodyTypeOption(code: 17, label: 'Cabrio', slug: 'cabrio', icon: Icons.wb_sunny),
  BodyTypeOption(code: 18, label: 'Pick-up', slug: 'pick-up', icon: Icons.local_shipping),
];

final Map<String, int> bodyTypeMap = {
  'limuzina': 11,
  'hatchback': 12,
  'karavan': 13,
  'enoprostorec': 14,
  'suv': 15,
  'coupe': 16,
  'cabrio': 17,
  'pick-up': 18,
};
