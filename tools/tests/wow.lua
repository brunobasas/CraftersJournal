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
      FRAMES[self] = true
    end end
    if k == "UnregisterEvent" then return function(self, e) self._events[e] = nil end end
    if k == "UnregisterAllEvents" then return function(self) self._events = {} end end
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
    if k == "Show" then return function(self)
      local was = self._shown
      self._shown = true
      if not was and self._scripts.OnShow then self._scripts.OnShow(self) end
    end end
    if k == "Hide" then return function(self)
      local was = self._shown
      self._shown = false
      if was and self._scripts.OnHide then self._scripts.OnHide(self) end
    end end
    if k == "SetShown" then return function(self, v) if v then self:Show() else self:Hide() end end end
    if k == "IsShown" or k == "IsVisible" then return function(self) return self._shown end end
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
    if k == "GetName" then return function(self) return self._globalName end end
    -- Como en WoW: solo los métodos (con mayúscula) existen; los campos propios no
    if type(k) ~= "string" or not k:match("^%u") then return nil end
    MOCK_METHODS[k] = true
    return function() return Mock(k) end
  end })
end
MockFrame = Mock

CreateFrame = function(_, name, parent)
  local f = Mock("frame")
  f._parent = parent
  if name then f._globalName = name _G[name] = f end
  return f
end

function FireEvent(e, ...)
  local list = {}
  for f in pairs(FRAMES) do if f._events[e] and f._scripts.OnEvent then list[#list + 1] = f end end
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
REALM = "Realm"
FACTION = "Alliance"
NPC_FACTION = "Alliance"
GetRealmName = function() return REALM end
UnitFactionGroup = function(u) if u == "npc" then return NPC_FACTION end return FACTION end
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

BAGS = {}          -- [itemID] = cantidad (GetItemCount)
KNOWN_SPELLS = {}  -- [spellID] = true (IsPlayerSpell)
GetItemCount = function(id) return BAGS[id] or 0 end
IsPlayerSpell = function(id) return KNOWN_SPELLS[id] or false end
-- Objetos: como un cliente con todo en caché (nombre en inglés de los datos y precio
-- de venta al vendedor). ITEM_INFO[id] = { name =, sell = } cambia uno;
-- UNCACHED[id] = true hace que el juego aún no lo tenga (devuelve nil)
ITEM_INFO, UNCACHED = {}, {}
GetItemInfo = function(id)
  if type(id) ~= "number" or UNCACHED[id] then return nil end
  local i = ITEM_INFO[id]
  if i then return i.name, nil, i.quality or 1, nil, nil, nil, nil, nil, nil, 134400, i.sell end
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

-- Bolsas: lo de BAGS, una pila por objeto en la bolsa 0 (en orden de número).
-- BAG_FLAGS[id] = { bound = true, quality = 0 } para ligados o grises
BAG_FLAGS = {}
local function BagIDs()
  local ids = {}
  for id, n in pairs(BAGS) do if n > 0 then ids[#ids + 1] = id end end
  table.sort(ids)
  return ids
end
C_Container = {
  GetContainerNumSlots = function(bag) if bag == 0 then return math.max(16, #BagIDs() + 4) end return 0 end,
  GetContainerItemID = function(bag, slot) if bag == 0 then return BagIDs()[slot] end end,
  GetContainerItemInfo = function(bag, slot)
    local id = bag == 0 and BagIDs()[slot]
    if not id then return nil end
    local f = BAG_FLAGS[id] or {}
    return { itemID = id, stackCount = BAGS[id], isBound = f.bound or false, quality = f.quality or 1,
      hasNoValue = f.noValue or false, isLocked = false, hyperlink = "|Hitem:" .. id .. "|h[" .. id .. "]|h" }
  end,
  GetContainerNumFreeSlots = function(bag) return bag == 0 and 4 or 0, 0 end,
  UseContainerItem = function(bag, slot)
    local id = bag == 0 and BagIDs()[slot]
    if id and MerchantFrame and MerchantFrame:IsShown() then
      SOLD[#SOLD + 1] = { itemID = id, count = BAGS[id] }
      BAGS[id] = 0
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
]]):gmatch("%a+") do WIDGET_API[name] = true end
