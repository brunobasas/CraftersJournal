"""Extrae de la base de datos de CMaNGOS (classic-db) lo que enseñan los instructores
de profesiones: precio, nivel de habilidad y de personaje, y los rangos.

Fuente: https://github.com/cmangos/classic-db (Full_DB/ClassicDB_*.sql.gz, GPL-2.0).
Los instructores de Classic enseñan "hechizos de aprender" (efecto 36) que ya no
existen en el cliente de Forever; se traducen a la receta con la tabla
spell_template del propio volcado.

Uso:  python extract_cmangos.py <ClassicDB_*.sql.gz>
Escribe tools/cmangos/trainer_spells.csv:
  npc, spell (receta o rango), cost (cobre), skill (línea), reqskill, reqlevel, rank_step
  (rank_step = 1 aprendiz, 2 oficial, 3 experto, 4 artesano; vacío si es una receta)
"""
import csv
import gzip
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT = HERE / "cmangos" / "trainer_spells.csv"
SKILL_LINES = {165, 333, 197, 164, 171, 202, 185, 129}
LEARN_SPELL, SKILL_STEP, SKILL = 36, 118, 44  # efectos de hechizo


def tuples(values):
    """Valores de un INSERT ... VALUES (...),(...): respeta comillas y escapes."""
    row, field, i, n = [], [], 0, len(values)
    depth, quoted = 0, False
    while i < n:
        c = values[i]
        if quoted:
            if c == "\\":
                field.append(values[i + 1])
                i += 2
                continue
            if c == "'":
                quoted = False
            else:
                field.append(c)
        elif c == "'":
            quoted = True
        elif c == "(" and depth == 0:
            depth, row, field = 1, [], []
        elif c == "," and depth == 1:
            row.append("".join(field))
            field = []
        elif c == ")" and depth == 1:
            row.append("".join(field))
            yield row
            depth = 0
        elif depth == 1:
            field.append(c)
        i += 1


def read_dump(path):
    columns, data = {}, {"spell_template": [], "npc_trainer": [], "npc_trainer_template": [], "creature_template": []}
    current = None
    with gzip.open(path, "rt", encoding="utf-8", errors="replace") as f:
        for line in f:
            m = re.match(r"CREATE TABLE `(\w+)`", line)
            if m:
                current = m.group(1) if m.group(1) in data else None
                if current:
                    columns[current] = []
                continue
            if current and line.startswith("  `"):
                columns[current].append(re.match(r"\s*`(\w+)`", line).group(1))
                continue
            m = re.match(r"INSERT INTO `(\w+)` VALUES ", line)
            if m and m.group(1) in data:
                data[m.group(1)].extend(tuples(line[m.end():]))
    return columns, data


def main():
    columns, data = read_dump(sys.argv[1])

    def col(table, name):
        return columns[table].index(name)

    # Hechizos de Classic: qué enseña cada uno (efecto 36) y qué rango da (efecto 118/44)
    st = "spell_template"
    idx = {k: col(st, k) for k in ["Id"] + [f"{p}{n}" for p in ("Effect", "EffectTriggerSpell", "EffectMiscValue", "EffectBasePoints") for n in (1, 2, 3)]}
    teaches, steps = {}, {}
    for r in data[st]:
        sid = int(r[idx["Id"]])
        for n in (1, 2, 3):
            effect = int(r[idx[f"Effect{n}"]])
            if effect == LEARN_SPELL:
                teaches[sid] = int(r[idx[f"EffectTriggerSpell{n}"]])
            elif effect in (SKILL_STEP, SKILL):
                line = int(r[idx[f"EffectMiscValue{n}"]])
                if line in SKILL_LINES:
                    steps[sid] = (line, int(r[idx[f"EffectBasePoints{n}"]]) + 1)

    # Plantillas de instructor -> PNJ que las usan
    ct = "creature_template"
    users = {}
    for r in data[ct]:
        tpl = int(r[col(ct, "TrainerTemplateId")])
        if tpl:
            users.setdefault(tpl, []).append(int(r[col(ct, "Entry")]))

    out = []
    for table in ("npc_trainer", "npc_trainer_template"):
        for r in data[table]:
            entry, spell, cost, reqskill, reqvalue, reqlevel = (int(x) for x in r[:6])
            target = teaches.get(spell, spell)
            step = steps.get(target)
            if not step and reqskill not in SKILL_LINES:
                continue
            skill = step[0] if step else reqskill
            npcs = users.get(entry, []) if table == "npc_trainer_template" else [entry]
            for npc in npcs:
                out.append((npc, target, cost, skill, reqvalue, reqlevel, step[1] if step else ""))
    out = sorted(set(out))
    OUT.parent.mkdir(exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(["npc", "spell", "cost", "skill", "reqskill", "reqlevel", "rank_step"])
        w.writerows(out)
    print(f"{OUT}: {len(out)} filas ({len({o[0] for o in out})} instructores, {sum(1 for o in out if o[6])} de rango)")


if __name__ == "__main__":
    main()
