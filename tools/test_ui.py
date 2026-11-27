"""Carga el addon completo con una API de WoW simulada y ejecuta la UI."""
import re
import sys
from pathlib import Path

import os
# Carpeta con lupa (Lua 5.1), solo si existe: si no, el lupa instalado con pip
_ESLUA = os.environ.get("ESLUA", r"C:\Users\bruno\AppData\Local\Temp\eslua")
if os.path.isdir(_ESLUA):
    sys.path.insert(0, _ESLUA)
from lupa import lua51

ADDON = Path(__file__).resolve().parent.parent  # el repositorio (no depende del enlace en AddOns)
lua = lua51.LuaRuntime(unpack_returned_tuples=True)

lua.execute(r"""
NOW = 2000000
time = function() return NOW end
EVENT_FRAMES = {}
function FireEvent(e, ...)
  local unit = ...
  for _, f in ipairs(EVENT_FRAMES[e] or {}) do
    -- (RegisterUnitEvent: como en el juego, solo si el primer argumento es una de sus unidades)
    local units = f._units and f._units[e]
    if f._scripts.OnEvent and (not units or units[unit]) then f._scripts.OnEvent(f, e, ...) end
  end
end
MOCK_METHODS = {} -- métodos de marcos que el addon ha llamado sin simulación propia
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
    if k == "SetAttribute" then return function(self, a, v) self._attributes = self._attributes or {} self._attributes[a] = v end end
    if k == "GetAttribute" then return function(self, a) return self._attributes and self._attributes[a] end end
    -- (los eventos que registra cada marco: FireEvent los lanza como el juego)
    if k == "RegisterEvent" then return function(self, e)
      EVENT_FRAMES[e] = EVENT_FRAMES[e] or {}
      table.insert(EVENT_FRAMES[e], self)
    end end
    if k == "RegisterUnitEvent" then return function(self, e, ...)
      self:RegisterEvent(e)
      self._units = self._units or {}
      local units = {}
      for i = 1, select("#", ...) do units[select(i, ...)] = true end
      self._units[e] = units
    end end
    if k == "GetChildren" then return function(self) return unpack(self._children or {}) end end
    if k == "IsProtected" then return function() return false end end
    if k == "Show" then return function(self) self._shown = true end end
    if k == "Hide" then return function(self) self._shown = false end end
    if k == "SetShown" then return function(self, v) self._shown = v and true or false end end
    if k == "IsShown" or k == "IsVisible" then return function() return true end end
    if k == "GetChecked" then return function(self) if self._checked == nil then return true end return self._checked end end
    if k == "SetChecked" then return function(self, v) self._checked = v and true or false end end
    -- Como en WoW: solo los métodos (con mayúscula) existen; los campos propios no
    if type(k) ~= "string" or not k:match("^%u") then return nil end
    MOCK_METHODS[k] = true -- (al final se comparan con la API real: WIDGET_API)
    return function() return Mock(k) end
  end })
end
CreateFrame = function(_, name, parent)
  local f = Mock("frame")
  if name then _G[name] = f end
  -- (los hijos, para GetChildren)
  if type(parent) == "table" then
    local kids = rawget(parent, "_children") or {}
    rawset(parent, "_children", kids)
    kids[#kids + 1] = f
  end
  return f
end
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
-- (el personaje: su clave es nombre y GUID, Keys.lua. Este simulador es un cliente de
-- antes del parche de Forever: da el reino y no tiene C_GameRules)
UnitGUID = function(u) if u == "player" then return "Player-1-00000001" end end
""")

# Globales escritas desde los archivos del addon (los mocks del test no cuentan)
lua.execute(r"""
LEAKS = {}
local ALLOWED = { CraftersJournalDB = true, SLASH_CRAFTERSJOURNAL1 = true, SLASH_CRAFTERSJOURNAL2 = true, SLASH_CRAFTERSJOURNAL3 = true,
  CraftersJournal_OnAddonCompartmentClick = true, CraftersJournal = true, CraftersJournalMainFrame = true,
  CraftersJournalAHButton = true, CraftersJournalMinimapButton = true, CraftersJournalRowMarkButton = true,
  LibStub = true, } -- (LibStub es global a propósito: así comparten librerías los addons)
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
lua.globals().TOC_TEXT = toc  # (para comprobar lo que no se publica)
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

# --v1: todo con el planificador antiguo (el de antes del GPS), para comparar
if "--v1" in sys.argv:
    lua.execute("ES.Planner.USE_GPS = false")

out = lua.execute(r"""
local log = {}
local function step(name, fn)
  local ok, err = pcall(fn)
  log[#log + 1] = (ok and "OK   " or "FAIL ") .. name .. (ok and "" or (": " .. tostring(err)))
end

-- Simular ADDON_LOADED a mano (el mock no dispara eventos)
CraftersJournalDB = { scans = {} }
ES.db = CraftersJournalDB
ES.db.assistant = {}
-- (C_Timer.After no hace nada aquí: sin espera, el paso siguiente se pinta al momento)
if ES.Assistant then ES.Assistant.CELEBRATE_HOLD = 0 end
ES.db.minimap = { angle = 200 } -- (formato antiguo: se pasa a minimapPos de LibDBIcon)

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
  local last = ES.db.history[key][3]
  log[#log+1] = "     baratas que siguen (último): " .. tostring(last.stuck)
  assert(last.sold == nil, "el historial no debe guardar ventas")
end)

step("crear panel", function() ES:ShowMainFrame() end)

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
  -- Las ventas son al vendedor (no "Profit": son ingresos), con tooltip que manda a la
  -- vista Profit para lo de la AH (CurseForge: "should be called Revenue")
  do
    local tip, savedAddL = {}, GameTooltip.AddLine
    GameTooltip.AddLine = function(_, t) tip[#tip + 1] = tostring(t) end
    local okTip, errTip = pcall(page.salesHover._scripts.OnEnter, page.salesHover)
    GameTooltip.AddLine = savedAddL
    assert(okTip, tostring(errTip))
    local all = table.concat(tip, "\n")
    assert(all:find("Ventas al vendedor", 1, true) and all:find("venta segura", 1, true) and all:find("vista Profit", 1, true),
      "el tooltip de las ventas dice qué cuentan y dónde está lo de la AH: " .. all)
    log[#log+1] = "     ventas: " .. (tip[#tip] or ""):gsub("|T[^|]+|t", "")
  end
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
  -- Demanda de TSM: señal aparte. Sin TSM, ni se nombra y todo es como antes
  assert(TSM_API == nil and not good.demand.known and good.total == 3, "sin TSM: 3 señales")
  for _, l in ipairs(ES.Market.Describe(good)) do assert(not l[1]:find("TSM"), "sin TSM no se nombra: " .. l[1]) end
  local tsm = {}
  TSM_API = { GetCustomPriceValue = function(src, itemString)
    local d = tsm[tonumber(itemString:match("^i:(%d+)$"))]
    if not d then return nil end
    local v = src == "DBRegionSaleRate * 1000" and d[1] * 1000 or src == "DBRegionSoldPerDay * 1000" and d[2] * 1000
      or src == "DBRegionSaleAvg" and d[3] or nil
    return v and v > 0 and math.floor(v) or nil
  end }
  -- Se vende bien: sigue bien y TSM cuenta como una señal más
  tsm[8888] = { 0.6, 40, 500 }
  ES.Market.ClearTSM()
  local s = ES.Market:Signals(8888)
  assert(s.demand.known and not s.demand.flag and s.verdict == "good" and s.total == 4,
    "TSM bien: esperado bien de 4, salió " .. s.verdict .. " de " .. s.total)
  -- Poca demanda (Tuxedo Jacket: 0,75 al día, tasa 0,30): ojo, no evitar
  tsm[8888] = { 0.30, 0.75, 175 }
  ES.Market.ClearTSM()
  s = ES.Market:Signals(8888)
  assert(s.demand.flag and s.verdict == "watch" and s.flags == 1, "poca demanda sola: esperado ojo, salió " .. s.verdict)
  local found
  for _, l in ipairs(ES.Market.Describe(s)) do
    if l[1]:find("TSM") then found = l log[#log+1] = "     8888 " .. l[1] end
  end
  assert(found and found[2] == true and found[1]:find("0,75") and found[1]:find("0,3"), "línea de TSM con sus cifras y en contra")
  assert(ES.Market.TSMLowPrice(s, 500) and not ES.Market.TSMLowPrice(s, 200), "aviso de venta media de TSM por debajo")
  -- Poca demanda + otra alerta nuestra: evitar
  local realSupply = ES.Market.Supply
  ES.Market.Supply = function() return { known = true, flag = true, from = 1, to = 20, growth = 19, hours = 24 } end
  s = ES.Market:Signals(8888)
  ES.Market.Supply = realSupply
  assert(s.verdict == "avoid", "poca demanda y más oferta: esperado evitar, salió " .. s.verdict)
  -- Tasa muy baja aunque se vendan muchas: también en contra
  tsm[8888] = { 0.05, 30, 500 }
  ES.Market.ClearTSM()
  assert(ES.Market:Signals(8888).demand.flag, "tasa de venta baja: en contra")
  -- TSM sin datos de ese objeto: se dice, pero no cuenta
  s = ES.Market:Signals(6666)
  assert(not s.demand.known and s.total == 3, "sin datos de TSM no cuenta")
  local said
  for _, l in ipairs(ES.Market.Describe(s)) do if l[1]:find("TSM") then said = l end end
  assert(said and said[2] == nil, "sin datos de TSM: línea gris")
  -- Recetas para aprender (cuestan oro): ni con poca demanda ni con venta media de TSM
  -- muy por debajo de nuestro precio (Discord: Frost Tunic)
  local function Learnable(rate, sold, avg)
    tsm[8888] = { rate, sold, avg }
    ES.Market.ClearTSM()
    local res = { learnable = {} }
    ES.Earn.AddLearnable(res, { cost = 100, profit = 2000, sellWhere = "ah", itemID = 8888, ahPrice = 500, learn = 1 }, "Tailoring", 150, 1000)
    return #res.learnable == 1
  end
  assert(Learnable(0.6, 40, 500), "TSM bien: se propone aprenderla")
  assert(not Learnable(0.55, 0.82, 4888), "poca demanda: no se propone aprenderla")
  assert(not Learnable(0.6, 40, 100), "venta media de TSM muy por debajo: no se propone aprenderla")
  -- Umbrales elegidos por el jugador: con 0, ese criterio no cuenta
  ES.db.tsmMinSold = 0
  assert(Learnable(0.55, 0.82, 500), "sin mínimo de vendidos al día: la de 0,82 al día vale")
  ES.db.tsmMinSold, ES.db.tsmMinRate = 5, 0
  tsm[8888] = { 0.01, 3, 500 }
  ES.Market.ClearTSM()
  s = ES.Market:Signals(8888)
  assert(s.demand.flag, "mínimo 5 al día: 3 al día en contra")
  ES.db.tsmMinSold = 2
  assert(not ES.Market:Signals(8888).demand.flag, "mínimo 2 al día y tasa sin mínimo: 3 al día con tasa 0,01 vale")
  ES.db.tsmMinSold, ES.db.tsmMinRate = nil, nil
  -- Opción quitada: como sin TSM
  ES.db.noTsmDemand = true
  ES.Market.ClearTSM()
  s = ES.Market:Signals(8888)
  assert(not s.demand.known and not s.demand.tsm and s.verdict == good.verdict, "opción quitada: como sin TSM")
  ES.db.noTsmDemand = nil
  TSM_API = nil
  ES.Market.ClearTSM()
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
step("lista de compra", function()
  local searched
  AuctionFrame = CreateFrame("Frame")
  BrowseName = CreateFrame("EditBox")
  AuctionFrameBrowse_Search = function() searched = BrowseName:GetText() end
  CanSendAuctionQuery = function() return true, true end
  local realData = ES.GetItemData
  ES.GetItemData = function(self, id) return "Item" .. id, 1, 134400 end
  ES:SearchAuction(2318)
  assert(searched == "Item2318", "no buscó: " .. tostring(searched))
  local SH = ES.Shopping
  local savedChar, savedOpenAH = ES.charData, ES.IsAuctionHouseOpen
  ES.charData = { shopping = {} }
  local real = ES.ItemCount
  ES.ItemCount = function() return 0 end
  -- Dos listas: una ruta y un lote. Guardan la cantidad entera (lo que llevas se
  -- cuenta al enseñarlas) y lo que se fabrica no entra
  local route = SH.Add("route", "Ruta", { { itemID = 2318, quantity = 20, unit = 100, source = "ah" },
    { itemID = 2319, quantity = 5, unit = 300, source = "ah" }, { itemID = 159, quantity = 3, unit = 25, source = "vendor" },
    { itemID = 2318, quantity = 2, unit = 100, source = "ah" } }, { key = "Leatherworking" })
  assert(route and #route.items == 3 and route.items[1].need == 22, "ruta añadida (juntando repetidos)")
  local money = SH.Add("money", "Lote", { { itemID = 2318, quantity = 10, unit = 100, source = "ah" },
    { itemID = 2320, quantity = 4, unit = 50, source = "ah" }, { itemID = 1, quantity = 1, source = "craft" } })
  assert(money and #money.items == 2, "el lote no debería pedir lo que se fabrica")
  -- Lo que llevas (bolsas): 25 de 2318 llenan primero la ruta (22) y 3 del lote
  local BAGS = { [2318] = 25, [2320] = 4, [159] = 3 }
  ES.ItemCount = function(self, id) return BAGS[id] or 0 end
  local st = SH.Status()
  local r1, r2 = st.lists[1].items, st.lists[2].items
  assert(r1[1].bought == 22 and r1[1].left == 0 and r2[1].bought == 3 and r2[1].left == 7,
    string.format("reparto de lo que llevas: %d %d %d", r1[1].bought, r2[1].bought, r2[1].left))
  assert(r1[3].left == 0 and r2[2].left == 0, "lo que llevas cuenta como tenido")
  assert(st.done == 3 and st.total == 5, string.format("progreso %d/%d", st.done, st.total))
  -- Lo "de camino" de versiones anteriores (Discord: "48 en el correo" pegado) se borra
  -- al entrar; sin compras nuevas, lo que tienes es lo de tus bolsas
  do
    ES.db.ahOnWay = { [2319] = { n = 48, last = 0, t = time() } }
    FireEvent("PLAYER_ENTERING_WORLD")
    assert(ES.db.ahOnWay == nil, "lo de camino de versiones anteriores debería borrarse al entrar")
    assert(ES:HaveForShopping(2319) == ES:ItemCount(2319), "sin compras de camino, lo que tienes son tus bolsas")
  end
  -- Ruta acabada (la profesión llega a su objetivo): su lista se quita sola
  local savedSkill = ES.GetProfessionSkill
  ES.GetProfessionSkill = function(_, line) if line == ES.Data.Leatherworking.skillLine then return 300, 300 end end
  local done = SH.Status()
  ES.GetProfessionSkill = savedSkill
  assert(#done.lists == 1 and done.lists[1].list.kind == "money" and #SH.Lists() == 1, "la lista de una ruta acabada debería quitarse")
  table.insert(SH.Lists(), 1, route) -- (vuelve para el resto de la prueba)
  -- Comprar siguiente: el primero que falta (2319); el abierto, si aún falta
  local id, left = SH.NextToBuy(st)
  assert(id == 2319 and left == 5, "siguiente: " .. tostring(id))
  id, left = SH.NextToBuy(st, 2318)
  assert(id == 2318 and left == 7, "sigue con el abierto: " .. tostring(id) .. " " .. tostring(left))
  -- Volver a añadir la misma ruta la sustituye
  SH.Add("route", "Ruta 2", { { itemID = 2319, quantity = 1, source = "ah" } }, { key = "Leatherworking" })
  assert(#SH.Lists() == 2 and SH.Lists()[2].title == "Ruta 2", "la ruta se duplicó")
  -- Pestaña: abierta desde la AH, con Comprar siguiente
  ES.IsAuctionHouseOpen = function() return true end
  -- (en estas pruebas IsShown siempre dice que sí: la ventana grande mira _shown)
  local mf = ES:GetMainFrame()
  mf.IsShown = function(self) return self._shown ~= false end
  -- Con la ventana grande abierta, abrir la AH no la cierra (ni sale el panel pequeño)
  ES:ShowMainFrame("home")
  ES.db.shopMiniHidden = nil
  ES:SetupAuctionPanel(AuctionFrame)
  local mini = ES.ShoppingMini()
  assert(mf._shown ~= false, "con el addon abierto, abrir la AH no debería cerrarlo")
  assert(mini and mini._shown == false, "con el addon abierto no debería salir también el panel pequeño")
  -- Con la ventana grande cerrada: sale el panel pequeño con la misma lista
  ES:HideMainFrame()
  ES:SetupAuctionPanel(AuctionFrame)
  assert(mini._shown, "al abrir la AH con el addon cerrado: falta el panel pequeño")
  mf.IsShown = nil
  assert(mini.progress > 0 and mini.progress < 1 and mini.rows[1] and mini.rows[1]._shown, "panel pequeño sin la lista")
  -- "Ver completa": la pestaña grande en su lugar del pequeño
  ES:OpenShoppingAtAuction(AuctionFrame)
  assert(mini._shown == false and ES.db.lastPage == "shopping", "Ver completa: la grande en lugar del pequeño")
  -- El botón de la AH (o su X) lo oculta solo hasta la próxima vez que abras la AH:
  -- antes se quedaba cerrado para siempre y la lista no volvía a salir
  ES:ToggleShoppingMini(AuctionFrame)
  assert(mini._shown == false and ES.shopMiniClosed, "ocultar el panel pequeño")
  ES:RenderShopping()
  assert(mini._shown == false, "cerrado, no vuelve a salir mientras sigas en la AH")
  -- (con la ventana grande cerrada: abierta a su lado, el panel pequeño no sale)
  mf.IsShown = function(self) return self._shown ~= false end
  ES:HideMainFrame()
  ES:SetupAuctionPanel(AuctionFrame)
  mf.IsShown = nil
  assert(mini._shown and not ES.shopMiniClosed, "al volver a abrir la AH, con algo por comprar, vuelve a salir")
  -- Junto a la AH solo lo de la AH: lo de vendedor (Leaded Vial de la calculadora) no
  local VIAL = 3371
  SH.Add("calc", "Calc vial", { { itemID = VIAL, quantity = 5, source = "vendor", cost = 180 } }, { key = "vial" })
  ES:RenderShopping()
  for _, row in ipairs(mini.rows) do
    assert(not (row._shown ~= false and row.line and row.line.item == VIAL), "el panel de la AH enseña algo de vendedor")
  end
  local stv = SH.Status()
  assert(stv.bySource.vendor.total >= 1 and stv.bySource.ah.total == stv.total - stv.bySource.vendor.total, "cuentas por origen")
  for i, l in ipairs(SH.Lists()) do if l.key == "vial" then table.remove(SH.Lists(), i) break end end
  ES:RenderShopping()
  -- Una lista vieja se quita desde el panel pequeño: la ✕ de su título (CurseForge: "no
  -- hay forma de borrar los cálculos viejos" desde la AH)
  do
    SH.Add("calc", "Calc vieja", { { itemID = 2589, quantity = 3, source = "ah", cost = 50 } }, { key = "vieja" })
    ES:RenderShopping()
    local head
    for _, row in ipairs(mini.rows) do
      if row._shown ~= false and row.line and row.line.section == "Calc vieja" then head = row end
    end
    assert(head and head.remove._shown ~= false, "el título de la lista en el panel de la AH no tiene ✕")
    head.remove._scripts.OnClick(head.remove)
    for _, l in ipairs(SH.Lists()) do assert(l.key ~= "vieja", "la ✕ del panel de la AH no quitó la lista") end
    for _, row in ipairs(mini.rows) do
      assert(not (row._shown ~= false and row.line and row.line.section == "Calc vieja"), "la lista quitada sigue en el panel")
      assert(not (row._shown ~= false and row.line and not row.line.section and row.remove._shown == true), "una fila de material tiene la ✕ de lista")
    end
    log[#log+1] = "     panel de la AH: la ✕ del título quita esa lista"
    -- Y al revés: quitada en la pestaña (la ✕ de su total), tampoco sale en el panel
    -- de la AH (CurseForge: "la quito en la pestaña y sigue en la de la AH")
    SH.Add("calc", "Calc tab", { { itemID = 2589, quantity = 3, source = "ah", cost = 50 } }, { key = "tab" })
    ES:RenderShopping()
    local inMini = false
    for _, row in ipairs(mini.rows) do if row._shown ~= false and row.line and row.line.section == "Calc tab" then inMini = true end end
    assert(inMini, "la lista nueva no sale en el panel de la AH")
    local page = ES.shoppingPage
    local total
    for _, row in ipairs(page.rows) do
      if row._shown ~= false and row.onSkip and row.title and tostring(row.title._text):find("listos") then total = row end
    end
    -- (la última fila de total es la de "Calc tab", la más nueva)
    assert(total, "la pestaña no tiene la fila de total con ✕")
    total.onSkip()
    for _, l in ipairs(SH.Lists()) do assert(l.key ~= "tab", "la ✕ de la pestaña no quitó la lista") end
    for _, row in ipairs(mini.rows) do
      assert(not (row._shown ~= false and row.line and row.line.section == "Calc tab"), "quitada en la pestaña, sigue en el panel de la AH")
    end
    log[#log+1] = "     quitada en la pestaña: también desaparece del panel de la AH"
  end
  -- Colocación: a la derecha de la ventana de vender en la AH si se ve; si no, pegado a la AH
  local anchor
  local savedSP, savedSell = mini.SetPoint, CraftersJournalAuctionSellPanel
  mini.SetPoint = function(_, _, rel) anchor = rel end
  local fakeSell = { IsShown = function() return true end }
  CraftersJournalAuctionSellPanel = fakeSell
  ES:PlaceShoppingMini()
  assert(anchor == fakeSell, "con la ventana de vender, la lista de compra va a su derecha")
  CraftersJournalAuctionSellPanel = nil
  ES:PlaceShoppingMini()
  assert(anchor == (AuctionHouseFrame or AuctionFrame), "sin ella, pegada a la AH")
  mini.SetPoint, CraftersJournalAuctionSellPanel = savedSP, savedSell
  local page = ES.shoppingPage
  assert(page and page:IsVisible(), "la pestaña no se abrió")
  local opened
  local savedOpen = ES.OpenAuctionBuy
  ES.OpenAuctionBuy = function(_, oid) opened = oid end
  ES:ShoppingBuyNext()
  ES.OpenAuctionBuy = savedOpen
  -- (sin la primera ruta, las 25 compradas completan el lote: falta 2319 de la ruta nueva)
  assert(opened == 2319, "Comprar siguiente: " .. tostring(opened))
  assert(page.progress > 0 and page.progress < 1, "barra: " .. tostring(page.progress))
  -- Quitar un material; si la lista se queda vacía, se quita entera
  local last = SH.Lists()[2]
  SH.RemoveItem(last, 2319)
  assert(#SH.Lists() == 1, "la lista vacía debería quitarse")
  SH.Lists()[2] = last
  last.items[1] = { itemID = 2319, need = 1, unit = 0, source = "ah" }
  last.items[2] = { itemID = 2321, need = 2, unit = 0, source = "ah" }
  SH.RemoveItem(last, 2321)
  assert(#last.items == 1 and last.items[1].itemID == 2319, "quitar un material")
  -- Quitar una lista
  assert(SH.Remove(SH.Lists()[1]) and #SH.Lists() == 1, "quitar lista")
  ES:RenderShopping()
  mini:Hide()
  log[#log+1] = string.format("     %d de %d materiales; siguiente %s", st.done, st.total, tostring(opened))
  ES:ShowMainFrame("home")
  ES.ItemCount, ES.GetItemData, ES.charData, ES.IsAuctionHouseOpen = real, realData, savedChar, savedOpenAH
end)
step("ganar dinero (sin correo)", function()
  -- Peletería al 150 sabiendo todas sus recetas de instructor
  local realSkill, realKnown = ES.GetProfessionSkill, ES.IsRecipeKnown
  ES.GetProfessionSkill = function(self, line) if line == ES.Data.Leatherworking.skillLine then return 150, 225 end end
  ES.IsRecipeKnown = function(self, id) local r = ES.Data.Leatherworking.recipes[id] return r ~= nil and r.fee ~= nil end
  -- El buzón no se lee ni se guarda (ni el módulo existe)
  assert(ES.Mail == nil, "el addon no debería leer el correo")
  -- Beneficio mínimo por línea: escalones y filtro
  ES.db.earnMinProfit = 0
  assert(ES.Earn.StepMinLineProfit(1) == 1000 and ES.Earn.StepMinLineProfit(-1) == 0
    and ES.Earn.StepMinLineProfit(-1) == 200000, "escalones del mínimo")
  ES.db.earnMinProfit = 0
  ES.Earn:Clear()
  local all = ES.Earn:Ideas()
  ES.db.earnMinProfit = 50000
  ES.Earn:Clear()
  local few = ES.Earn:Ideas()
  for _, idea in ipairs(few.ideas) do
    assert(ES.Earn.LineValue(idea) >= 50000, "idea por debajo del mínimo: " .. idea.e.recipe.name)
  end
  for _, idea in ipairs(few.batch) do assert(ES.Earn.LineValue(idea) >= 50000, "lote por debajo del mínimo") end
  for _, idea in ipairs(few.vendor) do assert(ES.Earn.LineValue(idea) >= 50000, "vendedor por debajo del mínimo") end
  assert(#few.ideas <= #all.ideas and (few.hidden > 0 or #few.ideas == #all.ideas), "el mínimo no ocultó nada")
  log[#log+1] = string.format("     mínimo 5g: %d de %d ideas (%d ocultas)", #few.ideas, #all.ideas, few.hidden)
  ES:SelectPage("money")
  ES:RenderEarn()
  ES:SelectPage("home")
  ES.db.earnMinProfit = 0
  -- (los datos de prueba dejan pocos cobres: sin el mínimo interno de oro por hora del
  -- vendedor no habría líneas que comprobar)
  local savedVGPH = ES.Earn.VENDOR_MIN_GPH
  ES.Earn.VENDOR_MIN_GPH = 0
  ES.Earn:Clear()
  local res = ES.Earn:Ideas()
  assert(res.known > 0, "no detecta recetas conocidas")
  -- Tiempo: las líneas del vendedor no pasan de VENDOR_TIME_BUDGET (577 Linen Bag eran ~40 min)
  for _, idea in ipairs(res.vendor) do
    assert(idea.seconds and idea.seconds > 0, "línea del vendedor sin tiempo: " .. idea.e.recipe.name)
    assert(idea.crafts * idea.craftSecs <= ES.Earn.VENDOR_TIME_BUDGET + idea.craftSecs,
      string.format("%s: %d fabricaciones pasan del tope de tiempo", idea.e.recipe.name, idea.crafts))
    -- (con lo intermedio: el tope mide lo mismo que idea.seconds; margen de un minuto
    -- por el redondeo de las fabricaciones de lo intermedio)
    assert(idea.crafts <= 1 or idea.seconds <= ES.Earn.VENDOR_TIME_BUDGET + 60,
      string.format("%s: %d s con lo intermedio pasan del tope de tiempo", idea.e.recipe.name, idea.seconds))
  end
  -- El tiempo cuenta fabricaciones, no unidades (spec make-money-timing): 10 de 3 s y 20
  -- unidades de un intermedio que da 2 por fabricación y tarda 5 s = 10×3 + 10×5 = 80 s
  do
    local savedCS, savedV = ES.Earn.CraftSeconds, ES.Earn.VENDOR_MIN_GPH
    local INT = 990001
    ES.Earn.CraftSeconds = function(id) return id == INT and 5 or 3 end
    local idea = { e = { id = 990000 }, itemID = 1, crafts = 10, profit = 10000, sellWhere = "vendor",
      ctx = { data = { recipes = { [INT] = { out = { 2, 2 } } } } },
      actions = { { kind = "craft", item = 2, qty = 20, recipe = INT }, { kind = "ah", item = 3, qty = 40 } } }
    ES.Earn.Timing(idea)
    assert(idea.seconds == 80, "tiempo con un intermedio que da 2: " .. tostring(idea.seconds))
    -- El oro por hora usa ese tiempo: 1g en 80 s = 45g/h, por encima de un mínimo de 40g/h
    assert(math.abs(idea.gph - 450000) < 1, "oro por hora: " .. tostring(idea.gph))
    ES.Earn.VENDOR_MIN_GPH = 400000
    assert(ES.Earn.FastEnough(idea), "45g/h no queda escondida por un mínimo de 40g/h")
    -- Unidades que no llenan la última fabricación: 5 de un intermedio que da 2 = 3
    assert(ES.Earn.IdeaSeconds(idea, 0, { { kind = "craft", item = 2, qty = 5, recipe = INT } }) == 15,
      "5 unidades de un intermedio que da 2 son 3 fabricaciones")
    -- Sin intermedios: 12 de 3 s = 36 s
    idea.crafts, idea.actions = 12, {}
    ES.Earn.Timing(idea)
    assert(idea.seconds == 36, "sin intermedios: " .. tostring(idea.seconds))
    ES.Earn.CraftSeconds, ES.Earn.VENDOR_MIN_GPH = savedCS, savedV
  end
  local savedGSI = GetSpellInfo
  GetSpellInfo = function(id) return "x", nil, 0, 5000 end -- lanzamiento de 5 s
  assert(math.abs(ES.Earn.CraftSeconds(1) - 5.5) < 0.01, "segundos por fabricación: lanzamiento + margen")
  GetSpellInfo = function() return "x", nil, 0, 0 end -- instantánea: al menos el tiempo global
  assert(ES.Earn.CraftSeconds(1) >= 2, "instantánea: el tiempo global cuenta")
  GetSpellInfo = savedGSI
  -- Con el mínimo interno, lo del vendedor que no compensa el tiempo no se propone
  -- (577 Linen Bag: ~5g en ~40 min); las de la AH no se filtran por tiempo
  ES.Earn.VENDOR_MIN_GPH = 500000
  ES.Earn:Clear()
  local fast = ES.Earn:Ideas()
  for _, idea in ipairs(fast.vendor) do
    assert(idea.gph and idea.gph >= 500000, "venta al vendedor que no compensa el tiempo: " .. idea.e.recipe.name)
  end
  assert(#fast.ideas == #res.ideas, "las de la AH no se filtran por tiempo")
  -- Las escondidas por tiempo no cuentan en "por debajo del mínimo" (habla del beneficio)
  assert(fast.hidden == res.hidden, "las escondidas por tiempo se suman a las del mínimo: " .. fast.hidden .. " vs " .. res.hidden)
  assert((fast.slow or 0) == #res.vendor - #fast.vendor, "cuenta aparte de las que no compensan el tiempo")
  -- El mínimo depende del nivel: a nivel bajo, mucho menos que a nivel alto
  ES.Earn.VENDOR_MIN_GPH = nil
  local savedLevel = UnitLevel
  UnitLevel = function() return 10 end
  local low = ES.Earn.VendorMinGPH()
  UnitLevel = function() return 60 end
  local high = ES.Earn.VendorMinGPH()
  UnitLevel = savedLevel
  assert(low == 20000 and high == 120000, string.format("mínimo por nivel: %d y %d", low, high))
  log[#log+1] = string.format("     vendedor: %d líneas sin mínimo de oro por hora, %d con 50g/h", #res.vendor, #fast.vendor)
  ES.Earn.VENDOR_MIN_GPH = 0
  ES.Earn:Clear()
  res = ES.Earn:Ideas()
  -- Venta al vendedor: aparte del lote, sin tope de 20, cada una hasta que la siguiente no compense
  for _, idea in ipairs(res.batch) do assert(idea.sellWhere ~= "vendor", "el lote no debería llevar ventas al vendedor") end
  for _, idea in ipairs(res.vendor) do
    assert(idea.sellWhere == "vendor" and not idea.inBatch and idea.crafts > 0 and idea.profit > 0 and idea.limit,
      "línea del vendedor mal: " .. idea.e.recipe.name)
    if idea.limit == "margin" then
      -- La siguiente ya no deja el margen mínimo
      local n = idea.crafts
      local cost = ES.Planner.RecipeCost(idea.ctx, idea.e.recipe, n + 1, {})
      local marginal = cost - idea.invest
      assert(idea.sale - marginal < math.max(5, 0.1 * marginal), "la siguiente aún compensaba: " .. idea.e.recipe.name)
    end
  end
  if res.vendor[1] then
    local v = res.vendor[1]
    log[#log+1] = string.format("     vendedor: %d líneas; la mejor %dx %s +%s (tope: %s)", #res.vendor, v.crafts, v.e.recipe.name, ES.Money(v.profit), v.limit)
  end
  log[#log+1] = string.format("     %d conocidas, %d ideas, %d evitar, lote %d: invierte %s gana %s, %d materiales",
    res.known, #res.ideas, #res.avoided, #res.batch, ES.Money(res.invest), ES.Money(res.profit), #res.shopping)
  for i = 1, math.min(3, #res.batch) do
    local idea = res.batch[i]
    log[#log+1] = string.format("       %dx %s +%s (%s, %s)", idea.crafts, idea.e.recipe.name, ES.Money(idea.profit), tostring(idea.verdict or idea.sellWhere), idea.why)
  end
  -- La lista de compra del lote lleva lo que se compra de verdad: también los materiales
  -- de lo intermedio que fabricas tú (Bolt of Mageweave -> Mageweave Cloth), nunca "craft"
  local inShop = {}
  for _, it in ipairs(res.shopping) do
    assert(it.source ~= "craft", "en la lista de compra hay algo que se fabrica: " .. it.itemID)
    inShop[it.itemID] = true
  end
  local crafted = 0
  for _, idea in ipairs(res.batch) do
    for _, a in ipairs(idea.actions or {}) do
      if a.kind == "ah" or a.kind == "vendor" then assert(inShop[a.item], "falta en la lista de compra: " .. a.item) end
      if a.kind == "craft" and a.item ~= idea.itemID then
        crafted = crafted + 1
        -- (cada intermedio lleva el id de su receta: Earn.Timing mide su tiempo con ella)
        local r = type(a.recipe) == "number" and idea.ctx.data.recipes[a.recipe]
        assert(r and r.out and r.out[1] == a.item, "intermedio sin el id de su receta: " .. a.item)
      end
    end
  end
  log[#log+1] = string.format("     lista del lote: %d materiales (%d intermedios fabricados por el camino)", #res.shopping, crafted)
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
  -- Recetas que no sabes y darían beneficio (Peletería al 150 sabiendo solo las de instructor)
  for _, idea in ipairs(res.learnable) do
    assert(idea.learnable and idea.e.learnSource ~= "known" and idea.e.profit > 0, "receta para aprender mal: " .. idea.e.recipe.name)
    assert(idea.canLearn == (150 >= idea.need), "ya puedes / pide: " .. idea.e.recipe.name)
  end
  for i = 2, #res.learnable do
    local a, b = res.learnable[i - 1], res.learnable[i]
    assert(a.canLearn or not b.canLearn, "primero las que ya puedes aprender")
  end
  -- (directo, con entradas inventadas: los datos de prueba no traen ninguna con beneficio)
  do
    local fake = { learnable = {} }
    local function E(source, profit, learn, cost) return { recipe = { name = source }, itemID = 1, learnSource = source,
      cost = 1000, profit = profit, learn = learn, learnCost = cost, sellWhere = "vendor", vendor = 1000 + profit } end
    ES.Earn.AddLearnable(fake, E("trainer", 500, 100, 2000), "Leatherworking", 150, 1000)  -- sí: ya puedes, se paga en 4
    ES.Earn.AddLearnable(fake, E("vendor", 800, 200, 0), "Leatherworking", 150, 1000)     -- sí: pide 200
    ES.Earn.AddLearnable(fake, E("trainer", 50, 100, 0), "Leatherworking", 150, 5000)     -- no: 50 x 20 < 5000
    ES.Earn.AddLearnable(fake, E("trainer", 2, 100, 0), "Leatherworking", 150, 0)         -- no: menos del margen
    assert(#fake.learnable == 2, "recetas para aprender: " .. #fake.learnable)
    local t, v = fake.learnable[1], fake.learnable[2]
    assert(t.canLearn and t.payback == 4 and not v.canLearn and v.payback == nil, "ya puedes / se paga en")
  end
  log[#log+1] = string.format("     recetas para aprender con beneficio: %d%s", #res.learnable,
    res.learnable[1] and (" · la primera " .. res.learnable[1].e.recipe.name .. " +" .. ES.Money(res.learnable[1].e.profit) .. "/u") or "")
  -- Página y portada
  ES:SelectPage("money")
  ES:RenderEarn()
  -- Secciones plegables: clic en el encabezado la pliega (con cuántas tiene) y se recuerda
  local page = ES.earnPage
  local function SectionRow()
    for _, row in ipairs(page.rows) do
      if row._shown ~= false and row.onClick and tostring(row.section._text) ~= "" then return row end
    end
  end
  local sec = SectionRow()
  if sec then
    local shownBefore = 0
    for _, row in ipairs(page.rows) do if row._shown ~= false then shownBefore = shownBefore + 1 end end
    sec._scripts.OnClick(sec)
    local key = next(ES.db.earnCollapsed or {})
    assert(key and ES.UI.EarnCollapsed(key), "plegar: no se guardó")
    local shownAfter = 0
    for _, row in ipairs(page.rows) do if row._shown ~= false then shownAfter = shownAfter + 1 end end
    assert(shownAfter < shownBefore, "plegar: siguen las mismas filas (" .. shownBefore .. " -> " .. shownAfter .. ")")
    assert(tostring(SectionRow().section._text):find("%(%d+%)"), "plegada, dice cuántas tiene: " .. tostring(SectionRow().section._text))
    SectionRow()._scripts.OnClick(SectionRow())
    assert(not ES.UI.EarnCollapsed(key), "desplegar")
    log[#log+1] = "     secciones plegables: " .. key
  end
  -- Mínimo con el deslizador: escalón a escalón, y la rueda
  local savedAfter = C_Timer.After
  C_Timer.After = function(_, fn) fn() end
  page.minSlider._scripts.OnValueChanged(page.minSlider, 4)
  assert(ES.Earn.MinLineProfit() == ES.Earn.MIN_LINE_STEPS[4] and ES.Earn.MinLineStep() == 4, "deslizador: escalón 4")
  assert(tostring(page.minLabel._text):find("50"), "el texto del mínimo: " .. tostring(page.minLabel._text))
  page.minSlider.SetValue = function(self, v) self._scripts.OnValueChanged(self, v) end
  page.minSlider._scripts.OnMouseWheel(page.minSlider, -1)
  assert(ES.Earn.MinLineStep() == 3, "rueda: un escalón menos")
  page.minSlider._scripts.OnValueChanged(page.minSlider, 1)
  assert(ES.Earn.MinLineProfit() == 0, "deslizador al principio: sin mínimo")
  page.minSlider.SetValue = nil
  C_Timer.After = savedAfter
  -- Añadir el lote a la lista de compra (una lista por día)
  local savedChar = ES.charData
  ES.charData = { shopping = {} }
  local savedFlash, earnFlashed = ES.FlashTab, nil
  ES.FlashTab = function(_, key, sound) earnFlashed = key == "shopping" and sound end
  ES.earnPage.addButton._scripts.OnClick(ES.earnPage.addButton)
  ES.earnPage.addButton._scripts.OnClick(ES.earnPage.addButton)
  ES.FlashTab = savedFlash
  local lists = ES.Shopping.Lists()
  assert(#lists == 0 or earnFlashed, "Ganar dinero añade a la lista sin sonido ni brillo")
  local needed = 0
  for _, it in ipairs(res.shopping) do if it.source ~= "craft" and it.quantity > 0 then needed = needed + 1 end end
  assert((needed == 0 and #lists == 0) or (#lists == 1 and lists[1].kind == "money"), "lote a la lista: " .. #lists)
  ES.charData = savedChar
  -- Con TSM: no se proponen más de las que se venden en la región en 2 días
  local function B(sold, qty, verdict)
    local idea = { sellWhere = "ah", verdict = verdict or "good",
      signals = { demand = sold and { known = true, sold = sold } or { known = false } } }
    return ES.Earn.Batch(idea, { quantity = 100, qty = qty or 1 })
  end
  local n0 = B(nil)
  local n1, why1 = B(0.4)
  local n2 = B(12, 5)
  local n3 = B(100)
  assert(n0 == 10, "sin TSM: el tope de siempre (10), salió " .. n0)
  assert(n1 == 1 and why1:find("TSM"), "TSM a 0,4 al día: 1 y dice por qué, salió " .. n1)
  assert(n2 == 5, "TSM a 12 al día de 5 en 5: 5 fabricaciones, salió " .. n2)
  assert(n3 == 10, "TSM con mucha venta no sube el tope, salió " .. n3)
  assert(B(0.4, 1, "watch") == 1, "ojo y TSM bajo: 1")
  log[#log+1] = "     lote con TSM: " .. why1
  ES:SelectPage("home")
  ES.GetProfessionSkill, ES.IsRecipeKnown = realSkill, realKnown
  ES.db.earnMinProfit = nil
  ES.Earn.VENDOR_MIN_GPH = savedVGPH
  ES.Earn:Clear()
end)
step("sin contabilidad ni precios aprendidos de tus ventas", function()
  assert(ES.Books == nil, "la contabilidad del dinero debería haberse quitado")
  -- Ya no se aprende el precio del vendedor de tus ventas (dos cobradas juntas
  -- dejaban el doble: Barbaric Leggings a 63s 02c, CurseForge): ni el código, ni lo
  -- que quedara guardado de versiones anteriores
  assert(ES.Ledger.NoteSale == nil and ES.Ledger.ChargeSale == nil and ES.Ledger.OnMoney == nil, "queda el código que aprendía de las ventas")
  local savedSeen = ES.db.sellSeen
  ES.db.sellSeen = { [5963] = { price = 6302, time = 0, ok = true } }
  local data = ES.Data.SellPrices[5963]
  local price = ES:VendorSellPrice(5963)
  assert(price ~= 6302 and (price == data or price == select(11, GetItemInfo(5963))),
    "un precio aprendido de versiones anteriores todavía cuenta: " .. tostring(price))
  ES.db.sellSeen = savedSeen
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
  -- Mismo orden fijo que la portada (ES.PROFESSIONS)
  local porder, want = {}, {}
  for _, c in ipairs(ES.patternsPage.cards) do if c.key then porder[#porder + 1] = c.key end end
  for _, learnedPass in ipairs({ true, false }) do
    for _, pr in ipairs(ES.PROFESSIONS) do
      local has = ES.Data[pr.key] and ES:GetProfessionSkill(ES.Data[pr.key].skillLine) ~= nil
      if ES.Data[pr.key] and has == learnedPass then want[#want + 1] = pr.key end
    end
  end
  assert(table.concat(porder, ",") == table.concat(want, ","), "orden de Patterns: " .. table.concat(porder, ","))
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
  -- Beneficio solo al vendedor (Discord): ordena y pinta con él
  ES.db.collection.vendorProfit, ES.db.collection.sort = true, "profit"
  ES:RenderCollection(cf)
  local market = ES.Planner:RecipeMarket(ES.Data.Leatherworking, {})
  for _, e in ipairs(market) do
    if e.profit then assert(e.profitVendor and e.profitVendor <= e.profit + 0.01, "beneficio al vendedor: " .. tostring(e.profitVendor)) break end
  end
  ES.db.collection.vendorProfit = nil
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
  -- Sin Auctionator, Escanear lo pide el propio addon (aquí se cancela en seguida)
  f.scanButton.SetEnabled = function(self, on) self._enabled = on and true or false end
  local started
  QueryAuctionItems = function(...) if select(7, ...) then started = true end end
  GetNumAuctionItems = function() return 0 end
  CanSendAuctionQuery = function() return true, true end
  Auctionator = nil
  ES:RefreshScanButtons()
  assert(f.scanButton._enabled == true, "sin Auctionator el botón Escanear debe poder pulsarse")
  local after = C_Timer.After
  C_Timer.After = function() end
  ES.Scanner:Start()
  assert(started and ES.Scanner:IsBusy(), "sin Auctionator el addon debe pedir su escaneo")
  ES.Scanner:Abort()
  C_Timer.After = after
  ES.db.lastFullScan, ES.db.lastScanFail, ES.countdownTicking = nil, nil, false
  started = false
  -- Con Auctionator: Escanear lanza su escaneo (con la API clásica) y el addon lo lee
  local atrWaiting = false
  Auctionator = { State = { FullScanFrameRef = {
    InitiateScan = function() QueryAuctionItems("", nil, nil, 0, nil, nil, true, false, nil) end,
    CanInitiate = function() return not atrWaiting end,
  } } }
  ES:RefreshScanButtons()
  assert(f.scanButton._text == "Escanear", "sin escaneos previos se puede escanear")
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
  -- El servidor no responde: se abandona a los 120 s con la cuenta atrás ya corriendo
  ES.db.lastFullScan = { [ES:CharKey()] = NOW - 16 * 60 }
  ES:RefreshScanButtons()
  assert(f.scanButton._text == "Escanear", "pasados 15 min se puede escanear")
  ES.Scanner:Start()
  assert(ES.Scanner:IsBusy(), "debería pedir")
  clock = clock + 61 pending()
  assert(ES.Scanner:IsBusy(), "a los 60 s aún debe esperar (reinos llenos tardan)")
  clock = clock + 60 pending()
  assert(not ES.Scanner:IsBusy(), "debería abandonar sin respuesta")
  assert(f.scanButton._text:match("^1[345]:%d%d$"), "cuenta atrás tras no responder: " .. tostring(f.scanButton._text))
  -- Si Auctionator aún no deja otro escaneo, no se pide
  ES.db.lastFullScan, ES.db.lastScanFail = nil, nil
  atrWaiting = true
  started = false
  ES:RefreshScanButtons()
  assert(f.scanButton._enabled == false, "con Auctionator en su cuenta atrás el botón no debe poder pulsarse")
  ES.Scanner:Start()
  assert(not started and not ES.Scanner:IsBusy(), "con Auctionator en su cuenta atrás no debe pedirse")
  GetTime = realGetTime
  C_Timer.After = function() end
  ES.db.lastFullScan, ES.countdownTicking = nil, false
  QueryAuctionItems, CanSendAuctionQuery, GetNumAuctionItems, Auctionator = nil, nil, nil, nil
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
step("material que sale más barato fabricar pero da puntos: se explica por qué se compra", function()
  -- Discord: Heavy Blasting Powder (3s 68c fabricada, 4s 22c en la AH) se compraba para
  -- Heavy Dynamite. Las dos dan puntos en 125-145: cada pólvora fabricada quita un punto a
  -- la dinamita, que es lo que gana dinero. El tooltip solo explicaba el caso contrario
  local P, eng = ES.Planner, ES.Data.Engineering
  P.Annotate(eng)
  local powder = eng.recipes[3945]
  local plan = { steps = { { id = 3946, recipe = eng.recipes[3946], from = 125, to = 145, reagents = { { item = 4377 } } } } }
  local st = P.CraftTakesPoints(plan, 4377, powder)
  assert(st and st.id == 3946, "la pólvora aún da puntos donde la gasta la dinamita: debería decirlo")
  plan.steps[1].from = 145
  assert(P.CraftTakesPoints(plan, 4377, powder) == nil, "a 145 la pólvora ya está gris: fabricarla no quita puntos")
  plan.steps[1].from, plan.steps[1].reagents = 125, { { item = 2592 } }
  assert(P.CraftTakesPoints(plan, 4377, powder) == nil, "ningún paso gasta la pólvora: nada que explicar")
end)
step("recetas de instructores de un rango superior (Green Iron Bracers a 144, Discord)", function()
  -- Forever subió Green Iron Bracers (140) a los instructores de Experto (Bengus, Saru) y
  -- Artesano (Brikk Keencraft): con Oficial (tope 150) nadie te la enseña. La ruta 144-150
  -- mandaba a Booty Bay a aprenderla, y al quitarla no quedaba alternativa
  local P, bs = ES.Planner, ES.Data.Blacksmithing
  P.Annotate(bs)
  local gib, legs, hammer = bs.recipes[3501], bs.recipes[3506], bs.recipes[9985]
  assert(gib.rankCap == 225 and legs.rankCap == 225, "Green Iron Bracers/Leggings: piden Experto")
  assert(not hammer.rankCap, "Bronze Warhammer la enseña el de Oficial: sin requisito de rango")
  -- Solo las Green Iron (visto en el juego): las demás que los datos dan a instructores de
  -- un rango superior, sin ningún caso visto, siguen igual (Nightscape Pants, Heavy Mithril)
  P.Annotate(ES.Data.Leatherworking)
  assert(not ES.Data.Leatherworking.recipes[10548].rankCap and not bs.recipes[9959].rankCap,
    "la regla de rango solo para Green Iron Bracers/Helm/Leggings")
  -- A quién manda la flecha: los de Experto (Saru, Bengus), no Brikk (Artesano, Booty Bay)
  local tr = {}
  for _, npc in ipairs(gib.rankTr or {}) do tr[npc] = true end
  assert(tr[3355] and tr[4258] and not tr[2836], "Green Iron Bracers: a Saru o Bengus, no a Brikk Keencraft")
  local savedKnown, savedScans = ES.IsRecipeKnown, ES.db.scans
  ES.IsRecipeKnown = function() return false end
  assert(P.LearnSkill(gib, { from = 144, to = 150, cap = 150 }) == nil, "con Oficial y objetivo 150 no se puede aprender")
  assert(P.LearnSkill(gib, { from = 144, to = 150 }) == nil, "sin tope conocido, a 144 se supone Oficial")
  assert(P.LearnSkill(gib, { from = 144, to = 150, cap = 225 }) == 140, "con Experto sí, a 140")
  -- Si la ruta pasa de 150 entrena Experto (desde 125): desde entonces sí
  assert(P.LearnSkill(gib, { from = 100, to = 200, cap = 150 }) == 140, "la ruta que entrena Experto sí la usa")
  assert(P.LearnSkill(legs, { from = 100, to = 200, cap = 150 }) == 130, "Green Iron Leggings: a 130 con Experto")
  assert(P.LearnSkill(hammer, { from = 144, to = 150, cap = 150 }) == 100, "las demás, igual que antes")
  -- La ruta 144-150 con Oficial: sin las de Experto, y llega a 150 (también quitando una)
  local items = {}
  for _, r in pairs(bs.recipes) do
    for _, rq in ipairs(r.r or {}) do items[rq[1]] = { minUnit = 100, quantity = 1000 } end
  end
  ES.db.scans = { [ES:RealmKey()] = { time = time(), items = items } }
  local opts = ES:PlanOptions("Blacksmithing", 144, 150, 150)
  local plan = P:Plan(bs, opts)
  assert(not plan.stoppedAt and #plan.steps > 0, "la ruta 144-150 debería llegar a 150")
  for _, st in ipairs(plan.steps) do
    assert(not st.recipe.rankCap, "la ruta usa una receta que pide Experto: " .. st.recipe.name)
  end
  opts = ES:PlanOptions("Blacksmithing", 144, 150, 150)
  opts.excluded = { [plan.steps[1].id] = true }
  local other = P:Plan(bs, opts)
  assert(not other.stoppedAt and #other.steps > 0 and other.steps[1].id ~= plan.steps[1].id,
    "quitando la receta de la ruta debería salir otra hasta 150")
  -- Ruta empezada: sus precios guardados son solo los de sus objetos (RoutePrices). Las
  -- alternativas de cada paso se miran con el último escaneo: con solo los guardados
  -- ninguna otra receta tenía precio ("ninguna otra sirve sin cambiar el resto")
  local ids = {}
  for _, st in ipairs(plan.steps) do
    for _, rq in ipairs(st.recipe.r) do ids[rq[1]] = true end
    if st.recipe.out then ids[st.recipe.out[1]] = true end
  end
  for _, tl in ipairs(plan.tools or {}) do ids[tl.item] = true end
  local lockOpts = ES:PlanOptions("Blacksmithing", 144, 150, 150)
  lockOpts.prices = {}
  for id in pairs(ids) do lockOpts.prices[id] = items[id] end
  lockOpts.forced, lockOpts.via, lockOpts.fullInfo = plan.choice, plan.ctx.via, true
  local locked = P:Plan(bs, lockOpts)
  local st = locked.steps[1]
  local function CountAlts()
    local n = 0
    for _, id in ipairs(P.AlternativeCandidates(bs, locked, st)) do
      if P.EvaluateAlternative(bs, locked, st, id) then n = n + 1 end
    end
    return n
  end
  locked.altPrices = lockOpts.prices -- (como antes: solo los precios guardados)
  local before = CountAlts()
  locked.altPrices = nil
  local after = CountAlts()
  assert(after > 0 and after > before, "ruta empezada: el paso debería tener alternativas (" .. before .. " -> " .. after .. ")")
  assert(locked.altPrices and locked.altPrices[next(lockOpts.prices)] == lockOpts.prices[next(lockOpts.prices)],
    "lo de la ruta, con sus precios guardados")
  log[#log+1] = string.format("     144-150 con Oficial: %s; ruta empezada: %d -> %d alternativas", st.recipe.name, before, after)
  ES.IsRecipeKnown, ES.db.scans = savedKnown, savedScans
end)
step("sin variables globales sueltas", function()
  assert(#LEAKS == 0, "globales: " .. table.concat(LEAKS, ", "))
end)
step("aviso de recetas de botín en la AH: una vez al día por receta", function()
  -- Ahora hay un escaneo en cada visita a la AH (el de otro addon): el mismo aviso
  -- no tiene que repetirse cada vez
  local savedSkill, savedKnown, savedPrint, savedAlerts = ES.GetProfessionSkill, ES.IsRecipeKnown, ES.Print, ES.db.scrollAlerts
  ES.GetProfessionSkill = function(_, line) if line == ES.Data.Leatherworking.skillLine then return 150, 225 end end
  ES.IsRecipeKnown = function() return false end
  local printed = {}
  ES.Print = function(_, msg) printed[#printed + 1] = msg end
  ES.db.scrollAlerts = nil
  local items = {}
  for _, r in pairs(ES.Data.Leatherworking.recipes) do
    if r.scroll then items[r.scroll] = { minUnit = 5000, quantity = 1 } end
  end
  local scan = { items = items }
  ES.Collection:AlertScan(scan)
  local first = #printed
  ES.Collection:AlertScan(scan)
  ES.GetProfessionSkill, ES.IsRecipeKnown, ES.Print = savedSkill, savedKnown, savedPrint
  if first > 0 then
    assert(#printed == first, "el aviso de recetas de botín se repitió en el siguiente escaneo")
    log[#log+1] = "     aviso de recetas de botín: " .. tostring(printed[1]):sub(1, 90)
  else
    log[#log+1] = "     (ninguna receta de botín sin vendedor ni misión en los datos de prueba)"
  end
  ES.db.scrollAlerts = savedAlerts
end)
step("recetas de vendedor con stock limitado (lim)", function()
  -- Raptor Hide Harness: solo la vende Tunkk, 1 y repone con el tiempo
  local src = ES.Data.ItemSources
  assert(src[13287] and src[13287].lim == true, "Raptor Hide Harness debería marcarse con stock limitado")
  -- Hilo y tintes de los vendedores de materiales: siempre hay
  assert(src[2320] and not src[2320].lim, "Coarse Thread no tiene stock limitado")
  -- Solo se marca lo que tiene vendedor
  local n = 0
  for id, s in pairs(src) do
    if s.lim then
      n = n + 1
      assert(s.v and #s.v > 0, "lim sin vendedor: " .. id)
    end
  end
  log[#log+1] = "     " .. n .. " objetos con stock limitado en todos sus vendedores"
  -- Opción: por defecto se cuenta con el vendedor (lo más barato); desactivada, no
  local WP = ES.Waypoints
  local harness = ES.Data.Leatherworking.recipes[4096]
  -- Misiones que dan recetas: qué piden entregar y cuántas hay antes (CurseForge:
  -- Wild Leather Leggings pide 2 Turtle Scale Helms, 2 Bracers y 2 Wildvines)
  local wl = ES.Data.Quests[2859]
  assert(wl and tostring(wl[5]):find("Turtle Scale Helms") and wl[6] == 4, "Wild Leather Leggings: falta lo que pide o su cadena")
  assert(ES.Waypoints.Quest(2859).asks == wl[5], "la misión no lleva lo que pide")
  -- Su vendedor es Androd Fadran (Alianza), no Tunkk: Wowhead lo tenía al revés
  assert(src[13287].v[1] == 2816 and src[13288].v[1] == 2819, "Raptor Hide Harness la vende Androd Fadran y el Belt, Tunkk")
  local VENDOR = src[13287].v[1]
  local savedSide = ES.Data.NPCs[VENDOR][2]
  ES.Data.NPCs[VENDOR][2] = "" -- (de los dos bandos para la prueba)
  local prices = { [13287] = { minUnit = 150000, listings = 2 } }
  local on = WP.RecipeSource(harness, prices, nil, nil)
  if on and on.vendors[1] then
    assert(on.limited and on.best.kind == "vendor", "con la opción por defecto, la receta se compra al vendedor (lo más barato)")
    local off = WP.RecipeSource(harness, prices, nil, true)
    assert(off.vendorsOff and off.best.kind == "ah", "sin vendedores de stock limitado, la receta sale de la AH")
    local none = WP.RecipeSource(harness, {}, nil, true)
    assert(not none.best, "sin vendedor ni AH no hay de dónde sacarla")
    log[#log+1] = "     opción: vendedor por defecto (" .. on.best.kind .. "), sin stock limitado: " .. off.best.kind
  else
    log[#log+1] = "     (sin datos de vendedores en la prueba: la opción no se comprueba aquí)"
  end
  ES.Data.NPCs[VENDOR][2] = savedSide
end)
step("añadir a la lista de compra: sonido y la pestaña brilla", function()
  local savedFlash, savedPrint, savedChar = ES.FlashTab, ES.Print, ES.charData
  local flashed
  ES.FlashTab = function(_, key, sound) flashed = { key, sound } end
  ES.Print = function() end
  ES.charData = { shopping = {} }
  ES:AddToShopping("calc", "Prueba", { { itemID = 2318, quantity = 5, unit = 10, source = "ah" } })
  local added = flashed
  flashed = nil
  ES:AddToShopping("calc", "Nada", {})
  ES.FlashTab, ES.Print, ES.charData = savedFlash, savedPrint, savedChar
  assert(added and added[1] == "shopping" and added[2], "al añadir no suena ni brilla la pestaña")
  assert(not flashed, "sin nada que añadir no debería avisar")
end)
step("sin escaneo de la AH: la ruta dice que escanees", function()
  -- (Discord: "Can't level from...: X materials without price" en casi todas las
  -- profesiones; sin escaneo, lo que solo se compra en la AH no tiene precio)
  ES:GetMainFrame()
  local page
  for _, p in ipairs(ES.professionPages) do if p.profKey == "Leatherworking" then page = p end end
  local key = ES:RealmKey()
  local savedScan, savedLock = ES.db.scans[key], ES.db.prof.Leatherworking.lock
  ES.db.scans[key], ES.db.prof.Leatherworking.lock = nil, nil
  ES.lockedPlans = {}
  page.from = 100
  page.toBox._text = "200"
  ES:CalculatePlan(page)
  local status = tostring(page.status._text)
  ES.db.scans[key], ES.db.prof.Leatherworking.lock = savedScan, savedLock
  ES.lockedPlans = {}
  if page.plan and #page.plan.steps == 0 then
    assert(status:find("Escanear"), "sin escaneo, la ruta parada no dice que escanees: " .. status)
  end
  log[#log+1] = "     " .. status:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):sub(1, 150)
  ES:CalculatePlan(page)
end)
step("equipo que no fabricas: no se propone vender (opción)", function()
  local INV = ES.Inventory
  local crafted
  for _, r in pairs(ES.Data.Leatherworking.recipes) do if r.out then crafted = r.out[1] break end end
  local LOOT, GREYGEAR, MAT = 990001, 990002, 2318
  local savedInstant, savedData, savedNever, savedGear = GetItemInfoInstant, ES.GetItemData, ES.db.neverSell, ES.db.protectGear
  GetItemInfoInstant = function(id)
    if id == LOOT or id == GREYGEAR or id == crafted then return id, "Armor", "Leather", "INVTYPE_CHEST" end
    return id, "Trade Goods", "Leather", ""
  end
  ES.GetItemData = function(_, id) if id == GREYGEAR then return "Grey", 0, 1 end if id == LOOT then return "Green", 2, 1 end return savedData(ES, id) end
  ES.db.neverSell, ES.db.protectGear = {}, nil
  -- Por defecto (opción desactivada) se propone todo, también tu equipo ligado
  assert(INV.NeverSell(LOOT, true) == nil, "por defecto, el equipo ligado se propone vender")
  ES.db.protectGear = true -- (la opción, activada)
  -- Tu equipo: ligado o en un conjunto. Los verdes sin ligar se venden (es el oro)
  assert(INV.NeverSell(LOOT, true) == "gear", "el equipo ligado no se propone vender")
  assert(INV.NeverSell(LOOT, nil) == nil, "un verde sin ligar sí se propone vender")
  local SETITEM = 990003
  local savedSets = C_EquipmentSet
  C_EquipmentSet = { GetEquipmentSetIDs = function() return { 1 } end, GetItemIDs = function() return { [5] = SETITEM, [6] = -1 } end }
  local savedGetTime = GetTime
  GetTime = function() return 12345.5 end -- (la caché de conjuntos es por segundo)
  local savedInstant2 = GetItemInfoInstant
  GetItemInfoInstant = function(id) if id == SETITEM then return id, "Armor", "Cloth", "INVTYPE_ROBE" end return savedInstant2(id) end
  local savedData2 = ES.GetItemData
  ES.GetItemData = function(_, id) if id == SETITEM then return "Healer Robe", 2, 1 end return savedData2(ES, id) end
  assert(INV.NeverSell(SETITEM, nil) == "gear", "lo de un conjunto del gestor de equipo no se propone vender")
  C_EquipmentSet, GetTime, GetItemInfoInstant, ES.GetItemData = savedSets, savedGetTime, savedInstant2, savedData2
  assert(INV.NeverSell(crafted, true) == nil, "lo que fabricas sí se vende")
  assert(INV.NeverSell(GREYGEAR, true) == nil, "el equipo gris sí se vende")
  assert(INV.NeverSell(MAT, true) == nil, "los materiales sí se venden")
  -- Clic derecho en No se venden: ese sí se puede vender
  local savedPrint = ES.Print
  ES.Print = function() end
  INV.SetNeverSell(LOOT, false)
  assert(INV.NeverSell(LOOT, true) == nil and ES.db.neverSell[LOOT] == false, "con clic derecho se puede permitir uno")
  ES.db.neverSell = {}
  -- La casilla: desmarcada, el equipo se propone como lo demás
  local op = ES:OptionsWindow()
  op._scripts.OnShow(op)
  local gcb, ccb, mcb
  for _, cb in ipairs(op.checks) do
    if cb.option.key == "protectGear" then gcb = cb elseif cb.option.key == "noChatAlerts" then ccb = cb elseif cb.option.key == "minimap" then mcb = cb end
  end
  assert(gcb and gcb:GetChecked(), "con la opción activada, la casilla sale marcada")
  gcb:SetChecked(false)
  gcb._scripts.OnClick(gcb)
  assert(ES.db.protectGear == nil and INV.NeverSell(LOOT, true) == nil, "desmarcada, tu equipo ligado se propone vender")
  gcb:SetChecked(true)
  gcb._scripts.OnClick(gcb)
  assert(ES.db.protectGear == true and INV.NeverSell(LOOT, true) == "gear", "marcada otra vez, el equipo vuelve a protegerse")
  -- Avisos del chat: desmarcados, el de recetas de botín no sale
  assert(ccb and ccb:GetChecked(), "los avisos del chat salen activados por defecto")
  ccb:SetChecked(false)
  ccb._scripts.OnClick(ccb)
  local said = 0
  ES.Print = function() said = said + 1 end
  local items = {}
  for _, r in pairs(ES.Data.Leatherworking.recipes) do if r.scroll then items[r.scroll] = { minUnit = 5000, quantity = 1 } end end
  local savedAlerts = ES.db.scrollAlerts
  ES.db.scrollAlerts = nil
  ES.Collection:AlertScan({ items = items })
  ES:AnnounceRouteDrift()
  assert(said == 0, "con los avisos desactivados sale algo en el chat")
  ccb:SetChecked(true)
  ccb._scripts.OnClick(ccb)
  assert(ES.db.noChatAlerts == nil, "los avisos no se vuelven a activar")
  ES.db.scrollAlerts = savedAlerts
  -- Botón del minimapa: la casilla usa el mismo sitio que /cj minimap
  ES.db.minimap = ES.db.minimap or {}
  local savedHide = ES.db.minimap.hide
  ES.db.minimap.hide = nil
  op._scripts.OnShow(op)
  assert(mcb and mcb:GetChecked(), "el botón del minimapa sale marcado")
  mcb:SetChecked(false)
  mcb._scripts.OnClick(mcb)
  assert(ES.db.minimap.hide == true, "desmarcada, el botón del minimapa se esconde")
  ES.db.minimap.hide = savedHide
  ES.Print = savedPrint
  GetItemInfoInstant, ES.GetItemData, ES.db.neverSell, ES.db.protectGear = savedInstant, savedData, savedNever, savedGear
  log[#log+1] = "     equipo de botín protegido; fabricado, gris y materiales se venden; avisos y minimapa con su casilla"
end)
step("botón del minimapa con LibDBIcon", function()
  -- La librería estándar (Leatrix Plus avisaba de un botón propio); la posición de
  -- antes (angle) se conserva como minimapPos
  ES.db.minimap = { angle = 200 }
  -- (el dibujo del botón es de LibDBIcon y necesita frames reales: aquí solo se
  -- comprueba que se registra con nuestros datos)
  local icon = LibStub("LibDBIcon-1.0")
  local savedReg, registered = icon.Register, nil
  icon.Register = function(self, name, object, db)
    registered = { name = name, object = object, db = db }
    self.objects[name] = CreateFrame("Button")
  end
  ES.CreateMinimapButton()
  icon.Register = savedReg
  assert(icon:IsRegistered("CraftersJournal") and registered and registered.db == ES.db.minimap
    and registered.object.icon == ES.ICON and registered.object.OnClick, "no se registró en LibDBIcon con nuestros datos")
  assert(ES.db.minimap.minimapPos == 200 and ES.db.minimap.angle == nil, "posición antigua: " .. tostring(ES.db.minimap.minimapPos))
  assert(LibStub("LibDataBroker-1.1"):GetDataObjectByName("CraftersJournal"), "falta el objeto de LibDataBroker")
  SlashCmdList.CRAFTERSJOURNAL("minimap")
  assert(ES.db.minimap.hide, "/cj minimap lo oculta")
  SlashCmdList.CRAFTERSJOURNAL("minimap")
  assert(not ES.db.minimap.hide, "/cj minimap lo vuelve a enseñar")
  -- Volver a crearlo (otra carga) no lo registra dos veces
  ES.CreateMinimapButton()
end)
step("alemán y francés: completos, con el mismo formato y nombres del juego", function()
  local function Tokens(s)
    local t = {}
    for tok in s:gmatch("%%[-+ #0]*%d*%.?%d*[dsfxXq%%]") do t[#t + 1] = tok end
    for tok in s:gmatch("|c%x%x%x%x%x%x%x%x") do t[#t + 1] = "c" end
    for _ in s:gmatch("|r") do t[#t + 1] = "r" end
    for _ in s:gmatch("|T") do t[#t + 1] = "T" end
    return table.concat(t, " ")
  end
  for _, lang in ipairs({ "de", "fr" }) do
    local loc = ES.Locales[lang]
    assert(loc, "falta ES.Locales." .. lang)
    local missing, extra, bad = {}, {}, {}
    for key, en in pairs(ES.Locales.en) do
      local v = loc[key]
      if not v then missing[#missing + 1] = key
      elseif Tokens(v) ~= Tokens(en) then bad[#bad + 1] = key .. " -> " .. v end
    end
    for key in pairs(loc) do if not ES.Locales.en[key] then extra[#extra + 1] = key end end
    assert(#missing == 0, lang .. ": " .. #missing .. " sin traducir: " .. table.concat(missing, " | "):sub(1, 400))
    assert(#extra == 0, lang .. ": " .. #extra .. " claves que el inglés no tiene: " .. table.concat(extra, " | "):sub(1, 400))
    assert(#bad == 0, lang .. ": formato distinto del inglés: " .. table.concat(bad, " | "):sub(1, 400))
  end
  -- Cambiar a alemán: textos, recetas y objetos en alemán; coma decimal
  local savedLang, savedDBLang = ES.lang, ES.db.lang
  ES:SetLanguage("de")
  assert(ES.L["Lista de compra"] == "Einkaufsliste", "texto en alemán")
  assert(ES.Data.Leatherworking.recipes[2149].name == "Handgenähte Lederstiefel", "receta en alemán: " .. tostring(ES.Data.Leatherworking.recipes[2149].name))
  assert(ES.Num(2.5) == "2,5", "coma decimal en alemán")
  -- Un texto que el alemán no tenga sale en inglés, no en español
  ES.Locales.en["__prueba__"] = "english"
  assert(ES.L["__prueba__"] == "english", "sin traducción al alemán, el inglés")
  ES.Locales.en["__prueba__"] = nil
  ES:SetLanguage("fr")
  assert(ES.L["Lista de compra"] == "Liste de courses", "texto en francés")
  assert(ES.Data.Leatherworking.recipes[2149].name ~= "Handgenähte Lederstiefel", "al pasar a francés no se queda el alemán")
  ES:SetLanguage("en")
  assert(ES.Data.Leatherworking.recipes[2149].name == "Handstitched Leather Boots", "de vuelta al inglés, el nombre original: " .. tostring(ES.Data.Leatherworking.recipes[2149].name))
  assert(ES.Num(2.5) == "2.5", "punto decimal en inglés")
  -- Como estaba: idioma y textos de antes, recetas con su nombre original (inglés),
  -- que es como las buscan las pruebas de después
  ES.lang, ES.db.lang = savedLang, savedDBLang
  ES.ApplyLocalization()
  if ES.RebuildMainFrame then ES:RebuildMainFrame() end
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
    if cf.profKey == "Tailoring" then
      -- Buscar tras bajar en la lista: antes las filas quedaban fuera de la vista (vacía)
      local sc = cf.scroll
      sc._vs = 0
      sc.GetVerticalScroll = function(self) return self._vs end
      sc.SetVerticalScroll = function(self, v) self._vs = v end
      sc.GetHeight = function() return 400 end
      sc._vs = 6000
      cf.search:SetText("bag")
      cf.search._scripts.OnTextChanged(cf.search)
      local drawn = 0
      for _, row in ipairs(cf.rows) do if row._shown and row.entry then drawn = drawn + 1 end end
      assert(cf.shown > 0, "'bag' no encuentra recetas de sastrería")
      assert(sc._vs == 0 and drawn > 0, "buscar tras bajar deja la lista vacía: scroll " .. sc._vs .. ", filas " .. drawn)
      log[#log+1] = string.format("     buscar 'bag' tras bajar: %d recetas, %d filas a la vista", cf.shown, drawn)
      cf.search:SetText("")
      cf.search._scripts.OnTextChanged(cf.search)
    end
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
  -- Uno de fondo por tarjeta + el dibujo de las secundarias (cocina y primeros auxilios)
  assert(#atlasAsked == ES.homePage.shownCards + 2, "atlas pedidos: " .. #atlasAsked)
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
  -- Orden: secciones (tuyas / demás) y dentro el fijo de ES.PROFESSIONS; el mismo en Patterns
  local order = {}
  for i, c in ipairs(ES.homePage.cards) do if c._shown ~= false and c.key then order[#order + 1] = c.key end end
  -- Primero las que tienes, luego las demás; en cada sección, el orden de ES.PROFESSIONS
  local want = {}
  for _, learnedPass in ipairs({ true, false }) do
    for _, p in ipairs(ES.PROFESSIONS) do
      local has = ES.Data[p.key] and ES:GetProfessionSkill(ES.Data[p.key].skillLine) ~= nil
      if has == learnedPass then want[#want + 1] = p.key end
    end
  end
  assert(table.concat(order, ",") == table.concat(want, ","), "orden de la portada: " .. table.concat(order, ","))
  log[#log+1] = "     orden: " .. table.concat(order, ", ")
  local lw
  for _, c in ipairs(ES.homePage.cards) do if c.key == "Leatherworking" then lw = c end end
  assert(tostring(lw.level._text):find("%d+|r / %d+"), "nivel no mostrado: " .. tostring(lw.level._text))
  -- Pestañas laterales: cada una abre su página y queda marcada
  local mf = ES:GetMainFrame()
  assert(#mf.tabs == 9, "pestañas: " .. #mf.tabs)
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
  -- (un paso de la ruta, no "Fabrica N×" de un material: esos se prueban aparte)
  for _, l in ipairs(page.lines) do if l.craftCount and not l.skipTip then craftLine = l break end end
  assert(craftLine, "con la opción por defecto, el clic en un paso debería fabricar")
  -- Ventana de la profesión cerrada: el primer clic solo la abre (fabricar ahí hacía
  -- solo 1, y fabricar después desde un temporizador lo bloquea el juego). El aviso,
  -- una vez aunque se pulse varias veces
  local printed, savedPrint = {}, ES.Print
  ES.Print = function(_, msg) printed[#printed + 1] = msg end
  craftLine.onClick()
  craftLine.onClick()
  ES.Print = savedPrint
  assert(opened == page.plan.steps[1].id and not crafted, "con la ventana cerrada debería solo abrir la receta")
  assert(#printed == 1, "el aviso de pulsar otra vez se repite: " .. #printed)
  -- Abierta y cargada (Forever no da numAvailable): el clic fabrica lo que falta
  ProfessionsFrame = CreateFrame("Frame")
  ProfessionsFrame:Show()
  C_TradeSkillUI.GetRecipeInfo = function() return { learned = true } end
  -- Sin materiales: no fabrica y dice cuál falta (antes, "Fabricando N" igualmente)
  local savedCount = ES.ItemCount
  ES.ItemCount = function() return 0 end
  printed = {}
  ES.Print = function(_, msg) printed[#printed + 1] = msg end
  craftLine.onClick()
  assert(not crafted and printed[1] and printed[1]:find("te falta"), "sin materiales: " .. tostring(printed[1]))
  -- Materiales para 1: fabrica 1 y dice que falta para el resto
  local r = page.plan.steps[1].recipe
  local per = {}
  for _, rq in ipairs(r.r) do per[rq[1]] = rq[2] end
  ES.ItemCount = function(_, id) return per[id] or 0 end
  printed = {}
  craftLine.onClick()
  if page.plan.steps[1].crafts > 1 then
    assert(crafted and crafted[2] == 1 and printed[1]:find("de " .. page.plan.steps[1].crafts), "con material para 1: " .. tostring(printed[1]))
  end
  ES.ItemCount = function() return 9999 end
  ES.Print = savedPrint
  crafted, opened = nil, nil
  craftLine.onClick()
  ES.ItemCount = savedCount
  ProfessionsFrame = nil
  assert(opened == page.plan.steps[1].id, "el clic no abrió la receta del paso")
  assert(crafted and crafted[1] == page.plan.steps[1].id and crafted[2] == page.plan.steps[1].crafts, "el clic no fabricó lo del paso")
  log[#log+1] = "     fabricar: " .. tostring(craftLine.title)
  -- Sin panel en Opciones: pulsar un paso siempre fabrica
  assert(ES.optionsPanel == nil, "no debería haber nada en Opciones")
  -- Una receta que no sabes: el clic solo abre la receta (no hay nada que fabricar)
  ES.IsRecipeKnown = function() return false end
  ES:RenderPlan(page)
  crafted, opened = nil, nil
  for _, l in ipairs(page.lines) do assert(not l.craftCount, "sin saber la receta no debería fabricar") end
  for _, l in ipairs(page.lines) do if l.onClick and l.item then l.onClick() break end end
  assert(opened and not crafted, "sin saber la receta el clic solo abre la receta")
  ES.IsRecipeKnown, C_TradeSkillUI = savedKnown, nil
  ES:RenderPlan(page)
  -- ✕ en un paso: la receta sale de la ruta y una fila permite recuperarla
  local firstStep = page.plan.steps[1].id
  local skipRow
  -- (la de un paso de receta, no la de fabricar un material: esa lo compra hecho)
  for _, row in ipairs(page.rows) do if row.onSkip and not row.skipTip and row._shown ~= false then skipRow = row break end end
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
  -- (con las bolsas llenas, por tramos todo el primer tramo está en "Ya lo tienes")
  bags = 0
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
  C_AuctionHouse = { MakeItemKey = function(id) return { itemID = id } end,
    GetNumCommoditySearchResults = function() return 0 end }
  ES:OpenAuctionBuy(ahLine.item, 7)
  -- Sin resultados aún no pone nada (ponerla antes la hacía parpadear: Blizzard la reinicia)
  assert(selected and selected.itemID == ahLine.item and qtySet == nil, "no abrió la compra, o puso cantidad sin resultados")
  -- Llegan los resultados: solo 5 baratas (4s) y luego a 31s: pone 5, no 7
  local rows = { { unitPrice = 400, quantity = 3 }, { unitPrice = 450, quantity = 2 },
    { unitPrice = 3100, quantity = 50 } }
  C_AuctionHouse.GetNumCommoditySearchResults = function() return #rows end
  C_AuctionHouse.GetCommoditySearchResultInfo = function(_, i) return rows[i] end
  ES.AuctionState.applyBuy()
  assert(qtySet == 5, "debería poner solo las baratas, puso " .. tostring(qtySet))
  -- Blizzard vuelve a poner 1 justo después (al refrescar la compra): se vuelve a poner
  do
    local display = AuctionHouseFrame.CommoditiesBuyFrame.BuyDisplay
    display.GetQuantitySelected = function() return qtySet end
    local timers, savedAfter = {}, C_Timer.After
    C_Timer.After = function(_, fn) timers[#timers + 1] = fn end
    ES.AuctionState.buying.holding = nil
    ES.AuctionState.applyBuy()
    qtySet = 1 -- (Blizzard la reinicia)
    for _ = 1, 3 do
      local run = timers
      timers = {}
      for _, fn in ipairs(run) do fn() end
    end
    C_Timer.After = savedAfter
    display.GetQuantitySelected = nil
    assert(qtySet == 5, "Blizzard la dejó en 1 y no se volvió a poner: " .. tostring(qtySet))
  end
  -- Otro clic en el mismo material al momento: no vuelve a buscar
  selected = nil
  ES:OpenAuctionBuy(ahLine.item, 7)
  assert(selected == nil, "un doble clic vuelve a lanzar la búsqueda")
  -- Con un plan que acepta 31s, las 7
  ES.AuctionState.buying = nil
  ES:OpenAuctionBuy(ahLine.item, 7, 3100)
  assert(qtySet == 7, "con el precio del plan por encima debería poner todas, puso " .. tostring(qtySet))
  rows[1].numOwnerItems = 3 -- las tuyas no cuentan
  ES.AuctionState.buying = nil
  ES:OpenAuctionBuy(ahLine.item, 7)
  assert(qtySet == 2, "las propias no deberían contar como baratas, puso " .. tostring(qtySet))
  -- El servidor pierde la búsqueda ("Buscando..." para siempre). Como Blizzard: abrir
  -- otra vez el material que ya está abierto no lo vuelve a pedir; solo tras Atrás.
  -- El addon tiene que hacer Atrás y abrirlo otra vez, como a mano
  local queries, current, mode = 0, nil, "browse"
  local timers = {}
  local savedAfter = C_Timer.After
  C_Timer.After = function(_, fn) timers[#timers + 1] = fn end
  AuctionHouseFrameDisplayMode = { Buy = "browse" }
  AuctionHouseFrame = {
    SelectBrowseResult = function(self, r)
      mode = "commodity"
      if current ~= r.itemKey.itemID then current = r.itemKey.itemID queries = queries + 1 end
    end,
    SetDisplayMode = function(self, m) mode = m current = nil end,
    CommoditiesBuyFrame = { IsShown = function() return mode == "commodity" end,
      BuyDisplay = { SetQuantitySelected = function(_, q) qtySet = q end } } }
  C_AuctionHouse.GetNumCommoditySearchResults = function() return 0 end -- la búsqueda se perdió
  ES.AuctionState.buying = nil
  ES:OpenAuctionBuy(ahLine.item, 7)
  assert(queries == 1, "la primera búsqueda no se pidió")
  for _ = 1, 4 do
    local run = timers
    timers = {}
    for _, fn in ipairs(run) do fn() end
  end
  assert(queries > 1, "con la búsqueda perdida no vuelve a pedirla (se queda en Buscando...)")
  -- Y un clic nuevo con la página del material abierta sin resultados también la pide
  local before = queries
  ES.AuctionState.buying = nil
  ES:OpenAuctionBuy(ahLine.item, 7)
  assert(queries == before + 1, "un clic con la búsqueda atascada no la vuelve a pedir")
  log[#log+1] = string.format("     AH: búsqueda perdida, la vuelve a pedir sola (%d peticiones)", queries)
  C_Timer.After, AuctionHouseFrameDisplayMode = savedAfter, nil
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
    -- (×5: la ruta de prueba vende lo fabricado con beneficio y con ×3 no movía su coste
    -- lo bastante, ES.DriftMatters)
    if c.minUnit then c.minUnit = c.minUnit * 5 end
    if c.ladder then
      c.ladder = {}
      for i, v in ipairs(e.ladder) do c.ladder[i] = (i % 2 == 1) and v * 5 or v end
    end
    newItems[id] = c
  end
  -- Ruta empezada sin escaneo nuevo: el botón se ve (que se sepa que existe), al día
  ES:RenderPlan(page)
  assert(page.pricesButton._shown ~= false and page.pricesUpToDate, "con la ruta empezada, Actualizar precios siempre a la vista")
  -- Con la ruta empezada, el botón del asistente junto a Dejar ruta (en la copia de
  -- desarrollo, que es la que cargan las pruebas)
  assert(page.assistButton._shown, "falta el botón del asistente junto a Dejar ruta")
  ES.db.scans[scanKey] = { time = oldScan.time + 3600, total = oldScan.total, unique = oldScan.unique, items = newItems }
  ES.lockedPlans = {}
  local frozen = ES:LockedPlan("Leatherworking")
  assert(math.abs(frozen.net - net) < 1, string.format("la ruta fijada cambió de coste con el escaneo nuevo: %d -> %d", net, frozen.net))
  ES:RenderPlan(page)
  assert(page.pricesButton._shown ~= false and not page.pricesUpToDate, "falta Actualizar precios con un escaneo nuevo")
  -- Con los precios ×3, lo que queda cuesta bastante más: se dice en la ruta y una
  -- sola vez en el chat (otro escaneo con los mismos precios de ruta no lo repite)
  assert(page.drift and page.drift.new > page.drift.old, "falta comparar lo que queda con los precios nuevos")
  assert(tostring(page.status._text):find("más"), "la ruta no dice cuánto más cuesta: " .. tostring(page.status._text))
  local savedPrint, said = ES.Print, {}
  ES.Print = function(_, msg) said[#said + 1] = msg end
  ES:AnnounceRouteDrift()
  ES.db.scans[scanKey].time = ES.db.scans[scanKey].time + 60
  ES:AnnounceRouteDrift()
  ES.Print = savedPrint
  local drift = 0
  for _, m in ipairs(said) do if tostring(m):find("Actualizar precios") then drift = drift + 1 end end
  assert(drift == 1, "el aviso del chat de precios nuevos salió " .. drift .. " veces")
  log[#log+1] = "     " .. tostring(page.status._text):gsub("|T[^|]+|t", "")
  -- Cambio pequeño: no se avisa
  assert(not ES.DriftMatters({ old = 100000, new = 110000 }) and ES.DriftMatters({ old = 100000, new = 130000 })
    and not ES.DriftMatters({ old = 1000, new = 5000 }), "umbral del aviso de precios nuevos")
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
  local knownBefore = ES.IsRecipeKnown
  ES.IsRecipeKnown = function() return false end
  ES:RefreshAfterSkill()
  local cur
  -- Sin saber aún la receta del paso, lo que toca es aprenderla (o, antes, fabricar
  -- el material que haga falta: "Fabrica N× ...")
  if s1.fee and s1.fee > 0 then
    for _, l in ipairs(page.lines) do if l.current then cur = l end end
    assert(cur and (cur.skipTip or (cur.title:find("Entrenar") or cur.title:find("Comprar"))) ~= nil,
      "sin saber la receta, el paso actual debería ser aprenderla: " .. tostring(cur and cur.title))
  end
  -- Sabiéndola y con lo que hay que fabricar antes ya hecho, el de fabricar, con lo que queda
  ES.IsRecipeKnown = function() return true end
  local countBefore = ES.ItemCount
  ES.ItemCount = function() return 1000000 end
  ES:RenderPlan(page)
  cur = nil
  for _, l in ipairs(page.lines) do if l.current then cur = l end end
  ES.IsRecipeKnown, ES.ItemCount = knownBefore, countBefore
  -- (lo que llevas en puntos, no en fabricaciones de esa receta: otras también suben)
  assert(cur and cur.sub:find("puntos") and cur.sub:find("fabricaciones más"), "falta el paso actual con lo que queda: " .. tostring(cur and cur.sub))
  local curRow
  for _, row in ipairs(page.rows) do if row._shown ~= false and row.title._text == cur.title then curRow = row end end
  log[#log+1] = "     paso actual: " .. tostring(cur.level) .. " · " .. tostring(cur.sub)
  -- Asistente (Assistant.lua): enseña la MISMA fila actual que la vista Ruta (mismo
  -- texto y mismo clic), sin la ventana abierta
  do
    local A = ES.Assistant
    local savedSkill, savedKnown, savedCount = ES.GetProfessionSkill, ES.IsRecipeKnown, ES.ItemCount
    local savedDetected, savedPlan = page.detected, page.plan
    ES.GetProfessionSkill = function() return newLevel, 300 end
    ES.IsRecipeKnown = function() return true end
    ES.ItemCount = function() return 1000000 end
    local ok, err = pcall(function()
    page.from, page.detected = newLevel, { rank = newLevel, cap = 300 }
    page.plan = ES:LockedPlan("Leatherworking") -- (como CalculatePlan con la ruta empezada)
    ES:RenderPlan(page)
    local big
    for _, l in ipairs(page.lines) do if l.current then big = l end end
    A.Update()
    local st, f = A.State(), A.Frame()
    assert(f and f._shown, "con una ruta empezada el asistente debería verse")
    assert(big and st.line and st.line.title == big.title and st.line.sub == big.sub and st.line.level == big.level,
      "el asistente no enseña la fila actual de la ruta: " .. tostring(st.line and (st.line.level .. " " .. st.line.sub))
      .. " / " .. tostring(big and (big.level .. " " .. big.sub)))
    assert(f.banner.title._text == (big.bannerTitle or big.title), "título del banner: " .. tostring(f.banner.title._text))
    assert(tostring(big.bannerTitle):find("Fabrica"), "el paso de fabricar del asistente lleva el verbo: " .. tostring(big.bannerTitle))
    -- (cada pintado crea sus funciones: se compara que sean las de la misma fila)
    assert(f.banner.onClick == st.line.onClick and f.banner.go == st.line.go
      and (big.onClick ~= nil) == (st.line.onClick ~= nil) and (big.go ~= nil) == (st.line.go ~= nil), "el clic del banner no es el de la fila")
    -- ◀ ▶: ojear otro paso no cambia el actual ni deja pulsarlo
    if #st.steps > st.index then
      A.Step(1)
      assert(st.peek == st.index + 1 and f.banner.onClick ~= st.line.onClick and f.banner.go == nil, "ojeando, el banner no debería hacer lo del paso")
      A.Peek(nil)
      assert(st.peek == nil and f.banner.onClick == st.line.onClick, "no vuelve al paso actual")
    end
    -- ×: cerrado para esta ruta (no vuelve a salir solo); quitarlo de nuevo lo saca
    A.Close()
    A.Update()
    assert(not f._shown, "cerrado para la ruta, no debería volver a salir")
    ES.db.prof.Leatherworking.assistantHidden = nil
    A.Update()
    assert(f._shown, "no vuelve a salir")
    -- En el tope de tu rango sin el siguiente: lo que toca es entrenarlo (también en la ruta grande)
    local rk = rebuilt.ranks[1]
    if rk and rk.cap - 75 < ES.db.prof.Leatherworking.lock.to then
      local prevCap = rk.cap - 75
      local lvl = math.max(rk.skill, prevCap)
      ES.GetProfessionSkill = function() return lvl, prevCap end
      page.from, page.detected = lvl, { rank = lvl, cap = prevCap }
      ES:RenderPlan(page)
      local currents, train = 0, nil
      for _, l in ipairs(page.lines) do if l.current then currents = currents + 1 train = l end end
      assert(currents == 1 and train.rankCap == rk.cap, "en el tope del rango, el paso actual debería ser entrenar: " .. tostring(train and train.title))
      A.Update()
      assert(st.line and st.line.rankCap == rk.cap, "el asistente no dice que entrenes el rango")
      log[#log+1] = string.format("     asistente en el tope (%d): %s", lvl, tostring(st.line.title):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
      -- Ya puedes entrenarlo pero aún no estás en tu tope. Si no estás a mitad de
      -- fabricar (a por una receta, a comprar, a empezar el paso siguiente): es el paso
      -- actual, en el mismo viaje. A mitad de fabricar: solo un aviso, para no cortar
      if rk.skill < prevCap then
        local function At(lvl)
          ES.GetProfessionSkill = function() return lvl, prevCap end
          page.from, page.detected = lvl, { rank = lvl, cap = prevCap }
          ES:RenderPlan(page)
          local cur, trainRow, n, trainAt, curAt = nil, nil, 0, nil, nil
          for i, l in ipairs(page.lines) do
            if l.current then cur, n, curAt = l, n + 1, i end
            if l.rankCap == rk.cap then trainRow, trainAt = l, i end
          end
          assert(n == 1, "un solo paso actual a " .. lvl .. ": " .. n)
          -- En la lista, entrenar va donde toca hacerlo: no delante de un recado pendiente
          -- (la receta de la AH, una compra), sino justo antes de fabricar
          if trainAt and curAt and trainRow ~= cur then
            local cstart = tonumber(tostring(cur.level):match("^(%d+)"))
            local mid = cur.stepRecipe and cstart and lvl > cstart
            assert(trainAt > curAt, string.format("a %d la fila de entrenar (%d) no debería ir antes del paso actual %s (%d)",
              lvl, trainAt, tostring(cur.title), curAt))
            if not mid then
              for i = curAt, trainAt - 1 do
                assert(not page.lines[i].stepRecipe or page.lines[i].done, "entrenar debería ir antes de empezar a fabricar")
              end
            end
          end
          local start = cur and tonumber(tostring(cur.level):match("^(%d+)"))
          return cur, trainRow, cur and cur.stepRecipe and start and lvl > start
        end
        -- Entrenar es el paso actual justo antes de empezar a fabricar (o si lo actual es
        -- aprender en el instructor); con recados pendientes o a mitad de fabricar, aviso
        local promoted, reminded = false, false
        for lvl = rk.skill, prevCap - 1 do
          local cur, trainRow = At(lvl)
          if cur.rankCap == rk.cap then
            -- En el instructor: aprende también las recetas que ya puedes y la ruta usa luego
            for _, l in ipairs(page.lines) do
              if l.trainerLearn and not l.done and (l.learnAt or 999) <= lvl then
                assert(l.learnNow, "a " .. lvl .. " en el instructor debería decir que aprendas también " .. tostring(l.learnName))
              end
            end
            if not promoted then
              promoted = true
              A.Update()
              assert(st.line and st.line.rankCap == rk.cap, "el asistente debería mandarte a entrenar ya")
            end
          else
            local start = tonumber(tostring(cur.level):match("^(%d+)"))
            assert(not (cur.stepRecipe and start and lvl <= start) and not cur.trainerLearn,
              "a " .. lvl .. " al empezar a fabricar (o en el instructor), entrenar debería ir antes: " .. tostring(cur.title))
            if not reminded then
              reminded = true
              -- Solo la nota en su fila: el paso actual no lo repite (la fila va justo detrás)
              assert(trainRow and tostring(trainRow.sub):find(tostring(prevCap)), "la fila de entrenar dice que ya puedes")
              assert(not tostring(cur.sub):find(tostring(prevCap)) and not tostring(cur.bannerSub or ""):find(tostring(prevCap)),
                "el paso actual no debería repetir lo de entrenar: " .. tostring(cur.bannerSub))
              A.Update()
              assert(not tostring(st.line.bannerSub or ""):find(tostring(prevCap)), "el asistente no debería repetirlo: " .. tostring(st.line.bannerSub))
            end
          end
          if promoted and reminded then break end
        end
        -- (solo si algún paso empieza entre el nivel del rango y tu tope: si uno los cruza
        -- entero, entrenar es el paso actual al llegar al tope; ver arriba)
        local startsBetween = false
        for _, s in ipairs(rebuilt.steps) do
          if s.from >= rk.skill and s.from < prevCap then startsBetween = true end
        end
        assert(promoted or not startsBetween, "en algún nivel antes del tope, entrenar debería ser el paso actual")
        log[#log+1] = string.format("     rango antes del tope: paso actual %s, aviso a mitad de fabricar %s", tostring(promoted), tostring(reminded))
      end
    end
    -- Ruta completada: lo dice y no se cierra
    ES.GetProfessionSkill = function() return 225, 300 end
    A.Update()
    assert(f._shown and st.completed and tostring(f.banner.title._text):find("completada"), "falta la ruta completada en el asistente")
    -- Su clic abre la pestaña Profit (lo que sacas vendiendo lo fabricado), con un
    -- subtítulo corto que cabe
    assert(f.banner.sub._text == ES.L["Clic: ver lo que sacas vendiéndolo"], "subtítulo corto: " .. tostring(f.banner.sub._text))
    do
      local savedShow, shown = ES.ShowMainFrame, nil
      ES.ShowMainFrame = function(_, p) shown = p end
      f.banner.onClick()
      ES.ShowMainFrame = savedShow
      assert(shown == "Leatherworking" and ES.db.prof.Leatherworking.view == "profit", "debería abrir la pestaña Profit")
      ES.db.prof.Leatherworking.view = "route"
    end
    log[#log+1] = "     asistente: " .. tostring(big.bannerTitle) .. " · " .. #st.steps .. " pasos"
    end)
    -- (se deja todo como estaba aunque falle: si no, fallan las pruebas de después)
    ES.GetProfessionSkill, ES.IsRecipeKnown, ES.ItemCount = savedSkill, savedKnown, savedCount
    page.from, page.detected, page.plan = newLevel, savedDetected, savedPlan
    ES.db.prof.Leatherworking.assistantHidden = nil
    if not ok then error(err, 0) end
  end
  ES.DetectSkill = savedDetect
  ES:DetectSkill(page)
  -- Llegar al objetivo no libera la ruta: se queda como completada
  local lp = ES.db.prof.Leatherworking
  ES.DetectSkill = function(_, p) p.from = 225 end
  ES:RefreshAfterSkill()
  assert(lp.lock and lp.lock.completed, "al llegar al objetivo la ruta debería quedar completada, no liberarse")
  assert(tostring(page.status._text):find("completada"), "falta el aviso de ruta completada: " .. tostring(page.status._text))
  ES.DetectSkill = savedDetect
  lp.lock.completed = nil
  ES:DetectSkill(page)
  ES:CalculatePlan(page)
  -- Sin registro de dinero: la franja no tiene fila "Real" y Profit no cuenta vendidos
  local buyItem, sellItem = rebuilt.shopping[1].itemID, nil
  for _, st in ipairs(rebuilt.steps) do if st.sale then sellItem = st.sale.itemID break end end
  local counts = { [buyItem] = 0, [sellItem] = 10 }
  GetItemCount = function(id) return counts[id] or 0 end
  GetMerchantNumItems = function() return 1 end
  GetMerchantItemID = function() return buyItem end
  GetMerchantItemInfo = function() return "x", nil, 300, 3 end -- 3 por 300: 100 cada uno
  ES:RenderPlan(page)
  assert(page.real == nil, "la franja no debería tener la fila Real")
  page.view = "profit"
  ES:RenderPlan(page)
  local sellLine
  for _, l in ipairs(page.lines) do if l.item == sellItem then sellLine = l end end
  assert(sellLine and not (sellLine.sub or ""):find("vendidos"), "Profit no debería contar vendidos")
  assert(sellLine.go, "sin vendedor ni AH abiertos, el clic marca dónde venderlo")
  assert(sellLine.title:find("en bolsas"), "Profit debería decir cuántos llevas en las bolsas: " .. sellLine.title)
  -- Lo que llevas en las bolsas: el mismo consejo que Inventario y el panel de la AH
  -- (último escaneo), no el de los precios de cuando empezaste la ruta (Rage Potion:
  -- la ruta decía "al vendedor" y la AH "ponlo en la AH")
  do
    local savedList = ES.Inventory.List
    ES.Inventory.List = function() return { { itemID = sellItem, count = 9, keep = 0, ahN = 9, vendorN = 0, listPrice = 4321, ahUnit = 4000, verdict = "good", value = 1 } } end
    ES:RenderPlan(page)
    local l2
    for _, l in ipairs(page.lines) do if l.item == sellItem then l2 = l end end
    local d
    for _, x in ipairs(page.plan.destinations) do if x.itemID == sellItem then d = x end end
    assert(d and d.advice.fromBags and d.advice.ah == 9 and d.advice.vendor == 0 and d.advice.price == 4321,
      "con el objeto en las bolsas, el consejo de Inventario")
    assert(not tostring(l2 and l2.sub):find("vendedor"), "si Inventario dice AH, Profit no dice vendedor: " .. tostring(l2 and l2.sub))
    -- Y otro total: siguiendo el consejo (9 en la AH a 4000 netos cada una)
    local adv
    for _, l in ipairs(page.lines) do if l.advisedTotal then adv = l end end
    assert(adv and adv.advisedTotal >= 9 * 4000, "falta el total siguiendo el consejo: " .. tostring(adv and adv.advisedTotal))
    -- Y en la franja, bajo el total seguro: el posible total con la AH (mismo cálculo)
    local _, advS = ES.ProfitSalesTotals(page.plan)
    assert(advS == adv.advisedTotal, "franja y vista Profit no suman igual: " .. tostring(advS) .. " vs " .. tostring(adv.advisedTotal))
    assert(page.totalAHInfo and tostring(page.totalAH._text):find("AH"), "falta el total con AH bajo el total: " .. tostring(page.totalAH._text))
    ES.Inventory.List = savedList
    ES:RenderPlan(page)
  end
  -- Sin correo: lo comprado en la AH no cuenta hasta que está en las bolsas
  assert(ES.Ledger.InMail == nil and ES.Ledger.NoteAHPurchase == nil, "el correo ya no debería contar")
  -- Lista de la compra con la ruta empezada: secciones según lo que llevas ahora
  page.view = "shop"
  ES:RenderPlan(page)
  local sections, haveSection = {}, false
  for _, l in ipairs(page.lines) do
    if l.section then sections[#sections + 1] = l.section end
    if l.section == "Ya lo tienes" then haveSection = true end
  end
  local lastLine = page.lines[#page.lines]
  assert(lastLine.total and lastLine.title == "Te falta por comprar", "con la ruta empezada, el total es lo que falta: " .. tostring(lastLine.title))
  log[#log+1] = "     lista con ruta empezada: " .. table.concat(sections, " | ")
  page.view = "route"
  -- Anunciar en la AH: con cobres, como dice la fila (la AH de Forever los admite)
  assert(ES.Ledger.PostPrice(2070) == 2070 and ES.Ledger.PostPrice(50) == 50, "precio de anuncio sin los cobres")
  -- Con la AH abierta y nada en las bolsas, el clic avisa en vez de marcar el subastador
  -- (y sin repetir "no llevas ninguno": el título ya dice "0 en bolsas")
  local savedOpen = ES.IsAuctionHouseOpen
  ES.IsAuctionHouseOpen = function() return true end
  page.view = "profit"
  ES:RenderPlan(page)
  for _, l in ipairs(page.lines) do
    if l.title and l.title:find("0 en bolsas") and l.onClick then
      assert(not l.go, "con la AH abierta y sin el objeto, el clic no debería marcar el subastador")
      assert(not (l.sub or ""):find("no llevas ninguno"), "repite que no llevas ninguno")
      l.onClick()
    end
  end
  page.view = "route"
  ES.IsAuctionHouseOpen = savedOpen
  -- Vendedor abierto con la ruta empezada: ventana al lado con lo que falta y "Comprar todo"
  local bought = {}
  MerchantFrame = CreateFrame("Frame")
  GetMoney = function() return 10000000 end
  C_MerchantFrame = { GetItemInfo = function() return { price = 300, stackCount = 3, numAvailable = -1, isPurchasable = true } end }
  BuyMerchantItem = function(i, n) bought[#bought + 1] = n or 3 end -- sin cantidad: un lote (de 3)
  counts[buyItem] = 0
  -- (ruta entera: buyItem es el material más caro de toda la ruta, no del tramo)
  local phaseSaved = ES.db.prof[page.profKey].byPhase
  ES.db.prof[page.profKey].byPhase = false
  -- MERCHANT_SHOW antes de que el juego enseñe la ventana del vendedor (orden de los
  -- addons): la ventana tiene que salir igual, sin tener que vender algo a mano
  if CraftersJournalVendorPanel then CraftersJournalVendorPanel:Hide() end
  local merchantShown, later = false, {}
  MerchantFrame.IsShown = function() return merchantShown end
  local savedAfter = C_Timer.After
  C_Timer.After = function(_, fn) later[#later + 1] = fn end
  -- (solo al marco de la ventana del vendedor, el único con MERCHANT_UPDATE: lo demás
  -- que escucha MERCHANT_SHOW recalcula y acabaría refrescándola por otro lado)
  local vf = EVENT_FRAMES["MERCHANT_UPDATE"][1]
  vf._scripts.OnEvent(vf, "MERCHANT_SHOW")
  merchantShown = true
  for _, fn in ipairs(later) do fn() end
  C_Timer.After = savedAfter
  MerchantFrame.IsShown = nil
  local vp = CraftersJournalVendorPanel
  assert(vp and vp._shown == true and vp.rows[1].entry, "con MERCHANT_SHOW antes de abrirse el vendedor, la ventana no sale")
  log[#log+1] = "     vendedor: la ventana sale aunque MERCHANT_SHOW llegue antes de abrirse el vendedor"
  -- Opciones: la casilla quita la ventana del vendedor al momento, y vuelve al marcarla
  local op = ES:OptionsWindow()
  op._scripts.OnShow(op)
  local vcb
  for _, cb in ipairs(op.checks) do if cb.option.key == "noVendorWindow" then vcb = cb end end
  assert(vcb and vcb:GetChecked(), "la casilla del vendedor sale marcada por defecto")
  vcb:SetChecked(false)
  vcb._scripts.OnClick(vcb)
  assert(ES.db.noVendorWindow == true and vp._shown == false, "desmarcada, la ventana del vendedor no sale")
  ES.VendorShop:Refresh()
  assert(vp._shown == false, "desmarcada, la ventana del vendedor vuelve a salir al refrescar")
  vcb:SetChecked(true)
  vcb._scripts.OnClick(vcb)
  assert(ES.db.noVendorWindow == nil and vp._shown == true, "marcada otra vez, la ventana del vendedor sale")
  log[#log+1] = "     opciones: la ventana del vendedor se quita y vuelve con su casilla"
  vp.sellAll._scripts.OnEnter(vp.sellAll)
  ES.VendorShop:Refresh()
  assert(vp and vp.rows[1].entry and vp.rows[1].entry.itemID == buyItem, "la ventana del vendedor no lista lo que falta")
  assert(vp.rows[1].entry.qty % 3 == 0, "se compra en los lotes del vendedor: " .. vp.rows[1].entry.qty)
  vp.rows[1]._scripts.OnEnter(vp.rows[1])
  vp.buyAll._scripts.OnClick(vp.buyAll)
  -- Comprar todo pregunta antes (ES:Confirm): sin el Sí, no compra nada
  local confirm = ES.ConfirmFrame()
  assert(confirm and confirm.pending and #bought == 0, "Comprar todo debería preguntar antes de comprar")
  confirm.ok._scripts.OnClick(confirm.ok)
  assert(#bought > 0 and bought[1] > 0, "Comprar todo no compró nada")
  -- Pulsar su fila mientras se compra no lo compra dos veces
  local queued = #ES.VendorShop.queue
  ES.VendorShop:Buy({ itemID = buyItem, qty = 3, batch = 3, price = 300, cost = 300 })
  assert(#ES.VendorShop.queue == queued, "compró dos veces el mismo material")
  log[#log+1] = string.format("     vendedor: %s · primera compra de %d", tostring(vp.buyAll._text), bought[1])
  -- Entrega lenta del servidor: la comprobación final no vuelve a comprar mientras lo
  -- comprado sigue llegando (antes, al primer vistazo, compraba otra vez: de más)
  local V = ES.VendorShop
  V.queue, V.pumping = {}, nil
  bought = {}
  counts[buyItem] = 0
  local function Bought() local n = 0 for _, b in ipairs(bought) do n = n + b end return n end
  V:Buy({ itemID = buyItem, qty = 6, batch = 3, price = 300, cost = 600 })
  while V.queue[1] and not V.queue[1].check do V:Pump() end
  assert(Bought() == 6, "debería pedir 6: " .. Bought())
  V:Pump() -- aún no ha llegado nada: espera
  assert(Bought() == 6, "volvió a comprar antes de que llegara lo comprado")
  counts[buyItem] = 3
  V:Pump() -- va llegando: espera
  assert(Bought() == 6, "volvió a comprar mientras llegaba")
  counts[buyItem] = 6
  V:Pump() -- ya está todo
  assert(Bought() == 6 and not V.queue[1], "con todo en las bolsas no debería quedar nada en cola")
  -- Si no llega (servidor lento o sin existencias), NUNCA lo vuelve a comprar solo
  -- (Discord: 14 Fine Thread -> 28): espera, avisa de lo que falta y deja de mirar.
  -- Mientras espera, pulsar la fila tampoco lo compra otra vez
  V.queue, V.pumping = {}, nil
  bought = {}
  counts[buyItem] = 0
  local printed = {}
  local savedPrint = ES.Print
  ES.Print = function(_, msg) printed[#printed + 1] = msg end
  V:Buy({ itemID = buyItem, qty = 3, batch = 3, price = 300, cost = 300 })
  while V.queue[1] and not V.queue[1].check do V:Pump() end
  V:Pump() -- primer vistazo: espera
  V:Buy({ itemID = buyItem, qty = 3, batch = 3, price = 300, cost = 300 }) -- clic en la fila mientras espera
  for _ = 1, 20 do if V.queue[1] then V:Pump() end end
  ES.Print = savedPrint
  assert(Bought() == 3 and not V.queue[1], "lo que no llegó no debería comprarse otra vez: " .. Bought())
  assert(printed[#printed] and printed[#printed]:find("3"), "debería avisar de lo que falta: " .. tostring(printed[#printed]))
  log[#log+1] = "     vendedor: con entrega lenta no compra de más; si no llega, avisa y no lo vuelve a comprar"
  -- Mientras espera a uno que no llega, compra los demás (no los retrasa la espera)
  V.queue, V.pumping = {}, nil
  local order = {}
  local savedBuyFn, savedFind = BuyMerchantItem, GetMerchantItemID
  local OTHER = buyItem + 1
  GetMerchantNumItems = function() return 2 end
  GetMerchantItemID = function(i) return i == 1 and buyItem or OTHER end
  BuyMerchantItem = function(i) order[#order + 1] = i end
  counts[buyItem], counts[OTHER] = 0, 0
  ES.Print = function() end
  V:Buy({ itemID = buyItem, qty = 3, batch = 3, price = 300, cost = 300 }) -- (arranca la cola: compra el primero)
  V:Buy({ itemID = OTHER, qty = 3, batch = 3, price = 300, cost = 300 })
  V:Pump() -- su comprobación: no ha llegado, espera al final
  assert(V.queue[1] and not V.queue[1].check and V.queue[1].itemID == OTHER, "la espera retrasa el siguiente")
  for _ = 1, 30 do if V.queue[1] then V:Pump() end end
  ES.Print = savedPrint
  assert(#order == 2 and order[2] == 2, "compró los dos, uno tras otro")
  BuyMerchantItem, GetMerchantItemID = savedBuyFn, savedFind
  GetMerchantNumItems = function() return 1 end
  counts[OTHER] = nil
  V.queue, V.pumping = {}, nil
  -- Ruta sin empezar: la ventana del vendedor no propone nada de ella, aunque sea la
  -- última profesión que miraste (CurseForge: "200 Weak Flux" con la Lista de compra vacía)
  do
    local savedLock, savedLast, savedLocked = ES.RouteLock, ES.db.lastProf, ES.LockedPlan
    ES.RouteLock = function() return nil end
    ES.db.lastProf = page.profKey
    for _, e in ipairs(V:List()) do
      assert(e.itemID ~= buyItem, "sin empezar la ruta, la ventana del vendedor no propone sus materiales")
    end
    -- Empezada (sin "por tramos"): lo de la ruta entera desde tu nivel, sin el colchón
    -- del tramo (como la vista Materiales: Discord, 12 Fine Thread en la ruta y 14 aquí)
    local savedPhase = ES.db.prof[page.profKey].byPhase
    ES.db.prof[page.profKey].byPhase = false
    ES.RouteLock = function(_, k) return k == page.profKey and { from = page.plan.from, to = page.plan.to } or nil end
    ES.LockedPlan = function(_, k) return k == page.profKey and page.plan or nil end
    local rank = ES:GetProfessionSkill(ES.Data[page.profKey].skillLine)
    local want = ES.Planner.NeedFrom(page.plan, math.max(page.plan.from, rank or page.plan.from))[buyItem]
    local entry
    for _, e in ipairs(V:List()) do if e.itemID == buyItem then entry = e end end
    assert(entry and want and entry.need == math.ceil(want - 0.001),
      "empezada, la ventana del vendedor pide " .. tostring(entry and entry.need) .. " y la ruta " .. tostring(want))
    ES.RouteLock = function() return nil end
    ES.db.prof[page.profKey].byPhase = nil -- (por tramos, lo de por defecto)
    -- Y la regla única: sin empezar, aunque "por tramos" esté activado, la ruta entera
    local rn, ph = ES.Planner.RouteNeed(page.profKey, page.plan, rank)
    assert(ph == nil and rn[buyItem] and rn[buyItem].need == entry.need, "RouteNeed sin empezar: ruta entera")
    -- Empezada y por tramos: el tramo (lo mismo para Materiales, Lista de compra y vendedor)
    ES.RouteLock = function(_, k) return k == page.profKey and { from = page.plan.from, to = page.plan.to } or nil end
    local rnP, phP = ES.Planner.RouteNeed(page.profKey, page.plan, rank)
    local pn = ES.Planner.PhaseNeed(page.plan, math.max(page.plan.from, rank or page.plan.from))
    assert(phP, "RouteNeed empezada y por tramos: el tramo")
    for itemID, n in pairs(pn) do assert(rnP[itemID] and rnP[itemID].need == n.target, "RouteNeed por tramos: " .. itemID) end
    -- Inventario (keep): siempre la ruta entera, aunque vaya por tramos
    local rnK, phK = ES.Planner.RouteNeed(page.profKey, page.plan, rank, { keep = true })
    assert(phK == nil and rnK[buyItem] and rnK[buyItem].need == entry.need, "RouteNeed keep: ruta entera")
    ES.db.prof[page.profKey].byPhase = false
    -- Lo de vendedor de las demás listas de la compra (calculadora, Ganar dinero) también
    -- sale aquí: junto a la AH ya no sale
    ES.RouteLock = function(_, k) return k == page.profKey and { from = page.plan.from, to = page.plan.to } or nil end
    local savedChar = ES.charData
    ES.charData = { shopping = { { kind = "calc", title = "Calc", key = "c",
      items = { { itemID = buyItem, need = 7, unit = 100, source = "vendor" } } } } }
    local withCalc
    for _, e in ipairs(V:List()) do if e.itemID == buyItem then withCalc = e end end
    assert(withCalc and withCalc.need == entry.need + 7, "la ventana del vendedor suma lo de vendedor de la lista de compra: "
      .. tostring(withCalc and withCalc.need) .. " vs " .. entry.need .. " + 7")
    ES.charData = savedChar
    ES.db.prof[page.profKey].byPhase = savedPhase
    ES.RouteLock, ES.db.lastProf, ES.LockedPlan = savedLock, savedLast, savedLocked
    log[#log+1] = "     vendedor: sin empezar la ruta no propone nada; empezada, lo de la ruta (" .. entry.need .. ")"
  end
  -- Cliente clásico: BuyMerchantItem(i, n) cuenta n en lotes. Pedir 6 de uno que va
  -- de 3 en 3 compraba 18; ahora, de lote en lote (sin cantidad): 6
  V.queue, V.pumping = {}, nil
  bought = {}
  counts[buyItem] = 0
  BuyMerchantItem = function(i, n) bought[#bought + 1] = (n or 1) * 3 end
  V:Buy({ itemID = buyItem, qty = 6, batch = 3, price = 300, cost = 600 })
  while V.queue[1] and not V.queue[1].check do V:Pump() end
  assert(Bought() == 6, "con lotes de 3, pedir 6 debería comprar 6, no " .. Bought())
  log[#log+1] = "     vendedor: por lotes compra lo que falta, también si el cliente cuenta en lotes"
  V.queue, V.pumping = {}, nil
  -- Lo que la vista Profit dice que vendas al vendedor, en la misma ventana, con "Vender todo"
  local savedBag, savedSell, savedOpen2 = ES.Ledger.BagCount, ES.Ledger.SellToVendor, ES.Ledger.MerchantOpen
  local sold = {}
  ES.Ledger.BagCount = function(id) return counts[id] or 0 end
  ES.Ledger.SellToVendor = function(_, id, n) sold[#sold + 1] = { id, n } return n end
  ES.Ledger.MerchantOpen = function() return true end
  ES.VendorShop.queue, ES.VendorShop.pumping = {}, nil
  local sellList = ES.VendorShop:SellList()
  if #sellList > 0 then
    ES.VendorShop:Refresh()
    local sellRow
    for _, row in ipairs(vp.rows) do if row.kind == "sell" and row._shown ~= false then sellRow = row break end end
    assert(sellRow and sellRow.entry.n > 0, "falta la fila de vender en la ventana del vendedor")
    sellRow._scripts.OnEnter(sellRow)
    assert(vp.sellAll._shown ~= false and tostring(vp.sellAll._text):find("Vender todo"), "falta Vender todo")
    vp.sellAll._scripts.OnClick(vp.sellAll)
    assert(#sold > 0 and sold[1][1] == sellList[1].itemID, "Vender todo no vendió")
    log[#log+1] = string.format("     vendedor: %s · vende %d de %s", tostring(vp.sellAll._text), sold[1][2], ES:DataItemName(sold[1][1]) or sold[1][1])
  else
    log[#log+1] = "     vendedor: nada que vender en esta ruta"
  end
  ES.Ledger.BagCount, ES.Ledger.SellToVendor, ES.Ledger.MerchantOpen = savedBag, savedSell, savedOpen2
  ES.VendorShop.selling = nil
  ES.VendorShop.queue, ES.VendorShop.pumping = {}, nil
  MerchantFrame, C_MerchantFrame, BuyMerchantItem, GetMoney = nil, nil, nil, nil
  ES.db.prof[page.profKey].byPhase = phaseSaved
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
  -- Con lo que llevas (bolsas activadas): una cita que solo informa (no se pulsa).
  -- Con alternativas de mentira: no compensa -> "mejor vender"; compensa con la
  -- ruta fijada -> "Recalcular ruta"; compensa sin fijar -> nada (ya va en la ruta)
  local function FindBagsLine()
    for _, l in ipairs(page.lines) do if l.quote then return l end end
  end
  local savedAlt = ES.Planner.BagsAlternative
  local fake = { saving = 380, value = 900 }
  ES.Planner.BagsAlternative = function(data, plan, owned, from, excluded)
    local st = plan.steps[#plan.steps]
    if excluded and excluded[st.id] then return nil end
    local r = data.recipes[st.id]
    return { id = st.id, recipe = r, from = st.from, to = st.to, crafts = 3, fee = 0, gold = 120, spend = 150, value = fake.value,
      routeCost = 500, saving = fake.saving, use = { { itemID = r.r[1][1], qty = 6, value = fake.value } } }
  end
  ES:RenderPlan(page)
  local bagsLine = FindBagsLine()
  assert(bagsLine and bagsLine.quote:find("Con lo que llevas podrías hacer") and bagsLine.quote:find("Vender lo tuyo"),
    "falta la cita de Con lo que llevas (no compensa)")
  assert(not bagsLine.onClick and not bagsLine.tooltip, "la cita no debería pulsarse")
  log[#log+1] = "     con lo que llevas: " .. bagsLine.quote:gsub("\n", " / ")
  -- ✕ en la cita: deja de salir (la ruta no cambia) y se recupera con "Recetas quitadas"
  local lockBefore = ES.db.prof.Leatherworking.lock
  assert(bagsLine.onSkip, "la cita debería tener la ✕ para descartarla")
  bagsLine.onSkip()
  assert(not FindBagsLine(), "la cita descartada sigue saliendo")
  assert(ES.db.prof.Leatherworking.lock == lockBefore, "descartar la cita no debería soltar la ruta")
  local restoreNote
  for _, l in ipairs(page.lines) do if l.title and l.title:find("Avisos ocultos") then restoreNote = l end end
  assert(restoreNote, "falta la fila para recuperar la cita descartada")
  restoreNote.onClick()
  assert(FindBagsLine(), "la cita no volvió al recuperarla")
  assert(ES.db.prof.Leatherworking.lock == lockBefore, "recuperar la cita no debería soltar la ruta")
  fake.saving, fake.value = 900, 100
  ES:RenderPlan(page)
  bagsLine = FindBagsLine()
  assert(bagsLine and bagsLine.quote:find("Dejar ruta"), "con la ruta fijada, la cita debería pedir dejar la ruta")
  -- Aprendes la receta (instructor) con la ruta fijada: su fila de aprender queda hecha
  local learnRows = 0
  for _, l in ipairs(page.lines) do if l.onSkip and l.title and (l.title:find("Entrenar") or l.title:find("Comprar receta")) then learnRows = learnRows + 1 end end
  local knownBefore = ES.IsRecipeKnown
  ES.IsRecipeKnown = function() return true end
  ES:RefreshAfterLearn()
  local learned, pendingLearn = 0, 0
  for _, l in ipairs(page.lines) do
    if l.sub and l.sub:find("Aprendida") then learned = learned + 1 end
    if l.onSkip and l.title and (l.title:find("Entrenar") or l.title:find("Comprar receta")) then pendingLearn = pendingLearn + 1 end
  end
  ES.IsRecipeKnown = knownBefore
  assert(pendingLearn == 0 and learned == learnRows, string.format("al aprenderla, la fila no quedó hecha (%d de %d)", learned, learnRows))
  log[#log+1] = string.format("     aprendidas: %d filas de aprender marcadas como hechas", learned)
  -- Un doble clic en Empezar ruta no la suelta; Recalcular ruta (más tarde) sí
  page.routeStartedAt = GetTime and GetTime() or 0
  page.routeButton._scripts.OnClick(page.routeButton)
  assert(ES.db.prof.Leatherworking.lock, "un doble clic en Empezar ruta la soltó")
  page.routeStartedAt = nil
  -- Dejar ruta pide un segundo clic: el primero solo pregunta
  page.routeButton._scripts.OnClick(page.routeButton)
  assert(ES.db.prof.Leatherworking.lock, "Dejar ruta la soltó con un solo clic")
  page.routeButton._scripts.OnClick(page.routeButton)
  assert(not ES.db.prof.Leatherworking.lock, "Dejar ruta no la liberó")
  ES:RenderPlan(page)
  assert(not FindBagsLine(), "sin fijar, lo que compensa ya va en la ruta: no hay cita")
  ES.Planner.BagsAlternative = savedAlt
  ES.db.prof.Leatherworking.useBags = savedBags
  GetItemCount = nil
  ES:ClearHomeCache()
  ES:CalculatePlan(page)
  ES:SelectPage("home")
  -- Pulsar la tarjeta abre la profesión; Volver regresa
  local lwCard
  for _, c in ipairs(ES.homePage.cards) do if c.key == "Leatherworking" then lwCard = c end end
  lwCard._scripts.OnClick(lwCard)
  assert(ES.db.lastPage == "Leatherworking", "no abrió la profesión")
  CraftersJournalMainFrame.back._scripts.OnClick(CraftersJournalMainFrame.back)
  assert(ES.db.lastPage == "home", "Volver no regresó a la portada")
  GetProfessions, GetProfessionInfo = nil, nil
end)
step("cabecera: título, escanear e idioma", function()
  local f = CraftersJournalMainFrame
  assert(f.title._text == "Crafter's Journal", "título: " .. tostring(f.title._text))
  -- Botón Escanear: durante el escaneo muestra el % de progreso y al acabar vuelve a "Escanear"
  local savedBusy = ES.Scanner.IsBusy
  ES.Scanner.IsBusy = function() return true end
  ES.Scanner.progress = 0.05
  ES:OnScanProgress()
  assert(f.scanButton._text == "5%", "progreso inicial: " .. tostring(f.scanButton._text))
  ES.Scanner.progress = 0.537
  ES.progressAt = nil -- (el progreso se repinta como mucho cada 0,25 s: pasado ese rato)
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
step("estrella sobre el PNJ al que te manda el addon", function()
  -- Poner marcas está protegido: el addon no llama a SetRaidTarget; al pasar el
  -- ratón por una fila de vendedor, un botón seguro con la macro se pone encima
  local WP = ES.Waypoints
  local called = false
  local savedSet, savedGo, savedAvail = SetRaidTarget, WP.Go, WP.Available
  SetRaidTarget = function() called = true end
  WP.Go, WP.Available = function() end, function() return true end
  local npcID = WP.Nearest(ES.Data.Auctioneers) or next(ES.Data.NPCs or {})
  local npc = WP.NPC(npcID)
  local row = CreateFrame("Button")
  row.go = function() return npcID end
  WP.HoverRow(row)
  local h = WP.HoverButton()
  local macro = h and h:GetAttribute("macrotext")
  assert(h._shown and macro and macro:find("/targetexact [nocombat] " .. npc.name, 1, true) and macro:find("/tm [nocombat,exists] 1", 1, true),
    "falta el botón seguro sobre la fila: " .. tostring(macro)) -- (su clic: PostClick, solo en el juego)
  assert(not called, "el addon no puede llamar a SetRaidTarget por su cuenta (acción bloqueada)")
  assert(CraftersJournalMarkButton == nil, "no debería haber botón flotante")
  -- Sin tapar el icono del objeto: encima de él, su tooltip (vista Profit: salía el de la fila)
  do
    local withIcon = CreateFrame("Button")
    withIcon.go = function() return npcID end
    withIcon.GetLeft = function() return 100 end
    withIcon.iconHover = CreateFrame("Frame")
    withIcon.iconHover.GetRight = function() return 150 end
    local x
    h.SetPoint = function(self, p, rel, rp, ox) if p == "TOPLEFT" then x = ox end end
    WP.HoverRow(withIcon)
    h.SetPoint = nil
    assert(x == 50, "el botón seguro empieza a la derecha del icono: " .. tostring(x))
    WP.HoverRow(row) -- (de vuelta a la fila de antes, para lo que sigue)
  end
  -- En combate no se toca
  local savedLock = InCombatLockdown
  InCombatLockdown = function() return true end
  local other = CreateFrame("Button")
  other.go = function() return npcID end
  WP.HoverRow(other)
  assert(h.row == row, "en combate el botón seguro no debería moverse")
  InCombatLockdown = savedLock
  -- Un buzón no se puede seleccionar: sin botón seguro (su macro volvía a tu objetivo de
  -- antes: en "Recoge el correo", el clic seleccionaba al subastador; Discord)
  local mailbox = ES.Data.Mailboxes and ES.Data.Mailboxes[1]
  if mailbox then
    local mrow = CreateFrame("Button")
    mrow.go = function() return mailbox end
    WP.HoverRow(mrow)
    assert(h.row ~= mrow and h._shown == false, "sobre un buzón no debería ponerse la macro de seleccionar")
    assert(WP.Targetable(npcID) and not WP.Targetable(mailbox), "los PNJ se seleccionan; los buzones no")
    WP.HoverRow(row)
  end
  WP.ReleaseHover()
  assert(h._shown == false, "al salir de la fila el botón seguro se suelta")
  SetRaidTarget, WP.Go, WP.Available = savedSet, savedGo, savedAvail
  log[#log+1] = "     estrella: " .. macro:gsub("\n", " / ")
end)
step("icono menos fabricaciones: pesa cada fabricación al elegir", function()
  local page
  for _, p in ipairs(ES.professionPages) do if p.profKey == "Enchanting" then page = p end end
  assert(page.fewerButton, "falta el icono de menos fabricaciones")
  ES.db.prof.Enchanting = ES.db.prof.Enchanting or {}
  local settings = ES.db.prof.Enchanting
  local saved = settings.fewerCrafts
  settings.fewerCrafts = nil
  assert(ES:PlanOptions("Enchanting", 79, 150).craftWeight == nil, "por defecto (apagado), la ruta más barata (con el peso mínimo por fabricación)")
  local k1 = ES:PlanKey("Enchanting", 79, 150)
  page.fewerButton:GetScript("OnClick")(page.fewerButton)
  assert(settings.fewerCrafts, "el clic no lo activó")
  assert(ES:PlanOptions("Enchanting", 79, 150).craftWeight == ES.Planner.FEWER_CRAFTS_WEIGHT, "no pasa el peso al plan")
  assert(ES:PlanKey("Enchanting", 79, 150) ~= k1, "la caché no distingue el icono")
  -- La puntuación de una ruta cuenta cada fabricación con ese peso
  local plan = { fees = 0, steps = { { crafts = 10, unitValue = 0, unitCost = 0, from = 1, to = 5 } }, ctx = { opts = {} } }
  local base = ES.Planner.RouteScore(plan)
  plan.ctx.opts.craftWeight = 100
  assert(ES.Planner.RouteScore(plan) - base == 10 * (100 - 5), "el peso no cuenta en la puntuación")
  -- Con el icono, cada fabricación pesa lo que tarda (CurseForge: recetas de 30-50 s):
  -- una de 50 s pesa ~14 veces una normal; sin el icono, todas igual
  local savedSpell = C_Spell
  C_Spell = { GetSpellInfo = function(id)
    if id == 990001 then return { castTime = 50000 } end
    if id == 990002 then return { castTime = 3000 } end
  end }
  ES.Planner.ClearCraftSeconds()
  local slow = ES.Planner.RecipeWeight({ craftWeight = 100 }, 990001)
  local normal = ES.Planner.RecipeWeight({ craftWeight = 100 }, 990002)
  assert(math.abs(normal - 100) < 1e-9 and slow > 13 * normal, string.format("la lenta pesa %.0f, la normal %.0f", slow, normal))
  assert(ES.Planner.RecipeWeight({}, 990001) == ES.Planner.RecipeWeight({}, 990002), "sin el icono, todas pesan igual")
  local slowPlan = { fees = 0, steps = { { id = 990001, crafts = 10, unitValue = 0, unitCost = 0, from = 1, to = 5 } }, ctx = { opts = { craftWeight = 100 } } }
  local fastPlan = { fees = 0, steps = { { id = 990002, crafts = 10, unitValue = 0, unitCost = 0, from = 1, to = 5 } }, ctx = { opts = { craftWeight = 100 } } }
  assert(ES.Planner.RouteScore(slowPlan) > ES.Planner.RouteScore(fastPlan) + 10000, "con el icono, la ruta lenta puntúa peor")
  C_Spell = savedSpell
  page.fewerButton:GetScript("OnClick")(page.fewerButton)
  settings.fewerCrafts = saved
  log[#log+1] = string.format("     menos fabricaciones: una de 50 s pesa %.0f, una de 3 s %.0f", slow, normal)
end)
step("ruta: lo que se tarda en fabricar cada paso y la ruta", function()
  -- Una receta lenta (50 s por fabricación): su fila lo dice en naranja, el tooltip da
  -- el tiempo por fabricación (el del paso ya va en la fila), y la fila del total el de
  -- toda la ruta
  local page
  for _, p in ipairs(ES.professionPages) do if p.profKey == "Leatherworking" then page = p end end
  local savedPlan, savedFrom, savedSpell = page.plan, page.from, C_Spell
  local opts = ES:PlanOptions("Leatherworking", 1, 75)
  opts.owned = nil
  page.from = 1
  page.plan = ES.Planner:Plan(ES.Data.Leatherworking, opts)
  local st1 = page.plan.steps[1]
  local slowID = st1.id
  C_Spell = { GetSpellInfo = function(id) if id == slowID then return { castTime = 50000 } end return { castTime = 0 } end }
  ES.Planner.ClearCraftSeconds()
  ES:RenderPlan(page)
  local slowLine, totalLine
  for _, l in ipairs(page.lines) do
    if l.level == st1.from .. "–" .. st1.to and l.onClick then slowLine = slowLine or l end
    if l.total then totalLine = l end
  end
  assert(slowLine and tostring(slowLine.sub):find("ff9933", 1, true) and tostring(slowLine.sub):find("min", 1, true),
    "la fila de la receta lenta dice el tiempo en naranja: " .. tostring(slowLine and slowLine.sub))
  assert(totalLine and tostring(totalLine.sub):find("min", 1, true), "el total dice el tiempo de la ruta: " .. tostring(totalLine and totalLine.sub))
  -- y la franja de resumen, el de toda la ruta (para comparar rutas por tiempo)
  local timeText = page.stats.time and page.stats.time:GetText()
  assert(timeText and tostring(timeText):find("min", 1, true), "la franja no dice el tiempo de la ruta: " .. tostring(timeText))
  local lines = {}
  local savedAL = GameTooltip.AddLine
  GameTooltip.AddLine = function(_, a) lines[#lines + 1] = tostring(a) end
  slowLine.tooltip(CreateFrame("Button"))
  GameTooltip.AddLine = savedAL
  assert(table.concat(lines, "|"):find("por fabricación", 1, true), "el tooltip de la lenta da el tiempo por fabricación: " .. table.concat(lines, "|"))
  C_Spell, page.plan, page.from = savedSpell, savedPlan, savedFrom
  ES.Planner.ClearCraftSeconds()
  log[#log+1] = "     paso lento: " .. tostring(slowLine.sub):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. " · total: " .. tostring(totalLine.sub)
end)
step("ruta: el rango aprendido sale hecho", function()
  -- Alquimia 63 con tope 75: la ruta pide Oficial; al aprenderlo (tope 150) se tacha
  local page
  for _, p in ipairs(ES.professionPages) do if p.profKey == "Leatherworking" then page = p end end
  local savedPlan, savedFrom, savedDet = page.plan, page.from, page.detected
  page.from, page.detected = 63, { rank = 63, cap = 75 }
  local opts = ES:PlanOptions("Leatherworking", 63, 225, 75)
  opts.owned = nil
  page.plan = ES.Planner:Plan(ES.Data.Leatherworking, opts)
  local function RankLine()
    ES:RenderPlan(page)
    for _, l in ipairs(page.lines) do
      if l.rankCap == 150 then return l end
    end
  end
  local l = RankLine()
  assert(l and not l.done, "falta la fila de Oficial, o sale hecha sin aprenderla")
  page.detected.cap = 150
  l = RankLine()
  assert(l and l.done, "Oficial aprendido no sale hecho: " .. tostring(l and l.sub))
  page.plan, page.from, page.detected = savedPlan, savedFrom, savedDet
end)
step("comprar por tramos: tramo, margen, lista viva y avisos", function()
  local saved = { RouteLines = ES.RouteLines, RouteLock = ES.RouteLock, LockedPlan = ES.LockedPlan, GPS = ES.GetProfessionSkill,
    ItemCount = ES.ItemCount, Print = ES.Print, charData = ES.charData, byPhase = ES.db.prof.Alchemy and ES.db.prof.Alchemy.byPhase }
  ES.charData = { shopping = {}, books = { moves = {}, posts = {}, days = {}, partners = {} } }
  local ok, err = pcall(function()
  local P = ES.Planner
  -- Ruta de prueba: A (1-3, materiales 100), B (3-5, también 100: se junta), C (5-7, pide 200)
  local A, B, C = { name = "A" }, { name = "B" }, { name = "C" }
  local plan = { from = 1, to = 7,
    steps = { { from = 1, to = 3, recipe = A }, { from = 3, to = 5, recipe = B }, { from = 5, to = 7, recipe = C } },
    pointNeed = { [1] = { [100] = 1 }, [2] = { [100] = 2 }, [3] = { [100] = 1 }, [4] = { [100] = 1 },
      [5] = { [200] = 1 }, [6] = { [200] = 4 } },
    pointChance = { [1] = 1, [2] = 0.5, [3] = 1, [4] = 1, [5] = 1, [6] = 0.25 },
    shopping = { { itemID = 100, source = "ah", unit = 10 }, { itemID = 200, source = "vendor", unit = 5 } } }
  local ph = P.Phase(plan, 1)
  assert(ph.from == 1 and ph.to == 5 and #ph.steps == 2, "B no pide nada nuevo: se junta con A")
  assert(P.Phase(plan, 5).to == 7 and not P.Phase(plan, 7), "tramo C / ruta acabada")
  -- Naranja, justo; al 50%, con margen: 5 esperadas, varianza 2*2*0.5 = 2 -> 5 + 1,41 -> 7
  local need = P.PhaseNeed(plan, 1)
  assert(math.abs(need[100].expected - 5) < 1e-6 and need[100].target == 7, "margen: " .. need[100].target)
  assert(P.PhaseNeed(plan, 1, 0)[100].target == 5, "sin margen, lo esperado")
  assert(P.PhaseNeed(plan, 3)[100].target == 2, "desde el 3 solo quedan los naranjas")
  -- Cómo vas: con 4 te falta 1 para lo esperado; con 6, lo justo; con 7, todo
  local o = P.PhaseOutlook(plan, 1, function() return 4 end)
  assert(not o.ok and o.short[100] == 1, "con 4 deberían faltar 1")
  o = P.PhaseOutlook(plan, 1, function() return 6 end)
  assert(o.ok and o.extra[100] == 1, "con 6, lo esperado sin margen")
  -- Lista viva: con la ruta empezada sale el tramo y no la lista guardada de la ruta entera
  local level, have, printed = 1, {}, {}
  ES.db.prof.Alchemy = ES.db.prof.Alchemy or {}
  ES.db.prof.Alchemy.byPhase = nil
  ES.RouteLock = function(_, k) return k == "Alchemy" and { from = 1, to = 7 } or nil end
  ES.LockedPlan = function(_, k) return k == "Alchemy" and plan or nil end
  ES.GetProfessionSkill = function(_, line) if line == ES.Data.Alchemy.skillLine then return level, 150 end end
  ES.ItemCount = function(_, id) return have[id] or 0 end
  ES.Print = function(_, msg) printed[#printed + 1] = msg end
  ES.Shopping.Add("route", "Ruta entera", { { itemID = 100, quantity = 50, unit = 10, source = "ah" } }, { key = "Alchemy" })
  local st = ES.Shopping.Status()
  local live, whole
  for _, s in ipairs(st.lists) do
    if s.list.live and s.list.key == "Alchemy" then live = s end
    if s.list.kind == "route" and s.list.key == "Alchemy" then whole = s end
  end
  assert(live and not whole, "por tramos: la lista viva sustituye a la de la ruta entera")
  assert(live.items[1].it.itemID == 100 and live.items[1].left == 7, "pide lo del tramo con margen")
  have[100] = 3
  st = ES.Shopping.Status()
  for _, s in ipairs(st.lists) do if s.list.live then live = s end end
  assert(live.items[1].left == 4 and live.items[1].bought == 3, "cuenta lo que llevas")
  assert(ES.Shopping.NextToBuy(st) == 100, "Comprar siguiente usa el tramo")
  ES.db.prof.Alchemy.byPhase = false
  st = ES.Shopping.Status()
  live, whole = nil, nil
  for _, s in ipairs(st.lists) do
    if s.list.live then live = s end
    if s.list.kind == "route" and s.list.key == "Alchemy" then whole = s end
  end
  -- Ruta entera: también sale sola (todo lo que queda: 1+2+1+1 de 100 desde el 1), sin la guardada
  assert(live and live.list.whole and not whole, "ruta entera: lista viva de toda la ruta")
  assert(live.items[1].it.itemID == 100 and live.items[1].it.need == 5, "ruta entera: pide todo lo que queda")
  ES.db.prof.Alchemy.byPhase = nil
  -- Comprado, a fabricar (Planner.Stocked): con todo lo del tramo se apunta; mientras
  -- puedas fabricar no pide nada más (lo que gastas es lo comprado); si lo gastas sin
  -- poder seguir, pide la tanda siguiente
  do
    local savedCFB = ES.CraftableFromBags
    plan.steps[1].id, plan.steps[2].id = 9001, 9002
    local can = 1
    ES.CraftableFromBags = function(id) return (id == 9001 or id == 9002) and can or nil end
    ES.db.prof.Alchemy.stocked = nil
    -- Al empezar el paso, sin nada: pide el tramo
    have[100] = 0
    local w, ph = P.RouteNeed("Alchemy", plan, 1)
    assert(w[100] and w[100].need == 7 and not ph.hold, "al empezar debería pedir el tramo: " .. tostring(w[100] and w[100].need))
    assert(not ES.db.prof.Alchemy.stocked, "se apunta sin tenerlo todo")
    -- Lo compras todo: se apunta hasta el 5
    have[100] = 7
    P.RouteNeed("Alchemy", plan, 1)
    local m = ES.db.prof.Alchemy.stocked
    assert(m and m.from == 1 and m.to == 5, "no se apunta lo comprado")
    -- Fabricas (gastas) aún en el nivel 1: no vuelve a pedir lo gastado
    have[100] = 4
    w, ph = P.RouteNeed("Alchemy", plan, 1)
    assert(ph.hold and w[100].need == 4, "pide lo que estás gastando: " .. tostring(w[100] and w[100].need))
    level = 3
    w, ph = P.RouteNeed("Alchemy", plan, 3)
    assert(ph.hold and w[100].need <= 4, "en el paso siguiente del tramo vuelve a pedir")
    -- Lo gastas todo en el 2 sin poder seguir: la tanda siguiente desde tu nivel (una
    -- compra), no lo justo para un punto (dos viajes seguidos)
    level, have[100], can = 2, 0, 0
    w, ph = P.RouteNeed("Alchemy", plan, 2)
    local batch = P.PhaseNeed(plan, 2)[100].target
    assert(ph.refill and w[100] and w[100].need == batch, "debería pedir la tanda siguiente: " .. tostring(w[100] and w[100].need) .. " de " .. batch)
    -- Al llegar se olvida y va el tramo siguiente
    level, can = 5, 1
    w, ph = P.RouteNeed("Alchemy", plan, 5)
    assert(not ph.refill and not ph.hold and w[200], "al llegar debería pedir el tramo siguiente")
    plan.steps[1].id, plan.steps[2].id, ES.CraftableFromBags, level, have[100], have[200] = nil, nil, savedCFB, 1, 0, nil
    ES.db.prof.Alchemy.stocked = nil
  end
  -- La ✕ de la lista de una ruta empezada la quita (sin dejar la ruta); una ruta nueva
  -- vuelve a tener la suya (antes no había forma de quitarla de la pestaña)
  local lockA = { from = 1, to = 7, started = 1000 }
  ES.RouteLock = function(_, k) return k == "Alchemy" and lockA or nil end
  local function LiveAlchemy()
    for _, s in ipairs(ES.Shopping.Status().lists) do if s.list.live and s.list.key == "Alchemy" then return s end end
  end
  assert(LiveAlchemy(), "con la ruta empezada sale su lista")
  ES.Shopping.SetRouteListHidden("Alchemy", true)
  assert(not LiveAlchemy() and ES.Shopping.RouteListHidden("Alchemy"), "la ✕ no quitó la lista de la ruta")
  lockA.started = 2000 -- (otra ruta empezada)
  assert(LiveAlchemy(), "una ruta nueva no vuelve a tener su lista")
  ES.Shopping.SetRouteListHidden("Alchemy", true)
  ES.Shopping.SetRouteListHidden("Alchemy", false)
  assert(LiveAlchemy(), "no se vuelve a poner desde la ruta")
  ES.RouteLock = function(_, k) return k == "Alchemy" and { from = 1, to = 7 } or nil end
  -- Avisos, a la par que el asistente (las filas de ES:RouteLines): el primero solo
  -- apunta el tramo; al pasar a C, tramo nuevo; mientras el paso sea fabricar, nada
  -- aunque falte para acabar el tramo; al pasar el paso a comprar, un aviso con lo
  -- mismo que pide la fila
  local rows -- las filas del asistente
  ES.RouteLines = function(_, k) return k == "Alchemy" and rows or nil, plan end
  local craftRow = { level = "5", current = true, stepRecipe = 1 }
  local buyRow = { level = "6", current = true, buyRow = "vendor", buyItems = { { itemID = 200, quantity = 3 } } }
  rows = { { level = "1", current = true, stepRecipe = 1 } }
  ES.phaseState.Alchemy = nil
  ES:PhaseNotices("Alchemy")
  assert(#printed == 0, "al empezar no debería avisar: " .. tostring(printed[1]))
  level, rows = 5, { craftRow }
  ES:PhaseNotices("Alchemy")
  assert(printed[1] and printed[1]:find("C"), "falta el aviso de tramo nuevo: " .. tostring(printed[1]))
  level = 6 -- te faltará para acabar el tramo, pero aún puedes fabricar: nada
  ES:PhaseNotices("Alchemy")
  assert(#printed == 1, "avisa de comprar mientras el asistente pide fabricar: " .. tostring(printed[2]))
  rows = { buyRow, { level = "6", stepRecipe = 1 } } -- sin materiales: el paso es comprar
  ES:PhaseNotices("Alchemy")
  assert(printed[2] and printed[2]:find("3", 1, true), "falta el aviso con lo que pide la fila: " .. tostring(printed[2]))
  ES:PhaseNotices("Alchemy")
  assert(#printed == 2, "el aviso se repite")
  rows = { craftRow } -- compraste: vuelve a fabricar; si te vuelves a quedar sin, otro aviso
  ES:PhaseNotices("Alchemy")
  rows = { buyRow }
  ES:PhaseNotices("Alchemy")
  assert(#printed == 3, "no avisa la segunda vez que te quedas sin materiales")
  end)
  -- Restaurar siempre (si no, un fallo aquí arrastra a las pruebas siguientes)
  ES.RouteLines = saved.RouteLines
  ES.RouteLock, ES.LockedPlan, ES.GetProfessionSkill = saved.RouteLock, saved.LockedPlan, saved.GPS
  ES.ItemCount, ES.Print, ES.charData = saved.ItemCount, saved.Print, saved.charData
  ES.db.prof.Alchemy.byPhase = saved.byPhase
  ES.phaseState.Alchemy = nil
  if not ok then error(err, 0) end
end)
-- (Receta en la bolsa, clic para aprenderla: el botón seguro compartido de las filas, en
-- las pruebas de tools/tests/categories/route.lua, GitHub #11)
step("vender parte de una pila: se parte y se vende lo justo", function()
  -- 17 Elixir of Ogre Strength en una pila, hay que vender 12: antes no vendía ninguno
  local ID = 3391
  local bag0 = { { ID, 17 }, false, false }
  local used, splitTo, timers = {}, nil, {}
  local cursor
  local saved = { CC = C_Container, open = ES.Ledger.MerchantOpen, after = C_Timer.After }
  C_Container = {
    GetContainerNumSlots = function(b) return b == 0 and 3 or 0 end,
    GetContainerItemID = function(b, s) local e = b == 0 and bag0[s] return e and e[1] or nil end,
    GetContainerItemInfo = function(b, s) local e = b == 0 and bag0[s] return e and { stackCount = e[2] } or nil end,
    GetContainerNumFreeSlots = function(b) return b == 0 and 2 or 0, 0 end,
    UseContainerItem = function(b, s) used[#used + 1] = { s, bag0[s] and bag0[s][2] } bag0[s] = false end,
    SplitContainerItem = function(b, s, n) bag0[s][2] = bag0[s][2] - n cursor = { bag0[s][1], n } end,
    PickupContainerItem = function(b, s) bag0[s] = cursor cursor = nil splitTo = s end,
  }
  ES.Ledger.MerchantOpen = function() return true end
  C_Timer.After = function(_, fn) timers[#timers + 1] = fn end
  local ok, err = pcall(function()
    local sold = ES.Ledger:SellToVendor(ID, 12)
    assert(sold == 12 and splitTo == 2 and bag0[1][2] == 5, "no partió la pila: " .. tostring(sold))
    for _, fn in ipairs(timers) do fn() end
    assert(#used == 1 and used[1][1] == 2 and used[1][2] == 12, "no vendió la pila de 12")
    -- Sin hueco libre: avisa en vez de no hacer nada
    bag0 = { { ID, 17 }, { 1, 1 }, { 2, 1 } }
    used = {}
    C_Container.GetContainerNumFreeSlots = function() return 0, 0 end
    local printed, savedPrint = {}, ES.Print
    ES.Print = function(_, m) printed[#printed + 1] = m end
    sold = ES.Ledger:SellToVendor(ID, 12)
    ES.Print = savedPrint
    assert(sold == 0 and #used == 0 and printed[1] and printed[1]:find("hueco"), "sin hueco debería avisar: " .. tostring(printed[1]))
  end)
  C_Container, ES.Ledger.MerchantOpen, C_Timer.After = saved.CC, saved.open, saved.after
  if not ok then error(err, 0) end
end)
step("asistente: bajar la cuenta del mismo paso no es un paso nuevo", function()
  -- Discord: al fabricar, "Fabrica 136×" -> "135×" hacía el destello de paso nuevo
  local A = ES.Assistant
  local a = A.LineKey({ title = "Fabrica 136× Bolt of Linen Cloth", level = "72" })
  assert(a == A.LineKey({ title = "Fabrica 135× Bolt of Linen Cloth", level = "72" }), "misma fila con otra cuenta: el mismo paso")
  assert(a ~= A.LineKey({ title = "Fabrica 136× Bolt of Linen Cloth", level = "80" }), "otro nivel: otro paso")
  assert(a ~= A.LineKey({ title = "Fabrica 136× Linen Belt", level = "72" }), "otra receta: otro paso")
end)
step("vender al vendedor: de una en una, sin que el servidor se salte ninguna", function()
  -- Discord: Vender todo con 17 Linen Belt (no se apilan) vendía unas cuantas y había
  -- que pulsar varias veces: 17 ventas en el mismo instante y el servidor se saltaba algunas
  local BELT = 7026
  local bag0, used, timers, locked = {}, {}, {}, {}
  for i = 1, 17 do bag0[i] = { BELT, 1 } end
  local saved = { CC = C_Container, open = ES.Ledger.MerchantOpen, after = C_Timer.After }
  C_Container = {
    GetContainerNumSlots = function(bag) return bag == 0 and #bag0 or 0 end,
    GetContainerItemID = function(bag, slot) return bag == 0 and bag0[slot] and bag0[slot][1] or nil end,
    GetContainerItemInfo = function(bag, slot) local b = bag == 0 and bag0[slot] return b and { stackCount = b[2], isLocked = locked[slot] } end,
    UseContainerItem = function(bag, slot) used[#used + 1] = slot bag0[slot] = nil end,
  }
  local open = true
  ES.Ledger.MerchantOpen = function() return open end
  C_Timer.After = function(_, fn) timers[#timers + 1] = fn end
  local function Tick() local fn = table.remove(timers, 1) if fn then fn() return true end end
  local ok, err = pcall(function()
    ES.Ledger.sellQueue, ES.Ledger.selling = {}, nil
    locked[2] = true
    local n = ES.Ledger:SellToVendor(BELT, 17)
    assert(n == 17, "dice que vende 17: " .. n)
    assert(#used == 1, "una venta por vez, no todas de golpe: " .. #used)
    Tick() -- la 2 está bloqueada: espera
    assert(#used == 1, "con la casilla bloqueada, espera")
    locked[2] = nil
    for _ = 1, 10 do Tick() end
    assert(#used == 11, "una por tic: " .. #used)
    -- Se cierra el vendedor: la cola se para (lo que queda no se usa: ¡se equiparía!)
    open = false
    while Tick() do end
    assert(#used == 11 and not ES.Ledger.selling and #ES.Ledger.sellQueue == 0, "cerrado el vendedor, no vende más")
    -- Otra vez abierto: vende lo que queda, todo
    open = true
    ES.Ledger:SellToVendor(BELT, 17)
    while Tick() do end
    assert(#used == 17, "al final, las 17: " .. #used)
  end)
  C_Container, ES.Ledger.MerchantOpen, C_Timer.After = saved.CC, saved.open, saved.after
  ES.Ledger.sellQueue, ES.Ledger.selling = {}, nil
  if not ok then error(err, 0) end
  log[#log+1] = "     vender: 17 sin apilar, de una en una; espera a la bloqueada y para al cerrar"
end)
step("flechas para pasar de profesión (Subir profesiones y Colección)", function()
  local f = ES:GetMainFrame()
  local savedSkill = ES.GetProfessionSkill
  -- Tienes Alquimia: va primera, luego el resto en el orden de siempre
  ES.GetProfessionSkill = function(_, line) if line == ES.Data.Alchemy.skillLine then return 100, 150 end end
  local ok, err = pcall(function()
    ES:SelectPage("home")
    assert(f.prevPage._shown == false and f.nextPage._shown == false, "en la portada no hay flechas")
    ES:SelectPage("Alchemy")
    assert(f.prevPage._shown and f.nextPage._shown, "dentro de una profesión salen las flechas")
    local list = ES:SiblingPages("Alchemy")
    assert(list[1] == "Alchemy" and #list > 2, "tus profesiones primero: " .. tostring(list[1]))
    f.nextPage._scripts.OnClick(f.nextPage)
    assert(ES.db.lastPage == list[2], "la flecha siguiente no pasó a " .. tostring(list[2]))
    f.prevPage._scripts.OnClick(f.prevPage)
    f.prevPage._scripts.OnClick(f.prevPage)
    assert(ES.db.lastPage == list[#list], "desde la primera, la anterior da la vuelta: " .. tostring(ES.db.lastPage))
    -- En la colección, entre las colecciones
    ES:SelectPage("pattern:Alchemy")
    f.nextPage._scripts.OnClick(f.nextPage)
    assert(tostring(ES.db.lastPage):match("^pattern:") and ES.db.lastPage ~= "pattern:Alchemy", "en la colección: " .. tostring(ES.db.lastPage))
  end)
  ES.GetProfessionSkill = savedSkill
  ES:SelectPage("home")
  if not ok then error(err, 0) end
end)
step("tooltip del objeto al pasar por su icono", function()
  local row = ES.UI.CreateRow(CreateFrame("Frame"))
  ES.UI.StyleRow(row, { title = "45× Sweet Nectar", icon = 134400, item = 2318 })
  assert(row.iconHover._shown ~= false, "el icono de un objeto debería tener tooltip")
  local link
  local savedSet = GameTooltip.SetHyperlink
  GameTooltip.SetHyperlink = function(_, l) link = l end
  row.iconHover._scripts.OnEnter(row.iconHover)
  GameTooltip.SetHyperlink = savedSet
  assert(link == "item:2318", "no enseña el tooltip del objeto: " .. tostring(link))
  ES.UI.StyleRow(row, { title = "Total", total = true })
  assert(row.iconHover._shown == false, "una fila sin objeto no debería tener tooltip de icono")
end)
step("ruta: los materiales fabricados por el camino también dan puntos", function()
  -- Discord: 63 Rough Dynamite pedían 63 Rough Blasting Powder, que ya subían puntos
  local CB = ES.Planner.CraftBonus
  local eng = { data = ES.Data.Engineering }
  local powder = { { kind = "craft", recipe = 3918, qty = 2, item = 4357 } } -- Rough Blasting Powder
  assert(math.abs(CB(eng, powder, 10) - 2) < 1e-6, "en naranja, cada pólvora da un punto")
  local yellow = CB(eng, powder, 30)
  assert(yellow > 0 and yellow < 2, "en amarillo/verde, menos: " .. yellow)
  assert(CB(eng, powder, 40) == 0, "en gris, nada")
  assert(CB(eng, { { kind = "ah", item = 4357, qty = 2 } }, 10) == 0, "comprada no da puntos")
  -- Las "intermediate" (Cured Thick Hide) y las conversiones no dan puntos
  local ctx = { data = { recipes = { [1] = { intermediate = true, t = { 1, 175, 175, 175 }, out = { 9, 1 } } } } }
  assert(CB(ctx, { { kind = "craft", recipe = 1, qty = 10 } }, 50) == 0, "un intermedio marcado no da puntos")
end)
step("parar de fabricar al llegar al tope o al final de la ruta", function()
  local saved = { GPS = ES.GetProfessionSkill, T = C_TradeSkillUI, Print = ES.Print, RouteLock = ES.RouteLock, LockedPlan = ES.LockedPlan }
  local rank, cap, stopped, printed = 148, 150, 0, {}
  ES.GetProfessionSkill = function(_, line) if line == ES.Data.Alchemy.skillLine then return rank, cap end end
  ES.RouteLock = function() return nil end
  C_TradeSkillUI = { GetRecipeRepeatCount = function() return 5 end, StopRecipeRepeat = function() stopped = stopped + 1 end }
  ES.Print = function(_, m) printed[#printed + 1] = m end
  local ok, err = pcall(function()
    ES.lastRanks = {}
    ES:CheckCraftStop() -- (punto de partida)
    rank = 149
    ES:CheckCraftStop()
    assert(stopped == 0, "a 149 de 150 no debería parar")
    rank = 150
    ES:CheckCraftStop()
    assert(stopped == 1 and printed[1] and printed[1]:find("tope"), "al llegar al tope debería parar: " .. tostring(printed[1]))
    -- Final de la ruta (antes del tope)
    rank, cap, printed = 99, 225, {}
    ES.lastRanks = {}
    ES.RouteLock = function(_, k) return k == "Alchemy" and { from = 1, to = 100 } or nil end
    ES:CheckCraftStop()
    rank = 100
    ES:CheckCraftStop()
    assert(stopped == 2 and printed[1]:find("final de la ruta"), "al acabar la ruta debería parar")
    -- Sin fabricación en serie: nada que parar ni avisar
    C_TradeSkillUI.GetRecipeRepeatCount = function() return 0 end
    rank, printed = 101, {}
    ES.RouteLock = function(_, k) return k == "Alchemy" and { from = 1, to = 101 } or nil end
    ES:CheckCraftStop()
    assert(stopped == 2 and #printed == 0, "sin nada en marcha no debería avisar")
    -- Al acabar un paso (sin llegar al tope ni al final de la ruta) NO se para: se quitó
    -- porque paraba cuando no tocaba (Discord)
    C_TradeSkillUI.GetRecipeRepeatCount = function() return 5 end
    ES.RouteLock = function(_, k) return k == "Alchemy" and { from = 1, to = 100 } or nil end
    ES.lastRanks, printed = {}, {}
    rank = 49 ES:CheckCraftStop()
    rank = 50 ES:CheckCraftStop()
    assert(stopped == 2 and #printed == 0, "a mitad de ruta no para")
  end)
  ES.GetProfessionSkill, C_TradeSkillUI, ES.Print, ES.RouteLock = saved.GPS, saved.T, saved.Print, saved.RouteLock
  ES.LockedPlan = saved.LockedPlan
  ES.lastRanks = {}
  if not ok then error(err, 0) end
end)
step("barra de progreso al calcular la ruta", function()
  local P = ES.Planner
  local saved = { run = ES.planRunning, passes = P.passes, db = ES.db.planPasses }
  local ok, err = pcall(function()
    -- La última vez, 200 pasadas para 100 niveles: a 100 pasadas, la mitad
    ES.db.planPasses = { Alchemy = { passes = 200, span = 100 } }
    ES.planRunning = { prof = "Alchemy", span = 100 }
    P.passes = 100
    assert(math.abs(ES:PlanProgress("Alchemy") - 0.5) < 1e-6, "a mitad: " .. ES:PlanProgress("Alchemy"))
    -- Tramo el doble de largo: se espera el doble
    ES.planRunning.span = 200
    assert(math.abs(ES:PlanProgress("Alchemy") - 0.25) < 1e-6, "tramo más largo")
    -- Pasada la previsión: se acerca al 99% sin llegar
    P.passes = 2000
    local p = ES:PlanProgress("Alchemy")
    assert(p > 0.9 and p < 0.99, "pasada la previsión: " .. p)
    -- Sin cálculo en marcha para esa profesión: nada
    assert(ES:PlanProgress("Tailoring") == nil, "otra profesión no se está calculando")
    -- La página: barra y porcentaje mientras calcula; sin calcular, se esconde
    local page
    for _, pg in ipairs(ES.professionPages) do if pg.profKey == "Alchemy" then page = pg end end
    if page and page.calcBar then
      P.passes, ES.planRunning.span = 100, 100
      page.calculating = true
      ES:UpdateCalcProgress(page)
      assert(page.calcBar._shown and tostring(page.status._text):find("50%%"), "falta la barra: " .. tostring(page.status._text))
      page.calculating = nil
      ES:UpdateCalcProgress(page)
      assert(page.calcBar._shown == false, "la barra debería esconderse al acabar")
    end
  end)
  ES.planRunning, P.passes, ES.db.planPasses = saved.run, saved.passes, saved.db
  if not ok then error(err, 0) end
end)
step("pestañas: vuelven a donde estabas, no a su portada", function()
  local f = ES:GetMainFrame()
  local function Tab(key) for _, t in ipairs(f.tabs) do if t.key == key then return t end end end
  ES:SelectPage("Alchemy")
  Tab("shopping")._scripts.OnClick(Tab("shopping"))
  assert(ES.db.lastPage == "shopping", "no fue a la lista de compra")
  Tab("home")._scripts.OnClick(Tab("home"))
  assert(ES.db.lastPage == "Alchemy", "Subir profesiones debería volver a Alquimia: " .. tostring(ES.db.lastPage))
  -- El botón "Profesiones" sí lleva a la portada, y la pestaña recuerda la portada
  f.back._scripts.OnClick(f.back)
  assert(ES.db.lastPage == "home", "el botón Profesiones lleva a la portada")
  Tab("shopping")._scripts.OnClick(Tab("shopping"))
  Tab("home")._scripts.OnClick(Tab("home"))
  assert(ES.db.lastPage == "home", "tras volver a la portada, la pestaña abre la portada")
  -- Colección: igual
  ES:SelectPage("pattern:Alchemy")
  ES:SelectPage("home")
  Tab("patterns")._scripts.OnClick(Tab("patterns"))
  assert(ES.db.lastPage == "pattern:Alchemy", "la colección debería volver a Alquimia")
  ES:SelectPage("home")
end)
step("lista de compra: añadir tramo o ruta entera, con aviso", function()
  local f = ES:GetMainFrame()
  local saved = { lock = ES.RouteLock, locked = ES.LockedPlan, play = PlaySound, print = ES.Print }
  local played, printed = 0, {}
  PlaySound = function() played = played + 1 end
  ES.Print = function(_, m) printed[#printed + 1] = m end
  local ok, err = pcall(function()
    local page
    for _, p in ipairs(ES.professionPages) do if p.profKey == "Leatherworking" then page = p end end
    local opts = ES:PlanOptions("Leatherworking", page.from or 1, 225, nil)
    opts.owned = nil
    local plan = ES.Planner:Plan(ES.Data.Leatherworking, opts)
    ES.RouteLock = function(_, k) return k == "Leatherworking" and { from = plan.from, to = 225 } or nil end
    ES.LockedPlan = function(_, k) return k == "Leatherworking" and plan or nil end
    page.plan, page.view = plan, "shop"
    ES:RenderPlan(page)
    local line
    for _, l in ipairs(page.lines) do if l.phaseLine then line = l end end
    assert(line and line.onClick and line.title:find("Tramo"), "falta la fila de la lista de compra (por tramos)")
    assert(line.sub:find("Pulsa para cambiar a la ruta entera"), "el texto debería decir qué hace pulsar: " .. tostring(line.sub))
    line.tooltip(CreateFrame("Frame"))
    line.onClick() -- (pulsar la fila: pasa a la ruta entera)
    assert(ES.db.prof.Leatherworking.byPhase == false, "no pasó a ruta entera")
    for _, l in ipairs(page.lines) do if l.phaseLine then line = l end end
    assert(line.title:find("Ruta entera") and line.sub:find("solo este tramo"), "la fila debería decir ruta entera: " .. tostring(line.title))
    assert(printed[1] and printed[1]:find("Añadido"), "falta el aviso en el chat")
    assert(played == 1, "falta el sonido")
    local shopTab
    for _, t in ipairs(f.tabs) do if t.key == "shopping" then shopTab = t end end
    assert(shopTab.flashing, "la pestaña Lista de compra debería brillar")
    line.onClick() -- (y otra vez: vuelve a tramos)
    assert(ES.db.prof.Leatherworking.byPhase == nil, "no volvió a tramos")
  end)
  ES.RouteLock, ES.LockedPlan, PlaySound, ES.Print = saved.lock, saved.locked, saved.play, saved.print
  ES.db.prof.Leatherworking.byPhase = nil
  for _, p in ipairs(ES.professionPages) do if p.profKey == "Leatherworking" then p.view = "route" end end
  if not ok then error(err, 0) end
end)
step("ruta: lo que aún da puntos no se fabrica como preparación", function()
  -- (Rough Blasting Powder: la ruta decía "fabrica 133 a nivel 1" y subían la profesión
  -- sin contar; tiene que ser un paso de la ruta, o fabricarse cuando ya está en gris)
  local checked = 0
  for _, prof in ipairs({ "Leatherworking", "Tailoring", "Blacksmithing", "Alchemy", "Engineering", "Enchanting" }) do
    local opts = ES:PlanOptions(prof, 1, 225, nil)
    opts.owned = nil
    local plan = ES.Planner:Plan(ES.Data[prof], opts)
    for _, c in ipairs(plan.crafted or {}) do
      local r = c.recipe
      if r and c.from and not r.intermediate and not r.conversion then
        local isTool = false
        for _, t in pairs(ES.Data.Tools or {}) do if t.item == c.itemID then isTool = true end end
        assert(isTool or ES.Planner.Chance(r.t, c.from) == 0,
          string.format("%s: fabrica %d %s como preparación a %d, donde aún da puntos", prof, c.quantity, r.name or "?", c.from))
        checked = checked + 1
      end
    end
  end
  log[#log+1] = "     preparación revisada: " .. checked .. " materiales"
  -- Todas las rutas, como las ves: la columna de nivel nunca baja; nada que dé puntos se
  -- compra y además se fabrica; y ningún paso usa algo fabricado que salga después
  local routes = 0
  for _, prof in ipairs({ "Leatherworking", "Tailoring", "Blacksmithing", "Alchemy", "Engineering", "Enchanting", "Cooking", "FirstAid" }) do
    local page
    for _, p in ipairs(ES.professionPages) do if p.profKey == prof then page = p end end
    for _, rg in ipairs({ { 1, 225 }, { 150, 300 } }) do
      local opts = ES:PlanOptions(prof, rg[1], rg[2], nil)
      opts.owned = nil
      local plan = ES.Planner:Plan(ES.Data[prof], opts)
      if page and #plan.steps > 0 then
        routes = routes + 1
        local where = string.format("%s %d-%d", prof, rg[1], rg[2])
        page.plan, page.view = plan, "route"
        ES:RenderPlan(page)
        local last = 0
        for _, l in ipairs(page.lines) do
          local n = l.level and tonumber(tostring(l.level):match("^(%d+)"))
          if n then
            assert(n >= last, string.format("%s no va en orden: %s después de %d (%s)", where, tostring(l.level), last, tostring(l.title)))
            last = n
          end
        end
        -- La mezcla confusa: comprar un material en un paso mientras aún da puntos y
        -- fabricarlo más tarde (la pólvora: comprada de 3 a 40, fabricada desde 40)
        for _, c in ipairs(plan.crafted or {}) do
          local r = c.recipe
          if r and c.from and not r.intermediate and not r.conversion then
            for _, st in ipairs(plan.steps) do
              for _, rg2 in ipairs(st.reagents or {}) do
                local buys = rg2.kinds and (rg2.kinds.ah or rg2.kinds.vendor)
                if rg2.item == c.itemID and buys and st.from < c.from and ES.Planner.Chance(r.t, st.from) > 0 then
                  error(string.format("%s: %s se compra en %s %d-%d (cuando aún da puntos) y se fabrica desde %d",
                    where, tostring(r.name), st.recipe.name, st.from, st.to, c.from), 0)
                end
              end
            end
          end
        end
        -- Lo "tuyo de la ruta" (stock) de un paso sale de un paso anterior
        local made = {}
        for _, st in ipairs(plan.steps) do
          for _, rg2 in ipairs(st.reagents or {}) do
            if rg2.kinds and rg2.kinds.stock then
              assert(made[rg2.item], string.format("%s: %s usa %s de un paso que va después", where, st.recipe.name, tostring(ES:DataItemName(rg2.item))))
            end
          end
          if st.sale then made[st.sale.itemID] = true end
        end
      end
    end
  end
  log[#log+1] = "     rutas revisadas (orden, mezclas, de dónde sale cada material): " .. routes
  for _, p in ipairs(ES.professionPages) do p.view = "route" end
end)
step("ruta parada: con lo que llevas se puede intentar el punto siguiente", function()
  -- Herrería 60 sin AH, 2 Rough Stone y 4 Copper Bar (Discord): ningún punto
  -- seguro, pero Rough Grinding Stone al 62% sí se puede probar
  local data, yes = ES.Data.Blacksmithing, function() return true end
  local t = ES.Planner.Attempt(data, 60, { [2835] = 2, [2840] = 4 }, yes)
  assert(t and t.recipe.name and t.crafts == 1 and math.abs(t.prob - 0.625) < 0.01, "no propone intentarlo")
  assert(not ES.Planner.Attempt(data, 60, { [2835] = 1 }, yes), "con 1 piedra no cabe ninguna")
  assert(not ES.Planner.Attempt(data, 60, { [2835] = 2, [2840] = 4 }, function() return false end), "solo recetas que sabes")
end)
step("máximo 300: el objetivo llega hasta 300", function()
  assert(ES.MAX_SKILL == 300, "el máximo debería ser 300")
  ES.db.prof.Tailoring = ES.db.prof.Tailoring or {}
  local t = ES.db.prof.Tailoring
  local savedT, savedLock = t.target, t.lock
  t.target, t.lock = 260, nil
  assert(ES:ProfessionTarget("Tailoring") == 260, "un objetivo entre 225 y 300 no debería recortarse")
  t.target = nil
  -- Sin objetivo: el final de tu tope (150, 225 o 300), no tu nivel + 150 (151, 152...)
  local savedSkill = ES.GetProfessionSkill
  local rank = 1
  ES.GetProfessionSkill = function(_, line) if line == ES.Data.Tailoring.skillLine then return rank, 150 end end
  for _, c in ipairs({ { 1, 150 }, { 2, 150 }, { 149, 150 }, { 150, 225 }, { 224, 225 }, { 225, 300 }, { 299, 300 }, { 300, 300 } }) do
    rank = c[1]
    assert(ES:ProfessionTarget("Tailoring") == c[2], string.format("sin objetivo, con %d debería ser %d y es %d", c[1], c[2], ES:ProfessionTarget("Tailoring")))
  end
  rank = 60
  -- Calcular con el de por defecto no lo guarda (sube contigo); uno escrito, sí
  local page
  for _, p in ipairs(ES.professionPages) do if p.profKey == "Tailoring" then page = p end end
  if page and page.toBox then
    rank = 60
    ES:DetectSkill(page)
    page.toBox._text = "150" -- (con 60, el de por defecto: el final del tope, 150)
    ES:CalculatePlan(page)
    assert(t.target == nil, "el objetivo por defecto no debería guardarse: " .. tostring(t.target))
    page.toBox._text = "250"
    ES:CalculatePlan(page)
    assert(t.target == 250, "el objetivo escrito debería guardarse")
  end
  ES.GetProfessionSkill = savedSkill
  t.target, t.lock = savedT, savedLock
end)
step("sin icono de la Casa de Subastas: la ruta siempre puede usarla", function()
  local page
  for _, p in ipairs(ES.professionPages) do if p.profKey == "Enchanting" then page = p end end
  assert(page.ahButton == nil, "el icono de la Casa de Subastas debería haberse quitado")
  assert(ES:PlanOptions("Enchanting", 1, 50).noAH == nil, "la ruta siempre usa la AH")
end)
step("objetos que llegan: solo recalcula por los que esperaba, y nunca a mitad de cálculo", function()
  local page
  for _, p in ipairs(ES.professionPages) do if p.profKey == "Enchanting" then page = p end end
  local savedAfter, savedCalc, savedPlan, savedVisible = C_Timer.After, ES.CalculatePlan, page.plan, page.IsVisible
  local timers, calcs = {}, 0
  C_Timer.After = function(_, fn) timers[#timers + 1] = fn end
  ES.CalculatePlan = function() calcs = calcs + 1 end
  page.IsVisible = function() return true end
  local function Flush() local t = timers timers = {} for _, fn in ipairs(t) do fn() end end
  page.plan = { pendingInfo = true, pendingItems = { [11288] = true }, steps = {} }
  page.pendingItems, page.refreshQueued, page.recalcQueued, page.calculating = nil, nil, nil, nil
  local onEvent = page:GetScript("OnEvent")
  -- Un objeto cualquiera (bolsas, chat, los que pide el propio cálculo): nada
  onEvent(page, "GET_ITEM_INFO_RECEIVED", 2589, true)
  Flush()
  assert(calcs == 0, "recalculó por un objeto que la ruta no esperaba")
  -- Uno que esperaba, a mitad de cálculo: no tira lo calculado
  page.calculating = true
  onEvent(page, "GET_ITEM_INFO_RECEIVED", 11288, true)
  Flush()
  assert(calcs == 0, "recalculó a mitad de cálculo (tira lo hecho)")
  assert(page.recalcQueued, "debería recalcular al acabar")
  -- Sin calcular: una vez
  page.calculating = nil
  onEvent(page, "GET_ITEM_INFO_RECEIVED", 11288, true)
  Flush()
  assert(calcs == 1, "no recalculó con el precio que esperaba: " .. calcs)
  -- Una oleada (varios seguidos): un solo cálculo, al parar
  onEvent(page, "GET_ITEM_INFO_RECEIVED", 11288, true)
  onEvent(page, "GET_ITEM_INFO_RECEIVED", 11288, true)
  onEvent(page, "GET_ITEM_INFO_RECEIVED", 11288, true)
  Flush()
  assert(calcs == 2, "una oleada de objetos debería recalcular una sola vez: " .. calcs)
  C_Timer.After, ES.CalculatePlan, page.plan, page.IsVisible = savedAfter, savedCalc, savedPlan, savedVisible
  page.recalcQueued, page.refreshQueued = nil, nil
end)
step("fabricando: la ruta sin empezar se recalcula una vez al parar; cambiar de idioma no deja rutas viejas en cola", function()
  local page
  for _, p in ipairs(ES.professionPages) do if p.profKey == "Enchanting" then page = p end end
  local saved = { After = C_Timer.After, Calc = ES.CalculatePlan, Render = ES.RenderPlan, Visible = page.IsVisible,
    GT = GetTime, last = ES.lastCraftAt, dps = debugprofilestop }
  local ok, err = pcall(function()
    local timers, calcs, renders, clock = {}, 0, 0, 100
    C_Timer.After = function(_, fn) timers[#timers + 1] = fn end
    ES.CalculatePlan = function() calcs = calcs + 1 end
    ES.RenderPlan = function() renders = renders + 1 end
    page.IsVisible = function() return true end
    GetTime = function() return clock end
    local function Flush() local t = timers timers = {} for _, fn in ipairs(t) do fn() end end
    -- Sin fabricar: al momento
    ES.lastCraftAt = nil
    ES:RecalcWhenQuiet(page)
    assert(calcs == 1, "sin fabricar debería recalcular al momento")
    -- Fabricando: repinta la de antes y espera; cada bolsa nueva no recalcula
    ES.lastCraftAt = clock - 1
    ES:RecalcWhenQuiet(page)
    ES:RecalcWhenQuiet(page)
    assert(calcs == 1 and renders >= 1, "recalculó mientras fabricabas")
    clock = clock + 10
    Flush()
    assert(calcs == 2, "al dejar de fabricar debería recalcular una sola vez: " .. calcs)
    -- Rutas viejas en la cola (otra ventana, otro idioma): se descartan al vaciar la caché
    debugprofilestop = function() return 0 end
    ES.Jobs.Run("plan:Tailoring:old", "v1", function() return {} end, function() end, "old")
    ES.Jobs.Run("better:Tailoring", "v2", function() return {} end, function() end, "x", true)
    assert(ES.Jobs.Queued("plan:"), "el trabajo de prueba no quedó en cola")
    ES:ClearHomeCache()
    assert(not ES.Jobs.Queued("plan:"), "las rutas viejas siguen en cola tras vaciar la caché")
    assert(ES.Jobs.Busy("better:Tailoring"), "se quitó un trabajo que no era de rutas")
    ES.Jobs.Cancel("better:")
    Flush() -- (el paso de la cola que quedó pendiente: con la cola vacía, la deja lista)
  end)
  C_Timer.After, ES.CalculatePlan, ES.RenderPlan, page.IsVisible = saved.After, saved.Calc, saved.Render, saved.Visible
  GetTime, ES.lastCraftAt, debugprofilestop = saved.GT, saved.last, saved.dps
  if not ok then error(err, 0) end
end)
step("conversión de esencias: dice cuáles, cuántas veces y que se compran antes", function()
  local page
  for _, p in ipairs(ES.professionPages) do if p.profKey == "Enchanting" then page = p end end
  local savedDetect, savedCount = ES.DetectSkill, ES.ItemCount
  ES.DetectSkill = function(_, pg) pg.from = 28 end
  ES.ItemCount = function() return 0 end
  ES.db.prof.Enchanting = ES.db.prof.Enchanting or {}
  ES.db.prof.Enchanting.target, ES.db.prof.Enchanting.lock = 225, nil
  page.toBox._text = "225"
  ES:DetectSkill(page)
  ES:CalculatePlan(page)
  ES:SelectProfessionView(page, "route")
  local conv
  for _, l in ipairs(page.lines) do if l.title and l.title:find("^Convierte") then conv = l end end
  local hasConv = false
  for _, c in ipairs(page.plan and page.plan.crafted or {}) do if c.recipe and c.recipe.conversion then hasConv = true end end
  assert(not hasConv or conv, "la ruta convierte esencias pero no hay fila que lo explique")
  if conv then
    assert(conv.sub:find("veces") and conv.sub:find("cómpralas"), "la conversión no explica qué hacer: " .. tostring(conv.sub))
    log[#log+1] = "     " .. conv.title .. " · " .. conv.sub
  else
    log[#log+1] = "     (esta ruta no convierte esencias)"
  end
  -- Herramientas fabricadas (Runed Golden Rod): en el nivel donde hacen falta, y sin
  -- ✕ si no se pueden comprar (se ligan al recogerlas)
  local toolSkill = {}
  for _, tl in ipairs(page.plan and page.plan.tools or {}) do toolSkill[tl.item] = tl.skill end
  for _, l in ipairs(page.lines) do
    if l.item and toolSkill[l.item] and l.title and l.title:find("^Fabrica") then
      assert(tonumber(l.level) == toolSkill[l.item], string.format("herramienta fuera de sitio: %s en %s (hace falta en %d)", l.title, tostring(l.level), toolSkill[l.item]))
      if l.sub:find("no se puede comprar") then assert(not l.onSkip, "una herramienta que no se puede comprar no debería tener la ✕") end
      log[#log+1] = "     " .. l.level .. " · " .. l.title .. " · " .. l.sub
    end
  end
  -- Ya tienes la herramienta (comprada o fabricada por ti): su fila sale hecha
  local tool = page.plan and page.plan.tools and page.plan.tools[1]
  if tool then
    local count = ES.ItemCount
    ES.ItemCount = function(self, id) if id == tool.item then return 1 end return count(self, id) end
    ES:RenderPlan(page)
    local toolLine
    for _, l in ipairs(page.lines) do
      if l.item == tool.item and l.title and l.title:find("Herramienta") then toolLine = l end
    end
    assert(toolLine and toolLine.done, "con la herramienta en las bolsas, su fila debería salir hecha")
    ES.ItemCount = count
    log[#log+1] = "     herramienta en las bolsas: fila hecha (" .. tostring(toolLine.sub) .. ")"
  end
  ES.DetectSkill, ES.ItemCount = savedDetect, savedCount
end)
step("ruta empezada: aviso de ruta mejor (cambiar o seguir con la tuya)", function()
  local page
  for _, p in ipairs(ES.professionPages) do if p.profKey == "Leatherworking" then page = p end end
  local lp = ES.db.prof.Leatherworking
  local saved = { lock = lp.lock, plan = page.plan, view = page.view, Print = ES.Print }
  ES.Print = function() end
  local from, to = page.from or 1, tonumber(page.toBox:GetText()) or 225
  local opts = ES:PlanOptions("Leatherworking", from, to, nil)
  local good = ES.Planner:Plan(ES.Data.Leatherworking, opts)
  assert(#good.steps > 1, "la ruta de prueba debería tener varios pasos")
  -- Ruta empezada mala: la receta del primer paso para todo (se pone gris y se para)
  local choice = {}
  for s = from, to - 1 do choice[s] = good.steps[1].id end
  lp.lock = { from = from, to = to, choice = choice, via = {}, started = 777 }
  ES.lockedPlans.Leatherworking, ES.betterCache.Leatherworking = nil, nil
  page.plan, page.view = ES:LockedPlan("Leatherworking"), "route"
  -- Abrir la página: se busca una vez y sale el aviso arriba
  page.shownToken, page.betterAsked = (page.shownToken or 0) + 1, nil
  ES:RenderPlan(page)
  local better = page.lines[1]
  assert(better and tostring(better.title):find("ruta mejor"), "falta el aviso de ruta mejor: " .. tostring(better and better.title))
  assert(better.onClick and better.onSkip, "el aviso debería poder pulsarse y descartarse")
  -- Repintar (comprar, fabricar) no vuelve a calcular
  local runs = 0
  local savedRun = ES.Jobs.Run
  ES.Jobs.Run = function(...) runs = runs + 1 return savedRun(...) end
  ES:RenderPlan(page)
  ES.Jobs.Run = savedRun
  assert(runs == 0, "repintar la página volvió a buscar una ruta mejor")
  -- ✕: sigues con la tuya y esa alternativa no vuelve a salir
  better.onSkip()
  assert(not tostring(page.lines[1].title):find("ruta mejor"), "descartado, el aviso sigue saliendo")
  assert(lp.lock and lp.lock.started == 777, "descartar el aviso no debería cambiar la ruta")
  -- Clic: la nueva pasa a ser tu ruta empezada
  lp.lock.keepMine = nil
  ES:RenderPlan(page)
  page.lines[1].onClick()
  assert(lp.lock and lp.lock.started ~= 777, "al pulsar el aviso no cambió de ruta")
  assert(lp.lock.choice[from] ~= nil and ES:LockedPlan("Leatherworking").reached >= good.reached, "la ruta nueva no llega tan lejos")
  log[#log+1] = "     aviso: " .. tostring(better.title):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  lp.lock, page.plan, page.view, ES.Print = saved.lock, saved.plan, saved.view, saved.Print
  ES.lockedPlans.Leatherworking, ES.betterCache.Leatherworking = nil, nil
end)
step("lista por tramos: en verde, por tandas", function()
  -- Un paso que entra en verde: la lista no pide todo el tramo con colchón, sino una
  -- tanda (~BATCH_CRAFTS fabricaciones) sin colchón; la siguiente, al gastarla
  local P = ES.Planner
  -- Un paso con bastante verde (que dé para más de una tanda) y en el que lo que queda
  -- tras la tanda aún gasta materiales (si no, la tanda pide lo mismo que el tramo)
  -- (sin el riesgo en verde al elegir la ruta, Planner.GreenRisk: con él las rutas de
  -- prueba casi no tienen tramos verdes largos, y esto prueba cómo se compran)
  local savedRisk = P.GREEN_RISK
  P.GREEN_RISK = 0
  local function Less(p, s)
    local saved = P.BATCH_CRAFTS
    P.BATCH_CRAFTS = 1e9
    local whole = P.PhaseNeed(p, s.from)
    P.BATCH_CRAFTS = saved
    local batch, ph = P.PhaseNeed(p, s.from)
    if not (ph and ph.batchTo and ph.batchTo < ph.to) then return false end
    for id, n in pairs(batch) do if whole[id] and n.target < whole[id].target then return true, ph end end
    return false
  end
  local plan, st, phase
  for _, prof in ipairs({ "Engineering", "Leatherworking", "Blacksmithing", "Tailoring" }) do
    local opts = ES:PlanOptions(prof, 1, 150, nil)
    opts.owned = nil
    local p = P:Plan(ES.Data[prof], opts)
    for _, s in ipairs(p.steps) do
      if s.to - math.max(s.from, s.recipe.t[3]) >= 4 then
        local ok, ph = Less(p, s)
        if ok then plan, st, phase = p, s, ph break end
      end
    end
    if st then break end
  end
  P.GREEN_RISK = savedRisk -- (solo para elegir la ruta de prueba; lo demás no lo usa)
  assert(st, "ninguna ruta de prueba tiene un paso en verde en el que la tanda pida menos que el tramo entero")
  -- El tamaño de la tanda, en las opciones (ES.db.batchCrafts): más pequeña, llega menos lejos
  do
    local savedBatch = ES.db.batchCrafts
    ES.db.batchCrafts = 20
    local _, small = P.PhaseNeed(plan, st.from)
    ES.db.batchCrafts = 150
    local _, big = P.PhaseNeed(plan, st.from)
    ES.db.batchCrafts = savedBatch
    local smallTo, bigTo = small.batchTo or small.to, big.batchTo or big.to
    assert(smallTo <= bigTo, string.format("tanda de 20 hasta %d, de 150 hasta %d", smallTo, bigTo))
    assert(P.BatchCrafts() == (savedBatch or P.BATCH_CRAFTS), "sin opción, la de por defecto")
    -- En verde, un colchón (GREEN_Z) para no ir a por más a cada rato (Discord: 4-5 viajes
    -- a por Linen Cloth para Red Linen Bag): con él se pide algo más que sin él
    local savedZ = P.GREEN_Z
    P.GREEN_Z = 0
    local bare = P.PhaseNeed(plan, st.from)
    P.GREEN_Z = savedZ
    local cushioned = P.PhaseNeed(plan, st.from)
    local more = false
    for id, n in pairs(cushioned) do
      assert(n.target >= (bare[id] and bare[id].target or 0), "con colchón nunca menos")
      if bare[id] and n.target > bare[id].target then more = true end
    end
    assert(more, "en verde, el colchón pide algo más que lo justo")
    log[#log+1] = string.format("     tanda (opción): de 20 hasta %d, de 150 hasta %d", smallTo, bigTo)
  end
  -- Al subir dentro del verde, la tanda sigue (lo que pide sale desde tu nivel)
  local _, later = P.PhaseNeed(plan, phase.batchTo)
  assert(later and (later.batchTo or later.to) > phase.batchTo, "al acabar una tanda debería venir la siguiente")
  log[#log+1] = string.format("     %s %d-%d: tanda hasta %d", st.recipe.name, phase.from, phase.to, phase.batchTo)
end)
step("recetas de especialización: solo si la tienes", function()
  -- (Goblin, Gnomish, Armorsmith, Dragonscale: las enseña un instructor de esa
  -- especialización; sin ella la ruta no puede usarlas)
  local r
  for id, x in pairs(ES.Data.Engineering.recipes) do if x.spec == "Goblin" then r = x break end end
  assert(r, "faltan recetas marcadas con su especialización en los datos")
  ES.Planner.Annotate(ES.Data.Engineering)
  local saved = ES.HasSpecialization
  ES.HasSpecialization = function() return false end
  assert(ES.Planner.LearnSkill(r, {}) == nil, "sin la especialización, la ruta no debería poder usar " .. r.name)
  ES.HasSpecialization = function(_, spec) return spec == "Goblin" end
  assert(ES.Planner.LearnSkill(r, {}), "con la especialización, " .. r.name .. " debería poder usarse")
  ES.HasSpecialization = saved
  log[#log+1] = "     " .. r.name .. ": solo con " .. r.spec
  -- Patrones que Forever no vende (Spitfire, de Aendel Windspear): no se consiguen
  local spit
  for _, x in pairs(ES.Data.Leatherworking.recipes) do if x.name == "Spitfire Bracers" then spit = x end end
  assert(spit and spit.gone, "Spitfire Bracers debería estar marcada como que no se consigue en Forever")
  ES.Planner.Annotate(ES.Data.Leatherworking)
  assert(ES.Planner.LearnSkill(spit, { includeScrolls = true }) == nil, "la ruta no debería poder usar un patrón que no se consigue")
end)
step("lista de la compra: cuenta lo que hicieron pasos anteriores", function()
  -- (Light Leather del paso 1-26 que gastan las Embossed Leather Pants: si ya no las
  -- llevas, la lista te las pide; antes daba por hecho que las tenías)
  local P = ES.Planner
  local opts = ES:PlanOptions("Leatherworking", 1, 150, nil)
  opts.owned = nil
  local plan = P:Plan(ES.Data.Leatherworking, opts)
  local level, item
  for s = plan.from + 1, plan.reached - 1 do
    for id, u in pairs(plan.pointUse[s] or {}) do
      if (u.stock or 0) > 0 and not (plan.pointNeed[s] and plan.pointNeed[s][id]) then level, item = s, id end
    end
    if level then break end
  end
  assert(level, "la ruta de prueba debería gastar algo hecho en un paso anterior")
  local need = P.NeedFrom(plan, level)
  assert((need[item] or 0) > 0, "la lista no cuenta " .. tostring(ES:DataItemName(item)) .. " hecho en un paso anterior")
  local pn = P.PhaseNeed(plan, level)
  assert(pn[item] and pn[item].target > 0, "la lista del tramo no cuenta lo hecho en un paso anterior")
  log[#log+1] = string.format("     a %d la lista pide %d %s hechos antes (frente a tus bolsas)", level, math.ceil(need[item]), tostring(ES:DataItemName(item)))
  -- Solo lo que de verdad hicieron los pasos ya pasados (no lo de pasos por venir)
  local made = 0
  for s = plan.from, level - 1 do
    local r = ES.Data.Leatherworking.recipes[plan.choice[s]]
    if r and r.out and r.out[1] == item then made = made + r.out[2] / plan.pointChance[s] end
  end
  for _, st in ipairs(plan.steps) do
    if st.to <= level and st.ahead and st.recipe.out[1] == item then
      for _, a in ipairs(st.ahead) do made = made + a.quantity end
    end
  end
  assert(need[item] <= made + 1, string.format("la lista pide %d hechos antes y solo se hicieron %d", need[item], made))
end)
step("Working Overtime: se lee del árbol de legado (las rutas aún no lo cuentan)", function()
  -- Árbol de legado simulado como lo da C_Traits (sistema 45): un nodo con el talento
  local savedT, savedName, savedGSI, savedPrint = C_Traits, C_Spell, GetSpellInfo, ES.Print
  local rank = 5
  C_Traits = {
    GetConfigIDBySystemID = function(id) return id == 45 and 7 or nil end,
    GetConfigInfo = function() return { treeIDs = { 1 } } end,
    GetTreeNodes = function() return { 10, 11 } end,
    GetNodeInfo = function(_, nodeID) return { entryIDs = { nodeID * 10 }, currentRank = nodeID == 11 and rank or 2 } end,
    GetEntryInfo = function(_, entryID) return { definitionID = entryID } end,
    GetDefinitionInfo = function(def) return { spellID = def == 110 and 999001 or 999002 } end,
  }
  C_Spell = nil
  GetSpellInfo = function(id) if id == 999001 then return "Working Overtime" end return "Diplomat" end
  ES.db.overtimeSpell = nil
  local r, spell = ES:ReadWorkingOvertime()
  assert(r == 5 and spell == 999001 and ES.db.overtimeSpell == 999001, "rango y hechizo de Working Overtime: " .. tostring(r))
  -- Por ahora las rutas NO lo cuentan (ES.COUNT_OVERTIME = false): se lee el rango para
  -- el indicador, pero la probabilidad no cambia
  local t = { 1, 100, 125, 150 }
  ES.Planner.SKILL_BONUS = 0
  ES:UpdateSkillUpBonus()
  assert(ES.overtimeRank == 5 and ES.Planner.SKILL_BONUS == 0, "sin contarlo, el rango no cambia las rutas: " .. ES.Planner.SKILL_BONUS)
  assert(math.abs(ES.Planner.Chance(t, 125) - 0.50) < 1e-9, "sin contarlo, verde al 50% se queda en 50%")
  -- Si se activa, multiplica (×1,20), no suma: 50% -> 60%; al final del verde, 2% -> 2,4%
  -- (sumado daba 22%: la ruta pedía menos de la mitad de las fabricaciones)
  ES.COUNT_OVERTIME = true
  ES:UpdateSkillUpBonus()
  assert(math.abs(ES.Planner.SKILL_BONUS - 0.20) < 1e-9, "contándolo, bonus del rango 5: " .. ES.Planner.SKILL_BONUS)
  assert(math.abs(ES.Planner.Chance(t, 125) - 0.60) < 1e-9, "verde al 50% -> 60%: " .. ES.Planner.Chance(t, 125))
  assert(math.abs(ES.Planner.Chance(t, 149) - 0.024) < 1e-9, "al final del verde, 2% -> 2,4%: " .. ES.Planner.Chance(t, 149))
  assert(ES.Planner.Chance(t, 101) == 1, "no pasa del 100%")
  assert(ES.Planner.Chance(t, 50) == 1 and ES.Planner.Chance(t, 150) == 0, "naranja y gris sin cambios")
  local keyWith = ES:PlanKey("Leatherworking", 1, 150, nil)
  rank = 0
  ES:UpdateSkillUpBonus()
  assert(ES.Planner.SKILL_BONUS == 0 and ES:PlanKey("Leatherworking", 1, 150, nil) ~= keyWith, "sin el talento: otra clave de ruta")
  ES.COUNT_OVERTIME = false
  -- Indicador en la cabecera (sin comando: se lee del juego): con rango, icono y
  -- "Working Overtime +12%" en las páginas de rutas; sin rango, nada
  local mf = ES:GetMainFrame()
  rank = 3
  ES:UpdateSkillUpBonus()
  ES:SelectPage("home")
  assert(mf.overtime._shown and tostring(mf.overtime.label._text):find("12"), "indicador con rango 3: " .. tostring(mf.overtime.label._text))
  ES:SelectPage("inventory")
  assert(mf.overtime._shown == false, "fuera de las páginas de rutas no sale")
  ES:SelectPage("Leatherworking")
  assert(mf.overtime._shown, "en una profesión sale")
  rank = 0
  ES:UpdateSkillUpBonus()
  assert(mf.overtime._shown == false, "sin el talento no sale")
  ES:SelectPage("home")
  -- Se reconoce también por su hechizo (1225451) aunque el nombre no cuadre
  GetSpellInfo = function() return "Otro nombre" end
  C_Traits.GetDefinitionInfo = function(def) return { spellID = def == 110 and 1225451 or 999002 } end
  rank = 4
  ES.db.overtimeSpell = nil
  local r4, s4 = ES:ReadWorkingOvertime()
  assert(r4 == 4 and s4 == 1225451, "por su ID de hechizo: " .. tostring(r4))
  -- Sin C_Traits (cliente sin legado): nada cambia
  C_Traits = nil
  assert(ES:ReadWorkingOvertime() == nil, "sin C_Traits no se lee")
  C_Traits, C_Spell, GetSpellInfo, ES.Print = savedT, savedName, savedGSI, savedPrint
  ES.Planner.SKILL_BONUS = 0
  ES.db.overtimeSpell = nil
  ES:ClearHomeCache()
end)
step("materiales de la ruta: fabricaciones enteras", function()
  -- Cada paso redondea sus fabricaciones (14,7 -> 15); lo que la ruta dice que compres
  -- tiene que llegar para esas fabricaciones (Discord: "me pide 98 y hacen falta 100")
  local data = ES.Data.Leatherworking
  local plan = ES.Planner:Plan(data, { from = 1, to = 225, hours = 24, ignoreSupply = true })
  local need = ES.Planner.NeedFrom(plan, 1)
  local bought = {}
  for _, it in ipairs(plan.shopping) do bought[it.itemID] = (bought[it.itemID] or 0) + it.quantity end
  local checked = 0
  for itemID, q in pairs(bought) do
    if need[itemID] then
      checked = checked + 1
      assert(q >= need[itemID], string.format("%s: la ruta compra %d y las fabricaciones enteras piden %d",
        ES:DataItemName(itemID) or itemID, q, need[itemID]))
    end
  end
  assert(checked > 0, "no se comprobó ningún material")
  log[#log+1] = string.format("     %d materiales: lo que se compra llega para las fabricaciones enteras", checked)
end)
step("lista por tramos: fabricaciones enteras", function()
  -- (15 Light Leather no dan para 2 Light Leather Pants, que piden 10: la lista pide 20)
  -- En todas las profesiones, por tramos y con la ruta entera: un material que solo gasta
  -- una receta (con la misma cantidad) va en múltiplos de lo que pide cada fabricación
  local P = ES.Planner
  local checked = 0
  local function Check(plan, need, from, to, what)
    local per = {}
    for s = from, to - 1 do
      local r = ES.Data[plan.profKey].recipes[plan.choice[s]]
      local direct = {}
      for _, rq in ipairs(r and r.r or {}) do
        direct[rq[1]] = true
        local cur = per[rq[1]]
        if cur == nil then per[rq[1]] = rq[2] elseif cur ~= rq[2] then per[rq[1]] = false end
      end
      -- (también lo gasta un intermedio de esa receta: esa parte va por unidades)
      for itemID in pairs(plan.pointNeed[s] or {}) do
        if not direct[itemID] then per[itemID] = false end
      end
    end
    for itemID, n in pairs(need) do
      local target = type(n) == "table" and n.target or n
      local each = per[itemID]
      if each and each > 1 then
        assert(target % each == 0, string.format("%s %s desde %d: pide %d %s, que no son fabricaciones enteras (de %d en %d)",
          plan.profKey, what, from, target, ES:DataItemName(itemID) or itemID, each, each))
        checked = checked + 1
      end
    end
  end
  for _, prof in ipairs({ "Leatherworking", "Tailoring", "Blacksmithing", "Engineering", "Alchemy", "Enchanting", "Cooking", "FirstAid" }) do
    local opts = ES:PlanOptions(prof, 1, 300, nil)
    opts.owned = nil
    local plan = P:Plan(ES.Data[prof], opts)
    plan.profKey = prof
    for _, st in ipairs(plan.steps) do
      local need, phase = P.PhaseNeed(plan, st.from)
      if phase then Check(plan, need, phase.from, phase.batchTo or phase.to, "tramo") end
      Check(plan, P.NeedFrom(plan, st.from), st.from, plan.reached, "ruta entera")
    end
  end
  assert(checked > 0, "ningún material de más de 1 por fabricación en las rutas de prueba")
  log[#log+1] = "     " .. checked .. " materiales comprobados en fabricaciones enteras (8 profesiones)"
end)
step("comandos /es", function()
  SlashCmdList.CRAFTERSJOURNAL("") SlashCmdList.CRAFTERSJOURNAL("cancel")
  -- Registro de errores: los iguales juntos, con cuántas veces; /cj errores los lista y los borra   ES.db.errorLog = nil   ES:RecordError("lua", "Interface/AddOns/CraftersJournal/Planner.lua:1: boom", "pila")   ES:RecordError("lua", "Interface/AddOns/CraftersJournal/Planner.lua:1: boom", "pila")   ES:RecordError("bloqueada", "SetRaidTarget()")   assert(#ES.db.errorLog == 2 and ES.db.errorLog[1].count == 2, "no agrupó los errores iguales")   SlashCmdList.CRAFTERSJOURNAL("errores")   SlashCmdList.CRAFTERSJOURNAL("errores borrar")   assert(ES.db.errorLog == nil, "/cj errores borrar no lo vació")
end)
step("rutas repartidas entre fotogramas (sin tirones)", function()
  -- En el juego (con debugprofilestop) la portada no calcula rutas: la tarjeta dice
  -- "Abrir para calcular" (CurseForge: abrir el addon calculaba las de todas las tuyas).
  -- Al abrir la profesión, cada fotograma hace un trozo de 8 ms ("Calculando la ruta…")
  local frames = {}
  local realAfter = C_Timer.After
  C_Timer.After = function(_, fn) frames[#frames + 1] = fn end
  local ms = 0
  debugprofilestop = function() ms = ms + 0.05 return ms end
  -- El personaje tiene Peletería (nivel 50); las demás no se calculan solas
  local savedSkill = ES.GetProfessionSkill
  ES.GetProfessionSkill = function(self, line)
    if line == ES.Data.Leatherworking.skillLine then return 50, 225 end
    return savedSkill(self, line)
  end
  ES:ClearHomeCache()
  if ES.db.prof.Leatherworking then ES.db.prof.Leatherworking.lastRoute = nil end -- (ni la guardada)
  ES:SelectPage("home")
  local openText = (ES.L["Abrir para calcular|r"]:gsub("|r", ""))
  local first = ES.homePage.cards[1]
  for _, c in ipairs(ES.homePage.cards) do
    if c.key == "Leatherworking" then first = c
    else assert(not tostring(c.note._text):find("Calculando"), "no debería calcular una profesión que no tienes: " .. tostring(c.key)) end
  end
  log[#log+1] = "     al abrir: " .. tostring(first.cost._text) .. " | " .. tostring(first.note._text)
  assert(tostring(first.note._text):find(openText, 1, true), "la tarjeta debería poner " .. openText .. ": " .. tostring(first.note._text))
  assert(#frames == 0, "la portada no debería calcular: " .. #frames .. " fotogramas pedidos")
  -- Abrir la profesión: se calcula repartida entre fotogramas
  ES:SelectPage(first.key)
  local page = ES.professionPages[1]
  for _, p in ipairs(ES.professionPages) do if p.profKey == first.key then page = p end end
  page._scripts.OnShow(page) -- el simulacro no lanza OnShow al mostrar
  assert(page.calculating, "la página debería estar calculando")
  local n = 0
  while #frames > 0 and n < 100000 do
    local fn = table.remove(frames, 1)
    local before = ms
    fn()
    assert(ms - before < 30, "un fotograma ha durado " .. (ms - before) .. " ms simulados")
    n = n + 1
  end
  log[#log+1] = "     fotogramas hasta tener la ruta de tu profesión: " .. n
  assert(n > 1, "no se repartió el cálculo (" .. n .. " fotogramas)")
  assert(page.plan and not page.calculating, "la página sigue sin ruta tras acabar")
  -- La portada enseña ya su coste, sin calcular (de la caché)
  frames = {}
  ES:SelectPage("home")
  for _, c in ipairs(ES.homePage.cards) do if c.key == "Leatherworking" then first = c end end
  log[#log+1] = "     al acabar: " .. tostring(first.cost._text) .. " | " .. tostring(first.note._text)
  assert(not tostring(first.note._text):find("Calculando"), "sigue calculando tras acabar")
  assert(not tostring(first.note._text):find(openText, 1, true), "la portada no usa la ruta calculada: " .. tostring(first.note._text))
  assert(#frames == 0, "no debería recalcular: " .. #frames)
  debugprofilestop = nil
  C_Timer.After = realAfter
  ES.GetProfessionSkill = savedSkill
  ES:SelectPage("home")
end)
step("ruta con error: no se queda calculando para siempre", function()
  -- CurseForge: "se queda en el 99%". Si el planificador da error, la página deja de
  -- calcular y lo dice, y la misma ruta no se vuelve a lanzar en bucle
  local frames, realAfter = {}, C_Timer.After
  local savedPlan, savedEH, savedDPS = ES.Planner.Plan, geterrorhandler, debugprofilestop
  local ms, calls, reported = 0, 0, 0
  local ok, err = pcall(function()
    C_Timer.After = function(_, fn) frames[#frames + 1] = fn end
    debugprofilestop = function() ms = ms + 0.05 return ms end
    geterrorhandler = function() return function() reported = reported + 1 end end
    ES.Planner.Plan = function() calls = calls + 1 error("boom") end
    ES:InvalidatePlan("Cooking")
    ES:SelectPage("Cooking")
    local page
    for _, p in ipairs(ES.professionPages) do if p.profKey == "Cooking" then page = p end end
    page._scripts.OnShow(page)
    assert(page.calculating, "debería empezar calculando")
    local n = 0
    while #frames > 0 and n < 1000 do table.remove(frames, 1)() n = n + 1 end
    assert(not page.calculating, "con el error, sigue calculando")
    assert(page.planFailed and ES.planRunning == nil, "debería quedar como fallida y sin cálculo en marcha")
    assert(tostring(page.status._text):find("No se pudo calcular"), "no avisa del error: " .. tostring(page.status._text))
    assert(reported == 1 and calls >= 1, "el error debería informarse una vez: " .. reported)
    -- Repintar no la relanza
    local before = calls
    ES:CalculatePlan(page)
    while #frames > 0 and n < 2000 do table.remove(frames, 1)() n = n + 1 end
    assert(calls == before, "la misma ruta fallida se ha vuelto a calcular")
  end)
  ES.Planner.Plan, geterrorhandler, debugprofilestop, C_Timer.After = savedPlan, savedEH, savedDPS, realAfter
  ES:InvalidatePlan("Cooking")
  ES.planFailed = {}
  ES:SelectPage("home")
  if not ok then error(err, 0) end
end)
step("herramienta que piden los pasos y no llevas: en la lista", function()
  -- CurseForge: "me mandó fabricar unas gafas que piden Arclight Spanner y no estaba en
  -- la lista". La ruta la consiguió en 60 (Crude Scope) y a 222 daba por hecho que la llevas
  local P, E = ES.Planner, ES.Data.Engineering
  local savedCount = ES.ItemCount
  local bags = {}
  local ok, err = pcall(function()
    ES.ItemCount = function(_, id) return bags[id] or 0 end
    local plan = { from = 1, to = 300, reached = 300, tools = { { item = 6219, skill = 60, cost = 170 } },
      steps = { { from = 60, to = 75, id = 3977, recipe = E.recipes[3977] }, { from = 222, to = 245, id = 12607, recipe = E.recipes[12607] } } }
    local out = {}
    assert(P.AddMissingTools("Engineering", plan, 222, 245, out) and out[6219] and out[6219].need == 1,
      "a 222, sin la llave, la lista debería pedirla")
    out = {}
    assert(not P.AddMissingTools("Engineering", plan, 60, 75, out) and not out[6219],
      "en el nivel donde la ruta la consigue ya va en pointNeed: no dos veces")
    bags[6219] = 1
    out = {}
    -- (las Catseye Ultra Goggles piden también el Gyromatic Micro-Adjustor: tool2)
    -- (no lo vende nadie: se piden sus materiales para fabricarlo)
    assert(P.AddMissingTools("Engineering", plan, 222, 245, out) and not out[6219],
      "con la llave, falta el Micro-Adjustor")
    bags[10498] = 1
    out = {}
    assert(not P.AddMissingTools("Engineering", plan, 222, 245, out), "llevándolas no se piden")
    -- Sin ella no se puede fabricar el paso (y no cuenta como "comprado, a fabricar")
    for _, rq in ipairs(E.recipes[12607].r) do bags[rq[1]] = rq[2] * 3 end
    assert(ES.CraftableFromBags(12607) == 3, "con la llave y materiales para 3: " .. tostring(ES.CraftableFromBags(12607)))
    bags[6219] = nil
    local n, short = ES.CraftableFromBags(12607)
    assert(n == 0 and short and short.itemID == 6219, "sin la llave no se puede fabricar: " .. tostring(n))
    -- Dos herramientas (CurseForge, 0.62.0: Goblin Mining Helmet pide Blacksmith Hammer Y
    -- Arclight Spanner; solo se leía la primera y nunca pedía la llave)
    local helm = E.recipes[12717]
    assert(helm.tool == 162 and helm.tool2 == 14, "el casco pide martillo y llave en los datos")
    bags = { [5956] = 1 } -- (solo el martillo)
    local miss = P.MissingTools(helm)
    assert(#miss == 1 and miss[1].item == 6219, "con el martillo, falta la llave")
    plan.steps[#plan.steps + 1] = { from = 230, to = 245, id = 12717, recipe = helm }
    out = {}
    assert(P.AddMissingTools("Engineering", plan, 230, 245, out) and out[6219] and not out[5956],
      "la lista pide la llave (no el martillo, que llevas)")
    bags = {}
    out = {}
    P.AddMissingTools("Engineering", plan, 230, 245, out)
    assert(out[6219] and out[5956], "sin ninguna, pide las dos")
    for _, rq in ipairs(helm.r) do bags[rq[1]] = rq[2] * 2 end
    bags[5956] = 1
    assert(ES.CraftableFromBags(12717) == 0, "sin la llave el casco no se fabrica")
    bags[6219] = 1
    assert(ES.CraftableFromBags(12717) == 2, "con las dos, sí")
  end)
  ES.ItemCount = savedCount
  if not ok then error(err, 0) end
end)
step("precio que sube de golpe: TSM y probar la AH si el depósito compensa (Star Ruby)", function()
  -- Discord: Star Ruby a 85s en la AH (toda la semana a ~50-60s) se mandaba al vendedor
  -- a 50s: el precio inflado se contaba a ~58s y tras la comisión no compensaba
  local RUBY = 7910
  local bags = { { RUBY, 1 } }
  local savedCC, savedScans, savedVendor = C_Container, ES.db.scans, ES.VendorSellPrice
  local savedRef, savedSig, savedTSM = ES.Market.ReferencePrice, ES.Market.Signals, TSM_API
  C_Container = {
    GetContainerNumSlots = function(bag) return bag == 0 and #bags or 0 end,
    GetContainerItemID = function(bag, slot) return bags[slot] and bags[slot][1] end,
    GetContainerItemInfo = function(bag, slot) local b = bags[slot] return b and { stackCount = b[2] } end,
  }
  ES.VendorSellPrice = function() return 5000 end
  ES.db.scans = { [ES:RealmKey()] = { time = time() - 600, items = { [RUBY] = { minUnit = 8534, quantity = 300 } } } }
  ES.Market.ReferencePrice = function() return 5068, 3, 0 end
  ES.Market.Signals = function() return { verdict = "good" } end
  local function Ruby()
    ES.Market.ClearTSM()
    for _, e in ipairs(ES.Inventory:List()) do if e.itemID == RUBY then return e end end
  end
  -- Sin TSM: inflado, pero en la AH al precio real compensa aunque se pierda el depósito
  TSM_API = nil
  local e = Ruby()
  assert(e and e.fair.inflated and e.tryRise, "Star Ruby: subida de golpe, se prueba la AH")
  assert(e.ahN == 1 and e.listPrice == 8533, "se anuncia al precio real (85s33): " .. tostring(e.listPrice))
  -- TSM dice que en la región se vende a ~84s: la subida es real, no es precio inflado
  local tsm = { rate = 300, sold = 20000, avg = 8400 }
  TSM_API = { GetCustomPriceValue = function(src) if src:find("SaleRate") then return tsm.rate end
    if src:find("SoldPerDay") then return tsm.sold end if src:find("SaleAvg") then return tsm.avg end end }
  e = Ruby()
  assert(e and not e.fair.inflated and e.fair.tsmSupported and e.ahN == 1 and e.listPrice == 8533, "TSM respalda el precio nuevo")
  -- TSM: venta media de 55s (de antes de la subida) pero se vende mucho: se prueba igual.
  -- Los datos de TSM del juego el 17-11: Star Ruby 55s07 de media, ~102 al día, 72%
  tsm.avg = 5507
  e = Ruby()
  assert(e and e.fair.inflated and e.tryRise and e.ahN == 1 and e.listPrice == 8533, "la media de TSM va por detrás: se prueba la AH")
  -- TSM: casi no se vende (poca demanda): tampoco
  tsm.avg, tsm.sold, tsm.rate = 8400, 100, 10
  e = Ruby()
  assert(e and e.fair.inflated and not e.tryRise and e.ahN == 0, "TSM dice que casi no se vende: al vendedor")
  -- El depósito no es exagerado para lo que ganas: 77s (73s tras la comisión) menos
  -- 10s de depósito sigue sacando más que 50s del vendedor: se prueba la AH
  TSM_API = nil
  ES.db.scans[ES:RealmKey()].items[RUBY].minUnit = 7700
  ES.Market.ReferencePrice = function() return 4000, 3, 0 end
  e = Ruby()
  assert(e and e.tryRise and e.ahN == 1, "77s: compensa arriesgar el depósito")
  -- Exagerado: 60s (57s tras la comisión) menos 10s de depósito no llega a 50s: al vendedor
  ES.db.scans[ES:RealmKey()].items[RUBY].minUnit = 6000
  ES.Market.ReferencePrice = function() return 3500, 3, 0 end
  e = Ruby()
  assert(e and e.ahN == 0 and e.vendorN == 1, "60s: el depósito se come lo que ganas, al vendedor")
  log[#log+1] = string.format("     Star Ruby: 85s a la AH (probando 1); 77s a la AH; 60s al vendedor (depósito %s)", ES.Money(e.depositRisk or 0))
  C_Container, ES.db.scans, ES.VendorSellPrice = savedCC, savedScans, savedVendor
  ES.Market.ReferencePrice, ES.Market.Signals, TSM_API = savedRef, savedSig, savedTSM
  ES.Market.ClearTSM()
end)
step("inventario: qué vender de las bolsas, dónde y qué guardar", function()
  -- Bolsas: 20 Light Leather (la ruta fijada necesita 5), 3 de un objeto que ha subido,
  -- 2 que solo valen para el vendedor y 1 ligado
  local LL, UP, JUNK, BOUND = 2318, 4234, 4251, 5000
  local bags = { { LL, 20 }, { UP, 3 }, { JUNK, 2 }, { BOUND, 1, true } }
  local savedCC, savedScans, savedVendor = C_Container, ES.db.scans, ES.VendorSellPrice
  local savedRef, savedSig, savedLock, savedLocked, savedNeed = ES.Market.ReferencePrice, ES.Market.Signals, ES.RouteLock, ES.LockedPlan, ES.Planner.NeedFrom
  local savedMerchant, savedSell, savedPost, savedAH = ES.Ledger.MerchantOpen, ES.Ledger.SellToVendor, ES.Ledger.PostOnAH, ES.IsAuctionHouseOpen
  C_Container = {
    GetContainerNumSlots = function(bag) return bag == 0 and #bags or 0 end,
    GetContainerItemID = function(bag, slot) return bags[slot] and bags[slot][1] end,
    GetContainerItemInfo = function(bag, slot) local b = bags[slot] return b and { stackCount = b[2], isBound = b[3] } end,
  }
  local VENDOR = { [LL] = 15, [UP] = 100, [JUNK] = 659, [BOUND] = 500 }
  ES.VendorSellPrice = function(_, id) return VENDOR[id] end
  ES.db.scans = { [ES:RealmKey()] = { time = time() - 600, items = {
    [LL] = { minUnit = 40, quantity = 50 }, [UP] = { minUnit = 5000, quantity = 2 }, [JUNK] = { minUnit = 600, quantity = 4 },
    [BOUND] = { minUnit = 9000, quantity = 1 } } } }
  local REF = { [LL] = 45, [UP] = 3000, [JUNK] = 650 }
  ES.Market.ReferencePrice = function(_, id) if REF[id] then return REF[id], 3, 0 end end
  ES.Market.Signals = function() return { verdict = "good" } end
  ES.RouteLock = function(_, k) return k == "Leatherworking" end
  ES.LockedPlan = function() return { from = 1 } end
  ES.Planner.NeedFrom = function() return { [LL] = 5 } end
  local list = ES.Inventory:List()
  local by = {}
  for _, e in ipairs(list) do by[e.itemID] = e end
  assert(by[LL] and by[LL].keep == 5 and by[LL].ahN + by[LL].vendorN == 15, "Light Leather: guarda 5 y vende 15")
  assert(by[LL].ahN == 15, "Light Leather a 40 en la AH deja más que 15 del vendedor: " .. by[LL].ahN)
  assert(by[UP] and by[UP].rise and by[UP].ahN == 3, "lo que ha subido va a la AH y se marca")
  assert(by[JUNK] and by[JUNK].ahN == 0 and by[JUNK].vendorN == 2, "la AH no deja más que el vendedor: al vendedor")
  assert(not by[BOUND] or by[BOUND].ahN == 0, "un objeto ligado no se anuncia en la AH")
  -- La página: secciones, cifras y el botón de vender (solo con el vendedor abierto)
  ES:SelectPage("inventory")
  local page = ES.inventoryPage
  page._shown = true
  local sold = {}
  ES.Ledger.MerchantOpen = function() return true end
  ES.Ledger.SellToVendor = function(_, id, n) sold[id] = n end
  ES:RenderInventory()
  local sections = {}
  for i, row in ipairs(page.rows) do if row._shown and row.title then sections[#sections + 1] = tostring(row.title._text) end end
  log[#log+1] = "     inventario: " .. tostring(page.stats.total._text) .. " · " .. table.concat(sections, " | "):sub(1, 220)
  assert(page.action._shown, "con el vendedor abierto sale el botón de vender")
  -- "Al vendedor" de arriba: lo mismo que vende el botón (solo la sección del vendedor)
  local vendorSum = 0
  for _, e in ipairs(ES.Inventory:Sections().vendor) do vendorSum = vendorSum + e.vendorN * e.vendorUnit end
  local shownVendor = tostring(page.stats.vendor._text)
  assert(vendorSum == 0 and shownVendor:find("—") or shownVendor:find(tostring(vendorSum % 100)),
    "la cifra Al vendedor no es la de su sección: " .. shownVendor .. " frente a " .. vendorSum)
  page.action._scripts.OnClick(page.action)
  -- Pregunta antes (ES:Confirm); con "No volver a mostrar" marcado, la próxima vez ya no
  local confirm = ES.ConfirmFrame()
  assert(confirm and confirm.pending and not sold[JUNK], "vender todo al vendedor debería preguntar antes")
  confirm.check:SetChecked(true)
  confirm.ok._scripts.OnClick(confirm.ok)
  assert(sold[JUNK] == 2 and not sold[LL] and not sold[UP], "el botón solo vende lo que va al vendedor")
  assert(ES.db.noInventorySellConfirm == true, "No volver a mostrar debería apagar el aviso")
  ES.db.noInventorySellConfirm = nil
  -- Clic en una fila con la AH abierta: anuncia
  local posted
  ES.IsAuctionHouseOpen = function() return true end
  ES.Ledger.PostOnAH = function(_, id, n, price) posted = { id, n, price } end
  -- Primero pregunta (opción activada por defecto); Anunciar anuncia, Cancelar no
  local savedNoConfirm, savedPrintC = ES.db.noPostConfirm, ES.Print
  ES.db.noPostConfirm = nil
  local function ClickUp()
    for _, row in ipairs(page.rows) do if row.onClick and row.title and tostring(row.title._text):find("3×") then row.onClick() end end
  end
  ClickUp()
  local dlg = CraftersJournalPostConfirm
  assert(dlg and dlg._shown and not posted, "con la confirmación activada, el clic pregunta antes de anunciar")
  assert(tostring(dlg.text._text):find("3", 1, true) and tostring(dlg.note._text):find("/cj opciones", 1, true),
    "la confirmación dice cuántos y dónde se vuelve a activar: " .. tostring(dlg.text._text))
  dlg.cancel._scripts.OnClick(dlg.cancel)
  assert(not dlg._shown and not posted, "Cancelar no anuncia")
  ClickUp()
  dlg.ok._scripts.OnClick(dlg.ok)
  assert(posted and posted[1] == UP and posted[2] == 3, "Anunciar en la confirmación no anunció")
  assert(not ES.db.noPostConfirm, "sin marcar la casilla, sigue preguntando")
  -- "No volver a preguntar": apaga la opción y desde entonces anuncia directamente
  posted = nil
  ES.Print = function() end
  ClickUp()
  dlg.check:SetChecked(true)
  dlg.ok._scripts.OnClick(dlg.ok)
  assert(posted and ES.db.noPostConfirm == true, "con la casilla marcada, anuncia y deja de preguntar")
  ES.Print = savedPrintC
  -- Una sola unidad no pregunta (un clic sin querer no anuncia un montón)
  ES.db.noPostConfirm, posted = nil, nil
  ES.AuctionSell.Post(UP, 1, 500, 24)
  assert(posted and posted[2] == 1 and not dlg._shown, "una sola unidad se anuncia sin preguntar")
  ES.db.noPostConfirm = true
  posted = nil
  ClickUp()
  assert(posted and posted[1] == UP and posted[2] == 3, "el clic con la AH abierta no anunció")
  -- Ventana junto a la AH: lo que el Inventario manda a la AH, con clic para anunciar
  do
    local savedMain, savedAHF = CraftersJournalMainFrame, AuctionHouseFrame
    CraftersJournalMainFrame = nil -- (con la ventana grande al lado de la AH no sale)
    AuctionHouseFrame = CreateFrame("Frame")
    ES.AuctionSell.closed = nil
    -- Por defecto la ventana de vender sale, y la primera vez avisa de que se puede quitar
    local savedSellOpt, savedTips, savedPrintT = ES.db.noAuctionSellWindow, ES.db.windowTips, ES.Print
    ES.db.noAuctionSellWindow, ES.db.windowTips = nil, nil
    local tips = {}
    ES.Print = function(_, m) tips[#tips + 1] = tostring(m) end
    -- (un objeto azul, como los da el juego: el nombre sale con el color de su calidad)
    local savedData, savedQC = ES.GetItemData, ITEM_QUALITY_COLORS[3]
    ES.GetItemData = function(_, id) if id == UP then return "Blue Thing", 3, 134400 end return savedData(ES, id) end
    ITEM_QUALITY_COLORS[3] = { r = 0, g = 0.44, b = 0.87, hex = "|cff0070dd" }
    ES.AuctionSell:Refresh()
    ES.GetItemData, ITEM_QUALITY_COLORS[3] = savedData, savedQC
    local sp = CraftersJournalAuctionSellPanel
    assert(sp and sp._shown == true, "con la AH abierta sale la ventana de vender en la AH")
    assert(#tips == 1 and tips[1]:find("/cj opciones", 1, true), "la primera vez, el aviso de que se puede quitar: " .. table.concat(tips, " | "))
    ES:WindowTip("sell")
    assert(#tips == 1, "el aviso solo sale una vez")
    -- Engranaje junto a la ✕: un menú pequeño con la opción justa de esta ventana
    -- ("No mostrar esta ventana") y, debajo, todas las opciones
    local savedOpen, opened = ES.OpenOptions, false
    ES.OpenOptions = function(_, cat) opened = cat or true end
    assert(sp.optionsGear, "la ventana de vender tiene el engranaje de opciones")
    sp.optionsGear._scripts.OnClick(sp.optionsGear)
    local menu = sp.optionsGear.menu
    assert(menu and menu._shown == true and not opened, "el engranaje abre su menú, no el panel entero")
    menu._scripts.OnShow(menu)
    assert(tostring(menu.title._text):find("Vender en la AH"), "el menú dice qué ventana es: " .. tostring(menu.title._text))
    assert(tostring(menu.off._text):find("No mostrar"), "botón para quitarla: " .. tostring(menu.off._text))
    menu.all._scripts.OnClick(menu.all)
    assert(opened == "auction" and menu._shown == false, "Todas las opciones: abre la ventana en su categoría y cierra el menú: " .. tostring(opened))
    sp.optionsGear._scripts.OnClick(sp.optionsGear)
    menu.off._scripts.OnClick(menu.off)
    assert(ES.db.noAuctionSellWindow == true and sp._shown == false and menu._shown == false,
      "No mostrar esta ventana: como quitar su casilla, y se cierra al momento")
    assert(tostring(tips[#tips]):find("/cj opciones", 1, true), "dice dónde volver a activarla: " .. tostring(tips[#tips]))
    -- (otra vez con el objeto azul de arriba: lo de abajo mira el color del nombre)
    ES.GetItemData = function(_, id) if id == UP then return "Blue Thing", 3, 134400 end return savedData(ES, id) end
    ITEM_QUALITY_COLORS[3] = { r = 0, g = 0.44, b = 0.87, hex = "|cff0070dd" }
    ES:SetOption("noAuctionSellWindow", true)
    ES.GetItemData, ITEM_QUALITY_COLORS[3] = savedData, savedQC
    assert(ES.db.noAuctionSellWindow == nil and sp._shown == true, "activada otra vez, vuelve")
    log[#log+1] = "     engranaje: menú con No mostrar esta ventana y Todas las opciones"
    ES.OpenOptions = savedOpen
    ES.Print = savedPrintT
    local upRow
    for _, row in ipairs(sp.rows) do if row._shown ~= false and row.entry and row.entry.itemID == UP then upRow = row end end
    assert(upRow and upRow.entry.ahN == 3, "la ventana de la AH lista lo que va a la AH")
    for _, row in ipairs(sp.rows) do assert(not (row._shown ~= false and row.entry and row.entry.itemID == JUNK), "lo del vendedor no va a la ventana de la AH") end
    assert(tostring(upRow.name._text):find("|cff0070dd", 1, true), "el nombre lleva el color de su calidad: " .. tostring(upRow.name._text))
    assert(tostring(sp.hint._text):find("derecho"), "a la vista, qué hace el clic derecho")
    -- Al anunciar, de cuándo son los precios: escaneando, en naranja con el % (y el clic
    -- no anuncia, Ledger:PostOnAH); de hace más de 1 h, en naranja; recientes, el subtítulo
    do
      local scanRow = ES.db.scans and ES.db.scans[ES:RealmKey()]
      assert(scanRow, "(la prueba necesita un escaneo)")
      local savedTime, savedState, savedProg = scanRow.time, ES.Scanner.state, ES.Scanner.progress
      scanRow.time = time() - 60
      ES.AuctionSell:Refresh()
      assert(tostring(sp.sub._text):find("Para vender"), "precios recientes: el subtítulo de siempre: " .. tostring(sp.sub._text))
      scanRow.time = time() - 3 * 3600 - 60
      ES.AuctionSell:Refresh()
      assert(tostring(sp.sub._text):find("hace 3 h", 1, true) and tostring(sp.sub._text):find("ff9933"), "precios de hace 3 h, en naranja: " .. tostring(sp.sub._text))
      ES.Scanner.state, ES.Scanner.progress = "scanning", 0.45
      ES:UpdatePostStatus()
      -- Escaneando: la capa de espera tapa las filas (reloj de arena y %), sin el aviso arriba
      assert(sp.wait and sp.wait._shown == true, "escaneando: sale la capa de espera")
      assert(tostring(sp.wait.text._text):find("45%", 1, true), "la capa dice el %: " .. tostring(sp.wait.text._text))
      assert(tostring(sp.sub._text):find("Para vender"), "escaneando, arriba el subtítulo de siempre: " .. tostring(sp.sub._text))
      sp.wait._scripts.OnUpdate(sp.wait, 2) -- (el reloj se da la vuelta sin errores)
      ES.Scanner.progress = 0.8
      ES:UpdatePostStatus()
      assert(tostring(sp.wait.text._text):find("80%", 1, true), "el % avanza sin recalcular: " .. tostring(sp.wait.text._text))
      ES.Scanner.state, ES.Scanner.progress = savedState, savedProg
      scanRow.time = time() - 60
      ES:UpdatePostStatus() -- acaba: la ventana se recalcula con los precios nuevos
      assert(sp.wait._shown == false, "al acabar el escaneo, la capa de espera se quita")
      assert(tostring(sp.sub._text):find("Para vender"), "al acabar el escaneo, el subtítulo vuelve: " .. tostring(sp.sub._text))
      scanRow.time = savedTime
      ES.AuctionSell:Refresh()
      log[#log+1] = "     ventana de la AH: avisa escaneando (con el %) y con precios de más de 1 h"
    end
    posted = nil
    -- (el tooltip es el del Inventario; aquí Market.Signals está simulado sin sus cifras)
    -- Clic: todas las de la fila (como en Inventario); Mayús+clic: solo una
    local savedShift = IsShiftKeyDown
    IsShiftKeyDown = function() return false end
    upRow._scripts.OnClick(upRow, "LeftButton")
    assert(posted and posted[1] == UP and posted[2] == 3, "clic en la ventana de la AH: anunciar todas (" .. tostring(posted and posted[2]) .. ")")
    posted = nil
    IsShiftKeyDown = function() return true end
    upRow._scripts.OnClick(upRow, "LeftButton")
    assert(posted and posted[1] == UP and posted[2] == 1, "Mayús+clic en la ventana de la AH: anunciar solo 1")
    IsShiftKeyDown = savedShift
    -- Alertas dudosas (ojo): solo unas pocas de las que tienes (Discord: "¿por qué 5 Turtle
    -- Meat si tengo muchas?"). La fila dice "5 de 40", el tooltip por qué, y Ctrl+clic
    -- anuncia todas avisando del riesgo (en el chat sin confirmación; en el diálogo con ella)
    do
      local savedList, savedCtrl, savedPrintW = ES.AuctionSell.List, IsControlKeyDown, ES.Print
      local few = { itemID = UP, count = 40, keep = 0, sellN = 40, ahN = 5, vendorN = 35, vendorUnit = 10,
        ahUnit = 150, listPrice = 158, hours = 8, verdict = "watch", depositUnit = 4, value = 0 }
      ES.AuctionSell.List = function() return { few } end
      ES.AuctionSell:Refresh()
      local row = sp.rows[1]
      local qty = tostring(row.qty._text)
      assert(row.entry == few and qty:find("5 de 40", 1, true), "la fila dice de cuántas: " .. qty)
      assert(tostring(sp.hint._text):find("Ctrl", 1, true), "abajo, qué hace Ctrl+clic: " .. tostring(sp.hint._text))
      -- (Market.Signals está simulado sin sus cifras: su sección del tooltip, fuera)
      local tip, savedAddL, savedAddD, savedMkt = {}, GameTooltip.AddLine, GameTooltip.AddDoubleLine, ES.Market.AddToTooltip
      GameTooltip.AddLine = function(_, t) tip[#tip + 1] = tostring(t) end
      GameTooltip.AddDoubleLine = function(_, a, b) tip[#tip + 1] = tostring(a) .. " | " .. tostring(b) end
      ES.Market.AddToTooltip = function() end
      local okTip, errTip = pcall(row._scripts.OnEnter, row)
      GameTooltip.AddLine, GameTooltip.AddDoubleLine, ES.Market.AddToTooltip = savedAddL, savedAddD, savedMkt
      if not okTip then ES.AuctionSell.List = savedList error(errTip) end
      local all = table.concat(tip, "\n")
      assert(all:find("para probar", 1, true) and all:find("Ctrl+clic: anunciar las 40", 1, true),
        "el tooltip explica por qué 5 y qué hace Ctrl+clic: " .. all)
      -- Ctrl+clic sin confirmación (noPostConfirm, arriba): las 40, con el aviso en el chat
      local printed = {}
      ES.Print = function(_, m) printed[#printed + 1] = tostring(m) end
      IsShiftKeyDown, IsControlKeyDown = function() return false end, function() return true end
      posted = nil
      row._scripts.OnClick(row, "LeftButton")
      assert(posted and posted[2] == 40, "Ctrl+clic: todas (" .. tostring(posted and posted[2]) .. ")")
      assert(printed[1] and printed[1]:find("alertas", 1, true) and printed[1]:find("depósito", 1, true),
        "Ctrl+clic avisa en el chat del riesgo: " .. tostring(printed[1]))
      -- Con confirmación: el aviso va en el diálogo
      ES.db.noPostConfirm, posted = nil, nil
      row._scripts.OnClick(row, "LeftButton")
      local dlg = CraftersJournalPostConfirm
      assert(dlg._shown and not posted and tostring(dlg.warn._text):find("alertas", 1, true), "el diálogo avisa: " .. tostring(dlg.warn._text))
      dlg.ok._scripts.OnClick(dlg.ok)
      assert(posted and posted[2] == 40, "confirmado: las 40")
      -- Un clic normal después: las 5 y sin aviso en el diálogo
      IsControlKeyDown = function() return false end
      posted = nil
      row._scripts.OnClick(row, "LeftButton")
      assert(dlg._shown and dlg.warn._shown == false and tostring(dlg.text._text):find("5", 1, true), "clic normal: 5 y sin aviso")
      dlg.cancel._scripts.OnClick(dlg.cancel)
      ES.db.noPostConfirm = true
      -- Con "bien" ya van todas a la AH: ni "de 40" ni Ctrl+clic
      few.verdict, few.ahN = "good", 40
      ES.AuctionSell:Refresh()
      assert(not tostring(sp.rows[1].qty._text):find(" de 40", 1, true) and not tostring(sp.hint._text):find("Ctrl", 1, true),
        "con bien no hay tope: " .. tostring(sp.rows[1].qty._text))
      ES.AuctionSell.List, IsControlKeyDown, ES.Print, IsShiftKeyDown = savedList, savedCtrl, savedPrintW, savedShift
      ES.AuctionSell:Refresh()
      log[#log+1] = "     ventana de la AH, con ojo: " .. qty:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T[^|]+|t", "") .. " · Ctrl+clic anuncia las 40 avisando"
    end
    -- Abajo, una línea por acción
    local hint = tostring(sp.hint._text)
    assert(hint:find("Clic") and hint:find("Mayús") and hint:find("derecho") and select(2, hint:gsub("\n", "")) >= 2,
      "la ayuda de abajo, una línea por acción: " .. hint)
    -- Clic derecho: no venderlo nunca, y la fila desaparece al momento de esta ventana
    local savedPrint, savedNever = ES.Print, ES.db.neverSell
    ES.Print = function() end
    upRow._scripts.OnClick(upRow, "RightButton")
    for _, row in ipairs(sp.rows) do
      assert(not (row._shown ~= false and row.entry and row.entry.itemID == UP), "tras el clic derecho sigue en la ventana de la AH")
    end
    ES.db.neverSell, ES.Print = savedNever, savedPrint
    ES.AuctionSell:Refresh()
    -- Opciones: cada ventana con su casilla. Sin la lista de compra, la de vender sigue
    local wasShown = sp._shown
    ES:SetOption("noAuctionWindows", false)
    assert(sp._shown == wasShown, "sin la lista de compra, la de vender sigue saliendo")
    local mini = ES.ShoppingMini()
    assert(not mini or mini._shown == false, "con la lista de compra desactivada, no sale sola")
    ES:SetOption("noAuctionWindows", true)
    assert(ES.db.noAuctionWindows == nil, "la lista de compra, activada otra vez")
    local sellOpt
    for _, cb in ipairs(ES:OptionsWindow().checks) do if cb.option.key == "noAuctionSellWindow" then sellOpt = cb.option end end
    assert(sellOpt and sellOpt.cat == "auction", "la opción de la ventana de vender está en la categoría Casa de Subastas")
    ES:SetOption("noAuctionSellWindow", false)
    assert(sp._shown == false and ES.db.noAuctionSellWindow == true, "desactivada, la ventana de vender no sale")
    ES:SetOption("noAuctionSellWindow", true)
    assert(sp._shown == wasShown and ES.db.noAuctionSellWindow == nil, "activada otra vez, la de vender vuelve")
    -- Quien había quitado las ventanas de la AH (eran una opción) sigue sin la de vender
    local m = { noAuctionWindows = true }
    local savedDB = ES.db
    ES.db = m
    ES:MigrateWindowOptions()
    assert(m.noAuctionSellWindow == true and m.sellWindowSplit, "migración: sin ventanas de la AH, tampoco la de vender")
    m.noAuctionSellWindow = nil
    ES:MigrateWindowOptions()
    assert(m.noAuctionSellWindow == nil, "la migración solo se hace una vez")
    ES.db = savedDB
    log[#log+1] = "     opciones: la lista de compra y la ventana de vender, cada una con su casilla"
    -- La ✕ de la ventana de vender: la lista de compra se recoloca junto a la AH (sin hueco)
    local savedPlace, placed = ES.PlaceShoppingMini, false
    ES.PlaceShoppingMini = function() placed = true end
    local okClose, errClose = pcall(sp.closeButton._scripts.OnClick, sp.closeButton)
    assert(okClose, "la ✕ de la ventana de vender da error: " .. tostring(errClose))
    assert(placed and sp._shown == false, "al cerrar la de vender, la lista de compra se recoloca")
    ES.PlaceShoppingMini, ES.AuctionSell.closed = savedPlace, nil
    ES.AuctionSell:Refresh()
    CraftersJournalMainFrame = savedMain
    ES.AuctionSell:Refresh()
    assert(sp._shown == false, "con la ventana grande al lado de la AH, la de vender no sale")
    ES.db.noAuctionSellWindow, ES.db.windowTips = savedSellOpt, savedTips
    AuctionHouseFrame = savedAHF
  end
  -- La ventana junto al vendedor vende también lo que el Inventario manda al vendedor
  local inSell = {}
  for _, s in ipairs(ES.VendorShop:SellList()) do inSell[s.itemID] = s.n end
  assert(inSell[JUNK] == 2 and not inSell[LL], "ventana del vendedor: lo del Inventario para el vendedor (" .. tostring(inSell[JUNK]) .. ")")
  -- No vender nunca: las herramientas de profesión no se proponen (Blacksmith Hammer:
  -- 3c al vendedor, pero sin él no hay Herrería); con clic derecho, lo que tú quieras
  local Inv = ES.Inventory
  assert(Inv.NeverSell(5956) == "tool" and Inv.NeverSell(2901) == "tool" and not Inv.NeverSell(JUNK), "herramientas")
  local savedPrint = ES.Print
  ES.Print = function() end
  local savedNever = ES.db.neverSell
  ES.db.neverSell = nil
  local function Find(id) for _, e in ipairs(Inv:List()) do if e.itemID == id then return e end end end
  -- Clic derecho en su fila del Inventario: deja de proponerse y pasa a "No se venden"
  ES:RenderInventory()
  local junkRow
  for _, row in ipairs(page.rows) do if row._shown ~= false and row.item == JUNK and row.onRightClick then junkRow = row end end
  assert(junkRow, "la fila del Inventario tiene clic derecho")
  junkRow._scripts.OnClick(junkRow, "RightButton")
  local j = Find(JUNK)
  assert(Inv.NeverSell(JUNK) == "user" and j and j.never == "user" and j.vendorN == 0 and j.keep == j.count, "marcar: no se vende")
  for _, s in ipairs(ES.VendorShop:SellList()) do assert(s.itemID ~= JUNK, "la ventana del vendedor lo sigue proponiendo") end
  local sections = {}
  for _, row in ipairs(page.rows) do if row._shown ~= false then sections[#sections + 1] = tostring(row.section._text) end end
  assert(table.concat(sections, "|"):find("No se venden"), "falta la sección No se venden")
  -- Clic derecho en "No se venden": vuelve a proponerse
  for _, row in ipairs(page.rows) do
    if row._shown ~= false and row.item == JUNK and row.onRightClick then junkRow = row end
  end
  junkRow._scripts.OnClick(junkRow, "RightButton")
  assert(not Inv.NeverSell(JUNK) and Find(JUNK).vendorN == 2, "desmarcar: se vuelve a proponer")
  -- Una herramienta desmarcada sí se puede vender
  Inv.SetNeverSell(5956, false)
  assert(not Inv.NeverSell(5956), "herramienta desmarcada")
  Inv.SetNeverSell(5956, true)
  assert(Inv.NeverSell(5956) == "user", "herramienta marcada otra vez")
  ES.db.neverSell, ES.Print = savedNever, savedPrint
  C_Container, ES.db.scans, ES.VendorSellPrice = savedCC, savedScans, savedVendor
  ES.Market.ReferencePrice, ES.Market.Signals, ES.RouteLock, ES.LockedPlan, ES.Planner.NeedFrom = savedRef, savedSig, savedLock, savedLocked, savedNeed
  ES.Ledger.MerchantOpen, ES.Ledger.SellToVendor, ES.Ledger.PostOnAH, ES.IsAuctionHouseOpen = savedMerchant, savedSell, savedPost, savedAH
  ES.db.noPostConfirm = savedNoConfirm
  ES:SelectPage("home")
end)
step("anunciar con la AH ocupada: un aviso, no uno por clic", function()
  local savedCAH, savedIL, savedAH, savedPrint, savedGT = C_AuctionHouse, ItemLocation, ES.IsAuctionHouseOpen, ES.Print, GetTime
  local clock, ready, printed, posts = 100, false, {}, 0
  GetTime = function() return clock end
  ES.IsAuctionHouseOpen = function() return true end
  ES.Print = function(_, msg) printed[#printed + 1] = msg end
  C_AuctionHouse = { IsThrottledMessageSystemReady = function() return ready end,
    PostItem = function() posts = posts + 1 end }
  ItemLocation = { CreateFromBagAndSlot = function() return {} end }
  -- Escaneando: no se anuncia (el precio de la fila es el del escaneo anterior)
  do
    local savedState, savedProg = ES.Scanner.state, ES.Scanner.progress
    ES.Scanner.state, ES.Scanner.progress = "scanning", 0.45
    ready = true
    local n = ES.Ledger:PostOnAH(2318, 1, 500)
    assert(n == 0 and posts == 0, "escaneando no se anuncia")
    assert(#printed == 1 and printed[1]:find("45%", 1, true), "escaneando: aviso con el %: " .. tostring(printed[1]))
    ES.Scanner.state, ES.Scanner.progress = savedState, savedProg
    ready, printed = false, {}
  end
  ES.Ledger.ahBusy = nil
  for _ = 1, 5 do ES.Ledger:PostOnAH(2318, 1, 500) clock = clock + 0.3 end
  assert(#printed == 1 and posts == 0, "cinco clics con la AH ocupada: un solo aviso (" .. #printed .. ")")
  ready = true
  FireEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
  assert(#printed == 2 and (printed[2]:find("ready") or printed[2]:find("lista")),"avisa cuando la AH está lista: " .. tostring(printed[2]))
  -- Ocupada aunque pasen segundos: nunca se anuncia con la AH ocupada (el servidor lo
  -- rechazaba en silencio y el chat decía "Anunciados" igual)
  ready, printed, posts = false, {}, 0
  ES.Ledger:PostOnAH(2318, 1, 500)
  clock = clock + 4
  ES.Ledger:PostOnAH(2318, 1, 500)
  assert(#printed == 1 and posts == 0, "ocupada: ni se anuncia ni se repite el aviso")
  ready = true
  FireEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
  printed = {}
  FireEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
  assert(#printed == 0, "sin clic pendiente, la AH lista no avisa")
  -- "Anunciados" solo cuando la AH confirma; si da error, se dice cuál
  local savedCC = C_Container
  C_Container = {
    GetContainerNumSlots = function(bag) return bag == 0 and 1 or 0 end,
    GetContainerItemID = function(bag, slot) return 2318 end,
    GetContainerItemInfo = function() return { stackCount = 5 } end,
  }
  ES.Ledger.pendingPost = nil
  printed, posts = {}, 0
  local n = ES.Ledger:PostOnAH(2318, 2, 500)
  assert(n == 2 and posts == 1 and #printed == 0, "al pedir el anuncio aún no se dice Anunciados (" .. #printed .. ")")
  FireEvent("AUCTION_HOUSE_AUCTION_CREATED")
  assert(#printed == 1 and (printed[1]:find("Posted") or printed[1]:find("Anunciados")), "confirmado: " .. tostring(printed[1]))
  printed = {}
  ES.Ledger:PostOnAH(2318, 2, 500)
  ES.Ledger:PostOnAH(2318, 2, 500) -- (sin confirmar el anterior: uno cada vez)
  assert(posts == 2, "con un anuncio sin confirmar no se pide otro: " .. posts)
  -- Un error en rojo que no es de la AH no rechaza el anuncio (antes: "no aceptó X: Out of range")
  ERR_NOT_ENOUGH_MONEY = "Not enough money" -- (el texto del juego; se lee al primer error)
  FireEvent("UI_ERROR_MESSAGE", 1, "Out of range")
  assert(ES.Ledger.pendingPost, "un error que no es de la AH rechazó el anuncio")
  FireEvent("UI_ERROR_MESSAGE", 1, "Not enough money")
  assert(printed[#printed]:find("Not enough money", 1, true), "error de la AH: " .. tostring(printed[#printed]))
  assert(ES.Ledger.pendingPost == nil, "tras el error ya no hay anuncio pendiente")
  FireEvent("UI_ERROR_MESSAGE", 1, "Out of range")
  assert(not printed[#printed]:find("Out of range", 1, true), "sin anuncio pendiente, los errores no son del addon")
  C_Container = savedCC
  -- Duración: se pregunta al juego por el depósito de cada índice (Forever 2/8/24 h)
  local D = ES.Ledger.DurationIndex
  local function Deposits(a, b, c)
    ES.Ledger.durationHours = nil
    return { CalculateItemDeposit = function(_, d) return ({ a, b, c })[d] end }
  end
  local i, h = D(24, Deposits(5, 20, 60), {}, 1, 1, false)
  assert(i == 3 and h == 24, "Forever: 24 h es el índice 3 (" .. tostring(i) .. ")")
  i, h = D(8, Deposits(5, 20, 60), {}, 1, 1, false)
  assert(i == 2 and h == 8, "Forever: 8 h es el índice 2")
  i, h = D(8, Deposits(15, 30, 60), {}, 1, 1, false)
  assert(i == 1 and h == 12, "cliente moderno: lo más corto que cubra 8 h son 12 h")
  i, h = D(24, Deposits(100, 100, 100), {}, 1, 1, false) -- depósito mínimo: no se sabe
  assert(i == 3 and h == 24 and ES.Ledger.durationHours == nil, "sin saberlo: 2/8/24")
  ES.Ledger.durationHours = nil
  C_AuctionHouse, ItemLocation, ES.IsAuctionHouseOpen, ES.Print, GetTime = savedCAH, savedIL, savedAH, savedPrint, savedGT
end)
step("inventario: sin saber si se vende, el depósito que se pierde cuenta", function()
  -- Crimson Silk Pantaloons: 32s en la AH (30s 39c tras la comisión) frente a 24s 30c del
  -- vendedor. Con pocos datos se anuncia a 8 h y, si caduca, se pierde su depósito
  -- (4s 86c): 25s 53c no compensa frente a 24s 30c seguros. Con pocos datos, vendedor
  local PANTS = 7062
  local savedCC, savedScans, savedVendor, savedSig, savedRef = C_Container, ES.db.scans, ES.VendorSellPrice, ES.Market.Signals, ES.Market.ReferencePrice
  C_Container = {
    GetContainerNumSlots = function(bag) return bag == 0 and 1 or 0 end,
    GetContainerItemID = function(bag, slot) return slot == 1 and PANTS or nil end,
    GetContainerItemInfo = function() return { stackCount = 5 } end,
  }
  ES.VendorSellPrice = function(_, id) return id == PANTS and 2430 or 1 end
  ES.Market.ReferencePrice = function() return nil end
  ES.db.scans = { [ES:RealmKey()] = { time = time() - 600, items = { [PANTS] = { minUnit = 3200, quantity = 3 } } } }
  local function Pants()
    for _, e in ipairs(ES.Inventory:List()) do if e.itemID == PANTS then return e end end
  end
  ES.Market.Signals = function() return { verdict = "unknown" } end
  local e = Pants()
  assert(e.ahN == 0 and e.vendorN == 5 and e.riskyAH, "con pocos datos, al vendedor (y avisando): ah " .. e.ahN)
  assert(e.hours == 8 and math.abs(e.depositRisk - 2430 * 0.2) < 1, "riesgo = depósito de 8 h: " .. tostring(e.depositRisk))
  -- Con un margen mayor, el depósito de 8 h ya compensa: a la AH, a 8 h
  ES.db.scans[ES:RealmKey()].items[PANTS].minUnit = 3600
  e = Pants()
  assert(e.ahN > 0 and e.hours == 8 and not e.riskyAH, "margen suficiente con el depósito de 8 h: ah " .. e.ahN)
  -- Las ventanas junto al vendedor y la AH enseñan EXACTAMENTE las secciones de la
  -- pestaña: con mercado dudoso, 5 a la AH y el resto se GUARDA para anunciarlo después
  -- ("+3 después"; antes iba al vendedor y en la AH valen más), en "Vender en la AH". La
  -- ventana del vendedor no lo propone (Discord: 2 Bolt of Woolen Cloth al vendedor) y
  -- la de la AH sí
  local getInfo = C_Container.GetContainerItemInfo
  C_Container.GetContainerItemInfo = function() return { stackCount = 8 } end
  e = Pants()
  assert(e.ahN == 5 and e.vendorN == 0 and e.ahLater == 3,
    string.format("con mercado dudoso: ah %d, después %s, vendedor %d", e.ahN, tostring(e.ahLater), e.vendorN))
  local sec = ES.Inventory:Sections()
  local inAHSection = false
  for _, x in ipairs(sec.ah) do if x.itemID == PANTS then inAHSection = true end end
  assert(inAHSection, "la pestaña lo tiene en Vender en la AH")
  for _, s in ipairs(ES.VendorShop:SellList()) do assert(s.itemID ~= PANTS, "la ventana del vendedor propone algo que la pestaña tiene en la AH") end
  local inAHWindow = false
  for _, x in ipairs(ES.AuctionSell:List()) do if x.itemID == PANTS then inAHWindow = true end end
  assert(inAHWindow, "la ventana de la AH no lo lista")
  C_Container.GetContainerItemInfo = getInfo
  -- Lo que el vendedor no compra y en la AH no compensa (Basic Campfire Kit: 50c con
  -- miles a la venta y 1s de depósito si caduca): no se propone, pero sale explicado
  local savedVSP = ES.VendorSellPrice
  ES.VendorSellPrice = function(_, id) return id == PANTS and 0 or 1 end
  ES.db.scans[ES:RealmKey()].items[PANTS].minUnit = 50
  e = Pants()
  assert(e and e.riskyAH and e.ahN == 0 and e.vendorN == 0, "no compensa: ni AH ni vendedor")
  local nw = false
  for _, x in ipairs(ES.Inventory:Sections().notWorth) do if x.itemID == PANTS then nw = true end end
  assert(nw, "sale en No compensa venderlo ahora")
  ES.VendorSellPrice = savedVSP
  ES.db.scans[ES:RealmKey()].items[PANTS].minUnit = 3200
  ES.db.scans[ES:RealmKey()].items[PANTS].minUnit = 3200
  -- Si se sabe que se vende, a la AH a 24 h (el depósito se devuelve)
  ES.Market.Signals = function() return { verdict = "good" } end
  e = Pants()
  assert(e.ahN == 5 and not e.riskyAH and e.hours == 24, "con buen mercado, a la AH")
  -- Ctrl+clic derecho: lo pasas al vendedor aunque en la AH valga más (y vuelta)
  local savedPrintFV, savedForce = ES.Print, ES.db.forceVendor
  ES.Print = function() end
  assert(ES.Inventory.CanForceVendor(e), "una fila de la AH se puede pasar al vendedor")
  ES.Inventory.SetForceVendor(PANTS, true)
  e = Pants()
  assert(e.forcedVendor and e.ahN == 0 and e.vendorN == 5 and not e.unsure, "pasado al vendedor: todo al vendedor")
  local inV = false
  for _, x in ipairs(ES.Inventory:Sections().vendor) do if x.itemID == PANTS then inV = true end end
  assert(inV, "pasado al vendedor, sale en Vender al vendedor")
  ES.Inventory.SetForceVendor(PANTS, false)
  e = Pants()
  assert(not e.forcedVendor and e.ahN == 5 and ES.db.forceVendor == nil, "devuelto, vuelve a la AH")
  ES.Print, ES.db.forceVendor = savedPrintFV, savedForce
  C_Container, ES.db.scans, ES.VendorSellPrice, ES.Market.Signals, ES.Market.ReferencePrice = savedCC, savedScans, savedVendor, savedSig, savedRef
end)
step("inventario: sin precio de AH fiable, al vendedor (sin 'decide tú')", function()
  -- Discord: 17 Linen Belt y 44 Red Linen Bag en "sin precio de AH fiable: decide tú",
  -- sin proponerse a nadie ("no me gusta lo de decide tú"). Ahora, al vendedor con su
  -- nota; lo arriesgado (con precio) se puede pasar a la AH con Ctrl+clic derecho
  local BELT, CLOTH, BAG = 990010, 990011, 990012
  local bags = { { BELT, 17 }, { CLOTH, 20 }, { BAG, 44 } }
  local saved = { C_Container, ES.db.scans, ES.VendorSellPrice, GetItemInfoInstant, ES.GetItemData, ES.Market.AddonPrice, C_Item,
    ES.Market.Signals, ES.Market.ReferencePrice }
  local ok, err = pcall(function()
    C_Container = {
      GetContainerNumSlots = function(bag) return bag == 0 and #bags or 0 end,
      GetContainerItemID = function(bag, slot) return bags[slot] and bags[slot][1] end,
      GetContainerItemInfo = function(bag, slot) local b = bags[slot] return b and { stackCount = b[2], quality = 1 } end,
    }
    C_Item = nil
    GetItemInfoInstant = function(id)
      if id == BELT then return id, "Armor", "Cloth", "INVTYPE_WAIST", 134400, 4, 1 end
      if id == BAG then return id, "Container", "Bag", "INVTYPE_BAG", 134400, 1, 0 end
      return id, "Trade Goods", "Cloth", "", 134400, 7, 5
    end
    ES.GetItemData = function(_, id) if id == BELT or id == CLOTH or id == BAG then return "Obj" .. id, 1, 1 end return saved[5](ES, id) end
    ES.VendorSellPrice = function(_, id) return (id == BELT or id == CLOTH or id == BAG) and 25 or 1 end
    ES.Market.AddonPrice = function() return nil end
    ES.db.scans = { [ES:RealmKey()] = { time = time() - 600, items = {} } }
    local by = {}
    for _, e in ipairs(ES.Inventory:List()) do by[e.itemID] = e end
    assert(by[BELT] and by[BELT].noAH and by[BELT].vendorN == 17, "el cinturón sin precio de AH va al vendedor")
    assert(by[CLOTH] and by[CLOTH].noAH and by[CLOTH].vendorN == 20, "el material sin precio de AH también, con su nota")
    assert(not ES.Inventory.CanForceAH(by[CLOTH]), "sin precio de AH no se puede pasar a la AH")
    local sec, inVendor = ES.Inventory:Sections(), 0
    for _, x in ipairs(sec.vendor) do if x.itemID == BELT or x.itemID == CLOTH or x.itemID == BAG then inVendor = inVendor + 1 end end
    assert(inVendor == 3 and sec.unsure == nil, "los tres en Vender al vendedor, sin sección 'decide tú'")
    -- Con precio en la AH, pero arriesgado (pocos datos, el depósito no compensa: como
    -- los Crimson Silk Pantaloons de arriba): el equipo blanco también al vendedor
    ES.VendorSellPrice = function(_, id) return (id == BELT or id == CLOTH or id == BAG) and 2430 or 1 end
    ES.db.scans[ES:RealmKey()].items = { [BELT] = { minUnit = 3200, quantity = 3 }, [CLOTH] = { minUnit = 3200, quantity = 3 },
      [BAG] = { minUnit = 3200, quantity = 3 } }
    ES.Market.Signals = function() return { verdict = "unknown" } end
    ES.Market.ReferencePrice = function() return nil end
    by = {}
    for _, e in ipairs(ES.Inventory:List()) do by[e.itemID] = e end
    assert(by[BELT].riskyAH and by[BELT].vendorN == 17, "con la AH arriesgada, el cinturón al vendedor")
    assert(by[CLOTH].riskyAH and by[CLOTH].vendorN == 20, "con la AH arriesgada, el material al vendedor")
    assert(by[BAG].riskyAH and by[BAG].vendorN == 44, "con la AH arriesgada, la bolsa al vendedor (Red Linen Bag)")
    -- Ctrl+clic derecho: lo arriesgado, a la AH (y vuelta)
    local savedPrint, savedForceAH = ES.Print, ES.db.forceAH
    ES.Print = function() end
    assert(ES.Inventory.CanForceAH(by[CLOTH]), "lo arriesgado se puede pasar a la AH")
    ES.Inventory.SetForceAH(CLOTH, true)
    by = {}
    for _, e in ipairs(ES.Inventory:List()) do by[e.itemID] = e end
    assert(by[CLOTH].forcedAH and by[CLOTH].ahN == 20 and by[CLOTH].vendorN == 0, "pasado a la AH: todo a la AH")
    ES.Inventory.SetForceAH(CLOTH, false)
    by = {}
    for _, e in ipairs(ES.Inventory:List()) do by[e.itemID] = e end
    assert(not by[CLOTH].forcedAH and by[CLOTH].vendorN == 20 and ES.db.forceAH == nil, "devuelto, otra vez al vendedor")
    ES.Print, ES.db.forceAH = savedPrint, savedForceAH
  end)
  C_Container, ES.db.scans, ES.VendorSellPrice, GetItemInfoInstant, ES.GetItemData, ES.Market.AddonPrice, C_Item =
    saved[1], saved[2], saved[3], saved[4], saved[5], saved[6], saved[7]
  ES.Market.Signals, ES.Market.ReferencePrice = saved[8], saved[9]
  if not ok then error(err, 0) end
  log[#log+1] = "     sin precio de AH fiable: al vendedor con su nota; lo arriesgado, a la AH con Ctrl+clic derecho"
end)
step("inventario: lo que daría desencantar (solo informativo)", function()
  -- Un verde de armadura nivel 22 ligado (4-6 polvos extraños de media al 75%), un arma
  -- verde del mismo nivel (sobre todo esencias), un gris y un verde que se vende caro
  local ARMOR, WEAPON, GREY, PRICEY = 9001, 9002, 9003, 9004
  local bags = { { ARMOR, 1, true }, { WEAPON, 1 }, { GREY, 1 }, { PRICEY, 1 } }
  local INFO = { [ARMOR] = { 2, 22, 4 }, [WEAPON] = { 2, 22, 2 }, [GREY] = { 0, 22, 4 }, [PRICEY] = { 2, 22, 4 } }
  local savedCC, savedScans, savedVendor, savedGII = C_Container, ES.db.scans, ES.VendorSellPrice, GetItemInfo
  local savedSkill, savedSpell, savedSig = ES.GetProfessionSkill, GetSpellInfo, ES.Market.Signals
  C_Container = {
    GetContainerNumSlots = function(bag) return bag == 0 and #bags or 0 end,
    GetContainerItemID = function(bag, slot) return bags[slot] and bags[slot][1] end,
    GetContainerItemInfo = function(bag, slot) local b = bags[slot] return b and { stackCount = b[2], isBound = b[3] } end,
  }
  GetItemInfo = function(id) local i = INFO[id] if i then return "Obj" .. id, nil, i[1], i[2], 20, nil, nil, 1, nil, 134400, 100, i[3] end
    return savedGII(id) end
  local VENDOR = { [ARMOR] = 100, [WEAPON] = 100, [GREY] = 100, [PRICEY] = 100 }
  ES.VendorSellPrice = function(_, id) return VENDOR[id] or 1 end
  -- Polvo extraño a 50c, esencia astral menor a 1s; el verde caro se vende a 50s en la AH
  ES.db.scans = { [ES:RealmKey()] = { time = time() - 600, items = {
    [10940] = { minUnit = 50, quantity = 100 }, [10998] = { minUnit = 100, quantity = 20 },
    [PRICEY] = { minUnit = 5000, quantity = 1 } } } }
  ES.Market.Signals = function() return { verdict = "good" } end
  GetSpellInfo = function(id) if id == 13262 then return "Desencantar" end end
  local function By()
    local by = {}
    for _, e in ipairs(ES.Inventory:List()) do by[e.itemID] = e end
    return by
  end
  -- Solo informativo: el reparto AH / vendedor no cambia, y se dice lo que daría
  ES.GetProfessionSkill = function() return nil end
  local by = By()
  local de = by[ARMOR] and by[ARMOR].de
  -- 0.75 x 5 polvos x ~47c + 0.15 x 1.5 esencias x ~95c + 0.10 x fragmento (sin precio: vendedor 1c)
  log[#log+1] = string.format("     verde nivel 22 (armadura): desencantado ~%dc frente a 100c del vendedor", de and de.value or -1)
  assert(de and not by[ARMOR].deCan and by[ARMOR].vendorN == 1, "sin Encantamiento: se informa y se sigue vendiendo")
  assert(de.value > 150 and de.value < 220, "valor medio del verde de armadura: " .. de.value)
  assert(de.partial, "el fragmento no estaba en el escaneo: se avisa")
  assert(by[WEAPON] and by[WEAPON].de and by[WEAPON].de.value < de.value, "un arma da sobre todo esencias (aquí valen menos que los polvos)")
  assert(not by[GREY] or not by[GREY].de, "un gris no se desencanta")
  assert(by[PRICEY] and not by[PRICEY].de and by[PRICEY].ahN == 1, "si en la AH vale más, no se habla de desencantar")
  -- Con Encantamiento: 30 llega al 25 que pide el nivel 22; 10 no
  ES.GetProfessionSkill = function(_, line) if line == 333 then return 30, 75 end end
  by = By()
  assert(by[ARMOR].deCan and by[ARMOR].vendorN == 1, "con Encantamiento 30 se puede, pero sigue en vender")
  ES.GetProfessionSkill = function(_, line) if line == 333 then return 10, 75 end end
  by = By()
  assert(not by[ARMOR].deCan and by[ARMOR].deRank == 10, "con 10 no llega al 25 que pide")
  -- La página: la fila lo dice; no hay botón de desencantar
  ES:SelectPage("inventory")
  local page = ES.inventoryPage
  page._shown = true
  ES:RenderInventory()
  assert(page.deButton == nil, "no debe haber botón de desencantar")
  local found
  for _, row in ipairs(page.rows) do if row._shown and row.sub and tostring(row.sub._text):find("desencantado") then found = tostring(row.sub._text) end end
  assert(found, "la fila debería decir lo que daría desencantado")
  log[#log+1] = "     fila: " .. found:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  C_Container, ES.db.scans, ES.VendorSellPrice, GetItemInfo = savedCC, savedScans, savedVendor, savedGII
  ES.GetProfessionSkill, GetSpellInfo, ES.Market.Signals = savedSkill, savedSpell, savedSig
  ES:SelectPage("home")
end)
step("novedades: una vez por versión, y en vista de desarrollo cuando quieras", function()
  local savedGet, savedSeen, savedScans, savedPage, savedDev = GetAddOnMetadata, ES.db.whatsNewSeen, ES.db.scans, ES.db.lastPage, ES.db.devTools
  -- (la versión de las últimas notas, para no tocar la prueba en cada versión; y otras
  -- derivadas de ella: la anterior, un parche sin notas y una futura)
  local latest = ES.WHATS_NEW[1].version
  -- (la de las notas puede ser un parche: 0.72.2; el parche siguiente, sin notas, 0.72.3)
  local ma, mi, pa = latest:match("^(%d+)%.(%d+)%.?(%d*)")
  ma, mi, pa = tonumber(ma), tonumber(mi), tonumber(pa) or 0
  local previous, patch = ma .. "." .. (mi - 1) .. ".0", ma .. "." .. mi .. "." .. (pa + 1)
  local midway, future = ma .. "." .. mi .. "." .. (pa + 3), ma .. "." .. (mi + 1) .. ".0"
  local version = latest
  GetAddOnMetadata = function(_, field) if field == "Version" then return version end end
  local function Shown() local f = ES.WhatsNewFrame() return f and f._shown end
  local function Hide() local f = ES.WhatsNewFrame() if f then f:Hide() end end
  -- Comparar versiones número a número (0.10 va después de 0.9)
  assert(ES.CompareVersions(latest, previous) == 1 and ES.CompareVersions("0.9.0", "0.10.0") == -1
    and ES.CompareVersions("1.0", "1.0.0") == 0, "comparar versiones")
  -- Instalación nueva: no sale, se apunta la versión
  ES.db.whatsNewSeen, ES.db.scans, ES.db.lastPage = nil, {}, nil
  ES:CheckWhatsNew()
  assert(not Shown() and ES.db.whatsNewSeen == version, "en una instalación nueva no salen novedades")
  -- Quien venía de antes (sin versión vista, pero con escaneos): la de esta versión
  ES.db.whatsNewSeen, ES.db.scans = nil, savedScans
  ES:CheckWhatsNew()
  assert(Shown() and ES.db.whatsNewSeen == version, "al actualizar desde antes de las novedades, salen")
  local f = ES.WhatsNewFrame()
  assert(tostring(f.sub._text):find(version, 1, true), "la cabecera dice la versión: " .. tostring(f.sub._text))
  local items = 0
  for _, l in ipairs(f.lines) do if l._shown ~= false and l.icon._shown ~= false and tostring(l.text._text) ~= "" then items = items + 1 end end
  -- (las de imagen, una página cada una en vez de una fila)
  if f.page and f.page._shown and f.pages then items = items + #f.pages end
  -- (la de elegir algo, su diapositiva sola)
  if f.choiceView and f.choiceView._shown then items = items + 1 end
  assert(items == #ES.WHATS_NEW[1].items, "una fila o una página por novedad: " .. items)
  assert(tostring(f.devTag._text) == "", "sin vista de desarrollo, no lo dice")
  Hide()
  -- Otra vez con la misma versión: no sale
  ES:CheckWhatsNew()
  assert(not Shown(), "con la versión ya vista, no vuelve a salir")
  -- Versión nueva sin notas: no sale, pero se apunta
  version = patch
  ES:CheckWhatsNew()
  assert(not Shown() and ES.db.whatsNewSeen == patch, "una versión sin notas no abre la ventana")
  -- Saltándose versiones: desde la vista hasta la actual, nunca las aún sin publicar
  local fake = { version = future, items = { { title = "x", text = "y" } } }
  table.insert(ES.WHATS_NEW, 1, fake)
  local since = ES:WhatsNewSince(previous, midway)
  assert(#since == 1 and since[1].version == latest, "solo las publicadas y no vistas")
  since = ES:WhatsNewSince(previous, future)
  assert(#since == 2 and since[1].version == future, "las dos versiones nuevas, la más nueva arriba")
  table.remove(ES.WHATS_NEW, 1)
  -- Saltándose versiones, en la ventana: UNA lista sin cabeceras de versión, como mucho
  -- WHATS_NEW_MAX_ITEMS, y las destacadas (top) primero aunque sean de una versión anterior
  do
    local fakeTop = { version = future, items = {
      { title = "nueva 1", text = "a" }, { title = "nueva 2", text = "b" } } }
    local fakeOld = { version = midway, items = {
      { title = "vieja 1", text = "c" }, { title = "destacada", text = "d", top = true },
      { title = "vieja 3", text = "e" }, { title = "vieja 4", text = "f" }, { title = "vieja 5", text = "g" } } }
    table.insert(ES.WHATS_NEW, 1, fakeOld)
    table.insert(ES.WHATS_NEW, 1, fakeTop)
    ES:ShowWhatsNew(ES:WhatsNewSince(latest, future))
    local f2 = ES.WhatsNewFrame()
    local titles = {}
    for _, l in ipairs(f2.lines) do
      if l._shown ~= false then
        assert(l.icon._shown ~= false, "una fila sin icono: cabecera de versión (ya no las hay)")
        titles[#titles + 1] = tostring(l.title._text)
      end
    end
    assert(#titles == ES.WHATS_NEW_MAX_ITEMS, "como mucho " .. ES.WHATS_NEW_MAX_ITEMS .. ": " .. #titles)
    assert(titles[1] == "destacada" and titles[2] == "nueva 1" and titles[3] == "nueva 2",
      "la destacada primero, luego lo más nuevo: " .. table.concat(titles, " | "))
    Hide()
    table.remove(ES.WHATS_NEW, 1)
    table.remove(ES.WHATS_NEW, 1)
    log[#log+1] = "     novedades saltándose versiones: " .. table.concat(titles, " | ")
  end
  -- Vista de desarrollo (/cj whatsnew, DevTools.lua: en esta copia sí está): no cambia lo visto
  assert(ES.DevCommand, "en la copia de desarrollo se carga DevTools.lua")
  local savedPrint = ES.Print
  ES.Print = function() end
  local seenBefore = ES.db.whatsNewSeen
  SlashCmdList.CRAFTERSJOURNAL("whatsnew " .. latest)
  assert(Shown() and ES.db.whatsNewSeen == seenBefore, "la vista de desarrollo se abre y no cuenta como vista")
  assert(tostring(ES.WhatsNewFrame().devTag._text) ~= "", "la vista de desarrollo lo dice abajo")
  Hide()
  -- Sin DevTools.lua (lo publicado), /cj whatsnew es como /cj: abre la ventana principal
  local savedDevCmd, savedToggle, toggled = ES.DevCommand, ES.ToggleMainFrame, false
  ES.DevCommand, ES.ToggleMainFrame = nil, function() toggled = true end
  SlashCmdList.CRAFTERSJOURNAL("whatsnew")
  assert(toggled and not Shown(), "sin DevTools.lua, /cj whatsnew no abre las novedades")
  ES.DevCommand, ES.ToggleMainFrame, ES.Print = savedDevCmd, savedToggle, savedPrint
  -- Lo publicado no lleva DevTools.lua: su línea del .toc va en #@do-not-package@
  assert(TOC_TEXT:find("#@do%-not%-package@%s+DevTools%.lua%s+#@end%-do%-not%-package@"),
    "DevTools.lua debe ir dentro de #@do-not-package@ en el .toc")
  -- El asistente de ruta se publica (beta, 0.61.0): con los buzones, fuera de
  -- #@do-not-package@; sus bancos (A.BANK, apagado), aún dentro
  assert(TOC_TEXT:find("\nAssistant%.lua") and not TOC_TEXT:find("#@do%-not%-package@%s+Assistant%.lua"),
    "Assistant.lua debe publicarse (fuera de #@do-not-package@)")
  assert(TOC_TEXT:find("\nData\\Mailboxes%.lua") and not TOC_TEXT:find("#@do%-not%-package@%s+Data\\Mailboxes%.lua"),
    "Data\\Mailboxes.lua debe publicarse con el asistente")
  assert(TOC_TEXT:find("#@do%-not%-package@%s+Data\\Bankers%.lua%s+#@end%-do%-not%-package@"),
    "Data\\Bankers.lua (banco apagado) sigue sin publicarse")
  -- BulkMoney y su botón de anunciar (en desarrollo): tampoco se publican
  assert(TOC_TEXT:find("#@do%-not%-package@%s+BulkMoneyUI%.lua%s+BulkPostUI%.lua%s+#@end%-do%-not%-package@"),
    "BulkMoneyUI.lua y BulkPostUI.lua deben ir dentro de #@do-not-package@ en el .toc")
  GetAddOnMetadata = savedGet
  ES.db.whatsNewSeen, ES.db.scans, ES.db.lastPage, ES.db.devTools = savedSeen, savedScans, savedPage, savedDev
  log[#log+1] = "     novedades: una vez por versión, nada en instalaciones nuevas, /cj whatsnew solo en la copia de desarrollo"
end)
-- Receta de la AH ya comprada (Ledger.OnWay): la fila no lleva a ninguna parte, y su
-- tooltip ni da error (WP.AddToTooltip con pick nil) ni promete "buscarla en la AH"
step("receta comprada en la AH: el tooltip sin error y sin prometer el clic", function()
  local WP = ES.Waypoints
  local saved = { WP.RecipeSource, ES.Ledger.OnWay, ES.IsAuctionHouseOpen, WP.Available,
    GameTooltip.AddLine, GameTooltip.AddDoubleLine }
  local ok, err = pcall(function()
    local SCROLL = 99901
    WP.RecipeSource = function()
      return { best = { kind = "ah" }, ah = { price = 5000, listings = 3 }, quests = {}, vendors = {}, options = {} }
    end
    local bought = 1
    ES.Ledger.OnWay = function(id) return id == SCROLL and bought or 0 end
    WP.Available = function() return true end
    local tip = {}
    GameTooltip.AddLine = function(_, t) tip[#tip + 1] = tostring(t) end
    GameTooltip.AddDoubleLine = function(_, a, b) tip[#tip + 1] = tostring(a) .. " | " .. tostring(b) end
    local r = { name = "Pattern: Prueba", scroll = SCROLL, train = 100 }
    local st = { from = 100, fee = 5000 }
    local plan = { ctx = { prices = {}, opts = {} } }
    local line = ES.SourcedLearnLine(r, st, "Sastrería", plan)
    assert(line and line.bought and line.go == nil and line.ahItem == nil,
      "la fila comprada no busca en la AH ni marca el camino")
    for _, open in ipairs({ false, true }) do
      ES.IsAuctionHouseOpen = function() return open end
      tip = {}
      local okTip, errTip = pcall(line.tooltip, CreateFrame("Button"))
      assert(okTip, "con la AH " .. (open and "abierta" or "cerrada") .. ", el tooltip da error: " .. tostring(errTip))
      local text = table.concat(tip, "\n")
      assert(not text:find("Clic: buscarla en la Casa de Subastas", 1, true), "promete buscarla en la AH:\n" .. text)
      assert(not text:find("Clic: marcar el camino", 1, true), "promete marcar el camino:\n" .. text)
    end
    -- Sin comprar, la misma receta sí: con la AH abierta, buscarla
    bought = 0
    line = ES.SourcedLearnLine(r, st, "Sastrería", plan)
    ES.IsAuctionHouseOpen = function() return true end
    tip = {}
    line.tooltip(CreateFrame("Button"))
    assert(line.ahItem == SCROLL and table.concat(tip, "\n"):find("Clic: buscarla en la Casa de Subastas", 1, true),
      "sin comprar, la fila de la AH busca la receta")
    -- WP.AddToTooltip sin función: nada, sin error
    tip = {}
    WP.AddToTooltip("Subastador más cercano", nil)
    assert(#tip == 0, "WP.AddToTooltip sin pick no añade nada")
  end)
  WP.RecipeSource, ES.Ledger.OnWay, ES.IsAuctionHouseOpen, WP.Available, GameTooltip.AddLine, GameTooltip.AddDoubleLine =
    saved[1], saved[2], saved[3], saved[4], saved[5], saved[6]
  if not ok then error(err, 0) end
end)
-- La versión del .toc la pone el empaquetador (@project-version@ -> la etiqueta): en la
-- copia de desarrollo se queda el marcador
step("versión del addon: la de la etiqueta, o dev en la copia de desarrollo", function()
  local savedGet, savedSeen, savedLog = GetAddOnMetadata, ES.db.whatsNewSeen, ES.db.errorLog
  local ok, err = pcall(function()
    assert(TOC_TEXT:find("\n## Version: @project%-version@"), "el .toc del repositorio lleva @project-version@")
    local version
    GetAddOnMetadata = function(_, field) if field == "Version" then return version end end
    local function Shown() local f = ES.WhatsNewFrame() return f and f._shown end
    if ES.WhatsNewFrame() then ES.WhatsNewFrame():Hide() end
    -- Copia de desarrollo: "dev", Novedades no sale sola ni apunta nada
    version = "@project-version@"
    assert(ES.AddonVersion() == "dev", "el marcador es la versión de desarrollo: " .. tostring(ES.AddonVersion()))
    ES.db.whatsNewSeen = "0.1.0"
    ES:CheckWhatsNew()
    assert(not Shown() and ES.db.whatsNewSeen == "0.1.0", "en la copia de desarrollo Novedades no sale sola")
    ES.db.errorLog = {}
    ES:RecordError("test", "error de prueba (dev)")
    assert(ES.db.errorLog[1].version == "dev", "el error apunta dev: " .. tostring(ES.db.errorLog[1].version))
    -- Lo publicado: la de la etiqueta, con o sin la v
    for _, meta in ipairs({ "0.64.0", "v0.64.0" }) do
      version = meta
      assert(ES.AddonVersion() == "0.64.0", meta .. " -> " .. tostring(ES.AddonVersion()))
      ES.db.errorLog = {}
      ES:RecordError("test", "error de prueba")
      assert(ES.db.errorLog[1].version == "0.64.0", "el error apunta 0.64.0: " .. tostring(ES.db.errorLog[1].version))
    end
    ES:CheckWhatsNew()
    assert(ES.db.whatsNewSeen == "0.64.0", "con la versión publicada, Novedades la apunta")
    if ES.WhatsNewFrame() then ES.WhatsNewFrame():Hide() end
    -- Quien vio la 0.61.0 y entra con la 0.64.0: la 0.64.0, la 0.63.0 y la 0.62.0
    -- (la 0.61.2 no se publicó: sus notas van con la 0.62.0)
    local has = {}
    for _, v in ipairs(ES.WHATS_NEW) do has[v.version] = true end
    assert(has["0.62.0"] and has["0.63.0"], "faltan las notas de la 0.62.0 o la 0.63.0")
    local fake = not has["0.64.0"] and { version = "0.64.0", items = { { title = "x", text = "y" } } }
    if fake then table.insert(ES.WHATS_NEW, 1, fake) end
    local since = ES:WhatsNewSince("0.61.0", "0.64.0")
    if fake then table.remove(ES.WHATS_NEW, 1) end
    local got = {}
    for _, v in ipairs(since) do got[#got + 1] = v.version end
    assert(table.concat(got, " ") == "0.64.0 0.63.0 0.62.0", "novedades de 0.61.0 a 0.64.0: " .. table.concat(got, " "))
    version = nil
    assert(ES.AddonVersion() == nil, "sin metadatos, nil")
  end)
  GetAddOnMetadata, ES.db.whatsNewSeen, ES.db.errorLog = savedGet, savedSeen, savedLog
  if not ok then error(err, 0) end
end)
step("sin modo desarrollo: ni Subastas, ni Flipping, ni Pesca, ni buscador", function()
  assert(ES.DEV == nil and ES.DEV_BUILD == nil, "queda el modo desarrollo")
  local f = ES:GetMainFrame()
  -- portada, lista de compra, ganar dinero, inventario, inversiones, Merchant's Favor,
  -- calculadora y colección; y, solo en esta copia de desarrollo, BulkMoney (dev)
  local published = 0
  for _, tab in ipairs(f.tabs) do if not ES.Tabs.Info(tab.key).dev then published = published + 1 end end
  assert(published == 8, "pestañas publicadas: " .. published)
  assert(not f.globalSearch, "queda el buscador de la cabecera")
  assert(not ES.optionsPanel, "queda el panel de Opciones (con el interruptor de vista de jugador)")
  -- Lo guardado de versiones anteriores (la última página) vuelve a la portada
  for _, key in ipairs({ "ah", "flipping", "Fishing", "pattern:Fishing" }) do
    ES:SelectPage(key)
    assert(ES.db.lastPage == "home", key .. " no debería abrirse")
  end
  for _, p in ipairs(ES.PROFESSIONS) do assert(p.key ~= "Fishing", "la Pesca sigue en la lista") end
  assert(not ES.Data.Fishing, "quedan los datos de la Pesca")
end)
step("ruta: la segunda mejor receta de cada paso y por qué es peor", function()
  local page
  for _, p in ipairs(ES.professionPages) do if p.profKey == "Leatherworking" then page = p end end
  ES:SelectPage("Leatherworking")
  page._shown = true
  page.toBox._text = "225"
  ES:CalculatePlan(page)
  local plan = page.plan
  assert(plan and #plan.steps > 0, "sin ruta de peletería")
  -- Se calculan repartidas en fotogramas: se ejecutan todos
  local savedAfter, queue = C_Timer.After, {}
  C_Timer.After = function(_, fn) queue[#queue + 1] = fn end
  plan.alts, plan.altsRunning = nil, nil
  ES:ComputeAlternatives(page, plan)
  local ticks = 0
  while #queue > 0 and ticks < 100000 do table.remove(queue, 1)() ticks = ticks + 1 end
  C_Timer.After = savedAfter
  assert(plan.alts, "no calculó las alternativas")
  local withAlt, cheaper = 0, 0
  for i = 1, #plan.steps do
    local list = plan.alts[i]
    assert(list, "paso " .. i .. " sin lista de alternativas")
    if list[1] then withAlt = withAlt + 1 end
    for _, a in ipairs(list) do
      -- La vara de la ruta (RouteScore) y el veredicto, en todas
      assert(type(a.score) == "number", "alternativa sin puntuación de ruta")
      local v = ES.Planner.AlternativeVerdict(plan, plan.steps[i], a)
      if a.delta <= -0.5 or a.score <= -0.5 then
        assert(v, "más barata sin veredicto")
        local st = plan.steps[i]
        log[#log+1] = string.format("       %s en %d-%d: %s oro %+.0fc, vara %+.0fc (ruta: %s)", v, st.from, st.to,
          ES.Data.Leatherworking.recipes[a.id].name, a.delta, a.score, st.recipe.name)
      else
        assert(v == nil, "veredicto sin ser más barata: " .. tostring(v))
      end
    end
    if list[1] and ES.Planner.AlternativeVerdict(plan, plan.steps[i], list[1]) == "better" then cheaper = cheaper + 1 end
    for k = 2, #list do assert(list[k].score >= list[k - 1].score, "alternativas sin ordenar") end
  end
  log[#log+1] = string.format("     %d pasos: %d con segunda opción, %d con una mejor que la ruta (%d fotogramas)", #plan.steps, withAlt, cheaper, ticks)
  assert(withAlt > 0, "ningún paso con segunda opción")
  -- La fila del paso ya no lo dice (estaba repetido): solo el tooltip, con las cifras y el motivo
  ES:RenderPlan(page)
  local tip, savedAdd, savedDouble = {}, GameTooltip.AddLine, GameTooltip.AddDoubleLine
  GameTooltip.AddLine = function(_, t) tip[#tip + 1] = tostring(t) end
  GameTooltip.AddDoubleLine = function(_, a, b) tip[#tip + 1] = tostring(a) .. " | " .. tostring(b) end
  local why = false
  for _, l in ipairs(page.lines) do
    local s = tostring(l.sub or "")
    assert(not s:find("2ª") and not s:find("única"), "la fila repite la segunda opción del tooltip: " .. s)
    if l.stepRecipe and l.tooltip and not why then
      tip = {}
      l.tooltip(CreateFrame("Frame"))
      for _, t in ipairs(tip) do if t:find("Por qué esta y no otra") or t:find("única receta") then why = true end end
    end
  end
  GameTooltip.AddLine, GameTooltip.AddDoubleLine = savedAdd, savedDouble
  assert(why, "el tooltip no explica por qué esta y no otra")
  for _, t in ipairs(tip) do if t:find("Peor porque") then log[#log+1] = "     tooltip: " .. t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") break end end
  ES:SelectPage("home")
end)
step("calculadora: desglose en crudo, precios a mano y cálculos guardados", function()
  local Calc = ES.Calc
  -- Dinero escrito como en una hoja de cálculo
  assert(Calc.ParseMoney("2,7") == 270 and Calc.ParseMoney("2.7") == 270, "2,7 = 2s 70c")
  assert(Calc.ParseMoney("1g 20s 5c") == 12005 and Calc.ParseMoney("1o 20p") == 12000, "con unidades")
  assert(Calc.ParseMoney("27c") == 27 and Calc.ParseMoney("") == nil and Calc.ParseMoney("abc") == nil, "cobre, vacío y basura")
  assert(Calc.FormatMoney(12005) == "1g 20s 5c" and Calc.FormatMoney(0) == "0c", "formato: " .. Calc.FormatMoney(12005))
  -- Una receta de sastrería que pide Bolt of Silk Cloth (4305), que sabes fabricar
  local data = ES.Data.Tailoring
  local SILK, BOLT, recipeID, boltID = 4306, 4305
  for id, r in pairs(data.recipes) do
    if r.out and r.out[1] == BOLT then boltID = id end
  end
  for id, r in pairs(data.recipes) do
    for _, rq in ipairs(r.r) do if rq[1] == BOLT and r.out and (not recipeID or id < recipeID) then recipeID = id end end
  end
  assert(boltID and recipeID, "no hay receta con Bolt of Silk Cloth")
  local savedKnown, savedScans, savedStanding, savedCalcs = ES.IsRecipeKnown, ES.db.scans, ES.Standing, ES.db.calcs
  ES.IsRecipeKnown = function(_, id) return id == boltID end
  ES.db.calcs = nil
  local outID = data.recipes[recipeID].out[1]
  ES.db.scans = { [ES:RealmKey()] = { time = time() - 600, items = {
    [SILK] = { minUnit = 200, quantity = 500 }, [outID] = { minUnit = 50000, quantity = 3 } } } }
  ES.Standing = function() return 4 end
  local c = Calc:Add("Tailoring", recipeID)
  local res = Calc:Compute(c)
  local by = {}
  for _, row in ipairs(res.rows) do by[row.itemID] = row end
  assert(not by[BOLT] and by[SILK], "el Bolt de seda debería desglosarse en su tela")
  assert(#res.made == 1 and res.made[1].itemID == BOLT, "y decirse que lo fabricas tú")
  local boltsNeeded
  for _, rq in ipairs(data.recipes[recipeID].r) do if rq[1] == BOLT then boltsNeeded = rq[2] end end
  local silkPerBolt
  for _, rq in ipairs(data.recipes[boltID].r) do if rq[1] == SILK then silkPerBolt = rq[2] end end
  assert(by[SILK].qty == boltsNeeded * silkPerBolt / (data.recipes[boltID].out[2] or 1), "tela: " .. by[SILK].qty)
  assert(by[SILK].source == "ah" and by[SILK].price == 200, "la seda, del escaneo")
  assert(res.made[1].mode == "craft" and not res.made[1].chosen, "sin precio del Bolt hecho, se fabrica")
  -- La hoja como árbol: el Bolt y, debajo y más adentro, su seda
  do
    local pos = {}
    for i, node in ipairs(res.display) do pos[node.made and "bolt" or node.item] = { i = i, depth = node.depth } end
    assert(pos.bolt and pos[SILK] and pos[SILK].i == pos.bolt.i + 1 and pos[SILK].depth == pos.bolt.depth + 1,
      "la seda no va debajo del Bolt, con sangría")
  end
  -- Comprarlo hecho o fabricarlo: lo más barato; clic en su fila para cambiarlo
  do
    c.prices[BOLT] = 1 -- (el Bolt hecho, casi regalado: comprarlo es lo más barato)
    local rb = Calc:Compute(c)
    local byB = {}
    for _, row in ipairs(rb.rows) do byB[row.itemID] = row end
    assert(rb.made[1].mode == "buy" and byB[BOLT] and not byB[SILK], "con el Bolt barato debería comprarse hecho")
    -- (comprado hecho: debajo de su fila sale él mismo, con su precio)
    local boltNode
    for i, node in ipairs(rb.display) do if node.item == BOLT then boltNode = { i = i, depth = node.depth } end end
    assert(boltNode and rb.display[boltNode.i - 1].made and boltNode.depth == rb.display[boltNode.i - 1].depth + 1,
      "comprado hecho, el Bolt no sale debajo de su fila")
    Calc:ToggleVia(c, rb.made[1])
    local rc = Calc:Compute(c)
    local byC = {}
    for _, row in ipairs(rc.rows) do byC[row.itemID] = row end
    assert(c.via[BOLT] == "craft" and rc.made[1].mode == "craft" and rc.made[1].chosen and byC[SILK] and not byC[BOLT],
      "el clic no lo cambió a fabricarlo")
    Calc:ToggleVia(c, rc.made[1])
    assert(c.via[BOLT] == nil and Calc:Compute(c).made[1].mode == "buy", "volver a lo más barato deja de estar elegido")
    c.prices[BOLT], c.via = nil, nil
  end
  -- Las cuentas: venta - comisión - materiales. El depósito (24 h: 60% del precio de
  -- vendedor) se devuelve al venderse: se enseña, pero no resta
  assert(math.abs(res.profit - (res.revenue - res.cut - res.cost)) < 0.01, "beneficio mal sumado")
  local outVendor = ES:VendorSellPrice(outID) or 0
  -- Mínimo de Forever: 1s por subasta (por montón en lo que se apila)
  assert(Calc.Deposit(1.5, 1, 1) == 100, "por debajo de 1s, 1s")
  assert(Calc.Deposit(300, 2, 1) == 600, "dos subastas de 3s")
  local d, n = Calc.Deposit(2, 20, 20)
  assert(d == 100 and n == 1, "un montón de 20 paga el mínimo una vez")
  d, n = Calc.Deposit(2, 25, 20)
  assert(d == 200 and n == 2, "25 en montones de 20: dos subastas")
  local stack = Calc.StackSize(outID)
  assert(res.hours == 24 and math.abs(res.deposit - Calc.Deposit(outVendor * 0.6, res.outN, stack)) < 0.01, "depósito 24 h = 60% del vendedor: " .. res.deposit)
  -- Duración elegida: 2 h = 5%, 8 h = 20% (y el beneficio no cambia: se devuelve)
  for hours, pct in pairs({ [2] = 0.05, [8] = 0.20 }) do
    c.hours = hours
    local rh = Calc:Compute(c)
    assert(math.abs(rh.deposit - Calc.Deposit(outVendor * pct, rh.outN, stack)) < 0.01 and rh.depositPct == pct * 100, hours .. " h: " .. rh.deposit)
    assert(math.abs(rh.profit - res.profit) < 0.01, "la duración no cambia el beneficio")
  end
  c.hours = nil
  assert(res.cutRate == 0.05 and res.saleSource == "ah" and res.sale == 49999, "venta en la AH a 1c menos: " .. tostring(res.sale))
  -- Precio a mano: solo en este cálculo
  c.prices[SILK] = Calc.ParseMoney("2,7")
  local res2 = Calc:Compute(c)
  for _, row in ipairs(res2.rows) do if row.itemID == SILK then assert(row.source == "manual" and row.price == 270, "precio a mano") end end
  assert(res2.cost > res.cost, "con la seda más cara, más coste")
  local c2 = Calc:Add("Tailoring", boltID)
  local r3 = Calc:Compute(c2)
  assert(r3.rows[1].price == 200, "el precio a mano de un cálculo no cambia otro")
  -- Cantidad: el doble de fabricaciones, el doble de materiales
  c.qty = 2
  assert(math.abs(Calc:Compute(c).cost - 2 * res2.cost) < 0.01, "cantidad x2")
  -- Descuento de vendedor por reputación con una capital (honorable: -10%)
  local vendorItem
  for _, rq in ipairs(data.recipes[recipeID].r) do if ES.Data.VendorPrices[rq[1]] then vendorItem = rq[1] end end
  if vendorItem then
    ES.Standing = function(_, id) return id == 72 and 6 or 4 end
    local r4 = Calc:Compute(c)
    for _, row in ipairs(r4.rows) do
      if row.itemID == vendorItem then
        assert(row.source == "vendor" and row.price == math.floor(ES.Data.VendorPrices[vendorItem] * 0.9 + 0.5), "descuento de ciudad")
      end
    end
    assert(r4.discount == 0.10, "descuento: " .. r4.discount)
  end
  -- La página: lista de guardados, hoja y escribir un precio en su casilla
  ES:SelectPage("calc")
  local page = ES.calculatorPage
  page._shown = true
  Calc:Select(c.id)
  ES:RenderCalculator()
  assert(page.saved[1]._shown and page.saved[2]._shown, "dos cálculos guardados en la lista")
  -- Muchos materiales: las filas van en su marco desplazable y el resumen no se sale
  -- del panel (antes empujaban el beneficio y los botones hacia abajo)
  do
    local savedH, savedW = page.sheet.GetHeight, page.sheet.GetWidth
    page.sheet.GetHeight = function() return 330 end  -- (poco alto: no caben todas)
    page.sheet.GetWidth = function() return 500 end
    local rowsH, scrollH
    local realSet, realScrollSet = page.rowsChild.SetHeight, page.rowsScroll.SetHeight
    page.rowsChild.SetHeight = function(self, h) rowsH = h end
    page.rowsScroll.SetHeight = function(self, h) scrollH = h end
    ES:RenderCalculator()
    assert(rowsH and scrollH and scrollH <= rowsH, "lo que se ve no pasa de las filas")
    if rowsH > 330 - 78 - 160 - 38 then
      assert(page.rowsScroll.overflow and scrollH < rowsH, "con poco alto, las filas se desplazan")
    end
    page.sheet.GetHeight = function() return 2000 end -- (mucho alto: caben todas, como antes)
    ES:RenderCalculator()
    assert(not page.rowsScroll.overflow and scrollH == rowsH, "si caben, se ven todas sin desplazar")
    page.rowsChild.SetHeight, page.rowsScroll.SetHeight = realSet, realScrollSet
    page.sheet.GetHeight, page.sheet.GetWidth = savedH, savedW
    log[#log+1] = string.format("     calculadora: %d px de filas", rowsH)
    ES:RenderCalculator()
  end
  -- Ratón sobre el icono de un cálculo o de un material: el tooltip del objeto
  do
    local savedLink, link = GameTooltip.SetHyperlink, nil
    GameTooltip.SetHyperlink = function(_, l) link = l end
    local s1 = page.saved[1]
    s1.iconHover._scripts.OnEnter(s1.iconHover)
    assert(s1.itemID and link == "item:" .. s1.itemID, "sin tooltip del objeto en el icono del cálculo: " .. tostring(link))
    link = nil
    local m1 = page.sheetRows[1]
    m1.iconHover._scripts.OnEnter(m1.iconHover)
    assert(link == "item:" .. m1.itemID, "sin tooltip del objeto en el icono del material")
    GameTooltip.SetHyperlink = savedLink
  end
  -- La fila del intermedio en la hoja: clic = cambiar cómo se consigue
  do
    local mr = page.madeRows and page.madeRows[1]
    assert(mr and mr._shown ~= false and mr.m and mr.m.itemID == BOLT, "falta la fila del Bolt en la hoja")
    mr._scripts.OnClick(mr)
    assert(Calc:Selected().via and Calc:Selected().via[BOLT] == "buy", "el clic en la fila no cambia a comprarlo hecho")
    mr = page.madeRows[1]
    mr._scripts.OnClick(mr)
    assert(not (Calc:Selected().via and Calc:Selected().via[BOLT]), "el segundo clic no vuelve a lo de antes")
  end
  -- "Añadir a la lista de compra" de la calculadora: suena y brilla la pestaña
  do
    local savedFlash, savedChar2, savedPrint2, flashed = ES.FlashTab, ES.charData, ES.Print, nil
    ES.FlashTab = function(_, key, sound) flashed = key == "shopping" and sound end
    ES.charData, ES.Print = { shopping = {} }, function() end
    page.addShopping._scripts.OnClick(page.addShopping)
    local added = #ES.Shopping.Lists() > 0
    ES.FlashTab, ES.charData, ES.Print = savedFlash, savedChar2, savedPrint2
    assert(not added or flashed, "la calculadora añade a la lista sin sonido ni brillo")
  end
  local silkRow
  for _, row in ipairs(page.sheetRows) do if row._shown and row.itemID == SILK then silkRow = row end end
  -- Tres casillas: oro, plata y cobre
  -- Precio como texto con su fuente; clic: una sola casilla para escribirlo
  local pf = silkRow and silkRow.price
  local function plain(t) return (tostring(t or ""):gsub("|T[^|]+|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
  -- (escrito a mano más arriba: 2s 70c)
  assert(pf and pf.copper == 270 and plain(pf.text._text):find("a mano"), "el precio se lee con su fuente: " .. plain(pf and pf.text._text))
  pf._scripts.OnClick(pf)
  assert(pf.box._shown ~= false and pf.box._text == "2s 70c", "al pulsar se abre la casilla con el precio: " .. tostring(pf.box._text))
  pf.box:SetText("1g 3s")
  pf.box._scripts.OnEditFocusLost(pf.box)
  assert(c.prices[SILK] == 10300, "1g 3s = 10300: " .. tostring(c.prices[SILK]))
  pf = silkRow.price
  assert(pf.copper == 10300 and plain(pf.text._text):find("a mano"), "se repinta a mano: " .. plain(pf.text._text))
  -- Escape: no cambia nada
  pf._scripts.OnClick(pf)
  pf.box:SetText("99g")
  pf.box._scripts.OnEscapePressed(pf.box)
  assert(c.prices[SILK] == 10300, "Escape cambió el precio")
  -- Vacía: vuelve al automático
  pf._scripts.OnClick(pf)
  pf.box:SetText("")
  pf.box._scripts.OnEditFocusLost(pf.box)
  assert(c.prices[SILK] == nil, "vacía vuelve al automático")
  -- "Vender en": un solo selector con un menú (AH 24/8/2 h, chat, vendedor)
  local function plainT(s) return (tostring(s or ""):gsub("|T[^|]+|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
  local function Choose(channel, hours)
    page.sellOn._scripts.OnClick(page.sellOn)
    assert(page.sellOnMenu._shown ~= false, "el selector no abre su menú")
    for _, b in ipairs(page.sellOnMenu.options) do
      if b.option.channel == channel and (not hours or b.option.hours == hours) then
        b._scripts.OnEnter(b)
        b._scripts.OnClick(b)
        return
      end
    end
    error("falta la opción " .. channel .. " " .. tostring(hours))
  end
  local function ProfitTooltip()
    local all = {}
    local savedAdd, savedDouble = GameTooltip.AddLine, GameTooltip.AddDoubleLine
    GameTooltip.AddLine = function(_, l) all[#all + 1] = plainT(l) end
    GameTooltip.AddDoubleLine = function(_, a, b) all[#all + 1] = plainT(a) .. " = " .. plainT(b) end
    page.profitLine._scripts.OnEnter(page.profitLine)
    GameTooltip.AddLine, GameTooltip.AddDoubleLine = savedAdd, savedDouble
    return table.concat(all, " | ")
  end
  assert(page.sellOnLine._shown ~= false and plainT(page.sellOn.text._text):find("24"), "por defecto, AH 24 h: " .. plainT(page.sellOn.text._text))
  Choose("ah", 8)
  assert(c.channel == "ah" and c.hours == 8, "elegir AH 8 h lo guarda en el cálculo: " .. tostring(c.hours))
  assert(page.cutLine._shown ~= false, "en la AH se ve la comisión")
  -- El depósito y lo que darían las otras formas de vender, en el tooltip del beneficio
  local tip = ProfitTooltip()
  assert(tip:find("Depósito") and tip:find("chat"), "el tooltip del beneficio no trae depósito y comparación: " .. tip)
  -- Por el chat: sin comisión ni depósito
  Choose("trade")
  local rt = Calc:Compute(c)
  assert(c.channel == "trade" and rt.cut == 0 and rt.deposit == 0, "por el chat: sin comisión ni depósito")
  assert(math.abs(rt.profit - (rt.revenue - rt.cost)) < 0.01, "beneficio por el chat = venta - materiales")
  assert(math.abs((rt.profitTrade - rt.profitAH) - rt.revenue * rt.cutRate) < 0.01, "la diferencia es la comisión")
  assert(page.cutLine._shown == false, "por el chat no se enseña la comisión")
  log[#log+1] = "     calculadora: vender en " .. plainT(page.sellOn.text._text) .. " · " .. ProfitTooltip():sub(1, 140)
  -- Al vendedor (Discord): su precio, sin comisión ni depósito
  Choose("vendor")
  local rv = Calc:Compute(c)
  assert(c.channel == "vendor" and rv.cut == 0 and rv.deposit == 0 and rv.sale == ES:VendorSellPrice(rv.outID),
    "al vendedor: su precio, sin comisión ni depósito")
  assert(rv.profitVendor and math.abs(rv.profit - rv.profitVendor) < 0.01, "beneficio al vendedor")
  assert(ProfitTooltip():find("vendedor"), "el tooltip del beneficio incluye al vendedor")
  Choose("ah", 24)
  assert(c.channel == "ah" and c.hours == 24, "vuelve a la AH 24 h")
  log[#log+1] = "     calculadora: " .. tostring(page.title._text) .. " · beneficio " .. tostring(page.profitLine.value._text)
  assert(page.auctionator == nil, "ya no hay botón de Auctionator")
  -- Escaneo nuevo: los precios a mano de lo que trae dejan paso al escaneo (en todos
  -- los cálculos guardados); lo que no trae se queda con el tuyo
  local NOT_SCANNED = 2589
  c.prices[SILK], c.prices[NOT_SCANNED] = 999, 777
  c.sale = 123456
  Calc:Compute(c) -- (sin hora guardada: cuentan como de ahora)
  assert(c.prices[SILK] == 999 and c.sale == 123456, "sin escaneo nuevo, el precio a mano se queda")
  ES.db.scans[ES:RealmKey()].time = time() + 60
  local rs = Calc:Compute(c)
  for _, row in ipairs(rs.rows) do
    if row.itemID == SILK then assert(row.source == "ah" and row.price == 200, "tras escanear, la seda del escaneo: " .. tostring(row.source)) end
  end
  assert(c.prices[SILK] == nil and c.prices[NOT_SCANNED] == 777, "solo se quita el precio a mano de lo escaneado")
  assert(c.sale == nil and rs.saleSource == "ah", "la venta a mano deja paso al escaneo")
  c.prices[NOT_SCANNED] = nil
  ES.db.scans[ES:RealmKey()].time = time() - 600
  ES:RenderCalculator()
  -- Buscar y añadir; borrar con la ✕
  page.search:SetText("silk")
  page.search._scripts.OnTextChanged(page.search)
  assert(page.results._shown and page.results.rows[1].result, "el buscador no encuentra 'silk'")
  page.results.rows[1]._scripts.OnClick(page.results.rows[1])
  assert(#Calc:List() == 3, "el buscador debería añadir un cálculo")
  page.saved[1].del._scripts.OnClick(page.saved[1].del)
  assert(#Calc:List() == 2, "la ✕ debería borrarlo")
  ES.IsRecipeKnown, ES.db.scans, ES.Standing, ES.db.calcs = savedKnown, savedScans, savedStanding, savedCalcs
  ES:SelectPage("home")
end)
step("materiales: o se fabrican o se compran, y la ✕ los compra hechos", function()
  local data = ES.Data.Leatherworking
  -- Nunca las dos cosas a la vez con un mismo material
  local opts = ES:PlanOptions("Leatherworking", 75, 125, nil)
  local plan = ES.Planner:Plan(data, opts)
  local crafted = {}
  for _, c in ipairs(plan.crafted) do crafted[c.itemID] = true end
  for _, it in ipairs(plan.shopping) do
    assert(not (crafted[it.itemID] and it.source == "ah"), "se fabrica y se compra a la vez: " .. it.itemID)
  end
  -- Con la ✕ (comprarlo) no se fabrica: un material que se pueda comprar en la AH
  -- (sin precio, fabricarlo es la única vía y se fabrica igual)
  local item
  for id in pairs(plan.ctx.via) do if plan.ctx.ladders[id] then item = id break end end
  if item then
    local o = ES:PlanOptions("Leatherworking", 75, 125, nil)
    o.via = { [item] = "buy" }
    local p = ES.Planner:Plan(data, o)
    for _, c in ipairs(p.crafted) do assert(c.itemID ~= item, "con la ✕ no debería fabricarlo") end
  end
  -- La fila de fabricar tiene la ✕; al pulsarla queda en "Recetas quitadas" y se recupera
  local page
  for _, pg in ipairs(ES.professionPages) do if pg.profKey == "Leatherworking" then page = pg end end
  page.view = "route"
  ES:CalculatePlan(page)
  local craftLine
  -- (la fila de fabricar un material: su ✕ lo compra hecho; no la de otro tipo de fila)
  for _, l in ipairs(page.lines) do
    if l.skipTip and l.onSkip and tostring(l.skipTip):find("No fabricarlo") then craftLine = l end
  end
  if craftLine then
    craftLine.onSkip()
    assert(ES.db.prof.Leatherworking.noCraft and next(ES.db.prof.Leatherworking.noCraft), "la ✕ no apuntó el material")
    local restore
    for _, l in ipairs(page.lines) do if l.title and l.title:find("Recetas quitadas") then restore = l end end
    assert(restore, "falta la fila para recuperar el material")
    restore.onClick()
    assert(not ES.db.prof.Leatherworking.noCraft, "no se recuperó el material")
    log[#log+1] = "     ✕ en fabricar: " .. craftLine.title
  else
    log[#log+1] = "     ✕ en fabricar: la ruta de prueba no fabrica materiales"
  end
end)
step("cada personaje tiene sus rutas", function()
  -- El hunter empieza una ruta y sale; el warrior (que se llama igual, en el mismo
  -- reino: en Forever pasa) no la ve; el hunter vuelve y la recupera
  local savedGUID, savedProf = UnitGUID, ES.db.prof -- los ajustes de las demás pruebas
  UnitGUID = function() return "Player-70-0000AAAA" end
  ES.LoadCharacterData()
  ES.db.prof.Leatherworking = ES.db.prof.Leatherworking or {}
  ES.db.prof.Leatherworking.lock = { from = 1, to = 2, started = 1, choice = {} }
  ES.db.prof.Leatherworking.target = 175
  ES.SaveCharacterData()
  assert(ES.db.prof == nil, "al salir no deberían quedar copias sueltas")
  UnitGUID = function() return "Player-70-0000BBBB" end -- mismo nombre (UnitName no cambia)
  ES.LoadCharacterData()
  assert(not (ES.db.prof.Leatherworking and ES.db.prof.Leatherworking.lock), "otro personaje con el mismo nombre ve la ruta del primero")
  ES.SaveCharacterData()
  UnitGUID = function() return "Player-70-0000AAAA" end
  ES.LoadCharacterData()
  assert(ES.db.prof.Leatherworking.lock and ES.db.prof.Leatherworking.target == 175, "al volver, el personaje no recupera su ruta")
  ES.db.prof.Leatherworking.lock, ES.db.prof.Leatherworking.target = nil, nil
  ES.lockedPlans = {}
  -- De vuelta al personaje de las demás pruebas
  ES.SaveCharacterData()
  UnitGUID = savedGUID
  ES.LoadCharacterData()
  ES.charData.prof, ES.db.prof = savedProf, savedProf
end)
step("al volver a abrir, sigue donde estabas", function()
  local mf = ES:GetMainFrame()
  ES:SelectPage("Leatherworking")
  mf.openPage = nil
  mf._scripts.OnShow(mf) -- cerrar y volver a abrir la ventana
  assert(ES.db.lastPage == "Leatherworking", "al abrir debería seguir en la profesión: " .. tostring(ES.db.lastPage))
  -- Otra sesión (otro personaje): se empieza en la portada, no en lo del otro
  ES.sessionPage = nil
  mf._scripts.OnShow(mf)
  assert(ES.db.lastPage == "home", "con otro personaje debería abrir en la portada: " .. tostring(ES.db.lastPage))
end)
-- Informe de la 0.60: "atascado en la Lista de compra, ni con /cj". Las páginas de
-- arriba (Lista de compra, Ganar dinero, Calculadora...) solo se dejan por las pestañas
-- laterales, que cuelgan fuera del marco: pegado al borde derecho (junto a la AH) se
-- quedaban fuera de la pantalla
step("pestañas laterales siempre a la vista (salir de la lista de compra)", function()
  local mf = ES:GetMainFrame()
  local tab = mf.tabs[1]
  local savedSW, savedSP = GetScreenWidth, ES.sessionPage
  local ok, err = pcall(function()
    -- El marco cuenta las pestañas al mantenerse dentro de la pantalla
    local insets
    local probe = CreateFrame("Frame")
    probe.SetClampRectInsets = function(_, l, r, t, b) insets = { l, r, t, b } end
    ES:CreateSideTabs(probe)
    assert(insets and insets[2] >= 55 and insets[1] == 0, "el marco no cuenta las pestañas de la derecha al ajustarse a la pantalla")
    -- En todas las páginas de arriba, las pestañas siguen ahí para cambiar de página
    for _, key in ipairs({ "shopping", "money", "inventory", "favor", "calc", "patterns", "home" }) do
      ES:SelectPage(key)
      for _, t in ipairs(mf.tabs) do assert(t._shown ~= false, key .. ": pestaña " .. t.key .. " escondida") end
      local back = nil
      for _, t in ipairs(mf.tabs) do if t.key ~= key then back = t end end
      back._scripts.OnClick(back)
      assert(ES.db.lastPage ~= key, key .. ": la pestaña " .. back.key .. " no sale de la página")
    end
    -- Abierta en la lista de compra con las pestañas fuera de la pantalla: vuelve al centro
    local point
    mf.ClearAllPoints = function() end
    mf.SetPoint = function(_, p) point = p end
    GetScreenWidth = function() return 1920 end
    tab.GetRight = function() return 1990 end
    ES:SelectPage("shopping")
    mf.openPage = nil
    mf._scripts.OnShow(mf) -- (/cj)
    assert(ES.db.lastPage == "shopping" and point == "CENTER", "con las pestañas fuera, /cj debería traer la ventana al centro")
    -- Junto a la AH (la grande ya abierta), igual
    point = nil
    ES:SetupShoppingMini(CreateFrame("Frame"))
    assert(point == "CENTER", "junto a la AH con las pestañas fuera: al centro")
    -- Con las pestañas a la vista, no se mueve
    point = nil
    tab.GetRight = function() return 1800 end
    mf._scripts.OnShow(mf)
    assert(point == nil, "con las pestañas a la vista no debería moverse")
    -- Una página guardada que ya no existe: la portada
    ES.sessionPage = "noexiste"
    mf._scripts.OnShow(mf)
    assert(ES.db.lastPage == "home", "página guardada inválida: debería abrir la portada: " .. tostring(ES.db.lastPage))
  end)
  GetScreenWidth, ES.sessionPage = savedSW, savedSP
  tab.GetRight, mf.ClearAllPoints, mf.SetPoint = nil, nil, nil
  ES:SelectPage("home")
  if not ok then error(err, 0) end
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
step("instructor: aprende los precios reales", function()
  -- Receta nueva de Forever sin precio conocido (trainer = true, sin fee): al abrir
  -- el instructor se lee lo que cobra y el nivel que pide, y manda sobre los datos
  local data = ES.Data.Alchemy
  ES.Planner.Annotate(data)
  local acid, mana = data.recipes[1249633], data.recipes[2331]
  local saved = { acid.fee, acid.train, acid.trainer }
  acid.fee, acid.train, acid.trainer = nil, nil, true
  ES.db.trainerFees = nil
  local ctx = { opts = {}, prices = {} }
  local cost, source = ES.Planner.LearnCost(ctx, acid)
  assert(cost == 0 and source == "trainer", "sin precio conocido debería ser instructor a 0 (\"?\")")
  -- Ventana del instructor de Alquimia: una cabecera, el ácido por nombre y la
  -- poción de maná por el objeto que fabrica
  local services = {
    { name = "Alchemy", kind = "header" },
    { name = acid.nameEN or acid.name, kind = "available", cost = 135, skill = 40 },
    { name = "Whatever", kind = "used", cost = 100, skill = 25, link = "|cffffffff|Hitem:2455::::::::|h[Minor Mana Potion]|h|r" },
  }
  GetNumTrainerServices = function() return #services end
  GetTrainerServiceInfo = function(i) return services[i].name, "", services[i].kind end
  GetTrainerServiceSkillLine = function() return ES:ProfLabel("Alchemy") end
  GetTrainerServiceCost = function(i) return services[i].cost end
  GetTrainerServiceSkillReq = function(i) return "Alchemy", services[i].skill, true end
  GetTrainerServiceItemLink = function(i) return services[i].link end
  UnitReaction = function() return 4 end -- neutral: sin descuento
  -- Al abrirlo se leen todas, aunque sus filtros oculten algunas (y se dejan como estaban)
  local filters = { available = 1, unavailable = nil, used = nil }
  local shownAtRead
  GetTrainerServiceTypeFilter = function(f) return filters[f] end
  -- (como Forever: solo true/false; con 1/0 da "Missing on/off parameter")
  SetTrainerServiceTypeFilter = function(f, v)
    if type(v) ~= "boolean" then error("Missing on/off parameter in SetTrainerServiceTypeFilter") end
    filters[f] = v and 1 or nil
  end
  local realCount = GetNumTrainerServices
  GetNumTrainerServices = function() shownAtRead = filters.unavailable and filters.used return realCount() end
  local changed = ES.Ledger:ReadAllTrainerServices()
  assert(shownAtRead, "al leer, los filtros del instructor deberían mostrarlo todo")
  assert(filters.available == 1 and not filters.unavailable and not filters.used, "los filtros deberían quedar como estaban")
  GetTrainerServiceTypeFilter, SetTrainerServiceTypeFilter, GetNumTrainerServices = nil, nil, realCount
  -- (2 precios, más las recetas de los datos que este instructor no tiene: ver abajo)
  assert(changed >= 2, "debería haber leído 2 recetas: " .. tostring(changed))
  local seen = ES.db.trainerFees[1249633]
  assert(seen and seen.cost == 135 and seen.skill == 40, "no guardó el precio del ácido")
  cost, source = ES.Planner.LearnCost(ctx, acid)
  assert(cost == 135 and source == "trainer", "no usa el precio visto: " .. tostring(cost))
  assert(ES.Planner.LearnSkill(acid, {}) == 40, "no usa el nivel visto")
  assert(ES.Planner.LearnCost(ctx, mana) == 100, "la poción de maná debería costar lo visto (100)")
  -- Una receta de instructor de los datos que el instructor no tiene (Forever la quitó:
  -- Green Iron Leggings) deja de salir en las rutas; si otro instructor la enseña, vuelve
  local gone
  for id, r in pairs(data.recipes) do
    if r.fee and not r.scroll and r.train and r.train >= 25 and r.train <= 40 and id ~= 2331 and id ~= 1249633 and (not gone or id < gone) then gone = id end
  end
  -- Solo visto el instructor de su rango: puede estar en el del rango siguiente (Forever
  -- subió Green Iron Leggings al de Experto). Sigue en las rutas, con ese instructor
  assert(ES.db.trainerMissing and ES.db.trainerMissing[gone] == "rank", "no marcó que el instructor de su rango no la tiene")
  assert(ES.Planner.LearnSkill(data.recipes[gone], {}), "la quitó sin ver el instructor del rango siguiente")
  -- Un instructor de más nivel tampoco la tiene: no se enseña, fuera de las rutas
  local savedServices = services
  services = { { name = "Alchemy", kind = "header" }, { name = acid.nameEN or acid.name, kind = "available", cost = 135, skill = 60 },
    { name = "Whatever", kind = "used", cost = 100, skill = 90, link = "|cffffffff|Hitem:2455::::::::|h[Minor Mana Potion]|h|r" } }
  GetTrainerServiceTypeFilter = function() return 1 end
  SetTrainerServiceTypeFilter = function() end
  ES.Ledger:ReadAllTrainerServices()
  GetTrainerServiceTypeFilter, SetTrainerServiceTypeFilter = nil, nil
  services = savedServices
  assert(ES.db.trainerMissing[gone] == "gone", "tampoco en el instructor de más nivel: debería quedar fuera")
  assert(ES.Planner.LearnSkill(data.recipes[gone], {}) == nil, "la ruta aún puede usar una receta que ningún instructor enseña")
  assert(not ES.db.trainerMissing[1249633] and not ES.db.trainerMissing[2331], "marcó como no enseñada una que sí tiene")
  -- (las de fuera del tramo que enseña este instructor, 25-40, pueden ser de otro: no se tocan)
  local high, lowID
  for id, r in pairs(data.recipes) do
    if r.fee and not r.scroll and r.train and r.train > 40 then high = id end
    if r.fee and not r.scroll and r.train and r.train < 25 then lowID = id end
  end
  assert(not ES.db.trainerMissing[high], "marcó una de más nivel que lo que enseña el instructor")
  assert(not lowID or not ES.db.trainerMissing[lowID], "marcó una de menos nivel que lo que enseña el instructor")
  -- Otro instructor sí la tiene: vuelve
  table.insert(services, { name = data.recipes[gone].nameEN or data.recipes[gone].name, kind = "available", cost = 50, skill = data.recipes[gone].train })
  GetTrainerServiceTypeFilter = function() return 1 end
  SetTrainerServiceTypeFilter = function() end
  ES.Ledger:ReadAllTrainerServices()
  GetTrainerServiceTypeFilter, SetTrainerServiceTypeFilter = nil, nil
  assert(not ES.db.trainerMissing[gone] and ES.Planner.LearnSkill(data.recipes[gone], {}), "vista en otro instructor, debería volver")
  table.remove(services)
  log[#log+1] = "     instructor: lo que no enseña sale de las rutas (" .. data.recipes[gone].name .. "); si otro la enseña, vuelve"
  ES.db.trainerMissing, ES.db.trainerListed = nil, nil
  -- Con reputación el instructor rebaja: el precio base es el de todos
  assert(ES.Ledger.BaseCost({ cost = 135, rep = 6 }) == 150, "precio base con Honorable")
  -- Ruta fijada: el precio real del instructor también la corrige (mismas recetas)
  local lw = ES.Data.Leatherworking
  local hideID, from -- una receta de instructor de pago de nivel bajo (en los datos)
  for id, r in pairs(lw.recipes) do
    if r.fee and r.fee > 200 and r.train and r.train >= 10 and r.train <= 50 and r.t[4] > r.train + 15 and (not hideID or id < hideID) then hideID, from = id, r.train end
  end
  local choice = {}
  for s = from, from + 9 do choice[s] = hideID end
  ES.db.prof.Leatherworking = ES.db.prof.Leatherworking or {}
  local lp = ES.db.prof.Leatherworking
  local savedLock = lp.lock
  lp.lock = { from = from, to = from + 10, choice = choice, via = {}, started = 12345 }
  ES.lockedPlans.Leatherworking = nil
  local savedKnown = ES.IsRecipeKnown
  ES.IsRecipeKnown = function() return false end
  local before = ES:LockedPlan("Leatherworking")
  local fee = lw.recipes[hideID].fee
  services = { { name = lw.recipes[hideID].nameEN or lw.recipes[hideID].name, kind = "available", cost = fee - 100, skill = from } }
  GetTrainerServiceSkillLine = function() return ES:ProfLabel("Leatherworking") end
  -- (sin repintar las páginas: la de Peletería tiene otro objetivo y soltaría esta ruta de prueba)
  local savedRefresh = ES.RefreshProfessionPages
  ES.RefreshProfessionPages = function() end
  ES.Ledger:ReadTrainer()
  ES.RefreshProfessionPages = savedRefresh
  local after = ES:LockedPlan("Leatherworking")
  assert(after ~= before and math.abs((before.fees - after.fees) - 100) < 1,
    string.format("la ruta fijada no usó el precio del instructor: %d -> %d (pasos %d, para en %s, fee %s)", before.fees, after.fees, #before.steps, tostring(before.stoppedAt), tostring(before.steps[1] and before.steps[1].fee)))
  assert(after.steps[1].id == hideID, "la ruta fijada debería seguir con las mismas recetas")
  log[#log+1] = string.format("     ruta fijada: instructor %d -> %d", before.fees, after.fees)
  lp.lock = savedLock
  ES.IsRecipeKnown = savedKnown
  ES.lockedPlans.Leatherworking = nil
  -- Instructor de Minería (no es una profesión del addon): "Smelt Gold" (155) fabrica
  -- Gold Bar como Transmute: Iron to Gold (225). Discord: la ruta la aprendía a 155
  local iron = data.recipes[11479]
  ES.db.trainerFees = {}
  services = { { name = "Mining", kind = "header" },
    { name = "Smelt Gold", kind = "available", cost = 500, skill = 155, link = "|cffffffff|Hitem:3577::::::::|h[Gold Bar]|h|r" } }
  GetTrainerServiceSkillLine = function() return "Mining" end
  ES.Ledger:ReadTrainer()
  assert(not ES.db.trainerFees[11479], "el instructor de minería apuntó Smelt Gold como Transmute: Iron to Gold")
  -- Lo que ya quedó guardado mal: nunca por debajo del nivel de los datos, y se limpia
  ES.db.trainerFees = { [11479] = { cost = 500, skill = 155, prof = "Alchemy" }, [1249633] = { cost = 135, skill = 40 } }
  assert(ES.Planner.LearnSkill(iron, {}) == 225, "un nivel leído menor que el de los datos no debería contar: " .. tostring(ES.Planner.LearnSkill(iron, {})))
  ES.db.trainerFeesChecked = nil
  ES.Ledger:CleanTrainerFees()
  assert(not ES.db.trainerFees[11479] and ES.db.trainerFees[1249633], "la limpieza debería quitar solo la lectura equivocada")
  ES.db.trainerFees[11479] = { cost = 500, skill = 155 }
  ES.Ledger:CleanTrainerFees()
  assert(ES.db.trainerFees[11479], "la limpieza se hace una sola vez")
  log[#log+1] = "     instructor de minería: Smelt Gold ya no se toma por Transmute: Iron to Gold (225, no 155)"
  -- Receta que se aprende sola (Linen Bag, basic) y el instructor lista "a 5 por 1s" a
  -- quien no tiene Sastrería: sigue a nivel 1 y gratis (la ruta fijada 1-150 que la
  -- usaba desde 1 se quedaba vacía y el asistente sin pasos; captura del 2026-11-17)
  local bag = ES.Data.Tailoring.recipes[3755]
  ES.Planner.Annotate(ES.Data.Tailoring)
  assert(bag and bag.basic, "Linen Bag debería ser basic en los datos")
  ES.db.trainerFees = { [3755] = { cost = 100, skill = 5, prof = "Tailoring" } }
  assert(ES.Planner.LearnSkill(bag, {}) == 1, "una receta basic no debería tomar el nivel del instructor: " .. tostring(ES.Planner.LearnSkill(bag, {})))
  assert(not ES.Planner.Fee(bag), "una receta basic no debería costar lo que lista el instructor")
  acid.fee, acid.train, acid.trainer = saved[1], saved[2], saved[3]
  ES.db.trainerFees = nil
  GetNumTrainerServices, GetTrainerServiceInfo, GetTrainerServiceSkillLine, GetTrainerServiceCost = nil, nil, nil, nil
  GetTrainerServiceSkillReq, GetTrainerServiceItemLink, UnitReaction = nil, nil, nil
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
-- Los métodos de marcos que el addon ha llamado deben existir en el cliente: el
-- simulado acepta cualquiera, y así pasó ag:SetLoopType (no existe: es SetLooping),
-- que en el juego daba error cada vez que brillaba una pestaña. Si sale uno nuevo,
-- compruébalo en la API del juego (warcraft.wiki.gg, Widget API) antes de añadirlo
step("dinero: negativos, NaN e infinito no dan error", function()
  assert(ES.Money(nil):find("—", 1, true), "sin cantidad, raya")
  assert(ES.Money(0 / 0):find("—", 1, true), "NaN, raya")
  assert(ES.Money(math.huge):find("—", 1, true), "infinito, raya")
  local neg = ES.Money(-12345)
  assert(neg:sub(1, 1) == "-" and neg:find("1"), "negativo con el signo delante: " .. neg)
  assert(not ES.Money(12345):find("^%-"), "positivo sin signo")
end)
step("Merchant's Favor: con qué llenar cada caja y cuál da el punto más barato", function()
  local EXPERT_FABRICS, APPRENTICE_ORE, BOLT, HIDE, COPPER = 248708, 248683, 4339, 4236, 2770
  local savedScans, savedCount, savedSkill = ES.db.scans, ES.ItemCount, ES.GetProfessionSkill
  ES.GetProfessionSkill = function() return nil end -- (sin profesiones: solo comprar)
  -- Expert Fabrics (30 Favor): caja 20g; 8 Bolt of Mageweave a 25s (2g) o 2 Cured Heavy Hide a 3g (6g)
  -- Apprentice Ore (5 Favor): caja 50s; 20 Copper Ore a 10c (2s)
  ES.db.scans = { [ES:RealmKey()] = { time = time() - 120, items = {
    [EXPERT_FABRICS] = { minUnit = 200000, quantity = 1, listings = 1 },
    [APPRENTICE_ORE] = { minUnit = 5000, quantity = 3, listings = 3 },
    [BOLT] = { minUnit = 2500, quantity = 50, listings = 5 },
    [HIDE] = { minUnit = 30000, quantity = 10, listings = 2 },
    [COPPER] = { minUnit = 10, quantity = 200, listings = 10 },
  } } }
  local bags = {}
  ES.ItemCount = function(_, id) return bags[id] or 0 end
  ES.Favor.Clear()
  local function Find(list, id) for _, o in ipairs(list) do if o.crate.id == id then return o end end end
  local list = ES.Favor:Options()
  local ef, ao = Find(list, EXPERT_FABRICS), Find(list, APPRENTICE_ORE)
  assert(ef and ef.fill and ef.fill.itemID == BOLT and math.abs(ef.fill.cost - 20000) < 1, "Expert Fabrics: los Bolt (2g), no las pieles: " .. tostring(ef and ef.fill and ef.fill.itemID))
  assert(math.abs(ef.perFavor - 220000 / 30) < 1, "Expert Fabrics: (20g + 2g) / 30 por punto: " .. tostring(ef.perFavor))
  assert(ao and math.abs(ao.perFavor - (5000 + 200) / 5) < 1, "Apprentice Ore: (50s + 2s) / 5: " .. tostring(ao and ao.perFavor))
  assert(list[1].crate.id == APPRENTICE_ORE, "lo más barato por punto, primero: " .. tostring(list[1].crate.id))
  -- Una caja tuya: la caja no cuesta; si ya llevas un paquete entero, se usa ese
  bags[EXPERT_FABRICS], bags[HIDE] = 1, 2
  ef = Find(ES.Favor:Options(), EXPERT_FABRICS)
  assert(ef.have == 1 and ef.crateCost == 0 and ef.fill.itemID == BOLT, "las pieles que llevas cuestan 6g frente a 2g: no compensa")
  bags[HIDE], bags[BOLT] = nil, 8
  ef = Find(ES.Favor:Options(), EXPERT_FABRICS)
  assert(ef.haveFill, "llevas los 8 Bolt: ya tienes el paquete")
  -- La pestaña: tus cajas arriba, luego las de la AH; clic = a la lista de compra
  ES:GetMainFrame()
  ES:SelectPage("favor")
  local page = ES.favorPage
  ES:RenderFavor()
  local sections, mineRow = {}, nil
  for _, row in ipairs(page.rows) do
    if row._shown ~= false and row.section and row.section._text and row.section._text ~= "" then sections[#sections + 1] = tostring(row.section._text) end
    if row._shown ~= false and row.item == EXPERT_FABRICS then mineRow = row end
  end
  assert(#sections == 2 and sections[1]:find("Tus cajas") and sections[2]:find("AH"), "secciones: " .. table.concat(sections, " | "))
  assert(mineRow and tostring(mineRow.sub._text):find("ya lo tienes"), "tu caja dice que ya tienes el paquete: " .. tostring(mineRow and mineRow.sub._text))
  local added
  local savedAdd = ES.AddToShopping
  ES.AddToShopping = function(_, kind, title, items) added = { kind = kind, items = items } end
  bags[BOLT] = nil
  ES:RenderFavor()
  for _, row in ipairs(page.rows) do
    if row._shown ~= false and row.item == APPRENTICE_ORE and row.onClick then row.onClick() end
  end
  ES.AddToShopping = savedAdd
  assert(added and added.kind == "favor" and added.items[1].itemID == APPRENTICE_ORE and added.items[2].itemID == COPPER,
    "clic en una caja de la AH: la caja y su paquete a la lista de compra")
  if mineRow.tooltip then mineRow.tooltip(mineRow) end -- (sin errores)
  ES.db.scans, ES.ItemCount, ES.GetProfessionSkill = savedScans, savedCount, savedSkill
  ES.Favor.Clear()
  ES:SelectPage("home")
  log[#log+1] = string.format("     Expert Fabrics: 8 Bolt; Apprentice Ore, %s/punto, el más barato", ES.Money(math.floor(ao.perFavor)))
end)
step("yendo por el mundo: los avisos de objetos y bolsas no hacen trabajar al addon", function()
  -- Con la AH y la profesión cerradas, GET_ITEM_INFO_RECEIVED y BAG_UPDATE_DELAYED (sin
  -- parar yendo por el mundo) no programan repintados de esas ventanas
  local savedTimer, savedAH, savedSellRefresh, savedCraftRefresh = C_Timer.After, ES.IsAuctionHouseOpen, ES.AuctionSell.Refresh, ES.CraftWindow.Refresh
  local savedPF, savedTSF = ProfessionsFrame, TradeSkillFrame
  local sells, crafts = 0, 0
  C_Timer.After = function(_, fn) fn() end
  ES.IsAuctionHouseOpen = function() return false end
  ES.AuctionSell.Refresh = function() sells = sells + 1 end
  ES.CraftWindow.Refresh = function() crafts = crafts + 1 end
  ProfessionsFrame, TradeSkillFrame = nil, nil
  for _ = 1, 30 do FireEvent("GET_ITEM_INFO_RECEIVED", 2589, true) FireEvent("BAG_UPDATE_DELAYED") end
  assert(sells == 0, "con la AH cerrada, la ventana de vender se repintó " .. sells .. " veces")
  assert(crafts == 0, "sin profesión abierta, la ventana de la profesión se repintó " .. crafts .. " veces")
  C_Timer.After, ES.IsAuctionHouseOpen, ES.AuctionSell.Refresh, ES.CraftWindow.Refresh = savedTimer, savedAH, savedSellRefresh, savedCraftRefresh
  ProfessionsFrame, TradeSkillFrame = savedPF, savedTSF
  log[#log+1] = "     60 avisos de objetos y bolsas con todo cerrado: 0 repintados"
end)
step("historial de mercado: en segundo plano, sin congelar el juego", function()
  -- En el juego (con debugprofilestop) el índice se construye repartido entre
  -- fotogramas: mientras, se usa el anterior; al acabar, lo que esperaba se hace una vez
  local savedDPS, savedTimer, savedRefresh = debugprofilestop, C_Timer.After, ES.RefreshAllViews
  local queue, clock = {}, 0
  debugprofilestop = function() clock = clock + 1 return clock end -- (1 ms por consulta)
  C_Timer.After = function(_, fn) queue[#queue + 1] = fn end
  local refreshes = 0
  ES.RefreshAllViews = function() refreshes = refreshes + 1 end
  local old = ES.Market:Index()
  -- Un escaneo nuevo (otra entrada en el historial): el índice cambia
  local key = ES:RealmKey()
  ES.db.history = ES.db.history or {}
  local savedTrack = ES.db.track
  ES.db.track = { [key] = { time = time(), sigs = {} } }
  for i = 1, 3000 do ES.db.track[key].sigs[i .. ":1:100:x"] = "1" end
  local served = ES.Market:Index()
  assert(ES.Market.Building(), "con un historial nuevo, el índice se construye en segundo plano")
  assert(served == old or served.empty, "mientras, se usa el anterior (o uno vacío), sin esperar")
  local ran = false
  ES.Market.WhenReady(function() ran = true end)
  local frames = 0
  while #queue > 0 and frames < 10000 do
    local fn = table.remove(queue, 1)
    fn()
    frames = frames + 1
  end
  assert(not ES.Market.Building() and ran, "al acabar, lo que esperaba al índice se hace")
  assert(frames > 1, "repartido en varios fotogramas: " .. frames)
  assert(refreshes == 0, "con algo esperando, no se repinta otra vez")
  local new = ES.Market:Index()
  assert(new ~= old and not new.empty, "y después se usa el nuevo")
  debugprofilestop, C_Timer.After, ES.RefreshAllViews = savedDPS, savedTimer, savedRefresh
  ES.db.track = savedTrack
  ES.Market:Index() -- (de nuevo, sin debugprofilestop: de golpe)
  log[#log+1] = string.format("     historial nuevo: %d fotogramas en segundo plano, sin esperar", frames)
end)
step("un punto de arma o defensa no hace trabajar al addon", function()
  -- SKILL_LINES_CHANGED llega con cada punto de arma o defensa (en combate, sin parar):
  -- sin cambio en tus profesiones, ni se mira el tope ni se refrescan las rutas
  local savedSkill, savedAfter, savedStop, savedTimer = ES.GetProfessionSkill, ES.RefreshAfterSkill, ES.CheckCraftStop, C_Timer.After
  local level, refreshed, checked = 100, 0, 0
  ES.GetProfessionSkill = function(_, line) if line == ES.Data.Leatherworking.skillLine then return level, 150 end end
  ES.RefreshAfterSkill = function() refreshed = refreshed + 1 end
  ES.CheckCraftStop = function() checked = checked + 1 end
  C_Timer.After = function(_, fn) fn() end
  FireEvent("SKILL_LINES_CHANGED") -- (la primera vez, de referencia)
  refreshed, checked = 0, 0
  for _ = 1, 20 do FireEvent("SKILL_LINES_CHANGED") FireEvent("CHAT_MSG_SKILL") end
  assert(refreshed == 0 and checked == 0, string.format("sin cambio en las profesiones trabajó: %d refrescos, %d comprobaciones", refreshed, checked))
  level = 101
  FireEvent("CHAT_MSG_SKILL")
  assert(refreshed == 1 and checked == 1, "al subir Peletería no se refrescó")
  ES.GetProfessionSkill, ES.RefreshAfterSkill, ES.CheckCraftStop, C_Timer.After = savedSkill, savedAfter, savedStop, savedTimer
  log[#log+1] = "     40 puntos de arma/defensa: 0 trabajo; 1 punto de Peletería: se refresca"
end)
step("opciones: engranaje de la cabecera y categorías", function()
  local f = CraftersJournalMainFrame
  assert(f and f.optionsButton, "la cabecera tiene el engranaje de opciones")
  -- Nada en las opciones del juego: solo la ventana del addon
  for i, src in ipairs(SOURCES) do
    if not SOURCE_NAMES[i]:find("^Libs") then
      assert(not src:find("RegisterAddOnCategory", 1, true) and not src:find("InterfaceOptions_AddCategory", 1, true),
        SOURCE_NAMES[i] .. " registra opciones en las del juego")
    end
  end
  -- (el mock dice siempre que está visible: aquí, lo que diga Show/Hide)
  local w = ES:OptionsWindow()
  w._shown = false
  w.IsShown = function(self) return self._shown == true end
  f.optionsButton._scripts.OnClick(f.optionsButton)
  assert(w._shown == true, "el engranaje abre la ventana de opciones")
  w._scripts.OnShow(w)
  assert(w.selected == "general" and w.pages.general._shown == true and w.heading._text == ES.L["General"],
    "se abre en General: " .. tostring(w.selected))
  -- Abajo de las categorías: la versión y la invitación al Discord
  local savedVer = ES.AddonVersion
  ES.AddonVersion = function() return "9.8.7" end
  w._scripts.OnShow(w)
  ES.AddonVersion = savedVer
  assert(tostring(w.version._text):find("9.8.7", 1, true), "la versión, abajo de las categorías: " .. tostring(w.version._text))
  assert(w.discordButton.title._text == ES.L["Únete a nuestro Discord"], "la invitación al Discord: " .. tostring(w.discordButton.title._text))
  w.discordButton._scripts.OnClick(w.discordButton)
  local dlg = CraftersJournalReportDialog
  dlg._scripts.OnShow(dlg)
  assert(dlg.kind == "join" and dlg.title._text == ES.L["Únete a nuestro Discord"] and dlg.box._text == ES.DISCORD_URL,
    "el botón del Discord abre el enlace para copiarlo: " .. tostring(dlg.title._text))
  ES:ShowReportDialog()
  dlg._scripts.OnShow(dlg)
  assert(dlg.title._text == ES.L["Informar de un error"], "Informar sigue abriendo lo de los errores")
  dlg:Hide()
  local tip, savedAddL = {}, GameTooltip.AddLine
  GameTooltip.AddLine = function(_, t) tip[#tip + 1] = tostring(t) end
  f.optionsButton._scripts.OnEnter(f.optionsButton)
  GameTooltip.AddLine = savedAddL
  assert(tip[1] == ES.L["Opciones"], "el tooltip del engranaje: " .. table.concat(tip, " | "))
  -- Cada opción, en una categoría que existe; ninguna categoría vacía; todas en la ventana
  -- (las de página propia, como Pestañas, no tienen casillas: su página, sí)
  local count = {}
  for _, c in ipairs(ES.OPTION_CATEGORIES) do
    if c.build then
      assert(w.pages[c.key] and w.pages[c.key].Refresh, "categoría sin página: " .. c.key)
    else
      count[c.key] = 0
    end
  end
  for _, o in ipairs(ES.OPTIONS) do
    assert(count[o.cat], "opción sin categoría: " .. o.key)
    count[o.cat] = count[o.cat] + 1
  end
  for k, n in pairs(count) do assert(n > 0, "categoría sin opciones: " .. k) end
  assert(#w.checks == #ES.OPTIONS and #w.categoryButtons == #ES.OPTION_CATEGORIES, "todas las opciones y categorías en la ventana")
  -- Cambiar de categoría: se ve solo la suya, con su nombre arriba y marcada a la izquierda
  local ab
  for _, b in ipairs(w.categoryButtons) do if b.key == "auction" then ab = b end end
  ab._scripts.OnClick(ab)
  assert(w.selected == "auction" and w.pages.auction._shown == true and w.pages.general._shown == false,
    "al pulsar Casa de Subastas se ve su página")
  assert(w.heading._text == ES.L["Casa de Subastas"], "el título de la derecha: " .. tostring(w.heading._text))
  for _, b in ipairs(w.categoryButtons) do
    assert(b.sel._shown == (b.key == "auction"), "solo la categoría elegida sale marcada: " .. b.key)
  end
  -- Su casilla funciona como antes (mismo sitio en ES.db)
  local savedPC = ES.db.noPostConfirm
  local pc
  for _, cb in ipairs(w.pages.auction.checks) do if cb.option.key == "noPostConfirm" then pc = cb end end
  assert(pc and pc:GetChecked() == not savedPC, "la casilla de confirmar, en Casa de Subastas y con su valor")
  pc:SetChecked(false)
  pc._scripts.OnClick(pc)
  assert(ES.db.noPostConfirm == true, "desmarcada, se guarda como antes")
  pc:SetChecked(true)
  pc._scripts.OnClick(pc)
  assert(ES.db.noPostConfirm == nil, "marcada otra vez, se quita")
  ES.db.noPostConfirm = savedPC
  -- Ganar dinero: los umbrales de TSM son deslizadores por escalones
  ES:OpenOptions("earn")
  local sold, rate, tsmCb
  for _, cb in ipairs(w.pages.earn.checks) do
    if cb.option.key == "tsmMinSold" then sold = cb elseif cb.option.key == "tsmMinRate" then rate = cb
    elseif cb.option.key == "noTsmDemand" then tsmCb = cb end
  end
  assert(sold and sold.isSlider and rate and rate.isSlider, "los umbrales de TSM, en Ganar dinero y como deslizadores")
  assert(sold.value._text == string.format(ES.L["%s al día"], "1") and rate.value._text == "0,15",
    "por defecto: 1 al día y tasa 0,15: " .. tostring(sold.value._text) .. " / " .. tostring(rate.value._text))
  assert(sold.Set(1) and ES.db.tsmMinSold == 0 and ES.Market.TSMMinSold() == 0, "escalón 1: 0 (no cuenta)")
  assert(sold.value._text == ES.L["No cuenta"], "con 0 dice que no cuenta: " .. tostring(sold.value._text))
  assert(sold.Set(6) and ES.db.tsmMinSold == 5, "escalón 6: 5 al día")
  assert(sold.Set(4) and ES.db.tsmMinSold == nil, "el de por defecto no se guarda")
  assert(not sold.Set(4), "el mismo escalón no recalcula")
  -- Sin la demanda de TSM, en gris (y se repinta la página al quitarla)
  tsmCb:SetChecked(false)
  tsmCb._scripts.OnClick(tsmCb)
  assert(ES.db.noTsmDemand == true and not sold.option.enabled(), "sin TSM, los umbrales no cuentan")
  tsmCb:SetChecked(true)
  tsmCb._scripts.OnClick(tsmCb)
  assert(ES.db.noTsmDemand == nil and sold.option.enabled(), "con TSM otra vez, se pueden tocar")
  -- /cj opciones abre la ventana (en la última categoría); OpenOptions con categoría, en esa
  ES:OpenOptions("auction")
  w:Hide()
  SlashCmdList.CRAFTERSJOURNAL("opciones")
  assert(w._shown == true and w.selected == "auction", "/cj opciones abre la ventana")
  ES:OpenOptions(ES:OptionCategory("noVendorWindow"))
  assert(w.selected == "vendor" and w.pages.vendor._shown == true and w.pages.auction._shown == false,
    "se abre en la categoría pedida: " .. tostring(w.selected))
  -- Esquina para escalar, como la ventana principal; su escala va aparte
  assert(w.resize and w.resize ~= f.resize, "la ventana de opciones tiene su esquina para escalar")
  local savedFS, savedOS = ES.db.frameScale, ES.db.optionsScale
  ES.db.frameScale = 1.3
  w.resize._scripts.OnDoubleClick(w.resize)
  assert(ES.db.optionsScale == 1 and ES.db.frameScale == 1.3, "doble clic: tamaño normal, solo el de las opciones")
  ES.db.frameScale, ES.db.optionsScale = savedFS, savedOS
  -- El engranaje otra vez: se cierra
  f.optionsButton._scripts.OnClick(f.optionsButton)
  assert(w._shown == false, "el engranaje cierra la ventana si está abierta")
  w.IsShown = nil
  log[#log+1] = "     opciones: engranaje, " .. #ES.OPTION_CATEGORIES .. " categorías, " .. #ES.OPTIONS .. " casillas"
end)
-- El banner del asistente por sí solo (con unas filas de ruta de mentira): nivel,
-- textos cortos, ◀ ▶ y cerrar. Antes de "métodos de marcos": así también se comprueban los suyos
step("asistente: banner, nivel y flechas", function()
  local A = ES.Assistant
  local saved = { ES.RouteLock, ES.RouteLines, ES.GetProfessionSkill, ES.db.prof }
  local lock = { from = 200, to = 230, started = 12345 }
  local clicked = 0
  ES.db.prof = { Tailoring = {} }
  ES.RouteLock = function(_, k) return k == "Tailoring" and lock or nil end
  ES.RouteLines = function() return {
    { level = "200–226", title = "Hecho", done = true },
    { level = "226–230", title = "Brightcloth Robe", bannerTitle = "Fabrica 4× Brightcloth Robe",
      sub = "4 fabricaciones · 2g/u · 2ª: otra", bannerSub = "4 fabricaciones · ~4 min", current = true,
      icon = 134400, onClick = function() clicked = clicked + 1 end },
    { level = "230", title = "Entrenar Artesano", go = function() return nil end, icon = 134400 },
    { total = true, title = "Total" },
  } end
  ES.GetProfessionSkill = function() return 227, 230 end
  local ok, err = pcall(function()
    A.Update()
    local f, st = A.Frame(), A.State()
    assert(f._shown, "con una ruta empezada el asistente debería verse")
    assert(tostring(f.banner.level._text) == "226–230", "falta el nivel del paso: " .. tostring(f.banner.level._text))
    -- El nivel, como en la ventana: letra normal y en una línea, siempre (columna de 70)
    do
      local fs = f.banner.level
      local savedFonts = { GameFontNormal }
      GameFontNormal = GameFontNormal or { "normal" }
      local font
      local savedFont = fs.SetFontObject
      fs.SetFontObject = function(self, o) font = o end
      A.FitLevel(fs, "104–130")
      assert(font == GameFontNormal and fs._text == "104–130", "con la letra normal y en una línea: " .. tostring(fs._text))
      fs.SetFontObject = savedFont
      GameFontNormal = savedFonts[1]
      A.Update()
    end
    assert(f.banner.title._text == "Fabrica 4× Brightcloth Robe", "título: " .. tostring(f.banner.title._text))
    -- (sin precios; el "~" sale con su icono, ES.APPROX)
    assert(f.banner.sub._text == "4 fabricaciones · " .. ES.APPROX .. "4 min", "el asistente no debería enseñar precios: " .. tostring(f.banner.sub._text))
    assert(#st.steps == 3 and st.index == 2, "pasos del asistente (sin el total)")
    -- Etiqueta BETA abajo a la izquierda (arriba se montaba con la flecha GPS), junto a la
    -- pestaña de Saltar; su tooltip manda al canal de bugs del Discord
    assert(f.beta, "falta la etiqueta BETA")
    local bp = f.beta._points and f.beta._points[1]
    if bp then assert(bp[2] == f.skipTab, "la etiqueta BETA va junto a la pestaña de Saltar, abajo") end
    local tipLines = {}
    local savedAdd = GameTooltip.AddLine
    GameTooltip.AddLine = function(_, t) tipLines[#tipLines + 1] = tostring(t) end
    f.beta._scripts.OnEnter(f.beta)
    GameTooltip.AddLine = savedAdd
    local tip = table.concat(tipLines, " ")
    assert(tip:find("bugs") and tip:find("Informar de un error") and tip:find("/cj opciones"),
      "el tooltip de BETA: canal de bugs (enlace en Informar de un error) y cómo desactivarlo: " .. tip)
    -- Franja de color por tipo de paso
    assert(A.StepKind({ stepRecipe = 1 }) == "craft" and A.StepKind({ buyRow = "ah" }) == "buy"
      and A.StepKind({ go = function() end, rankCap = 150 }) == "npc" and A.StepKind({ done = true }) == "done"
      and A.StepKind(nil, true) == "completed", "tipos de paso del asistente")
    assert(f.arrows.prev and f.arrows.next and not f.strip and not f.arrows.bar, "solo ◀ ▶ en la pestaña, sin barra")
    assert(f.arrows.count._text == "2/3", "entre las flechas, el paso de cuántos: " .. tostring(f.arrows.count._text))
    f.banner._scripts.OnClick(f.banner, "LeftButton")
    assert(clicked == 1, "el clic del banner no hizo lo de la fila")
    f.arrows.next._scripts.OnClick(f.arrows.next)
    assert(st.peek == 3 and f.banner.level._text:find("230") and f.banner.onClick ~= nil and f.banner.go == nil,
      "ojeando el paso siguiente no se ve su nivel o deja hacer lo del paso")
    assert(tostring(f.arrows.count._text):find("3/3"), "ojeando, el contador debería decir el paso que miras")
    f.arrows.prev._scripts.OnClick(f.arrows.prev)
    assert(st.peek == nil and f.banner.title._text == "Fabrica 4× Brightcloth Robe", "no vuelve al paso actual")
    -- Acabar un paso (el actual pasa al siguiente): brillo y ✓
    local savedLines = ES.RouteLines
    ES.RouteLines = function() local l = savedLines() l[2].current, l[2].done, l[3].current = nil, true, true return l end
    -- (con la espera de verdad: el ✓ sale sobre el paso hecho, que sigue a la vista, y
    -- el siguiente entra al acabar; antes caía encima del nuevo, "Compra 10× Gold Bar ✓")
    local savedHold, savedAfter, later = A.CELEBRATE_HOLD, C_Timer.After, nil
    A.CELEBRATE_HOLD = 1
    C_Timer.After = function(_, fn) later = fn end
    local before = f.banner.title._text
    A.Update()
    assert(st.index == 3 and st.celebrated, "al acabar un paso debería celebrarse")
    assert(f.banner.title._text == before and later, "mientras se celebra, se ve el paso hecho")
    assert(f.banner.doneFrame._shown ~= false, "mientras se celebra, el ✓ se ve")
    A.Update() -- (lo que llegue entretanto espera)
    assert(f.banner.title._text == before, "lo que llega durante la celebración espera")
    -- Un clic mientras tanto no vuelve a hacer el paso hecho: solo enseña el siguiente
    local did = false
    local savedClick = f.banner.onClick
    f.banner.onClick = function() did = true end
    f.banner._scripts.OnClick(f.banner, "LeftButton")
    assert(not did, "un clic durante la celebración no repite el paso hecho")
    assert(f.banner.title._text ~= before and st.hold == nil, "el clic enseña el paso siguiente")
    -- (Discord: el ✓ se quedaba sobre el paso siguiente, aún por hacer)
    assert(f.banner.doneFrame._shown == false, "acabada la celebración, el ✓ no se queda")
    f.banner.doneFrame:Show() -- (como si la animación se hubiera cortado a medias)
    A.Update()
    assert(f.banner.doneFrame._shown == false, "al repintar, un ✓ que se quedó se quita")
    -- Dos celebraciones seguidas (comprar dos materiales de golpe: dos pasos hechos) y la
    -- animación sin avisar de que acabó: al repintar fuera de la celebración, sin ✓
    A.Celebrate()
    A.Celebrate()
    assert(f.banner.doneFrame._shown ~= false, "celebrando, el ✓ se ve")
    A.Update()
    assert(f.banner.doneFrame._shown == false, "tras dos celebraciones seguidas, el ✓ no se queda")
    if f.banner.onClick == nil then f.banner.onClick = savedClick end
    later() -- (el temporizador ya no hace nada)
    assert(f.banner.title._text ~= before, "al acabar, el paso siguiente")
    A.CELEBRATE_HOLD, C_Timer.After = savedHold, savedAfter
    ES.RouteLines = savedLines
    A.Update()
    assert(not st.celebrated, "volver a un paso anterior no se celebra")
    -- Aparece una fila de compra (solo aviso) delante del paso: no es avanzar
    ES.RouteLines = function()
      local l = savedLines()
      table.insert(l, 2, { level = "226", title = "Compra 2× X", buyRow = "ah", icon = 134400, buyItems = {} })
      return l
    end
    A.Update()
    assert(not st.celebrated and st.line.title == "Brightcloth Robe", "una fila de compra delante no debería contar como paso hecho")
    ES.RouteLines = savedLines
    A.Update()
    f.close._scripts.OnClick(f.close)
    assert(not f._shown and ES.db.prof.Tailoring.assistantHidden == lock.started, "la X no lo cierra para esta ruta")
    A.Update()
    assert(not f._shown, "cerrado para la ruta, no debería volver a salir")
    lock.started = 99999 -- otra ruta: vuelve a salir
    A.Update()
    assert(f._shown, "con otra ruta debería volver a salir")
    -- Siempre activo (ya no hay opción para activarlo)
    ES.db.assistant.enabled = nil
    A.Update()
    assert(f._shown and A.Enabled(), "el asistente debería estar activo sin opción")
    -- Opción "no sacarlo solo": sin abrirlo tú (botón o /cj mini), no sigue ninguna ruta
    ES.db.assistant = ES.db.assistant or {}
    ES.db.assistant.noAuto = true
    assert(A.Profession() == nil, "con la opción desactivada no debería salir solo")
    ES.db.prof.Tailoring.assistantPicked = 100000
    assert(A.Profession() == "Tailoring", "abierto por ti, sí")
    ES.db.assistant.noAuto, ES.db.prof.Tailoring.assistantPicked = nil, nil
    ES.db.assistant.stepsAlways = true
    A.Update()
    assert(f.tab._shown, "con Siempre visibles, la pestaña debería verse")
    ES.db.assistant.stepsAlways = nil
    -- Por defecto se despliega al pasar el ratón y se pliega al salir (tras medio segundo)
    local savedOver = A.MouseOver
    A.MouseOver = function(region) return region == f end
    f.tab:Hide() f.tab.open = 0
    A.SlideTab(1)
    assert(f.tab._shown and f.tab.open == 1, "al pasar el ratón la pestaña debería desplegarse")
    A.MouseOver = function() return false end
    A.SlideTab(0.2)
    assert(f.tab.open == 1, "no debería plegarse nada más salir (espera un poco)")
    A.SlideTab(0.4) A.SlideTab(1)
    assert(f.tab.open == 0 and f.tab._shown == false, "al salir debería plegarse")
    A.MouseOver = savedOver
    -- La detección: por el rectángulo en pantalla, con la zona de abajo (la pestaña)
    local rect = { IsVisible = function() return true end, GetLeft = function() return 100 end,
      GetRight = function() return 300 end, GetTop = function() return 500 end, GetBottom = function() return 400 end,
      GetEffectiveScale = function() return 1 end }
    local savedCursor, cx, cy = GetCursorPosition, 0, 0
    GetCursorPosition = function() return cx, cy end
    cx, cy = 200, 450
    assert(A.MouseOver(rect, 0), "ratón dentro del asistente")
    cx, cy = 200, 380
    assert(not A.MouseOver(rect, 0) and A.MouseOver(rect, 40), "ratón en la zona de la pestaña, debajo")
    cx, cy = 50, 450
    assert(not A.MouseOver(rect, 40), "ratón fuera")
    GetCursorPosition = savedCursor
    local opts = {}
    for _, o in ipairs(ES.OPTIONS) do if o.cat == "assistant" then opts[o.key] = true end end
    assert(opts.assistantArrow and opts.assistantStepsAlways,
      "faltan las opciones de la flecha y los controles siempre visibles")
    assert(not opts.assistantMinimapPin, "la opción del minimapa se quitó: el destino sale solo si nadie más pinta el camino")
    assert(not (opts.assistantEnabled or opts.assistantSteps or opts.assistantMark),
      "las opciones de activar, flechas de pasos y marcar el destino se quitaron")
    assert(not opts.assistantWorldPin, "el pin propio del mapa del mundo se quitó: lo marca WP.Mark")
    local cats = {}
    for _, c in ipairs(ES.OPTION_CATEGORIES) do cats[c.key] = true end
    assert(cats.assistant, "falta la categoría del asistente en las opciones")
    log[#log+1] = "     asistente: " .. f.banner.level._text .. " · " .. f.banner.title._text .. " · " .. f.banner.sub._text
  end)
  ES.RouteLock, ES.RouteLines, ES.GetProfessionSkill, ES.db.prof = saved[1], saved[2], saved[3], saved[4]
  if A.Frame() then A.Frame():Hide() end
  if not ok then error(err, 0) end
end)
-- Flecha GPS del asistente: hacia dónde apunta, el fotograma, el color, las yardas y
-- "Has llegado", con un continente de mentira de 1000 x 2000 yardas
step("asistente: flecha GPS", function()
  local A = ES.Assistant
  local saved = { C_Map, CreateVector2D, GetPlayerFacing, ES.RouteLock, ES.RouteLines, ES.GetProfessionSkill,
    ES.db.prof, ES.Waypoints.NPC }
  local ok, err = pcall(function()
    local pi = math.pi
    -- Giro: 0 delante, en el sentido del reloj (GetPlayerFacing: 0 al norte, crece al oeste)
    assert(math.abs(A.Turn(0, -10, 0)) < 1e-9, "al norte mirando al norte: delante")
    assert(math.abs(A.Turn(10, 0, 0) - pi / 2) < 1e-9, "al este mirando al norte: a la derecha")
    assert(math.abs(A.Turn(0, -10, pi / 2) - pi / 2) < 1e-9, "al norte mirando al oeste: a la derecha")
    assert(math.abs(A.Turn(0, 10, 0) - pi) < 1e-9, "al sur mirando al norte: detrás")
    local f0, l, r, t, b = A.ArrowCoords(0)
    assert(f0 == 0 and l == 0 and r == 1 / 8 and t == 0 and b == 1 / 8, "fotograma de delante")
    local f32, l2, _, t2 = A.ArrowCoords(pi)
    assert(f32 == 32 and l2 == 0 and t2 == 4 / 8, "fotograma de detrás: el 32")
    assert(A.ArrowCoords(2 * pi - 0.001) == 0, "casi una vuelta: delante")
    local gr, gg = A.TurnColor(0)
    local rr, rg = A.TurnColor(pi)
    assert(gg > gr and rr > rg, "verde de frente, rojo detrás")
    -- Posiciones: el jugador en el centro del continente 1414; el PNJ, en el mismo
    local function V(x, y) return { x = x, y = y, GetXY = function(self) return self.x, self.y end } end
    CreateVector2D = V
    local maps = { [1414] = { mapID = 1414, mapType = 2, name = "Kalimdor" },
      [1453] = { mapID = 1453, mapType = 3, parentMapID = 1414, name = "Stormwind" },
      [9999] = { mapID = 9999, mapType = 2, name = "Outland" },
      [1415] = { mapID = 1415, mapType = 2, name = "Eastern Kingdoms" },
      [1437] = { mapID = 1437, mapType = 3, parentMapID = 1415, name = "Wetlands" },
      [1439] = { mapID = 1439, mapType = 3, parentMapID = 1414, name = "Darkshore" },
      [1445] = { mapID = 1445, mapType = 3, parentMapID = 1414, name = "Dustwallow Marsh" } }
    local playerAt = V(0.5, 0.5)
    C_Map = {
      GetMapInfo = function(m) return maps[m] end,
      GetBestMapForUnit = function() return 1453 end,
      GetPlayerMapPosition = function(m) return m == 1414 and playerAt or nil end,
      GetWorldPosFromMapPos = function(m, v) return 0, V(v.x * 1000, v.y * 2000) end,
      GetMapPosFromWorldPos = function(_, w, m) return m, V(w.x / 1000, w.y / 2000) end,
    }
    local npc = { name = "Georgio Bolero", map = 1414, x = 0.6, y = 0.5, side = "" }
    local e, s = A.Relative(npc)
    assert(math.abs(e - 100) < 1e-6 and math.abs(s) < 1e-6, string.format("100 yardas al este: %s, %s", tostring(e), tostring(s)))
    assert(select(2, A.Relative({ name = "x", map = 9999, x = 0.5, y = 0.5 })) == "continent", "otro continente")
    -- En el asistente: el paso con PNJ fija el destino y la flecha lo enseña
    GetPlayerFacing = function() return 0 end
    ES.Waypoints.NPC = function(_, id) return id == 777 and npc or nil end
    ES.Waypoints.NPC = function(id) return id == 777 and npc or nil end
    local lock = { from = 100, to = 120, started = 4242 }
    ES.db.prof = { Tailoring = {} }
    ES.RouteLock = function(_, k) return k == "Tailoring" and lock or nil end
    local calls = 0
    ES.RouteLines = function() return {
      { level = "110", title = "Entrenar Oficial", current = true, icon = 134400,
        go = function() calls = calls + 1 return 777 end },
    } end
    ES.GetProfessionSkill = function() return 110, 150 end
    A.Update()
    local f = A.Frame()
    assert(f.nav._shown and f.nav.arrow._shown ~= false, "con un PNJ al que ir, la flecha debería verse")
    assert(tostring(f.nav.big._text):find("^100 yd"), "yardas: " .. tostring(f.nav.big._text))
    assert(tostring(f.nav.small._text):find("Georgio Bolero"), "falta a quién vas")
    -- Opción "Mostrar la flecha GPS" desactivada: sin flecha
    ES.db.assistant = ES.db.assistant or {}
    ES.db.assistant.noArrow = true
    A.NavTick()
    assert(f.nav._shown == false, "con la flecha desactivada no debería verse")
    ES.db.assistant.noArrow = nil
    A.NavTick()
    assert(f.nav._shown, "la flecha debería volver")
    -- Pasar el ratón por el banner pone encima el botón de la estrella, una capa por encima
    assert(f.banner.hoverStrata == "FULLSCREEN_DIALOG" and f.nav.hoverStrata == "FULLSCREEN_DIALOG",
      "el botón de la estrella debería ir por encima del asistente")
    local callsBefore = calls
    f.banner._scripts.OnEnter(f.banner)
    local hb = ES.Waypoints.HoverButton()
    assert(hb and hb.row == f.banner, "al pasar el ratón por el banner debería ponerse el botón de la estrella")
    calls = callsBefore -- (el botón de la estrella busca el PNJ al ponerse: no es el destino)
    -- El destino se fija al empezar el paso: otra actualización no lo vuelve a buscar
    A.Update()
    assert(calls == 1, "el destino no debería recalcularse en cada actualización: " .. calls)
    -- Pulsar el banner sí lo vuelve a buscar
    f.banner._scripts.OnClick(f.banner, "LeftButton") -- (el clic también marca el camino: lo busca una vez)
    local afterClick = calls
    A.Update()
    assert(calls == afterClick + 1, "pulsar el banner debería volver a buscar el más cercano")
    -- A menos de 10 yardas: "Has llegado" (y la flecha sigue)
    playerAt = V(0.595, 0.5)
    A.NavTick()
    assert(tostring(f.nav.small._text):find("Clic para marcarlo") and tostring(f.nav.big._text):find("Georgio Bolero"), "a 5 yardas: " .. tostring(f.nav.big._text) .. " / " .. tostring(f.nav.small._text))
    -- En otro continente: sin flecha, lo dice
    npc.map = 9999
    A.NavTick()
    assert(f.nav.arrow._shown == false and tostring(f.nav.big._text):find("otro continente"), "otro continente: " .. tostring(f.nav.big._text))
    -- En los Reinos del Este, y tú en Kalimdor (de la Alianza): barco en Costa Oscura o en Revolcafango
    npc.map = 1437
    A.NavTick()
    assert(tostring(f.nav.big._text):find("Eastern Kingdoms") and tostring(f.nav.small._text):find("Barco en Darkshore o Dustwallow Marsh"),
      "cómo cruzar: " .. tostring(f.nav.big._text) .. " / " .. tostring(f.nav.small._text))
    -- Minimapa (100 px de ancho en la prueba, zoom 0 fuera: 466 yardas de lado a lado):
    -- a 100 yardas, dentro; a 1000, en el borde
    assert(A.UpdateMinimap(100, 0, 0) == false, "a 100 yardas el destino debería caer dentro del minimapa")
    assert(A.UpdateMinimap(1000, 0, 0) == true, "a 1000 yardas debería ir al borde del minimapa")
    log[#log+1] = "     flecha GPS: giro, fotogramas, color, 100 yd, Has llegado, otro continente y minimapa"
  end)
  C_Map, CreateVector2D, GetPlayerFacing = saved[1], saved[2], saved[3]
  ES.RouteLock, ES.RouteLines, ES.GetProfessionSkill, ES.db.prof, ES.Waypoints.NPC = saved[4], saved[5], saved[6], saved[7], saved[8]
  if A.Frame() then A.Frame():Hide() end
  if not ok then error(err, 0) end
end)
-- Filas de compra de la ruta empezada (ProfessionUI.lua, AddBuyLines): lo que falta del
-- tramo (lo mismo que la vista Materiales), cuándo son el paso actual y cuándo solo avisan
step("ruta: filas de compra (paran al empezar el tramo o sin poder fabricar)", function()
  local saved = { prof = ES.db.prof, skill = ES.GetProfessionSkill, count = ES.ItemCount, known = ES.IsRecipeKnown,
    ahOpen = ES.IsAuctionHouseOpen, locked = ES.lockedPlans.Leatherworking }
  local ok, err = pcall(function()
    ES.db.prof = { Leatherworking = {} }
    local plan = ES.Planner:Plan(ES.Data.Leatherworking, ES:PlanOptions("Leatherworking", 120, 225, 300))
    assert(#plan.steps > 1, "sin ruta de peletería")
    local lock = { from = 120, to = 225, started = 777 }
    -- "Fabrica N× X": N es lo que te QUEDA por fabricar, y debajo el total y lo que tienes
    -- (Discord: "¿149 en total?")
    do
      local c1 = plan.crafted[1]
      ES.db.prof.Leatherworking.lock = { from = 120, to = 225, started = 777 }
      -- (con "ruta entera": por tramos, la fila pide lo del tramo; ver la categoría route)
      ES.db.prof.Leatherworking.byPhase = false
      plan.lockStarted, plan.lockPrices = 777, nil
      ES.lockedPlans.Leatherworking = plan
      local savedCount, savedSkill, savedKnown = ES.ItemCount, ES.GetProfessionSkill, ES.IsRecipeKnown
      ES.GetProfessionSkill = function() return plan.steps[1].from, 300 end
      ES.IsRecipeKnown = function() return true end
      ES.ItemCount = function(_, id) return id == c1.itemID and 10 or 0 end
      local prep
      for _, l in ipairs(ES:RouteLines("Leatherworking")) do if l.item == c1.itemID and l.stepRecipe and not l.level:find("–") then prep = l end end
      ES.ItemCount, ES.GetProfessionSkill, ES.IsRecipeKnown = savedCount, savedSkill, savedKnown
      if prep then
        assert(tostring(prep.title):find(tostring(c1.quantity - 10) .. "×"), "el título debería decir lo que queda: " .. tostring(prep.title))
        assert(tostring(prep.sub):find(tostring(c1.quantity) .. " en total · tienes 10"), "falta el total y lo que tienes: " .. tostring(prep.sub))
        assert(tostring(prep.sub):find("Hourglass"), "falta el tiempo de fabricar lo que queda: " .. tostring(prep.sub))
        -- En el asistente, sin el porqué (está en la ventana): solo cuántas y el tiempo
        assert(tostring(prep.bannerSub):find("en total · tienes 10") and tostring(prep.bannerSub):find("Hourglass")
          and not tostring(prep.bannerSub):find("pasos siguientes"), "el banner del intermedio: " .. tostring(prep.bannerSub))
        -- Sin material para ni uno del intermedio, pero sí para el paso: no te quedas parado
        -- en él (Discord: "Fabrica 3× Bolt of Linen Cloth" con 1 Linen Cloth y sin compra)
        local savedFit = ES.CraftableFromBags
        local midRecipe = c1.recipe and c1.recipe.id
        local at = tonumber(prep.level)
        local function Prep(fitMid)
          ES.CraftableFromBags = function(id) if id == midRecipe then return fitMid end return 5 end
          ES.GetProfessionSkill = function() return at, 300 end
          ES.IsRecipeKnown = function() return true end
          ES.ItemCount = function(_, id) return id == c1.itemID and 10 or 0 end
          local p
          for _, l in ipairs(ES:RouteLines("Leatherworking")) do if l.item == c1.itemID and l.stepRecipe and not l.level:find("–") then p = l end end
          ES.ItemCount, ES.GetProfessionSkill, ES.IsRecipeKnown, ES.CraftableFromBags = savedCount, savedSkill, savedKnown, savedFit
          return p
        end
        local canMake, cannot = Prep(5), Prep(0)
        if canMake and canMake.current then
          assert(cannot and not cannot.current, "sin material para el intermedio y con el paso fabricable, el intermedio no es el paso actual")
          assert(tostring(cannot.sub):find("sin materiales"), "se dice por qué: " .. tostring(cannot.sub))
          log[#log+1] = "     intermedio sin materiales: sigue el paso"
        else
          log[#log+1] = "     (intermedio sin materiales: en su nivel no era el paso actual)"
        end
      end
      -- Con "usar lo de tus bolsas" y 10 de ese intermedio en ellas: la ruta ya gasta esas
      -- 10 y fabrica el resto; la fila no tiene que restarlas otra vez (CurseForge: 57 Bolt
      -- of Silk Cloth y 10 en las bolsas decía "Fabrica 37× · 47 en total")
      local o = ES:PlanOptions("Leatherworking", 120, 225, 300)
      o.owned = { [c1.itemID] = 10 }
      local bagPlan = ES.Planner:Plan(ES.Data.Leatherworking, o)
      local cb
      for _, c in ipairs(bagPlan.crafted) do if c.itemID == c1.itemID then cb = c end end
      if cb and cb.owned == 10 then
        assert(ES.Planner.CraftedTotal(cb) == cb.quantity + 10, "el total cuenta lo de las bolsas")
        local full = ES.Planner.CraftedNeedFrom(bagPlan, c1.itemID, bagPlan.from, true)
        -- (sin withOwned, solo lo fabricado: lo que vale como su material ya convertido)
        local made = ES.Planner.CraftedNeedFrom(bagPlan, c1.itemID, bagPlan.from)
        assert(math.abs(math.ceil(made - 0.001) - cb.quantity) <= 1, string.format("solo lo fabricado: %s frente a %d", tostring(made), cb.quantity))
        assert(full and math.abs(math.ceil(full - 0.001) - ES.Planner.CraftedTotal(cb)) <= 1,
          string.format("lo que gasta la ruta, con lo de las bolsas: %s frente a %d", tostring(full), ES.Planner.CraftedTotal(cb)))
        bagPlan.lockStarted, bagPlan.lockPrices = 777, nil
        ES.lockedPlans.Leatherworking = bagPlan
        ES.GetProfessionSkill = function() return bagPlan.steps[1].from, 300 end
        ES.IsRecipeKnown = function() return true end
        ES.ItemCount = function(_, id) return id == c1.itemID and 10 or 0 end
        local row
        for _, l in ipairs(ES:RouteLines("Leatherworking")) do if l.item == c1.itemID and l.stepRecipe and not l.level:find("–") then row = l end end
        ES.ItemCount, ES.GetProfessionSkill, ES.IsRecipeKnown = savedCount, savedSkill, savedKnown
        assert(row, "sin la fila de fabricar el intermedio")
        assert(tostring(row.title):find(" " .. cb.quantity .. "×"), string.format("con bolsas, fabrica %d (no %d): %s", cb.quantity, cb.quantity - 10, tostring(row.title)))
        assert(tostring(row.sub):find(tostring(cb.quantity + 10) .. " en total · tienes 10"), "con bolsas, el total cuenta lo tuyo: " .. tostring(row.sub))
        log[#log+1] = string.format("     con bolsas: fabrica %d · %d en total · tienes 10", cb.quantity, cb.quantity + 10)
      else
        log[#log+1] = "     (con bolsas, la ruta de prueba no usa las 10 del intermedio)"
      end
      ES.db.prof.Leatherworking.byPhase = nil
    end
    ES.db.prof.Leatherworking.lock = lock
    plan.lockStarted, plan.lockPrices = lock.started, lock.scanTime
    ES.lockedPlans.Leatherworking = plan
    ES.routeBuyVisits.Leatherworking = nil
    local level = plan.steps[1].from
    ES.GetProfessionSkill = function() return level, 300 end
    ES.IsRecipeKnown = function() return true end
    ES.IsAuctionHouseOpen = function() return false end
    local function Lines()
      local lines = ES:RouteLines("Leatherworking", { buy = true }) -- (las del asistente)
      local buys, cur, n = {}, nil, 0
      for _, l in ipairs(lines) do
        if l.buyRow then buys[#buys + 1] = l end
        if l.current then cur, n = l, n + 1 end
      end
      assert(n <= 1, "más de un paso actual: " .. n)
      return lines, buys, cur
    end
    -- Empieza el tramo con las bolsas vacías: comprar es el paso actual, y lo que falta es
    -- lo mismo que dice la vista Materiales (RouteBuy)
    ES.ItemCount = function() return 0 end
    local allLines, buys, cur = Lines()
    -- (sin el aviso "¿No había en la AH?": la ruta ya cuenta lo que hay a la venta, y
    -- confundía con miles a la venta; Discord: 316× Bolt of Linen Cloth)
    for _, l in ipairs(allLines) do
      assert(not tostring(l.sub):find("No había en la AH"), "una fila aún dice que no había en la AH: " .. tostring(l.sub))
    end
    assert(buys[1] and cur == buys[1], "al empezar el tramo sin materiales, el paso actual debería ser comprar: " .. tostring(cur and cur.title))
    local buy = ES.RouteBuy(plan, "Leatherworking", level, { phase = true })
    -- Cada fila de compra lleva icono (el del objeto, o el de la AH, el vendedor o el banco)
    for _, b in ipairs(buys) do assert(b.icon ~= nil, "fila de compra sin icono: " .. tostring(b.buyRow)) end
    local listed = 0
    for _, b in ipairs(buys) do listed = listed + #b.buyItems end
    assert(listed == #buy.ah + #buy.vendor, "las filas de compra no piden lo mismo que la vista Materiales")
    -- Lo ya convertido cuenta como su material (Discord: al pasar Runecloth a Bolt of
    -- Runecloth, la fila volvía a pedir comprar Runecloth)
    do
      local mid, raw, per
      for _, c in ipairs(plan.crafted or {}) do
        local r = c.recipe
        if not mid and r and r.r and r.r[1] and r.out and buy.need[r.r[1][1]] then
          mid, raw, per = c.itemID, r.r[1][1], r.r[1][2] / math.max(1, r.out[2] or 1)
        end
      end
      if mid then
        local savedCount = ES.ItemCount
        ES.ItemCount = function(_, id) if id == mid then return 4 end return 0 end
        local b2 = ES.RouteBuy(plan, "Leatherworking", level, { phase = true })
        assert(b2.Have(raw) >= math.floor(4 * per + 0.001), string.format("4 intermedios cuentan como %d de su material: %d", math.floor(4 * per), b2.Have(raw)))
        local before, after = 0, 0
        for _, it in ipairs(buy.ah) do if it.itemID == raw then before = it.quantity end end
        for _, it in ipairs(buy.vendor) do if it.itemID == raw then before = it.quantity end end
        for _, it in ipairs(b2.ah) do if it.itemID == raw then after = it.quantity end end
        for _, it in ipairs(b2.vendor) do if it.itemID == raw then after = it.quantity end end
        assert(after <= math.max(0, before - math.floor(4 * per + 0.001)), "comprar menos: " .. before .. " -> " .. after)
        ES.ItemCount = savedCount
        log[#log+1] = string.format("     convertido: 4 de %d = %s de %d", mid, ES.Num(4 * per), raw)
        -- Lo que gasta la ruta de ese intermedio, desde tu nivel: desde el principio, lo
        -- de toda la ruta; según subes, menos (Discord: en 229 seguía pidiendo los 20
        -- Bolt of Runecloth del 226)
        local total
        for _, c in ipairs(plan.crafted) do if c.itemID == mid then total = ES.Planner.CraftedTotal(c) end end
        local full = ES.Planner.CraftedNeedFrom(plan, mid, plan.from)
        assert(full and math.abs(math.ceil(full - 0.001) - total) <= 1,
          string.format("desde el principio, lo de toda la ruta: %s frente a %d", tostring(full), total))
        local prev, lastUse = full, plan.from
        for s = plan.from, (plan.reached or plan.to) - 1 do
          local now = ES.Planner.CraftedNeedFrom(plan, mid, s)
          assert(now <= prev + 1e-6, "según subes, nunca más")
          if now > 0 then lastUse = s end
          prev = now
        end
        assert(ES.Planner.CraftedNeedFrom(plan, mid, lastUse + 1) == 0, "pasado el último nivel que lo gasta, nada")
      else
        log[#log+1] = "     (la ruta de prueba no fabrica intermedios del tramo)"
      end
    end
    assert(buys[1].go and not buys[1].onClick, "sin la AH ni el vendedor abiertos, el clic marca el camino")
    -- Solo el asistente: la vista Ruta de la ventana no tiene filas de compra (lo tiene en
    -- Materiales y la Lista de compra) y su paso actual sigue siendo el suyo
    local bigCur
    for _, l in ipairs(ES:RouteLines("Leatherworking")) do
      assert(not l.buyRow, "la vista Ruta de la ventana no debería tener filas de compra")
      if l.current then bigCur = l end
    end
    assert(bigCur and not (bigCur.sub or ""):find("luego compra"), "la vista Ruta no debería avisar de compras")
    -- Lista de la ruta quitada de la Lista de compra: la fila lo dice y el clic la vuelve a añadir
    ES.Shopping.SetRouteListHidden("Leatherworking", true)
    local _, hiddenBuys = Lines()
    assert(hiddenBuys[1].readd and hiddenBuys[1].onClick and tostring(hiddenBuys[1].bannerSub):find("Lista de compra"),
      "con la lista quitada, la fila debería decir que no está y poder añadirla")
    hiddenBuys[1].onClick()
    assert(not ES.Shopping.RouteListHidden("Leatherworking"), "el clic no volvió a añadir la lista de la ruta")
    local _, backBuys = Lines()
    assert(not backBuys[1].readd and backBuys[1].bannerSub == "", "con la lista ya puesta, la fila va sin subtítulo")
    -- Y el asistente enseña la de comprar
    ES.Assistant.Update()
    assert(ES.Assistant.State().line and ES.Assistant.State().line.buyRow, "el asistente debería decir que compres")
    ES.Assistant.Frame():Hide()
    log[#log+1] = "     compra: " .. tostring(buys[1].title):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. " · " .. tostring(buys[1].bannerSub)
    -- Con la AH abierta, el clic abre la compra
    ES.IsAuctionHouseOpen = function() return true end
    local _, buysAH = Lines()
    local ahRow
    for _, b in ipairs(buysAH) do
      if b.buyRow == "ah" then assert(b.onClick and not b.go, "con la AH abierta, el clic debería abrir la compra") ahRow = b end
    end
    -- En la AH, una fila por material: su clic abre la compra de ese (con todos en una,
    -- el clic siempre abría el primero y no se llegaba al segundo)
    local savedBuy, opened = ES.OpenAuctionBuy, {}
    ES.OpenAuctionBuy = function(_, id) opened[#opened + 1] = id end
    local nAH = 0
    for _, b in ipairs(buysAH) do
      if b.buyRow == "ah" then
        nAH = nAH + 1
        assert(#b.buyItems == 1 and b.item == b.buyItems[1].itemID, "fila de la AH con un solo material")
        b.onClick()
        assert(opened[#opened] == b.buyItems[1].itemID, "el clic abre la compra de su material")
      end
    end
    ES.OpenAuctionBuy = savedBuy
    local blockers = 0
    for _, b in ipairs(buysAH) do if b.current then blockers = blockers + 1 end end
    assert(blockers <= 1, "solo una fila de compra es el paso actual")
    -- El reparto: banco y vendedor en una fila; en la AH, una por material
    local g = ES.UI.BuyGroups({ bank = { { itemID = 1 } }, ah = { { itemID = 2 }, { itemID = 3 } }, vendor = { { itemID = 4 }, { itemID = 5 } } })
    assert(#g == 4 and g[1][1] == "bank" and g[2][1] == "ah" and g[2][2][1].itemID == 2 and #g[2][2] == 1
      and g[3][2][1].itemID == 3 and g[4][1] == "vendor" and #g[4][2] == 2, "filas: banco, una por material de la AH, vendedor")
    log[#log+1] = string.format("     compra en la AH: %d filas, una por material", nAH)
    ES.IsAuctionHouseOpen = function() return false end
    -- Con todo comprado: ni filas de compra ni nada que pare
    ES.ItemCount = function() return 100000 end
    local _, none, cur2 = Lines()
    assert(#none == 0 and cur2 and not cur2.buyRow, "con todo comprado no debería haber filas de compra")
    -- Comprado en la AH y aún sin llegar a las bolsas: "Recoge el correo" (te lleva al
    -- buzón; se da por hecho cuando lo tienes en las bolsas). Sin usar el correo
    do
      local needID
      for id in pairs(ES.RouteBuy(plan, "Leatherworking", level, { phase = true }).need) do needID = needID or id end
      local savedOW = ES.Ledger.OnWayItems
      ES.Ledger.OnWayItems = function() return { [needID] = 7, [999999] = 3 } end
      local savedCraft = ES.CraftableFromBags
      ES.CraftableFromBags = function() return 0 end
      local all, _, curM = Lines()
      local mailRow
      for _, l in ipairs(all) do if l.mailRow then mailRow = l end end
      assert(mailRow and mailRow.go and #mailRow.mailItems == 1 and mailRow.mailItems[1].itemID == needID,
        "falta el paso de recoger el correo (solo con lo de esta ruta)")
      assert(curM == mailRow, "sin compras pendientes y sin poder fabricar, el paso actual es recoger el correo")
      -- Saltar el correo (si no hace falta): queda hecho
      mailRow.markHave()
      local all2, _, curM2 = Lines()
      for _, l in ipairs(all2) do if l.mailRow then assert(l.done and l.skipped, "saltado, el correo queda hecho") end end
      assert(curM2 and not curM2.mailRow, "saltado el correo, el paso actual es otro")
      ES.routeBuyVisits.Leatherworking = nil
      ES.Ledger.OnWayItems, ES.CraftableFromBags = savedOW, savedCraft
      -- Sin nada de camino, no hay paso de correo
      local all3 = Lines()
      for _, l in ipairs(all3) do assert(not l.mailRow, "sin compras de camino no debería salir el correo") end
    end
    -- Ya fuiste a comprar (AH y vendedor cerrados con compras pendientes) y puedes fabricar:
    -- la ruta sigue y el paso avisa de lo que falta
    -- (sin el apunte de "con todo comprado" de arriba: con él, puedes fabricar y no pide
    -- nada, Planner.Stocked)
    ES.db.prof.Leatherworking.stocked = nil
    ES.ItemCount = function() return 0 end
    -- Cerrar la AH o un vendedor sin intentar comprar NO es "ya fuiste" (Discord: "No había
    -- suficiente" sin haber comprado ni una): abrir la AH para escanear, un vendedor para
    -- vender basura. Y lo apuntado en otra ruta de la misma profesión no cuenta en esta
    do
      local savedOnWay = ES.Ledger.OnWay
      ES.Ledger.OnWay = function() return 0 end
      ES.routeBuyVisits.Leatherworking = nil
      FireEvent("AUCTION_HOUSE_SHOW")
      FireEvent("AUCTION_HOUSE_CLOSED")
      FireEvent("MERCHANT_SHOW")
      FireEvent("MERCHANT_CLOSED")
      local v = ES.routeBuyVisits.Leatherworking
      assert(not (v and (v.ah or v.vendor)), "sin intentar comprar, cerrar la AH o un vendedor no es 'ya fuiste'")
      local _, fresh = Lines()
      for _, b in ipairs(fresh) do
        assert(not tostring(b.sub):find("No había"), "sin haber ido a comprar no debería decir 'No había suficiente': " .. tostring(b.sub))
      end
      local b0 = ES.RouteBuy(plan, "Leatherworking", level, ES.Shopping.ByPhase("Leatherworking") and { phase = true } or nil)
      if b0.ah[1] then
        -- Abriste la compra de uno (el clic de la fila: ES:OpenAuctionBuy) y no había bastante: sí
        FireEvent("AUCTION_HOUSE_SHOW")
        ES.buyTried.ah[b0.ah[1].itemID] = true
        FireEvent("AUCTION_HOUSE_CLOSED")
        v = ES.routeBuyVisits.Leatherworking
        assert(v and v.ah and v.key == ES.UI.BuyVisitKey("Leatherworking", b0.phase), "intentaste comprar en la AH: ya fuiste")
        -- Otra ruta de la misma profesión (otro inicio): no lo hereda
        local savedStarted = lock.started
        lock.started = savedStarted + 1
        local _, other = Lines()
        for _, b in ipairs(other) do
          assert(not tostring(b.sub):find("No había"), "una ruta nueva no hereda 'No había suficiente': " .. tostring(b.sub))
        end
        lock.started = savedStarted
        log[#log+1] = "     no había suficiente: solo tras intentar comprar, y de esta ruta"
      end
      ES.Ledger.OnWay = savedOnWay
      ES.routeBuyVisits.Leatherworking = nil
      -- (los eventos de la AH y del vendedor rehacen la ruta fijada: se deja la de la prueba)
      ES.db.prof.Leatherworking.lock = lock
      plan.lockStarted, plan.lockPrices = lock.started, lock.scanTime
      ES.lockedPlans.Leatherworking = plan
      ES.db.prof.Leatherworking.stocked = nil
    end
    -- (lo del vendedor, por material: cada fila de vendedor es un grupo de WP.VendorGroups)
    local seen = {}
    for _, it in ipairs(buy.vendor) do seen[it.itemID] = true end
    ES.routeBuyVisits.Leatherworking = { key = ES.UI.BuyVisitKey("Leatherworking", buy.phase), ah = true, vendorSeen = seen }
    local savedCraftable = ES.CraftableFromBags
    ES.CraftableFromBags = function() return 5 end
    local _, visitedBuys, cur3 = Lines()
    assert(visitedBuys[1] and cur3 and not cur3.buyRow, "ya fuiste y puedes fabricar: comprar no debería parar la ruta")
    assert(tostring(visitedBuys[1].sub):find("No había"), "la fila de compra debería decir que no había suficiente")
    -- (y el paso no avisa de lo que habrá que comprar: si no llegas, ya te manda; Discord)
    assert(not tostring(cur3.bannerSub):find("luego compra") and not tostring(cur3.sub):find("luego compra"),
      "el paso no debería decir 'luego compra': " .. tostring(cur3.bannerSub))
    -- Material para 5 y el paso pide más: la fila y el banner dicen la tanda (Discord:
    -- "Fabrica 101×" con material para 78, ¿es normal?)
    do
      local savedFit = ES.CraftableFromBags
      ES.CraftableFromBags = function() return 2 end
      local stepLine
      for _, l in ipairs(ES:RouteLines("Leatherworking", { buy = true })) do
        if not stepLine and l.stepRecipe and l.level and l.level:find("–") and not l.done then stepLine = l end
      end
      ES.CraftableFromBags = savedFit
      local n = stepLine and tonumber(tostring(stepLine.bannerTitle):match("(%d+)×")) or 0
      assert(n > 2, "el paso de prueba debería pedir más de 2: " .. tostring(stepLine and stepLine.bannerTitle))
      assert(stepLine.batchText == "esta tanda: 2", "falta la tanda: " .. tostring(stepLine.batchText))
      assert(tostring(stepLine.bannerSub):find("esta tanda: 2") and tostring(stepLine.sub):find("esta tanda: 2"),
        "la tanda, en la fila y en el banner: " .. tostring(stepLine.sub) .. " / " .. tostring(stepLine.bannerSub))
      assert(not tostring(stepLine.bannerSub):find("fabricaciones"), "el banner no repite las fabricaciones del título: " .. tostring(stepLine.bannerSub))
      log[#log+1] = "     tanda: " .. tostring(stepLine.bannerTitle) .. " / " .. tostring(stepLine.bannerSub)
    end
    -- ...pero sin poder fabricar ni una, vuelve a ser comprar (nunca te deja sin paso)
    ES.CraftableFromBags = function() return 0 end
    local _, _, cur4 = Lines()
    assert(cur4 and cur4.buyRow, "sin poder fabricar, el paso actual debería ser comprar")
    -- "Saltar" (la pestaña del asistente): esa compra se da por hecha en este tramo
    local src, srcItem = cur4.buyRow, cur4.buyItems[1].itemID
    local function Find(list)
      for _, b in ipairs(list) do if b.buyRow == src and b.buyItems[1].itemID == srcItem then return b end end
    end
    local othersBefore = 0
    do local _, all = Lines() for _, b in ipairs(all) do if not b.skipped and Find({ b }) == nil then othersBefore = othersBefore + 1 end end end
    assert(cur4.markHave, "la fila de compra debería poder darse por comprada")
    cur4.markHave()
    local _, afterHave, curAfter = Lines()
    local skipped = Find(afterHave)
    assert(skipped and skipped.skipped and skipped.done and not skipped.current and skipped.unmarkHave,
      "saltada, la fila queda como hecha y se puede recuperar")
    assert(curAfter ~= skipped, "la saltada no es el paso actual")
    -- Saltar un material de la AH no salta los demás
    local othersAfter = 0
    for _, b in ipairs(afterHave) do if not b.skipped then othersAfter = othersAfter + 1 end end
    assert(othersAfter == othersBefore, "saltar un material no debería saltar los demás: " .. othersBefore .. " -> " .. othersAfter)
    -- Recuperar: vuelve a pedirla
    skipped.unmarkHave()
    local _, restored = Lines()
    local r = Find(restored)
    assert(r and not r.skipped and r.markHave, "recuperada, la compra vuelve")
    -- En otro tramo, lo saltado se olvida
    r.markHave()
    ES.routeBuyVisits.Leatherworking.key = "otro"
    local _, again = Lines()
    local back = Find(again)
    assert(back and not back.skipped, "en otro tramo la compra vuelve a salir")
    -- Lista de la ruta entera: los pasos de compra del asistente piden la ruta entera
    -- (un solo ajuste para la lista y el asistente)
    ES.routeBuyVisits.Leatherworking = nil
    local stageQty = 0
    do local _, b = Lines() for _, x in ipairs(b) do for _, it in ipairs(x.buyItems) do stageQty = stageQty + it.quantity end end end
    ES.db.prof.Leatherworking.byPhase = false
    local wholeLines, whole = Lines()
    -- (con la ruta entera, en la AH: las recetas de la AH de más tarde, en el mismo viaje)
    local curAH
    for _, l in ipairs(wholeLines) do if l.current and (l.ahItem or l.buyRow == "ah") then curAH = l end end
    if curAH then
      -- ...y como pasos de esa misma parada: justo detrás de las compras de la AH, sin otro
      -- recado por medio (Discord: "todo lo de la AH junto")
      local lastAH, firstRecipe, lastRecipe
      for k, l in ipairs(wholeLines) do
        if l == curAH or l.buyRow == "ah" then lastAH = k end
        if l ~= curAH and l.ahItem and not l.done and l.recipeName then
          assert(l.buyNow, "con la ruta entera, en la AH debería proponer también la receta " .. l.recipeName)
          firstRecipe = firstRecipe or k
          lastRecipe = k
        end
      end
      if firstRecipe then
        assert(firstRecipe == lastAH + 1, "las recetas de la AH, justo detrás de sus compras: " .. firstRecipe .. " frente a " .. lastAH)
        for k = firstRecipe, lastRecipe do
          assert(wholeLines[k].ahItem and wholeLines[k].recipeName, "entre las recetas de la AH no debería haber otro recado")
        end
        log[#log+1] = "     ruta entera: " .. (lastRecipe - firstRecipe + 1) .. " receta(s) de la AH en la misma parada"
      else
        log[#log+1] = "     (ruta entera: la ruta de prueba no compra recetas en la AH)"
      end
    end
    local wholeQty, marked = 0, true
    for _, x in ipairs(whole) do
      for _, it in ipairs(x.buyItems) do wholeQty = wholeQty + it.quantity end
      if x.buyRow ~= "bank" and not x.wholeRoute then marked = false end
    end
    -- Ruta entera, como una tanda grande: a mitad de paso y pudiendo fabricar, no pide
    -- nada (Discord: al fabricar una, te mandaba a comprar 1 Bolt of Linen Cloth); sin
    -- poder fabricar, sí
    do
      local s1 = plan.steps[1]
      if s1.to - s1.from >= 2 then
        local savedFit = ES.CraftableFromBags
        ES.CraftableFromBags = function() return 5 end
        local held = ES.Planner.RouteNeed("Leatherworking", plan, s1.from + 1)
        ES.CraftableFromBags = function() return 0 end
        local stuck = ES.Planner.RouteNeed("Leatherworking", plan, s1.from + 1)
        ES.CraftableFromBags = savedFit
        assert(next(held) == nil, "ruta entera, a mitad de paso y pudiendo fabricar: no debería pedir nada")
        assert(next(stuck) ~= nil, "ruta entera, sin poder fabricar: debería pedir lo que falta")
      end
    end
    ES.db.prof.Leatherworking.byPhase = nil
    assert(#whole > 0 and marked, "con la ruta entera, los pasos de compra lo dicen")
    assert(wholeQty >= stageQty, string.format("la ruta entera pide al menos lo del tramo: %d < %d", wholeQty, stageQty))
    ES.CraftableFromBags = savedCraftable
    -- Tanda gastada a mitad de tramo (los puntos verdes no suben siempre): el ciclo entero.
    -- Fabricando con materiales -> sin materiales: comprar, y dice por qué -> comprado:
    -- otra vez fabricar
    ES.routeBuyVisits.Leatherworking = nil
    local s1 = plan.steps[1]
    if s1.to - s1.from >= 2 then
      level = s1.from + 1
      -- Por encima del principio del tramo SIN haber tenido sus materiales (el punto de
      -- más vino del paso anterior: captura del 2026-11-17, Fire Oil a 131): es la compra
      -- normal, no reponer
      ES.ItemCount = function() return 0 end
      local _, b0, c0 = Lines()
      assert(c0 and c0.buyRow and not c0.refill, "sin haber tenido los materiales del tramo no es reponer")
      ES.ItemCount = function() return 100000 end
      local _, b1, c1 = Lines()
      assert(#b1 == 0 and c1 and not c1.buyRow, "con materiales, fabricar")
      ES.ItemCount = function() return 0 end
      local _, b2, c2 = Lines()
      assert(c2 and c2.buyRow and c2.refill and tostring(c2.bannerSub):find("compra más")
        and not tostring(c2.bannerSub):lower():find("suerte"),
        "sin materiales a mitad de tramo: comprar más (sin hablar de suerte): " .. tostring(c2 and c2.bannerSub))
      ES.ItemCount = function() return 100000 end
      local _, b3, c3 = Lines()
      assert(#b3 == 0 and c3 and not c3.buyRow, "comprado lo que faltaba: otra vez fabricar")
      log[#log+1] = "     tanda gastada: fabricar -> comprar (" .. tostring(c2.title):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. ") -> fabricar"
      level = s1.from
    end
    -- Banco: lo que hay (según la foto) no se compra; va antes, en su fila
    do
      ES.ItemCount = function() return 0 end
      local firstNeed = (ES.RouteBuy(plan, "Leatherworking", level, { phase = true }).ah[1]
        or ES.RouteBuy(plan, "Leatherworking", level, { phase = true }).vendor[1])
      local savedBank, savedOpen = ES.Assistant.BankCount, ES.Assistant.BankOpen
      ES.Assistant.BankCount = function(id) return id == firstNeed.itemID and 100000 or 0 end
      ES.Assistant.BankOpen = function() return false end
      local blines = Lines()
      local bankRow, inBuy
      for _, l in ipairs(blines) do
        if l.buyRow == "bank" then bankRow = l end
        if l.buyRow == "ah" or l.buyRow == "vendor" then
          for _, it in ipairs(l.buyItems) do if it.itemID == firstNeed.itemID then inBuy = true end end
        end
      end
      assert(bankRow and bankRow.buyItems[1].itemID == firstNeed.itemID and bankRow.go, "falta la fila del banco con camino al banquero")
      assert(not inBuy, "lo que hay en el banco no debería comprarse")
      -- Con el banco abierto, su clic saca: montones partidos a huecos libres de las bolsas
      ES.Assistant.BankOpen = function() return true end
      local open = Lines()
      for _, l in ipairs(open) do if l.buyRow == "bank" then bankRow = l end end
      assert(bankRow.onClick and not bankRow.go, "con el banco abierto, el clic debería sacar")
      ES.Assistant.BankCount, ES.Assistant.BankOpen = savedBank, savedOpen
      -- TakeFromBank: banco con 20 + 20; bolsas con 2 huecos; faltan 25 -> 20 entero y 5 partidos
      local slots = { [-1] = { { id = 2318, n = 20 }, { id = 2318, n = 20 } }, [0] = { {}, {} } }
      local moves, cursor = {}, nil
      local savedC, savedCursor, savedClear = C_Container, CursorHasItem, ClearCursor
      C_Container = {
        GetContainerNumSlots = function(bag) return slots[bag] and #slots[bag] or 0 end,
        GetContainerItemInfo = function(bag, slot)
          local s = slots[bag] and slots[bag][slot]
          if s and s.id then return { itemID = s.id, stackCount = s.n, isLocked = false } end
        end,
        SplitContainerItem = function(bag, slot, n) moves[#moves + 1] = "split " .. n cursor = { id = slots[bag][slot].id, n = n } end,
        PickupContainerItem = function(bag, slot)
          local s = slots[bag][slot]
          if cursor then s.id, s.n, cursor = cursor.id, cursor.n, nil moves[#moves + 1] = "drop " .. bag
          else cursor = { id = s.id, n = s.n } moves[#moves + 1] = "pick " .. bag end
        end,
      }
      CursorHasItem = function() return cursor ~= nil end
      ClearCursor = function() cursor = nil end
      ES.Assistant.SetBankOpen(true)
      local left = ES.Assistant.TakeFromBank({ { itemID = 2318, quantity = 25 } })
      ES.Assistant.SetBankOpen(false)
      C_Container, CursorHasItem, ClearCursor = savedC, savedCursor, savedClear
      assert(left == 0 and table.concat(moves, ",") == "pick -1,drop 0,split 5,drop 0",
        "sacar del banco: " .. table.concat(moves, ",") .. " (faltan " .. tostring(left) .. ")")
      log[#log+1] = "     banco: fila antes de comprar; sacar 25 = " .. table.concat(moves, ", ")
    end
    -- Sin la profesión aprendida: la primera fila es aprenderla, y es el paso actual
    ES.GetProfessionSkill = function() return nil end
    local nlines, _, ncur = Lines()
    assert(nlines[1].learnProfession and ncur == nlines[1] and nlines[1].go,
      "sin la profesión, la primera fila (y el paso actual) debería ser aprenderla: " .. tostring(nlines[1].title))
    for i = 2, #nlines do assert(not nlines[i].learnProfession, "aprender la profesión, solo una vez") end
    assert(not nlines[1].onClick, "sin instructor abierto, aprender la profesión lleva a él (no aprende)")
    -- Saltar aprenderla (delante de la AH, comprar antes): queda hecha y el paso actual es
    -- otro; Recuperar la devuelve
    assert(nlines[1].markHave, "aprender la profesión debería poder saltarse")
    nlines[1].markHave()
    local slines, _, scur = Lines()
    assert(slines[1].learnProfession and slines[1].done and slines[1].skipped and slines[1].unmarkHave,
      "saltada, aprender la profesión queda hecha")
    assert(scur ~= slines[1], "saltada, el paso actual es otro")
    slines[1].unmarkHave()
    local rlines, _, rcur = Lines()
    assert(rcur == rlines[1] and not rlines[1].done, "recuperada, vuelve a ser el paso actual")
    -- Con el instructor abierto, el clic aprende la profesión (Apprentice Leatherworking);
    -- con dos principales ya (no disponible), lo dice en vez de "no lo enseña"
    do
      local svc = { { name = "Apprentice Leatherworking", kind = "available" } }
      local bought
      local saved = { GetNumTrainerServices, GetTrainerServiceInfo, GetTrainerServiceItemLink, BuyTrainerService, ES.Ledger.trainerOpen }
      GetNumTrainerServices = function() return #svc end
      GetTrainerServiceInfo = function(i) return svc[i].name, "", svc[i].kind end
      GetTrainerServiceItemLink = function() return nil end
      BuyTrainerService = function(i) bought = i end
      ES.Ledger.trainerOpen = true
      local tl = Lines()
      assert(tl[1].learnProfession and tl[1].onClick, "con el instructor abierto, aprender la profesión debería tener clic")
      tl[1].onClick()
      assert(bought == 1, "el clic no aprendió la profesión en el instructor")
      svc[1].kind, bought = "unavailable", nil
      local printed = {}
      local savedPrint = ES.Print
      ES.Print = function(_, text) printed[#printed + 1] = text end
      tl[1].onClick()
      ES.Print = savedPrint
      assert(not bought and printed[1] and printed[1]:find(ES:ProfLabel("Leatherworking"), 1, true),
        "con dos profesiones debería avisar: " .. tostring(printed[1]))
      GetNumTrainerServices, GetTrainerServiceInfo, GetTrainerServiceItemLink, BuyTrainerService, ES.Ledger.trainerOpen = unpack(saved)
      log[#log+1] = "     instructor abierto: el clic en Aprende la profesión la aprende (o avisa de las dos principales)"
    end
    ES.GetProfessionSkill = function() return level, 300 end
    local llines = Lines()
    assert(not llines[1].learnProfession, "con la profesión aprendida no hay fila de aprenderla")
    -- Entrenar va antes que comprar (Discord: Alquimia a 225 sin Artesano, el asistente
    -- mandaba antes a la AH): las compras, después, delante de lo que se fabrica
    local savedAlch = ES.lockedPlans.Alchemy
    ES.db.prof.Alchemy = {}
    local aplan = ES.Planner:Plan(ES.Data.Alchemy, ES:PlanOptions("Alchemy", 225, 230, 225))
    local alock = { from = 225, to = 230, cap = 225, started = 888 }
    ES.db.prof.Alchemy.lock = alock
    aplan.lockStarted, aplan.lockPrices = alock.started, alock.scanTime
    ES.lockedPlans.Alchemy = aplan
    ES.GetProfessionSkill = function(_, line) if line == ES.Data.Alchemy.skillLine then return 225, 225 end return level, 300 end
    ES.IsRecipeKnown = function() return false end
    -- (sin ruta de 225 a 230 con los precios de prueba, se comprueba con lo que haya)
    local alines = ES:RouteLines("Alchemy", { buy = true })
    if not alines then
      alines = {}
      log[#log+1] = "     (alquimia 225: sin ruta con los datos de prueba, no se comprueba)"
    end
    local acur, trainAt, buyAt
    for i, l in ipairs(alines) do
      if l.current then acur = l end
      if l.rankCap and not trainAt then trainAt = i end
      if l.buyRow and not buyAt then buyAt = i end
    end
    ES.lockedPlans.Alchemy = savedAlch
    if alines[1] then
      assert(acur and acur.rankCap == 300, "a 225 sin Artesano, lo primero debería ser entrenarlo: " .. tostring(acur and acur.title))
      assert(not buyAt or buyAt > trainAt, "las compras deberían ir después de entrenar")
      log[#log+1] = "     alquimia 225: primero " .. tostring(acur.title):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    end
  end)
  ES.db.prof, ES.GetProfessionSkill, ES.ItemCount, ES.IsRecipeKnown = saved.prof, saved.skill, saved.count, saved.known
  ES.IsAuctionHouseOpen, ES.lockedPlans.Leatherworking = saved.ahOpen, saved.locked
  ES.routeBuyVisits.Leatherworking = nil
  if not ok then error(err, 0) end
end)
-- Ganar dinero: quitar una receta con su ✕ (y recuperarla); las de enfriamiento no
-- entran en el lote (Discord: proponía transmutaciones en serie)
step("ganar dinero: quitar recetas y enfriamientos", function()
  local realSkill, realKnown = ES.GetProfessionSkill, ES.IsRecipeKnown
  local ok, err = pcall(function()
    ES.GetProfessionSkill = function(self, line) if line == ES.Data.Leatherworking.skillLine then return 150, 225 end end
    ES.IsRecipeKnown = function(self, id) local r = ES.Data.Leatherworking.recipes[id] return r ~= nil and r.fee ~= nil end
    -- Transmutar con el cliente en español (r.name traducido): sigue siendo de
    -- enfriamiento (la ruta de Alquimia pedía 186 "Transmutar: hierro a oro")
    local tr = ES.Data.Alchemy.recipes[11479]
    assert(ES.Planner.Cooldown({ name = "Transmutar: hierro a oro", nameEN = "Transmute: Iron to Gold" }, 11479)
      and tr and ES.Planner.Cooldown(tr, 11479), "Transmutar traducido debería tener enfriamiento")
    assert(not ES.Planner.Cooldown({ name = "Transmutar: fuego elemental", nameEN = "Transmute: Elemental Fire" }, 25146),
      "Transmute: Elemental Fire no tiene enfriamiento")
    ES.Earn:Clear()
    local res = ES.Earn:Ideas()
    -- (las de enfriamiento: como mucho una, nunca un lote en serie)
    for _, idea in ipairs(res.ideas) do
      if ES.Planner.Cooldown(idea.e.recipe, idea.e.id) then
        assert(idea.cooldown and idea.crafts <= 1, "enfriamiento en serie en Ganar dinero: " .. idea.e.recipe.name)
      end
    end
    local idea = res.ideas[1] or res.vendor[1] or res.learnable[1]
    if not idea then log[#log+1] = "     (sin ideas con los datos de prueba)" return end
    local id = idea.e.id
    ES.Earn.SetHidden(id, true)
    local res2 = ES.Earn:Ideas()
    for _, list in ipairs({ res2.ideas, res2.vendor, res2.learnable, res2.avoided }) do
      for _, i2 in ipairs(list) do assert(i2.e.id ~= id, "la receta quitada sigue en Ganar dinero") end
    end
    assert(res2.removed >= 1 and #ES.Earn.HiddenList() == 1, "falta contar la receta quitada")
    ES.Earn.SetHidden(id, false)
    assert(ES.db.earnHidden == nil, "al recuperarla no debería quedar nada guardado")
    local res3 = ES.Earn:Ideas()
    local back = false
    for _, list in ipairs({ res3.ideas, res3.vendor, res3.learnable }) do
      for _, i3 in ipairs(list) do if i3.e.id == id then back = true end end
    end
    assert(back, "la receta recuperada debería volver")
    log[#log+1] = "     ganar dinero: quitar y recuperar " .. idea.e.recipe.name
  end)
  ES.GetProfessionSkill, ES.IsRecipeKnown = realSkill, realKnown
  ES.db.earnHidden = nil
  ES.Earn:Clear()
  if not ok then error(err, 0) end
end)
-- Quién vende cada material en Forever (Data/MatVendors.lua) manda sobre
-- QuestieDB, que da los de Classic (Discord: mandaba a Edna Mullby a por Rune Thread)
step("vendedores de materiales: los de Forever", function()
  local RUNE, EDNA, ALEXANDRA = 14341, 1286, 1347
  assert(ES.Data.MatVendors and ES.Data.MatVendors[RUNE], "faltan los vendedores de materiales de Forever")
  local list = ES.Waypoints.Vendors(RUNE)
  local has = {}
  for _, id in ipairs(list) do has[id] = true end
  assert(not has[EDNA], "Edna Mullby no vende Rune Thread en Forever")
  assert(has[ALEXANDRA], "Alexandra Bolero sí")
  for _, id in ipairs(list) do
    assert(ES.Waypoints.NPC(id), "cada vendedor de la lista sabe dónde está: " .. id)
  end
  -- Lo que no está en esa lista sigue con los de QuestieDB
  local other
  for itemID, src in pairs(ES.Data.ItemSources or {}) do
    if src.v and src.v[1] and not ES.Data.MatVendors[itemID] then other = other or itemID end
  end
  if other then assert(#ES.Waypoints.Vendors(other) > 0, "lo demás, con los vendedores de siempre") end
  local n = 0
  for _ in pairs(ES.Data.MatVendors) do n = n + 1 end
  log[#log+1] = string.format("     vendedores de materiales: %d materiales, Rune Thread %d vendedores", n, #list)
end)
-- Con el vendedor abierto, la fila de compra del asistente compra justo lo que falta,
-- en los lotes del vendedor; lo que este vendedor no tiene, aparte
step("vendedor abierto: comprar justo lo que falta", function()
  local saved = { num = GetMerchantNumItems, iid = GetMerchantItemID,
    info = GetMerchantItemInfo, cmf = C_MerchantFrame, buy = ES.VendorShop.Buy, money = GetMoney }
  local ok, err = pcall(function()
    local RUNE, COARSE = 14341, 2320
    local stock = { COARSE, 2321 }
    GetMerchantNumItems = function() return #stock end
    GetMerchantItemID = function(i) return stock[i] end
    C_MerchantFrame = nil
    GetMerchantItemInfo = function(i) return nil, nil, 100, 5, -1, true, nil, false end
    GetMoney = function() return 1e9 end
    local bought = {}
    ES.VendorShop.Buy = function(self, e) bought[#bought + 1] = e end
    local b, m = ES.VendorShop:BuyExact({ { itemID = COARSE, quantity = 7 }, { itemID = RUNE, quantity = 2 } })
    assert(#b == 1 and b[1].itemID == COARSE and b[1].qty == 10 and #bought == 1, "7 de 5 en 5: 10")
    assert(#m == 1 and m[1].itemID == RUNE, "lo que no tiene, aparte")
    -- Con lo que llevas AHORA (captura del 2026-11-17: Empty Vial 49/46). Una fila pintada
    -- antes de otra compra pide de más: se recorta a lo que falta de verdad
    local savedHave = ES.HaveForShopping
    local bags = 40
    ES.HaveForShopping = function(_, id) return id == COARSE and bags or 0 end
    stock = { COARSE }
    GetMerchantItemInfo = function(i) return nil, nil, 100, 1, -1, true, nil, false end
    bought = {}
    b = ES.VendorShop:BuyExact({ { itemID = COARSE, quantity = 46, need = 46 } })
    assert(#b == 1 and b[1].qty == 6, "con 40 en las bolsas y 46 en total, compra 6: " .. tostring(b[1] and b[1].qty))
    bags = 46
    bought = {}
    b = ES.VendorShop:BuyExact({ { itemID = COARSE, quantity = 46, need = 46 } })
    assert(#b == 0 and #bought == 0, "con todo en las bolsas no compra nada (fila sin repintar)")
    ES.HaveForShopping = savedHave
  end)
  GetMerchantNumItems, GetMerchantItemID = saved.num, saved.iid
  GetMerchantItemInfo, C_MerchantFrame, ES.VendorShop.Buy, GetMoney = saved.info, saved.cmf, saved.buy, saved.money
  if not ok then error(err, 0) end
end)
-- En combate el juego bloquea que los clics del icono pasen a la fila (0.58.0:
-- ADDON_ACTION_BLOCKED al abrir una ruta peleando): se deja para cuando acabe
step("iconos de las filas: en combate no se toca lo bloqueado", function()
  local savedLock = InCombatLockdown
  local calls = 0
  local fake = { SetMouseClickEnabled = function() calls = calls + 1 end, SetPropagateMouseClicks = function() calls = calls + 1 end }
  InCombatLockdown = function() return true end
  ES.UI.PassClicks(fake)
  assert(calls == 0, "en combate no se llama a SetPropagateMouseClicks")
  InCombatLockdown = function() return false end
  FireEvent("PLAYER_REGEN_ENABLED")
  assert(calls == 2, "al acabar el combate se aplica: " .. calls)
  FireEvent("PLAYER_REGEN_ENABLED")
  assert(calls == 2, "solo una vez")
  InCombatLockdown = savedLock
end)
-- Enfriamientos en el lote: lista (o sin saber) y en la AH, 1 fabricación delante;
-- en marcha, fuera del lote y en su sección; al pasar el tiempo, vuelve sola
step("ganar dinero: enfriamientos listos en el lote", function()
  local saved = { skill = ES.GetProfessionSkill, known = ES.IsRecipeKnown, min = ES.db.earnMinProfit,
    cd = ES.charData.cdReady, tsui = C_TradeSkillUI, now = NOW,
    market = ES.Planner.RecipeMarket, cost = ES.Planner.RecipeCost }
  local r
  local ok, err = pcall(function()
    local LW = ES.Data.Leatherworking
    ES.GetProfessionSkill = function(self, line) if line == LW.skillLine then return 150, 225 end end
    ES.IsRecipeKnown = function(self, id) local x = LW.recipes[id] return x ~= nil and x.fee ~= nil end
    ES.db.earnMinProfit = 0
    ES.charData.cdReady = nil
    -- (los precios de prueba no dejan beneficio: dos recetas que sí, una con enfriamiento)
    local ids = {}
    for rid, x in pairs(LW.recipes) do if x.fee and x.out then ids[#ids + 1] = rid end end
    table.sort(ids)
    local id, other = ids[1], ids[2]
    r = LW.recipes[id]
    r.cd = true -- (Planner.Cooldown: los datos mandan)
    ES.Earn.ResetCooldownRecipes()
    local function Entry(rid, item, profit)
      return { id = rid, recipe = LW.recipes[rid], itemID = item, learnSource = "known", cost = 1000, profit = profit,
        sellWhere = "ah", ahNet = 1000 + profit, ahMin = 1100 + profit, qty = 1, quantity = 20, listings = 5, cut = 0.05, reagents = {} }
    end
    ES.Planner.RecipeMarket = function(self, data)
      if data ~= LW then return {}, { supply = {}, used = {} } end
      return { Entry(other, 990002, 90000), Entry(id, 990001, 5000) }, { supply = {}, used = {} }
    end
    ES.Planner.RecipeCost = function(ctx, recipe, n) return 1000 * n, {}, {}, nil end
    ES.Earn:Clear()
    local function Find(res)
      for _, i in ipairs(res.ideas) do if i.e.id == id then return i end end
    end
    -- Sin saber si está lista: entra, con 1 fabricación, delante y avisando
    ES.Earn:Clear(true)
    local res = ES.Earn:Ideas()
    local cd = Find(res)
    assert(cd and cd.cooldown and cd.cdUnknown and cd.crafts == 1, "enfriamiento sin saber: 1 fabricación en el lote")
    assert(res.ideas[1].e.id == id or res.ideas[1].custom, "el enfriamiento va delante")
    assert(cd.inBatch, "el enfriamiento entra en el lote")
    -- En marcha (2 h): fuera del lote y en la sección con lo que falta
    NOW = time()
    ES.charData.cdReady = { [id] = NOW + 7200 }
    ES.Earn:Clear(true)
    res = ES.Earn:Ideas()
    assert(not Find(res), "enfriamiento en marcha: fuera del lote")
    local found
    for _, c in ipairs(ES.Earn:Cooldowns()) do if c.id == id then found = c end end
    assert(found and not found.ready and not found.unknown and found.left > 7000, "sección: en marcha, con lo que falta")
    -- Cuándo estará lista, con la hora del ordenador del jugador (date del juego) y su
    -- ajuste de 12/24 h: "Listo hoy 18:40 (en 2 h)", "Listo viernes 14:30 (en 95 h)"
    local savedDate, savedCVar = date, GetCVarBool
    date = os.date
    GetCVarBool = function() return true end
    local base = os.time({ year = 2026, month = 11, day = 17, hour = 10, min = 0 })
    local function Has(s, pat) return s and s:find(pat, 1, true) end
    assert(Has(ES.LocalTimeLabel(base + 7200, base), os.date("%H:%M", base + 7200)), "hoy: con la hora")
    assert(ES.LocalTimeLabel(base + 7200, base) ~= ES.LocalTimeLabel(base + 86400 + 7200, base), "mañana no se dice como hoy")
    local friday = ES.LocalTimeLabel(base + 95 * 3600, base)
    assert(Has(friday, os.date("%H:%M", base + 95 * 3600)) and Has(friday, os.date("%A", base + 95 * 3600)), "a 95 h: el día de la semana y la hora: " .. tostring(friday))
    assert(Has(ES.LocalTimeLabel(base + 10 * 86400, base), os.date("%d/%m", base + 10 * 86400)), "a más de 6 días: la fecha")
    GetCVarBool = function() return false end
    assert(Has(ES.LocalTimeLabel(base + 7200, base), "12:00 PM"), "reloj de 12 horas: " .. tostring(ES.LocalTimeLabel(base + 7200, base)))
    date, GetCVarBool = savedDate, savedCVar
    log[#log+1] = "     enfriamiento: listo " .. tostring((function() date = os.date local s = ES.LocalTimeLabel(base + 95 * 3600, base) date = savedDate return s end)())
    -- Pasa el tiempo: vuelve al lote sin vaciar nada a mano
    NOW = NOW + 7300
    res = ES.Earn:Ideas()
    cd = Find(res)
    assert(cd and cd.cooldown and not cd.cdUnknown and cd.crafts == 1, "enfriamiento ya listo: vuelve al lote")
    for _, c in ipairs(ES.Earn:Cooldowns()) do if c.id == id then found = c end end
    assert(found.ready and found.inBatch, "sección: listo y en el lote")
    ES:SelectPage("money")
    ES:RenderEarn() -- (filas del lote y de la sección, con su clic)
    ES:SelectPage("home")
    -- Con la profesión abierta se lee del juego (C_TradeSkillUI.GetRecipeCooldown)
    C_TradeSkillUI = { GetRecipeCooldown = function(rid) if rid == id then return 3600, true, 0, 0 end end }
    assert(ES.Earn.ReadCooldowns("Leatherworking"), "leer el enfriamiento de la profesión abierta")
    assert(ES.charData.cdReady[id] == NOW + 3600, "se guarda cuándo estará lista")
    ES.Earn:Clear(true)
    assert(not Find(ES.Earn:Ideas()), "leído en marcha: fuera del lote")
    C_TradeSkillUI = { GetRecipeCooldown = function() return nil, true, 0, 0 end }
    assert(ES.Earn.ReadCooldowns("Leatherworking") and ES.Earn.CooldownLeft(id) == 0, "leído listo")
    -- Para aprender (Mooncloth): sí, contando una fabricación cada vez
    local lres = { learnable = {} }
    local le = { cost = 1000, profit = 5000, sellWhere = "ah", itemID = 990001, ahPrice = 6000, learn = 1, learnCost = 20000,
      listings = 5, quantity = 5 } -- (con mercado: ver Earn.LEARN_MIN_LISTINGS)
    ES.Earn.AddLearnable(lres, le, "Leatherworking", 150, 1000, true)
    assert(#lres.learnable == 1 and lres.learnable[1].cooldown and lres.learnable[1].payback == 4,
      "enfriamiento para aprender: se propone y se recupera en 4")
    lres = { learnable = {} }
    ES.Earn.AddLearnable(lres, le, "Leatherworking", 150, 10000, true)
    assert(#lres.learnable == 0, "enfriamiento para aprender: una sola por debajo del mínimo no se propone")
    lres = { learnable = {} }
    ES.Earn.AddLearnable(lres, { cost = 1000, profit = 5000, sellWhere = "vendor", itemID = 990001, vendor = 6000, learn = 1 },
      "Leatherworking", 150, 1000, true)
    assert(#lres.learnable == 0, "enfriamiento al vendedor: no se propone aprender")
    log[#log+1] = "     enfriamiento en el lote: " .. r.name
  end)
  if r then r.cd = nil end
  ES.Earn.ResetCooldownRecipes()
  ES.Planner.RecipeMarket, ES.Planner.RecipeCost = saved.market, saved.cost
  ES.GetProfessionSkill, ES.IsRecipeKnown, ES.db.earnMinProfit = saved.skill, saved.known, saved.min
  ES.charData.cdReady, C_TradeSkillUI, NOW = saved.cd, saved.tsui, saved.now
  ES.Earn:Clear()
  if not ok then error(err, 0) end
end)
-- Novedades: la casilla "No volver a mostrar" las apaga, y la opción de General también
step("novedades: no volver a mostrar", function()
  local savedSeen, savedNo, savedGet = ES.db.whatsNewSeen, ES.db.noWhatsNew, GetAddOnMetadata
  local ok, err = pcall(function()
    GetAddOnMetadata = function() return "99.0.0" end
    ES.db.whatsNewSeen, ES.db.noWhatsNew = "0.1.0", true
    local before = ES.WhatsNewFrame() and ES.WhatsNewFrame()._shown
    ES:CheckWhatsNew()
    assert(not ES.WhatsNewFrame() or ES.WhatsNewFrame()._shown == before, "con la opción apagada no deberían salir las novedades")
    assert(ES.db.whatsNewSeen == "99.0.0", "la versión se apunta igual (no sale de golpe al volver a activarla)")
    ES.db.noWhatsNew = nil
    ES:ShowWhatsNew(ES:WhatsNewSince("0.1.0", "0.58.0"))
    local f = ES.WhatsNewFrame()
    f.never:SetChecked(true)
    f._scripts.OnHide(f)
    assert(ES.db.noWhatsNew == true, "la casilla No volver a mostrar debería apagar las novedades")
    local found
    for _, o in ipairs(ES.OPTIONS) do if o.key == "noWhatsNew" and o.cat == "general" then found = true end end
    assert(found, "falta la opción de las novedades en General")
  end)
  ES.db.whatsNewSeen, ES.db.noWhatsNew, GetAddOnMetadata = savedSeen, savedNo, savedGet
  if not ok then error(err, 0) end
end)
-- Lo comprado en la AH cuenta ya, aunque esté en el correo (antes había que ir al buzón
-- tras cada compra para que el asistente y la Lista de compra lo vieran). Y no se queda
-- pegado: se borra al llegar a las bolsas, al abrir el buzón o pasada una hora
step("compras de la AH de camino al buzón", function()
  local LG = ES.Ledger
  local saved = { C_Container, ES.ItemCount, ERR_AUCTION_WON_S, GetInboxNumItems, GetInboxItem, GetItemInfo,
    ES.charData.ahOnWay, NOW, ES.ahOpen }
  ES.ahOpen = true -- (comprar es en la AH: fuera no se lee el chat)
  local bags, mail = 0, {}
  C_Container = { GetContainerNumSlots = function(b) return b == 0 and 1 or 0 end,
    GetContainerItemID = function() return bags > 0 and 765 or nil end,
    GetContainerItemInfo = function() return { stackCount = bags } end }
  ES.ItemCount = function(_, id) return id == 765 and bags or 0 end
  ERR_AUCTION_WON_S = "You won an auction for %s"
  GetInboxNumItems = function() return #mail end
  GetInboxItem = function(i, a) if a == 1 and mail[i] then return "Silverleaf", 765, 0, mail[i] end end
  GetItemInfo = function(n) if n == "Silverleaf" then return "Silverleaf", "|Hitem:765::|h[Silverleaf]|h" end end
  ES.charData.ahOnWay = nil
  local ok, err = pcall(function()
    local id, n = LG.ParseAuctionWon("You won an auction for |cffffffff|Hitem:765::::::::|h[Silverleaf]|h|rx21")
    assert(id == 765 and n == 21, "enlace y cantidad del mensaje: " .. tostring(id) .. " " .. tostring(n))
    id, n = LG.ParseAuctionWon("You won an auction for Silverleaf")
    assert(id == 765 and n == 1, "por el nombre y sin cantidad: una")
    assert(LG.ParseAuctionWon("You have been outbid on Silverleaf") == nil, "otro mensaje no es una compra")
    -- Forever añade el precio detrás (captura del 2026-11-17: no se enteraba de la compra)
    id, n = LG.ParseAuctionWon("You won an auction for |cffffffff|Hitem:765::|h[Silverleaf]|h|rx50 for 10s 50c")
    assert(id == 765 and n == 50, "con el precio detrás, enlace: " .. tostring(id) .. " " .. tostring(n))
    id, n = LG.ParseAuctionWon("You won an auction for [Silverleaf]x50 for 10s 50c")
    assert(id == 765 and n == 50, "con el precio detrás, sin enlace: " .. tostring(id) .. " " .. tostring(n))
    -- Con colores u otra cosa delante (addons de chat): igual
    id, n = LG.ParseAuctionWon("|cffffff00[12:03] You won an auction for |cffffffff|Hitem:765::|h[Silverleaf]|h|r|cffffff00x50 for 10s 50c|r")
    assert(id == 765 and n == 50, "con colores y hora delante: " .. tostring(id) .. " " .. tostring(n))
    -- Sin el objeto en la caché del juego: por los nombres de los datos del addon
    local savedGII = GetItemInfo
    GetItemInfo = function() return nil end
    id, n = LG.ParseAuctionWon("You won an auction for [Silverleaf]x50 for 10s 50c")
    GetItemInfo = savedGII
    assert(id == 765 and n == 50, "por el nombre de los datos: " .. tostring(id))
    -- Sin ERR_AUCTION_WON_S en el cliente: el texto en inglés
    local savedFmt = ERR_AUCTION_WON_S
    ERR_AUCTION_WON_S = nil
    id, n = LG.ParseAuctionWon("You won an auction for [Silverleaf]x50 for 10s 50c")
    ERR_AUCTION_WON_S = savedFmt
    assert(id == 765 and n == 50, "sin la cadena del cliente, en inglés")
    -- La compra (el mensaje del chat): cuenta ya
    FireEvent("CHAT_MSG_SYSTEM", "You won an auction for |cffffffff|Hitem:765::|h[Silverleaf]|h|rx21")
    assert(ES:HaveForShopping(765) == 21, "recién comprado, sin recoger: debería contar 21: " .. ES:HaveForShopping(765))
    -- Recoges una parte: no cuenta dos veces
    bags = 10
    assert(ES:HaveForShopping(765) == 21, "10 en las bolsas y 11 de camino: " .. ES:HaveForShopping(765))
    bags = 21
    assert(ES:HaveForShopping(765) == 21 and #ES.charData.ahOnWay == 0, "todo recogido: fuera de lo de camino")
    -- Recogido a la bolsa de componentes de Forever (Enum.BagIndex.ReagentBag = 5): también
    -- llega (captura del 2026-11-19: "Recoge el correo" seguía tras recoger las hierbas)
    local savedCC, savedEnum = C_Container, Enum
    Enum = setmetatable({ BagIndex = { ReagentBag = 5 } }, { __index = savedEnum })
    local reagent = 0
    C_Container = { GetContainerNumSlots = function(b) return (b == 0 or b == 5) and 1 or 0 end,
      GetContainerItemID = function(b) if b == 5 and reagent > 0 then return 765 end end,
      GetContainerItemInfo = function(b) return { stackCount = b == 5 and reagent or 0 } end }
    bags = 0
    LG.AddOnWay(765, 12, "sistema")
    assert(LG.OnWayItems()[765] == 12, "comprado: 12 de camino")
    reagent, bags = 12, 12 -- (GetItemCount cuenta todas las bolsas)
    assert(LG.OnWayItems()[765] == nil and #ES.charData.ahOnWay == 0, "recogido a la bolsa de componentes: ya no está de camino")
    C_Container, Enum, bags = savedCC, savedEnum, 21
    -- El correo no se mira (daba problemas): abrir el buzón no cambia nada
    bags = 0
    LG.AddOnWay(765, 5, "sistema")
    mail = {}
    FireEvent("MAIL_INBOX_UPDATE")
    assert(ES:HaveForShopping(765) == 5 and LG.ReconcileMail == nil, "el buzón no debería tocar lo comprado")
    -- Pasadas dos horas, fuera (no se queda pegado)
    NOW = NOW + 7300
    assert(ES:HaveForShopping(765) == 0, "pasadas dos horas no debería seguir de camino")
    -- Una receta comprada sin enlace en el mensaje ("Recipe: Rage Potion"): por el nombre
    -- de su pergamino, aunque el juego no la tenga en caché
    local savedGII2 = GetItemInfo
    GetItemInfo = function() return nil end
    local rid, rn = LG.ParseAuctionWon("You won an auction for Recipe: Rage Potion")
    GetItemInfo = savedGII2
    assert(rid == ES.Data.Alchemy.recipes[6617].scroll and rn == 1, "receta por el nombre del pergamino: " .. tostring(rid))
    -- Las demás vías (captura del 2026-11-17: el juego no mandaba el mensaje; la línea
    -- del chat la escribe TSM). Cada compra cuenta una vez aunque llegue por varias
    mail = {}
    local savedGT, clock = GetTime, 100
    GetTime = function() return clock end
    -- 1. La línea que escribe un addon (TSM) en la ventana de chat
    LG.OnChatLine("You won an auction for [Silverleaf]x50 for 35s 00c", "chat")
    assert(ES:HaveForShopping(765) == 50, "la línea de TSM en el chat cuenta: " .. ES:HaveForShopping(765))
    -- ...la misma línea en otra ventana de chat no cuenta otra vez
    LG.OnChatLine("You won an auction for [Silverleaf]x50 for 35s 00c", "chat")
    assert(ES:HaveForShopping(765) == 50, "la misma línea en dos ventanas cuenta una vez")
    -- ...y el mensaje del juego de la misma compra (sin cantidad) tampoco
    FireEvent("CHAT_MSG_SYSTEM", "You won an auction for Silverleaf")
    assert(ES:HaveForShopping(765) == 50, "el mensaje del juego de la misma compra no suma: " .. ES:HaveForShopping(765))
    -- ...pero dos compras iguales seguidas (dos mensajes, en fotogramas distintos y a
    -- menos de 2 s) cuentan las dos; y cada una, en dos ventanas, una vez
    local WIZARD_OIL = 20750
    local oil = "You won an auction for [Wizard Oil] for 1s 00c"
    assert(LG.ParseAuctionWon(oil) == WIZARD_OIL, "Wizard Oil por el nombre de los datos")
    clock = 150
    LG.OnChatLine(oil, "chat")
    LG.OnChatLine(oil, "chat") -- (otra ventana, el mismo fotograma)
    clock = 150.8
    LG.OnChatLine(oil, "chat")
    LG.OnChatLine(oil, "chat")
    assert(ES:HaveForShopping(WIZARD_OIL) == 2, "dos compras iguales seguidas: " .. ES:HaveForShopping(WIZARD_OIL))
    -- 2. AH clásica: compra inmediata (PlaceAuctionBid) y te cobran
    clock = 200
    local money, savedGM, savedGAI = 100000, GetMoney, GetAuctionItemInfo
    GetMoney = function() return money end
    GetAuctionItemInfo = function() return "Silverleaf", 0, 20, 1, true, 1, nil, 100, 1, 2000, 0, nil, nil, "x", nil, 0, 765 end
    LG.OnPlaceBid("list", 1, 2000)
    money = 98000
    FireEvent("PLAYER_MONEY")
    assert(ES:HaveForShopping(765) == 70, "compra inmediata en la AH clásica: " .. ES:HaveForShopping(765))
    -- (una puja que no es compra inmediata no cuenta)
    LG.OnPlaceBid("list", 1, 500)
    money = 97500
    FireEvent("PLAYER_MONEY")
    assert(ES:HaveForShopping(765) == 70, "una puja no es una compra")
    GetMoney, GetAuctionItemInfo = savedGM, savedGAI
    -- 3. AH moderna: compra de materiales confirmada
    clock = 300
    LG.pendingCommodity = { itemID = 765, n = 10 }
    FireEvent("COMMODITY_PURCHASE_SUCCEEDED")
    assert(ES:HaveForShopping(765) == 80, "compra de materiales en la AH moderna: " .. ES:HaveForShopping(765))
    LG.pendingCommodity = { itemID = 765, n = 10 }
    FireEvent("COMMODITY_PURCHASE_FAILED")
    assert(ES:HaveForShopping(765) == 80, "una compra fallida no cuenta")
    -- 4. Fuera de la AH no se lee el chat (mazmorras: textos secretos, error de taint).
    -- Justo tras cerrarla sí (el mensaje puede llegar tarde); pasado el margen, no
    clock = 400
    ES.ahOpen = false
    local savedAHF, savedAF = AuctionHouseFrame, AuctionFrame
    AuctionHouseFrame, AuctionFrame = nil, nil
    FireEvent("AUCTION_HOUSE_CLOSED")
    LG.OnChatLine("You won an auction for [Silverleaf]x5 for 1s 00c", "chat")
    assert(ES:HaveForShopping(765) == 85, "recién cerrada la AH, la compra cuenta: " .. ES:HaveForShopping(765))
    clock = 500
    LG.OnChatLine("You won an auction for [Silverleaf]x7 for 1s 00c", "chat")
    FireEvent("CHAT_MSG_SYSTEM", "You won an auction for [Silverleaf]x7")
    AuctionHouseFrame, AuctionFrame = savedAHF, savedAF
    assert(ES:HaveForShopping(765) == 85, "fuera de la AH el chat no se lee: " .. ES:HaveForShopping(765))
    -- Un texto secreto (issecretvalue) no se toca aunque esté la AH abierta
    ES.ahOpen = true
    local savedSecret = issecretvalue
    issecretvalue = function() return true end
    FireEvent("CHAT_MSG_SYSTEM", "You won an auction for [Silverleaf]x9")
    LG.OnChatLine("You won an auction for [Silverleaf]x9 for 1s 00c", "chat")
    issecretvalue = savedSecret
    assert(ES:HaveForShopping(765) == 85, "un texto secreto no se lee: " .. ES:HaveForShopping(765))
    GetTime = savedGT
  end)
  C_Container, ES.ItemCount, ERR_AUCTION_WON_S, GetInboxNumItems, GetInboxItem, GetItemInfo = saved[1], saved[2], saved[3], saved[4], saved[5], saved[6]
  ES.charData.ahOnWay, NOW, ES.ahOpen, LG.ahClosedAt = saved[7], saved[8], saved[9], nil
  if not ok then error(err, 0) end
end)
-- Con el instructor abierto, el paso de entrenar aprende con un clic lo que toca (y lo
-- de "aprende también"), de uno en uno; solo lo disponible
step("instructor abierto: aprender con un clic", function()
  local LG = ES.Ledger
  local saved = { GetNumTrainerServices, GetTrainerServiceInfo, GetTrainerServiceSkillLine, GetTrainerServiceItemLink,
    BuyTrainerService, C_Timer.After, LG.trainerOpen, ES.Print }
  local ok, err = pcall(function()
    local services = {
      { "Journeyman Alchemist", "available", nil },
      { "Elixir of Wisdom", "available", "spell:3171" },
      { "Swim Speed Potion", "available", "spell:7841" },
      { "Fire Oil", "unavailable", "spell:7837" },
    }
    local bought, printed = {}, nil
    GetNumTrainerServices = function() return #services end
    GetTrainerServiceInfo = function(i) return services[i][1], "", services[i][2] end
    GetTrainerServiceSkillLine = function() return ES:ProfLabel("Alchemy") end
    GetTrainerServiceItemLink = function(i) return services[i][3] end
    BuyTrainerService = function(i) bought[#bought + 1] = services[i][1] end
    C_Timer.After = function(_, fn) fn() end
    ES.Print = function(_, m) printed = m end
    LG.trainerOpen = true
    assert(LG.TrainerOpen(), "instructor abierto")
    assert(LG.TrainerService({ recipeID = 3171 }) == 2, "encuentra Elixir of Wisdom por su hechizo")
    assert(LG.TrainerService({ rank = 150 }) == 1, "encuentra el rango Oficial (Journeyman)")
    assert(LG.TrainerService({ recipeID = 7837 }) == nil, "lo que aún no está disponible no se aprende")
    local n = LG.LearnAtTrainer({ { rank = 150 }, { recipeID = 3171 }, { recipeID = 7837 } })
    assert(n == 2 and bought[1] == "Journeyman Alchemist" and bought[2] == "Elixir of Wisdom" and #bought == 2,
      "aprende el rango y la receta (no lo no disponible): " .. table.concat(bought, ", "))
    bought = {}
    assert(LG.LearnAtTrainer({ { recipeID = 7837 } }) == 0 and #bought == 0 and printed, "nada que aprender: lo dice")
    -- Captura del 2026-11-17: en Forever no lo encontraba. Con otro tipo de servicio que
    -- "available" y sin saber la profesión del instructor, también lo encuentra
    GetTrainerServiceInfo = function(i) return services[i][1], "", (i == 4 and "unavailable" or nil) end
    GetTrainerServiceSkillLine = function() return nil end
    assert(LG.TrainerService({ recipeID = 3171 }) == 2, "sin el tipo 'available' ni la profesión, encuentra Elixir of Wisdom")
    assert(LG.TrainerService({ recipeID = 7837 }) == nil, "lo no disponible sigue sin tocarse")
    LG.trainerOpen = nil
    assert(not LG.TrainerOpen(), "instructor cerrado")
  end)
  GetNumTrainerServices, GetTrainerServiceInfo, GetTrainerServiceSkillLine, GetTrainerServiceItemLink = saved[1], saved[2], saved[3], saved[4]
  BuyTrainerService, C_Timer.After, LG.trainerOpen, ES.Print = saved[5], saved[6], saved[7], saved[8]
  if not ok then error(err, 0) end
end)
-- Un material que la ruta compra en los dos sitios (4 Crystal Vial en la AH, más baratos,
-- y 40 al vendedor): se compra donde va la mayor parte. Antes ganaba la AH (Discord)
step("ruta: material en la AH y en el vendedor, donde va la mayor parte", function()
  local plan = { shopping = {
    { itemID = 8925, quantity = 40, source = "vendor", unit = 500, total = 20000 },
    { itemID = 8925, quantity = 4, source = "ah", unit = 449, total = 1796 },
    { itemID = 3820, quantity = 12, source = "ah", unit = 213, total = 2556 },
  } }
  local e = ES.Planner.ShoppingSource(plan, 8925)
  assert(e and e.source == "vendor" and e.quantity == 40, "Crystal Vial: al vendedor")
  e = ES.Planner.ShoppingSource(plan, 3820)
  assert(e and e.source == "ah", "lo que solo está en la AH, en la AH")
  assert(ES.Planner.ShoppingSource(plan, 1) == nil, "lo que no compra la ruta: nada")
end)
-- Lo que sobra de un paso acabado (Planner.Leftover): fabricarlo solo si deja más que
-- venderlo con la cuenta de la ruta (los puntos que ahorra a lo que los pagaba la ruta)
step("ruta: gastar lo que sobra solo si compensa", function()
  local PL = ES.Planner
  local saved = { ES.ItemCount, ES.IsRecipeKnown, ES.HaveForShopping, ES.VendorSellPrice, ES.Market.FairPrice }
  local bags = {}
  ES.ItemCount = function(_, id) return bags[id] or 0 end
  ES.HaveForShopping = function(_, id) return bags[id] or 0 end
  ES.IsRecipeKnown = function() return true end
  ES.VendorSellPrice = function() return 0 end
  ES.Market.FairPrice = function() return nil end -- (sin AH: se vende al vendedor por 0)
  local ok, err = pcall(function()
    -- Paso 1 (100-105): receta A (1 hierba + 1 vial). Paso 2 (105-115): receta B (1 flor + 1 vial)
    local A = { id = 901, name = "A", t = { 1, 100, 110, 120 }, r = { { 1, 1 }, { 3, 1 } }, out = { 11, 1 } }
    local B = { id = 902, name = "B", t = { 1, 105, 115, 125 }, r = { { 2, 1 }, { 3, 1 } }, out = { 12, 1 } }
    local plan = { from = 100, to = 115, reached = 115, choice = {}, pointNeed = {}, pointChance = {}, pointNet = {},
      steps = { { id = 901, recipe = A, from = 100, to = 105 }, { id = 902, recipe = B, from = 105, to = 115 } },
      ctx = { data = { recipes = { [901] = A, [902] = B } }, prices = { [3] = { minUnit = 10 } }, opts = {} } }
    for s = 100, 114 do
      local id = s < 105 and 901 or 902
      plan.choice[s], plan.pointChance[s] = id, 1
      plan.pointNeed[s] = { [s < 105 and 1 or 2] = 1, [3] = 1 }
      plan.pointNet[s] = 500 -- (cada punto de B le cuesta a la ruta 5s)
    end
    -- A 105 te sobran 3 hierbas; los 10 viales los pide B: se reponen a 10c cada uno
    bags = { [1] = 3, [3] = 10, [2] = 10 }
    local lo = PL.Leftover(plan, 105, 300)
    assert(lo and lo.id == 901 and lo.crafts == 3, "3 hierbas de sobra y B cuesta 5s el punto: fabricar 3 A: " .. tostring(lo and lo.crafts))
    assert(math.abs(lo.matValue - 30) < 1e-6, "los viales que pide B, a lo que cuesta reponerlos: " .. tostring(lo.matValue))
    -- Si la receta siguiente es barata (cada punto de B cuesta 5c), no compensa
    for s = 105, 114 do plan.pointNet[s] = 5 end
    assert(PL.Leftover(plan, 105, 300) == nil, "con B casi gratis, mejor no gastarlo")
    -- Si B da dinero (punto negativo), tampoco: la ruta saldría más cara
    for s = 105, 114 do plan.pointNet[s] = -200 end
    assert(PL.Leftover(plan, 105, 300) == nil, "con B dando beneficio, no se proponen")
    for s = 105, 114 do plan.pointNet[s] = 500 end
    -- Sin nada que sobre de verdad (las hierbas las pide la ruta... aquí, nada en las bolsas): nada
    bags = { [3] = 13, [2] = 10 }
    assert(PL.Leftover(plan, 105, 300) == nil, "sin hierbas de sobra no hay nada que gastar")
    -- Gris (A ya no da puntos a 120) o en tu tope: nada
    bags = { [1] = 3, [3] = 13, [2] = 10 }
    assert(PL.Leftover(plan, 105, 105) == nil, "en tu tope no suben puntos")
  end)
  ES.ItemCount, ES.IsRecipeKnown, ES.HaveForShopping, ES.VendorSellPrice, ES.Market.FairPrice = unpack(saved)
  assert(ok, err)
end)
-- Vendedor e instructor en el mismo viaje (captura del 2026-11-17: mandaba a un
-- vendedor junto a la AH habiendo uno al lado del instructor): el de al lado del
-- instructor, y el orden AH -> buzón -> instructor -> vendedor -> fabricar
step("ruta: vendedor junto al instructor en el mismo viaje", function()
  local WP = ES.Waypoints
  local saved = { WP.NPC, C_Map, CreateVector2D, WP.Vendors, UnitFactionGroup }
  local ok, err = pcall(function()
    local spots = { [1] = { 100, 100 }, [2] = { 0, 0 }, [3] = { 98, 101 } } -- 1 instructor, 2 vendedor (AH), 3 vendedor (instructor)
    WP.NPC = function(id) local s = spots[id] return s and { id = id, name = "PNJ " .. id, side = "", map = 1455, x = s[1], y = s[2] } end
    CreateVector2D = function(x, y) return { x = x, y = y } end
    C_Map = { GetWorldPosFromMapPos = function(map, v) return 0, { GetXY = function() return v.x, v.y end } end }
    UnitFactionGroup = function() return "Alliance" end
    assert(WP.NearestTo({ 2, 3 }, 1) == 3, "el vendedor más cercano al instructor, no a ti")
    WP.Vendors = function() return { 2, 3 } end
    local lines = {
      { level = "63", title = "Compra en la AH", buyRow = "ah", current = true },
      { level = "63", title = "Compra al vendedor", buyRow = "vendor", buyItems = { { itemID = 3371 } } },
      { level = "63", title = "Recoge el correo", mailRow = true },
      { level = "63", title = "Train Journeyman", rankCap = 150, go = function() return 1 end },
      { level = "63-104", title = "Rage Potion", stepRecipe = 6617 },
    }
    ES.UI.ArrangeTrip(lines, 63)
    local order = {}
    for _, l in ipairs(lines) do order[#order + 1] = l.title end
    assert(lines[1].buyRow == "ah" and lines[2].mailRow and lines[3].rankCap and lines[4].buyRow == "vendor" and lines[5].stepRecipe,
      "orden AH, buzón, instructor, vendedor, fabricar: " .. table.concat(order, " / "))
    assert(lines[4].nearTrainer and lines[4].go() == 3, "el vendedor, el de al lado del instructor")
    -- Varios materiales: el que vende más de ellos (aunque esté más lejos del instructor)
    WP.Vendors = function(id) if id == 3371 then return { 2, 3 } end return { 2 } end
    assert(WP.VendorFor({ 3371, 3372 }, 1) == 2, "el que vende los dos materiales de la fila")
    -- El que está al lado del instructor no lo tenía al abrirlo: a otro de la lista
    WP.Vendors = function() return { 2, 3 } end
    WP.MarkVendorLacks(3, 3371)
    assert(WP.VendorFor({ 3371 }, 1) == 2, "si el de al lado no lo tenía, a otro vendedor")
    WP.vendorLacks = {}
    -- Lejos del instructor (más de 100 yardas): no cuenta como "al lado"; el más cercano a ti
    spots[3] = { 400, 400 }
    local savedNearest = WP.Nearest
    WP.Nearest = function(list) return list[1] end
    assert(WP.VendorFor({ 3371 }, 1) == 2, "sin vendedor al lado del instructor, el más cercano a ti")
    WP.Nearest = savedNearest
    spots[3] = { 98, 101 }
    assert(lines[1].current, "primero la AH")
    -- Comprado lo de la AH: el siguiente recado pendiente es el actual (el buzón)
    lines[1].done, lines[1].current = true, nil
    lines[2].current = true -- (lo que dejaron los pasos de antes)
    lines[3].current = nil
    ES.UI.ArrangeTrip(lines, 63)
    assert(lines[2].current and not lines[3].current, "tras la AH, el buzón")
    -- Buzón y vendedor pendientes (sin instructor de por medio): al más cercano primero
    -- (Discord: con el buzón delante, te mandaba al vendedor)
    local savedDist = WP.DistanceTo
    local dist = { [50] = 10, [60] = 9000 } -- 50: buzón, 60: vendedor
    WP.DistanceTo = function(id) return dist[id] or math.huge end
    local trip = {
      { level = "99", title = "Compra al vendedor", buyRow = "vendor", buyItems = { { itemID = 2604 } }, go = function() return 60 end, current = true },
      { level = "99", title = "Recoge el correo", mailRow = true, go = function() return 50 end },
      { level = "99-110", title = "Red Linen Bag", stepRecipe = 6686 },
    }
    ES.UI.ArrangeTrip(trip, 99)
    assert(trip[2].current and not trip[1].current, "el buzón delante: primero el buzón")
    trip[1].current, trip[2].current = true, nil
    dist[50], dist[60] = 9000, 10
    ES.UI.ArrangeTrip(trip, 99)
    assert(trip[1].current and not trip[2].current, "el vendedor delante: primero el vendedor")
    WP.DistanceTo = savedDist
  end)
  WP.NPC, C_Map, CreateVector2D, WP.Vendors, UnitFactionGroup = saved[1], saved[2], saved[3], saved[4], saved[5]
  if not ok then error(err, 0) end
end)
-- Recetas en la ruta: comprada en la AH (detectada al comprar, sin mirar el correo), el
-- paso queda hecho y el de fabricar recuerda aprenderla; y "Saltar" también en ellas
step("ruta: receta comprada y saltar una receta", function()
  local Arrange = ES.UI.ArrangeRecipeErrands
  ES.routeSkips.TestProf = nil
  local function Lines(bought)
    return {
      { level = "1", title = "hecho", done = true },
      { level = "63", title = "Receta", recipeName = "Rage Potion", bought = bought or nil, current = true },
      { level = "63", title = "Compra 44× Briarthorn", buyRow = "ah" },
      { level = "63", title = "Train Journeyman", rankCap = 150 },
      { level = "63-104", title = "Rage Potion", stepRecipe = 6617, sub = "44 crafts" },
    }
  end
  -- Comprada: hecho, y el paso de fabricar recuerda aprenderla (sin hablar del correo)
  local l = Lines(true)
  Arrange(l, "TestProf")
  assert(l[2].done and not l[2].current, "receta comprada: el paso queda hecho")
  assert(l[5].learnFirst == "Rage Potion" and tostring(l[5].sub):find("Rage Potion"), "el paso de fabricar recuerda aprenderla")
  -- Saltar una receta: queda como hecha; Recuperar la devuelve
  l = Lines(false)
  Arrange(l, "TestProf")
  assert(l[2].markHave, "el paso de receta debería poder saltarse")
  l[2].markHave()
  l = Lines(false)
  Arrange(l, "TestProf")
  assert(l[2].done and l[2].skipped and not l[2].current and l[2].unmarkHave, "saltada, la receta queda como hecha")
  l[2].unmarkHave()
  l = Lines(false)
  Arrange(l, "TestProf")
  assert(not l[2].done and l[2].current, "recuperada, vuelve a ser el paso")
  ES.routeSkips.TestProf = nil
end)
-- Una compra hecha (el paso actual de comprar desaparece): la misma animación que un
-- paso hecho (✓ y 1 s antes del siguiente). Comprar una parte, cambiar de modo o saltarla, no
step("asistente: comprar celebra el paso", function()
  local A = ES.Assistant
  local saved = { ES.RouteLock, ES.RouteLines, ES.GetProfessionSkill, ES.db.prof, A.CELEBRATE_HOLD, C_Timer.After }
  local lock = { from = 1, to = 150, started = 999 }
  ES.db.prof = { Alchemy = {} }
  ES.RouteLock = function(_, k) return k == "Alchemy" and lock or nil end
  ES.GetProfessionSkill = function() return 63, 75 end
  local qty, bought, skipped = 21, false, false
  local craft = { level = "63-104", title = "Rage Potion", stepRecipe = 6617, icon = 134400 }
  ES.RouteLines = function()
    local buy = { level = "63", title = "Compra " .. qty .. "× Silverleaf", buyRow = "ah", buyItems = { { itemID = 765 } }, icon = 134400 }
    if skipped then buy.done, buy.skipped = true, true end
    if bought then return { craft, { total = true } } end
    buy.current = not skipped or nil
    craft.current = skipped or nil
    return { buy, craft, { total = true } }
  end
  A.CELEBRATE_HOLD = 1
  C_Timer.After = function() end
  local ok, err = pcall(function()
    local st = A.State()
    st.hold = nil
    A.Update()
    A.Update()
    assert(not st.celebrated, "sin cambios no se celebra")
    qty = 10 -- (compraste una parte: sigue pendiente)
    A.Update()
    assert(not st.celebrated, "comprar una parte no es acabar el paso")
    bought = true -- (comprado todo: la fila desaparece)
    A.Update()
    assert(st.celebrated and st.hold, "acabar la compra debería celebrarse como un paso hecho")
    A.EndHold()
    -- Saltarla no se celebra
    bought, skipped, qty = false, false, 21
    st.hold = nil
    A.Update()
    skipped = true
    A.Update()
    assert(not st.celebrated, "saltar la compra no se celebra")
    -- Dos compras en la AH: hecha la primera, la siguiente es el paso actual (antes no se
    -- celebraba: el avance solo contaba los pasos de fabricar y aprender)
    local firstDone = false
    ES.RouteLines = function()
      local a = { level = "63", title = "Compra 21× Silverleaf", buyRow = "ah", buyItems = { { itemID = 765 } }, icon = 134400 }
      local b = { level = "63", title = "Compra 44× Briarthorn", buyRow = "ah", buyItems = { { itemID = 2450 } }, icon = 134400 }
      if firstDone then b.current = true return { b, craft, { total = true } } end
      a.current = true
      craft.current = nil
      return { a, b, craft, { total = true } }
    end
    st.hold = nil
    A.Update()
    firstDone = true
    A.Update()
    assert(st.celebrated, "hecha una compra de varias, se celebra aunque quede otra")
    A.EndHold()
  end)
  ES.RouteLock, ES.RouteLines, ES.GetProfessionSkill, ES.db.prof, A.CELEBRATE_HOLD, C_Timer.After =
    saved[1], saved[2], saved[3], saved[4], saved[5], saved[6]
  local st = A.State()
  st.hold = nil
  A.Update()
  if not ok then error(err, 0) end
end)
-- "Saltar": una pestaña como la de las flechas, abajo a la izquierda, que solo se
-- despliega en los pasos de compra; su clic los da por comprados
step("asistente: pestaña Saltar en los pasos de compra", function()
  local A = ES.Assistant
  local saved = { ES.RouteLock, ES.RouteLines, ES.GetProfessionSkill, ES.db.prof, ES.db.assistant.stepsAlways }
  local marked = 0
  ES.db.prof = { Alchemy = {} }
  local lock = { from = 1, to = 150, started = 888 }
  local buyStep = true
  ES.RouteLock = function(_, k) return k == "Alchemy" and lock or nil end
  ES.RouteLines = function() return {
    buyStep and { level = "1", title = "Compra 21× Silverleaf", buyRow = "ah", current = true, icon = 134400,
      markHave = function() marked = marked + 1 buyStep = false end } or
      { level = "1", title = "Compra 21× Silverleaf", buyRow = "ah", done = true, skipped = true, icon = 134400,
        unmarkHave = function() marked = marked - 1 buyStep = true end },
    not buyStep and { level = "1", title = "Elixir of Minor Force", stepRecipe = 2329, current = true, icon = 134400 } or nil,
    { total = true, title = "Total" },
  } end
  ES.GetProfessionSkill = function() return 1, 75 end
  ES.db.assistant.stepsAlways = true
  local ok, err = pcall(function()
    A.Update()
    local f = A.Frame()
    assert(f.skipTab and f.skip, "falta la pestaña Saltar")
    assert(f.skipTab.available, "en un paso de compra, Saltar debería estar disponible")
    A.SlideTab(1)
    assert(f.skipTab._shown and (f.skipTab.open or 0) > 0, "Saltar se despliega como las flechas")
    assert(f.skip._text == ES.L["Saltar"], "el botón dice Saltar: " .. tostring(f.skip._text))
    f.skip._scripts.OnClick(f.skip)
    assert(marked == 1, "Saltar debería dar la compra por hecha")
    assert(not f.skipTab.available, "en un paso de fabricar no hay Saltar")
    -- Recuperar: con la flecha de paso anterior al saltado, la pestaña dice Recuperar
    local st = A.State()
    f.arrows.prev._scripts.OnClick(f.arrows.prev)
    assert(st.peek == 1 and f.skipTab.available and f.skipTab.undo, "ojeando el saltado, se puede recuperar")
    assert(f.skip._text == ES.L["Recuperar"], "el botón dice Recuperar: " .. tostring(f.skip._text))
    f.skip._scripts.OnClick(f.skip)
    assert(marked == 0 and st.peek == nil and f.skipTab.available and not f.skipTab.undo,
      "recuperado: vuelve el paso de compra y el botón Saltar")
    assert(f.skip._text == ES.L["Saltar"], "de nuevo Saltar")
    -- Sin menú del clic derecho (la UI es fija): el banner solo atiende al izquierdo
    assert(A.Menu == nil and A.RefreshMenu == nil, "el menú del clic derecho se quitó")
    A.ToggleBuyMode()
    assert(ES.db.prof.Alchemy.byPhase == false, "cambiar el modo: la lista a la ruta entera")
    A.ToggleBuyMode()
    assert(ES.db.prof.Alchemy.byPhase == nil, "y de vuelta a por tramos")
    -- Pestaña de arriba: [modo] [?] [X], se despliega con las demás
    assert(f.topTab and f.mode and f.help and f.close, "falta la pestaña de arriba con el modo, ? y la X")
    A.SlideTab(1)
    assert(f.topTab._shown and (f.topTab.open or 0) > 0, "la pestaña de arriba se despliega como las demás")
    -- Selector [Tramo | Ruta]: encendida la del modo de ahora
    local seg = f.mode
    assert(seg.stage.active and not seg.route.active, "por tramos: encendida Tramo")
    assert(seg.stage.iconPath:find("Bag") and seg.route.iconPath:find("Crate") and not seg.stage.text,
      "el selector son iconos (bolsa y caja), sin texto que traducir")
    seg.stage._scripts.OnClick(seg.stage) -- (la encendida no cambia nada)
    assert(ES.db.prof.Alchemy.byPhase == nil, "pulsar la parte encendida no cambia el modo")
    seg.route._scripts.OnClick(seg.route)
    assert(ES.db.prof.Alchemy.byPhase == false and seg.route.active and not seg.stage.active, "Ruta: cambia a la ruta entera")
    seg.stage._scripts.OnClick(seg.stage)
    assert(ES.db.prof.Alchemy.byPhase == nil and seg.stage.active, "Tramo: vuelve a por tramos")
    assert(f.help.icon and f.help.icon:find("ActiveQuestIcon"), "la ayuda es el icono ? amarillo, no un botón")
    -- Clic en ?: la ventana de ayuda, con sus temas; otro clic la cierra
    f.help._scripts.OnClick(f.help)
    local hf = A.HelpFrame()
    assert(hf and hf._shown and #hf.topics == 7, "el ? abre la ayuda con sus temas")
    for i, t in ipairs(hf.topics) do
      assert(hf.lines[i].title._text == t.title and t.text ~= "", "tema de la ayuda sin texto: " .. tostring(t.title))
    end
    f.help._scripts.OnClick(f.help)
    assert(not hf._shown, "otro clic en ? cierra la ayuda")
    -- Entre ? y la X: abre la ruta en la ventana (antes, el engranaje de opciones)
    assert(f.window and not f.gear, "falta el botón de la ventana (en lugar del engranaje)")
    local savedShow, shown = ES.ShowMainFrame, nil
    ES.ShowMainFrame = function(_, page) shown = page end
    f.window._scripts.OnClick(f.window)
    ES.ShowMainFrame = savedShow
    assert(shown == "Alchemy" and ES.db.prof.Alchemy.view == "route", "debería abrir la ruta de la profesión: " .. tostring(shown))
    -- Abierta desde el asistente, la lista baja hasta el paso actual
    local scrolled
    local fake = { rows = {}, content = CreateFrame("Frame"), scrollToCurrent = true,
      scroll = setmetatable({ SetVerticalScroll = function(_, v) scrolled = v end, GetHeight = function() return 100 end,
        GetWidth = function() return 600 end }, { __index = function() return function() end end }) }
    local fl = {}
    for i = 1, 12 do fl[i] = { level = tostring(i), title = "Paso " .. i, current = i == 9 } end
    ES.UI.RenderLines(fake, fl)
    assert(scrolled and scrolled > 0 and not fake.scrollToCurrent, "debería bajar hasta el paso actual: " .. tostring(scrolled))
    -- Sin nada que saltar ni recuperar, la pestaña se pliega
    buyStep = false
    ES.RouteLines = function() return {
      { level = "1", title = "Elixir of Minor Force", stepRecipe = 2329, current = true, icon = 134400 },
      { total = true, title = "Total" },
    } end
    A.Update()
    A.SlideTab(1)
    assert(f.skipTab._shown == false, "sin nada que saltar, la pestaña se pliega")
  end)
  ES.RouteLock, ES.RouteLines, ES.GetProfessionSkill, ES.db.prof, ES.db.assistant.stepsAlways = saved[1], saved[2], saved[3], saved[4], saved[5]
  A.Update()
  if not ok then error(err, 0) end
end)
-- Un solo sistema de navegación (WP.Mark): la ventana y el asistente marcan el destino
-- igual (Shortest Path, si no TomTom, si no el punto de ruta del juego). El asistente lo
-- marca solo a cada paso, una vez por destino; pulsar un PNJ en la ventana cambia
-- también la flecha; el destino propio del minimapa, solo si no se pudo marcar
step("navegación unificada: ventana y asistente marcan igual", function()
  local A, WP = ES.Assistant, ES.Waypoints
  local saved = { ES.RouteLock, ES.RouteLines, ES.GetProfessionSkill, ES.db.prof, WP.NPC,
    ShortestPathForever, TomTom, C_Map, UiMapPoint, C_SuperTrack, ES.Print }
  local sp, tt, removed, game, chat, target = {}, {}, {}, {}, {}, 7001
  ShortestPathForever = { API = { version = 1, Navigate = function(src, map, x, y, name)
    sp[#sp + 1] = name return true end } }
  WP.NPC = function(id) return { id = id, map = 1455, x = 0.5, y = 0.5, name = "PNJ " .. id } end
  ES.Print = function(_, msg) chat[#chat + 1] = msg end
  ES.db.prof = { Alchemy = {} }
  local lock = { from = 1, to = 150, started = 777 }
  ES.RouteLock = function(_, k) return k == "Alchemy" and lock or nil end
  ES.RouteLines = function() return {
    -- (títulos de verdad: el asistente no cuenta los números al ver si es otro paso, A.LineKey)
    { level = "1", title = "Aprender " .. (({ "Fire Oil", "Shadow Oil", "Frost Oil", "Elixir of Wisdom", "Rage Potion", "Swiftness Potion", "Mana Potion", "Healing Potion" })[(target or 0) - 7000] or ("PNJ " .. tostring(target))),
      go = function() return target end, current = true, icon = 134400 },
    { total = true, title = "Total" },
  } end
  ES.GetProfessionSkill = function() return 1, 75 end
  local ok, err = pcall(function()
    local st = A.State()
    A.Update()
    assert(#sp == 1 and sp[1] == "PNJ 7001", "al empezar el paso debería marcarlo con Shortest Path: " .. #sp)
    assert(st.pathHow == "shortestpath" and #chat == 0, "el asistente marca sin escribir en el chat")
    A.Update()
    assert(#sp == 1, "el mismo destino no se vuelve a marcar")
    target = 7002
    A.Update()
    assert(#sp == 2 and sp[2] == "PNJ 7002", "paso nuevo, destino nuevo")
    -- Pulsar otro PNJ en la ventana: se marca (con chat) y la flecha pasa a él
    assert(WP.SetWaypoint(7100) and sp[3] == "PNJ 7100" and #chat == 1, "la ventana marca con el mismo sistema")
    assert(st.navNpc == 7100, "pulsar en la ventana cambia también el destino de la flecha")
    A.Update()
    assert(#sp == 3 and st.navNpc == 7100, "mientras dura el paso, sigue el PNJ pulsado")
    -- Sin Shortest Path: TomTom, quitando el punto anterior (no se acumulan)
    ShortestPathForever = nil
    local uid = 0
    TomTom = { AddWaypoint = function(_, map, x, y, o) uid = uid + 1 tt[#tt + 1] = o.title return uid end,
      RemoveWaypoint = function(_, u) removed[#removed + 1] = u end }
    target = 7003
    A.Update()
    assert(#tt == 1 and st.pathHow == "tomtom", "sin Shortest Path, TomTom")
    target = 7004
    A.Update()
    assert(#tt == 2 and removed[1] == 1, "el punto anterior de TomTom se quita al cambiar de destino")
    -- Sin ninguno de los dos: el punto de ruta del juego
    TomTom = nil
    C_Map = { CanSetUserWaypointOnMap = function() return true end, SetUserWaypoint = function(p) game[#game + 1] = p end }
    UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { m, x, y } end }
    C_SuperTrack = { SetSuperTrackedUserWaypoint = function() end }
    target = 7005
    A.Update()
    assert(#game == 1 and st.pathHow == "game", "sin addons, el punto de ruta del juego")
    -- Nada con que marcar: el destino propio en el minimapa hace de respaldo
    C_Map = nil
    target = 7006
    A.Update()
    assert(st.pathHow == nil, "sin nada con que marcar, pathHow vacío (sale el del minimapa)")
    -- Siempre marca (ya no hay opción), aunque quede un noMark guardado de antes
    ShortestPathForever = { API = { version = 1, Navigate = function(src, map, x, y, name) sp[#sp + 1] = name return true end } }
    ES.db.assistant.noMark = true
    local before = #sp
    target = 7007
    A.Update()
    assert(#sp == before + 1, "debería marcar el destino aunque haya un noMark antiguo")
    ES.db.assistant.noMark = nil
    -- Versiones nuevas de la API de Shortest Path Forever también valen (GitHub PR #5)
    ShortestPathForever.API.version = 2
    before = #sp
    target = 7009
    A.Update()
    assert(#sp == before + 1 and st.pathHow == "shortestpath", "con la API versión 2 debería seguir marcando con Shortest Path")
    -- Una versión que no es un número no se acepta
    ShortestPathForever.API.version = "2"
    before = #sp
    WP.SetWaypoint(7101)
    assert(#sp == before, "una versión que no es un número no debería usarse")
    -- Paso nuevo sin encontrar a dónde ir: el camino del paso anterior se quita (Discord:
    -- "Recoge el correo" y el camino seguía al subastador)
    ShortestPathForever = nil
    local removedTT = {}
    TomTom = { AddWaypoint = function() return 42 end, RemoveWaypoint = function(_, u) removedTT[#removedTT + 1] = u end }
    target = 7008
    A.Update()
    assert(st.pathHow == "tomtom", "marcado con TomTom")
    target = nil -- (el paso siguiente no encuentra su PNJ)
    A.Update()
    assert(removedTT[#removedTT] == 42 and st.pathNpc == nil, "sin destino, el punto de TomTom del paso anterior se quita")
    -- El mismo paso: no salta de un PNJ a otro, pero si ahora apunta a otro tipo de sitio
    -- (un buzón), la flecha se pone al día sola (Discord: en "Recoge el correo" seguía en
    -- el subastador hasta pulsar la fila)
    local mb = ES.Data.Mailboxes and ES.Data.Mailboxes[1]
    if mb then
      -- (la fila del correo con el destino de antes, el subastador: como al cambiar de paso
      -- en el mismo instante en que aún apuntaba allí)
      local goID = mb
      ES.RouteLines = function() return {
        { level = "1", title = "Recoge el correo", mailRow = true, go = function() return goID end, current = true, icon = 134400 },
        { total = true, title = "Total" },
      } end
      A.Update()
      st.navNpc = 7001 -- (se quedó con el subastador)
      A.Update()
      assert(st.navNpc == mb, "el paso del correo con la flecha en un PNJ: se pone al día sola en el buzón")
      local other = ES.Data.Mailboxes[2]
      if other then
        goID = other
        A.Update()
        assert(st.navNpc == mb, "el mismo paso con otro buzón cerca: no salta")
      end
    end
  end)
  ES.RouteLock, ES.RouteLines, ES.GetProfessionSkill, ES.db.prof, WP.NPC = saved[1], saved[2], saved[3], saved[4], saved[5]
  ShortestPathForever, TomTom, C_Map, UiMapPoint, C_SuperTrack, ES.Print = saved[6], saved[7], saved[8], saved[9], saved[10], saved[11]
  A.Update()
  if not ok then error(err, 0) end
end)
step("métodos de marcos que existen en el juego", function()
  local REAL = {}
  for name in ([[
    AddDoubleLine AddLine ClearAllPoints ClearFocus CreateAnimation CreateAnimationGroup
    CreateFontString CreateTexture EnableMouse EnableMouseWheel GetFontString GetFrameStrata
    GetNormalTexture GetParent GetPushedTexture GetStringHeight GetVerticalScroll
    GetVerticalScrollRange HasFocus HighlightText HookScript IsMouseOver LockHighlight Play
    RegisterForClicks RegisterForDrag SetAllPoints SetAlpha SetAtlas SetAutoFocus SetBackdrop
    SetBackdropBorderColor SetBackdropColor SetBlendMode SetClampedToScreen SetColorTexture
    SetDesaturated SetDisabledTexture SetDuration SetEnabled SetFocus SetFont SetFontObject
    SetFrameLevel SetFrameStrata SetFromAlpha SetGradient SetHeight SetHighlightTexture
    SetHyperlink SetItemByID SetJustifyH SetJustifyV SetLooping SetMaxLetters SetMinMaxValues
    SetMotionScriptsWhileDisabled SetMouseClickEnabled SetMovable SetNormalTexture SetNumeric
    SetObeyStepOnDrag SetOrder SetOrientation SetOwner SetPoint SetPropagateMouseClicks
    SetPushedTexture SetScrollChild SetShadowOffset SetSize SetSpacing SetStatusBarColor
    SetStatusBarTexture SetTexCoord SetTextColor SetTexture SetThumbTexture SetToAlpha SetValue
    SetValueStep SetVertexColor SetVerticalScroll SetWidth SetWordWrap StartMoving Stop
    StopMovingOrSizing UnlockHighlight UnregisterAllEvents UpdateScrollChildRect
    SetGradientAlpha SetRotation CreateMaskTexture AddMaskTexture SetMaxLines SetToplevel GetZoom
    SetClampRectInsets GetRight RegisterUnitEvent GetChildren IsProtected
  ]]):gmatch("%a+") do REAL[name] = true end
  -- (SetGradientAlpha ya no existe en el cliente, pero solo se usa protegida con
  -- "elseif tex.SetGradientAlpha" para clientes viejos: HomeUI.lua. SetMaxLines, igual:
  -- "if fs.SetMaxLines then", EarnUI.lua)
  local unknown = {}
  for k in pairs(MOCK_METHODS) do if not REAL[k] then unknown[#unknown + 1] = k end end
  table.sort(unknown)
  assert(#unknown == 0, "métodos que no están en la lista de la API del juego: " .. table.concat(unknown, ", "))
end)

return table.concat(log, "\n")
""")
print(out)

# Caracteres que la fuente de WoW no tiene (salen como ▯): ✕, →, ←, − (menos
# tipográfico)... En los textos del addon, solo ASCII, Latin-1 y los de Windows-1252
# que sí dibuja (…, comillas tipográficas, guiones largos y la œ de los nombres
# franceses del juego, como "cœur"). Los comentarios no cuentan
ALLOWED_EXTRA = set("…’‘“”–—€œŒ")
# El cirílico (U+0400-U+04FF), solo en lo del ruso: sus textos y nombres, que se leen con
# el cliente en ruRU (su fuente sí lo dibuja), y el nombre del idioma en Locale.lua
CYRILLIC_FILES = {"Locales/ruRU.lua", "Data/Names_ruRU.lua", "Locale.lua"}


def allowed(ch, rel):
    return ch in ALLOWED_EXTRA or (rel in CYRILLIC_FILES and 0x0400 <= ord(ch) <= 0x04FF)


TOKEN = re.compile(r'--\[(=*)\[.*?\]\1\]|--[^\n]*|\[(=*)\[.*?\]\2\]|"(?:[^"\\\n]|\\.)*"|\'(?:[^\'\\\n]|\\.)*\'', re.S)
bad = []
for f in sorted(ADDON.rglob("*.lua")):
    text = f.read_text(encoding="utf-8")
    rel = f.relative_to(ADDON).as_posix()
    for m in TOKEN.finditer(text):
        tok = m.group(0)
        if tok.startswith("--"):
            continue
        for ch in tok:
            if ord(ch) > 0xFF and not allowed(ch, rel):
                line = text.count("\n", 0, m.start()) + 1
                bad.append(f"{f.relative_to(ADDON)}:{line}: {ch!r} (U+{ord(ch):04X})")
                break
print(("FAIL caracteres sin glifo en la fuente de WoW:\n  " + "\n  ".join(bad[:20])) if bad
      else "OK   textos sin caracteres que la fuente de WoW no dibuja")

# Código de salida: 1 si algún paso ha fallado (para tools/run_tests.py)
if bad or any(l.startswith("FAIL") for l in str(out).splitlines()):
    sys.exit(1)


