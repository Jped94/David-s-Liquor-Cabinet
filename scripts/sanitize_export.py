#!/usr/bin/env python3
"""Make a CellarTracker export safe to commit as a test fixture.

Blanks out financial and purchase details (prices, values, stores, dates,
barcodes, bins) and renumbers the per-bottle inventory IDs. It keeps
everything the menu needs: names, producers, regions, styles, sizes,
locations, bottle notes and community scores.

The output stays windows-1252 encoded, like the real CellarTracker export,
so the decoder tests run against realistic bytes.

Usage: python3 scripts/sanitize_export.py <export.csv> <output.csv>
"""
import csv
import sys

BLANK = {
    "Value", "Price", "NativePrice", "StoreName", "PurchaseDate",
    "DeliveryDate", "PurchaseNote", "Barcode", "WineBarcode",
    "BarcodePrinted", "Bin",
}


def read_rows(path):
    raw = open(path, "rb").read()
    try:
        text = raw.decode("utf-8-sig")
    except UnicodeDecodeError:
        text = raw.decode("cp1252")
    return list(csv.DictReader(text.splitlines(keepends=True)))


def main(src, dst):
    rows = read_rows(src)
    if not rows:
        sys.exit("no rows found")
    fields = list(rows[0].keys())
    for i, row in enumerate(rows, start=1):
        for col in BLANK & row.keys():
            row[col] = ""
        if "iInventory" in row:
            row["iInventory"] = str(i)
    with open(dst, "w", encoding="cp1252", errors="replace", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields, quoting=csv.QUOTE_ALL, lineterminator="\r\n")
        w.writeheader()
        w.writerows(rows)
    print(f"wrote {len(rows)} sanitized rows to {dst}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
