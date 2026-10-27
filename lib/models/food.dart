import 'package:flutter/material.dart';

import '../services/app_language.dart';
import 'food_emoji.dart';

/// Skupiny potravín - každá má vlastnú farbu a ikonu.
/// `name` sa používa aj pri prevode z API (FoodGroup.byName).
enum FoodGroup {
  vegetables(['Zelenina', 'Zelenina', 'Vegetables'], Icons.eco_outlined, Color(0xFF4CAF50), '🥬'),
  fruit(['Ovocie', 'Ovoce', 'Fruit'], Icons.apple_outlined, Color(0xFFEC407A), '🍎'),
  grains(['Obilniny a prílohy', 'Obiloviny a přílohy', 'Grains and sides'], Icons.grain, Color(0xFFFB8C00), '🌾'),
  legumes(['Strukoviny', 'Luštěniny', 'Legumes'], Icons.spa_outlined, Color(0xFF26A69A), '🫘'),
  nuts(['Orechy a semienka', 'Ořechy a semínka', 'Nuts and seeds'], Icons.cookie_outlined, Color(0xFF8D6E63), '🥜'),
  meat(['Mäso', 'Maso', 'Meat'], Icons.kebab_dining_outlined, Color(0xFFE53935), '🍖'),
  fish(['Ryby', 'Ryby', 'Fish'], Icons.set_meal_outlined, Color(0xFF1E88E5), '🐟'),
  eggs(['Vajcia', 'Vejce', 'Eggs'], Icons.egg_outlined, Color(0xFFFFB300), '🥚'),
  dairy(['Mliečne', 'Mléčné', 'Dairy'], Icons.local_drink_outlined, Color(0xFF90A4AE), '🥛'),
  cheese(['Syry', 'Sýry', 'Cheese'], Icons.bakery_dining_outlined, Color(0xFFFBC02D), '🧀'),
  fats(['Tuky a oleje', 'Tuky a oleje', 'Fats and oils'], Icons.water_drop_outlined, Color(0xFFC0CA33), '🫒'),
  sauces(['Omáčky', 'Omáčky', 'Sauces'], Icons.soup_kitchen_outlined, Color(0xFFD84315), '🥫'),
  sweets(['Sladkosti', 'Sladkosti', 'Sweets'], Icons.cake_outlined, Color(0xFFAB47BC), '🍬'),
  drinks(['Nápoje', 'Nápoje', 'Drinks'], Icons.local_cafe_outlined, Color(0xFF5C6BC0), '🥤'),
  other(['Ostatné', 'Ostatní', 'Other'], Icons.more_horiz, Color(0xFF9E9E9E), '🍽️');

  const FoodGroup(this.labels, this.icon, this.color, this.emoji);

  /// Názov skupiny v poradí sk, cs, en (ako AppLanguage).
  final List<String> labels;
  String get label => labels[AppLanguage.current.index];
  final IconData icon;
  final Color color;

  /// Záložné emoji, keď pre konkrétnu potravinu žiadne nemáme.
  final String emoji;

  static FoodGroup byName(String? name) =>
      FoodGroup.values.firstWhere((g) => g.name == name, orElse: () => other);
}

/// Úprava potraviny. `name` sa používa aj pri prevode z API (FoodPrep.byName).
enum FoodPrep {
  none(['', '', '']),
  raw(['surové', 'syrové', 'raw']),
  cooked(['varené', 'vařené', 'cooked']),
  baked(['pečené', 'pečené', 'baked']),
  fried(['smažené', 'smažené', 'fried']),
  canned(['balené', 'balené', 'packaged']),
  dried(['sušené', 'sušené', 'dried']);

  const FoodPrep(this.labels);

  /// Názov úpravy v poradí sk, cs, en (ako AppLanguage).
  final List<String> labels;
  String get label => labels[AppLanguage.current.index];

  static FoodPrep byName(String? name) => FoodPrep.values
      .firstWhere((p) => p.name == name, orElse: () => FoodPrep.none);
}

/// Potravina z online API (FoodApi) – hodnoty sú na 100 g.
class FoodInfo {
  const FoodInfo({
    required this.id,
    required this.names,
    required this.prep,
    required this.group,
    required this.kcal,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.fiber,
    required this.sugar,
  });

  /// Id potraviny v API (text, lebo každá API ho má inak).
  final String id;

  /// Potravina a druh v poradí sk, cs, en, napr. "Ryža, biela".
  final List<String> names;
  String get name => names[AppLanguage.current.index];
  String get nameEn => names[AppLanguage.en.index];
  final FoodPrep prep;
  final FoodGroup group;
  final double kcal;
  final double protein;
  final double carbs;
  final double fat;
  final double fiber;
  final double sugar;

  String get emoji => foodEmoji(nameEn, group);

  /// Názov aj s úpravou: "Ryža, biela · varené".
  String get displayName => prep == FoodPrep.none ? name : '$name · ${prep.label}';
}

/// Jedna potravina v jedle. [name] a [prep] sú to, čo povedala AI
/// (napr. "ryža", varené), [food] je konkrétna potravina z API.
class FoodItem {
  FoodItem(this.name, this.group, this.grams,
      {this.food, this.prep = FoodPrep.none, this.nameEn});
  String name;

  /// Anglický názov od AI (pre emoji a záložné hľadanie).
  String? nameEn;
  FoodGroup group;
  int grams;
  FoodInfo? food;
  FoodPrep prep;

  String get emoji => food?.emoji ?? foodEmoji(nameEn ?? name, group);

  double _per(double Function(FoodInfo f) value) =>
      food == null ? 0 : value(food!) * grams / 100;

  double get kcal => _per((f) => f.kcal);
  double get protein => _per((f) => f.protein);
  double get carbs => _per((f) => f.carbs);
  double get fat => _per((f) => f.fat);

  /// Priradí potravinu z API (aj s jej skupinou).
  void setFood(FoodInfo info, int newGrams) {
    food = info;
    group = info.group;
    prep = info.prep;
    grams = newGrams;
  }
}

/// Jedlo = len štatistika (zoznam potravín), fotka sa neukladá.
class Meal {
  Meal({required this.time, List<FoodItem>? items}) : items = items ?? [];
  final TimeOfDay time;
  final List<FoodItem> items;

  int get totalGrams => items.fold(0, (sum, i) => sum + i.grams);
  double get totalKcal => items.fold(0.0, (sum, i) => sum + i.kcal);
  double get totalProtein => items.fold(0.0, (sum, i) => sum + i.protein);
  double get totalCarbs => items.fold(0.0, (sum, i) => sum + i.carbs);
  double get totalFat => items.fold(0.0, (sum, i) => sum + i.fat);

  /// Či má každá potravina priradenú položku z API.
  bool get allMatched => items.every((i) => i.food != null);

  /// Gramy podľa skupiny (len skupiny, ktoré v jedle sú).
  Map<FoodGroup, int> get gramsByGroup {
    final map = <FoodGroup, int>{};
    for (final g in FoodGroup.values) {
      final sum = items.where((i) => i.group == g).fold(0, (s, i) => s + i.grams);
      if (sum > 0) map[g] = sum;
    }
    return map;
  }
}
