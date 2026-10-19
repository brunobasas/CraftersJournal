"""Carga el addon completo con una API de WoW simulada y ejecuta la UI."""
import re
import sys
from pathlib import Path

import os
sys.path.insert(0, os.environ.get("ESLUA", r"C:\Users\bruno\AppData\Local\Temp\eslua"))  # carpeta con lupa (Lua 5.1)
from lupa import lua51

ADDON = Path(__file__).resolve().parent.parent  # el repositorio (no depende del enlace en AddOns)
lua = lua51.LuaRuntime(unpack_returned_tuples=True)

lua.execute(r"""
NOW = 2000000
time = function() return NOW end
bit = bit or { band = function(a, b) local r, p = 0, 1 while a > 0 and b > 0 do if a % 2 == 1 and b % 2 == 1 then r = r + p end a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2 end return r end }
local function Mock(name)
  local m = { _scripts = {}, _name = name }
  return setmetatable(m, { __index = function(t, k)
    if k == "SetScript" then return function(self, n, f) self._scripts[n] = f end end
    if k == "GetScript" then return function(self, n) return self._scripts[n] end end
    if k == "GetWidth" or k == "GetHeight" or k == "GetEffectiveScale" or k == "GetStringWidth" or k == "GetFrameLevel" or k == "GetLeft" or k == "GetTop" then return function() return 100 end end
    if k == "GetScale" then return function(self) return self._scale or 1 end end
    if k == "SetScale" then return function(self, v) self._scale = v end end
    if k == "GetText" then return function(self) return self._text or "" end end
    if k == "SetText" then return function(self, v) self._text = v and tostring(v) end end
    if k == "GetCenter" then return function() return 0, 0 end end
    if k == "IsShown" or k == "IsVisible" then return function() return true end end
    if k == "GetChecked" then return function(self) if self._checked == nil then return true end return self._checked end end
    if k == "SetChecked" then return function(self, v) self._checked = v and true or false end end
    -- Como en WoW: solo los métodos (con mayúscula) existen; los campos propios no
    if type(k) ~= "string" or not k:match("^%u") then return nil end
    return function() return Mock(k) end
  end })
end
CreateFrame = function(_, name) local f = Mock("frame") if name then _G[name] = f end return f end
UIParent, Minimap, GameTooltip = Mock(), Mock(), Mock()
UISpecialFrames, SlashCmdList = {}, {}
tinsert = table.insert
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
C_Timer = { After = function(_, f) end }
GetRealmName = function() return "Realm" end
UnitFactionGroup = function() return "Alliance" end
ITEM_QUALITY_COLORS = { [1] = { r = 1, g = 1, b = 1, hex = "|cffffffff" } }
GetItemInfo = function(id) return nil end
GetCursorPosition = function() return 0, 0 end
GetTime = function() return 0 end
FrameUtil = {}
UnitExists = function() return true end
UnitName = function() return "Bruno" end
""")

# Globales escritas desde los archivos del addon (los mocks del test no cuentan)
lua.execute(r"""
LEAKS = {}
local ALLOWED = { CraftersJournalDB = true, SLASH_CRAFTERSJOURNAL1 = true, SLASH_CRAFTERSJOURNAL2 = true, SLASH_CRAFTERSJOURNAL3 = true,
  CraftersJournal_OnAddonCompartmentClick = true, CraftersJournal = true, CraftersJournalMainFrame = true,
  CraftersJournalAHButton = true, CraftersJournalMinimapButton = true }
setmetatable(_G, { __newindex = function(t, k, v)
  local info = debug.getinfo(2, "S")
  if info and info.source:match("^@[%w\\/]+%.lua$") and not ALLOWED[k] then LEAKS[#LEAKS + 1] = info.source .. ":" .. tostring(k) end
  rawset(t, k, v)
end })
""")

toc = (ADDON / "CraftersJournal.toc").read_text(encoding="utf-8")
files = [l.strip() for l in toc.splitlines() if l.strip() and not l.startswith("#")]
ES = lua.eval("{}")
loader = lua.eval("function(src, name, ES) assert(loadstring(src, '@' .. name))('CraftersJournal', ES) end")
for f in files:
    loader((ADDON / f.replace("\\", "/")).read_text(encoding="utf-8"), f, ES)
lua.globals().ES = ES
lua.execute("SOURCES, SOURCE_NAMES = {}, {}")
for f in files:
    lua.eval("function(s, n) SOURCES[#SOURCES + 1] = s SOURCE_NAMES[#SOURCES] = n end")(
        (ADDON / f.replace("\\", "/")).read_text(encoding="utf-8"), f)
print("cargados:", ", ".join(files))

lua.execute(r"""
-- Eventos de inicio
CraftersJournalDB = nil
local events
-- El frame de eventos de Core es el primero creado con OnEvent: lo buscamos por el handler
for _, v in pairs(_G) do end
""")

out = lua.execute(r"""
local log = {}
local function step(name, fn)
  local ok, err = pcall(fn)
  log[#log + 1] = (ok and "OK   " or "FAIL ") .. name .. (ok and "" or (": " .. tostring(err)))
end

-- Simular ADDON_LOADED a mano (el mock no dispara eventos)
CraftersJournalDB = { scans = {} }
ES.db = CraftersJournalDB
ES.db.minimap = { angle = 225 }

local key = ES:RealmKey()
local S = ES.History
local function sigs(list)
  local t = {}
  for _, a in ipairs(list) do
    local sig = S.Signature(a[1], a[2], a[3], a[4])
    S.AddAuction(t, sig, a[5])
  end
  return t
end

step("historial: 3 escaneos", function()
  -- t0: 5 pantalones (4242) y 10 cuero ligero (2318 x5) con tiempo largo
  local a = {}
  for i = 1, 5 do a[#a+1] = { 4242, 1, 900, "Pepe", 4 } end
  for i = 1, 10 do a[#a+1] = { 2318, 5, 125, "Ana", 4 } end
  NOW = 2000000; S:Record(key, sigs(a), ";4242:900:5;2318:25:10", NOW)
  -- t0+1h: se venden 2 pantalones y 4 lotes de cuero
  local b = {}
  for i = 1, 3 do b[#b+1] = { 4242, 1, 900, "Pepe", 4 } end
  for i = 1, 6 do b[#b+1] = { 2318, 5, 125, "Ana", 4 } end
  NOW = 2003600; S:Record(key, sigs(b), ";4242:900:3;2318:25:6", NOW)
  -- t0+2h: se vende 1 pantalÃ³n mÃ¡s
  local c = {}
  for i = 1, 2 do c[#c+1] = { 4242, 1, 1000, "Pepe", 4 } end
  for i = 1, 6 do c[#c+1] = { 2318, 5, 125, "Ana", 4 } end
  NOW = 2007200; S:Record(key, sigs(c), ";4242:1000:2;2318:25:6", NOW)
  ES.db.scans[key] = { time = NOW, total = 8, unique = 2, items = {
    [4242] = { listings = 2, quantity = 2, minUnit = 1000, avgUnit = 1000, sellers = 1, topShare = 1 },
    [2318] = { listings = 6, quantity = 30, minUnit = 25, avgUnit = 25, sellers = 1, topShare = 1 },
    [2934] = { listings = 2, quantity = 40, minUnit = 5, avgUnit = 5, sellers = 2, topShare = 0.5 },
  } }
  local n, c2 = S:Summary()
  log[#log+1] = string.format("     resumen: %d escaneos, %d comparaciones", n, c2)
  assert(n == 3 and c2 == 2, "resumen incorrecto")
  log[#log+1] = "     snapshot antiguo pantalones: " .. tostring(S:OldestSnapshot(4242, 86400))
  local last = ES.db.history[key][3]
  log[#log+1] = "     baratas que siguen (último): " .. tostring(last.stuck)
  assert(last.sold == nil, "el historial no debe guardar ventas")
end)

step("crear panel", function() ES:ShowMainFrame() end)
step("pintar mercado", function() ES:RenderResults() end)
step("pintar mercado (3 días, todas las columnas)", function()
  ES.db.topWindow = "3d"
  for _, h in ipairs(CraftersJournalMainFrame.headers) do h._scripts.OnClick(h) h._scripts.OnClick(h) end
end)
step("tooltip fila mercado", function()
  local row = CraftersJournalMainFrame.rows[1]
  row._scripts.OnEnter(row)
  log[#log+1] = "     fila1: " .. tostring(row.cells.name._text) .. " | subastas " .. tostring(row.cells.listings._text)
    .. " | tendencia " .. tostring(row.cells.trend._text) .. " | mercado " .. tostring(row.cells.market._text)
end)
step("franja de 7 días y versión antigua guardada", function()
  ES.db.topWindow = "all"; ES.db.topSortBy = { key = "sold", asc = false } -- de versiones anteriores
  ES:RenderResults()
  assert(ES.db.topSortBy.key == "listings", "no migró el orden antiguo")
end)

step("pestaÃ±a peleterÃ­a", function()
  ES:SelectPage("lw")
  local page
  for _, p in ipairs(ES.professionPages) do if p.profKey == "Leatherworking" then page = p end end
  page._scripts.OnShow(page)
  -- El nivel actual no se edita (sin la profesión: 1); el objetivo sí, y recalcula
  assert(page.from == 1, "nivel actual " .. tostring(page.from))
  page.toBox._text = "75"
  page.toBox._scripts.OnEnterPressed(page.toBox)
  assert(page.plan and page.plan.to == 75, "no recalculó al cambiar el objetivo")
  log[#log+1] = string.format("     resumen: materiales %s | profit %s | instructor %s | total %s",
    tostring(page.stats.materials._text), tostring(page.stats.profit._text), tostring(page.stats.fees._text), tostring(page.stats.total._text))
  log[#log+1] = "     estado: " .. tostring(page.status._text)
  assert(#page.viewButtons == 3, "la vista Recetas ya no está dentro de la profesión")
  for _, view in ipairs({ "route", "profit", "shop" }) do
    local b
    for _, vb in ipairs(page.viewButtons) do if vb.key == view then b = vb end end
    b._scripts.OnClick(b)
    local n = 0
    for i = 1, #page.lines do
      local row = page.rows[i]
      if row.tooltip then row._scripts.OnEnter(row) end
      n = n + 1
      if i <= 3 then log[#log+1] = string.format("       %s %d: %s | %s | %s", view, i, tostring(row.title._text), tostring(row.sub._text), tostring(row.value._text)) end
    end
    log[#log+1] = string.format("     vista %s: %d filas", view, n)
  end
  assert(ES.db.prof.Leatherworking.view == "shop", "no recuerda la vista")
  -- Vista guardada de una versión anterior ("market"): vuelve a la ruta
  ES:SelectProfessionView(page, "market")
  assert(page.view == "route", "la vista antigua debería volver a Ruta")
  ES:SelectProfessionView(page, "route")
  -- Icono de bolsas: alterna y recalcula
  local before = ES.db.prof.Leatherworking.useBags
  page.bagsButton._scripts.OnClick(page.bagsButton)
  assert(ES.db.prof.Leatherworking.useBags ~= before, "el icono de bolsas no cambió el ajuste")
  page.bagsButton._scripts.OnEnter(page.bagsButton)
  page.bagsButton._scripts.OnClick(page.bagsButton)
end)
step("lista de la compra desglosada", function()
  local page
  for _, p in ipairs(ES.professionPages) do if p.profKey == "Leatherworking" then page = p end end
  local plan = page.plan
  for _, c in ipairs(plan.crafted) do
    log[#log+1] = string.format("     fabricar antes: %dx item %d", c.quantity, c.itemID)
  end
  for _, s in ipairs(plan.shopping) do
    log[#log+1] = string.format("     comprar: %dx item %d (%s)%s", s.quantity, s.itemID, tostring(s.source),
      s.ahShort and (" ¡solo " .. s.ahShort .. " en AH!") or "")
  end
  log[#log+1] = "     pendingInfo=" .. tostring(plan.pendingInfo)
end)
step("señales de mercado (1 escaneo cada 12 h)", function()
  -- 7777 atascado: las baratas siguen, el mínimo no se mueve, cada escaneo 6 más
  -- 8888 se mueve: las baratas desaparecen, el precio cambia, pocas subastas
  -- 6666 material con mucha competencia que se vende: muro en el mínimo pero rota
  local saved = { ES.db.history, ES.db.track }
  ES.db.history, ES.db.track = {}, {}
  local T = 3000000
  for k = 0, 4 do
    local a = {}
    local n = 10 + 6 * k
    for i = 1, n do a[#a+1] = { 7777, 1, 100, "?", 4 } end
    local p = 500 + 37 * k -- cada vez otras subastas, a otro precio
    for i = 1, 3 do a[#a+1] = { 8888, 1, p, "?", 4 } end
    for i = 1, 8 do a[#a+1] = { 6666, 20, 200 + k * 20, "?", 4 } end
    NOW = T + k * 12 * 3600
    S:Record(key, sigs(a), string.format(";7777:100:%d:100:%d;8888:%d:3:%d:3;6666:10:8:10:160", n, n, p, p), NOW)
  end
  local bad, good, wall = ES.Market:Signals(7777), ES.Market:Signals(8888), ES.Market:Signals(6666)
  for _, l in ipairs(ES.Market.Describe(bad)) do log[#log+1] = "     7777 " .. l[1] end
  for _, l in ipairs(ES.Market.Describe(good)) do log[#log+1] = "     8888 " .. l[1] end
  for _, l in ipairs(ES.Market.Describe(wall)) do log[#log+1] = "     6666 " .. l[1] end
  assert(bad.verdict == "avoid" and bad.flags == 3, "7777: esperado evitar 3/3, salió " .. bad.verdict .. " " .. bad.flags)
  assert(good.verdict == "good", "8888: esperado bien, salió " .. good.verdict .. " " .. good.flags)
  assert(wall.verdict ~= "avoid" and not wall.stuck.flag, "6666: la competencia sola no debe dar evitar, salió " .. wall.verdict)
  ES.db.history, ES.db.track = saved[1], saved[2]
end)
step("precio inflado (caso Westfall Stew)", function()
  local saved = { ES.db.history, ES.db.track }
  ES.db.history, ES.db.track = {}, {}
  local T = 4000000
  -- 3 días a ~4s90 y hoy, sin existencias baratas, el mínimo salta a 23s
  local mins = { 494, 493, 490, 489, 2300 }
  for k, m in ipairs(mins) do
    NOW = T + (k - 1) * 20 * 3600
    S:Record(key, sigs({ { 733, 1, m, "?", 4 } }), string.format(";733:%d:10:%d:40", m, m), NOW)
  end
  local fp = ES.Market:FairPrice(733, 2300)
  log[#log+1] = string.format("     referencia %s (%s días) · inflado %s · se cuenta a %s · anunciar a %s",
    tostring(fp.ref), tostring(fp.days), tostring(fp.inflated), tostring(fp.price), tostring(ES.Market.ListPrice(fp)))
  assert(fp.inflated and fp.ref >= 489 and fp.ref <= 494, "debería detectar el pico")
  assert(fp.price == math.floor(fp.ref * ES.Market.PREMIUM + 0.5), "precio realista")
  -- Normal: el mínimo de siempre se anuncia 1 cobre por debajo
  local normal = ES.Market:FairPrice(733, 500)
  assert(not normal.inflated and ES.Market.ListPrice(normal) == 499, "precio normal")
  -- Malvendido: se avisa pero se iguala
  local cheap = ES.Market:FairPrice(733, 200)
  assert(cheap.deflated and cheap.price == 200, "malvendido")
  -- Escaneos sueltos: un día a 4s90, nada en 4 días y hoy 23s: sigue detectando el pico
  ES.db.history, ES.db.track = {}, {}
  NOW = T
  S:Record(key, sigs({ { 733, 1, 490, "?", 4 } }), ";733:490:10:490:40", NOW)
  NOW = T + 4 * 86400 + 3600
  S:Record(key, sigs({ { 733, 1, 2300, "?", 4 } }), ";733:2300:10:2300:40", NOW)
  local loose = ES.Market:FairPrice(733, 2300)
  log[#log+1] = string.format("     escaneos sueltos: referencia %s de hace %s días · inflado %s", tostring(loose.ref), tostring(loose.ago), tostring(loose.inflated))
  assert(loose.inflated and loose.ref == 490 and loose.ago == 4, "escaneos sueltos")
  -- Sin historial: se avisa
  local none = ES.Market:FairPrice(99999, 1000)
  assert(none.noHistory and none.price == 1000, "sin historial")
  ES.db.history, ES.db.track = saved[1], saved[2]
end)
step("lista de compra en la AH", function()
  local searched
  AuctionFrame = CreateFrame("Frame")
  BrowseName = CreateFrame("EditBox")
  AuctionFrameBrowse_Search = function() searched = BrowseName:GetText() end
  CanSendAuctionQuery = function() return true, true end
  local realData = ES.GetItemData
  ES.GetItemData = function(self, id) return "Item" .. id, 1, 134400 end
  ES:SetupAuctionPanel(AuctionFrame)
  local st = ES.AuctionPanelState
  assert(st.profKey == "Leatherworking", "profesión: " .. tostring(st.profKey))
  local buys = 0
  for _, l in ipairs(st.lines) do if l.buy then buys = buys + 1 end end
  assert(buys > 0, "sin materiales que comprar")
  local first
  for _, l in ipairs(st.lines) do if l.buy then first = l.itemID break end end
  ES:SearchAuction(first)
  assert(searched == "Item" .. first, "no buscó: " .. tostring(searched))
  -- "Comprar" el primero: deja de salir como pendiente y Buscar siguiente pasa al segundo
  local real = ES.ItemCount
  ES.ItemCount = function(self, id) if id == first then return 999 end return real(self, id) end
  ES:RenderAuctionPanel()
  log[#log+1] = string.format("     %d materiales a comprar; buscado %s", buys, searched)
  for _, l in ipairs(st.lines) do
    if l.sell then log[#log+1] = "     vender: " .. l.itemID .. " x" .. l.s.advice.ah .. " a " .. l.s.advice.price end
  end
  ES.ItemCount = real
  ES.GetItemData = realData
end)
step("ganar dinero y buzón", function()
  -- Peletería al 150 sabiendo todas sus recetas de instructor
  local realSkill, realKnown = ES.GetProfessionSkill, ES.IsRecipeKnown
  ES.GetProfessionSkill = function(self, line) if line == ES.Data.Leatherworking.skillLine then return 150, 225 end end
  ES.IsRecipeKnown = function(self, id) local r = ES.Data.Leatherworking.recipes[id] return r ~= nil and r.fee ~= nil end
  -- Buzón: una venta y una caducada de algo de peletería
  local out
  for _, r in pairs(ES.Data.Leatherworking.recipes) do if r.out and r.fee then out = r.out[1] break end end
  ES.db.mail = { [ES:CharKey()] = { seen = {}, events = { { NOW - 3600, out, "sold", 1234, "X" }, { NOW - 7200, out, "expired", 0, "X" } } } }
  local st = ES.Mail:Stats(out)
  assert(st.sold == 1 and st.expired == 1 and st.money == 1234, "stats buzón")
  -- Lectura real del buzón: asuntos con el formato del juego (con caracteres especiales)
  AUCTION_SOLD_MAIL_SUBJECT, AUCTION_EXPIRED_MAIL_SUBJECT = "Auction successful: %s", "Auction expired: %s"
  assert(("Auction successful: Heavy Armor Kit (x2)"):match(ES.Mail.SubjectPattern(AUCTION_SOLD_MAIL_SUBJECT)) == "Heavy Armor Kit (x2)", "patrón de asunto")
  local inbox = {
    { "Auction House", "Auction successful: Copper Bar", 5000, 29 },
    { "Auction House", "Auction expired: Copper Bar", 0, 28 },
    { "Bob", "hola", 0, 10 },
  }
  GetInboxNumItems = function() return #inbox end
  GetInboxHeaderInfo = function(i) local m = inbox[i] return nil, nil, m[1], m[2], m[3], nil, m[4] end
  GetInboxItem = function() return "Copper Bar", 2840, nil, 5 end
  ES.db.mail = nil
  assert(ES.Mail:Scan() == 2, "debería leer 2 correos de subasta")
  assert(ES.Mail:Scan() == 0, "no debe contar dos veces el mismo correo")
  local sum = ES.Mail:Summary()
  assert(sum.sold == 1 and sum.expired == 1 and sum.money == 5000, "resumen del buzón")
  GetInboxNumItems, GetInboxHeaderInfo, GetInboxItem = nil, nil, nil
  ES.db.mail = { [ES:CharKey()] = { seen = {}, events = { { NOW - 3600, out, "sold", 1234, "X" }, { NOW - 7200, out, "expired", 0, "X" } } } }
  ES.Earn:Clear()
  local res = ES.Earn:Ideas()
  assert(res.known > 0, "no detecta recetas conocidas")
  log[#log+1] = string.format("     %d conocidas, %d ideas, %d evitar, lote %d: invierte %s gana %s, %d materiales",
    res.known, #res.ideas, #res.avoided, #res.batch, ES.Money(res.invest), ES.Money(res.profit), #res.shopping)
  for i = 1, math.min(3, #res.batch) do
    local idea = res.batch[i]
    log[#log+1] = string.format("       %dx %s +%s (%s, %s)", idea.crafts, idea.e.recipe.name, ES.Money(idea.profit), tostring(idea.verdict or idea.sellWhere), idea.why)
  end
  -- Presupuesto: con poco oro, el lote invierte como mucho eso
  if #res.batch > 1 then
    local first = res.batch[1]
    ES.db.earnBudget = tostring(math.max(1, math.ceil(first.invest / 10000)))
    ES.Earn:Clear()
    local small = ES.Earn:Ideas()
    log[#log+1] = string.format("     con presupuesto de %so: %d recetas, invierte %s", ES.db.earnBudget, #small.batch, ES.Money(small.invest))
    assert(small.invest <= tonumber(ES.db.earnBudget) * 10000, "se pasa del presupuesto")
    ES.db.earnBudget = nil
  end
  -- Lo que ya llevas fabricado: no se vuelve a fabricar
  if res.batch[1] then
    local item = res.batch[1].itemID
    local real = ES.ItemCount
    ES.ItemCount = function(self, id) if id == item then return 999 end return real(self, id) end
    ES.Earn:Clear()
    local again = ES.Earn:Ideas()
    local found
    for _, idea in ipairs(again.ideas) do if idea.itemID == item then found = idea end end
    assert(found and found.crafts == 0 and found.invest == 0, "debería no fabricar lo que ya tienes")
    ES.ItemCount = real
    ES.Earn:Clear()
  end
  -- Página y portada
  ES:SelectPage("money")
  ES:RenderEarn()
  ES:SelectPage("home")
  -- Panel de la AH en modo Ganar dinero
  ES.AuctionPanelState.profKey = "money"
  ES:RefreshAuctionPlan(true)
  assert(ES.AuctionPanelState.earn ~= nil, "panel sin modo ganar dinero")
  ES.GetProfessionSkill, ES.IsRecipeKnown = realSkill, realKnown
  ES.db.mail = nil
  ES.Earn:Clear()
  ES.AuctionPanelState.profKey = nil
end)
step("colección de recetas", function()
  local realSkill, realKnown = ES.GetProfessionSkill, ES.IsRecipeKnown
  ES.GetProfessionSkill = function(self, line) if line == ES.Data.Leatherworking.skillLine then return 150, 225 end end
  ES.IsRecipeKnown = function(self, id) local r = ES.Data.Leatherworking.recipes[id] return r ~= nil and r.fee ~= nil and (r.train or 1) <= 100 end
  local res = ES.Collection:Build("Leatherworking")
  local parts = {}
  for _, k in ipairs(ES.Collection.SOURCES) do parts[#parts+1] = k .. " " .. res.by[k].known .. "/" .. res.by[k].total end
  log[#log+1] = string.format("     peletería: %d/%d · %s · siguientes %d", res.known, res.total, table.concat(parts, ", "), #res.next)
  assert(res.total > 500 and res.known > 0 and res.by.drop.total > 0, "colección incompleta")
  -- Recetas sabidas guardadas para los alters
  assert(ES.db.known[ES:CharKey()].Leatherworking and #ES.db.known[ES:CharKey()].Leatherworking == res.known, "no guarda las sabidas")
  -- Pestaña "Colección de recetas": tarjetas con el progreso y la página de una profesión
  ES:SelectPage("patterns")
  ES:RenderPatterns()
  local pcard
  for _, c in ipairs(ES.patternsPage.cards) do if c.key == "Leatherworking" then pcard = c end end
  log[#log+1] = "     tarjeta colección: " .. tostring(pcard.cost._text) .. " | " .. tostring(pcard.level._text)
  assert(tostring(pcard.level._text):find(res.known .. "|r de " .. res.total), "progreso en la tarjeta")
  pcard._scripts.OnClick(pcard) -- abre la colección de peletería
  local page
  for _, p in ipairs(ES.patternPages) do if p.collectionFrame.profKey == "Leatherworking" then page = p end end
  assert(ES.db.lastPage == "pattern:Leatherworking", "no abrió la colección")
  local cf = page.collectionFrame
  ES.db.collection = nil
  ES:RefreshCollection(cf)
  local function Visible() return cf.shown end -- el simulacro no guarda qué filas se ocultan
  -- Por defecto se ven todas (las que tienes, apagadas con su check)
  assert(Visible() == res.total, "por defecto deberían verse todas: " .. Visible() .. " de " .. res.total)
  log[#log+1] = "     1ª fila: " .. tostring(cf.rows[1].title._text) .. " | " .. tostring(cf.rows[1].sub._text) .. " | " .. tostring(cf.rows[1].level._text)
  log[#log+1] = "     contador: " .. tostring(cf.counter._text) .. " | " .. tostring(cf.counterSub._text)
  -- Mostrar: casillas por estado (aprendidas, puedo aprender ya, me faltan)
  ES.db.collection.hiddenState = { known = true }
  ES:RenderCollection(cf)
  log[#log+1] = string.format("     sin las aprendidas: %d filas · %s", Visible(), tostring(cf.counterSub._text))
  assert(Visible() == res.total - res.known, "ocultar aprendidas")
  ES.db.collection.hiddenState = { known = true, missing = true }
  ES:RenderCollection(cf)
  log[#log+1] = string.format("     solo puedo aprender ya: %d filas", Visible())
  ES.db.collection.hiddenState = {}
  ES:RenderCollection(cf)
  assert(Visible() == res.total, "volver a todas")
  -- Filtros guardados por la versión anterior: se empieza de cero
  ES.db.collection = { show = "all", hidden = { trainer = true, vendor = true } }
  ES:RenderCollection(cf)
  assert(Visible() == res.total, "los filtros antiguos deberían reiniciarse")
  -- Ventana de filtros: abrirla, pulsar cada casilla (fuentes, orden) y restablecer
  cf.filterButton._scripts.OnClick(cf.filterButton)
  for _, cb in ipairs(cf.filterPopup.checks) do cb._scripts.OnClick(cb) end
  log[#log+1] = "     botón con filtros activos: " .. tostring(cf.filterButton._text)
  for _, o in ipairs({ "level", "scroll", "profit", "cheapest" }) do ES.db.collection.sort = o ES:RenderCollection(cf) end
  ES:RenderCollection(cf)
  -- Restablecer
  ES.db.collection = nil
  ES:RenderCollection(cf)
  assert(cf.filterButton._text == "Filtros", "tras restablecer no quedan filtros: " .. tostring(cf.filterButton._text))
  -- Lista virtual: solo se crean las filas que caben a la vista
  log[#log+1] = "     filas creadas para " .. cf.shown .. " recetas: " .. #cf.rows
  assert(#cf.rows < 30, "la lista no es virtual: " .. #cf.rows .. " filas")
  -- Pulsar una fila elige su receta
  local row1 = cf.rows[2]
  row1._scripts.OnClick(row1)
  assert(cf.selected == row1.entry, "no eligió la receta pulsada")
  -- Una receta de botín: su ficha a la derecha
  local drop
  for _, e in ipairs(cf.data.entries) do if e.main == "drop" then drop = e break end end
  ES:SelectCollectionEntry(cf, drop)
  assert(cf.selected == drop, "no eligió la receta de botín")
  local d = cf.detail
  local texts = {}
  for i = 1, d.used do texts[#texts + 1] = tostring(d.lines[i].left._text) .. " = " .. tostring(d.lines[i].right._text) end
  log[#log+1] = "     ficha: " .. tostring(d.title._text) .. " | " .. tostring(d.sub._text)
  for i = 1, math.min(8, #texts) do log[#log+1] = "       " .. texts[i] end
  assert(d.used >= 4, "ficha casi vacía")
  -- Las líneas con clic (marcar en el mapa) no fallan
  for i = 1, d.used do local line = d.lines[i] if line.onClick then line._scripts.OnClick(line) end end
  -- Barra como la del libro de profesiones: "Peletería 25/541"
  assert(tostring(cf.counter._text) == "Peletería " .. res.known .. "/" .. res.total, "texto de la barra: " .. tostring(cf.counter._text))
  -- La rueda del ratón mueve la lista (sin barra de desplazamiento)
  cf.scroll._scripts.OnMouseWheel(cf.scroll, -1)
  -- El estandarte de facción del otro bando no está (personaje de la Alianza)
  ES:DropOtherFactionRecipes() -- en el juego, al entrar (PLAYER_LOGIN)
  local banners = 0
  for _, r in pairs(ES.Data.Tailoring.recipes) do if r.name == "Faction Banner" then banners = banners + 1 end end
  assert(banners == 1, "estandartes de facción: " .. banners)
  -- "Volver" lleva a la pestaña de la colección
  ES.mainFrameForTests = ES:GetMainFrame()
  ES.mainFrameForTests.back._scripts.OnClick(ES.mainFrameForTests.back)
  assert(ES.db.lastPage == "patterns", "Volver debería ir a la colección")
  ES:SelectPage("home")
  -- Aviso de pergaminos de botín en la AH
  local scan = ES.db.scans[ES:RealmKey()]
  ES.Collection:AlertScan(scan)
  ES.GetProfessionSkill, ES.IsRecipeKnown = realSkill, realKnown
end)
step("escanear con barrera de 15 min", function()
  local f = ES:GetMainFrame()
  ES.ahOpen = true
  ES.db.lastFullScan = nil
  ES:RefreshScanButtons()
  assert(f.scanButton._text == "Escanear", "sin escaneos previos se puede escanear")
  -- Escaneo de verdad con la API clásica: arranca y el botón pasa a %
  local started
  GetFramesRegisteredForEvent = function() end
  QueryAuctionItems = function() started = true end
  CanSendAuctionQuery = function() return true, true end
  GetNumAuctionItems = function() return 0 end
  local pending
  C_Timer.After = function(_, fn) pending = fn end
  local realGetTime = GetTime
  local clock = 0
  GetTime = function() return clock end
  ES.Scanner:Start()
  assert(started and ES.Scanner:IsBusy(), "no arrancó el escaneo")
  log[#log+1] = "     botón al pulsar: " .. tostring(f.scanButton._text)
  assert(f.scanButton._text == "5%", "el botón debería mostrar el progreso")
  clock = 12 pending()
  log[#log+1] = "     esperando al servidor: " .. tostring(f.scanButton._text)
  assert(f.scanButton._text == "5% · 12s", "el botón debería mostrar la espera: " .. tostring(f.scanButton._text))
  ES.Scanner:Abort()
  -- Tras pedir, la barrera corre desde la petición: cuenta atrás y no se vuelve a pedir
  log[#log+1] = "     tras el escaneo: " .. tostring(f.scanButton._text)
  assert(f.scanButton._text == "15:00", "cuenta atrás de 15 min: " .. tostring(f.scanButton._text))
  -- Junto al botón se avisa de que el último intento no acabó
  log[#log+1] = "     tras cancelar: " .. tostring(f.lastScan._text)
  assert(tostring(f.lastScan._text):find("Cancelado"), "debería avisar del escaneo cancelado: " .. tostring(f.lastScan._text))
  ES.db.lastScanFail = nil
  started = false
  ES.Scanner:Start()
  assert(not started and not ES.Scanner:IsBusy(), "no debe pedirse otra vez antes de 15 min")
  -- El servidor no responde: se abandona a los 60 s con la cuenta atrás ya corriendo
  ES.db.lastFullScan = { [ES:CharKey()] = NOW - 16 * 60 }
  ES:RefreshScanButtons()
  assert(f.scanButton._text == "Escanear", "pasados 15 min se puede escanear")
  ES.Scanner:Start()
  assert(ES.Scanner:IsBusy(), "debería pedir")
  clock = clock + 61 pending()
  assert(not ES.Scanner:IsBusy(), "debería abandonar sin respuesta")
  assert(f.scanButton._text:match("^1[45]:%d%d$"), "cuenta atrás tras no responder: " .. tostring(f.scanButton._text))
  -- Si el cliente dice que no se puede, no se pide
  ES.db.lastFullScan = nil
  CanSendAuctionQuery = function() return true, false end
  started = false
  ES.Scanner:Start()
  assert(not started and not ES.Scanner:IsBusy(), "con canGetAll = false no debe pedirse")
  GetTime = realGetTime
  C_Timer.After = function() end
  ES.db.lastFullScan, ES.countdownTicking = nil, false
  QueryAuctionItems, CanSendAuctionQuery, GetNumAuctionItems = nil, nil, nil
  ES.ahOpen = false
  ES:RefreshScanButtons()
end)
step("instructores por rango (Forever)", function()
  -- Georgio Bolero (1346) solo enseña Experto: nunca para Oficial (75-150)
  local function Has(list, id) for _, v in ipairs(list) do if v == id then return true end end end
  local journeyman = ES.Waypoints.Trainers("Tailoring", 150)
  assert(not Has(journeyman, 1346), "Georgio Bolero no enseña Oficial")
  assert(Has(journeyman, 5567), "Sellandus enseña Oficial en Ventormenta")
  assert(Has(ES.Waypoints.Trainers("Tailoring", 225), 1346), "Georgio Bolero enseña Experto")
  assert(Has(ES.Waypoints.Trainers("Tailoring", 60), 1300), "Lawrence Schneider enseña Aprendiz y sus recetas")
  assert(Has(ES.Waypoints.Trainers("Tailoring", 300), 11052), "Timothy Worthington enseña Artesano")
end)
step("sin variables globales sueltas", function()
  assert(#LEAKS == 0, "globales: " .. table.concat(LEAKS, ", "))
end)
step("idioma inglés", function()
  -- Todas las claves L[...] del código tienen traducción al inglés
  local missing = {}
  for _, src in ipairs(SOURCES) do
    for key in src:gmatch('L%["(.-[^\\])"%]') do
      key = key:gsub('\\"', '"'):gsub("\\n", "\n")
      if key ~= "texto" and not ES.Locales.en[key] then missing[#missing + 1] = key end
    end
  end
  assert(#missing == 0, #missing .. " sin traducir: " .. table.concat(missing, " | "))
  -- Y ninguna traducción sobra (texto que ya no está en el código). Se busca en
  -- todo menos en las propias traducciones, donde siempre aparecería
  local code = {}
  for i, src in ipairs(SOURCES) do
    if not SOURCE_NAMES[i]:find("^Locales") then code[#code + 1] = src end
  end
  local all = table.concat(code, "\n")
  local unused = {}
  for key in pairs(ES.Locales.en) do
    local escaped = key:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n")
    if not all:find('"' .. escaped .. '"', 1, true) then unused[#unused + 1] = key end
  end
  assert(#unused == 0, #unused .. " traducciones sin uso: " .. table.concat(unused, " | "))
  ES.lang = "en"
  ES.ApplyLocalization()
  assert(ES.L["Ruta"] == "Route" and ES.Num(2.5) == "2.5", "inglés no aplicado")
  assert(ES:ProfLabel("Leatherworking") == "Leatherworking", "profesión: " .. ES:ProfLabel("Leatherworking"))
  ES.lang = "es"
  assert(ES.Num(2.5) == "2,5" and ES.L["Ruta"] == "Ruta", "español")
end)
step("recetas de reputación", function()
  -- Heavy Timbermaw Belt pide Amistoso con Fauces de Madera (576)
  local r, n = nil, 0
  for id, rc in pairs(ES.Data.Leatherworking.recipes) do
    if rc.rep then n = n + 1 end
    if rc.scroll == 19202 then r = rc; rc.id = id end
  end
  assert(r and r.rep and r.rep[1] == 576 and r.rep[2] == 5, "falta rep en Heavy Timbermaw Belt")
  local o = { sourcedScrolls = true }
  assert(ES.Planner.LearnSkill(r, o) == nil, "sin reputación no debería estar disponible")
  local _, src = ES.Planner.LearnCost({ opts = o, prices = {} }, r)
  assert(src == "rep", "LearnCost debería decir rep, dice " .. tostring(src))
  local old = GetFactionInfoByID
  GetFactionInfoByID = function(id) if id == 576 then return "Timbermaw Hold", "", 5 end return "x", "", 4 end
  ES.repStamp = ES:RepStamp()
  local _, src2 = ES.Planner.LearnCost({ opts = o, prices = {} }, r)
  assert(src2 ~= "rep", "con Amistoso debería poder aprenderse")
  log[#log+1] = string.format("     %d recetas de peletería con reputación; con Amistoso: %s", n, tostring(src2))
  GetFactionInfoByID = old
  ES.repStamp = ES:RepStamp()
end)
step("colección de las 8 profesiones", function()
  assert(#ES.patternPages == #ES.PROFESSIONS, "páginas: " .. #ES.patternPages)
  for _, page in ipairs(ES.patternPages) do
    local cf = page.collectionFrame
    ES:RefreshCollection(cf)
    cf.search:SetText("a")
    cf.search._scripts.OnTextChanged(cf.search)
    cf.search:SetText("")
    cf.search._scripts.OnTextChanged(cf.search)
    log[#log+1] = string.format("     %s: %d recetas", cf.profKey, cf.data.total)
  end
end)
step("portada: tarjetas de profesiones", function()
  -- El personaje tiene Peletería a 120 (tope 150)
  GetProfessions = function() return 1, nil end
  GetProfessionInfo = function(i) return "Leatherworking", nil, 120, 150, 0, 0, 165 end
  -- Atlas del libro de profesiones: existen todos menos el de Alquimia (usa el icono)
  local atlasAsked = {}
  C_Texture = { GetAtlasInfo = function(name)
    atlasAsked[#atlasAsked + 1] = name
    if name:find("^Profession%-overview") and not name:find("Alchemy") then
      return { file = 4071, leftTexCoord = 0.1, rightTexCoord = 0.6, topTexCoord = 0.2, bottomTexCoord = 0.4 }
    end
  end }
  -- Con una profesión aprendida, las demás van plegadas tras "Otras profesiones (7)"
  ES.db.othersCollapsed = nil
  ES:SelectPage("home")
  local header = ES.homePage.othersHeader
  log[#log+1] = "     plegadas: " .. tostring(header and header.text._text)
  assert(header and tostring(header.text._text):find(tostring(#ES.PROFESSIONS - 1)), "falta la fila de otras profesiones")
  assert(#atlasAsked == 1, "plegadas no deberían pintarse: " .. #atlasAsked)
  -- Al pulsarla se despliegan (y se recuerda)
  atlasAsked = {}
  header._scripts.OnClick(header)
  assert(ES.db.othersCollapsed == false, "no recuerda que están desplegadas")
  log[#log+1] = "     atlas pedidos: " .. table.concat(atlasAsked, ", ")
  -- Uno de fondo por tarjeta + el dibujo de las secundarias (cocina, primeros auxilios y pesca)
  assert(#atlasAsked == ES.homePage.shownCards + 3, "atlas pedidos: " .. #atlasAsked)
  -- Escalar: arrastrar la esquina al 150% del tamaño amplía la ventana x1,5 en
  -- ancho y alto (en el simulacro: marco de 100x100 en (100,100), escala de UI 100)
  local f = CraftersJournalMainFrame
  local savedCursor = GetCursorPosition
  GetCursorPosition = function() return 25000, -5000 end
  f.resize._scripts.OnMouseDown(f.resize, "LeftButton")
  f.resize._scripts.OnUpdate(f.resize)
  f.resize._scripts.OnMouseUp(f.resize)
  assert(math.abs(f:GetScale() - 1.5) < 0.001, "escala " .. tostring(f:GetScale()))
  assert(ES.db.frameScale == 1.5, "no guardó la escala")
  GetCursorPosition = function() return 99999, -99999 end -- más allá del máximo
  f.resize._scripts.OnMouseDown(f.resize, "LeftButton")
  f.resize._scripts.OnUpdate(f.resize)
  assert(f:GetScale() <= 1.8, "superó la escala máxima")
  f.resize._scripts.OnMouseUp(f.resize)
  f.resize._scripts.OnDoubleClick(f.resize)
  assert(f:GetScale() == 1 and ES.db.frameScale == 1, "doble clic no volvió a escala 1")
  GetCursorPosition = savedCursor
  C_Texture = nil
  local cards = {}
  for _, c in ipairs(ES.homePage.cards) do if c._shown ~= false then cards[#cards + 1] = c end end
  -- Solo las 8 profesiones: Ganar dinero, la colección y Subastas son pestañas
  assert(ES.homePage.shownCards == #ES.PROFESSIONS, "tarjetas: " .. tostring(ES.homePage.shownCards))
  local first = ES.homePage.cards[1]
  log[#log+1] = "     1ª: " .. tostring(first.name._text) .. " | " .. tostring(first.cost._text) .. " | " .. tostring(first.level._text) .. " | " .. tostring(first.note._text)
  assert(first.key == "Leatherworking", "la profesión del personaje debería ir primera, va " .. tostring(first.key))
  assert(tostring(first.level._text):find("120"), "nivel no mostrado")
  -- Pestañas laterales: cada una abre su página y queda marcada
  local mf = ES:GetMainFrame()
  assert(#mf.tabs == 4, "pestañas: " .. #mf.tabs)
  for _, tab in ipairs(mf.tabs) do
    tab._scripts.OnClick(tab)
    assert(ES.db.lastPage == tab.key, "la pestaña " .. tab.key .. " no abre su página")
    tab._scripts.OnEnter(tab)
  end
  ES:SelectPage("Leatherworking") -- una profesión pertenece a la pestaña de subir
  assert(mf.backTarget == "home", "Volver de una profesión")
  ES:SelectPage("home")
  for i, c in ipairs(ES.homePage.cards) do
    c._scripts.OnEnter(c) c._scripts.OnLeave(c)
    log[#log+1] = string.format("     %d. %s | %s | %s", i, tostring(c.name._text), tostring(c.cost._text):gsub("|T[^|]+|t", ""), tostring(c.level._text))
  end
  -- El coste de la tarjeta es el mismo que el del detalle (de 120 a 225)
  local page
  for _, p in ipairs(ES.professionPages) do if p.profKey == "Leatherworking" then page = p end end
  page._scripts.OnShow(page) -- detecta el nivel 120 del personaje
  assert(page.from == 120, "no detectó el nivel del personaje")
  page.toBox._text = "225"
  ES:CalculatePlan(page)
  local plan = ES.Planner:Plan(ES.Data.Leatherworking, ES:PlanOptions("Leatherworking", 120, 225, 150))
  assert(math.abs(page.plan.net - plan.net) < 1, "coste distinto en portada y detalle")
  -- Con otro objetivo guardado (p. ej. 150) la tarjeta usa ese mismo objetivo
  page.toBox._text = "150"
  ES:CalculatePlan(page)
  ES:SelectPage("home")
  local card
  for _, c in ipairs(ES.homePage.cards) do if c.key == "Leatherworking" then card = c end end
  assert(tostring(card.level._text):find("/ 150"), "la tarjeta no muestra el objetivo: " .. tostring(card.level._text))
  local detailCost = page.plan and page.plan.net or 0
  log[#log+1] = "     objetivo 150: tarjeta " .. tostring(card.cost._text):gsub("|T[^|]+|t", "") .. " | detalle " .. tostring(detailCost)
  local cardPlan = ES.Planner:Plan(ES.Data.Leatherworking, ES:PlanOptions("Leatherworking", 120, ES:ProfessionTarget("Leatherworking"), 150))
  assert(math.abs(cardPlan.net - detailCost) < 1, "tarjeta y detalle no coinciden con objetivo 150")
  page.toBox._text = "225"
  ES:CalculatePlan(page)
  -- Clic en un paso: abre la receta en la profesión; "Fabricar N" fabrica (C_TradeSkillUI)
  local opened, crafted
  C_TradeSkillUI = { OpenRecipe = function(id) opened = id end, CraftRecipe = function(id, n) crafted = { id, n } end }
  local savedKnown = ES.IsRecipeKnown
  ES.IsRecipeKnown = function() return true end
  ES:RenderPlan(page)
  local craftLine
  for _, l in ipairs(page.lines) do if l.craftCount then craftLine = l break end end
  assert(craftLine, "con la opción por defecto, el clic en un paso debería fabricar")
  craftLine.onClick() -- un solo clic: abre la receta y fabrica lo que falta
  assert(opened == page.plan.steps[1].id, "el clic no abrió la receta del paso")
  assert(crafted and crafted[1] == page.plan.steps[1].id and crafted[2] == page.plan.steps[1].crafts, "el clic no fabricó lo del paso")
  log[#log+1] = "     fabricar: " .. tostring(craftLine.title)
  -- Opción desactivada (Opciones > AddOns): el clic solo abre la receta
  local op = ES.optionsPanel
  op._scripts.OnShow(op)
  op.craftCheck:SetChecked(false)
  op.craftCheck._scripts.OnClick(op.craftCheck)
  assert(ES.db.autoCraft == false, "la opción no se guardó")
  ES:RenderPlan(page)
  crafted, opened = nil, nil
  for _, l in ipairs(page.lines) do assert(not l.craftCount, "con la opción desactivada no debería fabricar") end
  for _, l in ipairs(page.lines) do if l.onClick and l.item then l.onClick() break end end
  assert(opened and not crafted, "con la opción desactivada el clic solo abre la receta")
  ES.db.autoCraft = nil
  ES.IsRecipeKnown, C_TradeSkillUI = savedKnown, nil
  ES:RenderPlan(page)
  -- ✕ en un paso: la receta sale de la ruta y una fila permite recuperarla
  local firstStep = page.plan.steps[1].id
  local skipRow
  for _, row in ipairs(page.rows) do if row.onSkip and row._shown ~= false then skipRow = row break end end
  assert(skipRow, "los pasos de la ruta deberían tener la ✕")
  skipRow.skip._scripts.OnEnter(skipRow.skip)
  skipRow.skip._scripts.OnClick(skipRow.skip)
  assert(ES.db.prof.Leatherworking.excluded and next(ES.db.prof.Leatherworking.excluded), "no se quitó la receta")
  for _, st in ipairs(page.plan.steps) do
    assert(not ES.db.prof.Leatherworking.excluded[st.id], "la receta quitada sigue en la ruta: " .. st.recipe.name)
  end
  local restore
  for _, l in ipairs(page.lines) do if l.title and l.title:find("Recetas quitadas") then restore = l end end
  assert(restore, "falta la fila para recuperar las recetas quitadas")
  log[#log+1] = "     quitar receta: " .. restore.title .. " · primer paso ahora " .. page.plan.steps[1].recipe.name
  restore.onClick()
  assert(not ES.db.prof.Leatherworking.excluded and page.plan.steps[1].id == firstStep, "no se recuperó la ruta")
  -- Lista de la compra: cuántos tienes y cuántos faltan; se actualiza al cambiar las bolsas
  local bags = 0
  GetItemCount = function() return bags end
  page.view = "shop"
  ES:RenderPlan(page)
  local buyLine
  for _, l in ipairs(page.lines) do if l.sub and l.sub:find("Tienes") then buyLine = l break end end
  assert(buyLine, "la lista de la compra debería decir cuántos tienes")
  assert(buyLine.sub:find("faltan"), "sin nada en las bolsas deberían faltar: " .. buyLine.sub)
  bags = 100000
  ES:RefreshAfterBags()
  for _, l in ipairs(page.lines) do
    if l.item == buyLine.item and l.sub then
      assert(not l.sub:find("faltan"), "con todo en las bolsas no debería faltar nada: " .. l.sub)
    end
  end
  log[#log+1] = "     lista de la compra: " .. buyLine.title
  -- Clic en un material de la AH: sin la AH abierta marca el subastador; con ella, lo busca
  local savedSearch, savedOpen = ES.SearchAuction, ES.IsAuctionHouseOpen
  ES.IsAuctionHouseOpen = function() return false end
  ES:RenderPlan(page)
  local ahLine
  for _, l in ipairs(page.lines) do if l.go and not l.onClick and l.sub and l.sub:find("AH ·") then ahLine = l break end end
  assert(ahLine, "sin la AH abierta, el clic en un material de la AH debería marcar el subastador")
  local searched
  ES.SearchAuction = function(_, id) searched = id end
  ES.IsAuctionHouseOpen = function() return true end
  ES:RenderPlan(page)
  for _, l in ipairs(page.lines) do if l.item == ahLine.item and l.onClick then l.onClick() end end
  assert(searched == ahLine.item, "con la AH abierta, el clic debería buscar el objeto")
  ES.SearchAuction, ES.IsAuctionHouseOpen = savedSearch, savedOpen
  -- AH moderna: abre la compra del material con la cantidad que falta ya puesta
  local selected, qtySet
  local savedAHF, savedCAH = AuctionHouseFrame, C_AuctionHouse
  AuctionHouseFrame = { SelectBrowseResult = function(_, r) selected = r.itemKey end,
    CommoditiesBuyFrame = { IsShown = function() return true end,
      BuyDisplay = { SetQuantitySelected = function(_, q) qtySet = q end } } }
  C_AuctionHouse = { MakeItemKey = function(id) return { itemID = id } end }
  ES:OpenAuctionBuy(ahLine.item, 7)
  assert(selected and selected.itemID == ahLine.item and qtySet == 7, "no abrió la compra con la cantidad puesta")
  AuctionHouseFrame, C_AuctionHouse = savedAHF, savedCAH
  -- Empezar ruta: comprar (cambian las bolsas) no cambia la ruta ni su coste
  page.view = "route"
  bags = 0
  ES:CalculatePlan(page)
  local before = page.plan
  page.routeButton._scripts.OnEnter(page.routeButton)
  page.routeButton._scripts.OnClick(page.routeButton)
  local lock = ES.db.prof.Leatherworking.lock
  assert(lock and lock.choice and lock.to == 225, "no se fijó la ruta")
  local net = page.plan.net
  local savedBags = ES.db.prof.Leatherworking.useBags
  ES.db.prof.Leatherworking.useBags = true
  bags = 500
  ES:ClearHomeCache()
  ES:RefreshAfterBags()
  ES:CalculatePlan(page)
  assert(page.plan == before and page.plan.net == net, "la ruta fijada cambió al comprar")
  assert(tostring(page.status._text):find("Ruta en curso"), "falta el aviso de ruta en curso: " .. tostring(page.status._text))
  -- Tras recargar se rehace igual: mismas recetas y mismo coste
  ES.lockedPlans = {}
  local rebuilt = ES:LockedPlan("Leatherworking")
  assert(#rebuilt.steps == #before.steps and rebuilt.steps[1].id == before.steps[1].id, "la ruta fijada cambió al recargar")
  assert(math.abs(rebuilt.net - net) < 1, "el coste de la ruta fijada cambió al recargar")
  log[#log+1] = string.format("     ruta fijada: %d pasos, %s", #rebuilt.steps, tostring(page.routeButton._text))
  -- Escaneo nuevo con la ruta fijada: ni la ruta ni sus totales cambian, aunque se
  -- rehaga (recarga); "Actualizar precios" la recalcula con el escaneo nuevo
  local scanKey = ES:RealmKey()
  local oldScan = ES.db.scans[scanKey]
  local newItems = {}
  for id, e in pairs(oldScan.items) do
    local c = {}
    for k, v in pairs(e) do c[k] = v end
    if c.minUnit then c.minUnit = c.minUnit * 3 end
    if c.ladder then
      c.ladder = {}
      for i, v in ipairs(e.ladder) do c.ladder[i] = (i % 2 == 1) and v * 3 or v end
    end
    newItems[id] = c
  end
  ES.db.scans[scanKey] = { time = oldScan.time + 3600, total = oldScan.total, unique = oldScan.unique, items = newItems }
  ES.lockedPlans = {}
  local frozen = ES:LockedPlan("Leatherworking")
  assert(math.abs(frozen.net - net) < 1, string.format("la ruta fijada cambió de coste con el escaneo nuevo: %d -> %d", net, frozen.net))
  ES:RenderPlan(page)
  assert(page.pricesButton._shown ~= false, "falta Actualizar precios con un escaneo nuevo")
  page.pricesButton._scripts.OnEnter(page.pricesButton)
  page.pricesButton._scripts.OnClick(page.pricesButton)
  local updated = ES:LockedPlan("Leatherworking")
  assert(updated.net > net + 1 and updated.steps[1].id == frozen.steps[1].id, "Actualizar precios no usó el escaneo nuevo con la misma ruta")
  log[#log+1] = string.format("     precios: fijada %d, actualizada %d (mismas recetas)", frozen.net, updated.net)
  ES.db.scans[scanKey] = oldScan
  ES:RefreshRoutePrices("Leatherworking")
  -- Subes de nivel fabricando: el paso actual se resalta y dice cuántas faltan
  local savedDetect = ES.DetectSkill
  local s1 = rebuilt.steps[1]
  local newLevel = s1.from + math.max(1, math.floor((s1.to - s1.from) / 2))
  ES.DetectSkill = function(_, p) p.from = newLevel end
  page.view = "route"
  ES:RefreshAfterSkill()
  local cur
  for _, l in ipairs(page.lines) do if l.current then cur = l end end
  assert(cur and cur.sub:find("faltan"), "falta el paso actual con lo que queda: " .. tostring(cur and cur.sub))
  local curRow
  for _, row in ipairs(page.rows) do if row._shown ~= false and row.title._text == cur.title then curRow = row end end
  log[#log+1] = "     paso actual: " .. tostring(cur.level) .. " · " .. tostring(cur.sub)
  ES.DetectSkill = savedDetect
  ES:DetectSkill(page)
  -- Gasto real: comprar un material de la ruta al vendedor y vender algo fabricado
  local buyItem, sellItem = rebuilt.shopping[1].itemID, nil
  for _, st in ipairs(rebuilt.steps) do if st.sale then sellItem = st.sale.itemID break end end
  local counts = { [buyItem] = 0, [sellItem] = 10 }
  GetItemCount = function(id) return counts[id] or 0 end
  GetMerchantNumItems = function() return 1 end
  GetMerchantItemID = function() return buyItem end
  GetMerchantItemInfo = function() return "x", nil, 300, 3 end -- 3 por 300: 100 cada uno
  ES.Ledger:SetWhere("merchant")
  ES.Ledger.Snapshot()
  counts[buyItem], counts[sellItem] = 6, 7
  ES.Ledger.Process()
  local real = ES.Ledger:Summary("Leatherworking")
  assert(real.buy == 600, "compra al vendedor: " .. tostring(real.buy))
  assert(real.sold[sellItem] == 3 and real.sell == 3 * (ES:VendorSellPrice(sellItem) or 0), "venta al vendedor: " .. tostring(real.sell))
  ES.Ledger:SetWhere(nil)
  ES:RenderPlan(page)
  assert(tostring(page.real.materials._text):find("Real"), "falta la fila Real en la franja")
  page.view = "profit"
  ES:RenderPlan(page)
  local soldLine
  for _, l in ipairs(page.lines) do if l.item == sellItem and l.sub and l.sub:find("vendidos 3") then soldLine = l end end
  assert(soldLine, "la vista Profit debería decir cuántos llevas vendidos")
  assert(soldLine.go, "sin vendedor ni AH abiertos, el clic marca dónde venderlo")
  log[#log+1] = string.format("     gasto real: compras %d, ventas %d · %s", real.buy, real.sell, page.real.total._text)
  -- Anunciar en la AH: a platas enteras (la AH de Forever no admite cobres)
  assert(ES.Ledger.PostPrice(2070) == 2000 and ES.Ledger.PostPrice(50) == 100, "precio de anuncio en platas enteras")
  -- Con la AH abierta y nada en las bolsas, el clic avisa en vez de marcar el subastador
  local savedOpen = ES.IsAuctionHouseOpen
  ES.IsAuctionHouseOpen = function() return true end
  ES:RenderPlan(page)
  for _, l in ipairs(page.lines) do
    if l.sub and l.sub:find("no llevas ninguno") then
      assert(l.onClick and not l.go, "con la AH abierta y sin el objeto, el clic no debería marcar el subastador")
      l.onClick()
    end
  end
  ES.IsAuctionHouseOpen = savedOpen
  -- Vendedor abierto con la ruta empezada: ventana al lado con lo que falta y "Comprar todo"
  local bought = {}
  MerchantFrame = CreateFrame("Frame")
  GetMoney = function() return 10000000 end
  C_MerchantFrame = { GetItemInfo = function() return { price = 300, stackCount = 3, numAvailable = -1, isPurchasable = true } end }
  BuyMerchantItem = function(i, n) bought[#bought + 1] = n end
  counts[buyItem] = 0
  ES.VendorShop:Refresh()
  local vp = CraftersJournalVendorPanel
  assert(vp and vp.rows[1].entry and vp.rows[1].entry.itemID == buyItem, "la ventana del vendedor no lista lo que falta")
  assert(vp.rows[1].entry.qty % 3 == 0, "se compra en los lotes del vendedor: " .. vp.rows[1].entry.qty)
  vp.rows[1]._scripts.OnEnter(vp.rows[1])
  vp.buyAll._scripts.OnClick(vp.buyAll)
  assert(#bought > 0 and bought[1] > 0, "Comprar todo no compró nada")
  log[#log+1] = string.format("     vendedor: %s · primera compra de %d", tostring(vp.buyAll._text), bought[1])
  ES.VendorShop.queue, ES.VendorShop.pumping = {}, nil
  MerchantFrame, C_MerchantFrame, BuyMerchantItem, GetMoney = nil, nil, nil, nil
  page.view = "route"
  GetMerchantNumItems, GetMerchantItemID, GetMerchantItemInfo = nil, nil, nil
  -- Portada: la tarjeta de la profesión con la ruta en curso se distingue
  ES:SelectPage("home")
  ES:RenderHome()
  local activeCard
  for _, c in ipairs(ES.homePage.cards) do if c.key == "Leatherworking" then activeCard = c end end
  assert(activeCard and activeCard.active and tostring(activeCard.note._text):find("Ruta en curso"),
    "la tarjeta no indica la ruta en curso: " .. tostring(activeCard and activeCard.note._text))
  activeCard._scripts.OnEnter(activeCard)
  activeCard._scripts.OnLeave(activeCard)
  log[#log+1] = "     portada: " .. tostring(activeCard.note._text)
  ES:SelectPage("Leatherworking")
  -- Recalcular ruta la libera
  page.routeButton._scripts.OnClick(page.routeButton)
  assert(not ES.db.prof.Leatherworking.lock, "Recalcular ruta no la liberó")
  ES.db.prof.Leatherworking.useBags = savedBags
  GetItemCount = nil
  ES:ClearHomeCache()
  ES:CalculatePlan(page)
  ES:SelectPage("home")
  -- Pulsar la tarjeta abre la profesión; Volver regresa
  first._scripts.OnClick(first)
  assert(ES.db.lastPage == "Leatherworking", "no abrió la profesión")
  CraftersJournalMainFrame.back._scripts.OnClick(CraftersJournalMainFrame.back)
  assert(ES.db.lastPage == "home", "Volver no regresó a la portada")
  GetProfessions, GetProfessionInfo = nil, nil
end)
step("cabecera: buscador e idioma", function()
  local f = CraftersJournalMainFrame
  assert(f.title._text == "Crafter's Journal", "título: " .. tostring(f.title._text))
  local box, list = f.globalSearch, f.searchResults
  box._text = "pelet"
  box._scripts.OnTextChanged(box)
  assert(list.results[1] and list.results[1].kind == "prof" and list.results[1].profKey == "Leatherworking", "no encontró Peletería")
  box._text = "armor kit"
  box._scripts.OnTextChanged(box)
  local recipe
  for _, r in ipairs(list.results) do if r.kind == "recipe" and r.profKey == "Leatherworking" then recipe = r break end end
  assert(recipe, "no encontró recetas de armor kit")
  log[#log+1] = string.format("     'armor kit': %d resultados, 1º %s (%s)", #list.results, list.results[1].text, list.results[1].profKey)
  -- Elegir una receta: abre su ficha en la Colección, con la lista filtrada por ella
  local chosen = list.rows[1].result
  list.rows[1]._scripts.OnClick(list.rows[1])
  assert(ES.db.lastPage == "pattern:" .. chosen.profKey, "no abrió la colección: " .. tostring(ES.db.lastPage))
  local cf = f.pages["pattern:" .. chosen.profKey].collectionFrame
  assert(cf.search._text == chosen.recipe.name, "no filtró por la receta")
  assert(cf.selectedID == chosen.id, "no eligió la receta")
  -- Sin resultados: la fila no hace nada al pulsarla
  box._text = "zzzzqq"
  box._scripts.OnTextChanged(box)
  list.rows[1]._scripts.OnClick(list.rows[1])
  -- Botón Escanear: durante el escaneo muestra el % de progreso y al acabar vuelve a "Escanear"
  local savedBusy = ES.Scanner.IsBusy
  ES.Scanner.IsBusy = function() return true end
  ES.Scanner.progress = 0.05
  ES:OnScanProgress()
  assert(f.scanButton._text == "5%", "progreso inicial: " .. tostring(f.scanButton._text))
  ES.Scanner.progress = 0.537
  ES:OnScanProgress()
  log[#log+1] = "     botón durante el escaneo: " .. tostring(f.scanButton._text)
  assert(f.scanButton._text == "53%", "progreso: " .. tostring(f.scanButton._text))
  ES.Scanner.IsBusy = savedBusy
  ES:RefreshScanButtons()
  assert(f.scanButton._text == "Escanear", "al acabar el botón vuelve a decir Escanear")
  -- "Último escaneo: hace N min" junto al botón (sin intentos cancelados de pasos anteriores)
  ES.db.lastScanFail = nil
  ES:UpdateLastScan()
  log[#log+1] = "     junto al botón: " .. tostring(f.lastScan._text)
  assert(tostring(f.lastScan._text):find("Último escaneo") or f.lastScan._text == "Sin escanear", "último escaneo")
  -- Idioma: desplegable con Español
  f.languageButton._scripts.OnClick(f.languageButton)
  f.languageButton._scripts.OnEnter(f.languageButton)
  -- Informar de un error: ventana con el enlace del Discord listo para copiar
  assert(f.reportButton, "falta el botón Informar")
  f.reportButton._scripts.OnEnter(f.reportButton)
  f.reportButton._scripts.OnClick(f.reportButton)
  local d = CraftersJournalReportDialog
  assert(d, "no se creó la ventana de informar")
  d._scripts.OnShow(d)
  assert(d.box._text == ES.DISCORD_URL, "el enlace del Discord: " .. tostring(d.box._text))
  d.box._scripts.OnTextChanged(d.box, true)
  assert(d.box._text == ES.DISCORD_URL, "el enlace no se puede editar")
  log[#log+1] = "     informar: " .. tostring(d.title._text) .. " · " .. d.box._text
  d.ok._scripts.OnClick(d.ok)
  ES:SelectPage("home")
end)
step("ir al instructor o vendedor más cercano", function()
  local page
  for _, p in ipairs(ES.professionPages) do if p.profKey == "Leatherworking" then page = p end end
  page.from = 1
  page.toBox._text = "75"
  ES:CalculatePlan(page)
  ES:SelectProfessionView(page, "route")
  local trainRow
  for i = 1, #page.lines do
    if (page.lines[i].title or ""):find("^Entrenar ") and page.lines[i].go then trainRow = page.rows[i] break end
  end
  assert(trainRow, "no hay fila de Entrenar con camino")
  -- Sin Questie: solo avisa, no rompe
  PRINTED = {}
  local savedPrint = ES.Print
  ES.Print = function(_, msg) PRINTED[#PRINTED + 1] = msg end
  trainRow._scripts.OnClick(trainRow)
  -- Sin Questie también funciona: los PNJ vienen en Data/Sources.lua
  assert(PRINTED[1] and not PRINTED[1]:find("Instala Questie"), "sin Questie debería funcionar con los datos propios: " .. tostring(PRINTED[1]))
  log[#log+1] = "     sin Questie: " .. tostring(PRINTED[1])
  -- Respaldo con QuestieDB (si faltaran los datos propios): se quitan un momento
  local savedNPCs = ES.Data.NPCs
  ES.Data.NPCs = nil
  ES.Waypoints.ResetCache()
  -- QuestieDB simulado: instructores de Peletería de Aprendiz (en Forever cada rango
  -- tiene los suyos): 11096 Ventormenta, 5811 Orgrimmar, 1466 Forjaz
  local NPCS = {
    [11096] = { "Randal Worth", { [1519] = { { 46, 50 } } }, 1519, "A" },
    [5811] = { "Kamari", { [1637] = { { 80, 40 } } }, 1637, "H" },
    [1466] = { "Gretta Finespindle", { [1537] = { { 40, 20 } } }, 1537, "A" },
  }
  LibQuestieDB = {
    RequireContract = function() return true end,
    Meta = { ItemMeta = { itemKeys = { vendors = 1 } },
             NpcMeta = { npcKeys = { name = 1, spawns = 2, zoneID = 3, friendlyToFaction = 4 } } },
    Item = { GetAll = function(id) return { {} } end },
    Npc = { GetAll = function(id) return NPCS[id] end },
    Support = { Get = function() return { private = {
      areaIdToUiMapId = "return { [1519] = 1453, [1637] = 1454, [1537] = 1455 }",
      subZoneToParentZone = "return {}" } } end },
  }
  local WORLD = { [1453] = { 0, 100, 100 }, [1454] = { 1, 0, 0 }, [1455] = { 0, 5000, 5000 } }
  CreateVector2D = function(x, y) return { x = x, y = y } end
  C_Map = {
    GetWorldPosFromMapPos = function(map, v) local w = WORLD[map] return w[1], { GetXY = function() return w[2], w[3] end } end,
    GetMapInfo = function(map) return { name = "Mapa " .. map } end,
    CanSetUserWaypointOnMap = function() return true end,
    SetUserWaypoint = function(point) WAYPOINT = point end,
    GetBestMapForUnit = function() return 1453 end,
    GetPlayerMapPosition = function() return nil end,
  }
  UiMapPoint = { CreateFromCoordinates = function(map, x, y) return { map = map, x = x, y = y } end }
  C_SuperTrack = { SetSuperTrackedUserWaypoint = function(v) SUPERTRACK = v end }
  UnitPosition = function() return 90, 90, 0, 0 end -- en Ventormenta
  UnitFactionGroup = function() return "Alliance" end
  InCombatLockdown = function() return false end
  trainRow._scripts.OnEnter(trainRow)
  trainRow._scripts.OnClick(trainRow)
  assert(WAYPOINT and WAYPOINT.map == 1453, "no marcó el instructor más cercano: " .. tostring(WAYPOINT and WAYPOINT.map))
  assert(math.abs(WAYPOINT.x - 0.46) < 0.001 and math.abs(WAYPOINT.y - 0.5) < 0.001, "coordenadas mal")
  assert(SUPERTRACK == true, "no puso el punto en seguimiento")
  log[#log+1] = "     clic en '" .. tostring(trainRow.title._text) .. "': " .. tostring(PRINTED[#PRINTED])
  -- La Horda no cuenta para la Alianza aunque esté más cerca
  UnitPosition = function() return 1, 1, 0, 1 end -- otro continente que 1453
  assert(ES.Waypoints.Nearest({ 1385, 3365 }) ~= 3365, "eligió un PNJ de la Horda")
  ES.Data.NPCs = savedNPCs
  -- Con los datos propios: el instructor de Peletería de la Alianza más cercano a Ventormenta
  ES.Waypoints.ResetCache()
  -- Mundo simulado: cada mapa en su sitio; el jugador en Ventormenta (1453)
  C_Map.GetWorldPosFromMapPos = function(map, v) return 0, { GetXY = function() return map * 10 + v.x * 5, v.y * 5 end } end
  UnitPosition = function() return 1453 * 10 + 2.5, 2.5, 0, 0 end
  local near = ES.Waypoints.Nearest(ES.Waypoints.Trainers("Leatherworking", 76))
  local npc = near and ES.Waypoints.NPC(near)
  assert(npc and npc.side ~= "H", "datos propios: eligió " .. tostring(npc and npc.name))
  log[#log+1] = "     datos propios: instructor de Peletería más cercano: " .. tostring(npc and npc.name)
  ES.Print = savedPrint
end)
step("comandos /es", function() SlashCmdList.CRAFTERSJOURNAL("") SlashCmdList.CRAFTERSJOURNAL("cancel") end)
step("rutas repartidas entre fotogramas (sin tirones)", function()
  -- En el juego (con debugprofilestop) las rutas no se calculan al abrir: cada
  -- fotograma hace un trozo de 8 ms y las tarjetas ponen "Calculando la ruta…"
  local frames = {}
  local realAfter = C_Timer.After
  C_Timer.After = function(_, fn) frames[#frames + 1] = fn end
  local ms = 0
  debugprofilestop = function() ms = ms + 0.05 return ms end
  ES:ClearHomeCache()
  ES:SelectPage("home")
  local first = ES.homePage.cards[1]
  log[#log+1] = "     al abrir: " .. tostring(first.cost._text) .. " | " .. tostring(first.note._text)
  assert(tostring(first.note._text):find("Calculando"), "la tarjeta debería poner Calculando: " .. tostring(first.note._text))
  local n = 0
  while #frames > 0 and n < 100000 do
    local fn = table.remove(frames, 1)
    local before = ms
    fn()
    assert(ms - before < 30, "un fotograma ha durado " .. (ms - before) .. " ms simulados")
    n = n + 1
  end
  log[#log+1] = "     fotogramas hasta tener las 8 rutas: " .. n
  assert(n > 8, "no se repartió el cálculo (" .. n .. " fotogramas)")
  first = ES.homePage.cards[1]
  log[#log+1] = "     al acabar: " .. tostring(first.cost._text) .. " | " .. tostring(first.note._text)
  assert(not tostring(first.note._text):find("Calculando"), "sigue calculando tras acabar")
  -- Abrir la profesión con la ruta ya calculada: sin esperar (de la caché)
  frames = {}
  ES:SelectPage(first.key)
  local page = ES.professionPages[1]
  for _, p in ipairs(ES.professionPages) do if p.profKey == first.key then page = p end end
  page._scripts.OnShow(page) -- el simulacro no lanza OnShow al mostrar
  assert(page.plan and not page.calculating, "la página debería usar la ruta de la portada: " .. tostring(page.planKey)
    .. " vs " .. tostring(ES.homePlanCache[first.key] and ES.homePlanCache[first.key].key))
  assert(#frames == 0, "no debería recalcular: " .. #frames)
  debugprofilestop = nil
  C_Timer.After = realAfter
  ES:SelectPage("home")
end)
step("versión publicada: sin las pestañas en desarrollo", function()
  -- En el repositorio es copia de desarrollo; el empaquetador comenta el bloque @debug@
  assert(ES.DEV_BUILD == true and ES.DEV == true, "en desarrollo ES.DEV_BUILD y ES.DEV deberían ser true")
  local src
  for i, n in ipairs(SOURCE_NAMES) do if n == "Core.lua" then src = SOURCES[i] end end
  assert(src:find("%-%-@debug@\nES.DEV_BUILD = true\n%-%-@end%-debug@"), "falta el bloque @debug@ de ES.DEV_BUILD")
  -- Como en la publicada: Ganar dinero, Subastas y la Pesca no se abren
  ES.DEV = false
  for _, key in ipairs({ "money", "ah", "Fishing", "pattern:Fishing" }) do
    ES:SelectPage(key)
    assert(ES.db.lastPage == "home", key .. " no debería abrirse en la versión publicada")
  end
  ES.DEV = true
end)
step("interruptor de desarrollo: vista de jugador", function()
  ES:ShowMainFrame("home")
  local f = ES:GetMainFrame()
  assert(not f.devToggle, "el interruptor ya no va en la cabecera (sale en las capturas)")
  -- Está en Opciones > AddOns > Crafter's Journal
  local panel = ES.optionsPanel
  assert(panel and panel.devCheck, "en la copia de desarrollo el panel de opciones debería tener el interruptor")
  panel._scripts.OnShow(panel)
  assert(not panel.devCheck:GetChecked(), "en modo DEV la casilla debería estar desmarcada")
  log[#log+1] = "     interruptor: " .. tostring(panel.devCheck.label._text)
  panel.devCheck:SetChecked(true)
  panel.devCheck._scripts.OnClick(panel.devCheck)
  -- Vista de jugador: ventana nueva sin las pestañas, el buscador ni la Pesca
  local g = ES:GetMainFrame()
  assert(ES.DEV == false and ES.db.userPreview == true, "no pasó a vista de jugador")
  assert(#g.tabs == 2, "pestañas en vista de jugador: " .. #g.tabs)
  ES:SelectPage("home")
  for _, c in ipairs(ES.homePage.cards) do
    if c._shown ~= false then assert(c.key ~= "Fishing", "la Pesca no debería verse") end
  end
  assert(ES.homePage.shownCards == #ES.PROFESSIONS - 1, "tarjetas en vista de jugador: " .. ES.homePage.shownCards)
  log[#log+1] = "     vista de jugador: " .. #g.tabs .. " pestañas"
  -- Y vuelta al modo desarrollo
  panel.devCheck:SetChecked(false)
  panel.devCheck._scripts.OnClick(panel.devCheck)
  assert(ES.DEV == true and not ES.db.userPreview and #ES:GetMainFrame().tabs == 4, "no volvió al modo desarrollo")
end)
step("merchant's favor: solo con su icono", function()
  -- Por defecto la ruta no usa recetas de Merchant's Favor; con el icono, sí (0 oro)
  local data = ES.Data.Engineering
  local plan = ES.Planner:Plan(data, ES:PlanOptions("Engineering", 1, 225, nil))
  for _, st in ipairs(plan.steps) do assert(not st.recipe.favor, "receta de Merchant's Favor sin el icono: " .. st.recipe.name) end
  local favor
  for _, r in pairs(data.recipes) do if r.favor then favor = r break end end
  assert(ES.Planner.LearnSkill(favor, { useFavor = true }) == (favor.train or 1), "con el icono se puede aprender")
  local page
  for _, p in ipairs(ES.professionPages) do if p.profKey == "Engineering" then page = p end end
  assert(page and page.favorButton, "falta el icono de Merchant's Favor")
  page.favorButton._scripts.OnEnter(page.favorButton)
  page.favorButton._scripts.OnClick(page.favorButton)
  assert(ES.db.prof.Engineering.useFavor, "el icono no activó Merchant's Favor")
  local withFavor = ES.Planner:Plan(data, ES:PlanOptions("Engineering", 1, 225, nil))
  local used = 0
  for _, st in ipairs(withFavor.steps) do if st.recipe.favor then used = used + 1 end end
  log[#log+1] = string.format("     merchant's favor: %d pasos con el icono, neto %.1f oro (sin él %.1f)", used, withFavor.net / 10000, plan.net / 10000)
  page.favorButton._scripts.OnClick(page.favorButton)
  assert(not ES.db.prof.Engineering.useFavor, "el icono no desactivó Merchant's Favor")
end)
step("pesca: guía por tramos", function()
  -- Página propia: tramos con cómo conseguir el rango y las zonas; marca el tuyo
  local page = ES:GetMainFrame().pages.Fishing
  assert(page and ES.fishingPage == page, "no hay página de Pesca")
  ES:SelectPage("Fishing")
  page._scripts.OnShow(page)
  local sections, zones = 0, 0
  for _, l in ipairs(page.lines) do
    if l.section then sections = sections + 1 elseif l.icon == "Interface\\Icons\\INV_Misc_Map_01" then zones = zones + 1 end
  end
  log[#log+1] = string.format("     pesca: %d tramos, %d zonas · %s", sections, zones, tostring(page.lines[1].section))
  assert(sections == 4 and zones > 20, "guía incompleta")
  assert(tostring(page.lines[1].section):find("1%-75"), "el primer tramo debería ser 1-75")
  -- Las filas con camino (instructor, libro, Nat Pagle) se pueden pulsar
  for i, l in ipairs(page.lines) do if l.go then page.rows[i]._scripts.OnClick(page.rows[i]) end end
  -- Tramo según el nivel
  assert(ES.FishingStep(ES.Data.Fishing, 160).rank == "expert", "tramo de 160")
  -- La colección de Pesca: las mejoras de campamento
  local known, total = ES.Collection:Progress("Fishing")
  assert(total == 3, "mejoras de campamento: " .. total)
  ES:SelectPage("home")
end)
step("recetas y objetos en español", function()
  -- Addon en español: las recetas toman su nombre en español (y el buscador encuentra las dos)
  ES.lang = "es"
  ES:LocalizeRecipeNames()
  local r = ES.Data.Cooking.recipes[2538]
  log[#log+1] = "     receta 2538: " .. tostring(r.name) .. " / " .. tostring(r.nameEN)
  assert(r.name == "Carne de lobo carbonizada" and r.nameEN == "Charred Wolf Meat", "nombre de receta: " .. tostring(r.name))
  -- Objeto sin cargar en el juego: el nombre de los datos en el idioma del addon
  assert(ES:DataItemName(2318) == "Cuero ligero", "objeto: " .. tostring(ES:DataItemName(2318)))
  ES.lang = "en"
  assert(ES:DataItemName(2318) == "Light Leather", "objeto en inglés: " .. tostring(ES:DataItemName(2318)))
  ES.lang = "es"
end)
step("cambiar de idioma al momento (sin recargar)", function()
  local reloaded = false
  ReloadUI = function() reloaded = true end
  ES.lang = "es"
  ES.ApplyLocalization()
  ES:LocalizeRecipeNames()
  ES:ShowMainFrame("patterns")
  local old = ES:GetMainFrame()
  -- A inglés: pestañas, nombres de recetas y la ventana nueva en la misma página
  ES:SetLanguage("en")
  assert(not reloaded, "no debería recargar la interfaz")
  assert(ES.db.lang == "en" and ES.lang == "en", "no guardó el idioma")
  local f = ES:GetMainFrame()
  assert(f ~= old, "debería crear la ventana de nuevo")
  assert(ES.db.lastPage == "patterns", "debería volver a la misma página: " .. tostring(ES.db.lastPage))
  assert(ES.Data.Cooking.recipes[2538].name == "Charred Wolf Meat", "receta en inglés: " .. ES.Data.Cooking.recipes[2538].name)
  assert(ES:ProfLabel("Leatherworking") == "Leatherworking", "profesión en inglés")
  local tabTip
  GameTooltip.AddLine = function(_, t) tabTip = tabTip or t end
  f.tabs[1]._scripts.OnEnter(f.tabs[1])
  GameTooltip.AddLine = nil
  log[#log+1] = "     pestaña en inglés: " .. tostring(tabTip)
  assert(tabTip ~= "Subir profesiones", "la pestaña sigue en español")
  -- Y de vuelta a español
  ES:SetLanguage("es")
  assert(ES.Data.Cooking.recipes[2538].name == "Carne de lobo carbonizada", "receta en español")
  assert(ES:ProfLabel("Leatherworking") == "Peletería", "profesión en español")
  ReloadUI = nil
end)
step("estado escaneo sin AH", function() ES.Scanner:Start() end)

return table.concat(log, "\n")
""")
print(out)


