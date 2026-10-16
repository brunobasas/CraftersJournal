exec(open(__file__.replace("market_audit.py", "harness.py"), encoding="utf-8").read())
print(run(r"""
local out = {}
date = date or os.date
local function P(...) out[#out+1] = string.format(...) end
local key = ES:RealmKey()
local h = ES.History:Entries(key)
local scan = CraftersJournalDB.scans[key]
-- "Ahora" = momento del último escaneo, para ver las señales como las veías entonces
NOW = scan.time + 60
P("Escaneos en historial: %d (del %s al %s)", #h, date("%d/%m %H:%M", h[1].time), date("%d/%m %H:%M", h[#h].time))
local withStuck, gaps = 0, {}
for i, e in ipairs(h) do
  if e.stuck then withStuck = withStuck + 1 end
  if e.elapsed and e.elapsed > 0 then gaps[#gaps + 1] = math.floor(e.elapsed / 3600 * 10 + 0.5) / 10 end
end
P("Con dato de 'siguen' (estancamiento): %d · separaciones entre escaneos (h): %s", withStuck, table.concat(gaps, ", "))
local recent = 0
for _, e in ipairs(h) do if NOW - e.time < 7 * 86400 then recent = recent + 1 end end
P("Escaneos en los últimos 7 días (lo que miran las alertas): %d", recent)

-- Señales de todos los objetos de profesiones del último escaneo
local counts = { stuck = { k = 0, f = 0 }, price = { k = 0, f = 0 }, supply = { k = 0, f = 0 }, wall = { k = 0, f = 0 } }
local verdicts, n, crafted = {}, 0, {}
for _, data in pairs(ES.Data) do
  if type(data) == "table" and data.recipes then
    for _, r in pairs(data.recipes) do if r.out then crafted[r.out[1]] = true end end
  end
end
local examples = { wall = {}, price = {}, supply = {}, stuck = {} }
local wallByKind = { crafted = { 0, 0 }, material = { 0, 0 } }
for itemID, e in pairs(scan.items) do
  if e.minUnit and ES.History:IsTracked(itemID) then
    n = n + 1
    local s = ES.Market:Signals(itemID)
    verdicts[s.verdict] = (verdicts[s.verdict] or 0) + 1
    for k, c in pairs(counts) do
      if s[k].known then c.k = c.k + 1 end
      if s[k].flag then c.f = c.f + 1; if #examples[k] < 4 then examples[k][#examples[k] + 1] = itemID end end
    end
    local kind = crafted[itemID] and "crafted" or "material"
    if s.wall.known then
      wallByKind[kind][1] = wallByKind[kind][1] + 1
      if s.wall.flag then wallByKind[kind][2] = wallByKind[kind][2] + 1 end
    end
  end
end
P("Objetos de profesiones en la AH: %d", n)
for _, k in ipairs({ "stuck", "price", "supply", "wall" }) do
  P("  %-7s con datos para opinar %4d (%3d%%) · marcados %4d", k, counts[k].k, math.floor(counts[k].k / n * 100), counts[k].f)
end
P("  competencia marcada: fabricados %d de %d · materiales %d de %d", wallByKind.crafted[2], wallByKind.crafted[1], wallByKind.material[2], wallByKind.material[1])
local vt = {}
for k, v in pairs(verdicts) do vt[#vt + 1] = k .. " " .. v end
P("Veredictos: %s", table.concat(vt, " · "))
local names = {}
for _, prof in pairs({ "Leatherworking", "Tailoring", "Cooking", "Alchemy", "Blacksmithing", "Engineering", "Enchanting", "FirstAid" }) do
  for id, r in pairs(ES.Data[prof].recipes) do
    if r.out then names[r.out[1]] = r.name end
    for _, rq in ipairs(r.r) do names[rq[1]] = names[rq[1]] or ("mat " .. rq[1]) end
  end
end
for k, list in pairs(examples) do
  for _, id in ipairs(list) do
    local s = ES.Market:Signals(id)
    local e = scan.items[id]
    local lines = {}
    for _, l in ipairs(ES.Market.Describe(s)) do if l[2] then lines[#lines + 1] = l[1] end end
    P("  ej. %-7s %-28s (%d subastas, %d uds) -> %s", k, tostring(names[id] or id), e.listings, e.quantity, table.concat(lines, " | "))
  end
end
local nailed = 0
for itemID, e in pairs(scan.items) do
  if e.minUnit and ES.History:IsTracked(itemID) and ES.Market:Signals(itemID).nailed.flag then nailed = nailed + 1 end
end
P("Precio clavado (mínimo fijo + competencia): %d", nailed)
return table.concat(out, "\n")
"""))
