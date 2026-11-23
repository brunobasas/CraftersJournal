local _, ES = ...
local L = ES.L

---------------------------------------------------------------------------
-- Opciones del addon, en su propia ventana (ES:OpenOptions): la abren el engranaje de
-- la cabecera (junto al idioma), /cj opciones y "Todas las opciones" del menú del
-- engranaje de las ventanas junto al vendedor, la AH y la profesión. A la izquierda,
-- las categorías (General y una por pestaña o ventana con opciones); a la derecha, las
-- casillas de la elegida. Ya no se registran en las opciones del juego (AddOns).
-- Si salen solas las ventanas junto al vendedor y junto a la Casa de Subastas, y si se
-- propone vender tu equipo (ligado o en un conjunto), entre otras:
--   ES.db.protectGear      = true: tu equipo (ligado o en un conjunto) no se propone
--                            vender (InventoryUI.lua). Por defecto no: se propone todo
--   ES.db.noChatAlerts     = true: sin los avisos del chat tras un escaneo (recetas
--                            de botín en la AH, ruta que cuesta más con precios nuevos)
--   ES.db.minimap.hide     = true: sin botón del minimapa (LibDBIcon)
--   ES.db.noVendorWindow   = true: no sale la ventana junto al vendedor
--   ES.db.noCraftWindow    = true: no sale la ventana de Ganar dinero junto a la
--                            ventana de una profesión (CraftWindowUI.lua)
--   ES.db.noAuctionWindows = true: no sale sola la lista de compra junto a la AH; el
--                            botón de la AH la sigue abriendo a mano
--   ES.db.noAuctionSellWindow = true: no sale la ventana de vender en la AH lo de tus
--                            bolsas (AuctionSellUI.lua). Antes iba con noAuctionWindows:
--                            quien la tenía desactivada sigue sin las dos (ver Migrate)
--   ES.db.noPostConfirm    = true: anunciar en la AH sin preguntar antes (AuctionSellUI.lua,
--                            Sell.Post). Se apaga también con "No volver a preguntar"
--   ES.db.noScanButtons    = true: sin los botones de escanear, el de la cabecera y el
--                            "Crafter's Journal: Escanear" de encima de la AH (UI.lua,
--                            PlaceScanButtons). Los escaneos completos de Auctionator se
--                            leen igual; con Auctionator en modo resumen, o sin él, se
--                            ven en gris con lo que falta (UI.lua, ScanButtonsLock).
--                            CurseForge: ya tenían su botón Escanear. Antes era noAHButton,
--                            solo el de la AH (ver Migrate)
--   ES.db.noNeutralAHNotice = true: sin la ventana que avisa de que el addon aún no
--                            funciona en la Casa de Subastas neutral (Core.lua)
-- Todas salen por defecto (es lo normal del addon), salvo protectGear; la primera vez que sale cada ventana se dice en el chat que se puede quitar aquí (ES:WindowTip)
---------------------------------------------------------------------------

function ES:VendorWindowOn() return not (self.db and self.db.noVendorWindow) end
function ES:AuctionWindowsOn() return not (self.db and self.db.noAuctionWindows) end
function ES:AuctionSellWindowOn() return not (self.db and self.db.noAuctionSellWindow) end

-- Una vez: quien había quitado las ventanas de la AH (eran una sola opción) tampoco
-- ve la de vender ahora que va aparte
function ES:MigrateWindowOptions()
  local db = self.db
  if not db then return end
  -- Quien quitó el botón de encima de la AH (noAHButton) no quería los de escanear:
  -- tampoco ve ahora el de la cabecera, que va con él en una sola opción
  if db.noAHButton and db.noScanButtons == nil then db.noScanButtons = true end
  db.noAHButton = nil
  db.scanButtons = nil -- (de una prueba en la que venían desactivados por defecto)
  if db.sellWindowSplit then return end
  db.sellWindowSplit = true
  if db.noAuctionWindows and db.noAuctionSellWindow == nil then db.noAuctionSellWindow = true end
  db.auctionSellWindow = nil -- (de una prueba en la que venía desactivada por defecto)
end

-- La primera vez que sale sola cada ventana (junto al vendedor, la AH o la
-- profesión), un aviso en el chat: se puede quitar en /cj opciones. CurseForge: no
-- sabían que se podía y les parecía que el addon se metía en medio
local TIPS = {
  vendor = "Esta ventana sale sola al abrir un vendedor. Si no la quieres, quítala en /cj opciones.",
  shopping = "La lista de compra sale sola al abrir la Casa de Subastas. Si no la quieres, quítala en /cj opciones.",
  sell = "La ventana de vender en la AH sale sola al abrir la Casa de Subastas. Si no la quieres, quítala en /cj opciones.",
  craft = "Esta ventana sale sola al abrir una profesión. Si no la quieres, quítala en /cj opciones.",
}
-- Nombre de una opción (su etiqueta en el panel), para el menú del engranaje
local function OptionLabel(key)
  for _, o in ipairs(ES.OPTIONS or {}) do
    if o.key == key then return L[o.label] end
  end
end
ES.OptionLabel = OptionLabel -- (también el diálogo de confirmar: ES:Confirm, UI.lua)

-- Menú pequeño del engranaje: la opción justa de esa ventana ("No mostrar esta
-- ventana", lo mismo que quitar su casilla en las opciones) y, debajo, todas las
-- opciones. Antes el engranaje abría el panel entero y había que buscar la casilla
local function GearMenu(gear, frame, key)
  local m = CreateFrame("Frame", nil, frame, "BackdropTemplate")
  m:SetSize(230, 112)
  m:SetPoint("TOPRIGHT", gear, "BOTTOMRIGHT", 6, -4)
  if m.SetFrameStrata then m:SetFrameStrata("DIALOG") end
  if m.SetClampedToScreen then m:SetClampedToScreen(true) end
  m:EnableMouse(true)
  m:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  m:SetBackdropColor(0.08, 0.06, 0.04, 0.98)
  m:SetBackdropBorderColor(0.52, 0.38, 0.17, 1)
  m.title = m:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  m.title:SetPoint("TOPLEFT", 12, -10)
  m.title:SetPoint("RIGHT", -12, 0)
  m.title:SetJustifyH("LEFT")
  m.title:SetWordWrap(false)
  m.off = CreateFrame("Button", nil, m, "UIPanelButtonTemplate")
  m.off:SetSize(206, 24)
  m.off:SetPoint("TOP", 0, -30)
  m.off:SetScript("OnClick", function()
    m.open = false
    m:Hide()
    ES:SetOption(key, false) -- (como quitar su casilla: la ventana se cierra al momento)
    ES:Print(string.format(L["%s: desactivada. Vuelve a activarla en /cj opciones."], OptionLabel(key) or key))
  end)
  m.note = m:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  m.note:SetPoint("TOP", m.off, "BOTTOM", 0, -5)
  m.note:SetWidth(206)
  m.all = CreateFrame("Button", nil, m, "UIPanelButtonTemplate")
  m.all:SetSize(206, 22)
  m.all:SetPoint("BOTTOM", 0, 10)
  m.all:SetScript("OnClick", function()
    m.open = false
    m:Hide()
    ES:OpenOptions(ES:OptionCategory(key)) -- (en la categoría de esta ventana)
  end)
  -- Textos al mostrarse (el idioma puede haber cambiado)
  m:SetScript("OnShow", function()
    m.title:SetText(OptionLabel(key) or "Crafter's Journal")
    m.off:SetText(L["No mostrar esta ventana"])
    m.note:SetText(L["Se vuelve a activar en /cj opciones."])
    m.all:SetText(L["Todas las opciones"])
  end)
  m:SetScript("OnHide", function() m.open = false end)
  m:Hide()
  return m
end

-- Dibujo de un botón de engranaje (el de las ventanas de al lado y el de la cabecera)
-- El engranaje de 64 px del mapa (el cuarto de arriba a la izquierda del archivo): se
-- ve nítido al reducirlo. El de antes (UI-OptionsButton) es pequeño y salía borroso.
-- En gris y teñido de dorado
local GEAR = "Interface\\WorldMap\\Gear_64.png"
local function GearTexture(tex, r, g, b)
  if not tex then return end
  tex:SetTexture(GEAR)
  tex:SetTexCoord(0, 0.5, 0, 0.5)
  tex:SetDesaturated(true)
  tex:SetVertexColor(r, g, b)
end
function ES.StyleGear(b)
  -- Apagado como el resto de la cabecera; al pasar el ratón, se ilumina el mismo engranaje
  -- (el recuadro de UI-Common-MouseHilight se veía como un cuadrado)
  b:SetNormalTexture(GEAR)
  GearTexture(b:GetNormalTexture(), 0.88, 0.72, 0.38)
  local hover = b:CreateTexture(nil, "HIGHLIGHT")
  hover:SetAllPoints()
  GearTexture(hover, 1, 0.85, 0.45)
  hover:SetAlpha(0.5)
  b:SetHighlightTexture(hover, "ADD")
  b:SetPushedTexture(GEAR)
  local pushed = b:GetPushedTexture()
  if pushed then
    GearTexture(pushed, 0.66, 0.54, 0.3)
    pushed:ClearAllPoints()
    pushed:SetPoint("TOPLEFT", 1, -1)
    pushed:SetPoint("BOTTOMRIGHT", 1, -1)
  end
end

-- Engranaje en la esquina de las ventanas que salen solas (vendedor, AH, profesión).
-- `close`: su ✕, si tiene (va a su izquierda). `key`: la opción que la quita; con
-- ella, el clic abre un menú pequeño con esa opción (GearMenu); sin ella, el panel
function ES:OptionsGear(frame, close, key)
  local b = CreateFrame("Button", nil, frame)
  b:SetSize(18, 18)
  -- La ✕ (UIPanelCloseButton) mide 32 px con ~6 de aire alrededor del dibujo: pegado a
  -- su borde ya queda separado. Antes iba 4 px dentro y se montaba sobre la ✕ (y algo
  -- más alto, el dibujo de la ✕ está 1 px por debajo del centro)
  if close then b:SetPoint("RIGHT", close, "LEFT", 0, -1) else b:SetPoint("TOPRIGHT", -9, -9) end
  ES.StyleGear(b)
  b:SetScript("OnClick", function()
    if not key then ES:OpenOptions() return end
    b.menu = b.menu or GearMenu(b, frame, key)
    GameTooltip:Hide()
    -- (abierto o no: su propia marca, que OnHide pone a false también cuando se
    -- cierra la ventana de debajo)
    b.menu.open = not b.menu.open
    b.menu:SetShown(b.menu.open)
  end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(L["Opciones"])
    GameTooltip:AddLine(L["Clic: dejar de mostrar esta ventana, o ver todas las opciones."], 1, 1, 1, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  frame.optionsGear = b
  return b
end

function ES:WindowTip(kind)
  local db = self.db
  if not db or not TIPS[kind] then return end
  if type(db.windowTips) ~= "table" then db.windowTips = {} end
  if db.windowTips[kind] then return end
  db.windowTips[kind] = true
  self:Print(L[TIPS[kind]])
end
function ES:CraftWindowOn() return not (self.db and self.db.noCraftWindow) end

-- Cambia una opción (on: la casilla marcada) y lo aplica al momento: la pestaña
-- Inventario y las ventanas del vendedor y la AH, si están abiertos
function ES:SetOption(key, on)
  self.db[key] = (not on) or nil
  self:ApplyOptions(key, on)
end

function ES:ApplyOptions(key, on)
  if self.RenderInventory then self:RenderInventory() end
  if self.VendorShop and self.VendorShop.Refresh then self.VendorShop:Refresh() end
  if self.AuctionSell and self.AuctionSell.Refresh then self.AuctionSell:Refresh() end
  if self.CraftWindow and self.CraftWindow.Refresh then self.CraftWindow:Refresh() end
  -- (la lista de compra: desactivada se quita; activada sale la próxima vez que
  -- abras la AH, o ya con el botón de encima de la AH)
  local mini = self.ShoppingMini and self.ShoppingMini()
  if key == "noAuctionWindows" and not on and mini then mini:Hide() end
  -- (los botones de escanear: al momento; el de la AH, si no está abierta, al abrirla)
  -- (y en gris o no: escondidos con Auctionator en modo resumen, ES:ScanButtonsLock)
  if key == "noScanButtons" and self.PlaceScanButtons then
    self:PlaceScanButtons()
    self:RefreshScanButtons()
  end
end

local OPTIONS = {
  -- General
  -- (se guarda en ES.db.minimap.hide, el sitio de LibDBIcon: también /cj minimap)
  { key = "minimap", cat = "general", label = "Botón del minimapa", desc = "El botón de Crafter's Journal junto al minimapa. También con /cj minimap.",
    get = function() return not (ES.db.minimap and ES.db.minimap.hide) end,
    set = function(on) ES:SetMinimapShown(on) end },
  { key = "noWhatsNew", cat = "general", label = "Mostrar las novedades al actualizar",
    desc = "Tras actualizar el addon, una ventana con lo nuevo de esa versión (una vez por versión). También se quita con su casilla \"No volver a mostrar\"." },
  { key = "noChatAlerts", cat = "general", label = "Avisos en el chat",
    desc = "Tras un escaneo: recetas de botín que te faltan y están en la AH, y si tu ruta empezada cuesta bastante más con los precios nuevos. Desactivados, la ruta lo sigue diciendo en su línea de estado." },
  -- Lista de compra
  { key = "noAuctionWindows", cat = "shopping", label = "Lista de compra junto a la Casa de Subastas",
    desc = "Al abrir la AH: los materiales de tu ruta que te faltan, para comprarlos. Desactivada, se sigue pudiendo abrir con el botón de encima de la AH." },
  -- Tamaño de la tanda en verde (Planner.BatchCrafts): la compra por tramos en las
  -- recetas verdes compra para unas tantas fabricaciones; al gastarlas, la siguiente
  { key = "batchCrafts", cat = "shopping", kind = "slider", label = "Tamaño de las tandas (recetas verdes)",
    desc = "En verde no todas las fabricaciones suben punto: la ruta compra para unas tantas y, al gastarlas, la siguiente. Más grande, menos viajes a la AH; más pequeña, menos material de sobra si tienes suerte.",
    steps = ES.Planner.BATCH_STEPS, default = ES.Planner.BATCH_CRAFTS,
    text = function(v) return string.format(L["%d fabricaciones"], v) end,
    enabled = function() return true end,
    apply = function() if ES.RefreshAllViews then ES:RefreshAllViews() end ES:ApplyOptions() end },
  -- Casa de Subastas
  { key = "noScanButtons", cat = "auction", label = "Botones de escanear de Crafter's Journal",
    desc = "El botón Escanear de la cabecera del addon y el de encima de la AH, que además abre el addon. Piden el escaneo completo de Auctionator. Desactivados, se esconden si el botón Escanear de Auctionator hace el escaneo completo (su escaneo alternativo activado). Si no, porque Auctionator está en modo resumen (el de por defecto) o no está instalado, salen en gris con lo que falta: el addon solo se actualiza con escaneos completos. Ábrelo con /cj o el botón del minimapa." },
  -- (Core.lua, NeutralAHNotice: también se apaga con la casilla de su ventana)
  { key = "noNeutralAHNotice", cat = "auction", label = "Aviso en la Casa de Subastas neutral",
    desc = "Al abrir la Casa de Subastas neutral (Bahía del Botín, Gadgetzan, Vista Eterna), una ventana avisa de que Crafter's Journal aún no funciona en ella." },
  { key = "noAuctionSellWindow", cat = "auction", label = "Vender en la AH desde tus bolsas",
    desc = "Al abrir la AH: una ventana con lo de tus bolsas que se vende mejor en la AH. Clic en una fila para anunciarlo." },
  { key = "noPostConfirm", cat = "auction", label = "Confirmar antes de anunciar en la AH",
    desc = "Al anunciar más de una unidad de golpe (ventana de vender, Inventario, ruta), pregunta antes cuántas y a qué precio. Así un clic sin querer no anuncia un montón." },
  -- Vendedor
  { key = "noVendorWindow", cat = "vendor", label = "Ventana junto al vendedor",
    desc = "Al abrir un vendedor: lo que te falta de la lista de compra y lo que puedes venderle, con los botones Comprar todo y Vender todo." },
  -- Confirmar antes de las acciones de golpe (ES:Confirm, UI.lua): su casilla "No volver
  -- a mostrar este aviso" las apaga; aquí se vuelven a encender
  { key = "noSellAllConfirm", cat = "vendor", label = "Confirmar antes de Vender todo",
    desc = "Al pulsar Vender todo en la ventana junto al vendedor, pregunta antes qué vende y por cuánto." },
  { key = "noBuyAllConfirm", cat = "vendor", label = "Confirmar antes de Comprar todo",
    desc = "Al pulsar Comprar todo en la ventana junto al vendedor, pregunta antes cuántos materiales compra y por cuánto." },
  -- Inventario (qué se propone vender: también la ventana del vendedor)
  -- (por defecto desactivada: se propone todo y lo tuyo lo apartas con clic derecho)
  { key = "protectGear", cat = "inventory", label = "No vender tu equipo",
    desc = "Activado, el equipo ligado a ti (tu otro equipo, lo de las misiones) y el de los conjuntos del gestor de equipo no se propone vender (ni Vender todo lo vende); los verdes sin ligar de botín, lo que fabricas y lo gris, sí. Desactivado, se propone todo: lo que quieras guardar, clic derecho y no se vende nunca.",
    get = function() return ES.db.protectGear == true end,
    set = function(on) ES.db.protectGear = on or nil ES:ApplyOptions("protectGear", on) end },
  { key = "noInventorySellConfirm", cat = "inventory", label = "Confirmar antes de vender todo al vendedor",
    desc = "Al pulsar el botón de vender al vendedor de la pestaña Inventario, pregunta antes cuántos objetos vende y por cuánto." },
  { key = "noAddonPrices", cat = "inventory", label = "Usar los precios de Auctionator o TSM",
    desc = "Si tu escaneo no tiene un objeto de tus bolsas, se usa el precio que guarda Auctionator o TSM para decidir si va a la AH o al vendedor. Tu escaneo siempre manda." },
  -- Inversiones (Invest.lua; la cartera es siempre de la cuenta: todos tus personajes).
  -- Cómo se escribe el precio al apuntar una compra o venta (InvestUI.lua, OpenEntry):
  -- el total (por defecto) o por unidad; en la ventana se cambia para cada una
  { key = "investPriceMode", cat = "invest", kind = "segmented", label = "Precio al apuntar una compra o venta",
    desc = "Lo que escribes en el precio: el total (lo que pagaste por todo) o el precio por unidad. En la ventana de compra o venta lo puedes cambiar cada vez.",
    choices = { { value = "total", text = "Total" }, { value = "unit", text = "Por unidad" } }, default = "total" },
  -- Borrar un movimiento (su X en el detalle) pregunta antes (InvestUI.lua, ES:Confirm)
  { key = "noInvestDeleteConfirm", cat = "invest", label = "Confirmar antes de borrar un movimiento",
    desc = "Al pulsar la X de una compra o venta en el detalle de un objeto, pregunta antes de borrarla." },
  -- Columnas de la vista de lista que no se ven (InvestUI.lua, ES.InvestListColumns)
  { key = "investHiddenColumns", cat = "invest", kind = "hide", label = "Columnas de la lista",
    desc = "Clic en una columna para ocultarla de la vista de lista (o volver a mostrarla). El nombre del objeto gana el sitio.",
    items = function() return ES.InvestListColumns.Items() end,
    isHidden = function(key) return ES.InvestListColumns.IsHidden(key) end,
    setHidden = function(key, on) ES.InvestListColumns.SetHidden(key, on) end },
  -- Ganar dinero (la ventana junto a la profesión enseña lo que propone esa pestaña)
  { key = "noCraftWindow", cat = "earn", label = "Ventana junto a la profesión",
    desc = "Al abrir una profesión: lo que la pestaña Ganar dinero propone fabricar de esa profesión. Clic en una fila para fabricarlo." },
  -- (Market.lua: una señal más de mercado y tope del lote; sin TSM no hace nada)
  { key = "noTsmDemand", cat = "earn", label = "Usar la demanda de TSM",
    desc = "Si tienes TSM con su app de escritorio: cuántos se venden al día en la región y qué parte de lo que se anuncia se vende. Es una alerta más de mercado y no se proponen más de los que se venden en 2 días. Tus escaneos siguen mandando.",
    set = function(on)
      ES.db.noTsmDemand = (not on) or nil
      ES.Market.ClearTSM()
      if ES.Earn and ES.Earn.Clear then ES.Earn:Clear(true) end
      if ES.RefreshAllViews then ES:RefreshAllViews() end
      ES:ApplyOptions("noTsmDemand", on)
    end },
  -- Umbrales de la demanda de TSM (Market.TSMMinSold / TSMMinRate): deslizadores por
  -- escalones; en gris si no se usa TSM
  { key = "tsmMinSold", cat = "earn", kind = "slider", label = "Demanda de TSM: vendidos al día, mínimo",
    desc = "Por debajo, alerta de poca demanda (y no se propone aprender la receta). Cuenta toda la región: tu reino vende como mucho eso.",
    steps = ES.Market.TSM_SOLD_STEPS, default = ES.Market.TSM_MIN_SOLD,
    text = function(v) return v > 0 and string.format(L["%s al día"], ES.Market.Dec(v)) or L["No cuenta"] end,
    enabled = function() return not ES.db.noTsmDemand end },
  { key = "tsmMinRate", cat = "earn", kind = "slider", label = "Demanda de TSM: tasa de venta mínima",
    desc = "Qué parte de lo que se anuncia acaba vendiéndose (1 = todo). Por debajo, alerta de poca demanda.",
    steps = ES.Market.TSM_RATE_STEPS, default = ES.Market.TSM_MIN_RATE,
    text = function(v) return v > 0 and ES.Market.Dec(v) or L["No cuenta"] end,
    enabled = function() return not ES.db.noTsmDemand end },
}

-- Cambió un umbral de mercado: Ganar dinero y lo que dependa de las alertas, de nuevo
local function ApplyMarketSetting()
  if ES.Earn and ES.Earn.Clear then ES.Earn:Clear(true) end
  if ES.RefreshAllViews then ES:RefreshAllViews() end
  ES:ApplyOptions()
end
ES.OPTIONS = OPTIONS -- (el menú del engranaje saca de aquí el nombre de cada ventana)

-- Categorías de la ventana, en el orden de la lista de la izquierda: General y una por
-- pestaña o ventana que tiene opciones (cada opción dice la suya en `cat`). Con
-- `build`, la página es propia (no de casillas): build(ventana, padre, ancho) la crea
-- con su :Refresh() y, si tiene, su `header` (botones en la línea del título)
local CATEGORIES = {
  { key = "general",   label = "General" },
  -- Orden y visibilidad de las pestañas de la ventana principal (TabsOptionsUI.lua)
  { key = "tabs",      label = "Pestañas",
    build = function(f, parent, width) return ES:CreateTabsOptionsPage(f, parent, width) end },
  { key = "shopping",  label = "Lista de compra" },
  { key = "auction",   label = "Casa de Subastas" },
  { key = "vendor",    label = "Vendedor" },
  { key = "inventory", label = "Inventario" },
  { key = "earn",      label = "Ganar dinero" },
  { key = "invest",    label = "Inversiones" },
}
ES.OPTION_CATEGORIES = CATEGORIES

-- Categoría de una opción (para abrir la ventana justo donde está)
function ES:OptionCategory(key)
  for _, o in ipairs(OPTIONS) do
    if o.key == key then return o.cat end
  end
end

---------------------------------------------------------------------------
-- Ventana de opciones, al estilo de la del diario de mazmorras: cabecera con el
-- título y la ✕, categorías a la izquierda y, a la derecha, el nombre de la elegida
-- y sus casillas (con rueda y guía si no caben)
---------------------------------------------------------------------------
local WIN_W, WIN_H = 660, 440
local PAD, TOP = 14, 52       -- márgenes; TOP: bajo la cabecera
local SIDE_W = 176            -- lista de categorías
local GOLD = { 0.96, 0.79, 0.25 }
local CONTENT_W = WIN_W - PAD * 2 - SIDE_W - 8 - 24 -- ancho de las casillas (sin la guía)
local DESC_W = CONTENT_W - 44

local function Box(parent, r, g, b, a)
  local p = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  p:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  p:SetBackdropColor(r, g, b, a)
  p:SetBackdropBorderColor(0.52, 0.38, 0.17, 1)
  return p
end

-- Una casilla: marca, nombre y, debajo, qué hace
local function CreateCheck(page, o)
  local cb = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
  cb:SetSize(26, 26)
  cb.label = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  cb.label:SetPoint("LEFT", cb, "RIGHT", 6, 1)
  cb.label:SetWidth(DESC_W)
  cb.label:SetJustifyH("LEFT")
  cb.desc = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  cb.desc:SetPoint("TOPLEFT", cb.label, "BOTTOMLEFT", 0, -5)
  cb.desc:SetWidth(DESC_W)
  cb.desc:SetJustifyH("LEFT")
  cb.desc:SetTextColor(0.78, 0.74, 0.66)
  cb.option = o
  cb:SetScript("OnClick", function(self)
    local on = self:GetChecked() and true or false
    if o.set then o.set(on) else ES:SetOption(o.key, on) end
    if page.Refresh then page:Refresh() end -- (un deslizador puede depender de ella)
  end)
  return cb
end

-- Un deslizador por escalones (o.kind == "slider"): nombre, valor elegido a la
-- derecha, qué hace y la barra. Guarda ES.db[o.key] (el valor del escalón; nada si es
-- el de por defecto). o = { steps, default, text(v), enabled() }
local SLIDER_W = 240
local function SliderIndex(o)
  local v = ES.db[o.key]
  if type(v) ~= "number" then v = o.default end
  local best = 1
  for i, s in ipairs(o.steps) do if s <= v + 1e-9 then best = i end end
  return best
end

local function CreateSlider(page, o)
  local row = CreateFrame("Frame", nil, page)
  row:SetSize(CONTENT_W, 60)
  row.option, row.isSlider = o, true
  row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  row.label:SetPoint("TOPLEFT", 32, -5)
  row.label:SetWidth(DESC_W)
  row.label:SetJustifyH("LEFT")
  row.desc = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.desc:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -5)
  row.desc:SetWidth(DESC_W)
  row.desc:SetJustifyH("LEFT")
  row.desc:SetTextColor(0.78, 0.74, 0.66)
  local slider = CreateFrame("Slider", nil, row, "BackdropTemplate")
  slider:SetSize(SLIDER_W, 16)
  slider:SetPoint("TOPLEFT", row.desc, "BOTTOMLEFT", 0, -8)
  slider:SetOrientation("HORIZONTAL")
  slider:SetBackdrop({
    bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
    edgeFile = "Interface\\Buttons\\UI-SliderBar-Border", edgeSize = 8,
    insets = { left = 3, right = 3, top = 6, bottom = 6 },
  })
  slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  slider:SetMinMaxValues(1, #o.steps)
  slider:SetValueStep(1)
  if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
  slider:EnableMouseWheel(true)
  row.slider = slider
  row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.value:SetPoint("LEFT", slider, "RIGHT", 12, 0)

  -- Elegir el escalón i: se guarda y se aplica (true si cambió)
  function row.Set(i)
    i = math.max(1, math.min(#o.steps, i))
    local v = o.steps[i]
    local was = ES.db[o.key]
    ES.db[o.key] = (math.abs(v - o.default) > 1e-9) and v or nil
    row.value:SetText(o.text(v))
    if was == ES.db[o.key] then return false end
    if o.apply then o.apply() else ApplyMarketSetting() end
    return true
  end
  -- (al soltar o tras un momento quieto: arrastrar no recalcula en cada escalón)
  local pending, wanted
  slider:SetScript("OnValueChanged", function(self, value)
    if row.syncing then return end
    wanted = math.floor(value + 0.5)
    row.value:SetText(o.text(o.steps[math.max(1, math.min(#o.steps, wanted))]))
    if not pending and C_Timer then
      pending = true
      C_Timer.After(0.25, function() pending = nil row.Set(wanted) end)
    end
  end)
  slider:SetScript("OnMouseWheel", function(self, delta)
    if not o.enabled() then return end
    self:SetValue(math.max(1, math.min(#o.steps, SliderIndex(o) + (delta > 0 and 1 or -1))))
  end)

  -- Textos, valor guardado y si se puede tocar; devuelve lo que mide la fila
  function row.Refresh()
    row.label:SetText(L[o.label])
    row.desc:SetText(L[o.desc])
    local i = SliderIndex(o)
    row.value:SetText(o.text(o.steps[i]))
    row.syncing = true
    slider:SetValue(i)
    row.syncing = nil
    local on = o.enabled()
    slider:EnableMouse(on)
    slider:SetAlpha(on and 1 or 0.4)
    row.label:SetAlpha(on and 1 or 0.5)
    row.value:SetAlpha(on and 1 or 0.5)
    local descH = tonumber(row.desc:GetStringHeight()) or 0
    return 5 + 14 + 5 + descH + 8 + 16 + 4
  end
  return row
end

-- Un selector de segmentos (o.kind == "segmented"): nombre, qué hace y, debajo, un botón
-- por opción (ES.UI.Segmented, InvestUI.lua). Guarda ES.db[o.key] (nada si es la de por
-- defecto). o = { choices = { { value, text } }, default, apply() opcional }
local function SegmentedValue(o)
  local v = ES.db[o.key]
  for _, c in ipairs(o.choices) do if c.value == v then return v end end
  return o.default
end

local function CreateSegmented(page, o)
  local row = CreateFrame("Frame", nil, page)
  row:SetSize(CONTENT_W, 60)
  row.option, row.isRow = o, true
  row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  row.label:SetPoint("TOPLEFT", 32, -5)
  row.label:SetWidth(DESC_W)
  row.label:SetJustifyH("LEFT")
  row.desc = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.desc:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -5)
  row.desc:SetWidth(DESC_W)
  row.desc:SetJustifyH("LEFT")
  row.desc:SetTextColor(0.78, 0.74, 0.66)
  row.select = ES.UI.Segmented(row, o.choices, function(v)
    ES.db[o.key] = v ~= o.default and v or nil
    if o.apply then o.apply(v) end
  end, 110, 22)
  row.select:SetPoint("TOPLEFT", row.desc, "BOTTOMLEFT", 0, -8)
  function row.Refresh()
    row.label:SetText(L[o.label])
    row.desc:SetText(L[o.desc])
    row.select:SetValue(SegmentedValue(o))
    local descH = tonumber(row.desc:GetStringHeight()) or 0
    return 5 + 14 + 5 + descH + 8 + 24 + 4
  end
  return row
end

-- Cosas que se ocultan (o.kind == "hide"): nombre, qué hace y, debajo, una ficha por
-- cosa en dos columnas, con la paleta de las filas de la categoría Pestañas. Un clic la
-- oculta (gris, con OCULTA encima) o la vuelve a mostrar, al momento.
-- o = { items() -> { { key, label } }, isHidden(key), setHidden(key, on) }
local HIDE_ROW_H, HIDE_GAP = 28, 4
local function CreateHideList(page, o)
  local row = CreateFrame("Frame", nil, page)
  row:SetSize(CONTENT_W, 60)
  row.option, row.isRow = o, true
  row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  row.label:SetPoint("TOPLEFT", 32, -5)
  row.label:SetWidth(DESC_W)
  row.label:SetJustifyH("LEFT")
  row.desc = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.desc:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -5)
  row.desc:SetWidth(DESC_W)
  row.desc:SetJustifyH("LEFT")
  row.desc:SetTextColor(0.78, 0.74, 0.66)
  row.items = {}
  local itemW = math.floor((DESC_W - HIDE_GAP) / 2)

  local function Item(i)
    local b = row.items[i]
    if b then return b end
    b = CreateFrame("Button", nil, row, "BackdropTemplate")
    b:SetSize(itemW, HIDE_ROW_H)
    ES.UI.RowStyle(b)
    b.name = ES.UI.Label(b, "", "GameFontNormal")
    b.name:SetPoint("LEFT", 10, 0)
    b.name:SetPoint("RIGHT", -10, 0)
    b.name:SetJustifyH("LEFT")
    b.name:SetWordWrap(false)
    b.shade = b:CreateTexture(nil, "ARTWORK", nil, 7)
    b.shade:SetPoint("TOPLEFT", 2, -2)
    b.shade:SetPoint("BOTTOMRIGHT", -2, 2)
    b.shade:SetColorTexture(0, 0, 0, 0.5)
    b.hiddenText = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.hiddenText:SetPoint("RIGHT", -10, 0)
    b.hiddenText:SetTextColor(1, 1, 1)
    local function Tip(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(self.label)
      GameTooltip:AddLine(self.hidden and L["Clic: volver a mostrarla."] or L["Clic: ocultarla."], 0.5, 0.8, 1, true)
      GameTooltip:Show()
    end
    b:SetScript("OnClick", function(self)
      o.setHidden(self.key, not o.isHidden(self.key))
      row.Refresh()
      if self:IsMouseOver() then Tip(self) end -- (el tooltip dice lo que hará el próximo clic)
    end)
    b:SetScript("OnEnter", function(self)
      self:SetBackdropBorderColor(unpack(ES.UI.ROW_BORDER_HOVER))
      Tip(self)
    end)
    b:SetScript("OnLeave", function(self)
      self:SetBackdropBorderColor(unpack(ES.UI.ROW_BORDER))
      GameTooltip:Hide()
    end)
    row.items[i] = b
    return b
  end

  function row.Refresh()
    row.label:SetText(L[o.label])
    row.desc:SetText(L[o.desc])
    local top = 5 + 14 + 5 + (tonumber(row.desc:GetStringHeight()) or 0) + 8
    local list = o.items()
    for i, it in ipairs(list) do
      local b = Item(i)
      local hidden = o.isHidden(it.key) and true or false
      b.key, b.label, b.hidden = it.key, it.label, hidden
      b.name:SetText(it.label)
      b.name:SetAlpha(hidden and 0.45 or 1)
      b.shade:SetShown(hidden)
      b.hiddenText:SetText(L["OCULTA"])
      b.hiddenText:SetShown(hidden)
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", 32 + ((i - 1) % 2) * (itemW + HIDE_GAP), -(top + math.floor((i - 1) / 2) * (HIDE_ROW_H + HIDE_GAP)))
      b:Show()
    end
    for i = #list + 1, #row.items do row.items[i]:Hide() end
    return top + math.ceil(#list / 2) * (HIDE_ROW_H + HIDE_GAP) + 2
  end
  return row
end

-- Textos y marcas de una categoría (el idioma o las opciones pueden haber cambiado) y
-- las filas una debajo de otra: cada una mide lo que ocupe su descripción
local function RefreshPage(page)
  local y = -6
  for _, cb in ipairs(page.checks) do
    local o = cb.option
    cb:ClearAllPoints()
    cb:SetPoint("TOPLEFT", 6, y)
    if cb.isSlider or cb.isRow then
      local h = cb.Refresh()
      cb:SetHeight(h)
      y = y - h - 14
    else
      cb.label:SetText(L[o.label])
      cb.desc:SetText(L[o.desc])
      if o.get then cb:SetChecked(o.get()) else cb:SetChecked(not ES.db[o.key]) end
      local descH = tonumber(cb.desc:GetStringHeight()) or 0
      y = y - math.max(30, 24 + descH) - 14
    end
  end
  page:SetHeight(math.max(1, -y))
end

local function CategoryButton(f, i, cat)
  local b = CreateFrame("Button", nil, f.side)
  b:SetHeight(24)
  b:SetPoint("TOPLEFT", 8, -10 - (i - 1) * 26)
  b:SetPoint("TOPRIGHT", -8, -10 - (i - 1) * 26)
  -- La elegida: fondo dorado suave con una barra a la izquierda
  b.sel = b:CreateTexture(nil, "BACKGROUND")
  b.sel:SetAllPoints()
  b.sel:SetColorTexture(0.68, 0.52, 0.20, 0.28)
  b.bar = b:CreateTexture(nil, "ARTWORK")
  b.bar:SetPoint("TOPLEFT", 0, 0)
  b.bar:SetPoint("BOTTOMLEFT", 0, 0)
  b.bar:SetWidth(3)
  b.bar:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
  b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  b.text:SetPoint("LEFT", 12, 0)
  b.text:SetPoint("RIGHT", -6, 0)
  b.text:SetJustifyH("LEFT")
  b.text:SetWordWrap(false)
  b.key = cat.key
  b:SetScript("OnClick", function() f:SelectCategory(cat.key) end)
  return b
end

local window
local function CreateWindow()
  local f = CreateFrame("Frame", "CraftersJournalOptionsFrame", UIParent, "BackdropTemplate")
  f:SetSize(WIN_W, WIN_H)
  -- El marco de la ventana principal: roca oscura con borde de diálogo
  f:SetBackdrop({
    bgFile = "Interface\\FrameGeneral\\UI-Background-Rock",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 16, edgeSize = 24,
    insets = { left = 6, right = 6, top = 6, bottom = 6 },
  })
  f:SetBackdropColor(0.045, 0.042, 0.037, 0.99)
  f:SetPoint("CENTER")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetFrameStrata("DIALOG") -- (encima de la ventana principal, que va en HIGH)
  f:Hide()
  tinsert(UISpecialFrames, "CraftersJournalOptionsFrame") -- cerrar con Escape

  -- Cabecera: banda marrón con líneas doradas, como la de la ventana principal
  local band = f:CreateTexture(nil, "BACKGROUND", nil, 1)
  band:SetPoint("TOPLEFT", 12, -10)
  band:SetPoint("TOPRIGHT", -12, -10)
  band:SetHeight(32)
  band:SetColorTexture(0.14, 0.10, 0.055, 0.96)
  for _, edge in ipairs({ { "TOPLEFT", "TOPRIGHT", 0.65 }, { "BOTTOMLEFT", "BOTTOMRIGHT", 0.45 } }) do
    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetPoint(edge[1], band, edge[1], 0, 0)
    line:SetPoint(edge[2], band, edge[2], 0, 0)
    line:SetHeight(1)
    line:SetColorTexture(0.68, 0.52, 0.20, edge[3])
  end
  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  f.title:SetPoint("TOP", 0, -18)
  f.title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
  f.closeButton = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  f.closeButton:SetPoint("TOPRIGHT", -3, -3)
  -- Esquina para ampliar o reducir, como la ventana principal (escala en ES.db.optionsScale)
  ES.AddScaleGrip(f, "optionsScale")

  -- Izquierda: las categorías
  f.side = Box(f, 0.13, 0.095, 0.06, 0.95)
  f.side:SetPoint("TOPLEFT", PAD, -TOP)
  f.side:SetPoint("BOTTOMLEFT", PAD, PAD)
  f.side:SetWidth(SIDE_W)
  f.categoryButtons = {}
  for i, cat in ipairs(CATEGORIES) do f.categoryButtons[i] = CategoryButton(f, i, cat) end

  -- Abajo de las categorías: la versión del addon, pequeña y en blanco suave, y encima
  -- una invitación al Discord (abre la ventana con el enlace para copiarlo)
  f.version = f.side:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.version:SetPoint("BOTTOM", 0, 10)
  f.version:SetTextColor(0.78, 0.76, 0.72)
  f.version:SetAlpha(0.75)
  local discord = CreateFrame("Button", nil, f.side, "BackdropTemplate")
  f.discordButton = discord
  discord:SetPoint("BOTTOMLEFT", 8, 28)
  discord:SetPoint("BOTTOMRIGHT", -8, 28)
  discord:SetHeight(42)
  discord:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  discord:SetBackdropColor(0.20, 0.16, 0.10, 0.95)
  discord:SetBackdropBorderColor(0.68, 0.52, 0.20, 0.9)
  discord:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  discord.icon = discord:CreateTexture(nil, "OVERLAY")
  discord.icon:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-Chat-Up")
  discord.icon:SetSize(22, 22)
  discord.icon:SetPoint("LEFT", 8, 0)
  discord.title = discord:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  discord.title:SetPoint("TOPLEFT", discord.icon, "TOPRIGHT", 6, 1)
  discord.title:SetPoint("RIGHT", -6, 0)
  discord.title:SetJustifyH("LEFT")
  discord.title:SetWordWrap(false)
  discord.sub = discord:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  discord.sub:SetPoint("TOPLEFT", discord.title, "BOTTOMLEFT", 0, -3)
  discord.sub:SetPoint("RIGHT", -6, 0)
  discord.sub:SetJustifyH("LEFT")
  discord.sub:SetWordWrap(false)
  discord.sub:SetTextColor(0.78, 0.76, 0.72)
  discord:SetScript("OnClick", function() ES:ShowReportDialog("join") end)

  -- Derecha: nombre de la categoría, línea dorada y sus casillas
  f.body = Box(f, 0.18, 0.14, 0.10, 0.95)
  f.body:SetPoint("TOPLEFT", f.side, "TOPRIGHT", 8, 0)
  f.body:SetPoint("BOTTOMRIGHT", -PAD, PAD)
  f.heading = f.body:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  f.heading:SetPoint("TOPLEFT", 18, -14)
  f.heading:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
  local rule = f.body:CreateTexture(nil, "ARTWORK")
  rule:SetPoint("TOPLEFT", 14, -40)
  rule:SetPoint("TOPRIGHT", -14, -40)
  rule:SetHeight(1)
  rule:SetColorTexture(0.68, 0.52, 0.20, 0.55)
  f.scroll = ES.UI.WheelScroll(f.body, 40)
  f.scroll:SetPoint("TOPLEFT", 10, -48)
  f.scroll:SetPoint("BOTTOMRIGHT", -14, 10)
  -- (la guía mide la página que se ve ahora)
  local shown = { GetHeight = function()
    local page = f.pages[f.selected or ""]
    return page and page:GetHeight() or 0
  end }
  f.indicator = ES.UI.ScrollIndicator(f.scroll, shown, 5)

  -- Una página por categoría, con sus casillas. f.checks: todas, en el orden de OPTIONS
  f.pages, f.checks = {}, {}
  for _, cat in ipairs(CATEGORIES) do
    local page
    if cat.build then
      page = cat.build(f, f.scroll, CONTENT_W)
    else
      page = CreateFrame("Frame", nil, f.scroll)
      page:SetSize(CONTENT_W, 1)
      page.Refresh = RefreshPage
    end
    page:Hide()
    page.key, page.label, page.checks = cat.key, cat.label, {}
    f.pages[cat.key] = page
  end
  for _, o in ipairs(OPTIONS) do
    local page = f.pages[o.cat] or f.pages.general
    local cb = o.kind == "slider" and CreateSlider(page, o)
      or o.kind == "segmented" and CreateSegmented(page, o)
      or o.kind == "hide" and CreateHideList(page, o) or CreateCheck(page, o)
    page.checks[#page.checks + 1] = cb
    f.checks[#f.checks + 1] = cb
  end

  -- Enseña una categoría (la de antes si no existe la pedida)
  function f:SelectCategory(key)
    local page = self.pages[key] or self.pages[self.selected or ""] or self.pages.general
    self.selected = page.key
    for _, b in ipairs(self.categoryButtons) do
      local on = b.key == page.key
      b.sel:SetShown(on)
      b.bar:SetShown(on)
      if on then b.text:SetTextColor(1, 1, 1) else b.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3]) end
    end
    for _, p in pairs(self.pages) do
      p:SetShown(p == page)
      if p.header then p.header:SetShown(p == page) end
    end
    self.heading:SetText(L[page.label])
    page:Refresh()
    self.scroll:SetScrollChild(page)
    if self.scroll.UpdateScrollChildRect then self.scroll:UpdateScrollChildRect() end
    self.scroll:SetVerticalScroll(0)
    self.indicator:Update()
  end

  -- Textos al mostrarse: el idioma o las opciones pueden haber cambiado
  function f:Refresh()
    self.title:SetText("Crafter's Journal · " .. L["Opciones"])
    for i, b in ipairs(self.categoryButtons) do b.text:SetText(L[CATEGORIES[i].label]) end
    self.discordButton.title:SetText(L["Únete a nuestro Discord"])
    self.discordButton.sub:SetText(L["Ideas, errores y novedades"])
    local version = ES.AddonVersion and ES.AddonVersion()
    self.version:SetText(version and string.format(L["Versión %s"], version) or "")
    self:SelectCategory(self.selected or "general")
  end
  f:SetScript("OnShow", function(self) self:Refresh() end)
  return f
end

-- La ventana de opciones (se crea la primera vez)
function ES:OptionsWindow()
  window = window or CreateWindow()
  return window
end

-- Abre las opciones; `category` (opcional): la que se enseña, si no la última vista
function ES:OpenOptions(category)
  local w = self:OptionsWindow()
  if category then w.selected = category end
  if w:IsShown() then w:Refresh() else w:Show() end
end

-- Engranaje de la cabecera: abre o cierra la ventana
function ES:ToggleOptions()
  if window and window:IsShown() then window:Hide() return end
  self:OpenOptions()
end
