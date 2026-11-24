"""Qué recetas dejan beneficio vendiendo lo fabricado al VENDEDOR (el «vendor shuffle»).

Con tus datos guardados reales (harness.py: el último escaneo de la AH), TODAS las
recetas de todas las profesiones, las sepas o no:
  - coste de una fabricación comprando los materiales (AH o vendedor, lo más barato)
  - lo que paga el vendedor por lo fabricado
  - cuántas seguidas compensan subiendo por la escalera de las subastas (la misma
    cuenta que la sección «Venta segura al vendedor» de Ganar dinero), sin el tope de
    tiempo ni el mínimo de oro por hora: aquí se ven también las «lentas», que valen
    si fabricas sin estar delante
  - beneficio total, tiempo de fabricar y oro por hora

Uso:  python tools/vendor_audit.py [--min 50]   (beneficio por fabricación mínimo, cobre)
"""
import sys

argv = sys.argv[1:]
MIN = 1
if "--min" in argv:
    MIN = int(argv[argv.index("--min") + 1])
exec(open(__file__.replace("vendor_audit.py", "harness.py"), encoding="utf-8").read())

print(run(r"""
local MIN = {MIN}
local out = {}
local date = date or os.date
local function P(...) out[#out + 1] = string.format(...) end
local function G(c)
  if not c then return "-" end
  local neg = c < 0
  c = math.floor(math.abs(c) + 0.5)
  local g, s, k = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  local txt = g > 0 and string.format("%dg%02ds", g, s) or s > 0 and string.format("%ds%02dc", s, k) or (k .. "c")
  return (neg and "-" or "") .. txt
end

local key = ES:RealmKey()
local scan = assert(CraftersJournalDB.scans[key], "sin escaneo de " .. key)
NOW = scan.time + 60
P("%s · escaneo del %s", key, date("%d/%m %H:%M", scan.time))

-- Sin tope de tiempo: hasta 1000 fabricaciones (VENDOR_MAX)
ES.Earn.VENDOR_TIME_BUDGET = 1e9
local LEARN = { known = "sabida", trainer = "instructor", vendor = "receta vendedor", scroll = "pergamino",
  ah = "pergamino AH", quest = "misión", owned = "en bolsas", rep = "reputación", basic = "básica", favor = "Favor" }
local STOP = { margin = "margen", supply = "sin más subastas", max = "tope 1000", time = "tiempo" }

local rows = {}
for _, p in ipairs(ES.PROFESSIONS) do
  local data = ES.Data[p.key]
  if data then
    local entries, ctx = ES.Planner:RecipeMarket(data, { hours = 24, neutral = ES:IsNeutralAH(),
      sourcedScrolls = ES.Waypoints.SOURCED_PROFESSIONS[p.key] or nil })
    for _, e in ipairs(entries) do
      local sale = (e.vendor or 0) * math.max(1, e.qty)
      if e.cost and sale > 0 and sale - e.cost >= MIN and not ES.Planner.Cooldown(e.recipe, e.id) then
        ctx.used = {}
        local idea = { e = e, ctx = ctx, sellWhere = "vendor", sale = sale, itemID = e.itemID }
        ES.Earn.CostIdea(idea)
        if idea.crafts > 0 then
          -- Materiales que se compran en la AH (los que mueven el precio)
          local mats = {}
          for _, a in ipairs(idea.actions or {}) do
            if a.kind == "ah" then
              local name = (ES.ItemName and ES:ItemName(a.item)) or ("#" .. a.item)
              mats[#mats + 1] = string.format("%dx %s", math.ceil(a.qty - 1e-6), name)
            end
          end
          rows[#rows + 1] = { prof = p.key, e = e, idea = idea, mats = table.concat(mats, ", "),
            ahBetter = e.sellWhere == "ah" }
        end
      end
    end
  end
end
table.sort(rows, function(a, b) return a.idea.profit > b.idea.profit end)

P("")
P("%-14s %-32s %-16s %4s · %9s → %9s · %4s fab · %9s total · %5s min · %8s/h · para en", "profesión", "receta", "aprender", "pide",
  "coste 1ª", "vendedor", "", "beneficio", "", "oro")
for _, r in ipairs(rows) do
  local e, idea = r.e, r.idea
  local learn = LEARN[e.learnSource] or e.learnSource or "?"
  if (e.learnCost or 0) > 0 then learn = learn .. " " .. G(e.learnCost) end
  P("%-14s %-32s %-16s %4d · %9s → %9s · %4d fab · %9s total · %5.0f min · %8s/h · %s%s",
    r.prof, e.recipe.name:sub(1, 32), learn:sub(1, 16), e.learn or 0, G(e.cost), G(idea.sale), idea.crafts,
    G(idea.profit), (idea.seconds or 0) / 60, G(idea.gph), STOP[idea.limit] or tostring(idea.limit),
    r.ahBetter and " · (en la AH se vende mejor)" or "")
  if r.mats ~= "" then P("      compra en la AH: %s", r.mats) end
end
P("")
P("%d recetas. Coste 1ª = la primera fabricación con las subastas más baratas; total = todas las", #rows)
P("que compensan subiendo por la escalera. Tiempo con el lanzamiento por defecto (fuera del juego no")
P("se sabe el de cada receta). Sin enfriamientos.")
return table.concat(out, "\n")
""".replace("{MIN}", str(MIN))))
