local _, ES = ...
local L = ES.L

-- Con una ruta empezada ("Empezar ruta"), al abrir un vendedor sale al lado una
-- ventana con lo que te falta de la lista de la compra que vende ese vendedor, y
-- un botón "Comprar todo". Solo compra cuando pulsas (fila o botón).
--
-- Comprar en Forever: cada compra pide un número de objetos (como mucho una pila);
-- el servidor ignora las compras que llegan muy seguidas, así que van de una en
-- una con BUY_GAP de separación y al final se comprueba lo que ha llegado.

local Vendor = { queue = {} }
ES.VendorShop = Vendor

local BUY_GAP = 0.35
local ROW_H, MAX_ROWS = 34, 12
local WIDTH = 270

local function Ledger() return ES.Ledger end

-- Lo que falta de cada material para lo que queda de las rutas empezadas:
-- { [itemID] = unidades } (necesario desde tu nivel menos lo que llevas)
local function Missing()
  local need = {}
  for _, prof in ipairs(ES.PROFESSIONS) do
    local plan = ES:RouteLock(prof.key) and ES:LockedPlan(prof.key)
    if plan then
      local rank = ES:GetProfessionSkill(ES.Data[prof.key].skillLine)
      for itemID, q in pairs(ES.Planner.NeedFrom(plan, math.max(plan.from, rank or plan.from))) do
        need[itemID] = (need[itemID] or 0) + q
      end
    end
  end
  local missing = {}
  for itemID, q in pairs(need) do
    local left = math.ceil(q - 0.001) - ES:ItemCount(itemID) - Vendor:Pending(itemID)
    if left > 0 then missing[itemID] = left end
  end
  return missing
end

-- Lo que este vendedor vende de lo que falta: { { index, itemID, qty, price, batch, cost } }
function Vendor:List()
  local list = {}
  if not (GetMerchantNumItems and Ledger()) then return list end
  local missing = Missing()
  for i = 1, GetMerchantNumItems() or 0 do
    local itemID = Ledger().MerchantItemID(i)
    local left = itemID and missing[itemID]
    if left then
      local price, batch, avail, gold = Ledger().MerchantInfo(i)
      if price and price > 0 and gold and avail ~= 0 then
        batch = math.max(batch or 1, 1)
        local qty = math.ceil(left / batch) * batch -- el vendedor vende en sus lotes
        list[#list + 1] = { index = i, itemID = itemID, qty = qty, price = price, batch = batch,
          cost = qty / batch * price }
        missing[itemID] = nil -- un objeto que el vendedor tiene dos veces, una sola fila
      end
    end
  end
  table.sort(list, function(a, b) return a.cost > b.cost end)
  return list
end

---------------------------------------------------------------------------
-- Cola de compras
---------------------------------------------------------------------------
function Vendor:Pending(itemID)
  local n = 0
  for _, q in ipairs(self.queue) do if q.itemID == itemID and q.n then n = n + q.n end end
  return n
end

local function StackSize(itemID)
  local get = (C_Item and C_Item.GetItemMaxStackCount) or nil
  local n = get and get(itemID)
  if not n and GetItemInfo then n = select(8, GetItemInfo(itemID)) end
  return math.max(n or 1, 1)
end

local function FindIndex(itemID)
  for i = 1, (GetMerchantNumItems and GetMerchantNumItems()) or 0 do
    if Ledger().MerchantItemID(i) == itemID then return i end
  end
end

function Vendor:Pump()
  local q = table.remove(self.queue, 1)
  if not q or not Ledger():MerchantOpen() then
    self.pumping = nil
    if not Ledger():MerchantOpen() then self.queue = {} end
    self:Refresh()
    return
  end
  self.pumping = true
  if q.check then
    -- Comprobación final: lo que no llegó se vuelve a pedir (hasta 2 veces)
    local short = q.check - ES:ItemCount(q.itemID)
    if short > 0 and q.tries < 2 then
      local i = FindIndex(q.itemID)
      if i then
        table.insert(self.queue, 1, { itemID = q.itemID, check = q.check, tries = q.tries + 1 })
        table.insert(self.queue, 1, { itemID = q.itemID, n = short })
      end
    elseif short > 0 then
      ES:Print(string.format(L["El vendedor no vendió %d de %s (sin existencias, sin oro o sin sitio en las bolsas)."],
        short, ES:DataItemName(q.itemID) or q.itemID))
    end
  else
    local i = FindIndex(q.itemID)
    if i then BuyMerchantItem(i, q.n) end
  end
  C_Timer.After(q.check and 1.0 or BUY_GAP, function() Vendor:Pump() end)
end

-- Compra `entry` (de Vendor:List): en tandas de como mucho una pila
function Vendor:Buy(entry)
  local perCall = math.max(math.floor(StackSize(entry.itemID) / entry.batch) * entry.batch, entry.batch)
  local left = entry.qty
  local target = ES:ItemCount(entry.itemID) + entry.qty
  while left > 0 do
    local n = math.min(left, perCall)
    self.queue[#self.queue + 1] = { itemID = entry.itemID, n = n }
    left = left - n
  end
  self.queue[#self.queue + 1] = { itemID = entry.itemID, check = target, tries = 0 }
  if not self.pumping then self:Pump() end
end

function Vendor:BuyAll()
  local list = self:List()
  local total = 0
  for _, e in ipairs(list) do total = total + e.cost end
  if total > ((GetMoney and GetMoney()) or 0) then
    ES:Print(string.format(L["Comprarlo todo cuesta %s: más de lo que llevas."], ES.Money(total)))
    return
  end
  for _, e in ipairs(list) do self:Buy(e) end
  ES:Print(string.format(L["Comprando %d materiales de la lista de la compra por %s..."], #list, ES.Money(total)))
end

---------------------------------------------------------------------------
-- Ventana
---------------------------------------------------------------------------
local panel
local function CreatePanel()
  local f = CreateFrame("Frame", "CraftersJournalVendorPanel", MerchantFrame or UIParent, "BackdropTemplate")
  f:SetWidth(WIDTH)
  f:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  f:SetBackdropBorderColor(0.68, 0.52, 0.20, 1)
  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.title:SetPoint("TOPLEFT", 12, -10)
  f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -3)
  f.sub:SetWidth(WIDTH - 24)
  f.sub:SetJustifyH("LEFT")
  f.rows = {}
  for i = 1, MAX_ROWS do
    local row = CreateFrame("Button", nil, f)
    row:SetSize(WIDTH - 16, ROW_H)
    row:SetPoint("TOPLEFT", 8, -40 - (i - 1) * ROW_H)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.82, 0.25, 0.1)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(26, 26)
    row.icon:SetPoint("LEFT", 2, 0)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -1)
    row.name:SetPoint("RIGHT", -70, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.qty = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.qty:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, 1)
    row.cost = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.cost:SetPoint("RIGHT", -4, 0)
    row:SetScript("OnClick", function(self) if self.entry then Vendor:Buy(self.entry) end end)
    row:SetScript("OnEnter", function(self)
      if not self.entry then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.entry.itemID) end
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(string.format(L["Clic: comprar %d por %s."], self.entry.qty, ES.Money(self.entry.cost)), 0.5, 0.8, 1)
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.rows[i] = row
  end
  f.buyAll = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.buyAll:SetSize(WIDTH - 24, 24)
  f.buyAll:SetPoint("BOTTOM", 0, 10)
  f.buyAll:SetScript("OnClick", function() Vendor:BuyAll() end)
  f:Hide()
  return f
end

function Vendor:Refresh()
  if not (MerchantFrame and MerchantFrame:IsShown()) then
    if panel then panel:Hide() end
    return
  end
  local list = self:List()
  if #list == 0 and not self.pumping then
    if panel then panel:Hide() end
    return
  end
  panel = panel or CreatePanel()
  panel:ClearAllPoints()
  panel:SetPoint("TOPLEFT", MerchantFrame, "TOPRIGHT", 4, 0)
  panel.title:SetText("Crafter's Journal")
  local total = 0
  for _, e in ipairs(list) do total = total + e.cost end
  panel.sub:SetText(#list > 0 and L["Te falta para tu ruta y lo vende este vendedor:"] or L["Comprando…"])
  for i, row in ipairs(panel.rows) do
    local e = list[i]
    row.entry = e
    if e then
      local name, _, texture = ES:GetItemData(e.itemID)
      row.icon:SetTexture(texture or (GetItemIcon and GetItemIcon(e.itemID)) or 134400)
      row.name:SetText(name or ES:DataItemName(e.itemID) or ("#" .. e.itemID))
      row.qty:SetText(string.format(L["%d × %s"], e.qty, ES.Money(e.price / e.batch)))
      row.cost:SetText(ES.Money(e.cost))
      row:Show()
    else
      row:Hide()
    end
  end
  local shown = math.min(#list, MAX_ROWS)
  panel:SetHeight(40 + shown * ROW_H + 44)
  panel.buyAll:SetText(string.format(L["Comprar todo (%s)"], ES.Money(total)))
  panel.buyAll:SetEnabled(#list > 0 and not self.pumping)
  panel:Show()
end

do
  local f = CreateFrame("Frame")
  for _, e in ipairs({ "MERCHANT_SHOW", "MERCHANT_CLOSED", "MERCHANT_UPDATE", "BAG_UPDATE_DELAYED" }) do
    ES.SafeRegister(f, e)
  end
  f:SetScript("OnEvent", function(_, event)
    if not ES.db then return end
    if event == "MERCHANT_CLOSED" then
      Vendor.queue, Vendor.pumping = {}, nil
      if panel then panel:Hide() end
    elseif MerchantFrame and MerchantFrame:IsShown() then
      Vendor:Refresh()
    end
  end)
end
