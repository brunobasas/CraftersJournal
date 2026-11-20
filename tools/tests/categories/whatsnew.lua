-- Novedades: la ventana con lo nuevo, una vez por versión

local function SetVersion(v)
  GetAddOnMetadata = function(_, field) if field == "Version" then return v end end
end

local function Latest() return ES.WHATS_NEW[1].version end

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
      expect(type(it.title) == "string" and it.title ~= "" and type(it.text) == "string", "%s: novedad sin título o texto", v.version)
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

test("novedades con imagen: la textura está en Media y su parte útil cabe en el lienzo", function()
  local n = 0
  for _, v in ipairs(ES.WHATS_NEW) do
    for _, it in ipairs(v.items) do
      if it.image then
        n = n + 1
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
  expect(n >= 2, "las dos novedades de la 0.66.0 deben llevar imagen (hay %d)", n)
end, { boot = false })

test("páginas: la imagen, grande, nítida, centrada y sin deformar", function()
  local S = ES.WHATS_NEW_SIZES.pages
  -- Mayor que la principal (840x612) y dentro de la pantalla más pequeña (768 de alto)
  expect(S.w >= 840 and S.h >= 612 and S.h <= 700, "ventana de las páginas: %dx%d", S.w, S.h)
  local R = ES.WHATS_NEW_SIZES.rows
  expect(R.w == 540 and R.h == 500, "sin imágenes, la ventana cambió de tamaño: %dx%d", R.w, R.h)
  local items = ES.WhatsNewItems({ ES.WHATS_NEW[1] })
  expect_eq(items[1].title, "Nueva pestaña: Inversiones", "primera página")
  expect_eq(items[2].title, "Ordena y oculta las pestañas", "segunda página")
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
end, { boot = false })

test("con imágenes, solo las de imagen; sin ellas, filas y el tope de siempre", function()
  -- Te saltaste versiones: aun así, solo Inversiones y Pestañas (sin filas de la 0.63.0)
  local items = ES.WhatsNewItems(ES:WhatsNewSince("0.62.0", "0.66.0"))
  expect_eq(#items, 2, "novedades en la ventana")
  expect(items[1].image and items[2].image, "sale una sin imagen")
  -- Una versión sin imágenes: solo filas, como antes, con las destacadas primero
  local old = ES.WhatsNewItems(ES:WhatsNewSince("0.60.0", "0.61.0"))
  expect(#old > 0, "sin notas de la 0.61.0")
  expect(old[1].top, "la destacada no va primero")
  for i, it in ipairs(old) do expect(not it.image, "0.61.0, novedad %d con imagen", i) end
end, { boot = false })

test("la ventana con la 0.66.0: dos páginas, se pasan y se cierra en la última", function()
  SetVersion("0.66.0")
  ES.db.whatsNewSeen = "0.62.0" -- (te saltaste la 0.63.0: aun así, sin sus filas)
  ES:CheckWhatsNew()
  local f = expect(ES.WhatsNewFrame(), "no sale la ventana de novedades")
  expect(f:IsShown(), "la ventana no se ve")
  expect(f.size == ES.WHATS_NEW_SIZES.pages, "la ventana no es del tamaño de la principal")
  expect(f.page:IsShown() and not f.list:IsShown() and not f.head:IsShown(), "no salen las páginas solas")
  for _, l in ipairs(f.lines) do expect(not l:IsShown(), "sobra una fila") end
  expect_eq(#f.pages, 2, "páginas")
  expect_eq(f.pageIndex, 1, "empieza en la primera")
  expect(f.page.imageFile:find("Investments", 1, true), "la primera no es Inversiones: %s", f.page.imageFile)
  expect_eq(f.page.label:GetText(), "1 / 2", "contador")
  expect_eq(f.ok:GetText(), ES.L["Siguiente"], "botón en la primera")
  -- La rueda hacia arriba en la primera: nada
  f.page:GetScript("OnMouseWheel")(f.page, 1)
  expect_eq(f.pageIndex, 1, "la rueda pasó de la primera hacia atrás")
  -- Siguiente: a la segunda (la ventana sigue abierta)
  f.ok:GetScript("OnClick")(f.ok)
  expect(f:IsShown(), "Siguiente cerró la ventana")
  expect_eq(f.pageIndex, 2, "Siguiente no pasó de página")
  expect(f.page.imageFile:find("Tabs", 1, true), "la segunda no es Pestañas: %s", f.page.imageFile)
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
  ES:ShowWhatsNew(ES:WhatsNewSince("0.62.0", "0.66.0"), true)
  expect(f.page.imageFile and f.page.imageFile:find("Investments", 1, true), "al volver a abrir no hay imagen")
  f:Hide()
  -- Después, una versión sin imágenes: la ventana de siempre, sin páginas y con filas
  ES:ShowWhatsNew(ES:WhatsNewSince("0.60.0", "0.61.0"), true)
  expect(f.size == ES.WHATS_NEW_SIZES.rows, "sin imágenes, la ventana no vuelve a su tamaño")
  expect(not f.page:IsShown() and f.list:IsShown() and f.head:IsShown(), "quedan las páginas")
  expect(f.lines[1] and f.lines[1]:IsShown(), "no salen las filas")
  expect_eq(f.ok:GetText(), ES.L["¡Entendido!"], "botón sin páginas")
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
