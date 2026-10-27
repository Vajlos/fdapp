import 'food.dart';

/// Emoji pre potravinu podľa názvu (po anglicky).
/// Mrkva má vždy 🥕, zemiaky 🥔… Ak nič nesedí, použije sa emoji skupiny.
String foodEmoji(String name, FoodGroup group) =>
    _cache.putIfAbsent('$name|${group.name}', () => _resolve(name, group));

final _cache = <String, String>{};

String _resolve(String name, FoodGroup group) {
  final parts = name.toLowerCase().split(',').map((s) => s.trim()).toList();
  final main = parts.first;
  // "Beverages, coffee" / "Nuts, almonds" – dôležitá je až druhá časť
  if (_generic.contains(main) && parts.length > 1) {
    final second = _lookup(parts[1]);
    if (second != null) return second;
  }
  return _lookup(main) ?? group.emoji;
}

String? _lookup(String text) {
  for (final (pattern, emoji) in _rules) {
    if (pattern.hasMatch(text)) return emoji;
  }
  return null;
}

/// Hlavné názvy, ktoré sú len kategóriou – hľadá sa podľa druhej časti.
const _generic = {
  'beverages', 'beverage', 'alcoholic beverage', 'alcoholic beverages',
  'nuts', 'seeds', 'fish', 'cereals', 'cereals ready-to-eat',
  'candies', 'vegetables', 'juice', 'oil', 'snacks', 'game meat',
  'crustaceans', 'mollusks', 'sweeteners', 'syrups', 'toppings', 'desserts',
  'frozen novelties', 'poultry', 'seasoning mix', 'fat', 'sugars',
};

/// Pravidlá sa skúšajú v poradí – konkrétnejšie musia byť skôr
/// (peanut pred butter, ice cream pred cream, pineapple pred apple…).
/// Kľúč je začiatok slova, koncovka s/es sa doplní sama.
final _rules = <(RegExp, String)>[
  for (final (keys, emoji) in _table)
    (RegExp(r'\b(?:' + keys + r')(?:s|es)?\b'), emoji),
];

const _table = [
  // nápoje
  ('coffee|espresso', '☕'),
  ('tea', '🍵'),
  ('beer|ale', '🍺'),
  ('wine', '🍷'),
  ('liquor|vodka|whiskey|whisky|rum|gin|brandy|liqueur|distilled', '🥃'),
  ('milk shake|shake|smoothie', '🥤'),
  ('juice|nectar|lemonade|cocktail', '🧃'),
  ('water convolvulus|watercress|waterchestnut', '🥬'),
  ('water', '💧'),
  ('carbonated beverage|soda|cola|soft drink|energy drink', '🥤'),
  // sladké
  ('ice cream|frozen yogurt|sherbet|sorbet|frozen novelty|popsicle', '🍦'),
  ('custard|flan|pudding|gelatin dessert', '🍮'),
  ('doughnut|donut', '🍩'),
  ('cookie|brownie', '🍪'),
  ('cake|cheesecake|cupcake', '🍰'),
  ('pie|tart', '🥧'),
  ('chocolate|cocoa|fudge', '🍫'),
  ('honey|syrup|molasses|jam|jelly|jellies|preserves|marmalade', '🍯'),
  ('candy|candies|chewing gum|marshmallow|sugar|sweetener', '🍬'),
  ('frosting|topping|whipped', '🧁'),
  // pečivo a obilniny
  ('croissant|danish pastry|puff pastry|pastry|pastries|sweet roll', '🥐'),
  ('bagel', '🥯'),
  ('pretzel', '🥨'),
  ('waffle', '🧇'),
  ('pancake|french toast|crepe', '🥞'),
  ('tortilla|taco|burrito', '🌮'),
  ('popcorn', '🍿'),
  ('noodle|ramen|soba|udon', '🍜'),
  ('pasta|spaghetti|macaroni|lasagna|couscous|gnocchi', '🍝'),
  ('rice|risotto', '🍚'),
  ('oat|oatmeal|granola|muesli|bran|cereal', '🥣'),
  ('bread|roll|bun|toast|biscuit|muffin|crouton|cracker|rusk|pita', '🍞'),
  ('flour|wheat|barley|rye|millet|quinoa|bulgur|buckwheat|spelt|teff|'
      'sorghum|semolina|amaranth|grain', '🌾'),
  // orechy (pred maslom a mliekom)
  ('peanut', '🥜'),
  ('coconut', '🥥'),
  ('chestnut', '🌰'),
  ('nut|almond|walnut|cashew|pistachio|hazelnut|pecan|macadamia|filbert|'
      'brazilnut|pine nut', '🥜'),
  ('seed|sesame|sunflower|chia|flax|tahini', '🌰'),
  // mliečne a vajcia
  ('cheese', '🧀'),
  ('butter|margarine|ghee', '🧈'),
  ('milk|yogurt|kefir|cream|whey|buttermilk|soymilk', '🥛'),
  ('egg', '🥚'),
  // mäso a ryby
  ('bacon', '🥓'),
  ('sausage|frankfurter|hot dog|bratwurst|kielbasa|wurst|beerwurst', '🌭'),
  ('chicken|turkey|duck|goose|hen|quail|pheasant|squab|emu|ostrich|'
      'poultry|broiler|fryer|cornish', '🍗'),
  ('ham|salami|bologna|pastrami|luncheon meat|pate|meatball|lamb|mutton|'
      'goat|venison|rabbit|game meat', '🍖'),
  ('beef|veal|bison|steak|pork|loin', '🥩'),
  ('shrimp|prawn', '🦐'),
  ('crab', '🦀'),
  ('lobster|crayfish|crustacean', '🦞'),
  ('oyster|clam|mussel|scallop|mollusk|snail', '🦪'),
  ('squid|octopus|cuttlefish', '🦑'),
  ('fish|salmon|tuna|cod|trout|herring|mackerel|sardine|carp|pike|tilapia|'
      'halibut|anchovy|catfish|bass|perch|pollock|haddock', '🐟'),
  // ovocie
  ('pineapple', '🍍'),
  ('apple|applesauce', '🍎'),
  ('pear', '🍐'),
  ('banana|plantain', '🍌'),
  ('orange|tangerine|mandarin|clementine|grapefruit', '🍊'),
  ('lemon|lime', '🍋'),
  ('watermelon', '🍉'),
  ('melon|cantaloupe|honeydew', '🍈'),
  ('grape|raisin', '🍇'),
  ('strawberry|strawberries', '🍓'),
  ('cherry|cherries', '🍒'),
  ('blueberry|blueberries|raspberry|raspberries|blackberry|blackberries|'
      'cranberry|cranberries|currant|gooseberry|gooseberries|boysenberry|'
      'boysenberries|elderberry|elderberries|berry|berries', '🫐'),
  ('peach|nectarine|apricot|plum|prune', '🍑'),
  ('mango', '🥭'),
  ('kiwi|kiwifruit', '🥝'),
  ('avocado', '🥑'),
  ('olive', '🫒'),
  // zelenina
  ('sweet potato|yam', '🍠'),
  ('potato|french fries|hash brown', '🥔'),
  ('carrot', '🥕'),
  ('tomato|catsup|ketchup', '🍅'),
  ('cucumber|pickle|gherkin', '🥒'),
  ('broccoli|cauliflower', '🥦'),
  ('corn|hominy|polenta', '🌽'),
  ('chili|jalapeno|hot pepper', '🌶️'),
  ('pepper|paprika', '🫑'),
  ('garlic', '🧄'),
  ('onion|shallot|leek|scallion|chive', '🧅'),
  ('mushroom|shiitake', '🍄'),
  ('eggplant|aubergine', '🍆'),
  ('pumpkin|squash|zucchini|courgette|gourd', '🎃'),
  ('lettuce|cabbage|kale|spinach|chard|collard|arugula|greens|brussels sprout|'
      'endive|cress|celery|bok choy', '🥬'),
  ('asparagus|sprout|shoot', '🌱'),
  ('parsley|basil|dill|mint|spearmint|herb|seaweed|coriander|cilantro|'
      'rosemary|thyme|oregano', '🌿'),
  // strukoviny
  ('bean|lentil|chickpea|garbanzo|pea|soybean|edamame|lupin|cowpea|'
      'broadbean|hummus|tofu|tempeh|falafel', '🫘'),
  // omáčky, polievky, koreniny, tuky
  ('soup|stew|broth|chowder|bouillon', '🍲'),
  ('salad dressing|dressing|mayonnaise|sauce|gravy|salsa|dip|relish', '🥫'),
  ('oil|shortening|lard|tallow|fat', '🫒'),
  ('salt|spice|seasoning|vinegar|vanilla|leavening|baking powder|'
      'baking soda|mustard|wasabi|yeast|cinnamon|nutmeg', '🧂'),
];
