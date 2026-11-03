"""Build a whole-foods catalog from USDA FoodData Central CSV exports (Foundation + SR Legacy).

Usage: python tools/build_foods.py <csv_dir> <output_csv>

Keeps only whole foods (no brands, ready meals, mixes, sauces, sweets...). Each
food is reduced to a short name ("Chicken breast") plus a preparation
("raw", "roasted", ...); all USDA variants of the same name + preparation are
merged into one row using the median of their nutrients (per 100 g).
Slovak and Czech names come from data/food_translations.csv.
"""
import csv
import re
import statistics
import sys
from collections import Counter, defaultdict
from pathlib import Path

# (column, [nutrient ids in order of preference])
NUTRIENTS = [
    ("kcal", [1008, 2048, 2047]),
    ("protein_g", [1003]),
    ("fat_g", [1004, 1085]),
    ("saturated_fat_g", [1258]),
    ("carbs_g", [1005, 1050]),
    ("sugars_g", [2000, 1063]),
    ("fiber_g", [1079, 2033]),
    ("sodium_mg", [1093]),
    ("cholesterol_mg", [1253]),
    ("potassium_mg", [1092]),
    ("calcium_mg", [1087]),
    ("iron_mg", [1089]),
    ("vitamin_c_mg", [1162]),
]
WANTED_IDS = {nid for _, ids in NUTRIENTS for nid in ids}

TRANSLATIONS = Path(__file__).resolve().parent.parent / "data" / "food_translations.csv"

DATASETS = ["2", "3"]  # FoodData Central file suffixes: Foundation, SR Legacy
FOOD_TYPES = {"foundation_food", "sr_legacy_food"}

KEPT_CATEGORIES = {
    "Dairy and Egg Products", "Spices and Herbs", "Fats and Oils", "Poultry Products",
    "Fruits and Fruit Juices", "Pork Products", "Vegetables and Vegetable Products",
    "Nut and Seed Products", "Beef Products", "Beverages", "Alcoholic Beverages",
    "Finfish and Shellfish Products", "Legumes and Legume Products",
    "Lamb, Veal, and Game Products", "Cereal Grains and Pasta",
}
# Categories where a food without an explicit preparation is raw (e.g. "Tomato, roma")
RAW_BY_DEFAULT = {
    "Poultry Products", "Fruits and Fruit Juices", "Pork Products",
    "Vegetables and Vegetable Products", "Beef Products", "Finfish and Shellfish Products",
    "Lamb, Veal, and Game Products",
}
DRY_CATEGORIES = {"Cereal Grains and Pasta", "Legumes and Legume Products"}

# USDA category -> FoodGroup.name in the app (lib/models/food.dart)
FOOD_GROUPS = {
    "Beef Products": "meat", "Pork Products": "meat", "Poultry Products": "meat",
    "Lamb, Veal, and Game Products": "meat", "Finfish and Shellfish Products": "fish",
    "Dairy and Egg Products": "dairy", "Vegetables and Vegetable Products": "vegetables",
    "Fruits and Fruit Juices": "fruit", "Legumes and Legume Products": "legumes",
    "Nut and Seed Products": "nuts", "Cereal Grains and Pasta": "grains",
    "Fats and Oils": "fats", "Spices and Herbs": "other", "Beverages": "drinks",
    "Sweets": "sweets", "Baked Products": "grains", "Sausages and Luncheon Meats": "meat",
}

# Basic foods kept even though their category or wording is otherwise filtered out
ALLOWED = re.compile(r"""^(?:
    sugars?,\ (?:granulated|brown|powdered)$|honey$|syrups,\ maple$|
    bread,\ (?:white,\ commercially\ prepared|whole-wheat,\ commercially\ prepared|rye|
              multi-grain\ \(includes\ whole-grain\)|french\ or\ vienna\ \(includes\ sourdough\)|
              pumpernickel)$|
    rolls,\ (?:dinner,\ plain,\ commercially\ prepared.*|hard.*|dinner,\ whole-wheat)$|
    ham,\ sliced,\ regular.*
)""", re.IGNORECASE | re.VERBOSE)

# Anything matching these is a product, mix or dish rather than a whole food
EXCLUDE = re.compile(r"""\b(?:
    juice|nectar|drink|punch|lemonade|limeade|soda|cola|carbonated|energy|cocktail|smoothie|shake|
    mix|mixes|mixture|syrup|sweetened|sugar\ added|with\ sugar|with\ added\ sugar|flavou?red|
    fortified|
    chocolate|vanilla|strawberry|prepared\ (?:with|from)\ (?!calcium|nigari|magnesium)|made\ with|
    instant|powder|powdered|concentrate|substitutes?|imitation|analog|
    sauce|soup|gravy|dressing|spread|margarine|shortening|mayonnaise|relish|pickled?|pickles|pie|
    salad(?!\ or\ cooking)|breaded|batter|coated|stuffed|dinner|entree|sandwich|souffle|omelet|
    process|processed|cheese\ food|baby|infant|toddler|candied|candies|
    bbq|teriyaki|marinated|seasoned|seasoning|pre-basted|with\ cream|creamer|whitener|
    mechanically|composite|formula|formulated|protein\ (?:isolate|concentrate)|meal|
    chips|crackers|fries|french\ fried|hash\ brown|puffs|au\ gratin|scalloped|mashed|o'brien|
    with\ (?:cheese|butter|sauce|onion|pork|beef|chicken|ham|bacon|franks)|in\ (?:oil|olive\ oil|tomato|sauce)|
    solids\ and\ liquids|water\ pack|juice\ pack|liquid\ from|puree|paste|crushed|
    cured|ham|luncheon|sausage|frankfurter|bologna|salami|jerky|pastrami|corned|canadian\ bacon|
    bacon\ bits|separable\ fat|suet|backfat|seal\ oil|
    eggnog|dulce|custard|pudding|dessert|topping|ice\ cream|whipped|supplement|
    daiquiri|pina\ colada|tequila\ sunrise|whiskey\ sour|liqueur|creme\ de\ menthe|horchata|malt|
    refried|frijoles|succotash|vegetables,\ mixed|peas\ and|greens\ and|chili\ with|baked\ beans|
    beans,\ baked|potato\ pancakes|nuggets|patty|patties|meatloaf|burgers?|fillets|vegetarian|
    meatless|extender|surimi|gefiltefish|pate|papad|poi|okara|kimchi|catsup|ketchup|hummus|
    chowchow|stabilized|mixed\ nuts|melon\ balls|maraschino|filled|producer|human|
    nutritional|vitasoy|reddi\ wip|powerade|yogurt,\ (?:fruit|tofu)|tofu\ yogurt|horned\ melon|
    prepared(?!\ with\ (?:calcium|magnesium|nigari))|precooked|fish\ sticks|falafel|omega-3|
    industrial|lecithin|wine,\ (?:cooking|non-alcoholic)|restaurant|cake|cereal|crackers?|
    vermicelli\ mix|rice\ mix|beerwurst|wedges
)\b""", re.IGNORECASE | re.VERBOSE)

# A word of 3+ capitals usually means a brand (CHOBANI, KELLOGG'S, SILK...)
BRAND = re.compile(r"\b[A-Z][A-Z&]{2,}\b|®|™")
BRAND_OK = {"USDA", "NFS", "UHT", "USA"}

# Words that only qualify a food and never belong in its name
FILLER = re.compile(r"""^(?:
    raw|fresh|all\ (?:types|varieties|classes|grades|commercial\ varieties|areas|kinds)|regular|all|
    commercial|commercially\ prepared|domestic|imported|home-prepared|includes.*|usda.*|
    new\ zealand|australian|grass-fed|enhanced|natural|organic|wild|farmed|wild\ caught|
    whole\ grain|separable\ lean.*|lean\ only|choice|select|prime|
    boneless|bone-in|with\ bone|without\ bone|bone\ removed|trimmed\ to.*|\d.*|
    with(?:out)?\ (?:added\ )?salt.*|salted|unsalted|no\ salt\ added|sodium\ added|low[\ -]sodium|
    salt\ added.*|with(?:out)?\ added.*|prepared\ with.*|remaining.*|common|table|
    mature.*|fluid|freshly\ harvest|stored|
    enriched|unenriched|drained|drained\ solids|unheated|heated|regular\ pack|
    mature\ seeds|mature|immature\ seeds|kernels|edible\ portion|peeled|unpeeled|
    with(?:out)?\ (?:skin|peel)|flesh.*|cooked\ in\ skin|cooked\ without\ skin|in\ skin|
    (?:large|medium|small)|retail\ cuts?|ns\ as\ to.*|nfs|plain|pasteurized|refrigerated|
    shelf\ stable|retail|packaged|bulk|chopped(?:\ or\ leaf)?|leaf|spears|unsweetened|
    freeze-dried|sulfured|seedless|uncreamed|fluid|grade\ a|vacuum\ pack|
    long-grain|medium-grain|short-grain|parboiled|glutinous|unprepared
)$""", re.IGNORECASE | re.VERBOSE)

# (pattern, label) checked in order; the first match is the preparation
PREPARATIONS = [
    (r"stir-fried|pan-fried|deep-fried|fried", "fried"),
    (r"roasted", "roasted"),
    (r"baked", "baked"),
    (r"grilled", "grilled"),
    (r"broiled", "broiled"),
    (r"braised", "braised"),
    (r"stewed", "stewed"),
    (r"steamed", "steamed"),
    (r"hard-boiled|boiled|simmered|moist heat|poached", "boiled"),
    (r"scrambled", "scrambled"),
    (r"microwaved", "microwaved"),
    (r"smoked", "smoked"),
    (r"dry heat|cooked", "cooked"),
    (r"canned", "canned"),
    (r"dried|dehydrated", "dried"),
    (r"frozen", "frozen"),
]
PREP_WORD = re.compile(
    r"^(?:cooked|uncooked|raw|fresh|canned|frozen|dry|dried|dehydrated|smoked|"
    r"(?:pan-|stir-|deep-)?fried|roasted|baked|grilled|broiled|braised|stewed|steamed|"
    r"(?:hard-)?boiled|simmered|poached|scrambled|microwaved|moist heat|dry heat|"
    r"fast roasted|dry roasted|oil roasted|dry-roasted|oil-roasted|toasted|blanched|sprouted|"
    r"pasteurized|unprepared|raw or frozen)$",
    re.IGNORECASE,
)

# Leading words that just name the group ("Fish, salmon" -> "Salmon")
GROUP_PREFIXES = {"fish", "nuts", "seeds", "spices", "beverages", "alcoholic beverage",
                  "alcoholic beverages", "mollusks", "crustaceans", "game meat"}

# Foods where the second word is a real type ("Rice, brown", "Milk, whole"); others keep just the head
TYPED_HEADS = {
    "beans", "peas", "cheese", "oil", "milk", "cream", "rice", "wheat flour", "wheat flours",
    "flour", "pasta", "noodles", "peppers", "mushrooms", "mushroom", "squash", "cabbage", "egg",
    "eggs", "fat", "fish oil", "corn", "lentils", "yogurt", "sour cream", "vinegar", "seaweed",
    "whey", "cornmeal", "barley", "sorghum grain", "soybeans", "lima beans", "cowpeas", "tofu",
    "coconut", "butter", "chard", "melons", "taro", "buttermilk",
}
# "whole" is a type only for these ("Milk, whole"); elsewhere it is filler ("Onions, whole")
WHOLE_IS_TYPE = {"milk", "egg", "eggs", "yogurt"}
PLANT_PARTS = {"leaves", "shoots", "leafy tips", "young pods with seeds", "tuber", "flowers"}

# Descriptions that need a hand-picked name: (regex on description, name)
NAME_RULES = [
    (r"^Alcoholic beverage, beer", "Beer"),
    (r"^Alcoholic beverage, wine, table, red", "Red wine"),
    (r"^Alcoholic beverage, wine, (?:table, white|light)", "White wine"),
    (r"^Alcoholic beverage, wine, rose", "Rose wine"),
    (r"^Alcoholic beverage, wine, dessert", "Dessert wine"),
    (r"^Alcoholic beverage, wine", "Wine"),
    (r"^Alcoholic beverage, distilled", "Spirits"),
    (r"^Onions, (?:spring|young green)", "Spring onions"),
    (r"^Radishes, oriental", "Daikon"),
    (r"^Potatoes,(?!.*flesh).*\bskin\b", "Potato skin"),
    (r"^Eggs?,(?:.*\begg)? whole\b", "Egg"),
    (r"^Sugars?, granulated", "Sugar"),
    (r"^Sugars?, brown", "Brown sugar"),
    (r"^Sugars?, powdered", "Powdered sugar"),
    (r"^Syrups, maple", "Maple syrup"),
    (r"^Bread, white", "White bread"),
    (r"^Bread, whole-wheat", "Whole-wheat bread"),
    (r"^Bread, rye", "Rye bread"),
    (r"^Bread, multi-grain", "Multigrain bread"),
    (r"^Bread, french or vienna", "Baguette"),
    (r"^Bread, pumpernickel", "Pumpernickel bread"),
    (r"^Rolls, dinner, whole-wheat", "Whole-wheat roll"),
    (r"^Rolls, ", "Bread roll"),
    (r"^Ham, sliced", "Ham"),
    (r"^Eggs?,(?:.*\begg)? white\b", "Egg white"),
    (r"^Eggs?,(?:.*\begg)? yolk\b", "Egg yolk"),
    (r"^Lettuce, (?:cos or )?romaine", "Romaine lettuce"),
    (r"^Lettuce, iceberg", "Iceberg lettuce"),
    (r"^Lettuce", "Lettuce"),
    (r"^Peanut butter", "Peanut butter"),
]
NAME_RULES = [(re.compile(p, re.IGNORECASE), n) for p, n in NAME_RULES]

MEATS = {"chicken", "turkey", "duck", "goose", "beef", "pork", "lamb", "veal", "ostrich", "emu",
         "quail", "pheasant", "guinea hen", "squab", "rabbit", "goat", "bison", "deer",
         "elk", "moose", "game meat", "buffalo", "boar", "antelope", "caribou", "horse"}
# Checked in order: the first part found in the description becomes part of the name
MEAT_PARTS = [
    "breast", "thigh", "drumstick", "wing", "leg", "back", "neck", "giblets", "gizzard",
    "liver", "heart", "kidneys?", "tongue", "brain", "tripe", "skin", "dark meat", "light meat",
    "ground", "tenderloin", "sirloin", "brisket", "flank", "skirt", "ribeye", "spareribs",
    "backribs", "rib", "chuck", "round", "shank", "short loin", "top loin", "loin", "shoulder",
    "belly", "bacon", "chop", "steak",
]
MEAT_PART_RE = [(p.removesuffix("s?"), re.compile(rf"\b{p}\b", re.IGNORECASE)) for p in MEAT_PARTS]

RENAMES = {"Pork loin": "Pork", "Turkey from whole": "Turkey"}


def read(path):
    with open(path, newline="", encoding="utf-8") as f:
        yield from csv.DictReader(f)


def is_brand(description):
    return any(w not in BRAND_OK for w in BRAND.findall(description))


def preparation(description, category):
    text = description.lower()
    for pattern, label in PREPARATIONS:
        if re.search(rf"\b(?:{pattern})\b", text):
            return label
    if category in DRY_CATEGORIES and re.search(r"\b(?:dry|uncooked)\b", text):
        return "raw"
    if category == "Dairy and Egg Products" and re.search(r"\bdry\b", text):
        return "dried"  # milk powder must not merge with fluid milk
    if re.search(r"\b(?:raw|fresh)\b", text) or category in RAW_BY_DEFAULT or text.startswith("egg"):
        return "raw"
    return ""


def food_name(description):
    for pattern, name in NAME_RULES:
        if pattern.search(description):
            return name

    text = re.sub(r"\(.*?\)|\(.*$", "", description)
    tokens = [re.sub(r"\s+", " ", t).strip(" .-") for t in text.split(",")]
    tokens = [t for t in tokens if t]
    head, rest = tokens[0], tokens[1:]

    if head.lower() in GROUP_PREFIXES and rest:
        head, rest = rest[0], rest[1:]
        head = head[:1].upper() + head[1:]
    head = RENAMES.get(head, head)

    if head.lower() in MEATS:
        body = description.lower()
        part = next((p for p, rx in MEAT_PART_RE if rx.search(body)), None)
        if part == "ground":
            return f"Ground {head.lower()}"
        return f"{head.capitalize()} {part}" if part else head.capitalize()

    head = RENAMES.get(head, head)
    if head.lower() in TYPED_HEADS:
        for token in rest:
            if PREP_WORD.match(token) or FILLER.match(token):
                continue
            if token.lower() == "whole" and head.lower() not in WHOLE_IS_TYPE:
                continue
            kind = token.lower()
            # "Cheese, feta" -> "Feta cheese", "Milk, buttermilk" -> "Buttermilk"
            if head.lower() in kind or kind.endswith("butter"):
                name = kind
            elif kind in PLANT_PARTS:
                name = f"{head.lower()} {kind}"  # "Taro, leaves" -> "Taro leaves"
            elif head.lower() == "fat" and "tallow" in kind:
                name = kind  # "Fat, beef tallow" -> "Beef tallow"
            else:
                name = f"{kind} {head.lower()}"
            return name[:1].upper() + name[1:]
    return head


def food_group(name_en, category):
    group = FOOD_GROUPS.get(category, "other")
    if group == "dairy":
        lower = name_en.lower()
        if re.search(r"\begg", lower):
            return "eggs"
        if "cheese" in lower:
            return "cheese"
    return group


# Letters with diacritics and their plain form. Must stay identical to _accentGroups
# in lib/services/food_api.dart, which folds search queries the same way.
ACCENT_GROUPS = {
    "a": "áäàâãåāăą", "c": "čçćĉ", "d": "ďđ", "e": "éěèêëēęė", "i": "íìîïīį",
    "l": "ĺľł", "n": "ňñń", "o": "óôòöõōőø", "r": "ŕř", "s": "šśșş", "t": "ťțţ",
    "u": "úůùûüūűų", "y": "ýÿ", "z": "žźż",
}
ACCENTS = str.maketrans({c: plain for plain, chars in ACCENT_GROUPS.items() for c in chars})


def fold(text):
    """Lowercase text without diacritics, only letters, digits and single spaces."""
    return re.sub(r"[^a-z0-9]+", " ", text.lower().translate(ACCENTS)).strip()


def group_key(name):
    """Spelling-insensitive key so "Apricot"/"Apricots" and "Mahi mahi"/"Mahimahi" land in one row."""
    words = re.findall(r"[a-z0-9]+", name.lower())
    singular = [re.sub(r"(?:ves|oes|ies|s)$",
                       lambda m: {"ves": "f", "oes": "o", "ies": "y"}.get(m.group(), ""), w)
                for w in words]
    return "".join(singular)


def main(csv_dir, out_path):
    csv_dir = Path(csv_dir)
    categories = {r["id"]: r["description"] for r in read(csv_dir / "food_category (2).csv")}

    seen_descriptions = set()
    foods = {}  # fdc_id -> food
    for suffix in DATASETS:
        batch = {}
        for r in read(csv_dir / f"food ({suffix}).csv"):
            description = r["description"].strip()
            category = categories.get(r["food_category_id"], "")
            if r["data_type"] not in FOOD_TYPES:
                continue
            if not ALLOWED.search(description) and (
                    category not in KEPT_CATEGORIES or EXCLUDE.search(description)
                    or is_brand(description)):
                continue
            batch[r["fdc_id"]] = {"description": description, "category": category, "nutrients": {}}

        for r in read(csv_dir / f"food_nutrient ({suffix}).csv"):
            food = batch.get(r["fdc_id"])
            if food and r["amount"] and int(r["nutrient_id"]) in WANTED_IDS:
                food["nutrients"][int(r["nutrient_id"])] = float(r["amount"])

        for fdc_id, food in batch.items():
            if not any(i in food["nutrients"] for i in NUTRIENTS[0][1]):
                continue  # no energy value: not useful for a food diary
            # Same description in both datasets: Foundation (read first) wins,
            # but only when it actually has nutrients
            key = re.sub(r"[^a-z0-9]+", " ", food["description"].lower()).strip()
            if key not in seen_descriptions:
                seen_descriptions.add(key)
                foods[fdc_id] = food

    groups = defaultdict(list)
    for food in foods.values():
        food["name"] = food_name(food["description"])
        prep = preparation(food["description"], food["category"])
        groups[(group_key(food["name"]), prep)].append(food)

    # One display name per food across all its preparations
    spellings = defaultdict(Counter)
    for (key, _), members in groups.items():
        spellings[key].update(m["name"] for m in members)

    translations = {r["en"]: r for r in read(TRANSLATIONS)}

    rows = []
    missing = set()
    for (key, prep), members in groups.items():
        name = spellings[key].most_common(1)[0][0]
        translation = translations.get(name)
        if not translation:
            missing.add(name)
        category = statistics.mode(m["category"] for m in members)
        row = {
            "name_en": name,
            "name_sk": translation["sk"] if translation else "",
            "name_cs": translation["cs"] if translation else "",
            "preparation": prep,
            "category": category,
            "food_group": food_group(name, category),
        }
        for col, ids in NUTRIENTS:
            values = [next(m["nutrients"][i] for i in ids if i in m["nutrients"])
                      for m in members if any(i in m["nutrients"] for i in ids)]
            row[col] = round(statistics.median(values), 2) if values else ""
        # Search columns: the user's language plus English, without diacritics
        row["search_en"] = fold(name)
        row["search_sk"] = fold(f"{row['name_sk']} {name}")
        row["search_cs"] = fold(f"{row['name_cs']} {name}")
        rows.append(row)
    rows.sort(key=lambda r: (r["name_en"].lower(), r["preparation"]))
    for i, row in enumerate(rows, start=1):
        row["id"] = i

    out_path = Path(out_path)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w", newline="", encoding="utf-8") as f:
        columns = (["id", "name_en", "name_sk", "name_cs", "preparation", "category", "food_group"]
                   + [c for c, _ in NUTRIENTS] + ["search_en", "search_sk", "search_cs"])
        writer = csv.DictWriter(f, fieldnames=columns)
        writer.writeheader()
        writer.writerows(rows)

    print(f"Wrote {len(rows)} foods (from {len(foods)} USDA entries) to {out_path}")
    if missing:
        print(f"Missing translations in {TRANSLATIONS.name}: {', '.join(sorted(missing))}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
