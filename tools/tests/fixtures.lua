-- Datos de prueba fijos: lo guardado en tres estados y los precios de la AH.
--   Fixtures.State("empty")  usuario nuevo: nada guardado, sin escaneo
--   Fixtures.State("scan")   un escaneo de la AH y nada más
--   Fixtures.State("full")   escaneo, recetas aprendidas, profesiones con nivel,
--                            cálculos, y tras arrancar: historial y lista de compra
--
-- Los precios no se escriben a mano para miles de objetos: salen de una regla fija por
-- objeto (Fixtures.Price). Unos pocos tienen precio a mano (Fixtures.FIXED) para las
-- cuentas que las pruebas comprueban "como hechas a mano".

Fixtures = {}

-- Precios a mano (cobre por unidad)
Fixtures.FIXED = {
  [2318] = 25,    -- Light Leather
  [2319] = 60,    -- Medium Leather
  [2589] = 15,    -- Linen Cloth
  [2592] = 40,    -- Wool Cloth
  [2770] = 30,    -- Copper Ore
  [2840] = 50,    -- Copper Bar
  [765] = 20,     -- Silverleaf
  [2447] = 25,    -- Peacebloom
  [2672] = 30,    -- Stringy Wolf Meat
}

-- Regla fija: más caro que el vendedor (así el vendedor sale mejor cuando vende el
-- objeto), y si no lo vende, a partir de lo que paga el vendedor por él, o del número
-- del objeto. Siempre un entero > 0
function Fixtures.Price(itemID)
  local fixed = Fixtures.FIXED[itemID]
  if fixed then return fixed end
  local D = ES.Data
  local vendor = D.VendorPrices and D.VendorPrices[itemID]
  if vendor and vendor > 0 then return math.ceil(vendor * 1.25) + 1 end
  local sell = D.SellPrices and D.SellPrices[itemID]
  if sell and sell > 0 then return sell * 3 + (itemID % 50) end
  return 20 + (itemID % 89) * 7
end

-- Objetos con precio en el escaneo: materiales y resultados de todas las recetas y
-- lo que llena las cajas de Merchant's Favor
function Fixtures.ScannedItems()
  local set = {}
  for _, key in ipairs(ProfessionKeys()) do
    local data = ES.Data[key]
    for _, r in pairs(data and data.recipes or {}) do
      for _, mat in ipairs(r.r or {}) do set[mat[1]] = true end
      if r.out then set[r.out[1]] = true end
    end
  end
  for _, crate in ipairs(ES.Data.Crates or {}) do
    for _, fill in ipairs(crate.fills or {}) do set[fill[1]] = true end
  end
  local ids = {}
  for id in pairs(set) do ids[#ids + 1] = id end
  table.sort(ids)
  return ids
end

-- Un escaneo de la AH con la forma que guarda Scanner:Finish
function Fixtures.Scan(when)
  local items, total = {}, 0
  for _, id in ipairs(Fixtures.ScannedItems()) do
    local p = Fixtures.Price(id)
    local qty = 20 + (id % 7) * 10
    items[id] = {
      listings = 4, quantity = qty, minUnit = p, avgUnit = math.floor(p * 1.1 + 0.5),
      sellers = 3, topShare = 0.4, median = math.floor(p * 1.05 + 0.5),
      ladder = { p, math.floor(qty / 2), math.floor(p * 1.2 + 0.5), qty - math.floor(qty / 2) },
    }
    total = total + 4
  end
  local n = 0
  for _ in pairs(items) do n = n + 1 end
  return { time = when or (NOW - 600), total = total, unique = n, items = items }
end

local function RealmKey() return REALM .. "-" .. FACTION end
local function CharKey() return "Bruno-" .. REALM end

-- Las primeras recetas (por nivel naranja) de una profesión
local function FirstRecipes(profKey, n)
  local list = {}
  for id, r in pairs(ES.Data[profKey].recipes) do list[#list + 1] = { id = id, t = r.t[1] } end
  table.sort(list, function(a, b) if a.t ~= b.t then return a.t < b.t end return a.id < b.id end)
  local out = {}
  for i = 1, math.min(n, #list) do out[i] = list[i].id end
  return out
end

-- Niveles de profesión del estado "full" (el resto no las tiene)
Fixtures.FULL_SKILLS = { Leatherworking = { 120, 150 }, Tailoring = { 80, 150 }, Cooking = { 180, 225 } }

function Fixtures.State(name)
  if name == "empty" then return nil end
  local db = { scans = { [RealmKey()] = Fixtures.Scan() } }
  if name == "scan" then return db end
  assert(name == "full", "estado desconocido: " .. tostring(name))
  db.known = { [CharKey()] = {} }
  for prof, s in pairs(Fixtures.FULL_SKILLS) do
    SKILLS[ES.Data[prof].skillLine] = { s[1], s[2] }
    local ids = FirstRecipes(prof, 12)
    db.known[CharKey()][prof] = ids
    for _, id in ipairs(ids) do KNOWN_SPELLS[id] = true end
  end
  db.neverSell = { [2318] = true }
  db.lang = "es"
  return db
end

-- Historial de mercado grande y siempre igual (pruebas de memoria y del índice de
-- Market.lua): `scans` escaneos de `items` objetos repartidos en ~6,5 días, con
-- "baratas que siguen", y un último escaneo con unas `auctions` subastas en ES.db.track
-- (formato v = 2, una clave por firma). Escribe en ES.db.history/track del reino y
-- devuelve la lista de objetos. Casos límite según el objeto (j % 10):
--   0 sin cantidad   1 un solo punto (solo en el último escaneo)
--   2 solo en las últimas ~3 h (todo dentro de REF_GAP)   3 mínimo que no se mueve
--   4 cada vez más oferta   5 las baratas siguen todas   6 no está en la AH ahora
-- Además: una entrada de hace 8 días (fuera de la semana) y la segunda con 10 min
-- desde la anterior (no cuenta para "estancado")
function Fixtures.BigMarket(scans, items, auctions)
  local seed = 12345
  local function rnd(n) seed = (seed * 16807) % 2147483647 return seed % n end
  local key = ES:RealmKey()
  local DAY = 86400
  local gap = math.floor(6.5 * DAY / scans)
  local ids = {}
  for j = 1, items do ids[j] = 100000 + j end
  local history = { { time = NOW - 8 * DAY, elapsed = 0, snap = ";" .. ids[1] .. ":50:3:50:10" } }
  for i = 1, scans do
    local t = NOW - (scans - i) * gap
    local snap, stuck = {}, {}
    for j, id in ipairs(ids) do
      local kind = j % 10
      local show = true
      if kind == 1 then show = i == scans end
      if kind == 2 then show = NOW - t <= 3 * 3600 end
      if show then
        local base = 20 + (j % 97) * 3
        local min = kind == 3 and base or base + rnd(base)
        local listings = 1 + rnd(12)
        local qty = kind == 4 and (10 + i * 15) or (5 + rnd(60))
        if kind == 0 then
          snap[#snap + 1] = id .. ":" .. min .. ":" .. listings
        else
          snap[#snap + 1] = id .. ":" .. min .. ":" .. listings .. ":" .. (min + rnd(10)) .. ":" .. qty
        end
        if i > 1 then
          local tot = 1 + rnd(8)
          local rem = kind == 5 and tot or rnd(tot + 1)
          stuck[#stuck + 1] = id .. ":" .. rem .. ":" .. tot
        end
      end
    end
    local entry = { time = t, elapsed = 0, snap = ";" .. table.concat(snap, ";") }
    if i > 1 then
      entry.elapsed = i == 2 and 600 or gap
      entry.stuck = ";" .. table.concat(stuck, ";")
    end
    history[#history + 1] = entry
  end
  local sigs = {}
  local S = ES.History
  for a = 1, auctions do
    local j = 1 + rnd(items)
    if j % 10 == 6 then j = j + 1 end
    if j > items then j = 1 end
    local count = 1 + rnd(20)
    local buyout = a % 13 == 0 and 0 or count * (20 + (j % 97) * 3 + rnd(80))
    S.AddAuction(sigs, S.Signature(ids[j], count, buyout, "?"), 1 + rnd(4))
  end
  ES.db.history = ES.db.history or {}
  ES.db.history[key] = history
  ES.db.track = ES.db.track or {}
  ES.db.track[key] = { time = NOW, sigs = sigs, v = 2 }
  return ids
end

-- Lo que se monta con el addon ya arrancado (usa sus propias funciones)
function Fixtures.After(name)
  if name ~= "full" then return end
  local key = ES:RealmKey()
  -- Historial: tres escaneos, una hora entre cada uno, con ventas de por medio
  local S = ES.History
  local function sigs(list)
    local t = {}
    for _, a in ipairs(list) do S.AddAuction(t, S.Signature(a[1], a[2], a[3], a[4]), a[5]) end
    return t
  end
  local base = NOW - 3 * 3600
  for step, left in ipairs({ 10, 6, 4 }) do
    local a = {}
    for _ = 1, left do a[#a + 1] = { 2318, 5, 125, "Ana", 4 } end
    S:Record(key, sigs(a), ";2318:25:" .. left, base + step * 3600)
  end
  -- Una lista de la compra (como la que añade Ganar dinero)
  ES.Shopping.Add("money", "Prueba", {
    { itemID = 2318, quantity = 10, unit = 25, source = "ah" },
    { itemID = 2589, quantity = 20, unit = 15, source = "ah" },
  })
  -- Bolsas con algo de todo
  BAGS[2318], BAGS[2589], BAGS[2592] = 4, 30, 12
  -- Inversiones: Auctionator con historial (un día dudoso) y una cartera con compras,
  -- una venta y un objeto sin precio
  InstallAuctionator()
  AUCTIONATOR_DAYS[4306] = { { ago = 0, max = 199 }, { ago = 2, max = 169 }, { ago = 4, max = 190 },
    { ago = 5, max = 20 }, { ago = 6, max = 196 }, { ago = 14, max = 120 } }
  AUCTIONATOR_DAYS[13468] = { { ago = 0, max = 108800 }, { ago = 4, max = 122200 } }
  ES.Invest:Add(4306, "buy", 20, 200)
  ES.Invest:Add(4306, "buy", 20, 400)
  ES.Invest:Add(4306, "sell", 15, 500)
  ES.Invest:Add(13468, "buy", 5, 450000, true)
  ES.Invest:Add(9258, "buy", 10, 233)
end
