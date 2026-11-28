# Crafter's Journal: plan de funciones

Documento vivo: se actualiza al implementar cada parte.

Principios que se mantienen en todo:

- **Nada de estimar ventas** con los escaneos. Para decidir qué vender se usan las alertas de mercado (estancado, precio clavado, más oferta) y tus ventas reales del buzón.
- **Costes en rojo con "-" y beneficios en verde con "+".**
- **Ruta = la más barata y óptima.**
- **El addon nunca compra ni vende solo:** solo prepara búsquedas, listas y consejos.
- **Todo texto visible va como `L["texto en español"]`**, con su traducción en `Locales/enUS.lua`. La prueba "idioma inglés" falla si falta alguna. Las tablas que se crean al cargar un archivo se registran con `ES.Localize(tabla[, campo])`.

---

## A. Colección de recetas (completista): hecho en 0.28

Archivos: `Collection.lua` (datos) y `CollectionUI.lua` (vista "Colección", 5.º botón de cada profesión).

- [x] **Contador** `Recetas: N / total (%)`, con barra de progreso y desglose por fuente principal: instructor, básica, misión, reputación, vendedor, botín, desconocida.
- [x] **Colores de las filas:** verde con check si la tienes, amarillo si puedes aprenderla ya, gris si te falta.
- [x] **Cada fila:**
  - nivel;
  - fuente principal;
  - dónde se consigue: PNJ y zona más cercanos de tu bando, misión, reputación pedida frente a la tuya, o criatura y zona del botín / botín del mundo / cofres;
  - pergamino en la AH, o beneficio por unidad si ya la tienes.
- [x] **Filtros:** me faltan / puedo aprender ya / en la AH / todas, más filtro por fuente y buscador.
- [x] **Orden:** nivel, pergamino en la AH, beneficio, más barata de conseguir.
- [x] **Clic** en una fila:
  - de instructor o vendedor, marca el camino;
  - de misión, marca a quien la da;
  - si el pergamino está en la AH y la tienes abierta, lo busca.
- [x] **Tooltip:** todas las fuentes, el pergamino en la AH, el coste de fabricar, el precio en la AH y el beneficio.
- [x] **Botín:** `tools/gen_sources.py` saca de QuestieDB las criaturas (hasta 12; si son más, "botín del mundo" con cuántas) y los cofres de cada pergamino. 405 pergaminos tienen botín conocido.
- [x] **Recetas sin fuente conocida:** se marcan "Desconocida"; no se inventa nada.
- [x] **Recetas que no existen en Forever:** comprobado. Todas las de los datos están en el SkillLineAbility de Forever.
- [x] **Alters:** se guarda qué recetas sabe cada personaje (al abrir la ventana de profesión, al aprender una receta y al abrir la colección). El tooltip dice "La tiene tu personaje: X".
- [x] **Siguientes para completar:** las 5 más baratas que puedes aprender ya.
- [x] **Alerta al escanear:** si hay en la AH pergaminos de botín que te faltan, lo dice en el chat con su precio.
- [x] **Progreso en la portada:** "recetas N/total" en la tarjeta de cada profesión que tienes.

## B. Ganar dinero (día a día): hecho en 0.28

Archivos: `Earn.lua` (ideas y lote), `EarnUI.lua` (página "Ganar dinero", con tarjeta en la portada) y `Mail.lua` (buzón).

- [x] **Qué fabricar hoy:** solo recetas que sabes, con:
  - coste de fabricar (escalera de la AH o vendedor);
  - lo que te queda en la AH (mínimo − 1 cobre − comisión − depósito de 24 h) o en el vendedor;
  - beneficio y alertas de mercado.
- [x] **Cuántas hacer**, sin estimar ventas:
  - "bien": hasta el 30% de lo que hay a la venta, máximo 10;
  - "ojo" o "pocos datos": 3;
  - venta segura al vendedor: 20;
  - "evitar": se lista aparte.
- [x] **Puntuación** = beneficio × cuántas ("ojo" × 0,5). Quedan fuera las recetas con menos de 5 cobres o menos de un 10% de beneficio.
- [x] **Resumen** del lote de hoy (8 recetas): inviertes, beneficio si se vende todo y lo vendido en 7 días. Avisa si el escaneo tiene más de 12 h.
- [x] **Panel de la AH:** modo "Ganar dinero" que busca los materiales del lote que no llevas, y sección "Vender" con lo fabricado del lote que llevas encima.
- [x] **Buzón:** se leen los correos de "subasta vendida" y "caducada" (los tuyos, reales):
  - histórico de 7 días por objeto;
  - ajusta "cuántas": no menos de lo que vendiste, y solo 3 si caducan más de las que se venden.
- [x] **Enfriamientos:** transmutaciones y tela lunar que sabes, con si están listos.
- [x] **Materiales que llevas y no usas:** para venderlos, con su precio de AH o de vendedor.
- [ ] **Desencantamiento:** valor de desencantar objetos verdes de la AH. Necesita tablas de desencantamiento que no están en los datos. Queda para cuando haya fuente fiable.

## C. Tanda anterior: hecho en 0.27

- [x] **Lista de la compra en la AH:** ~~panel junto a la AH~~ → pestaña Lista de compra (ver G4).
- [x] **Consejo de venta de lo fabricado** (`Planner.SaleAdvice`).
- [x] **Escaneo:** getAll y procesado por tiempo por fotograma.
- [x] ~~**Filtro "Lo que recolectas tú".**~~ Quitado en 0.32.0 a petición del jugador (botón, opción y su código en el planificador). Los datos de qué se recolecta (`ES.Data.GatheredBy`) se siguen generando para la vía "Vender en bruto".
- [x] **`tools/build_data.py`:** regenera los datos y pasa las pruebas con un comando.
- [x] **Idiomas:** español e inglés.

## D. Datos sin depender de otros addons: hecho en 0.28.1

El addon nunca dependió de SkillUpForever en el juego, pero el generador de datos leía sus archivos. Ahora `tools/build_data.py` usa solo fuentes originales:

| Dato | Fuente |
|---|---|
| Recetas, umbrales, nombres, materiales, qué fabrican, pergaminos (y su nivel y reputación), herramientas, precios de compra y venta, tipo de objeto | wago.tools, tablas del cliente de Forever (`tools/filter_wago.py`) |
| Precio y nivel de cada receta en el instructor, rangos e instructores | CMaNGOS classic-db (`tools/extract_cmangos.py`) |
| Qué se compra sin límite a un vendedor (vendido por 10 PNJ o más; bebidas, 3), vendedores, misiones, botín y posiciones de PNJ | QuestieDB (`tools/questie.py`) |

Comparado con los datos anteriores:
- **Iguales:** umbrales y nombres (2.327 de 2.327), materiales, rangos y precios de instructor (salvo Goblin Mortar, de la especialización goblin, que CMaNGOS no tiene).
- **Mejoras:** unos 160 pergaminos nuevos que antes salían como "fuente desconocida", más instructores de aprendiz, los lingotes cuentan como recolectados con Minería, y se corrigió un nombre de receta con notas pegadas.

## E. Precio realista y nueva interfaz: hecho en 0.29

- [x] **Precio de referencia** (`Market:FairPrice`): mediana de los mínimos de los últimos 3 días con escaneo (sirve con escaneos sueltos, dentro de los 7 días guardados).
  - Si el mínimo de ahora pasa de 1,5× la referencia, se considera inflado y se calcula a referencia ×1,15 (caso Westfall Stew: de 23s a ~5,6s).
  - Si alguien malvende, se avisa y se iguala.
  - Sin historial: se avisa de que podría ser un pico.
  - Se aplica en Ganar dinero, Profit, el panel de la AH, la vista Recetas y los materiales sobrantes.
- [x] **Ganar dinero:**
  - el lote se costea receta a receta, contando los materiales que ya compran las anteriores;
  - descuenta lo que ya llevas fabricado;
  - tiene presupuesto opcional;
  - los enfriamientos muestran su beneficio.
- [x] **Pestañas laterales** a la derecha: Subir profesiones, Ganar dinero, Colección de recetas (Patterns) y Subastas.
  - La colección tiene tarjetas por profesión con "X de Y recetas · %" y página propia por profesión; ya no está dentro de cada profesión.
- [x] **Botón "Escanear"** junto al título: funciona desde cualquier pestaña y está en gris si la AH está cerrada. Los mensajes del escaneo siguen en Subastas.
- [x] **Pestañas idénticas a las del libro de profesiones de Forever:** 55×55, separadas 2 px, con los atlas `common-sidetab`, `common-sidetab-selected` y `common-sidetab-hover`. Medidas leídas del juego con `/es pestaña`.
- [x] **Escaneo como Auctionator:** sin límite propio de 15 min (se pide si el cliente dice que se puede); el botón muestra el % de progreso y, a su lado, "Último escaneo: hace N min".
  - **Revertido en 0.30.2:** el servidor de Forever no contesta a un segundo escaneo antes de 15 min aunque el cliente diga que sí. Vuelve la barrera de 15 min desde cada petición, con cuenta atrás en el botón, y se abandona a los 60 s sin respuesta.
- [ ] **Historial diario de 30 días**, aparte del detallado de 7 (pendiente de decidir).
- [ ] **Guardar también las búsquedas sueltas** en la AH en el historial (pendiente de decidir).
- [x] **Auctionator como respaldo opcional del historial:** hecho en 0.66.0 para la pestaña Inversiones (su historial de precios por día y su API pública para el último mínimo).
- [x] **Escanear con Auctionator (0.66.0):** el addon ya no pide su propio escaneo completo. Escanear lanza el de Auctionator y el addon lee esas subastas para todas las pestañas; sin Auctionator el botón sale en gris. Los escaneos que pida cualquier addon se leen siempre (fuera la opción de no leerlos). Change de OpenSpec `scan-only-with-auctionator`.
  - **Cambiado en 0.73.0:** Auctionator vuelve a ser opcional (dependencia opcional en CurseForge). Dos modos, cada uno con una sola fuente: con Auctionator, su escaneo y su historial; sin él, o con la opción «Escanear con Auctionator» desactivada, el addon pide su escaneo y la gráfica de Inversiones sale de 21 días que apunta él. Change de OpenSpec `optional-auctionator-scan`.
- [x] **Historial diario de 21 días** para Inversiones (los precios del día de los objetos de profesiones y de cartera, 0.73.0): resuelve en parte el de 30 días de arriba.

## F. La 1.0 (actualizado el 2026-10-15, versión 0.34.0)

La 1.0 son **Subir profesiones** y **Colección de recetas** (8 profesiones). Lo demás (Ganar dinero, Subastas, Pesca, buscador de la cabecera) queda en modo DEV y no frena la 1.0. Nombre: **Crafter's Journal** (carpeta `CraftersJournal`, decidido el 2026-10-16).

### Hecho
- Rutas 1-225 más baratas, repartidas entre fotogramas (sin tirones), con instructores por rango (QuestieDB + guías de Mobalytics) y caché común.
- Colección al estilo del diario de mazmorras (F2): lista, ficha, filtros, barra de progreso, búsqueda en español e inglés.
- Datos limpios: sin recetas de SoD ni repetidas, sin las del otro bando, calidad del pergamino, ligadas (BoP), Merchant's Favor, niveles de las criaturas del botín, precios de vendedor solo si alguien lo vende.
- Español e inglés al momento (textos, recetas y objetos).
- Separación 1.0 / desarrollo con `ES.DEV_BUILD` y el botón "Vista jugador"; `.pkgmeta` listo.

### Pendiente para la 1.0 (por orden)
**Bloqueantes: sin esto no se publica**
- [ ] **Prueba en el juego de la vista de jugador**, de punta a punta: portada, una profesión, la colección, el idioma, el escaneo (barrera de 15 min) y el panel de la AH. Anotar todo lo que falle.
- [ ] **Errores de Lua:** jugar un rato con `/console scriptErrors 1` (o BugSack) y que no salga ninguno del addon.
- [x] **Nombre definitivo:** Crafter's Journal. Carpeta, `.toc`, variables y datos guardados renombrados (0.34.1); el código vive en el repositorio `GitHub\Addons\CraftersJournal` y `Interface\AddOns\CraftersJournal` es un enlace a él.
- [ ] **Instalación limpia:** probar el addon sin datos guardados y sin QuestieDB/TomTom (personaje nuevo): que todo funcione y se entienda sin escanear.

**Importantes: calidad de la 1.0**
- [ ] **Ruta 1-225 de las 8 profesiones** revisada al menos una vez en el juego (instructor de cada rango, recetas de vendedor, intermedios). Empezar por la que estés subiendo.
- [ ] **Instructores** de Herrería, Peletería, Encantamiento, Cocina y Primeros auxilios: comparar con guías de Forever (wow-professions.com tiene las 8) y corregir con `trainer_overrides.csv`.
- [ ] **Barra de progreso de la colección** con los atlas exactos de la de Forever (`/es pestaña` sobre la barra de nivel del libro de profesiones).
- [x] **Merchant's Favor en la ruta (0.35.0):** fuera de la ruta (Planner.LearnSkill); antes salían gratis (SAF-T Dynamite, Gizmo Girdle, Dented Goggles, Mystic Mushroom).
- [ ] **Estaciones:** recetas que piden yunque, forja, fuego, horno o estación de campamento. Al menos avisarlo en la ruta y en la ficha.
- [ ] **Textos en inglés** revisados por alguien que lo hable bien (los de CurseForge también).
- [ ] **Panel de la AH:** confirmar que es útil en la 1.0 o esconderlo en modo DEV.

**Publicación**
- [ ] Repositorio en GitHub, proyecto en CurseForge (`## X-Curse-Project-ID`), flujo de GitHub Actions con BigWigsMods/packager y el token de CurseForge.
- [ ] Página de CurseForge: descripción, capturas (portada, ruta, colección) y GIF.
- [ ] `CHANGELOG.md` para la 1.0 (el empaquetador lo usa como notas de la versión).

### Después de la 1.0
- [x] **Gasto real de la ruta (0.35.0, Ledger.lua):** con la ruta fijada, la franja enseña "Real" bajo lo previsto: compras al vendedor y en la AH, instructor y depósitos, ventas al vendedor y en la AH (correos). Solo los objetos de la ruta.
- [x] **Vender y anunciar desde la vista Profit (0.35.0):** con el vendedor abierto, clic = vender lo que toca; con la AH abierta, clic = anunciar al precio sugerido; si no, marca el subastador o el vendedor más cercano (ES.Data.Auctioneers / SellVendors, de QuestieDB). **Regla cambiada el 2026-10-19:** el addon nunca compra ni vende sin un clic explícito del jugador que diga qué va a hacer (antes: nunca compra ni vende).
- [ ] Probar en el juego la lectura del gasto real (sobre todo la AH de Forever: si las compras llegan a las bolsas o por correo) y el anuncio con C_AuctionHouse.PostItem/PostCommodity.
- Revisado (2026-10-19): los ~1490 cueros pesados de Peletería 1-225 son 203 Thick Leather fabricados (6 pesados cada uno) para Nightscape y Wild Leather: con los precios del escaneo sale más barato que comprar el cuero grueso. Si en la AH baja el cuero grueso, la ruta lo compra.
- Fuentes de los pergaminos nuevos de Forever cuando las publiquen (F1), regenerar con QuestieDB nuevo.
- Pesca (ya hecha en modo DEV) y buscador de la cabecera: publicarlos en una 1.1.
- Ganar dinero 2.0 (G) y Subastas.
- Alters (H) y resumen de personajes.

### F2. Colección al estilo del diario de mazmorras (0.32.0, decidido el 2026-10-15)

- [x] **Una profesión cada vez.** Lista de todas las recetas a la izquierda; al pulsar una, su ficha a la derecha (la lista no se sustituye).
- [x] **Filas:** icono de lo fabricado, nombre sin color, debajo de dónde sale ("Instructor", "Receta · Botín: …", "Receta · Vendedor: …") y el nivel a la derecha. La palabra **"Receta" va del color de la calidad del pergamino** (blanco, verde, azul, morado). Sin etiqueta "Nueva": da igual si es de Classic o de Forever.
- [x] **Las que tienes:** fila en verde apagado con check e icono gris, como las misiones hechas del diario. No se ocultan por defecto (se puede con los filtros).
- [x] ~~Mosaico~~ (se veía muy pequeño) → **barra como la de nivel del libro de profesiones** con "Peletería 25/541" y, debajo, "% · N puedes aprender ya". Falta copiar los atlas exactos de la barra de Forever (`/es pestaña` sobre ella).
- [x] **Sin barras de desplazamiento** en la lista y la ficha: se mueven con la rueda del ratón.
- [x] **Ficha:** dónde conseguirla (cada fuente con "Marcar en el mapa"), precios (pergamino en la AH y en el vendedor, fabricar 1 en rojo, vender lo fabricado, beneficio en verde, tras cuántas fabricaciones se recupera el pergamino) y materiales.
- [x] **Filtros** en un solo botón con ventana (como el Loot Filter): mostrar, fuentes, orden y restablecer. El botón dice cuántos hay activos.
- [x] **Bando:** las recetas del otro bando no existen para el personaje (máscara de razas del cliente; hoy solo el estandarte de facción).
- [x] **Datos nuevos:** calidad del pergamino (`sq`) y de lo fabricado (`oq`), bando (`faction`).
- [ ] **Ligado (BoP/BoE) del pergamino:** el campo del cliente no cuadra con lo conocido de Classic (pergaminos de vendedor salen como BoP). No se muestra; "se puede comprar en la AH" sale de los escaneos.
- [ ] Revisar en el juego medidas, colores y que se lea en pocos segundos.

### F1. Datos de recetas: lo que falta (revisado el 2026-10-14)

Comparado con las webs de Forever (ForeverDB, Forever Codex, SeeMeta, Metaforge): todas salen del mismo cliente que nosotros (wago) y **ninguna sabe más que nosotros de dónde sale cada pergamino nuevo** (ForeverDB pone "not in the client yet"; Metaforge deja la fuente vacía).

Cobertura (0.34.0; pergaminos sin fuente conocida en QuestieDB / total de recetas; entre paréntesis, los de nivel ≤ 225; los de Merchant's Favor cuentan aquí aunque sí se sabe dónde se compran):

| Profesión | Recetas | Pergamino sin fuente | Ni instructor ni pergamino |
|---|---|---|---|
| Alquimia | 185 | 28 (12) | 17 |
| Herrería | 438 | 109 (40) | 6 |
| Encantamiento | 239 | 53 (12) | 6 |
| Ingeniería | 259 | 79 (35) | 13 |
| Peletería | 501 | 136 (28) | 9 |
| Sastrería | 398 | 78 (31) | 6 |
| Cocina | 130 | 29 (12) | 6 |
| Primeros auxilios | 29 | 7 (3) | 6 |

Pendiente:
- [ ] **Estaciones:** qué recetas piden yunque, forja, fuego de cocina, horno o una **estación de campamento** (Codex: 65 de Herrería, 19 de Cocina…). Sale del cliente (foco de hechizo requerido).
- [ ] **Campamentos y planos (Blueprints):** las mejoras de campamento de nivel 2 y 3 se aprenden con planos. Sacar qué da cada uno y qué profesión lo pone.
- [ ] **Fuentes de los pergaminos nuevos: de dataminers de internet** (decidido el 2026-10-14). Se descarta apuntarlas jugando (abrir a mano vendedores e instructores).
  - Se revisan cada cierto tiempo las webs y bases de datos de Forever (ForeverDB, Forever Codex, SeeMeta, Metaforge, QuestieDB y, si aparece, Wowhead) por si publican vendedores, botín o instructores de lo nuevo.
  - Lo que se encuentre va a `tools/forever/` (un CSV por tipo, con la web y la fecha de cada dato, como `trainer_overrides.csv`) y entra al regenerar con `tools/build_data.py`.
- [x] **Recuento (0.32.2):** fuera 100 recetas que piden materiales que no existen en el cliente de Forever: copias de Season of Discovery con el mismo nombre que las de Classic (Icebane, Glacial, Obsidian, Qiraji Silk, Flask of Madness…). Quedan Herrería 455, Peletería 518, Sastrería 412, Encantamiento 241, Ingeniería 260, Alquimia 186, Cocina 130, Primeros auxilios 29. `gen_profession.py` lista las que quita.
- [x] **Repetidas (0.32.8):** fuera 60 recetas con el mismo nombre que otra (copias de SoD con otro número, p. ej. Sulfuron Hammer 460460). Se queda la de más datos: instructor > pergamino con fuente o de Merchant's Favor > pergamino sin fuente; a igualdad, la que no es de los rangos de SoD. No se tocan las de bandos distintos (estandarte) ni Basic Campfire (el hechizo y el kit son cosas distintas).
- [ ] Comparar de nuevo con Codex (Herrería 441; ahora 438) por si quedan más diferencias.
- [x] **Pesca (0.33.0):** `tools/gen_fishing.py` → `Data/Fishing.lua`. Página propia (`FishingUI.lua`) con la guía por tramos: rango que aprender (instructor, libro de Experto de Old Man Heming, misión de Nat Pagle) y zonas donde pescar; marca tu tramo. Colección: las mejoras de campamento que se fabrican (Fish Bowl, Fishing Rack, Fishing Hut). Zonas de wow-professions.com; instructores, libro y misión de QuestieDB.
- [x] **Profesiones que no tienes** (0.33.0): plegadas tras "Otras profesiones (N)" en la portada y en la colección; se recuerda si las abres.
- [x] **Vista "Recetas" dentro de las profesiones:** quitada (está en la pestaña Colección). El buscador de la cabecera abre la ficha en la Colección.
- [x] **Idioma (0.33.0):** nombres en español de recetas y objetos desde el cliente esES (`tools/fetch_names_es.py` + `gen_names.py` → `Data/Names_esES.lua`). Con el addon en un idioma distinto al del cliente se usan los de los datos. El cambio de idioma se aplica al momento sin recargar (0.33.1: Forever no deja que un addon recargue la interfaz).
- [x] **Sin barras de desplazamiento** en todas las ventanas (rueda del ratón).
- [x] **Versión 1.0 frente a desarrollo (0.34.0):** `ES.DEV_BUILD` (Core.lua) entre `--@debug@`; el empaquetador de CurseForge lo apaga. `ES.DEV` = qué se ve: en la copia de desarrollo hay una casilla "Vista jugador" en Opciones > AddOns > Crafter's Journal (Options.lua; desde 0.34.2 ya no está en la cabecera, para que no salga en las capturas) para ver el addon como los jugadores. Solo en modo DEV: pestañas Ganar dinero y Subastas, la Pesca y el buscador de la cabecera. `.pkgmeta` deja fuera tools y docs.
- [x] Sin check verde en las tarjetas de profesión (tus profesiones ya van primero).
- [x] **Merchant's Favor (0.32.5):** 309 recetas que se compran con esa moneda en los campamentos (Durotar Supply and Logistics / Azeroth Commerce Authority), con su coste y la reputación que piden. Fuente: wow-professions.com, descargada con `tools/forever/fetch_merchants_favor.py` a `tools/forever/merchants_favor.csv`. En la colección salen con su icono, en azul: "Merchant's Favor: 45 · Amistoso".
- [ ] Merchant's Favor en la ruta de Subir profesiones: hoy el plan no sabe que esas recetas cuestan fichas y reputación (no oro).
- [ ] **QuestieDB:** volver a regenerar los datos cuando se actualice, porque es lo que más fuentes nuevas trae.

## G. Ganar dinero 2.0 (roadmap, se hace sobre la marcha)

### Qué falla hoy
- **Mucho ruido:** siete secciones en una lista (lote, más opciones, enfriamientos, evitar, sobrantes, buzón, presupuesto) y ningún "qué hago ahora".
- **Falta medio ciclo:** se ayuda a comprar, pero no a fabricar, anunciar ni a saber si el lote dio dinero.
- **"Hasta el 30% de lo que hay a la venta" no tiene base:** es un número a ojo. Se quita (ver G3).
- **Solo mira "fabricar y vender en la AH".** Las vías que la gente usa de verdad (desencantar, vender en bruto) no salen.

### G1. Vías en vez de una lista
La página pasa a tener **tarjetas de vías**, como la portada. Cada una muestra solo las 3 mejores oportunidades de hoy y su beneficio; al entrar, el detalle. Solo se ven las vías que tu personaje puede usar.

| Vía | Qué calcula | Necesita |
|---|---|---|
| **Fabricar y vender** | Lo de ahora: coste de fabricar frente a lo que te queda en la AH o el vendedor. Aquí entran las bolsas (Linen Bag, Woolen Bag…): salen solas si dan beneficio. | Ya existe |
| **Fabricar y desencantar** | Coste de fabricar un objeto verde frente al valor medio de lo que da al desencantarlo (polvo, esencias, fragmentos a precio de referencia). Ejemplo típico: Sastrería con lino → Brown Linen Robe → Strange Dust / Lesser Magic Essence. | Tabla de desencantamiento (G2) y Encantamiento en el personaje |
| **Comprar y desencantar** | Verdes de la AH cuyo precio está por debajo del valor medio de desencantarlos. | Tabla de desencantamiento y nivel/calidad de todos los objetos |
| **Vender en bruto** | Lo que recolectas o llevas encima: ¿vale más en bruto, fabricado o desencantado? (amplía "materiales que llevas y no usas"). Solo valor por unidad: **no se estima cuánto se recoge por hora.** | Ya casi existe |
| **Enfriamientos** | Transmutaciones, tela lunar…: listo o no y beneficio. | Ya existe |

Reglas que se mantienen: no se estiman ventas, el addon no compra ni vende solo, costes en rojo y beneficios en verde.

### G2. Datos para desencantar
- [ ] `tools/filter_wago.py`: sacar de ItemSparse el **nivel de objeto, la calidad y el tipo** (arma/armadura) de los objetos fabricables y de los que pueden salir en la AH.
- [ ] **Tabla de desencantamiento de Classic** (por calidad, nivel de objeto y arma/armadura: qué materiales y con qué probabilidad) y el **nivel de Encantamiento necesario** para desencantar cada nivel de objeto. Fuente: tablas públicas de Classic, apuntadas en `tools/forever/` con su fuente, como los instructores. Comprobar en el juego algunos casos, por si Forever cambia algo.
- [ ] `Market`: **valor medio de desencantar** = Σ probabilidad × cantidad media × precio de referencia del material (menos la comisión de la AH al venderlo). Es un **valor esperado de lo que da el objeto, no una estimación de ventas.**
- [ ] El valor de desencantar se muestra también en el tooltip de los objetos verdes.

### G3. Cuántas hacer (sustituye al 30%)
- **Por defecto, una tanda corta de prueba** (p. ej. 3-5), igual para todo lo que se vende en la AH.
- **Tus ventas reales mandan:** si en los últimos 7 días vendiste más de las que caducaron, la tanda sube a lo que vendiste; si caducan más que se venden, se queda en la de prueba o se desaconseja.
- **Desencantar:** sin límite por mercado del objeto (no se vende); el tope es tu presupuesto y lo que hay del material a la venta para no hundir el polvo.
- **Vendedor:** sin límite.
- El jugador puede **cambiar la cantidad** de cada fila.

### G4. Flujo de hoy: comprar → fabricar → (desencantar) → anunciar → balance
- [x] **Comprar (Shopping.lua, ShoppingUI.lua):** pestaña Lista de compra, una sola para todo. Se añade con "Añadir a la lista de compra" desde Ganar dinero, la calculadora y la vista Materiales de cada ruta (antes "Lista de compra"); nada entra solo. Cada lista guarda sus cantidades al añadirla y lo comprado sale de la contabilidad (AH, vendedor, trades) desde ese momento. Con la AH abierta, clic o "Comprar siguiente" abre la compra de Blizzard con la cantidad puesta (solo las baratas); confirmas tú. Al abrir la AH, la ventana grande se esconde y sale un panel pequeño con la misma lista (ShoppingUI.lua: mismas filas, barra, Comprar siguiente, ✕; "Ver completa" abre la pestaña). Sustituye al panel antiguo con modos ruta / Ganar dinero (2026-11-11).
- [ ] **Fabricar:** botón que abre la receta en el libro de profesiones con la cantidad puesta. Fabricas tú.
- [ ] **Desencantar:** lista de lo que llevas encima que conviene desencantar.
- [ ] **Anunciar:** al abrir la pestaña de vender de la AH con un objeto del lote, se rellenan precio y cantidad. El clic de anunciar es tuyo.
- [ ] ~~Balance del lote~~ **descartado (2026-11-11):** "seguir un lote" era un concepto más que entender y cerrar. Para medir está `/cj books` (dinero real por categoría, hoy y sesión).

### Orden propuesto
1. **G1 sin vías nuevas:** quitar ruido (secciones secundarias plegadas o fuera) y G3.
2. **G2 + "Fabricar y desencantar"**: la vía que más piden los vídeos (Sastrería + Encantamiento).
3. **G4:** abrir receta, rellenar precio, balance.
4. **"Comprar y desencantar"** y **"Vender en bruto"**.

### Decisiones y preguntas abiertas
- **Alters (decidido el 2026-10-14):** el Encantamiento de un alter cuenta para desencantar, **como opción** que activa el jugador. Cómo se manejan los alters en general está en H.
- Las bolsas también se venden por el chat de comercio: eso no se ve en la AH ni en el buzón, así que no se puede medir.

## H. Alters y profesiones de varios personajes (por definir)

Hoy solo se guarda qué recetas sabe cada personaje (`ES.db.known[personaje][profesión]`, al abrir el libro de profesiones). No se guarda su nivel de habilidad ni sus bolsas.

Propuesta para discutir, de menos a más:
1. **Ficha por personaje:** al entrar con cada uno, guardar sus profesiones y su nivel (no hace falta abrir el libro). Es la base de todo lo demás.
2. **Opción "contar con mis alters"** (apagada por defecto): Ganar dinero muestra vías que necesitan a otro personaje, marcadas con su nombre ("desencanta: Fulano"). El lote no cambia de personaje solo: el paso dice a quién enviar qué por correo.
3. **Colección y Subir profesiones** siguen siendo del personaje con el que juegas; el tooltip ya dice qué alter tiene una receta.
4. **Más adelante:** bolsas y banco de los alters (como hacen otros addons de inventario), para no comprar lo que ya tiene otro personaje.

Respuestas del jugador (2026-10-14):
- Sus alters están en el mismo reino y bando, pero **el addon debe comprobarlo**: solo se proponen alters del mismo reino y bando (a los que se puede enviar por correo).
- **Resumen de todos los personajes** (profesiones y niveles): sí, más adelante.

## Ideas para más adelante

- Desencantamiento: ahora en G2.
- Vista de colección de todas las profesiones a la vez (logros por cuenta).
- Avisos de enfriamiento listo al entrar al juego.

## I. Mejoras pendientes de la prueba de Alchemy 0-150 (2026-11-17)

Apuntadas mientras se prueba en el juego; se resuelven al final de la prueba.

### Lista de compra
- [ ] **Selector "Por tramos / Ruta entera" también en la página de la Lista de compra.** Hoy solo está en la fila de arriba de la vista Materiales de la ruta y cuesta encontrarlo (informe de un jugador: "no hay botón para fijar la ruta, sigue añadiendo ingredientes").
- [ ] **Avisar al cambiar de tramo:** en el chat o en la lista, p. ej. "Tramo 60-90: nuevos materiales", para que no parezca que la lista "añade cosas" sola.
- [ ] Opcional: **preguntar al pulsar Empezar ruta** cómo se quiere la lista (por tramos o la ruta entera).
- [ ] Revisar en el juego si el **margen de cada tramo** sobra o falta, y que lo que llevas en las bolsas descuente bien al pasar de un tramo a otro.

### Asistente
- [x] **Un solo modo de compra (cambiado el 2026-11-17):** los pasos de compra del asistente siguen el modo de la Lista de compra (`BuyMode` en ProfessionUI.lua). Con la ruta entera, el paso pide toda la ruta y dice "ruta entera"; comprado, los tramos siguientes ya no piden nada. Se cambia en la fila de la vista Materiales o con la bolsa / caja de la pestaña de arriba del asistente. Antes el asistente compraba siempre por tramos.
- [x] **Pestaña de arriba a la derecha del asistente** (2026-11-17): [Por tramos / Ruta entera] [?] [X], se despliega con las demás; la flecha GPS pasa arriba a la izquierda.
- [x] **Mercado dudoso: el resto se guarda, no al vendedor** (2026-11-17): con la alerta "vigilar" o sin datos, se anuncian unas pocas (AH_FEW) y el resto se guarda para anunciarlo cuando se vendan ("+33 después"), en Inventario, Profit, el panel de la AH y SaleAdvice. Antes iba al vendedor aunque en la AH valiera claramente más (Fire Oil: 1s frente a 2c). Texto corto en las filas, como Inventario.
- [x] **Profit = Inventario para lo que llevas** (2026-11-17): en la pestaña Profit, qué hacer con lo fabricado que llevas en las bolsas sale de Inventory:List (último escaneo, las mismas reglas que Inventario y el panel de la AH). Antes usaba los precios fijados al empezar la ruta y otra regla (Rage Potion: "al vendedor" en la ruta, "a la AH" en el panel). Lo que aún no llevas sigue con el consejo de la ruta.
- [x] **Sin menú del clic derecho** (2026-11-17): la UI del asistente es fija (sin bloquear ni tamaño desde el asistente; el tamaño guardado de antes ya no cuenta). El modo de compra, en la pestaña de arriba; bloquear y lo demás, en /cj opciones.
- [x] **Rango que ya puedes entrenar antes de tu tope** (2026-11-17): se quedaba atrás sin aviso y parecía saltado. Ahora es el paso actual en cuanto puedes entrenarlo (en el mismo viaje que la receta o las compras), salvo a mitad de un paso de fabricar: entonces solo se recuerda ("entrena Journeyman antes de 75") y a tu tope pasa a ser el paso actual.
- [x] Quitada la etiqueta BETA del asistente (se montaba con la flecha GPS, que pasa a la esquina izquierda).
- [x] **Botón de la ventana en el asistente** (2026-11-17): el icono del addon, en lugar del engranaje, abre la ruta en la ventana grande bajando hasta el paso actual (quitar receta, opciones de la ruta, dejarla); otra vez, la cierra. Las opciones del asistente, en /cj opciones.
- [x] **Orden de recados con menos viajes, en todas las rutas** (2026-11-17, `RouteLines`):
  - Un rango que ya puedes entrenar es el paso actual justo antes de empezar a fabricar (primero la receta y las compras en la AH, luego el instructor), o si lo actual es aprender en el instructor. A mitad de fabricar o con recados pendientes, solo un aviso.
  - En el instructor: "aprende también: X, Y" (recetas del instructor que la ruta usa más tarde y ya puedes aprender por nivel).
  - En el instructor, si lo siguiente es fabricar y volver a él: "fabrica aquí hasta 104 y aprende Elixir of Wisdom sin irte".
  - **Por tramos (decidido):** cada tramo compra solo lo suyo, para no perder dinero en lo que quizá no haga falta; el orden óptimo se aplica dentro del tramo. **Con la ruta entera** (lo elige el jugador), todo de golpe: los materiales ya los pide la ruta entera, y en la AH, "compra también la receta: X" con las recetas de la AH de más tarde.
- [ ] Con la ruta entera, agrupar también las recetas de vendedor de más tarde (hoy solo las de la AH).
- [ ] **Botón ? del asistente:** hoy solo un resumen en el tooltip. Hacer la explicación de cómo funciona (al pulsarlo).
- [ ] Revisar en el juego que la flecha GPS (arriba a la izquierda) y la pestaña de arriba no se pisen, sobre todo en alemán, y que la X se encuentre (ahora sale al pasar el ratón).
- [x] **Vendedor junto al instructor** (2026-11-17): si en el viaje toca el instructor, lo del vendedor se compra al de al lado del instructor (`WP.NearestTo`), no al más cercano a ti (solo si está a menos de 100 yardas de él; y de los que venden más materiales de la fila, `WP.VendorFor`). Si al abrir un vendedor no tiene un material (o está agotado), se apunta para la sesión y la fila lleva a otro de la lista. Orden del viaje: AH → buzón → instructor → vendedor de al lado → fabricar (`ArrangeTrip`: el paso actual es el primer recado pendiente).
- [x] **Aprender con un clic en el instructor** (2026-11-17): con el instructor abierto, el paso de entrenar (rango o receta) del asistente o de la ventana aprende lo que toca y lo de "aprende también" (`Ledger.LearnAtTrainer`, de uno en uno; solo lo disponible).
- [ ] Arreglar "Missing on/off parameter in SetTrainerServiceTypeFilter" (Ledger.lua, ReadAllTrainerServices): en Forever pide true/false; hoy falla la lectura de la lista entera del instructor (recetas quitadas o movidas).
- [x] **Paso "Recoge el correo" en el asistente** (2026-11-17): tras las compras en la AH, te lleva al buzón más cercano (Data/Mailboxes.lua, 180 buzones de QuestieDB: `tools/gen_mailboxes.py`, solo en la copia de desarrollo como el asistente) y se da por hecho cuando lo comprado para la ruta está en tus bolsas. Sin ninguna función del correo. Se puede saltar.
- [x] **Sin correo (2026-11-17):** el addon no lee el buzón (daba problemas; lo que llega puede venir de un intercambio o un alter). Lo comprado cuenta hasta que llega a las bolsas o pasan 2 h. Cada compra detectada se dice en el chat ("Compra detectada: X ×N"); si no sale, Saltar (también en los pasos de receta). Una receta comprada deja su paso hecho y el de fabricar dice "aprende X primero". Arreglado también: las recetas por nombre ("Recipe: Rage Potion", sin enlace) no se reconocían con el addon en otro idioma.
- [x] **Hecho (2026-11-17), falta probarlo en el juego:** `Ledger.OnWay` (Ledger.lua: del mensaje "You won an auction", se borra al llegar a las bolsas, con el buzón abierto o en 1 h) y la pestaña "Saltar" del asistente (se despliega como la de las flechas; `routeBuyVisits.had`, por material de la AH). Lo saltado queda como paso hecho ("Saltado"): con la flecha de paso anterior se vuelve a él y la misma pestaña dice "Recuperar".
- [ ] ~~**Lo comprado en la AH no cuenta hasta recogerlo del correo**~~ (asistente y Lista de compra: "Compra 21× Silverleaf · There wasn't enough" y "0 de 1" justo después de "You won an auction for [Silverleaf]x21"). Con varios materiales obliga a ir al buzón tras cada compra. `ES:HaveForShopping` solo mira las bolsas desde que se quitó `ES.db.ahOnWay` (se quedaba pegado: "48 en el correo" sin nada en el buzón). Propuesta, las dos cosas:
  1. **"De camino" fiable:** apuntar lo comprado al confirmarse (mensaje "You won an auction for [x]×N" / evento de compra), que cuente como tuyo, y que se borre solo: al llegar a las bolsas, al abrir el buzón (leer el contenido del correo, que es la verdad) o pasado un tiempo (p. ej. 1 h). Así no se queda pegado como antes.
  2. **Confirmación manual en el asistente:** en el paso de compra, "Ya lo tengo" pasa al siguiente paso (sirve también para compras por el chat de comercio, el banco de hermandad o un alter). Se olvida al cambiar de tramo.
- [ ] **Aviso en el paso de compra con la lista en ruta entera:** debajo del paso, algo como "Este tramo · tu lista tiene la ruta entera", para que no parezca que la lista no se ha actualizado.

### Navegación (unificada en esta tanda, falta probarla)
- [x] **Minimapa sin nada (2026-11-17):** con el punto de ruta del juego marcado se escondían los puntos propios del minimapa, pero ese punto no se dibuja en el cliente del usuario. Los puntos propios vuelven a salir siempre (salvo con el camino de Shortest Path).
- [ ] Probar en el juego `WP.Mark` sin Shortest Path ni TomTom: que el **punto de ruta del juego** salga en el mapa grande y el minimapa en el cliente de Forever. Si no funciona, volver a un pin propio en el mapa grande como respaldo.
- [ ] Probar con Shortest Path Forever: que el asistente marque el camino a cada paso y que pulsar un PNJ en la ventana cambie también la flecha.

### Ventana principal
- [ ] Probar en el juego que las **pestañas laterales** no se salgan de la pantalla con la ventana junto a la AH o pegada al borde derecho (`SetClampRectInsets`, `ES:KeepTabsOnScreen`). Informe de la 0.60: "atascado en la Lista de compra, ni con /cj".
