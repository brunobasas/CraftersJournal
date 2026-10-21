"""Errores que el addon ha registrado jugando (CraftersJournalDB.errorLog).

Se guardan al hacer /reload o salir del juego. Muestra cada error distinto con
cuántas veces ha pasado, cuándo, con qué versión y su pila.

Uso:  python -X utf8 tools/show_errors.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import run  # noqa: E402

print(run(r"""
local out = {}
local log = ES.db.errorLog or {}
if #log == 0 then return "Ningún error registrado." end
for i, e in ipairs(log) do
  out[#out + 1] = string.format("%d. [%s] x%d  %s - %s  v%s", i, e.kind, e.count,
    os.date("%d/%m %H:%M", e.first), os.date("%d/%m %H:%M", e.last), tostring(e.version))
  out[#out + 1] = "   " .. e.msg
  if e.stack then out[#out + 1] = "   " .. e.stack:gsub("\n", "\n   ") end
end
return table.concat(out, "\n")
"""))
