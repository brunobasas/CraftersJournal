local _, ES = ...
local L = ES.L

-- Al abrir la Casa de Subastas sale al lado una ventana (como la del vendedor,
-- VendorUI.lua) con lo que la pestaña Inventario dice que vendas en la AH: cuántos,
-- a cuánto y lo que te queda tras la comisión. Clic en una fila: anuncia todas las
-- de la fila; Mayús+clic, solo una (un anuncio por clic: la AH pide un clic del
-- jugador para cada uno). Clic derecho: no venderlo nunca. Va pegada a la AH, y la
-- lista de compra pequeña, si sale, a su derecha. Con la ventana grande al lado de la AH no sale (ya tienes el
-- Inventario ahí).

local Sell = {}
ES.AuctionSell = Sell

local ROW_H, MAX_ROWS = 34, 12
local WIDTH = 300
local COST_W = 74 -- columna del valor a la derecha (hasta "99g 99s 99c")
local GREEN, GREY = "|cff40ff40", "|cff999999"

local panel

-- EXACTAMENTE las secciones de AH de la pestaña Inventario ("Ha subido" y "Vender en
-- la Casa de Subastas", Inventory:Sections), lo que más deja arriba: { e de Inventory:List }
function Sell:List()
  local list = {}
  if not ES.Inventory then return list end
  local ok, sec = pcall(ES.Inventory.Sections, ES.Inventory)
  if not ok then return list end
  for _, e in ipairs(sec.rising) do list[#list + 1] = e end
  for _, e in ipairs(sec.ah) do list[#list + 1] = e end
  table.sort(list, function(a, b)
    local va, vb = a.ahN * (a.ahUnit or 0), b.ahN * (b.ahUnit or 0)
    return va > vb or (va == vb and a.itemID < b.itemID)
  end)
  return list
end

local function AHFrame()
  return AuctionHouseFrame or AuctionFrame
end

local function RowClick(self, button)
  local e = self.entry
  if not e then return end
  if button == "RightButton" then
    if ES.Inventory then ES.Inventory.SetNeverSell(e.itemID, true) end
    return
  end
  -- Clic: todas las que la fila dice que vendas en la AH (lo normal; esa cantidad ya
  -- es prudente: lo dudoso, pocas y a 8 h), como en la pestaña Inventario.
  -- Mayús+clic: una sola, para probar el precio (como Mayús en las bolsas: una parte)
  local n = (IsShiftKeyDown and IsShiftKeyDown()) and 1 or e.ahN
  ES.Ledger:PostOnAH(e.itemID, n, e.listPrice, e.hours)
  C_Timer.After(0.6, function() Sell:Refresh() end)
end

local function RowEnter(self)
  if not self.entry then return end
  if ES.Inventory and ES.Inventory.Tooltip then
    ES.Inventory.Tooltip(self.entry, true)(self) -- (sin sus líneas de clic: aquí van las de esta ventana)
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine(string.format(L["Clic: anunciar %d."], self.entry.ahN), 0.5, 0.8, 1)
  if self.entry.ahN > 1 then
    GameTooltip:AddLine(L["Mayús+clic: anunciar solo 1."], 0.5, 0.8, 1)
  end
  GameTooltip:AddLine(L["Clic derecho: no venderlo nunca."], 0.6, 0.6, 0.6)
  GameTooltip:Show()
end

local function CreatePanel(parent)
  local f = CreateFrame("Frame", "CraftersJournalAuctionSellPanel", parent or UIParent, "BackdropTemplate")
  f:SetWidth(WIDTH)
  -- (el mismo aspecto que la ventana del vendedor)
  f:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  local G = ES.UI.BROWN.group
  f:SetBackdropColor(G[1], G[2], G[3], 0.99)
  f:SetBackdropBorderColor(0.52, 0.38, 0.17, 1)
  if f.SetClampedToScreen then f:SetClampedToScreen(true) end
  f:EnableMouse(true)
  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.title:SetPoint("TOPLEFT", 12, -10)
  f.title:SetText("Crafter's Journal")
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)
  close:SetScript("OnClick", function()
    -- (cerrada, no vuelve a salir hasta /reload o hasta abrir otra vez la AH)
    Sell.closed = true
    f:Hide()
    PlaceShopping()
  end)
  f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -3)
  f.sub:SetWidth(WIDTH - 24)
  f.sub:SetJustifyH("LEFT")
  f.rows = {}
  for i = 1, MAX_ROWS do
    local row = CreateFrame("Button", nil, f)
    row:SetSize(WIDTH - 16, ROW_H)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.82, 0.25, 0.1)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(26, 26)
    row.icon:SetPoint("LEFT", 2, 0)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -1)
    row.name:SetPoint("RIGHT", row, "RIGHT", -COST_W, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.cost = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.cost:SetPoint("TOP", row.name, "TOP", 0, 0)
    row.cost:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.cost:SetJustifyH("RIGHT")
    row.qty = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.qty:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, 1)
    row.qty:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.qty:SetJustifyH("LEFT")
    row.qty:SetWordWrap(false)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", RowClick)
    row:SetScript("OnEnter", RowEnter)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.rows[i] = row
  end
  f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.hint:SetJustifyH("LEFT")
  if f.hint.SetSpacing then f.hint:SetSpacing(2) end
  f:Hide()
  return f
end

-- Dónde va: pegada a la AH; la lista de compra pequeña, si sale, a su derecha
-- (ES:PlaceShoppingMini, ShoppingUI.lua)
local function Place(ah)
  panel:ClearAllPoints()
  panel:SetPoint("TOPLEFT", ah, "TOPRIGHT", 2, -12)
end

-- La lista de compra se coloca según si esta ventana se ve
local function PlaceShopping()
  if ES.PlaceShoppingMini then ES:PlaceShoppingMini() end
end

function Sell:Refresh()
  self:HookPanels()
  local ah = AHFrame()
  local main = CraftersJournalMainFrame
  if not (ah and ES:IsAuctionHouseOpen()) or self.closed or (main and main:IsShown()) then
    if panel then panel:Hide() end
    PlaceShopping()
    return
  end
  local list = self:List()
  if #list == 0 then
    if panel then panel:Hide() end
    PlaceShopping()
    return
  end
  panel = panel or CreatePanel(ah)
  Place(ah)
  if panel.SetFrameStrata and ah.GetFrameStrata then panel:SetFrameStrata(ah:GetFrameStrata()) end
  panel.sub:SetText(L["Para vender en la AH, de tus bolsas:"])
  local function H(fs) return math.min(tonumber(fs:GetStringHeight()) or 12, 40) end
  local y = -(10 + H(panel.title) + 3 + H(panel.sub) + 8)
  local shown = math.min(#list, MAX_ROWS)
  for i = 1, shown do
    local row, e = panel.rows[i], list[i]
    row.entry = e
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 8, y)
    y = y - ROW_H
    local _, _, texture = ES:GetItemData(e.itemID)
    row.icon:SetTexture(texture or (GetItemIcon and GetItemIcon(e.itemID)) or 134400)
    row.name:SetText((ES.UI.ItemLabel(e.itemID, "#" .. e.itemID)))
    -- Cuántos y a cuánto se anuncian, la duración y lo que dicen las alertas
    local verdict = ES.Market.LABELS and ES.Market.LABELS[e.verdict]
    row.qty:SetText(string.format(L["Anuncias %d × %s · %d h"], e.ahN, ES.Money(e.listPrice), e.hours or 24)
      .. (verdict and (" · " .. verdict) or ""))
    row.cost:SetText(GREEN .. "+" .. ES.Money(e.ahN * (e.ahUnit or 0)) .. "|r")
    row:Show()
  end
  for k = shown + 1, MAX_ROWS do
    panel.rows[k].entry = nil
    panel.rows[k]:Hide()
  end
  -- A la vista: qué hace el clic y el clic derecho (y cuántas no caben)
  panel.hint:ClearAllPoints()
  panel.hint:SetPoint("TOPLEFT", 12, y - 4)
  panel.hint:SetPoint("RIGHT", panel, "RIGHT", -12, 0)
  -- Una línea por acción, la tecla en el azul de las acciones del addon (antes era una
  -- sola línea gris que se partía y no se leía)
  local KEY = "|cff80ccff"
  local hint = KEY .. L["Clic"] .. "|r  " .. L["anunciar todas"] .. "\n"
    .. KEY .. L["Mayús+clic"] .. "|r  " .. L["anunciar solo 1"] .. "\n"
    .. KEY .. L["Clic derecho"] .. "|r  " .. L["no venderlo nunca"]
  if #list > shown then
    hint = hint .. "\n" .. GREY .. string.format(L["(%d más en la pestaña Inventario)"], #list - shown) .. "|r"
  end
  panel.hint:SetText(hint)
  y = y - 4 - math.max(14, math.min(tonumber(panel.hint:GetStringHeight()) or 0, 70))
  panel:SetHeight(-y + 10)
  panel:Show()
  PlaceShopping() -- (la lista de compra, a la derecha de esta)
end

do
  local f = CreateFrame("Frame")
  for _, e in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED" }) do
    ES.SafeRegister(f, e)
  end
  local queued = false
  f:SetScript("OnEvent", function(_, event)
    if not ES.db then return end
    if event == "AUCTION_HOUSE_CLOSED" then
      Sell.closed = nil
      if panel then panel:Hide() end
      return
    end
    if event == "AUCTION_HOUSE_SHOW" then Sell.closed = nil end
    -- (agrupado: al abrir la AH la lista de compra pequeña se coloca primero)
    if not queued then
      queued = true
      C_Timer.After(0.3, function()
        queued = false
        Sell:Refresh()
      end)
    end
  end)
end

-- La ventana grande aparece o se va (con ella al lado de la AH, esta no sale)
function Sell:HookPanels()
  local main = CraftersJournalMainFrame
  if main and not main.cjSellHook then
    main.cjSellHook = true
    main:HookScript("OnShow", function() Sell:Refresh() end)
    main:HookScript("OnHide", function() Sell:Refresh() end)
  end
end
