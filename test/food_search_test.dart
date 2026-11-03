import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:foodapp/models/food.dart';
import 'package:foodapp/services/food_api.dart';

/// Riadky CSV ako mapy stĺpec → hodnota (zvláda úvodzovky a čiarky v nich).
List<Map<String, String>> readCsv(String path) {
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  final text = File(path).readAsStringSync().replaceAll('\r\n', '\n');
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (quoted) {
      if (c == '"' && i + 1 < text.length && text[i + 1] == '"') {
        cell.write('"');
        i++;
      } else if (c == '"') {
        quoted = false;
      } else {
        cell.write(c);
      }
    } else if (c == '"') {
      quoted = true;
    } else if (c == ',') {
      row.add(cell.toString());
      cell.clear();
    } else if (c == '\n') {
      row.add(cell.toString());
      cell.clear();
      rows.add(row);
      row = <String>[];
    } else {
      cell.write(c);
    }
  }
  final header = rows.first;
  return [
    for (final r in rows.skip(1))
      {for (var i = 0; i < header.length; i++) header[i]: r[i]},
  ];
}

void main() {
  test('foldText removes diacritics and punctuation', () {
    expect(foldText('Kuřecí prsa'), 'kureci prsa');
    expect(foldText('  Pečené, KURACIE   prsia! '), 'pecene kuracie prsia');
  });

  test('foldText matches the search columns in data/foods.csv', () {
    for (final r in readCsv('data/foods.csv')) {
      expect(foldText('${r['name_sk']} ${r['name_en']}'), r['search_sk']);
      expect(foldText('${r['name_cs']} ${r['name_en']}'), r['search_cs']);
    }
  });

  test('data/foods_full.csv fits the app', () {
    final categories = {
      for (final c in readCsv('data/categories.csv'))
        '${c['category']}/${c['sub_category']}',
    };
    final rows = readCsv('data/foods_full.csv');
    expect(rows.length, greaterThan(2000));
    expect({for (final r in rows) r['id']}.length, rows.length);
    for (final r in rows) {
      final prep = r['preparation']!;
      expect(
        prep.isEmpty || FoodPrep.byName(prep) != FoodPrep.none,
        isTrue,
        reason: 'unknown preparation "$prep"',
      );
      expect(FoodGroup.byName(r['food_group']).name, r['food_group']);
      expect(categories, contains('${r['category']}/${r['sub_category']}'));
      final brand = r['brand']!.isEmpty ? '' : ' ${r['brand']}';
      expect(foldText('${r['name_sk']} ${r['name_en']}$brand'), r['search_sk']);
      expect(foldText('${r['name_cs']} ${r['name_en']}$brand'), r['search_cs']);
    }
  });

  test('database preparation keys map to FoodPrep', () {
    expect(FoodPrep.hardBoiled.key, 'hard_boiled');
    expect(FoodPrep.byName('soft_boiled'), FoodPrep.softBoiled);
    expect(FoodPrep.omelette.kind, FoodPrep.fried);
  });

  test('AI only chooses coarse preparations', () {
    expect(FoodPrep.aiValues, [
      FoodPrep.none,
      FoodPrep.raw,
      FoodPrep.cooked,
      FoodPrep.baked,
      FoodPrep.fried,
      FoodPrep.canned,
      FoodPrep.dried,
    ]);
    expect(FoodPrep.grilled.kind, FoodPrep.baked);
  });
}
