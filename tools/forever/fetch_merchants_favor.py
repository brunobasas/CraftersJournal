"""Recetas que se compran con Merchant's Favor (campamentos de Durotar Supply and
Logistics / Azeroth Commerce Authority) -> tools/forever/merchants_favor.csv

Fuente: https://www.wow-professions.com/forever/merchants-favor-durotar-supply-azeroth-commerce
(tablas por profesión: receta, coste en Merchant's Favor y reputación que pide).
Uso: python fetch_merchants_favor.py   (vuelve a descargar y reescribe el CSV)
"""
import csv
import datetime
import re
import sys
import urllib.request
from html.parser import HTMLParser
from pathlib import Path

URL = "https://www.wow-professions.com/forever/merchants-favor-durotar-supply-azeroth-commerce"
OUT = Path(__file__).with_name("merchants_favor.csv")
# Prefijo del id de cada tabla -> profesión
PROFS = {"alc": "Alchemy", "bs": "Blacksmithing", "prof-cooking": "Cooking", "enc": "Enchanting",
         "eng": "Engineering", "lw": "Leatherworking", "tl": "Tailoring"}
REPS = {"": 0, "Friendly": 5, "Honored": 6, "Revered": 7, "Exalted": 8}


class Tables(HTMLParser):
    """Filas de las tablas, con el id del elemento más cercano que tenga id."""
    def __init__(self):
        super().__init__()
        self.ids, self.rows, self.row, self.cell = [], [], None, None

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        self.ids.append(a.get("id"))
        if tag == "tr":
            self.row = []
        elif tag == "td" and self.row is not None:
            self.cell = []

    def handle_endtag(self, tag):
        if tag == "td" and self.cell is not None:
            self.row.append(re.sub(r"\s+", " ", "".join(self.cell)).strip())
            self.cell = None
        elif tag == "tr" and self.row:
            section = next((i for i in reversed(self.ids) if i and i.startswith("mf-")), None)
            self.rows.append((section, self.row))
            self.row = None
        if self.ids:
            self.ids.pop()

    def handle_data(self, data):
        if self.cell is not None:
            self.cell.append(data)


def main():
    req = urllib.request.Request(URL, headers={"User-Agent": "Mozilla/5.0"})
    html = urllib.request.urlopen(req, timeout=30).read().decode("utf-8")
    parser = Tables()
    parser.feed(html)
    out = []
    for section, cells in parser.rows:
        if not section or len(cells) < 3:
            continue
        key = section[3:]
        prof = next((p for k, p in PROFS.items() if key.startswith(k)), None)
        if not prof:
            continue
        rep = cells[-1] if cells[-1] in REPS else ""
        cost = cells[-2] if rep or cells[-1] == "" else cells[-1]
        if not cost.replace(",", "").isdigit():
            continue
        out.append({"profession": prof, "recipe": cells[1], "favor": int(cost.replace(",", "")), "rep": REPS[rep]})
    if not out:
        sys.exit("No se encontró ninguna receta: ¿ha cambiado la página?")
    today = datetime.date.today().isoformat()
    with open(OUT, "w", encoding="utf-8", newline="") as f:
        f.write(f"# Fuente: {URL} ({today}). rep: 0 ninguna, 5 amistoso, 6 honorable, 7 venerado, 8 exaltado\n")
        w = csv.DictWriter(f, fieldnames=["profession", "recipe", "favor", "rep"])
        w.writeheader()
        w.writerows(out)
    print(f"{OUT}: {len(out)} recetas")


if __name__ == "__main__":
    main()
