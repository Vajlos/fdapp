import 'package:flutter/material.dart';

/// Jeden deň v horizontálnom prepínači.
class DayChip extends StatelessWidget {
  const DayChip({
    super.key,
    required this.date,
    required this.selected,
    required this.isToday,
    required this.hasMeals,
    required this.onTap,
  });

  final DateTime date;
  final bool selected;
  final bool isToday;
  final bool hasMeals;
  final VoidCallback onTap;

  static const _short = ['Po', 'Ut', 'St', 'Št', 'Pi', 'So', 'Ne'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = selected ? scheme.surface : scheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: selected ? scheme.onSurface : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: scheme.onSurface.withValues(
                alpha: selected || isToday ? 1 : 0.25,
              ),
              width: isToday && !selected ? 1.6 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _short[date.weekday - 1],
                style: TextStyle(
                  fontSize: 12,
                  color: fg.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${date.day}',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hasMeals ? fg.withValues(alpha: 0.8) : Colors.transparent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
