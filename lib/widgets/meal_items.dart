import 'package:flutter/material.dart';

import '../models/food.dart';
import '../pages/food_search_page.dart';
import 'food_item_row.dart';

/// Súčet kalórií a makroživín jedla.
class MealSummary extends StatelessWidget {
  const MealSummary({super.key, required this.meal});

  final Meal meal;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.6);

    Widget cell(String value, String label) => Expanded(
          child: Column(
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                ),
              ),
              Text(label, style: TextStyle(fontSize: 12, color: muted)),
            ],
          ),
        );

    return Row(
      children: [
        cell('${meal.totalKcal.round()}', 'kcal'),
        cell('${meal.totalProtein.round()} g', 'bielkoviny'),
        cell('${meal.totalCarbs.round()} g', 'sacharidy'),
        cell('${meal.totalFat.round()} g', 'tuky'),
      ],
    );
  }
}

/// Zoznam potravín jedla: ťuknutie = výber potraviny, potiahnutie = zmazanie.
class MealItemList extends StatelessWidget {
  const MealItemList({super.key, required this.meal, required this.onChanged});

  final Meal meal;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final item in meal.items)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Dismissible(
              key: ObjectKey(item),
              direction: DismissDirection.endToStart,
              onDismissed: (_) {
                meal.items.remove(item);
                onChanged();
              },
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 24),
                decoration: BoxDecoration(
                  color: Colors.red.shade400,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.delete_outline, color: Colors.white),
              ),
              child: FoodItemRow(
                item: item,
                onTap: () async {
                  if (await changeFoodItem(context, item)) onChanged();
                },
              ),
            ),
          ),
        TextButton.icon(
          onPressed: () async {
            final item = await newFoodItem(context);
            if (item == null) return;
            meal.items.add(item);
            onChanged();
          },
          icon: const Icon(Icons.add),
          label: const Text('Pridať potravinu'),
        ),
      ],
    );
  }
}
