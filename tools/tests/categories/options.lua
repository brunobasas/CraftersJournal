-- Opciones: la ventana, y cada opción cambia lo que guarda y se aplica sin errores

local PAGES = { "home", "shopping", "money", "bulk", "inventory", "invest", "favor", "calc", "patterns", "Leatherworking" }

test("la ventana de opciones se abre en cada categoría", function()
  for _, cat in ipairs(ES.OPTION_CATEGORIES) do
    ES:OpenOptions(cat.key)
    RunTimers()
  end
  local w = ES:OptionsWindow()
  expect(w and w:IsShown(), "la ventana no se ve")
end, { state = "full" })

test("cada opción de casilla: cambia lo guardado y se aplica", function()
  BAGS[2589], BAGS[2318] = 40, 12
  OpenPage("inventory")
  local n = 0
  for _, opt in ipairs(ES.OPTIONS) do
    if opt.kind ~= "slider" and opt.kind ~= "segmented" and opt.kind ~= "hide" then -- (las de ocultar: invest)
      for _, on in ipairs({ false, true }) do
        if opt.set then opt.set(on) else ES:SetOption(opt.key, on) end
        RunTimers()
        if opt.get then
          expect_eq(opt.get(), on, opt.key .. " tras cambiarla")
        else
          expect_eq(ES.db[opt.key], (not on) or nil, opt.key .. " guardada")
        end
      end
      n = n + 1
    end
  end
  note("%d opciones de casilla", n)
  for _, page in ipairs(PAGES) do ES:SelectPage(page) RunTimers() end
end, { state = "full" })

test("cada deslizador: cada escalón se guarda y se aplica", function()
  local n = 0
  for _, opt in ipairs(ES.OPTIONS) do
    if opt.kind == "slider" then
      for _, v in ipairs(opt.steps) do
        ES.db[opt.key] = v
        if opt.apply then opt.apply(v) else ES:ApplyOptions(opt.key) end
        RunTimers()
        no_error(opt.text, v)
      end
      n = n + 1
    end
  end
  expect(n > 0, "no hay deslizadores")
  OpenPage("money")
end, { state = "full" })

test("cada selector de segmentos: cada opción se guarda (la de por defecto, nada)", function()
  local n = 0
  ES:OpenOptions()
  RunTimers()
  for _, cb in ipairs(ES:OptionsWindow().checks) do
    local o = cb.option
    if o.kind == "segmented" then
      for _, c in ipairs(o.choices) do
        for _, b in ipairs(cb.select.buttons) do if b.value == c.value then b:GetScript("OnClick")(b) end end
        RunTimers()
        expect_eq(ES.db[o.key], c.value ~= o.default and c.value or nil, o.key .. " = " .. tostring(c.value))
        expect_eq(cb.select.value, c.value, o.key .. ": marcada")
      end
      n = n + 1
    end
  end
  expect(n > 0, "no hay selectores de segmentos")
end, { state = "full" })

test("Inversiones: sin opción de cartera por personaje (es de la cuenta)", function()
  expect_eq(ES:OptionCategory("investPerChar"), nil, "sigue la opción")
  expect_eq(ES:OptionCategory("investPriceMode"), "invest", "el precio al apuntar, en Inversiones")
end)

test("botón del minimapa: esconder y volver a enseñar", function()
  SlashCmdList.CRAFTERSJOURNAL("minimap")
  expect(ES.db.minimap.hide, "/cj minimap no lo esconde")
  SlashCmdList.CRAFTERSJOURNAL("minimap")
  expect(not ES.db.minimap.hide, "/cj minimap no lo enseña")
end)

---------------------------------------------------------------------------
-- Pestañas: orden, ocultas e inicio (ES.Tabs, UI.lua; categoría Pestañas)
---------------------------------------------------------------------------
local DEFAULT_TABS = { "home", "shopping", "money", "bulk", "inventory", "invest", "favor", "calc", "patterns" }

local function Joined(list) return table.concat(list, ",") end
-- Un orden completo (como el que se guarda): estas primero y luego las demás
local function OrderWith(...)
  local out, seen = {}, {}
  for _, k in ipairs({ ... }) do out[#out + 1] = k seen[k] = true end
  for _, k in ipairs(DEFAULT_TABS) do if not seen[k] then out[#out + 1] = k end end
  return out
end
-- Las pestañas que se ven en la ventana principal, de arriba abajo
local function ShownTabs()
  local out = {}
  for _, tab in ipairs(ES:GetMainFrame().visibleTabs or {}) do
    expect(tab:IsShown(), "la pestaña %s está en la lista de visibles pero escondida", tab.key)
    out[#out + 1] = tab.key
  end
  for _, tab in ipairs(ES:GetMainFrame().tabs) do
    local listed = false
    for _, k in ipairs(out) do if k == tab.key then listed = true end end
    if not listed then expect(not tab:IsShown(), "la pestaña oculta %s se ve", tab.key) end
  end
  return out
end
-- La pestaña que sale marcada (de las que se ven)
local function CheckedTab()
  for _, tab in ipairs(ES:GetMainFrame().tabs) do
    if tab:IsShown() and tab.selected[1]:IsShown() then return tab.key end
  end
end

test("pestañas: sin nada guardado, el orden de siempre y todas visibles", function()
  expect_eq(Joined(ES.Tabs.Order()), Joined(DEFAULT_TABS), "orden")
  expect_eq(Joined(ES.Tabs.Visible()), Joined(DEFAULT_TABS), "visibles")
  expect_eq(ES.Tabs.StartKey(), "home", "inicio")
  OpenMain()
  expect_eq(Joined(ShownTabs()), Joined(DEFAULT_TABS), "pestañas en la ventana")
  expect_eq(ES.db.lastPage, "home", "página al abrir")
end)

test("pestañas: orden guardado, claves que ya no existen y pestañas nuevas", function()
  ES.db.tabOrder = { "shopping", "auctions", "home", "shopping", 7, "patterns", "calc" }
  -- (faltan money, bulk, inventory, invest y favor: como si fueran nuevas en esta versión)
  -- (money va tras shopping, que la precede en el de siempre, y así cada una)
  expect_eq(Joined(ES.Tabs.Order()), "shopping,money,bulk,inventory,invest,favor,home,patterns,calc",
    "las que faltan, tras la que las precede en el orden de siempre")
  -- Falta la primera del de siempre: no la precede ninguna y va arriba
  ES.db.tabOrder = { "calc", "shopping", "money", "inventory", "invest", "favor", "patterns" }
  expect_eq(Joined(ES.Tabs.Order()), "home,calc,shopping,money,bulk,inventory,invest,favor,patterns",
    "nueva sin ninguna antes")
  ES.db.tabOrder = OrderWith("calc", "home")
  expect_eq(ES.Tabs.Order()[1], "calc", "la primera guardada sigue arriba")
  ES.db.tabOrder = "roto"
  expect_eq(Joined(ES.Tabs.Order()), Joined(DEFAULT_TABS), "orden guardado roto")
end)

-- BulkMoney es solo para el desarrollador: existe en la copia de desarrollo (carga
-- DevTools.lua) y no en lo publicado (sin DevTools.lua: ES.DevCommand no existe)
test("pestañas: BulkMoney solo en la copia de desarrollo", function()
  expect(ES.Tabs.Info("bulk"), "en la copia de desarrollo no está BulkMoney (la prueba no prueba nada)")
  ES.DevCommand = nil -- (lo publicado)
  expect(not ES.Tabs.Info("bulk"), "lo publicado tiene BulkMoney")
  expect(not Joined(ES.Tabs.Order()):find("bulk", 1, true), "BulkMoney en el orden de lo publicado")
  -- Un orden guardado con ella (de la copia de desarrollo, misma cuenta): fuera
  ES.db.tabOrder = OrderWith("bulk", "calc")
  expect(not Joined(ES.Tabs.Order()):find("bulk", 1, true), "BulkMoney en el orden guardado de lo publicado")
  ES.db.tabOrder = nil
  OpenMain()
  for _, tab in ipairs(ES:GetMainFrame().tabs) do expect(tab.key ~= "bulk", "lo publicado tiene la pestaña BulkMoney") end
  expect(not ES:GetMainFrame().pages.bulk, "lo publicado tiene la página BulkMoney")
  ES:SelectPage("bulk")
  expect(ES.db.lastPage ~= "bulk", "lo publicado abre BulkMoney")
end)

test("pestañas: ocultas, la de inicio y nunca ninguna", function()
  ES.db.hiddenTabs = { home = true }
  expect_eq(ES.Tabs.StartKey(), "shopping", "inicio con Subir profesiones oculta")
  expect(ES.Tabs.IsHidden("home"), "Subir profesiones no sale oculta")
  ES.db.tabOrder = OrderWith("calc", "shopping")
  ES.db.hiddenTabs = { calc = true }
  expect_eq(ES.Tabs.StartKey(), "shopping", "la de arriba oculta: la siguiente visible")
  -- Lo guardado las oculta todas (a mano o roto): se ve la primera
  ES.db.hiddenTabs = {}
  for _, k in ipairs(DEFAULT_TABS) do ES.db.hiddenTabs[k] = true end
  expect_eq(Joined(ES.Tabs.Visible()), "calc", "todas ocultas")
  expect(not ES.Tabs.IsHidden("calc"), "la que se ve no puede contar como oculta")
end)

test("pestañas: mover, ocultar, no ocultar la última y restaurar", function()
  local T = ES.Tabs
  expect(not T.Move(1, 1), "mismo puesto")
  expect(not T.Move(1, 0), "subir la primera")
  expect(not T.Move(9, 10), "bajar la última")
  expect_eq(ES.db.tabOrder, nil, "sin cambio no se guarda nada")
  expect(T.Move(2, 3), "bajar Lista de compra")
  expect_eq(Joined(T.Order()), "home,money,shopping,bulk,inventory,invest,favor,calc,patterns", "tras bajarla")
  expect(T.Move(3, 2), "volver a subirla")
  expect_eq(ES.db.tabOrder, nil, "de vuelta al orden de siempre no se guarda nada")
  expect(T.Move(9, 1), "Colección arriba")
  expect_eq(T.StartKey(), "patterns", "la de arriba es la de inicio")
  -- Ocultar todas menos una
  for i, k in ipairs(DEFAULT_TABS) do
    if k ~= "inventory" then expect(T.SetHidden(k, true), "no se oculta %s", k) end
  end
  local ok, why = T.SetHidden("inventory", true)
  expect(not ok and why == "last", "deja ocultar la última")
  expect_eq(Joined(T.Visible()), "inventory", "solo queda Inventario")
  expect(T.SetHidden("calc", false), "volver a mostrar")
  expect_eq(Joined(T.Visible()), "inventory,calc", "visibles tras mostrar la Calculadora")
  T.Reset()
  expect_eq(ES.db.tabOrder, nil, "orden tras restaurar")
  expect_eq(ES.db.hiddenTabs, nil, "ocultas tras restaurar")
  expect_eq(Joined(T.Visible()), Joined(DEFAULT_TABS), "visibles tras restaurar")
  expect(not T.SetHidden("auctions", true), "oculta una pestaña que no existe")
end)

test("pestañas: dónde cae una fila al soltarla", function()
  local T = ES.Tabs
  local mids = { 300, 260, 220, 180 } -- (de arriba abajo: la pantalla cuenta hacia arriba)
  expect_eq(T.DropIndex(330, mids), 1, "encima de todo")
  expect_eq(T.DropIndex(280, mids), 2, "entre la 1 y la 2")
  expect_eq(T.DropIndex(221, mids), 3, "justo encima del centro de la 3")
  expect_eq(T.DropIndex(100, mids), 5, "debajo de todo")
  expect_eq(T.GapToIndex(1, 3), 2, "la 1 soltada entre la 2 y la 3")
  expect_eq(T.GapToIndex(4, 1), 1, "la 4 soltada arriba del todo")
  expect_eq(T.GapToIndex(2, 5), 4, "la 2 soltada debajo de todo")
  expect_eq(T.GapToIndex(2, 2), 2, "soltada en su propio sitio")
  expect_eq(T.GapToIndex(2, 3), 2, "soltada justo debajo de sí misma")
end)

test("pestañas: con la ventana abierta, ocultar y reordenar se ve al momento", function()
  OpenMain()
  ES.Tabs.SetHidden("favor", true)
  expect_eq(Joined(ShownTabs()), "home,shopping,money,bulk,inventory,invest,calc,patterns", "tras ocultar Merchant's Favor")
  ES.Tabs.Move(5, 1)
  expect_eq(Joined(ShownTabs()), "inventory,home,shopping,money,bulk,invest,calc,patterns", "tras subir Inventario")
  ES.Tabs.Reset()
  expect_eq(Joined(ShownTabs()), Joined(DEFAULT_TABS), "tras restaurar")
end)

test("pestañas: con la primera del orden de siempre oculta no hay errores al abrir", function()
  ES.db.hiddenTabs = { home = true }
  OpenMain()
  expect_eq(ShownTabs()[1], "shopping", "pestaña de arriba")
  no_error(ES.KeepTabsOnScreen, ES)
  expect_eq(ES.db.lastPage, "shopping", "página al abrir")
end)

test("pestañas: el addon se abre en la de arriba; quien pide una página manda", function()
  ES.db.tabOrder = OrderWith("money", "home")
  OpenMain()
  expect_eq(ES.db.lastPage, "money", "primera apertura de la sesión")
  expect_eq(CheckedTab(), "money", "pestaña marcada")
  ES:HideMainFrame()
  ES.sessionPage = nil
  ES.db.tabOrder = OrderWith("calc", "shopping")
  ES.db.hiddenTabs = { calc = true }
  OpenMain()
  expect_eq(ES.db.lastPage, "shopping", "con la de arriba oculta")
  -- Una página guardada que ya no existe lleva a la de inicio
  ES:SelectPage("auctions")
  expect_eq(ES.db.lastPage, "shopping", "página que no existe")
  -- Quien pide una página la abre
  ES:HideMainFrame()
  ES.sessionPage = nil
  ES:ShowMainFrame("Leatherworking")
  RunTimers()
  expect_eq(ES.db.lastPage, "Leatherworking", "profesión pedida (asistente de ruta)")
end)

test("pestañas: una oculta pierde solo su icono", function()
  ES.Tabs.SetHidden("shopping", true)
  ES:OpenShoppingAtAuction(AuctionFrame)
  RunTimers()
  expect_eq(ES.db.lastPage, "shopping", "el botón de la AH abre la Lista de compra")
  expect_eq(CheckedTab(), nil, "ninguna pestaña marcada")
  no_error(ES.FlashTab, ES, "shopping", true)
  RunTimers()
  -- Ocultar la pestaña de la página que se está viendo
  OpenPage("favor")
  ES.Tabs.SetHidden("favor", true)
  RunTimers()
  expect_eq(ES.db.lastPage, "favor", "la página sigue")
  expect(ES:GetMainFrame().pages.favor:IsShown(), "la página de Merchant's Favor se escondió")
  expect_eq(CheckedTab(), nil, "ninguna pestaña marcada tras ocultarla")
end, { state = "full" })

-- La categoría Pestañas de las opciones -------------------------------------------
local function TabsPage()
  ES:OpenOptions("tabs")
  RunTimers()
  return ES:OptionsWindow().pages.tabs
end
-- Claves de las filas que se ven, de arriba abajo
local function RowKeys(page)
  local out = {}
  for _, row in ipairs(page.rows) do if row:IsShown() then out[#out + 1] = row.key end end
  return out
end
local function Row(page, key)
  for _, row in ipairs(page.rows) do if row:IsShown() and row.key == key then return row end end
  error("no hay fila de " .. key)
end
local function Click(b) b:GetScript("OnClick")(b) RunTimers() end

test("Pestañas en opciones: una fila por pestaña, en su orden, solo con icono y nombre", function()
  OpenMain()
  local page = TabsPage()
  expect_eq(Joined(RowKeys(page)), Joined(DEFAULT_TABS), "filas")
  local row = Row(page, "shopping")
  expect_eq(row.name:GetText(), ES.L["Lista de compra"], "nombre de la fila")
  expect(row.desc == nil and row.start == nil, "la fila tiene descripción o «Inicio»")
  expect(page.header:IsShown(), "el botón Ocultar no se ve")
  expect(page.header.reset == nil, "sigue el botón Restaurar")
  ES.Tabs.Move(8, 1)
  ES.Tabs.SetHidden("calc", true)
  page = TabsPage()
  expect_eq(Joined(RowKeys(page)), "calc,home,shopping,money,bulk,inventory,invest,favor,patterns", "filas tras cambiar el orden")
  expect(Row(page, "calc").hiddenText:IsShown(), "la oculta no dice OCULTA")
  -- El botón solo con esta categoría
  ES:OpenOptions("general")
  RunTimers()
  expect(not page.header:IsShown(), "el botón de Pestañas sale en General")
end)

test("Pestañas en opciones: las flechas suben y bajan una fila", function()
  OpenMain()
  local page = TabsPage()
  Click(Row(page, "shopping").down)
  expect_eq(Joined(RowKeys(page)), "home,money,shopping,bulk,inventory,invest,favor,calc,patterns", "filas tras bajar Lista de compra")
  expect_eq(Joined(ShownTabs()), "home,money,shopping,bulk,inventory,invest,favor,calc,patterns", "pestañas tras bajarla")
  Click(Row(page, "home").up)
  expect_eq(Joined(RowKeys(page)), "home,money,shopping,bulk,inventory,invest,favor,calc,patterns", "subir la primera no hace nada")
  Click(Row(page, "patterns").down)
  expect_eq(Row(page, "patterns").index, 9, "bajar la última no hace nada")
end)

test("Pestañas en opciones: modo ocultar, Hecho y avisos", function()
  OpenMain()
  local page = TabsPage()
  -- Fuera del modo de ocultar, el clic no oculta
  Click(Row(page, "calc"))
  expect(not ES.Tabs.IsHidden("calc"), "un clic fuera del modo de ocultar la oculta")
  Click(page.header.hide)
  expect(page.hideMode, "Ocultar no pone el modo de ocultar")
  expect(page.header.hide:GetText():find(ES.L["Hecho"], 1, true), "el botón no pasa a Hecho")
  Click(Row(page, "calc"))
  expect(ES.Tabs.IsHidden("calc"), "el clic no oculta la Calculadora")
  expect(Row(page, "calc").hiddenText:IsShown(), "la fila no dice OCULTA")
  Click(Row(page, "calc"))
  expect(not ES.Tabs.IsHidden("calc"), "el segundo clic no la vuelve a mostrar")
  -- En el modo de ocultar, las flechas no mueven
  Click(Row(page, "shopping").down)
  expect_eq(ES.db.tabOrder, nil, "las flechas mueven en el modo de ocultar")
  -- Aviso al ocultar la Lista de compra
  Click(Row(page, "shopping"))
  expect(ES.Tabs.IsHidden("shopping"), "no se oculta la Lista de compra")
  expect(page.status:GetText():find("^Lista de compra oculta:"), "sin aviso al ocultar la Lista de compra")
  -- Todas menos una; la última no se oculta y lo dice
  for _, k in ipairs(DEFAULT_TABS) do
    if k ~= "shopping" and k ~= "favor" then Click(Row(page, k)) end
  end
  expect_eq(Joined(ES.Tabs.Visible()), "favor", "solo queda Merchant's Favor")
  Click(Row(page, "favor"))
  expect_eq(Joined(ES.Tabs.Visible()), "favor", "se ocultó la última")
  expect_eq(page.status:GetText(), ES.L["Tiene que quedar al menos una pestaña visible."], "aviso de la última")
  -- Hecho: vuelta al modo normal, las ocultas siguen
  Click(page.header.hide)
  expect(not page.hideMode, "Hecho no vuelve al modo normal")
  expect_eq(page.header.hide:GetText(), ES.L["Ocultar"], "el botón no vuelve a Ocultar")
  expect(Row(page, "calc").hiddenText:IsShown(), "tras Hecho las ocultas no dicen OCULTA")
  expect_eq(Joined(ShownTabs()), "favor", "pestañas tras Hecho")
  -- Al cambiar de categoría se va el aviso y el modo de ocultar
  Click(page.header.hide)
  Click(Row(page, "calc"))
  Click(Row(page, "calc"))
  page:Notice("algo")
  ES:OpenOptions("general")
  RunTimers()
  expect(not page.hideMode, "el modo de ocultar sigue tras cambiar de categoría")
  expect_eq(page.status:GetText(), "", "el aviso sigue tras cambiar de categoría")
end)

-- Arrastrar con un ratón falso: la lista mide 424 de ancho y su borde de arriba está a
-- 400 (en sus coordenadas); `scale` es la escala de la ventana de opciones
local function FakeGeometry(page, scale)
  page.GetTop = function() return 400 end
  page.GetLeft = function() return 0 end
  page.GetRight = function() return 424 end
  page.GetEffectiveScale = function() return scale end
end
local function Mouse(x, y, scale)
  GetCursorPosition = function() return x * scale, y * scale end
end
local function Drag(page, key, x, y, scale)
  local row = Row(page, key)
  Mouse(200, 400 - (row.index - 1) * 37 - 17, scale) -- (sobre su propia fila)
  row:GetScript("OnDragStart")(row)
  expect(page.ghost:IsShown(), "al arrastrar no sale la fila fantasma")
  Mouse(x, y, scale)
  page:UpdateDrag()
  return row
end
local function Drop(page, row)
  row:GetScript("OnDragStop")(row)
  RunTimers()
  expect(not page.ghost:IsShown(), "la fila fantasma se queda al soltar")
  expect(not page.dropLine:IsShown(), "la línea dorada se queda al soltar")
end

test("Pestañas en opciones: arrastrar una fila la cambia de sitio; fuera, nada", function()
  for _, scale in ipairs({ 1, 1.5, 0.7 }) do
    ES.Tabs.Reset()
    OpenMain()
    local page = TabsPage()
    FakeGeometry(page, scale)
    -- Inventario (5.ª) por encima de Subir profesiones
    local row = Drag(page, "inventory", 200, 395, scale)
    expect(page.dropLine:IsShown(), "escala %s: no sale la línea de dónde caerá", scale)
    Drop(page, row)
    expect_eq(Joined(RowKeys(page)), "inventory,home,shopping,money,bulk,invest,favor,calc,patterns", "escala " .. scale .. ": filas")
    expect_eq(Joined(ShownTabs()), "inventory,home,shopping,money,bulk,invest,favor,calc,patterns", "escala " .. scale .. ": pestañas")
    -- Subir profesiones (ahora 2.ª) entre Merchant's Favor (7.ª) y la Calculadora (8.ª)
    row = Drag(page, "home", 200, 400 - 7 * 37 + 1, scale)
    Drop(page, row)
    expect_eq(Joined(RowKeys(page)), "inventory,shopping,money,bulk,invest,favor,home,calc,patterns", "escala " .. scale .. ": entre dos")
    -- Soltarla fuera de la lista (debajo, y a la derecha)
    row = Drag(page, "calc", 200, 20, scale)
    expect(not page.dropLine:IsShown(), "fuera de la lista sale la línea")
    Drop(page, row)
    row = Drag(page, "calc", 600, 395, scale)
    Drop(page, row)
    expect_eq(Joined(RowKeys(page)), "inventory,shopping,money,bulk,invest,favor,home,calc,patterns", "escala " .. scale .. ": soltada fuera")
  end
end)

test("Pestañas en opciones: no se arrastra en el modo de ocultar; cerrar a mitad no deja nada", function()
  OpenMain()
  local page = TabsPage()
  FakeGeometry(page, 1)
  Click(page.header.hide)
  local row = Row(page, "money")
  row:GetScript("OnDragStart")(row)
  expect(not page.ghost:IsShown() and not page.dragRow, "se arrastra en el modo de ocultar")
  Click(page.header.hide)
  -- Cerrar la ventana a mitad del arrastre
  row = Drag(page, "money", 200, 395, 1)
  ES:OptionsWindow():Hide()
  expect(not page.ghost:IsShown() and not page.dragRow, "al cerrar sigue el arrastre")
  expect_eq(ES.db.tabOrder, nil, "cerrar a mitad cambia el orden")
  row:GetScript("OnDragStop")(row) -- (el juego aún avisa de que se soltó: no pasa nada)
  expect_eq(ES.db.tabOrder, nil, "soltar tras cerrar cambia el orden")
  -- Cambiar de categoría a mitad
  page = TabsPage()
  row = Drag(page, "money", 200, 395, 1)
  ES:OpenOptions("general")
  RunTimers()
  expect(not page.ghost:IsShown() and not page.dragRow, "al cambiar de categoría sigue el arrastre")
  expect_eq(ES.db.tabOrder, nil, "cambiar de categoría a mitad cambia el orden")
end)

test("Pestañas en opciones: en el idioma elegido", function()
  OpenMain()
  TabsPage()
  ES:SetLanguage("en")
  RunTimers()
  local page = TabsPage()
  expect_eq(Row(page, "shopping").name:GetText(), ES.Locales.en["Lista de compra"], "nombre en inglés")
  expect_eq(page.header.hide:GetText(), ES.Locales.en["Ocultar"], "Ocultar en inglés")
  expect_eq(ES:OptionsWindow().heading:GetText(), ES.Locales.en["Pestañas"], "título en inglés")
end)

test("ya no está la opción de leer los escaneos de otros addons (se leen siempre)", function()
  for _, o in ipairs(ES.OPTIONS) do
    expect(o.key ~= "noForeignScans", "sigue la opción «Leer los escaneos de otros addons»")
  end
end)

test("comandos /cj sin errores", function()
  for _, cmd in ipairs({ "", "opciones", "errores", "minimap", "minimap", "ayuda", "algo raro" }) do
    no_error(SlashCmdList.CRAFTERSJOURNAL, cmd)
    RunTimers()
  end
end, { state = "full" })

-- /cj mem (DevTools.lua, solo en la copia de desarrollo): las cachés que cuelgan de
-- variables locales (ES.MemPart) se ven, y no van a parar a "el resto"
test("/cj mem: mide las cachés de variables locales", function()
  UpdateAddOnMemoryUsage = function() end
  GetAddOnMemoryUsage = function() return collectgarbage("count") end
  OpenPage("money")
  local names, parts = {}, {}
  for _, part in ipairs(ES.MemParts) do
    local ok, v = pcall(part.get)
    expect(ok, "%s: %s", part.name, tostring(v))
    names[#names + 1] = part.name
    parts[part.name] = v
  end
  local all = table.concat(names, " | ")
  for _, want in ipairs({ "índice de mercado", "Ganar dinero: ideas y costes por profesión", "dónde conseguir cada receta" }) do
    expect(all:find(want, 1, true), "/cj mem no mide «%s» (hay: %s)", want, all)
  end
  local earn = parts["Ganar dinero: ideas y costes por profesión"]
  expect(earn and (earn[1] or next(earn[2])), "con Ganar dinero abierto, su caché sale vacía")
  for i = #PRINTS, 1, -1 do PRINTS[i] = nil end
  SlashCmdList.CRAFTERSJOURNAL("mem")
  local out = table.concat(PRINTS, "\n")
  expect(out:find("Memoria:", 1, true) and out:find("el resto", 1, true), "/cj mem no informa:\n%s", out)
end, { state = "full" })

-- /cj cpu (DevTools.lua): cronometra lo que corre con la ventana cerrada
test("/cj cpu: cronometra el asistente al cambiar las bolsas", function()
  StartRoute("Tailoring", 1, 75)
  ES:HideMainFrame()
  RunTimers()
  SlashCmdList.CRAFTERSJOURNAL("cpu")
  BAGS[2589] = (BAGS[2589] or 0) + 3
  FireEvent("BAG_UPDATE_DELAYED")
  RunTimers()
  for i = #PRINTS, 1, -1 do PRINTS[i] = nil end
  SlashCmdList.CRAFTERSJOURNAL("cpu")
  local out = table.concat(PRINTS, "\n")
  local n = out:match("(%d+)×%s+máx%s+[%d.]+ ms%s+asistente: releer la ruta")
  expect(n and tonumber(n) >= 1, "/cj cpu no cuenta el asistente:\n%s", out)
  -- /cj cpu reset vuelve a cero
  SlashCmdList.CRAFTERSJOURNAL("cpu reset")
  for i = #PRINTS, 1, -1 do PRINTS[i] = nil end
  SlashCmdList.CRAFTERSJOURNAL("cpu")
  expect(not table.concat(PRINTS, "\n"):find("asistente: releer la ruta", 1, true), "tras reset sigue contando lo de antes")
end, { state = "scan" })
