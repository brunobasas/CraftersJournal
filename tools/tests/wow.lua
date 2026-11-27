-- API de WoW simulada para las pruebas por categoría (tools/run_tests.py).
-- Junta la de tools/test_ui.py (marcos, atributos, MOCK_METHODS) y la de
-- tools/harness.py (eventos registrados, C_Timer con cola, AH clásica, tooltip,
-- bolsas y hechizos). Lo justo para que el código del addon corra y se pueda leer
-- lo que pinta: no hay tamaños, posiciones ni botones seguros reales.

NOW = 2000000 -- hora fija: las pruebas dan lo mismo cada vez
time = function() return math.floor(NOW) end
GetTime = function() return NOW end
debugprofilestop = function() return 0 end

bit = bit or { band = function(a, b) local r, p = 0, 1 while a > 0 and b > 0 do if a % 2 == 1 and b % 2 == 1 then r = r + p end a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2 end return r end }

PRINTS = {}
print = function(...)
  local t = {}
  for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end
  PRINTS[#PRINTS + 1] = table.concat(t, " ")
end

-- Marcos ---------------------------------------------------------------------
FRAMES = {}       -- marco -> true (los que tienen eventos registrados)
EVENT_ORDER = {}  -- eventos en el orden en que se registraron (para lanzarlos todos)
MOCK_METHODS = {} -- métodos de marcos que el addon ha llamado sin simulación propia
TOOLTIP = {}      -- líneas añadidas a cualquier tooltip
UNKNOWN_EVENTS = { AUCTION_OWNED_LIST_UPDATE = true, REPLICATE_ITEM_LIST_UPDATE = true }

-- Avisa con `script` (OnShow / OnHide) a un marco que acaba de verse o dejar de verse y
-- a los suyos que estaban mostrados (en ese orden, como el juego)
function VisibilityChanged(f, script)
  if f._scripts[script] then f._scripts[script](f) end
  local kids = rawget(f, "_children")
  if not kids then return end
  local copy = {}
  for i, c in ipairs(kids) do copy[i] = c end
  for _, c in ipairs(copy) do
    if c._shown then VisibilityChanged(c, script) end
  end
end

local function Mock(name)
  local m = { _scripts = {}, _events = {}, _name = name, _shown = false }
  return setmetatable(m, { __index = function(t, k)
    if k == "SetScript" then return function(self, n, f) self._scripts[n] = f end end
    if k == "GetScript" then return function(self, n) return self._scripts[n] end end
    if k == "HookScript" then return function(self, n, f)
      local prev = self._scripts[n]
      self._scripts[n] = prev and function(...) prev(...) return f(...) end or f
    end end
    if k == "RegisterEvent" then return function(self, e)
      if UNKNOWN_EVENTS[e] then error('Attempt to register unknown event "' .. e .. '"') end
      if not EVENT_ORDER[e] then EVENT_ORDER[e] = true EVENT_ORDER[#EVENT_ORDER + 1] = e end
      self._events[e] = true
      if self._units then self._units[e] = nil end
      FRAMES[self] = true
    end end
    -- Como en el juego: el evento solo llega si su primer argumento es una de esas unidades
    if k == "RegisterUnitEvent" then return function(self, e, ...)
      self:RegisterEvent(e)
      self._units = self._units or {}
      local units = {}
      for i = 1, select("#", ...) do units[select(i, ...)] = true end
      self._units[e] = units
    end end
    if k == "UnregisterEvent" then return function(self, e)
      self._events[e] = nil
      if self._units then self._units[e] = nil end
    end end
    if k == "UnregisterAllEvents" then return function(self) self._events, self._units = {}, nil end end
    if k == "IsEventRegistered" then return function(self, e) return self._events[e] or false end end
    if k == "GetWidth" or k == "GetHeight" or k == "GetEffectiveScale" or k == "GetStringWidth"
      or k == "GetFrameLevel" or k == "GetLeft" or k == "GetTop" or k == "GetRight" or k == "GetBottom" then
      return function() return 100 end
    end
    if k == "GetScale" then return function(self) return self._scale or 1 end end
    if k == "SetScale" then return function(self, v) self._scale = v end end
    if k == "GetText" then return function(self) return self._text or "" end end
    if k == "SetText" then return function(self, v) self._text = v ~= nil and tostring(v) or nil end end
    if k == "SetFormattedText" then return function(self, f, ...) self._text = string.format(f, ...) end end
    if k == "GetCenter" then return function() return 0, 0 end end
    if k == "SetAttribute" then return function(self, a, v) self._attributes = self._attributes or {} self._attributes[a] = v end end
    if k == "GetAttribute" then return function(self, a) return self._attributes and self._attributes[a] end end
    -- Como en el juego: OnShow / OnHide cuando cambia si se ve (IsVisible), para él y
    -- para los suyos que estaban mostrados (abrir la ventana avisa a la página elegida y
    -- a lo que lleva dentro; mostrar algo dentro de una ventana cerrada no avisa aún)
    if k == "Show" then return function(self)
      local was = self:IsVisible()
      self._shown = true
      if not was and self:IsVisible() then VisibilityChanged(self, "OnShow") end
    end end
    if k == "Hide" then return function(self)
      local was = self:IsVisible()
      self._shown = false
      if was then VisibilityChanged(self, "OnHide") end
    end end
    if k == "SetShown" then return function(self, v) if v then self:Show() else self:Hide() end end end
    if k == "IsShown" then return function(self) return self._shown end end
    -- Como en el juego: visible si él y todos los que lo contienen se ven (una página de
    -- la ventana cerrada no se ve aunque esté elegida)
    if k == "IsVisible" then return function(self)
      local f = self
      while f do
        if not f._shown then return false end
        f = f._parent
      end
      return true
    end end
    if k == "SetEnabled" then return function(self, v) self._enabled = v and true or false end end
    if k == "IsEnabled" then return function(self) return self._enabled ~= false end end
    if k == "GetChecked" then return function(self) return self._checked end end
    if k == "SetChecked" then return function(self, v) self._checked = v and true or false end end
    -- Desplazamiento de un ScrollFrame: se recuerda (como en el juego, no se limita
    -- solo al encoger el contenido). La altura pedida se apunta en _height (GetHeight
    -- sigue devolviendo 100)
    if k == "GetVerticalScroll" then return function(self) return self._vscroll or 0 end end
    if k == "SetVerticalScroll" then return function(self, v)
      self._vscroll = v
      if self._scripts.OnVerticalScroll then self._scripts.OnVerticalScroll(self, v) end
    end end
    if k == "SetHeight" then return function(self, v) self._height = v end end
    if k == "GetValue" then return function(self) return self._value or 0 end end
    if k == "SetValue" then return function(self, v) self._value = v end end
    if k == "AddLine" or k == "AddDoubleLine" then return function(self, a, b)
      TOOLTIP[#TOOLTIP + 1] = tostring(a) .. (type(b) == "string" and (" | " .. b) or "")
    end end
    -- Lo que se crea dentro de un marco sabe quién es su padre (LibDBIcon lo usa)
    if k == "CreateTexture" or k == "CreateFontString" or k == "CreateAnimationGroup" or k == "CreateMaskTexture" then
      return function(self) local c = Mock(k) c._parent = self return c end
    end
    if k == "GetParent" then return function(self) return self._parent end end
    if k == "GetChildren" then return function(self) return unpack(self._children or {}) end end
    -- Como en el juego: un marco seguro (de plantilla Secure...) es protegido, y lo es todo
    -- marco que tenga uno dentro (GitHub #11: la ventana entera quedaba protegida)
    if k == "IsProtected" then return function(self)
      local function protected(f)
        local tpl = rawget(f, "_template")
        if type(tpl) == "string" and tpl:find("Secure") then return true end
        for _, c in ipairs(rawget(f, "_children") or {}) do
          if protected(c) then return true end
        end
        return false
      end
      return protected(self)
    end end
    -- Anclajes: cuántos puntos tiene y a qué marco el último (ClearAllPoints los quita)
    if k == "SetPoint" then return function(self, _, rel)
      self._anchors = (self._anchors or 0) + 1
      if type(rel) == "table" then self._anchorTo = rel end
    end end
    if k == "ClearAllPoints" then return function(self) self._anchors, self._anchorTo = 0, nil end end
    if k == "GetNumPoints" then return function(self) return self._anchors or 0 end end
    if k == "GetName" then return function(self) return self._globalName end end
    -- Como en WoW: solo los métodos (con mayúscula) existen; los campos propios no
    if type(k) ~= "string" or not k:match("^%u") then return nil end
    MOCK_METHODS[k] = true
    return function() return Mock(k) end
  end })
end
MockFrame = Mock

CreateFrame = function(_, name, parent, template)
  local f = Mock("frame")
  f._shown = true -- (como en el juego: un marco nuevo se muestra; se ve si su padre se ve)
  f._parent = parent
  f._template = template -- (la plantilla: IsProtected)
  -- (los hijos, para GetChildren)
  if type(parent) == "table" then
    local kids = rawget(parent, "_children") or {}
    rawset(parent, "_children", kids)
    kids[#kids + 1] = f
  end
  if name then f._globalName = name _G[name] = f end
  return f
end

function FireEvent(e, ...)
  local list = {}
  local unit = ...
  for f in pairs(FRAMES) do
    local units = f._units and f._units[e]
    if f._events[e] and f._scripts.OnEvent and (not units or units[unit]) then list[#list + 1] = f end
  end
  for _, f in ipairs(list) do f._scripts.OnEvent(f, e, ...) end
  return #list
end
GetFramesRegisteredForEvent = function(e)
  local t = {}
  for f in pairs(FRAMES) do if f._events[e] then t[#t + 1] = f end end
  return unpack(t)
end

-- C_Timer con cola: RunTimers() ejecuta lo que toca en los próximos `seconds` (30 por
-- defecto) avanzando la hora, como dejar pasar ese rato en el juego. Lo de más tarde
-- (una cuenta atrás de 15 min...) se queda en la cola
TIMERS = {}
C_Timer = {
  After = function(d, f) TIMERS[#TIMERS + 1] = { at = NOW + (d or 0), f = f } end,
  NewTicker = function(d, f, n)
    local tk = { _cancelled = false }
    function tk:Cancel() self._cancelled = true end
    function tk:IsCancelled() return self._cancelled end
    local left = n or 50 -- (los tickers sin fin se cortan: las pruebas no esperan para siempre)
    local function tick()
      if tk._cancelled or left <= 0 then return end
      left = left - 1
      f(tk)
      C_Timer.After(d, tick)
    end
    C_Timer.After(d, tick)
    return tk
  end,
}
C_Timer.NewTimer = function(d, f) return C_Timer.NewTicker(d, f, 1) end
function RunTimers(seconds)
  local limit = NOW + (seconds or 30)
  local n = 0
  while #TIMERS > 0 and n < 20000 do
    table.sort(TIMERS, function(a, b) return a.at < b.at end)
    if TIMERS[1].at > limit then break end
    local t = table.remove(TIMERS, 1)
    if t.at > NOW then NOW = t.at end
    t.f()
    n = n + 1
  end
  return n
end

-- Jugador, mundo y objetos ---------------------------------------------------
-- Como el cliente de Forever desde el parche del 21/11/2026: no da el reino (vacío, y
-- su número 0) y sí el modo de juego (el ruleset: 14 PvP, 15 Normal). Una prueba de un
-- cliente anterior pone REALM = "Realm" y C_GameRules = nil; GAME_MODE = 0 es un modo
-- que aún no ha llegado (SetGameMode lo cambia y avisa, como el juego)
REALM = ""
GAME_MODE = 14
FACTION = "Alliance"
NPC_FACTION = "Alliance"
GetRealmName = function() return REALM end
GetRealmID = function() return 0 end
GetNativeRealmID = function() return 0 end
C_GameRules = { GetCurrentGameModeRecordID = function() return GAME_MODE end }
function SetGameMode(id)
  GAME_MODE = id
  FireEvent("ACTIVE_GAME_MODE_UPDATED", id)
end
UnitFactionGroup = function(u) if u == "npc" then return NPC_FACTION end return FACTION end
-- El mapa del jugador (C_Map.GetBestMapForUnit) solo para las pruebas que lo piden: sin
-- llamar a esto no hay C_Map, como antes (Waypoints y Assistant se portan distinto con él)
function SetPlayerMap(id)
  C_Map = C_Map or {}
  C_Map.GetBestMapForUnit = function(u) if u == "player" then return id end end
  C_Map.GetPlayerMapPosition = C_Map.GetPlayerMapPosition or function() return nil end
end
UnitExists = function() return true end
UnitName = function() return "Bruno" end
UnitGUID = function(u) if u == "player" then return "Player-1-00000001" end end
UnitLevel = function() return 60 end
GetMoney = function() return MONEY or 0 end

-- Profesiones del personaje: SKILLS[skillLine] = { nivel, tope } (GetProfessions)
SKILLS = {}
GetProfessions = function()
  local t = {}
  for line in pairs(SKILLS) do t[#t + 1] = line end
  table.sort(t)
  return unpack(t)
end
GetProfessionInfo = function(line)
  local s = SKILLS[line]
  if s then return "prof" .. line, nil, s[1], s[2], 0, 0, line end
end

-- Misiones hechas: QUESTS_DONE[questID] = true (C_QuestLog.IsQuestFlaggedCompleted)
QUESTS_DONE = {}
C_QuestLog = { IsQuestFlaggedCompleted = function(id) return QUESTS_DONE[id] == true end }
IsQuestFlaggedCompleted = function(id) return QUESTS_DONE[id] == true end

BAGS = {}          -- [itemID] = cantidad (GetItemCount)
REAGENT_BAG = {}   -- [itemID] = cantidad en la bolsa de componentes (la 5, como en Forever)
KNOWN_SPELLS = {}  -- [spellID] = true (IsPlayerSpell)
Enum = { BagIndex = { ReagentBag = 5 } }
GetItemCount = function(id) return (BAGS[id] or 0) + (REAGENT_BAG[id] or 0) end
IsPlayerSpell = function(id) return KNOWN_SPELLS[id] or false end
-- Objetos: como un cliente con todo en caché (nombre en inglés de los datos y precio
-- de venta al vendedor). ITEM_INFO[id] = { name =, sell = } cambia uno;
-- UNCACHED[id] = true hace que el juego aún no lo tenga (devuelve nil)
ITEM_INFO, UNCACHED = {}, {}
GetItemInfo = function(id)
  if type(id) ~= "number" or UNCACHED[id] then return nil end
  local i = ITEM_INFO[id]
  -- (i.bind: 1 ligado al recogerlo, 4 de misión; es el 14.º valor, como en el juego)
  if i then return i.name, nil, i.quality or 1, nil, nil, nil, nil, nil, nil, 134400, i.sell, nil, nil, i.bind end
  local D = ES and ES.Data
  local name = D and D.ItemNames and D.ItemNames[id] or ("Item " .. id)
  local sell = D and D.SellPrices and D.SellPrices[id] or 0
  return name, "|cffffffff|Hitem:" .. id .. "|h[" .. name .. "]|h|r", 1, 1, 1, "Trade Goods", "Trade Goods", 20, "", 134400, sell
end
GetItemInfoInstant = function(id)
  if type(id) ~= "number" then return nil end
  return id, "Trade Goods", "Trade Goods", "", 134400, 7, 0
end
ITEM_QUALITY_COLORS = {}
for q = -1, 7 do ITEM_QUALITY_COLORS[q] = { r = 1, g = 1, b = 1, hex = "|cffffffff" } end

-- Bolsas: lo de BAGS, una pila por objeto en la bolsa 0 (en orden de número), y lo de
-- REAGENT_BAG igual en la bolsa de componentes (la 5, 16 casillas).
-- BAG_FLAGS[id] = { bound = true, quality = 0 } para ligados o grises
BAG_FLAGS = {}
local REAGENT_SLOTS = 16
local function BagTable(bag)
  if bag == 0 then return BAGS end
  if bag == Enum.BagIndex.ReagentBag then return REAGENT_BAG end
end
local function BagIDs(bag)
  local ids, t = {}, BagTable(bag or 0)
  for id, n in pairs(t or {}) do if n > 0 then ids[#ids + 1] = id end end
  table.sort(ids)
  return ids
end
C_Container = {
  GetContainerNumSlots = function(bag)
    if bag == 0 then return math.max(16, #BagIDs(0) + 4) end
    if bag == Enum.BagIndex.ReagentBag then return REAGENT_SLOTS end
    return 0
  end,
  GetContainerItemID = function(bag, slot) return BagTable(bag) and BagIDs(bag)[slot] or nil end,
  GetContainerItemInfo = function(bag, slot)
    local t = BagTable(bag)
    local id = t and BagIDs(bag)[slot]
    if not id then return nil end
    local f = BAG_FLAGS[id] or {}
    return { itemID = id, stackCount = t[id], isBound = f.bound or false, quality = f.quality or 1,
      hasNoValue = f.noValue or false, isLocked = false, hyperlink = "|Hitem:" .. id .. "|h[" .. id .. "]|h" }
  end,
  GetContainerNumFreeSlots = function(bag)
    if bag == 0 then return 4, 0 end
    if bag == Enum.BagIndex.ReagentBag then return REAGENT_SLOTS - #BagIDs(bag), 0 end
    return 0, 0
  end,
  UseContainerItem = function(bag, slot)
    local t = BagTable(bag)
    local id = t and BagIDs(bag)[slot]
    if id and MerchantFrame and MerchantFrame:IsShown() then
      SOLD[#SOLD + 1] = { itemID = id, count = t[id] }
      t[id] = 0
    end
  end,
}
SOLD = {}

-- Vendedor abierto: MERCHANT = { { item =, price =, batch = 1, avail = -1 } };
-- OpenMerchant() lo abre como el juego (MERCHANT_SHOW). Lo comprado va a BAGS y a BOUGHT
MERCHANT, BOUGHT = {}, {}
MONEY = 1000000
MerchantFrame = Mock("MerchantFrame")
GetMerchantNumItems = function() return #MERCHANT end
GetMerchantItemID = function(i) return MERCHANT[i] and MERCHANT[i].item end
GetMerchantItemInfo = function(i)
  local m = MERCHANT[i]
  if not m then return nil end
  return "item" .. m.item, 134400, m.price, m.batch or 1, m.avail or -1, true, true, false
end
GetMerchantItemMaxStack = function() return 20 end
BuyMerchantItem = function(i, n)
  local m = MERCHANT[i]
  if not m then return end
  local units = n or (m.batch or 1)
  BAGS[m.item] = (BAGS[m.item] or 0) + units
  BOUGHT[#BOUGHT + 1] = { itemID = m.item, units = units }
  MONEY = MONEY - m.price * units / (m.batch or 1)
end
function OpenMerchant(list)
  MERCHANT = list
  MerchantFrame:Show()
  FireEvent("MERCHANT_SHOW")
  RunTimers()
end
function CloseMerchant()
  MerchantFrame:Hide()
  FireEvent("MERCHANT_CLOSED")
  RunTimers()
end

-- Merchant's Favor (moneda)
FAVOR = 0
C_CurrencyInfo = { GetCurrencyInfo = function(id) return { quantity = FAVOR, name = "Merchant's Favor", currencyID = id } end }

-- Manejador de errores de Lua del juego: GAME_ERROR_HANDLER es el del juego (apunta en
-- GAME_ERRORS lo que le llega). El addon no debe cambiarlo salvo con /cj errores grabar
GAME_ERRORS = {}
GAME_ERROR_HANDLER = function(msg) GAME_ERRORS[#GAME_ERRORS + 1] = tostring(msg) end
local errorHandler = GAME_ERROR_HANDLER
geterrorhandler = function() return errorHandler end
seterrorhandler = function(f) errorHandler = f end

InCombatLockdown = function() return IN_COMBAT or false end
IsShiftKeyDown = function() return false end
IsControlKeyDown = function() return false end
GetCursorPosition = function() return 0, 0 end
PlaySound = function() end

UIParent, Minimap = Mock("UIParent"), Mock("Minimap")
UIParent._shown, Minimap._shown = true, true
GameTooltip = Mock("tooltip")
UISpecialFrames, SlashCmdList = {}, {}
FrameUtil = {}
tinsert = table.insert
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- AH clásica simulada: AUCTIONS = { { item =, count =, buyout =, owner =, tl = } }
AUCTIONS = {}
AH_RESPONDS = true
CanSendAuctionQuery = function() return true, true end
QueryAuctionItems = function(...)
  local getAll = select(7, ...)
  if getAll and AH_RESPONDS then C_Timer.After(3, function() FireEvent("AUCTION_ITEM_LIST_UPDATE") end) end
end
GetNumAuctionItems = function() return #AUCTIONS, #AUCTIONS end
GetAuctionItemInfo = function(_, i)
  local a = AUCTIONS[i]
  if not a then return end
  return nil, nil, a.count, 1, true, 1, nil, 0, 0, a.buyout, 0, nil, nil, a.owner, a.owner, 0, a.item, true
end
GetAuctionItemTimeLeft = function(_, i) return AUCTIONS[i] and AUCTIONS[i].tl end
AuctionFrame = Mock("AuctionFrame")

-- Auctionator simulado: su historial de precios por día (Auctionator.Database).
-- InstallAuctionator() lo carga (sin llamarla no hay Auctionator, como sin el addon).
--   AUCTIONATOR_DAYS[itemID] = { { ago = días, max = cobre, min = cobre, avail = n }, ... }
--   AUCTIONATOR_FAIL = true      GetPriceHistory da error
--   AUCTIONATOR_ROWS = { ... }   devuelve estas filas tal cual (otra forma de datos)
--   AUCTIONATOR_DB["itemID"] = {} los objetos con precios en Auctionator (Database.db)
-- Los días van como en Auctionator: días desde SCAN_DAY_0 (aquí 0), en texto
AUCTIONATOR_DAYS, AUCTIONATOR_CALLBACKS, AUCTIONATOR_DB = {}, {}, {}
function AuctionatorToday() return math.floor(time() / 86400) end
function InstallAuctionator()
  Auctionator = {
    Constants = { SCAN_DAY_0 = 0 },
    Database = {
      db = AUCTIONATOR_DB,
      GetPriceHistory = function(self, key)
        if AUCTIONATOR_FAIL then error("Auctionator: error simulado") end
        if AUCTIONATOR_ROWS then return AUCTIONATOR_ROWS end
        local out, today = {}, AuctionatorToday()
        for _, d in ipairs(AUCTIONATOR_DAYS[tonumber(key)] or {}) do
          out[#out + 1] = { rawDay = tostring(today - d.ago), date = "día " .. (today - d.ago),
            minSeen = d.min or d.max, maxSeen = d.max, available = d.avail }
        end
        table.sort(out, function(a, b) return tonumber(a.rawDay) > tonumber(b.rawDay) end)
        return out
      end,
    },
    -- (AUCTIONATOR_LATEST[itemID] = { price, age }: el último mínimo que vio y hace
    -- cuántos días; sin él, su API pública no da precio)
    API = { v1 = {
      RegisterForDBUpdate = function(_, cb) AUCTIONATOR_CALLBACKS[#AUCTIONATOR_CALLBACKS + 1] = cb end,
      GetAuctionPriceByItemID = function(_, id) local l = AUCTIONATOR_LATEST and AUCTIONATOR_LATEST[id] return l and l.price end,
      GetAuctionAgeByItemID = function(_, id) local l = AUCTIONATOR_LATEST and AUCTIONATOR_LATEST[id] return l and (l.age or 0) end,
    } },
    -- Su escaneo completo (el marco lo crea al abrir la AH): AUCTIONATOR_FULL_SCANS cuenta
    -- las veces que se lanza
    -- (AUCTIONATOR_WAITING = true: un escaneo en curso; y, como el de verdad, su propia
    -- cuenta de 15 min desde SavedState.TimeOfLastReplicateScan, CanInitiate)
    SavedState = {},
    State = { FullScanFrameRef = {
      -- (como el de verdad con la AH clásica: pide el escaneo completo al servidor)
      -- (como el de verdad: «en curso», inProgress, desde justo antes de pedirlo hasta
      -- acabar; aquí, unos segundos)
      InitiateScan = function()
        local fr = Auctionator.State.FullScanFrameRef
        AUCTIONATOR_FULL_SCANS = (AUCTIONATOR_FULL_SCANS or 0) + 1
        Auctionator.SavedState.TimeOfLastReplicateScan = time()
        fr.inProgress = true
        QueryAuctionItems("", nil, nil, 0, nil, nil, true, false, nil)
        C_Timer.After(10, function() fr.inProgress = nil end)
      end,
      CanInitiate = function()
        if AUCTIONATOR_WAITING then return false end
        local last = Auctionator.SavedState.TimeOfLastReplicateScan
        return last == nil or time() - last > 15 * 60
      end,
    },
    -- Su escaneo en modo resumen (AH moderna, su botón con REPLICATE_SCAN desactivado):
    -- AUCTIONATOR_SUMMARY_SCANS cuenta las veces; no trae subastas al addon
    IncrementalScanFrameRef = {
      InitiateScan = function()
        AUCTIONATOR_SUMMARY_SCANS = (AUCTIONATOR_SUMMARY_SCANS or 0) + 1
      end,
    } },
    -- Su configuración: AUCTIONATOR_REPLICATE = false es su modo resumen (el de por
    -- defecto en el juego). Aquí, por defecto, el completo: las pruebas de antes no cambian
    Config = {
      Options = { REPLICATE_SCAN = "replicate_scan_3" },
      Get = function(name)
        if name == "replicate_scan_3" then return AUCTIONATOR_REPLICATE ~= false end
      end,
    },
    -- (Events solo existe con la AH moderna, la de Forever)
    IncrementalScan = { Events = {} },
  }
end
-- Auctionator acaba un escaneo: avisa a quien se registró
function AuctionatorUpdated() for _, cb in ipairs(AUCTIONATOR_CALLBACKS) do cb() end end

-- Métodos de marco que existen en el juego (los que usa el addon). Un método que
-- el addon llame y no esté aquí es casi seguro un error (sale como fallo)
WIDGET_API = {}
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
  SetClampRectInsets GetRight GetBottom GetName IsEventRegistered GetValue
  GetVertexColor SetFixedFrameLevel SetFixedFrameStrata SetStartDelay SetToFinalAlpha
  CreateLine SetStartPoint SetEndPoint SetThickness SetCursorPosition
  RegisterUnitEvent GetChildren IsProtected
]]):gmatch("%a+") do WIDGET_API[name] = true end
