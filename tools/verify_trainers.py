"""Contrasta la regla del subtítulo de QuestieDB con las listas de instructores de Mobalytics."""
import re, sys
sys.stdout.reconfigure(encoding="utf-8")
sys.path.insert(0, r"C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\CraftersJournal\tools")
import questie
questie.load_store()

GUIDE = {  # profesión -> rango -> instructores (Mobalytics, 14/10/2026)
    "Tailor": {
        75: ["Lawrence Schneider", "Uthrar Threx", "Trianna", "Eldrin", "Grondal Moonbreeze", "Taleen Shimmerthread", "Othesia Evengale",
             "Snang", "Victor Ward", "Vhan", "Bowen Brisboise"],
        150: ["Sellandus", "Jormund Stonebrow", "Me'lynn", "Taleen Shimmerthread", "Othesia Evengale", "Magar", "Rhiannon Davis", "Tepa"],
        225: ["Georgio Bolero", "Josef Gregorian"],
        300: ["Timothy Worthington", "Daryl Stack"],
    },
    "Alchemist": {
        75: ["Tel'Athir", "Vosur Brakthel", "Milla Fairancora", "Alchemist Mallory", "Cyndra Kindwhisper", "Ghak Healtouch", "Whuut", "Kray",
             "Doctor Martin Felben", "Miao'zan", "Carolai Anise", "Iaadaria Bitterwind", "Nyassa Swiftdraught", "Valiena Swiftgale"],
        150: ["Lilyssia Nightbreeze", "Tally Berryfizz", "Sylvanna Forestmoon", "Kylanna", "Alchemist Narett", "Yelmak", "Bena Winterhoof",
              "Doctor Marsh", "Serge Hinott", "Jaxin Chong"],
        225: ["Ainethil", "Linzy Blackbolt", "Patricia Egan", "Doctor Herbert Halsey"],
        300: ["Kylanna Windwhisper", "Rogvar", "Master Mycologist Shurome"],
    },
    "Engineer": {
        75: ["Bronk Guzzlegear", "Deek Fizzlebizz", "Jemma Quikswitch", "Jenna Lemkenilli", "Sprite Jumpsprocket", "Tinkerwiz", "Strange Hermit",
             "Graham Van Talen", "Mukdrak", "Thund", "Twizwick Sprocketgrind"],
        150: ["Finbus Geargrind", "Lilliam Sparkspindle", "Trixie Quikswitch", "Franklin Lloyd", "Nogg"],
        225: ["Springspindle Fizzlegear", "Roxxik"],
        300: ["Buzzek Bracketswing", "Kaylaena Springwhisper"],
    },
}
PREFIX = {"Journeyman": 75, "Expert": 150, "Artisan": 225, "Master": 300}

wanted = {n for p in GUIDE.values() for lst in p.values() for n in lst}
subs = {}
for key in questie.store:
    m = re.match(r"X-Npc-(\d+)-S$", key)
    if m:
        nid = int(m.group(1))
        r = questie.row("Npc", nid)
        name = questie.field("Npc", nid, 1, r)
        if name in wanted:
            subs.setdefault(name, []).append((nid, questie.field("Npc", nid, 14, r)))

ok = bad = 0
for noun, ranks in GUIDE.items():
    for cap, names in ranks.items():
        for n in names:
            entries = subs.get(n, [])
            derived = set()
            for nid, s in entries:
                s = s or ""
                m = re.match(r"^(Journeyman|Expert|Artisan|Master) " + noun + "$", s)
                if m:
                    derived.add(PREFIX[m.group(1)])
            if cap in derived:
                ok += 1
            else:
                bad += 1
                print(f"  {noun} {cap}: {n} -> {entries} (regla da {sorted(derived)})")
print(f"coinciden {ok}, no {bad}")
