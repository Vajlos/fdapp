import 'package:flutter/material.dart';

import '../models/food.dart';
import '../widgets/donut_chart.dart';
import '../widgets/meal_items.dart';

// ---------------------------------------------------------------------------
// Detail jedla: hore graf a súčty, dole potraviny (ťukni = zmeniť potravinu)
// ---------------------------------------------------------------------------

class MealDetailPage extends StatefulWidget {
  const MealDetailPage({super.key, required this.meal, required this.title});

  final Meal meal;
  final String title;

  @override
  State<MealDetailPage> createState() => _MealDetailPageState();
}

class _MealDetailPageState extends State<MealDetailPage> {
  Meal get meal => widget.meal;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              children: [
                Text(
                  'Zjedené o ${meal.time.format(context)}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6)),
                ),
                const SizedBox(height: 16),
                Center(child: DonutChart(data: meal.gramsByGroup)),
                const SizedBox(height: 20),
                MealSummary(meal: meal),
                const SizedBox(height: 24),
                MealItemList(meal: meal, onChanged: () => setState(() {})),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
