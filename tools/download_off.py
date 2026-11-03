"""Download Slovak and Czech products from Open Food Facts (ODbL) into one JSON file.

Usage: python tools/download_off.py <output_json>

Uses the Open Food Facts search service (search.openfoodfacts.org). It returns
at most 10 000 hits per query, so each country is split by the last digit of
the barcode. Only the fields needed for the food catalog are kept.
"""
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://search.openfoodfacts.org/search"
HEADERS = {"User-Agent": "foodapp-dataprep/0.1 (food diary app; data import)"}
COUNTRIES = ["en:slovakia", "en:czech-republic"]
FIELDS = ("code,product_name,product_name_sk,product_name_cs,product_name_en,"
          "generic_name,brands,categories_tags,nutriments")
NUTRIENTS = ["energy-kcal_100g", "energy_100g", "proteins_100g", "fat_100g",
             "saturated-fat_100g", "carbohydrates_100g", "sugars_100g", "fiber_100g",
             "salt_100g", "sodium_100g", "cholesterol_100g", "potassium_100g",
             "calcium_100g", "iron_100g", "vitamin-c_100g"]
PAGE_SIZE = 100


def fetch(params):
    url = f"{API}?{urllib.parse.urlencode(params)}"
    for attempt in range(5):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=HEADERS), timeout=120) as r:
                return json.loads(r.read())
        except (urllib.error.URLError, TimeoutError) as e:
            wait = 10 * (attempt + 1)
            print(f"  {e}; retrying in {wait}s", flush=True)
            time.sleep(wait)
    raise RuntimeError(f"giving up on {url}")


def main(out_path):
    products = {}
    for country in COUNTRIES:
        for digit in range(10):
            query = f'countries_tags:"{country}" AND code:*{digit}'
            page = 1
            while True:
                data = fetch({"q": query, "fields": FIELDS, "page_size": PAGE_SIZE, "page": page})
                for p in data.get("hits", []):
                    n = p.get("nutriments") or {}
                    p["nutriments"] = {k: n[k] for k in NUTRIENTS if k in n}
                    if isinstance(p.get("brands"), list):
                        p["brands"] = ", ".join(p["brands"])
                    products[p.get("code")] = p
                if page >= data.get("page_count", 0):
                    break
                page += 1
                time.sleep(0.3)
            print(f"{country} *{digit}: total {len(products)}", flush=True)

    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(list(products.values()), f, ensure_ascii=False)
    print(f"Saved {len(products)} products to {out_path}")


if __name__ == "__main__":
    main(sys.argv[1])
