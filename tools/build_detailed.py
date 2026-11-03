"""Build the detailed food catalog (cheeses, hams, cereals, eggs...) with two-level categories.

Usage: python tools/build_detailed.py <off_json> <usda_csv_dir>

Inputs:
  off_json      Slovak/Czech products from Open Food Facts (tools/download_off.py), ODbL
  usda_csv_dir  USDA FoodData Central CSV exports (same as tools/build_foods.py)

Outputs (in data/):
  foods_detailed.csv   new rows to merge into foods.csv
  categories.csv       category / sub_category keys with sk, cs, en labels
  foods_categories.csv category / sub_category for the existing rows of foods.csv

Generic foods ("Eidam 30%", "Šunka dusená") get the median nutrients of all
matching Open Food Facts products, without brands. Cereals, sweets and soft
drinks are kept as branded products.
"""
import csv
import json
import re
import statistics
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_foods import fold  # noqa: E402  same folding as the search columns

DATA = Path(__file__).resolve().parent.parent / "data"
FIRST_ID = 100001  # new rows get ids far from foods.csv

# ---------------------------------------------------------------------------
# Categories: key -> (sk, cs, en). Sub-categories: (category, key) -> (sk, cs, en)
# ---------------------------------------------------------------------------
CATEGORIES = {
    "meat": ("Mäso", "Maso", "Meat"),
    "meat_products": ("Mäsové výrobky", "Masné výrobky", "Meat products"),
    "fish": ("Ryby a morské plody", "Ryby a mořské plody", "Fish and seafood"),
    "eggs": ("Vajcia", "Vejce", "Eggs"),
    "cheese": ("Syry", "Sýry", "Cheese"),
    "dairy": ("Mliečne výrobky", "Mléčné výrobky", "Dairy"),
    "cereals": ("Cereálie", "Cereálie", "Cereals"),
    "bakery": ("Pečivo", "Pečivo", "Bakery"),
    "grains": ("Obilniny, ryža a cestoviny", "Obiloviny, rýže a těstoviny", "Grains, rice and pasta"),
    "sides": ("Prílohy", "Přílohy", "Side dishes"),
    "vegetables": ("Zelenina", "Zelenina", "Vegetables"),
    "fruit": ("Ovocie", "Ovoce", "Fruit"),
    "legumes": ("Strukoviny", "Luštěniny", "Legumes"),
    "nuts": ("Orechy a semená", "Ořechy a semena", "Nuts and seeds"),
    "fats": ("Tuky a oleje", "Tuky a oleje", "Fats and oils"),
    "sweets": ("Sladkosti", "Sladkosti", "Sweets"),
    "drinks": ("Nápoje", "Nápoje", "Drinks"),
    "spices": ("Koreniny a dochucovadlá", "Koření a dochucovadla", "Spices and condiments"),
}
SUB_CATEGORIES = {
    ("meat", "chicken"): ("Kuracie", "Kuřecí", "Chicken"),
    ("meat", "turkey"): ("Morčacie", "Krůtí", "Turkey"),
    ("meat", "pork"): ("Bravčové", "Vepřové", "Pork"),
    ("meat", "beef"): ("Hovädzie", "Hovězí", "Beef"),
    ("meat", "veal"): ("Teľacie", "Telecí", "Veal"),
    ("meat", "lamb"): ("Jahňacie", "Jehněčí", "Lamb"),
    ("meat", "duck"): ("Kačacie", "Kachní", "Duck"),
    ("meat", "goose"): ("Husacie", "Husí", "Goose"),
    ("meat", "game"): ("Divina", "Zvěřina", "Game"),
    ("meat", "other"): ("Iné mäso", "Jiné maso", "Other meat"),
    ("meat_products", "ham"): ("Šunky", "Šunky", "Ham"),
    ("meat_products", "salami"): ("Salámy", "Salámy", "Salami"),
    ("meat_products", "sausages"): ("Párky a klobásy", "Párky a klobásy", "Sausages"),
    ("meat_products", "bacon"): ("Slanina", "Slanina", "Bacon"),
    ("meat_products", "pate"): ("Paštéty", "Paštiky", "Pâté"),
    ("meat_products", "traditional"): ("Tlačenka a zabíjačkové", "Tlačenka a zabijačkové", "Brawn and blood sausages"),
    ("fish", "fish"): ("Ryby", "Ryby", "Fish"),
    ("fish", "seafood"): ("Morské plody", "Mořské plody", "Seafood"),
    ("eggs", "chicken_eggs"): ("Slepačie vajcia", "Slepičí vejce", "Chicken eggs"),
    ("eggs", "other_eggs"): ("Iné vajcia", "Jiná vejce", "Other eggs"),
    ("cheese", "hard"): ("Tvrdé a polotvrdé", "Tvrdé a polotvrdé", "Hard and semi-hard"),
    ("cheese", "soft_ripened"): ("Plesňové a zrejúce", "Plísňové a zrající", "Mould and soft-ripened"),
    ("cheese", "fresh"): ("Čerstvé", "Čerstvé", "Fresh"),
    ("cheese", "processed"): ("Tavené", "Tavené", "Processed"),
    ("cheese", "traditional"): ("Ovčie a tradičné", "Ovčí a tradiční", "Sheep and traditional"),
    ("dairy", "milk"): ("Mlieko", "Mléko", "Milk"),
    ("dairy", "yogurt"): ("Jogurty", "Jogurty", "Yogurt"),
    ("dairy", "fermented"): ("Kefíry a acidofilné", "Kefíry a zakysané", "Kefir and fermented milk"),
    ("dairy", "quark"): ("Tvaroh", "Tvaroh", "Quark"),
    ("dairy", "cream"): ("Smotana", "Smetana", "Cream"),
    ("dairy", "butter"): ("Maslo", "Máslo", "Butter"),
    ("dairy", "plant_milk"): ("Rastlinné nápoje", "Rostlinné nápoje", "Plant-based drinks"),
    ("cereals", "breakfast"): ("Raňajkové cereálie", "Snídaňové cereálie", "Breakfast cereals"),
    ("cereals", "muesli"): ("Müsli a granola", "Müsli a granola", "Muesli and granola"),
    ("cereals", "flakes"): ("Vločky", "Vločky", "Flakes"),
    ("cereals", "porridge"): ("Kaše", "Kaše", "Porridge"),
    ("cereals", "bars"): ("Cereálne tyčinky", "Cereální tyčinky", "Cereal bars"),
    ("bakery", "bread"): ("Chlieb", "Chléb", "Bread"),
    ("bakery", "rolls"): ("Rožky a žemle", "Rohlíky a housky", "Rolls"),
    ("bakery", "other"): ("Iné pečivo", "Jiné pečivo", "Other bakery"),
    ("grains", "rice"): ("Ryža", "Rýže", "Rice"),
    ("grains", "pasta"): ("Cestoviny", "Těstoviny", "Pasta"),
    ("grains", "flour"): ("Múka", "Mouka", "Flour"),
    ("grains", "grains"): ("Obilniny a zrná", "Obiloviny a zrna", "Grains"),
    ("sides", "dumplings"): ("Knedle", "Knedlíky", "Dumplings"),
    ("sides", "potato"): ("Zemiakové prílohy", "Bramborové přílohy", "Potato sides"),
    ("vegetables", "mushrooms"): ("Huby", "Houby", "Mushrooms"),
    ("vegetables", "vegetables"): ("Zelenina", "Zelenina", "Vegetables"),
    ("sweets", "chocolate"): ("Čokolády", "Čokolády", "Chocolate"),
    ("sweets", "biscuits"): ("Sušienky a oblátky", "Sušenky a oplatky", "Biscuits and wafers"),
    ("sweets", "candies"): ("Cukríky", "Bonbony", "Candies"),
    ("sweets", "sugar"): ("Cukor, med a sirupy", "Cukr, med a sirupy", "Sugar, honey and syrups"),
    ("drinks", "soft_drinks"): ("Limonády", "Limonády", "Soft drinks"),
    ("drinks", "juices"): ("Džúsy", "Džusy", "Juices"),
    ("drinks", "alcohol"): ("Alkohol", "Alkohol", "Alcohol"),
    ("drinks", "hot"): ("Káva a čaj", "Káva a čaj", "Coffee and tea"),
    ("drinks", "water"): ("Voda", "Voda", "Water"),
}

FOOD_GROUP = {  # category -> FoodGroup.name in the app
    "meat": "meat", "meat_products": "meat", "fish": "fish", "eggs": "eggs", "cheese": "cheese",
    "dairy": "dairy", "cereals": "grains", "bakery": "grains", "grains": "grains", "sides": "grains",
    "vegetables": "vegetables", "fruit": "fruit", "legumes": "legumes", "nuts": "nuts",
    "fats": "fats", "sweets": "sweets", "drinks": "drinks", "spices": "other",
}

# ---------------------------------------------------------------------------
# Generic foods: median of matching Open Food Facts products.
# (en, sk, cs, category, sub, preparation, regex on the folded product name, options)
# Options: "not" = regex that rules a product out, nutrient ranges like fat=(a, b).
# Order matters: a product counts only for the first food it matches.
# ---------------------------------------------------------------------------
FLAVOURED = (r"jahod|malin|cokol|kakao|vanil|ovocn|broskyn|meruň|merun|cucoried|boruvk|"
             r"visn|tresn|banan|kokos|karamel|med\b|lieskov|liskov|oriesk|orisk|citron|"
             r"slan[ay] karamel|stracciatel|puding|dezert|smoothie|drink|napoj")
G = [
    # --- cheese / hard ---
    ("Edam 30%", "Eidam 30 %", "Eidam 30 %", "cheese", "hard", "", r"\beida[mn]\w*\b.*\b30\b|\b30\b.*\beida[mn]", {}),
    ("Edam 45%", "Eidam 45 %", "Eidam 45 %", "cheese", "hard", "", r"\beida[mn]\w*\b.*\b4[05]\b|\b4[05]\b.*\beida[mn]", {}),
    ("Gouda cheese", "Gouda", "Gouda", "cheese", "hard", "", r"\bgouda\b", {"not": r"taven"}),
    ("Cheddar cheese", "Cheddar", "Čedar", "cheese", "hard", "", r"cheddar|cedar\b", {"not": r"taven|omack|chips|cips|kraker|cracker"}),
    ("Parmesan cheese", "Parmezán", "Parmazán", "cheese", "hard", "", r"parmez|parmaz|parmigiano|parmesan", {"not": r"omack|pesto|kraker"}),
    ("Moravian loaf cheese", "Moravský bochník", "Moravský bochník", "cheese", "hard", "", r"moravsk\w* bochn", {}),
    ("Maasdam cheese", "Maasdam", "Maasdam", "cheese", "hard", "", r"maasdam", {}),
    ("Tilsit cheese", "Tilsit (tylžský syr)", "Tylžský sýr", "cheese", "hard", "", r"tylz|tilsit", {}),
    ("Grana Padano", "Grana Padano", "Grana Padano", "cheese", "hard", "", r"grana padano|gran moravia", {}),
    ("Pecorino", "Pecorino", "Pecorino", "cheese", "hard", "", r"pecorino", {}),
    ("Emmental cheese", "Ementál", "Ementál", "cheese", "hard", "", r"emental|emmental", {}),
    # --- cheese / soft-ripened ---
    ("Niva", "Niva", "Niva", "cheese", "soft_ripened", "", r"\bniva\b|\bnivy\b", {}),
    ("Hermelin", "Hermelín", "Hermelín", "cheese", "soft_ripened", "", r"hermelin", {"not": r"smazen|vypraz|obal"}),
    ("Gorgonzola", "Gorgonzola", "Gorgonzola", "cheese", "soft_ripened", "", r"gorgonzol", {}),
    ("Brie", "Brie", "Brie", "cheese", "soft_ripened", "", r"\bbrie\b", {}),
    ("Camembert", "Camembert", "Camembert", "cheese", "soft_ripened", "", r"camembert", {"not": r"smazen|vypraz|obal"}),
    ("Encian", "Encián", "Encián", "cheese", "soft_ripened", "", r"encian", {}),
    ("Olomouc quargel", "Olomoucké tvarôžky", "Olomoucké tvarůžky", "cheese", "soft_ripened", "", r"tvaruz|olomouck", {}),
    # --- cheese / fresh ---
    ("Mascarpone", "Mascarpone", "Mascarpone", "cheese", "fresh", "", r"mascarpone", {}),
    ("Halloumi", "Halloumi", "Halloumi", "cheese", "fresh", "", r"halloumi|haloumi", {"not": r"smazen|vypraz"}),
    ("Cottage cheese light", "Cottage syr light", "Cottage sýr light", "cheese", "fresh", "", r"cottage", {"fat": (0, 3)}),
    ("Cheese spread (cream cheese)", "Čerstvý krémový syr (lučina)", "Čerstvý krémový sýr (lučina)", "cheese", "fresh", "", r"lucin|zerve|ziervo|cerstv\w* (syr|sy) \w*krem", {"not": FLAVOURED}),
    ("Mozzarella light", "Mozzarella light", "Mozzarella light", "cheese", "fresh", "", r"mozzarel", {"fat": (0, 12)}),
    ("Mozzarella", "Mozzarella", "Mozzarella", "cheese", "fresh", "", r"mozzarel", {"not": r"pizza|smazen|tycink"}),
    ("Cottage cheese", "Cottage syr", "Cottage sýr", "cheese", "fresh", "", r"cottage", {"not": FLAVOURED}),
    ("Ricotta", "Ricotta", "Ricotta", "cheese", "fresh", "", r"ricott", {}),
    ("Feta", "Feta", "Feta", "cheese", "fresh", "", r"\bfeta\b", {"not": r"salat|omack"}),
    ("Balkan cheese (white brined)", "Balkánsky syr", "Balkánský sýr", "cheese", "fresh", "", r"balkan|\bsalatov\w* (syr|sy)\b|syr\w* v slanom|nalev", {}),
    # --- cheese / processed ---
    ("Processed cheese", "Tavený syr", "Tavený sýr", "cheese", "processed", "", r"\btaven\w*\b", {"not": FLAVOURED, "fat": (8, 40)}),
    ("Processed cheese light", "Tavený syr light", "Tavený sýr light", "cheese", "processed", "", r"\btaven\w*\b", {"not": FLAVOURED, "fat": (0, 8)}),
    # --- cheese / traditional ---
    ("Bryndza", "Bryndza", "Brynza", "cheese", "traditional", "", r"bryndz|brynz", {}),
    ("Oscypek (smoked sheep cheese)", "Oštiepok", "Oštěpek", "cheese", "traditional", "", r"ostiep|ostep", {}),
    ("Parenica", "Parenica", "Pařenica", "cheese", "traditional", "", r"parenic", {}),
    ("Korbacik (string cheese)", "Korbáčiky", "Korbáčiky", "cheese", "traditional", "", r"korbac", {}),
    ("Sheep cheese", "Ovčí syr hrudkový", "Ovčí sýr", "cheese", "traditional", "", r"ovc\w* (hrudk|syr|sy)\b|hrudkov", {"not": r"bryndz|brynz|ostiep|parenic", "fat": (10, 35)}),
    # --- cheese fried (preparation of cheese) ---
    ("Hermelin", "Hermelín", "Hermelín", "cheese", "soft_ripened", "fried", r"(smazen|vypraz|obalen)\w* hermelin|hermelin\w* (smazen|vypraz|obal)", {}),
    ("Edam 45%", "Eidam 45 %", "Eidam 45 %", "cheese", "hard", "fried", r"(smazen|vypraz|obalen)\w* (syr|sy)\b|\b(syr|sy) (smazen|vypraz|obalen)", {"not": r"hermelin|halloumi"}),
    # --- meat products / ham (specific kinds first) ---
    ("Turkey ham", "Morčacia šunka", "Krůtí šunka", "meat_products", "ham", "", r"(morcac|krut)\w* sunk|sunk\w* (z )?(morcac|krut)", {}),
    ("Chicken ham", "Kuracia šunka", "Kuřecí šunka", "meat_products", "ham", "", r"(kurac|kurec)\w* sunk|sunk\w* (z )?(kurac|kurec)", {}),
    ("Prague ham", "Pražská šunka", "Pražská šunka", "meat_products", "ham", "", r"prazsk\w* sunk", {}),
    ("Cured ham (prosciutto)", "Sušená šunka (prosciutto)", "Sušená šunka (prosciutto)", "meat_products", "ham", "", r"prosciutto|serrano|\bparma\b|susen\w* sunk|sunk\w* susen|prsut|jamon", {}),
    ("Smoked ham", "Údená šunka", "Uzená šunka", "meat_products", "ham", "", r"(uden|uzen)\w* sunk|sunk\w* (uden|uzen)|od kosti", {}),
    ("Premium ham", "Šunka výberová", "Šunka nejvyšší jakosti", "meat_products", "ham", "", r"sunk.*(vyberov|nejvyssi|najvyssi|extra|premium)", {}),
    ("Cooked ham", "Šunka dusená", "Šunka dušená", "meat_products", "ham", "", r"\bsunk(a|y|ova|ou)?\b", {"not": r"salam|park|klobas|pizza|bageta|sendvic|toast|chleb|chlieb|rohlik|syr\b"}),
    # --- meat products / salami ---
    ("Hunter's salami", "Lovecká saláma", "Lovecký salám", "meat_products", "salami", "", r"lovec", {}),
    ("Polican salami", "Poličan", "Poličan", "meat_products", "salami", "", r"polican", {}),
    ("Herkules salami", "Herkules", "Herkules", "meat_products", "salami", "", r"herkules", {}),
    ("Hungarian salami", "Uhorská saláma", "Uherský salám", "meat_products", "salami", "", r"uhersk\w* sala|uhorsk\w* sala", {}),
    ("Milan salami", "Milánska saláma", "Milánský salám", "meat_products", "salami", "", r"milan", {}),
    ("Chorizo", "Chorizo", "Chorizo", "meat_products", "salami", "", r"chorizo", {}),
    ("Pepperoni", "Pepperoni (feferónková saláma)", "Pepperoni (feferonkový salám)", "meat_products", "salami", "", r"pepperoni|feferonk", {"not": r"pizza"}),
    ("Mortadella", "Mortadela", "Mortadela", "meat_products", "salami", "", r"mortadel", {}),
    ("Gothaer sausage", "Gothajská saláma", "Gothajský salám", "meat_products", "salami", "", r"gothaj|gothajsk", {}),
    ("Ham sausage", "Šunková saláma", "Šunkový salám", "meat_products", "salami", "", r"sunkov\w* (salam|sal)", {}),
    ("Vysocina salami", "Vysočina", "Vysočina", "meat_products", "salami", "", r"vysocin", {}),
    ("Spicy salami", "Pikantná saláma", "Pikantní salám", "meat_products", "salami", "", r"pikant\w* salam|salam\w* pikant", {}),
    ("Salami", "Saláma", "Salám", "meat_products", "salami", "", r"\bsalam\w*", {"not": r"pizza|bageta|sendvic"}),
    # --- meat products / sausages ---
    ("Frankfurters", "Párky", "Párky", "meat_products", "sausages", "", r"\bpar(ky|ek|ok|kov)\w*\b", {"not": r"rohlik|rozok|testo|cesto|pizza"}),
    ("Spekacky sausage", "Špekáčky", "Špekáčky", "meat_products", "sausages", "", r"spekac", {}),
    ("Sausage (klobasa)", "Klobása", "Klobása", "meat_products", "sausages", "", r"klobas|klobasa|kabanos", {}),
    # --- meat products / bacon ---
    ("Bacon (streaky)", "Anglická slanina", "Anglická slanina", "meat_products", "bacon", "", r"anglick\w* slanin|\bbacon\b", {}),
    ("Smoked bacon", "Údená slanina", "Uzená slanina", "meat_products", "bacon", "", r"slanin", {}),
    # --- meat products / pate ---
    ("Liver pate", "Pečeňová paštéta", "Játrová paštika", "meat_products", "pate", "", r"(pecen|jatr)\w* (pastet|pastik)|(pastet|pastik)\w* (pecen|jatr)", {}),
    ("Pate", "Paštéta", "Paštika", "meat_products", "pate", "", r"pastet|pastik", {}),
    # --- meat products / traditional ---
    ("Brawn (head cheese)", "Tlačenka", "Tlačenka", "meat_products", "traditional", "", r"tlacenk", {}),
    ("Liver sausage (jaternice)", "Jaternica", "Jitrnice", "meat_products", "traditional", "", r"jaternic|jitrnic", {}),
    ("Blood sausage", "Krvavnička", "Jelito", "meat_products", "traditional", "", r"krvavnic|jelit", {}),
    # --- cereals / flakes (no brands) ---
    ("Oat flakes", "Ovsené vločky", "Ovesné vločky", "cereals", "flakes", "", r"ovsen\w* vlock|ovesn\w* vlock|oat flakes|rolled oats", {"not": FLAVOURED}),
    ("Spelt flakes", "Špaldové vločky", "Špaldové vločky", "cereals", "flakes", "", r"spald\w* vlock", {}),
    ("Buckwheat flakes", "Pohánkové vločky", "Pohankové vločky", "cereals", "flakes", "", r"pohank\w* vlock", {}),
    ("Rye flakes", "Ražné vločky", "Žitné vločky", "cereals", "flakes", "", r"(razn|zitn)\w* vlock", {}),
    ("Barley flakes", "Jačmenné vločky", "Ječné vločky", "cereals", "flakes", "", r"(jacmen|jecn)\w* vlock", {}),
    # --- dairy ---
    ("Semi-skimmed milk 1.5%", "Polotučné mlieko 1,5 %", "Polotučné mléko 1,5 %", "dairy", "milk", "", r"\b(mliek|mlek)o\b", {"not": FLAVOURED + r"|kondenz|zahust|kozie|kozi|sus|prasok|instan", "fat": (1.2, 2.0)}),
    ("Whole milk 3.5%", "Plnotučné mlieko 3,5 %", "Plnotučné mléko 3,5 %", "dairy", "milk", "", r"\b(mliek|mlek)o\b", {"not": FLAVOURED + r"|kondenz|zahust|kozie|kozi|sus|prasok|instan", "fat": (3.0, 4.2)}),
    ("Plain yogurt", "Biely jogurt", "Bílý jogurt", "dairy", "yogurt", "", r"jogurt", {"not": FLAVOURED + r"|reck|greek|skyr|napoj|tycink|kefir", "sugars": (0, 6), "fat": (2, 5)}),
    ("Low-fat plain yogurt", "Biely jogurt nízkotučný", "Bílý jogurt nízkotučný", "dairy", "yogurt", "", r"jogurt", {"not": FLAVOURED + r"|reck|greek|skyr|napoj|tycink|kefir", "sugars": (0, 6), "fat": (0, 2)}),
    ("Greek yogurt 0%", "Grécky jogurt 0 %", "Řecký jogurt 0 %", "dairy", "yogurt", "", r"(reck|greek)\w* (typ )?jogurt|jogurt\w* (reck|greek)", {"not": FLAVOURED, "sugars": (0, 6), "fat": (0, 2)}),
    ("Greek yogurt 10%", "Grécky jogurt 10 %", "Řecký jogurt 10 %", "dairy", "yogurt", "", r"(reck|greek)\w* (typ )?jogurt|jogurt\w* (reck|greek)", {"not": FLAVOURED, "sugars": (0, 6), "fat": (6, 12)}),
    ("Fruit yogurt", "Ovocný jogurt", "Ovocný jogurt", "dairy", "yogurt", "", r"jogurt", {"not": r"napoj|tycink|cereal|musli|cokolad|polev|reck|greek", "sugars": (8, 20)}),
    ("Skyr", "Skyr", "Skyr", "dairy", "yogurt", "", r"\bskyr\b", {"sugars": (0, 6)}),
    ("Kefir", "Kefír", "Kefír", "dairy", "fermented", "", r"kefir", {"not": FLAVOURED, "sugars": (0, 6)}),
    ("Acidophilus milk", "Acidofilné mlieko (acidko)", "Acidofilní mléko", "dairy", "fermented", "", r"acidof|acidk|zakysank", {"not": FLAVOURED}),
    ("Buttermilk", "Cmar", "Podmáslí", "dairy", "fermented", "", r"\bcmar|podmasl", {"not": FLAVOURED}),
    ("Low-fat quark", "Tvaroh nízkotučný", "Tvaroh nízkotučný", "dairy", "quark", "", r"tvaroh", {"not": FLAVOURED + r"|dezert|tycink|kolac|buchta|knedl", "fat": (0, 1.5)}),
    ("Semi-fat quark", "Tvaroh polotučný", "Tvaroh polotučný", "dairy", "quark", "", r"tvaroh", {"not": FLAVOURED + r"|dezert|tycink|kolac|buchta|knedl", "fat": (1.5, 7)}),
    ("Full-fat quark", "Tvaroh tučný", "Tvaroh tučný", "dairy", "quark", "", r"tvaroh", {"not": FLAVOURED + r"|dezert|tycink|kolac|buchta|knedl", "fat": (7, 20)}),
    ("Sour cream", "Kyslá smotana", "Zakysaná smetana", "dairy", "cream", "", r"kysl\w* smotan|zakysan\w* smetan", {"not": FLAVOURED}),
    ("Cooking cream 12%", "Smotana na varenie 12 %", "Smetana na vaření 12 %", "dairy", "cream", "", r"smotan|smetan", {"not": FLAVOURED + r"|kysl|zakysan|sprej|rostlin|rastlin", "fat": (8, 22)}),
    ("Whipping cream 33%", "Smotana na šľahanie 33 %", "Smetana ke šlehání 33 %", "dairy", "cream", "", r"smotan|smetan", {"not": FLAVOURED + r"|kysl|zakysan|sprej|rostlin|rastlin", "fat": (28, 40)}),
    ("Oat drink", "Ovsený nápoj", "Ovesný nápoj", "dairy", "plant_milk", "", r"\b(ovsen|oves|oat)\w*\b.*\b(napoj|drink|mlieko|mleko)\b", {"not": FLAVOURED.replace("|drink|napoj", "")}),
    ("Almond drink", "Mandľový nápoj", "Mandlový nápoj", "dairy", "plant_milk", "", r"\b(mandl|almond)\w*\b.*\b(napoj|drink|mlieko|mleko)\b", {"not": FLAVOURED.replace("|drink|napoj", "")}),
    # --- bakery ---
    ("Whole-grain roll", "Celozrnný rožok", "Celozrnný rohlík", "bakery", "rolls", "", r"celozrn\w* (rozok|rohlik|rozky|rohliky)", {}),
    ("Graham roll", "Grahamový rožok", "Grahamový rohlík", "bakery", "rolls", "", r"graham\w* (rozok|rohlik|rozky|rohliky|pecivo)", {}),
    ("White roll (rohlik)", "Rožok", "Rohlík", "bakery", "rolls", "", r"\b(rozok|rozky|rohlik|rohliky)\b", {"not": r"sladk|plnen|maslov|celozrn|graham|sunk|park"}),
    ("Kaiser roll", "Žemľa (kaiserka)", "Houska (kajzerka)", "bakery", "rolls", "", r"kaiserk|kajzerk|\bzeml|housk", {"not": r"knedl|strouhank|struhank"}),
    ("Croissant", "Croissant", "Croissant", "bakery", "other", "", r"croissant|kroasan|kroisan", {"not": r"cokol|naplne|plnen|jahod|vanil|orisk|lieskov"}),
    ("Toast bread", "Toastový chlieb", "Toastový chléb", "bakery", "bread", "", r"toast", {"not": r"celozrn|sunk|syr"}),
    ("Whole-grain toast bread", "Celozrnný toastový chlieb", "Celozrnný toastový chléb", "bakery", "bread", "", r"toast", {"not": r"sunk|syr"}),
    ("Crispbread", "Knäckebrot (chrumkavý chlieb)", "Knäckebrot (křehký chléb)", "bakery", "bread", "", r"knacke|kneck|kreh\w* chleb|chrumkav\w* chlieb", {}),
    ("Tortilla wrap", "Tortilla", "Tortilla", "bakery", "other", "", r"tortil", {"not": r"chips|cips|nachos"}),
    ("Pita bread", "Pita", "Pita", "bakery", "other", "", r"\bpita\b", {}),
    ("Wheat-rye bread", "Chlieb pšenično-ražný", "Chléb pšenično-žitný", "bakery", "bread", "", r"\b(chlieb|chleb)\b", {"not": r"celozrn|toast|knacke|kreh|chrumk|strouhank|struhank|bezlep|sladk"}),
    # --- sides ---
    ("Bread dumplings", "Knedľa parená (žemľová)", "Houskový knedlík", "sides", "dumplings", "", r"(housk|zeml|paren|kysnut)\w* knedl|knedl\w* (housk|zeml|paren)", {}),
    ("Potato dumplings", "Zemiakové knedle", "Bramborové knedlíky", "sides", "dumplings", "", r"(bramb|zemiak)\w* knedl|knedl\w* (bramb|zemiak)", {"not": r"plnen|ovoc|jahod|svestk|slivk|mas[ao]"}),
    ("Gnocchi", "Gnocchi (noky)", "Gnocchi (noky)", "sides", "potato", "", r"gnocchi|\bnoky\b", {"not": r"plnen|syr|omack"}),
    ("French fries", "Hranolky", "Hranolky", "sides", "potato", "frozen", r"hranol", {"not": r"sladk|batat"}),
    ("Potato croquettes", "Krokety", "Krokety", "sides", "potato", "frozen", r"kroket", {}),
]

# ---------------------------------------------------------------------------
# Branded products: Open Food Facts category tags -> our category / sub_category.
# ---------------------------------------------------------------------------
BRANDED = [
    ("cereals", "muesli", {"en:mueslis", "en:granolas", "en:crunchy-cereal-clusters"}),
    ("cereals", "porridge", {"en:porridge", "en:porridges", "en:instant-porridge"}),
    ("cereals", "bars", {"en:cereal-bars", "en:granola-bars", "en:muesli-bars"}),
    ("cereals", "breakfast", {"en:breakfast-cereals"}),
    ("sweets", "chocolate", {"en:chocolates", "en:dark-chocolates", "en:milk-chocolates",
                             "en:white-chocolates", "en:chocolate-bars"}),
    ("sweets", "biscuits", {"en:biscuits", "en:cookies", "en:wafers", "en:biscuits-and-cakes"}),
    ("sweets", "candies", {"en:candies", "en:gummies", "en:confectioneries"}),
    ("drinks", "soft_drinks", {"en:sodas", "en:colas", "en:carbonated-drinks", "en:energy-drinks",
                               "en:iced-teas", "en:soft-drinks"}),
    ("drinks", "juices", {"en:fruit-juices", "en:juices-and-nectars", "en:fruit-nectars"}),
]
# Tags that mean the product is not what the branded category promises
BRANDED_NOT = {"en:dietary-supplements", "en:pet-food", "en:baby-foods", "en:meals"}

# ---------------------------------------------------------------------------
# Egg preparations from USDA SR Legacy (description -> preparation key)
# ---------------------------------------------------------------------------
EGG_PREPS = [
    ("Egg, whole, raw, fresh", "raw"),
    ("Egg, whole, cooked, hard-boiled", "hard_boiled"),
    ("Egg, whole, cooked, hard-boiled", "soft_boiled"),  # same composition, only softer
    ("Egg, whole, cooked, fried", "fried"),
    ("Egg, whole, cooked, scrambled", "scrambled"),
    ("Egg, whole, cooked, poached", "poached"),
    ("Egg, whole, cooked, omelet", "omelette"),
]
USDA_NUTRIENTS = {  # our column -> USDA nutrient ids in order of preference
    "kcal": [1008, 2048, 2047], "protein_g": [1003], "fat_g": [1004], "saturated_fat_g": [1258],
    "carbs_g": [1005], "sugars_g": [2000, 1063], "fiber_g": [1079], "sodium_mg": [1093],
    "cholesterol_mg": [1253], "potassium_mg": [1092], "calcium_mg": [1087], "iron_mg": [1089],
    "vitamin_c_mg": [1162],
}
NUTRIENT_COLUMNS = list(USDA_NUTRIENTS)

# OFF nutriments (grams per 100 g) -> our columns
OFF_NUTRIENTS = {
    "protein_g": ("proteins_100g", 1), "fat_g": ("fat_100g", 1),
    "saturated_fat_g": ("saturated-fat_100g", 1), "carbs_g": ("carbohydrates_100g", 1),
    "sugars_g": ("sugars_100g", 1), "fiber_g": ("fiber_100g", 1),
    "cholesterol_mg": ("cholesterol_100g", 1000), "potassium_mg": ("potassium_100g", 1000),
    "calcium_mg": ("calcium_100g", 1000), "iron_mg": ("iron_100g", 1000),
    "vitamin_c_mg": ("vitamin-c_100g", 1000),
}
# Existing USDA foods (name_en) superseded by the detailed rows even though the names differ
REPLACED_BY_DETAILED = {"Egg", "Edam cheese", "Cream cheese"}

# Plausible ranges (g per 100 g) a matching product must fit, so that e.g. crackers
# named after a cheese do not count as the cheese. Spec options override these.
DEFAULT_RANGES = {
    "cheese": {"protein": (12, 40), "carbs": (0, 6)},
    ("cheese", "fresh"): {"protein": (3, 30), "carbs": (0, 8)},
    ("cheese", "processed"): {"protein": (6, 25), "carbs": (0, 12)},
    "meat_products": {"protein": (8, 40), "carbs": (0, 8)},
    ("meat_products", "pate"): {"protein": (5, 25), "carbs": (0, 12)},
    ("meat_products", "traditional"): {"protein": (5, 25), "carbs": (0, 20)},
    ("bakery", "rolls"): {"carbs": (40, 65), "fat": (0, 10)},
    ("bakery", "bread"): {"carbs": (35, 75), "fat": (0, 12)},
}

# Generic foods with no Open Food Facts match take USDA values (Slovak name -> USDA description)
USDA_FALLBACK = {
    "Brie": "Cheese, brie",
    "Uhorská saláma": "Salami, dry or hard, pork",
    "Ricotta": "Cheese, ricotta, whole milk",
    "Balkánsky syr": "Cheese, feta",
    "Rožok": "Rolls, dinner, plain, commercially prepared (includes brown-and-serve)",
    "Grahamový rožok": "Rolls, dinner, whole-wheat",
    "Parmezán": "Cheese, parmesan, hard",
    "Feta": "Cheese, feta",
    "Tilsit (tylžský syr)": "Cheese, tilsit",
    "Pecorino": "Cheese, romano",
    "Pepperoni (feferónková saláma)": "Pepperoni, beef and pork, sliced",
    "Mortadela": "Mortadella, beef, pork",
    "Pečeňová paštéta": "Pate, liver, not specified, canned",
    "Tlačenka": "Headcheese, pork",
    "Krvavnička": "Blood sausage",
    "Pita": "Bread, pita, white, enriched",
    "Žemľa (kaiserka)": "Rolls, hard (includes kaiser)",
    "Celozrnný rožok": "Rolls, dinner, whole-wheat",
    "Celozrnný toastový chlieb": "Bread, whole-wheat, commercially prepared, toasted",
    "Špaldové vločky": "Spelt, uncooked",
    "Pohánkové vločky": "Buckwheat",
    "Ražné vločky": "Rye grain",
    "Jačmenné vločky": "Barley, pearled, raw",
    "Grécky jogurt 10 %": "Yogurt, Greek, plain, whole milk",
    "Pikantná saláma": "Salami, dry or hard, pork, beef",
    "Tavený syr light": "Cheese, pasteurized process, American, low fat",
    "Špekáčky": "Polish sausage, pork",
}

# Breading for 100 g of cheese: 15 g breadcrumbs, 10 g egg, 5 g flour and 8 g oil
# soaked up while frying; the fried piece weighs about 130 g.
BREADING = {"kcal": 162, "protein_g": 3.8, "fat_g": 9.8, "saturated_fat_g": 1.3, "carbs_g": 14.6,
            "sugars_g": 0.9, "fiber_g": 0.8, "sodium_mg": 124, "cholesterol_mg": 37}
FRIED_WEIGHT = 130


def fried_in_breadcrumbs(cheese):
    """Nutrients of breaded fried cheese per 100 g, estimated from the plain cheese."""
    out = {}
    for col in NUTRIENT_COLUMNS:
        base = cheese.get(col)
        if base == "" or base is None:
            out[col] = ""
            continue
        out[col] = round((float(base) + BREADING.get(col, 0)) * 100 / FRIED_WEIGHT, 2)
    return out


def number(value):
    try:
        v = float(value)
    except (TypeError, ValueError):
        return None
    return v if v >= 0 else None


def off_nutrients(product):
    """Nutrients per 100 g from an OFF product, or None when the basics are missing or inconsistent."""
    n = product.get("nutriments") or {}
    kcal = number(n.get("energy-kcal_100g"))
    if kcal is None and number(n.get("energy_100g")) is not None:
        kcal = number(n.get("energy_100g")) / 4.184
    row = {"kcal": kcal}
    for col, (key, factor) in OFF_NUTRIENTS.items():
        v = number(n.get(key))
        row[col] = None if v is None else v * factor
    sodium = number(n.get("sodium_100g"))
    if sodium is None and number(n.get("salt_100g")) is not None:
        sodium = number(n.get("salt_100g")) / 2.5
    row["sodium_mg"] = None if sodium is None else sodium * 1000

    if any(row[c] is None for c in ("kcal", "protein_g", "fat_g", "carbs_g")):
        return None
    if row["protein_g"] + row["fat_g"] + row["carbs_g"] > 101 or row["kcal"] > 950:
        return None
    # Energy must roughly agree with the macronutrients (catches kJ typed as kcal)
    expected = 4 * row["protein_g"] + 9 * row["fat_g"] + 4 * row["carbs_g"] + 2 * (row["fiber_g"] or 0)
    if expected > 20 and not 0.75 <= row["kcal"] / expected <= 1.3:
        return None
    return row


def product_names(p):
    names = [p.get(k) or "" for k in ("product_name_sk", "product_name_cs", "product_name", "generic_name")]
    return [n.strip() for n in names if n and n.strip()]


def median_row(rows):
    out = {}
    for col in NUTRIENT_COLUMNS:
        values = [r[col] for r in rows if r.get(col) is not None]
        out[col] = round(statistics.median(values), 2) if values else ""
    return out


def clean_brand(brands):
    first = (brands or "").split(",")[0].strip()
    return first[:1].upper() + first[1:] if first else ""


def clean_name(name):
    name = re.sub(r"\s+", " ", name).strip(" ,-")
    if name.isupper():
        name = name.capitalize()
    return name[:1].upper() + name[1:]


# Letters and words that mark a product name in another language than Slovak/Czech
FOREIGN_LETTERS = re.compile(r"[łąęśźżćńăâșțîßüöőű]", re.IGNORECASE)
FOREIGN_WORDS = re.compile(r"\b(mit|und|saft|with|and|juice|cu|z orzech|ze|der|die|das|für|"
                           r"czekolad|ciastk|wafel|sok|biscuit|cookies|chocolate|gums|bar|zitrone|"
                           r"succo|nuss\w*|caramelised|assortment|buns|sour|beans|fine)\b", re.IGNORECASE)


def is_local_name(name):
    """True for Slovak/Czech names and plain brand-style names (e.g. "Toffifee")."""
    return not FOREIGN_LETTERS.search(name) and not FOREIGN_WORDS.search(name)


def read_csv(path):
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


# ---------------------------------------------------------------------------
# Categories for the existing foods.csv rows
# ---------------------------------------------------------------------------
GAME = {"bison", "deer", "elk", "boar", "moose", "antelope", "caribou", "buffalo", "bear",
        "beaver", "muskrat", "opossum", "raccoon", "squirrel", "rabbit", "pheasant", "quail",
        "squab", "dove", "emu", "ostrich", "guinea", "horse", "goat", "canada", "ruffed", "frog", "turtle"}
SEAFOOD = re.compile(r"\b(abalone|clam|conch|crab|crayfish|cuttlefish|jellyfish|lobster|mussel|octopus|"
                     r"oyster|scallop|shrimp|snail|squid|whelk|roe|caviar|spiny)\b", re.IGNORECASE)
CHEESE_SUB = [
    (r"cottage|cream cheese|ricotta|mozzarella|feta|queso fresco|neufchatel|goat|white cheese|mascarpone", "fresh"),
    (r"blue|brie|camembert|roquefort|limburger|gorgonzola", "soft_ripened"),
    (r"american|processed", "processed"),
]


def existing_category(row):
    name = row["name_en"]
    lower = name.lower()
    group = row["food_group"]
    first = re.sub(r"^ground ", "", lower).split()[0]
    if group == "meat":
        if re.search(r"\bham\b|bacon", lower):
            return "meat_products", "ham" if "ham" in lower else "bacon"
        if first in {"chicken", "turkey", "pork", "beef", "veal", "lamb", "duck", "goose"}:
            return "meat", first
        if first in GAME:
            return "meat", "game"
        return "meat", "other"
    if group == "fish":
        return "fish", "seafood" if SEAFOOD.search(lower) else "fish"
    if group == "eggs":
        return "eggs", "chicken_eggs" if re.match(r"egg\b|egg (white|yolk)", lower) else "other_eggs"
    if group == "cheese":
        for pattern, sub in CHEESE_SUB:
            if re.search(pattern, lower):
                return "cheese", sub
        return "cheese", "hard"
    if group == "dairy":
        if "butter" in lower:
            return "dairy", "butter"
        if "yogurt" in lower:
            return "dairy", "yogurt"
        if "cream" in lower:
            return "dairy", "cream"
        if re.search(r"buttermilk|kefir|whey", lower):
            return "dairy", "fermented"
        return "dairy", "milk"
    if group == "grains":
        if re.search(r"bread|roll|baguette", lower):
            return "bakery", "rolls" if "roll" in lower else "bread"
        if "rice" in lower and "flour" not in lower and "bran" not in lower:
            return "grains", "rice"
        if re.search(r"pasta|noodle|spaghetti|macaroni|vermicelli|couscous", lower):
            return "grains", "pasta"
        if re.search(r"flour|cornstarch|semolina|starch", lower):
            return "grains", "flour"
        if re.search(r"\boats\b|flakes", lower):
            return "cereals", "flakes"
        return "grains", "grains"
    if group == "vegetables":
        return "vegetables", "mushrooms" if re.search(r"mushroom|fungi|jew's ear|pepeao", lower) else "vegetables"
    if group == "drinks":
        if re.search(r"\bmilk\b|^rice$", lower):
            return "dairy", "plant_milk"
        if re.search(r"beer|wine|spirits", lower):
            return "drinks", "alcohol"
        if re.search(r"coffee|tea", lower):
            return "drinks", "hot"
        return "drinks", "water"
    if group == "sweets":
        return "sweets", "sugar"
    if group == "other":
        return "spices", ""
    return group if group in CATEGORIES else "spices", ""


def main(off_json, usda_dir):
    usda_dir = Path(usda_dir)
    with open(off_json, encoding="utf-8") as f:
        products = json.load(f)

    candidates = []  # (folded name, product, nutrients)
    for p in products:
        nutrients = off_nutrients(p)
        names = product_names(p)
        if nutrients and names:
            candidates.append((fold(" ".join(names)), p, nutrients))
    print(f"{len(products)} OFF products, {len(candidates)} with usable nutrients")

    rows = []
    report = []

    # --- USDA values (eggs and fallbacks for foods missing in Open Food Facts) ---
    descriptions = {d for d, _ in EGG_PREPS} | set(USDA_FALLBACK.values())
    fdc = {r["fdc_id"]: r["description"] for r in read_csv(usda_dir / "food (3).csv")
           if r["description"] in descriptions}
    usda = {d: {} for d in descriptions}
    with open(usda_dir / "food_nutrient (3).csv", newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            if r["fdc_id"] in fdc and r["amount"]:
                usda[fdc[r["fdc_id"]]][int(r["nutrient_id"])] = float(r["amount"])
    missing = descriptions - {d for d, v in usda.items() if v}
    assert not missing, f"USDA descriptions not found: {missing}"

    def usda_row(description):
        values = usda[description]
        return {col: next((round(values[i], 2) for i in ids if i in values), "")
                for col, ids in USDA_NUTRIENTS.items()}

    # --- generic foods ---
    compiled = [(spec, re.compile(spec[6]), re.compile(spec[7]["not"]) if "not" in spec[7] else None)
                for spec in G]
    matches = {i: [] for i in range(len(G))}
    for text, p, nutrients in candidates:
        for i, (spec, pattern, rule_out) in enumerate(compiled):
            if not pattern.search(text) or (rule_out and rule_out.search(text)):
                continue
            ranges = {**DEFAULT_RANGES.get((spec[3], spec[4]), DEFAULT_RANGES.get(spec[3], {})),
                      **{k: v for k, v in spec[7].items() if k != "not"}}
            if any(nutrients.get(f"{k}_g") is None or not lo <= nutrients[f"{k}_g"] <= hi
                   for k, (lo, hi) in ranges.items()):
                continue
            matches[i].append(nutrients)
            break
    generic = {}  # (name_en, preparation) -> row, for the fried-cheese recipe
    for i, (spec, _, _) in enumerate(compiled):
        en, sk, cs, category, sub, prep, *_ = spec
        found = matches[i]
        if found:
            values, source = median_row(found), f"Open Food Facts ({len(found)} products)"
        elif sk in USDA_FALLBACK:
            values, source = usda_row(USDA_FALLBACK[sk]), f"USDA: {USDA_FALLBACK[sk]}"
        elif prep == "fried" and (en, "") in generic:
            values, source = fried_in_breadcrumbs(generic[(en, "")]), "Recipe estimate (breaded, fried)"
        else:
            report.append(("missing", f"{sk} [{prep or '-'}]"))
            continue
        report.append((source, f"{sk} [{prep or '-'}]"))
        row = {"name_en": en, "name_sk": sk, "name_cs": cs, "brand": "", "preparation": prep,
               "category": category, "sub_category": sub, "source": source, **values}
        generic[(en, prep)] = row
        rows.append(row)

    # --- eggs from USDA ---
    for description, prep in EGG_PREPS:
        rows.append({"name_en": "Egg", "name_sk": "Vajce", "name_cs": "Vejce", "brand": "", "preparation": prep,
                     "category": "eggs", "sub_category": "chicken_eggs", "source": f"USDA: {description}",
                     **usda_row(description)})

    # --- branded products ---
    seen = set()
    branded_counts = {}
    for text, p, nutrients_ in candidates:
        brand = clean_brand(p.get("brands"))
        tags = set(p.get("categories_tags") or [])
        if not brand or tags & BRANDED_NOT:
            continue
        for category, sub, wanted in BRANDED:
            if tags & wanted:
                break
        else:
            continue
        names = {k: (p.get(k) or "").strip() for k in ("product_name_sk", "product_name_cs", "product_name_en", "product_name")}
        main = names["product_name_sk"] or names["product_name_cs"] or names["product_name"]
        if not main or not (names["product_name_sk"] or names["product_name_cs"] or is_local_name(main)):
            continue
        key = (fold(brand), fold(main))
        if key in seen:
            continue
        seen.add(key)
        branded_counts[(category, sub)] = branded_counts.get((category, sub), 0) + 1
        rows.append({
            "name_en": clean_name(names["product_name_en"] or main),
            "name_sk": clean_name(names["product_name_sk"] or main),
            "name_cs": clean_name(names["product_name_cs"] or main),
            "brand": brand, "preparation": "", "category": category, "sub_category": sub,
            "source": f"Open Food Facts {p.get('code', '')}",
            **{c: ("" if nutrients_[c] is None else round(nutrients_[c], 2)) for c in NUTRIENT_COLUMNS},
        })

    # --- write foods_detailed.csv ---
    for i, row in enumerate(rows):
        row["id"] = FIRST_ID + i
        row["food_group"] = FOOD_GROUP[row["category"]]
        brand = f" {row['brand']}" if row["brand"] else ""
        row["search_en"] = fold(f"{row['name_en']}{brand}")
        row["search_sk"] = fold(f"{row['name_sk']} {row['name_en']}{brand}")
        row["search_cs"] = fold(f"{row['name_cs']} {row['name_en']}{brand}")
    columns = (["id", "name_en", "name_sk", "name_cs", "brand", "preparation", "category", "sub_category",
                "food_group"] + NUTRIENT_COLUMNS + ["source", "search_en", "search_sk", "search_cs"])
    with open(DATA / "foods_detailed.csv", "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=columns)
        writer.writeheader()
        writer.writerows(rows)

    # --- write categories.csv ---
    with open(DATA / "categories.csv", "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["category", "sub_category", "sk", "cs", "en"])
        for key, labels in CATEGORIES.items():
            writer.writerow([key, "", *labels])
            for (cat, sub), sub_labels in SUB_CATEGORIES.items():
                if cat == key:
                    writer.writerow([key, sub, *sub_labels])

    # --- write foods_categories.csv for the existing foods ---
    existing = read_csv(DATA / "foods.csv")
    with open(DATA / "foods_categories.csv", "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["id", "name_en", "preparation", "category", "sub_category"])
        for r in existing:
            category, sub = existing_category(r)
            assert category in CATEGORIES, (r["name_en"], category)
            assert not sub or (category, sub) in SUB_CATEGORIES, (r["name_en"], category, sub)
            writer.writerow([r["id"], r["name_en"], r["preparation"], category, sub])

    # --- write foods_full.csv: existing foods + new rows, ready to replace the Supabase table ---
    # A new generic food replaces an existing one with the same name (in any language)
    # and preparation; new egg rows replace the old egg preparations.
    def keys(row):
        # "Syr brie" and "Brie" are the same food: ignore the word cheese itself
        return {(re.sub(r"\b(syr|sy|cheese)\b", "", fold(row[c])).strip(), row["preparation"])
                for c in ("name_en", "name_sk", "name_cs")}

    replaced = set().union(*(keys(r) for r in rows if not r["brand"]))
    full = []
    dropped = []
    for r in existing:
        if r["name_en"] in REPLACED_BY_DETAILED or keys(r) & replaced:
            dropped.append(f"{r['name_sk']} [{r['preparation'] or '-'}]")
            continue
        category, sub = existing_category(r)
        full.append({**r, "brand": "", "category": category, "sub_category": sub,
                     "source": "USDA FoodData Central"})
    full.extend(rows)
    with open(DATA / "foods_full.csv", "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=columns)
        writer.writeheader()
        writer.writerows(full)

    print(f"Wrote {len(rows)} rows to foods_detailed.csv, {len(existing)} rows to foods_categories.csv")
    print(f"Wrote {len(full)} rows to foods_full.csv; replaced existing: {', '.join(dropped)}")
    print("Generic foods (matched OFF products):")
    for source, label in report:
        print(f"  {label:40s} {source}")
    print("Branded products:", {f"{c}/{s}": n for (c, s), n in sorted(branded_counts.items())})


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
