import 'package:flutter/material.dart';

import '../services/app_language.dart';
import 'food_emoji.dart';

/// Skupiny potravín - každá má vlastnú farbu a ikonu.
/// `name` sa používa aj pri prevode z API (FoodGroup.byName).
enum FoodGroup {
  vegetables(
    ['Zelenina', 'Zelenina', 'Vegetables'],
    Icons.eco_outlined,
    Color(0xFF4CAF50),
    '🥬',
  ),
  fruit(
    ['Ovocie', 'Ovoce', 'Fruit'],
    Icons.apple_outlined,
    Color(0xFFEC407A),
    '🍎',
  ),
  grains(
    ['Obilniny a prílohy', 'Obiloviny a přílohy', 'Grains and sides'],
    Icons.grain,
    Color(0xFFFB8C00),
    '🌾',
  ),
  legumes(
    ['Strukoviny', 'Luštěniny', 'Legumes'],
    Icons.spa_outlined,
    Color(0xFF26A69A),
    '🫘',
  ),
  nuts(
    ['Orechy a semienka', 'Ořechy a semínka', 'Nuts and seeds'],
    Icons.cookie_outlined,
    Color(0xFF8D6E63),
    '🥜',
  ),
  meat(
    ['Mäso', 'Maso', 'Meat'],
    Icons.kebab_dining_outlined,
    Color(0xFFE53935),
    '🍖',
  ),
  fish(
    ['Ryby', 'Ryby', 'Fish'],
    Icons.set_meal_outlined,
    Color(0xFF1E88E5),
    '🐟',
  ),
  eggs(
    ['Vajcia', 'Vejce', 'Eggs'],
    Icons.egg_outlined,
    Color(0xFFFFB300),
    '🥚',
  ),
  dairy(
    ['Mliečne', 'Mléčné', 'Dairy'],
    Icons.local_drink_outlined,
    Color(0xFF90A4AE),
    '🥛',
  ),
  cheese(
    ['Syry', 'Sýry', 'Cheese'],
    Icons.bakery_dining_outlined,
    Color(0xFFFBC02D),
    '🧀',
  ),
  fats(
    ['Tuky a oleje', 'Tuky a oleje', 'Fats and oils'],
    Icons.water_drop_outlined,
    Color(0xFFC0CA33),
    '🫒',
  ),
  sauces(
    ['Omáčky', 'Omáčky', 'Sauces'],
    Icons.soup_kitchen_outlined,
    Color(0xFFD84315),
    '🥫',
  ),
  sweets(
    ['Sladkosti', 'Sladkosti', 'Sweets'],
    Icons.cake_outlined,
    Color(0xFFAB47BC),
    '🍬',
  ),
  drinks(
    ['Nápoje', 'Nápoje', 'Drinks'],
    Icons.local_cafe_outlined,
    Color(0xFF5C6BC0),
    '🥤',
  ),
  other(
    ['Ostatné', 'Ostatní', 'Other'],
    Icons.more_horiz,
    Color(0xFF9E9E9E),
    '🍽️',
  );

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
///
/// Prvých 7 hodnôt sú hrubé typy, ktoré vracia AI. Ostatné sú podrobnejšie
/// úpravy z databázy potravín; [kind] hovorí, pod ktorý hrubý typ patria.
enum FoodPrep {
  none(['', '', ''], [[], [], []]),
  raw(
    ['surové', 'syrové', 'raw'],
    [
      ['surov', 'cerstv'],
      ['syrov', 'cerstv'],
      ['raw', 'fresh'],
    ],
  ),
  cooked(
    ['tepelne upravené', 'tepelně upravené', 'cooked'],
    [
      ['varen', 'uvaren', 'upraven'],
      ['varen', 'uvaren', 'upraven'],
      ['cooked'],
    ],
  ),
  baked(
    ['pečené v rúre', 'pečené v troubě', 'baked'],
    [
      ['pecen', 'zapecen'],
      ['pecen', 'zapecen'],
      ['baked'],
    ],
  ),
  fried(
    ['vyprážané', 'smažené', 'fried'],
    [
      ['vypraz', 'opekan', 'restovan'],
      ['smazen', 'osmazen', 'restovan'],
      ['fried'],
    ],
  ),
  canned(
    ['konzervované', 'konzervované', 'canned'],
    [
      ['konzerv', 'sterilizovan'],
      ['konzerv', 'sterilizovan'],
      ['canned'],
    ],
  ),
  dried(
    ['sušené', 'sušené', 'dried'],
    [
      ['susen'],
      ['susen'],
      ['dried'],
    ],
  ),
  boiled(
    ['varené', 'vařené', 'boiled'],
    [
      ['varen', 'uvaren'],
      ['varen', 'uvaren'],
      ['boiled', 'simmered'],
    ],
    cooked,
  ),
  steamed(
    ['na pare', 'v páře', 'steamed'],
    [
      ['na pare', 'naparen'],
      ['v pare', 'naparen'],
      ['steamed'],
    ],
    cooked,
  ),
  stewed(
    ['dusené', 'dušené', 'stewed'],
    [
      ['dusen'],
      ['dusen'],
      ['stewed'],
    ],
    cooked,
  ),
  braised(
    ['dusené', 'dušené', 'braised'],
    [
      ['dusen'],
      ['dusen'],
      ['braised'],
    ],
    cooked,
  ),
  microwaved(
    ['v mikrovlnke', 'v mikrovlnce', 'microwaved'],
    [
      ['mikrovln'],
      ['mikrovln'],
      ['microwaved'],
    ],
    cooked,
  ),
  scrambled(
    ['praženica', 'míchaná', 'scrambled'],
    [
      ['prazenic'],
      ['michan'],
      ['scrambled'],
    ],
    fried,
  ),
  roasted(
    ['pečené', 'pečené', 'roasted'],
    [
      ['pecen', 'opecen'],
      ['pecen', 'opecen'],
      ['roasted'],
    ],
    baked,
  ),
  grilled(
    ['grilované', 'grilované', 'grilled'],
    [
      ['grilovan'],
      ['grilovan'],
      ['grilled'],
    ],
    baked,
  ),
  broiled(
    ['grilované', 'grilované', 'broiled'],
    [
      ['grilovan'],
      ['grilovan'],
      ['broiled'],
    ],
    baked,
  ),
  smoked(
    ['údené', 'uzené', 'smoked'],
    [
      ['uden'],
      ['uzen'],
      ['smoked'],
    ],
    none,
  ),
  frozen(
    ['mrazené', 'mražené', 'frozen'],
    [
      ['mrazen'],
      ['mrazen'],
      ['frozen'],
    ],
    raw,
  ),
  hardBoiled(
    ['natvrdo', 'natvrdo', 'hard-boiled'],
    [
      ['natvrd'],
      ['natvrd'],
      ['hard boiled', 'hard-boiled'],
    ],
    cooked,
  ),
  softBoiled(
    ['namäkko', 'naměkko', 'soft-boiled'],
    [
      ['namakk'],
      ['namekk'],
      ['soft boiled', 'soft-boiled'],
    ],
    cooked,
  ),
  poached(
    ['pošírované', 'ztracené', 'poached'],
    [
      ['posir'],
      ['ztracen'],
      ['poached'],
    ],
    cooked,
  ),
  omelette(
    ['omeleta', 'omeleta', 'omelette'],
    [
      ['omelet'],
      ['omelet'],
      ['omelet'],
    ],
    fried,
  );

  const FoodPrep(this.labels, this.searchStems, [this._kind]);

  /// Hodnota v stĺpci `preparation` databázy, napr. hardBoiled → hard_boiled.
  String get key =>
      name.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');

  /// Názov úpravy v poradí sk, cs, en (ako AppLanguage).
  final List<String> labels;
  String get label => labels[AppLanguage.current.index];

  /// Začiatky slov bez diakritiky, podľa ktorých sa úprava spozná
  /// v hľadanom texte (v poradí sk, cs, en).
  final List<List<String>> searchStems;

  final FoodPrep? _kind;

  /// Hrubý typ úpravy (ako ho vracia AI), napr. grilled → baked.
  FoodPrep get kind => _kind ?? this;

  /// Úpravy, z ktorých si vyberá AI.
  static List<FoodPrep> get aiValues => [
    for (final p in values)
      if (p.kind == p) p,
  ];

  static FoodPrep byName(String? name) => FoodPrep.values.firstWhere(
    (p) => p.name == name || p.key == name,
    orElse: () => FoodPrep.none,
  );
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
  String get displayName =>
      prep == FoodPrep.none ? name : '$name · ${prep.label}';
}

/// Jedna potravina v jedle. [name] a [prep] sú to, čo povedala AI
/// (napr. "ryža", varené), [food] je konkrétna potravina z API.
class FoodItem {
  FoodItem(
    this.name,
    this.group,
    this.grams, {
    this.food,
    this.prep = FoodPrep.none,
    this.nameEn,
  });
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
      final sum = items
          .where((i) => i.group == g)
          .fold(0, (s, i) => s + i.grams);
      if (sum > 0) map[g] = sum;
    }
    return map;
  }
}
