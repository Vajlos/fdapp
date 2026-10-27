import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_ai/firebase_ai.dart';

import '../models/food.dart';
import 'app_language.dart';

/// Jedna samostatná potravina, ktorú model našiel na fotke.
/// [name] je krátky názov v jazyku aplikácie (napr. "ryža"), podľa ktorého
/// sa hľadá v API potravín, [nameEn] ten istý po anglicky (záloha pri hľadaní),
/// [prep] je úprava z našich typov (FoodPrep).
class RecognizedFood {
  RecognizedFood({
    required this.name,
    required this.nameEn,
    required this.prep,
    required this.group,
    required this.grams,
  });

  final String name;
  final String nameEn;
  final FoodPrep prep;
  final FoodGroup group;
  final int grams;

  FoodItem toFoodItem() => FoodItem(name, group, grams, prep: prep, nameEn: nameEn);

  factory RecognizedFood.fromJson(Map<String, dynamic> json) {
    return RecognizedFood(
      name: (json['name'] as String?)?.trim().toLowerCase() ?? '?',
      nameEn: (json['name_en'] as String?)?.trim().toLowerCase() ?? '',
      prep: FoodPrep.byName(json['preparation'] as String?),
      group: FoodGroup.byName(json['group'] as String?),
      grams: (json['grams'] as num?)?.round() ?? 0,
    );
  }
}

/// Chyba pri rozpoznávaní – [message] sa dá ukázať používateľovi.
class FoodRecognitionException implements Exception {
  FoodRecognitionException(this.message);
  final String message;

  @override
  String toString() => message;
}

const _modelName = 'gemini-3.1-flash-lite';

// Názov je v jazyku aplikácie (hľadá sa v API v tom istom jazyku),
// name_en je záloha po anglicky. Zložené jedlá sa rozkladajú na potraviny.
String _prompt(AppLanguage language) => '''
You are the vision step of a food diary app. List every single (whole) food
visible in the photo.

Never return a composed dish as one item. Break it into its visible components:
a burger becomes bun, beef, cheese, lettuce, tomato; a pizza becomes pizza dough,
tomato sauce, mozzarella and toppings; a sandwich becomes bread and its fillings.

Return one item per food:
- name: short generic name of the food in ${language.englishName}, lowercase,
  without preparation or details (in English e.g. "rice", "chicken breast",
  "potatoes", "broccoli", "bread", "gravy", "cream sauce"). Do not guess brands.
- name_en: the same short name in English.
- preparation: how the food is prepared, exactly one of:
  raw (fresh, uncooked), cooked (boiled, steamed, stewed), baked (roasted,
  grilled, baked in oven or on a pan without much oil), fried (fried in oil),
  canned, dried, none (ready-made foods that are not prepared further,
  like bread, cheese, milk, yogurt, sauces).
- group: the closest group from the list.
- grams: estimated weight of the visible portion in grams (integer).

If there is no food in the photo, return an empty items list.
''';

final _schema = Schema.object(
  properties: {
    'items': Schema.array(
      items: Schema.object(
        properties: {
          'name': Schema.string(),
          'name_en': Schema.string(),
          'preparation': Schema.enumString(
            enumValues: [for (final p in FoodPrep.values) p.name],
          ),
          'group': Schema.enumString(
            enumValues: [for (final g in FoodGroup.values) g.name],
          ),
          'grams': Schema.integer(),
        },
      ),
    ),
  },
);

final _model = FirebaseAI.googleAI().generativeModel(
  model: _modelName,
  generationConfig: GenerationConfig(
    responseMimeType: 'application/json',
    responseSchema: _schema,
  ),
);

/// Pošle fotku jedla do Gemini a vráti zoznam rozpoznaných potravín.
/// Fotku pred odoslaním zmenši (napr. max 1024 px) – je to rýchlejšie a lacnejšie.
Future<List<RecognizedFood>> recognizeFood(
  Uint8List imageBytes, {
  String mimeType = 'image/jpeg',
}) async {
  final GenerateContentResponse response;
  try {
    response = await _model.generateContent([
      Content.multi([
        TextPart(_prompt(AppLanguage.current)),
        InlineDataPart(mimeType, imageBytes),
      ]),
    ]);
  } on FirebaseAIException catch (e) {
    throw FoodRecognitionException('Rozpoznanie zlyhalo: ${e.message}');
  }

  final text = response.text;
  if (text == null || text.isEmpty) {
    throw FoodRecognitionException('Model nevrátil žiadnu odpoveď.');
  }

  try {
    final json = jsonDecode(text) as Map<String, dynamic>;
    final items = (json['items'] as List? ?? const []);
    return [
      for (final i in items.whereType<Map<String, dynamic>>())
        RecognizedFood.fromJson(i),
    ].where((f) => f.grams > 0).toList();
  } on FormatException {
    throw FoodRecognitionException('Odpoveď modelu sa nedala prečítať.');
  }
}
