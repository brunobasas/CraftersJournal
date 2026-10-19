local _, ES = ...

-- Planificador de subida de profesión.
-- Para cada punto de habilidad elige la receta con menor coste esperado:
-- (materiales para 1/probabilidad fabricaciones) - (lo que recuperas vendiendo).
--
-- Materiales, por orden: lo que tienes en bolsas, lo que recolectas tú, lo
-- fabricado en pasos anteriores (si sale más barato que venderlo y comprar),
-- vendedor, AH o fabricarlo. En la AH se recorren las subastas de más barata a
-- más cara descontando lo ya comprado; con ignoreSupply (lo que usa la UI), lo
-- que exceda de lo anunciado se paga a la mediana en vez de parar el plan.

local Planner = {}
ES.Planner = Planner

-- Comisión y depósito de la AH (Classic / WoW Forever, subastas de 2, 8 o 24 h).
-- Depósito = precio de vendedor x unidades x tasa por cada 2 h: 5% en la AH de
-- tu facción (2 h = 5%, 8 h = 20%, 24 h = 60%) y 5 veces más en la neutral.
-- Se pierde si la subasta no se vende; aquí se cuenta como coste de vender en la AH.
local AH_CUT, AH_CUT_NEUTRAL = 0.05, 0.15
local DEPOSIT_RATE, DEPOSIT_RATE_NEUTRAL = 0.05, 0.25
Planner.DURATIONS = { 2, 8, 24 }

-- Depósito por unidad y comisión según la AH y la duración elegidas
function Planner.AuctionCosts(vendorPrice, opts)
  local hours = opts.hours or 24
  local rate = opts.neutral and DEPOSIT_RATE_NEUTRAL or DEPOSIT_RATE
  return (vendorPrice or 0) * rate * hours / 2, opts.neutral and AH_CUT_NEUTRAL or AH_CUT
end
local APPRENTICE_CAP = 75
local BASIC_MAX_YELLOW = 50 -- recetas sin instructor ni pergamino por debajo de esto: básicas
-- Coste simbólico por fabricación y cuánto más puede costar la ruta que lo tiene
-- en cuenta frente a la más barata (ver Planner:Plan)
local CRAFT_COST = 5          -- cobre por fabricación, solo para elegir
local MAX_EXTRA_PCT = 0.03    -- hasta un 3% de los materiales más
local MAX_EXTRA_MIN = 100     -- o 1 plata, lo que sea mayor
-- Recetas de pago usadas menos puntos de los supuestos al elegirlas (ver Planner:Plan)
local FEE_PASSES = 4          -- pasadas como mucho
local FEE_SLACK = 0.75        -- se repite si se usó menos del 75% de lo supuesto

-- Fabricaciones totales de un plan
function Planner.TotalCrafts(plan)
  local n = 0
  for _, st in ipairs(plan.steps or {}) do n = n + st.crafts end
  return n
end
local MAX_CRAFT_DEPTH = 3
local EPS = 1e-6

-- Probabilidad clásica de subir punto
function Planner.Chance(t, skill)
  local yellow, grey = t[2], t[4]
  if skill < yellow then return 1 end
  if skill >= grey then return 0 end
  return (grey - skill) / (grey - yellow)
end

-- Recetas de pergamino buscadas por sus fuentes reales (misión, vendedor, AH;
-- ver Waypoints.RecipeSource): solo si la profesión está en la prueba piloto
local function Sourced(recipe, opts)
  return opts.sourcedScrolls and recipe.scroll and not recipe.fee
end

local function ScanPrices()
  local scan = ES.db and ES.db.scans and ES.db.scans[ES:RealmKey()]
  return scan and scan.items or {}
end

-- ¿Ya la sabe el personaje? (necesita recipe.id; ver Annotate)
local function Known(recipe)
  return recipe.id and ES.IsRecipeKnown and ES:IsRecipeKnown(recipe.id)
end

-- Cada receta guarda su id (el hechizo) para poder preguntar si ya se sabe
local function Annotate(data)
  if data._annotated then return end
  for id, r in pairs(data.recipes) do r.id = id end
  data._annotated = true
end
Planner.Annotate = Annotate

-- Nivel mínimo para aprender la receta, o nil si no la consideramos disponible
function Planner.LearnSkill(recipe, opts)
  if Known(recipe) then return recipe.train or 1 end -- ya la sabes: siempre disponible
  if recipe.rep and not ES:RepMet(recipe.rep) then return nil end -- te falta reputación
  if Sourced(recipe, opts) then
    local src = ES.Waypoints.RecipeSource(recipe, ScanPrices(), opts.noQuests)
    return src and src.best and (recipe.train or 1) or nil
  end
  if recipe.fee or recipe.intermediate then return recipe.train end
  if not recipe.scroll and recipe.t[2] <= BASIC_MAX_YELLOW then return 1 end -- básica
  if not opts.includeScrolls then return nil end
  if recipe.scroll then return recipe.train end
  -- Sin instructor ni pergamino conocido (misión, reputación...): estimación
  return math.max(1, recipe.t[2] - 10)
end

-- Cuánto cuesta aprender la receta y de dónde: "known" (ya la sabes), "trainer",
-- "vendor", "scroll", "owned" (pergamino en tus bolsas), "quest", "ah" o "unknown"
function Planner.LearnCost(ctx, recipe)
  if Known(recipe) then return 0, "known" end
  if recipe.rep and not ES:RepMet(recipe.rep) then return 0, "rep" end -- solo para la vista Recetas
  if recipe.fee then return recipe.fee, "trainer" end
  if Sourced(recipe, ctx.opts) then
    local src = ES.Waypoints.RecipeSource(recipe, ScanPrices(), ctx.opts.noQuests)
    if src and src.best then return src.best.cost, src.best.kind end
    return 0, "unknown"
  end
  if recipe.intermediate then return 0, nil end -- precio del instructor desconocido
  if recipe.scroll then
    local ah = ctx.prices[recipe.scroll]
    if ah and ah.minUnit then return ah.minUnit, "scroll" end
    return 0, "unknown"
  end
  if recipe.t[2] <= BASIC_MAX_YELLOW then return 0, nil end
  return 0, "unknown"
end

---------------------------------------------------------------------------
-- Existencias y precios
---------------------------------------------------------------------------
-- Escalera { p1, q1, p2, q2, ... }; los escaneos antiguos solo tienen el mínimo
local function Ladder(entry)
  if not entry then return nil end
  if entry.ladder and #entry.ladder > 0 then return entry.ladder end
  if entry.minUnit then return { entry.minUnit, entry.quantity or 1 } end
  return nil
end

local function LadderSupply(ladder)
  local total = 0
  for i = 2, #ladder, 2 do total = total + ladder[i] end
  return total
end

-- Precio por unidad de la unidad mediana anunciada (no le afectan ni una
-- subasta suelta muy barata ni una absurdamente cara)
local function MedianPrice(ladder)
  local half = LadderSupply(ladder) / 2
  local acc = 0
  for i = 1, #ladder, 2 do
    acc = acc + ladder[i + 1]
    if acc >= half then return ladder[i] end
  end
  return ladder[#ladder - 1]
end
Planner.MedianPrice = MedianPrice

-- Coste de comprar `qty` unidades después de las `used` ya compradas; nil si no hay bastantes
local function LadderCost(ladder, used, qty)
  local cost, skip, need = 0, used, qty
  for i = 1, #ladder, 2 do
    local price, q = ladder[i], ladder[i + 1]
    if skip >= q then
      skip = skip - q
    else
      local take = math.min(q - skip, need)
      skip = 0
      cost = cost + take * price
      need = need - take
      if need <= EPS then return cost end
    end
  end
  return nil
end

local function NewContext(data, opts)
  Annotate(data)
  local scan = ES.db.scans[ES:RealmKey()]
  local ctx = {
    data = data,
    opts = opts,
    prices = scan and scan.items or {},
    scanTime = scan and scan.time,
    ladders = {},
    supply = {},     -- unidades a la venta de cada objeto (suma de su escalera)
    medians = {},    -- mediana de lo anunciado (con todos los precios; ver Scanner.BuildLadder)
    used = {},       -- unidades de cada objeto ya compradas en la AH por el plan
    stock = {},      -- inventario del plan: lo fabricado en pasos anteriores, por lotes de valor
    owned = {},      -- lo que llevas en bolsas/banco y queda por usar
    visiting = {},
    producers = {},
  }
  for itemID, entry in pairs(ctx.prices) do
    local ladder = Ladder(entry)
    ctx.ladders[itemID] = ladder
    ctx.supply[itemID] = ladder and LadderSupply(ladder)
    ctx.medians[itemID] = entry.median
  end
  for itemID, count in pairs(opts.owned or {}) do
    if count > 0 then ctx.owned[itemID] = count end
  end
  -- Herramientas por familia (bastones rúnicos, martillo, piedra filosofal):
  -- dentro de una familia la mejor que ya tienes cubre las inferiores
  ctx.toolMask = {}
  for _, tool in pairs(ES.Data.Tools or {}) do
    local fam = tool.family or "rod"
    if (opts.owned or {})[tool.item] and tool.mask > (ctx.toolMask[fam] or 0) then ctx.toolMask[fam] = tool.mask end
  end
  for id, r in pairs(data.recipes) do
    local learn = r.out and Planner.LearnSkill(r, opts)
    if learn and learn <= opts.to then
      local list = ctx.producers[r.out[1]] or {}
      list[#list + 1] = id
      ctx.producers[r.out[1]] = list
    end
  end
  return ctx
end

local function Copy(t)
  local c = {}
  for k, v in pairs(t) do c[k] = v end
  return c
end

-- Lotes del inventario del plan: { valor1, cantidad1, ... } de menor a mayor valor
local function AddLot(lots, value, qty)
  if qty <= EPS then return end
  value = math.floor(value + 0.5)
  for i = 1, #lots, 2 do
    if lots[i] == value then lots[i + 1] = lots[i + 1] + qty return end
    if lots[i] > value then
      table.insert(lots, i, qty)
      table.insert(lots, i, value)
      return
    end
  end
  lots[#lots + 1] = value
  lots[#lots + 1] = qty
end

-- Saca `qty` del inventario empezando por lo de menor valor
local function ConsumeLots(lots, qty)
  while qty > EPS and #lots > 0 do
    local take = math.min(lots[2], qty)
    lots[2] = lots[2] - take
    qty = qty - take
    if lots[2] <= EPS then
      table.remove(lots, 1)
      table.remove(lots, 1)
    end
  end
end

-- Consigue `qty` unidades de un objeto por la vía más barata disponible.
-- Primero lo que ya has fabricado en pasos anteriores (inventario del plan:
-- cuesta lo que dejas de ganar al no venderlo); el resto del vendedor, la AH
-- (según existencias) o fabricándolo. Devuelve el coste o nil, y anota en
-- `extra` lo gastado (AH con clave itemID, inventario con clave -itemID) y en
-- `actions` lo que hay que hacer. `why` recoge el motivo cuando no se puede:
-- "price" (sin precio) o "supply" (no hay bastantes).
local function Acquire(ctx, itemID, qty, depth, extra, actions, why, skip)
  -- 1. Lo que ya llevas en bolsas/banco: gratis
  local have = skip == nil and ctx.owned[itemID]
  if have then
    local ownKey = "o" .. itemID
    local usedNow = extra[ownKey] or 0
    local avail = have - usedNow
    if avail > EPS then
      local take = math.min(avail, qty)
      extra[ownKey] = usedNow + take
      actions[#actions + 1] = { kind = "owned", item = itemID, qty = take, cost = 0 }
      if qty - take <= EPS then return 0 end
      return Acquire(ctx, itemID, qty - take, depth, extra, actions, why, "owned")
    end
  end

  -- 2. Lo fabricado en pasos anteriores del plan
  local lots = skip ~= "all" and ctx.opts.reuseCrafted and ctx.stock[itemID]
  if lots then
    local usedNow = extra[-itemID] or 0
    local avail = LadderSupply(lots) - usedNow
    if avail > EPS then
      -- Opción A: lo que tienes (hasta donde llegue) y el resto por otra vía
      local take = math.min(avail, qty)
      local exA, acA = Copy(extra), {}
      local costA = LadderCost(lots, usedNow, take)
      exA[-itemID] = usedNow + take
      acA[1] = { kind = "stock", item = itemID, qty = take, cost = costA }
      if qty - take > EPS then
        local rest = Acquire(ctx, itemID, qty - take, depth, exA, acA, why, "all")
        costA = rest and costA + rest or nil
      end
      -- Opción B: no tocar el inventario (se vende) y conseguirlo por otra vía
      local exB, acB = Copy(extra), {}
      local costB = Acquire(ctx, itemID, qty, depth, exB, acB, why, "all")

      local useA = costA and (not costB or costA <= costB)
      local cost, ex, ac = costB, exB, acB
      if useA then cost, ex, ac = costA, exA, acA end
      if not cost then return nil end
      for k, v in pairs(ex) do extra[k] = v end
      for _, a in ipairs(ac) do actions[#actions + 1] = a end
      return cost
    end
  end

  local best, kind, craft
  local vendor = ES.Data.VendorPrices[itemID]
  if vendor then best, kind = vendor * qty, "vendor" end

  local ladder = ctx.ladders[itemID]
  if ladder then
    local cost
    local used = (ctx.used[itemID] or 0) + (extra[itemID] or 0)
    if ctx.opts.ignoreSupply then
      -- Lo anunciado se compra de más barata a más cara, descontando lo que el
      -- plan ya ha comprado (lo que pagarías de verdad). Si hace falta más de lo
      -- que hay a la venta, el resto al precio de referencia (mediana): el plan
      -- no se para por existencias.
      local fromAH = math.min(qty, math.max(0, ctx.supply[itemID] - used))
      local median = ctx.medians[itemID] or MedianPrice(ladder)
      cost = (fromAH > EPS and (LadderCost(ladder, used, fromAH) or fromAH * median) or 0) + (qty - fromAH) * median
    else
      cost = LadderCost(ladder, used, qty)
    end
    if cost then
      if not best or cost < best then best, kind = cost, "ah" end
    elseif not vendor then
      why[itemID] = why[itemID] or "supply"
    end
  end

  if depth < MAX_CRAFT_DEPTH and ctx.producers[itemID] and not ctx.visiting[itemID] then
    ctx.visiting[itemID] = true
    for _, rid in ipairs(ctx.producers[itemID]) do
      local r = ctx.data.recipes[rid]
      local crafts = qty / r.out[2]
      local subExtra, subActions, total = Copy(extra), {}, 0
      for _, rq in ipairs(r.r) do
        local cost = Acquire(ctx, rq[1], rq[2] * crafts, depth + 1, subExtra, subActions, why)
        if not cost then total = nil break end
        total = total + cost
      end
      if total and (not best or total < best) then
        best, kind = total, "craft"
        craft = { extra = subExtra, actions = subActions, recipe = rid }
      end
    end
    ctx.visiting[itemID] = nil
  end

  if not best then
    if not ladder and not vendor then why[itemID] = why[itemID] or "price" end
    return nil
  end

  if kind == "craft" then
    for k, v in pairs(craft.extra) do extra[k] = v end
    for _, a in ipairs(craft.actions) do actions[#actions + 1] = a end
    actions[#actions + 1] = { kind = "craft", item = itemID, qty = qty, cost = best, recipe = craft.recipe }
  else
    if kind == "ah" then extra[itemID] = (extra[itemID] or 0) + qty end
    actions[#actions + 1] = { kind = kind, item = itemID, qty = qty, cost = best }
  end
  return best
end

-- Cuánto costaría fabricar tú 1 unidad de un objeto (la receta más barata que
-- lo produce), sin usar inventario ni bolsas. nil si no se fabrica o falta precio.
-- Sirve para explicar en la lista de la compra por qué se compra en vez de fabricar.
function Planner.CraftUnitCost(ctx, itemID)
  local best, bestRecipe
  for _, rid in ipairs(ctx.producers[itemID] or {}) do
    local r = ctx.data.recipes[rid]
    local total = 0
    for _, rq in ipairs(r.r) do
      local c = Acquire(ctx, rq[1], rq[2], 1, {}, {}, {}, "all")
      if not c then total = nil break end
      total = total + c
    end
    if total then
      total = total / r.out[2]
      if not best or total < best then best, bestRecipe = total, r end
    end
  end
  return best, bestRecipe
end

-- Coste de los materiales de `crafts` fabricaciones; devuelve también el
-- desglose por material, lo comprado en la AH y las acciones
local function RecipeCost(ctx, recipe, crafts, why)
  local extra, actions, total, reagents = {}, {}, 0, {}
  for _, rq in ipairs(recipe.r) do
    local first = #actions + 1
    local cost = Acquire(ctx, rq[1], rq[2] * crafts, 0, extra, actions, why)
    if not cost then return nil end
    total = total + cost
    -- De dónde sale este material (puede ser una mezcla: inventario + AH...)
    local kinds = {}
    for i = first, #actions do
      if actions[i].item == rq[1] then kinds[actions[i].kind] = true end
    end
    reagents[#reagents + 1] = { item = rq[1], qty = rq[2] * crafts, cost = cost, kinds = kinds }
  end
  return total, reagents, extra, actions
end

Planner.RecipeCost = RecipeCost -- coste de N fabricaciones subiendo por la escalera (Earn.lua)

-- Cómo se puede vender lo que fabrica una receta (precios por unidad).
-- No se puede saber cuánto se vende en la AH (el juego no lo dice), así que el
-- plan valora lo fabricado a precio de vendedor, que es seguro. La AH queda
-- como opción: lo que te quedaría igualando a la más barata (menos comisión y
-- depósito), con las alertas de mercado para juzgar si se venderá.
function Planner.SaleInfo(ctx, recipe)
  if not recipe.out then return nil end
  local itemID = recipe.out[1]
  local vendor = ES:VendorSellPrice(itemID)
  if not vendor then ctx.pendingInfo = true end -- el juego aún no ha cargado el objeto
  local sale = { itemID = itemID, qty = recipe.out[2], vendor = vendor or 0 }
  local ah = ctx.prices[itemID]
  sale.ahMin = ah and ah.minUnit
  sale.risk = ES:PriceRisk(itemID, ah)
  sale.deposit, sale.cut = Planner.AuctionCosts(sale.vendor, ctx.opts)
  sale.duration = ctx.opts.hours or 24 -- duración de la subasta (h)
  -- Precio realista (si el mínimo de ahora está inflado frente al histórico, el de referencia)
  -- Lo que se liga al recogerlo no se puede vender en la AH: solo al vendedor
  sale.fair = not recipe.bop and ES.Market:FairPrice(itemID, sale.ahMin) or nil
  if sale.fair then
    sale.ahPrice = sale.fair.price
    local net = sale.ahPrice * (1 - sale.cut) - sale.deposit
    if net > sale.vendor then sale.ahNet = net end
  end
  return sale
end

-- Qué hacer con lo que sobra de un objeto fabricado (d = plan.destinations[i]).
-- Solo merece la pena la AH si deja bastante más que el vendedor; cuánto anunciar
-- depende de las alertas de mercado:
--   good    -> anúncialos todos
--   watch / unknown -> unos pocos (AH_FEW) y el resto al vendedor
--   avoid   -> al vendedor
-- Devuelve { kind = "keep" | "vendor" | "ah" | "none", ah = n, vendor = n, price, verdict }
local AH_MIN_GAIN, AH_MIN_GAIN_PCT, AH_FEW = 5, 0.15, 5
function Planner.SaleAdvice(d)
  local sale = d.sale
  local a = { ah = 0, vendor = 0, unsold = 0 }
  if d.sell <= 0 then a.kind = "keep" return a end
  local worth = sale.ahNet and sale.ahNet - sale.vendor >= math.max(AH_MIN_GAIN, sale.vendor * AH_MIN_GAIN_PCT)
  if worth then
    local s = ES.Market:Signals(sale.itemID)
    a.verdict = s.verdict
    if s.verdict == "good" then
      a.ah = d.sell
    elseif s.verdict ~= "avoid" then
      a.ah = math.min(d.sell, AH_FEW)
    end
    -- Precio: 1 cobre por debajo de la más barata, o el realista si está inflada
    a.price = ES.Market.ListPrice(sale.fair) or 1
    a.inflated = sale.fair and sale.fair.inflated
  end
  a.vendor = sale.vendor > 0 and d.sell - a.ah or 0
  a.unsold = d.sell - a.ah - a.vendor -- ni AH ni vendedor
  if a.ah > 0 then
    a.kind = "ah"
  elseif sale.vendor > 0 then
    a.kind = "vendor"
  else
    a.kind = "none" -- ni la AH compensa ni lo compra el vendedor
  end
  return a
end

-- Valor de fabricar `crafts` veces: a precio de vendedor (ver SaleInfo)
local function SaleValue(sale, crafts)
  if not sale then return 0 end
  return crafts * sale.qty * sale.vendor
end

---------------------------------------------------------------------------
-- Plan
---------------------------------------------------------------------------
-- opts = { from, to, includeScrolls, hours (duración subasta), neutral, reuseCrafted, ignoreSupply, cap,
--          owned = { [itemID] = cantidad en bolsas/banco } }
function Planner:Plan(data, opts)
  -- Con lo de tus bolsas: la ruta se elige como si no lo tuvieras y luego se
  -- recorre usándolo. Si no, como lo tuyo sale gratis, el plan se desvía para
  -- gastarlo cuanto antes (2 fabricaciones de una receta y vuelta a la otra), y
  -- no ahorra nada: esos materiales se iban a usar igual más adelante.
  if opts.owned and next(opts.owned) and not opts.forced then
    local base, withBags = {}, {}
    for k, v in pairs(opts) do base[k], withBags[k] = v, v end
    base.owned = nil
    local route = Planner:Plan(data, base)
    withBags.forced = route.choice
    local plan = Planner:Plan(data, withBags)
    plan.cheapest = route.cheapest
    return plan
  end

  -- Coste simbólico por fabricación: se buscan dos rutas, la más barata pura y
  -- otra en la que cada fabricación "cuesta" CRAFT_COST (no se cobra: solo pesa
  -- al elegir). La segunda solo se usa si apenas cuesta más (MAX_EXTRA_PCT de los
  -- materiales, mínimo MAX_EXTRA_MIN) y llega igual de lejos: el addon sigue
  -- dando la ruta más barata, pero sin cientos de fabricaciones por un ahorro mínimo.
  if not opts.forced and opts.craftCost == nil then
    local cheapOpts, balancedOpts = {}, {}
    for k, v in pairs(opts) do cheapOpts[k], balancedOpts[k] = v, v end
    cheapOpts.craftCost, balancedOpts.craftCost = 0, CRAFT_COST
    local cheap = Planner:Plan(data, cheapOpts)
    local balanced = Planner:Plan(data, balancedOpts)
    local allowed = math.max(MAX_EXTRA_MIN, MAX_EXTRA_PCT * cheap.reagentCost)
    local cheapCrafts, balancedCrafts = Planner.TotalCrafts(cheap), Planner.TotalCrafts(balanced)
    if balanced.reached >= cheap.reached and balanced.net <= cheap.net + allowed and balancedCrafts < cheapCrafts then
      balanced.cheapest = { net = cheap.net, crafts = cheapCrafts }
      return balanced
    end
    return cheap
  end

  -- Recetas de pago (pergamino, instructor): al elegirlas, su precio se reparte
  -- entre los puntos que quedan hasta que se ponen grises. Si luego la ruta solo
  -- la usa unos pocos (otra receta pasa a ser mejor), el reparto era demasiado
  -- optimista (Deviate Scale Cloak: pergamino de 70s para 3 fabricaciones). Se
  -- repite el plan repartiendo el precio solo entre los puntos que de verdad la
  -- usa; se queda el plan que llega más lejos y, a igualdad, el más barato.
  if not opts.forced and not opts.feeSpan then
    local o = {}
    for k, v in pairs(opts) do o[k] = v end
    o.feeSpan = {}
    local best
    for _ = 1, FEE_PASSES do
      local plan = Planner:Plan(data, o)
      if not best or plan.reached > best.reached or (plan.reached == best.reached and plan.net < best.net - EPS) then
        best = plan
      end
      local changed = false
      for id, use in pairs(plan.feeUse or {}) do
        if use.points < use.assumed * FEE_SLACK and (not o.feeSpan[id] or use.points < o.feeSpan[id]) then
          o.feeSpan[id] = use.points
          changed = true
        end
      end
      if not changed then break end
    end
    return best
  end

  local ctx = NewContext(data, opts)
  local plan = {
    choice = {}, -- [nivel] = receta elegida para ese punto
    from = opts.from, to = opts.to, scanTime = ctx.scanTime,
    steps = {}, ranks = {}, shopping = {}, crafted = {}, kept = {}, keptByItem = {},
    reagentCost = 0, resale = 0, fees = 0,
    stockValue = 0, -- valor de lo que se usa del inventario (venta a la que renuncias)
    owned = {},
    tools = {}, toolsCost = 0, -- herramientas (bastones rúnicos) que hay que conseguir
    missingPrice = {}, shortSupply = {},
  }

  -- Recetas candidatas y lo que no depende del nivel
  local info = {}
  for id, r in pairs(data.recipes) do
    local learn = Planner.LearnSkill(r, opts)
    -- opts.excluded: recetas que el jugador ha quitado de la ruta (p. ej. el pergamino está lejos)
    if learn and learn < opts.to and r.t[4] > opts.from and not (opts.excluded and opts.excluded[id]) then
      local learnCost, learnSource = Planner.LearnCost(ctx, r)
      info[id] = { learn = learn, sale = Planner.SaleInfo(ctx, r), learnCost = learnCost, learnSource = learnSource }
    end
  end

  -- Voraz: el mejor por cada punto, gastando existencias de la AH
  local learned = {}
  local bought = {} -- [itemID] = { ahQty, ahCost, vendorQty, vendorCost }
  local craftedQty = {}
  local keptQty = {}  -- [itemID] = unidades fabricadas en el plan que se usan después
  local keptFor = {}  -- [itemID] = { [recetaQueLoUsa] = unidades }
  local ownedQty = {} -- [itemID] = unidades que se usan de tus bolsas/banco
  local perPoint = {}
  local lastWhy

  for s = opts.from, opts.to - 1 do
    local best
    local why = {}
    local blocked = {} -- recetas que se podrían usar pero les falta el precio de algún material
    -- Ruta fijada (ver arriba): en ese punto solo vale la receta ya elegida; donde
    -- la ruta sin bolsas se paraba, lo tuyo puede permitir seguir con cualquiera
    local forced = opts.forced and opts.forced[s]
    for id, inf in pairs(info) do
      ES.Yield() -- calculado como trabajo (Jobs.lua): sigue en el siguiente fotograma
      if inf.learn <= s and (not forced or forced == id) then
        local r = data.recipes[id]
        local chance = Planner.Chance(r.t, s)
        if chance > 0 then
          local crafts = 1 / chance
          local whyR = {}
          local cost, reagents, extra, actions = RecipeCost(ctx, r, crafts, whyR)
          -- Herramienta que pide (se consigue una sola vez, la primera vez que hace falta)
          local toolCost, tool
          if cost and r.tool then
            tool = ES.Data.Tools[r.tool]
            if tool and (ctx.toolMask[tool.family or "rod"] or 0) < tool.mask then
              toolCost = Acquire(ctx, tool.item, 1, 0, extra, actions, whyR)
              if not toolCost then cost = nil end
            else
              tool = nil
            end
          end
          for itemID, reason in pairs(whyR) do why[itemID] = why[itemID] or reason end
          if not cost then
            blocked[#blocked + 1] = { id = id, chance = chance, missing = whyR }
          else
            local value = SaleValue(inf.sale, crafts)
            -- Coste simbólico de cada fabricación (solo al elegir; ver Plan)
            local score = cost - value + (opts.craftCost or 0) * crafts
            local span = math.max(1, math.min(r.t[4], opts.to) - s)
            local feeSpan
            if inf.learnCost > 0 and not learned[id] then
              -- Entre los puntos que la usó la pasada anterior, si fueron menos (ver arriba)
              feeSpan = math.max(1, math.min(span, opts.feeSpan and opts.feeSpan[id] or span))
              score = score + inf.learnCost / feeSpan
            end
            if toolCost then score = score + toolCost / span end
            if not best or score < best.score then
              best = {
                id = id, score = score, crafts = crafts, chance = chance, cost = cost, value = value,
                reagents = reagents, extra = extra, actions = actions,
                tool = tool, toolCost = toolCost or 0, feeSpan = feeSpan,
              }
            end
          end
        end
      end
    end

    if not best then
      plan.stoppedAt = s
      lastWhy = why
      break
    end

    -- Herramienta conseguida: ya cubre esta categoría y las inferiores
    if best.tool then
      local fam = best.tool.family or "rod"
      ctx.toolMask[fam] = math.max(ctx.toolMask[fam] or 0, best.tool.mask)
      plan.tools[#plan.tools + 1] = { item = best.tool.item, cost = best.toolCost, skill = s }
      plan.toolsCost = plan.toolsCost + best.toolCost
    end

    -- Recetas con más probabilidad que la elegida que no se pueden usar por falta de precio
    best.blocked = {}
    for _, b in ipairs(blocked) do
      if b.chance > best.chance then best.blocked[#best.blocked + 1] = b end
    end

    -- Confirmar: gastar existencias de la AH y del inventario, y anotar compras
    learned[best.id] = true
    for key, q in pairs(best.extra) do
      if type(key) == "string" then
        local itemID = tonumber(key:sub(2))
        ctx.owned[itemID] = ctx.owned[itemID] - q
      elseif key > 0 then
        ctx.used[key] = (ctx.used[key] or 0) + q
      else
        ConsumeLots(ctx.stock[-key], q)
      end
    end
    for _, a in ipairs(best.actions) do
      if a.kind == "craft" then
        craftedQty[a.item] = craftedQty[a.item] or { qty = 0, recipe = a.recipe }
        craftedQty[a.item].qty = craftedQty[a.item].qty + a.qty
      elseif a.kind == "stock" then
        keptQty[a.item] = (keptQty[a.item] or 0) + a.qty
        plan.stockValue = plan.stockValue + a.cost
        -- Para qué receta se guarda
        keptFor[a.item] = keptFor[a.item] or {}
        keptFor[a.item][best.id] = (keptFor[a.item][best.id] or 0) + a.qty
      elseif a.kind == "owned" then
        ownedQty[a.item] = (ownedQty[a.item] or 0) + a.qty
      else
        local b = bought[a.item] or { ahQty = 0, ahCost = 0, vendorQty = 0, vendorCost = 0 }
        bought[a.item] = b
        if a.kind == "ah" then
          b.ahQty, b.ahCost = b.ahQty + a.qty, b.ahCost + a.cost
        else
          b.vendorQty, b.vendorCost = b.vendorQty + a.qty, b.vendorCost + a.cost
        end
      end
    end
    -- Lo fabricado entra al inventario del plan, valorado como se ha contado su venta
    local sale = info[best.id].sale
    if sale then
      ctx.stock[sale.itemID] = ctx.stock[sale.itemID] or {}
      AddLot(ctx.stock[sale.itemID], sale.vendor, best.crafts * sale.qty)
    end
    perPoint[#perPoint + 1] = best
    best.skill = s
    plan.choice[s] = best.id
  end

  -- Recetas de pago: entre cuántos puntos se repartió su precio y cuántos se usaron
  plan.feeUse = {}
  for _, p in ipairs(perPoint) do
    local use = plan.feeUse[p.id]
    if use then
      use.points = use.points + 1
    elseif p.feeSpan then
      plan.feeUse[p.id] = { assumed = p.feeSpan, points = 1 }
    end
  end

  -- Por qué se paró: materiales sin precio o sin existencias suficientes
  if lastWhy then
    for itemID, reason in pairs(lastWhy) do
      if reason == "supply" then plan.shortSupply[itemID] = true else plan.missingPrice[itemID] = true end
    end
  end

  -- Rangos del instructor (Oficial, Experto, Artesano...) que el plan necesita
  local reached = plan.stoppedAt or opts.to
  local caps = { APPRENTICE_CAP }
  for _, rank in ipairs(data.ranks) do caps[#caps + 1] = rank[1] end
  -- Tope actual: el real del juego si se conoce (p. ej. 75 con Aprendiz); si
  -- no, se supone entrenado el rango que cubre el nivel de partida
  local currentCap = opts.cap
  if not currentCap then
    for _, c in ipairs(caps) do
      if c > opts.from then currentCap = c break end
    end
  end
  for i, rank in ipairs(data.ranks) do
    local prevCap = caps[i]
    if rank[1] > (currentCap or 0) and prevCap < reached then
      plan.ranks[#plan.ranks + 1] = { cap = rank[1], fee = rank[2], skill = math.max(opts.from, rank[3]), level = rank[4] }
      plan.fees = plan.fees + rank[2]
    end
  end

  -- Agrupar puntos consecutivos con la misma receta
  local step
  for _, p in ipairs(perPoint) do
    if not (step and step.id == p.id) then
      step = {
        id = p.id, from = p.skill, expected = 0, costSum = 0, valueSum = 0,
        reagents = {}, firstChance = p.chance, blocked = {},
      }
      plan.steps[#plan.steps + 1] = step
    end
    step.to = p.skill + 1
    step.lastChance = p.chance
    for _, b in ipairs(p.blocked) do
      local missing = step.blocked[b.id]
      if not missing then
        missing = {}
        step.blocked[b.id] = missing
        step.blocked[#step.blocked + 1] = b.id
      end
      for itemID in pairs(b.missing) do missing[itemID] = true end
    end
    step.expected = step.expected + p.crafts
    step.costSum = step.costSum + p.cost
    step.valueSum = step.valueSum + p.value
    for _, rg in ipairs(p.reagents) do
      local agg = step.reagents[rg.item]
      if not agg then
        agg = { item = rg.item, qty = 0, cost = 0, kinds = {} }
        step.reagents[rg.item] = agg
        step.reagents[#step.reagents + 1] = agg
      end
      agg.qty = agg.qty + rg.qty
      agg.cost = agg.cost + rg.cost
      for kind in pairs(rg.kinds) do agg.kinds[kind] = true end
    end
  end

  local feePaid = {}
  for _, st in ipairs(plan.steps) do
    local inf = info[st.id]
    st.recipe = data.recipes[st.id]
    st.crafts = math.ceil(st.expected - 0.001)
    st.unitCost = st.costSum / st.expected
    st.unitValue = st.valueSum / st.expected
    st.sale = inf.sale
    local firstUse = not feePaid[st.id]
    st.fee = firstUse and inf.learnCost or 0
    st.learnSource = firstUse and inf.learnSource or nil
    feePaid[st.id] = true
    st.total = st.crafts * (st.unitCost - st.unitValue) + st.fee

    plan.reagentCost = plan.reagentCost + st.crafts * st.unitCost
    plan.resale = plan.resale + st.crafts * st.unitValue
    plan.fees = plan.fees + st.fee
  end

  -- Lista de la compra (separando AH y vendedor) y lo que conviene fabricar antes
  for itemID, b in pairs(bought) do
    local supply = ctx.ladders[itemID] and LadderSupply(ctx.ladders[itemID])
    if b.ahQty > EPS then
      plan.shopping[#plan.shopping + 1] = {
        itemID = itemID, quantity = math.ceil(b.ahQty - 0.001), source = "ah",
        unit = b.ahCost / b.ahQty, total = b.ahCost, supply = supply,
      }
    end
    if b.vendorQty > EPS then
      plan.shopping[#plan.shopping + 1] = {
        itemID = itemID, quantity = math.ceil(b.vendorQty - 0.001), source = "vendor",
        unit = b.vendorCost / b.vendorQty, total = b.vendorCost,
      }
    end
  end
  table.sort(plan.shopping, function(a, b) return a.total > b.total end)

  for itemID, c in pairs(craftedQty) do
    plan.crafted[#plan.crafted + 1] = { itemID = itemID, quantity = math.ceil(c.qty - 0.001), recipe = data.recipes[c.recipe] }
  end

  -- Lo que sale de tus bolsas
  plan.owned = {}
  for itemID, q in pairs(ownedQty) do plan.owned[#plan.owned + 1] = { itemID = itemID, quantity = math.ceil(q - 0.001) } end
  table.sort(plan.owned, function(a, b) return a.quantity > b.quantity end)

  -- Lo que hay que guardar de tus fabricaciones para pasos posteriores
  plan.kept, plan.keptByItem = {}, {}
  for itemID, q in pairs(keptQty) do
    local qty = math.ceil(q - 0.001)
    plan.kept[#plan.kept + 1] = { itemID = itemID, quantity = qty }
    plan.keptByItem[itemID] = qty
  end

  -- Qué hacer con cada cosa que fabricas: guardar (para qué paso) o vender. El
  -- coste del plan cuenta la venta al vendedor; si en la AH te quedaría más,
  -- se indica como opción (ahExtra), sin sumarlo: no se sabe si se venderá.
  plan.destinations = {}
  local destByItem = {}
  for _, st in ipairs(plan.steps) do
    local sale = st.sale
    if sale then
      local d = destByItem[sale.itemID]
      if not d then
        d = { itemID = sale.itemID, produced = 0, sale = sale, firstStep = st }
        destByItem[sale.itemID] = d
        plan.destinations[#plan.destinations + 1] = d
      end
      d.produced = d.produced + st.crafts * sale.qty
    end
  end
  for itemID, d in pairs(destByItem) do
    d.produced = math.floor(d.produced + 0.5)
    d.keep = math.min(d.produced, plan.keptByItem[itemID] or 0)
    d.sell = d.produced - d.keep
    d.ahExtra = d.sale.ahNet and d.sell * (d.sale.ahNet - d.sale.vendor) or nil
    -- Para qué pasos se guarda
    d.usedIn = {}
    for recipeID, q in pairs(keptFor[itemID] or {}) do
      local where
      for _, st in ipairs(plan.steps) do
        if st.id == recipeID then where = st break end
      end
      d.usedIn[#d.usedIn + 1] = { recipe = data.recipes[recipeID], qty = math.ceil(q - 0.001), step = where }
    end
    table.sort(d.usedIn, function(a, b) return (a.step and a.step.from or 0) < (b.step and b.step.from or 0) end)
    d.income = d.sell * d.sale.vendor
  end

  plan.pendingInfo = ctx.pendingInfo
  plan.ctx = ctx
  plan.net = plan.reagentCost - plan.resale + plan.fees + plan.toolsCost
  plan.reached = reached
  return plan
end

---------------------------------------------------------------------------
-- Recetas y AH: cada receta que puedes conseguir ahora (instructor, vendedor,
-- básica o pergamino anunciado en la AH) con lo que cuesta fabricar 1 y a
-- cuánto se anuncia lo fabricado. Sin estimar ventas: se compara con el mínimo
-- anunciado, que es lo que tendrías que igualar para vender.
---------------------------------------------------------------------------
-- opts.all: todas las recetas (también las que no puedes conseguir ahora y las
-- que no fabrican objeto, como los encantamientos), para la Colección
function Planner:RecipeMarket(data, opts)
  local o = { from = 1, to = 300, includeScrolls = false, ignoreSupply = true,
    hours = opts.hours, neutral = opts.neutral, sourcedScrolls = opts.sourcedScrolls, noQuests = opts.noQuests }
  local ctx = NewContext(data, o)
  Annotate(data)
  local list = {}
  -- "rep": se lista para que veas qué te daría subir la reputación, pero la ruta no la usa
  local OBTAINABLE = { trainer = true, vendor = true, scroll = true, quest = true, ah = true, owned = true, known = true, rep = true }
  for id, r in pairs(data.recipes) do
    if (r.out or opts.all) and not r.conversion and not r.intermediate then
      local learnCost, learnSource = Planner.LearnCost(ctx, r)
      local basic = learnSource == nil and Planner.LearnSkill(r, o) ~= nil
      -- opts.anySource: también las de fuente desconocida (vista Recetas: que el buscador las encuentre)
      if OBTAINABLE[learnSource] or basic or opts.all or opts.anySource then
        local cost, reagents = RecipeCost(ctx, r, 1, {})
        local itemID, qty = r.out and r.out[1], r.out and r.out[2] or 1
        local ah = itemID and ctx.prices[itemID]
        local vendor = itemID and ES:VendorSellPrice(itemID)
        if itemID and not vendor then ctx.pendingInfo = true end
        local deposit, cut = Planner.AuctionCosts(vendor or 0, o)
        local e = {
          id = id, recipe = r, itemID = itemID, qty = qty, cost = cost, reagents = reagents,
          learn = basic and 1 or r.train or 1, learnCost = learnCost or 0, learnSource = learnSource or (basic and "basic" or "unknown"),
          vendor = vendor or 0, deposit = deposit, cut = cut,
          ahMin = ah and ah.minUnit, ahMedian = ah and (ah.median or ah.minUnit),
          listings = ah and ah.listings or 0, quantity = ah and ah.quantity or 0,
        }
        -- Lo que te queda por unidad en la AH al precio realista (el mínimo, o la
        -- referencia del histórico si el mínimo está inflado): - comisión - depósito
        e.fair = itemID and not r.bop and ES.Market:FairPrice(itemID, e.ahMin) or nil -- ligado: sin AH
        if e.fair then
          e.ahPrice = e.fair.price
          e.ahNet = e.ahPrice * (1 - cut) - deposit
        end
        if cost and itemID then
          local best = e.vendor
          e.sellWhere = "vendor"
          if e.ahNet and e.ahNet > best then best, e.sellWhere = e.ahNet, "ah" end
          e.profit = best * qty - cost
          e.margin = cost > 0 and e.profit / cost or nil
        end
        list[#list + 1] = e
      end
    end
  end
  return list, ctx
end

---------------------------------------------------------------------------
-- Nivel actual del jugador en una profesión
---------------------------------------------------------------------------
local LOCAL_NAMES = {
  [165] = { "Leatherworking", "Peletería", "Peleteria" },
  [333] = { "Enchanting", "Encantamiento" },
  [197] = { "Tailoring", "Sastrería", "Sastreria" },
  [164] = { "Blacksmithing", "Herrería", "Herreria" },
  [171] = { "Alchemy", "Alquimia" },
  [202] = { "Engineering", "Ingeniería", "Ingenieria" },
  [185] = { "Cooking", "Cocina" },
  [129] = { "First Aid", "Primeros auxilios" },
  [356] = { "Fishing", "Pesca" },
}

function ES:GetProfessionSkill(skillLine)
  if GetProfessions and GetProfessionInfo then
    -- GetProfessions devuelve huecos con nil (p. ej. sin segunda profesión):
    -- recorrer por posición, no con ipairs, que se pararía en el primer nil
    local slots = { GetProfessions() }
    for i = 1, select("#", GetProfessions()) do
      local index = slots[i]
      if index then
        local _, _, rank, maxRank, _, _, line = GetProfessionInfo(index)
        if line == skillLine then return rank, maxRank end
      end
    end
  end
  if GetNumSkillLines and GetSkillLineInfo then
    local names = LOCAL_NAMES[skillLine] or {}
    for i = 1, GetNumSkillLines() do
      local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
      if not isHeader then
        for _, n in ipairs(names) do
          if name == n then return rank, maxRank end
        end
      end
    end
  end
  return nil
end
