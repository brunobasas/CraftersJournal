local _, ES = ...
local L = ES.L

-- Al abrir un vendedor que tiene algo de tu lista de la compra (de las rutas
-- empezadas o, si no hay, de la profesión que estabas mirando) sale al lado una
-- ventana con esos materiales: lo que te falta, con un botón "Comprar todo", y lo
-- que ya tienes, en gris. Solo compra cuando pulsas (fila o botón).
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

-- Rutas de las que sale la lista de la compra: las empezadas; si no hay ninguna,
-- la de la profesión que estabas mirando (si ya está calculada)
local function Plans()
  local plans = {}
  for _, prof in ipairs(ES.PROFESSIONS) do
    local plan = ES:RouteLock(prof.key) and ES:LockedPlan(prof.key)
    if plan then plans[#plans + 1] = { key = prof.key, plan = plan } end
  end
  if #plans == 0 and ES.db.lastProf then
    local key, plan = ES.db.lastProf, nil
    for _, page in ipairs(ES.professionPages or {}) do
      if page.profKey == key then plan = page.plan end
    end
    plan = plan or (ES.homePlanCache[key] and ES.homePlanCache[key].plan)
    if plan and plan.pointNeed then plans[1] = { key = key, plan = plan } end
  end
  return plans
end

-- Lo que pide la lista de la compra desde tu nivel, y lo que tienes (bolsas, banco y
-- lo comprado que espera en el correo): { [itemID] = { need, have } }
local function Needs()
  local need = {}
  for _, p in ipairs(Plans()) do
    local rank = ES:GetProfessionSkill(ES.Data[p.key].skillLine)
    for itemID, q in pairs(ES.Planner.NeedFrom(p.plan, math.max(p.plan.from, rank or p.plan.from))) do
      need[itemID] = (need[itemID] or 0) + q
    end
  end
  local out = {}
  for itemID, q in pairs(need) do
    local n = math.ceil(q - 0.001)
    if n > 0 then
      out[itemID] = { need = n, have = ES:ItemCount(itemID) + Ledger():InMail(itemID) + Vendor:Pending(itemID) }
    end
  end
  return out
end

-- Lo de la lista de la compra que vende este vendedor:
-- { { index, itemID, need, have, qty (lo que falta, en lotes; 0 si tienes bastante), price, batch, cost } }
function Vendor:List()
  local list = {}
  if not (GetMerchantNumItems and Ledger()) then return list end
  local needs = Needs()
  for i = 1, GetMerchantNumItems() or 0 do
    local itemID = Ledger().MerchantItemID(i)
    local n = itemID and needs[itemID]
    if n then
      local price, batch, avail, gold = Ledger().MerchantInfo(i)
      if price and price > 0 and gold and avail ~= 0 then
        batch = math.max(batch or 1, 1)
        local left = math.max(0, n.need - n.have)
        local qty = math.ceil(left / batch) * batch -- el vendedor vende en sus lotes
        list[#list + 1] = { index = i, itemID = itemID, need = n.need, have = n.have, qty = qty, price = price,
          batch = batch, cost = qty / batch * price }
        needs[itemID] = nil -- un objeto que el vendedor tiene dos veces, una sola fila
      end
    end
  end
  -- Lo que falta primero (lo más caro arriba); lo que ya tienes, al final
  table.sort(list, function(a, b)
    if (a.qty > 0) ~= (b.qty > 0) then return a.qty > 0 end
    return a.cost > b.cost
  end)
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

-- Lo más que se puede pedir en una compra: lo que deja el vendedor (o una pila), en lotes enteros
local function PerCall(itemID, batch)
  local i = FindIndex(itemID)
  local most = math.max((i and GetMerchantItemMaxStack and GetMerchantItemMaxStack(i)) or 1, StackSize(itemID))
  return math.max(math.floor(most / batch) * batch, batch)
end

-- Pone en la cola `qty` unidades en compras de como mucho `perCall`
local function Enqueue(queue, itemID, qty, perCall, at)
  local calls = {}
  while qty > 0 do
    local n = math.min(qty, perCall)
    calls[#calls + 1] = { itemID = itemID, n = n }
    qty = qty - n
  end
  for k = #calls, 1, -1 do table.insert(queue, at or (#queue + 1), calls[k]) end
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
      if FindIndex(q.itemID) then
        short = math.ceil(short / q.batch) * q.batch
        table.insert(self.queue, 1, { itemID = q.itemID, check = q.check, tries = q.tries + 1, batch = q.batch })
        Enqueue(self.queue, q.itemID, short, PerCall(q.itemID, q.batch), 1) -- en tandas, delante de la comprobación
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
  -- Ya se está comprando (p. ej. "Comprar todo" y luego un clic en su fila): no dos veces
  for _, q in ipairs(self.queue) do if q.itemID == entry.itemID then return end end
  local target = ES:ItemCount(entry.itemID) + entry.qty
  Enqueue(self.queue, entry.itemID, entry.qty, PerCall(entry.itemID, entry.batch))
  self.queue[#self.queue + 1] = { itemID = entry.itemID, check = target, tries = 0, batch = entry.batch }
  if not self.pumping then self:Pump() end
end

function Vendor:BuyAll()
  local list = {}
  for _, e in ipairs(self:List()) do if e.qty > 0 then list[#list + 1] = e end end
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
    row:SetScript("OnClick", function(self) if self.entry and self.entry.qty > 0 then Vendor:Buy(self.entry) end end)
    row:SetScript("OnEnter", function(self)
      if not self.entry then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.entry.itemID) end
      GameTooltip:AddLine(" ")
      if self.entry.qty > 0 then
        GameTooltip:AddLine(string.format(L["Clic: comprar %d por %s."], self.entry.qty, ES.Money(self.entry.cost)), 0.5, 0.8, 1)
      else
        GameTooltip:AddLine(L["Ya tienes lo que te hace falta para la ruta."], 0.4, 1, 0.4)
      end
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
  local total, missing = 0, 0
  for _, e in ipairs(list) do
    total = total + e.cost
    if e.qty > 0 then missing = missing + 1 end
  end
  panel.sub:SetText(self.pumping and L["Comprando…"]
    or missing > 0 and L["De tu lista de la compra, este vendedor tiene:"]
    or L["Ya tienes todo lo que te hace falta de este vendedor."])
  for i, row in ipairs(panel.rows) do
    local e = list[i]
    row.entry = e
    if e then
      local name, _, texture = ES:GetItemData(e.itemID)
      row.icon:SetTexture(texture or (GetItemIcon and GetItemIcon(e.itemID)) or 134400)
      row.icon:SetDesaturated(e.qty == 0)
      local label = name or ES:DataItemName(e.itemID) or ("#" .. e.itemID)
      if e.qty > 0 then
        row.name:SetText(label)
        row.qty:SetText(string.format(L["Tienes %d/%d · compras %d × %s"], math.min(e.have, e.need), e.need, e.qty,
          ES.Money(e.price / e.batch)))
        row.cost:SetText(ES.Money(e.cost))
      else
        -- Ya lo tienes: se ve, en gris, para que sepas que este vendedor también lo vende
        row.name:SetText("|cff9d9d9d" .. label:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. "|r")
        row.qty:SetText("|cff40ff40" .. string.format(L["Tienes %d/%d"], e.have, e.need) .. "|r")
        row.cost:SetText("")
      end
      row:Show()
    else
      row:Hide()
    end
  end
  local shown = math.min(#list, MAX_ROWS)
  panel:SetHeight(40 + shown * ROW_H + 44)
  panel.buyAll:SetText(missing > 0 and string.format(L["Comprar todo (%s)"], ES.Money(total)) or L["Nada que comprar"])
  panel.buyAll:SetEnabled(missing > 0 and not self.pumping)
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
