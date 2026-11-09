import 'package:flutter/material.dart';

/// Standardværdier der deles af alle formularer til indkøbsvarer.
const defaultGroceryCategories = [
  'Frugt & Grønt',
  'Brød',
  'Mejeri',
  'Kød & Fisk',
  'Kolonial',
  'Frost',
  'Drikkevarer',
  'Husholdning',
  'Andet',
];

const defaultGroceryUnits = [
  'stk',
  'g',
  'kg',
  'ml',
  'l',
  'pk',
  'bakke',
  'poser'
];

/// Returnerer ikonet for en kategori.
IconData categoryIconFor(String category) {
  switch (normalizeGroceryCategory(category)) {
    case 'Frugt & Grønt':
      return Icons.apple;
    case 'Brød':
      return Icons.bakery_dining;
    case 'Mejeri':
      return Icons.egg_alt;
    case 'Kød & Fisk':
      return Icons.restaurant;
    case 'Kolonial':
      return Icons.kitchen;
    case 'Frost':
      return Icons.ac_unit;
    case 'Drikkevarer':
      return Icons.local_drink;
    case 'Husholdning':
      return Icons.cleaning_services;
    case 'Andet':
    default:
      return Icons.shopping_basket;
  }
}

/// Normaliserer ældre kategorinavne og sikrer gyldig kategori.
String normalizeGroceryCategory(String? raw) {
  final trimmed = raw?.trim() ?? '';
  if (trimmed.isEmpty) return 'Andet';
  final lower = trimmed.toLowerCase();
  if (lower == 'grønt' ||
      lower == 'frugt' ||
      lower == 'frugt & grønt' ||
      lower == 'frugt og grønt') {
    return 'Frugt & Grønt';
  }
  if (lower == 'kød' ||
      lower == 'fisk' ||
      lower == 'kød & fisk' ||
      lower == 'kød og fisk') {
    return 'Kød & Fisk';
  }
  if (lower == 'brød') return 'Brød';
  if (lower == 'mejeri') return 'Mejeri';
  if (lower == 'kolonial') return 'Kolonial';
  if (lower == 'frost') return 'Frost';
  if (lower == 'drikkevarer') return 'Drikkevarer';
  if (lower == 'husholdning') return 'Husholdning';
  if (lower == 'andet') return 'Andet';
  return trimmed;
}

/// Sorterer kategorier efter standardrækkefølgen og derefter alfabetisk for egne kategorier.
List<String> sortGroceryCategories(Iterable<String> categories) {
  final list = categories.toList();
  list.sort((a, b) {
    final normA = normalizeGroceryCategory(a);
    final normB = normalizeGroceryCategory(b);
    final indexA = defaultGroceryCategories.indexOf(normA);
    final indexB = defaultGroceryCategories.indexOf(normB);
    if (indexA != -1 && indexB != -1) {
      final cmp = indexA.compareTo(indexB);
      if (cmp != 0) return cmp;
    } else if (indexA != -1) {
      return -1;
    } else if (indexB != -1) {
      return 1;
    }
    return a.toLowerCase().compareTo(b.toLowerCase());
  });
  return list;
}
