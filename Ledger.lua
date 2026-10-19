local _, ES = ...
local L = ES.L

-- Gasto real de la ruta fijada ("Empezar ruta"): lo que de verdad pagas y cobras
-- por los objetos de la ruta, leído del juego. Junto al coste previsto se ve lo
-- que llevas gastado y recuperado.
--   compras al vendedor: lo que aumenta en tus bolsas con el vendedor abierto, a su precio
--   compras en la AH: lo que aumenta con la AH abierta, por lo que baja tu dinero
--     (o la factura del correo si llegan por correo; ver Mail.lua)
--   instructor: lo que baja tu dinero con el instructor abierto
--   ventas al vendedor: lo fabricado que sale de tus bolsas con el vendedor abierto
--   ventas en la AH: los correos de subasta vendida desde que empezaste (Mail.lua)
--   depósitos de la AH: lo que baja tu dinero al anunciar (se cuenta con el instructor)
-- Solo cuenta lo de la ruta: materiales de la lista de la compra, sus pergaminos y
-- lo que fabrica. Se guarda en settings.lock.ledger = { buy, sell, fees, sold = { [itemID] = n } }.
--
-- Vender al vendedor y anunciar en la AH desde la vista Profit: siempre con un
-- clic del jugador que dice exactamente qué va a hacer. El addon no compra ni
-- vende nada sin ese clic.

local Ledger = { sets = {}, stamp = 0 }
ES.Ledger = Ledger

local NumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
local ContainerItemID = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID
local UseItem = (C_Container and C_Container.UseContainerItem) or UseContainerItem
local PROCESS_DELAY = 0.3 -- s tras el último cambio en las bolsas (el dinero llega aparte)

local function Count(itemID)
  local get = (C_Item and C_Item.GetItemCount) or GetItemCount
  return get and (get(itemID, true) or 0) or 0
end

-- Unidades de un objeto en una casilla de las bolsas
local function SlotCount(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local info = C_Container.GetContainerItemInfo(bag, slot)
    return info and info.stackCount or 0
  end
  local _, count = GetContainerItemInfo(bag, slot)
  return count or 0
end

-- Casillas de las bolsas (no el banco) con este objeto: { {bag, slot, count} }
local function Slots(itemID)
  local list = {}
  if not (NumSlots and ContainerItemID) then return list end
  for bag = 0, 4 do
    for slot = 1, NumSlots(bag) or 0 do
      if ContainerItemID(bag, slot) == itemID then
        list[#list + 1] = { bag = bag, slot = slot, count = SlotCount(bag, slot) }
      end
    end
  end
  return list
end

local function BagCount(itemID)
  local n = 0
  for _, s in ipairs(Slots(itemID)) do n = n + s.count end
  return n
end
Ledger.BagCount = BagCount

---------------------------------------------------------------------------
-- Rutas fijadas y sus objetos
---------------------------------------------------------------------------
-- { { key, lock, set = { buy, scroll, sell } } }, la profesión que estás mirando primero
local function Routes()
  local list = {}
  for _, prof in ipairs(ES.PROFESSIONS) do
    local lock = ES.RouteLock and ES:RouteLock(prof.key)
    local plan = lock and ES:LockedPlan(prof.key)
    if plan then
      local set = Ledger.sets[prof.key]
      if not set or set.started ~= lock.started then
        set = { started = lock.started, buy = {}, scroll = {}, sell = {} }
        for _, it in ipairs(plan.shopping or {}) do set.buy[it.itemID] = true end
        for _, it in ipairs(plan.owned or {}) do set.buy[it.itemID] = true end
        for _, st in ipairs(plan.steps or {}) do
          if st.sale then set.sell[st.sale.itemID] = true end
          if st.recipe.scroll and (st.fee or 0) > 0 then set.scroll[st.recipe.scroll] = true end
        end
        Ledger.sets[prof.key] = set
      end
      local entry = { key = prof.key, lock = lock, set = set }
      if prof.key == ES.db.lastProf then table.insert(list, 1, entry) else list[#list + 1] = entry end
    end
  end
  return list
end

local function Book(lock)
  lock.ledger = lock.ledger or { buy = 0, sell = 0, fees = 0, sold = {} }
  return lock.ledger
end

local function Changed()
  Ledger.stamp = Ledger.stamp + 1
  if ES.RefreshAfterBags then ES:RefreshAfterBags() end
end

-- kind: "buy" (material), "scroll" (pergamino de la ruta), "sell" (lo fabricado).
-- Se apunta en la primera ruta fijada que tenga ese objeto (`when`: lo de antes de
-- empezarla no cuenta). Devuelve si se apuntó.
function Ledger:Record(kind, itemID, qty, money, when)
  for _, r in ipairs(Routes()) do
    if r.set[kind] and r.set[kind][itemID] and not (when and when < r.lock.started) then
      local b = Book(r.lock)
      if kind == "sell" then
        b.sell = b.sell + money
        b.sold[itemID] = (b.sold[itemID] or 0) + qty
      elseif kind == "scroll" then
        b.fees = b.fees + money
      else
        b.buy = b.buy + money
      end
      Changed()
      return true
    end
  end
  return false
end

-- Instructor o depósito de la AH: a la ruta de la profesión que estás mirando
-- (o a la única fijada)
function Ledger:RecordFee(money)
  local routes = Routes()
  local r = routes[1]
  if not r or (#routes > 1 and r.key ~= ES.db.lastProf) then return false end
  local b = Book(r.lock)
  b.fees = b.fees + money
  Changed()
  return true
end

-- ¿Este objeto es de alguna ruta fijada? (para leer las facturas del correo)
function Ledger:Kind(itemID)
  for _, r in ipairs(Routes()) do
    if r.set.scroll[itemID] then return "scroll" end
    if r.set.buy[itemID] then return "buy" end
  end
end

-- Objeto de una ruta fijada por su nombre (los correos solo traen el nombre)
function Ledger:IDByName(name)
  for _, r in ipairs(Routes()) do
    for _, kind in ipairs({ "scroll", "buy" }) do
      for itemID in pairs(r.set[kind]) do
        if ES:GetItemData(itemID) == name then return itemID end
      end
    end
  end
end

-- Lo real de la ruta fijada: { buy, sell, fees, sold = { [itemID] = n }, ahSales }
-- (las ventas en la AH salen de los correos de subasta vendida desde que empezaste)
function Ledger:Summary(profKey)
  local lock = ES:RouteLock(profKey)
  if not lock then return nil end
  local b = Book(lock)
  local set = Ledger.sets[profKey]
  local res = { buy = b.buy, sell = b.sell, fees = b.fees, sold = {}, ahSales = 0 }
  for id, n in pairs(b.sold) do res.sold[id] = n end
  local mail = ES.db.mail and ES.db.mail[ES:CharKey()]
  if set and mail then
    for _, e in ipairs(mail.events) do
      if e[3] == "sold" and e[1] >= lock.started and set.sell[e[2]] then
        res.ahSales = res.ahSales + e[4]
        res.sold[e[2]] = (res.sold[e[2]] or 0) + 1 -- un correo por subasta
      end
    end
  end
  res.recovered = res.sell + res.ahSales
  res.net = res.buy + res.fees - res.recovered -- como plan.net: positivo = gastas
  return res
end

---------------------------------------------------------------------------
-- Lectura: qué cambia en tus bolsas y tu dinero con el vendedor, la AH o el instructor
---------------------------------------------------------------------------
local where          -- "merchant" | "ah" | "trainer" | nil
local snapshot = {}  -- [itemID] = unidades al abrir (o en la última lectura)
local lastMoney, spent, gained = 0, 0, 0
local processStamp = 0

local function Tracked()
  local items = {}
  for _, r in ipairs(Routes()) do
    for _, kind in ipairs({ "buy", "scroll", "sell" }) do
      for itemID in pairs(r.set[kind]) do items[itemID] = true end
    end
  end
  return items
end

local function Snapshot()
  snapshot = {}
  for itemID in pairs(Tracked()) do snapshot[itemID] = Count(itemID) end
  lastMoney = GetMoney and GetMoney() or 0
  spent, gained = 0, 0
end

-- Precio de una unidad en el vendedor abierto, o nil
local function MerchantUnitPrice(itemID)
  if not (GetMerchantNumItems and GetMerchantItemInfo) then return nil end
  for i = 1, GetMerchantNumItems() do
    local id = GetMerchantItemID and GetMerchantItemID(i)
    if not id and GetMerchantItemLink then
      local link = GetMerchantItemLink(i)
      id = link and tonumber(link:match("item:(%d+)"))
    end
    if id == itemID then
      local _, _, price, stack = GetMerchantItemInfo(i)
      return price and price / math.max(1, stack or 1)
    end
  end
end

local function Process()
  if not where then return end
  local up, down, upQty = {}, {}, 0
  for itemID, before in pairs(snapshot) do
    local now = Count(itemID)
    if now > before then up[itemID] = now - before upQty = upQty + now - before end
    if now < before then down[itemID] = before - now end
    snapshot[itemID] = now
  end
  if where == "merchant" then
    for itemID, q in pairs(up) do
      local unit = MerchantUnitPrice(itemID)
      if unit then
        local kind = Ledger:Kind(itemID)
        if kind then Ledger:Record(kind, itemID, q, unit * q) end
      elseif Ledger:Kind(itemID) == nil then
        -- Recompra de algo que acabas de vender: se descuenta
        Ledger:Record("sell", itemID, -q, -q * (ES:VendorSellPrice(itemID) or 0))
      end
    end
    for itemID, q in pairs(down) do
      Ledger:Record("sell", itemID, q, q * (ES:VendorSellPrice(itemID) or 0))
    end
  elseif where == "ah" then
    -- Compras: el dinero que bajó, repartido entre lo que ha llegado
    if upQty > 0 and spent > 0 then
      for itemID, q in pairs(up) do
        local kind = Ledger:Kind(itemID)
        if kind then Ledger:Record(kind, itemID, q, spent * q / upQty) end
      end
    elseif next(down) and spent > 0 then
      Ledger:RecordFee(spent) -- depósito al anunciar
    end
  end
  spent, gained = 0, 0
end

local function QueueProcess()
  processStamp = processStamp + 1
  local stamp = processStamp
  C_Timer.After(PROCESS_DELAY, function() if stamp == processStamp then Process() end end)
end

do
  local f = CreateFrame("Frame")
  for _, e in ipairs({ "MERCHANT_SHOW", "MERCHANT_CLOSED", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED",
    "TRAINER_SHOW", "TRAINER_CLOSED", "BAG_UPDATE_DELAYED", "PLAYER_MONEY" }) do
    ES.SafeRegister(f, e)
  end
  f:SetScript("OnEvent", function(_, event)
    if not ES.db then return end
    if event == "MERCHANT_SHOW" or event == "AUCTION_HOUSE_SHOW" or event == "TRAINER_SHOW" then
      where = event == "MERCHANT_SHOW" and "merchant" or event == "TRAINER_SHOW" and "trainer" or "ah"
      Snapshot()
      if ES.RefreshAfterBags then ES:RefreshAfterBags() end -- la vista Profit cambia sus clics
    elseif event == "MERCHANT_CLOSED" or event == "AUCTION_HOUSE_CLOSED" or event == "TRAINER_CLOSED" then
      Process()
      where = nil
      if ES.RefreshAfterBags then ES:RefreshAfterBags() end
    elseif event == "PLAYER_MONEY" then
      local money = GetMoney and GetMoney() or 0
      local delta = money - lastMoney
      lastMoney = money
      if not where then return end
      if delta < 0 then spent = spent - delta else gained = gained + delta end
      if where == "trainer" and spent > 0 then
        Ledger:RecordFee(spent)
        spent = 0
      end
    elseif event == "BAG_UPDATE_DELAYED" and where then
      QueueProcess()
    end
  end)
end
Ledger.Process, Ledger.Snapshot = Process, Snapshot -- para pruebas
function Ledger:SetWhere(w) where = w end           -- para pruebas

---------------------------------------------------------------------------
-- Vender y anunciar (vista Profit): siempre desde un clic del jugador
---------------------------------------------------------------------------
function Ledger:MerchantOpen()
  return MerchantFrame and MerchantFrame:IsShown() and true or false
end

-- Vende hasta `n` unidades al vendedor abierto, pilas enteras que quepan en `n`.
-- Devuelve cuántas vendió.
function Ledger:SellToVendor(itemID, n)
  if not self:MerchantOpen() or not UseItem or n <= 0 then return 0 end
  local sold = 0
  for _, s in ipairs(Slots(itemID)) do
    if sold + s.count <= n then
      UseItem(s.bag, s.slot)
      sold = sold + s.count
    end
  end
  if sold < n then
    ES:Print(string.format(L["Vendidos %d de %d: el resto está en pilas más grandes de lo que hay que vender."], sold, n))
  end
  return sold
end

-- Anuncia `n` unidades en la AH abierta a `unit` cobre cada una (24 h). Solo con
-- la AH de Forever (C_AuctionHouse); con la clásica, se anuncia a mano.
function Ledger:PostOnAH(itemID, n, unit)
  local AH = C_AuctionHouse
  if not (ES:IsAuctionHouseOpen() and AH and AH.PostItem and ItemLocation) then
    ES:Print(L["Anúncialo desde la ventana de la Casa de Subastas."])
    return 0
  end
  local first = Slots(itemID)[1]
  if not first or n <= 0 then return 0 end
  local qty = math.min(n, BagCount(itemID))
  local location = ItemLocation:CreateFromBagAndSlot(first.bag, first.slot)
  local commodity = AH.GetItemCommodityStatus and AH.GetItemCommodityStatus(location) == 2
  local price = math.max(1, math.floor(unit + 0.5))
  local ok, err = pcall(function()
    if commodity and AH.PostCommodity then
      AH.PostCommodity(location, 2, qty, price)
    else
      AH.PostItem(location, 2, qty, nil, price)
    end
  end)
  if not ok then
    ES:Print(L["No se pudo anunciar: "] .. tostring(err))
    return 0
  end
  return qty
end
