exec(open(__file__.replace("perf.py", "harness.py"), encoding="utf-8").read())
print(run(r"""
local out = {}
local clock = py_clock
UnitFactionGroup = function() return "Alliance" end
ES:GetMainFrame()
local t0 = clock()
ES:SelectPage("home")
out[#out+1] = string.format("Portada (8 planes): %.2fs", clock() - t0)
for _, page in ipairs(ES.professionPages) do
  page.from = 1
  page.toBox._text = "225"
  local t = clock()
  ES:CalculatePlan(page)
  out[#out+1] = string.format("  %-15s plan 1-225: %.3fs", page.profKey, clock() - t)
end
ES.db.prof.Leatherworking.useBags = true
local page
for _, p in ipairs(ES.professionPages) do if p.profKey == "Leatherworking" then page = p end end
BAGS[2318] = 50
local t = clock()
ES:CalculatePlan(page)
out[#out+1] = string.format("  Peletería con bolsas: %.3fs", clock() - t)
ES.db.prof.Leatherworking.useBags = nil
t = clock()
ES.Market:Index()
local n = 0
for itemID in pairs(CraftersJournalDB.scans[ES:RealmKey()].items) do ES.Market:Signals(itemID) n = n + 1 end
out[#out+1] = string.format("Señales de mercado de %d objetos: %.2fs", n, clock() - t)
t = clock()
ES:RefreshAllViews()
out[#out+1] = string.format("Refrescar todo tras un escaneo: %.2fs", clock() - t)
-- Ganar dinero y Colección (personaje con peletería y cocina al 150, sabiendo las de instructor)
local realSkill, realKnown = ES.GetProfessionSkill, ES.IsRecipeKnown
ES.GetProfessionSkill = function(self, line)
  if line == ES.Data.Leatherworking.skillLine or line == ES.Data.Cooking.skillLine then return 150, 225 end
end
ES.IsRecipeKnown = function(self, id)
  local r = ES.Data.Leatherworking.recipes[id] or ES.Data.Cooking.recipes[id]
  return r ~= nil and r.fee ~= nil and (r.train or 1) <= 150
end
ES.Earn:Clear()
t = clock()
local res = ES.Earn:Ideas()
out[#out+1] = string.format("Ganar dinero (2 profesiones, %d conocidas): %.2fs · %d ideas, %d evitar", res.known, clock() - t, #res.ideas, #res.avoided)
for i = 1, math.min(5, #res.batch) do
  local idea = res.batch[i]
  out[#out+1] = string.format("   %2dx %-28s +%5dc/u  %s  %s", idea.crafts, idea.e.recipe.name, math.floor(idea.e.profit), tostring(idea.verdict or idea.sellWhere), idea.why)
end
t = clock()
local col = ES.Collection:Build("Leatherworking")
out[#out+1] = string.format("Colección peletería (%d recetas): %.2fs", col.total, clock() - t)
ES.GetProfessionSkill, ES.IsRecipeKnown = realSkill, realKnown
return table.concat(out, "\n")
"""))
