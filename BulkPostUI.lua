local _, ES = ...
local L = ES.L

-- Botón de anunciar (BulkMoney, solo en la copia de desarrollo): un marco flotante y
-- movible, como el asistente, que se abre desde la pestaña BulkMoney. Pones un objeto
-- (lo sueltas en su casilla) y el precio que quieres; cada clic en «Anunciar» pone en la
-- AH UNA unidad, en una subasta de 2 h, a ese precio. Siempre el mismo precio, sin mirar
-- el mercado: para marcar tú el precio de un material con pocas subastas.
-- Un anuncio por clic: la AH pide un clic del jugador para cada uno. Anuncia
-- Ledger:PostOnAH (la AH de Forever: espera si está ocupada o escaneando, y solo dice
-- "Anunciados" cuando el servidor lo confirma).
-- Sirve de cebo: lo pones muy barato para que los que rebajan «al más barato» anuncien
-- por debajo. El registro de cebos (abajo) dice cuántos te compró al instante un sniper y
-- sugiere el precio del siguiente.
--   ES.db.bulkPost = { itemID, price (cobre), shown, point = { punto, x, y }, sale, log }

local P = {}
ES.BulkPost = P

P.HOURS = 2 -- duración de cada subasta
P.UNITS = 1 -- unidades por anuncio

local WIDTH, HEIGHT = 250, 124
local GREY, ORANGE = "|cff999999", "|cffff9933"
-- Por encima de la ventana del addon (HIGH, UI.lua), que se abre en el centro: en MEDIUM
-- salía detrás de ella y no se veía al pulsar el botón. Como el asistente
P.STRATA = "DIALOG"

local frame

function P.DB()
  if type(ES.db.bulkPost) ~= "table" then ES.db.bulkPost = {} end
  return ES.db.bulkPost
end

-- ¿Se puede usar? Solo con la pestaña BulkMoney (copia de desarrollo)
function P.Available()
  return ES.Tabs ~= nil and ES.Tabs.Info("bulk") ~= nil
end

function P.SetItem(itemID)
  P.DB().itemID = type(itemID) == "number" and itemID or nil
  P.Refresh()
end

-- Precio por unidad en cobre (se anuncia tal cual, con cobres: Ledger.PostPrice)
function P.SetPrice(copper)
  copper = tonumber(copper)
  P.DB().price = (copper and copper > 0) and math.floor(copper) or nil
end

---------------------------------------------------------------------------
-- La subasta puesta: mientras está en la AH el botón va en gris («Selling»); al
-- venderse, «SOLD» y se puede anunciar otra. ES.db.bulkPost.sale =
--   { state = "posting" (esperando a la AH) | "selling" | "sold" | "expired",
--     itemID, ends (time() en que caduca) }
-- Se sabe por el mensaje del sistema de la venta (ERR_AUCTION_SOLD_S: llega aunque no
-- estés en la AH) o de que caducó (ERR_AUCTION_EXPIRED_S). Si no llega (estabas
-- desconectado), pasadas las horas de la subasta se da por acabada
---------------------------------------------------------------------------
function P.State()
  local sale = P.DB().sale
  if type(sale) ~= "table" then return nil end
  if sale.state == "selling" and sale.ends and time() > sale.ends + 60 then sale.state = "expired" end
  -- (esperando a la AH más de un minuto: no respondió; se puede volver a intentar)
  if sale.state == "posting" and time() - (sale.t or 0) > 60 then P.DB().sale = nil return nil end
  return sale.state
end

-- ¿Hay una subasta en marcha? (no se anuncia otra hasta que se venda o caduque)
function P.Busy()
  local s = P.State()
  return s == "posting" or s == "selling"
end

---------------------------------------------------------------------------
-- Registro de cebos: cada anuncio que la AH acepta se apunta en ES.db.bulkPost.log =
--   { { itemID, price (cobre), t (time() al aceptarlo), secs (segundos hasta venderse) }, ... }
-- (los últimos P.LOG_MAX). Un cebo vendido en menos de P.INSTANT s lo ha comprado un
-- sniper (otro jugador que compra todo lo muy barato); si pasa ese tiempo sin venderse,
-- ha aguantado, y los que rebajan «al más barato» pueden ponerse por debajo. Con los
-- últimos cebos del objeto se sugiere el precio del siguiente: el umbral del sniper está
-- entre el más caro que te compró al instante y el más barato que aguantó por encima
---------------------------------------------------------------------------
P.INSTANT = 60 -- segundos: vendido antes, lo compró un sniper
P.LOG_MAX = 100 -- cebos apuntados (de todos los objetos)
P.RECENT = 10 -- cebos del objeto que cuentan para la sugerencia
P.RAISE = 1.5 -- sin ninguno que aguante: se sube así el más caro comprado al instante

function P.Log()
  local db = P.DB()
  if type(db.log) ~= "table" then db.log = {} end
  return db.log
end

-- ¿Qué pasó con el cebo? "sniped" (comprado al instante), "held" (aguantó P.INSTANT s
-- sin venderse) o nil (aún no se sabe)
function P.Outcome(e, now)
  if e.secs then return e.secs <= P.INSTANT and "sniped" or "held" end
  if (now or time()) - (e.t or 0) > P.INSTANT then return "held" end
  return nil
end

local function LogEntry(t, itemID)
  local log = P.Log()
  for i = #log, 1, -1 do
    if log[i].t == t and log[i].itemID == itemID then return log[i] end
  end
end

-- Un precio redondo, hacia arriba (cobres sueltos por debajo de 1s; luego de 5c, de 1s y de 10s)
local function Round(copper)
  local step = copper < 100 and 1 or copper < 10000 and 5 or copper < 100000 and 100 or 1000
  return math.ceil(copper / step - 1e-9) * step
end

-- Los últimos cebos del objeto (P.RECENT, ya decididos): cuántos, cuántos comprados al
-- instante y el precio que se sugiere para el siguiente (nil: ninguno comprado al
-- instante, el precio aguanta)
function P.Summary(itemID)
  local res = { n = 0, sniped = 0 }
  if not itemID then return res end
  local log, now = P.Log(), time()
  local top, held = nil, {}
  for i = #log, 1, -1 do
    local e = log[i]
    local o = e.itemID == itemID and P.Outcome(e, now)
    if o then
      res.n = res.n + 1
      if o == "sniped" then
        res.sniped = res.sniped + 1
        top = math.max(top or 0, e.price)
      else
        held[#held + 1] = e.price
      end
      if res.n >= P.RECENT then break end
    end
  end
  if not top then return res end
  local floor -- el más barato que aguantó por encima del más caro comprado al instante
  for _, p in ipairs(held) do
    if p > top and (not floor or p < floor) then floor = p end
  end
  if not floor then
    res.suggest = math.max(Round(top * P.RAISE), top + 1)
  else
    -- Entre los dos, mientras haya hueco (búsqueda del umbral); si no, el que aguantó
    local mid = Round((top + floor) / 2)
    res.suggest = (floor - top > floor * 0.1 and mid > top and mid < floor) and mid or floor
  end
  return res
end

-- La subasta puesta se ha vendido: se apunta cuánto tardó y, si fue al instante, se dice
-- en el chat con el precio que se sugiere
local function MarkSold(sale)
  sale.state = "sold"
  local e = sale.logT and LogEntry(sale.logT, sale.itemID)
  if not e or e.secs then return end
  e.secs = math.max(0, time() - e.t)
  if e.secs <= P.INSTANT then
    local s = P.Summary(sale.itemID)
    if s.suggest then
      ES:Print(string.format(L["Vendido en %d s: seguramente un sniper. Prueba el siguiente a %s."], e.secs, ES.Money(s.suggest)))
    end
  end
end

-- Respuesta de la AH al anuncio (Ledger:ConfirmPost / CancelAsked: p.onResult). `p`: el
-- anuncio, con las horas de verdad (la AH de Forever es de 12, 24 y 48 h: pedir 2 da 12)
function P.OnPostResult(ok, p)
  local sale = P.DB().sale
  if type(sale) ~= "table" or sale.state ~= "posting" then return end
  if ok then
    local hours = type(p) == "table" and tonumber(p.hours) or P.HOURS
    sale.state, sale.ends = "selling", time() + hours * 3600
    -- Al registro de cebos (al precio con que se anunció)
    if sale.price then
      local log = P.Log()
      sale.logT = time()
      log[#log + 1] = { itemID = sale.itemID, price = sale.price, t = sale.logT }
      while #log > P.LOG_MAX do table.remove(log, 1) end
      -- (pasado el tiempo de un sniper sin venderse, cuenta como que aguantó)
      if C_Timer then C_Timer.After(P.INSTANT + 1, P.Refresh) end
    end
  else
    P.DB().sale = nil -- (no se anunció o no se sabe: se puede volver a intentar)
  end
  P.Refresh()
end

-- El nombre del objeto en el idioma del cliente (el de los mensajes del sistema)
local function ClientName(itemID)
  local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
  if not name and GetItemInfo then name = (GetItemInfo(itemID)) end
  return name or ES:DataItemName(itemID)
end

-- Aviso de la AH moderna (la de Forever): AUCTION_HOUSE_SHOW_NOTIFICATION o su variante
-- _FORMATTED_, con Enum.AuctionHouseNotification (AuctionSold, AuctionExpired) y, de
-- argumento, el objeto. Es el aviso de verdad: la línea "A buyer has been found for your
-- auction of..." la escribe la interfaz del juego en el chat sin CHAT_MSG_SYSTEM, así que
-- solo con el mensaje del sistema el botón se quedaba en «Selling» (lo vio el jugador).
-- Con un argumento que nombra otro objeto, no es la nuestra
local AHN = Enum and Enum.AuctionHouseNotification
P.NOTE_SOLD = AHN and AHN.AuctionSold or 4
P.NOTE_EXPIRED = AHN and AHN.AuctionExpired or 5
function P.OnNotification(note, arg)
  local sale = P.DB().sale
  if type(sale) ~= "table" or sale.state ~= "selling" then return end
  local state = note == P.NOTE_SOLD and "sold" or note == P.NOTE_EXPIRED and "expired" or nil
  if not state then return end
  if type(arg) == "string" and ES.Ledger.Readable and ES.Ledger.Readable(arg) then
    local name = ClientName(sale.itemID)
    if name and not arg:find(name, 1, true) then return end
  end
  if state == "sold" then MarkSold(sale) else sale.state = state end
  P.Refresh()
end

-- Un mensaje del sistema: ¿es la venta (o la caducidad) de la subasta puesta? (por si
-- algún cliente lo da así; en Forever llega por P.OnNotification)
function P.OnSystemMessage(message)
  local sale = P.DB().sale
  if type(sale) ~= "table" or sale.state ~= "selling" then return end
  if not (ES.Ledger.Readable and ES.Ledger.Readable(message)) then return end
  local name = ClientName(sale.itemID)
  if not name then return end
  if type(ERR_AUCTION_SOLD_S) == "string" and message == string.format(ERR_AUCTION_SOLD_S, name) then
    MarkSold(sale)
  elseif type(ERR_AUCTION_EXPIRED_S) == "string" and message == string.format(ERR_AUCTION_EXPIRED_S, name) then
    sale.state = "expired"
  else
    return
  end
  P.Refresh()
end

-- Anuncia una unidad a 2 h al precio puesto. Devuelve cuántas anunció (0 si no pudo:
-- lo dice en el chat)
function P.Post()
  local db = P.DB()
  if P.Busy() then ES:Print(L["Ya tienes uno a la venta: espera a que se venda."]) return 0 end
  if not db.itemID then ES:Print(L["Suelta un objeto en el botón de anunciar."]) return 0 end
  if not db.price then ES:Print(L["Pon el precio al que quieres anunciarlo."]) return 0 end
  if (ES:ItemCount(db.itemID) or 0) <= 0 then
    ES:Print(string.format(L["No llevas %s."], (ES.UI.ItemLabel(db.itemID, "#" .. db.itemID))))
    return 0
  end
  -- (al precio exacto, con cobres: Forever los admite)
  local n = ES.Ledger:PostOnAH(db.itemID, P.UNITS, db.price, P.HOURS) or 0
  if n > 0 then
    -- En gris hasta que la AH responda; luego «Selling» hasta que se venda (P.OnPostResult)
    db.sale = { state = "posting", itemID = db.itemID, price = db.price, t = time() }
    local pending = ES.Ledger.pendingPost
    if pending then pending.onResult = P.OnPostResult end
  end
  P.Refresh()
  if C_Timer then C_Timer.After(1, P.Refresh) end -- (cuántos te quedan)
  return n
end

-- Lo que hay en el cursor, a la casilla
local function DropFromCursor()
  if not GetCursorInfo then return false end
  -- (no `GetCursorInfo and GetCursorInfo()`: el `and` se queda solo con el primer valor)
  local kind, itemID = GetCursorInfo()
  if kind == "item" and itemID then
    P.SetItem(itemID)
    if ClearCursor then ClearCursor() end
    return true
  end
  return false
end
P.DropFromCursor = DropFromCursor -- (pruebas)

local function MoneyBox(parent, width, label)
  local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  box:SetSize(width, 20)
  box:SetAutoFocus(false)
  box:SetNumeric(true)
  box:SetMaxLetters(width > 40 and 5 or 2)
  box:SetJustifyH("CENTER")
  box.icon = parent:CreateTexture(nil, "ARTWORK")
  box.icon:SetSize(13, 13)
  box.icon:SetPoint("LEFT", box, "RIGHT", 2, 0)
  box.icon:SetTexture(label)
  box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  return box
end

local function Create()
  local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  f:SetSize(WIDTH, HEIGHT)
  f:SetFrameStrata(P.STRATA)
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, _, x, y = self:GetPoint()
    P.DB().point = { point, x, y }
  end)
  f:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  local G = ES.UI.BROWN and ES.UI.BROWN.group or { 0.1, 0.08, 0.05 }
  f:SetBackdropColor(G[1], G[2], G[3], 0.97)
  f:SetBackdropBorderColor(0.52, 0.38, 0.17, 1)

  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.title:SetPoint("TOPLEFT", 10, -8)
  f.title:SetPoint("RIGHT", -28, 0) -- (no se mete bajo la X)
  f.title:SetJustifyH("LEFT")
  f.title:SetWordWrap(false)
  f.title:SetText(L["Botón de anunciar"])
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetSize(22, 22)
  close:SetPoint("TOPRIGHT", -2, -2)
  close:SetScript("OnClick", function() P.Show(false) end)

  -- Casilla del objeto: suelta uno encima (o clic con él en el cursor)
  local slot = CreateFrame("Button", nil, f)
  slot:SetSize(40, 40)
  slot:SetPoint("TOPLEFT", 10, -26)
  slot.icon = slot:CreateTexture(nil, "ARTWORK")
  slot.icon:SetAllPoints()
  slot.count = slot:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  slot.count:SetPoint("BOTTOMRIGHT", -2, 2)
  slot:SetScript("OnReceiveDrag", function() DropFromCursor() end)
  slot:SetScript("OnClick", function() DropFromCursor() end)
  slot:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local id = P.DB().itemID
    if id then GameTooltip:SetHyperlink("item:" .. id) GameTooltip:AddLine(" ") end
    GameTooltip:AddLine(L["Suelta aquí el objeto que quieres anunciar."], 0.5, 0.8, 1, true)
    GameTooltip:Show()
  end)
  slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
  f.slot = slot

  f.name = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.name:SetPoint("TOPLEFT", slot, "TOPRIGHT", 8, -1)
  f.name:SetPoint("RIGHT", -28, 0)
  f.name:SetJustifyH("LEFT")
  f.name:SetWordWrap(false)

  -- Precio por unidad: oro, plata y cobre (se anuncia al precio exacto: Forever admite cobres)
  f.gold = MoneyBox(f, 46, "Interface\\MoneyFrame\\UI-GoldIcon")
  f.gold:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 4, -6)
  f.silver = MoneyBox(f, 26, "Interface\\MoneyFrame\\UI-SilverIcon")
  f.silver:SetPoint("LEFT", f.gold.icon, "RIGHT", 10, 0)
  f.copper = MoneyBox(f, 26, "Interface\\MoneyFrame\\UI-CopperIcon")
  f.copper:SetPoint("LEFT", f.silver.icon, "RIGHT", 10, 0)
  local function Changed(self, user)
    if not user then return end
    P.SetPrice((tonumber(f.gold:GetText()) or 0) * 10000 + (tonumber(f.silver:GetText()) or 0) * 100
      + (tonumber(f.copper:GetText()) or 0))
    P.Refresh()
  end
  f.gold:SetScript("OnTextChanged", Changed)
  f.silver:SetScript("OnTextChanged", Changed)
  f.copper:SetScript("OnTextChanged", Changed)

  -- Registro de cebos del objeto: cuántos te compraron al instante y el precio sugerido
  -- («Usar» lo pone en las casillas). Encima, los últimos cebos
  local use = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  use:SetSize(54, 18)
  use:SetPoint("TOPRIGHT", -10, -72)
  use:SetText(L["Usar"])
  use:SetScript("OnClick", function()
    local s = P.Summary(P.DB().itemID)
    if s.suggest then P.SetPrice(s.suggest) P.Refresh() end
  end)
  f.use = use
  local baits = CreateFrame("Button", nil, f)
  baits:SetHeight(18) -- (sus puntos, en P.Refresh: hasta «Usar» o hasta el borde)
  baits.text = baits:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  baits.text:SetAllPoints()
  baits.text:SetJustifyH("LEFT")
  baits.text:SetWordWrap(false)
  baits:SetScript("OnEnter", function(self) P.BaitsTooltip(self) end)
  baits:SetScript("OnLeave", function() GameTooltip:Hide() end)
  f.baits = baits

  -- Anunciar: una unidad (en una subasta de P.HOURS) al precio puesto (un clic, un anuncio)
  local post = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  post:SetSize(WIDTH - 20, 22)
  post:SetPoint("BOTTOMLEFT", 10, 8)
  post:SetScript("OnClick", function() P.Post() end)
  post:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(self:GetText() or "", 1, 0.82, 0)
    GameTooltip:AddLine(string.format(L["Cada clic pone en la Casa de Subastas %d unidad, siempre al precio que has puesto (sin mirar el mercado). Con la AH abierta."],
      P.UNITS), 1, 1, 1, true)
    GameTooltip:Show()
  end)
  post:SetScript("OnLeave", function() GameTooltip:Hide() end)
  f.post = post

  ES.SafeRegister(f, "BAG_UPDATE_DELAYED")
  ES.SafeRegister(f, "AUCTION_HOUSE_SHOW")
  ES.SafeRegister(f, "AUCTION_HOUSE_CLOSED")
  f:SetScript("OnEvent", function(self) if self:IsShown() then P.Refresh() end end)

  local pt = P.DB().point
  if type(pt) == "table" and pt[1] then
    f:SetPoint(pt[1], UIParent, pt[1], pt[2] or 0, pt[3] or 0)
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
  end
  f:Hide()
  return f
end

-- Los últimos cebos del objeto: precio, qué pasó y a qué hora (el más reciente arriba)
P.TOOLTIP_ROWS = 8
function P.BaitsTooltip(owner)
  local id = P.DB().itemID
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:AddLine(L["Cebos recientes"], 1, 0.82, 0)
  local log, now, shown = P.Log(), time(), 0
  for i = #log, 1, -1 do
    local e = log[i]
    if e.itemID == id then
      local o = P.Outcome(e, now)
      local what
      if o == "sniped" then
        what = ORANGE .. string.format(L["al instante (%d s)"], e.secs) .. "|r"
      elseif e.secs then
        what = "|cff40ff40" .. string.format(L["vendido en %d min"], math.floor(e.secs / 60 + 0.5)) .. "|r"
      elseif o == "held" then
        what = "|cff40ff40" .. L["no lo compraron al instante"] .. "|r"
      else
        what = GREY .. L["pendiente"] .. "|r"
      end
      local hour = date and date("%H:%M", e.t) or ""
      GameTooltip:AddDoubleLine(ES.Money(e.price) .. GREY .. ES.SEP .. hour .. "|r", what, 1, 1, 1, 1, 1, 1)
      shown = shown + 1
      if shown >= P.TOOLTIP_ROWS then break end
    end
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine(string.format(L["Un cebo vendido en menos de %d s lo suele comprar un sniper, y entonces nadie rebaja por debajo de él: sube el precio hasta que deje de pasar. La sugerencia va entre el más caro comprado al instante y el más barato que aguantó."],
    P.INSTANT), 0.5, 0.8, 1, true)
  GameTooltip:Show()
end

-- Lo que enseña: el objeto, cuántos llevas, el precio y si se puede anunciar ya
function P.Refresh()
  if not frame then return end
  local db = P.DB()
  local id = db.itemID
  local name, texture = nil, nil
  if id then name, texture = ES.UI.ItemLabel(id, "#" .. id) end
  frame.slot.icon:SetTexture(texture or (id and 134400) or "Interface\\PaperDoll\\UI-Backpack-EmptySlot")
  local have = id and (ES:ItemCount(id) or 0) or 0
  frame.slot.count:SetText(id and have or "")
  frame.name:SetText(name or (GREY .. L["Suelta aquí un objeto"] .. "|r"))
  -- (el precio, sin pisar lo que estás escribiendo)
  if not frame.gold:HasFocus() and not frame.silver:HasFocus() and not frame.copper:HasFocus() then
    local price = db.price or 0
    frame.gold:SetText(price > 0 and tostring(math.floor(price / 10000)) or "")
    frame.silver:SetText(price > 0 and tostring(math.floor(price / 100) % 100) or "")
    frame.copper:SetText(price > 0 and tostring(price % 100) or "")
  end
  local ready = id and db.price and have > 0 and ES:IsAuctionHouseOpen()
  -- La subasta puesta (P.State): en gris mientras está en la AH; al venderse, SOLD y
  -- se puede anunciar otra
  local state = P.State()
  if state == "posting" then
    frame.post:SetText(L["Anunciando..."])
    frame.post:SetEnabled(false)
  elseif state == "selling" then
    frame.post:SetText(L["En venta"])
    frame.post:SetEnabled(false)
  elseif state == "sold" then
    frame.post:SetText("|cff40ff40" .. L["VENDIDO"] .. "|r")
    frame.post:SetEnabled(ready and true or false)
  else
    frame.post:SetText(string.format(L["Anunciar %d"], P.UNITS))
    frame.post:SetEnabled(ready and true or false)
  end
  -- Registro de cebos del objeto: cuántos, cuántos comprados al instante y la sugerencia
  local s = P.Summary(id)
  local line
  if s.n == 0 then
    line = GREY .. L["Sin cebos de este objeto todavía"] .. "|r"
  elseif s.sniped == 0 then
    line = string.format(L["Cebos: %d, ninguno comprado al instante"], s.n)
  else
    line = string.format(L["Cebos: %d, %d comprados al instante"], s.n, s.sniped)
  end
  local offer = s.suggest and s.suggest ~= db.price
  if offer then line = line .. GREY .. ES.SEP .. "|r" .. string.format(L["prueba %s"], ES.Money(s.suggest)) end
  frame.baits.text:SetText(line)
  frame.use:SetShown(offer and true or false)
  -- (sin «Usar», la línea llega hasta el borde)
  frame.baits:ClearAllPoints()
  frame.baits:SetPoint("TOPLEFT", 10, -72)
  if offer then frame.baits:SetPoint("RIGHT", frame.use, "LEFT", -4, 0) else frame.baits:SetPoint("RIGHT", -10, 0) end
  -- Título: qué pasa ahora (sin la duración: siempre la misma, P.HOURS)
  local notes = {}
  if state == "expired" then
    notes[#notes + 1] = ORANGE .. L["la anterior caducó"] .. "|r"
  elseif state ~= "posting" and state ~= "selling" then
    if not ES:IsAuctionHouseOpen() then
      notes[#notes + 1] = GREY .. L["abre la AH"] .. "|r"
    elseif id and have <= 0 then
      notes[#notes + 1] = ORANGE .. L["no te quedan"] .. "|r"
    end
  end
  frame.title:SetText(L["Botón de anunciar"] .. (#notes > 0 and (GREY .. ES.SEP .. "|r" .. table.concat(notes, GREY .. ES.SEP .. "|r")) or ""))
end

function P.IsShown() return frame ~= nil and frame:IsShown() end
function P.Frame() return frame end -- (pruebas)

-- Abre o cierra el botón (se recuerda: vuelve al entrar)
function P.Show(show)
  if show and not P.Available() then return end
  P.DB().shown = show and true or nil
  -- Al cerrarlo se olvida la subasta puesta: al volver a abrirlo se puede anunciar. Así
  -- nunca se queda en gris sin forma de salir (un mensaje de venta que no llegó, una
  -- respuesta de la AH perdida...)
  if not show then P.DB().sale = nil end
  if show then
    frame = frame or Create()
    frame:Show()
    P.Refresh()
  elseif frame then
    frame:Hide()
  end
  if ES.RenderBulkMoney then pcall(ES.RenderBulkMoney, ES) end
end

function P.Toggle() P.Show(not P.IsShown()) end

-- Abierto la última vez: vuelve al entrar. Y la venta de la subasta puesta: el mensaje
-- del sistema (solo mientras hay una a la venta; ver P.OnSystemMessage)
do
  local f = CreateFrame("Frame")
  ES.SafeRegister(f, "PLAYER_LOGIN")
  ES.SafeRegister(f, "CHAT_MSG_SYSTEM")
  ES.SafeRegister(f, "AUCTION_HOUSE_SHOW_NOTIFICATION")
  ES.SafeRegister(f, "AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION")
  f:SetScript("OnEvent", function(_, event, a1, a2)
    if event == "CHAT_MSG_SYSTEM" then
      if ES.db and P.Available() then P.OnSystemMessage(a1) end
      return
    end
    if event == "AUCTION_HOUSE_SHOW_NOTIFICATION" or event == "AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION" then
      if ES.db and P.Available() then P.OnNotification(a1, a2) end
      return
    end
    if C_Timer then
      C_Timer.After(0, function() if ES.db and P.DB().shown then P.Show(true) end end)
    end
  end)
end
