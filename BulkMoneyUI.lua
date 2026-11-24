local _, ES = ...
local L = ES.L

-- Pestaña BulkMoney (nombre provisional): fabricar en cantidad para vender al vendedor
-- (Earn:VendorShuffle). Cada fila es una hora de fabricar y su cifra, el oro por hora,
-- de más a menos (ES.UI.BulkMoneyLine, EarnUI.lua); también dice para cuántas horas hay
-- material barato en la AH. Lo que se compra al vendedor va
-- con el descuento de tu reputación con tu capital y, con la casilla, el de Bartering
-- (talento de legado, -10%; por ahora una casilla: ES.db.bulkBartering).

local GREY, ORANGE, GOLD, GREEN = "|cff999999", "|cffff9933", "|cffffd100", "|cff40ff40"
local HEAD_H, STATUS_GAP, LIST_GAP = 70, 6, 30

function ES:CreateBulkMoneyPage(page)
  local Label = ES.UI.Label
  local head = ES.UI.CardHead(page, HEAD_H)
  local icon = head:CreateTexture(nil, "ARTWORK")
  icon:SetSize(44, 44)
  icon:SetPoint("LEFT", 12, 0)
  icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_03")
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  local name = Label(head, L["BulkMoney"], "GameFontNormalHuge")
  name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, 4)
  name:SetTextColor(0.96, 0.79, 0.25)
  page.subtitle = Label(head, L["Recetas de todas las profesiones (las sepas o no) que dejan beneficio vendiendo lo fabricado al vendedor. Cada fila es una hora de fabricar y su cifra, el oro por hora."], "GameFontHighlightSmall")
  page.subtitle:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
  page.subtitle:SetPoint("RIGHT", -230, 0)
  page.subtitle:SetJustifyH("LEFT")

  -- Bartering (talento de legado): por ahora se marca a mano
  local barter = CreateFrame("CheckButton", nil, head, "UICheckButtonTemplate")
  barter:SetSize(24, 24)
  barter:SetPoint("RIGHT", -190, 12)
  barter.label = Label(head, L["Bartering (-10% en vendedores)"], "GameFontHighlightSmall")
  barter.label:SetPoint("LEFT", barter, "RIGHT", 2, 1)
  barter:SetScript("OnClick", function(self)
    ES.db.bulkBartering = self:GetChecked() and true or nil
    ES:RenderBulkMoney()
  end)
  barter:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    GameTooltip:AddLine("Bartering", 1, 0.82, 0)
    GameTooltip:AddLine(L["Talento de legado, rango 2/2: los vendedores te cobran un 10% menos. Márcalo si lo tienes: lo que se compra al vendedor sale más barato."], 1, 1, 1, true)
    GameTooltip:Show()
  end)
  barter:SetScript("OnLeave", function() GameTooltip:Hide() end)
  page.barter = barter

  -- Botón de anunciar (BulkPostUI.lua): abre o cierra el marco flotante
  local postButton = CreateFrame("Button", nil, head, "UIPanelButtonTemplate")
  postButton:SetSize(170, 22)
  postButton:SetPoint("TOPLEFT", barter, "BOTTOMLEFT", 2, -4)
  postButton:SetScript("OnClick", function() if ES.BulkPost then ES.BulkPost.Toggle() end end)
  postButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    GameTooltip:AddLine(self:GetText() or "", 1, 0.82, 0)
    GameTooltip:AddLine(L["Un botón flotante, como el del asistente: pones un objeto y un precio, y cada clic anuncia 1 unidad en la AH a ese precio."], 1, 1, 1, true)
    GameTooltip:Show()
  end)
  postButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
  page.postButton = postButton

  page.status = Label(page, "", "GameFontHighlightSmall")
  page.status:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 6, -STATUS_GAP)
  page.status:SetPoint("RIGHT", head, "RIGHT", -6, 0)
  page.status:SetJustifyH("LEFT")

  local list = ES.UI.ListPanel(page, head, LIST_GAP)
  page.head, page.list = head, list
  local scroll = ES.UI.WheelScroll(list)
  scroll:SetPoint("TOPLEFT", 8, -8)
  scroll:SetPoint("BOTTOMRIGHT", -8, 8)
  page.scroll = scroll
  page.content = CreateFrame("Frame", nil, scroll)
  page.content:SetSize(ES.UI.LIST_WIDTH, 1)
  scroll:SetScrollChild(page.content)
  page.rows = {}

  -- Casilla para escribir tu precio de un material (una para todas las filas: se pone
  -- encima de la que pulsas). Como en la Calculadora: "6.5" = 6s 50c, "1g 20s"; vacía
  -- vuelve al de la AH; Escape no cambia nada
  local box = CreateFrame("EditBox", nil, page.content, "InputBoxTemplate")
  box:SetSize(110, 20)
  box:SetAutoFocus(false)
  box:SetFrameLevel((page.content:GetFrameLevel() or 1) + 10)
  box:Hide()
  local function Save()
    if not box:IsShown() or not box.itemID then return end
    local text = strtrim(box:GetText() or "")
    local copper = ES.Calc.ParseMoney(text)
    local id = box.itemID
    box.itemID = nil
    box:Hide()
    -- (lo que no se entiende no cambia nada; vacío = el de la AH)
    if text == "" or copper then ES.Earn.SetBulkPrice(id, copper) end
    ES:RenderBulkMoney()
  end
  box:SetScript("OnEnterPressed", function(self) Save() self:ClearFocus() end)
  box:SetScript("OnEditFocusLost", Save)
  box:SetScript("OnEscapePressed", function(self)
    self.itemID = nil
    self:Hide()
    self:ClearFocus()
  end)
  page.priceBox = box
  -- Abre la casilla sobre la fila `row` para el material `itemID`
  function page.EditPrice(row, itemID)
    box.itemID = itemID
    box:ClearAllPoints()
    box:SetPoint("RIGHT", row, "RIGHT", -12, 0)
    local current = ES.Earn.BulkPrice(itemID)
    box:Show()
    box:SetText(current and ES.Calc.FormatMoney(current) or "")
    box:SetFocus()
    box:HighlightText()
  end

  page.empty = Label(page.content, "", "GameFontDisable")
  page.empty:SetPoint("TOP", 0, -30)
  page.empty:SetWidth(600)

  ES.SafeRegister(page, "GET_ITEM_INFO_RECEIVED")
  page:SetScript("OnEvent", function(self, _, itemID)
    if ES.UI.WaitingForItem(self, itemID) and not self.refreshQueued and self:IsVisible() then
      self.refreshQueued = true
      C_Timer.After(0.5, function()
        self.refreshQueued = false
        if self:IsVisible() then ES:RenderBulkMoney() end
      end)
    end
  end)
  page:SetScript("OnShow", function() ES:RenderBulkMoney() end)
  self.bulkPage = page
end

function ES:RenderBulkMoney()
  local page = self.bulkPage
  if not page or not page:IsVisible() then return end
  page.barter:SetChecked(ES.db.bulkBartering and true or false)
  page.postButton:SetText(ES.BulkPost and ES.BulkPost.IsShown() and L["Cerrar botón de anunciar"] or L["Botón de anunciar"])
  local res = ES.Earn:VendorShuffle()

  -- Estado: el escaneo y el descuento que se aplica
  local parts = {}
  if not res.scanTime then
    parts[#parts + 1] = ORANGE .. L["Sin escaneo de la AH: escanea para ver qué da beneficio.|r"]
  else
    local age = time() - res.scanTime
    parts[#parts + 1] = age > ES.Earn.OLD_SCAN
      and (ORANGE .. string.format(L["Precios de hace %d h: escanea antes de fabricar.|r"], math.floor(age / 3600)))
      or (GREY .. string.format(L["Precios de la AH de hace %d min"], math.floor(age / 60)) .. "|r")
  end
  local d = {}
  if res.city > 0 then d[#d + 1] = string.format("%s -%d%%", res.cityName or "?", math.floor(res.city * 100 + 0.5)) end
  if res.bartering then d[#d + 1] = string.format("%s -%d%%", "Bartering", math.floor(ES.Earn.BARTERING * 100 + 0.5)) end
  parts[#parts + 1] = GREY .. (#d > 0 and string.format(L["vendedores: %s"], table.concat(d, ", "))
    or L["vendedores sin descuento"]) .. "|r"
  page.status:SetText(table.concat(parts, GREY .. ES.SEP .. "|r"))

  -- Una sola lista: cada receta, una hora de fabricar; en su fila, también para cuántas
  -- horas hay en la AH por debajo del precio máximo (Earn.StockFor). (Una sección aparte
  -- para eso, con otra cifra de oro para la misma receta, confundía)
  local lines = {}
  for i = 1, math.min(#res.list, ES.Earn.SHUFFLE_MAX) do lines[#lines + 1] = ES.UI.BulkMoneyLine(res.list[i]) end
  -- Con gangas (Earn:BulkBargains): hoy no dejan nada, pero sí comprando sus materiales por
  -- debajo del objetivo, y cuántas veces ha pasado en tu historial. Clic, con la AH
  -- abierta: buscar el material
  local bargains = res.scanTime and ES.Earn:BulkBargains() or { list = {} }
  if #bargains.list > 0 then
    lines[#lines + 1] = { section = L["Con gangas: rentables comprando por debajo de este precio"] }
    for _, b in ipairs(bargains.list) do
      local e = b.e
      local name, texture = ES.UI.ItemLabel(e.itemID, e.recipe.name)
      local parts = {}
      for _, m in ipairs(b.mats) do
        local mname = ES.UI.ItemLabel(m.itemID, "#" .. m.itemID)
        parts[#parts + 1] = m.target > 0 and string.format(L["%s hasta %s"], mname or "", ES.Money(math.floor(m.target)))
          or (GREY .. string.format(L["%s a lo de hoy"], mname or "") .. "|r")
      end
      local top = b.mats[1]
      local freq = top.medBelow > 0 and (GREEN .. string.format(L["suele estar así (%d de %d escaneos)"], top.medBelow, bargains.scans) .. "|r")
        or string.format(L["gangas sueltas (%d de %d escaneos)"], top.minBelow, bargains.scans)
      lines[#lines + 1] = {
        icon = texture or 134400, item = e.itemID, title = name or e.recipe.name,
        sub = ES:ProfLabel(b.profKey) .. ES.SEP .. table.concat(parts, ", ") .. GREY .. ES.SEP .. "|r" .. freq,
        value = GREEN .. "+" .. string.format(L["hasta %s/fab"], ES.Money(math.floor(b.best))) .. "|r",
        onClick = ES.ahOpen and function() ES:SearchAuction(top.itemID) end or nil,
        tooltip = function(row)
          GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
          GameTooltip:AddLine(name or e.recipe.name, 1, 0.82, 0)
          GameTooltip:AddLine(string.format(L["Hoy no deja nada vendiéndola al vendedor (%s por fabricación); deja si compras sus materiales por debajo de estos precios (cada uno, con los demás a lo de hoy)."],
            ES.Money(math.floor(b.sale))), 1, 1, 1, true)
          GameTooltip:AddLine(" ")
          for _, m in ipairs(b.mats) do
            GameTooltip:AddLine((ES.UI.ItemLabel(m.itemID, "#" .. m.itemID)), 1, 0.82, 0)
            GameTooltip:AddDoubleLine(L["Objetivo"], m.target > 0 and ES.Money(math.floor(m.target)) or "-", 0.8, 0.8, 0.8, 1, 1, 1)
            GameTooltip:AddDoubleLine(L["Hoy"], string.format("%s (%d)", ES.Money(math.floor(m.now + 0.5)), m.onSale), 0.8, 0.8, 0.8, 1, 1, 1)
            if m.low then GameTooltip:AddDoubleLine(L["Lo más barato visto"], ES.Money(m.low), 0.8, 0.8, 0.8, 1, 1, 1) end
            GameTooltip:AddDoubleLine(L["Escaneos con el mínimo por debajo"], string.format("%d / %d", m.minBelow, bargains.scans), 0.8, 0.8, 0.8, 1, 1, 1)
            GameTooltip:AddDoubleLine(L["Escaneos con la mediana por debajo"], string.format("%d / %d", m.medBelow, bargains.scans), 0.8, 0.8, 0.8, 1, 1, 1)
          end
          GameTooltip:AddLine(" ")
          GameTooltip:AddLine(L["La mediana por debajo: suele estar así de barato, con volumen. Solo el mínimo: gangas sueltas, a veces una sola unidad; el objetivo te sirve de precio máximo para cazarlas."], 0.8, 0.8, 0.8, true)
          GameTooltip:AddLine(L["La cifra: lo que dejaría cada fabricación con lo más barato visto."], 0.8, 0.8, 0.8, true)
          if ES.ahOpen then GameTooltip:AddLine(L["Clic: buscarlo en la AH."], 0.5, 0.8, 1, true) end
          GameTooltip:Show()
        end,
      }
    end
  end
  -- Materiales de esas recetas: clic para poner tu precio (Earn.SetBulkPrice), como en la
  -- Calculadora. Con el tuyo, en dorado «a mano» y, al lado, el de la AH
  local mats = ES.Earn.BulkMaterials(res)
  if #mats > 0 and res.scanTime then
    lines[#lines + 1] = { section = L["Materiales: clic para poner tu precio"] }
    for _, m in ipairs(mats) do
      local name, texture = ES.UI.ItemLabel(m.itemID, L["Objeto "] .. m.itemID)
      local where = m.source == "vendor" and string.format(L["vendedor %s/u"], ES.Money(math.floor((m.unit or 0) + 0.5)))
        or m.ah and string.format(L["AH %s/u"], ES.Money(m.ah)) or (GREY .. L["sin precio"] .. "|r")
      local sub = m.mine and (GOLD .. L["a mano"] .. "|r" .. GREY .. ES.SEP .. "|r" .. where) or where
      local index = #lines + 1
      local id = m.itemID
      lines[index] = {
        icon = texture or 134400, item = id, title = name or ("#" .. id), sub = sub,
        value = (m.mine or m.unit) and ES.Money(math.floor((m.mine or m.unit) + 0.5)) .. "/u" or "",
        onClick = function() if page.rows[index] then page.EditPrice(page.rows[index], id) end end,
        tooltip = function(row)
          GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
          GameTooltip:AddLine(name or "", 1, 0.82, 0)
          if m.mine then GameTooltip:AddDoubleLine(L["Tu precio"], ES.Money(m.mine), 1, 0.82, 0.25, 1, 1, 1) end
          if m.ah then GameTooltip:AddDoubleLine(L["La más barata en la AH"], ES.Money(m.ah), 0.8, 0.8, 0.8, 1, 1, 1) end
          GameTooltip:AddLine(" ")
          GameTooltip:AddLine(L["Clic: escribir el precio por unidad"], 0.5, 0.8, 1)
          GameTooltip:AddLine(L["Con tu precio, BulkMoney cuenta que compras todos los que quieras a ese precio (por ejemplo, lo que te cuesta farmearlo). Vacío vuelve al de la AH."], 0.8, 0.8, 0.8, true)
          GameTooltip:Show()
        end,
      }
    end
  end
  -- Recetas quitadas con la ✕: clic para volver a tenerlas todas en cuenta (como en
  -- Ganar dinero, pero su propia lista)
  local removed = ES.Earn.HiddenList(true)
  if #removed > 0 then
    lines[#lines + 1] = {
      icon = "Interface\\Buttons\\UI-RefreshButton", iconSize = 16,
      title = string.format(L["Recetas quitadas de BulkMoney: %d"], #removed),
      sub = L["Clic para volver a tenerlas en cuenta"],
      onClick = function()
        for _, r in ipairs(removed) do ES.Earn.SetBulkHidden(r.id, false) end
        ES:RenderBulkMoney()
      end,
      tooltip = function(row)
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Quitadas de BulkMoney"])
        for _, r in ipairs(removed) do GameTooltip:AddLine(r.name, 0.8, 0.8, 0.8) end
        GameTooltip:AddLine(L["Clic para volver a tenerlas en cuenta"], 0.5, 0.8, 1)
        GameTooltip:Show()
      end,
    }
  end
  page.empty:SetText(#lines == 0 and (not res.scanTime and L["Escanea la AH para ver qué da beneficio."]
    or L["Ninguna receta deja beneficio vendiéndola al vendedor con los precios de este escaneo."]) or "")
  ES.UI.RenderLines(page, lines)
end
