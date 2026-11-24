"""Qué recetas de una profesión dan dinero en la AH y cuáles se venden de verdad.

Con tus datos guardados reales (harness.py: el último escaneo y el historial de la
semana), TODAS las recetas de la profesión, las sepas o no:
  - lo que cuesta fabricar una unidad (comprando los materiales en la AH) y a cuánto se
    vende (el precio realista de Ganar dinero: el mínimo, o la referencia del
    historial si el mínimo está inflado), menos comisión y depósito
  - si hay mercado: cuántas subastas hay a la venta
  - si se vende: cuántas de las subastas más baratas desaparecen al día entre
    escaneos (Market:Stuck, campo gone). Es una cota: también desaparecen las que
    caducan o se retiran. Sin TSM (fuera del juego no lo hay) es lo único que hay
  - la alerta de mercado (bien, ojo, evitar, pocos datos) y por qué

Grupos:
  SE VENDE          hay mercado (>= MIN_LISTINGS subastas), las baratas se van y la
                    alerta no es "evitar": ordenadas por beneficio al día (cota)
  SIN DATOS         hay mercado pero falta historial para saber si se vende
                    (bastan 1-2 escaneos al día durante un par de días)
  SIN MERCADO       menos de MIN_LISTINGS subastas: no se sabe si es el precio
  EVITAR            la alerta de mercado dice evitar (estancado, precio clavado...)
Las que no dejan el margen mínimo de Ganar dinero (5c y un 10% del coste) no salen.

Uso:  python tools/earn_audit.py [Tailoring] [--all] [--json archivo.json]
      (--all: también las que no dan beneficio, al final)
      (--json: además, todas las filas en JSON { rows, meta }, para la web del informe;
       el dinero en cobre)
"""
import json
import sys
import time

argv = sys.argv[1:]
JSON_OUT = None
if "--json" in argv:
    i = argv.index("--json")
    JSON_OUT = argv[i + 1]
    del argv[i:i + 2]
args = [a for a in argv if not a.startswith("--")]
PROF = args[0] if args else "Tailoring"
SHOW_ALL = "--all" in sys.argv
exec(open(__file__.replace("earn_audit.py", "harness.py"), encoding="utf-8").read())

print(run(r"""
local PROF, SHOW_ALL = "{PROF}", {SHOW_ALL}
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
local function Dec(x) return x and string.format("%.1f", x) or "-" end

local data = assert(ES.Data[PROF], "no hay datos de " .. PROF)
local key = ES:RealmKey()
local scan = assert(CraftersJournalDB.scans[key], "sin escaneo de " .. key)
-- "Ahora" = el momento del último escaneo: las señales como se veían entonces
NOW = scan.time + 60
local history = ES.History:Entries(key)
P("%s · %s · escaneo del %s · %d escaneos en el historial", PROF, key, date("%d/%m %H:%M", scan.time), #history)

local MIN_LISTINGS = ES.Earn.LEARN_MIN_LISTINGS
local MIN_PROFIT, MIN_MARGIN = 5, 0.10
-- Todas las recetas que se pueden conseguir; lo intermedio (Bolt of Runecloth) se
-- fabrica aunque no sepas la receta: el informe es de la profesión, no del personaje
local entries = ES.Planner:RecipeMarket(data, { hours = 24, neutral = ES:IsNeutralAH(),
  sourcedScrolls = ES.Waypoints.SOURCED_PROFESSIONS[PROF] or nil })

local LEARN = { known = "sabida", trainer = "instructor", vendor = "vendedor", scroll = "pergamino",
  ah = "pergamino AH", quest = "misión", owned = "en bolsas", rep = "reputación", basic = "básica", favor = "Favor" }
local groups = { sells = {}, nodata = {}, thin = {}, avoid = {}, loss = {} }
AUDIT_ROWS = {}
local skipped = { bop = 0, vendor = 0, nocost = 0, noah = 0 }
for _, e in ipairs(entries) do
  if not e.cost then
    skipped.nocost = skipped.nocost + 1
  elseif e.recipe.bop then
    skipped.bop = skipped.bop + 1
  elseif not e.ahNet then
    skipped.noah = skipped.noah + 1
  else
    local qty = math.max(1, e.qty)
    local row = { e = e, costU = e.cost / qty, priceU = e.ahPrice, netU = e.ahNet }
    row.profitU = row.netU - row.costU
    local ok = row.profitU * qty >= math.max(MIN_PROFIT, e.cost * MIN_MARGIN)
    local s = ES.Market:Signals(e.itemID)
    row.s = s
    -- Unidades por subasta (para pasar de subastas que se van a unidades)
    row.perAuction = e.listings > 0 and e.quantity / e.listings or 1
    row.goneU = s.stuck.gone and s.stuck.gone * row.perAuction or nil
    row.dayProfit = row.goneU and row.goneU * row.profitU or nil
    local why = {}
    for _, l in ipairs(ES.Market.Describe(s)) do
      if l[2] then why[#why + 1] = (l[1]:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
    end
    row.why = table.concat(why, " | ")
    local g
    if not ok then g = "loss"
    elseif s.verdict == "avoid" then g = "avoid"
    elseif e.listings < MIN_LISTINGS then g = "thin"
    elseif not s.stuck.known then g = "nodata"
    else g = "sells" end
    local list = groups[g]
    list[#list + 1] = row
    -- (para --json: valores sueltos, el dinero en cobre)
    local function Round(x, d) return x and math.floor(x * 10 ^ (d or 0) + 0.5) / 10 ^ (d or 0) or nil end
    AUDIT_ROWS[#AUDIT_ROWS + 1] = {
      recipe = e.recipe.name, group = g, learn = e.learnSource, learnCost = Round(e.learnCost or 0),
      skill = e.learn or 0, cost = Round(row.costU), price = Round(row.priceU), profit = Round(row.profitU),
      margin = Round(row.profitU / math.max(1, row.costU) * 100), listings = e.listings, units = e.quantity,
      gonePerDay = Round(row.goneU, 1), marketPerDay = Round(row.dayProfit), hours = Round(s.stuck.hours, 1),
      verdict = s.verdict, alerts = row.why,
      inflated = e.fair and e.fair.inflated or false, noHistory = e.fair and e.fair.noHistory or false,
      cooldown = ES.Planner.Cooldown(e.recipe, e.id) and true or false,
    }
  end
end
AUDIT_META = { scan = scan.time, realm = key, scans = #history, minListings = MIN_LISTINGS }

local function Line(row, extra)
  local e = row.e
  local learn = LEARN[e.learnSource] or e.learnSource
  if (e.learnCost or 0) > 0 then learn = learn .. " " .. G(e.learnCost) end
  -- (con enfriamiento: una cada tanto, por mucho que se venda)
  local cd = ES.Planner.Cooldown(e.recipe, e.id)
  if cd then extra = (extra or "") .. " · ENFRIAMIENTO" end
  P("  %-34s %-20s pide %3d · coste %9s · AH %9s%s · gana %9s/u (%3d%%) · %3d subastas %4d uds%s",
    e.recipe.name:sub(1, 34), learn:sub(1, 20), e.learn or 0, G(row.costU), G(row.priceU),
    e.fair and e.fair.inflated and "*" or (e.fair and e.fair.noHistory and "?" or " "),
    G(row.profitU), math.floor((row.profitU / math.max(1, row.costU)) * 100 + 0.5), e.listings, e.quantity, extra or "")
end

local function Section(title, list, sort, extra)
  if #list == 0 then return end
  table.sort(list, sort)
  P("")
  P("%s (%d)", title, #list)
  for _, row in ipairs(list) do
    Line(row, extra and extra(row))
    if row.why ~= "" and (title:find("EVITAR") or title:find("SE VENDE")) then P("      alertas: %s", row.why) end
  end
end

Section("SE VENDE: hay mercado y las baratas se van (por mercado al día: beneficio × lo que se va)", groups.sells,
  function(a, b) return (a.dayProfit or 0) > (b.dayProfit or 0) end,
  function(row)
    local label = (ES.Market.LABELS[row.s.verdict] or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return string.format(" · se van ~%s/día · mercado ~%s/día · %s", Dec(row.goneU), G(row.dayProfit), label)
  end)
Section("SIN DATOS DE VENTAS: hay mercado, falta historial", groups.nodata,
  function(a, b) return a.profitU > b.profitU end,
  function(row) return string.format(" · %s h observadas", Dec(row.s.stuck.hours)) end)
Section(string.format("SIN MERCADO: menos de %d subastas (no se sabe si es el precio)", MIN_LISTINGS), groups.thin,
  function(a, b) return a.profitU > b.profitU end)
Section("EVITAR: la alerta de mercado dice evitar", groups.avoid,
  function(a, b) return a.profitU > b.profitU end)
if SHOW_ALL then
  Section("SIN BENEFICIO (menos del margen mínimo)", groups.loss, function(a, b) return a.profitU > b.profitU end)
end
P("")
P("Leyenda: AH con * = precio inflado recortado a la referencia; ? = sin historial (el precio de ahora).")
P("«se van/día» = subastas baratas (hasta un 10%% sobre el mínimo) que desaparecen al día × unidades")
P("por subasta: cota de ventas (también cuentan las que caducan, se retiran o se vuelven a anunciar).")
P("«mercado/día» = ese beneficio por todo lo que se va: lo que se reparten TODOS los vendedores, no tu parte.")
P("Fuera: %d ligadas al recogerlas, %d sin precio de materiales, %d sin AH (no están a la venta o el",
  skipped.bop, skipped.nocost, skipped.noah)
P("vendedor paga más), %d sin beneficio%s.", #groups.loss, SHOW_ALL and "" or " (--all para verlas)")
return table.concat(out, "\n")
""".replace("{PROF}", PROF).replace("{SHOW_ALL}", "true" if SHOW_ALL else "false")))

if JSON_OUT:
    # Las filas (todas, también las sin beneficio) y de dónde salen: el código de este
    # script, para poder revisarlo y volver a ejecutarlo
    g = lua.globals()
    rows = []
    for i in range(1, len(g.AUDIT_ROWS) + 1):
        r = g.AUDIT_ROWS[i]
        rows.append({k: r[k] for k in r.keys()})
    m = g.AUDIT_META
    when = time.strftime("%d/%m/%Y %H:%M", time.localtime(m["scan"]))
    code = open(__file__, encoding="utf-8").read()
    meta = [
        {"label": "earn_audit.py", "value": code, "type": "code", "lang": "python"},
        {"label": "Input", "value": "SavedVariables de Crafter's Journal: escaneo de la AH del %s (%s) e historial de %d escaneos"
            % (when, m["realm"], m["scans"])},
        {"label": "Profesión", "value": PROF},
    ]
    with open(JSON_OUT, "w", encoding="utf-8") as f:
        json.dump({"rows": rows, "meta": meta}, f, ensure_ascii=False)
    print("JSON: %d filas en %s" % (len(rows), JSON_OUT))
