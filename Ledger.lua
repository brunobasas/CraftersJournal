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

-- Diario de lo que lee el registro (para diagnosticar en el juego): ES.db.ledgerLog
local function Log(text)
  ES.db.ledgerLog = ES.db.ledgerLog or {}
  local log = ES.db.ledgerLog
  log[#log + 1] = (date and date("%H:%M:%S ") or "") .. text
  while #log > 60 do table.remove(log, 1) end
end
Ledger.Log = Log

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
      Log(string.format("  apuntado %s %dx%d = %d en %s", kind, qty, itemID, money, r.key))
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

-- Instructor o depósito de la AH: a la ruta de esa profesión (`profKey`). Sin saber
-- de qué profesión es, solo si hay una única ruta fijada (si no, no se apunta:
-- mejor no apuntar que apuntarlo a la ruta equivocada)
function Ledger:RecordFee(money, profKey)
  local routes, r = Routes(), nil
  for _, x in ipairs(routes) do if x.key == profKey then r = x end end
  if not r and not profKey and #routes == 1 then r = routes[1] end
  if not r then
    Log(string.format("  gasto de %d sin ruta a la que apuntarlo (%s)", money, tostring(profKey)))
    return false
  end
  local b = Book(r.lock)
  Log(string.format("  apuntado instructor/depósito %d en %s", money, r.key))
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

-- Ruta fijada que fabrica (y vende) este objeto
local function SellRoute(itemID)
  for _, r in ipairs(Routes()) do
    if r.set.sell[itemID] then return r.key end
  end
end

-- Nombre en el idioma del juego (el de los correos), no en el del addon
local function ClientItemName(itemID)
  if C_Item and C_Item.GetItemNameByID then return C_Item.GetItemNameByID(itemID) end
  return GetItemInfo and (GetItemInfo(itemID))
end

-- Objeto de una ruta fijada por su nombre (los correos solo traen el nombre)
function Ledger:IDByName(name)
  for _, r in ipairs(Routes()) do
    for _, kind in ipairs({ "scroll", "buy" }) do
      for itemID in pairs(r.set[kind]) do
        if ClientItemName(itemID) == name then return itemID end
      end
    end
  end
end

-- Profesión del instructor abierto (por la línea de habilidad de lo que enseña), o nil
local PROF_SPELLS = { Alchemy = 2259, Blacksmithing = 2018, Enchanting = 7411, Engineering = 4036,
  Leatherworking = 2108, Tailoring = 3908, Cooking = 2550, FirstAid = 3273 }
local function SpellName(id)
  if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
  return GetSpellInfo and (GetSpellInfo(id))
end
local function TrainerProfession()
  if not (GetNumTrainerServices and GetTrainerServiceSkillLine) then return nil end
  for i = 1, GetNumTrainerServices() or 0 do
    local line = GetTrainerServiceSkillLine(i)
    if line and line ~= "" then
      for key, spell in pairs(PROF_SPELLS) do
        if line == SpellName(spell) or line == ES:ProfLabel(key) then return key end
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
local trainerProf    -- profesión del instructor abierto
local snapshot = {}  -- [itemID] = unidades al abrir (o en la última lectura)
local lastMoney, spent, gained = 0, 0, 0
local processStamp = 0
local ahUp, ahUpQty, ahSpent = {}, 0, 0 -- AH: objetos y dinero aún sin emparejar
local ahUpAt, ahSpentAt = 0, 0          -- cuándo llegó lo que aún no se ha emparejado
local AH_PAIR_WINDOW = 3                -- s: lo que no se empareja en este tiempo no es de la ruta
local function Now() return GetTime and GetTime() or 0 end

---------------------------------------------------------------------------
-- Compras en la AH: en Forever llegan por correo, así que se apuntan al comprar
-- (al confirmar la compra en la AH), con lo que baja tu dinero en ese momento.
-- Mientras esperan en el buzón cuentan como tuyas (Ledger:InMail).
---------------------------------------------------------------------------
local ahPending = {}           -- compras enviadas a la AH aún sin cobrar: { itemID, qty, cost, t }
local AH_CHARGE_WINDOW = 15    -- s entre confirmar la compra y que baje tu dinero
local MAIL_KEEP = 2 * 86400    -- lo comprado que no aparece en 2 días ya no se espera

local function NoteAHPurchase(itemID, qty, cost)
  if not itemID then return end
  ahPending[#ahPending + 1] = { itemID = itemID, qty = qty or 1, cost = cost, t = Now() }
  Log(string.format("ah: compra enviada %dx%d%s", qty or 1, itemID, cost and (" por " .. cost) or ""))
end

-- Lo comprado en la AH que aún está en el buzón: [personaje][itemID] = { q, base, t }
local function MailStore()
  ES.db.mailBought = ES.db.mailBought or {}
  local char = ES:CharKey()
  ES.db.mailBought[char] = ES.db.mailBought[char] or {}
  return ES.db.mailBought[char]
end

local function NoteMail(itemID, qty)
  local store = MailStore()
  local left = Ledger:InMail(itemID)
  store[itemID] = { q = left + qty, base = Count(itemID), t = time() }
end

-- Unidades compradas en la AH que aún no han salido del buzón
function Ledger:InMail(itemID)
  local store = ES.db and ES.db.mailBought and ES.db.mailBought[ES:CharKey()]
  local m = store and store[itemID]
  if not m then return 0 end
  local left = m.q - math.max(0, Count(itemID) - m.base)
  if left <= 0 or time() - m.t > MAIL_KEEP then
    store[itemID] = nil
    return 0
  end
  return left
end

-- Baja tu dinero con la AH abierta y había una compra enviada: es su cobro
local function ChargeAHPurchase(amount)
  local t = Now()
  while ahPending[1] and t - ahPending[1].t > AH_CHARGE_WINDOW do table.remove(ahPending, 1) end
  local p = table.remove(ahPending, 1)
  if not p then return false end
  local kind = Ledger:Kind(p.itemID)
  if kind then Ledger:Record(kind, p.itemID, p.qty, p.cost or amount) end
  NoteMail(p.itemID, p.qty)
  return true
end

-- Las compras que se hacen en la AH, con el addon o a mano
if hooksecurefunc and C_AuctionHouse then
  if C_AuctionHouse.ConfirmCommoditiesPurchase then
    -- Materiales ("Comprar ahora"): el precio llega al cobrarlo
    hooksecurefunc(C_AuctionHouse, "ConfirmCommoditiesPurchase", function(itemID, qty) NoteAHPurchase(itemID, qty) end)
    Ledger.hooksAH = true
  end
  if C_AuctionHouse.PlaceBid then
    -- Objetos sueltos: la subasta dice qué es y cuántos
    hooksecurefunc(C_AuctionHouse, "PlaceBid", function(auctionID, amount)
      local ok, info = false, nil
      if C_AuctionHouse.GetAuctionInfoByID then ok, info = pcall(C_AuctionHouse.GetAuctionInfoByID, auctionID) end
      local itemID = ok and type(info) == "table" and info.itemKey and info.itemKey.itemID
      if itemID then NoteAHPurchase(itemID, info.quantity or 1, amount) end
    end)
    Ledger.hooksAH = true
  end
end
if hooksecurefunc and PlaceAuctionBid and GetAuctionItemInfo then
  -- AH clásica: comprar al precio de compra directa en la lista
  hooksecurefunc("PlaceAuctionBid", function(kind, index, bid)
    local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = GetAuctionItemInfo(kind or "list", index)
    if itemID and bid and buyout and buyout > 0 and bid >= buyout then NoteAHPurchase(itemID, count or 1, bid) end
  end)
  Ledger.hooksAH = true
end
Ledger.NoteAHPurchase, Ledger.ChargeAHPurchase = NoteAHPurchase, ChargeAHPurchase -- para pruebas

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
  ahUp, ahUpQty, ahSpent = {}, 0, 0
end

-- Objeto de la casilla `i` del vendedor abierto
local function MerchantItemID(i)
  local id = GetMerchantItemID and GetMerchantItemID(i)
  if not id and GetMerchantItemLink then
    local link = GetMerchantItemLink(i)
    id = link and tonumber(link:match("item:(%d+)"))
  end
  return id
end
Ledger.MerchantItemID = MerchantItemID

-- Precio, cuántos vienen por compra, cuántos quedan (-1 sin límite), si se compra con
-- oro. Forever (cliente moderno) usa C_MerchantFrame.GetItemInfo; el clásico, GetMerchantItemInfo
local function MerchantInfo(i)
  if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
    local info = C_MerchantFrame.GetItemInfo(i)
    if info then
      return info.price, info.stackCount, info.numAvailable, info.isPurchasable ~= false and not info.hasExtendedCost
    end
  elseif GetMerchantItemInfo then
    local _, _, price, stack, avail, purchasable, _, ext = GetMerchantItemInfo(i)
    return price, stack, avail, purchasable ~= false and not ext
  end
end
Ledger.MerchantInfo = MerchantInfo

-- Precio de una unidad en el vendedor abierto, o nil
local function MerchantUnitPrice(itemID)
  if not GetMerchantNumItems then return nil end
  for i = 1, GetMerchantNumItems() do
    if MerchantItemID(i) == itemID then
      local price, stack = MerchantInfo(i)
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
  if next(up) or next(down) then
    local parts = {}
    for itemID, q in pairs(up) do parts[#parts + 1] = "+" .. q .. "x" .. itemID end
    for itemID, q in pairs(down) do parts[#parts + 1] = "-" .. q .. "x" .. itemID end
    Log(string.format("%s: %s · dinero -%d +%d", where, table.concat(parts, " "), spent, gained))
  end
  if where == "merchant" then
    for itemID, q in pairs(up) do
      local unit = MerchantUnitPrice(itemID)
      if unit then
        local kind = Ledger:Kind(itemID)
        if kind then Ledger:Record(kind, itemID, q, unit * q) end
      elseif spent > 0 and Ledger:Kind(itemID) == nil then
        -- Recompra de algo que acabas de vender (si ha bajado tu dinero; si no, lo has
        -- fabricado con la ventana abierta): se descuenta
        Ledger:Record("sell", itemID, -q, -q * (ES:VendorSellPrice(itemID) or 0))
      end
    end
    -- Ventas: solo si ha subido tu dinero (si no, lo has gastado fabricando)
    if gained > 0 then
      for itemID, q in pairs(down) do
        Ledger:Record("sell", itemID, q, q * (ES:VendorSellPrice(itemID) or 0))
      end
    end
  elseif where == "ah" then
    -- Compras: el dinero que bajó, repartido entre lo que ha llegado. El dinero y los
    -- objetos pueden llegar por separado: se emparejan si llegan con poco tiempo de
    -- diferencia; lo que se queda solo (comprar algo que no es de la ruta) se descarta
    local t = Now()
    if next(ahUp) and t - ahUpAt > AH_PAIR_WINDOW then ahUp, ahUpQty = {}, 0 end
    if ahSpent > 0 and t - ahSpentAt > AH_PAIR_WINDOW then ahSpent = 0 end
    if upQty > 0 then ahUpAt = t end
    if spent > 0 then ahSpentAt = t end
    for itemID, q in pairs(up) do ahUp[itemID] = (ahUp[itemID] or 0) + q end
    ahUpQty, ahSpent = ahUpQty + upQty, ahSpent + spent
    if ahUpQty > 0 and ahSpent > 0 then
      for itemID, q in pairs(ahUp) do
        local kind = Ledger:Kind(itemID)
        if kind then Ledger:Record(kind, itemID, q, ahSpent * q / ahUpQty) end
      end
      ahUp, ahUpQty, ahSpent = {}, 0, 0
    elseif next(down) and ahSpent > 0 then
      -- Depósito al anunciar: a la ruta que fabrica lo anunciado
      local posted = next(down)
      local prof = SellRoute(posted)
      if prof then Ledger:RecordFee(ahSpent, prof) end
      ahSpent = 0
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
      trainerProf = where == "trainer" and TrainerProfession() or nil
      Snapshot()
      local n = 0
      for _ in pairs(snapshot) do n = n + 1 end
      Log(string.format("abierto %s%s · %d objetos de rutas fijadas vigilados", where,
        trainerProf and (" de " .. trainerProf) or "", n))
      if ES.RefreshAfterBags then ES:RefreshAfterBags() end -- la vista Profit cambia sus clics
    elseif event == "MERCHANT_CLOSED" or event == "AUCTION_HOUSE_CLOSED" or event == "TRAINER_CLOSED" then
      Process()
      where = nil
      if ES.RefreshAfterBags then ES:RefreshAfterBags() end
    elseif event == "PLAYER_MONEY" then
      local money = GetMoney and GetMoney() or 0
      local delta = money - lastMoney
      lastMoney = money
      -- Cobro de una compra enviada a la AH (llega por correo): se apunta ya, aunque
      -- acabes de cerrar la AH (el cobro puede llegar justo después)
      if delta < 0 and ChargeAHPurchase(-delta) then return end
      if not where then return end
      if delta < 0 then spent = spent - delta else gained = gained + delta end
      if where == "trainer" and spent > 0 then
        Ledger:RecordFee(spent, trainerProf)
        spent = 0
      elseif where == "ah" and delta < 0 then
        QueueProcess() -- el dinero de una compra puede llegar después que el objeto
      end
    elseif event == "BAG_UPDATE_DELAYED" and where then
      QueueProcess()
    end
  end)
end
Ledger.Process, Ledger.Snapshot = Process, Snapshot -- para pruebas
function Ledger:SetWhere(w) where = w end           -- para pruebas
function Ledger:SetMoney(s, g) spent, gained = s or 0, g or 0 end -- para pruebas: dinero gastado/ganado

-- Empiezas o cambias una ruta con el vendedor, la AH o el instructor abiertos: se
-- vuelve a mirar qué llevas, para que cuente lo que compres en esta misma visita
function Ledger:Resync()
  if where then Snapshot() end
end

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

-- Precio de anuncio en la AH de Forever: solo admite platas enteras (redondeo hacia abajo)
function Ledger.PostPrice(unit)
  unit = math.floor(unit or 0)
  return math.max(unit - unit % 100, 100)
end

-- Anuncia `n` unidades en la AH abierta a `unit` cobre cada una (24 h). Solo con
-- la AH de Forever (C_AuctionHouse); con la clásica, se anuncia a mano. Los
-- materiales (commodities) van en un solo anuncio; el resto, todos de una vez y,
-- si la AH no lo acepta, de uno en uno. Devuelve cuántos anunció.
function Ledger:PostOnAH(itemID, n, unit)
  local AH = C_AuctionHouse
  if not (ES:IsAuctionHouseOpen() and AH and AH.PostItem and ItemLocation) then
    ES:Print(L["Anúncialo desde la ventana de la Casa de Subastas."])
    return 0
  end
  if AH.IsThrottledMessageSystemReady and not AH.IsThrottledMessageSystemReady() then
    ES:Print(L["La Casa de Subastas está ocupada: vuelve a pulsar en un momento."])
    return 0
  end
  local slot
  for _, s in ipairs(Slots(itemID)) do
    local locked = C_Container and C_Container.GetContainerItemInfo and (C_Container.GetContainerItemInfo(s.bag, s.slot) or {}).isLocked
    if not locked then slot = s break end
  end
  if not slot or n <= 0 then return 0 end
  local qty = math.min(n, BagCount(itemID))
  local location = ItemLocation:CreateFromBagAndSlot(slot.bag, slot.slot)
  local commodity = false
  if AH.GetItemCommodityStatus then
    local ok, status = pcall(AH.GetItemCommodityStatus, location)
    local COMMODITY = Enum and Enum.ItemCommodityStatus and Enum.ItemCommodityStatus.Commodity or 2
    commodity = ok and status == COMMODITY
  end
  local price = Ledger.PostPrice(unit)
  local ok, err
  if commodity and AH.PostCommodity then
    ok, err = pcall(AH.PostCommodity, location, 2, qty, price)
  else
    ok, err = pcall(AH.PostItem, location, 2, qty, nil, price)
    if not ok and qty > 1 then -- no acepta varios de una vez: uno (el resto, con otro clic)
      qty = 1
      ok, err = pcall(AH.PostItem, location, 2, 1, nil, price)
    end
  end
  if not ok then
    ES:Print(L["No se pudo anunciar: "] .. tostring(err))
    return 0
  end
  ES:Print(string.format(L["Anunciados %d de %s a %s cada uno (24 h)."], qty, ES:DataItemName(itemID) or itemID, ES.Money(price)))
  return qty
end
