local _, ES = ...
local L = ES.L

-- Detalle de una profesión, al estilo del diario de mazmorras:
--   cabecera: icono, nombre, nivel actual (el del personaje) y objetivo editable;
--             a la derecha, usar bolsas (icono) y las vistas Ruta / Profit /
--             Materiales / Recetas
--   franja:   materiales, profit, instructor y herramientas, total
--   lista:    filas de dos líneas según la vista

local MAX_SKILL = ES.MAX_SKILL
local LOW_CHANCE_CRAFTS = 3 -- más fabricaciones por punto que esto: se avisa
-- Tiempo de fabricar (Planner.CraftSeconds): en la fila del paso si cada fabricación
-- es lenta (en naranja) o el paso es largo; siempre en su tooltip y en el total
local SLOW_CRAFT = 8          -- s por fabricación: lenta (algunas de Forever tardan 30-50 s)
local LONG_STEP = 5 * 60      -- s de un paso: largo

-- "~45 s", "~13 min", "~1 h 10 min"
local function Duration(secs)
  secs = math.floor(secs + 0.5)
  if secs < 60 then return string.format(L["~%d s"], secs) end
  local mins = math.floor(secs / 60 + 0.5)
  if mins < 60 then return string.format(L["~%d min"], mins) end
  return string.format(L["~%d h %d min"], math.floor(mins / 60), mins % 60)
end
-- Igual, con el reloj de arena del asistente en vez de "~" (como el tiempo de camino
-- de la flecha): "⌛ 16 min". Para el tiempo suelto en una fila, no dentro de una frase
local function DurationIcon(secs)
  local icon = ES.Assistant and ES.Assistant.HOURGLASS
  if not icon then return Duration(secs) end
  return icon .. " " .. (Duration(secs):gsub("^~", ""))
end
local ROW_HEIGHT, ROW_GAP, SECTION_HEIGHT = 40, 4, 24
local LIST_WIDTH = 762
-- Filas de cita (line.quote, ver CreateRow): comillas, texto y margen
local QUOTE_SIZE, QUOTE_TEXT_SIZE, QUOTE_PAD, QUOTE_TEXT_X = 34, 11, 12, 52
local QUOTE_COIN_Y = -2 -- píxeles que se bajan los iconos de monedas en la cita (quedan altos)
local LEVEL_W = 70 -- columna de nivel de la vista Ruta (cabe "225–300")
local VIEW_BUTTON_H = 32 -- botones Ruta / Profit / Materiales (como los del diario de mazmorras)
local STATUS_BUTTON_H = 26 -- Empezar / Dejar ruta y Actualizar precios (barra de estado)
local LIST_TOP = 90       -- de la cabecera a la lista (sin la fila "Real")
-- Marrones del diario de mazmorras: el fondo que agrupa la página, la tarjeta de la
-- cabecera (la más clara), el panel de la lista y las filas (más oscuras que el panel)
local BROWN = {
  group = { 0.165, 0.125, 0.086, 0.97 },
  card  = { 0.23, 0.18, 0.12, 0.97 },
  list  = { 0.18, 0.14, 0.10, 0.95 },
  row   = { 0.13, 0.10, 0.07, 0.95 },
}
local PAD = 14 -- margen interior: del fondo de la página a sus paneles

local SOURCE_LABEL = ES.Localize({
  vendor = "Vendedor", ah = "AH", craft = "Fabricar", stock = "Tuyo",
  owned = "Bolsas",
})
local LEARN_LABEL = ES.Localize({ trainer = "instructor", vendor = "receta del vendedor", scroll = "pergamino AH", unknown = "pergamino/drop, precio ?", favor = "Merchant's Favor",
  quest = "misión", ah = "pergamino en la AH", owned = "pergamino en tus bolsas", known = "ya la sabes" })
local RANK_NAMES = ES.Localize({ [150] = "Oficial", [225] = "Experto", [300] = "Artesano" })
local GOLD, GREEN, GREY, RED, ORANGE = "|cffffd100", "|cff40ff40", "|cff999999", "|cffff4040", "|cffff9933"

local VIEWS = ES.Localize({
  -- (anchos justos para su texto: con cinco iconos de filtro a su izquierda, más anchos
  -- empujaban el primer icono encima de la casilla del objetivo)
  { key = "route",  label = "Ruta",            width = 84,  icon = "Interface\\Icons\\INV_Misc_Map_01" },
  { key = "shop",   label = "Materiales", width = 118, icon = "Interface\\Icons\\INV_Misc_Note_01" },
  { key = "profit", label = "Profit",          width = 84,  icon = "Interface\\Icons\\INV_Misc_Coin_02" },
}, "label")
local VIEW_KEYS = { route = true, profit = true, shop = true }

-- Coste con signo: lo que pagas en rojo con "-", lo que ganas en verde con "+"
-- (`copper` es coste: positivo = pagas, negativo = ganas)
local function Signed(copper)
  if copper <= -0.5 then return GREEN .. "+" .. ES.Money(-copper) .. "|r" end
  if copper >= 0.5 then return RED .. "-" .. ES.Money(copper) .. "|r" end
  return ES.Money(0)
end

-- Nombre del objeto en su color de calidad. Si el juego aún no lo ha cargado, el
-- nombre de los datos del addon (o `fallback`); el tercer valor dice que falta
function ES:ItemName(itemID)
  return (self:GetItemData(itemID)) or self:DataItemName(itemID)
end

local function ItemLabel(itemID, fallback)
  local name, quality, texture = ES:GetItemData(itemID)
  local color = name and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality or 1]
  if name and color and color.hex then
    name = color.hex .. name .. "|r"
  end
  return name or ES:DataItemName(itemID) or fallback, texture, name == nil
end

local function Label(parent, text, template)
  local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormalSmall")
  fs:SetText(text)
  return fs
end

local function CheckBox(parent, text, onClick)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetSize(24, 24)
  local label = Label(parent, text, "GameFontHighlightSmall")
  label:SetPoint("LEFT", cb, "RIGHT", 2, 1)
  cb:SetScript("OnClick", onClick)
  cb.label = label
  return cb
end

local function Panel(parent, r, g, b, a)
  local p = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  p:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  p:SetBackdropColor(r or 0.13, g or 0.09, b or 0.05, a or 0.94)
  p:SetBackdropBorderColor(0.52, 0.38, 0.17, 1)
  return p
end

-- ¿La AH activa es la neutral? (más depósito y 15% de comisión). Ahora siempre no: la
-- neutral no tiene soporte (Core.lua, DetectAuctionHouse). Se deja para el día que lo tenga
function ES:IsNeutralAH()
  return self:RealmKey():match("%-Neutral$") ~= nil
end

-- Marco desplazable con la rueda del ratón, sin barra de desplazamiento a la vista
local function WheelScroll(parent, step)
  local scroll = CreateFrame("ScrollFrame", nil, parent)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    -- Sin la plantilla, algunos clientes no recalculan solos el alto del contenido
    if self.UpdateScrollChildRect then self:UpdateScrollChildRect() end
    local range = tonumber(self:GetVerticalScrollRange()) or 0
    local cur = tonumber(self:GetVerticalScroll()) or 0
    self:SetVerticalScroll(math.max(0, math.min(range, cur - delta * (step or 40))))
  end)
  return scroll
end

-- Indicador de desplazamiento de un WheelScroll: una guía fina pegada a su borde
-- derecho con un tirador que dice dónde estás y cuánto queda; se puede arrastrar.
-- Solo se ve si hay más contenido del que cabe. Deja `width` px libres a la derecha
-- del contenido para que no tape nada. Llamar a :Update() al cambiar el contenido.
local function ScrollIndicator(scroll, content, width)
  width = width or 5
  local track = CreateFrame("Frame", nil, scroll:GetParent())
  track:SetWidth(width)
  track:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 0, 0)
  track:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 0, 0)
  track:SetFrameLevel(scroll:GetFrameLevel() + 5)
  local bg = track:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0, 0, 0, 0.35)
  local thumb = CreateFrame("Frame", nil, track)
  thumb:SetWidth(width)
  thumb:EnableMouse(true)
  local tex = thumb:CreateTexture(nil, "ARTWORK")
  tex:SetAllPoints()
  local function Tint(hover) tex:SetColorTexture(0.80, 0.62, 0.26, hover and 1 or 0.75) end
  Tint(false)

  local function Range()
    return math.max(0, (tonumber(content:GetHeight()) or 0) - (tonumber(scroll:GetHeight()) or 0))
  end
  function track:Update()
    local range, h = Range(), tonumber(track:GetHeight()) or 0
    if range <= 1 or h <= 0 then track:Hide() return end
    track:Show()
    local view = tonumber(scroll:GetHeight()) or 0
    local th = math.max(24, h * view / (view + range))
    thumb:SetHeight(th)
    local cur = math.max(0, math.min(range, tonumber(scroll:GetVerticalScroll()) or 0))
    thumb:ClearAllPoints()
    thumb:SetPoint("TOP", track, "TOP", 0, -(h - th) * cur / range)
  end

  -- Arrastrar el tirador: lo que baja el ratón, proporcional a todo el recorrido
  local startY, startScroll
  thumb:SetScript("OnMouseDown", function(self)
    local _, y = GetCursorPosition()
    startY, startScroll = y / (self:GetEffectiveScale() or 1), tonumber(scroll:GetVerticalScroll()) or 0
    self:SetScript("OnUpdate", function(s)
      local _, cy = GetCursorPosition()
      local free = (tonumber(track:GetHeight()) or 0) - (tonumber(s:GetHeight()) or 0)
      if free <= 0 then return end
      local delta = (startY - cy / (s:GetEffectiveScale() or 1)) * Range() / free
      scroll:SetVerticalScroll(math.max(0, math.min(Range(), startScroll + delta)))
    end)
  end)
  thumb:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
  thumb:SetScript("OnEnter", function() Tint(true) end)
  thumb:SetScript("OnLeave", function() Tint(false) end)

  scroll:HookScript("OnVerticalScroll", function() track:Update() end)
  scroll:HookScript("OnSizeChanged", function() track:Update() end)
  track:Hide()
  return track
end

-- Utilidades compartidas con otras pestañas
-- Fondo que agrupa toda una página (como el del diario de mazmorras), detrás de lo demás
local function GroupPanel(page)
  local g = Panel(page, BROWN.group[1], BROWN.group[2], BROWN.group[3], BROWN.group[4])
  g:SetPoint("TOPLEFT", 2, 0)
  g:SetPoint("BOTTOMRIGHT", -2, 2)
  g:SetFrameLevel(page:GetFrameLevel())
  return g
end

-- Paleta común de todas las pestañas (la de Subir profesiones): fondo agrupado,
-- tarjeta de cabecera arriba (BROWN.card) y panel de la lista (BROWN.list)
local function CardHead(page, height)
  page.group = page.group or GroupPanel(page)
  local head = Panel(page, BROWN.card[1], BROWN.card[2], BROWN.card[3], BROWN.card[4])
  head:SetPoint("TOPLEFT", PAD, -PAD + 2)
  head:SetPoint("TOPRIGHT", -PAD, -PAD + 2)
  head:SetHeight(height or 66)
  return head
end

local function ListPanel(page, anchor, gap)
  local list = Panel(page, BROWN.list[1], BROWN.list[2], BROWN.list[3], BROWN.list[4])
  list:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -(gap or 8))
  list:SetPoint("BOTTOMRIGHT", -PAD, PAD)
  return list
end

-- La paleta de las filas de las rutas: fondo marrón de fila, borde fino ocre, brillo
-- dorado suave al pasar el ratón y la línea secundaria en beige apagado. La usan las
-- fichas y la lista de Inversiones y la categoría Pestañas de las opciones. Quien la
-- use pone el borde ROW_BORDER_HOVER al entrar el ratón y ROW_BORDER al salir
local ROW_BORDER, ROW_BORDER_HOVER = { 0.40, 0.29, 0.13, 1 }, { 0.80, 0.62, 0.26, 1 }
local SUB_COLOR = { 0.75, 0.72, 0.65 }
local function RowStyle(frame)
  frame:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  local B = BROWN.row
  frame:SetBackdropColor(B[1], B[2], B[3], B[4])
  frame:SetBackdropBorderColor(unpack(ROW_BORDER))
  local hl = frame:CreateTexture(nil, "HIGHLIGHT")
  hl:SetPoint("TOPLEFT", 2, -2)
  hl:SetPoint("BOTTOMRIGHT", -2, 2)
  hl:SetColorTexture(1, 0.82, 0.25, 0.08)
end

ES.UI = { Label = Label, CheckBox = CheckBox, ItemLabel = ItemLabel, Panel = Panel, WheelScroll = WheelScroll,
  ScrollIndicator = ScrollIndicator,
  BROWN = BROWN, GroupPanel = GroupPanel, PAD = PAD, CardHead = CardHead, ListPanel = ListPanel,
  RowStyle = RowStyle, ROW_BORDER = ROW_BORDER, ROW_BORDER_HOVER = ROW_BORDER_HOVER, SUB_COLOR = SUB_COLOR }

-- Objetivo de una profesión (editable en su detalle). Por defecto, el final del tope
-- en el que estás: 150 si tienes menos de 150, 225 hasta 224 y si no 300 (antes era tu
-- nivel + 150: salía 151, 152...). Una ruta más corta se calcula mucho antes, y sube
-- contigo (no se guarda: solo se guarda el que escribes). Lo usan la tarjeta de la
-- portada y el detalle, para que el coste coincida.
ES.DEFAULT_TARGETS = { 150, 225, 300 }
function ES:DefaultTarget(profKey)
  local data = ES.Data[profKey]
  local rank = data and data.skillLine and self:GetProfessionSkill(data.skillLine) or 1
  for _, t in ipairs(ES.DEFAULT_TARGETS) do
    if rank < t then return t end
  end
  return MAX_SKILL
end
function ES:ProfessionTarget(profKey)
  local settings = self.db.prof and self.db.prof[profKey] or {}
  return math.max(1, math.min(MAX_SKILL, tonumber(settings.target) or self:DefaultTarget(profKey)))
end

-- Opciones del plan de una profesión con los ajustes guardados. Las usan el
-- detalle y la tarjeta de la portada, para que el coste salga igual en los dos.
-- Depósito de subasta de 24 h y reutilizar lo fabricado: fijos por ahora.
function ES:PlanOptions(profKey, from, to, cap)
  self.db.prof = self.db.prof or {}
  local settings = self.db.prof[profKey] or {}
  -- Materiales que no quieres fabricar (✕ en "Fabrica 30× Light Leather"): se compran
  local via
  for itemID in pairs(settings.noCraft or {}) do
    via = via or {}
    via[itemID] = "buy"
  end
  -- Recetas que sabes de otras profesiones (fundir el mineral para Herrería): la ruta las
  -- usa como preparación, y con "usar lo de las bolsas" cuenta también sus materiales
  local foreign = self:ForeignProducers(profKey)
  if not next(foreign.producers) then foreign = nil end
  return {
    via = via,
    foreignProducers = foreign,
    -- La última ruta calculada de esta profesión: el GPS la prueba primero (ver PlanGPS).
    -- Tras recargar, la guardada (settings.lastRoute), aunque ya no valga tal cual
    hint = self.lastRoutes[profKey] or self:SavedRouteHint(profKey),
    from = from, to = to, cap = cap,
    hours = 24,
    neutral = self:IsNeutralAH(),
    owned = settings.useBags and self:GetOwnedReagents(ES.Data[profKey], foreign) or nil,
    ignoreSupply = true, -- no se mira cuántos hay a la venta: el plan no se para por existencias
    includeScrolls = false, -- recetas de pergamino/drop: pendiente para una versión futura
    reuseCrafted = true,
    -- Prueba piloto: recetas de pergamino por sus fuentes reales (misión, vendedor, AH)
    sourcedScrolls = ES.Waypoints.SOURCED_PROFESSIONS[profKey] or nil,
    noQuests = settings.useQuests == false or nil, -- icono de misión desactivado
    noLimited = settings.noLimited or nil, -- icono de vendedores de stock limitado desactivado
    excluded = settings.excluded and next(settings.excluded) and settings.excluded or nil, -- quitadas con la ✕
    useFavor = settings.useFavor or nil, -- recetas de Merchant's Favor (icono; por defecto no)
    -- Icono "Menos fabricaciones": cada fabricación pesa más al elegir (por defecto no)
    -- (apagado: la ruta más barata en dinero, con un peso mínimo por fabricación, 5c,
    -- que no cambia el coste y evita pasos de 20 fabricaciones por punto para ahorrar un
    -- cobre; encendido: cada fabricación pesa FEWER_CRAFTS_WEIGHT)
    craftWeight = settings.fewerCrafts and self.Planner.FEWER_CRAFTS_WEIGHT or nil,
  }
end

-- Recetas quitadas de la ruta y materiales que no quieres fabricar, en orden fijo
-- (para la clave de la caché)
local function ExcludedKey(settings)
  local ids = {}
  for id in pairs(settings.excluded or {}) do ids[#ids + 1] = id end
  for id in pairs(settings.noCraft or {}) do ids[#ids + 1] = -id end
  table.sort(ids)
  return table.concat(ids, ",")
end

---------------------------------------------------------------------------
-- Ruta fijada ("Empezar ruta"): una vez decidida, comprar (AH, vendedor, correo)
-- no la cambia ni cambia sus totales. Se guardan las recetas de cada nivel y lo
-- que llevabas en las bolsas al empezar (solo eso cuenta como gratis: lo que
-- compras para la ruta ya está contado como gasto). La lista de la compra dice
-- cuánto tienes de lo que falta desde tu nivel. Se libera con "Dejar ruta",
-- al cambiar el objetivo u otra opción, con la ✕, o al llegar al objetivo.
--   settings.lock = { from, to, cap, choice = { [nivel] = receta }, via = { [material] = "craft" | "buy" },
--                     owned, started, scanTime }
---------------------------------------------------------------------------
ES.lockedPlans = {} -- ruta fijada ya calculada, por profesión (en memoria)
ES.lastRoutes = {}  -- última ruta calculada de cada profesión { choice, via } (pista para el GPS)

local function Remember(profKey, plan)
  if plan and plan.choice then ES.lastRoutes[profKey] = { choice = plan.choice, via = plan.ctx and plan.ctx.via } end
end

function ES:RouteLock(profKey)
  local settings = self.db.prof and self.db.prof[profKey]
  return settings and settings.lock
end

-- Precios del escaneo de los objetos que usa una ruta: materiales, lo que se
-- fabrica antes, lo que sale de cada paso, los pergaminos y las herramientas.
-- Con ellos la ruta fijada se rehace igual aunque haya escaneos nuevos.
-- Los objetos que usa una ruta: { [itemID] = true }
local function RouteItems(plan)
  local ids = {}
  local function Recipe(r)
    if not r then return end
    for _, rq in ipairs(r.r or {}) do ids[rq[1]] = true end
    if r.out then ids[r.out[1]] = true end
    if r.scroll then ids[r.scroll] = true end
  end
  for _, st in ipairs(plan.steps) do Recipe(st.recipe) end
  for _, c in ipairs(plan.crafted or {}) do ids[c.itemID] = true Recipe(c.recipe) end
  for _, it in ipairs(plan.shopping or {}) do ids[it.itemID] = true end
  for _, tl in ipairs(plan.tools or {}) do ids[tl.item] = true end
  return ids
end
ES.RouteItems = RouteItems -- (pruebas)

local function RoutePrices(plan)
  local scan = ES.db.scans and ES.db.scans[ES:RealmKey()]
  local items = scan and scan.items or {}
  local prices = {}
  for id in pairs(RouteItems(plan)) do prices[id] = items[id] end
  return prices, scan and scan.time
end

-- Opciones para rehacer una ruta ya decidida (mismas recetas en cada nivel y mismos
-- materiales fabricados o comprados) en una sola pasada: la ruta fijada y la última
-- ruta guardada (settings.lastRoute)
function ES:ForcedPlanOptions(profKey, from, to, cap, choice, via)
  local opts = self:PlanOptions(profKey, from, to, cap)
  opts.forced, opts.via, opts.fullInfo = choice, via, true
  return opts
end

-- La ruta fijada: la de esta sesión tal cual; tras recargar se rehace con las
-- mismas recetas, las bolsas y los precios del principio (una sola pasada: rápido)
function ES:LockedPlan(profKey)
  local lock = self:RouteLock(profKey)
  if not lock then return nil end
  local plan = self.lockedPlans[profKey]
  if plan and plan.lockStarted == lock.started and plan.lockPrices == lock.scanTime then return plan end
  local opts = self:ForcedPlanOptions(profKey, lock.from, lock.to, lock.cap, lock.choice, lock.via)
  opts.owned, opts.excluded = lock.owned, nil
  opts.prices, opts.pricesTime = lock.prices, lock.scanTime
  plan = self.Planner:Plan(ES.Data[profKey], opts)
  plan.lockStarted, plan.lockPrices = lock.started, lock.scanTime
  self.lockedPlans[profKey] = plan
  return plan
end

-- "Actualizar precios": la misma ruta (mismas recetas por nivel) con los precios
-- del último escaneo.
function ES:RefreshRoutePrices(profKey)
  local lock = self:RouteLock(profKey)
  if not lock then return end
  local opts = self:ForcedPlanOptions(profKey, lock.from, lock.to, lock.cap, lock.choice, lock.via)
  opts.owned, opts.excluded = lock.owned, nil
  local plan = self.Planner:Plan(ES.Data[profKey], opts) -- con el último escaneo
  lock.prices, lock.scanTime = RoutePrices(plan)
  plan.lockStarted, plan.lockPrices = lock.started, lock.scanTime
  self.lockedPlans[profKey] = plan
end

function ES:StartRoute(page)
  local plan = page.plan
  if not plan or #plan.steps == 0 then return end
  local owned
  if plan.ctx and plan.ctx.opts.owned then
    owned = {}
    for itemID, q in pairs(plan.ctx.opts.owned) do owned[itemID] = q end
  end
  local choice = {}
  for s, id in pairs(plan.choice) do choice[s] = id end
  -- Materiales que se fabrican o se compran (ver Planner:Plan): igual al rehacerla
  local via = {}
  for itemID, way in pairs(plan.ctx and plan.ctx.via or {}) do via[itemID] = way end
  local prices, scanTime = RoutePrices(plan)
  local lock = { from = plan.from, to = plan.to, cap = page.detected and page.detected.cap or nil, choice = choice,
    via = via, owned = owned, started = time(), scanTime = scanTime, prices = prices }
  self.db.prof[page.profKey].lock = lock
  plan.lockStarted, plan.lockPrices = lock.started, lock.scanTime
  self.lockedPlans[page.profKey] = plan
  self:RenderPlan(page)
  if self.Assistant then self.Assistant.Refresh() end -- (sale el asistente de esta ruta)
  -- Empezar la ruta pone su lista en la Lista de compra (se calcula sola): se avisa
  -- como cualquier otra cosa que se añade
  local list = ES.Shopping and ES.Shopping.PhaseList(page.profKey)
  if list then
    self:Print(string.format(L["Añadido a la lista de compra: %s."], list.title))
    self:FlashTab("shopping", true)
    if self.RenderShopping then self:RenderShopping() end
  end
  -- Empezada con "ruta entera" (elegida en la vista Materiales): se recuerda que por
  -- tramos suele salir mejor y dónde se cambia
  if ES.Shopping and not ES.Shopping.ByPhase(page.profKey) then self:WholeRouteNotice(page.profKey) end
end

-- Aviso al empezar una ruta comprando la ruta entera: por tramos suele salir mejor, y se
-- cambia con los iconos del asistente (la bolsa, por tramos; la caja, la ruta entera).
-- "Por tramos" lo cambia ya. Se apaga con su casilla (ES.db.noWholeRouteNotice) y se
-- vuelve a encender en /cj opciones (Asistente de ruta)
function ES:WholeRouteNotice(profKey)
  self:Confirm({
    key = "noWholeRouteNotice", title = L["Vas a comprar la ruta entera"],
    text = L["Has elegido comprar toda la ruta de una vez. Por tramos suele salir mejor: compras solo lo del tramo en el que estás, con un margen, y no te sobra material si los puntos suben antes."]
      .. "\n\n" .. L["Lo puedes cambiar cuando quieras con los iconos del asistente: la bolsa es por tramos y la caja, la ruta entera."],
    extra = 70,
    yes = L["Ruta entera"], no = L["Por tramos"],
    onYes = function() end,
    onNo = function()
      local s = self.db.prof[profKey]
      if not s then return end
      s.byPhase = nil
      if self.Assistant and self.Assistant.ModeChanged then self.Assistant.ModeChanged() end
      if self.RenderShopping then self:RenderShopping() end
      for _, page in ipairs(self.professionPages or {}) do
        if page.initialized and page.profKey == profKey and page:IsVisible() then self:RenderPlan(page) end
      end
      if self.Assistant and self.Assistant.Refresh then self.Assistant.Refresh() end
    end,
  })
end

function ES:StopRoute(profKey)
  local settings = self.db.prof and self.db.prof[profKey]
  if settings then settings.lock = nil end
  self.lockedPlans[profKey] = nil
  if self.Assistant then self.Assistant.Refresh() end
end

-- Plan de una profesión con su nivel actual y su objetivo, sin necesidad de abrir
-- su página (lo usan la lista de compra de la AH). nil si ya estás en el objetivo.
function ES:ProfessionPlan(profKey)
  local data = ES.Data[profKey]
  local rank, maxRank = self:GetProfessionSkill(data.skillLine)
  local from, to = rank or 1, self:ProfessionTarget(profKey)
  if from >= to then return nil, from, to end
  local locked = self:LockedPlan(profKey)
  if locked then return locked, from, to end
  local cap = rank and maxRank or nil
  local cached = self:CachedPlan(profKey, from, to, cap)
  if cached then return cached, from, to end
  local stable = self:StableRouteKey(profKey, from, to, cap)
  local key = self:PlanKey(profKey, from, to, cap, stable)
  local plan = self.Planner:Plan(data, self:PlanOptions(profKey, from, to, cap))
  self:StorePlan(profKey, key, stable, plan)
  return plan, from, to
end

-- Rutas ya calculadas, una por profesión: las comparten la portada, la página de
-- la profesión y la lista de compra de la AH. Dos niveles:
--   en memoria: homePlanCache[prof] = { key, plan, bags }, con la clave entera
--     (ES:PlanKey: la estable más planGen, que sube ES:ClearHomeCache, y planGens,
--     que sube ES:InvalidatePlan solo para una profesión)
--   guardada (por personaje): settings.lastRoute = { key, choice, via, bags, reached },
--     con la clave estable (ES:StableRouteKey). Tras recargar, si coincide, la ruta se
--     rehace en una sola pasada (mismas recetas, precios de ahora) en vez de buscarla
-- Con "usar lo de las bolsas", `bags` = { [itemID] = cantidad } de los objetos de la
-- ruta al calcularla: la ruta deja de valer si cambia alguno, no con cualquier objeto
ES.planGen = 0
ES.planGens = {}
ES.knownStamp = {} -- [profesión] = recetas sabidas (HomeUI.lua, CheckLearned)
function ES:InvalidatePlan(profKey)
  self.planGens[profKey] = (self.planGens[profKey] or 0) + 1
  self.homePlanCache[profKey] = nil
end

-- Recetas sabidas de una profesión (para la clave estable): las cuenta CheckLearned al
-- entrar y al aprender; si aún no, aquí
function ES:KnownStamp(profKey)
  local n = self.knownStamp[profKey]
  if n == nil and self.KnownCount and self.Data[profKey] and self.Data[profKey].recipes then
    n = self.KnownCount(profKey)
    self.knownStamp[profKey] = n
  end
  return n or 0
end

local recipeCount = {} -- [profesión] = recetas en los datos (cambia al regenerarlos)
local function RecipeCount(profKey)
  if not recipeCount[profKey] then
    local n = 0
    for _ in pairs(ES.Data[profKey] and ES.Data[profKey].recipes or {}) do n = n + 1 end
    recipeCount[profKey] = n
  end
  return recipeCount[profKey]
end

-- Todo lo que cambia la ruta y se puede comparar entre sesiones: escaneo, niveles,
-- opciones de la profesión, reino, Working Overtime, recetas sabidas, precios de
-- instructor, standing con las facciones que dan recetas y versión del addon y de
-- sus datos
function ES:StableRouteKey(profKey, from, to, cap)
  local settings = self.db.prof and self.db.prof[profKey] or {}
  local scan = self.db.scans and self.db.scans[self:RealmKey()]
  local trainer = self.db.trainerStamp and self.db.trainerStamp[profKey] or 0
  return table.concat({ profKey, scan and scan.time or 0, from, to, tostring(cap), tostring(settings.useBags),
    tostring(settings.useQuests), self:RealmKey(), ExcludedKey(settings), tostring(settings.useFavor),
    tostring(settings.fewerCrafts), tostring(self.Planner.SKILL_BONUS or 0), -- (Working Overtime)
    tostring(settings.noLimited or false), self:KnownStamp(profKey), trainer,
    self.RepStamp and self:RepStamp() or "", tostring(self.AddonVersion and self.AddonVersion()), RecipeCount(profKey),
    self.SpecStamp and self:SpecStamp() or "",
    -- (recetas sabidas de otras profesiones que fabrican lo que usa: aprender Smelt Thorium)
    self:ForeignProducers(profKey).stamp }, ":")
end
function ES:PlanKey(profKey, from, to, cap, stable)
  return (stable or self:StableRouteKey(profKey, from, to, cap)) .. ":" .. self.planGen .. "." .. (self.planGens[profKey] or 0)
end

-- ¿Llevas lo mismo de los objetos de la ruta que al calcularla? (sin `bags`: la ruta
-- no usa lo de las bolsas)
local function BagsMatch(bags)
  if bags == nil then return true end
  if type(bags) ~= "table" then return false end
  for itemID, n in pairs(bags) do
    if (ES:ItemCount(itemID) or 0) ~= n then return false end
  end
  return true
end
ES.RouteBagsMatch = BagsMatch

-- Lo que llevabas de cada objeto de la ruta al calcularla, si usa lo de las bolsas
local function BagItems(plan)
  local owned = plan and plan.ctx and plan.ctx.opts and plan.ctx.opts.owned
  if not owned then return nil end
  local bags = {}
  for id in pairs(RouteItems(plan)) do bags[id] = owned[id] or 0 end
  return bags
end

local function Copy(t)
  if type(t) ~= "table" then return nil end
  local c = {}
  for k, v in pairs(t) do c[k] = v end
  return c
end

-- Apunta una ruta recién calculada: en memoria y, si está completa, en lo guardado
-- (sin los precios de vendedor que faltaban no se guarda: con ellos sería otra)
function ES:StorePlan(profKey, key, stable, plan)
  local bags = BagItems(plan)
  self.homePlanCache[profKey] = { key = key, plan = plan, bags = bags }
  Remember(profKey, plan)
  if not (plan and type(plan.choice) == "table" and next(plan.choice)) then return end
  if plan.pendingItems and next(plan.pendingItems) then return end
  self.db.prof = self.db.prof or {}
  self.db.prof[profKey] = self.db.prof[profKey] or {}
  self.db.prof[profKey].lastRoute = { key = stable, choice = Copy(plan.choice), via = Copy(plan.ctx and plan.ctx.via),
    bags = bags, reached = plan.reached }
end

-- La ruta guardada, si tiene la forma que se espera (si no: nil, y se descarta)
local function SavedRoute(profKey)
  local settings = ES.db.prof and ES.db.prof[profKey]
  local saved = settings and settings.lastRoute
  if saved == nil then return nil end
  local ok = type(saved) == "table" and type(saved.key) == "string" and type(saved.choice) == "table"
    and next(saved.choice) ~= nil and type(saved.reached) == "number"
    and (saved.via == nil or type(saved.via) == "table") and (saved.bags == nil or type(saved.bags) == "table")
  if ok then
    for s, id in pairs(saved.choice) do
      if type(s) ~= "number" or type(id) ~= "number" then ok = false break end
    end
  end
  if not ok then
    settings.lastRoute = nil
    return nil
  end
  return saved, settings
end

-- La ruta guardada como pista del GPS (ver PlanOptions), aunque ya no valga tal cual
function ES:SavedRouteHint(profKey)
  local saved = SavedRoute(profKey)
  return saved and { choice = saved.choice, via = saved.via } or nil
end

-- La ruta guardada, rehecha en una pasada si sigue valiendo (misma clave estable y,
-- con las bolsas, lo mismo de sus objetos). Si al rehacerla no sale la misma (una
-- receta que ya no está), se descarta y habrá que calcularla
local function FromSaved(profKey, from, to, cap, key, stable)
  local saved, settings = SavedRoute(profKey)
  if not saved or saved.key ~= stable or not BagsMatch(saved.bags) then return nil end
  local ok, plan = pcall(function()
    return ES.Planner:Plan(ES.Data[profKey], ES:ForcedPlanOptions(profKey, from, to, cap, saved.choice, saved.via))
  end)
  local same = ok and type(plan) == "table" and type(plan.choice) == "table" and (plan.reached or 0) >= saved.reached
  if same then
    for s = from, saved.reached - 1 do
      if plan.choice[s] ~= saved.choice[s] then same = false break end
    end
  end
  if not same then
    if not ok and ES.RecordError then ES:RecordError("rehacer la ruta guardada", plan) end
    settings.lastRoute = nil
    return nil
  end
  ES.homePlanCache[profKey] = { key = key, plan = plan, bags = saved.bags }
  Remember(profKey, plan)
  return plan
end

-- La ruta en memoria si sigue valiendo
local function Fresh(profKey, key)
  local cached = ES.homePlanCache[profKey]
  if cached and cached.key == key and BagsMatch(cached.bags) then return cached.plan end
end

-- La ruta ya calculada (fijada, en la caché o guardada, y aún válida), sin buscarla
function ES:CachedPlan(profKey, from, to, cap)
  local locked = self:LockedPlan(profKey)
  if locked then return locked end
  local stable = self:StableRouteKey(profKey, from, to, cap)
  local key = self:PlanKey(profKey, from, to, cap, stable)
  return Fresh(profKey, key) or FromSaved(profKey, from, to, cap, key, stable)
end

-- Ruta de una profesión: la de la caché si vale; si no, se calcula repartida entre
-- fotogramas (Jobs.lua) y al acabar se llama a onDone(plan). Devuelve la ruta si ya
-- está (en caché, o calculada de golpe fuera del juego). `owner` identifica a quien
-- la pide (la portada, una página) para no avisarle dos veces.
function ES:RequestPlan(profKey, from, to, cap, onDone, owner)
  local locked = self:LockedPlan(profKey) -- ruta fijada: la portada enseña la misma
  if locked then return locked end
  local stable = self:StableRouteKey(profKey, from, to, cap)
  local key = self:PlanKey(profKey, from, to, cap, stable)
  local ready = Fresh(profKey, key) or FromSaved(profKey, from, to, cap, key, stable)
  if ready then return ready end
  -- Esta misma ruta ya dio error: no se repite (la portada la volvería a pedir con
  -- cada repintado). Cambiar algo (nivel, objetivo, escaneo, opciones) es otra clave
  if self.planFailed[profKey] == key then return nil, true end
  local inline = true
  self.Jobs.Run("plan:" .. profKey .. ":" .. tostring(owner), key, function()
    -- Progreso (barra de "Calculando"): cuántas veces recorre la ruta el planificador,
    -- frente a las que necesitó la última vez para este tramo (ES:PlanProgress)
    local P = self.Planner
    P.passes = 0
    self.planRunning = { prof = profKey, span = to - from }
    local plan = P:Plan(ES.Data[profKey], self:PlanOptions(profKey, from, to, cap))
    self.db.planPasses = self.db.planPasses or {}
    self.db.planPasses[profKey] = { passes = P.passes, span = to - from }
    self.planRunning = nil
    return plan
  end, function(plan, err)
    if err then
      if not inline and onDone then onDone(nil, true) end
      return
    end
    if self:PlanKey(profKey, from, to, cap) == key then self:StorePlan(profKey, key, stable, plan) end
    if not inline and onDone then onDone(plan) end
    -- (la portada, si se ve, enseña ya su coste: ella no la pide, ver ProfessionEntries)
    if not inline and self.RenderHome then self:RenderHome() end
  end, owner, nil, function()
    self.planRunning = nil
    self.planFailed[profKey] = key
  end)
  inline = false
  local cached = self.homePlanCache[profKey]
  if cached and cached.key == key then return cached.plan end
  if self.planFailed[profKey] == key then return nil, true end
end
ES.planFailed = {} -- [profKey] = clave de la ruta que dio error (ver RequestPlan)

-- Barra y porcentaje de "Calculando la ruta…" de una página (se llama al pintarla y
-- cada 0,1 s mientras la barra se ve)
function ES:UpdateCalcProgress(page)
  local bar = page.calcBar
  if not bar then return end
  local p = page.calculating and self:PlanProgress(page.profKey)
  if not p then bar:Hide() return end
  bar:SetValue(p)
  bar:Show()
  page.status:SetText("|cff999999" .. L["Calculando la ruta…"] .. string.format(" %d%%", math.floor(p * 100)) .. "|r")
end

-- Progreso del cálculo de la ruta de una profesión, de 0 a 1, o nil si no se está
-- calculando ahora (en cola: 0). Se estima con las pasadas de la última vez (ajustadas
-- si el tramo es más largo o más corto); sin ella, unas 7 por nivel. Nunca llega a 1
-- hasta acabar: si tarda más de lo previsto, se acerca despacio
function ES:PlanProgress(profKey)
  local run = self.planRunning
  if not run or run.prof ~= profKey then
    return self.Jobs.Queued and self.Jobs.Queued("plan:" .. profKey .. ":") and 0 or nil
  end
  local last = self.db.planPasses and self.db.planPasses[profKey]
  local expected = last and last.passes * math.max(0.3, run.span / math.max(1, last.span)) or run.span * 7
  -- (la búsqueda tiene tope: Planner.GPS_MAX_WALKS, más los arreglos del final, que
  -- no lo tienen: con un usuario nuevo, 1-300 da hasta ~2300 pasadas en Sastrería. Sin
  -- esto, una previsión de antes del tope, de 3700, dejaba la barra a medias)
  expected = math.min(expected, (self.Planner.GPS_MAX_WALKS or math.huge) + 500)
  local x = (self.Planner.passes or 0) / math.max(1, expected)
  if x <= 0.9 then return x end
  return 0.9 + 0.09 * (1 - math.exp(-(x - 0.9) * 3)) -- (pasada la previsión: hasta 99%)
end

---------------------------------------------------------------------------
-- Tooltips
---------------------------------------------------------------------------
-- Por qué se para un plan, en una frase
local function StopReason(plan)
  local short, missing = {}, 0
  for itemID in pairs(plan.shortSupply) do
    short[#short + 1] = (ItemLabel(itemID, L["objeto "] .. itemID))
    if #short >= 3 then break end
  end
  for _ in pairs(plan.missingPrice) do missing = missing + 1 end
  if #short > 0 then
    return L["no quedan suficientes en la AH de: "] .. table.concat(short, ", ")
  elseif missing > 0 and not plan.scanTime then
    -- Sin escaneo de la AH, lo que solo se compra allí no tiene precio: lo que hay que
    -- hacer es escanear (antes solo decía "N materiales sin precio")
    return string.format(L["%d materiales sin precio: aún no tienes escaneo de la Casa de Subastas. Ábrela y pulsa Escanear"], missing)
  elseif missing > 0 then
    return string.format(L["%d materiales sin precio (no están en la AH)"], missing)
  end
  -- No quedan recetas de instructor: ¿hay otras que darían puntos y no se pueden usar?
  -- Se dice cuáles y por qué (Primeros auxilios a 270: lo que sigue son pergaminos de
  -- botín; antes solo decía "no hay más recetas de instructor" y parecía un fallo)
  local data, s = plan.ctx and plan.ctx.data, plan.stoppedAt
  if data and s then
    local why = { scroll = {}, rep = {}, spec = {}, favor = {} }
    local opts = plan.ctx.opts or {}
    -- (un pergamino cuenta solo si de verdad no hay de dónde sacarlo: ni vendedor, ni
    -- misión, ni la AH)
    local function NoSource(r)
      local src = ES.Waypoints.RecipeSource(r, plan.ctx.prices, opts.noQuests, opts.noLimited)
      return not (src and src.best)
    end
    for id, r in pairs(data.recipes) do
      local level = r.train or (r.t and r.t[1]) or 1
      if r.t and r.t[4] > s and level <= s and not r.gone and not ES:IsRecipeKnown(id) then
        local kind = (r.rep and not ES:RepMet(r.rep) and "rep")
          or (r.spec and not ES:HasSpecialization(r.spec) and "spec")
          or (r.favor and not opts.useFavor and "favor")
          or (r.scroll and not r.fee and not r.favor and NoSource(r) and "scroll")
        if kind then table.insert(why[kind], r.name) end
      end
    end
    local function Names(list)
      table.sort(list)
      local shown = {}
      for i = 1, math.min(3, #list) do shown[i] = list[i] end
      return table.concat(shown, ", ") .. (#list > 3 and ", …" or "")
    end
    if #why.scroll > 0 then
      return string.format(L["lo que sigue se aprende de pergaminos que no vende ningún vendedor ni están en la AH: %s"], Names(why.scroll))
    elseif #why.rep > 0 then
      return string.format(L["lo que sigue pide más reputación: %s"], Names(why.rep))
    elseif #why.spec > 0 then
      return string.format(L["lo que sigue es de una especialización que no tienes: %s"], Names(why.spec))
    elseif #why.favor > 0 then
      return string.format(L["lo que sigue se compra con Merchant's Favor (actívalo con su icono): %s"], Names(why.favor))
    end
  end
  return L["no hay más recetas de instructor para ese nivel"]
end

-- Donde se para, lo que puedes intentar con lo que llevas (ver Planner.Attempt):
-- una receta al 62% con material para 1 fabricación no da un punto seguro, pero
-- se puede probar. Con lo de tus bolsas aunque el icono esté apagado; lo que ya
-- gasta la ruta, descontado
local function AttemptHint(page, plan)
  local skill = plan.stoppedAt or plan.from
  local owned = ES:GetOwnedReagents(page.data)
  for _, o in ipairs(plan.owned or {}) do
    if owned[o.itemID] then owned[o.itemID] = owned[o.itemID] - o.quantity end
  end
  local try = ES.Planner.Attempt(page.data, skill, owned, function(id) return ES:IsRecipeKnown(id) end)
  if not try then return "" end
  return " " .. string.format(L["%sCon lo que llevas puedes intentarlo: %d× %s (%d%% de llegar a %d).|r"],
    "|cff66ccff", try.crafts, try.recipe.name, math.floor(try.prob * 100 + 0.5), skill + 1)
end

-- Lo que llevas de un material contando lo que ya convertiste: la ruta pide Runecloth
-- para hacer Bolt of Runecloth, y al convertirlo el Runecloth bajaba y la ruta volvía a
-- pedir comprarlo (Discord). Por cada intermedio que fabrica la ruta (plan.crafted), lo
-- que llevas de él vale lo que lleva de cada material (y así hacia abajo).
-- bags(itemID): lo que hay en las bolsas. Devuelve have(itemID)
-- `level`: de cada intermedio cuenta como mucho lo que la ruta aún gasta desde ahí (los
-- de más no son material de la ruta: si no, sobrarían Bolts y faltaría el Runecloth
-- suelto que pide otra receta)
local function ConvertedHave(plan, bags, level)
  local made, cap = {}, {}
  for _, c in ipairs(plan.crafted or {}) do
    if c.recipe and c.recipe.r and c.recipe.out then
      made[c.itemID] = c.recipe
      local rem = level and ES.Planner.CraftedNeedFrom(plan, c.itemID, level)
      -- (solo lo fabricado: lo de tus bolsas al calcular la ruta no pidió su material)
      cap[c.itemID] = rem and math.ceil(rem - 0.001) or c.quantity
    end
  end
  local function Held(itemID) return math.min(bags(itemID), cap[itemID] or math.huge) end
  local inside = {} -- [material] = { { intermedio, unidades por intermedio } }
  local function Walk(top, itemID, per, depth)
    local r = made[itemID]
    if not r or depth > 3 then return end
    local outN = math.max(1, r.out[2] or 1)
    for _, rg in ipairs(r.r) do
      local q = per * rg[2] / outN
      inside[rg[1]] = inside[rg[1]] or {}
      table.insert(inside[rg[1]], { top, q })
      Walk(top, rg[1], q, depth + 1)
    end
  end
  for itemID in pairs(made) do Walk(itemID, itemID, 1, 1) end
  return function(itemID)
    local n = bags(itemID)
    for _, x in ipairs(inside[itemID] or {}) do n = n + math.floor(Held(x[1]) * x[2] + 0.001) end
    return n
  end
end

-- Lo que llevas para la ruta (bolsas y correo, con lo ya convertido): Planner.RouteNeed
-- lo usa para saber si ya lo tienes todo (Planner.Stocked)
function ES.RouteHave(plan, level)
  return ConvertedHave(plan, function(itemID)
    return ES.HaveForShopping and ES:HaveForShopping(itemID) or ES:ItemCount(itemID) or 0
  end, level)
end

-- Avisos en el chat (con el addon abierto o no), A LA PAR que el asistente: salen de
-- sus mismas filas (ES:RouteLines con opts.buy), así que nunca piden otra cosa ni en
-- otro momento:
--   · tramo nuevo: sus recetas y cuántos materiales faltan (las filas de compra);
--   · sin materiales: el paso pasa de fabricar a comprar (no puedes fabricar ni una
--     vez más y aún no llegas). Mientras puedas fabricar, nada: primero acabas lo que
--     pide el paso. Antes salía "Siguiente tanda (hasta 58): te faltan ~7 Coarse
--     Thread" a mitad de "Fabrica 46× Linen Bag", con otro cálculo que el asistente
-- Se llama al subir un punto y al cambiar las bolsas (fabricar gasta materiales sin
-- subir siempre un punto)
ES.phaseState = {}
-- lines, plan: las filas que el asistente acaba de hacer (A.Update), para no rehacerlas
function ES:PhaseNotices(profKey, lines, plan)
  local data = ES.Data[profKey]
  local level = data and data.skillLine and ES:GetProfessionSkill(data.skillLine)
  if not (level and ES:RouteLock(profKey)) then return end
  if not lines then lines, plan = ES:RouteLines(profKey, { buy = true, lean = true }) end
  local ph = lines and ES.Planner.Phase(plan, level)
  if not ph then return end
  local cur, items = nil, {}
  for _, l in ipairs(lines) do
    if l.current and not cur then cur = l end
    if l.buyRow and not l.done then
      for _, it in ipairs(l.buyItems or {}) do items[#items + 1] = it end
    end
  end
  local buying = cur ~= nil and cur.buyRow ~= nil
  local state = ES.phaseState[profKey] or {}
  ES.phaseState[profKey] = state
  local phaseKey = ph.steps[1].from .. ":" .. ph.to -- (el mismo tramo aunque subas dentro de él)
  if state.last == nil then
    -- Primera vez (al entrar al juego): el asistente ya lo enseña
    state.buyWarned = buying
  elseif state.last ~= phaseKey then
    local names = {}
    for _, st in ipairs(ph.steps) do names[#names + 1] = st.recipe.name end
    ES:Print(string.format(L["Tramo nuevo %s: %s."], ph.from .. "-" .. ph.to, table.concat(names, ", "))
      .. (#items > 0 and (" " .. string.format(L["Te faltan %d materiales: están en la Lista de compra."], #items)) or ""))
    -- La lista de la compra ha cambiado sola: que se note (si hay algo que comprar)
    if #items > 0 then ES:FlashTab("shopping", true) end
    state.buyWarned = buying -- (ya lo dice este aviso)
  elseif not buying then
    state.buyWarned = nil
  elseif not state.buyWarned then
    state.buyWarned = true
    local first = cur.buyItems and cur.buyItems[1]
    if first then
      local more = #items > 1 and string.format(L[" y %d más"], #items - 1) or ""
      local name = ES:DataItemName(first.itemID) or first.itemID
      -- (lo mismo que pide la fila: la tanda siguiente; sin hablar de suerte)
      ES:Print(string.format(cur.buyRow == "bank" and L["Para seguir fabricando, saca %d %s%s del banco."]
        or L["Para seguir fabricando, compra %d %s%s. Está en la Lista de compra."], first.quantity, name, more))
      if cur.buyRow ~= "bank" then ES:FlashTab("shopping", true) end
    end
  end
  state.last = phaseKey
end

-- Al gastar materiales fabricando (o comprarlos) el paso puede pasar a comprar sin que
-- suba un punto: también se mira entonces (una vez por tanda de cambios)
do
  local f, stamp = CreateFrame("Frame"), 0
  ES.SafeRegister(f, "BAG_UPDATE_DELAYED")
  f:SetScript("OnEvent", function()
    if not ES.db then return end
    stamp = stamp + 1
    local mine = stamp
    C_Timer.After(0.5, function()
      if mine ~= stamp then return end
      -- (la del asistente no: él rehace sus filas con este mismo cambio de las bolsas y
      -- los avisos salen de ellas, A.Update; antes se hacían dos veces)
      local assisted = ES.Assistant and ES.Assistant.BuildsFor and ES.Assistant.BuildsFor()
      for _, p in ipairs(ES.PROFESSIONS or {}) do
        -- (solo las que ya tienen estado: el primer aviso lo pone la subida de nivel)
        if p.key ~= assisted and ES.Data[p.key] and ES.phaseState[p.key] and ES:RouteLock(p.key) then
          local ok, err = pcall(ES.PhaseNotices, ES, p.key)
          if not ok and ES.RecordError then ES:RecordError("avisos de tramo", err) end
        end
      end
    end)
  end)
end

---------------------------------------------------------------------------
-- Alternativas de cada paso: la segunda mejor receta y por qué es peor
---------------------------------------------------------------------------
local ALT_BUDGET = 8   -- ms por fotograma calculándolas (se reparten: no traban el juego)
local ALT_BATCH = 10   -- sin debugprofilestop: pasadas por fotograma
local ALT_SHOWN = 3    -- en el tooltip, las mejores

-- Motivo en el idioma del addon (al pintar: si se cambia de idioma, cambia)
local function AltReason(st, alt)
  local k = ES.Planner.AlternativeReason(st, alt)
  if k == "materials" then return L["materiales más caros"] end
  if k == "sale" then return L["se recupera menos vendiéndolo"] end
  if k == "fee" then return L["hay que aprenderla"] end
  if k == "crafts" then return L["hacen falta más fabricaciones"] end
  return L["encarece otros pasos de la ruta"]
end

-- Por qué la ruta no usa una alternativa más barata en oro (ver Planner.AlternativeVerdict)
local function WhyNotText(v, plan, alt)
  if v == "learnFew" then return string.format(L["aprenderla para %d fabricaciones no compensa"], math.floor((alt.step.crafts or 0) + 0.5)) end
  if v == "zigzag" then return L["dejaría un salto de pocos puntos entre recetas"] end
  if v == "crafts" then
    return string.format(L["%d fabricaciones más"], math.floor((alt.crafts or 0) - ES.Planner.TotalCrafts(plan) + 0.5))
  end
  if v == "steps" then return L["un paso más en la ruta"] end
  if v == "unfollowable" then return L["la ruta no se podría seguir en orden"] end
  return L["la ruta también cuenta fabricaciones, pasos y lo de tus bolsas"]
end

-- Calcula, poco a poco, las alternativas de cada paso de la ruta y repinta al acabar
-- (plan.alts[i] = lista de la más barata a la más cara; vacía si no hay otra receta)
function ES:ComputeAlternatives(page, plan)
  -- (la misma ruta en otra página, la de la ventana rehecha al cambiar de idioma: sigue
  -- con lo que ya iba calculado y repinta esa; si no, la página vieja lo cortaba)
  if plan.altsRunning and plan.altsPage ~= page then plan.altsPage = page return end
  if plan.alts or plan.altsRunning or not plan.choice or not (plan.ctx and plan.ctx.opts) then return end
  plan.altsRunning, plan.altsPage = true, page
  local P, data = self.Planner, page.data
  local jobs, results = {}, {}
  for i, st in ipairs(plan.steps) do
    results[i] = {}
    for _, id in ipairs(P.AlternativeCandidates(data, plan, st)) do jobs[#jobs + 1] = { i, id } end
  end
  local k = 1
  local function Work()
    local page = plan.altsPage
    if page.plan ~= plan then plan.altsRunning, plan.altsPage = nil, nil return end -- ruta nueva: se deja
    -- Como los cálculos de Jobs.lua: con la ventana cerrada o en combate se espera (se
    -- mira otra vez cada segundo); antes seguía gastando hasta 8 ms de cada fotograma
    local main = CraftersJournalMainFrame
    if C_Timer and ((main and not main:IsShown()) or (InCombatLockdown and InCombatLockdown())) then
      C_Timer.After(1, Work)
      return
    end
    local started = debugprofilestop and debugprofilestop()
    local n = 0
    while k <= #jobs do
      local i, id = jobs[k][1], jobs[k][2]
      local alt = P.EvaluateAlternative(data, plan, plan.steps[i], id)
      if alt then table.insert(results[i], alt) end
      k, n = k + 1, n + 1
      if started then
        if debugprofilestop() - started > ALT_BUDGET then break end
      elseif n >= ALT_BATCH then break end
    end
    if k <= #jobs then C_Timer.After(0, Work) return end
    -- (de mejor a peor con la vara de la ruta, RouteScore: la primera es la que el
    -- planificador pondría en segundo lugar)
    for _, list in pairs(results) do
      table.sort(list, function(a, b)
        if a.score ~= b.score then return a.score < b.score end
        return a.delta < b.delta
      end)
    end
    plan.alts, plan.altsRunning, plan.altsPage = results, nil, nil
    if page:IsVisible() and page.plan == plan then ES:RenderPlan(page) end
  end
  -- (en el fotograma siguiente: la ruta recién calculada se pinta al acabar su trabajo,
  -- con el fotograma ya gastado; empezar aquí lo alargaba otros ALT_BUDGET ms)
  C_Timer.After(0, Work)
end

-- Las mejores alternativas del paso, con sus cifras frente a la de la ruta
-- `row`: la fila (o el asistente); lo de la X, solo si la tiene
local function AddAltTooltip(plan, i, data, row)
  local withX = row and row.onSkip ~= nil
  local list = plan.alts and plan.alts[i]
  if list and #list == 0 then return end -- (sin alternativa que valga: nada que contar)
  GameTooltip:AddLine(" ")
  if not list then
    GameTooltip:AddLine(L["Comparando con otras recetas…"], 0.6, 0.6, 0.6)
    return
  end
  local st = plan.steps[i]
  GameTooltip:AddLine(L["Por qué esta y no otra:"], 1, 0.82, 0)
  for n = 1, math.min(ALT_SHOWN, #list) do
    local alt = list[n]
    local a, r = alt.step, data.recipes[alt.id]
    GameTooltip:AddDoubleLine(string.format("%d. %s", n + 1, r and r.name or "?"),
      alt.delta >= 0.5 and (RED .. "+" .. ES.Money(alt.delta) .. "|r")
      or alt.delta <= -0.5 and (GREEN .. "-" .. ES.Money(-alt.delta) .. "|r") or L["igual"], 1, 1, 1, 1, 1, 1)
    GameTooltip:AddLine("   " .. string.format(L["%d fabricaciones (aquí %d) · %s/u (aquí %s) · recuperas %s/u (aquí %s)"],
      a.crafts, st.crafts, ES.Money(a.unitCost), ES.Money(st.unitCost), ES.Money(a.unitValue), ES.Money(st.unitValue))
      .. ((a.fee or 0) > 0 and (" · " .. L["aprender"] .. " " .. ES.Money(a.fee)) or ""), 0.75, 0.75, 0.75, true)
    local v = ES.Planner.AlternativeVerdict(plan, st, alt)
    if v == "better" then
      GameTooltip:AddLine("   " .. (withX and L["Sale mejor que la de la ruta: quita la de la ruta con su |TInterface/Buttons/UI-GroupLoot-Pass-Up:0|t para usar esta."]
        or L["Sale mejor que la de la ruta."]), 0.4, 1, 0.4, true)
    elseif v == "crafts" then
      GameTooltip:AddLine("   " .. L["La ruta prefiere pagar un poco más a cambio de fabricar menos veces."], 0.75, 0.75, 0.75, true)
    elseif v then
      GameTooltip:AddLine("   " .. string.format(L["Más barata en oro, pero la ruta no la usa: %s."], WhyNotText(v, plan, alt)), 0.75, 0.75, 0.75, true)
    else
      GameTooltip:AddLine("   " .. L["Peor porque: "] .. AltReason(st, alt), 0.75, 0.75, 0.75, true)
    end
    if alt.ahGain > alt.delta + 0.5 then
      GameTooltip:AddLine("   " .. string.format(L["Vendiendo lo fabricado en la AH saldría %s mejor que la ruta, si se vende (la ruta cuenta el vendedor, que es lo seguro)."],
        ES.Money(alt.ahGain - alt.delta)), 1, 0.82, 0, true)
    end
  end
end

-- Comprar o fabricar un material (si tiene receta): una línea gris para debajo del
-- material, con lo que cuesta la otra forma de conseguirlo y por qué la ruta no la usa.
-- `unit`: lo que cuesta como lo consigue la ruta; `crafted`: la ruta lo fabrica.
-- nil si no se puede fabricar o falta algún precio
local function CraftCompareText(plan, itemID, unit, crafted)
  if not (plan and plan.ctx and plan.ctx.producers) then return nil end
  local craftUnit, recipe = ES.Planner.CraftUnitCost(plan.ctx, itemID)
  if not craftUnit then return nil end
  local mats = {}
  for _, rq in ipairs(recipe.r) do
    mats[#mats + 1] = rq[2] .. "× " .. (ES:DataItemName(rq[1]) or (ItemLabel(rq[1], L["objeto "] .. rq[1])))
  end
  local how = table.concat(mats, ", ")
  if crafted then
    local ladder = plan.ctx.ladders and plan.ctx.ladders[itemID]
    local buy = ES.Data.VendorPrices and ES.Data.VendorPrices[itemID] or (ladder and ladder[1])
    if not buy then return nil end
    return string.format(L["fabricarlo (%s): %s/u · comprarlo hecho: %s/u"], how, ES.Money(craftUnit), ES.Money(buy))
  end
  local text = string.format(L["comprado: %s/u · fabricarlo (%s): %s/u"], ES.Money(unit), how, ES.Money(craftUnit))
  if craftUnit < unit then
    -- Más barato fabricarlo y aun así se compra: su receta da puntos donde se usa
    local st = ES.Planner.CraftTakesPoints(plan, itemID, recipe)
    if st then text = text .. " · " .. string.format(L["fabricarlo quitaría puntos a %s"], st.recipe.name) end
  end
  return text
end
ES.UI.CraftCompareText = CraftCompareText -- (asistente y pruebas)

-- Tooltip de un paso: solo lo que no se ve en la fila (la fila ya dice fabricaciones,
-- puntos, coste y tiempo): por qué tantas fabricaciones, los materiales (y si comprar
-- o fabricarlos), lo que se guarda y lo que se podría sacar en la AH
local function RecipeTooltip(step, plan)
  return function(row)
    local r = step.recipe
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(ItemLabel(r.out and r.out[1] or 0, r.name))
    GameTooltip:AddLine(string.format(L["Amarilla desde %d · verde desde %d · gris desde %d"], r.t[2], r.t[3], r.t[4]), 0.8, 0.8, 0.8)
    GameTooltip:AddLine(string.format(L["Probabilidad de subir: del %d%% al %d%%"],
      math.floor(step.firstChance * 100 + 0.5), math.floor(step.lastChance * 100 + 0.5)), 0.8, 0.8, 0.8)

    -- Si sale caro por baja probabilidad, explicar por qué no hay algo mejor
    if step.expected / (step.to - step.from) > LOW_CHANCE_CRAFTS then
      if #step.blocked > 0 then
        GameTooltip:AddLine(L["Hay recetas con más probabilidad, pero falta el precio de algún material en la AH:"], 1, 0.5, 0, true)
        for i, rid in ipairs(step.blocked) do
          if i > 4 then break end
          local br = plan.ctx.data.recipes[rid]
          local missing = {}
          for itemID in pairs(step.blocked[rid]) do missing[#missing + 1] = (ItemLabel(itemID, L["objeto "] .. itemID)) end
          GameTooltip:AddLine("  " .. (ItemLabel(br.out and br.out[1] or 0, br.name)) .. L[": falta "] .. table.concat(missing, ", "), 1, 0.7, 0.4, true)
        end
        GameTooltip:AddLine(L["Si consigues esos materiales (o aparecen en la AH), el plan las usará."], 0.8, 0.8, 0.8, true)
      else
        GameTooltip:AddLine(L["No hay ninguna receta de instructor mejor en este tramo: esta es la única opción."], 1, 0.5, 0, true)
      end
    end

    -- Materiales de todo el paso, con su precio medio real de compra y, si tienen
    -- receta, lo que costaría conseguirlos de la otra forma (comprar o fabricar)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Materiales de este paso:"], 1, 0.82, 0)
    for _, rg in ipairs(step.reagents) do
      local name = ItemLabel(rg.item, L["Objeto "] .. rg.item)
      local kinds = {}
      for kind in pairs(rg.kinds) do kinds[#kinds + 1] = SOURCE_LABEL[kind] or kind end
      GameTooltip:AddDoubleLine(string.format("%dx %s", math.ceil(rg.qty - 0.001), name),
        string.format("%s %s(%s)|r", ES.Money(rg.cost), GREY, table.concat(kinds, "+")),
        1, 1, 1, 1, 1, 1)
      if not rg.kinds.stock and not rg.kinds.owned and rg.qty > 0 then
        local cmp = CraftCompareText(plan, rg.item, rg.cost / rg.qty, rg.kinds.craft ~= nil)
        if cmp then GameTooltip:AddLine("   " .. cmp, 0.6, 0.6, 0.6, true) end
      end
    end

    -- Parte de lo fabricado se usa más adelante en el plan
    local kept = r.out and plan.keptByItem[r.out[1]]
    if kept then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(string.format(L["Guarda %d para pasos posteriores."], kept), 0.6, 1, 0.6, true)
    end

    -- Lo que se recupera vendiendo lo fabricado (la ruta cuenta el vendedor, lo
    -- seguro); solo si en la AH se sacaría más, cuánto
    local sale = step.sale
    if sale then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(string.format(L["Vendido al vendedor recuperas %s por fabricación."], ES.Money(step.unitValue)), 0.8, 0.8, 0.8, true)
      if sale.ahNet then
        GameTooltip:AddLine(string.format(L["Si lo vendes en la AH podrías sacar hasta %s más en este paso, pero no se sabe cuántos se venden."],
          ES.Money(step.crafts * sale.qty * (sale.ahNet - sale.vendor))), 1, 0.82, 0, true)
        ES.Market.AddToTooltip(sale.itemID)
      end
      if sale.risk then
        GameTooltip:AddLine(L["Precio poco fiable: "] .. sale.risk .. ".", 1, 0.5, 0, true)
      end
    end
    GameTooltip:Show()
  end
end

local function DestinationTooltip(d, name, signals)
  return function(row)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(name)
    GameTooltip:AddLine(string.format(L["Fabricas %d en total en el plan."], d.produced), 0.8, 0.8, 0.8)
    GameTooltip:AddLine(" ")
    if d.keep > 0 then
      GameTooltip:AddLine(string.format(L["Guarda %d (no los vendas):"], d.keep), 0.4, 1, 0.4)
      for _, u in ipairs(d.usedIn) do
        local where = u.step and string.format(L[" (paso %d-%d)"], u.step.from, u.step.to) or ""
        GameTooltip:AddLine(string.format(L["  %dx para %s%s"], u.qty, (ItemLabel(u.recipe.out and u.recipe.out[1] or 0, u.recipe.name)), where), 1, 1, 1, true)
      end
    end
    if d.sell > 0 then
      GameTooltip:AddLine(string.format(L["Te sobran %d. El plan cuenta venderlos al vendedor a %s cada uno."],
        d.sell, ES.Money(d.sale.vendor)), 0.8, 0.8, 0.8, true)
      if signals then
        GameTooltip:AddLine(string.format(L["En la AH te quedarían %s cada uno igualando a la más barata (subasta de 24 h, comisión y depósito de %s descontados): hasta %s más en total."],
          ES.Money(d.sale.ahNet), ES.Money(d.sale.deposit), ES.Money(d.ahExtra)), 1, 0.82, 0, true)
        GameTooltip:AddLine(L["Pero el juego no dice cuántos se venden: puede que no los vendas todos, o ninguno. Anuncia unos pocos y mira las alertas:"], 1, 0.6, 0.2, true)
        ES.Market.AddToTooltip(d.itemID)
      end
      -- Consejo final
      local a = d.advice or ES.Planner.SaleAdvice(d)
      GameTooltip:AddLine(" ")
      if a.ah > 0 and a.verdict == "good" then
        GameTooltip:AddLine(string.format(L["Consejo: pon los %d en la AH a %s (1 cobre menos que la más barata)."], a.ah, ES.Money(a.price)), 0.4, 1, 0.4, true)
      elseif a.ah > 0 then
        GameTooltip:AddLine(string.format(L["Consejo: pon solo %d en la AH a %s para probar y vende el resto al vendedor; si se venden, anuncia más."], a.ah, ES.Money(a.price)), 1, 0.82, 0, true)
      elseif signals and signals.verdict == "avoid" then
        GameTooltip:AddLine(L["Consejo: con estas alertas, mejor véndelos al vendedor."], 1, 0.4, 0.4, true)
      elseif a.vendor > 0 then
        GameTooltip:AddLine(L["Consejo: véndelos al vendedor; en la AH no compensa la diferencia."], 0.8, 0.8, 0.8, true)
      end
    end
    GameTooltip:Show()
  end
end

local function ShopTooltip(it, plan)
  return function(row)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink("item:" .. it.itemID)
    if it.source == "ah" then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(string.format(L["%d uds a %s de media, comprando de la más barata a la más cara (ahora hay %d a la venta)."],
        it.quantity, ES.Money(it.unit), it.supply or 0), 0.8, 0.8, 0.8, true)
      if it.supply and it.quantity > it.supply then
        GameTooltip:AddLine(string.format(L["Hacen falta más de las que hay: las %d que faltan se cuentan al precio típico (mediana)."],
          it.quantity - it.supply), 1, 0.6, 0.2, true)
      end
    end
    -- Si también se puede fabricar: por qué se compra en vez de hacerlo tú (la misma
    -- línea que en el paso y en el asistente)
    local cmp = CraftCompareText(plan, it.itemID, it.unit)
    if cmp then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(cmp, 0.8, 0.8, 0.8, true)
    end
    if it.source == "vendor" then
      ES.Waypoints.AddToTooltip(L["Vendedor más cercano"], ES.Waypoints.Target("vendor", it.itemID))
    end
    GameTooltip:Show()
  end
end

local function SimpleTooltip(itemID, text)
  return function(row)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink("item:" .. itemID)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(text, 0.6, 1, 0.6, true)
    GameTooltip:Show()
  end
end

---------------------------------------------------------------------------
-- Filas de la lista
---------------------------------------------------------------------------
-- Los clics de un marco de tooltip pasan al de debajo (la fila). En combate el juego
-- lo bloquea (SetPropagateMouseClicks: ADDON_ACTION_BLOCKED al abrir una ruta peleando,
-- una vez por fila): se deja para cuando acabe; mientras, el icono no pasa el clic
local pendingClicks = {}
local function PassClicks(frame)
  if InCombatLockdown and InCombatLockdown() then
    pendingClicks[#pendingClicks + 1] = frame
    return
  end
  if frame.SetMouseClickEnabled then frame:SetMouseClickEnabled(false) end
  if frame.SetPropagateMouseClicks then frame:SetPropagateMouseClicks(true) end
end
do
  local f = CreateFrame("Frame")
  ES.SafeRegister(f, "PLAYER_REGEN_ENABLED")
  f:SetScript("OnEvent", function()
    local list = pendingClicks
    pendingClicks = {}
    for _, frame in ipairs(list) do PassClicks(frame) end
  end)
end
ES.UI.PassClicks = PassClicks

-- Tooltip del objeto al pasar el ratón por un icono (en filas propias de otras
-- páginas: la calculadora). getItem() da el itemID o nil. Los clics pasan a la fila
function ES.UI.ItemIconTooltip(row, icon, getItem)
  local hover = CreateFrame("Frame", nil, row)
  hover:SetAllPoints(icon)
  hover:EnableMouse(true)
  PassClicks(hover)
  hover:SetScript("OnEnter", function(self)
    local id = getItem()
    if not id then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink("item:" .. id)
    GameTooltip:Show()
  end)
  hover:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return hover
end

-- Clic en una fila (y en el asistente, que hace lo mismo que su fila: ES.UI.RowClick).
-- Filas de instructor o vendedor: marcar el camino al más cercano. Clic derecho: lo
-- que diga la línea (line.onRightClick; p. ej. "no venderlo nunca")
local function RowClick(self, button)
  if button == "RightButton" then
    if self.onRightClick then self.onRightClick() end
    return
  end
  -- Mayús+clic en una fila con objeto: como en el resto del juego, su nombre en la
  -- búsqueda de la AH abierta, o su enlace en el chat (ES:ItemShiftClick)
  if self.item and IsShiftKeyDown and IsShiftKeyDown() and ES:ItemShiftClick(self.item) then return end
  if self.onClick then
    self.onClick()
  elseif self.ahItem and ES:IsAuctionHouseOpen() then
    ES:SearchAuction(self.ahItem) -- (receta en la AH, con la AH abierta: buscarla)
  elseif self.go then
    ES.Waypoints.Go(self.go)
  end
end

-- Botón seguro encima de la fila al pasar el ratón (Waypoints.lua, HoverRow): usa el
-- objeto de la fila (row.useItem: aprender una receta que llevas; usar objetos es
-- protegido) o, en las de instructor o vendedor, pone la estrella. Es uno solo y
-- cuelga de UIParent: uno hijo de la fila dejaba protegida la ventana y cerrarla en
-- combate daba "acción bloqueada" (GitHub #11). En combate no hay botón
local function WantsHover(row)
  return row.useItem ~= nil or (row.go ~= nil and not row.onClick)
end

local function CreateRow(parent)
  local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
  row:SetWidth(LIST_WIDTH)
  row:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  local hl = row:CreateTexture(nil, "HIGHLIGHT")
  row.hl = hl
  hl:SetPoint("TOPLEFT", 2, -2)
  hl:SetPoint("BOTTOMRIGHT", -2, 2)
  hl:SetColorTexture(1, 0.82, 0.25, 0.08)

  -- Columna de nivel (vista Ruta): "72–75" en fabricar, "75" en aprender o entrenar.
  -- Sin ancho fijo (nunca se corta) y centrada en la columna y a media altura
  row.level = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  row.level:SetPoint("CENTER", row, "LEFT", LEVEL_W / 2 + 1, 0)
  row.level:SetWordWrap(false)
  row.levelLine = row:CreateTexture(nil, "ARTWORK")
  row.levelLine:SetSize(1, ROW_HEIGHT - 12)
  row.levelLine:SetPoint("LEFT", LEVEL_W, 0)
  row.levelLine:SetColorTexture(0.40, 0.29, 0.13, 0.8)

  -- Hueco del icono (30x30): el texto se alinea con él aunque el icono sea más
  -- pequeño (line.iconSize: texturas de botón, que ampliadas se ven pixeladas)
  row.iconSlot = row:CreateTexture(nil, "BACKGROUND")
  row.iconSlot:SetSize(30, 30)
  row.iconSlot:SetPoint("LEFT", 6, 0)
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(30, 30)
  row.icon:SetPoint("CENTER", row.iconSlot)
  row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  -- Ratón sobre el icono de un objeto: su tooltip del juego (el resto de la fila
  -- sigue con el suyo). Los clics pasan a la fila
  row.iconHover = CreateFrame("Frame", nil, row)
  row.iconHover:SetAllPoints(row.iconSlot)
  row.iconHover:EnableMouse(true)
  PassClicks(row.iconHover)
  row.iconHover:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink("item:" .. row.item)
    GameTooltip:Show()
  end)
  row.iconHover:SetScript("OnLeave", function() GameTooltip:Hide() end)

  row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  row.title:SetPoint("TOPLEFT", row.iconSlot, "TOPRIGHT", 10, -1)
  row.title:SetPoint("RIGHT", -170, 0)
  row.title:SetJustifyH("LEFT")
  row.title:SetWordWrap(false)

  row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.sub:SetPoint("BOTTOMLEFT", row.iconSlot, "BOTTOMRIGHT", 10, 1)
  row.sub:SetPoint("RIGHT", -170, 0)
  row.sub:SetJustifyH("LEFT")
  row.sub:SetWordWrap(false)
  row.sub:SetTextColor(0.75, 0.72, 0.65)

  row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.value:SetPoint("RIGHT", -12, 0)
  row.value:SetJustifyH("RIGHT")

  -- Fila de cita (line.quote): el texto en varias líneas entre comillas grandes,
  -- con margen alrededor para que ni las comillas ni el texto toquen el borde.
  -- La comilla se dibuja en la parte alta de su caja (unos 0,78 del tamaño por
  -- encima del pie): la de cerrar se baja para que su dibujo quede a QUOTE_PAD del borde
  local QUOTE_FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
  row.quoteOpen = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  row.quoteOpen:SetFont(QUOTE_FONT, QUOTE_SIZE)
  row.quoteOpen:SetText("\226\128\156") -- “
  row.quoteOpen:SetTextColor(1, 0.82, 0.25, 0.55)
  row.quoteOpen:SetPoint("TOPLEFT", QUOTE_PAD + 4, -QUOTE_PAD + 6)
  row.quoteClose = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  row.quoteClose:SetFont(QUOTE_FONT, QUOTE_SIZE)
  row.quoteClose:SetText("\226\128\157") -- ”
  row.quoteClose:SetTextColor(1, 0.82, 0.25, 0.55)
  row.quoteClose:SetPoint("BOTTOMRIGHT", -(QUOTE_PAD + 4), QUOTE_PAD - math.floor(QUOTE_SIZE * 0.78))
  row.quote = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.quote:SetFont(QUOTE_FONT, QUOTE_TEXT_SIZE)
  row.quote:SetPoint("LEFT", QUOTE_TEXT_X, 0) -- ancho: el de la fila menos los márgenes (StyleRow)
  row.quote:SetJustifyH("LEFT")
  row.quote:SetWordWrap(true)
  row.quote:SetSpacing(3)
  row.quote:SetTextColor(0.78, 0.75, 0.68) -- atenuado: es información, no un paso

  -- Encabezado de sección (sin recuadro)
  row.section = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  row.section:SetPoint("LEFT", 4, 0)

  -- ✕ para quitar la receta de la ruta (solo en los pasos de la ruta: line.onSkip)
  local skip = CreateFrame("Button", nil, row)
  row.skip = skip
  skip:SetSize(16, 16)
  skip:SetPoint("RIGHT", -8, 0)
  skip:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
  skip:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight", "ADD")
  skip:SetPushedTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Down")
  skip:SetScript("OnClick", function() if row.onSkip then row.onSkip() end end)
  skip:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(row.skipTitle or L["Quitar de la ruta"])
    GameTooltip:AddLine(row.skipTip or L["La ruta busca otra receta en su lugar (por ejemplo, si no quieres ir a por este pergamino)."], 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  skip:SetScript("OnLeave", function() GameTooltip:Hide() end)
  skip:Hide()

  row:SetScript("OnEnter", function(self)
    -- Botón seguro encima: estrella o usar el objeto de la fila (Waypoints.lua, HoverRow)
    if WantsHover(self) then ES.Waypoints.HoverRow(self) end
    if self.tooltip then self.tooltip(self) end
  end)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  -- Filas de instructor o vendedor: clic para marcar el camino al más cercano.
  -- Clic derecho: lo que diga la línea (line.onRightClick; p. ej. "no venderlo nunca")
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  row:SetScript("OnClick", RowClick)
  return row
end

-- Tooltip de una fila con camino: qué es, y el instructor o vendedor más cercano
local function TravelTooltip(title, text, label, pick)
  return function(row)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(title)
    if text then GameTooltip:AddLine(text, 0.8, 0.8, 0.8, true) end
    ES.Waypoints.AddToTooltip(label, pick)
    GameTooltip:Show()
  end
end

-- Alto de una línea de la lista: las de cita llevan el suyo (line.height)
local function LineHeight(line)
  return line.section and SECTION_HEIGHT or line.height or ROW_HEIGHT
end

-- Botones − y +para cambiar una cantidad (line.onStep(delta); con Mayús, de 5 en 5),
-- a la izquierda del valor. Solo se crean en las filas que los usan (lote de Ganar dinero)
local STEP_VALUE_COL = 130 -- ancho reservado al valor (cabe "+99g 99s 99c")
local function SetStepper(row, line)
  local onStep = line.onStep
  if not onStep then
    if row.stepper then row.stepper:Hide() end
    return
  end
  local s = row.stepper
  if not s then
    s = CreateFrame("Frame", nil, row)
    s:SetSize(44, 18)
    local function Button(label, sign, x)
      local b = CreateFrame("Button", nil, s, "UIPanelButtonTemplate")
      b:SetSize(20, 18)
      b:SetPoint("LEFT", x, 0)
      b:SetText(label)
      b:SetScript("OnClick", function()
        local step = (IsShiftKeyDown and IsShiftKeyDown()) and 5 or 1
        if row.onStep then row.onStep(sign * step) end
      end)
      b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(sign > 0 and L["Fabricar más"] or L["Fabricar menos"])
        GameTooltip:AddLine(L["Con Mayús, de 5 en 5. Tu cantidad dura hasta el siguiente escaneo; luego vuelve a la recomendada."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
      end)
      b:SetScript("OnLeave", function() GameTooltip:Hide() end)
      return b
    end
    s.minus = Button("-", -1, 0)
    s.plus = Button("+", 1, 22)
    row.stepper = s
  end
  row.onStep = onStep
  s:ClearAllPoints()
  -- A una distancia fija del borde (la columna del valor), alineados en todas las
  -- filas: pegados al valor bailaban según lo largo que fuera ("+1g 26s 85c" o "+16s 99c")
  local valueW = tonumber(row.value.GetStringWidth and row.value:GetStringWidth()) or 0
  -- (con la ✕ de la fila, el valor y los botones se apartan lo que ocupa: StyleRow)
  s:SetPoint("RIGHT", row, "RIGHT", -((row.onSkip and 30 or 12) + math.max(STEP_VALUE_COL, valueW) + 8), 0)
  s:Show()
  -- (el nombre y la línea de abajo acaban antes de los botones, sin meterse debajo)
  row.title:SetPoint("RIGHT", s, "LEFT", -6, 0)
  row.sub:SetPoint("RIGHT", s, "LEFT", -6, 0)
end

-- Pinta una línea en una fila y devuelve el alto que ocupa
local function StyleRow(row, line)
  local isSection = line.section ~= nil
  local isQuote = line.quote ~= nil
  row.quote:SetText(line.quote or "")
  row.quoteOpen:SetShown(isQuote)
  row.quoteClose:SetShown(isQuote)
  row.quote:SetShown(isQuote)
  row.hl:SetShown(not isQuote) -- la cita solo informa: no se resalta al pasar el ratón
  -- La cita, tan alta como su texto más el margen (como mínimo line.height)
  local height = LineHeight(line)
  if isQuote then
    -- Ancho fijo (la fila aún no está colocada): así el alto del texto ya se puede medir
    row.quote:SetWidth(math.max(100, (tonumber(row:GetWidth()) or LIST_WIDTH) - 2 * QUOTE_TEXT_X))
    local textH = tonumber(row.quote:GetStringHeight()) or 0
    height = math.max(height, math.ceil(textH) + 2 * (QUOTE_PAD + 8))
  end
  row:SetHeight(height)
  if isSection then
    row:SetBackdropColor(0, 0, 0, 0)
    row:SetBackdropBorderColor(0, 0, 0, 0)
  elseif line.total then
    row:SetBackdropColor(0.20, 0.14, 0.06, 0.95)
    row:SetBackdropBorderColor(0.68, 0.52, 0.20, 1)
  elseif line.current then
    -- Ruta empezada: el paso en el que estás
    row:SetBackdropColor(0.17, 0.13, 0.06, 0.96)
    row:SetBackdropBorderColor(1, 0.82, 0.25, 1)
  else
    row:SetBackdropColor(BROWN.row[1], BROWN.row[2], BROWN.row[3], BROWN.row[4])
    row:SetBackdropBorderColor(0.40, 0.29, 0.13, 1)
  end
  row.section:SetText(isSection and (GOLD .. line.section .. "|r") or "")
  -- Columna de nivel: todas las filas de la ruta la llevan; el resto empieza en el borde
  local hasLevel = line.level ~= nil
  local left = hasLevel and (LEVEL_W + 8) or 6
  row.level:SetText(hasLevel and ((line.done and GREY or "") .. line.level .. (line.done and "|r" or "")) or "")
  row.levelLine:SetShown(hasLevel)
  row.iconSlot:ClearAllPoints()
  row.iconSlot:SetPoint("LEFT", left, 0)
  row.icon:SetShown(not isSection and not isQuote and line.icon ~= nil)
  if line.icon == ES.QUEST_ICON then ES.SetQuestIcon(row.icon) else row.icon:SetTexture(line.icon) end
  -- Icono más pequeño (textura de botón): entera, sin recortar el borde como los de objeto
  row.icon:SetSize(line.iconSize or 30, line.iconSize or 30)
  if line.iconSize then row.icon:SetTexCoord(0, 1, 0, 1) elseif line.icon ~= ES.QUEST_ICON then row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
  row.title:SetText(not isQuote and line.title or "")
  -- "~104" -> "≈104": el "más o menos" con su icono (ES.APPROX, ver Assistant.lua)
  row.sub:SetText(not isQuote and line.sub and ES.APPROX and (line.sub:gsub("~", ES.APPROX)) or (not isQuote and line.sub) or "")
  row.value:SetText(line.value or "")
  -- Sin icono, el texto empieza más a la izquierda
  row.title:ClearAllPoints()
  row.sub:ClearAllPoints()
  local anchor, x = row.iconSlot, 10
  if not line.icon then anchor, x = row, left + 6 end
  if line.icon then
    row.title:SetPoint("TOPLEFT", anchor, "TOPRIGHT", x, -1)
    row.sub:SetPoint("BOTTOMLEFT", anchor, "BOTTOMRIGHT", x, 1)
  else
    row.title:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, -7)
    row.sub:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", x, 7)
  end
  row.title:SetPoint("RIGHT", -170, 0)
  row.sub:SetPoint("RIGHT", -170, 0)
  row.tooltip = line.tooltip
  row.item = line.item
  row.iconHover:SetShown(line.item ~= nil and line.icon ~= nil and not isSection)
  row.go = line.go
  row.ahItem = line.ahItem
  row.onClick = line.onClick
  row.onRightClick = line.onRightClick
  row.onSkip, row.skipTip, row.skipTitle = line.onSkip, line.skipTip, line.skipTitle
  row.skip:SetShown(line.onSkip ~= nil)
  row.value:ClearAllPoints()
  row.value:SetPoint("RIGHT", line.onSkip and -30 or -12, 0)
  SetStepper(row, line)
  row.useItem = line.useItem
  -- Repintada con el botón seguro encima (el ratón sigue ahí): que haga lo de la fila
  -- de ahora, no el pergamino o la estrella de la de antes. (En combate ya está suelto)
  local hover = ES.Waypoints.HoverButton()
  if hover and hover.row == row then
    if WantsHover(row) then ES.Waypoints.HoverRow(row) else ES.Waypoints.ReleaseHover() end
  end
  return height
end

-- Filas de dos líneas compartidas con otras páginas (Ganar dinero, Colección)
ES.UI.CreateRow, ES.UI.StyleRow, ES.UI.Signed, ES.UI.RowClick = CreateRow, StyleRow, Signed, RowClick
ES.UI.ROW_HEIGHT, ES.UI.ROW_GAP, ES.UI.SECTION_HEIGHT, ES.UI.LIST_WIDTH = ROW_HEIGHT, ROW_GAP, SECTION_HEIGHT, LIST_WIDTH

-- Ancho de las filas: el de la zona de la lista (llegan hasta el borde, también al
-- cambiar el tamaño de la ventana); sin ella, el fijo de siempre
local function ListWidth(page)
  local w = page.scroll and page.scroll:GetWidth()
  return (w and w > 50) and w or LIST_WIDTH
end
ES.UI.ListWidth = ListWidth

-- ¿Es `itemID` (GET_ITEM_INFO_RECEIVED) uno de los que faltaban al pintar la lista? Solo
-- esos repintan: un objeto que el servidor no da nunca dejaba la lista repintándose con
-- cada objeto que llegaba de cualquier otra cosa (bolsas, chat, otros addons)
function ES.UI.WaitingForItem(page, itemID)
  return page.pendingItems and itemID ~= nil and page.pendingItemIDs ~= nil and page.pendingItemIDs[itemID] == true
end

-- Pinta una lista de líneas (ver StyleRow) en page.content con page.rows
function ES.UI.RenderLines(page, lines)
  local y = 0
  page.pendingItems = false
  -- (y cuáles: solo su llegada repinta, ver ES.UI.WaitingForItem)
  local waiting = page.pendingItemIDs
  if waiting then for id in pairs(waiting) do waiting[id] = nil end else waiting = {} page.pendingItemIDs = waiting end
  local width = ListWidth(page)
  page.content:SetWidth(width)
  local currentY
  for i, line in ipairs(lines) do
    local row = page.rows[i] or CreateRow(page.content)
    page.rows[i] = row
    row:SetWidth(width)
    local height = StyleRow(row, line)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 0, -y)
    if line.current and not currentY then currentY = y end
    y = y + height + ROW_GAP
    if line.item and not ES:GetItemData(line.item) then page.pendingItems, waiting[line.item] = true, true end
    row:Show()
  end
  for i = #lines + 1, #page.rows do page.rows[i]:Hide() end
  page.content:SetHeight(math.max(1, y))
  -- Con menos filas que antes (dejar la ruta la rehace desde tu nivel, más corta), que
  -- no se quede desplazada más allá del final: el juego no lo limita solo y las
  -- primeras filas quedaban arriba, fuera de la vista, con un hueco vacío debajo
  -- (CurseForge: "falta 105-135 de Encantamiento")
  if page.scroll then
    if page.scroll.UpdateScrollChildRect then page.scroll:UpdateScrollChildRect() end
    local range = math.max(0, y - (tonumber(page.scroll:GetHeight()) or 0))
    if (tonumber(page.scroll:GetVerticalScroll() or 0) or 0) > range then page.scroll:SetVerticalScroll(range) end
  end
  -- Abierta desde el asistente: la lista baja hasta el paso actual (con un poco de lo
  -- de antes a la vista)
  if page.scrollToCurrent and currentY and page.scroll then
    page.scrollToCurrent = nil
    local range = math.max(0, y - (tonumber(page.scroll:GetHeight()) or 0))
    page.scroll:SetVerticalScroll(math.max(0, math.min(range, currentY - ROW_HEIGHT)))
  end
end

---------------------------------------------------------------------------
-- Página de la profesión
---------------------------------------------------------------------------
function ES:CreateProfessionPage(page, profKey)
  local data = ES.Data[profKey]
  self.db.prof = self.db.prof or {}
  self.db.prof[profKey] = self.db.prof[profKey] or {}
  local settings = self.db.prof[profKey]
  settings.sellAH, settings.duration, settings.reuseCrafted = nil, nil, nil -- opciones retiradas

  local prof
  for _, p in ipairs(ES.PROFESSIONS) do if p.key == profKey then prof = p end end
  page.data, page.profKey, page.rows, page.lines = data, profKey, {}, {}
  page.profName = ES:ProfLabel(profKey)
  page.profIcon = prof and prof.icon or ES.ICON
  page.view = "route"
  for _, v in ipairs(VIEWS) do if v.key == settings.view then page.view = v.key end end

  -- Fondo que agrupa toda la página (como el del diario de mazmorras): un marrón más
  -- claro, de la tarjeta de la profesión hasta debajo del total
  page.group = GroupPanel(page)

  -- Cabecera de la profesión
  local head = Panel(page, BROWN.card[1], BROWN.card[2], BROWN.card[3], BROWN.card[4])
  head:SetPoint("TOPLEFT", PAD, -PAD + 2)
  head:SetPoint("TOPRIGHT", -PAD, -PAD + 2)
  head:SetHeight(66)
  page.head = head

  local icon = head:CreateTexture(nil, "ARTWORK")
  icon:SetSize(44, 44)
  icon:SetPoint("LEFT", 12, 0)
  icon:SetTexture(prof and prof.icon or ES.ICON)
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

  local name = Label(head, page.profName, "GameFontNormalHuge")
  name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, 2)
  name:SetTextColor(0.96, 0.79, 0.25)

  page.levelText = Label(head, "", "GameFontHighlight")
  page.levelText:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 12, 0)

  -- Objetivo: lo único editable; al cambiarlo se recalcula
  page.toBox = CreateFrame("EditBox", nil, head, "InputBoxTemplate")
  page.toBox:SetSize(36, 18)
  page.toBox:SetAutoFocus(false)
  page.toBox:SetNumeric(true)
  page.toBox:SetMaxLetters(3)
  page.toBox:SetJustifyH("CENTER")
  page.toBox:SetPoint("LEFT", page.levelText, "RIGHT", 10, 0)
  page.toBox:SetText(ES:ProfessionTarget(profKey))
  local function TargetChanged(self)
    self:ClearFocus()
    ES:CalculatePlan(page)
  end
  page.toBox:SetScript("OnEnterPressed", TargetChanged)
  page.toBox:SetScript("OnEditFocusLost", function(self)
    if tonumber(self:GetText()) ~= page.lastTarget then ES:CalculatePlan(page) end
  end)
  page.toBox:SetScript("OnEscapePressed", function(self)
    self:SetText(page.lastTarget or MAX_SKILL)
    self:ClearFocus()
  end)

  -- Empezar ruta (la fija) / Dejar ruta (la suelta: vuelve la ruta sin empezar).
  -- Con la ruta empezada no hay "recalcular": si hay una mejor desde tu nivel, lo
  -- dice una fila arriba de la ruta (ver ES:CheckBetterRoute) y decides tú
  -- (a la derecha de la línea de estado, bajo la franja de resumen: se coloca allí abajo)
  local routeButton = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
  page.routeButton = routeButton
  routeButton:SetSize(140, STATUS_BUTTON_H)
  routeButton:SetMotionScriptsWhileDisabled(true)
  -- Cada vez que abres la página se mira si hay una ruta mejor (una vez)
  page:HookScript("OnShow", function() page.shownToken = (page.shownToken or 0) + 1 end)
  routeButton:SetScript("OnClick", function()
    local now = GetTime and GetTime() or 0
    if ES:RouteLock(profKey) then
      -- El botón pasa de Empezar a Dejar en el mismo sitio: un doble clic soltaba la
      -- ruta recién fijada sin querer. Y dejarla pide un segundo clic
      if page.routeStartedAt and now - page.routeStartedAt < 1 then return end
      if not (page.leaveAsked and now - page.leaveAsked < 4) then
        page.leaveAsked = now
        ES:RenderPlan(page)
        C_Timer.After(4, function()
          if page.leaveAsked == now then page.leaveAsked = nil ES:RenderPlan(page) end
        end)
        return
      end
      page.leaveAsked = nil
      ES:StopRoute(profKey)
      ES:ClearHomeCache() -- con lo que llevas ahora
      ES:CalculatePlan(page)
    else
      page.routeStartedAt = now
      ES:StartRoute(page)
    end
  end)
  routeButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    if ES:RouteLock(profKey) then
      GameTooltip:AddLine(L["Dejar ruta"])
      GameTooltip:AddLine(L["Suelta tu ruta empezada y vuelve a la ruta calculada con lo que llevas ahora. Pide un segundo clic."], 0.8, 0.8, 0.8, true)
      GameTooltip:AddLine(L["Si hay una ruta mejor desde tu nivel, te lo dice una fila arriba de la ruta."], 0.6, 0.6, 0.6, true)
    else
      GameTooltip:AddLine(L["Empezar ruta"])
      GameTooltip:AddLine(L["Fija esta ruta: mientras compras en la AH, al vendedor o sacas del correo, ni la ruta ni su coste cambian. La lista de la compra va marcando lo que te falta."], 0.8, 0.8, 0.8, true)
      GameTooltip:AddLine(L["Púlsalo antes de empezar a comprar."], 0.5, 0.8, 1, true)
    end
    GameTooltip:Show()
  end)
  routeButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- Actualizar precios: misma ruta con el último escaneo. Con la ruta empezada siempre
  -- se ve; solo se puede pulsar si hay un escaneo más nuevo (ver RenderPlan)
  local pricesButton = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
  page.pricesButton = pricesButton
  pricesButton:SetSize(140, STATUS_BUTTON_H)
  pricesButton:SetPoint("RIGHT", routeButton, "LEFT", -6, 0)
  -- (desactivado también enseña su tooltip: que se sepa por qué)
  if pricesButton.SetMotionScriptsWhileDisabled then pricesButton:SetMotionScriptsWhileDisabled(true) end
  pricesButton:SetScript("OnClick", function()
    ES:RefreshRoutePrices(profKey)
    ES:CalculatePlan(page)
  end)
  pricesButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(L["Actualizar precios"])
    if page.pricesUpToDate then
      local scan = ES.db.scans and ES.db.scans[ES:RealmKey()]
      local mins = scan and math.floor((time() - scan.time) / 60)
      GameTooltip:AddLine(mins and string.format(L["Tu ruta ya usa tu último escaneo de la AH (de hace %d min). Cuando escanees otra vez, aquí aplicas los precios nuevos."], mins)
        or L["Tu ruta ya usa tu último escaneo de la AH. Cuando escanees otra vez, aquí aplicas los precios nuevos."], 1, 0.82, 0, true)
    elseif page.drift then
      GameTooltip:AddLine(string.format(L["Con el último escaneo, lo que te queda cuesta %s (con los precios de tu ruta, %s)."],
        ES.Money(page.drift.new), ES.Money(page.drift.old)), 1, 0.6, 0.2, true)
    end
    GameTooltip:AddLine(L["La misma ruta (mismas recetas en cada nivel) con los precios del último escaneo. Lo que llevas gastado y vendido se mantiene."], 0.8, 0.8, 0.8, true)
    GameTooltip:AddLine(L["Si hay una ruta mejor desde tu nivel, te lo dice una fila arriba de la ruta."], 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
  end)
  pricesButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
  pricesButton:Hide()

  -- Asistente (Assistant.lua): junto a Dejar ruta, solo con la ruta empezada y si el
  -- asistente está cargado (ver RenderPlan). Abre o cierra
  -- el banner con esta ruta
  local assistButton = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
  page.assistButton = assistButton
  assistButton:SetSize(STATUS_BUTTON_H + 4, STATUS_BUTTON_H)
  assistButton:SetPoint("RIGHT", routeButton, "LEFT", -6, 0)
  assistButton.icon = assistButton:CreateTexture(nil, "ARTWORK")
  assistButton.icon:SetPoint("TOPLEFT", 5, -4)
  assistButton.icon:SetPoint("BOTTOMRIGHT", -5, 4)
  assistButton.icon:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_03")
  assistButton.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  assistButton:SetScript("OnClick", function()
    if ES.Assistant then ES.Assistant.ToggleFor(profKey) end
  end)
  assistButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(L["Asistente de la ruta"])
    GameTooltip:AddLine(L["Sigue esta ruta paso a paso en un banner pequeño, sin la ventana del addon: qué toca, dónde ir y qué comprar. Clic otra vez para cerrarlo."], 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  assistButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
  assistButton:Hide()

  -- Botones de vista, de derecha a izquierda
  page.viewButtons = {}
  local prev
  for i = #VIEWS, 1, -1 do
    local v = VIEWS[i]
    -- Como los del diario de mazmorras: más altos, icono grande a la izquierda
    local b = CreateFrame("Button", nil, head, "UIPanelButtonTemplate")
    b:SetSize(v.width, VIEW_BUTTON_H)
    if prev then b:SetPoint("RIGHT", prev, "LEFT", -6, 0) else b:SetPoint("RIGHT", -12, 0) end
    b.icon = b:CreateTexture(nil, "OVERLAY")
    b.icon:SetSize(VIEW_BUTTON_H - 6, VIEW_BUTTON_H - 6)
    b.icon:SetPoint("LEFT", 3, 0)
    b.icon:SetTexture(v.icon)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b:SetText(v.label)
    local label = b:GetFontString()
    if label then
      label:ClearAllPoints()
      label:SetPoint("LEFT", b.icon, "RIGHT", 4, 0)
      label:SetPoint("RIGHT", -6, 0)
      label:SetJustifyH("CENTER")
    end
    b:SetScript("OnClick", function() ES:SelectProfessionView(page, v.key) end)
    b.key = v.key
    page.viewButtons[#page.viewButtons + 1] = b
    prev = b
  end

  -- Filtros: iconos que se tachan al desactivarlos y recalculan al pulsarlos.
  -- isOn() lee el ajuste; toggle() lo cambia; lines() da el texto del tooltip
  local function FilterIcon(anchor, texture, title, isOn, toggle, lines)
    local b = CreateFrame("Button", nil, head, "BackdropTemplate")
    -- (24 px y 3 de separación: con 26 y 4 el quinto icono, el de vendedores de stock
    -- limitado, empujaba el primero encima de la casilla del objetivo)
    b:SetSize(24, 24)
    -- Centrados en vertical con los botones de vista (Ruta, Materiales, Profit)
    b:SetPoint("RIGHT", anchor, "LEFT", anchor == prev and -8 or -3, 0)
    b:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10 })
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 3, -3)
    b.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    if texture == ES.QUEST_ICON then ES.SetQuestIcon(b.icon) else b.icon:SetTexture(texture) end
    if texture:find("Icons") then b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
    b.cross = b:CreateTexture(nil, "OVERLAY")
    b.cross:SetPoint("TOPLEFT", 4, -4)
    b.cross:SetPoint("BOTTOMRIGHT", -4, 4)
    b.cross:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b.icon)
    hl:SetColorTexture(1, 1, 1, 0.15)
    function b:Refresh()
      local on = isOn()
      self.icon:SetDesaturated(not on)
      self.icon:SetAlpha(on and 1 or 0.55)
      self.cross:SetShown(not on)
      self:SetBackdropBorderColor(on and 1 or 0.4, on and 0.82 or 0.4, on and 0.25 or 0.4, 1)
    end
    b:SetScript("OnClick", function(self)
      toggle()
      self:Refresh()
      ES:StopRoute(profKey) -- otra opción es otra ruta: decisión tuya (comprar o fabricar no la libera)
      ES:CalculatePlan(page)
      if self:IsMouseOver() then self:GetScript("OnEnter")(self) end
    end)
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
      GameTooltip:AddLine(title)
      for i, l in ipairs(lines()) do GameTooltip:AddLine(l, i == 1 and 1 or 0.7, i == 1 and 1 or 0.7, i == 1 and 1 or 0.7, true) end
      GameTooltip:AddLine(L["Pulsa para cambiarlo."], 0.5, 0.8, 1)
      if ES:RouteLock(profKey) then
        GameTooltip:AddLine(L["Con la ruta empezada, cambiarlo calcula una ruta nueva."], 1, 0.6, 0.2, true)
      end
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Refresh()
    return b
  end

  -- Usar lo de las bolsas
  page.bagsButton = FilterIcon(prev, "Interface\\Icons\\INV_Misc_Bag_08", L["Usar lo que tienes en bolsas"],
    function() return settings.useBags and true or false end,
    function() settings.useBags = not settings.useBags end,
    function()
      return { settings.useBags and L["La ruta usa primero tus materiales y solo compra lo que falta."]
        or L["La ruta compra todo, aunque lo tengas."] }
    end)

  -- Contar misiones para conseguir recetas (prueba piloto: solo en las profesiones con fuentes reales)
  if ES.Waypoints.SOURCED_PROFESSIONS[profKey] then
    page.questButton = FilterIcon(page.bagsButton, ES.QUEST_ICON, L["Recetas de misiones"],
      function() return settings.useQuests ~= false end,
      function() settings.useQuests = settings.useQuests == false end,
      function()
        return { settings.useQuests ~= false and L["Si una misión de tu bando da la receta, no cuesta oro. Lo que pida entregar no tiene precio: se ve en el tooltip de la receta."]
          or L["Las recetas solo se consiguen comprándolas (vendedor o Casa de Subastas)."] }
      end)
  end

  -- Vendedores de recetas de stock limitado (venden una y reponen con el tiempo; otros
  -- las acaparan para la AH): por defecto sí, es lo más barato. Desactivado, esas
  -- recetas solo cuentan por misión o en la AH (Waypoints.RecipeSource, noLimited)
  if ES.Waypoints.SOURCED_PROFESSIONS[profKey] then
    page.limitedButton = FilterIcon(page.questButton or page.bagsButton, "Interface\\Icons\\INV_Scroll_03",
      L["Vendedores de recetas de stock limitado"],
      function() return not settings.noLimited end,
      function() settings.noLimited = not settings.noLimited or nil end,
      function()
        return { not settings.noLimited and L["La ruta cuenta con ellos: suele ser lo más barato. Venden pocas y reponen con el tiempo, y a veces otros jugadores las acaparan para revenderlas."]
          or L["La ruta no cuenta con ellos: esas recetas solo se consiguen por misión o en la Casa de Subastas; si no, se usa otra receta."] }
      end)
  end

  -- Recetas de Merchant's Favor (fichas y reputación del campamento): por defecto no
  page.favorButton = FilterIcon(page.limitedButton or page.questButton or page.bagsButton, "Interface\\Icons\\INV_Misc_Coin_17",
    L["Recetas de Merchant's Favor"],
    function() return settings.useFavor and true or false end,
    function() settings.useFavor = not settings.useFavor or nil end,
    function()
      return { settings.useFavor and L["La ruta puede usar recetas que se compran con Merchant's Favor en el campamento de tu bando."]
        or L["La ruta no usa recetas de Merchant's Favor."] }
    end)

  -- Menos fabricaciones: pagar algo más por no fabricar decenas de veces una receta en verde
  page.fewerButton = FilterIcon(page.favorButton, "Interface\\Icons\\INV_Misc_PocketWatch_01",
    L["Menos fabricaciones"],
    function() return settings.fewerCrafts and true or false end,
    function() settings.fewerCrafts = not settings.fewerCrafts or nil end,
    function()
      return { settings.fewerCrafts and L["La ruta paga un poco más a cambio de fabricar menos y más rápido: evita las recetas en verde que piden varias fabricaciones por punto y las que tardan mucho en fabricarse."]
        or L["La ruta más barata, aunque pida más fabricaciones."] }
    end)

  -- Franja de resumen: materiales, ventas al vendedor, instructor y herramientas, total.
  -- Antes "Profit (vendiendo lo que fabricas)", pero son ingresos, no beneficio (CurseForge:
  -- "should be called Revenue"); y al vendedor, como el total de la vista Profit
  local strip = CreateFrame("Frame", nil, page)
  strip:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 4, -6)
  strip:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT", -4, -6)
  strip:SetHeight(56) -- (con aire bajo el total para la línea "con AH")
  page.strip = strip
  page.stats = {}
  -- (y el tiempo de fabricar la ruta: para elegir entre pagar algo más con "Menos
  -- fabricaciones" o dedicarle más tiempo). El total, siempre la última columna (la de
  -- la derecha del todo); el tiempo, justo antes
  local STATS = {
    { key = "materials", label = L["Materiales"] },
    { key = "profit",    label = L["Ventas al vendedor"] },
    { key = "fees",      label = L["Instructor y herramientas"] },
    { key = "time",      label = L["Tiempo fabricando"] },
    { key = "total",     label = L["Total"] },
  }
  local COL_OF = {}
  for i, s in ipairs(STATS) do COL_OF[s.key] = i - 1 end
  local COL = 152 -- (cinco columnas en el ancho de la lista)
  for i, s in ipairs(STATS) do
    local label = Label(strip, s.label, "GameFontDisableSmall")
    label:SetPoint("TOPLEFT", (i - 1) * COL + 6, -2)
    local value = Label(strip, "", s.key == "total" and "GameFontNormalLarge" or "GameFontHighlightLarge")
    value:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -3)
    page.stats[s.key] = value
  end
  -- El tiempo, con tooltip: qué cuenta y cómo cambiarlo
  local timeHover = CreateFrame("Frame", nil, strip)
  timeHover:SetPoint("TOPLEFT", strip, "TOPLEFT", COL_OF.time * COL + 2, 0)
  timeHover:SetSize(COL - 6, 44)
  timeHover:EnableMouse(true)
  timeHover:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(L["Tiempo fabricando"], 1, 0.82, 0)
    GameTooltip:AddLine(L["Lo que se tarda en fabricar todos los pasos de la ruta, sin contar los viajes. Con \"Menos fabricaciones\" la ruta tarda menos a cambio de pagar algo más."], 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  timeHover:SetScript("OnLeave", function() GameTooltip:Hide() end)
  -- Las ventas, con tooltip: qué cuentan y que lo de la AH está en la vista Profit (que
  -- aconseja anunciar algunas cosas: que no parezca que se contradicen)
  local salesHover = CreateFrame("Frame", nil, strip)
  salesHover:SetPoint("TOPLEFT", strip, "TOPLEFT", COL + 2, 0)
  salesHover:SetSize(COL - 6, 44)
  salesHover:EnableMouse(true)
  salesHover:SetScript("OnEnter", function(self)
    local plan = page.plan
    if not (plan and plan.steps and #plan.steps > 0) then return end
    -- (lo mismo que suma la vista Profit al pie: ProfitLines)
    local extra = 0
    for _, d in ipairs(plan.destinations or {}) do
      if d.sale and d.sale.ahNet and d.sell > 0 and d.ahExtra then extra = extra + d.ahExtra end
    end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(L["Ventas al vendedor"], 1, 0.82, 0)
    GameTooltip:AddLine(L["Lo que sacas vendiendo al vendedor todo lo que fabricas y no guardas para pasos siguientes. La ruta cuenta este precio porque es una venta segura."], 0.8, 0.8, 0.8, true)
    GameTooltip:AddLine(" ")
    if extra > 0 then
      GameTooltip:AddLine(string.format(L["En la vista %s verás qué conviene poner en la AH: hasta %s más, sin garantía de venta."],
        L["Profit"], ES.Money(extra)), 1, 0.82, 0, true)
    else
      GameTooltip:AddLine(string.format(L["En la vista %s verás qué hacer con cada cosa que fabricas."], L["Profit"]), 0.8, 0.8, 0.8, true)
    end
    GameTooltip:Show()
  end)
  salesHover:SetScript("OnLeave", function() GameTooltip:Hide() end)
  page.salesHover = salesHover
  -- Debajo del total: el posible total siguiendo el consejo de la vista Profit (unas
  -- cosas a la AH, el resto al vendedor). El total grande es el seguro; este depende
  -- de que lo de la AH se venda, y lo explica el tooltip
  page.totalAH = Label(strip, "", "GameFontNormalSmall")
  page.totalAH:SetPoint("TOPLEFT", page.stats.total, "BOTTOMLEFT", 0, -4)
  local totalHover = CreateFrame("Frame", nil, strip)
  totalHover:SetPoint("TOPLEFT", strip, "TOPLEFT", COL_OF.total * COL + 2, 0)
  totalHover:SetSize(COL - 6, 56)
  totalHover:EnableMouse(true)
  totalHover:SetScript("OnEnter", function(self)
    local t = page.totalAHInfo
    if not t then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(L["Total"], 1, 0.82, 0)
    GameTooltip:AddDoubleLine(L["Vendiendo al vendedor (seguro)"], Signed(t.net), 0.8, 0.8, 0.8)
    GameTooltip:AddDoubleLine(L["Siguiendo el consejo (AH y vendedor)"], Signed(t.advisedNet), 0.8, 0.8, 0.8)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(string.format(L["El segundo total cuenta lo que la vista %s aconseja anunciar en la AH a su precio actual. No es seguro: depende de que se venda, a ese precio y antes de que caduque la subasta. Lo del vendedor sí es seguro."],
      L["Profit"]), 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  totalHover:SetScript("OnLeave", function() GameTooltip:Hide() end)
  page.routeButton:SetPoint("TOPRIGHT", strip, "BOTTOMRIGHT", 0, 0)
  page.status = Label(page, "", "GameFontHighlightSmall")
  page.status:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", 2, -4)
  page.status:SetPoint("RIGHT", page.routeButton, "LEFT", -10, 0)
  page.status:SetJustifyH("LEFT")
  page.status:SetWordWrap(false)

  -- Barra de progreso mientras se calcula la ruta (al lado de "Calculando la ruta… 42%")
  page.calcBar = CreateFrame("StatusBar", nil, page)
  page.calcBar:SetHeight(8)
  page.calcBar:SetPoint("LEFT", page.status, "LEFT", 190, 0)
  page.calcBar:SetPoint("RIGHT", page.routeButton, "LEFT", -12, 0)
  page.calcBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  page.calcBar:SetStatusBarColor(0.95, 0.75, 0.25)
  page.calcBar:SetMinMaxValues(0, 1)
  local calcBg = page.calcBar:CreateTexture(nil, "BACKGROUND")
  calcBg:SetAllPoints()
  calcBg:SetColorTexture(0, 0, 0, 0.5)
  page.calcBar:Hide()
  local since = 0
  page.calcBar:SetScript("OnUpdate", function(self, elapsed)
    since = since + (elapsed or 0)
    if since < 0.1 then return end
    since = 0
    ES:UpdateCalcProgress(page)
  end)

  -- Lista
  local list = Panel(page, BROWN.list[1], BROWN.list[2], BROWN.list[3], BROWN.list[4])
  list:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -LIST_TOP)
  list:SetPoint("BOTTOMRIGHT", -PAD, PAD)
  page.listPanel = list
  local scroll = WheelScroll(list)
  scroll:SetPoint("TOPLEFT", 8, -8)
  scroll:SetPoint("BOTTOMRIGHT", -8, 8)
  page.content = CreateFrame("Frame", nil, scroll)
  page.content:SetSize(LIST_WIDTH, 1)
  scroll:SetScrollChild(page.content)
  page.scroll = scroll
  -- Al cambiar el tamaño de la ventana, las filas siguen llegando hasta el borde
  scroll:HookScript("OnSizeChanged", function()
    local width = ListWidth(page)
    page.content:SetWidth(width)
    for _, row in ipairs(page.rows) do row:SetWidth(width) end
  end)
  page.empty = Label(page.content, "", "GameFontDisable")
  page.empty:SetPoint("TOP", 0, -30)
  page.empty:SetWidth(600)

  ES.SafeRegister(page, "GET_ITEM_INFO_RECEIVED")
  page:SetScript("OnEvent", function(self, _, itemID, success)
    if not self.plan then return end
    -- Faltaban nombres (repintar) o precios de vendedor (recalcular). Solo recalcula
    -- si llega un objeto cuyo precio esperaba esta ruta: con cualquier objeto (los
    -- que pide el propio cálculo, bolsas, chat) la ruta de 88 a 300 se rehacía sin
    -- parar y tardaba 10 minutos en salir
    local waiting = self.plan.pendingItems
    if success ~= false and itemID and waiting and waiting[itemID] then self.recalcQueued = true end
    -- (sin verse, nada más: yendo por el mundo llegan sin parar; se repinta al verse)
    if not self:IsVisible() then return end
    if not (self.recalcQueued or ES.UI.WaitingForItem(self, itemID)) then return end
    -- Llegan en oleadas: se espera a que paren (cada uno reinicia la espera) y se
    -- recalcula una vez. Con 0,5 s desde el primero, cada oleada era un cálculo entero
    self.infoStamp = (self.infoStamp or 0) + 1
    local mine = self.infoStamp
    C_Timer.After(1.5, function()
      if mine ~= self.infoStamp then return end
      if not self:IsVisible() then return end
      if self.recalcQueued and not ES:RouteLock(self.profKey) then
        -- Calculando: no se tira lo hecho; se recalcula una vez al acabar (CalculatePlan)
        if self.calculating then return end
        self.recalcQueued = nil
        ES:InvalidatePlan(self.profKey) -- solo esta profesión (si no, la caché daría el precio antiguo)
        ES:CalculatePlan(self)
      else
        self.recalcQueued = nil
        ES:RenderPlan(self)
      end
    end)
  end)

  -- Al mostrarse: nivel actual del personaje (puede haber subido) y recalcular
  page:SetScript("OnShow", function(self)
    self.initialized = true
    ES:DetectSkill(self)
    ES:CalculatePlan(self)
    ES:SelectProfessionView(self, self.view)
  end)

  self.professionPages = self.professionPages or {}
  self.professionPages[#self.professionPages + 1] = page
end

-- Nivel actual: el del personaje (no se edita); si no tiene la profesión, 1
function ES:DetectSkill(page)
  local rank, maxRank = self:GetProfessionSkill(page.data.skillLine)
  page.from = rank or 1
  page.detected = rank and { rank = rank, cap = maxRank } or nil -- tope real (p. ej. 75 sin Oficial)
  page.levelText:SetText(string.format(L["Nivel %s%d|r%s   %sObjetivo:|r"], GOLD, page.from,
    rank and "" or (GREY .. L[" (no la tienes)|r"]), GREY))
end

function ES:SelectProfessionView(page, key)
  if not VIEW_KEYS[key] then key = "route" end -- "market" (Recetas) ya no existe: está en Colección
  page.view = key
  self.db.prof[page.profKey].view = key
  self.db.lastProf = page.profKey -- la lista de compra de la AH empieza por esta
  for _, b in ipairs(page.viewButtons) do
    if b.key == key then b:LockHighlight() else b:UnlockHighlight() end
  end
  -- Otra vista, desde arriba: si no, se quedaba desplazada como la anterior y sus
  -- primeras filas no se veían (CurseForge: en Profit "no salían" las Small Silk Pack,
  -- la primera fila; y la fila del modo de compra, la primera de Materiales). Abrirla
  -- desde el asistente (page.scrollToCurrent) baja después, en RenderLines
  if page.scroll then page.scroll:SetVerticalScroll(0) end
  self:RenderPlan(page)
end

-- Solo la que está a la vista: las demás se recalculan al mostrarse (OnShow),
-- así un escaneo no congela el juego recalculando las 8 profesiones
-- Cambian tus bolsas (compras, correo, fabricar): con la ruta fijada o sin "usar
-- lo de las bolsas" la ruta no cambia y basta con repintar (la lista de la compra
-- cuenta lo que llevas); sin fijar y con bolsas, se recalcula solo si cambió algún
-- objeto que usa la ruta (lootear otra cosa no la toca)
function ES:RefreshAfterBags()
  if self.Assistant then self.Assistant.Refresh() end -- (el paso actual puede cambiar)
  for _, page in ipairs(self.professionPages or {}) do
    if page.initialized and page:IsVisible() and page.data then
      local settings = self.db.prof and self.db.prof[page.profKey] or {}
      local cached = self.homePlanCache[page.profKey]
      local still = cached and cached.plan == page.plan and self.RouteBagsMatch(cached.bags)
      if settings.useBags and not settings.lock and not still then self:RecalcWhenQuiet(page) else self:RenderPlan(page) end
    end
  end
end

-- Aprendes una receta: con la ruta fijada se repinta (su fila de aprender queda
-- hecha); sin fijar, se recalcula (ya no hay que pagarla)
function ES:RefreshAfterLearn()
  if self.Assistant then self.Assistant.Refresh() end
  for _, page in ipairs(self.professionPages or {}) do
    if page.initialized and page:IsVisible() and page.data then
      if self:RouteLock(page.profKey) then self:RenderPlan(page) else self:CalculatePlan(page) end
    end
  end
  -- Ganar dinero: lo que sabes cambia sus ideas (lo que estaba en "Recetas que puedes
  -- aprender" pasa al lote). Su caché solo se vaciaba con un escaneo nuevo o al cambiar
  -- las bolsas: aprender del instructor no las cambia y seguía saliendo como por aprender
  if self.Earn then self.Earn:Clear() end
  if self.RenderEarn then self:RenderEarn() end
  if self.CraftWindow and self.CraftWindow.Refresh then self.CraftWindow:Refresh() end
end

-- Sube tu nivel (fabricando): la profesión abierta lo relee al momento. Con la ruta
-- empezada solo se repinta (paso actual, lo que falta, pasos hechos); sin empezar,
-- la ruta se recalcula desde el nivel nuevo
function ES:RefreshAfterSkill()
  if self.Assistant then self.Assistant.Refresh() end
  -- Avisos de compra por tramos de las rutas empezadas (aunque el addon esté cerrado).
  -- Protegidos: si uno falla, la página se refresca igual (si no, se quedaba con el
  -- nivel de antes: "17/18 puntos" estando ya más arriba y fabricando de 2 en 2)
  for _, p in ipairs(self.PROFESSIONS or {}) do
    if self.Data[p.key] and self:RouteLock(p.key) then
      local ok, err = pcall(self.PhaseNotices, self, p.key)
      if not ok and self.RecordError then self:RecordError("avisos de tramo", err) end
    end
  end
  for _, page in ipairs(self.professionPages or {}) do
    if page.initialized and page:IsVisible() and page.data then
      local before, capBefore = page.from, page.detected and page.detected.cap
      self:DetectSkill(page)
      -- (también al aprender un rango: sube el tope sin subir el nivel)
      if page.from ~= before or (page.detected and page.detected.cap) ~= capBefore then
        if self:RouteLock(page.profKey) and page.from < self:RouteLock(page.profKey).to then
          self:RenderPlan(page)
        elseif self:RouteLock(page.profKey) then
          self:CalculatePlan(page) -- (llegaste al final de la ruta empezada: completada)
        else
          self:RecalcWhenQuiet(page) -- (sin empezar: una vez al dejar de fabricar)
        end
      end
    end
  end
end

-- Para la fabricación en serie si sigue (lo que pidió "Crear todo" o un clic en la
-- ruta). Devuelve si había algo que parar
local function StopCraftRepeat()
  local T = C_TradeSkillUI
  local repeating = T and T.GetRecipeRepeatCount and (T.GetRecipeRepeatCount() or 0) > 0
  if repeating == false then return false end
  local stop = (T and T.StopRecipeRepeat) or StopTradeSkillRepeat
  if not stop then return false end
  return pcall(stop) and true or false
end

-- Al subir un punto: si llegas al tope de tu rango (75 sin Oficial, 150 sin Experto...)
-- o al final de la ruta empezada, seguir fabricando gasta materiales sin subir nada
-- más: se para la fabricación en serie y se dice por qué
ES.lastRanks = {}
function ES:CheckCraftStop()
  for _, p in ipairs(self.PROFESSIONS or {}) do
    local data = self.Data[p.key]
    local rank, cap
    if data and data.skillLine then rank, cap = self:GetProfessionSkill(data.skillLine) end
    if rank then
      local before = self.lastRanks[p.key]
      self.lastRanks[p.key] = rank
      local lock = self:RouteLock(p.key)
      if before and rank > before then
        local atCap = cap and rank >= cap
        local atEnd = lock and rank >= lock.to
        if (atCap or atEnd) and StopCraftRepeat() then
          self:Print(atCap and not atEnd
            and string.format(L["%s ha llegado al tope (%d): he parado la fabricación. Aprende el siguiente rango en el instructor."], self:ProfLabel(p.key), cap)
            or string.format(L["%s ha llegado al final de la ruta (%d): he parado la fabricación."], self:ProfLabel(p.key), rank))
        end
      end
    end
  end
end

do
  local f, stamp, skills = CreateFrame("Frame"), 0, nil
  for _, e in ipairs({ "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL" }) do ES.SafeRegister(f, e) end
  f:SetScript("OnEvent", function()
    if not ES.db then return end
    -- Solo si cambió el nivel o el tope de una profesión: un punto de arma o defensa
    -- (continuos en combate) no tiene nada que hacer aquí (ES:ProfessionSkillStamp)
    local now = ES:ProfessionSkillStamp()
    if now == skills then return end
    skills = now
    -- (al momento: cada fabricación de más gasta materiales; protegido: si falla, la
    -- página se refresca igual)
    local ok, err = pcall(ES.CheckCraftStop, ES)
    if not ok and ES.RecordError then ES:RecordError("parar al llegar al tope", err) end
    stamp = stamp + 1
    local mine = stamp
    C_Timer.After(0.3, function() if mine == stamp then ES:RefreshAfterSkill() end end)
  end)
end

-- Recalcular la ruta (sin empezar) sin hacerlo a cada fabricación: con "usar lo de las
-- bolsas" cada bolsa cambiaba y cada punto subía, y la ruta se rehacía entera de 0 a
-- 100% una y otra vez mientras fabricabas. Mientras fabricas, se repinta la de antes; se
-- recalcula una vez cuando llevas CRAFT_QUIET s sin fabricar (ES.lastCraftAt)
local CRAFT_QUIET = 6
function ES:RecalcWhenQuiet(page)
  page.quietStamp = (page.quietStamp or 0) + 1
  local mine = page.quietStamp
  local function Try()
    if page.quietStamp ~= mine then return end
    if not page:IsVisible() then return end -- (al verse se recalcula: OnShow)
    local now = GetTime and GetTime() or 0
    local since = now - (ES.lastCraftAt or -math.huge)
    if since < CRAFT_QUIET then
      C_Timer.After(CRAFT_QUIET - since + 0.1, Try)
      return
    end
    ES:CalculatePlan(page)
  end
  local now = GetTime and GetTime() or 0
  if now - (ES.lastCraftAt or -math.huge) < CRAFT_QUIET then ES:RenderPlan(page) end
  Try()
end

function ES:RefreshProfessionPages()
  for _, page in ipairs(self.professionPages or {}) do
    if page.initialized and page:IsVisible() then self:CalculatePlan(page) end
  end
end

---------------------------------------------------------------------------
-- Cálculo y pintado
---------------------------------------------------------------------------
function ES:CalculatePlan(page)
  local from = page.from or 1
  local to = tonumber(page.toBox:GetText()) or MAX_SKILL
  to = math.max(1, math.min(MAX_SKILL, to))
  -- Ruta empezada: cambiar el objetivo es otra ruta (decisión tuya: se libera). Lo
  -- que pasa jugando no la libera: subir de nivel, comprar... y al llegar al
  -- objetivo se queda como completada hasta que la recalcules
  local lock = self:RouteLock(page.profKey)
  if lock and to ~= lock.to then
    self:StopRoute(page.profKey)
    lock = nil
  end
  if lock and from >= lock.to and not lock.completed then
    lock.completed = true
    self:Print(string.format(L["¡Ruta completada! %s de %d a %d."], page.profName, lock.from, lock.to))
  end
  page.toBox:SetText(to)
  page.lastTarget = to
  -- Solo se guarda si no es el de por defecto (el final de tu tope): así este sube contigo
  local settings = self.db.prof[page.profKey]
  if settings.target or to ~= self:DefaultTarget(page.profKey) then settings.target = to end
  page.calculating = nil
  if lock then
    page.plan, page.planKey = self:LockedPlan(page.profKey), nil
  elseif from >= to then
    page.plan, page.planKey = nil, nil -- y si llega una ruta pedida antes, se descarta
  else
    -- Con el nivel detectado se usa el tope real para saber qué rangos faltan.
    -- Si no está en la caché, se calcula repartida entre fotogramas: mientras, se
    -- ve "Calculando la ruta…" (o la ruta anterior) y al acabar se repinta
    local cap = page.detected and page.detected.cap or nil
    local key = self:PlanKey(page.profKey, from, to, cap)
    page.planKey = key
    page.planFailed = nil
    local plan, failed = self:RequestPlan(page.profKey, from, to, cap, function(result, err)
      if page.planKey ~= key then return end -- se pidió otra ruta después
      page.calculating = nil
      page.plan = result
      page.planFailed = err or nil
      -- Llegaron precios de vendedor que esperaba mientras calculaba: una vez más,
      -- con ellos (sin haber tirado lo calculado)
      if page.recalcQueued and not self:RouteLock(page.profKey) and page:IsVisible() then
        page.recalcQueued = nil
        self:InvalidatePlan(page.profKey)
        self:CalculatePlan(page)
        return
      end
      self:RenderPlan(page)
    end, page)
    if plan then page.plan = plan elseif failed then page.plan, page.planFailed = nil, true else page.calculating = true end
  end
  self:RenderPlan(page)
end

-- Líneas de la vista Ruta: pasos con entrenamientos, herramientas y lo que hay
-- que fabricar antes, cada cosa en su sitio
local TRAIN_ICON = "Interface\\Icons\\INV_Misc_Book_09"   -- libro del instructor
local RECIPE_ICON = "Interface\\Icons\\INV_Scroll_03"     -- receta comprada (vendedor/AH)
local LEARN_WHERE = ES.Localize({ trainer = "Instructor", vendor = "Vendedor de recetas", scroll = "Pergamino en la AH", unknown = "Pergamino o botín" })
local WP = ES.Waypoints
local QUEST_ICON = ES.QUEST_ICON -- se pinta con el atlas en alta resolución (Core.lua)
local AH_ICON = "Interface\\Icons\\INV_Misc_Coin_01"

-- Abrir la receta en la ventana de la profesión y fabricar (la ventana moderna de
-- Forever: C_TradeSkillUI). Solo desde un clic del jugador.
function ES:OpenRecipe(recipeID)
  if InCombatLockdown and InCombatLockdown() then
    self:Print(L["No se pueden abrir las profesiones en combate."])
    return false
  end
  local T = C_TradeSkillUI
  if T and T.OpenRecipe and pcall(T.OpenRecipe, recipeID) then return true end
  self:Print(L["Abre la ventana de tu profesión para ver la receta."])
  return false
end

-- ¿Está abierta la ventana de la profesión de esta receta, con sus recetas cargadas?
-- (Forever no da numAvailable: basta con que la ventana se vea y la receta esté)
local function TradeSkillReady(recipeID)
  local shown = (ProfessionsFrame and ProfessionsFrame:IsShown()) or (TradeSkillFrame and TradeSkillFrame:IsShown())
  if not shown then return false end
  local T = C_TradeSkillUI
  if T and T.IsTradeSkillReady then
    local ok, ready = pcall(T.IsTradeSkillReady)
    if ok and ready == false then return false end
  end
  local ok, info = pcall(T and T.GetRecipeInfo or function() end, recipeID)
  return ok and type(info) == "table"
end
ES.TradeSkillReady = TradeSkillReady

local openedNotice -- receta de la que ya se avisó "pulsa otra vez" (una vez, sin llenar el chat)

-- Cuántas veces se puede fabricar una receta con lo que llevas en las bolsas, según
-- los datos del addon, y el material que limita: n, { itemID, have, need } (need: lo
-- que pide una fabricación más). Lo que vende un vendedor también limita (hay que
-- comprarlo antes). nil si la receta no está en los datos
local function CraftableFromBags(recipeID)
  local r = ES:RecipeByID(recipeID) -- (también las de la fundición de Minería)
  if not (r and r.r) then return nil end
  -- Sin la herramienta que pide (Arclight Spanner) no se fabrica ni una
  local tool = ES.Planner.MissingTool(r)
  if tool then return 0, { itemID = tool.item, have = 0, need = 1 } end
  local n, short
  for _, rq in ipairs(r.r) do
    local have = ES:ItemCount(rq[1]) or 0
    local k = math.floor(have / rq[2])
    if not n or k < n then
      n = k
      short = { itemID = rq[1], have = have, need = (k + 1) * rq[2] }
    end
  end
  return n, short
end
ES.CraftableFromBags = CraftableFromBags

-- Cuántas veces has fabricado una receta desde tu último punto (en tu nivel de ahora):
-- en verde hacen falta varias por punto, y el "Fabrica N×" del paso las descuenta. Solo
-- esta sesión; al subir de nivel vuelve a 0
local craftsHere = {} -- [recipeID] = { level, n }
function ES.CraftsAtLevel(recipeID, level)
  local c = craftsHere[recipeID]
  return c and c.level == level and c.n or 0
end
do
  local f = CreateFrame("Frame")
  -- (solo tus lanzamientos: con todas las unidades llegaba uno por cada hechizo de cualquiera a tu alrededor)
  if not (f.RegisterUnitEvent and pcall(f.RegisterUnitEvent, f, "UNIT_SPELLCAST_SUCCEEDED", "player")) then ES.SafeRegister(f, "UNIT_SPELLCAST_SUCCEEDED") end
  f:SetScript("OnEvent", function(_, _, unit, _, spellID)
    if unit ~= "player" or not spellID then return end
    for _, p in ipairs(ES.PROFESSIONS or {}) do
      local data = ES.Data[p.key]
      if data and data.recipes and data.recipes[spellID] and data.skillLine then
        ES.lastCraftAt = GetTime and GetTime() or 0 -- (ES:RecalcWhenQuiet: estás fabricando)
        local level = ES:GetProfessionSkill(data.skillLine)
        if not level then return end
        local c = craftsHere[spellID]
        if not c or c.level ~= level then c = { level = level, n = 0 } craftsHere[spellID] = c end
        c.n = c.n + 1
        return
      end
    end
  end)
end

-- Abre la receta y fabrica `count`. Fabricar tiene que ir en el mismo clic (Forever
-- bloquea fabricar después, desde un temporizador). Con la ventana de la profesión
-- cerrada (o en otra profesión) el juego aún no la tiene cargada y fabricaba solo 1:
-- entonces el primer clic solo la abre y el segundo fabrica todo
function ES:CraftRecipe(recipeID, count)
  if InCombatLockdown and InCombatLockdown() then
    self:Print(L["No se puede fabricar en combate."])
    return
  end
  if not TradeSkillReady(recipeID) then
    if not self:OpenRecipe(recipeID) then return end
    if openedNotice ~= recipeID then
      openedNotice = recipeID
      self:Print(string.format(L["Receta abierta: pulsa otra vez para fabricar %d."], count))
    end
    return "opened"
  end
  openedNotice = nil
  self:OpenRecipe(recipeID)
  local T = C_TradeSkillUI
  -- Como mucho, las que te dan los materiales que llevas. Forever no da numAvailable:
  -- se cuenta con la receta de los datos y tus bolsas (antes decía "Fabricando 20"
  -- aunque faltaran viales)
  local wanted = count
  local fit, short = CraftableFromBags(recipeID)
  local info = T and T.GetRecipeInfo and select(2, pcall(T.GetRecipeInfo, recipeID))
  if type(info) == "table" and info.numAvailable then fit = info.numAvailable end
  if fit then count = math.min(count, fit) end
  if count <= 0 then
    self:Print(short and string.format(L["No puedes fabricar ninguna: te falta %s (tienes %d de %d)."],
      ES:DataItemName(short.itemID) or short.itemID, short.have, short.need) or L["No puedes fabricar ninguna: te faltan materiales."])
    return "missing"
  end
  if T and T.CraftRecipe then
    local ok, err = pcall(T.CraftRecipe, recipeID, count)
    if ok then
      -- Con el nombre de lo que fabricas: "Fabricando 26..." no decía qué, y con dos
      -- recetas parecidas (Linen Bag y Linen Belt) no se veía el error hasta el "Creas"
      local name = type(info) == "table" and info.name
      if not name then
        local r = ES:RecipeByID(recipeID)
        if r then name = (r.out and ES:DataItemName(r.out[1])) or r.name end
      end
      name = name or ("#" .. recipeID)
      if count < wanted then
        self:Print(string.format(L["Fabricando %d de %d× %s: para el resto te falta %s."], count, wanted, name,
          short and (ES:DataItemName(short.itemID) or short.itemID) or L["material"]))
      else
        self:Print(string.format(L["Fabricando %d× %s..."], count, name))
      end
      return
    end
    self:Print(L["No se pudo fabricar: "] .. tostring(err))
  end
end


local function CostOrFree(copper)
  if copper and copper >= 0.5 then return Signed(copper) end
  return GREEN .. L["gratis|r"]
end

-- Prueba piloto: fila "Conseguir receta" con su mejor fuente (misión, vendedor
-- o AH), el clic a quien da la misión o la vende, y todas las fuentes en el tooltip
local function SourcedLearnLine(r, st, profName, plan)
  local src = WP.RecipeSource(r, plan.ctx.prices, plan.ctx.opts.noQuests, plan.ctx.opts.noLimited)
  local best = src and src.best
  if not best then return nil end
  local title = L["Conseguir receta: "] .. r.name
  local also = src.ah and best.kind ~= "ah" and (L[" · también en la AH: "] .. ES.Money(src.ah.price)) or ""
  -- Todos sus vendedores venden pocos y reponen con el tiempo (Data/Sources.lua, lim):
  -- puede no haber. Se avisa; quien no quiera esperar la quita con la ✕ (o, en las
  -- opciones, deja de contar con esos vendedores: src.vendorsOff)
  local limited = src.limited
  -- (la ✕ ya se ve a la derecha de la fila: sin "X para quitarla" en el texto)
  local icon, sub, pick, label
  local useItem
  -- Comprada en la AH (Ledger.OnWay: detectada al comprar; el correo no se mira): el
  -- paso queda hecho. Aprenderla, cuando te llegue, lo recuerda el paso de fabricar.
  -- Sin `pick`: el clic no lleva a ninguna parte (y el tooltip no lo promete)
  local bought = best.kind ~= "owned" and r.scroll and ES.Ledger and ES.Ledger.OnWay and ES.Ledger.OnWay(r.scroll) > 0
  if bought then
    icon, title = RECIPE_ICON, L["Receta comprada: "] .. r.name
    sub = L["Comprada en la AH · apréndela antes de fabricar"]
  elseif best.kind == "owned" then
    icon, title = RECIPE_ICON, L["Aprender receta: "] .. r.name
    sub = string.format(L["La tienes en la bolsa%s · clic para aprenderla"], best.count > 1 and (" (" .. best.count .. ")") or "")
    useItem = r.scroll -- clic: usa el pergamino (botón seguro, ver WantsHover)
  elseif best.kind == "quest" then
    icon, label = QUEST_ICON, L["Da la misión"]
    -- Gratis en oro, pero puede pedir objetos o misiones antes (CurseForge): se dice
    -- aquí y el texto exacto va en el tooltip; la ruta no les pone precio (casi todo
    -- es botín de criaturas). Si no compensa, la X de la fila
    local q = best.quest
    local cost = (q.asks and L[" · pide objetos"] or "")
      .. ((q.chain or 0) > 0 and string.format(L[" · cadena de %d misiones"], q.chain + 1) or "")
    sub = L["Misión: "] .. q.name .. (cost ~= "" and (ORANGE .. cost .. "|r") or also)
    pick = function() return WP.Nearest(best.quest.starters) end
  elseif best.kind == "vendor" then
    icon, label = RECIPE_ICON, L["Vendedor más cercano"]
    sub = L["Vendedor de recetas"] .. (limited and (ORANGE .. L[" · stock limitado"] .. "|r") or "") .. also
    pick = function() return WP.Nearest(src.vendors) end
  else
    -- En la AH: clic al subastador más cercano; con la AH abierta, la busca
    icon, label = AH_ICON, L["Subastador más cercano"]
    sub = string.format(L["Casa de Subastas · la más barata ahora (%d a la venta)"], src.ah.listings)
    pick = WP.Target("auction")
  end

  local function Tooltip(row)
    -- Lo de la X, solo donde la fila tiene X (en el asistente no: ahí no se quita nada)
    local withX = row and row.onSkip ~= nil
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(L["Receta: "] .. r.name)
    GameTooltip:AddDoubleLine(L["Requiere "] .. profName, tostring(r.train or st.from), 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddLine(" ")
    local function Mark(kind) return best.kind == kind and ES.Market.ICON_OK or ES.Market.ICON_NONE end
    if src.owned then
      GameTooltip:AddDoubleLine(Mark("owned") .. L["En tus bolsas"], src.owned .. L[" · gratis"], 1, 0.82, 0, 1, 1, 1)
    end
    for _, q in ipairs(src.quests) do
      if src.questsOff then
        GameTooltip:AddDoubleLine(ES.Market.ICON_BAD .. L["Misión"], q.name .. L[" · desactivada"], 0.6, 0.6, 0.6, 0.6, 0.6, 0.6)
      else
        -- ("gratis" solo si no pide nada: si pide objetos, cuesta lo que cueste conseguirlos)
        GameTooltip:AddDoubleLine(Mark("quest") .. L["Misión"], q.name .. ((q.asks or (q.chain or 0) > 0) and "" or L[" · gratis"]),
          1, 0.82, 0, 1, 1, 1)
      end
      local starter = WP.Nearest(q.starters)
      local npc = starter and WP.NPC(starter)
      if npc then GameTooltip:AddDoubleLine(" ", npc.name .. " · " .. WP.LocationText(npc), 1, 1, 1, 0.6, 0.6, 0.6) end
      if q.level > 0 then GameTooltip:AddDoubleLine(" ", L["nivel "] .. q.level, 1, 1, 1, 0.6, 0.6, 0.6) end
      -- Lo que pide entregar, con el texto de la misión (en inglés: es el del juego)
      if q.asks then
        GameTooltip:AddLine(L["Pide: "] .. q.asks, 1, 0.6, 0.2, true)
      end
      if (q.chain or 0) > 0 then
        GameTooltip:AddLine(q.chain == 1 and L["Antes hay que hacer 1 misión de su cadena, que también puede pedir objetos."]
          or string.format(L["Antes hay que hacer %d misiones de su cadena, que también pueden pedir objetos."], q.chain), 1, 0.6, 0.2, true)
      end
      if (q.asks or (q.chain or 0) > 0) and withX then
        GameTooltip:AddLine(L["La ruta no le pone precio a lo que pide (casi todo se consigue matando criaturas). Si no te compensa, quítala con la X de la fila."], 0.6, 0.6, 0.6, true)
      end
    end
    if src.vendors[1] then
      local opt
      for _, o in ipairs(src.options) do if o.kind == "vendor" then opt = o end end
      if src.vendorsOff then
        GameTooltip:AddDoubleLine(ES.Market.ICON_BAD .. L["Vendedores"], L["stock limitado · no se cuentan"], 0.6, 0.6, 0.6, 0.6, 0.6, 0.6)
      else
        GameTooltip:AddDoubleLine(Mark("vendor") .. L["Vendedores"], string.format("%d · %s", #src.vendors,
          opt and opt.unknownPrice and L["precio ?"] or ES.Money(opt and opt.cost or 0)), 1, 0.82, 0, 1, 1, 1)
      end
      local v = WP.Nearest(src.vendors)
      local npc = v and WP.NPC(v)
      if npc then GameTooltip:AddDoubleLine(" ", npc.name .. " · " .. WP.LocationText(npc), 1, 1, 1, 0.6, 0.6, 0.6) end
      if src.vendorsOff then
        GameTooltip:AddLine(L["Su vendedor tiene stock limitado y desactivaste esos vendedores con su icono, arriba de la ruta."], 0.6, 0.6, 0.6, true)
      elseif limited then
        GameTooltip:AddLine(withX and L["Stock limitado: venden pocas y reponen con el tiempo, y a veces otros jugadores las compran para revenderlas. Si no está, quítala con la X de la fila y la ruta busca otra receta."]
          or L["Stock limitado: venden pocas y reponen con el tiempo, y a veces otros jugadores las compran para revenderlas."],
          1, 0.6, 0.2, true)
      end
    end
    if src.ah then
      GameTooltip:AddDoubleLine(Mark("ah") .. L["AH ahora"], string.format(L["%s · %d a la venta"], ES.Money(src.ah.price), src.ah.listings),
        1, 0.82, 0, 1, 1, 1)
    else
      GameTooltip:AddDoubleLine(ES.Market.ICON_NONE .. L["AH ahora"], L["no hay ninguna"], 1, 0.82, 0, 0.6, 0.6, 0.6)
    end
    if src.noQuestie then
      GameTooltip:AddLine(L["Sin Questie no se saben misiones ni vendedores: solo cuenta la AH."], 1, 0.6, 0.2, true)
    end
    GameTooltip:AddLine(" ")
    if bought then
      -- Comprada: su clic no lleva a ninguna parte (ni busca en la AH ni marca el camino
      -- al subastador), así que el tooltip no lo promete
    elseif best.kind == "owned" then
      GameTooltip:AddLine(L["Clic: usar el pergamino de tu bolsa y aprenderla."], 0.5, 0.8, 1, true)
    elseif best.kind == "ah" then
      if ES:IsAuctionHouseOpen() then
        GameTooltip:AddLine(L["Clic: buscarla en la Casa de Subastas."], 0.5, 0.8, 1)
      else
        WP.AddToTooltip(label, pick)
      end
    elseif pick then
      GameTooltip:AddLine(L["Clic: marcar el camino ("] .. (best.kind == "quest" and L["a quien da la misión"] or L["al vendedor"]) .. ").", 0.5, 0.8, 1)
    end
    if best.kind ~= "owned" and withX then
      GameTooltip:AddLine(L["X de la fila: quitar esta receta y que la ruta busque otra (se recupera con la fila de recetas quitadas)."], 0.6, 0.6, 0.6, true)
    end
    GameTooltip:Show()
  end

  return { icon = icon, title = title, sub = sub, value = CostOrFree(st.fee), go = pick, tooltip = Tooltip,
    ahItem = not bought and best.kind == "ah" and r.scroll or nil, useItem = useItem, recipeName = r.name,
    bought = bought or nil }
end
ES.SourcedLearnLine = SourcedLearnLine -- para pruebas

-- Cita "Con lo que llevas": por qué la ruta no usa una receta que podrías hacer
-- con tus materiales, en una frase que se entienda de un vistazo (sin desglose: la
-- cuenta la hace el addon). Solo informa, no se pulsa. Si compensa, la ruta ya la
-- incluye (Planner:Plan) y no hay nada que explicar; salvo con la ruta fijada, que
-- no cambia sola: entonces se dice que recalcules. nil si no hay que decir nada.
local function BagsLine(alt, locked)
  local diff = alt.saving - alt.value -- > 0: hacerla con lo tuyo sale mejor que venderlo
  -- Compensa o empata (ver Planner.BagsWorth): la ruta ya la usa; solo con la ruta
  -- fijada hay que decirlo (no cambia sola). Si no, solo sale cuando vender es
  -- claramente mejor: por 3s de diferencia no merece una cita
  local worth = ES.Planner.BagsWorth(alt)
  if worth and not locked then return nil end
  local r = alt.recipe
  local name = ItemLabel(r.out[1], r.name)
  -- "50 Earthroot y 25 Peacebloom"
  local parts = {}
  for _, u in ipairs(alt.use) do
    parts[#parts + 1] = string.format("%d %s", u.qty, (ItemLabel(u.itemID, L["Objeto "] .. u.itemID)))
  end
  local mats = #parts > 1 and (table.concat(parts, ", ", 1, #parts - 1) .. L[" y "] .. parts[#parts]) or parts[1]
  -- Monedas centradas con la letra pequeña de la cita
  local function Coins(copper) return ES.MoneyInline(copper, QUOTE_COIN_Y) end
  local spend = alt.spend > 0 and string.format(L["solo gastas %s en el instructor y el vendedor"], Coins(alt.spend))
    or L["no gastas oro"]
  if alt.feeUnknown then spend = spend .. L[" (más el instructor, precio desconocido)"] end
  -- La conclusión, en su propia línea y en un color apagado (es información, no un aviso)
  local verdict
  if worth and diff > 0 then
    verdict = "|cff8fc98f" .. string.format(L["Hacerla con lo tuyo te sale unos %s mejor que venderlo y seguir la ruta. Pulsa Dejar ruta para incluirla."], Coins(diff)) .. "|r"
  elseif worth then
    verdict = "|cff8fc98f" .. L["Sale casi igual que venderlo, así que es más cómodo usar lo tuyo. Pulsa Dejar ruta para incluirla."] .. "|r"
  else
    verdict = "|cffd9a066" .. string.format(L["Vender lo tuyo y seguir la ruta te sale unos %s mejor."], Coins(-diff)) .. "|r"
  end
  return {
    -- Cita: la frase entera en la fila, entre comillas grandes (alto según el texto)
    quote = string.format(L["Con lo que llevas podrías hacer %s (%d–%d): %s, pero usas %s, por los que te darían unos %s vendiéndolos."],
      name, alt.from, alt.to, spend, mats, Coins(alt.value)) .. "\n" .. verdict,
    height = 76,
    alt = alt, -- (para pruebas)
  }
end

-- Lo que falta comprar de la ruta desde `level`: la MISMA regla que la Lista de compra y
-- la vista Materiales (Planner.RouteNeed: con la ruta empezada, por tramos y con su
-- colchón) frente a lo que llevas en las bolsas.
-- { ah = { it }, vendor = { it }, have = { { itemID, quantity } }, left (lo que cuesta lo
-- que falta), need = { [itemID] = unidades }, phase, Have = función }
-- it = { itemID, quantity (lo que falta), need, source, unit, total, supply }
-- opts.phase: siempre por tramos (las filas de compra), aunque la lista sea de la ruta entera
local function RouteBuy(plan, profKey, level, opts)
  local routeNeed, phase = ES.Planner.RouteNeed(profKey, plan, level, opts)
  local function Bags(itemID) return ES.HaveForShopping and ES:HaveForShopping(itemID) or ES:ItemCount(itemID) end
  -- (lo ya convertido cuenta como su material: ConvertedHave)
  local Have = ConvertedHave(plan, Bags, math.max(plan.from or level or 1, level or plan.from or 1))
  -- (en los dos sitios, donde va la mayor parte: Planner.ShoppingSource)
  local shopping = {}
  for _, it in ipairs(plan.shopping or {}) do shopping[it.itemID] = ES.Planner.ShoppingSource(plan, it.itemID) end
  local res = { ah = {}, vendor = {}, have = {}, left = 0, need = {}, phase = phase, Have = Have, plan = plan }
  local ids = {}
  for itemID, n in pairs(routeNeed) do
    res.need[itemID] = n.need
    ids[#ids + 1] = itemID
  end
  table.sort(ids)
  for _, itemID in ipairs(ids) do
    local n = math.ceil(res.need[itemID] - 0.001)
    if n > 0 then
      local missing = n - Have(itemID)
      if missing > 0 then
        local planned = shopping[itemID]
        local vendorPrice = ES.Data.VendorPrices and ES.Data.VendorPrices[itemID]
        local source = planned and planned.source or (vendorPrice and "vendor" or "ah")
        local ahEntry = plan.ctx and plan.ctx.prices and plan.ctx.prices[itemID]
        local unit = planned and planned.unit or vendorPrice or (ahEntry and ahEntry.minUnit) or 0
        local it = { itemID = itemID, quantity = missing, need = n, source = source, unit = unit, total = unit * missing,
          supply = planned and planned.supply or (ahEntry and ahEntry.quantity) }
        res.left = res.left + it.total
        table.insert(source == "ah" and res.ah or res.vendor, it)
      else
        res.have[#res.have + 1] = { itemID = itemID, quantity = n }
      end
    end
  end
  return res
end

---------------------------------------------------------------------------
-- Filas de compra de la ruta empezada, SOLO para el asistente (docs/ASISTENTE.md,
-- sección 3; ES:RouteLines con opts.buy): la ventana tiene Materiales y la Lista de
-- compra, y el asistente un solo paso a la vista. "Compra en la AH" y "Compra al
-- vendedor", con lo que falta del tramo (RouteBuy, lo mismo que Materiales). Van delante del paso
-- en el que estás y son el paso actual cuando toca comprar:
--   · al empezar el tramo (aún sin puntos en él), si falta algo;
--   · cuando no puedes fabricar ni una vez el paso actual (mala suerte, tanda gastada).
-- Si aún puedes fabricar, no paran la ruta: el paso actual avisa ("luego compra...").
-- Si ya fuiste a la AH o al vendedor y no lo compraste todo (no había, no quisiste),
-- dejan de parar mientras puedas fabricar algo (ES.routeBuyVisits)
---------------------------------------------------------------------------
ES.routeBuyVisits = {} -- [profKey] = { key = tramo, ah = true, vendor = true } (esta sesión)
ES.routeSkips = {}     -- [profKey] = { ["recipe:Nombre"] = true }: recetas saltadas (esta sesión)
local VENDOR_ICON = "Interface\\Icons\\INV_Misc_Bag_10"
local BANK_ICON = "Interface\\Icons\\INV_Box_02"
-- Las filas de compra del asistente siguen el modo de la Lista de compra (por tramos o
-- la ruta entera, ES.Shopping.ByPhase): un solo ajuste para las dos cosas. Se cambia
-- en la vista Materiales o con el clic derecho del asistente
local function BuyMode(profKey) return ES.Shopping.ByPhase(profKey) and { phase = true } or nil end

local function PhaseKey(phase) return phase and (phase.steps[1].from .. ":" .. phase.to) or "route" end

-- La clave de ES.routeBuyVisits: el tramo DE ESTA RUTA (cuándo se empezó). Solo con el
-- tramo, una ruta nueva de la misma profesión heredaba el "No había suficiente" de la
-- anterior (con la lista de la ruta entera la clave era siempre "route")
local function VisitKey(profKey, phase)
  local lock = ES:RouteLock(profKey)
  return tostring(lock and lock.started or 0) .. "|" .. PhaseKey(phase)
end
ES.UI.BuyVisitKey = VisitKey -- (pruebas)

-- "Runecloth 12/40 · Thread 2/10 · +1"
local function BuyList(items, have)
  local parts = {}
  for i, it in ipairs(items) do
    if i > 2 then parts[#parts + 1] = "+" .. (#items - 2) break end
    parts[#parts + 1] = string.format("%s %d/%d", ES:DataItemName(it.itemID) or (ItemLabel(it.itemID, L["Objeto "] .. it.itemID)),
      have(it.itemID), it.need)
  end
  return table.concat(parts, " · ")
end

-- Qué filas de compra salen: { { source, items } }. Orden: banco (lo tuyo, gratis),
-- AH, vendedor. En la AH, una fila por material (el clic abre la compra de ese; con
-- todos en una, el clic siempre abría el primero y el asistente no llegaba al
-- segundo). El banco, en una: su clic ya lo saca todo. El vendedor, una por cada grupo
-- que vende entero un mismo vendedor (WP.VendorGroups; Discord: la de Mild Spices y
-- Bottle of Dalaran Noir llevaba a Barkeep Morag, que solo vende el Bottle)
local function BuyGroups(buy)
  local groups = {}
  for _, source in ipairs({ "bank", "ah", "vendor" }) do
    if source == "ah" then
      for _, it in ipairs(buy.ah) do groups[#groups + 1] = { source, { it } } end
    elseif source == "vendor" and buy.vendor[1] and WP and WP.VendorGroups then
      local byID, ids = {}, {}
      for _, it in ipairs(buy.vendor) do
        if not byID[it.itemID] then byID[it.itemID] = it ids[#ids + 1] = it.itemID end
      end
      for _, g in ipairs(WP.VendorGroups(ids)) do
        local items = {}
        for _, id in ipairs(g) do items[#items + 1] = byID[id] end
        groups[#groups + 1] = { source, items }
      end
    elseif buy[source][1] then
      groups[#groups + 1] = { source, buy[source] }
    end
  end
  return groups
end
ES.UI.BuyGroups = BuyGroups -- (pruebas)

local function BuyLine(source, items, buy, level, visited, profKey)
  local single = #items == 1 and items[1]
  local name, texture = single and ItemLabel(single.itemID, L["Objeto "] .. single.itemID)
  local cost = 0
  for _, it in ipairs(items) do cost = cost + it.total end
  local bank = source == "bank"
  local title
  if bank then
    title = single and string.format(L["Saca %d× %s del banco"], single.quantity, name)
      or string.format(L["Ve al banco: %d materiales"], #items)
  elseif single then
    title = string.format(L["Compra %d× %s"], single.quantity, name)
  else
    title = string.format(source == "ah" and L["Compra en la AH: %d materiales"] or L["Compra al vendedor: %d materiales"], #items)
  end
  local list = BuyList(items, buy.Have)
  local where = bank and L["en el banco"] or source == "ah" and L["en la AH"] or L["en el vendedor"]
  local sub = (single and string.format("%d/%d · %s", buy.Have(single.itemID), single.need, where) or list)
  if visited then sub = ORANGE .. L["No había suficiente"] .. "|r · " .. sub end
  -- Clic: con la AH abierta, la compra del primero que falta (cada clic, el siguiente);
  -- con el vendedor abierto, compra lo que vende de la lista; si no, el camino
  local onClick, go, action
  if bank and ES.Assistant and ES.Assistant.BankOpen() then
    -- Banco abierto: saca a las bolsas justo lo que falta (Assistant.lua)
    action = L["sacar a tus bolsas lo que falta"]
    onClick = function() ES.Assistant.TakeFromBank(items) end
  elseif source == "ah" and ES:IsAuctionHouseOpen() then
    -- (en la AH cada fila es un material: AddBuyLines)
    local it = items[1]
    action = string.format(L["abrir la compra de %d en la AH"], it.quantity)
    onClick = function() ES:OpenAuctionBuy(it.itemID, it.quantity, it.unit) end
  elseif source == "vendor" and ES.Ledger and ES.Ledger:MerchantOpen() and ES.VendorShop then
    -- Vendedor abierto: compra justo lo que falta del tramo (lo de esta fila, no lo de
    -- la lista de compra) de lo que tenga; lo que no tiene, se dice. Si no tiene nada
    -- de la fila, el clic marca el camino a quien lo vende (WP.Vendors)
    local sells = {}
    for i = 1, (GetMerchantNumItems and GetMerchantNumItems()) or 0 do
      local id = ES.Ledger.MerchantItemID(i)
      local _, _, avail = ES.Ledger.MerchantInfo(i)
      if id and avail ~= 0 then sells[id] = true end -- (agotado: como si no lo tuviera)
      -- (lo vende: al cerrar, "ya fuiste" si no lo compraste todo; ver ES.buyTried)
      if id and ES.buyTried then ES.buyTried.sells[id] = true end
    end
    -- Lo que este vendedor no tiene (aunque los datos digan que sí, o agotado): se apunta
    -- y la fila lleva a otro vendedor de la lista (WP.VendorFor)
    local guid = UnitGUID and UnitGUID("npc")
    local npcID = guid and tonumber(guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
    local here = false
    for _, it in ipairs(items) do
      if sells[it.itemID] then here = true elseif npcID then WP.MarkVendorLacks(npcID, it.itemID) end
    end
    if here then
      action = L["comprar a este vendedor justo lo que falta"]
      onClick = function()
        local bought, missing = ES.VendorShop:BuyExact(items)
        if missing[1] then
          local names = {}
          for _, it in ipairs(missing) do names[#names + 1] = ES:DataItemName(it.itemID) or tostring(it.itemID) end
          ES:Print(string.format(L["Este vendedor no tiene: %s. Sigue la fila para ir a otro."], table.concat(names, ", ")))
        end
      end
    end
  end
  if not onClick then
    if source == "vendor" then
      -- (el que vende más materiales de la fila, sin los que no los tenían al abrirlos)
      local ids = {}
      for _, it in ipairs(items) do ids[#ids + 1] = it.itemID end
      go = function() return WP.VendorFor(ids) end
    else
      go = WP.Target(bank and "bank" or "auction", items[1].itemID)
    end
  end
  local label = bank and L["Banquero más cercano"] or source == "ah" and L["Subastador más cercano"] or L["Vendedor más cercano"]
  -- Quitaste la lista de esta ruta de la Lista de compra: el clic (lejos de la AH y del
  -- vendedor) la vuelve a añadir, con el mismo aviso que al empezar la ruta, y marca el camino
  local readd = not bank and not onClick and ES.Shopping and ES.Shopping.RouteListHidden(profKey)
  local bannerSub = visited and (ORANGE .. L["No había suficiente"] .. "|r") or ""
  if readd then
    local pick = go
    onClick = function()
      ES.Shopping.SetRouteListHidden(profKey, false)
      local list = ES.Shopping.PhaseList(profKey)
      if list then ES:Print(string.format(L["Añadido a la lista de compra: %s."], list.title)) end
      if ES.FlashTab then ES:FlashTab("shopping", true) end
      if ES.RenderShopping then ES:RenderShopping() end
      WP.Go(pick)
    end
    action = L["volver a añadirla a la Lista de compra y marcar el camino"]
    bannerSub = (bannerSub ~= "" and (bannerSub .. " · ") or "") .. ORANGE .. L["No está en tu Lista de compra · clic para añadirla"] .. "|r"
  end
  return {
    level = tostring(level), buyRow = source, buyItems = items, readd = readd or nil, -- (para pruebas)
    icon = texture or (bank and BANK_ICON or source == "ah" and AH_ICON or VENDOR_ICON),
    title = title, sub = sub .. ((single or bank) and "" or (" · ~" .. ES.Money(cost))),
    -- En el asistente, sin subtítulo (el título lo dice; la lista, en el tooltip). Solo
    -- los avisos: no había suficiente, o no está en tu Lista de compra
    bannerSub = bannerSub,
    value = not bank and Signed(cost) or nil, item = single and single.itemID or nil,
    onClick = onClick, go = not readd and go or nil,
    tooltip = function(row)
      GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
      GameTooltip:AddLine(bank and L["Sacar del banco"] or source == "ah" and L["Comprar en la Casa de Subastas"] or L["Comprar al vendedor"])
      GameTooltip:AddLine(buy.phase and L["Lo que te falta para este tramo, con lo que llevas ahora"]
        or L["Lo que te falta para lo que queda de ruta, con lo que llevas ahora"], 0.8, 0.8, 0.8, true)
      GameTooltip:AddLine(" ")
      for _, it in ipairs(items) do
        GameTooltip:AddDoubleLine((ItemLabel(it.itemID, L["Objeto "] .. it.itemID)),
          bank and string.format(L["saca %d (tienes %d en el banco)"], it.quantity, it.stored or it.quantity)
          or string.format("%d/%d · %s", buy.Have(it.itemID), it.need, ES.Money(it.total)), 1, 1, 1, 1, 1, 1)
        -- Si se puede fabricar: por qué se compra (Bolt of Linen Cloth y no Linen Cloth)
        local cmp = not bank and (it.unit or 0) > 0 and CraftCompareText(buy.plan, it.itemID, it.unit)
        if cmp then GameTooltip:AddLine("   " .. cmp, 0.6, 0.6, 0.6, true) end
      end
      if bank then
        GameTooltip:AddLine(L["Según lo que había la última vez que abriste el banco."], 0.6, 0.6, 0.6, true)
      end
      if visited then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Ya fuiste y no lo compraste todo: mientras puedas fabricar, la ruta sigue. Si no hay de dónde sacarlo, quita esa receta desde la ventana del addon."], 1, 0.6, 0.2, true)
      end
      if action then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Clic: "] .. action .. ".", 0.5, 0.8, 1, true)
      else
        WP.AddToTooltip(label, go)
      end
      GameTooltip:Show()
    end,
  }
end

-- Añade las filas de compra a las de la ruta empezada (ver arriba) y decide si son el
-- paso actual. `level`: tu nivel
local function AddBuyLines(lines, plan, page, level)
  local buy = RouteBuy(plan, page.profKey, level, BuyMode(page.profKey))
  if not (buy.ah[1] or buy.vendor[1]) then
    -- Tienes todo lo del tramo: se apunta (esta sesión). Si luego falta y no puedes
    -- fabricar, es que los puntos no subieron lo esperado ("mala suerte"); si nunca lo
    -- tuviste, es la compra normal del principio del tramo
    local key = VisitKey(page.profKey, buy.phase)
    local v = ES.routeBuyVisits[page.profKey]
    if not v or v.key ~= key then v = { key = key } ES.routeBuyVisits[page.profKey] = v end
    v.stocked = true
    return
  end
  -- Lo que tienes en el banco (la foto de la última vez que lo abriste: Assistant.lua,
  -- BankCount) no se compra: primero se saca. Sin foto (nunca lo abriste), se compra
  buy.bank = {}
  local bankCount = ES.Assistant and ES.Assistant.BankCount
  if bankCount then
    for _, source in ipairs({ "ah", "vendor" }) do
      local keep = {}
      for _, it in ipairs(buy[source]) do
        local stored = bankCount(it.itemID) or 0
        local n = math.min(stored, it.quantity)
        if n > 0 then
          buy.bank[#buy.bank + 1] = { itemID = it.itemID, quantity = n, need = it.need, source = "bank",
            unit = 0, total = 0, stored = stored }
          it.quantity = it.quantity - n
          it.total = (it.unit or 0) * it.quantity
        end
        if it.quantity > 0 then keep[#keep + 1] = it end
      end
      buy[source] = keep
    end
  end
  local at -- la fila del paso en el que estás (delante de ella van las de compra)
  for i, line in ipairs(lines) do if line.current then at = i break end end
  if not at then
    for i, line in ipairs(lines) do if line.level and not line.done then at = i break end end
  end
  if not at then return end
  local cur = lines[at]
  -- Entrenar un rango o aprender una receta va antes que comprar (se hace en el
  -- instructor o el vendedor, no necesita los materiales): las compras van delante de la
  -- primera fila de fabricar desde la actual, y solo paran la ruta cuando toca fabricar
  local craftAt = at
  while lines[craftAt] and not lines[craftAt].stepRecipe do craftAt = craftAt + 1 end
  if not lines[craftAt] then craftAt = at end -- (sin nada que fabricar a la vista: delante de la actual)
  local crafting = cur.current and cur.stepRecipe ~= nil
  local key = VisitKey(page.profKey, buy.phase)
  local visits = ES.routeBuyVisits[page.profKey]
  if visits and visits.key ~= key then visits = nil ES.routeBuyVisits[page.profKey] = nil end
  -- ¿Puedes fabricar el paso actual al menos una vez?
  local canCraft = false
  if crafting and ES:IsRecipeKnown(cur.stepRecipe) then
    local n = ES.CraftableFromBags(cur.stepRecipe)
    canCraft = n == nil or n >= 1
  end
  -- Al principio del tramo: su primer nivel, o aún sin haber tenido sus materiales. Un
  -- nivel por encima de su principio puede venir del paso anterior (Elixir of Wisdom
  -- dejó a 131 y salía "mala suerte" en Fire Oil sin haber fabricado ninguno)
  -- (comprado y gastado, Planner.Stocked: es reponer, no el principio)
  local atStart = not buy.phase or (not buy.phase.refill
    and (level <= buy.phase.steps[1].from or not (visits and visits.stocked)))
  local new, blocking = {}, false
  local profKey = page.profKey
  for _, g in ipairs(BuyGroups(buy)) do
    local source, items = g[1], g[2]
    -- "Saltar" (la pestaña del asistente): lo diste por comprado en este tramo (compras
    -- por el chat, el banco de hermandad, un alter...). La fila queda como hecha
    -- ("Saltado"): con ◀ se vuelve a ella y "Recuperar" la devuelve. Cada fila de la AH
    -- es un material: se salta solo ese. Se olvida al cambiar de tramo o de sesión
    -- (el vendedor, por material: hay una fila por grupo de WP.VendorGroups, y saltar
    -- una no salta las demás ni se pierde si los grupos cambian)
    local gkeys = {}
    if source == "vendor" then
      for _, it in ipairs(items) do gkeys[#gkeys + 1] = "vendor:" .. it.itemID end
    else
      gkeys[1] = source == "ah" and ("ah:" .. items[1].itemID) or source
    end
    local had = visits and visits.had and true or false
    for _, k in ipairs(gkeys) do had = had and visits.had[k] and true or false end
    local function SetHad(on)
      local v = ES.routeBuyVisits[profKey]
      if not v or v.key ~= key then v = { key = key } ES.routeBuyVisits[profKey] = v end
      v.had = v.had or {}
      for _, k in ipairs(gkeys) do v.had[k] = on or nil end
    end
    if had then
      local line = BuyLine(source, items, buy, level, nil, profKey)
      line.done, line.skipped, line.onClick, line.go = true, true, nil, nil
      line.bannerSub = GREY .. L["Saltado · Recuperar lo vuelve a poner"] .. "|r"
      line.unmarkHave = function() SetHad(false) end
      new[#new + 1] = line
    else
      -- (el vendedor: visitada si cerraste uno que vendía algo de esta fila; ver el
      -- manejador de MERCHANT_CLOSED, vendorSeen)
      local visited = visits and visits[source]
      if source == "vendor" then
        visited = false
        for _, it in ipairs(items) do
          if visits and visits.vendorSeen and visits.vendorSeen[it.itemID] then visited = true end
        end
      end
      local line = BuyLine(source, items, buy, level, visited, profKey)
      if source ~= "bank" then line.markHave = function() SetHad(true) end end
      -- Con la lista de la ruta entera, la compra es la de toda la ruta: se dice
      if not buy.phase and source ~= "bank" then
        line.wholeRoute = true
        line.bannerSub = GREY .. L["ruta entera"] .. "|r" .. (line.bannerSub ~= "" and (" · " .. line.bannerSub) or "")
      end
      -- Para: toca fabricar y no puedes, o empieza el tramo y aún no has ido a comprar
      if crafting and not blocking and (not canCraft or (atStart and not visited)) then
        line.current, blocking = true, true
        -- A mitad de tramo y sin materiales: gastaste lo comprado (la tanda) y toca la
        -- siguiente. Se dice, para que no parezca un fallo de la ruta; tras comprar, el
        -- paso vuelve a ser fabricar. Sin hablar de "mala suerte": es lo normal en verde
        if not atStart and not canCraft then
          line.refill = true
          local text = ORANGE .. L["Para seguir fabricando, compra más"] .. "|r"
          line.bannerSub = (line.bannerSub ~= "" and (line.bannerSub .. " · ") or "") .. text
          line.sub = text .. " · " .. line.sub
          local tip = line.tooltip
          line.tooltip = function(row)
            tip(row)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["En las recetas verdes (y a veces en las amarillas) no todas las fabricaciones suben punto, así que la ruta compra por tandas: cuando gastas una, te trae a comprar la siguiente y luego vuelves a fabricar."], 1, 0.82, 0, true)
            GameTooltip:Show()
          end
        end
      end
      new[#new + 1] = line
    end
  end
  -- (si aún puedes fabricar, el paso no avisa de lo que habrá que comprar: con suerte no
  -- hace falta, y si no llegas, la ruta ya te manda a comprar. Antes decía "luego compra
  -- 4 Fine Thread y 1 más" y confundía; Discord)
  if blocking then
    cur.current = false
  end
  for i = #new, 1, -1 do table.insert(lines, craftAt, new[i]) end
end

-- Tras las compras en la AH, "Recoge el correo": te lleva al buzón más cercano y se
-- da por hecho cuando lo comprado está en tus bolsas. El addon no usa el correo: solo
-- sabe lo que compraste (Ledger.OnWay) y lo que llevas. Solo lo de esta ruta (el tramo
-- o la ruta entera, y los pergaminos de sus recetas). Va detrás de las compras y antes
-- de entrenar y fabricar; es el paso actual cuando ya no queda nada por comprar y toca
-- empezar a fabricar (o no puedes, porque lo tienes en el correo)
local MAIL_ICON = "Interface\\Icons\\INV_Letter_15"
local function AddMailLine(lines, plan, page, level)
  if not (ES.Ledger and ES.Ledger.OnWayItems) then return end
  local onWay = ES.Ledger.OnWayItems()
  if not next(onWay) then return end
  local buy = RouteBuy(plan, page.profKey, level, BuyMode(page.profKey))
  local wanted = {}
  for itemID in pairs(buy.need) do wanted[itemID] = true end
  for _, st in ipairs(plan.steps or {}) do
    if st.recipe and st.recipe.scroll then wanted[st.recipe.scroll] = true end
  end
  local items, total = {}, 0
  for itemID, n in pairs(onWay) do
    if wanted[itemID] and n > 0 then
      items[#items + 1] = { itemID = itemID, quantity = n }
      total = total + n
    end
  end
  if #items == 0 then return end
  table.sort(items, function(a, b) return a.quantity > b.quantity or (a.quantity == b.quantity and a.itemID < b.itemID) end)
  -- Saltar (como las compras): solo este tramo
  local profKey, key = page.profKey, VisitKey(page.profKey, buy.phase)
  local visits = ES.routeBuyVisits[profKey]
  if visits and visits.key ~= key then visits = nil end
  local function SetHad(on)
    local v = ES.routeBuyVisits[profKey]
    if not v or v.key ~= key then v = { key = key } ES.routeBuyVisits[profKey] = v end
    v.had = v.had or {}
    v.had.mail = on or nil
  end
  local names = {}
  for i, it in ipairs(items) do
    if i > 3 then break end
    names[#names + 1] = string.format("%s ×%d", ES:DataItemName(it.itemID) or (GetItemInfo and GetItemInfo(it.itemID)) or it.itemID, it.quantity)
  end
  local more = #items > 3 and string.format(L[" y %d más"], #items - 3) or ""
  local pick = WP.Target("mailbox")
  local line = {
    level = tostring(level), icon = MAIL_ICON, title = L["Recoge el correo"],
    sub = L["Lo comprado en la AH: "] .. table.concat(names, ", ") .. more,
    bannerSub = string.format(L["%d objetos comprados en la AH"], total),
    go = pick, mailRow = true, mailItems = items, -- (para pruebas)
    tooltip = function(row)
      GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
      GameTooltip:AddLine(L["Recoge el correo"])
      GameTooltip:AddLine(L["Lo que compraste en la AH para esta ruta. Este paso se da por hecho cuando lo tienes en las bolsas."], 0.8, 0.8, 0.8, true)
      GameTooltip:AddLine(" ")
      for _, it in ipairs(items) do
        GameTooltip:AddDoubleLine(ES:DataItemName(it.itemID) or tostring(it.itemID), "×" .. it.quantity, 1, 1, 1, 1, 1, 1)
      end
      WP.AddToTooltip(L["Buzón más cercano"], pick)
      GameTooltip:Show()
    end,
  }
  if visits and visits.had and visits.had.mail then
    line.done, line.skipped, line.go = true, true, nil
    line.bannerSub = GREY .. L["Saltado · Recuperar lo vuelve a poner"] .. "|r"
    line.unmarkHave = function() SetHad(false) end
  else
    line.markHave = function() SetHad(true) end
  end
  -- Detrás de las compras de la AH (lo del correo es lo comprado allí) y delante de las
  -- del vendedor y el banco: AH -> buzón -> vendedor (ArrangeTrip). Antes iba detrás de
  -- todas y, con algo del vendedor, te mandaba a él aunque tuvieras el buzón delante
  -- (Discord). Sin compras, delante del primer paso de fabricar sin hacer
  local at, lastAH, firstOther, buying
  for i, l in ipairs(lines) do
    if l.buyRow then
      if not l.done then buying = true end
      if l.buyRow == "ah" then lastAH = i elseif not firstOther then firstOther = i end
    end
  end
  if lastAH then
    at = lastAH + 1
  elseif firstOther then
    at = firstOther
  else
    for i, l in ipairs(lines) do if l.stepRecipe and not l.done then at = i break end end
  end
  -- Paso actual: sin compras pendientes y tocando fabricar (o sin un paso actual)
  local cur
  for _, l in ipairs(lines) do if l.current then cur = l break end end
  if not line.done and not buying and (not cur or cur.stepRecipe) then
    if cur then cur.current = nil end
    line.current = true
  end
  table.insert(lines, at or (#lines + 1), line)
end
ES.UI.AddMailLine = AddMailLine -- (para pruebas)
ES.RouteBuy = RouteBuy -- (para pruebas)

-- Al cerrar la AH o el vendedor con compras de la ruta pendientes: ya fuiste. Esas filas
-- dejan de parar la ruta mientras puedas fabricar (si no había, no te quedas atascado).
-- Solo si intentaste comprarlo ahí (Discord: "No había suficiente" sin haber comprado
-- nada): en la AH, si abriste la compra de alguno (ES:OpenAuctionBuy) o compraste
-- alguno; en un vendedor, si vende alguno. Abrir la AH para escanear o un vendedor para
-- vender basura no cuenta. ES.buyTried = { ah = { [itemID] = true }, sells = { ... } }
ES.buyTried = ES.buyTried or { ah = {}, sells = {} }
-- Lo que vende el vendedor abierto (al abrirlo, al cerrarlo si aún se sabe, y cada vez
-- que se pinta una fila de compra con él abierto: a veces llega después de MERCHANT_SHOW)
local function NoteMerchantSells()
  for i = 1, (GetMerchantNumItems and GetMerchantNumItems()) or 0 do
    local id = ES.Ledger and ES.Ledger.MerchantItemID and ES.Ledger.MerchantItemID(i)
    if id then ES.buyTried.sells[id] = true end
  end
end
local function TriedHere(source, items)
  local tried = ES.buyTried
  for _, it in ipairs(items) do
    if source == "ah" then
      if tried.ah[it.itemID] or (ES.Ledger and ES.Ledger.OnWay and ES.Ledger.OnWay(it.itemID) > 0) then return true end
    elseif tried.sells[it.itemID] then
      return true
    end
  end
  return false
end
ES.UI.BuyTriedHere = TriedHere -- (pruebas)
do
  local f = CreateFrame("Frame")
  -- (sin MERCHANT_UPDATE: ese es de la ventana del vendedor, VendorUI.lua)
  ES.SafeRegister(f, "AUCTION_HOUSE_SHOW")
  ES.SafeRegister(f, "MERCHANT_SHOW")
  ES.SafeRegister(f, "AUCTION_HOUSE_CLOSED")
  ES.SafeRegister(f, "MERCHANT_CLOSED")
  ES.SafeRegister(f, "BANKFRAME_CLOSED")
  f:SetScript("OnEvent", function(_, event)
    -- Cada visita empieza de cero
    if event == "AUCTION_HOUSE_SHOW" then ES.buyTried.ah = {} return end
    if event == "MERCHANT_SHOW" then ES.buyTried.sells = {} NoteMerchantSells() return end
    if event == "MERCHANT_CLOSED" then NoteMerchantSells() end
    -- (solo sirve al asistente: sin él, no hay filas de compra)
    if not (ES.Assistant and ES.db and ES.db.prof) then return end
    local source = event == "AUCTION_HOUSE_CLOSED" and "ah" or event == "BANKFRAME_CLOSED" and "bank" or "vendor"
    if source == "bank" and not ES.Assistant.BANK then return end -- (banco apagado: Assistant.lua)
    for _, p in ipairs(ES.PROFESSIONS or {}) do
      local data = ES.Data[p.key]
      local lock = data and ES:RouteLock(p.key)
      local plan = lock and not lock.completed and ES:LockedPlan(p.key)
      if plan then
        local level = ES:GetProfessionSkill(data.skillLine) or plan.from
        local buy = RouteBuy(plan, p.key, level, BuyMode(p.key))
        -- (el banco: lo que falta sale de lo de comprar; ver AddBuyLines)
        local pending = source == "bank" and (buy.ah[1] or buy.vendor[1]) or buy[source][1]
        if pending and source ~= "bank" and not TriedHere(source, buy[source]) then pending = nil end
        if pending then
          local key = VisitKey(p.key, buy.phase)
          local v = ES.routeBuyVisits[p.key]
          if not v or v.key ~= key then v = { key = key } ES.routeBuyVisits[p.key] = v end
          if source == "vendor" then
            -- Por material: solo lo que vendía este vendedor (cerrar a Barkeep Morag, que
            -- vende el Bottle, no da por visitada la fila de las Mild Spices)
            v.vendorSeen = v.vendorSeen or {}
            for _, it in ipairs(buy.vendor) do
              if ES.buyTried.sells[it.itemID] then v.vendorSeen[it.itemID] = true end
            end
          else
            v[source] = true
          end
        end
      end
    end
    if ES.RefreshAfterBags then ES:RefreshAfterBags() end
  end)
end

-- Pasos de conseguir una receta, con la ruta empezada:
--   · comprada en la AH (bought: detectada al comprar, sin mirar el correo): hecho; el
--     paso de fabricar recuerda aprenderla primero;
--   · "Saltar" (la pestaña del asistente): la das por conseguida (por el chat, un
--     alter, si no se detectó la compra...) y queda como hecha; con la flecha de paso
--     anterior y "Recuperar" vuelve. Solo esta sesión (ES.routeSkips)
local function ArrangeRecipeErrands(lines, profKey)
  ES.routeSkips[profKey] = ES.routeSkips[profKey] or {}
  local skips = ES.routeSkips[profKey]
  for i, l in ipairs(lines) do
    local k = not l.done and l.level and l.recipeName and ("recipe:" .. l.recipeName)
    local had = k and (l.bought or skips[k])
    if had then
      l.done, l.current, l.onClick, l.go, l.useItem, l.ahItem = true, nil, nil, nil, nil, nil
      if skips[k] then
        l.skipped = true
        l.bannerSub = GREY .. L["Saltado · Recuperar lo vuelve a poner"] .. "|r"
        l.unmarkHave = function() skips[k] = nil end
      end
      -- Aún sin aprender: el paso de fabricar que la usa lo recuerda
      for j = i + 1, #lines do
        local c = lines[j]
        if c.stepRecipe then
          local text = ORANGE .. string.format(L["aprende %s primero"], l.recipeName) .. "|r"
          c.sub = text .. " · " .. (c.sub or "")
          c.bannerSub = text .. ((c.bannerSub and c.bannerSub ~= "") and (" · " .. c.bannerSub) or "")
          c.learnFirst = l.recipeName -- (para pruebas)
          break
        end
      end
    elseif k then
      l.markHave = function() skips[k] = true end
    end
  end
end
ES.UI.ArrangeRecipeErrands = ArrangeRecipeErrands -- (para pruebas)

-- Vendedor e instructor en el mismo viaje: si toca pasar por el instructor (un rango o
-- una receta que ya puedes aprender, `from` = tu nivel), lo del vendedor se compra al de
-- al lado del instructor (no al más cercano a ti ahora, que podía estar junto a la AH)
-- y va justo detrás de él. El paso actual es el primer recado pendiente en ese orden:
-- AH -> buzón -> instructor -> vendedor de al lado -> fabricar
-- Lo lejos que está un recado (al cuadrado): 0 si ya lo tienes abierto (el vendedor o el
-- buzón: estás ahí); si no, hasta su PNJ (WP.DistanceTo)
local function ErrandDistance(l)
  if l.buyRow == "vendor" and ES.Ledger and ES.Ledger:MerchantOpen() then return 0 end
  if l.mailRow and MailFrame and MailFrame:IsShown() then return 0 end
  local ok, id = pcall(function() return l.go and l.go() end)
  return WP.DistanceTo(ok and id or nil)
end

local function ArrangeTrip(lines, from)
  local trainerLine
  for _, l in ipairs(lines) do
    if (l.rankCap or l.trainerLearn) and not l.done and l.go
        and (l.current or (tonumber(l.level) or math.huge) <= from) then
      trainerLine = l
      break
    end
  end
  if trainerLine then
    local moved = {}
    for i = #lines, 1, -1 do
      local l = lines[i]
      if l.buyRow == "vendor" and not l.done and l.buyItems and l.buyItems[1] then
        -- (el que vende más de la fila, al lado del instructor si lo hay; ver WP.VendorFor)
        local ids, at = {}, trainerLine.go
        for _, it in ipairs(l.buyItems) do ids[#ids + 1] = it.itemID end
        l.go = function() return WP.VendorFor(ids, at()) end
        l.nearTrainer = true
        table.insert(moved, 1, table.remove(lines, i))
      end
    end
    if #moved > 0 then
      local tAt
      for i, l in ipairs(lines) do if l == trainerLine then tAt = i break end end
      for k, l in ipairs(moved) do table.insert(lines, (tAt or #lines) + k, l) end
    end
  end
  local function Errand(l)
    return l.level and (l.buyRow or l.mailRow or l.rankCap or l.trainerLearn or l.recipeName) and true or false
  end
  local cur
  for _, l in ipairs(lines) do if l.current then cur = l break end end
  if cur and Errand(cur) then
    for i, l in ipairs(lines) do
      if l.stepRecipe and not l.done then break end -- (solo los recados de antes de fabricar)
      if Errand(l) and not l.done then
        -- Buzón y vendedor (no el de al lado del instructor), los dos pendientes: al más
        -- cercano primero (Discord: con el buzón delante, te mandaba al vendedor)
        local pick = l
        if l.mailRow or (l.buyRow == "vendor" and not l.nearTrainer) then
          for j = i + 1, #lines do
            local o = lines[j]
            if o.stepRecipe and not o.done then break end
            if not o.done and o ~= l and (o.mailRow or (o.buyRow == "vendor" and not o.nearTrainer)) then
              local dl, d2 = ErrandDistance(l), ErrandDistance(o)
              if d2 < dl then pick = o end
              break
            end
          end
        end
        if pick ~= cur then cur.current = nil pick.current = true end
        break
      end
    end
  end
end
ES.UI.ArrangeTrip = ArrangeTrip -- (para pruebas)

-- opts.buy: con las filas de compra (solo el asistente; ver AddBuyLines)
local function RouteLines(plan, page, opts)
  local lines = {}
  local profIcon, profName = page.profIcon or ES.ICON, page.profName
  local settings = ES.db.prof[page.profKey]
  local locked = settings.lock ~= nil
  -- ✕ de cada paso: quita la receta y se recalcula la ruta con otra en su lugar
  -- (con la ruta empezada, la libera: es decisión tuya cambiarla)
  local function Skip(id)
    return function()
      settings.excluded = settings.excluded or {}
      settings.excluded[id] = true
      ES:StopRoute(page.profKey)
      ES:CalculatePlan(page)
    end
  end
  -- ✕ de "Fabrica 30× Light Leather": no fabricarlo, comprarlo hecho (y no sus materiales)
  local function SkipCraft(itemID)
    return function()
      settings.noCraft = settings.noCraft or {}
      settings.noCraft[itemID] = true
      ES:StopRoute(page.profKey)
      ES:CalculatePlan(page)
    end
  end
  -- Lo que se fabrica antes va justo delante del primer paso que lo usa. Si no lo
  -- usa un paso sino otro material que también se fabrica (Light Leather para la
  -- Fine Leather Tunic), va donde va ese, delante de él: así se fabrica justo
  -- cuando hace falta y no al principio de la ruta
  local craftBefore = {}
  local direct = {} -- [itemID] = primer paso que lo usa directamente
  for _, c in ipairs(plan.crafted) do
    for i, st in ipairs(plan.steps) do
      local uses = false
      for _, rg in ipairs(st.reagents) do
        if rg.item == c.itemID and rg.kinds.craft then uses = true break end
      end
      if uses then direct[c.itemID] = i break end
    end
  end
  -- Herramientas que se fabrican (Runed Golden Rod): van en el paso donde hacen
  -- falta (el nivel de su fila "Herramienta:"), no al principio de la ruta
  local toolAt = {}
  for _, tl in ipairs(plan.tools) do
    for i, st in ipairs(plan.steps) do
      if tl.skill < st.to then toolAt[tl.item] = i break end
    end
  end
  -- Paso donde va cada uno y cuántos fabricados hay entre él y ese paso (depth)
  local placed = {}
  local function Place(c, seen)
    if placed[c.itemID] then return placed[c.itemID] end
    seen = seen or {}
    seen[c.itemID] = true
    local at, depth = direct[c.itemID] or toolAt[c.itemID], 0
    if not at then
      for _, c2 in ipairs(plan.crafted) do
        if not seen[c2.itemID] and c2.recipe then
          for _, rq in ipairs(c2.recipe.r or {}) do
            if rq[1] == c.itemID then
              local p = Place(c2, seen)
              if not at or p.at < at then at, depth = p.at, p.depth + 1 end
            end
          end
        end
      end
    end
    placed[c.itemID] = { at = at or 1, depth = depth }
    return placed[c.itemID]
  end
  for _, c in ipairs(plan.crafted) do
    local p = Place(c)
    craftBefore[p.at] = craftBefore[p.at] or {}
    table.insert(craftBefore[p.at], c)
  end
  -- En el mismo paso, primero lo que usan los otros (el cuero antes que la túnica)
  for _, list in pairs(craftBefore) do
    table.sort(list, function(a, b) return placed[a.itemID].depth > placed[b.itemID].depth end)
  end
  local events = {}
  for _, rk in ipairs(plan.ranks) do events[#events + 1] = { skill = rk.skill, rank = rk } end
  for _, tl in ipairs(plan.tools) do events[#events + 1] = { skill = tl.skill, tool = tl } end
  table.sort(events, function(a, b) return a.skill < b.skill end)

  local ev = 1
  -- Rango sin aprender y ya en el tope del tuyo: es lo que toca (sin él no sube nada más)
  local rankPending = false
  local rankDue -- rango que ya puedes entrenar, antes de llegar a tu tope (aviso)
  local function AddEvent(e)
    if e.rank then
      local rk = e.rank
      local rankName = RANK_NAMES[rk.cap] or (L["rango "] .. rk.cap)
      -- En las secundarias, Experto es un libro del vendedor (y Artesano, una misión)
      local secondary = (page.profKey == "Cooking" or page.profKey == "FirstAid") and rk.cap > 150
      local book = secondary and WP.RANK_BOOKS[page.profKey] and WP.RANK_BOOKS[page.profKey][rk.cap]
      local where = secondary and (rk.cap > 225 and L["Misión"] or L["Libro del vendedor"]) or L["Instructor"]
      local pick, label
      if book then
        pick, label = WP.Target("vendor", book), L["Vendedor más cercano"]
      elseif not secondary then
        pick, label = WP.Target("trainer", page.profKey, rk.cap), L["Instructor más cercano"]
      end
      local line = {
        level = tostring(rk.skill),
        icon = profIcon, -- como en el instructor: el rango lleva el icono de la profesión
        title = string.format(L["Entrenar %s %s(%s)|r"], rankName, GREY, profName),
        sub = string.format(L["%s · sube el tope a %d%s"], where, rk.cap,
          (rk.level or 0) > 0 and string.format(L[" · pide nivel %d"], rk.level) or ""),
        value = Signed(rk.fee), go = pick, rankCap = rk.cap, learnName = rankName,
        -- En el asistente, más corto: la profesión ya se ve en su icono
        bannerTitle = string.format("%s %s", L["Entrenar"], rankName),
        bannerSub = string.format(L["Sube el tope a %d%s"], rk.cap,
          (rk.level or 0) > 0 and string.format(L[" · pide nivel %d"], rk.level) or ""),
      }
      -- Ya aprendido (tu tope real llega a este): hecho, como los pasos pasados
      local cap = page.detected and page.detected.cap
      if cap and cap >= rk.cap then
        line.bannerTitle, line.bannerSub = nil, nil -- (hecho: como la fila, con su ✓)
        local function Plain(s) return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
        line.title = ES.Market.ICON_OK .. GREY .. Plain(line.title) .. "|r"
        line.sub = GREY .. L["Hecho"] .. "|r"
        line.value = line.value and (GREY .. Plain(line.value) .. "|r") or nil
        line.done, line.go, pick = true, nil, nil
      elseif locked and cap and (page.from or 0) >= cap and (page.from or 0) >= rk.skill then
        -- Ruta empezada y en el tope de tu rango: el paso en el que estás es entrenarlo
        line.current, rankPending = true, true
      elseif locked and cap and (page.from or 0) >= rk.skill and not rankDue then
        -- Ya puedes entrenarlo pero aún no estás en tu tope: la ruta sigue y el paso
        -- actual lo recuerda ("entrena Journeyman antes de 75"). Antes se quedaba atrás
        -- sin aviso y parecía saltado; a tu tope pasa a ser el paso actual
        rankDue = { name = rankName, before = cap, line = line }
      end
      if pick then
        line.tooltip = TravelTooltip(string.format(L["Entrenar %s (%s)"], rankName, profName),
          string.format(L["Sube el tope de %s a %d."], profName, rk.cap), label, pick)
      end
      lines[#lines + 1] = line
    else
      local tl = e.tool
      local name, texture = ItemLabel(tl.item, L["Herramienta "] .. tl.item)
      local line = {
        level = tostring(tl.skill),
        icon = texture or 134400, title = L["Herramienta: "] .. name,
        sub = L["Se consigue una vez y no se gasta"],
        value = Signed(tl.cost), item = tl.item,
        tooltip = SimpleTooltip(tl.item, L["Los siguientes pasos la necesitan. Sus materiales están en la lista de compra."]),
      }
      -- Ya la tienes (comprada o fabricada por ti): hecha, como los pasos acabados
      if ES:ItemCount(tl.item) > 0 then
        local function Plain(s) return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
        line.title = ES.Market.ICON_OK .. GREY .. Plain(line.title) .. "|r"
        line.sub = GREY .. L["Ya la tienes"] .. "|r"
        line.value = line.value and (GREY .. Plain(line.value) .. "|r") or nil
        line.done = true
      end
      lines[#lines + 1] = line
    end
  end
  local routeSecs = 0 -- lo que queda de fabricar en toda la ruta (fila del total)
  for i, st in ipairs(plan.steps) do
    while events[ev] and events[ev].skill <= st.from do AddEvent(events[ev]) ev = ev + 1 end
    -- Ruta fijada: los pasos que ya has pasado se marcan hechos (sin fila de aprender)
    local done = locked and st.to <= (page.from or 0)
    -- Ruta empezada: tu nivel cae en el tramo de este paso
    local inStep = locked and not done and (page.from or 0) >= st.from and (page.from or 0) < st.to
    -- Lo que hay que fabricar antes: en el paso actual, la primera que te falta es
    -- el paso en el que estás (antes que aprender la receta o fabricarla)
    local prepPending = false
    local afterStep = {} -- (lo que se fabrica más tarde: después de la fila del paso)
    for _, c0 in ipairs(craftBefore[i] or {}) do
      -- Ruta empezada: lo que gastan los niveles que te QUEDAN, no los de toda la ruta
      -- (en 229 de una túnica de 226 a 230 quedan las de un punto, no las 20 del
      -- principio). Si ya no hace falta, no sale
      -- quantity: lo que tienes que llevar de él (lo fabricado más lo que la ruta saca de
      -- tus bolsas); abajo se le resta lo que llevas
      local c = { itemID = c0.itemID, recipe = c0.recipe, from = c0.from, prof = c0.prof, quantity = ES.Planner.CraftedTotal(c0) }
      if locked and (page.from or 0) > (plan.from or 0) then
        local rem = ES.Planner.CraftedNeedFrom(plan, c0.itemID, page.from, true)
        if rem then c.quantity = math.min(c.quantity, math.ceil(rem - 0.001)) end
      end
      -- Comprando por tramos: lo del tramo, como la Lista de compra (los Bolt que da el
      -- Silk que pide). Un paso que aún no ha llegado, lo de su tramo cuando llegues.
      -- CurseForge: la compra del tramo pedía 32 Silk y esta fila "Fabrica 82×"
      if locked and ES.Shopping.ByPhase(page.profKey) then
        local inPhase = ES.Planner.PhaseCraftedNeed(plan, c0.itemID, math.max(page.from or 0, st.from))
        if inPhase then c.quantity = math.min(c.quantity, inPhase) end
      end
      if c.quantity > 0 then
      local name, texture = ItemLabel(c.itemID, L["Objeto "] .. c.itemID)
      local conversion = c.recipe and c.recipe.conversion
      -- Clic: como en los pasos, abre su receta y fabrica lo que falta (3 restos -> 1 cuero)
      local outQty = c.recipe and c.recipe.out and c.recipe.out[2] or 1
      local missing = math.max(0, c.quantity - ES:ItemCount(c.itemID))
      local crafts = math.ceil(missing / outQty - 0.001)
      local recipeID = c.recipe and c.recipe.id
      local craftNow = not conversion and recipeID and crafts > 0 and ES:IsRecipeKnown(recipeID)
      -- Se empieza a fabricar más tarde que el paso (cuando ya no da puntos: la pólvora
      -- a partir de 40): su fila va después del paso, con ese nivel (la ruta va en orden)
      -- (una de otra profesión no sube puntos de esta: nunca "más tarde")
      local later = c.from and c.from > st.from and not conversion and not c.prof and c.from or nil
      local current, prepLater
      if later then
        current = locked and not rankPending and (page.from or 0) >= later and (page.from or 0) < st.to and missing > 0
      else
        current = inStep and not rankPending and not prepPending and missing > 0
        -- No puedes fabricar ni uno (sin sus materiales) pero sí el paso: no te quedas
        -- parado en él. Sigues con el paso con lo que llevas y, al acabarse, la ruta te
        -- lleva a comprar (la compra por tandas no pide nada mientras puedas fabricar el
        -- paso). Discord: "Fabrica 3× Bolt of Linen Cloth" con 1 Linen Cloth y sin compra
        if current and not conversion and recipeID and ES.CraftableFromBags then
          local canMake = ES.CraftableFromBags(recipeID)
          local canStep = ES.CraftableFromBags(st.id)
          if canMake == 0 and canStep and canStep >= 1 then current, prepLater = false, true end
        end
        if current then prepPending = true end
      end
      -- Obligatorio: no se puede comprar hecho (se liga al recogerlo, o no está en la
      -- AH ni en ningún vendedor). Sin ✕: no hay otra forma de tenerlo
      local isTool = toolAt[c.itemID] ~= nil
      local buyable = not (c.recipe and c.recipe.bop)
        and (ES.Data.VendorPrices[c.itemID] or (plan.ctx and plan.ctx.ladders[c.itemID])) ~= nil
      local mandatory = not buyable
      local why = mandatory and (isTool and L["Herramienta para los pasos siguientes: no se puede comprar, hay que fabricarla"]
        or L["Hace falta para los pasos siguientes y no se puede comprar: hay que fabricarlo"])
      -- El título dice cuántas te QUEDAN por fabricar (lo que llevas ya cuenta: también lo
      -- que sale del paso de antes), y debajo, cuántas hacen falta en total. Discord:
      -- "Fabrica 149×" junto a un paso que ya fabrica lo mismo: ¿149 en total o más?
      local have = math.min(c.quantity, ES:ItemCount(c.itemID))
      local title, sub = string.format("%s %d× %s", L["Fabrica"], missing > 0 and missing or c.quantity, name),
        why or (isTool and L["Herramienta para los pasos siguientes: sale más barato que comprarla"]
          or L["Para los pasos siguientes: sale más barato que comprarlo"])
      local bannerSub -- (en el asistente, sin el porqué "Para los pasos siguientes...": está en la ventana)
      if not conversion then
        local count
        if missing == 0 then
          title = ES.Market.ICON_OK .. GREY .. string.format(L["Ya tienes %d× %s"], c.quantity, (tostring(name):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))) .. "|r"
          count = GREY .. string.format(L["los %d que hacen falta"], c.quantity) .. "|r"
        elseif have > 0 then
          count = string.format(L["%d en total · tienes %d"], c.quantity, have)
        else
          count = string.format(L["%d en total"], c.quantity)
        end
        -- (si cada fabricación da varias, cuántas veces hay que fabricar)
        if missing > 0 and outQty > 1 then count = count .. " · " .. string.format(L["%d fabricaciones"], crafts) end
        -- Lo que se tarda en fabricar lo que falta (como en los pasos: Discord, "Fabrica
        -- 136× Bolt of Linen Cloth" sin tiempo)
        if missing > 0 and recipeID then
          count = count .. " · " .. DurationIcon(crafts * ES.Planner.CraftSeconds(recipeID))
        end
        sub = count .. " · " .. sub
        bannerSub = count
        if prepLater then
          local text = ORANGE .. L["sin materiales: sigue con el paso, se compran en la siguiente tanda"] .. "|r"
          sub, bannerSub = text .. " · " .. sub, text .. " · " .. bannerSub
        end
      end
      if conversion then
        -- Esencias: se convierten con clic derecho sobre las de origen (1 Greater Magic
        -- Essence -> 3 Lesser, o 3 Lesser -> 1 Greater). Se dice cuáles, cuántas
        -- veces y, si aún no las tienes, que se compran antes (lista de la compra)
        local fromID, per = c.recipe.r[1][1], c.recipe.r[1][2]
        local uses = math.ceil((missing > 0 and missing or c.quantity) / outQty - 0.001)
        local fromName = ItemLabel(fromID, L["Objeto "] .. fromID)
        title = string.format(L["Convierte %d %s en %d %s"], uses * per, fromName, uses * outQty, name)
        sub = string.format(L["Clic derecho en las %s de tus bolsas (%d veces)"], ES:DataItemName(fromID) or fromName, uses)
        if missing > 0 and ES:ItemCount(fromID) < uses * per then
          sub = sub .. ORANGE .. L[" · primero cómpralas (lista de la compra)"] .. "|r"
        end
      end
      if later then
        local at = string.format(L["Al llegar a %d (antes aún te sube puntos)"], later)
        sub = at .. " · " .. sub
        if bannerSub then bannerSub = at .. " · " .. bannerSub end
      end
      -- Con una receta de otra profesión (Smelt Mithril): de cuál es, en la fila y en el
      -- asistente. Abre la receta en la ventana de esa profesión (ES:OpenRecipe)
      if c.prof then
        title = title .. " " .. GREY .. "(" .. string.format(L["con %s"], ES:ProfLabel(c.prof)) .. ")|r"
      end
      local line = {
        level = tostring(later or st.from),
        icon = texture or 134400,
        title = title,
        sub = sub, bannerSub = bannerSub,
        item = c.itemID, current = current, craftProf = c.prof,
        stepRecipe = not conversion and recipeID or nil,
        craftCount = craftNow and crafts or nil, -- (para pruebas)
        onClick = not conversion and recipeID and function()
          if craftNow then ES:CraftRecipe(recipeID, crafts) else ES:OpenRecipe(recipeID) end
        end or nil,
        -- ✕: no fabricarlo, comprarlo hecho (se recupera con "Recetas quitadas")
        onSkip = not conversion and not mandatory and SkipCraft(c.itemID) or nil,
        skipTip = L["No fabricarlo: la ruta lo compra hecho en la AH (sin comprar sus materiales). Se recupera con la fila de recetas quitadas."],
        tooltip = function(row)
          SimpleTooltip(c.itemID, L["Sale más barato fabricarlo que comprarlo; sus materiales ya están en la lista de compra."])(row)
          if not conversion and recipeID then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(craftNow and string.format(L["Clic: abrir la receta y fabricar %d (como mucho, las que te dan los materiales que llevas)."], crafts)
              or L["Clic: abrir la receta en tu profesión."], 0.5, 0.8, 1, true)
            GameTooltip:Show()
          end
        end,
      }
      -- Su receta aún no la sabes (Stonescale Oil, del instructor): antes, aprenderla. Es
      -- el paso actual mientras no la sepas (Discord: "me dice que fabrique 14 y no la
      -- tengo aprendida"). Su precio ya va en la ruta (plan.prepLearn)
      local prep = recipeID and plan.prepLearn and plan.prepLearn[recipeID]
      if prep and missing > 0 and not ES:IsRecipeKnown(recipeID) then
        local pr = c.recipe
        local trainer = prep.source == "trainer"
        local learnAt = pr.train or (pr.t and pr.t[1]) or st.from
        local pick, plabel
        if trainer and pr.tr then
          local who = pr.rankTr or pr.tr
          pick, plabel = function() return WP.Nearest(who) end, L["Instructor más cercano"]
        elseif trainer then
          pick, plabel = WP.Target("trainer", page.profKey, learnAt + 1), L["Instructor más cercano"]
        elseif pr.scroll then
          pick, plabel = WP.Target("vendor", pr.scroll), L["Vendedor más cercano"]
        end
        local ltitle = string.format("%s %s", trainer and L["Entrenar"] or L["Comprar receta:"], pr.name)
        local lsub = (LEARN_WHERE[prep.source] or "?") .. " · " .. string.format(L["para fabricar %s"], name)
        local learnLine = {
          level = line.level, icon = trainer and TRAIN_ICON or RECIPE_ICON, title = ltitle, sub = lsub,
          value = prep.cost > 0 and Signed(prep.cost) or (GREY .. "?|r"), go = pick,
          current = line.current, prepLearn = recipeID, -- (para pruebas)
          trainerLearn = trainer or nil, learnName = pr.name, learnAt = learnAt, learnID = recipeID,
          tooltip = pick and TravelTooltip(ltitle, string.format(L["%s · requiere %s (%d) · cuesta %s"], LEARN_WHERE[prep.source] or "?",
            profName, learnAt, prep.cost > 0 and ES.Money(prep.cost) or L["precio desconocido"]), plabel, pick) or nil,
        }
        line.current = nil
        if later then afterStep[#afterStep + 1] = learnLine else lines[#lines + 1] = learnLine end
      end
      if later then afterStep[#afterStep + 1] = line else lines[#lines + 1] = line end
      end -- (c.quantity > 0)
    end
    local r = st.recipe
    local name, texture = ItemLabel(r.out and r.out[1] or 0, r.name)
    -- Aprender la receta: fila propia (como en el instructor), con su coste
    -- Ya la sabes ("known"): sin fila de aprender
    local learnSource = not done and st.learnSource ~= "known" and st.learnSource or nil
    local learnLines = #lines -- (para marcar la fila de aprender si ya la sabes)
    -- Precio y nivel del instructor: lo visto en el juego, si no, los datos
    local fee, train = ES.Planner.Fee(r)
    local sourcedLine = learnSource and learnSource ~= "favor" and r.scroll and not fee and WP.SOURCED_PROFESSIONS[page.profKey]
      and SourcedLearnLine(r, st, profName, plan)
    if learnSource == "favor" then
      -- Merchant's Favor: en el campamento de tu bando, con fichas (no oro)
      local title = L["Conseguir receta: "] .. r.name
      local pick = WP.Target("vendor", r.scroll)
      local sub = string.format(L["Merchant's Favor: %d fichas"], r.favor)
        .. (r.favorRep and (" · " .. string.format(L["pide %s con el campamento"], ES.StandingName(r.favorRep))) or "")
      lines[#lines + 1] = {
        level = tostring(st.from), -- cuándo toca en la ruta (la columna va en orden)
        icon = "Interface\\Icons\\INV_Misc_Coin_17", title = title, sub = sub,
        value = string.format("|cff66bbff%d|r", r.favor), go = pick, onSkip = Skip(st.id),
        tooltip = TravelTooltip(title, sub, L["Vendedor más cercano"], pick),
      }
    elseif sourcedLine then
      sourcedLine.onSkip = Skip(st.id)
      sourcedLine.level = tostring(st.from) -- cuándo toca en la ruta (la columna va en orden)
      lines[#lines + 1] = sourcedLine
    elseif learnSource then
      local trainer = st.learnSource == "trainer"
      local learnAt = train or st.from
      -- Al pulsar: el instructor que enseña hasta ese nivel, o quien vende la receta
      local pick, label
      -- Visto en un instructor concreto: a ese (Forever enseña algunas solo en ciertos
      -- sitios); si no, el más cercano del rango
      local seenAt = ES.db.trainerFees and ES.db.trainerFees[st.id] and ES.db.trainerFees[st.id].npc
      -- El instructor de su rango no la tiene (ver Ledger:ReadTrainer): en Forever la
      -- enseña el del rango siguiente
      local upRank = trainer and not seenAt and ES.db.trainerMissing and ES.db.trainerMissing[st.id] == "rank"
      if trainer and seenAt then
        pick, label = function() return seenAt end, L["Instructor donde la viste"]
      elseif trainer and r.tr then
        -- Los datos dicen quién la enseña (no el del rango por nivel: Green Iron
        -- Leggings, de 130, la enseñan los de Experto); de ellos, los del rango que pide
        -- (rankTr, ver Planner RankGate: a Bengus o Saru, no a Brikk en Booty Bay)
        local who = r.rankTr or r.tr
        pick, label = function() return WP.Nearest(who) end, L["Instructor más cercano"]
      elseif upRank then
        local nextRank = (math.floor(math.max(0, learnAt - 1) / 75) + 1) * 75 + 1
        pick, label = WP.Target("trainer", page.profKey, nextRank), L["Instructor del rango siguiente"]
      elseif trainer then
        pick, label = WP.Target("trainer", page.profKey, learnAt + 1), L["Instructor más cercano"]
      elseif r.scroll then
        pick, label = WP.Target("vendor", r.scroll), L["Vendedor más cercano"]
      end
      local title = string.format("%s %s", trainer and L["Entrenar"] or L["Comprar receta:"], r.name)
      lines[#lines + 1] = {
        level = tostring(st.from), -- cuándo toca en la ruta (se puede aprender desde learnAt)
        icon = trainer and TRAIN_ICON or RECIPE_ICON,
        title = title,
        sub = upRank and L["Instructor del rango siguiente (el de su rango no la tiene)"] or LEARN_WHERE[st.learnSource] or "?",
        -- "?": fuente desconocida, o instructor de una receta nueva de Forever (precio sin datos)
        value = (st.learnSource == "unknown" or (r.trainer and not fee)) and (GREY .. "?|r") or Signed(st.fee),
        go = pick, onSkip = Skip(st.id),
        trainerLearn = trainer or nil, learnName = r.name, learnAt = learnAt, learnID = st.id, -- (para "aprende X sin irte")
        tooltip = pick and TravelTooltip(title, string.format(L["%s · requiere %s (%d) · cuesta %s"], LEARN_WHERE[st.learnSource] or "?",
          profName, learnAt, (r.trainer and not fee) and L["precio desconocido"] or ES.Money(st.fee)), label, pick) or nil,
      }
    end
    local learnPending = false
    if locked and #lines > learnLines then
      local line = lines[#lines]
      if ES:IsRecipeKnown(st.id) then
        -- Ya aprendida (en el instructor, de pergamino...): la fila de aprender queda
        -- hecha, como los pasos acabados (✓ y en gris)
        local function Plain(s) return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
        line.title = ES.Market.ICON_OK .. GREY .. Plain(line.title) .. "|r"
        line.sub = GREY .. L["Aprendida"] .. "|r"
        line.value = line.value and (GREY .. Plain(line.value) .. "|r") or nil
        line.done, line.onSkip, line.go = true, nil, nil
      elseif inStep then
        -- Aún no la sabes y ya toca: el paso actual es aprenderla, no fabricarla
        -- (salvo que antes falte fabricar algún material: entonces es ese)
        line.current, learnPending = not prepPending and not rankPending, true
      end
    end
    local perPoint = st.expected / (st.to - st.from)
    -- Lo que falta de este paso desde tu nivel (con la ruta empezada puedes ir por la mitad)
    local level = math.max(st.from, math.min(st.to, page.from or st.from))
    -- Con lo que fabrica de más para pasos siguientes (st.ahead, "60 pólvoras y
    -- guárdalas"): al acabar el paso tienes que llevar todo lo fabricado, así que lo
    -- que falta es lo que te falta en las bolsas, si es más que lo de los puntos
    local outID, outQty = r.out and r.out[1], (r.out and r.out[2]) or 1
    local function Left(lvl)
      local n = math.ceil(st.expected * (st.to - lvl) / (st.to - st.from) - 0.001)
      -- Con la probabilidad de cada nivel: lo de los niveles que quedan más lo que falta
      -- del tuyo, descontando lo que ya fabricaste en él (ES.CraftsAtLevel). Si no, en
      -- verde el número solo bajaba al subir un punto (Discord: "Fabrica 35× Linen Bag"
      -- fabricando y sin bajar)
      local pc = plan.pointChance
      if pc and pc[lvl] and pc[lvl] > 0 then
        local rest = 0
        for s = lvl + 1, st.to - 1 do rest = rest + 1 / math.max(pc[s] or 1, 0.01) end
        local here = math.max(1, 1 / pc[lvl] - ES.CraftsAtLevel(st.id, lvl))
        n = math.ceil(rest + here - 0.001)
      end
      if (st.aheadCrafts or 0) > 0 and outID then
        local total = (st.crafts + st.aheadCrafts) * outQty
        n = math.max(n, math.ceil((total - ES:ItemCount(outID)) / outQty - 0.001))
      end
      return n
    end
    local left = Left(level)
    local aheadText = ""
    for _, a in ipairs(st.ahead or {}) do
      aheadText = aheadText .. string.format(L[" · +%d para %s"], a.quantity, a.recipe and a.recipe.name or "?")
    end
    -- El paso en el que estás (si antes hay que aprender la receta, es esa fila)
    local current = inStep and not learnPending and not prepPending and not rankPending
    -- Lo que se tarda en fabricar este paso (lo que falta, si vas por él)
    local craftSecs = ES.Planner.CraftSeconds(st.id)
    -- Ya por encima del principio del paso (subiste con otra receta, o falta aprender
    -- esta): lo que queda desde tu nivel, no las del plan. Si no, a 240 seguía "33
    -- fabricaciones" del paso 236-265 sin la receta aprendida (Discord)
    local started = level > st.from and not done
    local stepCrafts = (current or started) and left or (st.crafts + (st.aheadCrafts or 0))
    local stepSecs = done and 0 or craftSecs * stepCrafts
    routeSecs = routeSecs + stepSecs
    local timeText = ""
    if not done and (craftSecs >= SLOW_CRAFT or stepSecs >= LONG_STEP) then
      timeText = " · " .. (craftSecs >= SLOW_CRAFT and ORANGE or "") .. DurationIcon(stepSecs) .. (craftSecs >= SLOW_CRAFT and "|r" or "")
    end
    -- Compra por tandas: lo que llevas da para menos fabricaciones de las que pide el paso
    -- (en verde se compra una tanda; al gastarla, la siguiente). Se dice, para que "101
    -- fabricaciones" con material para 78 no parezca un fallo (Discord: Bolt of Linen Cloth)
    local batchText
    if inStep and locked and not done and ES.CraftableFromBags then
      local fit = ES.CraftableFromBags(st.id)
      if fit and fit > 0 and fit < stepCrafts then
        batchText = string.format(L["esta tanda: %d"], fit)
      end
    end
    -- Clic: abre la receta y, con la opción "Fabricar al pulsar" (por defecto), fabrica lo que falta
    local craftNow = not done and left > 0 and ES:IsRecipeKnown(st.id)
    local recipeTooltip = RecipeTooltip(st, plan)
    local function tooltip(row)
      recipeTooltip(row)
      if batchText then
        GameTooltip:AddLine(" ")
        -- (con suerte puede bastar: no se dice que haya que comprar más)
        GameTooltip:AddLine(string.format(L["Lo que llevas da para %d de las ~%d fabricaciones del paso. Con suerte te basta; si no, al acabarlo la ruta te llevará a comprar más."],
          ES.CraftableFromBags(st.id) or 0, stepCrafts), 1, 1, 1, true)
        GameTooltip:AddLine(L["En las recetas verdes (y a veces en las amarillas) no todas las fabricaciones suben punto, así que la ruta compra por tandas: cuando gastas una, te trae a comprar la siguiente y luego vuelves a fabricar."], 1, 0.82, 0, true)
      end
      -- (el tiempo del paso ya va en la fila: aquí solo si es lenta, por qué y qué hacer)
      if not done and craftSecs >= SLOW_CRAFT then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(string.format(L["Lenta: %s por fabricación."], Duration(craftSecs))
          .. ((row and row.onSkip) and (" " .. L["Si prefieres otra receta, quítala con la X (o activa \"Menos fabricaciones\", que evita las lentas)."]) or ""),
          1, 0.6, 0.2, true)
      end
    end
    lines[#lines + 1] = {
      onClick = function()
        if not craftNow then ES:OpenRecipe(st.id) return end
        -- Lo que falta, con tu nivel de ahora (no el del último pintado: si la página
        -- se quedó atrás, fabricaba de 2 en 2). Ya pasado el paso: solo abre la receta
        local now = ES:GetProfessionSkill(page.data.skillLine) or level
        local lvl = math.max(st.from, math.min(st.to, now))
        local n = Left(lvl)
        if n > 0 then ES:CraftRecipe(st.id, n) else ES:OpenRecipe(st.id) end
        if now ~= page.from then ES:RefreshAfterSkill() end
      end,
      craftCount = craftNow and left or nil, -- (para pruebas)
      stepRecipe = st.id, -- (filas de compra: ¿puedes fabricarla ya?)
      level = st.from .. "–" .. st.to, -- columna de nivel: el tramo
      done = done, current = current,
      icon = texture or 134400,
      -- Hecho: icono de "listo" (la fuente no tiene ✓) y el nombre en gris (sin el color de calidad)
      title = done and (ES.Market.ICON_OK .. GREY .. name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. "|r") or name,
      -- En el asistente, con el verbo: "Fabrica ~12× Bolt of Runecloth" (lo que te queda)
      bannerTitle = not done and string.format("%s %d× %s", L["Fabrica"], stepCrafts, name) or nil,
      -- y debajo solo cuántas y cuánto se tarda (sin precios: eso está en la ventana)
      -- (sin "53 fabricaciones": ya lo dice el título. La tanda, corta, para que quepa en
      -- una línea; el porqué y que luego se compra más, en el tooltip)
      bannerSub = not done and ((batchText and (batchText .. " · ") or "") .. DurationIcon(stepSecs)) or nil,
      batchText = batchText, -- (para pruebas)
      sub = done and (GREY .. L["Hecho"] .. "|r")
        -- Lo que llevas se mide en puntos (tu nivel), no en fabricaciones de esta
        -- receta: los puntos que te dé otra (Bolt of Woolen Cloth) también cuentan
        or current and (string.format(L["%d/%d puntos · ~%s%d|r fabricaciones más · %s/u"], level - st.from, st.to - st.from,
          GOLD, left, ES.Money(st.unitCost)) .. (batchText and (" · " .. batchText) or "") .. timeText .. aheadText)
        or (string.format(L["%s%d fabricaciones|r · %s/u"], perPoint > LOW_CHANCE_CRAFTS and ORANGE or "",
        stepCrafts, ES.Money(st.unitCost)) .. (batchText and (" · " .. batchText) or "") .. timeText .. aheadText),
      -- (la segunda mejor receta y por qué es peor va solo en el tooltip: AddAltTooltip)
      value = Signed(st.total - st.fee), item = r.out and r.out[1], -- lo de aprender va en su fila
      onSkip = not done and Skip(st.id) or nil,
      tooltip = function(row)
        tooltip(row)
        AddAltTooltip(plan, i, page.data, row)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(craftNow and string.format(L["Clic: abrir la receta y fabricar %d (como mucho, las que te dan los materiales que llevas)."], left)
          or L["Clic: abrir la receta en tu profesión."], 0.5, 0.8, 1, true)
        GameTooltip:Show()
      end,
    }
    -- Lo que se fabrica más tarde dentro de este paso (la pólvora a 40), en su sitio:
    -- tras el paso y tras lo que pase antes de ese nivel (entrenar un rango a 30...)
    table.sort(afterStep, function(a, b) return tonumber(a.level) < tonumber(b.level) end)
    for _, line in ipairs(afterStep) do
      while events[ev] and events[ev].skill < tonumber(line.level) do AddEvent(events[ev]) ev = ev + 1 end
      lines[#lines + 1] = line
    end
  end
  while events[ev] do AddEvent(events[ev]) ev = ev + 1 end
  -- Aún no tienes la profesión: lo primero es aprenderla en su instructor (Aprendiz).
  -- Siempre la primera fila y el paso actual: sin ella no se puede hacer nada más
  if not page.detected then
    for _, line in ipairs(lines) do line.current = nil end
    local secondary = page.profKey == "Cooking" or page.profKey == "FirstAid"
    local pick = WP.Target("trainer", page.profKey, 1)
    local title = string.format(L["Aprende %s"], profName)
    local text = L["Aún no la tienes: apréndela en su instructor (Aprendiz, gratis o casi). Sube el tope a 75."]
    if not secondary then
      text = text .. "\n" .. L["Solo puedes tener dos profesiones principales (las de recolección también cuentan): si ya tienes dos, tendrías que olvidar una."]
    end
    local learnLine = {
      level = "1", icon = profIcon, title = title, current = true, learnProfession = true,
      sub = L["Instructor · aún no la tienes"],
      go = pick, tooltip = TravelTooltip(title, text, L["Instructor más cercano"], pick),
    }
    -- Con el instructor abierto, el clic la aprende (Apprentice Tailoring), como los rangos
    if ES.Ledger and ES.Ledger.TrainerOpen and ES.Ledger.TrainerOpen() then
      local targets = { { profession = page.profKey } }
      learnLine.onClick = function() ES.Ledger.LearnAtTrainer(targets) end
      learnLine.learnTargets = targets -- (para pruebas)
      local tip = learnLine.tooltip
      learnLine.tooltip = function(row)
        tip(row)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Clic: aprenderlo en este instructor."], 0.5, 0.8, 1, true)
        GameTooltip:Show()
      end
    end
    -- "Saltar" (como las compras y las recetas): para hacer antes otra cosa, si estás
    -- delante de la AH. Queda como hecha y el paso actual es el siguiente; "Recuperar" la
    -- devuelve. Solo esta sesión (ES.routeSkips); al aprenderla deja de salir
    ES.routeSkips[page.profKey] = ES.routeSkips[page.profKey] or {}
    local skips = ES.routeSkips[page.profKey]
    if skips.learnprof then
      learnLine.done, learnLine.skipped, learnLine.current = true, true, nil
      learnLine.onClick, learnLine.go = nil, nil
      learnLine.bannerSub = GREY .. L["Saltado · Recuperar lo vuelve a poner"] .. "|r"
      learnLine.unmarkHave = function() skips.learnprof = nil end
    else
      learnLine.markHave = function() skips.learnprof = true end
    end
    table.insert(lines, 1, learnLine)
  end
  -- Para el asistente, con la ruta empezada y sin acabar: lo que falta comprar, delante
  -- del paso en el que estás (la ventana lo tiene en Materiales y la Lista de compra)
  if opts and opts.buy and locked and (page.from or 0) < settings.lock.to then
    AddBuyLines(lines, plan, page, page.from or plan.from)
    AddMailLine(lines, plan, page, page.from or plan.from)
  end
  if locked then ArrangeRecipeErrands(lines, page.profKey) end
  -- En el tope de tu rango, el único paso actual es entrenarlo: si el paso de fabricar
  -- empezaba antes del nivel del rango y lo cruzaba (de 120 a 160 con Expert a 125), ya
  -- se había marcado como actual antes de saber que estás en tu tope (dos pasos actuales)
  if rankPending then
    for _, line in ipairs(lines) do
      if line.current and not line.rankCap then line.current = nil end
    end
  end
  -- Rango que ya puedes entrenar (rankDue) antes de tu tope: es el paso actual justo
  -- antes de empezar a fabricar (hechos ya la receta y las compras: primero la AH y
  -- luego el instructor, donde fabricas y sigues aprendiendo sin irte) o si lo actual
  -- es aprender en el instructor (el mismo sitio). A mitad de fabricar, o con recados
  -- pendientes (receta, compras), solo un aviso (abajo)
  if rankDue and not rankPending then
    local cur
    for _, line in ipairs(lines) do if line.current then cur = line break end end
    local start = cur and tonumber(tostring(cur.level or ""):match("^(%d+)"))
    local craftStart = cur and cur.stepRecipe and start and (page.from or 0) <= start
    if cur and (craftStart or cur.trainerLearn) then
      cur.current = nil
      rankDue.line.current, rankDue.promoted, rankPending = true, true, true
    end
    -- Y en la lista, donde toca hacerlo (la ruta lo ponía por nivel, delante de la
    -- receta de la AH): justo antes de empezar a fabricar, tras la receta y las compras.
    -- A mitad de fabricar, justo después del paso en curso
    local rl = rankDue.line
    for i, line in ipairs(lines) do if line == rl then table.remove(lines, i) break end end
    local midCraft = cur and cur.stepRecipe and not craftStart and not rankDue.promoted
    local at
    for i, line in ipairs(lines) do
      if midCraft then
        if line == cur then at = i + 1 break end
      elseif line.stepRecipe and not line.done then
        at = i
        break
      end
    end
    table.insert(lines, at or (#lines + 1), rl)
  end
  ArrangeTrip(lines, page.from or 0)
  -- En el instructor (en todas las rutas), menos viajes:
  --   · aprende ya las recetas del instructor que la ruta usará más tarde y que ya
  --     puedes aprender por nivel (si no, vuelves solo a por ellas);
  --   · si lo siguiente es fabricar y luego volver a él (otro rango o una receta que
  --     aún no puedes aprender): fabrica allí y aprende lo siguiente sin irte
  for i, line in ipairs(lines) do
    if line.current and (line.rankCap or line.trainerLearn) then
      local also = {}
      for j, l in ipairs(lines) do
        if j ~= i and l.trainerLearn and not l.done and (l.learnAt or math.huge) <= (page.from or 0) then
          also[#also + 1] = l
          l.learnNow = true -- (para pruebas)
        end
      end
      -- Con el instructor abierto, el clic aprende lo que toca (y lo de "aprende también")
      if ES.Ledger and ES.Ledger.TrainerOpen and ES.Ledger.TrainerOpen() then
        local targets = { line.rankCap and { rank = line.rankCap, rankName = line.learnName } or { recipeID = line.learnID } }
        for _, l in ipairs(also) do targets[#targets + 1] = { recipeID = l.learnID } end
        line.onClick = function() ES.Ledger.LearnAtTrainer(targets) end
        line.learnTargets = targets -- (para pruebas)
        local tip = line.tooltip
        line.tooltip = function(row)
          if tip then tip(row) else GameTooltip:SetOwner(row, "ANCHOR_RIGHT") GameTooltip:AddLine(line.title or "") end
          GameTooltip:AddLine(" ")
          GameTooltip:AddLine(L["Clic: aprenderlo en este instructor."], 0.5, 0.8, 1, true)
          GameTooltip:Show()
        end
      end
      if #also > 0 then
        local names = {}
        for _, l in ipairs(also) do names[#names + 1] = l.learnName end
        local text = ORANGE .. string.format(L["aprende también: %s"], table.concat(names, ", ")) .. "|r"
        line.sub = (line.sub or "") .. " · " .. text
        line.bannerSub = text
        line.alsoLearn = also -- (para pruebas)
      end
      for j = i + 1, #lines do
        local l = lines[j]
        if (l.trainerLearn or l.rankCap) and not l.learnNow then
          if not l.done then
            -- Solo en el asistente y corto: la lista ya enseña el orden (lo siguiente es
            -- volver al instructor); lo que no dice es que fabriques allí
            local text = ORANGE .. string.format(L["fabrica aquí hasta %s"], l.level) .. "|r"
            line.bannerSub = line.alsoLearn and (line.bannerSub .. " · " .. text) or text
            line.stayFor = l -- (para pruebas)
          end
          break
        elseif l.learnNow or l.nearTrainer then
          -- (ya se aprende en esta visita, o se compra al lado: no corta la estancia)
        elseif not (l.done or l.stepRecipe or not l.level) then
          break -- (otro recado por medio: receta, compra... no se queda allí)
        end
      end
      break
    end
  end
  -- En la AH con la ruta entera (lo has elegido: comprar todo de golpe), las recetas de
  -- la AH que la ruta usa más tarde, en el mismo viaje. Por tramos no: cada tramo compra
  -- solo lo suyo, para no gastar en lo que quizá no haga falta
  if locked and not ES.Shopping.ByPhase(page.profKey) then
    for i, line in ipairs(lines) do
      if line.current and (line.ahItem or line.buyRow == "ah") then
        local names, recipes = {}, {}
        for j, l in ipairs(lines) do
          if j ~= i and l.ahItem and not l.done and l.recipeName then
            names[#names + 1] = l.recipeName
            recipes[#recipes + 1] = l
            l.buyNow = true -- (para pruebas)
          end
        end
        if #names > 0 then
          local text = ORANGE .. string.format(L["compra también la receta: %s"], table.concat(names, ", ")) .. "|r"
          line.sub = (line.sub or "") .. " · " .. text
          line.bannerSub = ((line.bannerSub and line.bannerSub ~= "") and (line.bannerSub .. " · ") or "") .. text
          -- Y como pasos de esa misma parada: justo detrás de las compras de la AH (y antes
          -- del buzón), para comprarlas sin volver luego a la AH a por cada una (Discord:
          -- "todo lo de la AH junto"). Su nota de "aprende X primero" ya está en su paso
          local isRecipe = {}
          for _, r in ipairs(recipes) do isRecipe[r] = true end
          for k = #lines, 1, -1 do if isRecipe[lines[k]] then table.remove(lines, k) end end
          local at
          for k, l in ipairs(lines) do
            if l == line or l.buyRow == "ah" then at = k end
          end
          for k, r in ipairs(recipes) do table.insert(lines, (at or 0) + k, r) end
        end
        break
      end
    end
  end
  -- Rango que ya puedes entrenar y aún no es el paso actual: solo una nota en su fila
  -- ("ya puedes · antes de 75"). El paso actual no lo repite: la fila ya va justo
  -- detrás, donde toca hacerlo (arriba), y a tu tope pasa a ser el paso actual
  if rankDue and not rankDue.promoted then
    rankDue.line.sub = (rankDue.line.sub or "") .. " · " .. ORANGE
      .. string.format(L["ya puedes · antes de %d"], rankDue.before) .. "|r"
  end
  -- Lo que sobra de un paso acabado, si fabricarlo deja más que venderlo (ver
  -- Planner.Leftover: la misma cuenta que la ruta). Va justo antes del paso actual y es
  -- el paso actual: cuanto antes, más probabilidad de punto. "Saltar" lo quita esta sesión
  if locked and page.detected and (page.from or 0) < settings.lock.to then
    ES.routeSkips[page.profKey] = ES.routeSkips[page.profKey] or {}
    local skips = ES.routeSkips[page.profKey]
    local _, cap = ES:GetProfessionSkill(page.data.skillLine)
    local lo = ES.Planner.Leftover(plan, page.from or plan.from, cap)
    if lo and skips.leftover ~= lo.id then
      local r = lo.recipe
      local name, texture = ItemLabel(r.out and r.out[1] or 0, r.name)
      local p1 = math.floor(lo.points * 10 + 0.5) / 10
      local pts = ES.Market.Dec and ES.Market.Dec(p1) or string.format("%.1f", p1)
      local title = string.format(L["Gasta lo que sobra: %d× %s"], lo.crafts, name)
      local line = {
        level = tostring(page.from or plan.from), icon = texture or 134400, title = title,
        bannerTitle = string.format("%s %d× %s", L["Fabrica"], lo.crafts, name),
        sub = string.format(L["~%s puntos · deja %s más que vender los materiales"], pts, ES.Money(lo.gain)),
        bannerSub = string.format(L["lo que sobra · ~%s puntos"], pts),
        value = Signed(-lo.gain), leftover = lo, stepRecipe = lo.id, craftCount = lo.crafts,
        onClick = function()
          if ES:IsRecipeKnown(lo.id) then ES:CraftRecipe(lo.id, lo.crafts) else ES:OpenRecipe(lo.id) end
        end,
        markHave = function() skips.leftover = lo.id end,
        tooltip = function(row)
          GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
          GameTooltip:AddLine(title, 1, 0.82, 0)
          GameTooltip:AddLine(L["Te han sobrado materiales de un paso ya hecho y esta receta aún da puntos. Gastarlos deja más que venderlos: los puntos que te da ya no los subes con la receta siguiente."], 1, 1, 1, true)
          GameTooltip:AddLine(" ")
          GameTooltip:AddDoubleLine(L["Puntos que te ahorras"], ES.Money(lo.saving), 1, 1, 1, 1, 1, 1)
          GameTooltip:AddDoubleLine(L["Lo que vale lo fabricado"], ES.Money(lo.sale), 1, 1, 1, 1, 1, 1)
          GameTooltip:AddDoubleLine(L["Materiales (venderlos o reponerlos)"], "-" .. ES.Money(lo.matValue), 1, 1, 1, 1, 1, 1)
          GameTooltip:AddDoubleLine(L["Ganas"], ES.Money(lo.gain), 1, 0.82, 0, 0.4, 1, 0.4)
          GameTooltip:AddLine(" ")
          GameTooltip:AddLine(L["Solo cuenta lo que no pide el resto de la ruta. Si prefieres venderlo, Saltar lo quita."], 0.8, 0.8, 0.8, true)
          GameTooltip:AddLine(string.format(L["Clic: abrir la receta y fabricar %d."], lo.crafts), 0.5, 0.8, 1, true)
          GameTooltip:Show()
        end,
      }
      local at
      for i, l in ipairs(lines) do if l.current then at = i break end end
      if not at then
        for i, l in ipairs(lines) do if l.level and not l.done then at = i break end end
      end
      if at then lines[at].current = nil end
      line.current = true
      table.insert(lines, at or (#lines + 1), line)
    end
  end
  -- Con la ruta empezada siempre hay un paso actual (al saltar una receta, su paso de
  -- fabricar no lo era porque faltaba aprenderla): el primero sin hacer
  if locked and (page.from or 0) < settings.lock.to then
    local any = false
    for _, l in ipairs(lines) do if l.current then any = true break end end
    if not any then
      for _, l in ipairs(lines) do
        if l.level and not l.done then l.current = true break end
      end
    end
  end
  -- opts.lean (asistente y avisos de tramo): sin las filas del final (aviso de dónde se
  -- para, "Con lo que llevas", recetas quitadas, total), que no usan. "Con lo que llevas"
  -- repasa todas las recetas con tus bolsas, y esto se hace con cada cambio de las bolsas
  if opts and opts.lean then return lines end
  if plan.stoppedAt then
    lines[#lines + 1] = { title = ORANGE .. L["El plan se queda en "] .. plan.stoppedAt .. "|r", sub = StopReason(plan) }
  end
  -- Recetas quitadas con la ✕: clic para volver a ponerlas todas
  local excluded = {}
  for id in pairs(settings.excluded or {}) do
    local r = page.data.recipes[id]
    if r then excluded[#excluded + 1] = r.name end
  end
  -- Y los materiales que no quieres fabricar (se compran hechos)
  for itemID in pairs(settings.noCraft or {}) do
    excluded[#excluded + 1] = string.format(L["Fabricar %s (se compra hecho)"], (ItemLabel(itemID, L["Objeto "] .. itemID)))
  end
  -- Y los avisos "Con lo que llevas" descartados con su ✕ (no cambian la ruta)
  local onlyNotes = #excluded == 0
  for id in pairs(settings.dismissedNotes or {}) do
    local r = page.data.recipes[id]
    if r then excluded[#excluded + 1] = string.format(L["Aviso: %s con lo que llevas"], r.name) end
  end
  -- Con "usar lo de las bolsas": receta que podrías hacer con lo que llevas y la ruta no
  -- usa (las de avisos descartados, no: se mira la siguiente)
  if settings.useBags then
    local skip = {}
    for id in pairs(settings.excluded or {}) do skip[id] = true end
    for id in pairs(settings.dismissedNotes or {}) do skip[id] = true end
    local alt = ES.Planner.BagsAlternative(page.data, plan, ES:GetOwnedReagents(page.data), page.from, skip)
    local quote = alt and BagsLine(alt, locked)
    if quote then
      -- ✕: no volver a avisar de esta receta (solo informa: la ruta no cambia)
      quote.onSkip = function()
        settings.dismissedNotes = settings.dismissedNotes or {}
        settings.dismissedNotes[alt.id] = true
        ES:RenderPlan(page)
      end
      quote.skipTip = L["No volver a avisar de esta receta. Es solo un aviso: la ruta no cambia. Se recupera con la fila de recetas quitadas."]
      lines[#lines + 1] = quote
    end
  end
  if #excluded > 0 then
    table.sort(excluded)
    lines[#lines + 1] = {
      icon = "Interface\\Buttons\\UI-RefreshButton", iconSize = 16, -- textura de 16 px: más grande se pixela
      -- Solo avisos descartados: la ruta es la misma, el título no dice que se quitó nada
      title = string.format(onlyNotes and L["Avisos ocultos: %d"] or L["Recetas quitadas de la ruta: %d"], #excluded),
      sub = L["Clic para volver a tenerlas en cuenta"],
      onClick = function()
        settings.excluded, settings.noCraft, settings.dismissedNotes = nil, nil, nil
        -- Solo avisos descartados: la ruta no cambia, basta con repintar
        if onlyNotes then ES:RenderPlan(page) return end
        ES:StopRoute(page.profKey)
        ES:CalculatePlan(page)
      end,
      tooltip = function(row)
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Quitadas de la ruta"])
        for _, name in ipairs(excluded) do GameTooltip:AddLine(name, 0.8, 0.8, 0.8) end
        GameTooltip:AddLine(L["Clic para volver a tenerlas en cuenta"], 0.5, 0.8, 1)
        GameTooltip:Show()
      end,
    }
  end
  lines[#lines + 1] = { total = true, title = L["Total"], value = Signed(plan.net),
    sub = string.format(L["Subir de %d a %d"], plan.from, plan.reached)
      .. (routeSecs > 0 and (" · " .. string.format(L["%s fabricando"], Duration(routeSecs))) or "") }
  return lines
end

-- La vista Ruta de la ruta empezada de una profesión, sin su ventana abierta (el
-- asistente, Assistant.lua): las MISMAS filas, con tu nivel de ahora. Así el asistente
-- nunca decide nada por su cuenta. Devuelve las filas y la ruta, o nil sin ruta empezada.
-- (La ✕ y "Recetas quitadas" recalculan en la ventana: el asistente no las usa)
-- opts.buy: añade las filas de compra (AddBuyLines), que solo tiene el asistente: la
-- ventana tiene Materiales y la Lista de compra; el asistente, un solo paso a la vista
function ES:RouteLines(profKey, opts)
  local data = ES.Data[profKey]
  local plan = data and self:RouteLock(profKey) and self:LockedPlan(profKey)
  if not (plan and #plan.steps > 0) then return nil end
  local rank, maxRank = self:GetProfessionSkill(data.skillLine)
  local prof
  for _, p in ipairs(ES.PROFESSIONS or {}) do if p.key == profKey then prof = p end end
  local view = { profKey = profKey, data = data, profName = self:ProfLabel(profKey),
    profIcon = prof and prof.icon or ES.ICON, from = rank or 1,
    detected = rank and { rank = rank, cap = maxRank } or nil }
  return RouteLines(plan, view, opts), plan
end

-- Clic de una fila de la vista Profit: con el vendedor abierto vende lo que toca
-- vender; con la AH abierta anuncia lo que toca anunciar; si no, marca el
-- subastador o el vendedor más cercano. Devuelve onClick, go, etiqueta del botón.
local ACTION = "|cff80c0ff"
local function SaleAction(d, advice, page)
  local Ledger = ES.Ledger
  if not Ledger then return nil end
  local have = Ledger.BagCount(d.itemID)
  local toVendor, toAH = math.min(have, advice.vendor), math.min(have, advice.ah)
  local function Done() ES:RenderPlan(page) end
  if Ledger:MerchantOpen() and toVendor > 0 then
    return function() Ledger:SellToVendor(d.itemID, toVendor) C_Timer.After(0.5, Done) end, nil,
      string.format(L["Vender %d al vendedor"], toVendor)
  elseif ES:IsAuctionHouseOpen() and toAH > 0 then
    -- Las que diga la ruta, como mucho las que llevas; a platas enteras (la AH de Forever)
    local price = Ledger.PostPrice(advice.price)
    -- (con confirmación, si está activada: AuctionSellUI.lua)
    return function() ES.AuctionSell.Post(d.itemID, toAH, price, nil, function() C_Timer.After(0.5, Done) end) end, nil,
      string.format(L["Anunciar %d en la AH a %s"], toAH, ES.Money(price))
  elseif ES:IsAuctionHouseOpen() and advice.ah > 0 then
    -- AH abierta pero no llevas ninguno encima (en el banco o aún sin fabricar): el
    -- título ya dice "0 en bolsas", así que sin texto de clic (si pulsas, lo avisa)
    return function() ES:Print(string.format(L["No llevas %s en las bolsas."], ES:DataItemName(d.itemID) or d.itemID)) end, nil, nil
  elseif advice.ah > 0 then
    return nil, WP.Target("auction"), nil
  elseif advice.vendor > 0 then
    return nil, WP.Target("sell"), nil
  end
end

-- Lo que llevas en las bolsas: qué hacer con ello, EXACTAMENTE como la pestaña
-- Inventario y el panel de vender de la AH (Inventory:List, con el último escaneo).
-- Antes salía de los precios de cuando empezaste la ruta (fijados con ella) y con
-- otra regla: la ruta decía "al vendedor" y la AH "ponlo en la AH" (Rage Potion).
-- Lo que aún no llevas sigue con el consejo de la ruta
local function InventoryByItem()
  local inBags = {}
  if ES.Inventory and ES.Inventory.List then
    local ok, list = pcall(ES.Inventory.List, ES.Inventory)
    for _, e in ipairs(ok and list or {}) do inBags[e.itemID] = e end
  end
  return inBags
end

-- Consejo de venta de un destino (de las bolsas si lo llevas) y lo que saca seguirlo:
-- lo de la AH a su precio (neto) y el resto al vendedor
local function DestinationAdvice(d, inBags)
  local advice = ES.Planner.SaleAdvice(d)
  local inv = inBags[d.itemID]
  if inv then
    -- (lo mismo que Inventario: sin precio de AH fiable, al vendedor)
    advice = { ah = inv.ahN, vendor = inv.vendorN, unsold = 0, price = inv.listPrice,
      verdict = inv.verdict, later = inv.ahLater, fromBags = true }
    advice.kind = advice.ah > 0 and "ah" or advice.vendor > 0 and "vendor" or "none"
  end
  -- Lo que saca: lo seguro (todas las que vendes, al vendedor: d.income) más lo que la
  -- AH da de más en las que aconseja anunciar, ya o después. Antes sumaba solo lo que
  -- se anuncia ya y lo que llevas en las bolsas, y las demás (aún sin fabricar, "+N
  -- después", sin precio fiable) contaban 0: "con AH" salía PEOR que todo al vendedor
  local vendorUnit = d.sale.vendor or 0
  local ahUnit = (inv and inv.ahUnit) or d.sale.ahNet
  local onAH = math.min(d.sell, advice.ah + (advice.later or 0))
  local gain = ahUnit and onAH * math.max(0, ahUnit - vendorUnit) or 0
  return advice, inv, d.income + gain
end

-- Totales de ventas de la vista Profit: al vendedor (lo seguro, lo que cuenta la ruta)
-- y siguiendo el consejo de cada fila (AH y vendedor). anyAH: algo va a la AH
local function SalesTotals(plan, inBags)
  inBags = inBags or InventoryByItem()
  local income, advised, anyAH = 0, 0, false
  for _, d in ipairs(plan.destinations or {}) do
    local advice, _, value = DestinationAdvice(d, inBags)
    income = income + d.income
    advised = advised + value
    if advice.ah > 0 then anyAH = true end
  end
  return income, advised, anyAH
end
ES.ProfitSalesTotals = SalesTotals -- (para pruebas)

-- Líneas de la vista Profit: qué hacer con todo lo que fabricas
local function ProfitLines(plan, page, inBags)
  local lines = {}
  local dests = {}
  for _, d in ipairs(plan.destinations) do dests[#dests + 1] = d end
  table.sort(dests, function(a, b) return a.income + (a.ahExtra or 0) > b.income + (b.ahExtra or 0) end)
  local total, extra = 0, 0
  local advised, anyAH = 0, false -- (total siguiendo el consejo de cada fila)
  inBags = inBags or InventoryByItem() -- (el de RenderPlan si ya lo tiene: Inventory:List una vez por pintado)
  for _, d in ipairs(dests) do
    local name, texture = ItemLabel(d.itemID, L["Objeto "] .. d.itemID)
    local parts = {} -- cuántas fabricas: en la columna de la izquierda
    if d.keep > 0 then parts[#parts + 1] = GREEN .. L["guarda "] .. d.keep .. L[" para pasos siguientes|r"] end
    local signals = d.sale.ahNet and d.sell > 0 and ES.Market:Signals(d.itemID)
    local advice, inv, advisedValue = DestinationAdvice(d, inBags)
    d.advice = advice
    -- Corto, como la pestaña Inventario ("AH: 5 a 1s (vigilar) · vendedor: 33 a 2c"): la
    -- frase larga se cortaba. Con la AH abierta, lo de la AH ya lo dice "Clic: anunciar
    -- 5 en la AH a 1s" (delante): no se repite
    local onClick, go, action = SaleAction(d, advice, page)
    local postingNow = action and ES:IsAuctionHouseOpen()
    if advice.ah > 0 and not postingNow then
      parts[#parts + 1] = string.format(L["%sAH: %d a %s|r (%s)"], GOLD, advice.ah,
        ES.Money(ES.Ledger and ES.Ledger.PostPrice(advice.price) or advice.price), -- platas enteras, como se anuncia
        ES.Market.LABELS[advice.verdict] or "")
    end
    -- (el resto, para anunciarlo cuando se vendan esas; ver Inventory:List)
    if (advice.later or 0) > 0 then parts[#parts + 1] = GREY .. string.format(L["+%d después"], advice.later) .. "|r" end
    if advice.vendor > 0 then
      parts[#parts + 1] = string.format(L["vendedor: %d a %s"], advice.vendor,
        ES.Money(inv and inv.vendorUnit or d.sale.vendor or 0))
    end
    if advice.unsold > 0 then
      parts[#parts + 1] = GREY .. advice.unsold .. L[" no los compra el vendedor|r"]
    end
    if signals then extra = extra + d.ahExtra end
    total = total + d.income
    advised = advised + advisedValue -- (siguiendo el consejo de la fila)
    if advice.ah > 0 then anyAH = true end
    if action then table.insert(parts, 1, ACTION .. L["Clic: "] .. action .. "|r") end -- vendedor o AH abiertos
    local tip = DestinationTooltip(d, name, signals)
    -- Cuántos llevas ahora en las bolsas (lo que puedes vender o anunciar ya)
    local have = ES.Ledger and ES.Ledger.BagCount(d.itemID) or 0
    local bags = (have > 0 and "|cffffffff" or GREY) .. string.format(L["%d en bolsas"], have) .. "|r"
    lines[#lines + 1] = {
      level = "×" .. d.produced,
      icon = texture or 134400, title = name .. GREY .. " · |r" .. bags,
      sub = table.concat(parts, " · "),
      value = d.income > 0 and Signed(-d.income) or (GREY .. "—|r"), item = d.itemID,
      onClick = onClick, go = go,
      tooltip = function(row)
        tip(row)
        if action then
          GameTooltip:AddLine(" ")
          GameTooltip:AddLine(L["Clic: "] .. action .. ".", 0.5, 0.8, 1)
        elseif go then
          WP.AddToTooltip(advice.ah > 0 and L["Subastador más cercano"] or L["Vendedor más cercano"], go)
        end
        GameTooltip:Show()
      end,
    }
  end
  if #lines == 0 then return lines end
  lines[#lines + 1] = {
    total = true, title = L["Recuperas vendiendo al vendedor"],
    sub = extra > 0 and string.format(L["Vendiendo en la AH podrías sacar hasta %s más (sin garantía de venta)"], ES.Money(extra)) or L["Lo que no se guarda para pasos siguientes"],
    value = Signed(-total),
  }
  -- Y otro total: siguiendo el consejo de cada fila (unas en la AH, el resto al
  -- vendedor). El de arriba es lo seguro; este, si lo de la AH se vende
  if anyAH then
    lines[#lines + 1] = {
      total = true, title = L["Siguiendo el consejo (AH y vendedor)"],
      sub = L["Lo del vendedor es seguro; lo de la AH, si se vende"],
      value = Signed(-advised), advisedTotal = advised, -- (para pruebas)
    }
  end
  return lines
end

-- Tooltip de la fila del modo de compra (por tramos o ruta entera) de la vista Materiales
local function ModeTooltip(row)
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:AddLine(L["Qué va a la Lista de compra"])
  GameTooltip:AddLine(L["Por tramos: solo lo del tramo en el que estás, con un margen. Al acabarlo, sale el siguiente."], 1, 1, 1, true)
  GameTooltip:AddLine(L["Ruta entera: todo lo que queda de ruta, de una vez."], 1, 1, 1, true)
  GameTooltip:AddLine(L["Pulsa la fila para cambiar. La lista se llena sola: no hay que añadir nada."], 0.5, 0.8, 1, true)
  GameTooltip:Show()
end

-- Líneas de la vista Materiales
local function ShopLines(plan, page)
  local lines = {}
  local total = 0
  local function Section(title, items, build)
    if #items == 0 then return end
    lines[#lines + 1] = { section = title }
    for _, it in ipairs(items) do lines[#lines + 1] = build(it) end
  end
  local ah, vendor = {}, {}
  -- Lo que la ruta gasta de cada material desde tu nivel actual (compras + lo que
  -- usa de tus bolsas) frente a lo que llevas: cuántos tienes y cuántos faltan. Se
  -- actualiza al comprar, sacar del correo o fabricar (BAG_UPDATE_DELAYED, HomeUI.lua)
  for _, it in ipairs(plan.shopping) do
    -- (en los dos sitios, una sola fila: donde va la mayor parte, como las filas de compra)
    if ES.Planner.ShoppingSource(plan, it.itemID) == it then
      if it.source == "ah" then ah[#ah + 1] = it else vendor[#vendor + 1] = it end
    end
    total = total + it.total
  end
  -- Cuánto hace falta: la misma regla que la Lista de compra y la ventana del
  -- vendedor (Planner.RouteNeed: por tramos solo con la ruta empezada)
  -- Lo que tienes: las bolsas (ni el banco ni el correo; ver ES:HaveForShopping). Lo
  -- mismo que las filas de
  -- compra de la vista Ruta (RouteBuy)
  -- (sin empezar la ruta, preview: lo que pedirá al empezarla con el modo elegido)
  local buy = RouteBuy(plan, page.profKey, page.from, { preview = true })
  local need, phase, Have = buy.need, buy.phase, buy.Have
  local function Progress(itemID)
    local have = Have(itemID)
    local n = math.ceil((need[itemID] or 0) - 0.001)
    if n <= 0 then return GREEN .. L["Ya no hace falta"] .. "|r" end
    if have >= n then return GREEN .. string.format(L["Tienes %d/%d"], have, n) .. "|r" end
    return string.format(L["Tienes %d/%d · faltan %s%d|r"], have, n, ORANGE, n - have)
  end
  local function Buy(it)
    local name, texture = ItemLabel(it.itemID, L["Objeto "] .. it.itemID)
    local sub = it.source == "ah"
      and string.format("AH · %s/u%s", ES.Money(it.unit), it.supply and string.format(L[" · hay %d a la venta"], it.supply) or "")
      or string.format(L["Vendedor · %s/u"], ES.Money(it.unit))
    sub = Progress(it.itemID) .. " · " .. sub
    -- Clic: con la AH abierta, la busca; con el vendedor abierto, compra lo que falta
    -- (si lo vende); si no, marca el subastador o el vendedor más cercano
    local action, onClick
    local vendorEntry
    if it.source == "vendor" and ES.Ledger and ES.Ledger:MerchantOpen() and ES.VendorShop then
      for _, e in ipairs(ES.VendorShop:List()) do if e.itemID == it.itemID then vendorEntry = e end end
    end
    if it.source == "ah" and ES:IsAuctionHouseOpen() then
      -- Abre la compra con lo que falta ya puesto (solo queda "Comprar ahora" de Blizzard)
      local missing = math.ceil((need[it.itemID] or it.quantity) - 0.001) - Have(it.itemID)
      if missing > 0 then
        action = string.format(L["abrir la compra de %d en la AH"], missing)
        onClick = function() ES:OpenAuctionBuy(it.itemID, missing, it.unit) end
      else
        action, onClick = L["buscarlo en la AH"], function() ES:SearchAuction(it.itemID) end
      end
    elseif vendorEntry then
      action = string.format(L["comprar %d a este vendedor"], vendorEntry.qty)
      onClick = function() ES.VendorShop:Buy(vendorEntry) end
    end
    if action then sub = ACTION .. L["Clic: "] .. action .. "|r · " .. sub end
    local go = not onClick and WP.Target(it.source == "ah" and "auction" or "vendor", it.itemID) or nil
    local tip = ShopTooltip(it, plan)
    return { level = "×" .. it.quantity, icon = texture or 134400, title = name, sub = sub, value = Signed(it.total),
      item = it.itemID, onClick = onClick, go = go,
      tooltip = function(row)
        tip(row)
        if action then
          GameTooltip:AddLine(" ")
          GameTooltip:AddLine(L["Clic: "] .. action .. ".", 0.5, 0.8, 1)
        else
          WP.AddToTooltip(it.source == "ah" and L["Subastador más cercano"] or L["Vendedor más cercano"], go)
        end
        GameTooltip:Show()
      end }
  end
  -- Ruta empezada: las secciones salen de lo que llevas AHORA (lo que gastas o
  -- compras mueve cada material de "comprar" a "ya lo tienes" y al revés), no de lo
  -- que llevabas al empezarla; los totales de la ruta siguen congelados
  -- Comprar, al vendedor y "Ya lo tienes", con lo que falta (RouteBuy) y su total
  local function NeedSections()
    Section(L["Comprar en la Casa de Subastas"], buy.ah, Buy)
    Section(L["Comprar al vendedor"], buy.vendor, Buy)
    Section(L["Ya lo tienes"], buy.have, function(it)
      local name, texture = ItemLabel(it.itemID, L["Objeto "] .. it.itemID)
      return { level = "×" .. it.quantity, icon = texture or 134400, title = name, sub = Progress(it.itemID),
        item = it.itemID, tooltip = SimpleTooltip(it.itemID, phase and L["Ya tienes lo que te hace falta para este tramo."]
          or L["Ya tienes lo que te hace falta para lo que queda de ruta."]) }
    end)
    lines[#lines + 1] = { total = true, title = L["Te falta por comprar"],
      sub = phase and L["Lo que te falta para este tramo, con lo que llevas ahora"]
        or L["Lo que te falta para lo que queda de ruta, con lo que llevas ahora"], value = Signed(buy.left) }
  end
  -- Título de la fila del modo con el tramo: "… · Tramo 120-125 (Bright Yellow Shirt)"
  local function PhaseTitle(prefix)
    local names = {}
    for _, st in ipairs(phase.steps) do names[#names + 1] = st.recipe.name end
    return string.format(prefix, phase.from, phase.batchTo or phase.to, table.concat(names, ", "))
      .. (phase.batchTo and L[" · por tandas (en verde)"] or "")
  end
  if ES:RouteLock(page.profKey) then
    -- Por tramos (por defecto): solo lo del tramo en el que estás, con su margen
    -- (ya en `need`, de Planner.RouteNeed); la Lista de compra lo enseña sola
    local byPhase = ES.Shopping.ByPhase(page.profKey)
    NeedSections()
    -- Arriba, una fila: qué hay en la Lista de compra (el tramo o la ruta entera) y,
    -- al pulsarla, se cambia a lo otro. Eso pasa a la lista (ES.Shopping.PhaseList: no
    -- se guarda, se calcula) y se avisa: chat, monedas y la pestaña brilla
    local function Switch()
      -- (por tramos -> ruta entera = false; ruta entera -> por tramos = nil, el de por defecto)
      if byPhase then ES.db.prof[page.profKey].byPhase = false else ES.db.prof[page.profKey].byPhase = nil end
      ES:RenderPlan(page)
      if ES.RenderShopping then ES:RenderShopping() end
      if ES.Assistant and ES.Assistant.ModeChanged then ES.Assistant.ModeChanged() end -- (rehacer las compras no es acabarlas)
      if ES.Assistant and ES.Assistant.Refresh then ES.Assistant.Refresh() end -- (sus pasos de compra siguen este modo)
      local list = ES.Shopping.PhaseList(page.profKey)
      if list then
        ES:Print(string.format(L["Añadido a la lista de compra: %s."], list.title))
        ES:FlashTab("shopping", true)
      end
    end
    -- Título: lo que hay ahora en la lista. Debajo, primero y en azul (como las demás
    -- acciones del addon), lo que hace pulsar
    local title, sub
    local ACT = "|cff80c0ff"
    -- La quitaste de la Lista de compra (su ✕): la fila la vuelve a poner
    local hidden = ES.Shopping.RouteListHidden(page.profKey)
    if hidden then
      Switch = function()
        ES.Shopping.SetRouteListHidden(page.profKey, false)
        ES:RenderPlan(page)
        if ES.RenderShopping then ES:RenderShopping() end
        local list = ES.Shopping.PhaseList(page.profKey)
        if list then
          ES:Print(string.format(L["Añadido a la lista de compra: %s."], list.title))
          ES:FlashTab("shopping", true)
        end
      end
      title = L["Lista de compra · quitada"]
      sub = ACT .. L["Pulsa para volver a ponerla"] .. "|r · " .. L["la quitaste con la X de la Lista de compra"]
    elseif phase then
      title = PhaseTitle(L["Lista de compra · Tramo %d-%d (%s)"])
      sub = ACT .. L["Pulsa para cambiar a la ruta entera"] .. "|r · " .. L["ahora: este tramo, con margen por si los puntos tardan"]
    else
      title = L["Lista de compra · Ruta entera"]
      sub = ACT .. L["Pulsa para cambiar a solo este tramo"] .. "|r · " .. L["ahora: todo lo que queda de ruta"]
    end
    table.insert(lines, 1, { total = true, icon = "Interface\\Icons\\INV_Misc_Note_01", title = title, sub = sub,
      onClick = Switch, phaseLine = true, tooltip = ModeTooltip })
    return lines
  end

  -- Sin empezar la ruta: la fila del modo, igual que con la ruta empezada. Se elige
  -- aquí, antes de empezar, y "Empezar ruta" lo respeta; la lista de debajo es la que
  -- saldrá al empezarla (por tramos, el primer tramo), así se ve qué cambia al pulsar.
  -- CurseForge: elegías la ruta viendo 326 Silk Cloth y al empezarla la lista pasaba
  -- sola a "por tramos" (32): parecía que te la cambiaban
  local modeLine
  if #plan.shopping > 0 then
    local ACT = "|cff80c0ff"
    local byPhase = ES.Shopping.ByPhase(page.profKey)
    local title = not byPhase and L["Al empezar compras: la ruta entera"]
      or phase and PhaseTitle(L["Al empezar compras: por tramos · Tramo %d-%d (%s)"])
      or L["Al empezar compras: por tramos"]
    local sub = ACT .. (byPhase and L["Pulsa para comprar la ruta entera de una vez"] or L["Pulsa para comprar solo el tramo en el que estés"])
      .. "|r · " .. (phase and L["abajo, lo del primer tramo"] or L["abajo, lo que gasta la ruta entera"])
    modeLine = { total = true, icon = "Interface\\Icons\\INV_Misc_Note_01", title = title, sub = sub,
      phaseLine = true, tooltip = ModeTooltip,
      onClick = function()
        -- (por tramos -> ruta entera = false; ruta entera -> por tramos = nil, el de por defecto)
        if byPhase then ES.db.prof[page.profKey].byPhase = false else ES.db.prof[page.profKey].byPhase = nil end
        ES:RenderPlan(page)
      end }
  end
  if phase then
    -- Por tramos: lo del primer tramo, como saldrá al empezar la ruta
    NeedSections()
    if modeLine then table.insert(lines, 1, modeLine) end
    return lines
  end
  if modeLine then table.insert(lines, 1, modeLine) end
  Section(L["Comprar en la Casa de Subastas"], ah, Buy)
  Section(L["Comprar al vendedor"], vendor, Buy)
  -- Lo que también se compra ya dice arriba cuántos tienes y cuántos faltan: aquí
  -- solo que esa parte sale de tus bolsas (sin repetir el recuento)
  local alsoBought = {}
  for _, it in ipairs(plan.shopping) do alsoBought[it.itemID] = true end
  Section(L["Usar de tus bolsas"], plan.owned, function(it)
    local name, texture = ItemLabel(it.itemID, L["Objeto "] .. it.itemID)
    local sub = alsoBought[it.itemID] and L["Lo que tienes se usa primero; el resto se compra (arriba)"]
      or (Progress(it.itemID) .. " · " .. L["Ya lo tienes: se usa antes de comprar"])
    return { level = "×" .. it.quantity, icon = texture or 134400, title = name, sub = sub,
      item = it.itemID, tooltip = SimpleTooltip(it.itemID, L["Ya lo tienes: el plan lo usa antes de comprar nada."]) }
  end)
  if #plan.shopping > 0 then
    lines[#lines + 1] = { total = true, title = L["Total de la compra"], sub = L["Materiales y herramientas a comprar"], value = Signed(total) }
  end
  return lines
end

---------------------------------------------------------------------------
-- Ruta empezada: ¿hay una mejor desde tu nivel?
---------------------------------------------------------------------------
-- Una ruta empezada no cambia sola (lo que compras no la mueve). Al abrir su página
-- se busca en segundo plano (Jobs: poco tiempo por fotograma, nunca en combate) la
-- mejor desde tu nivel con lo que llevas, y se compara con seguir la tuya desde ahí.
-- Si compensa (BETTER_MIN, o BETTER_PCT de lo que te queda), una fila arriba de la
-- ruta lo dice con los pasos que cambian: clic para cambiar, ✕ para seguir con la tuya
local BETTER_MIN, BETTER_PCT, BETTER_PCT_MIN = 5000, 0.10, 1000
ES.betterCache = ES.betterCache or {}

local function ChoiceSig(plan)
  local keys = {}
  for _, st in ipairs(plan.steps) do keys[#keys + 1] = st.id .. "@" .. st.from end
  return table.concat(keys, ",")
end

-- { plan, saved, crafts, changes = { textos } } o nil si no compensa
local function CompareRoutes(lock, best, mine)
  if not best or #best.steps == 0 then return nil end
  local saved = mine.net - best.net
  local crafts = ES.Planner.TotalCrafts(mine) - ES.Planner.TotalCrafts(best)
  local further = best.reached > mine.reached
  local worth = further or saved >= BETTER_MIN
    or (saved >= BETTER_PCT_MIN and saved >= BETTER_PCT * math.abs(mine.net))
  if not worth then return nil end
  local sig = ChoiceSig(best)
  if lock.keepMine == sig then return nil end -- ya dijiste que sigues con la tuya
  local changes = {}
  for _, st in ipairs(best.steps) do
    local old = lock.choice and lock.choice[st.from]
    if old ~= st.id then
      changes[#changes + 1] = { st = st, old = old }
    end
  end
  return { plan = best, saved = saved, crafts = crafts, further = further, changes = changes, sig = sig }
end

function ES:CheckBetterRoute(page)
  local lock = self:RouteLock(page.profKey)
  if not lock or lock.completed then return end
  local from = page.from or lock.from
  if from >= lock.to then return end
  local cap = page.detected and page.detected.cap or nil
  local key = table.concat({ "better", self:PlanKey(page.profKey, from, lock.to, cap), tostring(lock.started) }, ":")
  local cached = self.betterCache[page.profKey]
  if cached and cached.key == key then return end
  local profKey = page.profKey
  self.Jobs.Run("better:" .. profKey, key, function()
    local data = ES.Data[profKey]
    local best = self.Planner:Plan(data, self:PlanOptions(profKey, from, lock.to, cap))
    -- La tuya desde tu nivel, con lo que llevas ahora (misma vara)
    local opts = self:PlanOptions(profKey, from, lock.to, cap)
    opts.forced, opts.via = lock.choice, lock.via
    local mine = self.Planner:Plan(data, opts)
    return CompareRoutes(lock, best, mine)
  end, function(result)
    self.betterCache[profKey] = { key = key, result = result }
    if page:IsVisible() and self:RouteLock(profKey) == lock then self:RenderPlan(page) end
  end, "better", true)
end

---------------------------------------------------------------------------
-- Precios nuevos con la ruta empezada: lo que te queda de ruta (las mismas recetas,
-- desde tu nivel y con lo que llevas) con los precios del principio y con los del
-- último escaneo. Si cambia mucho, se dice en la ruta y una vez en el chat, para
-- que pulses Actualizar precios. La ruta no cambia sola
---------------------------------------------------------------------------
ES.driftCache = ES.driftCache or {}
ES.DRIFT_MIN = 5000   -- 50s
ES.DRIFT_SHARE = 0.2  -- y un 20 % de lo que costaba

-- ¿Cambia lo bastante para avisar? d = { old, new } (coste de lo que te queda)
function ES.DriftMatters(d)
  if not d then return false end
  return math.abs(d.new - d.old) >= math.max(ES.DRIFT_MIN, ES.DRIFT_SHARE * math.abs(d.old))
end

-- Devuelve el resultado si ya está calculado (false: no se puede comparar). Si no,
-- lo calcula repartido entre fotogramas y llama a onDone(resultado), uno por owner
function ES:CheckRouteDrift(profKey, onDone, owner)
  local lock = self:RouteLock(profKey)
  local scan = self.db.scans and self.db.scans[self:RealmKey()]
  if not lock or lock.completed or not scan or scan.time == lock.scanTime then return nil end
  local rank, cap = self:GetProfessionSkill(ES.Data[profKey].skillLine)
  local from = math.max(rank or lock.from, lock.from)
  if from >= lock.to then return nil end
  local key = table.concat({ "drift", profKey, tostring(lock.started), tostring(lock.scanTime), tostring(scan.time), from,
    tostring(cap), tostring(self.Planner.SKILL_BONUS or 0) }, ":")
  local cached = self.driftCache[profKey]
  if cached and cached.key == key then return cached.result end
  self.Jobs.Run("drift:" .. profKey, key, function()
    local data = ES.Data[profKey]
    local function Mine(old)
      local opts = self:PlanOptions(profKey, from, lock.to, cap)
      opts.forced, opts.via = lock.choice, lock.via
      if old then opts.prices, opts.pricesTime = lock.prices, lock.scanTime end
      return self.Planner:Plan(data, opts)
    end
    local before, now = Mine(true), Mine(false)
    -- Solo si las dos llegan igual de lejos: si no, no es el mismo trabajo
    if #before.steps == 0 or #now.steps == 0 or before.stoppedAt ~= now.stoppedAt then return false end
    return { old = before.net, new = now.net, from = from }
  end, function(result)
    self.driftCache[profKey] = { key = key, result = result }
    if onDone then onDone(result) end
  end, owner or onDone or "drift", true)
  -- (fuera del juego se calcula de golpe: ya está)
  cached = self.driftCache[profKey]
  if cached and cached.key == key then return cached.result end
  return nil
end

-- Al acabar un escaneo: si alguna ruta empezada cuesta ahora bastante más, una
-- línea en el chat (una vez por precios de la ruta: hasta que pulses Actualizar
-- precios no se repite, aunque abras la AH otra vez)
function ES:AnnounceRouteDrift()
  if self.db.noChatAlerts then return end -- (opción: la ruta lo sigue diciendo en su estado)
  for _, p in ipairs(ES.PROFESSIONS) do
    local profKey = p.key
    local lock = self:RouteLock(profKey)
    if lock and not lock.completed and lock.driftWarned ~= lock.scanTime then
      local function Done(d)
        if self:RouteLock(profKey) ~= lock or lock.driftWarned == lock.scanTime then return end
        if not (ES.DriftMatters(d) and d.new > d.old) then return end
        lock.driftWarned = lock.scanTime
        self:Print(string.format(L["Con el último escaneo, lo que te queda de tu ruta de %s cuesta %s más (%s en vez de %s). Ábrela y pulsa Actualizar precios para verla con estos precios."],
          self:ProfLabel(profKey), ES.Money(d.new - d.old), ES.Money(d.new), ES.Money(d.old)))
      end
      local d = self:CheckRouteDrift(profKey, Done, "announce:" .. profKey)
      if d ~= nil then Done(d) end
    end
  end
end

-- Fila del aviso (arriba de la ruta) o nil
local function BetterLine(page)
  local lock = ES:RouteLock(page.profKey)
  local c = lock and not lock.completed and ES.betterCache[page.profKey]
  local b = c and c.result
  if not b or lock.keepMine == b.sig then return nil end
  local recipes = ES.Data[page.profKey].recipes
  local parts = {}
  for i, ch in ipairs(b.changes) do
    if i > 2 then parts[#parts + 1] = "…" break end
    local was = ch.old and recipes[ch.old]
    parts[#parts + 1] = string.format("%d-%d %s", ch.st.from, ch.st.to, ch.st.recipe.name)
      .. (was and string.format(L[" (antes %s)"], was.name) or "")
  end
  local gains = {}
  if b.further then gains[#gains + 1] = L["llega más lejos"] end
  if b.saved >= 1 then gains[#gains + 1] = string.format(L["%s menos"], ES.Money(b.saved)) end
  if b.crafts > 0 then gains[#gains + 1] = string.format(L["%d fabricaciones menos"], b.crafts) end
  return {
    level = tostring(page.from or lock.from),
    icon = "Interface\\Icons\\INV_Misc_Map_01",
    title = "|cff66bbff" .. L["Hay una ruta mejor desde tu nivel"] .. "|r · " .. table.concat(gains, " · "),
    sub = table.concat(parts, " · "),
    onClick = function()
      -- Cambiar: la nueva pasa a ser tu ruta empezada (lo que ya compraste cuenta como tuyo)
      ES:StopRoute(page.profKey)
      page.plan, page.planKey = b.plan, nil
      ES:StartRoute(page)
      ES.betterCache[page.profKey] = nil
      ES:Print(string.format(L["Ruta de %s cambiada: %s."], page.profName or page.profKey, table.concat(gains, ", ")))
      ES:CalculatePlan(page)
    end,
    onSkip = function()
      lock.keepMine = b.sig -- (esta alternativa no vuelve a salir; otra mejor, sí)
      ES:RenderPlan(page)
    end,
    skipTip = L["Seguir con mi ruta: esta alternativa no vuelve a salir."],
    tooltip = function(row)
      GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
      GameTooltip:AddLine(L["Hay una ruta mejor desde tu nivel"])
      GameTooltip:AddLine(L["Con lo que llevas ahora y los precios del último escaneo. Tu ruta empezada no cambia hasta que lo decidas."], 0.8, 0.8, 0.8, true)
      GameTooltip:AddLine(" ")
      for _, ch in ipairs(b.changes) do
        local was = ch.old and recipes[ch.old]
        GameTooltip:AddDoubleLine(string.format("%d-%d %s", ch.st.from, ch.st.to, ch.st.recipe.name), was and was.name or "", 1, 1, 1, 0.6, 0.6, 0.6)
      end
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(L["Clic: cambiar a esta ruta (lo que ya compraste cuenta como tuyo)."], 0.5, 0.8, 1, true)
      GameTooltip:Show()
    end,
  }
end

function ES:RenderPlan(page)
  local plan = page.plan

  -- Calculando la primera ruta: nada que enseñar aún
  local stats = page.stats
  if page.calculating and not plan then
    for _, fs in pairs(stats) do fs:SetText(GREY .. "—|r") end
    page.status:SetText(GREY .. L["Calculando la ruta…"] .. "|r")
    self:UpdateCalcProgress(page)
    page.lines = {}
    page.empty:SetText("")
    ES.UI.RenderLines(page, page.lines)
    return
  end

  -- Franja de resumen
  if plan and #plan.steps > 0 then
    stats.materials:SetText(Signed(plan.reagentCost))
    stats.profit:SetText(Signed(-plan.resale))
    stats.fees:SetText(Signed(plan.fees + plan.toolsCost))
    stats.total:SetText(Signed(plan.net))
    local secs = ES.Planner.RouteSeconds(plan)
    stats.time:SetText(secs > 0 and DurationIcon(secs) or (GREY .. "—|r"))
  else
    for _, fs in pairs(stats) do fs:SetText(GREY .. "—|r") end
  end
  -- Posible total siguiendo el consejo (AH y vendedor), bajo el total seguro
  page.totalAHInfo = nil
  local inBags -- (lo de las bolsas de este pintado: también lo usa la vista Profit)
  if page.totalAH then
    local text = ""
    if plan and #plan.steps > 0 then
      local ok, income, advised, anyAH = pcall(function()
        inBags = InventoryByItem()
        return SalesTotals(plan, inBags)
      end)
      if ok and anyAH and math.abs(advised - income) >= 1 then
        local advisedNet = plan.net - (advised - income)
        page.totalAHInfo = { net = plan.net, advisedNet = advisedNet }
        text = GREY .. L["con AH: "] .. "|r" .. Signed(advisedNet) .. GREY .. " *|r"
      end
    end
    page.totalAH:SetText(text)
  end

  local status
  if not plan and page.planFailed then
    status = ORANGE .. L["No se pudo calcular la ruta (error del addon). Pulsa Informar para enviárnoslo.|r"]
  elseif not plan then
    status = GREEN .. L["Ya estás en el objetivo. Sube el objetivo para ver la ruta.|r"]
  elseif #plan.steps == 0 then
    status = ORANGE .. L["No se puede subir desde "] .. plan.from .. ": " .. StopReason(plan) .. ".|r" .. AttemptHint(page, plan)
  elseif plan.stoppedAt then
    status = ORANGE .. L["Con recetas de instructor el plan llega hasta "] .. plan.stoppedAt .. ": " .. StopReason(plan) .. ".|r" .. AttemptHint(page, plan)
  elseif not plan.scanTime then
    status = ORANGE .. L["Sin escaneo de la AH: solo precios de vendedor. Escanea para un coste real.|r"]
  else
    status = GREY .. string.format(L["Precios de la AH de hace %d min · lo fabricado se cuenta vendido al vendedor"],
      math.floor((time() - plan.scanTime) / 60)) .. "|r"
  end
  -- Ruta con coste simbólico por fabricación: cuánto ahorra frente a la más barata
  if plan and plan.cheapest then
    local saved = plan.cheapest.crafts - self.Planner.TotalCrafts(plan)
    local extra = plan.net - plan.cheapest.net
    status = status .. GREY .. string.format(L[" · %d fabricaciones menos que la ruta más barata%s|r"], saved,
      extra >= 0.5 and (L[", por "] .. ES.Money(extra) .. L[" más"]) or "")
  end
  -- Ruta fijada: lo que compras no la cambia; un escaneo nuevo solo avisa
  local lock = self:RouteLock(page.profKey)
  local newPrices = false
  if lock and plan then
    local scan = self.db.scans and self.db.scans[self:RealmKey()]
    status = GREEN .. (lock.completed
      and string.format(L["¡Ruta completada! (de %d a %d) · pulsa Dejar ruta para empezar otra"], lock.from, lock.to)
      or string.format(L["Ruta en curso (de %d a %d): lo que compras no cambia la ruta ni su coste"], lock.from, lock.to)) .. "|r"
    page.drift = nil
    if scan and scan.time ~= lock.scanTime then
      newPrices = true
      -- Cuánto cambia lo que te queda con esos precios (se calcula aparte y se repinta)
      local d = self:CheckRouteDrift(page.profKey, function() if page:IsVisible() then ES:RenderPlan(page) end end, page)
      if ES.DriftMatters(d) then
        page.drift = d
        status = status .. ORANGE .. string.format(d.new > d.old and L[" · precios nuevos: %s más|r"]
          or L[" · precios nuevos: %s menos|r"], ES.Money(math.abs(d.new - d.old)))
      else
        status = status .. ORANGE .. L[" · hay precios nuevos de la AH|r"]
      end
    end
  elseif plan and #plan.steps > 0 and not page.calculating and self.db.prof[page.profKey].useBags then
    status = status .. GREY .. L[" · pulsa Empezar ruta antes de comprar|r"]
  end
  page.routeButton:SetText(lock and (page.leaveAsked and L["¿Seguro? Pulsa otra vez"] or L["Dejar ruta"]) or L["Empezar ruta"])
  -- Actualizar precios: con la ruta empezada, siempre a la vista (antes solo salía con
  -- un escaneo nuevo y no se sabía que existía); sin escaneo nuevo, desactivado y el
  -- tooltip dice por qué. Sin empezar, no hace falta: la ruta ya usa el último escaneo
  -- (también con la ruta completada: los totales de arriba y Profit siguen con los
  -- precios de cuando la empezaste, y el aviso "hay precios nuevos" no tenía botón)
  local showPrices = lock ~= nil and plan ~= nil
  page.pricesButton:SetText(L["Actualizar precios"])
  page.pricesButton:SetShown(showPrices)
  page.pricesButton:SetEnabled(newPrices)
  page.pricesUpToDate = showPrices and not newPrices
  -- Asistente: junto a Dejar ruta, con la ruta empezada (y solo si el asistente está:
  -- aún no se publica). Actualizar precios va a su izquierda
  local showAssist = lock ~= nil and plan ~= nil and self.Assistant ~= nil and self.Assistant.Enabled()
  page.assistButton:SetShown(showAssist)
  local right = showAssist and page.assistButton or page.routeButton
  page.pricesButton:ClearAllPoints()
  page.pricesButton:SetPoint("RIGHT", right, "LEFT", -6, 0)
  page.status:SetPoint("RIGHT", showPrices and page.pricesButton or right, "LEFT", -10, 0)
  page.routeButton:SetEnabled(lock ~= nil or (plan ~= nil and #plan.steps > 0 and not page.calculating))
  -- Recalculando: se ve la ruta anterior hasta que esté la nueva
  if page.calculating then status = GREY .. L["Calculando la ruta…"] .. "|r" end
  page.status:SetText(status)
  self:UpdateCalcProgress(page) -- (barra y % mientras calcula; si no, se esconde)

  -- Ruta empezada: buscar una mejor una vez cada vez que abres la página (no con cada
  -- cosa que compras o fabricas: es un cálculo entero). Antes de las filas: si acaba
  -- al momento (fuera del juego), su aviso ya sale en ellas
  if lock and page.shownToken and page.betterAsked ~= page.shownToken and not page.calculating then
    page.betterAsked = page.shownToken
    self:CheckBetterRoute(page)
  end

  local lines = {}
  if plan and #plan.steps > 0 then
    if page.view == "profit" then lines = ProfitLines(plan, page, inBags)
    elseif page.view == "shop" then lines = ShopLines(plan, page)
    else
      lines = RouteLines(plan, page)
      local better = BetterLine(page)
      if better then table.insert(lines, 1, better) end
    end
  end
  page.lines = lines
  page.empty:SetText(#lines == 0 and (plan and #plan.steps > 0 and L["Nada que mostrar en esta vista."] or "") or "")

  ES.UI.RenderLines(page, lines)
  -- Segunda mejor receta de cada paso: se calcula después, sin trabar (y se repinta)
  if plan and #plan.steps > 0 and not page.calculating then self:ComputeAlternatives(page, plan) end
end
