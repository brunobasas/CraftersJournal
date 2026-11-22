local _, ES = ...

---------------------------------------------------------------------------
-- Merchant's Favor con las Waylaid Crates: cada caja se llena con UNO de sus paquetes
-- (Data/Crates.lua) y se entrega en el campamento de tu bando. Para cada caja, la
-- forma más barata de llenarla con los precios del último escaneo: comprar el paquete
-- (AH o vendedor, subiendo por la escalera de precios como las rutas) o fabricarlo con
-- las recetas que sabes (Bolt of Linen Cloth, Cured Light Hide...: lo de Ganar dinero,
-- Planner.RecipeCost). Y, para las que no tienes, lo que cuesta la caja en la AH.
-- Lo que llevas en las bolsas cuenta a precio de mercado (venderlo es la otra opción,
-- como en Ganar dinero), pero se dice si ya lo tienes.
---------------------------------------------------------------------------
local Favor = {}
ES.Favor = Favor

-- Merchant's Favor que tienes (es una moneda del juego), o nil si el cliente no la da
function Favor.Balance()
  local C = C_CurrencyInfo
  local ok, info = pcall(function() return C and C.GetCurrencyInfo and C.GetCurrencyInfo(ES.Data.FAVOR_CURRENCY) end)
  return ok and info and info.quantity or nil
end

-- Un contexto del planificador con las recetas que sabes de todas tus profesiones (lo
-- intermedio solo con recetas que sabes: knownProducers). Uno solo: las escaleras de
-- precios de todo el escaneo se preparan una vez. Caché por escaneo y profesiones
local ctxCache
ES.MemPart("Merchant's Favor", function() return ctxCache end)
local function Context()
  local scan = ES.db.scans and ES.db.scans[ES:RealmKey()]
  local profs = ES.Earn and ES.Earn.MyProfessions() or {}
  local key = tostring(scan and scan.time or 0) .. ":" .. table.concat(profs, ",") .. ":" .. tostring(ES.planGen or 0)
  if ctxCache and ctxCache.key == key then return ctxCache.ctx end
  local merged = { recipes = {} }
  for _, profKey in ipairs(profs) do
    local data = ES.Data[profKey]
    ES.Planner.Annotate(data)
    for id, r in pairs(data.recipes) do merged.recipes[id] = r end
  end
  local ctx = ES.Planner.NewContext(merged, { from = 1, to = 300, knownProducers = true })
  ctxCache = { key = key, ctx = ctx }
  return ctx
end
function Favor.Clear() ctxCache = nil end

-- Lo que cuesta conseguir `n` de `itemID` por la vía más barata: { cost, actions } o nil
local function FillCost(ctx, itemID, n)
  local cost, _, _, actions = ES.Planner.RecipeCost(ctx, { r = { { itemID, n } } }, 1, {})
  if not cost then return nil end
  return { itemID = itemID, n = n, cost = cost, actions = actions }
end

-- Lo que fabricas tú para un paquete (lo intermedio): { { itemID, qty } }
local function Crafts(fill)
  local out = {}
  for _, a in ipairs(fill.actions or {}) do
    if a.kind == "craft" and (a.qty or 0) > 0 then out[#out + 1] = { itemID = a.item, qty = math.ceil(a.qty - 0.001) } end
  end
  return out
end
Favor.Crafts = Crafts

-- Lo que hay que comprar para un paquete (AH y vendedor), para la Lista de compra
local function Purchases(fill)
  local out = {}
  for _, a in ipairs(fill.actions or {}) do
    if (a.kind == "ah" or a.kind == "vendor") and (a.qty or 0) > 0 then
      out[#out + 1] = { itemID = a.item, quantity = a.qty, unit = (a.cost or 0) / a.qty, source = a.kind }
    end
  end
  return out
end
Favor.Purchases = Purchases

-- Todas las cajas con su mejor paquete: { { crate, have, crateCost, onAH, fill, fills,
-- total, perFavor, haveFill } }. fills: todos los paquetes con precio, del más barato
-- al más caro. Sin precio para ningún paquete, fill = nil
function Favor:Options()
  local scan = ES.db.scans and ES.db.scans[ES:RealmKey()]
  local prices = scan and scan.items or {}
  local ctx = Context()
  local list = {}
  for _, c in ipairs(ES.Data.Crates or {}) do
    local o = { crate = c, have = ES:ItemCount(c.id) or 0, fills = {} }
    local ah = prices[c.id]
    o.onAH = ah and ah.minUnit ~= nil
    if o.have > 0 then o.crateCost = 0 elseif o.onAH then o.crateCost = ah.minUnit end
    for _, f in ipairs(c.fills) do
      local fill = FillCost(ctx, f[1], f[2])
      if fill then
        fill.have = ES:ItemCount(f[1]) or 0
        o.fills[#o.fills + 1] = fill
      end
    end
    table.sort(o.fills, function(a, b) return a.cost < b.cost or (a.cost == b.cost and a.itemID < b.itemID) end)
    -- Lo que ya llevas entero en las bolsas va primero si no sale más caro que el
    -- más barato en más de un 10%: llenar con lo que tienes es lo fácil
    o.fill = o.fills[1]
    for _, f in ipairs(o.fills) do
      if f.have >= f.n and o.fill and f.cost <= o.fill.cost * 1.1 then o.fill = f break end
    end
    if o.fill then
      o.haveFill = o.fill.have >= o.fill.n
      if o.crateCost then
        o.total = o.crateCost + o.fill.cost
        o.perFavor = o.total / c.favor
      end
    end
    list[#list + 1] = o
  end
  table.sort(list, function(a, b)
    if (a.perFavor ~= nil) ~= (b.perFavor ~= nil) then return a.perFavor ~= nil end
    if a.perFavor and b.perFavor and a.perFavor ~= b.perFavor then return a.perFavor < b.perFavor end
    return a.crate.id < b.crate.id
  end)
  return list
end
