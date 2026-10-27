import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image_picker/image_picker.dart';

import 'models/food.dart';
import 'pages/food_search_page.dart';
import 'pages/meal_detail_page.dart';
import 'pages/new_meal_page.dart';
import 'services/app_language.dart';
import 'services/meal_photo.dart';
import 'utils/dates.dart';
import 'widgets/day_chip.dart';
import 'widgets/meal_tile.dart';

// ---------------------------------------------------------------------------
// Hlavná obrazovka: dátum + prepínanie dní + zoznam jedál + fotenie
// ---------------------------------------------------------------------------

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const double _dayExtent = 60;
  static const int _dayCount = 2000;

  final DateTime _today = dateOnly(DateTime.now());
  late DateTime _selected = _today;
  final Map<DateTime, List<Meal>> _mealsByDay = {};
  final ScrollController _scroll = ScrollController();

  List<Meal> get _meals => _mealsByDay[_selected] ?? const [];

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Odfotí jedlo alebo ho vyberie z galérie, AI ho rozpozná na NewMealPage.
  /// Jedlo sa pridá až keď ho používateľ potvrdí.
  Future<void> _takePhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Odfotiť'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Vybrať z galérie'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    final day = _selected;
    final Uint8List? photo;
    try {
      photo = await pickMealPhoto(source);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fotku sa nepodarilo načítať: $e')),
        );
      }
      return;
    }
    if (photo == null || !mounted) return;
    final bytes = photo;

    final meal = Meal(time: TimeOfDay.now());
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => NewMealPage(meal: meal, photo: bytes)),
    );
    if (added != true || !mounted) return;
    setState(() => _mealsByDay.putIfAbsent(day, () => []).add(meal));
  }

  Future<void> _openMeal(Meal meal, String title) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MealDetailPage(meal: meal, title: title)),
    );
    if (mounted) setState(() {});
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selected,
      firstDate: _today.subtract(const Duration(days: _dayCount - 1)),
      lastDate: _today,
    );
    if (picked == null) return;
    final date = dateOnly(picked);
    setState(() => _selected = date);
    _scrollTo(date);
  }

  void _scrollTo(DateTime date) {
    if (!_scroll.hasClients) return;
    final daysAgo = (_today.difference(date).inHours / 24).round();
    final pos = _scroll.position;
    final target = daysAgo * _dayExtent + _dayExtent / 2 - pos.viewportDimension / 2;
    _scroll.animateTo(
      target.clamp(0.0, pos.maxScrollExtent),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final meals = _meals;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Food Diary'),
        actions: [
          // jazyk: podľa neho sa zobrazujú a hľadajú potraviny a odpovedá AI
          PopupMenuButton<AppLanguage>(
            tooltip: 'Jazyk',
            initialValue: AppLanguage.current,
            onSelected: AppLanguageController.instance.set,
            itemBuilder: (_) => [
              for (final l in AppLanguage.values)
                PopupMenuItem(value: l, child: Text('${l.flag}  ${l.label}')),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                AppLanguage.current.flag,
                style: const TextStyle(fontSize: 22),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Potraviny',
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const FoodSearchPage()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await GoogleSignIn.instance.signOut();
              await FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _takePhoto,
        backgroundColor: scheme.onSurface,
        foregroundColor: scheme.surface,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        icon: const Icon(Icons.photo_camera_outlined),
        label: const Text('Odfotiť jedlo'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 12, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          formatDate(_selected),
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.calendar_month_outlined),
                        onPressed: _pickDate,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 76,
                  // reverse: dnes je vpravo, listovaním doľava ideš do minulosti
                  child: ListView.builder(
                    controller: _scroll,
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    itemExtent: _dayExtent,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: _dayCount,
                    itemBuilder: (_, i) {
                      final date = DateTime(
                        _today.year,
                        _today.month,
                        _today.day - i,
                      );
                      return DayChip(
                        date: date,
                        selected: date == _selected,
                        isToday: i == 0,
                        hasMeals: (_mealsByDay[date] ?? const []).isNotEmpty,
                        onTap: () => setState(() => _selected = date),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: meals.isEmpty
                      ? const Center(child: _EmptyState())
                      : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 110),
                    itemCount: meals.length,
                    itemBuilder: (_, i) {
                      final meal = meals[i];
                      final title = 'Jedlo ${i + 1}';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Dismissible(
                          key: ObjectKey(meal),
                          direction: DismissDirection.endToStart,
                          onDismissed: (_) =>
                              setState(() => meals.remove(meal)),
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 24),
                            decoration: BoxDecoration(
                              color: Colors.red.shade400,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: const Icon(Icons.delete_outline,
                                color: Colors.white),
                          ),
                          child: MealTile(
                            title: title,
                            meal: meal,
                            onTap: () => _openMeal(meal, title),
                          ),
                        ),
                      );
                    },
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

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.photo_camera_outlined,
            size: 56, color: color.withValues(alpha: 0.4)),
        const SizedBox(height: 12),
        Text(
          'Tento deň zatiaľ žiadne jedlo.\nKlikni na „Odfotiť jedlo“.',
          textAlign: TextAlign.center,
          style: TextStyle(color: color.withValues(alpha: 0.6)),
        ),
      ],
    );
  }
}
