-- Novedades: la ventana con lo nuevo, una vez por versión

local function SetVersion(v)
  GetAddOnMetadata = function(_, field) if field == "Version" then return v end end
end

local function Latest() return ES.WHATS_NEW[1].version end

-- Las notas de una versión
local function Notes(version)
  for _, v in ipairs(ES.WHATS_NEW) do if v.version == version then return v end end
end

-- La versión con la novedad de escanear con Auctionator o solo (su elección noAuctionator)
local function ChoiceVersion()
  for _, v in ipairs(ES.WHATS_NEW) do
    for _, it in ipairs(v.items) do if it.choice == "noAuctionator" then return v.version, it end end
  end
end

test("comparar versiones número a número", function()
  local C = ES.CompareVersions
  expect_eq(C("0.9.0", "0.10.0"), -1, "0.9.0 < 0.10.0")
  expect_eq(C("0.10.0", "0.9.0"), 1, "0.10.0 > 0.9.0")
  expect_eq(C("0.63.0", "0.63.0"), 0, "iguales")
  expect_eq(C("1.0", "1.0.0"), 0, "1.0 = 1.0.0")
  expect_eq(C("0.63.1", "0.63.0"), 1, "parche")
end, { boot = false })

test("las notas: de la más nueva a la más antigua, sin las de versiones por publicar", function()
  local list = ES.WHATS_NEW
  expect(#list > 0, "sin notas")
  for i = 2, #list do
    expect(ES.CompareVersions(list[i - 1].version, list[i].version) > 0, "notas desordenadas: %s antes de %s", list[i - 1].version, list[i].version)
  end
  for _, v in ipairs(list) do
    expect(#v.items > 0, "%s sin novedades", v.version)
    for _, it in ipairs(v.items) do
      -- (la de elegir algo no lleva texto: su diapositiva es el título y las casillas)
      expect(type(it.title) == "string" and it.title ~= "" and (it.choice or type(it.text) == "string"), "%s: novedad sin título o texto", v.version)
    end
  end
  local since = ES:WhatsNewSince(list[#list].version, list[2] and list[2].version or list[1].version)
  for _, v in ipairs(since) do
    expect(ES.CompareVersions(v.version, list[2] and list[2].version or list[1].version) <= 0, "sale %s, aún sin publicar", v.version)
  end
  expect(#since <= 3, "más de 3 versiones de golpe")
end, { boot = false })

-- Ancho y alto de un TGA (cabecera de 18 bytes)
local function TgaSize(path)
  local f = io.open(ADDON_DIR .. "/" .. path, "rb")
  if not f then return nil end
  local head = f:read(18)
  f:close()
  local function u16(i) return head:byte(i) + head:byte(i + 1) * 256 end
  return u16(13), u16(15)
end

-- Una versión de prueba con dos novedades con imagen y una sin ella: las de verdad (las
-- de la 0.66.0) se quitaron del addon, pero las páginas de imagen siguen. Se mete en
-- ES.WHATS_NEW, en su sitio por versión, mientras dura `fn`
local IMG_VERSION = "0.66.5"
local function WithImageVersion(fn)
  local v = { version = IMG_VERSION, items = {
    { title = "Página 1", text = "a", image = { file = ES.WHATS_NEW_SHOTS .. "Page1", w = 1531, h = 1024 } },
    { title = "Página 2", text = "b", image = { file = ES.WHATS_NEW_SHOTS .. "Page2", w = 1531, h = 1024 } },
    { title = "Fila", text = "c" } } }
  local pos = 1
  while ES.WHATS_NEW[pos] and ES.CompareVersions(ES.WHATS_NEW[pos].version, v.version) > 0 do pos = pos + 1 end
  table.insert(ES.WHATS_NEW, pos, v)
  local ok, err = pcall(fn, v)
  table.remove(ES.WHATS_NEW, pos)
  if not ok then error(err, 0) end
end

test("novedades con imagen: la textura está en Media y su parte útil cabe en el lienzo", function()
  for _, v in ipairs(ES.WHATS_NEW) do
    for _, it in ipairs(v.items) do
      if it.image then
        local file = it.image.file:match("^Interface\\AddOns\\CraftersJournal\\(.+)$")
        expect(file, "%s: la imagen no está en el addon (%s)", it.title, it.image.file)
        local path = file:gsub("\\", "/") .. ".tga"
        local w, h = TgaSize(path)
        expect(w, "%s: falta %s", it.title, path)
        expect(w == 2048 and h == 1024, "%s: %s mide %sx%s (el lienzo es 2048x1024)", it.title, path, tostring(w), tostring(h))
        expect(it.image.w > 0 and it.image.w <= 2048 and it.image.h > 0 and it.image.h <= 1024,
          "%s: parte útil %dx%d fuera del lienzo", it.title, it.image.w, it.image.h)
      end
    end
  end
end, { boot = false })

test("ya no van en el addon las imágenes de Inversiones y Pestañas (12 MB)", function()
  for _, name in ipairs({ "Investments", "Tabs" }) do
    expect(not TgaSize("Media/WhatsNew/" .. name .. ".tga"), "sigue Media/WhatsNew/%s.tga", name)
  end
  for _, it in ipairs(Notes("0.66.0").items) do
    expect(not it.image, "0.66.0: «%s» sigue con imagen", it.title)
  end
end, { boot = false })

test("páginas: la imagen, grande, nítida, centrada y sin deformar", function()
  local S = ES.WHATS_NEW_SIZES.pages
  -- Mayor que la principal (840x612) y dentro de la pantalla más pequeña (768 de alto)
  expect(S.w >= 840 and S.h >= 612 and S.h <= 700, "ventana de las páginas: %dx%d", S.w, S.h)
  local R = ES.WHATS_NEW_SIZES.rows
  expect(R.w == 540 and R.h == 500, "sin imágenes, la ventana cambió de tamaño: %dx%d", R.w, R.h)
  WithImageVersion(function(v)
    local items = ES.WhatsNewItems({ v })
    expect_eq(#items, 2, "páginas")
    expect_eq(items[1].title, "Página 1", "primera página")
    expect_eq(items[2].title, "Página 2", "segunda página")
    for i, it in ipairs(items) do
      local img = ES.WhatsNewPageLayout(it.image, S).img
      local want, got = it.image.w / it.image.h, img.w / img.h
      expect(math.abs(want - got) < 0.01, "%d: imagen deformada (%.3f en vez de %.3f)", i, got, want)
      -- Que se vea: a toda ventana (antes, con texto debajo, a 496 de alto)
      expect(img.h >= 560, "%d: imagen pequeña (%dx%d)", i, img.w, img.h)
      -- Nítida: la textura tiene al menos 1,5 píxeles por unidad de interfaz (en 1080p
      -- cada unidad son ~1,4 px reales: no se estira)
      expect(it.image.w >= img.w * 1.5, "%d: textura de %d px para %d unidades: se ve borrosa", i, it.image.w, img.w)
      expect(math.abs(img.x + img.w / 2 - S.w / 2) <= 1, "%d: imagen no centrada", i)
      expect(img.x >= 14 and img.x + img.w <= S.w - 14, "%d: la imagen se sale por el lado", i)
      -- (la X de cerrar, arriba a la derecha: 32x32 a 2 px del borde)
      expect(img.x + img.w <= S.w - 34 or img.y >= 34, "%d: la imagen pisa la X de cerrar", i)
      -- (los botones de abajo: hasta 42 px del borde)
      expect(img.y + img.h <= S.h - 42, "%d: la imagen pisa los botones", i)
    end
  end)
end, { boot = false })

test("con imágenes, solo las de imagen; sin ellas, filas y el tope de siempre", function()
  WithImageVersion(function()
    -- Te saltaste versiones: aun así, solo las dos de imagen (sin filas de la 0.66.0 ni la 0.63.0)
    local items = ES.WhatsNewItems(ES:WhatsNewSince("0.62.0", IMG_VERSION))
    expect_eq(#items, 2, "novedades en la ventana")
    expect(items[1].image and items[2].image, "sale una sin imagen")
  end)
  -- La 0.66.0 sin sus imágenes: filas, con la destacada (Inversiones) primero
  local mid = ES.WhatsNewItems({ Notes("0.66.0") })
  expect_eq(#mid, 2, "novedades de la 0.66.0")
  expect_eq(mid[1].title, "Nueva pestaña: Inversiones", "la destacada no va primero")
  -- Una versión sin imágenes: solo filas, como antes, con las destacadas primero
  local old = ES.WhatsNewItems(ES:WhatsNewSince("0.60.0", "0.61.0"))
  expect(#old > 0, "sin notas de la 0.61.0")
  expect(old[1].top, "la destacada no va primero")
  for i, it in ipairs(old) do expect(not it.image, "0.61.0, novedad %d con imagen", i) end
end, { boot = false })

test("la ventana con imágenes: dos páginas, se pasan y se cierra en la última", function()
  WithImageVersion(function()
    SetVersion(IMG_VERSION)
    ES.db.whatsNewSeen = "0.62.0" -- (te saltaste la 0.63.0 y la 0.66.0: aun así, sin sus filas)
    ES:CheckWhatsNew()
    local f = expect(ES.WhatsNewFrame(), "no sale la ventana de novedades")
    expect(f:IsShown(), "la ventana no se ve")
    expect(f.size == ES.WHATS_NEW_SIZES.pages, "la ventana no es del tamaño de la principal")
    expect(f.page:IsShown() and not f.list:IsShown() and not f.head:IsShown(), "no salen las páginas solas")
    expect(not f.choiceView:IsShown(), "sale la diapositiva de la elección")
    for _, l in ipairs(f.lines) do expect(not l:IsShown(), "sobra una fila") end
    expect_eq(#f.pages, 2, "páginas")
    expect_eq(f.pageIndex, 1, "empieza en la primera")
    expect(f.page.imageFile:find("Page1", 1, true), "la primera no es la 1: %s", f.page.imageFile)
    expect_eq(f.page.label:GetText(), "1 / 2", "contador")
    expect_eq(f.ok:GetText(), ES.L["Siguiente"], "botón en la primera")
    -- La rueda hacia arriba en la primera: nada
    f.page:GetScript("OnMouseWheel")(f.page, 1)
    expect_eq(f.pageIndex, 1, "la rueda pasó de la primera hacia atrás")
    -- Siguiente: a la segunda (la ventana sigue abierta)
    f.ok:GetScript("OnClick")(f.ok)
    expect(f:IsShown(), "Siguiente cerró la ventana")
    expect_eq(f.pageIndex, 2, "Siguiente no pasó de página")
    expect(f.page.imageFile:find("Page2", 1, true), "la segunda no es la 2: %s", f.page.imageFile)
    expect_eq(f.page.label:GetText(), "2 / 2", "contador")
    expect_eq(f.ok:GetText(), ES.L["¡Entendido!"], "botón en la última")
    -- Clic en la imagen en la última: nada; la flecha de atrás vuelve a la primera
    f.page.image:GetScript("OnClick")(f.page.image)
    expect_eq(f.pageIndex, 2, "el clic en la última imagen pasó de página")
    f.page.prev:GetScript("OnClick")(f.page.prev)
    expect_eq(f.pageIndex, 1, "la flecha de atrás no vuelve")
    f.page.image:GetScript("OnClick")(f.page.image)
    expect_eq(f.pageIndex, 2, "el clic en la imagen no pasa")
    -- ¡Entendido! en la última: se cierra y suelta la imagen (SetTexture(nil): el juego
    -- libera la textura en vez de guardarla)
    local released
    f.page.tex.SetTexture = function(_, file) released = (file == nil) end
    f.ok:GetScript("OnClick")(f.ok)
    expect(not f:IsShown(), "¡Entendido! no cierra en la última")
    expect(released, "al cerrar no se suelta la imagen")
    expect(f.page.imageFile == nil, "al cerrar sigue apuntada la imagen")
    f.page.tex.SetTexture = nil -- (vuelve el del simulador)
    -- Al volver a abrir, la imagen se pone otra vez
    ES:ShowWhatsNew(ES:WhatsNewSince("0.62.0", IMG_VERSION), true)
    expect(f.page.imageFile and f.page.imageFile:find("Page1", 1, true), "al volver a abrir no hay imagen")
    f:Hide()
    -- Después, una versión sin imágenes: la ventana de siempre, sin páginas y con filas
    ES:ShowWhatsNew(ES:WhatsNewSince("0.60.0", "0.61.0"), true)
    expect(f.size == ES.WHATS_NEW_SIZES.rows, "sin imágenes, la ventana no vuelve a su tamaño")
    expect(not f.page:IsShown() and f.list:IsShown() and f.head:IsShown(), "quedan las páginas")
    expect(f.lines[1] and f.lines[1]:IsShown(), "no salen las filas")
    expect_eq(f.ok:GetText(), ES.L["¡Entendido!"], "botón sin páginas")
    f:Hide()
  end)
end, { state = "scan" })

---------------------------------------------------------------------------
-- Novedad con elección: escanear con Auctionator o solo con Crafter's Journal
---------------------------------------------------------------------------
test("novedad con elección: de la versión más nueva y su opción es de varias casillas", function()
  local version, it = ChoiceVersion()
  expect(version, "no hay novedad con la elección noAuctionator")
  expect(it.top, "la novedad de Auctionator no es destacada")
  expect_eq(it.title, "Ahora puedes escoger el modo de escaneo para Crafter's Journal", "título")
  expect_eq(ES.CompareVersions(version, ES.WHATS_NEW[1].version), 0, "no es de la versión más nueva")
  for _, v in ipairs(ES.WHATS_NEW) do
    for _, item in ipairs(v.items) do
      if item.choice then
        local found
        for _, o in ipairs(ES.OPTIONS) do if o.key == item.choice then found = o end end
        expect(found, "%s: la elección %s no es una opción", v.version, item.choice)
        expect(found and found.kind == "radio" and #found.choices == 2, "%s: la elección %s no es de dos casillas", v.version, item.choice)
      end
    end
  end
end, { boot = false })

test("novedad con elección: sale sola, sin las páginas de Inversiones y Pestañas", function()
  local version = ChoiceVersion()
  local items = ES.WhatsNewItems(ES:WhatsNewSince("0.62.0", version))
  expect_eq(#items, 1, "novedades en la ventana")
  expect_eq(items[1].choice, "noAuctionator", "la que sale")
end, { boot = false })

-- La diapositiva de la elección: sus dos fichas (Auctionator, Crafter's Journal)
local function ChoiceSlide()
  local version = ChoiceVersion()
  ES:ShowWhatsNew({ Notes(version) }, true)
  local f = expect(ES.WhatsNewFrame(), "no sale la ventana")
  local v = f.choiceView
  expect(f:IsShown() and v:IsShown(), "no se ve la diapositiva")
  expect(f.size == ES.WHATS_NEW_SIZES.choice, "la ventana no es la pequeña")
  local S, R = ES.WHATS_NEW_SIZES.choice, ES.WHATS_NEW_SIZES.rows
  expect(S.w <= R.w and S.h < R.h, "la diapositiva no es más pequeña que la lista: %dx%d", S.w, S.h)
  expect(not f.page:IsShown() and not f.list:IsShown() and not f.head:IsShown(), "sale algo más que la diapositiva")
  expect_eq(v.title:GetText(), ES.L["Ahora puedes escoger el modo de escaneo para Crafter's Journal"], "título")
  -- Sin icono, y el panel marrón de las pestañas del addon (con su margen) sobre el
  -- fondo oscuro: el título y las fichas van dentro
  expect(v.icon == nil, "la diapositiva lleva icono")
  expect(v.panel and v.panel:IsVisible(), "sin el panel marrón")
  expect(v.title:GetParent() == v.panel and v.tiles[1]:GetParent() == v.panel, "el título o las fichas no van en el panel")
  local atr, cj = v.tiles[1], v.tiles[2]
  expect(atr:IsShown() and cj:IsShown(), "no salen las dos fichas")
  expect_eq(atr.name:GetText(), "Auctionator", "primera ficha")
  expect_eq(cj.name:GetText(), "Crafter's Journal", "segunda ficha")
  expect_eq(f.ok:GetText(), ES.L["¡Entendido!"], "botón")
  return f, atr, cj
end

test("novedad con elección: con Auctionator, marcada Auctionator; solo una y cambia el modo al momento", function()
  InstallAuctionator()
  local f, atr, cj = ChoiceSlide()
  expect(atr.can and cj.can, "con Auctionator, alguna en gris")
  -- Bajo cada casilla, qué hace (corto)
  expect_eq(atr.off:GetText(), ES.L["Un solo escaneo para los dos addons. Inversiones usa su historial de precios."], "línea de Auctionator")
  expect_eq(cj.off:GetText(), ES.L["Escanea por su cuenta y solo usa sus propios datos. No hace falta ningún addon más."], "línea de Crafter's Journal")
  expect(atr.cb:GetChecked() and not cj.cb:GetChecked(), "por defecto no está marcada solo Auctionator")
  -- Clic en la ficha de Crafter's Journal: al momento y sin cerrar la ventana
  cj:GetScript("OnClick")(cj)
  expect_eq(ES.db.noAuctionator, true, "Crafter's Journal no se guarda")
  expect(not ES.Scanner.UsesAuctionator(), "con Crafter's Journal se sigue usando Auctionator")
  expect(cj.cb:GetChecked() and not atr.cb:GetChecked(), "marcar Crafter's Journal no desmarca Auctionator")
  expect(f:IsShown(), "elegir cerró la ventana")
  -- Pulsar la casilla marcada no la quita
  cj.cb:SetChecked(false)
  cj.cb:GetScript("OnClick")(cj.cb)
  expect(cj.cb:GetChecked() and not atr.cb:GetChecked(), "pulsar la marcada la desmarca")
  expect_eq(ES.db.noAuctionator, true, "pulsar la marcada cambia el modo")
  -- La casilla de Auctionator: vuelve
  atr.cb:SetChecked(true)
  atr.cb:GetScript("OnClick")(atr.cb)
  expect_eq(ES.db.noAuctionator, nil, "Auctionator otra vez no se guarda")
  expect(ES.Scanner.UsesAuctionator(), "Auctionator otra vez, no se usa Auctionator")
  expect(atr.cb:GetChecked() and not cj.cb:GetChecked(), "marcar Auctionator no desmarca Crafter's Journal")
  -- Al volver a abrir, dice lo guardado
  f:Hide()
  ES:SetOption("noAuctionator", false)
  f, atr, cj = ChoiceSlide()
  expect(cj.cb:GetChecked() and not atr.cb:GetChecked(), "al volver a abrir no dice lo guardado")
  f:Hide()
end, { state = "scan" })

test("novedad con elección: sin Auctionator, marcada Crafter's Journal y Auctionator en gris", function()
  local f, atr, cj = ChoiceSlide()
  expect(cj.cb:GetChecked() and not atr.cb:GetChecked(), "no está marcada solo Crafter's Journal")
  expect(not atr.can and atr.cb._enabled == false and atr._enabled == false, "sin Auctionator, su ficha se puede pulsar")
  expect(cj.can, "Crafter's Journal en gris")
  expect_eq(atr.off:GetText(), ES.L["No está instalado: Crafter's Journal escanea solo."], "Auctionator no dice que no está")
  expect_eq(cj.off:GetText(), ES.L["Escanea por su cuenta y solo usa sus propios datos. No hace falta ningún addon más."], "línea de Crafter's Journal")
  -- (aunque llegue el clic, no cambia nada)
  atr:GetScript("OnClick")(atr)
  expect(not atr.cb:GetChecked() and cj.cb:GetChecked(), "el clic en Auctionator gris la marca")
  expect(not ES.Scanner.UsesAuctionator(), "sin Auctionator, se usa Auctionator")
  f:Hide()
end, { state = "scan" })

test("novedad con elección: quien se saltó versiones desde la 0.62.0 solo ve la diapositiva", function()
  InstallAuctionator()
  local version = ChoiceVersion()
  SetVersion(version)
  ES.db.whatsNewSeen = "0.62.0"
  ES:CheckWhatsNew()
  local f = expect(ES.WhatsNewFrame(), "no sale la ventana")
  expect(f.choiceView:IsShown() and f.size == ES.WHATS_NEW_SIZES.choice, "no sale la diapositiva")
  expect(not f.page:IsShown() and f.pages == nil and f.page.imageFile == nil, "salen las páginas de imagen")
  for _, l in ipairs(f.lines) do expect(not l:IsShown(), "sobra una fila") end
  -- ¡Entendido! la cierra; luego una versión con imágenes ya no enseña la diapositiva
  f.ok:GetScript("OnClick")(f.ok)
  expect(not f:IsShown(), "¡Entendido! no la cierra")
  ES:ShowWhatsNew(ES:WhatsNewSince("0.62.0", "0.66.0"), true)
  expect(not f.choiceView:IsShown() and f.list:IsShown(), "sin elección sigue la diapositiva")
  f:Hide()
end, { state = "scan" })

test("versión nueva: sale una vez", function()
  SetVersion(Latest())
  ES.db.whatsNewSeen = list and nil or (ES.WHATS_NEW[2] and ES.WHATS_NEW[2].version or "0.1.0")
  ES:CheckWhatsNew()
  local f = expect(ES.WhatsNewFrame(), "no sale la ventana de novedades")
  expect(f:IsShown(), "la ventana no se ve")
  expect_eq(ES.db.whatsNewSeen, Latest(), "versión vista")
  f:Hide()
  ES:CheckWhatsNew()
  expect(not f:IsShown(), "sale otra vez con la misma versión")
end, { state = "scan" })

test("instalación nueva: no hay novedades que enseñar", function()
  SetVersion(Latest())
  ES:CheckWhatsNew()
  local f = ES.WhatsNewFrame()
  expect(not (f and f:IsShown()), "sale a quien acaba de instalar")
  expect_eq(ES.db.whatsNewSeen, Latest(), "no apunta la versión")
end, { state = "empty" })

test("«no volver a mostrar» y la opción la apagan", function()
  SetVersion(Latest())
  ES.db.whatsNewSeen = "0.1.0"
  ES.db.noWhatsNew = true
  ES:CheckWhatsNew()
  local f = ES.WhatsNewFrame()
  expect(not (f and f:IsShown()), "sale con la opción apagada")
end, { state = "scan" })

test("copia de desarrollo: no sale sola", function()
  SetVersion("@project-version@")
  expect_eq(ES.AddonVersion(), "dev", "versión de desarrollo")
  ES.db.whatsNewSeen = "0.1.0"
  ES:CheckWhatsNew()
  local f = ES.WhatsNewFrame()
  expect(not (f and f:IsShown()), "sale en la copia de desarrollo")
end, { state = "scan" })

test("al entrar sale a los pocos segundos", function()
  SetVersion(Latest())
  local db = Fixtures.State("scan")
  db.whatsNewSeen = "0.1.0"
  Boot(db)
  RunTimers()
  local f = ES.WhatsNewFrame()
  expect(f and f:IsShown(), "no salió al entrar")
end, { boot = false })
