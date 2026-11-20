local _, ES = ...
local L = ES.L

---------------------------------------------------------------------------
-- Categoría Pestañas de las opciones (Options.lua): una fila por pestaña de la ventana
-- principal, en su orden, con la paleta de las filas de las rutas. Se reordenan
-- arrastrando una fila o con sus flechas (salen al pasar el ratón). Con Ocultar, un
-- clic en una fila la oculta o la vuelve a mostrar, como el diario de mazmorras, hasta
-- pulsar Hecho. La de arriba (la primera visible) es la que se abre al abrir el addon.
-- Qué se guarda y cómo se aplica: ES.Tabs (UI.lua)
---------------------------------------------------------------------------
local ROW_H, ROW_GAP = 34, 3
local STATUS_H = 26 -- línea de avisos bajo la lista
local GOLD = { 0.96, 0.79, 0.25 }
local ORANGE = { 1, 0.6, 0.2 }
local READY = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t"

-- Desplazamiento del borde de arriba de la fila i (o del hueco i) desde el de la página
local function RowTop(i) return -(i - 1) * (ROW_H + ROW_GAP) end

local function TabIcon(t) return t.icon == "skills" and ES.SKILLS_ICON or t.icon end

-- Posición del ratón en las coordenadas de `frame` (cuenta la escala de la ventana de
-- opciones, que se amplía con su esquina)
local function Cursor(frame)
  local x, y = GetCursorPosition()
  local s = frame:GetEffectiveScale() or 1
  return x / s, y / s
end

local function ArrowButton(row, name)
  local b = CreateFrame("Button", nil, row)
  b:SetSize(22, 22)
  b:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-" .. name .. "-Up")
  b:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-" .. name .. "-Down")
  b:SetDisabledTexture("Interface\\ChatFrame\\UI-ChatIcon-" .. name .. "-Disabled")
  b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  b:Hide()
  return b
end

local function CreateRow(page, i)
  local row = CreateFrame("Button", nil, page, "BackdropTemplate")
  row:SetHeight(ROW_H)
  row:SetPoint("TOPLEFT", 0, RowTop(i))
  row:SetPoint("TOPRIGHT", 0, RowTop(i))
  ES.UI.RowStyle(row)
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(26, 26)
  row.icon:SetPoint("LEFT", 6, 0)
  row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  row.name = ES.UI.Label(row, "", "GameFontNormal")
  row.name:SetPoint("LEFT", 40, 0)
  row.name:SetPoint("RIGHT", row, "RIGHT", -56, 0)
  row.name:SetJustifyH("LEFT")
  row.name:SetWordWrap(false)
  row.up = ArrowButton(row, "ScrollUp")
  row.up:SetPoint("RIGHT", -28, 0)
  row.down = ArrowButton(row, "ScrollDown")
  row.down:SetPoint("RIGHT", -6, 0)
  -- Oculta: icono en gris, textos apagados, una capa oscura y «OCULTA» grande encima
  row.shade = row:CreateTexture(nil, "ARTWORK", nil, 7)
  row.shade:SetPoint("TOPLEFT", 2, -2)
  row.shade:SetPoint("BOTTOMRIGHT", -2, 2)
  row.shade:SetColorTexture(0, 0, 0, 0.5)
  row.hiddenText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  row.hiddenText:SetPoint("CENTER")
  row.hiddenText:SetTextColor(1, 1, 1)

  local function ShowArrows(on)
    on = on and not page.hideMode and not page.dragRow
    row.up:SetShown(on)
    row.down:SetShown(on)
  end
  local function Leave()
    if not row:IsMouseOver() then ShowArrows(false) end
  end
  row.ShowArrows = ShowArrows

  row:RegisterForDrag("LeftButton")
  row:SetScript("OnClick", function(self)
    if page.hideMode then page:ToggleHidden(self.key) end
  end)
  row:SetScript("OnDragStart", function(self) page:StartDrag(self) end)
  row:SetScript("OnDragStop", function() page:StopDrag(true) end)
  row:SetScript("OnEnter", function(self)
    self:SetBackdropBorderColor(unpack(ES.UI.ROW_BORDER_HOVER))
    ShowArrows(true)
    local t = ES.Tabs.Info(self.key)
    if not t or page.dragRow then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(t.label)
    if page.hideMode then
      GameTooltip:AddLine(self.hidden and L["Clic: volver a mostrarla."] or L["Clic: ocultarla."], 0.5, 0.8, 1, true)
    else
      GameTooltip:AddLine(t.desc, 0.8, 0.8, 0.8, true)
      GameTooltip:AddLine(L["Arrastra la fila para cambiar el orden. La de arriba es la que se abre al abrir el addon."], 0.5, 0.8, 1, true)
    end
    GameTooltip:Show()
  end)
  row:SetScript("OnLeave", function(self)
    self:SetBackdropBorderColor(unpack(ES.UI.ROW_BORDER))
    GameTooltip:Hide()
    Leave()
  end)
  for _, b in ipairs({ row.up, row.down }) do
    b:SetScript("OnEnter", function() ShowArrows(true) end)
    b:SetScript("OnLeave", Leave)
  end
  row.up:SetScript("OnClick", function() page:MoveRow(row.index, row.index - 1) end)
  row.down:SetScript("OnClick", function() page:MoveRow(row.index, row.index + 1) end)
  return row
end

-- Botón Ocultar/Hecho, en la línea del título de la categoría (Options.lua lo enseña
-- solo con esta categoría elegida)
local function CreateHeader(page, body)
  local header = CreateFrame("Frame", nil, body)
  header:SetSize(100, 24)
  header:SetPoint("TOPRIGHT", -14, -10)
  header.hide = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
  header.hide:SetSize(100, 22)
  header.hide:SetPoint("RIGHT", 0, 0)
  header.hide:SetScript("OnClick", function() page:SetHideMode(not page.hideMode) end)
  local function Tip(b, text)
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:AddLine(text(), 1, 1, 1, true)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  Tip(header.hide, function()
    if page.hideMode then return L["Vuelve a poder ordenar las pestañas."] end
    return L["Elige qué pestañas no se ven: clic en cada una y luego Hecho. Su página sigue abriéndose desde la AH o el asistente de ruta."]
  end)
  header:Hide()
  return header
end

-- Fila «fantasma» que sigue al ratón al arrastrar, y la línea dorada de dónde caerá
local function CreateDragParts(page)
  local g = CreateFrame("Frame", nil, page, "BackdropTemplate")
  g:SetSize(220, ROW_H)
  ES.UI.RowStyle(g)
  g:SetBackdropBorderColor(unpack(ES.UI.ROW_BORDER_HOVER))
  g:SetFrameStrata("TOOLTIP")
  g:SetAlpha(0.9)
  g.icon = g:CreateTexture(nil, "ARTWORK")
  g.icon:SetSize(26, 26)
  g.icon:SetPoint("LEFT", 6, 0)
  g.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  g.name = ES.UI.Label(g, "", "GameFontNormal")
  g.name:SetPoint("LEFT", 40, 0)
  g.name:SetPoint("RIGHT", -8, 0)
  g.name:SetJustifyH("LEFT")
  g.name:SetWordWrap(false)
  g:Hide()
  page.ghost = g
  local line = page:CreateTexture(nil, "OVERLAY")
  line:SetHeight(2)
  line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
  line:Hide()
  page.dropLine = line
end

function ES:CreateTabsOptionsPage(window, parent, width)
  local page = CreateFrame("Frame", nil, parent)
  page:SetSize(width, 1)
  page.rows = {}
  page.header = CreateHeader(page, window.body)
  page.status = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  page.status:SetJustifyH("LEFT")
  page.status:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3])
  CreateDragParts(page)

  -- Un aviso bajo la lista (nada: lo quita)
  function page:Notice(text)
    self.status:SetText(text or "")
  end

  -- Filas en el orden de ES.Tabs, con su aspecto (oculta, flechas)
  function page:Refresh()
    local T = ES.Tabs
    local order = T.Order()
    for i, key in ipairs(order) do
      local row = self.rows[i] or CreateRow(self, i)
      self.rows[i] = row
      local t = T.Info(key)
      row.key, row.index = key, i
      row.iconPath = TabIcon(t)
      row.icon:SetTexture(row.iconPath)
      row.name:SetText(t.label)
      local hidden = T.IsHidden(key)
      row.hidden = hidden
      row.icon:SetDesaturated(hidden)
      row.name:SetAlpha(hidden and 0.45 or 1)
      row.shade:SetShown(hidden)
      row.hiddenText:SetText(L["OCULTA"])
      row.hiddenText:SetShown(hidden)
      row.up:SetEnabled(i > 1)
      row.down:SetEnabled(i < #order)
      if self.hideMode then row.ShowArrows(false) end
      row:SetAlpha(row == self.dragRow and 0.4 or 1)
      row:Show()
    end
    for i = #order + 1, #self.rows do self.rows[i]:Hide() end
    self.status:ClearAllPoints()
    self.status:SetPoint("TOPLEFT", 6, RowTop(#order + 1) - 4)
    self.status:SetPoint("RIGHT", self, "RIGHT", -6, 0)
    self:SetHeight(#order * (ROW_H + ROW_GAP) + STATUS_H)
    self.header.hide:SetText(self.hideMode and (L["Hecho"] .. " " .. READY) or L["Ocultar"])
  end

  function page:MoveRow(from, to)
    if self.hideMode then return end
    if ES.Tabs.Move(from, to) then
      self:Notice(nil)
      self:Refresh()
    end
  end

  -- Modo de ocultar (on) o el normal: el clic en una fila la oculta o la muestra
  function page:SetHideMode(on)
    self:CancelDrag()
    self.hideMode = on and true or nil
    self:Notice(nil)
    self:Refresh()
  end

  function page:ToggleHidden(key)
    local hide = not ES.Tabs.IsHidden(key)
    local ok, why = ES.Tabs.SetHidden(key, hide)
    if not ok and why == "last" then
      self:Notice(L["Tiene que quedar al menos una pestaña visible."])
    elseif ok and hide and key == "shopping" then
      self:Notice(L["Lista de compra oculta: ya no tiene pestaña ni brilla al añadirle algo. La lista junto a la Casa de Subastas y la ventana del vendedor siguen igual."])
    else
      self:Notice(nil)
    end
    self:Refresh()
  end

  -- Arrastrar ----------------------------------------------------------------
  -- Hueco en el que caería la fila con el ratón donde está, y si está sobre la lista
  -- (con media fila de margen arriba y abajo)
  function page:DropAt()
    local x, y = Cursor(self)
    local top, left, right = self:GetTop(), self:GetLeft(), self:GetRight()
    if not (top and left and right) then return nil end
    local n = #ES.Tabs.Order()
    local mids = {}
    for i = 1, n do mids[i] = top + RowTop(i) - ROW_H / 2 end
    local slack = ROW_H / 2
    local inside = x >= left and x <= right and y <= top + slack and y >= top + RowTop(n + 1) - slack
    return ES.Tabs.DropIndex(y, mids), inside, x, y
  end

  function page:UpdateDrag()
    local gap, inside, x, y = self:DropAt()
    if x then
      self.ghost:ClearAllPoints()
      -- (el fantasma es hijo de la página: sus desplazamientos van en su misma escala)
      self.ghost:SetPoint("LEFT", UIParent, "BOTTOMLEFT", x - 18, y)
    end
    local line = self.dropLine
    if gap and inside then
      local off = RowTop(gap) + math.floor(ROW_GAP / 2) + 1
      line:ClearAllPoints()
      line:SetPoint("TOPLEFT", 0, off)
      line:SetPoint("TOPRIGHT", 0, off)
      line:Show()
    else
      line:Hide()
    end
  end

  function page:StartDrag(row)
    if self.hideMode or self.dragRow or not row.key then return end
    self.dragRow = row
    row:SetAlpha(0.4)
    row.ShowArrows(false)
    GameTooltip:Hide()
    self.ghost.icon:SetTexture(row.iconPath)
    self.ghost.name:SetText(ES.Tabs.Info(row.key).label)
    self.ghost:Show()
    self.ghost:SetScript("OnUpdate", function() self:UpdateDrag() end)
    self:UpdateDrag()
  end

  -- Suelta la fila: commit = soltarla de verdad (dentro de la lista, la mueve); si no
  -- (o fuera de la lista), todo como estaba
  function page:StopDrag(commit)
    local row = self.dragRow
    if not row then return end
    local gap, inside = self:DropAt()
    self.dragRow = nil
    row:SetAlpha(1)
    self.ghost:SetScript("OnUpdate", nil)
    self.ghost:Hide()
    self.dropLine:Hide()
    if commit and gap and inside then
      self:MoveRow(row.index, ES.Tabs.GapToIndex(row.index, gap))
    end
  end

  function page:CancelDrag() self:StopDrag(false) end

  -- Al cambiar de categoría o cerrar la ventana: sin arrastre a medias, vuelta al modo
  -- normal y sin avisos
  local function Leave()
    page:CancelDrag()
    page.hideMode = nil
    page:Notice(nil)
  end
  page:SetScript("OnHide", Leave)
  window:HookScript("OnHide", Leave)
  return page
end
