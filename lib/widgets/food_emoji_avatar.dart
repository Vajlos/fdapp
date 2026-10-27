import 'package:flutter/material.dart';

import '../models/food.dart';

/// Krúžok s emoji potraviny na pozadí vo farbe jej skupiny.
class FoodEmojiAvatar extends StatelessWidget {
  const FoodEmojiAvatar({
    super.key,
    required this.emoji,
    required this.group,
    this.radius = 20,
  });

  final String emoji;
  final FoodGroup group;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: group.color.withValues(alpha: 0.25),
      child: Text(emoji, style: TextStyle(fontSize: radius * 1.05)),
    );
  }
}
