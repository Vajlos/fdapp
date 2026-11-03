import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/food.dart';
import 'app_language.dart';

/// Online zdroj potravín. Aplikácia pozná len toto rozhranie – teraz ho
/// implementuje [SupabaseFoodApi]; inú API stačí nastaviť vo [FoodApi.instance].
abstract class FoodApi {
  /// Používaná API. Na zmenu stačí priradiť inú implementáciu.
  static FoodApi instance = SupabaseFoodApi();

  /// Zdroj údajov, zobrazí sa na detaile potraviny.
  String get sourceName;

  /// Hľadá potraviny podľa textu (v jazyku aplikácie).
  /// Pri chybe siete alebo API hodí [FoodApiException].
  Future<List<FoodInfo>> search(String query, {int limit = 50});

  /// Najlepšia zhoda pre názov a úpravu od AI. Ak nič nenájde, skúsi
  /// anglický názov [nameEn]. Z výsledkov uprednostní ten s úpravou [prep].
  Future<FoodInfo?> bestMatch(
    String name, {
    FoodPrep prep = FoodPrep.none,
    String? nameEn,
  }) async {
    for (final query in [
      name,
      if (nameEn != null && nameEn.isNotEmpty) nameEn,
    ]) {
      final results = await search(query, limit: 10);
      if (results.isEmpty) continue;
      return results.firstWhere(
        (f) => f.prep == prep,
        orElse: () => results.firstWhere(
          (f) => f.prep.kind == prep,
          orElse: () => results.first,
        ),
      );
    }
    return null;
  }
}

/// Chyba pri komunikácii s API – [message] sa dá ukázať používateľovi.
class FoodApiException implements Exception {
  FoodApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// Supabase – tabuľka `foods` naimportovaná z data/foods.csv, čítaná cez REST.
// Adresa a anon kľúč sa zadávajú pri spustení:
//   flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co
//               --dart-define=SUPABASE_ANON_KEY=...
// ---------------------------------------------------------------------------

class SupabaseFoodApi extends FoodApi {
  SupabaseFoodApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _url = String.fromEnvironment('SUPABASE_URL');
  static const _anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const _table = String.fromEnvironment(
    'SUPABASE_FOODS_TABLE',
    defaultValue: 'foods',
  );
  static const _timeout = Duration(seconds: 10);

  static const _columns =
      'id,name_sk,name_cs,name_en,brand,preparation,food_group,'
      'kcal,protein_g,carbs_g,fat_g,fiber_g,sugars_g';

  @override
  String get sourceName => 'USDA FoodData Central';

  // Rovnaký dotaz sa nepýta znova (napr. pri návrate na hľadanie).
  final _cache = <String, List<FoodInfo>>{};

  @override
  Future<List<FoodInfo>> search(String query, {int limit = 50}) async {
    final language = AppLanguage.current;
    final words = foldText(query).split(' ').where((w) => w.isNotEmpty);
    if (words.isEmpty) return const [];
    final key = '${language.name}|$limit|${words.join(' ')}';
    if (_cache[key] case final cached?) return cached;

    if (_url.isEmpty || _anonKey.isEmpty) {
      throw FoodApiException(
        const [
          'Databáza potravín ešte nie je nastavená.',
          'Databáze potravin ještě není nastavena.',
          'Food database is not configured yet.',
        ][language.index],
      );
    }

    // Slová ako "pečené" sú úprava, ostatné sa hľadajú v názve
    // (v jazyku aplikácie a v angličtine).
    final preps = <FoodPrep>{};
    final nameWords = <String>[];
    for (final word in words) {
      final matched = _prepsFor(word, language);
      if (matched.isEmpty) {
        nameWords.add(word);
      } else {
        preps.addAll(matched);
      }
    }
    if (nameWords.isEmpty) return const [];

    final searchColumn = 'search_${language.name}';
    // Adresa projektu môže byť zadaná aj s "/rest/v1" na konci.
    final base = _url.replaceFirst(RegExp(r'(/rest/v1)?/*$'), '');
    final uri = Uri.parse('$base/rest/v1/$_table').replace(
      queryParameters: {
        'select': _columns,
        'and':
            '(${[for (final w in nameWords) '$searchColumn.ilike.*$w*'].join(',')})',
        if (preps.isNotEmpty)
          'preparation': 'in.(${preps.map((p) => p.key).join(',')})',
        // viac ako limit, aby sa po zoradení dostali dopredu najlepšie zhody
        'limit': '${limit * 4}',
      },
    );

    final http.Response response;
    try {
      response = await _client
          .get(
            uri,
            headers: {'apikey': _anonKey, 'Authorization': 'Bearer $_anonKey'},
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw FoodApiException(_errorText);
    } on http.ClientException {
      throw FoodApiException(_errorText);
    }
    if (response.statusCode != 200) {
      throw FoodApiException('$_errorText (${response.statusCode})');
    }

    final List<FoodInfo> foods;
    try {
      final json = jsonDecode(utf8.decode(response.bodyBytes)) as List;
      foods = [
        for (final item in json) ?_parseFood(item as Map<String, dynamic>),
      ];
    } on FormatException {
      throw FoodApiException(_errorText);
    } on TypeError {
      throw FoodApiException(_errorText);
    }

    // Najprv názvy, ktoré hľadaným textom začínajú, potom kratšie.
    final first = nameWords.first;
    int rank(FoodInfo f) {
      final name = foldText(f.name);
      return name.startsWith(first) ? 0 : (name.contains(' $first') ? 1 : 2);
    }

    foods.sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      if (byRank != 0) return byRank;
      final byLength = a.name.length.compareTo(b.name.length);
      if (byLength != 0) return byLength;
      final byName = a.name.compareTo(b.name);
      return byName != 0 ? byName : a.prep.index.compareTo(b.prep.index);
    });
    return _cache[key] = foods.take(limit).toList();
  }

  /// Úpravy, ktorých slovo [word] začína (jazyk aplikácie + angličtina).
  static List<FoodPrep> _prepsFor(String word, AppLanguage language) => [
    for (final p in FoodPrep.values)
      if ({
        language,
        AppLanguage.en,
      }.any((l) => p.searchStems[l.index].any((stem) => word.startsWith(stem))))
        p,
  ];

  String get _errorText => const [
    'Nepodarilo sa načítať potraviny. Skontroluj pripojenie.',
    'Nepodařilo se načíst potraviny. Zkontroluj připojení.',
    'Could not load foods. Check your connection.',
  ][AppLanguage.current.index];

  /// Prevod riadku z tabuľky `foods` na [FoodInfo]. Hodnoty sú na 100 g.
  FoodInfo? _parseFood(Map<String, dynamic> f) {
    final kcal = _num(f['kcal']);
    if (kcal == null) return null;
    final en = (f['name_en'] as String?)?.trim() ?? '';
    if (en.isEmpty) return null;
    // Pri značkových výrobkoch sa značka ukáže za názvom: "Cornflakes (Nestlé)".
    final brand = (f['brand'] as String?)?.trim() ?? '';
    String name(String column) {
      final value = (f[column] as String?)?.trim() ?? '';
      final base = value.isEmpty ? en : value;
      return brand.isEmpty || foldText(base).contains(foldText(brand))
          ? base
          : '$base ($brand)';
    }

    return FoodInfo(
      id: '${f['id']}',
      names: [name('name_sk'), name('name_cs'), name('name_en')],
      prep: FoodPrep.byName(f['preparation'] as String?),
      group: FoodGroup.byName(f['food_group'] as String?),
      kcal: kcal,
      protein: _num(f['protein_g']) ?? 0,
      carbs: _num(f['carbs_g']) ?? 0,
      fat: _num(f['fat_g']) ?? 0,
      fiber: _num(f['fiber_g']) ?? 0,
      sugar: _num(f['sugars_g']) ?? 0,
    );
  }

  static double? _num(Object? v) => switch (v) {
    num() => v.toDouble(),
    String() => double.tryParse(v),
    _ => null,
  };
}

/// Písmená s diakritikou a ich základný tvar. Musí sa zhodovať s ACCENT_GROUPS
/// v tools/build_foods.py, ktorý tak istým spôsobom plní stĺpce search_*.
const _accentGroups = {
  'a': 'áäàâãåāăą',
  'c': 'čçćĉ',
  'd': 'ďđ',
  'e': 'éěèêëēęė',
  'i': 'íìîïīį',
  'l': 'ĺľł',
  'n': 'ňñń',
  'o': 'óôòöõōőø',
  'r': 'ŕř',
  's': 'šśșş',
  't': 'ťțţ',
  'u': 'úůùûüūűų',
  'y': 'ýÿ',
  'z': 'žźż',
};

final _accents = {
  for (final MapEntry(key: plain, value: chars) in _accentGroups.entries)
    for (final c in chars.split('')) c: plain,
};

/// Malé písmená bez diakritiky, len písmená, čísla a medzery – rovnako
/// ako stĺpce search_* v databáze (tools/build_foods.py, funkcia fold).
String foldText(String text) {
  final buffer = StringBuffer();
  for (final char in text.toLowerCase().split('')) {
    buffer.write(_accents[char] ?? char);
  }
  return buffer.toString().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}
