local _, ES = ...
local L = ES.L

local GOLD_ICON   = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"
local SILVER_ICON = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t"
local COPPER_ICON = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"

local CoinString = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
  or function(copper)
    local g = math.floor(copper / 10000)
    local s = math.floor(copper / 100) % 100
    local c = copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. GOLD_ICON end
    if s > 0 then parts[#parts + 1] = s .. SILVER_ICON end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. COPPER_ICON end
    return table.concat(parts, " ")
  end

local function Money(copper)
  copper = tonumber(copper)
  -- Sin cantidad, NaN (no es igual a sí mismo) o infinito: una raya, no un error
  if not copper or copper ~= copper or copper == math.huge or copper == -math.huge then
    return "|cff888888—|r"
  end
  copper = math.floor(copper + 0.5)
  -- GetCoinTextureString solo acepta positivos (con negativos daba error: registro de
  -- errores de la 0.44, aviso de ruta que cuesta más): el signo va delante
  if copper < 0 then return "-" .. CoinString(-copper) end
  return CoinString(copper)
end
ES.Money = Money

-- Dinero dentro de un texto de letra más pequeña (las citas de la ruta): los
-- iconos del juego quedan altos, así que se bajan `offsetY` píxeles
function ES.MoneyInline(copper, offsetY)
  copper = math.floor((copper or 0) + 0.5)
  local function Icon(name) return string.format("|TInterface\\MoneyFrame\\UI-%sIcon:0:0:2:%d|t", name, offsetY or 0) end
  local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  local parts = {}
  if g > 0 then parts[#parts + 1] = g .. Icon("Gold") end
  if s > 0 then parts[#parts + 1] = s .. Icon("Silver") end
  if c > 0 or #parts == 0 then parts[#parts + 1] = c .. Icon("Copper") end
  return table.concat(parts, " ")
end

local function TimeAgo(t)
  local d = time() - t
  if d < 60 then return L["hace unos segundos"] end
  if d < 3600 then return string.format(L["hace %d min"], math.floor(d / 60)) end
  if d < 86400 then return string.format(L["hace %d h"], math.floor(d / 3600)) end
  return string.format(L["hace %d días"], math.floor(d / 86400))
end
ES.TimeAgo = TimeAgo -- (también el estado de los precios al anunciar, Ledger.lua)

---------------------------------------------------------------------------
-- Panel principal
---------------------------------------------------------------------------
local main
local PAGE_MARGIN = 14 -- margen negro de las páginas a los lados y abajo

-- Escalar arrastrando la esquina inferior derecha: toda la ventana se amplía o
-- reduce a la vez (mismo factor en ancho y alto). La esquina superior izquierda
-- se queda donde está. La escala se recuerda en ES.db[dbKey]. Lo usan la ventana
-- principal (frameScale) y la de opciones (optionsScale, Options.lua)
function ES.AddScaleGrip(f, dbKey)
  local BASE_W, BASE_H = f:GetWidth(), f:GetHeight()
  local MIN_SCALE, MAX_SCALE = 0.6, 1.8
  local savedScale = tonumber(ES.db[dbKey])
  if savedScale then f:SetScale(math.min(MAX_SCALE, math.max(MIN_SCALE, savedScale))) end

  f.resize = CreateFrame("Button", nil, f)
  f.resize:SetSize(16, 16)
  f.resize:SetPoint("BOTTOMRIGHT", -8, 8)
  f.resize:SetFrameLevel(f:GetFrameLevel() + 20)
  f.resize:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  f.resize:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  f.resize:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

  -- Escala para que la esquina inferior derecha quede bajo el ratón
  local function ScaleToCursor(left, top)
    local ui = UIParent:GetEffectiveScale()
    local x, y = GetCursorPosition()
    x, y = x / ui, y / ui
    local scale = math.max((x - left) / BASE_W, (top - y) / BASE_H)
    scale = math.min(MAX_SCALE, math.max(MIN_SCALE, scale))
    f:SetScale(scale)
    -- Los desplazamientos van en la escala del propio marco
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / scale, top / scale)
  end

  f.resize:SetScript("OnMouseDown", function(self, button)
    if button ~= "LeftButton" then return end
    -- Esquina superior izquierda en coordenadas de la pantalla (UIParent)
    local scale = f:GetScale()
    local left, top = f:GetLeft() * scale, f:GetTop() * scale
    self:SetScript("OnUpdate", function() ScaleToCursor(left, top) end)
  end)
  f.resize:SetScript("OnMouseUp", function(self)
    self:SetScript("OnUpdate", nil)
    ES.db[dbKey] = math.floor(f:GetScale() * 100 + 0.5) / 100
  end)
  f.resize:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(L["Arrastra para ampliar o reducir la ventana"])
    GameTooltip:AddLine(L["Doble clic: tamaño normal"], 0.8, 0.8, 0.8)
    GameTooltip:Show()
  end)
  f.resize:SetScript("OnLeave", function() GameTooltip:Hide() end)
  f.resize:SetScript("OnDoubleClick", function()
    local s = f:GetScale()
    local left, top = f:GetLeft() * s, f:GetTop() * s
    f:SetScale(1)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    ES.db[dbKey] = 1
  end)
end

local function CreateMainFrame()
  local f = CreateFrame("Frame", "CraftersJournalMainFrame", UIParent, "BackdropTemplate")
  f:SetSize(840, 612)
  -- Marco de roca oscura con borde de diálogo del juego
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
  f:SetFrameStrata("HIGH")
  f:Hide()
  tinsert(UISpecialFrames, "CraftersJournalMainFrame") -- cerrar con Escape

  -- Cabecera: Informar, título e idioma (HeaderUI.lua)
  ES:CreateHeader(f)

  -- Escalar arrastrando la esquina (ES.AddScaleGrip): la escala va en ES.db.frameScale
  ES.AddScaleGrip(f, "frameScale")

  -- Navegación: la portada (tarjetas) y una página por tarjeta. Encima de la
  -- página, el título y "Volver" a la portada
  -- Flechas a los lados, como "Mazmorras" en el diario: la profesión anterior y la
  -- siguiente (en Subir profesiones y en la colección de recetas)
  local function Arrow(dir)
    local b = CreateFrame("Button", nil, f)
    b:SetSize(26, 26)
    local base = "Interface\\Buttons\\UI-SpellbookIcon-" .. (dir < 0 and "Prev" or "Next") .. "Page-"
    b:SetNormalTexture(base .. "Up")
    b:SetPushedTexture(base .. "Down")
    b:SetDisabledTexture(base .. "Disabled")
    b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    b:SetScript("OnClick", function() ES:SelectSiblingPage(dir) end)
    b:SetScript("OnEnter", function(self)
      local key = ES:SiblingPage(dir)
      if not key then return end
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:AddLine(dir < 0 and L["Profesión anterior"] or L["Profesión siguiente"])
      GameTooltip:AddLine(f.pageTitles[key] or key, 1, 1, 1)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
  end
  f.prevPage = Arrow(-1)
  f.prevPage:SetPoint("TOPLEFT", 14, -57) -- con aire encima (cabecera) y debajo (la página)
  f.back = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.back:SetSize(130, 24)
  f.back:SetPoint("LEFT", f.prevPage, "RIGHT", 2, 0)
  f.back:SetText(L["Profesiones"])
  f.back:SetScript("OnClick", function() ES:SelectPage(f.backTarget or "home") end)
  f.nextPage = Arrow(1)
  f.nextPage:SetPoint("LEFT", f.back, "RIGHT", 2, 0)

  f.navTitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  f.navTitle:SetJustifyH("LEFT")

  -- Working Overtime activo (talento de legado, ES:UpdateSkillUpBonus): su icono y una
  -- etiqueta junto al título, en las páginas de rutas. Su tooltip dice si las rutas lo
  -- cuentan (ES.COUNT_OVERTIME; por ahora no) y que comprar por tramos lo compensa
  local ot = CreateFrame("Frame", nil, f)
  ot:SetSize(200, 22)
  ot:EnableMouse(true)
  ot.icon = ot:CreateTexture(nil, "ARTWORK")
  ot.icon:SetSize(20, 20)
  ot.icon:SetPoint("LEFT", 0, 0)
  ot.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  ot.label = ot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  ot.label:SetPoint("LEFT", ot.icon, "RIGHT", 6, 0)
  ot:SetScript("OnEnter", function(self)
    local rank = ES.overtimeRank or 0
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Working Overtime", 1, 0.82, 0)
    local bonus = rank * ES.OVERTIME_PER_RANK
    GameTooltip:AddLine(string.format(L["Talento de legado, rango %d/5: +%d%% de probabilidad de subir punto en las recetas amarillas y verdes."],
      rank, math.floor(bonus * 100 + 0.5)), 1, 1, 1, true)
    if ES.COUNT_OVERTIME then
      GameTooltip:AddLine(L["Las rutas lo cuentan: piden menos fabricaciones en los pasos amarillos y verdes."], 0.8, 0.8, 0.8, true)
    else
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(L["Las rutas aún no lo cuentan: no se sabe con certeza cómo lo aplica el juego. Con él necesitarás algo menos de fabricaciones de las que dice la ruta en los pasos amarillos y verdes."], 1, 0.82, 0, true)
      GameTooltip:AddLine(L["Por eso compensa comprar por tramos (lo que hace la Lista de compra por defecto): cada tramo compra solo lo suyo y el siguiente cuenta lo que te sobró, así que como mucho te sobra algo de un tramo."], 0.5, 0.8, 1, true)
    end
    GameTooltip:Show()
  end)
  ot:SetScript("OnLeave", function() GameTooltip:Hide() end)
  ot:Hide()
  f.overtime = ot

  f.pages, f.pageTitles = {}, {}
  local function AddPage(key, title)
    -- Márgenes negros a los lados y abajo, como el diario de mazmorras
    local page = CreateFrame("Frame", nil, f)
    page:SetPoint("TOPLEFT", PAGE_MARGIN, -94)
    page:SetPoint("BOTTOMRIGHT", -PAGE_MARGIN, PAGE_MARGIN)
    page:Hide()
    f.pages[key], f.pageTitles[key] = page, title
    return page
  end
  f.AddPage = AddPage

  ES:CreateHomePage(AddPage("home", L["Subir profesiones"]))
  ES:CreateEarnPage(AddPage("money", ""))
  ES:CreateInventoryPage(AddPage("inventory", ""))
  ES:CreateInvestPage(AddPage("invest", ""))
  ES:CreateInvestItemPage(AddPage("investItem", ""))
  ES:CreateFavorPage(AddPage("favor", ""))
  ES:CreateCalculatorPage(AddPage("calc", ""))
  ES:CreateShoppingPage(AddPage("shopping", ""))
  ES:CreatePatternsPage(AddPage("patterns", L["Colección de recetas"]))
  for _, prof in ipairs(ES.PROFESSIONS) do
    if ES.Data[prof.key] then ES:CreatePatternPage(AddPage("pattern:" .. prof.key, ES:ProfLabel(prof.key)), prof.key) end
  end

  -- Al abrir el panel se vuelve a donde estabas en esta sesión (la última página; en
  -- una profesión, también su vista), salvo que se pida otra. Solo en la sesión: con
  -- otro personaje (o al volver a entrar) se empieza en la portada
  -- El botón de la estrella sobre una fila (Waypoints.lua) no se queda flotando
  f:HookScript("OnHide", function() ES.Waypoints.ReleaseHover() end)
  -- Cerrada un rato, fuera las cachés que se rehacen al momento (ES:ScheduleIdleRelease)
  f:HookScript("OnHide", function() ES:ScheduleIdleRelease() end)
  f:SetScript("OnShow", function(self)
    ES.Jobs.Resume() -- rutas pendientes de cuando estaba cerrada (Jobs.lua)
    ES:RefreshScanButtons()
    -- (la primera vez en la sesión, la pestaña de arriba: ES.Tabs, se elige en opciones)
    ES:SelectPage(self.openPage or ES.sessionPage or ES.Tabs.StartKey())
    self.openPage = nil
    ES:KeepTabsOnScreen() -- (sin pestañas a la vista no se puede cambiar de página)
  end)

  main = f
  -- Profesiones con datos: su página lleva el nombre en su propia cabecera
  for _, prof in ipairs(ES.PROFESSIONS) do
    if ES.Data[prof.key] then
      ES:CreateProfessionPage(AddPage(prof.key, ""), prof.key)
    end
  end
  ES:CreateSideTabs(f)
  return f
end

---------------------------------------------------------------------------
-- Pestañas laterales (a la derecha, como las del libro de hechizos)
---------------------------------------------------------------------------
-- Icono de "Subir profesiones": el del libro de profesiones de Forever (pico y
-- martillo). Es un icono propio de Forever, sin nombre de archivo: su número
ES.SKILLS_ICON = 8197101
local TABS = ES.Localize({
  { key = "home",     label = "Subir profesiones",    icon = "skills",
    desc = "Cómo subir cada profesión: la ruta más barata paso a paso." },
  -- (justo debajo de Subir profesiones: es lo que se usa al seguir una ruta)
  { key = "shopping", label = "Lista de compra",      icon = "Interface\\Icons\\INV_Misc_Note_01",
    desc = "Lo que pide tu ruta empezada (sale sola) y lo que añades desde Ganar dinero o la calculadora; con la AH abierta, se compra desde aquí." },
  { key = "money",    label = "Ganar dinero",         icon = "Interface\\Icons\\INV_Misc_Coin_02",
    desc = "Qué fabricar hoy con tus recetas porque da beneficio." },
  { key = "inventory", label = "Inventario",          icon = "Interface\\Icons\\INV_Misc_Bag_08",
    desc = "Qué vender de tus bolsas, dónde y cuánto sacas; y lo que ha subido de precio." },
  { key = "invest",   label = "Inversiones",          icon = ES.Invest.ICON,
    desc = "Tu cartera de inversiones en la AH: lo que compraste, a qué precio medio y cuánto ganas o pierdes con cada objeto." },
  { key = "favor",    label = "Merchant's Favor",     icon = "Interface\\Icons\\INV_Misc_Coin_17",
    desc = "Las Waylaid Crates: con qué llenar las tuyas y qué cajas de la AH dan el Favor más barato." },
  { key = "calc",     label = "Calculadora",          icon = "Interface\\Icons\\INV_Misc_Note_02",
    desc = "Cuánto ganas con una receta, como en una hoja de cálculo: guarda varios cálculos y escribe tus precios." },
  { key = "patterns", label = "Colección de recetas", icon = "Interface\\Icons\\INV_Scroll_03",
    desc = "Todas las recetas de cada profesión: cuántas tienes y dónde conseguir las demás." },
}, "label")
ES.Localize(TABS, "desc")
ES.TABS = TABS -- (la categoría Pestañas de las opciones: TabsOptionsUI.lua)

---------------------------------------------------------------------------
-- Orden y visibilidad de las pestañas: se eligen en las opciones, categoría Pestañas
-- (TabsOptionsUI.lua). Se guardan para la cuenta:
--   ES.db.tabOrder   = { "shopping", "home", ... }: el orden elegido (nada si es el de
--                      siempre, el de TABS)
--   ES.db.hiddenTabs = { [clave] = true }: las ocultas (nada si no hay ninguna)
-- Ocultar quita solo el icono: la página sigue abriéndose desde la AH, el asistente de
-- ruta... Siempre queda al menos una visible, y la primera visible es la de inicio
---------------------------------------------------------------------------
local Tabs = {}
ES.Tabs = Tabs

function Tabs.Info(key)
  for _, t in ipairs(TABS) do if t.key == key then return t end end
end

local function DefaultOrder()
  local out = {}
  for i, t in ipairs(TABS) do out[i] = t.key end
  return out
end

local function IndexOf(list, key)
  for i, k in ipairs(list) do if k == key then return i end end
end

-- Claves en el orden efectivo: el guardado, sin las que ya no existen y con las que
-- falten (pestañas nuevas de una versión posterior) tras la que las precede en el de
-- siempre (o la primera, si no las precede ninguna)
function Tabs.Order()
  local saved = ES.db and ES.db.tabOrder
  if type(saved) ~= "table" then return DefaultOrder() end
  local out, seen = {}, {}
  for _, key in ipairs(saved) do
    if type(key) == "string" and not seen[key] and Tabs.Info(key) then
      out[#out + 1] = key
      seen[key] = true
    end
  end
  for i, t in ipairs(TABS) do
    if not seen[t.key] then
      local prev = i > 1 and IndexOf(out, TABS[i - 1].key)
      table.insert(out, prev and prev + 1 or 1, t.key)
      seen[t.key] = true
    end
  end
  return out
end

-- Las visibles, en orden. Nunca ninguna: si lo guardado las oculta todas (a mano o
-- roto), se ve la primera
function Tabs.Visible()
  local hidden = ES.db and type(ES.db.hiddenTabs) == "table" and ES.db.hiddenTabs or {}
  local order, out = Tabs.Order(), {}
  for _, key in ipairs(order) do
    if not hidden[key] then out[#out + 1] = key end
  end
  if #out == 0 then out[1] = order[1] end
  return out
end

function Tabs.IsHidden(key)
  return Tabs.Info(key) ~= nil and not IndexOf(Tabs.Visible(), key)
end

-- La pestaña en la que se abre el addon (la primera visible)
function Tabs.StartKey()
  return Tabs.Visible()[1]
end

-- Aplica lo elegido: las pestañas de la ventana principal, si ya existe
local function Apply()
  if ES.LayoutTabs then ES:LayoutTabs() end
end

-- Guarda un orden (nada si es el de siempre)
local function SaveOrder(order)
  local default = DefaultOrder()
  local same = #order == #default
  for i = 1, #default do if order[i] ~= default[i] then same = false end end
  ES.db.tabOrder = (not same) and order or nil
end

-- Mueve la pestaña del puesto `from` al `to` (en el orden efectivo). Sin cambio real
-- (mismo puesto o fuera de la lista) no hace nada y devuelve false
function Tabs.Move(from, to)
  local order = Tabs.Order()
  local n = #order
  if type(from) ~= "number" or type(to) ~= "number" or from < 1 or from > n or to < 1 or to > n or from == to then
    return false
  end
  table.insert(order, to, table.remove(order, from))
  SaveOrder(order)
  Apply()
  return true
end

-- Oculta (on) o vuelve a mostrar una pestaña. No deja ocultar la última visible:
-- devuelve false, "last"
function Tabs.SetHidden(key, on)
  if not Tabs.Info(key) then return false end
  local db = ES.db
  if on then
    if Tabs.IsHidden(key) then return true end
    if #Tabs.Visible() <= 1 then return false, "last" end
    if type(db.hiddenTabs) ~= "table" then db.hiddenTabs = {} end
    db.hiddenTabs[key] = true
  elseif type(db.hiddenTabs) == "table" then
    db.hiddenTabs[key] = nil
    if next(db.hiddenTabs) == nil then db.hiddenTabs = nil end
  end
  Apply()
  return true
end

-- El orden de siempre, con todas visibles
function Tabs.Reset()
  ES.db.tabOrder, ES.db.hiddenTabs = nil, nil
  Apply()
end

-- Arrastrar una fila (TabsOptionsUI.lua): `mids` son las alturas del centro de cada
-- fila de arriba abajo (decrecen: la pantalla cuenta hacia arriba) y `y` la del ratón.
-- Devuelve el hueco donde cae: 1 = encima de la primera, #mids + 1 = debajo de la última
function Tabs.DropIndex(y, mids)
  local gap = 1
  for _, mid in ipairs(mids) do
    if y < mid then gap = gap + 1 end
  end
  return gap
end

-- Puesto final de la fila `from` soltada en el hueco `gap` (para Tabs.Move): al
-- quitarla de su sitio, los huecos de debajo suben uno
function Tabs.GapToIndex(from, gap)
  if gap > from then return gap - 1 end
  return gap
end

-- Pestaña a la que pertenece cada página, y adónde vuelve "Volver"
local function TabOf(key)
  if key:match("^pattern:") then return "patterns", "patterns" end
  if key == "investItem" then return "invest", "invest" end -- detalle de una inversión
  if ES.Data[key] then return "home", "home" end -- página de una profesión
  return key, nil
end

-- Pestaña idéntica a las del libro de profesiones de Forever (medidas leídas del
-- juego sobre ProfessionsFrame): botón de 55x55; marco
-- "common-sidetab" de 55x60 centrado; icono de 50x50 desplazado -4 px y recortado
-- 1/32 por borde; seleccionada = "common-sidetab-selected" dos veces (normal y
-- sumado); ratón encima = "common-sidetab-hover". La primera, 60 px bajo la esquina
-- superior derecha; las demás, 2 px por debajo de la anterior.
local TAB_SIZE, TAB_GAP, TAB_TOP = 55, 2, -60

local function Atlas(tex, name, w, h)
  local ok = tex.SetAtlas and tex:SetAtlas(name)
  tex:SetSize(w, h)
  return ok
end

local function CreateTab(parent, icon)
  local tab = CreateFrame("Button", nil, parent)
  tab:SetSize(TAB_SIZE, TAB_SIZE)
  local bg = tab:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("CENTER")
  local hasAtlas = Atlas(bg, "common-sidetab", 55, 60)
  tab.icon = tab:CreateTexture(nil, "ARTWORK")
  tab.icon:SetSize(50, 50)
  tab.icon:SetPoint("CENTER", -4, 0)
  tab.icon:SetTexture(icon)
  tab.icon:SetTexCoord(0.03125, 0.96875, 0.03125, 0.96875)
  tab.selected = {}
  for _, blend in ipairs({ "BLEND", "ADD" }) do
    local sel = tab:CreateTexture(nil, "OVERLAY")
    sel:SetPoint("CENTER")
    Atlas(sel, "common-sidetab-selected", 55, 60)
    sel:SetBlendMode(blend)
    sel:Hide()
    tab.selected[#tab.selected + 1] = sel
  end
  local hover = tab:CreateTexture(nil, "HIGHLIGHT")
  hover:SetPoint("CENTER")
  Atlas(hover, "common-sidetab-hover", 55, 60)
  -- Cliente sin esos atlas: marco y brillos clásicos del libro de hechizos
  if not hasAtlas then
    bg:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
    bg:SetSize(64, 64)
    bg:ClearAllPoints()
    bg:SetPoint("TOPLEFT", -3, 11)
    for _, sel in ipairs(tab.selected) do sel:SetTexture("Interface\\Buttons\\CheckButtonHilight") sel:SetBlendMode("ADD") end
    hover:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    hover:SetBlendMode("ADD")
  end
  function tab:SetChecked(on)
    for _, sel in ipairs(self.selected) do sel:SetShown(on and true or false) end
  end
  return tab
end

-- Avisa de que algo nuevo ha llegado a una pestaña (la Lista de compra al añadir un
-- tramo): la pestaña brilla unos segundos y, si sound, suena el de las monedas
function ES:FlashTab(key, sound)
  if sound and PlaySound then
    pcall(PlaySound, SOUNDKIT and SOUNDKIT.IG_BACKPACK_COIN_OK or 891)
  end
  if not main or not main.tabs then return end
  for _, tab in ipairs(main.tabs) do
    if tab.key == key then
      if not tab.flash then
        tab.flash = tab:CreateTexture(nil, "OVERLAY")
        tab.flash:SetAllPoints(tab.icon)
        tab.flash:SetColorTexture(1, 0.82, 0.25, 1)
        tab.flash:SetBlendMode("ADD")
        tab.flash:SetAlpha(0)
        local ag = tab.flash:CreateAnimationGroup()
        local up = ag:CreateAnimation("Alpha")
        up:SetFromAlpha(0) up:SetToAlpha(0.55) up:SetDuration(0.35) up:SetOrder(1)
        local down = ag:CreateAnimation("Alpha")
        down:SetFromAlpha(0.55) down:SetToAlpha(0) down:SetDuration(0.35) down:SetOrder(2)
        -- (SetLooping: SetLoopType no existe y daba error cada vez, sin brillo)
        ag:SetLooping("REPEAT")
        tab.flashAnim = ag
      end
      tab.flashAnim:Stop()
      tab.flashAnim:Play()
      tab.flashing = true -- (para pruebas)
      C_Timer.After(2.8, function() if tab.flashAnim then tab.flashAnim:Stop() tab.flash:SetAlpha(0) end tab.flashing = nil end)
    end
  end
end

function ES:CreateSideTabs(f)
  f.tabs = {}
  -- (todas, también las ocultas: dónde va cada una lo decide ES:LayoutTabs)
  for _, t in ipairs(TABS) do
    local tab = CreateTab(f, t.icon == "skills" and ES.SKILLS_ICON or t.icon)
    tab.key = t.key
    -- Vuelve a donde estabas en esa pestaña (la profesión que mirabas), no a su portada;
    -- a la portada se va con el botón "Profesiones" / "Colección"
    tab:SetScript("OnClick", function() ES:SelectPage(ES.tabLastPage[t.key] or t.key) end)
    tab:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(t.label)
      GameTooltip:AddLine(t.desc, 0.8, 0.8, 0.8, true)
      GameTooltip:Show()
    end)
    tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.tabs[#f.tabs + 1] = tab
  end
  -- Las pestañas cuelgan fuera del marco, a la derecha, y SetClampedToScreen solo
  -- mira el marco: pegada al borde derecho (junto a la AH, o arrastrada) se quedaban
  -- fuera de la pantalla y no había forma de salir de la página (informe de la 0.60,
  -- atascado en la Lista de compra). Que cuenten para mantenerla dentro
  if f.SetClampRectInsets then f:SetClampRectInsets(0, TAB_SIZE, 0, 0) end
  ES:LayoutTabs(f)
end

-- Coloca las pestañas en el orden elegido: cada visible bajo la visible anterior (la
-- primera, TAB_TOP bajo la esquina) y las ocultas escondidas. main.visibleTabs: las
-- visibles, de arriba abajo. Se llama al crearlas y al cambiar el orden o las ocultas
function ES:LayoutTabs(f)
  f = f or main
  if not (f and f.tabs) then return end
  local byKey = {}
  for _, tab in ipairs(f.tabs) do byKey[tab.key] = tab end
  local shown = {}
  f.visibleTabs = {}
  for _, key in ipairs(Tabs.Visible()) do
    local tab = byKey[key]
    if tab then
      local prev = f.visibleTabs[#f.visibleTabs]
      tab:ClearAllPoints()
      if prev then
        tab:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -TAB_GAP)
      else
        tab:SetPoint("TOPLEFT", f, "TOPRIGHT", 0, TAB_TOP)
      end
      f.visibleTabs[#f.visibleTabs + 1] = tab
      shown[tab] = true
    end
  end
  for _, tab in ipairs(f.tabs) do tab:SetShown(shown[tab] or false) end
end

-- Por si acaso (escala, resolución que cambia, marco colocado antes de ajustarse):
-- si la primera pestaña sale por la derecha de la pantalla, la ventana vuelve al centro
function ES:KeepTabsOnScreen()
  local tab = main and main.visibleTabs and main.visibleTabs[1]
  local right = tab and tab:GetRight()
  local width = GetScreenWidth and GetScreenWidth()
  if type(right) ~= "number" or type(width) ~= "number" then return end
  local ratio = tab:GetEffectiveScale() / UIParent:GetEffectiveScale()
  if right * ratio > width + 1 then
    main:ClearAllPoints()
    main:SetPoint("CENTER")
  end
end

ES.tabLastPage = {} -- [pestaña] = última página vista en ella (solo esta sesión)
function ES:SelectPage(key)
  if key == "lw" or key == "profit" then key = "Leatherworking" end -- nombres de versiones anteriores
  -- (también pestañas que ya no existen: a la de inicio, la primera visible)
  if not main or not main.pages[key] then key = Tabs.StartKey() end
  self.db.lastPage = key
  self.sessionPage = key -- lo que recuerda la ventana al volver a abrirla (solo esta sesión)
  for k, page in pairs(main.pages) do page:SetShown(k == key) end
  local tab, back = TabOf(key)
  self.tabLastPage[tab] = key -- (la pestaña vuelve aquí al pulsarla otra vez)
  for _, t in ipairs(main.tabs or {}) do t:SetChecked(t.key == tab) end
  -- "Volver" solo dentro de una pestaña (una profesión, la colección de una profesión)
  local inner = key ~= tab
  main.back:SetShown(inner)
  main.backTarget = back
  main.back:SetText(back == "patterns" and L["Colección"] or back == "invest" and L["Inversiones"] or L["Profesiones"])
  -- Flechas: solo dentro de una profesión, y si hay otra a la que pasar
  local siblings = inner and #self:SiblingPages(key) > 1
  main.prevPage:SetShown(siblings)
  main.nextPage:SetShown(siblings)
  main.navTitle:ClearAllPoints()
  if inner then
    main.navTitle:SetPoint("LEFT", siblings and main.nextPage or main.back, "RIGHT", 12, 0)
  else
    main.navTitle:SetPoint("TOPLEFT", 22, -62)
  end
  main.navTitle:SetText(main.pageTitles[key] or "")
  self:RefreshOvertimeBadge(key)
  if key == "home" then self:RenderHome() end
end

-- El indicador de Working Overtime: en la portada de profesiones y en cada profesión
-- (las páginas con rutas), si tienes al menos un rango
function ES:RefreshOvertimeBadge(key)
  if not (main and main.overtime) then return end
  key = key or self.db.lastPage
  local ot = main.overtime
  local rank = self.overtimeRank or 0
  local routes = key == "home" or (self.Data[key] ~= nil and self.Data[key].recipes ~= nil)
  if rank <= 0 or not routes then
    ot:Hide()
    return
  end
  ot.icon:SetTexture(self:OvertimeIcon())
  ot.label:SetText("|cff40ff40" .. string.format(L["Working Overtime +%d%%"], math.floor(rank * self.OVERTIME_PER_RANK * 100 + 0.5)) .. "|r")
  ot:ClearAllPoints()
  -- (a la derecha del título; sin título, de las flechas o del botón Profesiones)
  local title = main.navTitle:GetText()
  local anchor = (title and title ~= "") and main.navTitle
    or (main.nextPage:IsShown() and main.nextPage) or (main.back:IsShown() and main.back) or main.navTitle
  ot:SetPoint("LEFT", anchor, "RIGHT", 14, 0)
  ot:Show()
end

-- Páginas hermanas de una página interior, en el orden de la portada: primero las
-- profesiones que tienes y luego el resto (las profesiones, o sus colecciones)
function ES:SiblingPages(key)
  if key == "investItem" then return {} end -- (el detalle de una inversión no tiene hermanas)
  local prefix = key:match("^pattern:") and "pattern:" or ""
  local mine, others = {}, {}
  for _, p in ipairs(self.PROFESSIONS or {}) do
    local k = prefix .. p.key
    if main and main.pages[k] then
      local data = self.Data[p.key]
      local has = data and data.skillLine and self:GetProfessionSkill(data.skillLine)
      table.insert(has and mine or others, k)
    end
  end
  for _, k in ipairs(others) do mine[#mine + 1] = k end
  return mine
end

-- La anterior (dir = -1) o la siguiente (1) de la página actual, dando la vuelta
function ES:SiblingPage(dir)
  local key = self.db and self.db.lastPage
  if not key then return nil end
  local list = self:SiblingPages(key)
  for i, k in ipairs(list) do
    if k == key then return list[(i - 1 + dir) % #list + 1] end
  end
end

function ES:SelectSiblingPage(dir)
  local key = self:SiblingPage(dir)
  if key then self:SelectPage(key) end
end

function ES:GetMainFrame()
  return main or CreateMainFrame()
end

-- Vuelve a crear la ventana (al cambiar de idioma: todos sus textos se ponen al
-- crearla). La vieja se esconde y se suelta; si estaba abierta, se abre la nueva
-- en la misma página.
-- La vieja no se puede borrar (el juego nunca libera ventanas): se deja sin eventos
-- (cada cambio de idioma dejaba otra ventana entera atendiendo las bolsas, los objetos
-- que llegan...) y se sueltan sus rutas calculadas y lo que sus filas guardan de ellas
-- (tooltips y clics, que guardan la ruta entera), para que esa memoria se recoja. Lo
-- de las filas solo lo leen sus propios clics y tooltips, que escondidas no saltan.
-- Los botones seguros (usar un objeto) no se tocan: en combate el juego lo bloquea
local ROW_FIELDS = { "tooltip", "onClick", "onRightClick", "go", "ahItem", "skipTitle" }
local function Retire(f, seen)
  if seen[f] then return end
  seen[f] = true
  if f.UnregisterAllEvents and not (f.IsProtected and f:IsProtected()) then f:UnregisterAllEvents() end
  for _, k in ipairs(ROW_FIELDS) do
    if rawget(f, k) ~= nil then f[k] = nil end
  end
  if f.GetChildren then
    for _, child in ipairs({ f:GetChildren() }) do Retire(child, seen) end
  end
end

function ES:RebuildMainFrame()
  if not main then return end
  local wasShown, page = main:IsShown(), self.db.lastPage
  main:Hide()
  main:SetScript("OnShow", nil)
  for _, p in ipairs(self.professionPages or {}) do p.plan, p.lines = nil, nil end
  pcall(Retire, main, {})
  main = nil
  self.professionPages, self.patternPages = nil, nil
  self.homePage, self.earnPage, self.patternsPage = nil, nil, nil
  self.shoppingPage = nil
  self.investPage, self.investItemPage = nil, nil
  if wasShown then self:ShowMainFrame(page) end
end

-- Abre el panel; `page` elige la página (por defecto, la última que viste en esta sesión)
function ES:ShowMainFrame(page)
  local f = self:GetMainFrame()
  if f:IsShown() then
    if page then self:SelectPage(page) end
  else
    f.openPage = page
    f:Show()
  end
end

-- Con la ventana cerrada IDLE_RELEASE segundos se sueltan las cachés que se rehacen
-- enseguida al volver a pedirlas (lighter-memory): Ganar dinero (~13 MB tras abrirlo),
-- Merchant's Favor y los precios de Inversiones. Cada página las rehace al mostrarse
-- (su OnShow), y la ventana de fabricar pide las ideas de Ganar dinero al abrirse. Las
-- rutas no: rehacerlas tarda segundos, y la fijada la usa el asistente
ES.IDLE_RELEASE = 60
local idleStamp = 0
function ES:ScheduleIdleRelease()
  idleStamp = idleStamp + 1
  local mine = idleStamp
  C_Timer.After(ES.IDLE_RELEASE, function()
    -- (otro cierre después de este, o la ventana abierta otra vez)
    if mine ~= idleStamp or (main and main:IsShown()) then return end
    ES:ReleaseIdleCaches()
  end)
end

function ES:ReleaseIdleCaches()
  if self.Earn then self.Earn:Clear() end
  if self.Favor then self.Favor.Clear() end
  if self.PriceHistory then self.PriceHistory.Clear() end
end

-- Esconde la ventana si está abierta (sin crearla si aún no existe)
function ES:HideMainFrame()
  if main and main:IsShown() then main:Hide() end
end

function ES:ToggleMainFrame()
  local f = self:GetMainFrame()
  f:SetShown(not f:IsShown())
end

-- `followed`: el escaneo lo pidió otro addon (ForeverForge al abrir la AH) y solo se
-- leyeron sus datos: no se abre la ventana, que si no se abría sola cada vez que
-- abrías la AH. Con el escaneo que pides tú (botón Escanear), sí, para ver el resultado
-- Cada parte en su fotograma (todo junto era un tirón al acabar el escaneo), y lo que
-- tarda cada una al registro de escaneos (/cj, Informar de un error)
function ES:OnScanComplete(scan, followed)
  -- Precio del día de lo que tienes en la cartera de inversiones (Invest.lua)
  if self.Invest then
    local ok, err = pcall(self.Invest.RecordScan, scan)
    if not ok then self:RecordError("invest", err) end
  end
  if not followed then self:ShowMainFrame() end
  local function Timed(label, f)
    local t = debugprofilestop and debugprofilestop()
    f()
    if t then ES:ScanLog(string.format("%s: %.0f ms", label, debugprofilestop() - t)) end
  end
  -- El historial con este escaneo (las alertas de mercado) se prepara en segundo plano
  -- (Market:Index, ~350 ms de golpe con una semana de escaneos): lo que depende de los
  -- precios nuevos, al tenerlo. Así se calcula una vez y sin congelar el juego
  local t0 = debugprofilestop and debugprofilestop()
  self.Market:Index()
  self.Market.WhenReady(function()
    if t0 then ES:ScanLog(string.format("historial (en segundo plano): %.0f ms", debugprofilestop() - t0)) end
    Timed("vistas", function() self:RefreshAllViews() end) -- precios nuevos: todos los apartados
    C_Timer.After(0, function()
      -- pergaminos de botín que te faltan, en la AH
      Timed("recetas en la AH", function() self.Collection:AlertScan(scan) end)
      C_Timer.After(0, function()
        -- ruta empezada que ahora cuesta bastante más
        Timed("ruta empezada", function() self:AnnounceRouteDrift() end)
        -- y la basura que ha dejado todo esto, en unos segundos (Jobs.lua)
        self.Jobs.CollectGarbage()
      end)
    end)
  end)
end

---------------------------------------------------------------------------
-- Botones de escaneo (panel + ventana de la AH)
---------------------------------------------------------------------------
local ahButton

-- Estado de los botones de escanear (cabecera y ventana de la AH). Escanear lanza el
-- escaneo de Auctionator (ver Scanner:Start):
--   escaneando -> el % de progreso, en gris
--   si no      -> "Escanear", pulsable solo con la AH abierta y Auctionator listo
-- Junto al botón de la cabecera, en pequeño: "Último escaneo: hace 3 min".
-- "14:21": lo que falta para poder pedir otro escaneo completo al servidor
local function Countdown(seconds)
  return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end
ES.Countdown = Countdown

function ES:RefreshScanButtons()
  local busy = self.Scanner:IsBusy()
  -- Límite de 15 min del servidor (ver Scanner): cuenta atrás en gris
  local wait = busy and 0 or self.Scanner:SecondsUntilNextScan()
  -- (el escaneo lo pide Auctionator: sin él no se puede, y también cuenta su propia
  -- cuenta atrás)
  local ahOpen = self:IsAuctionHouseOpen()
  local problem = self.Scanner.AuctionatorProblem()
  local enabled = ahOpen and not busy and wait == 0 and not problem
  -- Auctionator crea su marco de escaneo al abrirse la AH, quizá después que nosotros:
  -- se mira otra vez en un momento (unas pocas veces)
  if ahOpen and type(Auctionator) == "table" and not self.Scanner.AuctionatorFrame() then
    self.auctionatorRetries = (self.auctionatorRetries or 0) + 1
    if self.auctionatorRetries <= 5 then
      C_Timer.After(1, function() if ES:IsAuctionHouseOpen() then ES:RefreshScanButtons() end end)
    end
  else
    self.auctionatorRetries = nil
  end
  local progress
  if busy then
    progress = string.format("%d%%", math.floor((self.Scanner.progress or 0) * 100))
    if self.Scanner.state == "waiting" and (self.Scanner.waited or 0) > 0 then
      progress = progress .. string.format(" · %ds", self.Scanner.waited) -- esperando al servidor
    end
  elseif wait > 0 then
    progress = Countdown(wait)
  end

  -- Al diario solo los cambios de estado (no cada segundo de la cuenta atrás)
  local state = string.format("%s ah=%s busy=%s espera=%s", tostring(enabled), tostring(self.ahOpen), tostring(busy), tostring(wait > 0))
  if state ~= self.lastButtonState and not busy then
    self.lastButtonState = state
    self:ScanLog("botón " .. state)
  end
  if main then
    main.scanButton:SetEnabled(enabled)
    main.scanButton:SetText(progress or L["Escanear"])
    self:UpdateLastScan()
  end
  if ahButton then
    -- Siempre pulsable con la AH abierta: abre el addon aunque no se pueda escanear
    -- (CurseForge: con la cuenta atrás en gris no había forma de abrirlo desde la AH)
    ahButton:SetEnabled(self:IsAuctionHouseOpen())
    -- (sin Auctionator no escanea: solo abre el addon)
    ahButton:SetText(progress and ("Crafter's Journal: " .. progress)
      or type(Auctionator) ~= "table" and "Crafter's Journal" or L["Crafter's Journal: Escanear"])
  end
  self:UpdatePostStatus()
  -- Mientras dure el límite, la cuenta atrás avanza cada segundo
  if wait > 0 and not self.countdownTicking then
    self.countdownTicking = true
    local function Tick()
      if ES.Scanner:IsBusy() or ES.Scanner:SecondsUntilNextScan() == 0 then
        ES.countdownTicking = false
        ES:RefreshScanButtons()
        return
      end
      ES:RefreshScanButtons()
      C_Timer.After(1, Tick)
    end
    C_Timer.After(1, Tick)
  end
end

function ES:OnScanProgress()
  self:RefreshScanButtons()
end

-- Al empezar o acabar un escaneo (también si falla o se cancela), las ventanas desde
-- las que se anuncia cambian: mientras escanea no se anuncia y al acabar llegan los
-- precios nuevos. Entre medias, solo el % del aviso (sin recalcular las filas)
function ES:UpdatePostStatus()
  local busy = self.Scanner:IsBusy()
  if busy ~= self.postBusy then
    self.postBusy = busy
    if self.AuctionSell and self.AuctionSell.Refresh then self.AuctionSell:Refresh() end
    if self.RenderInventory then self:RenderInventory() end
    return
  end
  if not busy then return end
  local warn = self.Ledger:PostPriceWarning()
  if self.AuctionSell and self.AuctionSell.UpdateWait then self.AuctionSell:UpdateWait() end -- (el % de la capa de espera)
  local page = self.inventoryPage
  if page and page:IsVisible() and page.status and page.hintText then
    page.status:SetText(warn .. page.hintText)
  end
end

-- "Último escaneo: hace 3 min" junto al botón (de la AH activa)
function ES:UpdateLastScan()
  if not main or not main.lastScan then return end
  local key = self:RealmKey()
  local scan = self.db.scans and self.db.scans[key]
  local fail = self:LastScanFail()
  if fail then
    -- El último intento no acabó: que "hace 2 días" no parezca un escaneo perdido
    main.lastScan:SetText("|cffff9933" .. L["Cancelado · último: "] .. (scan and TimeAgo(scan.time) or L["nunca"]) .. "|r")
  else
    main.lastScan:SetText(scan and (L["Último escaneo: "] .. TimeAgo(scan.time)) or L["Sin escanear"])
  end
end

-- El último intento de escaneo, si falló después del último escaneo guardado
function ES:LastScanFail()
  local key = self:RealmKey()
  local fail = type(self.db.lastScanFail) == "table" and self.db.lastScanFail[key]
  local scan = self.db.scans and self.db.scans[key]
  if fail and (not scan or fail.time > scan.time) then return fail end
end

function ES:OnAuctionHouseShow()
  -- La ventana de la AH se carga bajo demanda: creamos el botón al abrirla
  local ahFrame = AuctionHouseFrame or AuctionFrame
  if not ahFrame then
    C_Timer.After(0.1, function() if ES.ahOpen then ES:OnAuctionHouseShow() end end)
    return
  end
  if not ahButton then
    ahButton = CreateFrame("Button", "CraftersJournalAHButton", ahFrame, "UIPanelButtonTemplate")
    ahButton:SetSize(180, 24)
    ahButton:SetPoint("BOTTOMRIGHT", ahFrame, "TOPRIGHT", 0, 2)
    -- Abre el addon siempre; escanea solo si se puede (sin escaneo en curso ni el
    -- límite de 15 min del servidor). Si no, se abre con los últimos precios
    ahButton:SetScript("OnClick", function()
      ES:ShowMainFrame()
      if not ES.Scanner:IsBusy() and ES.Scanner:SecondsUntilNextScan() == 0 then
        ES.Scanner:Start()
      end
    end)
    ahButton:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:AddLine("Crafter's Journal")
      GameTooltip:AddLine(L["Descarga todas las subastas y muestra el análisis."], 1, 1, 1, true)
      local wait = not ES.Scanner:IsBusy() and ES.Scanner:SecondsUntilNextScan() or 0
      local problem = ES.Scanner.AuctionatorProblem()
      if wait > 0 then
        GameTooltip:AddLine(string.format(L["El servidor solo permite un escaneo completo cada 15 min: podrás volver a escanear en %s."], ES.Countdown(wait)), 1, 0.6, 0.2, true)
      elseif problem then
        GameTooltip:AddLine(problem, 1, 0.6, 0.2, true)
      end
      GameTooltip:Show()
    end)
    ahButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  ahButton:Show() -- (escondido si la última AH fue la neutral)
  if self.ahListButton then self.ahListButton:Show() end
  self.Scanner.statusText = nil
  self:RefreshScanButtons()
  if self.SetupAuctionPanel then self:SetupAuctionPanel(ahFrame) end
end

-- AH neutral (sin soporte, ver Core.lua): fuera los botones y ventanas del addon que
-- van con la AH. Si ya estaban creados de otra visita, se verían junto a ella
function ES:HideAuctionHouseUI()
  if ahButton then ahButton:Hide() end
  if self.ahListButton then self.ahListButton:Hide() end
  local mini = self.ShoppingMini and self.ShoppingMini()
  if mini then mini:Hide() end
  if CraftersJournalAuctionSellPanel then CraftersJournalAuctionSellPanel:Hide() end
end

---------------------------------------------------------------------------
-- Confirmar antes de una acción de golpe (vender todo, comprar todo, anunciar en la AH):
-- "¿Seguro?" con Sí y No, y la casilla "No volver a mostrar este aviso", que apaga la
-- opción de ese aviso (ES.db[opts.key] = true); se vuelve a encender en /cj opciones,
-- en la categoría de esa acción. CurseForge: un clic sin querer anunció o vendió de golpe.
--   opts = { key, title, text, warn (aviso en naranja, opcional), yes (texto del botón,
--            opcional), onYes = función, no y onNo (texto y acción del otro botón,
--            opcionales), extra (alto de más para un texto largo, opcional),
--            closeOn = "MERCHANT_CLOSED" o
--            "AUCTION_HOUSE_CLOSED" (opcional: se cierra con esa ventana),
--            onCancel (opcional: se cierra sin Sí, con No, Escape o closeOn),
--            noCheck (sin la casilla ni `key`: una pregunta que no se puede apagar,
--            como la confirmación que pide la AH, GitHub #10) }
-- La acción sale del clic en Sí: vender, comprar y anunciar piden un clic del jugador
---------------------------------------------------------------------------
local confirm
local WARN_H = 40 -- alto extra con aviso (dos líneas)
local function ConfirmDialog()
  if confirm then return confirm end
  local d = CreateFrame("Frame", "CraftersJournalPostConfirm", UIParent, "BackdropTemplate")
  confirm = d
  d:SetSize(380, 170)
  d:SetPoint("CENTER", 0, 120)
  d:SetFrameStrata("FULLSCREEN_DIALOG")
  d:EnableMouse(true)
  d:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
  })
  tinsert(UISpecialFrames, "CraftersJournalPostConfirm") -- Escape: no
  d.title = d:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  d.title:SetPoint("TOP", 0, -20)
  d.text = d:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  d.text:SetPoint("TOP", d.title, "BOTTOM", 0, -10)
  d.text:SetWidth(330)
  d.check = CreateFrame("CheckButton", nil, d, "UICheckButtonTemplate")
  d.check:SetSize(24, 24)
  d.check:SetPoint("TOPLEFT", 24, -78)
  d.checkLabel = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  d.checkLabel:SetPoint("LEFT", d.check, "RIGHT", 2, 1)
  -- Aviso en naranja (p. ej. anunciar todas pese a las alertas); oculto si no hay
  d.warn = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  d.warn:SetPoint("TOP", d.text, "BOTTOM", 0, -6)
  d.warn:SetWidth(330)
  d.warn:SetTextColor(1, 0.6, 0.2)
  d.note = d:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  d.note:SetPoint("TOPLEFT", d.check, "BOTTOMLEFT", 4, -1)
  d.note:SetWidth(320)
  d.note:SetJustifyH("LEFT")
  d.ok = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
  d.ok:SetSize(120, 24)
  d.ok:SetPoint("BOTTOMRIGHT", d, "BOTTOM", -4, 18)
  d.cancel = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
  d.cancel:SetSize(120, 24)
  d.cancel:SetPoint("BOTTOMLEFT", d, "BOTTOM", 4, 18)
  -- (opts.onNo: el segundo botón también hace algo; entonces la casilla vale con los
  -- dos, porque es un aviso y no una pregunta)
  d.cancel:SetScript("OnClick", function()
    local p = d.pending
    d.pending = nil
    d:Hide()
    if p and p.onCancel then p.onCancel() end
    if p and p.onNo then
      p.onNo()
      if d.check:GetChecked() then
        ES.db[p.key] = true
        ES:Print(string.format(L["Ya no se mostrará este aviso. Se vuelve a activar en /cj opciones (%s)."],
          ES.OptionLabel and ES.OptionLabel(p.key) or p.key))
      end
    end
  end)
  -- La acción va lo PRIMERO del clic, antes de esconder el diálogo (con el botón que se
  -- acaba de pulsar) o de guardar la casilla: el anuncio en la AH pide el clic del
  -- jugador y, hecho después del Hide, el juego lo bloqueaba (GitHub #6: "ADDON BLOCKED"
  -- al pulsar Sí; sin el diálogo, anunciaba)
  d.ok:SetScript("OnClick", function()
    local p = d.pending
    d.pending = nil
    if p then p.onYes() end
    d:Hide()
    if p and d.check:GetChecked() then
      ES.db[p.key] = true
      ES:Print(string.format(L["Ya no se mostrará este aviso. Se vuelve a activar en /cj opciones (%s)."],
        ES.OptionLabel and ES.OptionLabel(p.key) or p.key))
    end
  end)
  -- Se cierra solo si se cierra el vendedor o la AH de la que es (opts.closeOn): pulsar
  -- Sí después no hacía nada y el Inventario decía "Vendidos" igualmente
  d:RegisterEvent("MERCHANT_CLOSED")
  d:RegisterEvent("AUCTION_HOUSE_CLOSED")
  d:SetScript("OnEvent", function(_, event)
    if d.pending and d.pending.closeOn == event then d:Hide() end
  end)
  -- Cerrado sin Sí ni No (Escape o closeOn): opts.onCancel. (onNo no: puede ser una
  -- acción, como "Por tramos" en WholeRouteNotice)
  d:SetScript("OnHide", function()
    local p = d.pending
    d.pending = nil
    if p and p.onCancel then p.onCancel() end
  end)
  d:Hide()
  return d
end
ES.ConfirmFrame = function() return confirm end -- (para pruebas)

function ES:Confirm(opts)
  -- Aviso apagado (casilla "No volver a mostrar" u opción): se hace sin preguntar.
  -- (opts.noCheck: siempre se pregunta)
  if not opts.noCheck and self.db and opts.key and self.db[opts.key] then
    opts.onYes()
    return
  end
  local d = ConfirmDialog()
  d.pending = opts
  d.title:SetText(opts.title)
  d.text:SetText(opts.text)
  d.warn:SetText(opts.warn or "")
  if opts.warn then d.warn:Show() else d.warn:Hide() end
  local extra = (opts.warn and WARN_H or 0) + (opts.extra or 0) -- (opts.extra: texto más largo)
  local withCheck = not opts.noCheck
  d:SetHeight((withCheck and 170 or 130) + extra)
  d.check:SetShown(withCheck)
  d.checkLabel:SetShown(withCheck)
  d.note:SetShown(withCheck)
  d.check:ClearAllPoints()
  d.check:SetPoint("TOPLEFT", 24, -78 - extra)
  d.check:SetChecked(false)
  d.checkLabel:SetText(L["No volver a mostrar este aviso"])
  d.note:SetText(withCheck and string.format(L["Se vuelve a activar en /cj opciones (%s)."],
    ES.OptionLabel and ES.OptionLabel(opts.key) or opts.key) or "")
  d.ok:SetText(opts.yes or YES or L["Sí"])
  d.cancel:SetText(opts.no or NO or L["No"])
  d:Show()
end