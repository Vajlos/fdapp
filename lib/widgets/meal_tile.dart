import 'package:flutter/material.dart';

import '../models/food.dart';

/// Karta jedla v zozname na hlavnej obrazovke.
class MealTile extends StatelessWidget {
  const MealTile({
    super.key,
    required this.title,
    required this.meal,
    required this.onTap,
  });

  final String title;
  final Meal meal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final byGroup = meal.gramsByGroup;

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(24),
      elevation: 4,
      shadowColor: Colors.black54,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: scheme.onSurface.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: scheme.onSurface,
                child: Icon(Icons.restaurant, color: scheme.surface),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (byGroup.isEmpty)
                      Text(
                        'Ťukni a pridaj, čo si jedol',
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurface.withValues(alpha: 0.55),
                        ),
                      )
                    else
                    // pomerový pásik jedla podľa skupín
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          height: 8,
                          child: Row(
                            children: [
                              for (final e in byGroup.entries)
                                Expanded(
                                  flex: e.value,
                                  child: ColoredBox(color: e.key.color),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    meal.time.format(context),
                    style: TextStyle(
                      color: scheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  Text(
                    '${meal.totalKcal.round()} kcal',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Icon(Icons.chevron_right,
                      color: scheme.onSurface.withValues(alpha: 0.5)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
