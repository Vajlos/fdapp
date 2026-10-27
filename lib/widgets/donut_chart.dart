import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/food.dart';

/// Prstencový graf podľa gramov na skupinu. Bez balíčkov, vlastný painter.
class DonutChart extends StatelessWidget {
  const DonutChart({super.key, required this.data});

  final Map<FoodGroup, int> data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = data.values.fold(0, (a, b) => a + b);

    return SizedBox(
      width: 240,
      height: 240,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size.square(240),
            painter: _DonutPainter(
              data: data,
              track: scheme.onSurface.withValues(alpha: 0.12),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$total',
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                ),
              ),
              Text(
                'gramov',
                style: TextStyle(
                  color: scheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.data, required this.track});

  final Map<FoodGroup, int> data;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 30.0;
    final rect = Offset(stroke / 2, stroke / 2) &
    Size(size.width - stroke, size.height - stroke);
    final total = data.values.fold(0, (a, b) => a + b);

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    if (total == 0) {
      canvas.drawArc(rect, 0, math.pi * 2, false, trackPaint);
      return;
    }

    final gap = data.length > 1 ? 0.06 : 0.0;
    var start = -math.pi / 2;
    for (final e in data.entries) {
      final sweep = e.value / total * math.pi * 2;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt
        ..color = e.key.color;
      canvas.drawArc(
        rect,
        start + gap / 2,
        math.max(sweep - gap, 0.001),
        false,
        paint,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => true;
}
