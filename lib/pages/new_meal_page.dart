import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/food.dart';
import '../services/food_api.dart';
import '../services/food_recognition.dart';
import '../widgets/donut_chart.dart';
import '../widgets/meal_items.dart';

// ---------------------------------------------------------------------------
// Po odfotení: fotka + čo AI rozpoznala, automaticky spárované s potravinami z API.
// Jedlo sa uloží až po "Pridať". Vráti true cez Navigator.pop, ak ho pridal.
// ---------------------------------------------------------------------------

class NewMealPage extends StatefulWidget {
  const NewMealPage({super.key, required this.meal, required this.photo});

  final Meal meal;

  /// Už predspracovaná fotka (pozri prepareMealPhoto).
  final Uint8List photo;

  @override
  State<NewMealPage> createState() => _NewMealPageState();
}

class _NewMealPageState extends State<NewMealPage> {
  Meal get meal => widget.meal;

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _recognize();
  }

  Future<void> _recognize() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final foods = await recognizeFood(widget.photo);
      final items = await Future.wait([
        for (final f in foods) _matched(f.toFoodItem()),
      ]);
      if (!mounted) return;
      setState(() {
        meal.items
          ..clear()
          ..addAll(items);
      });
    } on FoodRecognitionException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Skúsi rovno priradiť najlepšiu zhodu z API (používateľ ju môže zmeniť).
  /// Keď API zlyhá, potravina ostane nespárovaná a vyberie sa ručne.
  Future<FoodItem> _matched(FoodItem item) async {
    try {
      final match = await FoodApi.instance.bestMatch(
        item.name,
        prep: item.prep,
        nameEn: item.nameEn,
      );
      if (match != null) item.setFood(match, item.grams);
    } on FoodApiException {
      // nespárovaná – používateľ ju vyberie ručne
    }
    return item;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.6);
    final canAdd = !_loading && meal.items.isNotEmpty && meal.allMatched;

    return Scaffold(
      appBar: AppBar(title: const Text('Nové jedlo')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Image.memory(
                          widget.photo,
                          height: 200,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (_loading)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Column(
                            children: [
                              const CircularProgressIndicator(),
                              const SizedBox(height: 16),
                              Text(
                                'Rozpoznávam jedlo…',
                                style: TextStyle(color: muted),
                              ),
                            ],
                          ),
                        )
                      else if (_error != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Column(
                            children: [
                              Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.red),
                              ),
                              const SizedBox(height: 12),
                              TextButton.icon(
                                onPressed: _recognize,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Skúsiť znova'),
                              ),
                            ],
                          ),
                        )
                      else ...[
                        Text(
                          meal.items.isEmpty
                              ? 'Nenašli sme jedlo'
                              : 'Rozpoznali sme',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          meal.items.isEmpty
                              ? 'Pridaj potraviny ručne.'
                              : 'Ťukni na potravinu a vyber presný druh (varená, surová…) '
                                    'a gramy. Potiahnutím doľava ju zmažeš.',
                          style: TextStyle(color: muted),
                        ),
                        const SizedBox(height: 20),
                        if (meal.items.isNotEmpty) ...[
                          Center(child: DonutChart(data: meal.gramsByGroup)),
                          const SizedBox(height: 20),
                          MealSummary(meal: meal),
                          const SizedBox(height: 24),
                        ],
                        MealItemList(
                          meal: meal,
                          onChanged: () => setState(() {}),
                        ),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: canAdd
                          ? () => Navigator.of(context).pop(true)
                          : null,
                      icon: const Icon(Icons.check),
                      label: Text(
                        meal.allMatched
                            ? 'Pridať do denníka'
                            : 'Najprv vyber potraviny zo zoznamu',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
