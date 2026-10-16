"""Comprueba Data/<Prof>.lua (trainers) contra las guías de Mobalytics."""
import re, sys
from pathlib import Path
sys.stdout.reconfigure(encoding="utf-8")
exec(open(Path(__file__).with_name("verify_trainers.py"), encoding="utf-8").read().split("PREFIX = ")[0])  # GUIDE y questie
A = Path(r"C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\CraftersJournal\Data")
PROF = {"Tailor": "Tailoring", "Alchemist": "Alchemy", "Engineer": "Engineering"}
BIT = {75: 1, 150: 2, 225: 4, 300: 8}
names = {}
for key in questie.store:
    m = re.match(r"X-Npc-(\d+)-S$", key)
    if m:
        nid = int(m.group(1))
        names.setdefault(questie.field("Npc", nid, 1, questie.row("Npc", nid)), []).append(nid)
ok = bad = 0
for noun, ranks in GUIDE.items():
    text = (A / f"{PROF[noun]}.lua").read_text(encoding="utf-8")
    masks = {int(a): int(b) for a, b in re.findall(r"\{ (\d+), (\d+) \}", re.search(r"trainers = \{(.*)\},", text).group(1))}
    for cap, lst in ranks.items():
        for n in lst:
            if any(masks.get(i, 0) & BIT[cap] for i in names.get(n, [])):
                ok += 1
            else:
                bad += 1
                print(f"  falta {PROF[noun]} {cap}: {n} {[(i, masks.get(i)) for i in names.get(n, [])]}")
    # Instructores que el addon usaría para un rango y la guía no lista
    for cap in (75, 150, 225, 300):
        listed = {i for n in ranks[cap] for i in names.get(n, [])}
        extra = [i for i, m in masks.items() if m & BIT[cap] and i not in listed]
        if extra:
            print(f"  {PROF[noun]} {cap}: en datos pero no en la guía: {extra}")
print(f"OK {ok} · fallan {bad}")
