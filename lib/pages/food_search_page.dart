import 'dart:async';

import 'package:flutter/material.dart';

import '../models/food.dart';
import '../services/app_language.dart';
import '../services/food_api.dart';
import '../widgets/food_emoji_avatar.dart';
import 'food_info_page.dart';

/// Výsledok výberu potraviny: čo a koľko gramov.
class FoodPick {
  const FoodPick(this.food, this.grams);
  final FoodInfo food;
  final int grams;
}

/// Otvorí hľadanie v režime výberu. Vráti null, ak používateľ nič nevybral.
Future<FoodPick?> pickFood(
  BuildContext context, {
  String query = '',
  int grams = 100,
}) {
  return Navigator.of(context).push<FoodPick>(
    MaterialPageRoute(
      builder: (_) =>
          FoodSearchPage(initialQuery: query, grams: grams, pick: true),
    ),
  );
}

/// Ťuknutie na potravinu v jedle: hľadá v API podľa názvu od AI
/// a priradí vybranú potravinu aj gramy. Vráti true, ak sa niečo zmenilo.
Future<bool> changeFoodItem(BuildContext context, FoodItem item) async {
  final picked = await pickFood(context, query: item.name, grams: item.grams);
  if (picked == null) return false;
  item.setFood(picked.food, picked.grams);
  return true;
}

/// Ručné pridanie potraviny do jedla (prázdne hľadanie).
Future<FoodItem?> newFoodItem(BuildContext context) async {
  final picked = await pickFood(context);
  if (picked == null) return null;
  final f = picked.food;
  return FoodItem(f.name, f.group, picked.grams, food: f);
}

// ---------------------------------------------------------------------------
// Hľadanie potravín cez API. V režime [pick] sa výber vráti cez pop.
// ---------------------------------------------------------------------------

class FoodSearchPage extends StatefulWidget {
  const FoodSearchPage({
    super.key,
    this.initialQuery = '',
    this.grams = 100,
    this.pick = false,
  });

  final String initialQuery;
  final int grams;
  final bool pick;

  @override
  State<FoodSearchPage> createState() => _FoodSearchPageState();
}

class _FoodSearchPageState extends State<FoodSearchPage> {
  late final _query = TextEditingController(text: widget.initialQuery);
  bool _loading = false;
  String? _error;
  List<FoodInfo> _results = const [];
  Timer? _debounce;

  // Číslo posledného hľadania – staršie odpovede z API sa zahodia.
  int _searchId = 0;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  /// Pri písaní sa na API pýta až po krátkej pauze.
  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _search);
  }

  Future<void> _search() async {
    _debounce?.cancel();
    final id = ++_searchId;
    final query = _query.text;
    if (query.trim().isEmpty) {
      setState(() {
        _loading = false;
        _error = null;
        _results = const [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await FoodApi.instance.search(query);
      if (!mounted || id != _searchId) return;
      setState(() => _results = results);
    } on FoodApiException catch (e) {
      if (!mounted || id != _searchId) return;
      setState(() {
        _results = const [];
        _error = e.message;
      });
    } finally {
      if (mounted && id == _searchId) setState(() => _loading = false);
    }
  }

  Future<void> _open(FoodInfo food) async {
    final picked = await Navigator.of(context).push<FoodPick>(
      MaterialPageRoute(
        builder: (_) =>
            FoodInfoPage(food: food, grams: widget.grams, pick: widget.pick),
      ),
    );
    if (picked != null && mounted) Navigator.of(context).pop(picked);
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface
        .withValues(alpha: 0.6);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pick ? 'Vyber potravinu' : 'Potraviny'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                  child: TextField(
                    controller: _query,
                    autofocus: widget.initialQuery.isEmpty,
                    textInputAction: TextInputAction.search,
                    onChanged: _onChanged,
                    onSubmitted: (_) => _search(),
                    decoration: InputDecoration(
                      labelText: const [
                        'Hľadať, napr. ryža varená',
                        'Hledat, např. rýže vařená',
                        'Search, e.g. rice cooked',
                      ][AppLanguage.current.index],
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.red),
                                ),
                                const SizedBox(height: 12),
                                TextButton.icon(
                                  onPressed: _search,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Skúsiť znova'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _results.isEmpty
                      ? Center(
                          child: Text(
                            _query.text.trim().isEmpty
                                ? 'Napíš, čo hľadáš.'
                                : 'Nič sa nenašlo.',
                            style: TextStyle(color: muted),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                          itemCount: _results.length,
                          itemBuilder: (_, i) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: FoodInfoTile(
                              food: _results[i],
                              onTap: () => _open(_results[i]),
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

/// Karta potraviny vo výsledkoch hľadania (rovnaký štýl ako potraviny v jedle).
class FoodInfoTile extends StatelessWidget {
  const FoodInfoTile({super.key, required this.food, required this.onTap});

  final FoodInfo food;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = food.group.color;

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
              FoodEmojiAvatar(emoji: food.emoji, group: food.group),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      food.displayName,
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
                      'B ${food.protein.toStringAsFixed(1)} · '
                      'S ${food.carbs.toStringAsFixed(1)} · '
                      'T ${food.fat.toStringAsFixed(1)} g / 100 g',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${food.kcal.round()} kcal',
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
