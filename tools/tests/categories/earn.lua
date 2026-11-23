-- Ganar dinero: qué fabricar hoy con tus recetas porque da beneficio

local function Finite(x) return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge end

-- Precio de un objeto en el escaneo de las pruebas (y que no se pueda fabricar más barato)
local function SetPrice(itemID, price, qty)
  local scan = ES.db.scans[ES:RealmKey()]
  qty = qty or 50
  scan.items[itemID] = { listings = 5, quantity = qty, minUnit = price, avgUnit = price, sellers = 3, topShare = 0.3,
    median = price, ladder = { price, qty } }
end

local function Ideas()
  ES.db.earnMinProfit = 1 -- (todas las que dejan algo: la prueba es de las cuentas, no del mínimo)
  ES.Earn:Clear()
  return ES.Earn:Ideas()
end

for _, state in ipairs({ "empty", "scan", "full" }) do
  test("la pestaña se abre: " .. state, function()
    OpenPage("money")
    expect(ES:GetMainFrame().pages.money:IsShown(), "la página no se ve")
  end, { state = state })
end

test("sin profesiones ni escaneo: no propone nada", function()
  local res = Ideas()
  expect_eq(#res.batch, 0, "ideas sin escaneo")
end, { state = "empty" })

test("las cuentas de cada idea cuadran", function()
  local res = Ideas()
  expect(#res.batch > 0, "no hay ninguna idea en el lote (recetas sabidas: las primeras de 3 profesiones)")
  local invest, profit = 0, 0
  for _, idea in ipairs(res.batch) do
    local name = tostring(idea.e.recipe and idea.e.recipe.name)
    for _, k in ipairs({ "profit", "invest", "sale", "crafts" }) do
      expect_finite(idea[k], name .. ": " .. k)
    end
    expect(idea.crafts >= 0 and idea.crafts == math.floor(idea.crafts), "%s: %s fabricaciones", name, tostring(idea.crafts))
    expect(idea.invest >= 0, "%s: invierte %s", name, tostring(idea.invest))
    expect_near(idea.profit, idea.sale * idea.crafts - idea.invest, 0.5, name .. ": beneficio = venta × fabricaciones - inversión")
    invest, profit = invest + idea.invest, profit + idea.profit
    local e = idea.e
    if idea.sellWhere == "ah" then
      expect_near(e.ahNet, e.ahPrice * (1 - e.cut) - e.deposit, 0.01, name .. ": neto en la AH = precio - comisión - depósito")
      expect_near(e.cut, 0.05, 1e-9, name .. ": comisión de la AH de tu facción")
      expect_near(idea.sale, e.ahNet * e.qty, 0.01, name .. ": venta por fabricación")
    end
    expect_near(e.profit, math.max(e.vendor, e.ahNet or 0) * e.qty - e.cost, 0.5, name .. ": beneficio por fabricación")
  end
  expect_near(res.invest, invest, 0.5, "inversión del lote = suma de las líneas")
  expect_near(res.profit, profit, 0.5, "beneficio del lote = suma de las líneas")
  note("%d ideas en el lote, beneficio %.0f, invierte %.0f", #res.batch, res.profit, res.invest)
end, { state = "full" })

test("una idea con precios conocidos: la cuenta hecha a mano", function()
  -- Light Armor Kit (Peletería, 2152): 1 Light Leather. Light Leather a 25c y las
  -- chatarras para fabricarla, caras (así se compra); el kit, a 1000c en la AH
  local r = ES.Data.Leatherworking.recipes[2152]
  local kit = r.out[1]
  expect_eq(#r.r, 1, "materiales del kit")
  expect_eq(r.r[1][1], 2318, "material del kit")
  expect_eq(r.r[1][2], 1, "cantidad de Light Leather")
  SetPrice(2318, 25, 500)
  SetPrice(2934, 100000, 500) -- Ruined Leather Scraps
  SetPrice(kit, 1000, 40)
  KNOWN_SPELLS[2152] = true
  local res = Ideas()
  local idea
  for _, i in ipairs(res.ideas) do if i.e.id == 2152 then idea = i end end
  expect(idea, "el kit no sale en Ganar dinero")
  local e = idea.e
  local vendor = ES:VendorSellPrice(kit)
  -- A mano: depósito = venta al vendedor × 5% × 24 h / 2 (la fórmula de Classic, 24 h);
  -- neto = precio de venta × 95% - depósito; beneficio = neto - 25
  expect_near(e.deposit, vendor * 0.05 * 24 / 2, 0.01, "depósito de 24 h")
  expect_eq(e.cost, 25, "coste: una Light Leather")
  expect_eq(e.ahMin, 1000, "precio más bajo en la AH")
  note("precio de venta %s, depósito %s (venta al vendedor %s), neto %s, beneficio %s",
    tostring(e.ahPrice), tostring(e.deposit), tostring(vendor), tostring(e.ahNet), tostring(e.profit))
  expect(e.ahPrice <= 1000 and e.ahPrice >= 990, "precio de venta %s: el más bajo de la AH o justo por debajo", tostring(e.ahPrice))
  expect_near(e.ahNet, e.ahPrice * 0.95 - e.deposit, 0.01, "neto")
  expect_near(e.profit, e.ahNet - 25, 0.01, "beneficio por fabricación")
  expect_eq(idea.sellWhere, "ah", "se vende en la AH")
end, { state = "full" })

-- Spec recipe-requirements: «Recetas que podrías aprender» no propone las de una
-- especialización que no tienes (Frostsaber Boots pide Tribal Leatherworking)
test("recetas para aprender: solo las de tu especialización", function()
  local r = ES.Data.Leatherworking.recipes[19066] -- Frostsaber Boots
  expect(r and r.scroll and r.spec == "Tribal", "Frostsaber Boots no es un pergamino de Tribal: la prueba no prueba nada")
  SKILLS[ES.Data.Leatherworking.skillLine] = { 260, 300 }
  for _, m in ipairs(r.r) do SetPrice(m[1], 1, 5000) end -- materiales baratos
  SetPrice(r.scroll, 100, 1)                              -- el patrón, en la AH
  SetPrice(r.out[1], 500000, 40)                          -- lo fabricado, caro
  local function Offered()
    for _, idea in ipairs(Ideas().learnable) do
      if idea.e.id == 19066 then return true end
    end
    return false
  end
  expect(not Offered(), "sin Tribal Leatherworking propone aprender Frostsaber Boots")
  KNOWN_SPELLS[10660] = true
  expect(Offered(), "con Tribal Leatherworking no propone aprender Frostsaber Boots (la prueba no prueba nada)")
end, { state = "full" })

-- Spec recipe-requirements: con el icono de misión de la profesión desactivado, no se
-- propone aprender una receta que su instructor solo enseña tras una misión que no has
-- hecho (Discolored Healing Potion: Odd Child / Apothecary Renferrel)
test("recetas para aprender: sin la misión y con el icono desactivado, no salen las Discolored", function()
  local LESSER = 1244645
  local r = ES.Data.Alchemy.recipes[LESSER]
  expect(r and r.unlock, "Lesser Discolored Healing Potion no pide misión: la prueba no prueba nada")
  FACTION = "Alliance"
  SKILLS[ES.Data.Alchemy.skillLine] = { 100, 150 }
  for _, m in ipairs(r.r) do SetPrice(m[1], 1, 5000) end -- materiales baratos
  SetPrice(r.out[1], 500000, 40)                          -- lo fabricado, caro
  local function Offered()
    for _, idea in ipairs(Ideas().learnable) do
      if idea.e.id == LESSER then return true end
    end
    return false
  end
  expect(Offered(), "con el icono de misión activado no propone aprender Lesser Discolored (la prueba no prueba nada)")
  ES.db.prof = ES.db.prof or {}
  ES.db.prof.Alchemy = ES.db.prof.Alchemy or {}
  ES.db.prof.Alchemy.useQuests = false
  expect(not Offered(), "con el icono desactivado y sin la misión, propone aprender Lesser Discolored")
  QUESTS_DONE[92110] = true
  expect(Offered(), "con la misión hecha no propone aprender Lesser Discolored")
end, { state = "full" })

test("quitar una receta de Ganar dinero y recuperarla", function()
  local res = Ideas()
  local first = expect(res.batch[1], "sin ideas")
  local id = first.e.id
  ES.Earn.SetHidden(id, true)
  res = Ideas()
  for _, i in ipairs(res.ideas) do expect(i.e.id ~= id, "la receta quitada sigue en las ideas") end
  expect(res.removed >= 1, "no cuenta la quitada")
  ES.Earn.SetHidden(id, false)
  res = Ideas()
  local back = false
  for _, i in ipairs(res.ideas) do if i.e.id == id then back = true end end
  expect(back, "la receta no vuelve")
end, { state = "full" })

test("cambiar la cantidad de una línea con los botones", function()
  local res = Ideas()
  local idea
  for _, i in ipairs(res.batch) do if i.sellWhere == "ah" and not i.cooldown then idea = i break end end
  expect(idea, "sin ideas de AH en el lote")
  local before = idea.crafts
  ES.Earn.StepQuantity(idea, 5)
  res = Ideas()
  local after
  for _, i in ipairs(res.ideas) do if i.e.id == idea.e.id then after = i end end
  expect(after and after.custom, "la cantidad elegida no se guarda")
  expect_eq(after.crafts, before + 5, "fabricaciones tras +5")
  -- y la página se pinta con ella
  OpenPage("money")
end, { state = "full" })

-- Enfriamiento con el PC reiniciado después de transmutar: GetSpellCooldown da el inicio
-- desbordado (2^32 ms más tarde). Salía "Listo en 1195 h" con 59 min de verdad (Arcanite Bar)
test("enfriamiento empezado antes de arrancar el PC: las horas de verdad", function()
  local ARCANITE, WRAP = 17187, 2 ^ 32 / 1000
  local left = 59 * 60
  -- (transmutación: 1 día; empezó hace 23 h y 1 min, contado desde antes del arranque)
  GetSpellCooldown = function(id)
    if id == ARCANITE then return NOW - (86400 - left) + WRAP, 86400, 1 end
    return 0, 0, 1
  end
  expect_near(ES.Earn.CooldownLeft(ARCANITE), left, 1, "segundos que faltan")
  expect_near(ES.charData.cdReady[ARCANITE] - time(), left, 1, "lo guardado")
  -- Sin desbordar, igual
  GetSpellCooldown = function() return NOW - (86400 - left), 86400, 1 end
  expect_near(ES.Earn.CooldownLeft(ARCANITE), left, 1, "segundos que faltan (sin desbordar)")
  -- Lo guardado antes del arreglo (1193 h de más) no se fía: no se sabe
  GetSpellCooldown = function() return 0, 0, 1 end
  ES.charData.cdReady[ARCANITE] = time() + WRAP + left
  expect_eq(ES.Earn.CooldownLeft(ARCANITE), nil, "lo guardado con 1193 h de más")
  expect_eq(ES.charData.cdReady[ARCANITE], nil, "se borra lo guardado mal")
end, { state = "full" })

---------------------------------------------------------------------------
-- Con la ventana cerrada un rato se sueltan las cachés (lighter-memory, UI.lua)
---------------------------------------------------------------------------
local function KB()
  collectgarbage("collect")
  collectgarbage("collect")
  return collectgarbage("count")
end

-- Las ideas de Ganar dinero en texto (para comparar dos cálculos)
local function Digest(res)
  local t = {}
  for _, list in ipairs({ res.batch or {}, res.vendor or {} }) do
    for _, idea in ipairs(list) do
      t[#t + 1] = string.format("%s:%s:%s:%.4f:%.4f:%.4f", tostring(idea.profKey), tostring(idea.e.id), tostring(idea.crafts),
        idea.profit or 0, idea.invest or 0, idea.sale or 0)
    end
  end
  return table.concat(t, "\n"), #t
end

local function OpenMoney()
  ES.db.earnMinProfit = 1 -- (todas las que dejan algo)
  OpenPage("money")
  return ES.Earn:Ideas()
end

test("ventana cerrada un minuto: se sueltan las cachés de Ganar dinero", function()
  OpenMoney()
  -- Lo que ocupa la caché de Ganar dinero
  local with = KB()
  ES.Earn:Clear()
  local cache = with - KB()
  OpenMoney()
  ES:HideMainFrame()
  RunTimers(ES.IDLE_RELEASE - 5)
  local closed = KB()
  RunTimers(10)
  local freed = closed - KB()
  note("caché de Ganar dinero %.0f KB; liberado al minuto %.0f KB", cache, freed)
  expect(cache > 50, "la caché de Ganar dinero ocupa %.0f KB: la prueba no comprueba nada", cache)
  expect(freed >= cache * 0.9, "al minuto se liberan %.0f KB y la caché ocupaba %.0f KB", freed, cache)
end, { state = "full" })

test("ventana cerrada y abierta otra vez antes del minuto: Ganar dinero no se recalcula", function()
  local res = OpenMoney()
  ES:HideMainFrame()
  RunTimers(30)
  OpenMain()
  RunTimers(ES.IDLE_RELEASE)
  expect(ES.Earn:Ideas() == res, "Ganar dinero se recalculó al volver a abrir antes del minuto")
  -- Abrir y cerrar otra vez: cuenta el último cierre
  ES:HideMainFrame()
  RunTimers(30)
  expect(ES.Earn:Ideas() == res, "se soltó antes del minuto desde el último cierre")
  RunTimers(ES.IDLE_RELEASE)
  expect(ES.Earn:Ideas() ~= res, "no se soltó al minuto del último cierre")
end, { state = "full" })

test("ventana cerrada un minuto: la ruta empezada no se recalcula", function()
  local _, plan = StartRoute("Tailoring", 1, 75)
  local calls = 0
  local Plan = ES.Planner.Plan
  ES.Planner.Plan = function(...) calls = calls + 1 return Plan(...) end
  ES:HideMainFrame()
  local ok, err = pcall(RunTimers, ES.IDLE_RELEASE + 5)
  ES.Planner.Plan = Plan
  if not ok then error(err, 0) end
  expect(ES:LockedPlan("Tailoring") == plan, "la ruta fijada cambió al soltar las cachés")
  expect_eq(calls, 0, "rutas calculadas con la ventana cerrada")
end, { state = "full" })

test("soltadas las cachés, Ganar dinero da lo mismo al volver", function()
  local before, n = Digest(OpenMoney())
  ES:HideMainFrame()
  RunTimers(ES.IDLE_RELEASE + 5)
  local t = os.clock()
  local after = Digest(OpenMoney())
  note("%d líneas; recalcular al volver a abrir: %.0f ms (en el Lua de las pruebas)", n, (os.clock() - t) * 1000)
  expect(n > 0, "sin ideas: la prueba no comprueba nada")
  expect_eq(after, before, "ideas, cantidades y beneficios")
end, { state = "full" })

test("soltadas las cachés, la ventana de fabricar calcula sus ideas", function()
  local res = OpenMoney()
  local prof = expect(res.batch[1], "sin ideas").profKey
  local function List()
    local t = {}
    for _, idea in ipairs(ES.CraftWindow:List(prof)) do t[#t + 1] = idea.e.id .. "x" .. idea.crafts end
    return table.concat(t, " ")
  end
  local before = List()
  ES:HideMainFrame()
  RunTimers(ES.IDLE_RELEASE + 5)
  expect(ES.Earn:Ideas() ~= res, "no se soltó la caché")
  expect_eq(List(), before, "ideas de la ventana de fabricar de " .. prof)
  expect(before ~= "", "la ventana de fabricar no tiene ideas: la prueba no comprueba nada")
end, { state = "full" })

-- Las filas pintadas guardan sus funciones de clic, tooltip y − / +, y con ellas la idea
-- (y todo su cálculo): soltada la caché, seguían en memoria mientras no se repintara
test("soltadas las cachés, las filas de Ganar dinero no se quedan con las ideas", function()
  local res = OpenMoney()
  local idea
  for _, i in ipairs(res.batch) do if i.sellWhere == "ah" and not i.cooldown then idea = i break end end
  expect(idea, "sin ideas de AH en el lote (con botones - y +): la prueba no comprueba nada")
  local weak = setmetatable({ idea = idea }, { __mode = "v" })
  idea, res = nil, nil
  ES:HideMainFrame()
  RunTimers(ES.IDLE_RELEASE + 5)
  collectgarbage("collect")
  collectgarbage("collect")
  expect(weak.idea == nil, "la idea sigue en memoria tras soltar las cachés (la guarda una fila)")
  -- Al volver, la página se pinta entera otra vez
  OpenMoney()
  local shown = 0
  for _, row in ipairs(ES.earnPage.rows or {}) do if row:IsShown() then shown = shown + 1 end end
  expect(shown > 0, "al volver a abrir Ganar dinero no se pinta")
end, { state = "full" })

test("una fila que se repinta sin botones - y + suelta los de antes", function()
  OpenMoney()
  local page = ES.earnPage
  local withStep
  for _, row in ipairs(page.rows) do if row.onStep then withStep = row break end end
  expect(withStep, "ninguna fila con botones - y +: la prueba no comprueba nada")
  ES.UI.RenderLines(page, { { title = "a" }, { title = "b" } })
  for i, row in ipairs(page.rows) do
    expect(row.onStep == nil and row.onClick == nil and row.tooltip == nil, "la fila %d se queda con lo de antes", i)
  end
end, { state = "full" })

test("dinero: negativos, NaN e infinito no dan error al pintarse", function()
  for _, v in ipairs({ -12345, 0, 1, 99999999, 0 / 0, math.huge, -math.huge }) do
    no_error(ES.Money, v)
  end
end)
