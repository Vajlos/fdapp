import 'package:flutter/material.dart';

import '../models/food.dart';
import '../services/food_api.dart';
import '../widgets/food_emoji_avatar.dart';
import 'food_search_page.dart';

// ---------------------------------------------------------------------------
// Detail potraviny: hodnoty na 100 g a na zadané množstvo.
// V režime [pick] tlačidlo "Použiť" vráti FoodPick cez pop.
// ---------------------------------------------------------------------------

class FoodInfoPage extends StatefulWidget {
  const FoodInfoPage({
    super.key,
    required this.food,
    this.grams = 100,
    this.pick = false,
  });

  final FoodInfo food;
  final int grams;
  final bool pick;

  @override
  State<FoodInfoPage> createState() => _FoodInfoPageState();
}

class _FoodInfoPageState extends State<FoodInfoPage> {
  late final _grams = TextEditingController(text: '${widget.grams}');

  FoodInfo get food => widget.food;
  int get grams => int.tryParse(_grams.text.trim()) ?? 0;

  @override
  void dispose() {
    _grams.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.6);
    final g = grams;

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              children: [
                Center(
                  child: FoodEmojiAvatar(
                    emoji: food.emoji,
                    group: food.group,
                    radius: 44,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  food.displayName,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(food.group.icon, size: 18, color: food.group.color),
                    const SizedBox(width: 6),
                    Text(food.group.label, style: TextStyle(color: muted)),
                  ],
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _grams,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Množstvo (g)'),
                ),
                const SizedBox(height: 24),
                _NutrientTable(food: food, grams: g),
                const SizedBox(height: 16),
                Text(
                  'Zdroj: ${FoodApi.instance.sourceName}',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: widget.pick
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: FilledButton.icon(
                  onPressed: g > 0
                      ? () => Navigator.of(context).pop(FoodPick(food, g))
                      : null,
                  icon: const Icon(Icons.check),
                  label: const Text('Použiť'),
                ),
              ),
            )
          : null,
    );
  }
}

class _NutrientTable extends StatelessWidget {
  const _NutrientTable({required this.food, required this.grams});

  final FoodInfo food;
  final int grams;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.6);

    String fmt(double per100, {String unit = 'g', bool round = false}) {
      final v = per100 * grams / 100;
      return round ? '${v.round()} $unit' : '${v.toStringAsFixed(1)} $unit';
    }

    String fmt100(double v, {String unit = 'g', bool round = false}) =>
        round ? '${v.round()} $unit' : '${v.toStringAsFixed(1)} $unit';

    final rows = [
      ('Energia', food.kcal, 'kcal', true),
      ('Bielkoviny', food.protein, 'g', false),
      ('Sacharidy', food.carbs, 'g', false),
      ('  z toho cukry', food.sugar, 'g', false),
      ('Tuky', food.fat, 'g', false),
      ('Vláknina', food.fiber, 'g', false),
    ];

    TableRow row(List<String> cells, {bool header = false}) => TableRow(
          children: [
            for (final (i, c) in cells.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  c,
                  textAlign: i == 0 ? TextAlign.left : TextAlign.right,
                  style: TextStyle(
                    color: header ? muted : scheme.onSurface,
                    fontWeight: header || i == 2 ? FontWeight.w700 : FontWeight.w400,
                    fontSize: header ? 12 : 15,
                  ),
                ),
              ),
          ],
        );

    return Table(
      columnWidths: const {0: FlexColumnWidth(2)},
      border: TableBorder(
        horizontalInside: BorderSide(color: scheme.onSurface.withValues(alpha: 0.1)),
      ),
      children: [
        row(['', 'na 100 g', 'na $grams g'], header: true),
        for (final (label, value, unit, round) in rows)
          row([
            label,
            fmt100(value, unit: unit, round: round),
            fmt(value, unit: unit, round: round),
          ]),
      ],
    );
  }
}
