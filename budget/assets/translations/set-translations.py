#!/usr/bin/env python3
# Cashew Desktop: add or update translation keys.
#
# Usage:
#   python3 set-translations.py changes.json
#
# changes.json maps a key to its texts, by language code (columns of
# translations.csv). Languages left out keep their current text; new keys
# without a text fall back to English in the app.
#
#   {
#     "add-attachment": {"en": "Add Attachment", "pt": "Adicionar anexo"}
#   }
#
# Updates translations.csv and generated/<lang>.json for every language given.
# Safe to run more than once.
import csv
import io
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(__doc__ or "usage: set-translations.py changes.json")
    with open(sys.argv[1], encoding="utf-8") as f:
        changes = json.load(f)

    csv_path = os.path.join(HERE, "translations.csv")
    with open(csv_path, encoding="utf-8", newline="") as f:
        original = f.read()
    rows = list(csv.reader(io.StringIO(original)))
    header = rows[0]
    index = {row[0]: i for i, row in enumerate(rows) if row}

    added = 0
    languages = set()
    for key, texts in changes.items():
        if key not in index:
            rows.append([key] + [""] * (len(header) - 1))
            index[key] = len(rows) - 1
            added += 1
        for lang, text in texts.items():
            if lang not in header:
                sys.exit(f"unknown language column: {lang}")
            rows[index[key]][header.index(lang)] = text
            languages.add(lang)

    out = io.StringIO()
    csv.writer(out, quoting=csv.QUOTE_ALL, lineterminator="\n").writerows(rows)
    # The file has no trailing newline; keep it that way.
    with open(csv_path, "w", encoding="utf-8", newline="") as f:
        f.write(out.getvalue().rstrip("\n"))

    for lang in sorted(languages):
        path = os.path.join(HERE, "generated", lang + ".json")
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        for key, texts in changes.items():
            if lang in texts:
                data[key] = texts[lang]
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)

    print(f"{len(changes)} keys ({added} new), languages: {', '.join(sorted(languages))}")


if __name__ == "__main__":
    main()
