local _, ES = ...
local L = ES.L

-- Ganar dinero con tus profesiones, día a día: de las recetas que SABES, cuáles
-- dan beneficio con los precios del último escaneo y cuántas fabricar.
--
-- No se estiman ventas. "Cuántas" solo evita inundar el mercado:
--   alerta "bien":            hasta el AH_SHARE de las unidades a la venta (tope MAX_BATCH)
--   "ojo" / "pocos datos":    unas pocas para probar (TEST_BATCH)
--   "evitar":                 no se recomienda (se lista aparte con el motivo)
--   se vende al vendedor:     venta segura: tantas como dejen beneficio, mientras
--                             la siguiente aún compense y queden materiales en la AH
--                             (ver VendorCrafts); van aparte del lote
-- (El buzón no se lee: el addon no guarda nada de tu correo.)

local Earn = {}
ES.Earn = Earn

local MIN_PROFIT = 5         -- cobre por fabricación como mínimo
local MIN_MARGIN = 0.10      -- y al menos un 10% sobre el coste
local AH_SHARE = 0.3         -- no anunciar más del 30% de lo que ya hay a la venta
local MAX_BATCH = 10
local TEST_BATCH = 3
-- Vendedor: tope de la búsqueda (el vendedor compra sin límite; lo que para es la
-- escalera de los materiales)
local VENDOR_MAX = 1000
local BATCH_SIZE = 8         -- recetas en el lote de hoy
local WATCH_WEIGHT = 0.5     -- "ojo" puntúa la mitad
local OLD_SCAN = 12 * 3600   -- más viejo que esto: avisar

Earn.OLD_SCAN = OLD_SCAN

-- Beneficio mínimo de una línea (lo que dejan todas sus fabricaciones juntas, no
-- cada una): por debajo no compensa el viaje a la AH. Lo elige el jugador en la
-- cabecera (ES.db.earnMinProfit); por defecto, 10 platas
Earn.MIN_LINE_STEPS = { 0, 1000, 2500, 5000, 10000, 25000, 50000, 100000, 200000 } -- 0, 10s, 25s, 50s, 1g, 2g50s, 5g, 10g, 20g
Earn.DEFAULT_MIN_LINE = 1000
function Earn.MinLineProfit()
  local v = ES.db and ES.db.earnMinProfit
  return type(v) == "number" and v >= 0 and v or Earn.DEFAULT_MIN_LINE
end

-- Siguiente (o anterior, dir = -1) escalón del mínimo
function Earn.StepMinLineProfit(dir)
  local steps, cur = Earn.MIN_LINE_STEPS, Earn.MinLineProfit()
  local i = 1
  for k, v in ipairs(steps) do if v <= cur then i = k end end
  i = ((i - 1 + (dir or 1)) % #steps) + 1
  ES.db.earnMinProfit = steps[i]
  Earn:Clear()
  return steps[i]
end

-- Escalón del mínimo (1..#MIN_LINE_STEPS) del valor guardado, y fijarlo por escalón
-- (el deslizador de la cabecera)
function Earn.MinLineStep()
  local steps, cur = Earn.MIN_LINE_STEPS, Earn.MinLineProfit()
  local i = 1
  for k, v in ipairs(steps) do if v <= cur then i = k end end
  return i
end
function Earn.SetMinLineStep(i)
  local steps = Earn.MIN_LINE_STEPS
  i = math.max(1, math.min(#steps, math.floor((i or 1) + 0.5)))
  if ES.db.earnMinProfit == steps[i] then return false end
  ES.db.earnMinProfit = steps[i]
  Earn:Clear()
  return true
end

---------------------------------------------------------------------------
-- Tiempo: fabricar también cuesta. 577 Linen Bag al vendedor dejan ~5g, pero son
-- ~40 min de fabricar: farmeando se saca más (Discord). Las líneas de venta al
-- vendedor (las que pueden ser cientos de fabricaciones) se cortan a
-- VENDOR_TIME_BUDGET y no se proponen si dejan menos por hora que Earn.VendorMinGPH
-- (según tu nivel).
-- Es un criterio interno: no se enseña ni se ajusta (un deslizador y una cifra de
-- oro por hora complicaban la página más de lo que ayudaban)
---------------------------------------------------------------------------
Earn.VENDOR_TIME_BUDGET = 20 * 60 -- s de fabricar como mucho en una línea de vendedor

-- Segundos por fabricación de una receta (su lanzamiento en el juego + margen): la
-- misma cuenta que las rutas (Planner.CraftSeconds)
function Earn.CraftSeconds(recipeID) return ES.Planner.CraftSeconds(recipeID) end

-- Segundos de fabricar `crafts` de una idea con sus acciones (Planner.RecipeCost): sus
-- fabricaciones por su tiempo, y por cada intermedio que haces por el camino, SUS
-- fabricaciones (unidades entre las que da cada una, hacia arriba) por el tiempo de SU
-- receta (a.recipe es su id). Antes se sumaban las unidades con el tiempo de la receta
-- final: 20 Bolt que salen de 10 fabricaciones contaban como 20 de la receta final
local function IdeaSeconds(idea, crafts, actions)
  local secs = idea.craftSecs or Earn.CraftSeconds(idea.e.id)
  local recipes = idea.ctx and idea.ctx.data and idea.ctx.data.recipes or {}
  local total = (crafts or 0) * secs
  for _, a in ipairs(actions or {}) do
    if a.kind == "craft" and a.item ~= idea.itemID and (a.qty or 0) > 0 then
      local r = a.recipe and recipes[a.recipe]
      local per = math.max(1, r and r.out and r.out[2] or 1)
      local n = math.ceil(a.qty / per - 1e-6)
      total = total + n * (r and Earn.CraftSeconds(a.recipe) or secs)
    end
  end
  return total
end
Earn.IdeaSeconds = IdeaSeconds -- para pruebas

-- Tiempo de fabricar una idea (sus fabricaciones y las de lo intermedio que haces
-- por el camino) y el oro por hora que deja: idea.seconds, idea.gph (cobre/h)
function Earn.Timing(idea)
  idea.craftSecs = idea.craftSecs or Earn.CraftSeconds(idea.e.id)
  idea.seconds = IdeaSeconds(idea, idea.crafts or 0, idea.actions)
  idea.gph = idea.seconds > 0 and (idea.profit or 0) * 3600 / idea.seconds or nil
end

-- Venta al vendedor: lo mínimo que tiene que dejar por hora de fabricar (cobre/h),
-- según el nivel del personaje: lo que sacarías farmeando crece con el nivel. Con
-- 10g/h fijos, a nivel bajo no quedaba ninguna línea (revisión del 14/11). 20s/h por
-- nivel: nivel 10, 2g/h; nivel 37, ~7g/h (las 577 Linen Bag no salen); nivel 60, 12g/h
Earn.VENDOR_GPH_PER_LEVEL = 2000
function Earn.VendorMinGPH()
  if Earn.VENDOR_MIN_GPH then return Earn.VENDOR_MIN_GPH end -- (pruebas: fijo)
  local level = UnitLevel and UnitLevel("player") or 30
  if type(level) ~= "number" or level < 1 then level = 30 end
  return level * Earn.VENDOR_GPH_PER_LEVEL
end

-- ¿Compensa el tiempo? Solo se mira en la venta al vendedor (las de la AH son pocas
-- fabricaciones); las que no hay que fabricar, sí
function Earn.FastEnough(idea)
  if idea.sellWhere ~= "vendor" or not idea.gph then return true end
  return idea.gph >= Earn.VendorMinGPH()
end

-- Profesiones del personaje con datos
function Earn.MyProfessions()
  local list = {}
  for _, p in ipairs(ES.PROFESSIONS) do
    local data = ES.Data[p.key]
    if data and ES:GetProfessionSkill(data.skillLine) then list[#list + 1] = p.key end
  end
  return list
end

-- Cuántas fabricar y por qué
local function Batch(idea, e)
  if idea.sellWhere == "vendor" then
    return VENDOR_MAX, L["Se vende al vendedor: venta segura, sin límite de ventas."]
  end
  local onSale = math.floor((e.quantity or 0) / math.max(1, e.qty))
  local share = onSale > 0 and math.max(1, math.floor(onSale * AH_SHARE)) or TEST_BATCH
  local n, why
  if idea.verdict == "good" then
    n = math.min(MAX_BATCH, share)
    why = onSale > 0 and string.format(L["Hasta el %d%% de lo que hay a la venta (%d)."], AH_SHARE * 100, onSale)
      or L["No hay ninguno a la venta: unos pocos para probar."]
  else
    n = math.min(TEST_BATCH, share)
    why = L["Alertas de mercado dudosas: unos pocos para probar."]
  end
  -- Con TSM: no más de lo que se vende en toda la región en unos días (tu reino vende
  -- como mucho eso; los vendidos son unidades y aquí se cuentan fabricaciones)
  local d = idea.signals and idea.signals.demand
  if d and d.known then
    local days = ES.Market.TSM_SELL_DAYS
    local cap = math.max(1, math.ceil(d.sold * days / math.max(1, e.qty)))
    if cap < n then
      n = cap
      why = string.format(L["TSM: en la región se venden ~%s al día: como mucho lo que se vende en %d días."],
        ES.Market.Dec(d.sold), days)
    end
  end
  return math.max(1, n), why
end
Earn.Batch = Batch -- (pruebas)

---------------------------------------------------------------------------
-- Cantidad elegida por ti en una línea del lote (botones − y + de la fila): manda
-- sobre la recomendada hasta el siguiente escaneo (con precios nuevos vuelve a la
-- recomendada; si no, se quedaría una cantidad vieja para siempre).
--   ES.db.earnQty[itemID] = { n = fabricaciones que quieres tener, scan = escaneo }
---------------------------------------------------------------------------
Earn.MAX_CUSTOM = 200

local function ScanTime()
  local scan = ES.db.scans and ES.db.scans[ES:RealmKey()]
  return scan and scan.time or 0
end

function Earn.CustomQuantity(itemID)
  local o = type(ES.db.earnQty) == "table" and ES.db.earnQty[itemID]
  if o and o.scan == ScanTime() then return o.n end
  return nil
end

-- `idea`: una línea del lote; delta: +1, -1, +5... La cantidad es de fabricaciones a
-- hacer (lo que ya llevas hecho no cuenta); como mínimo 1. Si vuelve a la
-- recomendada, deja de estar elegida por ti
function Earn.StepQuantity(idea, delta)
  if type(ES.db.earnQty) ~= "table" then ES.db.earnQty = {} end
  local haveCrafts = math.floor((idea.have or 0) / math.max(1, idea.e.qty))
  local crafts = math.max(1, math.min(Earn.MAX_CUSTOM, (idea.crafts or 1) + delta))
  local wanted = crafts + haveCrafts
  local scanTime = ScanTime()
  -- (lo que se pasó de escaneos anteriores, fuera)
  for id, o in pairs(ES.db.earnQty) do if o.scan ~= scanTime then ES.db.earnQty[id] = nil end end
  if wanted == (idea.recommended or idea.wanted) and idea.custom then
    ES.db.earnQty[idea.e.itemID] = nil
  else
    ES.db.earnQty[idea.e.itemID] = { n = wanted, scan = scanTime }
  end
  Earn:Clear(true) -- (solo las ideas: los costes de las recetas no cambian)
end

-- ¿Cabe lo comprado en la AH (en `extra`, con clave itemID) en lo que hay a la venta,
-- contando lo que ya compran otras líneas (ctx.used)? Con ignoreSupply, lo que pasa
-- de ahí se pagaría a la mediana: para el vendedor no vale, esas subastas no existen
local function WithinSupply(ctx, extra)
  for key, q in pairs(extra or {}) do
    if type(key) == "number" and key > 0 then
      local supply = ctx.supply[key]
      if supply and (ctx.used[key] or 0) + q > supply + 1e-6 then return false end
    end
  end
  return true
end

-- Venta al vendedor: el vendedor compra todas, así que el límite lo pone la escalera
-- de los materiales. Se fabrica mientras la SIGUIENTE (no la media) deje al menos
-- MIN_PROFIT y MIN_MARGIN sobre lo que cuesta, y sus materiales sigan a la venta.
-- Cada fabricación cuesta igual o más que la anterior (se sube por la escalera), así
-- que se busca por bisección la última que compensa. Devuelve cuántas, por qué se
-- para ("margin", "supply" o "max") y el coste { cost, reagents, extra, actions }.
local function VendorCrafts(idea)
  local ctx, recipe, memo = idea.ctx, idea.e.recipe, {}
  local function At(n)
    if n == 0 then return { cost = 0 } end
    local r = memo[n]
    if not r then
      r = {}
      r.cost, r.reagents, r.extra, r.actions = ES.Planner.RecipeCost(ctx, recipe, n, {})
      memo[n] = r
    end
    return r
  end
  local function Fits(n)
    local cur, prev = At(n), At(n - 1)
    if not cur.cost or not prev.cost then return false, "supply" end
    if not WithinSupply(ctx, cur.extra) then return false, "supply" end
    local marginal = cur.cost - prev.cost
    if idea.sale - marginal < math.max(MIN_PROFIT, MIN_MARGIN * marginal) then return false, "margin" end
    return true
  end
  local ok, why = Fits(1)
  if not ok then return 0, why, { cost = 0 } end
  -- Tope: lo que cabe en VENDOR_TIME_BUDGET de fabricar (577 Linen Bag eran ~40 min),
  -- con lo intermedio: los segundos por fabricación de la idea entera (lo mismo que
  -- mide Earn.Timing), medidos en el tope que saldría sin lo intermedio (en 1, el
  -- redondeo de un intermedio que da 2 contaría una fabricación entera)
  local own = idea.craftSecs or DEFAULT_CAST
  local max = math.min(VENDOR_MAX, math.max(1, math.floor(Earn.VENDOR_TIME_BUDGET / own)))
  local ref = At(max).cost and max or 1
  local perCraft = IdeaSeconds(idea, ref, At(ref).actions) / ref
  if perCraft > own then
    max = math.min(max, math.max(1, math.floor(Earn.VENDOR_TIME_BUDGET / perCraft)))
  end
  if Fits(max) then return max, max < VENDOR_MAX and "time" or "max", At(max) end
  local lo, hi = 1, max
  while hi - lo > 1 do
    local mid = math.floor((lo + hi) / 2)
    if Fits(mid) then lo = mid else hi = mid end
  end
  local _, stop = Fits(hi)
  return lo, stop, At(lo)
end

-- Coste de una idea para las fabricaciones que quiere (idea.wanted), descontando
-- lo que ya llevas fabricado. El coste de 1 es el de las subastas más baratas;
-- para N hay que subir por la escalera: si a N ya no compensa, se reduce a la mitad.
function Earn.CostIdea(idea)
  local e = idea.e
  idea.have = ES:ItemCount(e.itemID)
  idea.craftSecs = idea.craftSecs or Earn.CraftSeconds(e.id)
  if idea.sellWhere == "vendor" then
    -- Lo que ya llevas también se lo vendes: no quita fabricaciones
    local n, limit, at = VendorCrafts(idea)
    idea.crafts, idea.limit, idea.why2, idea.fewer = n, limit, nil, nil
    idea.invest = at.cost or 0
    idea.profit = idea.sale * n - idea.invest
    idea.reagents, idea.extra, idea.actions = at.reagents or {}, at.extra or {}, at.actions
    Earn.Timing(idea)
    return
  end
  local haveCrafts = math.floor(idea.have / math.max(1, e.qty))
  local n = math.max(0, idea.wanted - haveCrafts)
  idea.why2 = haveCrafts > 0 and not idea.cooldown and string.format(L["Ya tienes %d: se fabrican solo las que faltan."], idea.have) or nil
  if n == 0 then
    idea.crafts, idea.invest, idea.profit, idea.reagents, idea.extra = 0, 0, 0, {}, {}
    idea.seconds, idea.gph = 0, nil
    return
  end
  local cost, reagents, extra, actions = ES.Planner.RecipeCost(idea.ctx, e.recipe, n, {})
  local start = n
  -- (cost es el de las n juntas: el margen se mide sobre él, el mínimo por fabricación).
  -- La cantidad elegida por ti no se reduce: se enseña lo que deja, aunque sea poco
  while not idea.custom and n > 1 and (not cost or idea.sale * n - cost < math.max(MIN_PROFIT * n, MIN_MARGIN * cost)) do
    n = math.max(1, math.floor(n / 2))
    cost, reagents, extra, actions = ES.Planner.RecipeCost(idea.ctx, e.recipe, n, {})
  end
  idea.fewer = n < start
  idea.crafts = n
  idea.invest = cost or e.cost * n
  idea.profit = idea.sale * n - idea.invest
  idea.reagents, idea.extra = reagents or e.reagents, extra or {}
  -- Lo que de verdad se compra: también los materiales de lo que fabricas tú por el
  -- camino (Bolt of Mageweave -> su Mageweave Cloth), no solo los de la receta
  idea.actions = actions
  Earn.Timing(idea)
end

-- Lo que deja una línea del lote: el beneficio de sus fabricaciones; si ya las
-- tienes hechas (no hay que fabricar), lo que dejan las que llevas
function Earn.LineValue(idea)
  if idea.sellWhere == "vendor" then return idea.profit or 0 end
  if idea.crafts and idea.crafts > 0 then return idea.profit or 0 end
  return (idea.e.profit or 0) * math.floor((idea.have or 0) / math.max(1, idea.e.qty))
end

-- Todas las ideas, ordenadas por puntuación. Caché por escaneo, reputación,
-- ventas propias y día (las recetas conocidas cambian poco; se vacía en RefreshAllViews).
local cache
-- Lo caro (Planner:RecipeMarket: el coste de cada receta, ~10 ms por profesión) no
-- depende de tus bolsas: se guarda por profesión hasta otro escaneo, otra reputación,
-- otra AH o el historial nuevo. Cambiar las bolsas (cada fabricación) solo rehace las
-- ideas (~2 ms): antes se rehacía todo, ~20 ms por fabricación con la profesión abierta.
-- `keepMarket`: solo las ideas (bolsas, cantidades); sin él, todo (aprendes una receta,
-- escaneo nuevo...)
local marketMemo = {}
ES.MemPart("Ganar dinero: ideas y costes por profesión", function() return { cache, marketMemo } end)
function Earn:Clear(keepMarket)
  cache = nil
  if not keepMarket then marketMemo = {} end
end

local function RecipeMarketFor(profKey, data, scan)
  -- Icono de misión de la profesión desactivado: tampoco se proponen las recetas de
  -- misión ni las de instructor que piden antes una misión que no has hecho (spec
  -- recipe-requirements); lo desbloqueado va en la clave
  local settings = ES.db.prof and ES.db.prof[profKey]
  local noQuests = settings and settings.useQuests == false or nil
  local key = table.concat({ scan and scan.time or 0, ES:RealmKey(), ES.repStamp or "", tostring(ES:IsNeutralAH()),
    ES.Market:Index().stamp or "", ES.SpecStamp and ES:SpecStamp() or "", tostring(noQuests),
    ES.Planner.UnlockStamp(data) }, ":")
  local m = marketMemo[profKey]
  if m and m.key == key then
    m.ctx.used = {} -- (lo que compró el lote anterior no cuenta: se vuelve a repartir)
    return m.entries, m.ctx
  end
  local entries, ctx = ES.Planner:RecipeMarket(data, {
    hours = 24, neutral = ES:IsNeutralAH(), noQuests = noQuests,
    sourcedScrolls = ES.Waypoints.SOURCED_PROFESSIONS[profKey] or nil,
    -- Lo intermedio, solo con recetas que sabes: lo que no sepas hacer se compra hecho
    knownProducers = true,
  })
  -- (si faltaba algún precio de vendedor, se guarda igual y se tira cuando el juego
  -- mande objetos: abajo. Sin guardar, un objeto que no llegue nunca la dejaba sin caché)
  marketMemo[profKey] = { key = key, entries = entries, ctx = ctx, pending = ctx.pendingInfo }
  return entries, ctx
end
do
  local f = CreateFrame("Frame")
  ES.SafeRegister(f, "GET_ITEM_INFO_RECEIVED")
  f:SetScript("OnEvent", function()
    for profKey, m in pairs(marketMemo) do
      if m.pending then marketMemo[profKey] = nil cache = nil end
    end
  end)
end
-- Lo que llevas cambia cuántas hay que fabricar
do
  local f = CreateFrame("Frame")
  ES.SafeRegister(f, "BAG_UPDATE_DELAYED")
  f:SetScript("OnEvent", function() cache = nil end)
end

-- De lo que hay que comprar (Earn.Shopping), lo que ya tienes (bolsas, y lo comprado
-- que viene por correo: lo mismo que descuenta la Lista de compra) y lo que vale:
-- { value, items = { { itemID, n, value } } }. Solo informa de lo que pagarás de
-- verdad: el beneficio sigue contando tus materiales a precio de la AH (venderlos es
-- la alternativa; contarlos gratis hacía rentable gastar materiales caros en cosas
-- que valen menos). Se calcula al pintar: las bolsas cambian y las ideas van en caché
function Earn.FromBags(shopping)
  local res = { value = 0, items = {} }
  for _, n in ipairs(shopping or {}) do
    if n.source == "ah" or n.source == "vendor" then
      local have = (ES.HaveForShopping and ES:HaveForShopping(n.itemID)) or ES:ItemCount(n.itemID) or 0
      local use = math.min(have, math.ceil((n.quantity or 0) - 0.001))
      if use > 0 then
        local v = use * (n.unit or 0)
        res.value = res.value + v
        res.items[#res.items + 1] = { itemID = n.itemID, n = use, value = v }
      end
    end
  end
  table.sort(res.items, function(a, b) return a.value > b.value end)
  return res
end

-- Lo que hay que comprar (AH y vendedor) para unas ideas ya costeadas, juntando cada
-- material: { itemID, quantity, total, source, unit }, de más a menos caro
function Earn.Shopping(ideas)
  local need, list = {}, {}
  local function Need(itemID, source, qty, cost)
    local n = need[itemID]
    if not n then
      n = { itemID = itemID, quantity = 0, total = 0, source = source }
      need[itemID] = n
    end
    n.quantity = n.quantity + qty
    n.total = n.total + cost
  end
  for _, idea in ipairs(ideas) do
    if idea.actions then
      -- Las compras (AH y vendedor) de todas sus fabricaciones, también las de los
      -- materiales que fabricas tú (un Bolt of Mageweave se compra como Mageweave Cloth)
      for _, a in ipairs(idea.actions) do
        if a.kind == "ah" or a.kind == "vendor" then Need(a.item, a.kind, a.qty, a.cost or 0) end
      end
    else
      -- idea.reagents ya va para todas sus fabricaciones
      for _, rg in ipairs(idea.reagents or {}) do
        Need(rg.item, rg.kinds.ah and "ah" or rg.kinds.vendor and "vendor" or "craft", rg.qty, rg.cost)
      end
    end
  end
  for _, n in pairs(need) do
    n.unit = n.total / math.max(1, n.quantity)
    list[#list + 1] = n
  end
  table.sort(list, function(a, b) return a.total > b.total end)
  return list
end

-- Recetas que no sabes pero puedes conseguir (instructor, vendedor, pergamino en la
-- AH o en tus bolsas, misión, Merchant's Favor) y darían beneficio: para decidir qué
-- aprender. Las de origen desconocido o con reputación que no tienes, no.
local LEARNABLE = { trainer = true, vendor = true, scroll = true, ah = true, quest = true, owned = true, favor = true }
-- Al vendedor no hay tope de ventas (VendorCrafts): para decidir si una receta que no
-- sabes llega al mínimo se cuentan estas fabricaciones, sin costear la escalera
local LEARN_VENDOR_CRAFTS = 20
-- Subastas que tiene que haber de lo fabricado para creerse su precio. Con menos, no
-- se sabe si es el precio ni si hay mercado (CurseForge: Mooncloth Shoulders a 350g
-- por una sola subasta, como receta para aprender). Con datos de TSM vale lo que diga
-- TSM (demanda y venta media)
Earn.LEARN_MIN_LISTINGS = 3

-- Añade `e` (de Planner:RecipeMarket) a res.learnable si da beneficio: el mismo
-- margen que las que sabes y, con lo más que se fabricaría en una línea (MAX_BATCH;
-- al vendedor, LEARN_VENDOR_CRAFTS), llega al mínimo. Lo que cuesta aprenderla no se resta:
-- se dice en cuántas fabricaciones se paga
-- `cooldown`: receta con enfriamiento (Mooncloth): una al día, así que se cuenta 1
-- fabricación y lo que cuesta aprenderla se recupera en días
function Earn.AddLearnable(res, e, profKey, rank, minLine, cooldown)
  if not (e.cost and e.profit and e.profit >= math.max(MIN_PROFIT, e.cost * MIN_MARGIN)) then return end
  if cooldown and e.sellWhere ~= "ah" then return end
  local idea = { e = e, profKey = profKey, itemID = e.itemID, sellWhere = e.sellWhere, learnable = true,
    need = e.learn or 1, rank = rank, cooldown = cooldown or nil }
  if idea.sellWhere == "ah" then
    local s = ES.Market:Signals(e.itemID)
    idea.verdict = s.verdict
    if idea.verdict == "avoid" then return end
    -- Aprenderla cuesta oro: con TSM, ni las que se venden poco en la región ni las que
    -- allí se venden muy por debajo del precio con el que contamos (Discord: Frost
    -- Tunic, 0,82 al día y 48s de media frente a 3g50)
    if s.demand.flag or ES.Market.TSMLowPrice(s, e.ahPrice or e.ahMin) then return end
    -- Sin TSM, con muy pocas subastas no hay mercado del que fiarse
    if not s.demand.known and (e.listings or 0) < Earn.LEARN_MIN_LISTINGS then return end
  end
  if e.profit * (cooldown and 1 or idea.sellWhere == "ah" and MAX_BATCH or LEARN_VENDOR_CRAFTS) < minLine then return end
  idea.canLearn = rank >= idea.need
  idea.payback = (e.learnCost or 0) > 0 and math.ceil(e.learnCost / e.profit) or nil
  res.learnable[#res.learnable + 1] = idea
end

-- Recetas que quitaste de Ganar dinero con la ✕ de su fila (Discord: proponía recetas
-- con enfriamiento y de cocina que piden una estación cara). ES.db.earnHidden[receta]
function Earn.IsHidden(id)
  return ES.db.earnHidden ~= nil and ES.db.earnHidden[id] == true
end

function Earn.SetHidden(id, hidden)
  ES.db.earnHidden = ES.db.earnHidden or {}
  ES.db.earnHidden[id] = hidden and true or nil
  if not next(ES.db.earnHidden) then ES.db.earnHidden = nil end
  Earn:Clear(true) -- (se vuelve a hacer el lote sin ellas; los precios no cambian)
end

-- Las quitadas, con su nombre: { { id, name } }, por nombre
function Earn.HiddenList()
  local list = {}
  for id in pairs(ES.db.earnHidden or {}) do
    local name
    for _, p in ipairs(ES.PROFESSIONS or {}) do
      local r = ES.Data[p.key] and ES.Data[p.key].recipes and ES.Data[p.key].recipes[id]
      if r then name = r.name end
    end
    list[#list + 1] = { id = id, name = name or ("#" .. id) }
  end
  table.sort(list, function(a, b) return a.name < b.name end)
  return list
end

function Earn:Ideas()
  local scan = ES.db.scans and ES.db.scans[ES:RealmKey()]
  local minLine = Earn.MinLineProfit()
  local stamp = table.concat({ scan and scan.time or 0, ES:RealmKey(), ES.repStamp or "", minLine,
    ES.SpecStamp and ES:SpecStamp() or "" }, ":")
  -- (y si una con enfriamiento ya está lista desde entonces, otra vez)
  if cache and cache.stamp == stamp and not (cache.cdNext and time() >= cache.cdNext) then return cache end
  local res = { stamp = stamp, ideas = {}, avoided = {}, vendor = {}, learnable = {}, scanTime = scan and scan.time, profs = Earn.MyProfessions(), known = 0,
    minLine = minLine, hidden = 0, removed = 0, cdProfit = {} }
  for _, profKey in ipairs(res.profs) do
    local data = ES.Data[profKey]
    local rank = ES:GetProfessionSkill(data.skillLine) or 0
    local entries, ctx = RecipeMarketFor(profKey, data, scan)
    for _, e in ipairs(entries) do
      -- Recetas con enfriamiento (transmutaciones, tela lunar): una al día, no un lote de
      -- 20. Si está lista (o no se sabe) y se vende en la AH, entra en el lote con 1
      -- fabricación; en marcha, solo en su sección (Enfriamientos)
      local cooldown = e.recipe and ES.Planner.Cooldown(e.recipe, e.id)
      local cdLeft = cooldown and Earn.CooldownLeft(e.id)
      if cooldown and e.profit then res.cdProfit[e.id] = e.profit end
      local usable = not cooldown or (e.sellWhere == "ah" and not (cdLeft and cdLeft > 0))
      if cooldown and cdLeft and cdLeft > 0 then
        res.cdNext = math.min(res.cdNext or math.huge, time() + math.ceil(cdLeft))
      end
      if Earn.IsHidden(e.id) then
        res.removed = res.removed + 1
      elseif LEARNABLE[e.learnSource] then
        Earn.AddLearnable(res, e, profKey, rank, minLine, cooldown)
      elseif e.learnSource == "known" then
        res.known = res.known + 1
        if usable and e.cost and e.profit and e.profit >= math.max(MIN_PROFIT, e.cost * MIN_MARGIN) then
          local idea = { e = e, profKey = profKey, itemID = e.itemID, sellWhere = e.sellWhere, unitCost = e.cost,
            cooldown = cooldown or nil, cdUnknown = cooldown and cdLeft == nil or nil }
          if idea.sellWhere == "ah" then
            idea.signals = ES.Market:Signals(e.itemID)
            idea.verdict = idea.signals.verdict
            idea.price = ES.Market.ListPrice(e.fair) or 1
            -- Con TSM: lo que en la región se vende poco (ventas al día o tasa de venta por
            -- debajo de los mínimos) o muy por debajo del precio con el que contamos no entra
            -- en el lote: va con las de "evitar" (Discord: Shadoweave Boots a ~2 al día y
            -- 0,14 de tasa, en el lote de hoy)
            local s = idea.signals
            if s.demand.flag or ES.Market.TSMLowPrice(s, e.ahPrice or e.ahMin) then idea.tsmAvoid = true end
          end
          if idea.verdict == "avoid" or idea.tsmAvoid then
            -- (sin costear: con lo más que se fabricaría, ¿llegaría al mínimo?)
            if e.profit * (cooldown and 1 or MAX_BATCH) >= minLine then
              res.avoided[#res.avoided + 1] = idea
            else
              res.hidden = res.hidden + 1
            end
          elseif cooldown then
            -- La de hoy: 1 fabricación aunque ya lleves alguna hecha (el enfriamiento se
            -- pierde si no se usa), sin botones de cantidad
            idea.ctx = ctx
            idea.wanted = math.floor(ES:ItemCount(e.itemID) / math.max(1, e.qty)) + 1
            idea.why = L["receta con enfriamiento, una cada vez."]
            idea.sale = e.ahNet * e.qty
          else
            idea.ctx = ctx
            idea.wanted, idea.why = Batch(idea, e)
            -- La que elegiste tú (botones de la fila), hasta el siguiente escaneo
            local custom = idea.sellWhere == "ah" and Earn.CustomQuantity(e.itemID)
            if custom then
              idea.recommended, idea.wanted, idea.custom = idea.wanted, custom, true
            end
            idea.sale = (idea.sellWhere == "ah" and e.ahNet or e.vendor) * e.qty -- por fabricación
          end
          if idea.sellWhere == "vendor" then
            -- Se costea después del lote (con lo que el lote ya compra)
            res.vendor[#res.vendor + 1] = idea
          elseif idea.verdict ~= "avoid" and not idea.tsmAvoid then
            Earn.CostIdea(idea)
            -- (la que elegiste tú se queda aunque baje del mínimo: si no, desaparecía al pulsar −)
            if idea.custom or Earn.LineValue(idea) >= minLine then
              idea.score = idea.profit * ((idea.verdict == "watch" or idea.verdict == "unknown") and WATCH_WEIGHT or 1)
              res.ideas[#res.ideas + 1] = idea
            else
              res.hidden = res.hidden + 1
            end
          end
        end
      end
    end
  end
  -- (las de cantidad elegida por ti, delante: si no, al pulsar − podían salirse del lote)
  -- (y las de enfriamiento listas: son una al día y ocupan poco, que no las desplacen)
  table.sort(res.ideas, function(a, b)
    if (a.custom or false) ~= (b.custom or false) then return a.custom == true end
    if (a.cooldown or false) ~= (b.cooldown or false) then return a.cooldown == true end
    return a.score > b.score
  end)
  table.sort(res.avoided, function(a, b) return a.e.profit > b.e.profit end)
  -- Primero las que ya puedes aprender; luego, de más a menos beneficio por fabricación
  table.sort(res.learnable, function(a, b)
    if a.canLearn ~= b.canLearn then return a.canLearn end
    return a.e.profit > b.e.profit
  end)

  -- Lote de hoy: de mejor a peor, cada receta se vuelve a costear contando lo que
  -- ya compran las anteriores (si dos usan el mismo material, la segunda paga las
  -- subastas siguientes, más caras).
  res.batch, res.invest, res.profit = {}, 0, 0
  local ctxs = {}
  for _, idea in ipairs(res.ideas) do ctxs[idea.ctx] = true end
  for _, idea in ipairs(res.vendor) do ctxs[idea.ctx] = true end
  for ctx in pairs(ctxs) do ctx.used = {} end
  for _, idea in ipairs(res.ideas) do
    if #res.batch >= BATCH_SIZE then break end
    Earn.CostIdea(idea)
    -- (con los materiales que ya compran las anteriores puede quedarse por debajo del mínimo)
    if idea.custom or ((idea.crafts == 0 or idea.profit > 0) and Earn.LineValue(idea) >= minLine) then
      res.batch[#res.batch + 1] = idea
      idea.inBatch = true
      res.invest = res.invest + idea.invest
      res.profit = res.profit + idea.profit
      -- Lo que compra esta receta ya no está para las siguientes (en todas las profesiones)
      for key, q in pairs(idea.extra or {}) do
        if type(key) == "number" and key > 0 then
          for ctx in pairs(ctxs) do ctx.used[key] = (ctx.used[key] or 0) + q end
        end
      end
    end
  end
  -- Orden fijo en la pantalla hasta el siguiente escaneo: el de la primera vez que sale
  -- cada línea. Al pulsar − o + cambia su beneficio y su puesto, y la fila saltaba de
  -- sitio: había que ir persiguiéndola (Discord). Lo de arriba (quién paga las subastas
  -- más baratas) sigue por puntuación; esto solo ordena lo que se ve
  local scanTime = ScanTime()
  local order = Earn.batchOrder
  if not order or order.scan ~= scanTime then
    order = { scan = scanTime, rank = {}, n = 0 }
    Earn.batchOrder = order
  end
  for _, idea in ipairs(res.batch) do
    local id = idea.e.itemID
    if not order.rank[id] then order.n = order.n + 1 order.rank[id] = order.n end
  end
  table.sort(res.batch, function(a, b) return order.rank[a.e.itemID] < order.rank[b.e.itemID] end)
  res.shopping = Earn.Shopping(res.batch)

  -- Venta al vendedor (venta segura): aparte del lote, cada línea por su cuenta con
  -- lo que el lote ya compra; si dos usan los mismos materiales, cada una se calcula
  -- como si fuera la única (se elige una)
  local vendor = res.vendor
  res.vendor = {}
  for _, idea in ipairs(vendor) do
    Earn.CostIdea(idea)
    if idea.crafts > 0 and Earn.LineValue(idea) >= minLine and Earn.FastEnough(idea) then
      idea.shopping = Earn.Shopping({ idea })
      res.vendor[#res.vendor + 1] = idea
    elseif idea.crafts > 0 and Earn.LineValue(idea) >= minLine then
      -- (no compensa el tiempo: no se cuenta en "por debajo del mínimo", que habla
      -- del beneficio mínimo de la cabecera)
      res.slow = (res.slow or 0) + 1
    else
      res.hidden = res.hidden + 1
    end
  end
  table.sort(res.vendor, function(a, b) return a.profit > b.profit end)
  cache = res
  return res
end

---------------------------------------------------------------------------
-- Enfriamientos (transmutaciones, tela lunar: Planner.Cooldown). ¿Está lista hoy?
-- Forever da el enfriamiento de una receta con C_TradeSkillUI.GetRecipeCooldown (lo
-- que usa TSM), pero solo es de fiar con su profesión abierta. Se lee al abrirla y al
-- fabricar, y se guarda por personaje:
--   ES.charData.cdReady[receta] = time() en que estará lista (pasada: lista)
-- Con la profesión cerrada se mira también el enfriamiento del hechizo (si el juego lo
-- da). Si nunca se ha visto, no se sabe: el lote la propone y lo dice (al pulsar la
-- fila se abre la profesión y se sabe).
---------------------------------------------------------------------------
local function CDStore()
  if type(ES.charData) ~= "table" then return nil end
  if type(ES.charData.cdReady) ~= "table" then ES.charData.cdReady = {} end
  return ES.charData.cdReady
end

-- GetTime cuenta desde que arrancó el ordenador, en milisegundos de 32 bits. Si el
-- enfriamiento empezó antes (reiniciaste el PC después de transmutar), el juego da su
-- inicio desbordado: 2^32 ms (unas 1193 h) más tarde de lo que es. Salía "Listo en
-- 1195 h" con 59 min de verdad (Arcanite Bar)
local GETTIME_WRAP = 2 ^ 32 / 1000
-- Ningún enfriamiento de profesión dura tanto: lo guardado más lejos es de antes de
-- arreglar el desbordamiento (y no se fía)
local MAX_COOLDOWN = 30 * 86400

-- Enfriamiento del hechizo de la receta: segundos que faltan, o nil si no da uno
local function SpellCooldownLeft(id)
  local start, duration
  if C_Spell and C_Spell.GetSpellCooldown then
    local ok, info = pcall(C_Spell.GetSpellCooldown, id)
    if ok and type(info) == "table" then start, duration = info.startTime, info.duration end
  elseif GetSpellCooldown then
    local ok, s, d = pcall(GetSpellCooldown, id)
    if ok then start, duration = s, d end
  end
  -- (más de 2 s: el tiempo global de lanzamiento no cuenta)
  if type(start) == "number" and type(duration) == "number" and start > 0 and duration > 2 then
    local now = GetTime()
    if start - now > GETTIME_WRAP / 2 then start = start - GETTIME_WRAP end
    return math.max(0, start + duration - now)
  end
end

-- Segundos que faltan para poder fabricarla (0: lista) o nil si no se sabe
function Earn.CooldownLeft(id)
  local store = CDStore()
  local spell = SpellCooldownLeft(id)
  if spell and spell > 0 then
    if store then store[id] = time() + math.floor(spell) end
    return spell
  end
  local ready = store and store[id]
  if not ready then return nil end
  if ready - time() > MAX_COOLDOWN then store[id] = nil return nil end
  return math.max(0, ready - time())
end

-- Las recetas con enfriamiento de una profesión (son pocas y no cambian: una vez) y,
-- de ellas, las que sabes: { [id] = receta }. (Antes se miraban todas las recetas de la
-- profesión en cada TRADE_SKILL_LIST_UPDATE, que llega en cada fabricación)
local cdRecipes = {}
local function KnownCooldowns(profKey)
  local all = cdRecipes[profKey]
  if not all then
    all = {}
    local data = ES.Data[profKey]
    for id, r in pairs(data and data.recipes or {}) do
      if ES.Planner.Cooldown(r, id) then all[id] = r end
    end
    cdRecipes[profKey] = all
  end
  local list = {}
  for id, r in pairs(all) do
    if ES:IsRecipeKnown(id) then list[id] = r end
  end
  return list
end
function Earn.ResetCooldownRecipes() cdRecipes = {} end -- (pruebas: datos cambiados a mano)

-- Recetas de una profesión que sabes y están en enfriamiento ahora (se sabe que no
-- están listas): la ruta no las propone (Discord: pedía Mooncloth con ella en
-- enfriamiento). Las que no se sabe si están listas sí. Lista de ids en orden fijo
-- (para la clave de la ruta: ES:StableRouteKey)
function Earn.OnCooldown(profKey)
  local list = {}
  for id in pairs(KnownCooldowns(profKey)) do
    local left = Earn.CooldownLeft(id)
    if left and left > 0 then list[#list + 1] = id end
  end
  table.sort(list)
  return list
end

-- Con la profesión abierta: guarda el enfriamiento de sus recetas. true si cambió
-- si alguna está lista o no
function Earn.ReadCooldowns(profKey)
  local T = C_TradeSkillUI
  local store = CDStore()
  if not (profKey and store and T and T.GetRecipeCooldown) then return false end
  local now, changed = time(), false
  for id in pairs(KnownCooldowns(profKey)) do
    local ok, cd, _, charges, maxCharges = pcall(T.GetRecipeCooldown, id)
    if ok then
      if (maxCharges or 0) > 0 and (charges or 0) > 0 then cd = nil end -- (con cargas: lista)
      local ready = now + math.floor(cd or 0)
      local was = store[id]
      if was == nil or (was > now) ~= (ready > now) then changed = true end
      store[id] = ready
    end
  end
  return changed
end

do
  local f = CreateFrame("Frame")
  local pendingRead = false
  local function Read()
    local prof = ES.CraftWindow and ES.CraftWindow.OpenProfession and ES.CraftWindow.OpenProfession()
    if prof and Earn.ReadCooldowns(prof) then
      Earn:Clear(true)
      if ES.RenderEarn then pcall(ES.RenderEarn, ES) end
      if ES.CraftWindow and ES.CraftWindow.Refresh then pcall(ES.CraftWindow.Refresh, ES.CraftWindow) end
      -- (y la ruta: una receta en enfriamiento no se propone, ver Earn.OnCooldown)
      if ES.RefreshAfterCooldown then pcall(ES.RefreshAfterCooldown, ES, prof) end
    end
  end
  ES.SafeRegister(f, "TRADE_SKILL_SHOW")
  ES.SafeRegister(f, "TRADE_SKILL_LIST_UPDATE")
  -- (solo tus lanzamientos: con todas las unidades llegaba uno por cada hechizo de cualquiera a tu alrededor)
  if not (f.RegisterUnitEvent and pcall(f.RegisterUnitEvent, f, "UNIT_SPELLCAST_SUCCEEDED", "player")) then ES.SafeRegister(f, "UNIT_SPELLCAST_SUCCEEDED") end
  f:SetScript("OnEvent", function(_, event, unit, _, spellID)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
      -- Fabricaste una con enfriamiento: ya no está lista (el juego tarda un poco en dar
      -- el enfriamiento nuevo: se vuelve a leer después)
      if unit ~= "player" or not spellID then return end
      local store = CDStore()
      local r
      for _, p in ipairs(ES.PROFESSIONS or {}) do
        r = r or (ES.Data[p.key] and ES.Data[p.key].recipes and ES.Data[p.key].recipes[spellID])
      end
      if not (r and store and ES.Planner.Cooldown(r, spellID)) then return end
      store[spellID] = time() + 3600 -- (provisional, hasta leer el de verdad)
      Earn:Clear(true)
      if ES.RenderEarn then pcall(ES.RenderEarn, ES) end
      if C_Timer then C_Timer.After(1, Read) end
      return
    end
    -- (TRADE_SKILL_LIST_UPDATE llega muchas veces seguidas: una lectura para todas)
    if not C_Timer then Read() return end
    if pendingRead then return end
    pendingRead = true
    C_Timer.After(0.3, function() pendingRead = false Read() end)
  end)
end

-- Recetas con enfriamiento que sabes: cuándo están listas y qué dejan
function Earn:Cooldowns()
  local list = {}
  local res = cache
  for _, profKey in ipairs(Earn.MyProfessions()) do
    for id, r in pairs(KnownCooldowns(profKey)) do
      local left = Earn.CooldownLeft(id)
      local inBatch = false
      for _, idea in ipairs(res and res.batch or {}) do if idea.e.id == id then inBatch = true end end
      list[#list + 1] = { recipe = r, id = id, profKey = profKey, ready = left == 0, unknown = left == nil,
        left = left or 0, profit = res and res.cdProfit and res.cdProfit[id], inBatch = inBatch }
    end
  end
  -- (listas primero; luego las que antes estarán)
  table.sort(list, function(a, b)
    if a.unknown ~= b.unknown then return not a.unknown end
    if a.left ~= b.left then return a.left < b.left end
    return (a.recipe.name or "") < (b.recipe.name or "")
  end)
  return list
end

-- Materiales de profesiones en tus bolsas que no usa ninguna receta que sabes:
-- candidatos a vender (precio de la AH y del vendedor)
local function BagItems()
  local items = {}
  local numSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
  local itemID = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID
  if not numSlots or not itemID then return items end
  for _, bag in ipairs(ES.CarriedBags()) do
    for slot = 1, numSlots(bag) or 0 do
      local id = itemID(bag, slot)
      if id then items[id] = true end
    end
  end
  return items
end

function Earn:Leftovers()
  local used = {}
  for _, profKey in ipairs(Earn.MyProfessions()) do
    local data = ES.Data[profKey]
    ES.Planner.Annotate(data)
    for id, r in pairs(data.recipes) do
      if ES:IsRecipeKnown(id) then
        for _, rq in ipairs(r.r) do used[rq[1]] = true end
      end
    end
  end
  local scan = ES.db.scans and ES.db.scans[ES:RealmKey()]
  local list, hidden = {}, 0
  local minLine = Earn.MinLineProfit()
  for id in pairs(BagItems()) do
    if not used[id] and ES.History:IsTracked(id) then
      local count = ES:ItemCount(id)
      local ah = scan and scan.items[id]
      local vendor = ES:VendorSellPrice(id) or 0
      -- En la AH, al precio realista (si el mínimo está inflado, el de los últimos días)
      local fair = ah and ES.Market:FairPrice(id, ah.minUnit)
      local ahPrice = fair and ES.Market.ListPrice(fair)
      local best = math.max(vendor, ahPrice and ahPrice * 0.95 or 0) -- 5% de comisión
      if best > 0 and best * count >= minLine then
        list[#list + 1] = { itemID = id, count = count, ahPrice = ahPrice, fair = fair, vendor = vendor, value = best * count }
      elseif best > 0 then
        hidden = hidden + 1
      end
    end
  end
  table.sort(list, function(a, b) return a.value > b.value end)
  return list, hidden
end
