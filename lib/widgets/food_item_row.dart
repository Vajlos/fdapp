import 'package:flutter/material.dart';

import '../models/food.dart';
import 'food_emoji_avatar.dart';

/// Riadok jednej potraviny v jedle: farba skupiny, názov z API
/// (alebo od AI, kým nie je vybraná), kalórie a gramy.
class FoodItemRow extends StatelessWidget {
  const FoodItemRow({
    super.key,
    required this.item,
    required this.onTap,
  });

  final FoodItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = item.group.color;
    final food = item.food;
    final aiName = item.name.isEmpty
        ? item.name
        : item.name[0].toUpperCase() + item.name.substring(1);

    return Material(
      color: c.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: c, width: 1.2),
          ),
          child: Row(
            children: [
              FoodEmojiAvatar(emoji: item.emoji, group: item.group),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      food?.displayName ??
                          (item.prep == FoodPrep.none
                              ? aiName
                              : '$aiName · ${item.prep.label}'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      food == null
                          ? 'Ťukni a vyber potravinu'
                          : '${item.kcal.round()} kcal',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: food == null ? FontWeight.w700 : FontWeight.w400,
                        color: food == null
                            ? Colors.red.shade400
                            : scheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${item.grams} g',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
