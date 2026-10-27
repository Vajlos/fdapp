import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/food.dart';
import 'app_language.dart';

/// Online zdroj potravín. Aplikácia pozná len toto rozhranie – konkrétnu API
/// stačí doplniť v [HttpFoodApi] (alebo napísať vlastnú implementáciu)
/// a nastaviť ju vo [FoodApi.instance].
abstract class FoodApi {
  /// Používaná API. Na zmenu stačí priradiť inú implementáciu.
  static FoodApi instance = HttpFoodApi();

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
        orElse: () => results.first,
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
// HTTP implementácia – kostra pre zatiaľ neznámu API.
// TODO: po výbere API doplniť _baseUrl, _apiKey, _searchUri a _parseFood.
// ---------------------------------------------------------------------------

class HttpFoodApi extends FoodApi {
  HttpFoodApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  // TODO: adresa API, napr. 'https://api.example.com/v1'.
  static const _baseUrl = '';

  // TODO: kľúč API (ideálne cez --dart-define=FOOD_API_KEY=..., nie v kóde).
  static const _apiKey = String.fromEnvironment('FOOD_API_KEY');

  static const _timeout = Duration(seconds: 10);

  @override
  String get sourceName => 'Food API'; // TODO: názov poskytovateľa

  // Rovnaký dotaz sa nepýta znova (napr. pri návrate na hľadanie).
  final _cache = <String, List<FoodInfo>>{};

  @override
  Future<List<FoodInfo>> search(String query, {int limit = 50}) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final key = '${AppLanguage.current.name}|$limit|${q.toLowerCase()}';
    if (_cache[key] case final cached?) return cached;

    if (_baseUrl.isEmpty) {
      throw FoodApiException(
        const [
          'API potravín ešte nie je nastavená.',
          'API potravin ještě není nastavena.',
          'Food API is not configured yet.',
        ][AppLanguage.current.index],
      );
    }

    final http.Response response;
    try {
      response = await _client
          .get(_searchUri(q, limit), headers: _headers)
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
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      foods = [
        for (final item in _items(json))
          ?_parseFood(item as Map<String, dynamic>),
      ].take(limit).toList();
    } on FormatException {
      throw FoodApiException(_errorText);
    } on TypeError {
      throw FoodApiException(_errorText);
    }
    return _cache[key] = foods;
  }

  String get _errorText => const [
    'Nepodarilo sa načítať potraviny. Skontroluj pripojenie.',
    'Nepodařilo se načíst potraviny. Zkontroluj připojení.',
    'Could not load foods. Check your connection.',
  ][AppLanguage.current.index];

  // TODO: podľa API (napr. 'Authorization': 'Bearer $_apiKey' alebo 'X-Api-Key').
  Map<String, String> get _headers => {
    'Accept': 'application/json',
    if (_apiKey.isNotEmpty) 'Authorization': 'Bearer $_apiKey',
  };

  // TODO: endpoint a parametre hľadania podľa API.
  Uri _searchUri(String query, int limit) => Uri.parse('$_baseUrl/foods/search')
      .replace(
        queryParameters: {
          'query': query,
          'limit': '$limit',
          'lang': AppLanguage.current.name,
        },
      );

  // TODO: kde v odpovedi je zoznam potravín (napr. json['foods'] alebo json['items']).
  List<dynamic> _items(Object? json) => switch (json) {
    List() => json,
    {'foods': final List foods} => foods,
    {'items': final List items} => items,
    _ => const [],
  };

  /// Prevod jednej potraviny z API na [FoodInfo]. Hodnoty musia byť na 100 g.
  /// Vráti null pre položky, ktoré sa nedajú použiť (napr. bez kalórií).
  // TODO: kľúče podľa API.
  FoodInfo? _parseFood(Map<String, dynamic> f) {
    final kcal = _num(f['kcal']);
    if (kcal == null) return null;
    final name = (f['name'] as String?)?.trim() ?? '';
    if (name.isEmpty) return null;
    return FoodInfo(
      id: '${f['id']}',
      // API zvyčajne vráti názov len v jednom jazyku → rovnaký pre všetky
      names: List.filled(AppLanguage.values.length, name),
      prep: FoodPrep.byName(f['preparation'] as String?),
      group: FoodGroup.byName(f['group'] as String?),
      kcal: kcal,
      protein: _num(f['protein']) ?? 0,
      carbs: _num(f['carbs']) ?? 0,
      fat: _num(f['fat']) ?? 0,
      fiber: _num(f['fiber']) ?? 0,
      sugar: _num(f['sugar']) ?? 0,
    );
  }

  static double? _num(Object? v) => switch (v) {
    num() => v.toDouble(),
    String() => double.tryParse(v),
    _ => null,
  };
}
