local _, ES = ...
local L = ES.L

-- Cabecera del panel: buscador (profesiones y recetas) a la izquierda, título
-- en el centro, selector de idioma a la derecha y botón de cerrar.

local GOLD = { 0.96, 0.79, 0.25 }
local MAX_RESULTS = 8


local function SetBackdrop(frame, edgeSize, inset)
  frame:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = edgeSize,
    insets = { left = inset, right = inset, top = inset, bottom = inset },
  })
end

---------------------------------------------------------------------------
-- Búsqueda
---------------------------------------------------------------------------
-- Profesiones (por su nombre) y recetas que fabrican algo (por el nombre de la
-- receta o del objeto, si el juego ya lo tiene cargado)
local function Search(query)
  local results = {}
  query = query:lower()
  for _, prof in ipairs(ES.PROFESSIONS) do
    local label = ES:ProfLabel(prof.key)
    if ES.Data[prof.key] and (label:lower():find(query, 1, true) or prof.key:lower():find(query, 1, true)) then
      results[#results + 1] = { kind = "prof", profKey = prof.key, text = label, icon = prof.icon }
    end
  end
  for _, prof in ipairs(ES.PROFESSIONS) do
    local data = ES.Data[prof.key]
    for id, r in pairs(data and data.recipes or {}) do
      if #results >= 60 then break end
      if r.out and not r.intermediate and not r.conversion then
        local itemName, _, texture = ES:GetItemData(r.out[1])
        if (r.name or ""):lower():find(query, 1, true) or (r.nameEN or ""):lower():find(query, 1, true)
          or (itemName and itemName:lower():find(query, 1, true)) then
          results[#results + 1] = { kind = "recipe", profKey = prof.key, recipe = r, id = id,
            text = itemName or r.name, icon = texture or prof.icon, level = r.train or 1 }
        end
      end
    end
  end
  table.sort(results, function(a, b)
    if a.kind ~= b.kind then return a.kind == "prof" end
    if a.profKey ~= b.profKey then return a.profKey < b.profKey end
    return (a.level or 0) < (b.level or 0)
  end)
  return results
end

-- Abre la profesión del resultado; si es una receta, su ficha en la Colección
function ES:OpenSearchResult(result)
  if result.kind ~= "recipe" then
    self:SelectPage(result.profKey)
    return
  end
  local f = self:GetMainFrame()
  local page = f.pages["pattern:" .. result.profKey]
  if not page then return end
  local cf = page.collectionFrame
  cf.selectedID, cf.selected = result.id, nil
  self:SelectPage("pattern:" .. result.profKey)
  cf.search:SetText(result.recipe.name or "") -- la lista, filtrada por ella
  if cf.data then self:RenderCollection(cf) end
end

local function CreateSearch(f)
  local box = CreateFrame("EditBox", nil, f, "BackdropTemplate")
  f.globalSearch = box
  box:SetSize(265, 26)
  box:SetPoint("TOPLEFT", 18, -14)
  box:SetAutoFocus(false)
  box:SetMaxLetters(60)
  box:SetFontObject("GameFontHighlight")
  box:SetTextInsets(27, 22, 0, 0)
  SetBackdrop(box, 10, 3)
  box:SetBackdropColor(0.045, 0.043, 0.040, 0.98)
  box:SetBackdropBorderColor(0.34, 0.31, 0.27, 1)

  local icon = box:CreateTexture(nil, "ARTWORK")
  icon:SetSize(14, 14)
  icon:SetPoint("LEFT", 7, 0)
  icon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
  icon:SetVertexColor(0.72, 0.70, 0.66)

  local placeholder = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  placeholder:SetPoint("LEFT", 28, 0)
  placeholder:SetTextColor(0.48, 0.47, 0.44)
  placeholder:SetText(L["Buscar profesiones, recetas..."])

  local clear = CreateFrame("Button", nil, box)
  clear:SetSize(16, 16)
  clear:SetPoint("RIGHT", -5, 0)
  clear:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
  clear:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  clear:Hide()

  -- Lista de resultados bajo el buscador
  local list = CreateFrame("Frame", nil, f, "BackdropTemplate")
  f.searchResults = list
  list:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -3)
  list:SetWidth(340)
  list:SetFrameStrata("TOOLTIP")
  SetBackdrop(list, 10, 3)
  list:SetBackdropColor(0.045, 0.042, 0.037, 0.995)
  list:SetBackdropBorderColor(0.48, 0.40, 0.27, 1)
  list:Hide()
  list.rows, list.results = {}, {}

  local function Choose(result)
    list:Hide()
    box:SetText("")
    box:ClearFocus()
    ES:OpenSearchResult(result)
  end

  local function Row(i)
    local row = list.rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, list)
    row:SetHeight(22)
    row:SetPoint("TOPLEFT", 5, -5 - (i - 1) * 22)
    row:SetPoint("TOPRIGHT", -5, -5 - (i - 1) * 22)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", 4, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.text:SetJustifyH("LEFT")
    row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.sub:SetPoint("RIGHT", -6, 0)
    row.sub:SetJustifyH("RIGHT")
    row:SetScript("OnClick", function(self) if self.result then Choose(self.result) end end)
    list.rows[i] = row
    return row
  end

  local function Refresh()
    local text = strtrim(box:GetText() or "")
    placeholder:SetShown(text == "")
    clear:SetShown(text ~= "")
    if text:len() < 2 then list:Hide() return end
    local results = Search(text)
    list.results = results
    local shown = math.min(MAX_RESULTS, #results)
    for i = 1, shown do
      local r, row = results[i], Row(i)
      row.result = r
      row.icon:SetTexture(r.icon or ES.ICON)
      if r.kind == "prof" then
        row.text:SetText(r.text)
        row.text:SetTextColor(unpack(GOLD))
        row.sub:SetText(L["Profesión"])
      else
        row.text:SetText(r.text)
        row.text:SetTextColor(1, 1, 1)
        row.sub:SetText(string.format("%s · %d", ES:ProfLabel(r.profKey), r.level))
      end
      row:Show()
    end
    for i = shown + 1, #list.rows do list.rows[i]:Hide() end
    if shown == 0 then
      local row = Row(1)
      row.result = nil
      row.icon:SetTexture(nil)
      row.text:SetText(L["Sin resultados"])
      row.text:SetTextColor(0.5, 0.5, 0.5)
      row.sub:SetText("")
      row:Show()
      shown = 1
    end
    list:SetHeight(10 + shown * 22)
    list:Show()
  end

  box:SetScript("OnTextChanged", Refresh)
  box:SetScript("OnEnterPressed", function(self)
    local first = list.results[1]
    if list:IsShown() and first then Choose(first) else self:ClearFocus() end
  end)
  box:SetScript("OnEscapePressed", function(self)
    self:SetText("")
    self:ClearFocus()
    list:Hide()
  end)
  box:SetScript("OnEditFocusLost", function()
    -- Dejar tiempo a que llegue el clic en un resultado antes de cerrar la lista
    C_Timer.After(0.2, function() if not box:HasFocus() then list:Hide() end end)
  end)
  clear:SetScript("OnClick", function()
    box:SetText("")
    list:Hide()
  end)
end

---------------------------------------------------------------------------
-- Idioma
---------------------------------------------------------------------------
local function CreateLanguage(f)
  -- Idiomas en ES.LANGS (Locale.lua); cada uno con su nombre en su idioma
  local current = ES.lang
  local function Label(code)
    for _, l in ipairs(ES.LANGS) do if l.key == code then return l.name end end
    return ES.LANGS[1].name
  end

  local button = CreateFrame("Button", nil, f, "BackdropTemplate")
  f.languageButton = button
  button:SetSize(110, 24)
  button:SetPoint("TOPRIGHT", -49, -15)
  SetBackdrop(button, 12, 4)
  button:SetBackdropColor(0.12, 0.115, 0.105, 0.98)
  button:SetBackdropBorderColor(0.48, 0.40, 0.27, 1)
  button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

  local caret = button:CreateTexture(nil, "OVERLAY")
  caret:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
  caret:SetSize(12, 12)
  caret:SetPoint("RIGHT", -7, -3)

  local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  text:SetPoint("LEFT", 8, 0)
  text:SetPoint("RIGHT", -20, 0)
  text:SetJustifyH("CENTER")
  text:SetTextColor(1, 0.82, 0.27)
  text:SetText(Label(current))

  local menu = CreateFrame("Frame", nil, f, "BackdropTemplate")
  f.languageMenu = menu
  menu:SetSize(140, #ES.LANGS * 22 + 10)
  menu:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", 4, -4)
  menu:SetFrameStrata("TOOLTIP")
  SetBackdrop(menu, 12, 4)
  menu:SetBackdropColor(0.055, 0.05, 0.043, 0.99)
  menu:SetBackdropBorderColor(0.57, 0.43, 0.20, 1)
  menu:Hide()

  for i, lang in ipairs(ES.LANGS) do
    local option = CreateFrame("Button", nil, menu)
    option:SetPoint("TOPLEFT", 6, -5 - (i - 1) * 22)
    option:SetPoint("TOPRIGHT", -6, -5 - (i - 1) * 22)
    option:SetHeight(21)
    option:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    local label = option:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", 10, 0)
    label:SetText(lang.name)
    label:SetTextColor(0.95, 0.83, 0.53)
    option:SetScript("OnClick", function()
      menu:Hide()
      if lang.key ~= ES.lang then
        text:SetText(lang.name)
        ES:SetLanguage(lang.key) -- se aplica al momento: la ventana se vuelve a crear
      end
    end)
  end

  button:SetScript("OnClick", function() menu:SetShown(not menu:IsShown()) end)
  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(L["Idioma del addon"])
    GameTooltip:AddLine(L["Textos, recetas y objetos cambian al momento."], 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

---------------------------------------------------------------------------
-- Interruptor de desarrollo: solo existe en la copia de desarrollo (ES.DEV_BUILD).
-- "DEV" = se ve todo; "JUGADOR" = como lo verá quien se baje el addon.
---------------------------------------------------------------------------
local function CreateDevToggle(f)
  if not ES.DEV_BUILD then return end
  local b = CreateFrame("Button", nil, f, "BackdropTemplate")
  f.devToggle = b
  b:SetSize(84, 24)
  b:SetPoint("RIGHT", f.languageButton, "LEFT", -8, 0)
  SetBackdrop(b, 12, 4)
  b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.text:SetPoint("CENTER")
  if ES.DEV then
    b:SetBackdropColor(0.30, 0.10, 0.35, 0.98)
    b:SetBackdropBorderColor(0.75, 0.45, 0.90, 1)
    b.text:SetText("|cffe0a0ff" .. L["Modo DEV"] .. "|r")
  else
    b:SetBackdropColor(0.10, 0.22, 0.10, 0.98)
    b:SetBackdropBorderColor(0.45, 0.80, 0.40, 1)
    b.text:SetText("|cff90ff90" .. L["Vista jugador"] .. "|r")
  end
  b:SetScript("OnClick", function() ES:SetUserPreview(ES.DEV) end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(L["Modo desarrollo"])
    GameTooltip:AddLine(L["Solo en tu copia de desarrollo: la versión de CurseForge no tiene este botón."], 0.8, 0.8, 0.8, true)
    GameTooltip:AddLine(ES.DEV and L["Pulsa para ver el addon como lo verán los jugadores (sin Ganar dinero, Subastas, Pesca ni buscador)."]
      or L["Pulsa para volver al modo desarrollo (todo a la vista)."], 0.5, 0.8, 1, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

---------------------------------------------------------------------------
-- Cabecera completa
---------------------------------------------------------------------------
function ES:CreateHeader(f)
  -- Banda marrón con líneas doradas arriba y abajo
  local band = f:CreateTexture(nil, "BACKGROUND", nil, 1)
  band:SetPoint("TOPLEFT", 12, -10)
  band:SetPoint("TOPRIGHT", -12, -10)
  band:SetHeight(34)
  band:SetColorTexture(0.14, 0.10, 0.055, 0.96)
  for _, edge in ipairs({ { "TOPLEFT", "TOPRIGHT", 0.65 }, { "BOTTOMLEFT", "BOTTOMRIGHT", 0.45 } }) do
    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetPoint(edge[1], band, edge[1], 0, 0)
    line:SetPoint(edge[2], band, edge[2], 0, 0)
    line:SetHeight(1)
    line:SetColorTexture(0.68, 0.52, 0.20, edge[3])
  end

  -- Título y botón de escanear, centrados juntos en la cabecera
  local SCAN_W, GAP = 120, 12
  local group = CreateFrame("Frame", nil, f)
  f.title = group:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  f.title:SetText("Crafter's Journal")
  f.title:SetTextColor(unpack(GOLD))
  f.title:SetPoint("LEFT", group, "LEFT", 0, 0)
  group:SetSize(math.ceil(f.title:GetStringWidth()) + GAP + SCAN_W, 24)
  group:SetPoint("TOP", f, "TOP", 0, -15)

  -- Escanear la AH: desde cualquier pestaña; en gris si la AH está cerrada.
  -- Mientras escanea, el botón muestra el % de progreso (ver RefreshScanButtons)
  local scan = CreateFrame("Button", nil, group, "UIPanelButtonTemplate")
  scan:SetSize(SCAN_W, 22)
  scan:SetPoint("LEFT", f.title, "RIGHT", GAP, 0)
  scan:SetText(L["Escanear"])
  scan:SetMotionScriptsWhileDisabled(true) -- el tooltip explica por qué está gris
  scan:SetScript("OnClick", function() ES.Scanner:Start() end)
  scan:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(L["Escanear la Casa de Subastas"])
    local wait = ES.Scanner:SecondsUntilNextScan()
    if ES.Scanner:IsBusy() then
      GameTooltip:AddLine(L["Escaneo en curso."], 0.8, 0.8, 0.8, true)
    elseif wait > 0 then
      GameTooltip:AddLine(string.format(L["El servidor solo permite un escaneo completo cada 15 min: podrás volver a escanear en %s."],
        ES.Countdown(wait)), 1, 0.6, 0.2, true)
    elseif not ES:IsAuctionHouseOpen() then
      GameTooltip:AddLine(L["Abre la Casa de Subastas para poder escanearla."], 1, 0.6, 0.2, true)
    else
      GameTooltip:AddLine(L["Descarga todas las subastas y actualiza precios, rutas y alertas."], 0.8, 0.8, 0.8, true)
    end
    GameTooltip:Show()
  end)
  scan:SetScript("OnLeave", function() GameTooltip:Hide() end)
  scan:SetEnabled(false)
  f.scanButton = scan

  -- "Último escaneo: hace 3 min", en pequeño junto al botón; se actualiza cada 30 s
  f.lastScan = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.lastScan:SetPoint("LEFT", scan, "RIGHT", 8, 0)
  f.lastScan:SetWidth(140)
  f.lastScan:SetJustifyH("LEFT")
  f.lastScan:SetWordWrap(false)
  local ticker = CreateFrame("Frame", nil, f)
  ticker.elapsed = 0
  ticker:SetScript("OnUpdate", function(self, delta)
    self.elapsed = self.elapsed + (delta or 0)
    if self.elapsed < 30 then return end
    self.elapsed = 0
    ES:UpdateLastScan()
  end)

  CreateSearch(f)
  if not ES.DEV then f.globalSearch:Hide() end -- buscador: solo en modo desarrollo (no en la 1.0)
  CreateLanguage(f)
  CreateDevToggle(f)

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -3, -3)
  f.closeButton = close
end
