local ADDON_NAME, ES = ...
local L = ES.L

---------------------------------------------------------------------------
-- Novedades: al entrar con una versión nueva del addon sale una ventana con lo nuevo
-- de las versiones que no has visto, todo en una sola lista (sin cabeceras de versión;
-- como mucho ES.WHATS_NEW_MAX_ITEMS, lo más nuevo primero). Una vez por versión: se
-- guarda la última vista en ES.db.whatsNewSeen (de la cuenta, no del personaje).
--   * Instalación nueva (sin nada guardado): no sale; se apunta la versión actual.
--   * Versión sin notas en ES.WHATS_NEW: no sale; se apunta igual.
-- Para escribir las notas: /cj whatsnew [versión] la abre cuando quieras, sin tocar lo
-- visto. Solo en tu copia: el comando está en DevTools.lua, que no se publica.
--
-- Cómo añadir una versión: una entrada nueva ARRIBA en ES.WHATS_NEW, con la versión
-- de la etiqueta que la publicará (sin la v; el .toc la recibe al empaquetar). Los textos van en español y su traducción en
-- Locales/enUS.lua (como el resto del addon).
---------------------------------------------------------------------------

-- Lo nuevo de cada versión, de la más nueva a la más antigua. `items`: { icon, title,
-- text, top, image }. `top = true`: destacada, la primera de la lista aunque sea de una
-- versión anterior (si te saltaste versiones, todo sale junto: ver ShowWhatsNew)
-- `image`: una imagen que lo explica sola (título y la función, en inglés). Cada
-- novedad con imagen es una página: solo la imagen, a toda ventana, y flechas para
-- pasar; y solo salen esas (las demás, no). Su `text` no se ve en la página (sí si
-- algún día se quita la imagen y sale como fila). { file, w, h }: la textura de
-- Media/WhatsNew/ (lienzo de 2048x1024) y el tamaño útil dentro de él. Se generan con
-- tools/gen_whatsnew_images.py desde los PNG de tools/whatsnew/ (que imprime w y h).
-- Ahora ninguna lleva imagen: las de la 0.66.0 (Inversiones y Pestañas) se quitaron del
-- addon (12 MB); sus PNG siguen en tools/whatsnew/
-- `choice`: la clave de una opción de varias casillas de ES.OPTIONS (kind = "radio",
-- Options.lua) para elegirla ahí mismo. Una novedad con elección es lo único que sale en
-- la ventana (ver WhatsNewItems): una diapositiva pequeña con su título y, debajo, una
-- casilla grande por opción, una al lado de otra, con la lógica de /cj opciones (una sola
-- marcada, las que no se pueden en gris con su offDesc). Su `text` no se ve
local SHOTS = "Interface\\AddOns\\CraftersJournal\\Media\\WhatsNew\\"
ES.WHATS_NEW_SHOTS = SHOTS -- (las pruebas montan una versión con imágenes)
ES.WHATS_NEW = {
  {
    version = "0.72.2",
    items = {
      { top = true, title = "Ahora puedes escoger el modo de escaneo para Crafter's Journal",
        choice = "noAuctionator" },
    },
  },
  {
    version = "0.66.0",
    items = {
      { icon = ES.Invest.ICON, top = true, title = "Nueva pestaña: Inversiones",
        text = "Apunta lo que compras para revender (cantidad y precio, por unidad o total) y te dice tu precio medio y cuánto ganas o pierdes, neto de la comisión de la AH (5%)." },
      { icon = "Interface\\Icons\\INV_Misc_Book_09", title = "Ordena y oculta las pestañas",
        text = "En opciones, Pestañas: arrastra las pestañas para ordenarlas y oculta las que no uses. El addon se abre en la de arriba." },
    },
  },
  {
    version = "0.63.0",
    items = {
      { icon = "Interface\\Icons\\INV_Misc_Bag_10", title = "La bolsa de componentes cuenta",
        text = "Lo que llevas en la bolsa de componentes cuenta en la ruta, el Inventario y Ganar dinero, y \"Recoge el correo\" se completa aunque lo recogido vaya a esa bolsa." },
      { icon = "Interface\\Icons\\Trade_Engineering", title = "Recetas con dos herramientas",
        text = "Los cascos de ingeniería piden el Blacksmith Hammer y la Arclight Spanner, y la ruta ya pide las dos." },
      { icon = "Interface\\Icons\\INV_Misc_Coin_02", title = "Gasta lo que sobra",
        text = "Al acabar un paso, si te sobran materiales y fabricar con ellos deja más que venderlos, la ruta te lo propone." },
      { icon = "Interface\\Icons\\INV_Scroll_03", title = "Recetas de lo intermedio",
        text = "Si algo intermedio pide una receta que no sabes (Stonescale Oil), la ruta tiene una fila para aprenderla y cuenta su precio." },
      { icon = "Interface\\Icons\\INV_Misc_Coin_01", title = "Confirmar al anunciar, más fiable",
        text = "El Sí anuncia antes de cerrar el aviso, el aviso se cierra al cerrar la AH o el vendedor, y ya no dice \"Anunciados\" si la AH no responde." },
    },
  },
  {
    version = "0.62.0",
    items = {
      { icon = "Interface\\Icons\\INV_Misc_PocketWatch_01", title = "Rutas que no se quedan en el 99%",
        text = "Si el cálculo de una ruta falla, la página lo dice en vez de quedarse en \"Calculando la ruta… 99%\". E Ingeniería 1-300 vuelve a calcularse rápido." },
      { icon = "Interface\\Icons\\Trade_Engineering", title = "Herramientas en la lista de la compra",
        text = "Si un paso pide una herramienta que no llevas (Arclight Spanner), va a la lista de la compra en vez de darla por hecha." },
      { icon = "Interface\\Icons\\Trade_Alchemy", title = "Transmutaciones en otros idiomas",
        text = "Con el juego en español, alemán o francés, la ruta ya no pide 186 transmutaciones seguidas: reconoce su enfriamiento." },
      { icon = "Interface\\Icons\\Spell_Holy_BorrowedTime", title = "Sin errores en mazmorras",
        text = "Las compras de la AH se leen del chat solo con la AH abierta: en mazmorras y en combate ya no salen errores." },
    },
  },
  {
    version = "0.61.0",
    items = {
      { icon = "Interface\\Icons\\INV_Misc_Spyglass_02", top = true, title = "Nuevo: asistente de ruta (beta)",
        text = "Con una ruta empezada, un banner pequeño te dice qué toca: fabricar, comprar en la AH o al vendedor, recoger el correo o entrenar. Un clic lo hace o te lleva. Se abre con el botón junto a Dejar ruta o con /cj mini." },
      { icon = "Interface\\Icons\\INV_Misc_PocketWatch_01", title = "Cuánto se tarda en fabricar",
        text = "Cada paso de la ruta dice cuánto tardas en fabricarlo, y la franja de arriba el tiempo de toda la ruta." },
      { icon = "Interface\\Icons\\INV_Misc_Coin_02", title = "Lo que sacas vendiendo en la AH",
        text = "Bajo el total de la ruta, \"con AH\" dice lo que te quedaría si vendes lo fabricado como aconseja la vista Profit, en la AH y al vendedor." },
      { icon = "Interface\\Icons\\INV_Misc_Book_09", title = "Menos verdes en las rutas",
        text = "La ruta prefiere recetas seguras a tramos largos en verde: menos fabricaciones y menos viajes a comprar, por muy poco oro más." },
      { icon = "Interface\\Icons\\INV_Misc_Bag_10", title = "Compras por tandas en verde",
        text = "En las recetas verdes compra por tandas, con algo de margen, y \"esta tanda: N\" dice para cuántas te llega lo que llevas. El tamaño de la tanda se cambia en /cj opciones, Lista de compra." },
      { icon = "Interface\\Icons\\INV_Misc_Coin_17", title = "Vender, más fácil",
        text = "Vender todo vende todo de un clic, y lo que no tiene un precio fiable en la AH va al vendedor. Con Ctrl+clic derecho en una fila lo pasas de la AH al vendedor o al revés." },
    },
  },
  {
    version = "0.59.0",
    items = {
      { icon = "Interface\\Icons\\INV_Fabric_Moonrag_01", title = "Enfriamientos en el lote de hoy",
        text = "Las transmutaciones y la Mooncloth que tienes listas entran en el Lote de hoy, una cada vez, y vuelven solas cuando están otra vez listas. También salen en las recetas que podrías aprender." },
      { icon = "Interface\\Icons\\INV_Misc_Bag_10", title = "Confirmar antes de vender o comprar todo",
        text = "Vender todo, Comprar todo y vender al vendedor desde el Inventario preguntan antes. Cada aviso se quita con \"No volver a mostrar\" y se vuelve a activar en las opciones." },
      { icon = "Interface\\Icons\\INV_Scroll_03", title = "Quita recetas de Ganar dinero",
        text = "Con la X de una fila, Ganar dinero deja de proponerte esa receta (por ejemplo, si pide una estación que no tienes). Se recupera con la fila del final de la lista." },
      { icon = "Interface\\Icons\\INV_Misc_Spyglass_02", title = "Demanda de TSM",
        text = "Si tienes TSM con su app, Ganar dinero tiene en cuenta cuántas se venden al día en tu región y no te propone fabricar más de lo que se vende. Los mínimos se ajustan en las opciones de Ganar dinero." },
    },
  },
  {
    version = "0.58.0",
    items = {
      { icon = "Interface\\Icons\\INV_Misc_Gear_01", title = "Opciones en su propia ventana",
        text = "El engranaje junto al idioma abre las opciones, ordenadas por categorías: General y una por pestaña o ventana. Ya no están en el panel de AddOns del juego." },
      { icon = "Interface\\Icons\\INV_Misc_Bag_10", title = "Al vendedor, solo lo que no vale más en la AH",
        text = "Inventario y la ventana del vendedor ya no te proponen vender al vendedor lo que vale más en la AH. Si tu escaneo no tiene un objeto, se usa el precio de Auctionator o TSM." },
      { icon = "Interface\\Icons\\INV_Misc_Book_09", title = "En el tope de tu rango, a entrenar",
        text = "Si llegas al tope de tu rango sin el siguiente, el paso actual de la ruta pasa a ser entrenarlo, en vez de fabricar algo que ya no sube puntos." },
      { icon = "Interface\\Icons\\INV_Misc_Note_01", title = "La ruta explica su segunda receta",
        text = "Si hay otra receta más barata en oro y la ruta no la usa, el paso dice por qué: más fabricaciones, un paso más o aprenderla no compensa." },
    },
  },
  {
    version = "0.57.0",
    items = {
      { icon = "Interface\\Icons\\INV_Misc_Coin_03", title = "Precios del vendedor, siempre los del juego",
        text = "El addon ya no deduce lo que paga el vendedor del dinero que te entra al vender: con dos ventas cobradas juntas podía apuntar el doble, y Ganar dinero prometía de más. Ahora usa siempre el precio del juego." },
      { icon = "Interface\\Icons\\INV_Misc_Book_11", title = "Aprender una receta, solo si compensa",
        text = "La ruta ya no te manda al instructor a aprender una receta para unas pocas fabricaciones que ahorran unas monedas: esos puntos los hace con la receta de al lado, salvo que ahorre más de 5s." },
      { icon = "Interface\\Icons\\Spell_Holy_BorrowedTime", title = "Se ve cuándo esperar en la AH",
        text = "Mientras se escanea la AH, la ventana de vender queda tapada con un reloj de arena y el progreso: así no anuncias a precios viejos sin querer." },
    },
  },
  {
    version = "0.56.0",
    items = {
      { icon = "Interface\\Icons\\INV_Misc_Coin_17", top = true, title = "Nueva pestaña: Merchant's Favor",
        text = "Con qué llenar tus Waylaid Crates al menor coste y qué cajas de la AH dan el Favor más barato por punto. Clic en una fila para añadirlo a la lista de compra." },
      { icon = "Interface\\Icons\\Spell_Nature_TimeStop", title = "Más fluido",
        text = "Sin tirones al acabar un escaneo ni al entrar, fabricar en serie va fluido y el addon apenas trabaja mientras juegas por el mundo." },
      { icon = "Interface\\Icons\\INV_Misc_PocketWatch_01", title = "Cuánto se tarda en fabricar",
        text = "Cada paso de la ruta dice cuánto se tarda en fabricarlo (en naranja si es lento) y el total, el de toda la ruta. \"Menos fabricaciones\" ahora también evita las recetas lentas." },
      { icon = "Interface\\Icons\\INV_Misc_Coin_02", title = "Ganar dinero, más fiable",
        text = "Solo fabrica lo intermedio con recetas que sabes y dice qué fabricar antes. Enseña cuánto ya llevas en las bolsas, y las filas del lote no cambian de sitio al pulsar - o +." },
      { icon = "Interface\\Icons\\INV_Misc_Gear_01", title = "Quitar una ventana, en un clic",
        text = "El engranaje de las ventanas junto al vendedor, la AH y la profesión abre un menú con \"No mostrar esta ventana\", sin buscarla en las opciones." },
      { icon = "Interface\\Icons\\INV_Misc_Spyglass_03", title = "Buscar en la AH con Mayús+clic",
        text = "Mayús+clic en un objeto del addon lo busca en la AH (o lo enlaza en el chat). Y la lista de compra junto a la AH tiene una X en cada lista para quitarla." },
    },
  },
  {
    version = "0.55.0",
    items = {
      { icon = "Interface\\Icons\\INV_Misc_Book_09", title = "Ahora en alemán y francés",
        text = "Textos, recetas y objetos en alemán y francés, con los nombres del juego. Se cambia con el selector de idioma de arriba. Si ves una traducción mejorable, dínoslo en Discord." },
      { icon = "Interface\\Icons\\INV_Misc_Gear_01", title = "Cada ventana, con su propia opción",
        text = "Las ventanas que salen solas junto al vendedor, la Casa de Subastas y la profesión tienen un engranaje que abre las opciones. La lista de compra y la de vender en la AH ya se quitan por separado." },
      { icon = "Interface\\Icons\\INV_Misc_Coin_01", title = "Confirmar antes de anunciar",
        text = "Al anunciar más de una unidad de golpe se pregunta antes cuántas y a qué precio. Así un clic sin querer no anuncia un montón. Se puede desactivar." },
      { icon = "Interface\\Icons\\INV_Misc_PocketWatch_01", title = "La AH sin tirones",
        text = "Al acabar un escaneo (el tuyo o el de otro addon, como Auctionator) los precios se guardan poco a poco y el juego ya no se congela. Nueva opción para no leer los escaneos de otros addons." },
      { icon = "Interface\\Icons\\Trade_Alchemy", title = "Rutas sin enfriamientos",
        text = "Las transmutaciones y el Mooncloth tienen enfriamiento: la ruta ya no pide 186 transmutaciones seguidas. Como mucho las usa para un punto." },
      { icon = "Interface\\Icons\\INV_Misc_Bag_10", title = "Lista de compra en su sitio",
        text = "Al cerrar la ventana de vender en la AH, la lista de compra se pega a la AH y no deja un hueco." },
    },
  },
}

-- (Core.lua: "0.64.0", "dev" en la copia de desarrollo o nil)
local function AddonVersion() return ES.AddonVersion() end

-- Compara "0.47.0" con "0.48.0" número a número: -1, 0 o 1 (lo que no es número, 0)
local function CompareVersions(a, b)
  local pa, pb = {}, {}
  for n in tostring(a or ""):gmatch("%d+") do pa[#pa + 1] = tonumber(n) end
  for n in tostring(b or ""):gmatch("%d+") do pb[#pb + 1] = tonumber(n) end
  for i = 1, math.max(#pa, #pb) do
    local x, y = pa[i] or 0, pb[i] or 0
    if x ~= y then return x < y and -1 or 1 end
  end
  return 0
end
ES.CompareVersions = CompareVersions

-- Notas de las versiones posteriores a `seen` hasta `current` (como mucho MAX_SHOWN, de
-- la más nueva a la más antigua). Sin `seen`: solo la de `current`
local MAX_SHOWN = 3
-- En la ventana, todas juntas en una lista (sin cabeceras de versión) y como mucho
-- estas: lo de la versión más nueva primero. Por eso, en cada versión, lo más
-- importante arriba
ES.WHATS_NEW_MAX_ITEMS = 6
function ES:WhatsNewSince(seen, current)
  local out = {}
  for _, v in ipairs(ES.WHATS_NEW) do
    local released = CompareVersions(v.version, current) <= 0 -- (no las de una versión aún sin publicar)
    local unseen
    if seen then unseen = CompareVersions(v.version, seen) > 0
    else unseen = CompareVersions(v.version, current) == 0 end
    if released and unseen then
      out[#out + 1] = v
      if #out >= MAX_SHOWN then break end
    end
  end
  return out
end

-- Las novedades que enseña la ventana, en su orden. Si alguna pide elegir algo (choice),
-- solo esa: su diapositiva, sola (la de la versión más nueva). Si alguna tiene imagen,
-- solo las que tienen imagen (en grande; las demás, aunque sean de versiones que te
-- saltaste, no salen: que lo grande no quede pequeño ni enterrado). Si no, las
-- destacadas (top = true: una pestaña nueva...) y luego el resto. En cada grupo, de la
-- versión más nueva a la más antigua, y como mucho WHATS_NEW_MAX_ITEMS en total
function ES.WhatsNewItems(notes)
  local items, withImage = {}, false
  for _, v in ipairs(notes or {}) do
    for _, it in ipairs(v.items) do
      if it.choice then return { it } end
      if it.image then withImage = true end
    end
  end
  local function Group(it)
    if withImage then return it.image and 1 or nil end
    return it.top == true and 1 or 2
  end
  for group = 1, 2 do
    for _, v in ipairs(notes or {}) do
      for _, it in ipairs(v.items) do
        if Group(it) == group and #items < ES.WHATS_NEW_MAX_ITEMS then items[#items + 1] = it end
      end
    end
  end
  return items
end

---------------------------------------------------------------------------
-- Ventana
---------------------------------------------------------------------------
local GOLD = { 0.96, 0.79, 0.25 }
local ARROWS = "Interface\\AddOns\\CraftersJournal\\Media\\Assistant\\" -- (las del asistente)
local frame

-- Dos formas: la de siempre, una lista de filas; y con novedades con imagen, páginas
-- (una imagen por página, toda la ventana, y flechas para pasar), en una ventana algo
-- mayor que la principal (UI.lua: 840x612) para que la imagen se vea bien; cabe en
-- cualquier pantalla (la interfaz mide al menos 768 de alto).
-- Medidas de la lista: arriba la cabecera (30 + 70 + 8), abajo el pie (52), y 10 de
-- margen del scroll arriba y abajo
-- (choice: la diapositiva de una novedad con elección, más pequeña que la lista)
local SIZES = { rows = { w = 540, h = 500 }, pages = { w = 900, h = 660 }, choice = { w = 520, h = 330 } }
for _, s in pairs(SIZES) do
  s.content = s.w - 28 - 24
  s.visible = s.h - 108 - 52 - 20
end
ES.WHATS_NEW_SIZES = SIZES
local GAP = 6
-- Página: margen de arriba (bajo la X de cerrar), de los lados y el pie (botones). La
-- textura es un lienzo de 2048x1024
local PAGE_TOP, PAGE_SIDE, PAGE_FOOT = 34, 14, 48
local CANVAS_W, CANVAS_H = 2048, 1024

-- Dónde va la imagen de una página (función pura, para las pruebas): { img = { x, y,
-- w, h } }, medido desde la esquina de arriba a la izquierda de la ventana. Lo más
-- grande que cabe con su proporción, centrada
function ES.WhatsNewPageLayout(image, size)
  size = size or SIZES.pages
  local ratio = (image.w or CANVAS_W) / (image.h or CANVAS_H)
  local h = size.h - PAGE_TOP - PAGE_FOOT
  local w = h * ratio
  if w > size.w - 2 * PAGE_SIDE then w = size.w - 2 * PAGE_SIDE; h = w / ratio end
  w, h = math.floor(w + 0.5), math.floor(h + 0.5)
  return { img = { x = math.floor((size.w - w) / 2), y = PAGE_TOP, w = w, h = h } }
end

-- La opción de ES.OPTIONS con esa clave (Options.lua)
local function OptionByKey(key)
  for _, o in ipairs(ES.OPTIONS or {}) do if o.key == key then return o end end
end

-- Diapositiva de una novedad con elección (it.choice): el título y, debajo, una ficha
-- por opción, una al lado de otra, con una casilla grande, el nombre y una línea corta
-- (su `short`). Como en /cj opciones (CreateRadio): una sola marcada, pulsar la marcada
-- no la quita y la que no se puede (Auctionator sin instalar) sale en gris con su
-- offDesc en lugar de la línea. Clic en la ficha o en la casilla: la elige al momento
local TILE_W, TILE_H, TILE_GAP = 210, 100, 20
local function CreateChoiceView(f)
  local UI = ES.UI
  local v = CreateFrame("Frame", nil, f)
  v:SetAllPoints()
  v:Hide()
  -- El fondo de las pestañas del addon: el panel marrón (BROWN.group) con su margen,
  -- sobre el fondo oscuro de la ventana; bajo la X de cerrar y encima de los botones
  v.panel = UI.Panel(v, UI.BROWN.group[1], UI.BROWN.group[2], UI.BROWN.group[3], UI.BROWN.group[4])
  v.panel:SetPoint("TOPLEFT", 14, -30)
  v.panel:SetPoint("BOTTOMRIGHT", -14, 52)
  v.title = UI.Label(v.panel, "", "GameFontNormalHuge")
  v.title:SetPoint("TOP", 0, -22)
  v.title:SetWidth(SIZES.choice.w - 80)
  v.title:SetJustifyH("CENTER")
  v.title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
  v.hint = UI.Label(v.panel, "", "GameFontDisableSmall")
  v.hint:SetPoint("BOTTOM", 0, 12)
  v.hint:SetWidth(SIZES.choice.w - 60)
  v.hint:SetJustifyH("CENTER")
  v.tiles = {}

  local function Pick(tile)
    local o, c = v.option, tile.choice
    if o and c and (not c.enabled or c.enabled()) and o.value() ~= c.on then ES:SetOption(o.key, c.on) end
    v:Refresh() -- (y vuelve a marcar la suya)
  end
  for i = 1, 2 do
    local t = CreateFrame("Button", nil, v.panel, "BackdropTemplate")
    t:SetSize(TILE_W, TILE_H)
    UI.RowStyle(t)
    t.cb = CreateFrame("CheckButton", nil, t, "UICheckButtonTemplate")
    t.cb:SetSize(40, 40)
    t.cb:SetPoint("TOPLEFT", 10, -10)
    t.name = UI.Label(t, "", "GameFontNormalLarge")
    t.name:SetPoint("LEFT", t.cb, "RIGHT", 4, 1)
    t.name:SetPoint("RIGHT", -8, 0)
    t.name:SetJustifyH("LEFT")
    t.name:SetWordWrap(false)
    t.off = UI.Label(t, "", "GameFontHighlightSmall")
    t.off:SetPoint("TOPLEFT", t.cb, "BOTTOMLEFT", 4, -2)
    t.off:SetPoint("RIGHT", -8, 0)
    t.off:SetJustifyH("LEFT")
    t:SetScript("OnClick", Pick)
    t.cb:SetScript("OnClick", function() Pick(t) end)
    t:SetScript("OnEnter", function(self)
      if self.can then self:SetBackdropBorderColor(unpack(UI.ROW_BORDER_HOVER)) end
    end)
    t:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(unpack(UI.ROW_BORDER)) end)
    v.tiles[i] = t
  end

  -- Rellena con la novedad `it` (su opción) y lo guardado
  function v:Fill(it)
    self.option = OptionByKey(it.choice)
    self.title:SetText(L[it.title])
    self.hint:SetText(L["Se cambia cuando quieras en /cj opciones, General."])
    self:Refresh()
  end
  function v:Refresh()
    local o = self.option
    local choices = o and o.choices or {}
    local current = o and o.value()
    local n = math.min(#choices, #self.tiles)
    local left = -((n * TILE_W + (n - 1) * TILE_GAP) / 2)
    for i, t in ipairs(self.tiles) do
      local c = choices[i]
      t.choice = i <= n and c or nil
      if t.choice then
        local can = not c.enabled or c.enabled()
        t.can = can
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", self.panel, "TOP", left + (i - 1) * (TILE_W + TILE_GAP), -96)
        t.cb:SetChecked(c.on == current)
        t.cb:SetEnabled(can)
        t:SetEnabled(can)
        t.name:SetText(c.text) -- (nombres de addons: no se traducen)
        if can then t.name:SetTextColor(1, 1, 1) else t.name:SetTextColor(0.5, 0.5, 0.5) end
        -- (debajo: qué hace; en gris, por qué no se puede)
        local line = (not can and c.offDesc) or c.short
        t.off:SetText(line and L[line] or "")
        if can then t.off:SetTextColor(0.78, 0.74, 0.66) else t.off:SetTextColor(0.5, 0.5, 0.5) end
        t:SetAlpha(can and 1 or 0.75)
        t:Show()
      else
        t:Hide()
      end
    end
  end
  return v
end

local function CreateWindow()
  local UI = ES.UI
  local BROWN = UI.BROWN
  local f = CreateFrame("Frame", "CraftersJournalWhatsNew", UIParent, "BackdropTemplate")
  f:SetSize(SIZES.rows.w, SIZES.rows.h)
  f:SetPoint("CENTER", 0, 40)
  -- El marco de la ventana principal: roca oscura con borde de diálogo
  f:SetBackdrop({
    bgFile = "Interface\\FrameGeneral\\UI-Background-Rock",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 16, edgeSize = 24,
    insets = { left = 6, right = 6, top = 6, bottom = 6 },
  })
  f:SetBackdropColor(0.045, 0.042, 0.037, 0.99)
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  tinsert(UISpecialFrames, "CraftersJournalWhatsNew") -- Escape la cierra
  f:Hide()

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -2, -2)
  close:SetScript("OnClick", function() f:Hide() end)

  -- Cabecera: icono del addon, "Novedades" y la versión (la tarjeta de las pestañas)
  local head = UI.Panel(f, BROWN.card[1], BROWN.card[2], BROWN.card[3], BROWN.card[4])
  head:SetPoint("TOPLEFT", 14, -30)
  head:SetPoint("TOPRIGHT", -14, -30)
  head:SetHeight(70)
  f.icon = head:CreateTexture(nil, "ARTWORK")
  f.icon:SetSize(46, 46)
  f.icon:SetPoint("LEFT", 12, 0)
  f.icon:SetTexture("Interface\\Icons\\Trade_BlackSmithing")
  f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  f.title = UI.Label(head, "", "GameFontNormalHuge")
  f.title:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 12, 0)
  f.title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
  f.sub = UI.Label(head, "", "GameFontHighlightSmall")
  f.sub:SetPoint("BOTTOMLEFT", f.icon, "BOTTOMRIGHT", 12, 2)
  f.sub:SetPoint("RIGHT", -12, 0)
  f.sub:SetJustifyH("LEFT")

  -- Lista con scroll (rueda e indicador, como las pestañas)
  local list = UI.Panel(f, BROWN.list[1], BROWN.list[2], BROWN.list[3], BROWN.list[4])
  list:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -8)
  list:SetPoint("BOTTOMRIGHT", -14, 52)
  local scroll = UI.WheelScroll(list)
  scroll:SetPoint("TOPLEFT", 10, -10)
  scroll:SetPoint("BOTTOMRIGHT", -14, 10)
  f.content = CreateFrame("Frame", nil, scroll)
  f.content:SetSize(SIZES.rows.content, 1)
  scroll:SetScrollChild(f.content)
  f.scroll = scroll
  f.indicator = UI.ScrollIndicator and UI.ScrollIndicator(scroll, f.content)
  f.lines = {}
  f.head, f.list = head, list

  -- Páginas (novedades con imagen): la imagen con un borde oscuro y, abajo, las flechas
  -- con "1 / 2". Clic en la imagen o la rueda también pasan
  local page = CreateFrame("Frame", nil, f)
  page:SetAllPoints()
  page:Hide()
  page.border = page:CreateTexture(nil, "BORDER")
  page.border:SetColorTexture(0, 0, 0, 0.9)
  page.image = CreateFrame("Button", nil, page)
  page.tex = page.image:CreateTexture(nil, "ARTWORK")
  page.tex:SetAllPoints()
  page.border:SetPoint("TOPLEFT", page.image, "TOPLEFT", -1, 1)
  page.border:SetPoint("BOTTOMRIGHT", page.image, "BOTTOMRIGHT", 1, -1)
  page.image:SetScript("OnClick", function() ES.WhatsNewTurn(1) end)
  page:EnableMouseWheel(true)
  page:SetScript("OnMouseWheel", function(_, delta) ES.WhatsNewTurn(delta < 0 and 1 or -1) end)
  page.label = UI.Label(page, "", "GameFontNormal")
  page.label:SetPoint("BOTTOM", 0, 22)
  local function Arrow(dir)
    local b = CreateFrame("Button", nil, page)
    b:SetSize(24, 24)
    local tex = ARROWS .. (dir < 0 and "ArrowLeft" or "ArrowRight")
    b:SetNormalTexture(tex)
    b:SetPushedTexture(tex .. "-Down")
    b:SetDisabledTexture(tex .. "-Disabled")
    b:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
    b:SetScript("OnClick", function() ES.WhatsNewTurn(dir) end)
    return b
  end
  page.prev = Arrow(-1)
  page.prev:SetPoint("RIGHT", page.label, "LEFT", -10, 0)
  page.next = Arrow(1)
  page.next:SetPoint("LEFT", page.label, "RIGHT", 10, 0)
  f.page = page
  -- La diapositiva de una novedad con elección (it.choice)
  f.choiceView = CreateChoiceView(f)

  -- ¡Entendido! (en las páginas, Siguiente hasta la última)
  f.ok = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.ok:SetSize(160, 26)
  f.ok:SetPoint("BOTTOM", 0, 16)
  f.ok:SetScript("OnClick", function()
    if f.pages and f.pageIndex < #f.pages then ES.WhatsNewTurn(1) else f:Hide() end
  end)
  -- "No volver a mostrar": apaga la ventana en las próximas versiones (ES.db.noWhatsNew;
  -- se vuelve a encender en /cj opciones, General). Se aplica al cerrarla
  f.never = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
  f.never:SetSize(24, 24)
  f.never:SetPoint("BOTTOMLEFT", 16, 17)
  f.neverLabel = UI.Label(f, "", "GameFontHighlightSmall")
  f.neverLabel:SetPoint("LEFT", f.never, "RIGHT", 2, 1)
  f:SetScript("OnHide", function()
    -- Suelta la imagen (6 MB de textura): el juego la libera en vez de guardarla
    -- hasta que la necesite otra cosa. Al volver a abrir, ShowPage la pone otra vez
    page.tex:SetTexture(nil)
    page.imageFile = nil
    if f.never:GetChecked() and not f.isDev and not ES.db.noWhatsNew then
      ES.db.noWhatsNew = true
      ES:Print(L["Ya no se mostrarán las novedades. Se vuelven a activar en /cj opciones (General)."])
    end
  end)
  f.devTag = UI.Label(f, "", "GameFontDisableSmall")
  f.devTag:SetPoint("BOTTOMRIGHT", -18, 22)
  return f
end

-- Una línea de la lista (se reutilizan): cabecera de versión o novedad con icono
local function Line(f, i)
  local l = f.lines[i]
  if l then return l end
  l = CreateFrame("Frame", nil, f.content)
  l.bg = l:CreateTexture(nil, "BACKGROUND")
  l.bg:SetAllPoints()
  local R = ES.UI.BROWN.row
  l.bg:SetColorTexture(R[1], R[2], R[3], R[4])
  l.icon = l:CreateTexture(nil, "ARTWORK")
  l.icon:SetSize(32, 32)
  l.icon:SetPoint("TOPLEFT", 8, -8)
  l.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  l.title = ES.UI.Label(l, "", "GameFontNormal")
  l.title:SetJustifyH("LEFT")
  l.text = ES.UI.Label(l, "", "GameFontHighlightSmall")
  l.text:SetJustifyH("LEFT")
  if l.text.SetSpacing then l.text:SetSpacing(2) end
  f.lines[i] = l
  return l
end

local function Height(fs, cap)
  return math.min(tonumber(fs:GetStringHeight()) or 12, cap or 200)
end

-- Enseña la página `i` de las novedades con imagen (f.pages)
local function ShowPage(f, i)
  local page, it = f.page, f.pages[i]
  f.pageIndex = i
  local pos = ES.WhatsNewPageLayout(it.image)
  page.image:ClearAllPoints()
  page.image:SetPoint("TOPLEFT", pos.img.x, -pos.img.y)
  page.image:SetSize(pos.img.w, pos.img.h)
  page.tex:SetTexture(it.image.file)
  page.tex:SetTexCoord(0, it.image.w / CANVAS_W, 0, it.image.h / CANVAS_H)
  page.imageFile = it.image.file -- (para las pruebas)
  local n = #f.pages
  page.label:SetText(string.format("%d / %d", i, n))
  page.label:SetShown(n > 1)
  page.prev:SetShown(n > 1)
  page.next:SetShown(n > 1)
  page.prev:SetEnabled(i > 1)
  page.next:SetEnabled(i < n)
  f.ok:SetText(i < n and L["Siguiente"] or L["¡Entendido!"])
end

-- Pasa de página (`dir`: 1 la siguiente, -1 la anterior); en la primera o la última,
-- nada (la ventana se cierra con ¡Entendido!, no al pasar)
function ES.WhatsNewTurn(dir)
  local f = frame
  if not (f and f.pages) then return end
  local i = f.pageIndex + dir
  if i >= 1 and i <= #f.pages then ShowPage(f, i) end
end

-- Rellena la ventana con `notes` (de ES:WhatsNewSince) y la enseña. `dev`: vista de
-- desarrollo (lo dice abajo y no cuenta como vista)
function ES:ShowWhatsNew(notes, dev)
  if not notes or #notes == 0 then return end
  frame = frame or CreateWindow()
  local f = frame
  local items = ES.WhatsNewItems(notes)
  f.devTag:SetText(dev and L["Vista de desarrollo: no cuenta como vista."] or "")
  f.isDev = dev
  f.never:SetChecked(false)
  f.neverLabel:SetText(L["No volver a mostrar"])
  f.devTag:ClearAllPoints()
  f.ok:ClearAllPoints()
  -- (la cabecera, también con páginas aunque no se vea: dice la versión)
  f.title:SetText(L["Novedades"])
  f.sub:SetText(string.format(L["Crafter's Journal %s: esto es lo nuevo desde la última vez."], notes[1].version))

  -- Una novedad con elección: su diapositiva sola, en una ventana pequeña (sin cabecera,
  -- lista ni páginas)
  f.choiceView:Hide()
  if items[1] and items[1].choice then
    f.pages, f.pageIndex = nil, nil
    f.size = SIZES.choice
    f:SetSize(SIZES.choice.w, SIZES.choice.h)
    f.head:Hide()
    f.list:Hide()
    f.page:Hide()
    f.ok:SetPoint("BOTTOMRIGHT", -16, 16)
    f.ok:SetText(L["¡Entendido!"])
    f.devTag:SetPoint("TOPLEFT", 16, -12)
    f.choiceView:Fill(items[1])
    f.choiceView:Show()
    f:Show()
    return
  end

  -- Con novedades con imagen: páginas, en una ventana grande (la imagen ya dice qué es
  -- y de qué versión: sin cabecera, lista ni texto)
  local paged = false
  for _, it in ipairs(items) do if it.image then paged = true end end
  if paged then
    f.size = SIZES.pages
    f:SetSize(SIZES.pages.w, SIZES.pages.h)
    f.head:Hide()
    f.list:Hide()
    f.ok:SetPoint("BOTTOMRIGHT", -16, 16)
    f.devTag:SetPoint("LEFT", f.neverLabel, "RIGHT", 16, 0)
    f.pages = items
    ShowPage(f, 1)
    f.page:Show()
    f:Show()
    return
  end

  f.pages, f.pageIndex = nil, nil
  f.page:Hide()
  f.head:Show()
  f.list:Show()
  local S = SIZES.rows
  f.size = S -- (para las pruebas)
  f:SetSize(S.w, S.h)
  f.content:SetWidth(S.content)
  f.ok:SetPoint("BOTTOM", 0, 16)
  f.devTag:SetPoint("BOTTOMRIGHT", -18, 22)
  local width = S.content
  f.ok:SetText(L["¡Entendido!"])
  local y, n = 0, 0
  -- Una sola lista, sin cabeceras de versión: si te saltaste versiones, lo de todas
  -- junto, de la más nueva a la más antigua y como mucho MAX_ITEMS (antes una
  -- sección por versión, una tras otra: salía muy larga), las destacadas primero
  for _, it in ipairs(items) do
    n = n + 1
    local l = Line(f, n)
    l:ClearAllPoints()
    l:SetPoint("TOPLEFT", 0, -y)
    l:SetWidth(width)
    l.bg:Show()
    l.icon:Show()
    l.icon:SetTexture(it.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    l.title:ClearAllPoints()
    l.title:SetPoint("TOPLEFT", l.icon, "TOPRIGHT", 10, -1)
    l.title:SetWidth(width - 60)
    l.title:SetText(L[it.title])
    l.title:SetTextColor(1, 0.82, 0)
    l.text:ClearAllPoints()
    l.text:SetPoint("TOPLEFT", l.title, "BOTTOMLEFT", 0, -4)
    l.text:SetWidth(width - 60)
    l.text:SetText(L[it.text])
    local h = math.max(48, 8 + Height(l.title, 30) + 4 + Height(l.text) + 10)
    l:SetHeight(h)
    l:Show()
    y = y + h + GAP
  end
  for k = n + 1, #f.lines do f.lines[k]:Hide() end
  f.content:SetHeight(math.max(1, y - GAP))
  f.scroll:SetVerticalScroll(0)
  if f.indicator and f.indicator.Update then f.indicator:Update() end
  f:Show()
end

-- Al entrar: si hay versión nueva con notas, la ventana (una vez por versión)
function ES:CheckWhatsNew()
  local db, current = self.db, AddonVersion()
  -- (en la copia de desarrollo no salen solas ni se apunta nada: /cj whatsnew)
  if not db or not current or current == "dev" then return end
  local seen = db.whatsNewSeen
  if seen and CompareVersions(current, seen) <= 0 then return end
  -- Instalación nueva (ni un escaneo ni la ventana abierta nunca): no hay "novedades"
  -- para quien empieza. (Los datos del personaje no sirven: se crean al cargar)
  local fresh = not seen and not (db.scans and next(db.scans)) and not db.lastPage
  db.whatsNewSeen = current
  -- (apagada en las opciones o con su casilla "No volver a mostrar")
  if fresh or db.noWhatsNew then return end
  self:ShowWhatsNew(self:WhatsNewSince(seen, current))
end

do
  local f = CreateFrame("Frame")
  ES.SafeRegister(f, "PLAYER_LOGIN")
  -- (un momento después de entrar: que no salga encima de la pantalla de carga)
  f:SetScript("OnEvent", function() C_Timer.After(3, function() ES:CheckWhatsNew() end) end)
end

ES.WhatsNewFrame = function() return frame end -- para pruebas
