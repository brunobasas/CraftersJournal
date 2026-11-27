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
-- Lo que vende un vendedor solo se compra en la AH si sale al menos un 10% más barato
-- (si no, ir a la AH por 1 cobre de diferencia: Fine Thread, Crystal Vial)
Planner.VENDOR_EDGE = 0.9

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
local PROFIT_FULL_CRAFTS = 5  -- hasta estas fabricaciones por punto, el beneficio de vender cuenta entero
-- Lo que tiene que ahorrar cada fabricación de un material intermedio (Light Leather
-- de Ruined Leather Scraps, barras...) frente a comprarlo para fabricarlo (ver Acquire)
local INTERMEDIATE_CRAFT_COST = 5
local VIA_ROUNDS = 2          -- vueltas de cambiar fabricar ↔ comprar (ver Planner:Plan)
local MAX_EXTRA_PCT = 0.03    -- hasta un 3% de los materiales más
local MAX_EXTRA_MIN = 100     -- o 1 plata, lo que sea mayor
-- Recetas de pago usadas menos puntos de los supuestos al elegirlas (ver Planner:Plan)
local FEE_PASSES = 4          -- pasadas como mucho
local FEE_SLACK = 0.75        -- se repite si se usó menos del 75% de lo supuesto
-- Sin zigzag (ver Planner.Smooth)
local SMOOTH_MIN = 3          -- pasos de menos puntos que esto son "cortos"
local SMOOTH_TOLERANCE = 100  -- cobre que puede costar de más hacer el tramo con una sola receta
-- Aprender una receta nueva para un paso de pocas fabricaciones tiene que ahorrar al
-- menos esto frente a hacer esos puntos con la receta de al lado (ver PlanGPS)
local LEARN_FEW_CRAFTS = 5    -- fabricaciones: paso "de pocas"
local LEARN_WORTH = 500       -- cobre (5s)
Planner.LEARN_FEW_CRAFTS, Planner.LEARN_WORTH = LEARN_FEW_CRAFTS, LEARN_WORTH
function Planner.SetLearnWorth(v) LEARN_WORTH = v Planner.LEARN_WORTH = v end -- (pruebas: comparar con y sin)
local SMOOTH_PCT = 0.005      -- o el 0,5% de los materiales, lo que sea mayor
local SMOOTH_PASSES = 4       -- tramos que se arreglan como mucho
-- Recetas de pergamino que se prueba a quitar al acabar la ruta (ver Planner:Plan)
local MAX_SEARCH = 3
local SEARCH_MIN_SAVING = 10  -- cobre: por debajo no merece cambiar la ruta
local SEARCH_SOURCES = { vendor = true, ah = true, scroll = true, quest = true }
-- Con lo que llevas (ver Planner.BagsAlternative)
local BAGS_MIN_POINTS = 5   -- puntos que te tienen que dar tus materiales
local BAGS_MIN_SAVING = 50  -- cobre de oro ahorrado: por debajo no se considera
local BAGS_MIN_WORTH = 50   -- cobre que tiene que ganar a vender lo tuyo para meterla en la ruta
local BAGS_PASSES = 3       -- recetas con lo tuyo que se meten como mucho
-- Empate: si usar lo tuyo sale casi igual que venderlo (la diferencia es menos del
-- BAGS_TIE_PCT de lo que vale lo tuyo), se usa lo tuyo: no hay que vender 68 telas
-- en la AH (depósito, sin garantía de venderlas) ni comprar los materiales de la ruta
local BAGS_TIE_PCT = 0.15
Planner.BAGS_MIN_WORTH = BAGS_MIN_WORTH

-- ¿Usar lo tuyo (alt: ver BagsAlternative) compensa o empata con venderlo?
function Planner.BagsWorth(alt)
  return alt.saving - alt.value > -BAGS_TIE_PCT * (alt.value or 0)
end

-- Tramos de pasos cortos (menos de SMOOTH_MIN puntos cada uno, al menos dos
-- seguidos): se rehace la ruta con cada receta del tramo para todo él (ruta fijada,
-- una pasada) y se queda la más barata de las que no cuestan más de SMOOTH_TOLERANCE
-- (o SMOOTH_PCT de los materiales) que la original y llegan igual de lejos.
function Planner.Smooth(data, opts, plan)
  local skip = {} -- tramos (por su nivel de inicio) que no se pudieron arreglar
  for _ = 1, SMOOTH_PASSES do
    local steps, window = plan.steps, nil
    local i = 1
    while i <= #steps and not window do
      local j = i
      while j <= #steps and steps[j].to - steps[j].from < SMOOTH_MIN do j = j + 1 end
      if j - i >= 2 and not skip[steps[i].from] then window = { i, j - 1 } else i = math.max(i + 1, j) end
    end
    if not window then return plan end
    local from, to = steps[window[1]].from, steps[window[2]].to
    local allowed = plan.net + math.max(SMOOTH_TOLERANCE, SMOOTH_PCT * (plan.reagentCost or 0))
    local best, tried = nil, {}
    for k = window[1], window[2] do
      local id = steps[k].id
      if not tried[id] then
        tried[id] = true
        local o = {}
        for key, v in pairs(opts) do o[key] = v end
        o.forced = {}
        for s, c in pairs(plan.choice) do o.forced[s] = c end
        for s = from, to - 1 do o.forced[s] = id end
        local p = Planner:Plan(data, o)
        if p.reached >= plan.reached and p.net <= allowed and (not best or p.net < best.net) then best = p end
      end
    end
    if best then
      best.cheapest, best.craftCostUsed = plan.cheapest, plan.craftCostUsed
      plan = best
    else
      skip[from] = true -- ninguna sirve: se deja como estaba
    end
  end
  return plan
end

-- Unidades de cada material que pide la ruta desde el nivel `level` hasta el final
-- Lo que la ruta gasta de lo fabricado en sus propios pasos (Light Leather del paso de
-- Light Leather para las Embossed Leather Pants) no se compra, pero hay que llevarlo.
-- La lista de la compra lo cuenta frente a tus bolsas: si lo vendiste o lo gastaste, te
-- lo pide (antes daba por hecho que lo llevabas y faltaban 21 a mitad de paso).
-- Solo lo que ya hicieron los pasos que has pasado y aún no se ha gastado: lo de pasos
-- por venir lo fabricarás tú. { [itemID] = unidades } para los niveles de `level` a `to`
local function MadeNeed(plan, level, to)
  local recipes = plan.ctx and plan.ctx.data and plan.ctx.data.recipes
  if not (recipes and plan.choice and plan.pointUse) then return {} end
  local left = {} -- lo hecho antes de `level` menos lo gastado antes de `level`
  for s = plan.from or 1, level - 1 do
    local r = plan.choice[s] and recipes[plan.choice[s]]
    local p = plan.pointChance and plan.pointChance[s]
    if r and r.out and p and p > 0 then left[r.out[1]] = (left[r.out[1]] or 0) + r.out[2] / p end
    for itemID, u in pairs(plan.pointUse[s] or {}) do
      left[itemID] = (left[itemID] or 0) - (u.stock or 0) - (u.ahead or 0)
    end
  end
  for _, st in ipairs(plan.steps or {}) do -- (lo fabricado de más en pasos ya pasados)
    if st.to <= level and st.ahead and st.recipe.out then
      local o = st.recipe.out
      for _, a in ipairs(st.ahead) do left[o[1]] = (left[o[1]] or 0) + a.quantity end
    end
  end
  local use = {}
  for s = level, to - 1 do
    for itemID, u in pairs(plan.pointUse[s] or {}) do
      local q = (u.stock or 0) + (u.ahead or 0)
      if q > 0 then use[itemID] = (use[itemID] or 0) + q end
    end
  end
  local need = {}
  for itemID, q in pairs(use) do
    local n = math.min(q, left[itemID] or 0)
    if n > 0 then need[itemID] = n end
  end
  return need
end

-- Colchón en los niveles verdes (desviaciones): menor que en amarillo, porque cerca del
-- gris la incertidumbre es muy grande y se compraría mucho de más; pero no cero. Sin
-- colchón, con mala suerte (la mitad de las veces) no llegabas y cada reposición
-- compraba otra vez lo justo: 4 o 5 viajes seguidos a por Linen Cloth para Red Linen
-- Bag (Discord). 0,75: te llega ~3 de cada 4 veces
Planner.GREEN_Z = 0.75

-- Lo que piden los niveles de `from` a `to`: { [itemID] = { expected, target } }.
-- target lleva el colchón (z desviaciones; en los niveles green(s), GREEN_Z) y va
-- en fabricaciones enteras: no se hace media receta (15 Light Leather no dan para 2
-- Light Leather Pants, que piden 10 cada una: 20). Cada material se reparte entre las
-- recetas que lo gastan y la parte de cada una se redondea a lo que pide por
-- fabricación (si lo gastan dos recetas con cantidades distintas, cada una la suya).
-- Lo que no es material directo de la receta (lo de un intermedio), a la unidad
local function DirectQty(r, itemID)
  for _, rq in ipairs(r and r.r or {}) do
    if rq[1] == itemID then return rq[2] end
  end
end

-- El colchón de un material: z desviaciones de lo que varía en los niveles amarillos
-- (var) y, en los verdes (varGreen), como mucho GREEN_Z. Lo comparten Need y
-- CraftedNeedIn: así un intermedio y su material llevan el mismo colchón (los Bolt que
-- pide la fila son los que da el paño que pide la compra)
local function Margin(var, varGreen, z)
  return z * math.sqrt(var) + math.min(z, Planner.GREEN_Z) * math.sqrt(varGreen)
end

local function Need(plan, from, to, z, green)
  local recipes = plan.ctx and plan.ctx.data and plan.ctx.data.recipes or {}
  local acc = {} -- [itemID] = { expected, var, shares = { [receta] = { q, per } }, other, first }
  local function Item(itemID)
    local a = acc[itemID]
    if not a then a = { expected = 0, var = 0, varGreen = 0, shares = {}, other = 0 } acc[itemID] = a end
    return a
  end
  local function Share(a, id, per, q)
    local sh = a.shares[id]
    if not sh then sh = { q = 0, per = per } a.shares[id] = sh end
    sh.q = sh.q + q
    a.first = a.first or id
  end
  for s = from, to - 1 do
    local id = plan.choice and plan.choice[s]
    local r = id and recipes[id]
    local p = plan.pointChance and plan.pointChance[s] or 1
    local g = green and green(s)
    for itemID, q in pairs(plan.pointNeed and plan.pointNeed[s] or {}) do
      local a = Item(itemID)
      a.expected = a.expected + q
      if g then a.varGreen = a.varGreen + q * q * (1 - p) else a.var = a.var + q * q * (1 - p) end
      local per = DirectQty(r, itemID)
      if per then Share(a, id, per, q) else a.other = a.other + q end
    end
  end
  -- (y lo que hicieron pasos ya pasados: tienes que llevarlo; ver MadeNeed), con la
  -- primera receta del tramo que lo gasta
  local made = MadeNeed(plan, from, to)
  for itemID, q in pairs(made) do
    local a = Item(itemID)
    a.expected = a.expected + q
    a.made = q
    for s = from, to - 1 do
      local id = plan.choice and plan.choice[s]
      local per = id and DirectQty(recipes[id], itemID)
      if per then Share(a, id, per, q) q = 0 break end
    end
    a.other = a.other + q
  end
  local out = {}
  for itemID, a in pairs(acc) do
    -- El colchón, con la primera receta que lo gasta (es la que fabricas antes)
    local margin = Margin(a.var, a.varGreen, z)
    if a.first then a.shares[a.first].q = a.shares[a.first].q + margin else a.other = a.other + margin end
    local target = math.ceil(a.other - 0.001)
    for _, sh in pairs(a.shares) do
      target = target + math.ceil(sh.q / sh.per - 0.001) * sh.per
    end
    -- made: la parte que es lo hecho en pasos ya pasados (ver ShortMade)
    if target > 0 then out[itemID] = { expected = a.expected, target = target, made = a.made } end
  end
  return out
end

-- Lo que la ruta da por hecho en pasos ya pasados y debes llevar: { [itemID] = unidades }
-- para los niveles de `level` a `to` (ver MadeNeed)
function Planner.MadeNeed(plan, level, to)
  return MadeNeed(plan, level, to or plan.reached or plan.to or level)
end

-- El paso de la ruta que fabrica `itemID` (el primero), o nil
local function MadeStep(plan, itemID)
  for _, st in ipairs(plan.steps or {}) do
    local r = st.recipe
    if r and r.out and r.out[1] == itemID and r.r then return st end
  end
end
Planner.MadeStep = MadeStep

-- Lo hecho en pasos ya pasados que no llevas (Cured Medium Hide del paso de curarlas,
-- para las Hillman's Shoulders): se fabrica otra vez, no se compra hecho. Con suerte
-- en ese paso subes con menos fabricaciones de las previstas y te quedan menos; la
-- compra pedía las 5 que faltaban hechas en la AH, sin la Medium Hide ni la Salt para
-- curarlas (CurseForge). `need`: { [itemID] = { target, expected, made } } (ver Need),
-- se cambia aquí. raw(itemID): lo que llevas
local function ShortMade(plan, need, raw)
  local add = {}
  for itemID, n in pairs(need) do
    local st = n.made and n.made > 0 and MadeStep(plan, itemID)
    -- (en unidades enteras: lo hecho es una media, 12,6; si no quedaba "×0" en la lista)
    local short = st and math.min(math.ceil(n.made - 0.001), n.target - raw(itemID)) or 0
    if short > 0 then
      local r = st.recipe
      local crafts = math.ceil(short / math.max(1, r.out[2] or 1) - 0.001)
      n.target, n.expected = n.target - short, math.max(0, n.expected - short)
      n.made = math.max(0, n.made - short)
      for _, rq in ipairs(r.r) do add[rq[1]] = (add[rq[1]] or 0) + crafts * rq[2] end
    end
  end
  for itemID, q in pairs(add) do
    local n = need[itemID]
    if n then
      n.target, n.expected = n.target + q, n.expected + q
    else
      need[itemID] = { target = q, expected = q }
    end
  end
  for itemID, n in pairs(need) do if n.target <= 0 then need[itemID] = nil end end
end

-- Dónde comprar un material de la ruta: la entrada de plan.shopping (o nil). Si la ruta
-- lo compra en los dos sitios (las pocas subastas más baratas que el vendedor y el resto
-- al vendedor), donde va la mayor parte. Antes ganaba la AH y las filas de compra
-- mandaban a comprar allí los 44 Crystal Vial cuando solo 4 estaban más baratos (Discord)
function Planner.ShoppingSource(plan, itemID)
  local found
  for _, e in ipairs(plan and plan.shopping or {}) do
    if e.itemID == itemID and (not found or e.quantity > found.quantity) then found = e end
  end
  return found
end

-- Lo que pide la ruta desde tu nivel hasta el final: { [itemID] = unidades }, en
-- fabricaciones enteras (ver Need)
function Planner.NeedFrom(plan, level)
  local need = {}
  for itemID, n in pairs(Need(plan, level, plan.reached or plan.to or level, 0)) do need[itemID] = n.target end
  return need
end

---------------------------------------------------------------------------
-- Lo que sobra de un paso acabado (el colchón de la compra por tramos, o la suerte):
-- ¿fabricarlo o venderlo? Solo se propone fabricarlo si deja más que venderlo, con la
-- misma cuenta que la ruta: cada punto que te da es un punto que ya no subes con la
-- receta prevista (plan.pointNet: lo que cuesta de media), y lo fabricado se vende.
-- Si la receta prevista deja más (o cuesta menos) que gastar lo que sobra, no sale:
-- la ruta saldría más cara (Discord: sobraban materiales de pasos cortos en amarillo).
-- Sobra lo que no pide el resto de la ruta. Si una fabricación gasta además algo que sí
-- pide (el Leaded Vial de Nature Protection Potion, que también gasta Greater Mana
-- Potion), eso cuenta a lo que costaría volver a comprarlo: hay que reponerlo
---------------------------------------------------------------------------
Planner.LEFTOVER_MIN_GAIN = 100 -- cobre: por debajo, no compensa ni decirlo

-- Lo que te dan por una unidad: lo mejor de vendedor y AH (precio realista, menos
-- comisión y depósito), con los precios de la ruta
local function UnitSellValue(plan, itemID)
  local ctx = plan.ctx
  local vendor = ES:VendorSellPrice(itemID) or 0
  local best = vendor
  local ah = ctx and ctx.prices and ctx.prices[itemID]
  local fair = ah and ES.Market:FairPrice(itemID, ah.minUnit)
  if fair and fair.price then
    local deposit, cut = Planner.AuctionCosts(vendor, ctx.opts or {})
    best = math.max(best, fair.price * (1 - cut) - deposit)
  end
  return best
end
Planner.UnitSellValue = UnitSellValue

-- Lo que cuesta volver a comprar una unidad (lo más barato de la AH y el vendedor, con
-- los precios de la ruta), o nil si no se puede comprar
local function UnitBuyCost(plan, itemID)
  local ah = plan.ctx and plan.ctx.prices and plan.ctx.prices[itemID]
  local cost = ah and ah.minUnit
  local vendor = ES.Data.VendorPrices and ES.Data.VendorPrices[itemID]
  if vendor and (not cost or vendor < cost) then cost = vendor end
  return cost
end

-- Lo mejor que hacer con lo que sobra a tu nivel `level` (`cap`: el tope de tu rango):
-- { recipe, id, crafts, points, gain, saving, sale, matValue } o nil. Una receta de un
-- paso ya acabado que aún da puntos, tantas fabricaciones como dejen más que venderlo
function Planner.Leftover(plan, level, cap)
  if not (plan and plan.steps and plan.pointNet and level) then return nil end
  local recipes = plan.ctx and plan.ctx.data and plan.ctx.data.recipes or {}
  local stop = math.min(plan.reached or plan.to or level, cap or math.huge)
  if level >= stop then return nil end
  local current
  for _, st in ipairs(plan.steps) do
    if level >= st.from and level < st.to then current = st.id end
  end
  local need = Planner.NeedFrom(plan, level)
  local best, seen = nil, {}
  for _, st in ipairs(plan.steps) do
    local r = recipes[st.id] or st.recipe
    if st.to <= level and st.id ~= current and not seen[st.id] and r and r.r and r.t
      and not Planner.Cooldown(r, st.id) and ES:IsRecipeKnown(st.id) then
      seen[st.id] = true
      -- De cada material: lo que llevas, lo que sobra (lo que no pide el resto de la
      -- ruta), lo que te darían por él y lo que costaría reponerlo
      local mats, crafts = {}, math.huge
      for _, rq in ipairs(r.r) do
        local bags = ES:ItemCount(rq[1]) or 0
        local have = ES.HaveForShopping and ES:HaveForShopping(rq[1]) or bags
        local m = { per = rq[2], bags = bags, sell = UnitSellValue(plan, rq[1]), buy = UnitBuyCost(plan, rq[1]),
          surplus = math.max(0, math.min(bags, have - (need[rq[1]] or 0))) }
        mats[#mats + 1] = m
        crafts = math.min(crafts, math.floor(bags / rq[2]))
        -- (algo tiene que sobrar de verdad: lo que no sobra de ninguno no es lo que sobra)
        if m.surplus >= rq[2] then m.leftover = true end
      end
      -- Las que da lo que sobra: el material que sobra que antes se acaba
      local cap = math.huge
      for _, m in ipairs(mats) do
        if m.leftover then cap = math.min(cap, math.floor(m.surplus / m.per)) end
      end
      crafts = cap < math.huge and math.min(crafts, cap) or 0
      local outValue = r.out and r.out[2] * UnitSellValue(plan, r.out[1]) or 0
      -- Una a una, mientras sume: cada fabricación da su probabilidad de punto (más baja
      -- según subes) y ese punto se ahorra al precio que lo pagaba la ruta
      local lvl, sum, saving, matValue = level, 0, 0, 0
      local top = { gain = 0 }
      for k = 1, crafts do
        local s = math.floor(lvl + 1e-6) -- (EPS se declara más abajo)
        if s >= stop then break end
        local c = Planner.Chance(r.t, s)
        if c <= 0 then break end
        -- Lo que gasta esta: lo que sobra, a lo que te darían por ello; lo demás, a
        -- lo que cuesta reponerlo (sin precio para reponerlo, no se gasta)
        local cost, ok = 0, true
        for _, m in ipairs(mats) do
          local fromSurplus = math.max(0, math.min(m.per, m.surplus - (k - 1) * m.per))
          local rest = m.per - fromSurplus
          if rest > 0 and not m.buy then ok = false break end
          cost = cost + fromSurplus * m.sell + rest * (m.buy or 0)
        end
        if not ok then break end
        local save = c * (plan.pointNet[s] or 0)
        saving = saving + save
        matValue = matValue + cost
        sum = sum + save + outValue - cost
        lvl = lvl + c
        if sum > top.gain then
          top = { gain = sum, crafts = k, points = lvl - level, saving = saving,
            sale = outValue * k, matValue = matValue }
        end
      end
      if top.crafts and top.gain >= Planner.LEFTOVER_MIN_GAIN and (not best or top.gain > best.gain) then
        top.recipe, top.id = r, st.id
        best = top
      end
    end
  end
  return best
end

---------------------------------------------------------------------------
-- Comprar por tramos: en vez de toda la ruta de golpe, lo del tramo en el que
-- estás, con un colchón donde la suerte cuenta (amarillo y verde). Al acabar el
-- tramo, el siguiente. La lista es viva: lo que falta = lo del tramo - lo que llevas
---------------------------------------------------------------------------
Planner.PHASE_Z = 1 -- colchón: 1 desviación (te llega ~8 de cada 10 veces); 0 = lo esperado

-- Materiales que pide un nivel (las claves de pointNeed)
local function PointItems(plan, s)
  local set = {}
  for itemID in pairs(plan.pointNeed and plan.pointNeed[s] or {}) do set[itemID] = true end
  return set
end

-- Rangos que no se suben solo con pasar por el instructor: los de Cooking y First Aid
-- por encima de 150 (Experto es un libro de un vendedor lejano; Artesano, una misión) y
-- los que piden más nivel de personaje del que tienes. Puede que no llegues a subirlo
-- (o que no quieras): no se compra para los puntos de después.
-- CurseForge: subiendo First Aid hasta 225 la lista le hizo comprar 107 Mageweave Cloth
-- (la tanda de Mageweave Bandage de 210 llegaba a 258) y vendió 88
local QUEST_RANKS = { [129] = 150, [185] = 150 } -- [skillLine] = por encima de este tope
local function HardRank(data, rank)
  local over = QUEST_RANKS[data.skillLine]
  if over and rank[1] > over then return true end
  local need, have = rank[4] or 0, UnitLevel and UnitLevel("player")
  return need > 0 and have ~= nil and have < need
end

-- El nivel entre `from` y `to` (los dos fuera) en el que la ruta se topa con un rango
-- así que aún no tienes, o nil
function Planner.RankStop(plan, from, to)
  local data = plan and plan.ctx and plan.ctx.data
  if not (data and data.ranks) then return nil end
  local max = data.skillLine and ES.GetProfessionSkill and select(2, ES:GetProfessionSkill(data.skillLine))
  local cap = APPRENTICE_CAP -- (el tope que sube cada rango)
  for _, rank in ipairs(data.ranks) do
    if cap > from and cap < to and not (max and max > cap) and HardRank(data, rank) then return cap end
    cap = rank[1]
  end
end

-- Tramo en el que estás: { from, to, steps = { pasos } } o nil (ruta acabada). Es el
-- paso de tu nivel; los siguientes se juntan si no piden ningún material nuevo
-- (Copper Bracers y luego Copper Chain Pants: una sola visita a la AH). Se acaba en un
-- rango que no es ir al instructor (Planner.RankStop)
function Planner.Phase(plan, level)
  local steps = plan and plan.steps or {}
  local first
  for i, st in ipairs(steps) do
    if level < st.to then first = i break end
  end
  if not first then return nil end
  local phase = { from = math.max(level, steps[first].from), to = steps[first].to, steps = { steps[first] } }
  local items = {}
  for s = steps[first].from, steps[first].to - 1 do
    for itemID in pairs(PointItems(plan, s)) do items[itemID] = true end
  end
  for i = first + 1, #steps do
    local st, new = steps[i], false
    for s = st.from, st.to - 1 do
      for itemID in pairs(PointItems(plan, s)) do if not items[itemID] then new = true end end
    end
    if new or st.from ~= phase.to then break end
    phase.to = st.to
    phase.steps[#phase.steps + 1] = st
  end
  local stop = Planner.RankStop(plan, phase.from, phase.to)
  if stop then
    phase.to, phase.rankStop = stop, true
    for i = #phase.steps, 2, -1 do
      if phase.steps[i].from >= stop then table.remove(phase.steps, i) end
    end
  end
  return phase
end

-- Lo que pide el tramo desde tu nivel: { [itemID] = { expected, target } }. target
-- lleva el colchón: en un punto con probabilidad p, las fabricaciones son aleatorias
-- (media 1/p, varianza (1-p)/p²); un material que pide q de media en ese punto
-- varía q²(1-p). Naranja (p = 1): lo justo
-- En verde (la receta sube poco: muchas fabricaciones por punto, y con mucha suerte
-- o mala suerte) no se compra el tramo entero con colchón: una tanda de unas
-- BATCH_CRAFTS fabricaciones, lo esperado sin colchón. Como la lista es viva, al
-- gastarla pide la siguiente: si tienes suerte no compras de más (Discord: subió
-- Heavy Blasting Powder hasta 145 con mucho menos de lo que pedía la lista).
-- phase.batchTo: hasta qué nivel llega la tanda
-- (50: con 20, Linen Bag de 26 a 65 eran 8-9 viajes a la AH. Lo que sobra de una tanda
-- se gasta en la siguiente del mismo paso: más grande solo arriesga sobrante al final)
Planner.BATCH_CRAFTS = 50
-- El tamaño de la tanda: el de las opciones (/cj opciones, Lista de compra: ES.db.batchCrafts)
-- o el de por defecto. Más grande, menos viajes a comprar; más pequeña, menos sobrante
Planner.BATCH_STEPS = { 20, 30, 50, 75, 100, 150 }
function Planner.BatchCrafts()
  local v = ES.db and ES.db.batchCrafts
  return type(v) == "number" and v > 0 and v or Planner.BATCH_CRAFTS
end

local function GreenPoint(plan, s)
  local id = plan.choice and plan.choice[s]
  local r = id and plan.ctx and plan.ctx.data and plan.ctx.data.recipes[id]
  if r and r.t then return s >= r.t[3] end
  local p = plan.pointChance and plan.pointChance[s] or 1
  return p < 0.5
end

-- `upTo`: hasta ese nivel y no la tanda (lo que falta para llegar a lo que compraste:
-- ver Planner.Stocked)
function Planner.PhaseNeed(plan, level, z, upTo)
  local phase = Planner.Phase(plan, level)
  if not phase then return {}, nil end
  z = z or Planner.PHASE_Z
  -- Hasta dónde: el tramo, o en verde la tanda (unas BATCH_CRAFTS fabricaciones)
  local batch -- fabricaciones de la tanda en verde
  phase.batchTo = upTo and upTo < phase.to and upTo or nil
  local batchSize = Planner.BatchCrafts()
  for s = phase.from, upTo and -1 or (phase.to - 1) do
    if GreenPoint(plan, s) then
      if batch and batch >= batchSize then
        phase.batchTo = s
        break
      end
      local p = plan.pointChance and plan.pointChance[s] or 1
      batch = (batch or 0) + (p > 0 and 1 / p or 0)
    end
  end
  local out = Need(plan, phase.from, phase.batchTo or phase.to, z, function(s) return GreenPoint(plan, s) end)
  return out, phase
end

-- Cuántos de un intermedio de plan.crafted (Bolt of Silk Cloth) gastan los niveles de
-- `from` a `to`, los fabricados y los que salen de tus bolsas, con el colchón de Need
-- (z desviaciones; en los niveles green(s), como mucho GREEN_Z). nil si el plan no lo
-- sabe (sin pointUse)
function Planner.CraftedNeedIn(plan, itemID, from, to, z, green)
  if not plan.pointUse then return nil end
  local expected, var, varGreen = 0, 0, 0
  for s = from, to - 1 do
    local u = plan.pointUse[s] and plan.pointUse[s][itemID]
    if u then
      local q = (u.craft or 0) + (u.owned or 0)
      local p = plan.pointChance and plan.pointChance[s] or 1
      expected = expected + q
      if green and green(s) then varGreen = varGreen + q * q * (1 - p) else var = var + q * q * (1 - p) end
    end
  end
  if expected <= 0 then return 0 end
  return math.ceil(expected + Margin(var, varGreen, z or 0) - 0.001)
end

-- Lo mismo para el tramo (o la tanda en verde) de `level`, el que compra la Lista de
-- compra por tramos (PhaseNeed): la fila "Fabrica N× Bolt of Silk Cloth" pide los
-- Bolt que da el Silk Cloth comprado. CurseForge: la compra del tramo pedía 32 Silk y
-- la fila, 82 Bolt (los de toda la ruta). Devuelve la cantidad y el tramo (o nil)
function Planner.PhaseCraftedNeed(plan, itemID, level)
  local _, phase = Planner.PhaseNeed(plan, level)
  if not phase then return nil end
  return Planner.CraftedNeedIn(plan, itemID, phase.from, phase.batchTo or phase.to, Planner.PHASE_Z,
    function(s) return GreenPoint(plan, s) end), phase
end

---------------------------------------------------------------------------
-- Comprado, a fabricar. Al tener todo lo de la tanda (o del tramo) en el que estás,
-- se apunta (con la ruta, en la partida: sobrevive a /reload) hasta qué nivel
-- llega lo comprado. Desde ahí:
--   · mientras puedas fabricar el paso, no se pide nada: lo que vas gastando es lo que
--     compraste (antes la tanda iba con tu nivel y en verde pedía más con cada punto:
--     "57× Bolt of Linen Cloth" con 24 en las bolsas y "Fabrica 35× Linen Bag");
--   · si lo gastas todo sin poder seguir, se pide la tanda siguiente desde tu nivel
--     (phase.refill = true): una compra para seguir, no lo justo para un punto;
--   · al llegar al nivel apuntado se olvida
-- Sin apunte (rutas empezadas antes, o comprado por otro lado) vale lo mismo una vez
-- subido un punto en el paso
---------------------------------------------------------------------------
local function CurrentStep(plan, level)
  for _, st in ipairs(plan and plan.steps or {}) do
    if level >= st.from and level < st.to then return st end
  end
end

local function MarkStore(profKey)
  local s = ES.db and ES.db.prof and ES.db.prof[profKey]
  local lock = ES.RouteLock and ES:RouteLock(profKey)
  return s, lock
end

-- El apunte que cubre tu nivel: { from, to } o nil (de otra ruta, o ya llegaste)
function Planner.Stocked(profKey, plan, level)
  local s, lock = MarkStore(profKey)
  local m = s and s.stocked
  if not (m and lock and m.started == lock.started and level >= m.from and level < m.to) then return nil end
  return m
end

function Planner.SetStocked(profKey, plan, level, to)
  local s, lock = MarkStore(profKey)
  if not (s and lock) then return end
  local m = s.stocked
  if m and m.started == lock.started and m.to == to and level >= m.from then return end
  s.stocked = { started = lock.started, from = level, to = to }
end

---------------------------------------------------------------------------
-- Herramientas (Arclight Spanner, Blacksmith Hammer, bastones rúnicos...). La ruta
-- apunta la herramienta solo en el nivel donde la consigue (pointNeed), y desde ahí
-- da por hecho que la llevas. Si no está en las bolsas (no la compraste, la dejaste
-- en el banco, la vendiste), los pasos siguientes no se pueden fabricar y la lista de
-- la compra no la pedía (CurseForge: "me mandó fabricar unas gafas que piden Arclight
-- Spanner y no estaba en la lista")
---------------------------------------------------------------------------
-- Las herramientas que pide una receta: { ES.Data.Tools[...] }. Puede pedir dos (los
-- cascos de ingeniería: Blacksmith Hammer y Arclight Spanner, recipe.tool y tool2);
-- antes solo se miraba la primera y la ruta nunca pedía la llave (CurseForge, 0.62.0)
-- (sin herramienta: siempre la misma lista vacía, sin crear tablas; quien la pide solo la recorre)
local NO_TOOLS = {}
function Planner.RecipeTools(recipe)
  local tools = ES.Data and ES.Data.Tools
  if not (recipe and tools) or not (recipe.tool or recipe.tool2) then return NO_TOOLS end
  local list = {}
  if recipe.tool and tools[recipe.tool] then list[#list + 1] = tools[recipe.tool] end
  if recipe.tool2 and tools[recipe.tool2] then list[#list + 1] = tools[recipe.tool2] end
  return list
end

-- ¿Llevas `tool` o una mejor de su familia?
local function CarriesTool(tool)
  local fam = tool.family or "rod"
  for _, t in pairs(ES.Data.Tools) do
    if (t.family or "rod") == fam and t.mask >= tool.mask and (ES:ItemCount(t.item) or 0) > 0 then return true end
  end
  return false
end

-- Las herramientas que pide `recipe` y no llevas en las bolsas: { tool } (vacía si no
-- pide ninguna o las llevas: vale cualquiera de su familia igual o mejor)
function Planner.MissingTools(recipe)
  local list = {}
  for _, tool in ipairs(Planner.RecipeTools(recipe)) do
    if not CarriesTool(tool) then list[#list + 1] = tool end
  end
  return list
end

-- La primera que falta, o nil
function Planner.MissingTool(recipe)
  return Planner.MissingTools(recipe)[1]
end

-- La receta de `profKey` que fabrica `itemID` (para una herramienta sin vendedor)
local function ToolRecipe(profKey, itemID)
  local data = ES.Data[profKey]
  for _, r in pairs(data and data.recipes or {}) do
    if r.out and r.out[1] == itemID and r.r then return r end
  end
end

-- Añade a `out` (el de RouteNeed) las herramientas que piden los pasos entre `from`
-- y `to` y no llevas: la herramienta si se vende en un vendedor; si no, los
-- materiales para fabricarla una vez. Devuelve true si añadió algo
function Planner.AddMissingTools(profKey, plan, from, to, out)
  -- (la que la ruta consigue dentro del tramo ya va en pointNeed: ella o sus materiales)
  local inRange = {}
  for _, tl in ipairs(plan and plan.tools or {}) do
    if tl.skill >= from and tl.skill < to then inRange[tl.item] = true end
  end
  local want = {} -- [familia] = herramienta (la mejor que piden)
  for _, st in ipairs(plan and plan.steps or {}) do
    if st.to > from and st.from < to then
      for _, tool in ipairs(Planner.MissingTools(st.recipe)) do
        if not inRange[tool.item] then
          local fam = tool.family or "rod"
          if not want[fam] or tool.mask > want[fam].mask then want[fam] = tool end
        end
      end
    end
  end
  local added = false
  for _, tool in pairs(want) do
    local vendor = ES.Data.VendorPrices and ES.Data.VendorPrices[tool.item]
    local r = not vendor and ToolRecipe(profKey, tool.item)
    if r then
      for _, rq in ipairs(r.r) do
        local e = out[rq[1]]
        local n = rq[2] + (e and e.need or 0)
        out[rq[1]] = { need = n, expected = (e and e.expected or 0) + rq[2] }
      end
    else
      out[tool.item] = { need = 1, expected = 1 }
    end
    added = true
  end
  return added
end

-- ¿Puedes fabricar el paso en el que estás al menos una vez? (nil: no se sabe)
local function CanCraftStep(plan, level)
  local st = CurrentStep(plan, level)
  if not (st and st.id and ES.CraftableFromBags) then return nil end
  local n = ES.CraftableFromBags(st.id)
  if n == nil then return nil end
  return n >= 1
end

-- ¿Sigues con lo que llevas? (comprado y aún puedes fabricar)
function Planner.PhaseHold(profKey, plan, level)
  local st = CurrentStep(plan, level)
  if not st or CanCraftStep(plan, level) ~= true then return false end
  return Planner.Stocked(profKey, plan, level) ~= nil or level > st.from
end

-- Cuánto hace falta de cada material de la ruta de `profKey` desde `level`. ÚNICA
-- regla para todas las vistas (Materiales, Lista de compra, ventana del vendedor,
-- Inventario), para que no vuelvan a separarse (Discord: la ruta pedía 12 Fine Thread
-- y la ventana del vendedor 14):
--   comprar (por defecto): con la ruta empezada y "por tramos" activado, el tramo en
--     el que estás con su colchón (PhaseNeed); si no, lo que queda de ruta, sin colchón
--   opts.keep: lo que queda de ruta entera, siempre (Inventario: lo que guardas no
--     es solo el tramo; si no, te diría que vendas lo del tramo siguiente)
--   opts.phase: por tramos aunque la Lista de compra sea de la ruta entera (las filas de
--     compra de la vista Ruta y el asistente: te guían tanda a tanda)
--   opts.preview: sin empezar la ruta, lo que pedirá al empezarla con el modo elegido
--     (la vista Materiales: por tramos, el primer tramo). No apunta nada (Stocked)
-- Devuelve { [itemID] = { need (unidades enteras), expected } } y el tramo (o nil)
function Planner.RouteNeed(profKey, plan, level, opts)
  local out = {}
  if not plan then return out, nil end
  level = math.max(plan.from or level or 1, level or plan.from or 1)
  local locked = ES:RouteLock(profKey)
  local preview = opts and opts.preview and not locked
  local byPhase = not (opts and opts.keep) and (locked or preview)
    and ((opts and opts.phase) or (ES.Shopping and ES.Shopping.ByPhase(profKey)))
  if byPhase then
    -- Comprado, a fabricar (Planner.Stocked): mientras puedas fabricar, nada más; sin
    -- poder, la tanda siguiente desde tu nivel (una sola compra). Antes pedía solo lo
    -- que faltaba para llegar al nivel apuntado: 12 Bolt para un punto y, al llegar,
    -- otra tanda: dos viajes seguidos (Discord, Linen Bag a 55)
    local mark = not preview and Planner.Stocked(profKey, plan, level)
    local hold = not preview and Planner.PhaseHold(profKey, plan, level)
    local need, phase = Planner.PhaseNeed(plan, level)
    if not phase then return out, nil end
    phase.hold = hold or nil
    phase.refill = mark and not hold or nil
    local function Raw(itemID) return ES.HaveForShopping and ES:HaveForShopping(itemID) or ES:ItemCount(itemID) or 0 end
    -- (¿lo tienes todo?: con lo ya convertido, Bolt of Linen Cloth cuenta como su Linen Cloth)
    local Have = ES.RouteHave and ES.RouteHave(plan, level) or Raw
    if not hold and not preview then ShortMade(plan, need, Raw) end
    local all = true
    for itemID, n in pairs(need) do
      local target = n.target
      -- (sin pedir: lo que llevas tal cual, que es lo que cuenta la Lista de compra)
      if hold then target = math.min(target, Raw(itemID)) end
      if Have(itemID) < target then all = false end
      if target > 0 then out[itemID] = { need = target, expected = n.expected } end
    end
    -- La herramienta que piden los pasos del tramo y no llevas (ver AddMissingTools)
    if Planner.AddMissingTools(profKey, plan, level, phase.batchTo or phase.to, out) then all = false end
    -- Y los pergaminos del tramo que se compran en la AH (fuera de `all` y de `hold`)
    Planner.AddRouteScrolls(plan, level, phase.batchTo or phase.to, out)
    -- Lo tienes todo: se apunta hasta dónde llega (y desde ahí, a fabricar)
    if all and not hold and not preview and next(need) then
      Planner.SetStocked(profKey, plan, level, phase.batchTo or phase.to)
    end
    return out, phase
  end
  -- La ruta entera, como una tanda grande (Discord: con "ruta entera", al fabricar una
  -- te mandaba a comprar 1 Bolt of Linen Cloth): con la ruta empezada, tenerlo todo se
  -- apunta (Planner.Stocked, hasta el final) y, mientras puedas fabricar el paso, no se
  -- pide nada más; sin poder, lo que falta de la ruta desde tu nivel
  local route = not (opts and opts.keep) and ES:RouteLock(profKey)
  local hold = route and Planner.PhaseHold(profKey, plan, level)
  local function Raw(itemID) return ES.HaveForShopping and ES:HaveForShopping(itemID) or ES:ItemCount(itemID) or 0 end
  local Have = route and ES.RouteHave and ES.RouteHave(plan, level) or Raw
  local all, any = true, false
  -- (con lo hecho en pasos pasados que no llevas, a fabricar otra vez: ShortMade)
  local whole = {}
  local made = route and not hold and MadeNeed(plan, level, plan.reached or plan.to or level) or {}
  for itemID, q in pairs(Planner.NeedFrom(plan, level)) do
    whole[itemID] = { target = q, expected = q, made = made[itemID] }
  end
  if route and not hold then ShortMade(plan, whole, Raw) end
  for itemID, w in pairs(whole) do
    local q = w.target
    local n = math.ceil(q - 0.001)
    if hold then n = math.min(n, Raw(itemID)) end
    if n > 0 then
      any = true
      if route and Have(itemID) < n then all = false end
      out[itemID] = { need = n, expected = q }
    end
  end
  if Planner.AddMissingTools(profKey, plan, level, plan.reached or plan.to or level + 1, out) then any, all = true, false end
  -- Y los pergaminos de lo que queda de ruta que se compran en la AH (fuera de `all` y de `hold`)
  Planner.AddRouteScrolls(plan, level, plan.reached or plan.to or level + 1, out)
  if route and any and all and not hold then
    Planner.SetStocked(profKey, plan, level, plan.reached or plan.to or level + 1)
  end
  return out, nil
end

-- Cuántos de un intermedio (Bolt of Runecloth) gasta la ruta desde `level` hasta el
-- final: lo que piden los niveles que te quedan, no los de toda la ruta. Con la ruta
-- empezada y medio paso hecho (3 de 4 Brightcloth Robe) la fila seguía pidiendo los 20
-- del principio (Discord). nil si el plan no lo sabe (sin pointUse)
-- `withOwned`: cuenta también lo que sale de tus bolsas: es lo que tienes que llevar
-- (la fila "Fabrica N×" le resta lo que hay en las bolsas; si no, se restaban dos
-- veces). Sin él, solo lo fabricado: lo que vale como su material ya convertido
-- (ConvertedHave; lo que ya tenías al calcular la ruta no pidió material)
function Planner.CraftedNeedFrom(plan, itemID, level, withOwned)
  if not plan.pointUse then return nil end
  local q = 0
  for s = level, (plan.reached or plan.to or level) - 1 do
    local u = plan.pointUse[s] and plan.pointUse[s][itemID]
    if u then q = q + (u.craft or 0) + (withOwned and u.owned or 0) end
  end
  return q
end

-- Lo ya convertido de una ruta: la ruta pide Runecloth para hacer Bolt of Runecloth, y
-- al convertirlo el Runecloth bajaba y la ruta volvía a pedir comprarlo (Discord). Por
-- cada intermedio que fabrica la ruta (plan.crafted), lo que llevas de él vale lo que
-- lleva de cada material (y así hacia abajo, hasta 3 niveles).
-- `level`: de cada intermedio cuenta como mucho lo que la ruta aún gasta desde ahí (los
-- de más no son material de la ruta: si no, sobrarían Bolts y faltaría el Runecloth
-- suelto que pide otra receta).
-- Devuelve { inside = { [material] = { { intermedio, unidades por intermedio } } },
--   cap = { [intermedio] = cuántos cuentan como mucho }, reserved = { [intermedio] = cuántos
--   son de pasos pasados } }
function Planner.Conversions(plan, level)
  local made, cap = {}, {}
  for _, c in ipairs(plan.crafted or {}) do
    if c.recipe and c.recipe.r and c.recipe.out then
      made[c.itemID] = c.recipe
      local rem = level and Planner.CraftedNeedFrom(plan, c.itemID, level)
      -- (solo lo fabricado: lo de tus bolsas al calcular la ruta no pidió su material)
      cap[c.itemID] = rem and math.ceil(rem - 0.001) or c.quantity
    end
  end
  -- (lo que la ruta da por hecho en pasos pasados, Planner.MadeNeed, ya es de esos pasos:
  -- no vale además como su material. 21 Cured Medium Hide para las Hillman's Shoulders
  -- contaban también como Medium Hide y la compra pedía una menos de las que faltaban)
  local reserved = {}
  for itemID, q in pairs(level and Planner.MadeNeed(plan, level) or {}) do reserved[itemID] = math.ceil(q - 0.001) end
  local inside = {}
  local function Walk(top, itemID, per, depth)
    local r = made[itemID]
    if not r or depth > 3 then return end
    local outN = math.max(1, r.out[2] or 1)
    for _, rg in ipairs(r.r) do
      local q = per * rg[2] / outN
      inside[rg[1]] = inside[rg[1]] or {}
      table.insert(inside[rg[1]], { top, q })
      Walk(top, rg[1], q, depth + 1)
    end
  end
  for itemID in pairs(made) do Walk(itemID, itemID, 1, 1) end
  return { inside = inside, cap = cap, reserved = reserved }
end

-- Lo que llevas de un material contando lo ya convertido (Planner.Conversions).
-- bags(itemID): lo que hay en las bolsas. Devuelve have(itemID)
function Planner.ConvertedHave(plan, bags, level)
  local conv = Planner.Conversions(plan, level)
  local function Held(itemID)
    return math.min(math.max(0, bags(itemID) - (conv.reserved[itemID] or 0)), conv.cap[itemID] or math.huge)
  end
  return function(itemID)
    local n = bags(itemID)
    for _, x in ipairs(conv.inside[itemID] or {}) do n = n + math.floor(Held(x[1]) * x[2] + 0.001) end
    return n
  end
end

-- Cuántas de un intermedio de plan.crafted gasta la ruta entera: las que fabricas y
-- las que saca de tus bolsas. Con "usar lo de tus bolsas", quantity ya no cuenta las
-- tuyas, y la fila les restaba otra vez lo que llevas: 57 Bolt of Silk Cloth, 10 en
-- las bolsas, y decía "Fabrica 37× · 47 en total" (CurseForge)
function Planner.CraftedTotal(c)
  return c.quantity + (c.owned or 0)
end

-- Cómo vas en el tramo con lo que llevas (have(itemID) = unidades):
-- { phase, short = { [itemID] = cuántas faltan para lo esperado }, extra = { [itemID]
--   = cuántas faltan hasta el colchón }, ok (llega a lo esperado) }
function Planner.PhaseOutlook(plan, level, have)
  local need, phase = Planner.PhaseNeed(plan, level)
  if not phase then return nil end
  local res = { phase = phase, short = {}, extra = {}, ok = true }
  for itemID, n in pairs(need) do
    local h = have(itemID) or 0
    local exp = math.ceil(n.expected - 0.001)
    if h < exp then res.short[itemID], res.ok = exp - h, false end
    if h < n.target then res.extra[itemID] = n.target - h end
  end
  return res
end

-- Fabricaciones totales de un plan
function Planner.TotalCrafts(plan)
  local n = 0
  for _, st in ipairs(plan.steps or {}) do n = n + st.crafts + (st.aheadCrafts or 0) end
  return n
end
local MAX_CRAFT_DEPTH = 3
local EPS = 1e-6

-- Probabilidad clásica de subir punto. Naranja es el 100% y gris no da puntos.
-- SKILL_BONUS (Working Overtime) está a 0: las rutas no lo cuentan hasta que se sepa
-- cómo lo aplica el juego (ver ES.COUNT_OVERTIME en Core.lua). Si se activa, aquí
-- multiplica (×1,16 con 4 rangos): sumado, al final del verde un 3% pasaba a 19% y la
-- ruta pedía menos de la mitad de las fabricaciones (CurseForge: "casi el triple")
Planner.SKILL_BONUS = 0
function Planner.Chance(t, skill)
  local yellow, grey = t[2], t[4]
  if skill < yellow then return 1 end
  if skill >= grey then return 0 end
  return math.min(1, (grey - skill) / (grey - yellow) * (1 + (Planner.SKILL_BONUS or 0)))
end

-- Al ELEGIR la ruta, los puntos verdes se cuentan con algo de mala suerte: las
-- fabricaciones esperadas (1/p) más GREEN_RISK desviaciones (√(1-p)/p). En verde la
-- incertidumbre es grande y no subir el punto es caro y frustra (comprar una y otra vez:
-- Discord, Red Linen Bag). Así, entre un verde y un naranja o amarillo que cuestan
-- parecido, gana el seguro. El coste que enseña la ruta sigue siendo el medio
Planner.GREEN_RISK = 0.5
-- Icono "Recetas en verde" desactivado (opts.noGreen): el recargo se dispara y la ruta
-- usa una receta naranja o amarilla siempre que haya una, aunque cueste más; en verde
-- solo donde no hay otra (Tailoring 285-300, First Aid 210-270). No es un filtro: la
-- ruta nunca se queda sin receta. CurseForge: "an option to NOT use green skill up
-- recipes"; "Menos fabricaciones" apenas las quitaba en niveles altos. Con 20 sale lo
-- mismo que con 100 en las rutas 1-300
Planner.NO_GREEN_RISK = 20
function Planner.GreenRisk(t, skill, chance, opts)
  if not (t and t[3]) or skill < t[3] or not chance or chance <= 0 or chance >= 1 then return 0 end
  local k = opts and opts.noGreen and Planner.NO_GREEN_RISK or Planner.GREEN_RISK
  return k * math.sqrt(1 - chance) / chance
end

-- Puntos de una ruta que se suben con la receta en verde (nivel >= su umbral verde,
-- t[3]). Para el tooltip del icono "Recetas en verde": en Peletería 1-150 la ruta tenía
-- uno solo y quitarlas apenas la cambiaba, y el jugador creía que la opción no hacía nada
function Planner.GreenPoints(plan)
  local n = 0
  for _, st in ipairs(plan and plan.steps or {}) do
    local t = st.recipe and st.recipe.t
    if t and t[3] then
      n = n + math.max(0, st.to - math.max(st.from, t[3]))
    end
  end
  return n
end

-- Recetas con enfriamiento (Transmute: Iron to Gold, una al día; Mooncloth, cada
-- 4 días). CurseForge: la ruta pedía 186 transmutaciones de 225 a 280 porque era lo
-- más barato. En la ruta valen como mucho para un punto, y solo en naranja (una sola
-- fabricación). Transmute: Elemental Fire no tiene enfriamiento. r.cd, si los datos
-- lo traen, manda
local NO_COOLDOWN = { [25146] = true }
local COOLDOWN = { [18560] = true } -- Mooncloth
function Planner.Cooldown(r, id)
  if r.cd ~= nil then return r.cd end
  if NO_COOLDOWN[id] then return false end
  -- (por el nombre en inglés: con el cliente en español r.name es "Transmutar: ..." y
  -- la ruta volvía a pedir 186 transmutaciones de hierro a oro)
  return COOLDOWN[id] or (r.nameEN or r.name or ""):find("^Transmute") ~= nil
end

-- Donde la ruta se para (no hay materiales para un punto entero: Rough Grinding
-- Stone al 62% pide 1,6 fabricaciones y llevas piedra para 1), lo que puedes
-- intentar con lo que llevas: la receta que sabes con más probabilidad de subir
-- a skill + 1. owned = { [itemID] = unidades }; isKnown(id) dice si la sabes.
-- Devuelve { id, recipe, crafts, chance, prob } o nil
function Planner.Attempt(data, skill, owned, isKnown)
  local best
  for id, r in pairs(data.recipes) do
    local chance = not r.intermediate and not r.conversion and Planner.Chance(r.t, skill) or 0
    local toolsOk = true
    for _, tool in ipairs(Planner.RecipeTools(r)) do
      if (owned[tool.item] or 0) <= 0 then toolsOk = false end
    end
    if chance > 0 and (r.t[1] or 1) <= skill and toolsOk and isKnown(id) then
      -- Fabricaciones que caben: lo que vende un vendedor no limita
      local fit
      for _, rq in ipairs(r.r) do
        if not ES.Data.VendorPrices[rq[1]] then
          local n = math.floor((owned[rq[1]] or 0) / rq[2])
          fit = fit and math.min(fit, n) or n
        end
      end
      local crafts = math.min(fit or 0, math.ceil(1 / chance - 0.001))
      if crafts >= 1 then
        local prob = 1 - (1 - chance) ^ crafts
        if not best or prob > best.prob + EPS or (math.abs(prob - best.prob) <= EPS and crafts < best.crafts) then
          best = { id = id, recipe = r, crafts = crafts, chance = chance, prob = prob }
        end
      end
    end
  end
  return best
end

-- Precio del instructor y nivel al que enseña la receta: lo visto en el juego
-- (Ledger:ReadTrainer, CraftersJournalDB.trainerFees) manda sobre los datos
function Planner.Fee(recipe)
  -- Las que se aprenden solas al coger la profesión (dato del cliente) no se pagan,
  -- aunque el instructor también las liste: Forever enseña Linen Bag "a 5 por 1s" a
  -- quien aún no tiene Sastrería, y tomarlo por bueno dejaba vacía la ruta fijada que
  -- la usaba desde 1 (captura del 2026-11-17)
  if recipe.basic then return recipe.fee, recipe.train end
  local seen = recipe.id and ES.db and ES.db.trainerFees and ES.db.trainerFees[recipe.id]
  if seen then
    -- El nivel leído del instructor nunca por debajo del de los datos del juego: uno
    -- más bajo es una lectura equivocada (Smelt Gold tomado por Transmute: Iron to
    -- Gold, 155 en vez de 225; ver Ledger, ServiceRecipe)
    local skill = seen.skill or recipe.train
    if skill and recipe.train and skill < recipe.train then skill = recipe.train end
    return seen.cost, skill
  end
  return recipe.fee, recipe.train
end
local Fee = Planner.Fee

-- Recetas de pergamino buscadas por sus fuentes reales (misión, vendedor, AH;
-- ver Waypoints.RecipeSource): solo si la profesión está en la prueba piloto
local function Sourced(recipe, opts)
  return opts.sourcedScrolls and recipe.scroll and not Fee(recipe)
end

local function ScanPrices()
  local scan = ES.db and ES.db.scans and ES.db.scans[ES:RealmKey()]
  return scan and scan.items or {}
end

-- ¿Ya la sabe el personaje? (necesita recipe.id; ver Annotate)
local function Known(recipe)
  return recipe.id and ES.IsRecipeKnown and ES:IsRecipeKnown(recipe.id)
end

-- Recetas que el instructor solo enseña tras una misión (recipe.unlock; spec
-- recipe-requirements). Discord 2026-11-23: Apothecary Renferrel no enseña las
-- Discolored Healing Potion hasta hacer su misión y la ruta mandaba allí sin decirlo.
-- La misión y quién la da en tu bando ({ q = misión o nil, npc = PNJ }), o nil
local SIDE = { Alliance = "A", Horde = "H" }
function Planner.UnlockFor(recipe)
  local u = recipe.unlock
  if not u then return nil end
  local faction = UnitFactionGroup and UnitFactionGroup("player")
  return faction and SIDE[faction] and u[SIDE[faction]] or nil
end

local function QuestDone(questID)
  if not questID then return false end
  local fn = (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) or IsQuestFlaggedCompleted
  if not fn then return false end
  local ok, done = pcall(fn, questID)
  return ok and done == true
end

-- ¿Ya te la enseña su instructor? Sí si no pide misión en tu bando, si la misión está
-- hecha, si ya la sabes o si un instructor se la ha listado a este personaje (Ledger:
-- ReadTrainer, CraftersJournalDB.unlockSeen: por personaje, porque lo guardado es de
-- toda la cuenta). Lo último sirve sin saber el número de la misión (la de la Horde)
function Planner.Unlocked(recipe, id)
  local mine = Planner.UnlockFor(recipe)
  if not mine then return true end
  id = id or recipe.id
  if id and ES.IsRecipeKnown and ES:IsRecipeKnown(id) then return true end
  if QuestDone(mine.q) then return true end
  local char = ES.CharKey and ES:CharKey()
  local all = char and ES.db and ES.db.unlockSeen
  local seen = type(all) == "table" and all[char]
  return type(seen) == "table" and id ~= nil and seen[id] == true
end

-- La misión que falta para que su instructor te la enseñe ({ q, npc } de tu bando), o
-- nil si no pide ninguna o ya está desbloqueada
function Planner.QuestFirst(recipe, id)
  if not (recipe and recipe.unlock) or Planner.Unlocked(recipe, id) then return nil end
  return Planner.UnlockFor(recipe)
end

-- Cuántas recetas con misión de la profesión están ya desbloqueadas (va en la clave de
-- la ruta: al entregar la misión cambia y la ruta se recalcula)
function Planner.UnlockStamp(data)
  local n = 0
  for id, r in pairs(data and data.recipes or {}) do
    if r.unlock and Planner.Unlocked(r, id) then n = n + 1 end
  end
  return n
end

-- Añade a `out` (el de RouteNeed) los pergaminos de receta que piden los pasos entre
-- `from` y `to` y se compran en la AH: uno por receta que aún no sabes (spec
-- route-shopping-mode). Con "ruta entera", tras comprarlo todo, el asistente volvía a
-- mandarte a la AH a por cada pergamino. Los de misión, vendedor o Merchant's Favor no:
-- su fila "Conseguir receta" te lleva. La fuente es la de comprarlo sin contar el que
-- llevas (WP.RecipeSource, buy): el comprado sigue en la lista, como comprado.
-- Entrada: { need = 1, expected = 1, source = "ah", unit, recipe }. No cuentan para "lo
-- tienes todo" (SetStocked) ni los recorta "hold": si no, tras comprar los materiales
-- dejaría de pedir el que no había, y uno en el correo impediría dar la compra por hecha
function Planner.AddRouteScrolls(plan, from, to, out)
  local ctx = plan and plan.ctx
  if not ctx then return false end
  local prices, opts = ctx.prices or ScanPrices(), ctx.opts or {}
  local seen, added = {}, false
  for _, st in ipairs(plan.steps or {}) do
    local r = st.recipe
    if r and r.scroll and st.to > from and st.from < to and not seen[r.scroll] then
      seen[r.scroll] = true
      -- (las de instructor, básicas, de fichas o intermedias no se compran: ver LearnCost)
      local learnable = not (Fee(r) or r.trainer or r.basic or r.favor)
        and not (Known(r) or (st.id and ES.IsRecipeKnown and ES:IsRecipeKnown(st.id)))
      local unit
      if learnable and Sourced(r, opts) then
        local src = Planner.RecipeSource(ctx, r)
        local buy = src and src.buy
        if buy and buy.kind == "ah" then unit = buy.cost end
      elseif learnable and not r.intermediate then
        local ah = prices[r.scroll]
        unit = ah and ah.minUnit
      end
      if unit then
        out[r.scroll] = { need = 1, expected = 1, source = "ah", unit = unit, recipe = st.id or r.id }
        added = true
      end
    end
  end
  return added
end

-- Tope del rango que enseña un instructor (máscara de Data/<Prof>.lua trainers): el más
-- bajo que enseña (1 aprendiz 75, 2 oficial 150, 4 experto 225, 8 artesano 300)
local MASK_CAPS = { { 1, 75 }, { 2, 150 }, { 4, 225 }, { 8, 300 } }
local function MaskCap(mask)
  for _, mc in ipairs(MASK_CAPS) do
    if mask % (mc[1] * 2) >= mc[1] then return mc[2] end
  end
end

-- Rango que hace falta para que un instructor te enseñe una receta. En Forever cada
-- rango tiene sus instructores y sus recetas: las que Forever subió de rango (Green
-- Iron Bracers/Helm/Leggings, de 130-145, solo las enseñan los de Experto: Bengus
-- Deepforge, Saru Steelfury, y Brikk Keencraft, de Artesano) no te las enseña nadie
-- mientras no tengas ese rango. Discord: a 144 con Oficial (nivel 10, Experto pide 20),
-- la ruta mandaba a Booty Bay a aprender Green Iron Bracers y Brikk no se la enseñaba.
-- r.tr = los únicos que la enseñan (ver tools/gen_profession.py); si ninguno es del
-- rango que le tocaría por su nivel, hace falta el más bajo de los de ellos.
-- Solo en las recetas en que se ha visto en el juego (RANK_GATED): en otras 27 los datos
-- dicen lo mismo, pero sin ningún caso visto, y aplicarlo a todas cambiaba rutas (la de
-- Peletería 120-225 con Oficial se paraba en 220). Si se confirma en más, se añaden aquí
local RANK_GATED = {
  [3501] = true, -- Green Iron Bracers (Discord: Brikk no se la enseñó a un Oficial de nivel 10)
  [3502] = true, -- Green Iron Helm
  [3506] = true, -- Green Iron Leggings (solo la enseñan los de Experto, ver CHANGELOG)
}
local function RankGate(data, r)
  if not (RANK_GATED[r.id] and r.tr and r.train and data.trainers and data.ranks) then return end
  local masks = {}
  for _, t in ipairs(data.trainers) do masks[t[1]] = t[2] end
  local need
  for _, npc in ipairs(r.tr) do
    local cap = masks[npc] and MaskCap(masks[npc])
    if not cap then return end -- instructor sin rango conocido: no se sabe, sin requisito
    need = need and math.min(need, cap) or cap
  end
  local own = r.train <= 75 and 75 or r.train <= 150 and 150 or r.train <= 225 and 225 or 300
  if not need or need <= own then return end
  -- A quién ir: los de ese rango (Bengus, Saru), no los de uno aún más alto (Brikk)
  local at = {}
  for _, npc in ipairs(r.tr) do
    if MaskCap(masks[npc]) == need then at[#at + 1] = npc end
  end
  local prev = APPRENTICE_CAP
  for _, rank in ipairs(data.ranks) do
    if rank[1] == need then return need, rank[3], prev, at end
    prev = rank[1]
  end
end

-- Cada receta guarda su id (el hechizo) para poder preguntar si ya se sabe, y el rango
-- que pide su instructor (rankCap, rankSkill, rankPrev, rankTr; ver RankGate)
local function Annotate(data)
  if data._annotated then return end
  for id, r in pairs(data.recipes) do
    r.id = id
    r.rankCap, r.rankSkill, r.rankPrev, r.rankTr = RankGate(data, r)
  end
  data._annotated = true
end
Planner.Annotate = Annotate

-- Nivel mínimo para aprender la receta, o nil si no la consideramos disponible
function Planner.LearnSkill(recipe, opts)
  local fee, train = Fee(recipe)
  if Known(recipe) then return train or 1 end -- ya la sabes: siempre disponible
  if recipe.gone then return nil end -- Forever no la enseña (ver tools/gen_profession.py)
  -- De especialización (Goblin, Armorsmith...): solo si la tienes
  if recipe.spec and not (ES.HasSpecialization and ES:HasSpecialization(recipe.spec)) then return nil end
  -- Ningún instructor visto la enseña (Forever la quitó; ver Ledger:ReadTrainer)
  -- (las que piden una misión no: una lectura de antes podía darlas por quitadas)
  if recipe.id and not recipe.unlock and ES.db and ES.db.trainerMissing and ES.db.trainerMissing[recipe.id] == "gone" then return nil end
  if recipe.rep and not ES:RepMet(recipe.rep) then return nil end -- te falta reputación
  -- Su instructor solo la enseña tras una misión que no has hecho: con el icono de
  -- misión desactivado, no se usa (con él, sí: el paso avisa de la misión)
  if recipe.unlock and opts.noQuests and not Planner.Unlocked(recipe) then return nil end
  -- Merchant's Favor: se compra con fichas y reputación del campamento, no con oro.
  -- Solo con su icono activado (opts.useFavor; por defecto no): entonces cuesta 0 oro
  if recipe.favor then return opts.useFavor and (recipe.train or 1) or nil end
  if Sourced(recipe, opts) then
    local src = ES.Waypoints.RecipeSource(recipe, opts.prices or ScanPrices(), opts.noQuests, opts.noLimited)
    return src and src.best and (recipe.train or 1) or nil
  end
  if fee and recipe.rankCap and opts.from and opts.to then
    -- Solo la enseñan instructores de un rango superior (ver RankGate): con ese rango
    -- ya entrenado, o si la ruta lo entrena (pasa de su tope anterior; ver Plan, rangos),
    -- desde que lo entrena. Si no, no la enseña nadie
    -- (tope sin conocer: el del rango que cubre tu nivel, como en Plan; ese es menor
    -- que el que pide justo cuando aún no has pasado el tope anterior)
    local below
    if opts.cap then below = opts.cap < recipe.rankCap else below = opts.from < recipe.rankPrev end
    if below then
      if opts.to <= recipe.rankPrev then return nil end
      return math.max(train or 1, recipe.rankSkill)
    end
  end
  if fee or recipe.intermediate then return train end
  if recipe.basic then return 1 end -- se aprende sola al coger la profesión (dato del cliente)
  -- De instructor sin precio conocido (nueva de Forever): al ponerse amarilla
  if recipe.trainer then return train or recipe.t[2] end
  -- Datos antiguos sin "basic": las de amarilla baja eran básicas
  if not recipe.scroll and recipe.basic == nil and recipe.trainer == nil and recipe.t[2] <= BASIC_MAX_YELLOW then return 1 end
  if not opts.includeScrolls then return nil end
  if recipe.scroll then return recipe.train end
  -- Sin instructor ni pergamino conocido (misión, reputación...): estimación
  return math.max(1, recipe.t[2] - 10)
end

-- Cuánto cuesta aprender la receta y de dónde: "known" (ya la sabes), "trainer",
-- "vendor", "scroll", "owned" (pergamino en tus bolsas), "quest", "ah", "favor"
-- (Merchant's Favor: fichas, no oro) o "unknown"
function Planner.LearnCost(ctx, recipe)
  if Known(recipe) then return 0, "known" end
  if recipe.rep and not ES:RepMet(recipe.rep) then return 0, "rep" end -- solo para la vista Recetas
  -- De una especialización que no tienes (Tribal, Goblin...): no se puede aprender, ni
  -- se propone en Ganar dinero (como en LearnSkill)
  if recipe.spec and not (ES.HasSpecialization and ES:HasSpecialization(recipe.spec)) then return 0, "spec" end
  -- Pide una misión que no has hecho y el icono de misión está desactivado: no se
  -- puede aprender (como en LearnSkill; tampoco sale en Ganar dinero)
  if recipe.unlock and ctx.opts and ctx.opts.noQuests and not Planner.Unlocked(recipe) then return 0, "locked" end
  local fee = Fee(recipe)
  if fee then return fee, "trainer" end
  if recipe.trainer then return 0, "trainer" end -- de instructor, precio desconocido (se pinta "?")
  if recipe.basic then return 0, nil end
  if recipe.favor then return 0, "favor" end
  if Sourced(recipe, ctx.opts) then
    -- (la misión, a lo que cuesta lo que piden ella y su cadena: Planner.RecipeSource)
    local src = Planner.RecipeSource(ctx, recipe)
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

-- (también la Calculadora: el coste de los materiales de la AH, subiendo por la escalera)
Planner.Ladder, Planner.LadderSupply, Planner.LadderCost = Ladder, LadderSupply, LadderCost

local NONE = {} -- (tabla vacía compartida: no se escribe en ella)
local function NewContext(data, opts)
  Annotate(data)
  local scan = ES.db.scans[ES:RealmKey()]
  local ctx = {
    data = data,
    opts = opts,
    -- opts.prices: los de la ruta fijada (guardados al empezarla); si no, el último escaneo
    prices = opts.prices or (scan and scan.items) or {},
    scanTime = opts.prices and opts.pricesTime or (scan and scan.time),
    ladders = {},
    supply = {},     -- unidades a la venta de cada objeto (suma de su escalera)
    medians = {},    -- mediana de lo anunciado (con todos los precios; ver Scanner.BuildLadder)
    used = {},       -- unidades de cada objeto ya compradas en la AH por el plan
    stock = {},      -- inventario del plan: lo fabricado en pasos anteriores, por lotes de valor
    owned = {},      -- lo que llevas en bolsas/banco y queda por usar
    -- [itemID] = "craft" | "buy": lo que se decidió la primera vez para un material que
    -- se puede fabricar; se mantiene en todo el plan (no restos Y cuero comprado a la
    -- vez). opts.via lo fija de antemano (ver Plan y la ruta fijada)
    via = {},
    visiting = {},
    producers = {},
  }
  -- opts.shared (PlanGPS): escaleras y quién fabrica qué, ya preparadas en este
  -- mismo cálculo (mismos precios y mismo objetivo); no se modifican, se comparten
  local shared = opts.shared
  if shared and shared.prices == ctx.prices and shared.to == opts.to then
    ctx.ladders, ctx.supply, ctx.medians, ctx.producers = shared.ladders, shared.supply, shared.medians, shared.producers
    ctx.foreign, ctx.foreignProf = shared.foreign, shared.foreignProf
  else
    shared = nil
    for itemID, entry in pairs(ctx.prices) do
      local ladder = Ladder(entry)
      ctx.ladders[itemID] = ladder
      ctx.supply[itemID] = ladder and LadderSupply(ladder)
      ctx.medians[itemID] = entry.median
    end
  end
  for itemID, count in pairs(opts.owned or {}) do
    if count > 0 then ctx.owned[itemID] = count end
  end
  for itemID, way in pairs(opts.via or {}) do ctx.via[itemID] = way end
  -- Herramientas por familia (bastones rúnicos, martillo, piedra filosofal):
  -- dentro de una familia la mejor que ya tienes cubre las inferiores. opts.tools: las
  -- que llevas, aunque la ruta no use lo de las bolsas (ES:CarriedTools)
  ctx.toolMask = {}
  for _, tool in pairs(ES.Data.Tools or {}) do
    local fam = tool.family or "rod"
    local have = (opts.tools and opts.tools[tool.item]) or (opts.owned and opts.owned[tool.item])
    if have and have > 0 and tool.mask > (ctx.toolMask[fam] or 0) then ctx.toolMask[fam] = tool.mask end
  end
  if not shared then
    for id, r in pairs(data.recipes) do
      local learn = r.out and Planner.LearnSkill(r, opts)
      -- opts.knownProducers (Ganar dinero): solo se fabrica lo intermedio con recetas
      -- que ya sabes. Con las que podrías aprender (lo de las rutas), proponía comprar
      -- 684 Heavy Stone para hacer Heavy Blasting Powder aunque no supieras hacerla
      -- (CurseForge). (r.id: Annotate, antes de NewContext)
      if learn and opts.knownProducers and not Known(r) then learn = nil end
      if learn and learn <= opts.to then
        local list = ctx.producers[r.out[1]] or {}
        list[#list + 1] = id
        ctx.producers[r.out[1]] = list
      end
    end
    -- opts.foreignProducers (las rutas: ES:ForeignProducers): recetas que sabes de otras
    -- profesiones y de la fundición (Smelt Mithril para Herrería). Van detrás de las de
    -- la profesión y solo como preparación (ver Acquire)
    local fp = opts.foreignProducers
    if fp then
      ctx.foreign, ctx.foreignProf = fp.recipes, fp.prof
      for itemID, ids in pairs(fp.producers) do
        local list = ctx.producers[itemID] or {}
        for _, id in ipairs(ids) do list[#list + 1] = id end
        ctx.producers[itemID] = list
      end
    end
  end
  ctx.foreign, ctx.foreignProf = ctx.foreign or NONE, ctx.foreignProf or NONE
  return ctx
end

-- La receta de un id de ctx.producers o de una acción de fabricar: de la profesión o de
-- otra (ctx.foreign)
local function CtxRecipe(ctx, rid)
  return ctx.data.recipes[rid] or ctx.foreign[rid]
end
Planner.CtxRecipe = CtxRecipe

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
-- Claves "o<itemID>" de lo tuyo en `extra`: la misma cadena, creada una vez por objeto
local OWN_KEYS = setmetatable({}, { __index = function(t, itemID) local k = "o" .. itemID t[itemID] = k return k end })
local function Acquire(ctx, itemID, qty, depth, extra, actions, why, skip)
  -- 1. Lo que ya llevas en bolsas/banco: gratis
  local have = skip == nil and ctx.owned[itemID]
  if have then
    local ownKey = OWN_KEYS[itemID]
    local usedNow = extra[ownKey] or 0
    local avail = have - usedNow
    if avail > EPS then
      local take = math.min(avail, qty)
      -- (el GPS le pone precio: lo que te darían vendiéndolo; ver PlanGPS)
      local own = take * (ctx.ownedPrice and ctx.ownedPrice[itemID] or 0)
      extra[ownKey] = usedNow + take
      actions[#actions + 1] = { kind = "owned", item = itemID, qty = take, cost = own }
      if qty - take <= EPS then return own end
      local rest = Acquire(ctx, itemID, qty - take, depth, extra, actions, why, "owned")
      return rest and rest + own
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

      -- (fabricar más de lo mismo dejando sin usar lo ya fabricado nunca: la ruta
      -- decía "fabrica 108 de pólvora" con las 86 del paso anterior en la bolsa)
      local craftsAgain = false
      for _, a in ipairs(acB) do
        if a.kind == "craft" and a.item == itemID then craftsAgain = true end
      end
      local useA = costA and (not costB or costA <= costB or craftsAgain)
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
  -- opts.vendorDiscount: descuento en lo que se compra al vendedor (reputación con tu
  -- capital, Bartering: la pestaña BulkMoney); las rutas no lo usan
  local discount = ctx.opts.vendorDiscount
  if vendor and discount and discount > 0 then vendor = math.floor(vendor * (1 - discount) + 0.5) end
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
      -- Si el vendedor lo vende, la AH tiene que salir bastante más barata: por 1 cobre
      -- (Fine Thread a 99c en la AH, 100c en el vendedor) no compensa ir a comprarlo allí
      if not best or cost < best * (kind == "vendor" and Planner.VENDOR_EDGE or 1) then best, kind = cost, "ah" end
    elseif not vendor then
      why[itemID] = why[itemID] or "supply"
    end
  end

  -- Decidido antes comprarlo (y se puede): no se mira fabricarlo
  local via = ctx.via[itemID]
  local canCraft = depth < MAX_CRAFT_DEPTH and ctx.producers[itemID] and not ctx.visiting[itemID]
  if via == "buy" and best then canCraft = false end
  local blockBuy -- (ver abajo: lo que la ruta fabrica y aún da puntos no se compra entretanto)
  local ahead -- (ver abajo: se fabrica de más en su propio paso, antes)
  if canCraft then
    ctx.visiting[itemID] = true
    for _, rid in ipairs(ctx.producers[itemID]) do
      local r = ctx.data.recipes[rid]
      -- De otra profesión (Smelt Mithril para Herrería): siempre preparación, como un
      -- intermedio. Sus colores son de la otra profesión: no se miran contra tu nivel,
      -- no es un paso (ni ahead) y no bloquea la compra
      local foreign = not r
      r = r or ctx.foreign[rid]
      local crafts = qty / r.out[2]
      local subExtra, subActions, total = Copy(extra), {}, 0
      -- Con enfriamiento (Mooncloth, transmutaciones: Planner.Cooldown) no se fabrica lo
      -- que se puede comprar: es una cada pocos días. La Mooncloth salía a 93s (2
      -- Felcloth) en vez de los 60g de la AH, y la Mooncloth Bag con 47g de beneficio
      -- (Calculadora: Calc.DefaultMode). Si no se puede comprar, se fabrica igual
      if best and Planner.Cooldown(r, rid) then
        total = nil
      -- Una receta que aún da puntos a tu nivel (Rough Blasting Powder a 1) no se
      -- fabrica a escondidas como preparación: la ruta diría "fabrica 133 a nivel 1" y
      -- esas fabricaciones subirían la profesión sin contar. Tiene que ser un paso de la
      -- ruta, y en ese paso se fabrica todo lo que pedirán los siguientes (como las
      -- guías: "1-30: 60 pólvoras, guárdalas para las bombas"): si la ruta ya tuvo un
      -- paso con esa receta (ctx.made), lo que falta se fabrica de más en él (ahead).
      -- Sí como preparación: lo intermedio que no da puntos (Cured Thick Hide,
      -- conversiones) y lo que ya está en gris
      -- Solo si al empezar el paso que lo usa aún daría puntos (ctx.stepStart): si no, a
      -- mitad de ese paso pediría fabricar algo que sube puntos (los tornillos de las
      -- bombas). Si ya está en gris al empezarlo, se fabrica ahí como preparación, no
      -- todo de golpe en un paso de hace 100 niveles (el Light Leather de las botas)
      elseif not foreign and ctx.skill and ctx.made and ctx.made[rid]
        and Planner.Chance(r.t, ctx.stepStart or ctx.skill) > 0 then
        ahead = rid
      elseif not foreign and ctx.skill and not r.intermediate and not r.conversion and Planner.Chance(r.t, ctx.skill) > 0 then
        total = nil
        -- Y si la ruta lo fabrica (via "craft"), tampoco se compra mientras tanto: si
        -- no, "compra hasta 40 y fabrica desde 40". Tiene que venir de un paso de la ruta
        if via == "craft" then blockBuy = true end
      end
      for _, rq in ipairs(total and r.r or {}) do
        local cost = Acquire(ctx, rq[1], rq[2] * crafts, depth + 1, subExtra, subActions, why)
        if not cost then total = nil break end
        total = total + cost
      end
      -- Fabricarlo tiene que ahorrar al menos INTERMEDIATE_CRAFT_COST por fabricación:
      -- si no, se compra (521 Ruined Leather Scraps y 174 fabricaciones de Light
      -- Leather por 1 cobre menos cada uno no compensan). Solo si se puede comprar:
      -- si no hay otra vía, se fabrica igual
      -- Decidido antes fabricarlo: se fabrica aunque ahora comprarlo saliera algo
      -- mejor. Entre dos recetas que lo fabrican, la más barata
      local better = total and (not best
        or (kind == "craft" and total < best)
        or (kind ~= "craft" and (via == "craft" or total + crafts * INTERMEDIATE_CRAFT_COST < best)))
      if better then
        best, kind = total, "craft"
        craft = { extra = subExtra, actions = subActions, recipe = rid, ahead = ahead == rid,
          prof = foreign and ctx.foreignProf[rid] or nil }
      end
    end
    ctx.visiting[itemID] = nil
  end
  if blockBuy and kind ~= "craft" then best, kind = nil, nil end

  if not best then
    if not ladder and not vendor then why[itemID] = why[itemID] or "price" end
    return nil
  end

  if kind == "craft" then
    for k, v in pairs(craft.extra) do extra[k] = v end
    for _, a in ipairs(craft.actions) do actions[#actions + 1] = a end
    actions[#actions + 1] = { kind = "craft", item = itemID, qty = qty, cost = best, recipe = craft.recipe, ahead = craft.ahead or nil,
      prof = craft.prof }
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
    local r = CtxRecipe(ctx, rid)
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

---------------------------------------------------------------------------
-- Lo que cuesta una receta de misión: los objetos que pide la misión y los que piden
-- las de su cadena que aún no has hecho (Data/Sources.lua, Quests: { objeto, cuántos }).
-- Antes contaban como gratis. Discord: la ruta de Peletería usaba Wild Leather Leggings
-- "gratis" y su cadena (Shoulders, Vest, Helmet y Leggings) pedía objetos por casi 20 de
-- oro: Turtle Scale y Nightscape fabricados, Thick Armor Kits, Wildvines...
---------------------------------------------------------------------------
-- Lo más barato entre lo que llevas, comprarlo (vendedor o AH) o fabricarlo; nil sin precio
local function TurnInItemCost(ctx, itemID, qty)
  local buy = Acquire(ctx, itemID, qty, MAX_CRAFT_DEPTH, {}, {}, {}) -- (sin fabricar)
  local unit = Planner.CraftUnitCost(ctx, itemID)
  local craft = unit and unit * qty
  if buy and craft then return math.min(buy, craft) end
  return buy or craft
end

-- { cost, unpriced, items = { { item, qty, cost } } } de una misión. unpriced: pide algo
-- sin precio (botín de criaturas, objetos de misión) o sin saber cuántos (qty 0); eso no
-- suma: la ruta cuenta lo que sí tiene precio y la fila avisa del resto
local function OneQuestCost(ctx, questID)
  local baked = ES.Data.Quests and ES.Data.Quests[questID]
  local c = { cost = 0, items = {} }
  if not baked then return c end -- (no está: no pide objetos)
  local list = baked[7]
  if baked[5] and not list then c.unpriced = true end -- (datos sin los objetos)
  for i = 1, #(list or {}), 2 do
    local itemID, qty = list[i], list[i + 1]
    local cost = qty > 0 and TurnInItemCost(ctx, itemID, qty) or nil
    if cost then c.cost = c.cost + cost else c.unpriced = true end
    c.items[#c.items + 1] = { item = itemID, qty = qty, cost = cost, quest = questID }
  end
  return c
end

-- Lo que cuesta la misión `q` (de WP.Quest) y lo que falta de su cadena: coste, si
-- hay algo sin precio y la lista de objetos. Las misiones hechas no cuentan, ni las de
-- `paid` (ya pagadas por otro paso de la ruta: Vest y Leggings comparten cadena)
function Planner.QuestCost(ctx, q, paid)
  local cache = ctx.questCost
  if not cache then cache = {} ctx.questCost = cache end
  local total, unpriced, items = 0, false, {}
  local function Add(questID)
    if (paid and paid[questID]) or QuestDone(questID) then return end
    local c = cache[questID]
    if not c then c = OneQuestCost(ctx, questID) cache[questID] = c end
    total = total + c.cost
    unpriced = unpriced or c.unpriced or false
    for _, it in ipairs(c.items) do items[#items + 1] = it end
  end
  Add(q.id)
  for _, p in ipairs(q.pre or {}) do Add(p) end
  return total, unpriced, items
end

-- WP.RecipeSource con la misión a su precio (lo que piden ella y su cadena): con eso se
-- elige la mejor fuente (si la misión cuesta más que el pergamino en la AH o en el
-- vendedor, gana el pergamino). Es la fuente que usan la ruta y su fila "Conseguir receta"
function Planner.RecipeSource(ctx, recipe)
  local opts = ctx.opts or {}
  local src = ES.Waypoints.RecipeSource(recipe, ctx.prices, opts.noQuests, opts.noLimited)
  if not (src and src.options) then return src end
  local cache = ctx.sources
  if not cache then cache = {} ctx.sources = cache end
  local hit = cache[recipe.scroll]
  if hit and hit.from == src then return hit.out end
  local out = src
  for i, o in ipairs(src.options) do
    if o.kind == "quest" then
      local cost, unpriced, items = Planner.QuestCost(ctx, o.quest)
      if cost > 0 or unpriced then
        out = {}
        for k, v in pairs(src) do out[k] = v end
        out.options = {}
        for j, other in ipairs(src.options) do out.options[j] = other end
        out.options[i] = { kind = "quest", cost = cost, quest = o.quest, unpriced = unpriced or nil, items = items }
        -- La más barata; a igual precio, misión antes que vendedor antes que AH (como WP)
        local best
        for _, x in ipairs(out.options) do
          if not best or x.cost < best.cost then best = x end
        end
        if src.repLocked then best = nil end
        out.buy = best
        -- (el pergamino en tus bolsas sigue siendo lo mejor: ver WP.WithOwned)
        out.best = (src.best and src.best.kind == "owned") and src.best or best
      end
      break
    end
  end
  cache[recipe.scroll] = { from = src, out = out }
  return out
end

-- Material que se compra aunque fabricarlo salga más barato por unidad, porque su receta
-- aún da puntos donde se usa: cada uno que fabricases sería un punto que daría el paso
-- que lo gasta. Devuelve ese paso (el primero que lo gasta con la receta aún con puntos)
-- o nil. Discord: Heavy Blasting Powder (3s 68c fabricada, 4s 22c en la AH) se compraba
-- para Heavy Dynamite, con los mismos umbrales (125/135/145) y que gana dinero vendida
function Planner.CraftTakesPoints(plan, itemID, recipe)
  if not (recipe and recipe.t) then return nil end
  -- (una de otra profesión, Smelt Mithril, no da puntos de esta)
  if plan.ctx and plan.ctx.foreign and plan.ctx.foreign[recipe.id] == recipe then return nil end
  for _, st in ipairs(plan.steps or {}) do
    for _, rg in ipairs(st.reagents or {}) do
      if rg.item == itemID and st.id ~= recipe.id and Planner.Chance(recipe.t, st.from) > 0 then return st end
    end
  end
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
      -- (lo fabricado de más en un paso anterior no lo fabrica este paso: "ahead")
      local a = actions[i]
      if a.item == rq[1] then kinds[a.ahead and "ahead" or a.kind] = true end
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
  -- El juego aún no ha cargado el objeto (precio de los datos, quizá antiguo): al
  -- llegar se recalcula la ruta con el precio de ahora
  -- (cuáles: la página recalcula solo cuando llega uno de estos, no con cualquier objeto)
  if not vendor or (ES.SellPriceIsLive and not ES:SellPriceIsLive(itemID)) then
    ctx.pendingInfo = true
    ctx.pendingItems = ctx.pendingItems or {}
    ctx.pendingItems[itemID] = true
  end
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
      -- (el resto se guarda para anunciarlo cuando se vendan esas, en varios días; no
      -- al vendedor: en la AH vale claramente más. Igual que Inventory:List)
      a.later = d.sell - a.ah
    end
    -- Precio: 1 cobre por debajo de la más barata, o el realista si está inflada
    a.price = ES.Market.ListPrice(sale.fair) or 1
    a.inflated = sale.fair and sale.fair.inflated
  end
  a.vendor = sale.vendor > 0 and d.sell - a.ah - (a.later or 0) or 0
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
-- GPS: la ruta más corta de nivel en nivel (Planner.PlanGPS)
---------------------------------------------------------------------------
-- Subir una profesión es como buscar el camino más corto: los niveles son las
-- ciudades y cada receta, una carretera que cuesta en cada punto sus fabricaciones
-- esperadas (materiales menos lo que sacas vendiéndolo). Empezar a usar una receta
-- paga su instructor o pergamino y GPS_STEP_COST (pocos pasos; volver a una ya
-- usada lo paga otra vez: sin zigzag). Programación dinámica: para cada nivel y
-- receta, la ruta más barata que llega ahí usándola. Mira la ruta entera.
-- El camino se calcula con precios por unidad; la escalera de la AH, lo fabricado
-- que se reutiliza y tus bolsas solo se ven al recorrer la ruta de verdad (la
-- pasada forzada de Plan, rápida). Así que PlanGPS propone caminos, los recorre,
-- y repite con los precios que pagaría la mejor (linealizar), quitando cada una de
-- sus recetas y cambiando fabricar ↔ comprar. Gana la de menor Planner.RouteScore.
Planner.USE_GPS = true         -- el planificador del addon (false: el antiguo, solo para tools/route_qa.py)
local GPS_STEP_COST = 100      -- cobre por cada receta nueva en la ruta (pocos pasos)
local ZIGZAG_STEPS, ZIGZAG_MIN, ZIGZAG_PCT = 5, 2000, 0.03 -- saltos A-B-A de hasta 5 puntos: fuera si cuesta < 20s o 3% más
local GPS_AHEAD_ROUNDS = 4      -- veces que se alarga un paso con lo que fabrica de más (ver Walk)
local UNFOLLOWABLE_COST = 10000000 -- ruta que no se puede seguir (ver plan.unfollowable): solo si no hay otra
local GPS_ROUNDS = 4           -- vueltas con los precios de la mejor ruta hasta ahora
local GPS_VIA_ROUNDS = 2       -- vueltas de fabricar ↔ comprar sobre cada ruta recorrida
local GPS_BAGS_ALTS = 4        -- recetas con lo tuyo que se prueban en su tramo
local GPS_TUNE_MOVES = 40      -- ajustes finos de fronteras que se aceptan como mucho
local GPS_TUNE_WALKS = 500     -- recorridos del ajuste fino como mucho
local GPS_SEGMENT_ROUNDS = 3   -- vueltas repensando cada tramo con el GPS
local GPS_SUB_ROUNDS = 8       -- cambios de receta de un paso que se aceptan como mucho
local GPS_SUB_CANDIDATES = 5   -- recetas que se prueban en lugar de cada paso
local GPS_TOP = 4              -- mejores rutas vistas que se repasan al final
-- Recorridos de la búsqueda como mucho (Planner.GPS_MAX_WALKS). Una ruta difícil
-- (Engineering 1-300, con GreenRisk) llegaba a 3700 y en el juego tardaba minutos:
-- "se queda en el 99%" (CurseForge). Pasado el tope se queda la mejor encontrada; los
-- arreglos del final (aprender para pocas, saltos) se hacen siempre
Planner.GPS_MAX_WALKS = 1800
local GPS_NEAR_PCT = 0.05      -- fabricar ↔ comprar solo en rutas a menos de un 5%
local GPS_NEAR_MIN = 500       -- (o 5s) de la mejor

-- Puntuación de una ruta entera, la vara con la que se comparan (PlanGPS y
-- tools/route_qa.py): lo que cuesta, más CRAFT_COST por fabricación (pasos e
-- intermedios: no 2000 materiales por unas monedas) y GPS_STEP_COST por paso. Lo
-- que ganas vendiendo un paso que da dinero cuenta como si hicieras una
-- fabricación por punto: si no, gana una receta casi gris solo por fabricar mucho
-- para el vendedor (96 Phoenix Bindings con un patrón de 75g). Lo que usas de tus
-- bolsas cuenta por lo que te darían vendiéndolo, con un margen de BAGS_TIE_PCT a
-- favor de usarlo (como Planner.BagsWorth): no se gastan 34 Medium Hide de 15g
-- para ahorrar 1g
-- Segundos por fabricación de una receta: su lanzamiento en el juego (algunas de
-- Forever tardan 30-50 s) con un mínimo (las instantáneas esperan el tiempo global) y
-- un margen. Se pregunta una vez por receta y sesión
local DEFAULT_CAST = 3        -- s si el juego no dice el lanzamiento
local MIN_CAST = 1.5
local CRAFT_OVERHEAD = 0.5
local castMemo = {}
ES.MemPart("tiempos de fabricar", function() return castMemo end)
-- Lo que se tarda en fabricar toda la ruta (sus pasos, como la fila del total): para
-- comparar rutas por tiempo y no solo por oro (la franja de resumen)
function Planner.RouteSeconds(plan)
  local secs = 0
  for _, st in ipairs(plan and plan.steps or {}) do
    secs = secs + (st.crafts + (st.aheadCrafts or 0)) * Planner.CraftSeconds(st.id)
  end
  return secs
end

function Planner.CraftSeconds(recipeID)
  local s = castMemo[recipeID]
  if s then return s end
  local ms
  if C_Spell and C_Spell.GetSpellInfo then
    local ok, info = pcall(C_Spell.GetSpellInfo, recipeID)
    if ok and type(info) == "table" then ms = info.castTime end
  end
  if not ms and GetSpellInfo then
    local ok, _, _, _, castTime = pcall(GetSpellInfo, recipeID)
    if ok then ms = castTime end
  end
  local known = type(ms) == "number" and ms > 0
  s = math.max(MIN_CAST, known and ms / 1000 or DEFAULT_CAST) + CRAFT_OVERHEAD
  -- (siempre se guarda: el planificador lo pide miles de veces por ruta, y los datos
  -- de los hechizos son del propio cliente, no llegan más tarde)
  castMemo[recipeID] = s
  return s
end
function Planner.ClearCraftSeconds() castMemo = {} end -- (pruebas)
-- Una fabricación "normal" (3 s): con "Menos fabricaciones", cada una pesa lo que
-- tarda frente a esta (una de 50 s pesa como ~14 normales)
Planner.NORMAL_CRAFT_SECONDS = DEFAULT_CAST + CRAFT_OVERHEAD

-- Peso de cada fabricación: CRAFT_COST, o el de opts.craftWeight (icono "Menos
-- fabricaciones": la ruta paga más a cambio de fabricar menos veces y, con él, cuenta
-- lo que tarda cada una: evita las lentas aunque salgan más baratas, CurseForge)
Planner.FEWER_CRAFTS_WEIGHT = 100 -- 1s por fabricación normal con el icono activado
local function CraftWeight(opts)
  return opts and opts.craftWeight or CRAFT_COST
end
Planner.CraftWeight = CraftWeight
-- El peso de una fabricación de esta receta: sin el icono, igual para todas
local function RecipeWeight(opts, recipeID)
  local w = CraftWeight(opts)
  if not (opts and opts.craftWeight) or not recipeID then return w end
  return w * Planner.CraftSeconds(recipeID) / Planner.NORMAL_CRAFT_SECONDS
end
Planner.RecipeWeight = RecipeWeight

-- memo (PlanGPS): { [plan] = puntuación sin lo de tus bolsas }, para no rehacerla en
-- cada comparación del mismo cálculo (lo de tus bolsas se cuenta siempre de nuevo)
function Planner.RouteScore(plan, memo)
  local opts = plan.ctx and plan.ctx.opts
  local score = memo and memo[plan]
  if not score then
  local CW = CraftWeight(opts)
  local crafts
  score, crafts = plan.fees + (plan.toolsCost or 0), 0
  for _, st in ipairs(plan.steps) do
    local gain = st.crafts * (st.unitValue - st.unitCost)
    -- (entero hasta PROFIT_FULL_CRAFTS fabricaciones por punto; más allá, rebajado: casi gris)
    local per = st.crafts / math.max(1, st.to - st.from)
    if gain > 0 and per > PROFIT_FULL_CRAFTS then gain = gain * PROFIT_FULL_CRAFTS / per end
    score = score - gain
    -- (con "Menos fabricaciones", cada una pesa lo que tarda: RecipeWeight)
    score = score + RecipeWeight(opts, st.id) * (st.crafts + (st.aheadCrafts or 0))
    -- En verde, algo de mala suerte (Planner.GreenRisk): las fabricaciones de más que
    -- podrían hacer falta, a lo que cuesta cada una
    local risk = 0
    for s = st.from, st.to - 1 do
      local p = plan.pointChance and plan.pointChance[s]
      risk = risk + Planner.GreenRisk(st.recipe and st.recipe.t, s, p, opts)
    end
    if risk > 0 then score = score + risk * (math.max(0, st.unitCost) + RecipeWeight(opts, st.id)) end
  end
  for _, c in ipairs(plan.crafted or {}) do crafts = crafts + c.quantity end
  score = score + CW * crafts + GPS_STEP_COST * math.max(0, #plan.steps - 1)
  -- (ruta que pide fabricar a mitad de paso lo que ya hacía falta al empezarlo)
  if plan.unfollowable then score = score + UNFOLLOWABLE_COST end
  if memo then memo[plan] = score end
  end
  local have = plan.ctx and plan.ctx.opts.owned
  if have and plan.owned then
    for _, o in ipairs(plan.owned) do
      score = score + (1 - BAGS_TIE_PCT) * Planner.OwnedCost(plan.ctx, o.itemID, have[o.itemID] or o.quantity, o.quantity)
    end
  end
  return score
end

-- Devuelve { [nivel] = receta } con la ruta más barata, o nil. weight: coste
-- simbólico por fabricación; skip: recetas que no se pueden usar; fixed:
-- { [nivel] = receta } que van sí o sí (una receta con lo tuyo en su tramo)
-- Lo que cuesta un punto de una receta en un nivel (sin el peso por fabricación):
-- { neto, fabricaciones } o false. Se guarda en el contexto: las variantes del
-- camino (sin tal receta, con tal tramo fijo) reutilizan los mismos costes
-- Puntos que dan de media los materiales que se fabrican para un punto (Rough
-- Blasting Powder para la Rough Dynamite, Light Leather de chatarras...): son recetas
-- normales y, si aún no están en gris, suben la profesión (Discord: 63 de dinamita
-- pedían 63 de pólvora, que ya llevaban a 51). Las marcadas "intermediate" (Cured
-- Thick Hide) y las conversiones no dan puntos
local function CraftBonus(ctx, actions, s)
  local g = 0
  for _, a in ipairs(actions or {}) do
    -- (lo fabricado de más en su paso, antes: sus puntos los da ese paso, ver Plan)
    local ir = a.kind == "craft" and not a.ahead and a.recipe and ctx.data.recipes[a.recipe]
    if ir and not ir.intermediate and not ir.conversion and ir.t and (ir.t[1] or 1) <= s then
      g = g + a.qty / ((ir.out and ir.out[2]) or 1) * Planner.Chance(ir.t, s)
    end
  end
  return g
end
Planner.CraftBonus = CraftBonus

local function PointCost(ctx, rc, s)
  local row = ctx.gpsCost[rc.id]
  if not row then row = {} ctx.gpsCost[rc.id] = row end
  local v = row[s]
  if v == nil then
    v = false
    local chance = Planner.Chance(rc.r.t, s)
    if chance > 0 then
      local crafts = 1 / chance
      ctx.skill = s -- (como en Plan: lo que da puntos a este nivel no se fabrica como preparación)
      local cost, _, _, actions = RecipeCost(ctx, rc.r, crafts, {})
      ctx.skill = nil
      if cost then
        -- Puntos de los materiales que se fabrican por el camino: con ellos, cada
        -- punto de la ruta cuesta 1/(1 + g) de lo que costaría sin ellos
        local g = CraftBonus(ctx, actions, s)
        -- Lo fabricado que la ruta necesita después (Light Leather, Handful of
        -- Copper Bolts) vale lo que costaría conseguirlo, no lo del vendedor
        -- (ctx.needValue, ver PlanGPS). Como al elegir punto a punto (ver Plan):
        -- el beneficio no crece con las fabricaciones de una receta casi gris
        local value = SaleValue(rc.sale, crafts)
        local need = rc.sale and ctx.needValue and ctx.needValue[rc.sale.itemID]
        if need then value = math.max(value, crafts * rc.sale.qty * need) end
        local net = cost - value
        if net < 0 and crafts > PROFIT_FULL_CRAFTS then
          net = net * PROFIT_FULL_CRAFTS / crafts + CRAFT_COST * (crafts - PROFIT_FULL_CRAFTS)
        end
        -- En verde, algo de mala suerte (como en Plan: Planner.GreenRisk)
        local risk = Planner.GreenRisk(rc.r.t, s, chance, ctx.opts)
        if risk > 0 then net, crafts = net + cost / crafts * risk, crafts + risk end
        v = { net / (1 + g), crafts / (1 + g) }
      end
    end
    row[s] = v
  end
  return v
end

-- Recetas candidatas del GPS con este contexto (las mismas para todas sus variantes)
local function GPSRecipes(data, opts, ctx)
  if not ctx.gpsRecipes then
    local list = {}
    for id, r in pairs(data.recipes) do
      local learn = Planner.LearnSkill(r, opts)
      if learn and learn < opts.to and r.t[4] > opts.from and not (opts.excluded and opts.excluded[id]) then
        -- Empezarla paga el instructor y, si pide una herramienta que no tienes
        -- (Arclight Spanner para Crude Scope), la herramienta. Sin precio: no vale
        local fee = Planner.LearnCost(ctx, r)
        for _, tool in ipairs(Planner.RecipeTools(r)) do
          if fee and (ctx.toolMask[tool.family or "rod"] or 0) < tool.mask then
            local cost = Acquire(ctx, tool.item, 1, 0, {}, {}, {})
            fee = cost and fee + cost or nil
          end
        end
        if fee then
          list[#list + 1] = { id = id, r = r, learn = learn, fee = fee, sale = Planner.SaleInfo(ctx, r),
            cd = Planner.Cooldown(r, id) }
        end
      end
    end
    table.sort(list, function(a, b) return a.id < b.id end) -- mismo orden siempre: misma ruta
    ctx.gpsRecipes, ctx.gpsCost = list, {}
  end
  return ctx.gpsRecipes
end

local function ShortestRoute(data, opts, ctx, weight, skip, fixed, paid)
  local recipes = GPSRecipes(data, opts, ctx)
  local nRecipes = #recipes -- (lista seguida, sin huecos: ver GPSRecipes)
  local INF = math.huge
  local prev, spare = {}, {} -- (spare: la fila de hace dos niveles, que se reescribe entera)
  for i = 1, #recipes do prev[i] = INF end
  local bestAll, bestIdx = 0, nil -- al empezar: nada pagado, ninguna receta
  -- (y la segunda mejor, de otra receta: una con enfriamiento no sigue a sí misma)
  local best2All, best2Idx = INF, nil
  local back, last = {}, nil
  for s = opts.from, opts.to - 1 do
    local cur, b = spare, {}
    local fs = fixed and fixed[s]
    local newBest, newIdx, newBest2, newIdx2 = INF, nil, INF, nil
    for i = 1, nRecipes do
      local rc = recipes[i]
      ES.Yield()
      local c = INF
      local allowed = not skip[rc.id] and (not fs or fs == rc.id)
      -- Con enfriamiento (ver Planner.Cooldown): un solo punto, en naranja
      if allowed and rc.cd and Planner.Chance(rc.r.t, s) < 1 then allowed = false end
      if allowed and rc.learn <= s and (prev[i] < INF or bestIdx or s == opts.from) then
        local pc = PointCost(ctx, rc, s)
        if pc then
          -- (con "Menos fabricaciones", lo que tarda cada una de esta receta: RecipeWeight)
          local point = pc[1] + (weight > 0 and opts.craftWeight and RecipeWeight(opts, rc.id) or weight) * pc[2]
          local base, baseIdx = bestAll, bestIdx
          if rc.cd and bestIdx == i then base, baseIdx = best2All, best2Idx end
          -- (paid: recetas que la ruta ya aprende en otro tramo: no se pagan otra vez)
          local switch = base + (paid and paid[rc.id] and 0 or rc.fee) + GPS_STEP_COST
          if not rc.cd and prev[i] <= switch then
            c, b[i] = prev[i] + point, i
          elseif switch < INF then
            c, b[i] = switch + point, baseIdx
          end
        end
      end
      cur[i] = c
      if c < newBest then
        newBest2, newIdx2 = newBest, newIdx
        newBest, newIdx = c, i
      elseif c < newBest2 then
        newBest2, newIdx2 = c, i
      end
    end
    if not newIdx then break end -- ninguna receta sigue: la ruta llega hasta aquí
    back[s], last = b, s
    spare = prev
    prev, bestAll, bestIdx, best2All, best2Idx = cur, newBest, newIdx, newBest2, newIdx2
  end
  if not last then return nil end
  local choice, i = {}, bestIdx
  for s = last, opts.from, -1 do
    if not i then break end
    choice[s] = recipes[i].id
    i = back[s][i]
  end
  return choice
end
Planner.ShortestRoute, Planner.NewContext = ShortestRoute, NewContext -- (para pruebas)

-- Clave de una ruta (para no recorrer dos veces la misma)
local function ChoiceKey(opts, choice, via)
  local keys = {}
  for s = opts.from, opts.to - 1 do keys[#keys + 1] = tostring(choice[s]) end
  local v = {}
  for itemID, way in pairs(via or {}) do v[#v + 1] = itemID .. way end
  table.sort(v)
  return table.concat(keys, ",") .. "|" .. table.concat(v, ",")
end

-- Lo que el GPS decidió fabricar o comprar al calcular un camino (cada material,
-- lo más barato en ese momento): para recorrerlo igual. Si no, se recorre con lo
-- que decida la pasada forzada y una ruta buena puede parecer mala (Deadly
-- Blunderbuss comprando los Handful of Copper Bolts en vez de fabricarlos)
local function RouteVia(data, opts, ctx, choice)
  -- Fabricaciones de cada receta en todo el camino: con poca cantidad comprar
  -- suele salir más barato, y lo que cuenta es lo que pide el tramo entero
  local crafts, order = {}, {}
  for s = opts.from, opts.to - 1 do
    local id = choice[s]
    local chance = id and Planner.Chance(data.recipes[id].t, s) or 0
    if chance > 0 then
      if not crafts[id] then order[#order + 1] = id end
      crafts[id] = (crafts[id] or 0) + 1 / chance
    end
  end
  local via = {}
  for _, id in ipairs(order) do
    local _, _, _, actions = RecipeCost(ctx, data.recipes[id], crafts[id], {})
    for _, a in ipairs(actions or {}) do
      if ctx.producers[a.item] and not via[a.item] then
        if a.kind == "craft" then via[a.item] = "craft"
        elseif a.kind == "ah" or a.kind == "vendor" then via[a.item] = "buy" end
      end
    end
  end
  for itemID, way in pairs(ctx.opts.via or {}) do via[itemID] = way end
  return via
end

-- Lo que vale fabricar al subir un material que la ruta `best` necesita (lo compra
-- o lo fabrica aparte): lo que costaría conseguirlo, lo más barato de comprarlo o
-- fabricarlo. Para el GPS (ver PointCost): subir con Light Leather no "regala" el
-- cuero al vendedor, ahorra comprarlo para los pasos de después
local function NeedValue(ctx, best)
  local v = {}
  local function Add(itemID, paid)
    if not ctx.producers[itemID] or v[itemID] then return end
    local ladder = ctx.ladders[itemID]
    local buy = paid or ES.Data.VendorPrices[itemID] or (ladder and ladder[1])
    local craft = Planner.CraftUnitCost(ctx, itemID)
    v[itemID] = (buy and craft) and math.min(buy, craft) or buy or craft
  end
  for _, it in ipairs(best.shopping or {}) do Add(it.itemID, it.unit) end
  for _, c in ipairs(best.crafted or {}) do Add(c.itemID) end
  return v
end

-- Precios con tus bolsas para el GPS: lo tuyo, al precio de la puntuación (lo que
-- te darían vendiéndolo, con el margen a favor de usarlo): ni gratis ni infinito
local function OwnedContext(data, opts, via)
  local w = Copy(opts)
  w.via = via
  local ctx = NewContext(data, w)
  ctx.ownedPrice = {}
  for itemID, q in pairs(ctx.owned) do
    ctx.ownedPrice[itemID] = (1 - BAGS_TIE_PCT) * Planner.OwnedValue(ctx, itemID, q) / q
  end
  return ctx
end

function Planner.PlanGPS(data, opts)
  -- Lo que no cambia en todo el cálculo (escaleras de precios, quién fabrica qué),
  -- preparado una vez para los cientos de recorridos (ver NewContext)
  opts = Copy(opts)
  local CW = CraftWeight(opts)
  local tpl = NewContext(data, opts)
  opts.shared = { prices = tpl.prices, to = opts.to, ladders = tpl.ladders, supply = tpl.supply,
    medians = tpl.medians, producers = tpl.producers, foreign = tpl.foreign, foreignProf = tpl.foreignProf }
  local RouteScore, scoreMemo = Planner.RouteScore, {}
  local function Score(p) return RouteScore(p, scoreMemo) end
  local best, seen, pool = nil, {}, {}
  -- Recorridos hechos; con `capped`, pasado GPS_MAX_WALKS no se recorre nada nuevo
  local walks, capped = 0, true
  local function Better(p)
    return not best or p.reached > best.reached or (p.reached == best.reached and Score(p) < Score(best) - EPS)
  end
  -- Recorre una ruta de verdad (pasada forzada, rápida). via: fabricar o comprar
  -- fijado (lo del jugador siempre manda)
  local function Walk(choice, via, depth)
    -- (también aquí: cientos de rutas ya recorridas seguidas salen sin pasar por Plan, que
    -- es donde se cede el fotograma, y el juego se paraba hasta 0,2 s)
    ES.Yield()
    local v = Copy(via or {})
    for itemID, way in pairs(opts.via or {}) do v[itemID] = way end
    local key = ChoiceKey(opts, choice, v)
    -- (ya recorrida: nil, salvo al alargar un paso, que quiere la ruta de verdad)
    if seen[key] then return depth and seen[key] or nil end
    if capped and walks >= Planner.GPS_MAX_WALKS then return nil end
    walks = walks + 1
    local t = Copy(opts)
    t.forced, t.via = choice, v
    -- (gpsWalk: sin completar la lista de la compra a fabricaciones enteras, que solo
    -- cambia cantidades y totales, y sin lo que pide cada nivel (pointNeed, pointUse): de
    -- estas rutas solo se lee itemID y unit de la compra (NeedValue), y nada de lo de cada
    -- nivel salvo pointChance (ni pointNet). La que se devuelve se recorre otra vez al final, completa)
    t.gpsWalk = true
    local p = Planner:Plan(data, t)
    seen[key] = p
    -- Lo que un paso fabrica de más para los siguientes (ver Acquire) también sube
    -- puntos: el paso se alarga con ellos y el siguiente empieza más tarde. Es la
    -- misma ruta contada como de verdad se hace (fabricas 60 pólvoras y llegas a 30)
    if (depth or 0) < GPS_AHEAD_ROUNDS then
      local moved
      for i, st in ipairs(p.steps) do
        if (st.aheadGain or 0) >= 1 and p.steps[i + 1] then
          moved = moved or Copy(p.choice)
          for s = st.to, math.min(st.to + st.aheadGain, opts.to) - 1 do moved[s] = st.id end
        end
      end
      if moved then
        local q = Walk(moved, via, (depth or 0) + 1)
        if q then seen[key] = q return q end
      end
    end
    -- Las mejores rutas vistas (la mejor recorrida de cada una), para repasarlas al final
    local rk = ChoiceKey(opts, p.choice)
    local q = pool[rk]
    if not q or p.reached > q.reached or (p.reached == q.reached and Score(p) < Score(q)) then pool[rk] = p end
    return p
  end
  -- Cambiar cada material (fabricar ↔ comprar) mientras mejore
  local function ViaPolish(p)
    for _ = 1, GPS_VIA_ROUNDS do
      local improved = false
      local items = {}
      for itemID in pairs(p.ctx and p.ctx.via or {}) do
        if not (opts.via and opts.via[itemID]) then items[#items + 1] = itemID end
      end
      table.sort(items)
      for _, itemID in ipairs(items) do
        local v = Copy(p.ctx.via)
        v[itemID] = v[itemID] == "craft" and "buy" or "craft"
        local q = Walk(p.choice, v)
        if q and (q.reached > p.reached or (q.reached == p.reached and Score(q) < Score(p) - EPS)) then
          p, improved = q, true
        end
      end
      if not improved then break end
    end
    return p
  end
  -- Recorrida y, si está cerca de la mejor, con fabricar ↔ comprar (en una ruta que
  -- sale mucho más cara no la salva, y es lo que más recorridos cuesta)
  local function Try(choice, via)
    local p = Walk(choice, via)
    if not p then return false end
    local near = not best or p.reached > best.reached
      or Score(p) <= Score(best) + GPS_NEAR_PCT * math.abs(Score(best)) + GPS_NEAR_MIN
    if near then p = ViaPolish(p) end
    if Better(p) then best = p return true end
    return false
  end
  -- Un camino del GPS: recorrido con lo que el GPS decidió fabricar o comprar, con
  -- lo de su contexto y (extra) con otro; gana el mejor
  local function TryDP(choice, ctx, extra)
    local a = Try(choice, RouteVia(data, opts, ctx, choice))
    local b = Try(choice, ctx.opts.via)
    local c = extra and Try(choice, extra)
    return a or b or c or false
  end
  -- Puntos de partida: la ruta voraz de una sola pasada (sin restricciones) y,
  -- con bolsas, la voraz del mercado (sin ellas) recorrida con lo tuyo
  Try({}, nil)
  -- La ruta que ya tenías (opts.hint, la última calculada de esta profesión): si
  -- cambian tus bolsas (conviertes chatarras en cuero), sigue siendo la misma salvo
  -- que de verdad haya otra mejor. Sin esto la ruta podía saltar a otra solo porque
  -- la búsqueda tomó otro camino
  if opts.hint and opts.hint.choice then Try(opts.hint.choice, opts.hint.via) end
  do -- (y la voraz con peso por fabricación: de ella sale a menudo la de siempre)
    local t = Copy(opts)
    t.forced, t.craftCost = {}, CW
    Try(Planner:Plan(data, t).choice, nil)
  end
  local owned = opts.owned and next(opts.owned)
  local marketGreedy
  if owned then
    local t = Copy(opts)
    t.owned, t.forced = nil, {}
    marketGreedy = Planner:Plan(data, t)
    Try(marketGreedy.choice, nil)
  end
  for round = 1, GPS_ROUNDS do
    local improved = false
    -- Contextos de precios: los del mercado (primera unidad) la primera vez; luego
    -- los que pagaría la mejor ruta (la mitad de lo que compra ya "comprada") y con
    -- lo que ella decidió fabricar o comprar. Con tus bolsas, también contándolas
    local ctxs = {}
    local m = Copy(opts)
    m.owned = nil
    if best and round > 1 then m.via = Copy(best.ctx.via) end
    ctxs[1] = NewContext(data, m)
    if owned then
      -- Lo tuyo, al precio de la puntuación (ver OwnedContext). A partir de la
      -- segunda vuelta, menos la mitad de lo que ya usa la mejor ruta
      local ctx = OwnedContext(data, opts, m.via)
      if best and round > 1 then
        for _, o in ipairs(best.owned or {}) do
          if ctx.owned[o.itemID] then ctx.owned[o.itemID] = math.max(0, ctx.owned[o.itemID] - o.quantity / 2) end
        end
      end
      ctxs[2] = ctx
    end
    if best and round > 1 then
      -- Lo fabricado que la ruta necesita, valorado a lo que costaría (NeedValue)
      -- y también sin eso, al precio del vendedor: cada vara ve bien unas rutas
      -- (subir con Light Leather o con Light Armor Kit) y mal otras
      local plain = NewContext(data, m)
      for _, ctx in ipairs(ctxs) do ctx.needValue = NeedValue(ctx, best) end
      ctxs[#ctxs + 1] = plain
      for _, ctx in ipairs(ctxs) do
        for itemID, q in pairs(best.ctx.used or {}) do ctx.used[itemID] = q / 2 end
      end
    end
    -- Caminos: el más corto, y sin cada receta de la mejor ruta hasta ahora
    local skips = { {} }
    for _, st in ipairs(best and best.steps or {}) do skips[#skips + 1] = { [st.id] = true } end
    for _, ctx in ipairs(ctxs) do
      for i, skip in ipairs(skips) do
        for _, weight in ipairs(i == 1 and { CW, 0 } or { CW }) do
          local choice = ShortestRoute(data, opts, ctx, weight, skip)
          if choice and TryDP(choice, ctx) then improved = true end
        end
      end
    end
    -- Y fabricando lo que la mejor ruta compra si su receta sube puntos (la pólvora de
    -- la dinamita): entonces el camino lleva esa receta como paso propio (lo que da
    -- puntos no se fabrica como preparación, ver Acquire). Sin esto el GPS no veía
    -- "Rough Blasting Powder 1-33 y luego dinamita", que el planificador antiguo sí
    if best then
      local flip = Copy(best.ctx.via or {})
      local any = false
      for itemID, way in pairs(best.ctx.via or {}) do
        if way == "buy" then
          for _, rid in ipairs(tpl.producers[itemID] or {}) do
            local r = data.recipes[rid]
            if r and not r.intermediate and not r.conversion then flip[itemID], any = "craft", true end
          end
        end
      end
      if any then
        local f = Copy(m)
        f.via = flip
        -- (sin tus bolsas y, si las usas, con ellas: la pólvora de tus Rough Stone)
        local fctxs = { NewContext(data, f) }
        if owned then fctxs[2] = OwnedContext(data, opts, flip) end
        for _, ctx in ipairs(fctxs) do
          for _, weight in ipairs({ CW, 0 }) do
            local choice = ShortestRoute(data, opts, ctx, weight, {})
            if choice and TryDP(choice, ctx, flip) then improved = true end
          end
        end
      end
    end
    if not improved and round > 1 then break end
  end
  if not best then return Planner:Plan(data, (function() local t = Copy(opts) t.forced = {} return t end)()) end

  -- Fases de pulido sobre la mejor ruta
  local function Polish()
    -- Recetas que puedes hacer con lo tuyo (como el aviso "Con lo que llevas"): el
    -- camino que la usa en su tramo. El GPS solo no las ve si lo que fabricas se
    -- reutiliza luego (Cured Medium Hide con tus Medium Hide, para Hillman's Shoulders)
    if owned then
      local m = Copy(opts)
      m.owned = nil
      local ctxs = { NewContext(data, m), OwnedContext(data, opts), OwnedContext(data, opts) }
      -- (y lo tuyo descontando la mitad de lo que ya gasta la mejor ruta: con 50
      -- Light Leather, Light Leather Pants parece gratis hasta que se acaba)
      for _, o in ipairs(best.owned or {}) do
        local have = ctxs[3].owned[o.itemID]
        if have then ctxs[3].owned[o.itemID] = math.max(0, have - o.quantity / 2) end
      end
      for itemID, q in pairs(best.ctx.used or {}) do ctxs[3].used[itemID] = q / 2 end
      -- Frente a la mejor ruta (con lo que ella no gasta) y frente a la del mercado
      -- (con todo lo tuyo): sin repetir receta
      local alts, tried = {}, {}
      for _, base in ipairs({ best, marketGreedy }) do
        local ex = Copy(opts.excluded or {})
        for _ = 1, GPS_BAGS_ALTS do
          local alt = Planner.BagsAlternative(data, base, opts.owned, opts.from, ex, false)
          if not alt then break end
          ex[alt.id] = true
          if not tried[alt.id .. ":" .. alt.to] then
            tried[alt.id .. ":" .. alt.to] = true
            alts[#alts + 1] = alt
          end
        end
      end
      for _, alt in ipairs(alts) do
        -- Su tramo, y hasta donde se podría usar (lo tuyo da para más si la ruta
        -- no lo gasta en otra cosa)
        local spans, last = {}, math.max(alt.to, math.min(opts.to, alt.recipe.t[3]))
      for _, f in ipairs({ 0.5, 0.75, 1 }) do spans[#spans + 1] = math.max(alt.from + 1, math.floor(alt.from + f * (alt.to - alt.from) + 0.5)) end
      if last > alt.to then spans[#spans + 1] = last end
      for _, span in ipairs(spans) do
          local fixed = {}
          for s = alt.from, span - 1 do fixed[s] = alt.id end
          for _, ctx in ipairs(ctxs) do
            local choice = ShortestRoute(data, opts, ctx, CW, {}, fixed)
            if choice then TryDP(choice, ctx) end
          end
        end
      end
    end

    -- Repensar cada tramo (un paso, o dos seguidos) con el GPS dejando el resto de la
    -- ruta como está, con los precios que paga la mejor ruta: mete una receta en
    -- medio de un paso largo (Deadly Blunderbuss dentro de Flying Tiger Goggles)
    for _ = 1, GPS_SEGMENT_ROUNDS do
      local improved = false
      local m = Copy(opts)
      m.owned, m.via = nil, Copy(best.ctx.via)
      local ctxs = { NewContext(data, m) }
      if owned then ctxs[2] = OwnedContext(data, opts, m.via) end
      for _, ctx in ipairs(ctxs) do
        for itemID, q in pairs(best.ctx.used or {}) do ctx.used[itemID] = q / 2 end
        ctx.needValue = NeedValue(ctx, best)
      end
      local steps, windows = best.steps, {}
      for i, st in ipairs(steps) do
        windows[#windows + 1] = { st.from, st.to }
        if steps[i + 1] then windows[#windows + 1] = { st.from, steps[i + 1].to } end
        -- Y el principio o el final de un paso largo (cuando la receta ya sube peor:
        -- Bronze Framework en los últimos niveles de Flying Tiger Goggles)
        for _, k in ipairs({ 5, 10 }) do
          if st.to - st.from > k then
            windows[#windows + 1] = { st.to - k, st.to }
            windows[#windows + 1] = { st.from, st.from + k }
          end
        end
      end
      for _, w in ipairs(windows) do
        local fixed, paid = {}, {}
        for s = opts.from, opts.to - 1 do
          if (s < w[1] or s >= w[2]) and best.choice[s] then
            fixed[s] = best.choice[s]
            paid[best.choice[s]] = true
          end
        end
        for _, ctx in ipairs(ctxs) do
          local choice = ShortestRoute(data, opts, ctx, CW, {}, fixed, paid)
          if choice and TryDP(choice, ctx, best.ctx.via) then improved = true end
        end
      end
      if not improved then break end
    end

    -- Cambiar la receta de un paso por otra en el mismo tramo (Raptor Hide Harness por
    -- Raptor Hide Belt, Rough Weightstone por Rough Sharpening Stone): las
    -- GPS_SUB_CANDIDATES que mejor lo cubren según el GPS, recorridas de verdad
    for _ = 1, GPS_SUB_ROUNDS do
      local improved = false
      local m = Copy(opts)
      m.owned, m.via = nil, Copy(best.ctx.via)
      local ctxs = { NewContext(data, m), NewContext(data, m) }
      ctxs[1].needValue = NeedValue(ctxs[1], best)
      for _, ctx in ipairs(ctxs) do
        for itemID, q in pairs(best.ctx.used or {}) do ctx.used[itemID] = q / 2 end
      end
      local paid = {}
      for _, st in ipairs(best.steps) do paid[st.id] = true end
      for _, st in ipairs(best.steps) do
        local tried = {}
        for _, ctx in ipairs(ctxs) do
          local cands = {}
          for _, rc in ipairs(GPSRecipes(data, opts, ctx)) do
            -- (desde que se aprende, si es a mitad del paso)
            local from = math.max(st.from, rc.learn)
            if rc.id ~= st.id and not tried[rc.id] and from < st.to then
              local sum = paid[rc.id] and 0 or rc.fee
              for s = from, st.to - 1 do
                local pc = PointCost(ctx, rc, s)
                if not pc then sum = nil break end
                sum = sum + pc[1] + RecipeWeight(opts, rc.id) * pc[2]
              end
              -- (por punto: los tramos cortos no salen baratos solo por ser cortos)
              if sum then cands[#cands + 1] = { id = rc.id, from = from, cost = sum / (st.to - from) } end
            end
          end
          table.sort(cands, function(a, b) return a.cost < b.cost or (a.cost == b.cost and a.id < b.id) end)
          for k = 1, math.min(GPS_SUB_CANDIDATES, #cands) do
            tried[cands[k].id] = true
            local choice = Copy(best.choice)
            for s = cands[k].from, st.to - 1 do choice[s] = cands[k].id end
            local p = Walk(choice, best.ctx.via)
            if p and Better(p) then best, improved = p, true break end
          end
          if improved then break end
        end
        if improved then break end
      end
      if not improved then break end
    end

    -- Ajuste fino, recorriendo de verdad: mover cada frontera entre pasos unos
    -- niveles, o quitar un paso dándoselo a la receta de antes o a la de después
    local tuneWalks = 0
    for _ = 1, GPS_TUNE_MOVES do
      local improved = false
      local steps = best.steps
      for i = 1, #steps do
        local st, prevSt, nextSt = steps[i], steps[i - 1], steps[i + 1]
        local moves = {}
        if nextSt then
          for _, d in ipairs({ -3, -1, 1, 3 }) do
            local cut = nextSt.from + d
            if cut > st.from and cut < nextSt.to then moves[#moves + 1] = { cut = cut, a = st, b = nextSt } end
          end
        end
        if prevSt then moves[#moves + 1] = { whole = st, to = prevSt.id } end
        if nextSt then moves[#moves + 1] = { whole = st, to = nextSt.id } end
        -- Los últimos niveles del paso, con una receta ya aprendida antes (no se
        -- vuelve a pagar: Flying Tiger Goggles al final de Deadly Blunderbuss)
        local earlier = {}
        for j = math.max(1, i - 3), i - 1 do
          if not earlier[steps[j].id] and steps[j].id ~= st.id then
            earlier[steps[j].id] = true
            for _, k in ipairs({ 2, 4, 8 }) do
              if st.to - st.from > k then moves[#moves + 1] = { tail = st, k = k, to = steps[j].id } end
            end
          end
        end
        for _, mv in ipairs(moves) do
          local choice = Copy(best.choice)
          if mv.whole then
            for s = mv.whole.from, mv.whole.to - 1 do choice[s] = mv.to end
          elseif mv.tail then
            for s = mv.tail.to - mv.k, mv.tail.to - 1 do choice[s] = mv.to end
          elseif mv.cut < mv.b.from then
            for s = mv.cut, mv.b.from - 1 do choice[s] = mv.b.id end
          else
            for s = mv.b.from, mv.cut - 1 do choice[s] = mv.a.id end
          end
          local p = Walk(choice, best.ctx.via)
          if p then tuneWalks = tuneWalks + 1 end
          if p and Better(p) then
            best, improved = p, true
            break
          end
          if tuneWalks >= GPS_TUNE_WALKS then break end
        end
        if improved or tuneWalks >= GPS_TUNE_WALKS then break end
      end
      if not improved then break end
    end
  end
  Polish()

  -- Al final, las mejores rutas vistas, con fabricar ↔ comprar sin poda: una ruta
  -- buena recorrida con una mala decisión pudo quedar por detrás de otra peor
  local top = {}
  for _, p in pairs(pool) do top[#top + 1] = p end
  -- (primero las que llegan más lejos: una que se para antes sale barata por subir menos)
  -- (la puntuación de cada una se calcula la primera vez que la pide la ordenación y se
  -- reutiliza: antes eran dos por comparación, ~40.000 con lo de tus bolsas, y una
  -- ordenación no puede ceder el fotograma: el juego se paraba casi medio segundo)
  local topScore = {}
  local function TopScore(p)
    local s = topScore[p]
    if s == nil then s = Score(p) topScore[p] = s end
    return s
  end
  table.sort(top, function(a, b) return a.reached > b.reached or (a.reached == b.reached and TopScore(a) < TopScore(b)) end)
  local again = false
  for k = 1, math.min(GPS_TOP, #top) do
    local p = ViaPolish(top[k])
    if Better(p) then best, again = p, true end
  end
  if again then Polish() end

  -- Hacer tú un ingrediente que un paso compra, como paso propio al empezar ese paso,
  -- si su receta aún da puntos: la pólvora de la Rough Dynamite con tus Rough Stone
  -- (pólvora 3-25 y luego dinamita, 19s más barata). Los caminos del GPS no la veían:
  -- se prueba directamente, cortando donde la receta cambia de color
  local function IngredientFirst()
    local found = false
    for _, st in ipairs(best.steps) do
      local tried = {}
      for _, rg in ipairs(st.reagents or {}) do
        if rg.kinds and (rg.kinds.ah or rg.kinds.vendor) then
          for _, rid in ipairs(tpl.producers[rg.item] or {}) do
            local r = data.recipes[rid]
            local learn = r and Planner.LearnSkill(r, opts)
            if r and not tried[rid] and not r.intermediate and not r.conversion and learn and learn <= st.from
              and Planner.Chance(r.t, st.from) > 0 then
              tried[rid] = true
              local cuts = {}
              for _, c in ipairs({ r.t[2], r.t[3], math.floor((r.t[3] + r.t[4]) / 2), r.t[4] }) do
                local to = math.min(c, st.to)
                if to > st.from and not cuts[to] then
                  cuts[to] = true
                  local choice = Copy(best.choice)
                  for s = st.from, to - 1 do choice[s] = rid end
                  -- (comprándolo como hasta ahora, y fabricándolo: lo que pida el
                  -- paso después se hace de más en este, ver Acquire)
                  local v = Copy(best.ctx.via)
                  v[rg.item] = "craft"
                  if Try(choice, best.ctx.via) then found = true end
                  if Try(choice, v) then found = true end
                end
              end
            end
          end
        end
      end
    end
    return found
  end
  if IngredientFirst() then Polish() end
  -- (lo que sigue son arreglos para que la ruta se pueda seguir: pocos recorridos, sin tope)
  capped = false

  -- Aprender una receta para unas pocas fabricaciones, solo si compensa: ir al
  -- instructor por 1-5 fabricaciones que ahorran 2s no merece la pena (CurseForge:
  -- "me manda aprender otra receta para 1 fabricación por ser más barato"). Esos
  -- puntos se prueban con la receta de al lado (la anterior o la siguiente) y se
  -- queda si cuesta como mucho LEARN_WORTH más; si ahorra más, aprenderla sí compensa
  for _ = 1, 4 do
    local changed = false
    local steps = best.steps
    for i, b in ipairs(steps) do
      local learns = b.learnSource ~= nil and b.learnSource ~= "known"
      if learns and (b.crafts or 0) <= LEARN_FEW_CRAFTS then
        local cand
        for _, nb in ipairs({ steps[i - 1], steps[i + 1] }) do
          if nb and nb.id ~= b.id then
            local choice = Copy(best.choice)
            for s = b.from, b.to - 1 do choice[s] = nb.id end
            -- (depth 0: si ese camino ya se recorrió, Walk lo devuelve; sin él, nil)
            local q = Walk(choice, best.ctx.via, 0)
            if q and q.reached >= best.reached and not q.unfollowable and Score(q) <= Score(best) + LEARN_WORTH
              and (not cand or Score(q) < Score(cand)) then
              cand = q
            end
          end
        end
        if cand then best, changed = cand, true break end
      end
    end
    if not changed then break end
  end

  -- Sin saltos: una receta unos pocos puntos en medio de otra (A, B 3 puntos, A otra
  -- vez: Bolt of Runecloth 210-215 dentro de Red Mageweave Headband) no tiene sentido
  -- para el jugador. Se prueba sin el salto (esos puntos, con A) y se queda si apenas
  -- cuesta más (ZIGZAG_MIN o ZIGZAG_PCT)
  for _ = 1, 4 do
    local changed = false
    local steps = best.steps
    for i = 2, #steps - 1 do
      local a, b, c = steps[i - 1], steps[i], steps[i + 1]
      if a.id == c.id and b.to - b.from <= ZIGZAG_STEPS then
        local choice = Copy(best.choice)
        for s = b.from, b.to - 1 do choice[s] = a.id end
        -- (depth 0: la ruta sin el salto casi siempre ya se recorrió en la búsqueda, y
        -- sin él Walk daba nil: el salto se quedaba. Alquimia 14-15: "Elixir de
        -- defensa menor" x1 entre dos tramos de "Elixir de fuerza menor")
        local q = Walk(choice, best.ctx.via, 0)
        local allowed = math.max(ZIGZAG_MIN, ZIGZAG_PCT * math.abs(Score(best)))
        if q and q.reached >= best.reached and not q.unfollowable and Score(q) <= Score(best) + allowed then
          best, changed = q, true
          break
        end
      end
    end
    if not changed then break end
  end

  -- La elegida, recorrida una vez con toda la información (las recetas que no se
  -- pudieron usar por falta de precio, para el tooltip de cada paso): mismo resultado
  local final = Copy(opts)
  final.forced, final.via, final.fullInfo = best.choice, best.ctx.via, true
  best = Planner:Plan(data, final)

  return best
end

---------------------------------------------------------------------------
-- Plan
---------------------------------------------------------------------------
-- opts = { from, to, includeScrolls, hours (duración subasta), neutral, reuseCrafted, ignoreSupply, cap,
--          owned = { [itemID] = cantidad en bolsas/banco }, via = { [itemID] = "craft" | "buy" } }
Planner.passes = 0 -- veces que se recorre una ruta (para la barra de progreso, ES:PlanProgress)
function Planner:Plan(data, opts)
  Planner.passes = Planner.passes + 1
  -- El planificador es el GPS (ver arriba). Lo de aquí abajo son las pasadas forzadas
  -- (ruta fijada, las que recorre el GPS) y el planificador antiguo, que solo se usa
  -- para compararlo en tools/route_qa.py (Planner.USE_GPS = false)
  if Planner.USE_GPS and not opts.forced then return Planner.PlanGPS(data, opts) end

  -- Materiales que se pueden fabricar (Light Leather de Ruined Leather Scraps): o se
  -- fabrican todos o se compran todos, nunca las dos cosas (ver Acquire). La primera
  -- vez decide con poca cantidad, así que se prueba la otra opción para todo el plan
  -- y se queda la más barata, contando INTERMEDIATE_CRAFT_COST por cada fabricación
  if not opts.forced and not opts.viaSearched then
    local o = Copy(opts)
    o.viaSearched = true
    local function Score(p)
      local n = 0
      for _, c in ipairs(p.crafted or {}) do n = n + c.quantity end
      return p.net + INTERMEDIATE_CRAFT_COST * n
    end
    local function Better(p, best)
      return p.reached > best.reached or (p.reached == best.reached and Score(p) < Score(best) - EPS)
    end
    local best = Planner:Plan(data, o)
    -- Cambiar un material cada vez (fabricar ↔ comprar), otra vuelta si alguno mejora.
    -- No solo los de la ruta actual: también los que salieron en otras rutas probadas
    -- (la ruta con Cured Medium Hide no usa Cured Light Hide, pero comprarlo hecho
    -- abre la de Black Whelp Cloak)
    local seen, tried = {}, {}
    local function See(p)
      for itemID in pairs(p.ctx and p.ctx.via or {}) do seen[itemID] = true end
    end
    See(best)
    -- Lo decidido sobre la marcha, fijado desde el principio: la ruta se elige ya
    -- sabiendo que Light Leather se fabrica. Con chatarras en las bolsas, la primera
    -- pasada lo decidía tarde, se quedaba con una ruta pensada para comprarlo y la
    -- ruta saltaba al ir convirtiéndolas (tener más cosas daba una ruta peor)
    if best.ctx and next(best.ctx.via) then
      local t = Copy(o)
      t.via = Copy(best.ctx.via)
      local p = Planner:Plan(data, t)
      if Better(p, best) then best = p end
      See(p)
    end
    for _ = 1, VIA_ROUNDS do
      local improved = false
      local items = {}
      for itemID in pairs(seen) do items[#items + 1] = itemID end
      table.sort(items) -- orden fijo: la misma ruta cada vez
      for _, itemID in ipairs(items) do
        local cur = best.ctx and best.ctx.via or {}
        -- Lo que el jugador fijó (✕ en "Fabrica 30× Light Leather": comprarlo) no se toca
        if not (opts.via and opts.via[itemID]) then
          for _, way in ipairs({ "craft", "buy" }) do
            local key = itemID .. way .. tostring(best)
            if cur[itemID] ~= way and not tried[key] then
              tried[key] = true
              local t = Copy(o)
              t.via = Copy(cur)
              t.via[itemID] = way
              local p = Planner:Plan(data, t)
              if Better(p, best) then best, improved = p, true end
              See(p)
              if improved then break end
            end
          end
        end
      end
      if not improved then break end
    end
    return best
  end

  -- Sin zigzag: donde la ruta alterna recetas en pasos de 1-2 puntos (Light Leather
  -- y Light Armor Kit, punto sí punto no), se prueba a hacer todo el tramo con una
  -- sola y se queda si apenas cuesta más (ver Smooth)
  if not opts.forced and not opts.smoothed then
    local o = {}
    for k, v in pairs(opts) do o[k] = v end
    o.smoothed = true
    return Planner.Smooth(data, o, Planner:Plan(data, o))
  end

  -- Con "usar bolsas y banco": la ruta se elige sin contar lo tuyo (ver abajo), así
  -- que una receta de pergamino puede ganar aunque la alternativa use materiales que
  -- ya llevas y salga más barata de verdad (Deviate Scale Cloak frente a Embossed
  -- Leather Gloves con cuero en las bolsas). Al acabar se prueba a quitar las
  -- recetas que hay que ir a buscar o comprar, de la más cara a la más barata, y se
  -- queda la ruta si sale más barata con su coste real (bolsas incluidas) y llega
  -- igual de lejos: se comparan rutas enteras, sin el zigzag de elegir punto a punto.
  -- Sin bolsas no se hace: la ruta ya es la del mercado y calcularla cuesta el doble.
  if not opts.forced and not opts.searched and opts.owned and next(opts.owned) then
    local o = {}
    for k, v in pairs(opts) do o[k] = v end
    o.searched = true
    local best = Planner:Plan(data, o)
    local candidates = {}
    for _, st in ipairs(best.steps) do
      if st.fee > 0 and SEARCH_SOURCES[st.learnSource] then candidates[#candidates + 1] = st end
    end
    table.sort(candidates, function(a, b) return a.fee > b.fee end)
    for i = 1, math.min(#candidates, MAX_SEARCH) do
      local t = {}
      for k, v in pairs(o) do t[k] = v end
      t.excluded = {}
      for id in pairs(o.excluded or {}) do t.excluded[id] = true end
      t.excluded[candidates[i].id] = true
      t.craftCost = best.craftCostUsed -- sin repetir la doble ruta (más barata / menos fabricaciones)
      local plan = Planner:Plan(data, t)
      if plan.reached >= best.reached and plan.net < best.net - SEARCH_MIN_SAVING then
        best, o = plan, t
      end
    end
    -- Receta que puedes hacer con lo tuyo y que te compensa más que vender lo tuyo
    -- y seguir la ruta (ver BagsAlternative): se mete en su tramo. Si no compensa,
    -- la ruta no la usa y la UI explica por qué. Varias pasadas: con lo que te
    -- queda puede salir otra
    for _ = 1, BAGS_PASSES do
      local alt = Planner.BagsAlternative(data, best, opts.owned, opts.from, o.excluded, true)
      if not alt or not Planner.BagsWorth(alt) then break end
      local t = {}
      for k, v in pairs(o) do t[k] = v end
      t.forced = {}
      for s, id in pairs(best.choice) do t.forced[s] = id end
      for s = alt.from, alt.to - 1 do t.forced[s] = alt.id end
      local plan = Planner:Plan(data, t)
      if plan.reached < best.reached then break end
      plan.cheapest, plan.craftCostUsed = best.cheapest, best.craftCostUsed
      best = plan
    end
    return best
  end

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
    -- Y con lo mismo fabricado o comprado: la ruta se eligió comprando Light Leather;
    -- si al recorrerla con tus chatarras pasara a fabricarlo, el coste sería de otra
    -- ruta y la búsqueda de arriba (fabricar ↔ comprar) compararía cosas distintas
    withBags.via = Copy(route.ctx and route.ctx.via or {})
    for itemID, way in pairs(opts.via or {}) do withBags.via[itemID] = way end
    local plan = Planner:Plan(data, withBags)
    plan.cheapest, plan.craftCostUsed = route.cheapest, route.craftCostUsed
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
      balanced.craftCostUsed = CRAFT_COST
      return balanced
    end
    cheap.craftCostUsed = 0
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

  -- Recetas candidatas y lo que no depende del nivel. Con la ruta entera forzada
  -- (la fijada, las que recorre el GPS) solo hacen falta las suyas: el resultado es
  -- el mismo y prepararlas todas era lo que más tardaba
  local only
  -- (opts.fullInfo: la ruta que se enseña, con las recetas bloqueadas de cada paso)
  if opts.forced and not opts.fullInfo then
    only = {}
    for s = opts.from, opts.to - 1 do
      local id = opts.forced[s]
      if not id then only = nil break end
      only[id] = true
    end
  end
  local info = {}
  for id, r in pairs(data.recipes) do
    local learn = (not only or only[id]) and Planner.LearnSkill(r, opts)
    -- opts.excluded: recetas que el jugador ha quitado de la ruta (p. ej. el pergamino está lejos)
    if learn and learn < opts.to and r.t[4] > opts.from and not (opts.excluded and opts.excluded[id]) then
      local learnCost, learnSource = Planner.LearnCost(ctx, r)
      info[id] = { learn = learn, sale = Planner.SaleInfo(ctx, r), learnCost = learnCost, learnSource = learnSource,
        cd = Planner.Cooldown(r, id) }
    end
  end

  -- Voraz: el mejor por cada punto, gastando existencias de la AH
  local learned = {}
  local bought = {} -- [itemID] = { ahQty, ahCost, vendorQty, vendorCost }
  local craftedQty = {}
  local aheadQty = {} -- [receta] = { [recetaQueLoUsa] = unidades } fabricadas de más en el paso de esa receta
  local keptQty = {}  -- [itemID] = unidades fabricadas en el plan que se usan después
  local keptFor = {}  -- [itemID] = { [recetaQueLoUsa] = unidades }
  local ownedQty = {} -- [itemID] = unidades que se usan de tus bolsas/banco
  local perPoint = {}
  local cdUsed = {} -- recetas con enfriamiento ya usadas para su punto (ver Planner.Cooldown)
  local lastWhy
  -- Puntos de media que ya han dado los materiales fabricados por el camino (ver
  -- CraftBonus): al llegar a uno entero, ese nivel no pide fabricar nada
  local carry, lastBest = 0, nil

  for s = opts.from, opts.to - 1 do
    if carry >= 1 - EPS and lastBest then
      -- Punto ya ganado con lo intermedio: sin fabricaciones ni materiales, en el
      -- paso de la receta anterior
      carry = carry - 1
      perPoint[#perPoint + 1] = { id = lastBest.id, crafts = 0, chance = lastBest.chance, cost = 0, value = 0,
        reagents = {}, need = {}, blocked = {}, skill = s, free = true }
      plan.choice[s] = lastBest.id
    else
    local best
    local why = {}
    ctx.skill = s -- (lo que aún da puntos a este nivel no se fabrica como preparación, ver Acquire)
    -- Primer nivel del paso de este nivel (ruta fijada: donde empieza la receta elegida;
    -- si no, el nivel anterior es de otra receta o de la misma, según lo elegido)
    local f = opts.forced
    if f and f[s] then
      ctx.stepStart = (s > opts.from and f[s - 1] == f[s]) and ctx.stepStart or s
    else
      ctx.stepStart = (lastBest and plan.choice[s - 1] == lastBest.id and ctx.stepStart) or s
    end
    local blocked = {} -- recetas que se podrían usar pero les falta el precio de algún material
    -- Ruta fijada (ver arriba): en ese punto solo vale la receta ya elegida; donde
    -- la ruta sin bolsas se paraba, lo tuyo puede permitir seguir con cualquiera
    local forced = opts.forced and opts.forced[s]
    for id, inf in pairs(info) do
      ES.Yield() -- calculado como trabajo (Jobs.lua): sigue en el siguiente fotograma
      if inf.learn <= s and (not forced or forced == id) then
        local r = data.recipes[id]
        local chance = Planner.Chance(r.t, s)
        -- Con enfriamiento: un solo punto en toda la ruta, y en naranja (una fabricación)
        if inf.cd and (cdUsed[id] or chance < 1) then chance = 0 end
        if chance > 0 then
          local crafts = 1 / chance
          local whyR = {}
          local cost, reagents, extra, actions = RecipeCost(ctx, r, crafts, whyR)
          -- Herramientas que pide y aún no tienes (se consiguen una sola vez, la primera
          -- vez que hace falta): { { tool, cost } }
          local toolCost, tools
          for _, tool in ipairs(cost and Planner.RecipeTools(r) or {}) do
            if cost and (ctx.toolMask[tool.family or "rod"] or 0) < tool.mask then
              -- (una herramienta se fabrica una vez y no se compra: vale aunque dé puntos)
              local skill = ctx.skill
              ctx.skill = nil
              local c = Acquire(ctx, tool.item, 1, 0, extra, actions, whyR)
              ctx.skill = skill
              if c then
                tools = tools or {}
                tools[#tools + 1] = { tool = tool, cost = c }
                toolCost = (toolCost or 0) + c
              else
                cost = nil
              end
            end
          end
          for itemID, reason in pairs(whyR) do why[itemID] = why[itemID] or reason end
          if not cost then
            blocked[#blocked + 1] = { id = id, chance = chance, missing = whyR }
          else
            local value = SaleValue(inf.sale, crafts)
            -- Si fabricarla da dinero (lo que sacas al vendedor supera los materiales),
            -- ese beneficio no puede crecer con las fabricaciones que pide una receta
            -- casi gris: Lesser Magic Wand al 8% (13 por punto) "ganaba" a Greater
            -- Magic Wand al 95% solo por vender más varitas. Para elegir, el beneficio
            -- cuenta entero hasta PROFIT_FULL_CRAFTS fabricaciones por punto y, más allá,
            -- rebajado (el coste real de la ruta no cambia). Antes se rebajaba siempre
            -- (como una sola fabricación) y se comía el beneficio de pasos normales: la
            -- Rough Dynamite con pólvora de tus piedras ganaba 45s y contaban 12s
            -- Y cada fabricación de más allá pesa CRAFT_COST: si no, una receta con
            -- beneficio ganaba a cualquiera que costase algo aunque estuviera casi gris
            local net = cost - value
            if net < 0 and crafts > PROFIT_FULL_CRAFTS then
              net = net * PROFIT_FULL_CRAFTS / crafts + CRAFT_COST * (crafts - PROFIT_FULL_CRAFTS)
            end
            -- Coste simbólico de cada fabricación (solo al elegir; ver Plan)
            local score = net + (opts.craftCost or 0) * crafts
            -- En verde, algo de mala suerte (solo al elegir: Planner.GreenRisk)
            local risk = Planner.GreenRisk(r.t, s, chance, opts)
            if risk > 0 then score = score + (cost / crafts + (opts.craftCost or 0)) * risk end
            local span = math.max(1, math.min(r.t[4], opts.to) - s)
            local feeSpan
            if inf.learnCost > 0 and not learned[id] then
              -- Entre los puntos que la usó la pasada anterior, si fueron menos (ver arriba)
              feeSpan = math.max(1, math.min(span, opts.feeSpan and opts.feeSpan[id] or span))
              score = score + inf.learnCost / feeSpan
            end
            if toolCost then score = score + toolCost / span end
            -- Lo fabricado por el camino también sube puntos: el punto sale más barato
            local bonus = CraftBonus(ctx, actions, s)
            score = score / (1 + bonus)
            if not best or score < best.score then
              best = {
                id = id, score = score, crafts = crafts, chance = chance, cost = cost, value = value,
                reagents = reagents, extra = extra, actions = actions,
                tools = tools, toolCost = toolCost or 0, feeSpan = feeSpan, bonus = bonus,
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

    -- Herramientas conseguidas: cada una cubre su categoría y las inferiores
    for _, t in ipairs(best.tools or {}) do
      local fam = t.tool.family or "rod"
      ctx.toolMask[fam] = math.max(ctx.toolMask[fam] or 0, t.tool.mask)
      plan.tools[#plan.tools + 1] = { item = t.tool.item, cost = t.cost, skill = s }
      plan.toolsCost = plan.toolsCost + t.cost
    end

    -- Recetas con más probabilidad que la elegida que no se pueden usar por falta de precio
    best.blocked = {}
    for _, b in ipairs(blocked) do
      if b.chance > best.chance then best.blocked[#best.blocked + 1] = b end
    end

    -- Confirmar: gastar existencias de la AH y del inventario, y anotar compras
    learned[best.id] = true
    if info[best.id].cd then cdUsed[best.id] = true end
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
      -- Material que se puede fabricar: lo decidido ahora (fabricar o comprar) se
      -- mantiene en el resto del plan (ver Acquire)
      if ctx.producers[a.item] and not ctx.via[a.item] then
        if a.kind == "craft" then ctx.via[a.item] = "craft"
        elseif a.kind == "ah" or a.kind == "vendor" then ctx.via[a.item] = "buy" end
      end
      if a.kind == "craft" and a.ahead then
        -- Se fabrica de más en el paso de su receta (antes): ver Acquire
        aheadQty[a.recipe] = aheadQty[a.recipe] or {}
        aheadQty[a.recipe][best.id] = (aheadQty[a.recipe][best.id] or 0) + a.qty
      elseif a.kind == "craft" then
        -- (from: el nivel en que se empieza a fabricar; antes, si daba puntos, no se podía)
        craftedQty[a.item] = craftedQty[a.item] or { qty = 0, recipe = a.recipe, from = s, prof = a.prof }
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
    -- Materiales que pide este punto (comprados o de tus bolsas): con la ruta
    -- fijada, la lista de la compra cuenta lo que falta desde tu nivel actual
    -- (los recorridos del GPS, opts.gpsWalk, no lo guardan: nadie lo lee de ellos, ver Walk)
    if not opts.gpsWalk then
    best.need = {}
    best.use = {} -- [itemID] = { [kind] = unidades }: de dónde sale cada material (auditoría)
    for _, a in ipairs(best.actions) do
      if a.kind == "ah" or a.kind == "vendor" or a.kind == "owned" then
        best.need[a.item] = (best.need[a.item] or 0) + a.qty
      end
      local u = best.use[a.item] or {}
      best.use[a.item] = u
      local k = a.ahead and "ahead" or a.kind
      u[k] = (u[k] or 0) + a.qty
    end
    end
    -- Esta receta ya es un paso de la ruta: lo que los siguientes pidan de lo que
    -- fabrica se hace de más en él (ver Acquire)
    ctx.made = ctx.made or {}
    ctx.made[best.id] = true
    -- Lo fabricado entra al inventario del plan, valorado como se ha contado su venta
    local sale = info[best.id].sale
    if sale then
      ctx.stock[sale.itemID] = ctx.stock[sale.itemID] or {}
      AddLot(ctx.stock[sale.itemID], sale.vendor, best.crafts * sale.qty)
    end
    perPoint[#perPoint + 1] = best
    best.skill = s
    plan.choice[s] = best.id
    lastBest, carry = best, carry + (best.bonus or 0)
    end
  end

  ctx.skill, ctx.stepStart = nil, nil -- (fuera del recorrido punto a punto: sin nivel)

  -- [nivel] = { [itemID] = unidades } que pide ese punto (ver arriba)
  plan.pointNeed, plan.pointChance, plan.pointUse = {}, {}, {}
  -- [nivel] = lo que cuesta de media ese punto (materiales menos lo que se recupera
  -- vendiendo lo fabricado): lo que te ahorras si lo subes de otra forma (ver Leftover)
  plan.pointNet = {}
  plan.freePoints = 0 -- puntos que dan los materiales fabricados por el camino (ver CraftBonus)
  for _, p in ipairs(perPoint) do
    plan.pointNeed[p.skill], plan.pointChance[p.skill] = p.need, p.chance
    if not opts.gpsWalk then plan.pointNet[p.skill] = (p.cost or 0) - (p.value or 0) end -- (solo lo lee Leftover)
    plan.pointUse[p.skill] = p.use -- (tools/route_audit.py)
    if p.free then plan.freePoints = plan.freePoints + 1 end
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
  local questPaid = {} -- misiones (y de su cadena) cuyos objetos ya cuenta un paso anterior
  for _, st in ipairs(plan.steps) do
    local inf = info[st.id]
    st.recipe = data.recipes[st.id]
    st.crafts = math.ceil(st.expected - 0.001)
    -- El desglose usa fabricaciones enteras al mismo precio medio que el total.
    local factor = st.crafts / st.expected
    for _, rg in ipairs(st.reagents) do
      rg.qty = rg.qty * factor
      rg.cost = rg.cost * factor
    end
    st.unitCost = st.costSum / st.expected
    st.unitValue = st.valueSum / st.expected
    st.sale = inf.sale
    local firstUse = not feePaid[st.id]
    st.fee = firstUse and inf.learnCost or 0
    st.learnSource = firstUse and inf.learnSource or nil
    -- De misión: lo que piden las misiones de su cadena se paga una vez aunque la ruta use
    -- varias recetas de la misma cadena (Wild Leather Vest y Leggings piden las dos Wild
    -- Leather Armor). La elección de recetas sí las cuenta en cada una: sale algo cara
    if st.learnSource == "quest" then
      local src = Planner.RecipeSource(ctx, st.recipe)
      local q = src and src.best and src.best.kind == "quest" and src.best.quest
      if q then
        -- (questCost: lo que paga este paso, para que el tooltip de la fila diga lo mismo)
        local fee, unpriced, items = Planner.QuestCost(ctx, q, questPaid)
        st.fee = fee
        st.questCost = { cost = fee, unpriced = unpriced or nil, items = items, quest = q }
        questPaid[q.id] = true
        for _, p in ipairs(q.pre or {}) do questPaid[p] = true end
      end
    end
    -- Antes hay que hacer la misión que la desbloquea (el paso avisa y lleva a quien la da)
    st.questFirst = firstUse and st.learnSource ~= "known" and Planner.QuestFirst(st.recipe) or nil
    feePaid[st.id] = true
    st.total = st.crafts * (st.unitCost - st.unitValue) + st.fee

    plan.reagentCost = plan.reagentCost + st.crafts * st.unitCost
    plan.resale = plan.resale + st.crafts * st.unitValue
    plan.fees = plan.fees + st.fee
  end

  -- Lo que pasos siguientes piden de lo que fabrica un paso, fabricado de más en él
  -- (ver Acquire): "Rough Blasting Powder 1-30 · 60 fabricaciones (27 para Rough
  -- Copper Bomb)". aheadGain: los puntos que darían esas fabricaciones de más al
  -- final del paso (el GPS alarga el paso con ellos, ver Walk)
  for rid, users in pairs(aheadQty) do
    local host
    for _, st in ipairs(plan.steps) do if st.id == rid then host = st end end
    if host then
      local r = host.recipe
      local qty = 0
      host.ahead = {}
      for user, q in pairs(users) do
        host.ahead[#host.ahead + 1] = { recipe = data.recipes[user], quantity = math.ceil(q - 0.001) }
        qty = qty + q
      end
      table.sort(host.ahead, function(a, b) return a.quantity > b.quantity end)
      host.aheadCrafts = math.ceil(qty / ((r.out and r.out[2]) or 1) - 0.001)
      local lvl = host.to
      for _ = 1, host.aheadCrafts do
        local c = Planner.Chance(r.t, math.floor(lvl))
        if c <= 0 then break end
        lvl = lvl + c
      end
      host.aheadGain = math.floor(lvl - host.to + EPS)
    end
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

  -- quantity: las que hay que FABRICAR (lo de tus bolsas ya está descontado); owned:
  -- las que la ruta saca de tus bolsas. Lo que gasta la ruta es la suma (Planner.CraftedTotal)
  for itemID, c in pairs(craftedQty) do
    -- (prof: la receta es de otra profesión, como Smelt Mithril; ver ES:ForeignProducers)
    plan.crafted[#plan.crafted + 1] = { itemID = itemID, quantity = math.ceil(c.qty - 0.001), recipe = CtxRecipe(ctx, c.recipe), from = c.from,
      owned = ownedQty[itemID] and math.ceil(ownedQty[itemID] - 0.001) or nil, prof = c.prof }
  end
  -- Recetas de lo que se fabrica por el camino que aún no sabes (Stonescale Oil para
  -- Elixir of Greater Defense: 1g 50s en el instructor). Su precio cuenta en la ruta (y
  -- así el GPS ve si sale mejor comprarlo hecho) y la vista Ruta pone una fila para
  -- aprenderla. Antes ni se contaba ni se decía: "Fabrica 14× Stonescale Oil" sin saberla
  plan.prepLearn = {}
  for _, c in ipairs(plan.crafted) do
    local r = c.recipe
    if r and r.id and not r.conversion and not feePaid[r.id] and not plan.prepLearn[r.id] then
      local cost, source = Planner.LearnCost(ctx, r)
      if source and source ~= "known" and source ~= "rep" and source ~= "spec" then
        plan.prepLearn[r.id] = { cost = cost or 0, source = source }
        plan.fees = plan.fees + (cost or 0)
      end
    end
  end

  -- Un paso que empieza gastando lo fabricado antes (la pólvora del paso anterior) y a
  -- mitad necesita fabricar más: el jugador lo tiene que tener ANTES de empezar el
  -- paso (Discord: "112 de dinamita y no tengo pólvora", que la ruta dejaba para el
  -- 40). Si la receta ya no da puntos al empezar el paso, se fabrica ahí; si aún los
  -- da, la ruta no se puede seguir (el material solo cuadra con lo esperado de media)
  -- y se descarta (ver RouteScore): mejor alargar el paso del ingrediente
  for _, c in ipairs(plan.crafted) do
    for _, st in ipairs(plan.steps) do
      if c.from and st.from < c.from and c.from < st.to and st.reagents[c.itemID] then
        local r = c.recipe
        -- (una de otra profesión no da puntos de esta: sus colores no cuentan aquí)
        if r and not c.prof and not r.intermediate and not r.conversion and Planner.Chance(r.t, st.from) > 0 then
          plan.unfollowable = true
        end
        c.from = st.from
        break
      end
    end
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
  plan.pendingItems = ctx.pendingItems -- [itemID] = true: objetos cuyo precio de vendedor aún no da el juego
  plan.ctx = ctx
  plan.net = plan.reagentCost - plan.resale + plan.fees + plan.toolsCost
  plan.reached = reached
  if not opts.gpsWalk then Planner.WholeCraftShopping(plan) end
  return plan
end

-- Lo que se compra, en fabricaciones enteras: cada paso redondea sus fabricaciones
-- hacia arriba (14,7 -> 15) y su coste ya las cuenta así, pero la lista sumaba lo
-- esperado fraccionario (Discord: "me pide 98 de algo y hacen falta 100"; Mageweave
-- Cloth x516 cuando 15 fabricaciones piden 519, con "Tienes 0/519" en la misma fila).
-- Se completa cada material hasta lo que piden las fabricaciones enteras (NeedFrom, la
-- misma regla que la Lista de compra), menos lo que sale de tus bolsas y lo que
-- fabricas por el camino. Solo se sube, nunca se baja.
function Planner.WholeCraftShopping(plan)
  if not (plan and plan.shopping and #plan.shopping > 0 and plan.pointNeed) then return end
  local whole = Planner.NeedFrom(plan, plan.from or 1)
  local have = {}
  for _, o in ipairs(plan.owned or {}) do have[o.itemID] = (have[o.itemID] or 0) + o.quantity end
  for _, c in ipairs(plan.crafted or {}) do have[c.itemID] = (have[c.itemID] or 0) + c.quantity end
  local byItem = {}
  for _, it in ipairs(plan.shopping) do
    local b = byItem[it.itemID]
    if not b then b = { qty = 0 } byItem[it.itemID] = b end
    b.qty = b.qty + it.quantity
    -- (lo que falta va a la fuente de la que más se compra)
    if not b.main or it.quantity > b.main.quantity then b.main = it end
  end
  local respectSupply = plan.ctx and plan.ctx.opts and not plan.ctx.opts.ignoreSupply
  for itemID, b in pairs(byItem) do
    local short = (whole[itemID] or 0) - (have[itemID] or 0) - b.qty
    -- (mirando existencias: no más de lo que hay a la venta en la AH)
    if respectSupply and b.main.source == "ah" and b.main.supply then
      short = math.min(short, b.main.supply - b.main.quantity)
    end
    if short > 0 then
      b.main.quantity = b.main.quantity + short
      b.main.total = b.main.total + short * (b.main.unit or 0)
    end
  end
end

---------------------------------------------------------------------------
-- Con lo que llevas: una receta que no está en la ruta y que podrías hacer
-- durante unos cuantos puntos solo con tus materiales (y lo del vendedor). La
-- ruta no la elige porque valora lo tuyo a precio de compra (ver Plan); aquí se
-- cuenta aparte: el oro que ahorrarías y lo que te darían por lo tuyo si lo
-- vendieras. Si compensa, Plan la mete en la ruta; si no, la UI explica por qué no.
---------------------------------------------------------------------------

-- Lo que te darían de verdad por `qty` unidades tuyas, con las mismas reglas que lo
-- fabricado en la vista Profit (SaleAdvice): en la AH al precio realista (el de
-- referencia si el mínimo está inflado) menos comisión y depósito, todas si el
-- mercado va bien, unas pocas si es dudoso y ninguna si va mal; el resto, al
-- vendedor. Y nunca más en la AH de las que hay ahora a la venta: un mercado de 15
-- Medium Hide no absorbe 34 más a ese precio. Con el último escaneo, no con los
-- precios de la ruta fijada (esos solo guardan lo que usa la ruta)
local OWNED_AH_FEW = 5
local function OwnedSaleTotal(ctx, itemID, qty)
  local vendor = ES:VendorSellPrice(itemID) or (ES.Data.SellPrices and ES.Data.SellPrices[itemID]) or 0
  local entry = ScanPrices()[itemID] or ctx.prices[itemID]
  local fair = entry and entry.minUnit and ES.Market:FairPrice(itemID, entry.minUnit)
  if not fair then return vendor * qty end
  local deposit, cut = Planner.AuctionCosts(vendor, ctx.opts)
  local net = fair.price * (1 - cut) - deposit
  if net <= vendor then return vendor * qty end
  local verdict = ES.Market:Signals(itemID).verdict
  local onAH = verdict == "good" and qty or verdict == "avoid" and 0 or math.min(qty, OWNED_AH_FEW)
  onAH = math.min(onAH, entry.quantity or onAH)
  return onAH * net + (qty - onAH) * vendor
end
Planner.OwnedValue = OwnedSaleTotal

-- Lo que dejas de ganar al usar `qty` de tus `have`: lo que vale todo lo tuyo
-- vendido menos lo que vale lo que te queda. No lo que valdrían esos `qty`
-- vendidos: usando 10 de tus 34 Medium Hide sigues vendiendo en la AH las pocas
-- que absorbe a buen precio; lo que pierdes son 10 al precio del vendedor
local function OwnedCost(ctx, itemID, have, qty)
  qty = math.min(qty, have)
  if qty <= 0 then return 0 end
  return OwnedSaleTotal(ctx, itemID, have) - OwnedSaleTotal(ctx, itemID, have - qty)
end
Planner.OwnedCost = OwnedCost -- (para Planner.RouteScore)

-- plan: la ruta que se enseña; owned: { [itemID] = cantidad } en bolsas/banco;
-- from: tu nivel; excluded: recetas quitadas con la ✕ (la ruta fijada no las
-- guarda). Devuelve la mejor alternativa o nil: la que da más puntos o, con
-- onlyWorth, la que más gana a vender lo tuyo de entre las que compensan (para
-- meterla en la ruta: la de más puntos puede no compensar y otra sí):
-- { id, recipe, from, to, crafts, fee, feeUnknown, spend (oro que pagas), gold (spend
--   menos lo que sacas vendiendo lo fabricado), value (lo tuyo, vendido), routeCost,
--   saving (routeCost - gold), use = { { itemID, qty, value } } (de más a menos valor) }
function Planner.BagsAlternative(data, plan, owned, from, excluded, onlyWorth)
  local ctx = plan and plan.ctx
  if not ctx or not owned or not next(owned) then return nil end
  from = math.max(from or plan.from, plan.from)
  local to = plan.reached or plan.to
  if from >= to then return nil end
  local inRoute = {}
  for _, st in ipairs(plan.steps) do inRoute[st.id] = true end
  -- Lo tuyo que ya gasta la ruta no se puede usar dos veces
  local left = {}
  for itemID, n in pairs(owned) do left[itemID] = n end
  for _, it in ipairs(plan.owned or {}) do
    if left[it.itemID] then left[it.itemID] = left[it.itemID] - it.quantity end
  end
  excluded = excluded or ctx.opts.excluded or {}
  local best
  for id, r in pairs(data.recipes) do
    -- (las de enfriamiento no: dan un punto como mucho, ver Planner.Cooldown)
    local learn = r.out and not inRoute[id] and not excluded[id] and not r.conversion and not r.intermediate
      and not Planner.Cooldown(r, id) and Planner.LearnSkill(r, ctx.opts)
    if learn and learn < to and r.t[4] > from then
      -- Fabricaciones que te dan tus materiales (lo del vendedor se compra)
      local crafts, mine = math.huge, false
      for _, rq in ipairs(r.r) do
        if not ES.Data.VendorPrices[rq[1]] then
          mine = true
          crafts = math.min(crafts, math.floor((left[rq[1]] or 0) / rq[2]))
        end
      end
      local start = math.max(from, learn)
      if mine and crafts >= 1 then
        -- Puntos que dan (como el plan: 1/probabilidad fabricaciones por punto)
        local s, used = start, 0
        while s < to do
          local chance = Planner.Chance(r.t, s)
          if chance <= 0 or used + 1 / chance > crafts + EPS then break end
          used = used + 1 / chance
          s = s + 1
        end
        if s - start >= BAGS_MIN_POINTS then
          local n = math.ceil(used - 0.001)
          local fee, source = Planner.LearnCost(ctx, r)
          local gold, value, use = fee, 0, {}
          for _, rq in ipairs(r.r) do
            local vendor = ES.Data.VendorPrices[rq[1]]
            if vendor then
              gold = gold + vendor * rq[2] * n
            else
              local v = OwnedCost(ctx, rq[1], left[rq[1]] or 0, rq[2] * n)
              value = value + v
              use[#use + 1] = { itemID = rq[1], qty = rq[2] * n, value = v }
            end
          end
          local spend = gold -- oro que sale de tu bolsillo (instructor y vendedor)
          gold = gold - SaleValue(Planner.SaleInfo(ctx, r), n)
          table.sort(use, function(a, b) return a.value > b.value end)
          -- Lo que cuesta la ruta en ese tramo; el precio de aprender una receta
          -- de la ruta solo se ahorra si ya no hace falta en ningún otro punto
          local outside = {}
          for _, st in ipairs(plan.steps) do
            if st.from < start or st.to > s then outside[st.id] = true end
          end
          local routeCost = 0
          for _, st in ipairs(plan.steps) do
            local a, b = math.max(st.from, start), math.min(st.to, s)
            if b > a then
              routeCost = routeCost + (st.total - st.fee) * (b - a) / (st.to - st.from)
              if not outside[st.id] then routeCost = routeCost + st.fee end
            end
          end
          local saving = routeCost - gold
          local alt = {
            id = id, recipe = r, from = start, to = s, crafts = n,
            fee = fee, feeUnknown = source == "trainer" and r.trainer and not Fee(r) or nil,
            gold = gold, spend = spend, value = value, routeCost = routeCost, saving = saving, use = use,
          }
          local diff = saving - value
          local better
          if onlyWorth then
            better = Planner.BagsWorth(alt) and (not best or diff > best.saving - best.value)
          else
            better = not best or alt.to - alt.from > best.to - best.from
              or (alt.to - alt.from == best.to - best.from and diff > best.saving - best.value)
          end
          if saving >= BAGS_MIN_SAVING and better then best = alt end
        end
      end
    end
  end
  return best
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
    hours = opts.hours, neutral = opts.neutral, sourcedScrolls = opts.sourcedScrolls, noQuests = opts.noQuests,
    noLimited = opts.noLimited, knownProducers = opts.knownProducers, vendorDiscount = opts.vendorDiscount,
    foreignProducers = opts.foreignProducers,
    -- (precios propios en vez de los del escaneo: los tuyos de BulkMoney)
    prices = opts.prices, pricesTime = opts.pricesTime }
  Annotate(data) -- (antes del contexto: knownProducers pregunta por r.id)
  local ctx = NewContext(data, o)
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
          learn = basic and 1 or select(2, Fee(r)) or 1, learnCost = learnCost or 0, learnSource = learnSource or (basic and "basic" or "unknown"),
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
          -- Solo al vendedor (venta segura): para la opción de la Colección
          e.profitVendor = e.vendor * qty - cost
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
}

-- Huella de los niveles y topes de tus profesiones (sin las armas ni la defensa):
-- SKILL_LINES_CHANGED y CHAT_MSG_SKILL llegan también con cada punto de arma o
-- defensa, que en combate son continuos. Con la huella igual no se hace nada (antes
-- se releían todas las profesiones y se recalculaban los avisos de las rutas
-- empezadas: ~5% de CPU yendo de misiones, CurseForge)
function ES:ProfessionSkillStamp()
  local parts = {}
  for _, p in ipairs(ES.PROFESSIONS or {}) do
    local data = ES.Data[p.key]
    local rank, cap
    if data and data.skillLine then rank, cap = self:GetProfessionSkill(data.skillLine) end
    parts[#parts + 1] = tostring(rank) .. "/" .. tostring(cap)
  end
  return table.concat(parts, ",")
end

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


---------------------------------------------------------------------------
-- Alternativas de un paso: por qué la ruta usa esta receta y no otra
---------------------------------------------------------------------------
-- La misma ruta, pero con otra receta en el tramo del paso (lo demás igual): la
-- diferencia de coste neto ya cuenta materiales, venta, aprender y lo que se reutiliza
-- después. Cada una es una pasada forzada (~2 ms)

-- Recetas que podrían hacer el tramo de `st`: se pueden aprender a ese nivel y aún dan
-- puntos al empezarlo (ni conversiones, ni materiales intermedios, ni las quitadas)
function Planner.AlternativeCandidates(data, plan, st)
  local opts = plan.ctx and plan.ctx.opts
  if not opts or not plan.choice then return {} end
  local out = {}
  for id, r in pairs(data.recipes) do
    if id ~= st.id and not r.conversion and not r.intermediate and r.t[4] > st.from
      and not (opts.excluded and opts.excluded[id]) then
      local learn = Planner.LearnSkill(r, opts)
      if learn and learn <= st.from then out[#out + 1] = id end
    end
  end
  table.sort(out)
  return out
end

-- Pasos A-B-A con B corto (los que la ruta quita a propósito, ver PlanGPS)
local function Zigzags(plan)
  local n, steps = 0, plan.steps or {}
  for i = 2, #steps - 1 do
    local a, b, c = steps[i - 1], steps[i], steps[i + 1]
    if a.id == c.id and b.to - b.from <= ZIGZAG_STEPS then n = n + 1 end
  end
  return n
end

-- La ruta con `id` en el tramo de `st`. Devuelve { id, delta (coste neto de más de toda
-- la ruta), score (lo mismo con la vara del planificador, Planner.RouteScore: también
-- fabricaciones, pasos...), step (su paso en ese tramo), ahGain (lo que ganaría
-- vendiendo lo fabricado en la AH en vez de al vendedor), crafts, steps, zigzags,
-- unfollowable (de la ruta con ella) }, o nil si así no se llega igual de lejos
function Planner.EvaluateAlternative(data, plan, st, id)
  local o = Copy(plan.ctx.opts)
  if o.prices then
    -- Ruta fijada: sus precios guardados son solo los de los objetos de sus recetas
    -- (ver RoutePrices en ProfessionUI). Con ellos, cualquier otra receta se quedaba sin
    -- precio para sus materiales y ningún paso tenía alternativa ("ninguna otra sirve
    -- sin cambiar el resto de la ruta", Discord: Green Iron Bracers a 144). Lo de la ruta
    -- con sus precios guardados; lo demás, con los del último escaneo
    if not plan.altPrices then
      local merged = {}
      for itemID, entry in pairs(ScanPrices()) do merged[itemID] = entry end
      for itemID, entry in pairs(o.prices) do merged[itemID] = entry end
      plan.altPrices = merged
    end
    o.prices, o.shared = plan.altPrices, nil
  end
  o.forced = {}
  for s, c in pairs(plan.choice) do o.forced[s] = c end
  for s = st.from, st.to - 1 do o.forced[s] = id end
  local ok, p = pcall(Planner.Plan, Planner, data, o)
  if not ok or not p or (p.reached or 0) < (plan.reached or 0) then return nil end
  local step
  for _, s in ipairs(p.steps or {}) do
    if s.id == id and s.from <= st.from and s.to > st.from then step = s break end
  end
  if not step then return nil end
  local sale, ahGain = step.sale, 0
  if sale and sale.ahNet and sale.vendor and sale.ahNet > sale.vendor then
    ahGain = step.crafts * (sale.qty or 1) * (sale.ahNet - sale.vendor)
  end
  return { id = id, delta = p.net - plan.net, score = Planner.RouteScore(p) - Planner.RouteScore(plan),
    step = step, ahGain = ahGain, crafts = Planner.TotalCrafts(p), steps = #p.steps,
    zigzags = Zigzags(p), unfollowable = p.unfollowable }
end

-- Si `alt` es de verdad mejor que la ruta, con la misma vara con la que el
-- planificador elige (antes la fila decía "sale X más barata" mirando solo el oro,
-- y la ruta podía haberla descartado a propósito). Devuelve:
--   "better":       mejor también para el planificador (no la encontró)
--   "learnFew":     aprenderla para pocas fabricaciones no compensa (LEARN_WORTH)
--   "zigzag":       deja un salto A-B-A, que la ruta quita si cuesta poco (ZIGZAG_*)
--   "crafts", "steps", "unfollowable", "weights": más barata en oro pero peor con la
--                   vara de la ruta, y el motivo principal
--   nil:            no es más barata ni en oro
function Planner.AlternativeVerdict(plan, st, alt)
  if alt.delta > -0.5 and (alt.score or alt.delta) > -0.5 then return nil end
  local score = alt.score or alt.delta
  if score <= -0.5 then
    -- Mejor con la vara de la ruta, salvo las reglas que la ruta aplica a propósito al final
    local a = alt.step
    local learns = a.learnSource ~= nil and a.learnSource ~= "known"
    if learns and (a.crafts or 0) <= LEARN_FEW_CRAFTS and -score <= LEARN_WORTH then return "learnFew" end
    if (alt.zigzags or 0) > Zigzags(plan) then
      local allowed = math.max(ZIGZAG_MIN, ZIGZAG_PCT * math.abs(Planner.RouteScore(plan)))
      if -score <= allowed then return "zigzag" end
    end
    return "better"
  end
  -- Más barata en oro, pero no para la ruta: por qué
  if alt.unfollowable and not plan.unfollowable then return "unfollowable" end
  if (alt.crafts or 0) > Planner.TotalCrafts(plan) + 0.5 then return "crafts" end
  if (alt.steps or 0) > #(plan.steps or {}) then return "steps" end
  return "weights"
end

-- Motivo principal por el que `alt` sale peor que el paso `st` de la ruta:
-- "materials" (materiales más caros), "sale" (se recupera menos vendiéndolo), "fee"
-- (hay que aprenderla), "crafts" (hacen falta más fabricaciones) o "route" (afecta a
-- otros pasos: lo que se reutiliza después)
function Planner.AlternativeReason(st, alt)
  local a = alt.step
  local parts = {
    materials = (a.costSum or 0) - (st.costSum or 0),
    sale = (st.valueSum or 0) - (a.valueSum or 0),
    fee = (a.fee or 0) - (st.fee or 0),
  }
  local best, bestV = nil, 0
  for k, v in pairs(parts) do if v > bestV then best, bestV = k, v end end
  if not best then
    -- Nada de este paso sale peor: más fabricaciones o el resto de la ruta
    return (a.expected or 0) > (st.expected or 0) + 0.5 and "crafts" or "route"
  end
  return best
end