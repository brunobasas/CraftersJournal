# Pruebas

Un solo comando lanza todas las pruebas del addon y dice sí o no:

```
python tools/run_tests.py
```

Termina con código 0 si todo pasa y con 1 si falla algo. Al final sale un resumen por categoría y la lista de lo que falla. Solo hace falta Python 3 y `lupa` (`pip install lupa`); no hace falta WoW ni tus SavedVariables.

**Cuándo:** al terminar el desarrollo de cada spec o change se lanzan **todas**, y se dice el resultado antes de poner la etiqueta. Mientras se desarrolla basta con la categoría que se toca. Las pruebas no se lanzan en GitHub: la publicación (`.github/workflows/release.yml`) no depende de ellas. Todo junto tarda ~55 s (16 núcleos; lo más largo es `tools/test_ui.py`).

**Cada desarrollo trae su prueba:** lo nuevo o cambiado se comprueba con una prueba nueva o modificada en su categoría. Cada bug arreglado lleva una prueba que falla sin el arreglo y pasa con él; si ese bug ya tenía una prueba marcada como fallo conocido, se le quita la marca.

## Comandos

| Para | Comando |
| --- | --- |
| Todas | `python tools/run_tests.py` |
| Una o varias categorías | `python tools/run_tests.py --only route earn` |
| Con el detalle de cada prueba | `python tools/run_tests.py --only favor -v` |
| Ver las categorías y sus pruebas | `python tools/run_tests.py --list` |
| Aceptar una instantánea que ha cambiado a propósito | `python tools/run_tests.py --only route --update-snapshots` |
| Solo la prueba antigua | `python tools/test_ui.py` (o `--only test_ui`) |

## Qué hay

- `tools/test_ui.py`: la prueba de siempre (más de cien pasos seguidos sobre la interfaz). Sale en el resumen como la categoría `test_ui`.
- `tools/tests/categories/<categoría>.lua`: una por pestaña o pieza del addon. Las obligatorias están en `REQUIRED` de `tools/run_tests.py`; si falta una o no tiene pruebas, es un fallo.

| Categoría | Qué cubre |
| --- | --- |
| `boot` | Carga con lo guardado vacío, antiguo o roto; todos los eventos sin error |
| `data` | Los archivos de `Data/`: recetas, PNJ, fuentes, cajas |
| `locales` | Nombres y textos en los cuatro idiomas; cambiar de idioma con cada pestaña abierta |
| `route` | Subir profesiones: páginas, rutas válidas de las 8 profesiones e instantánea |
| `shopping` | Lista de compra |
| `earn` | Ganar dinero |
| `calculator` | Calculadora |
| `inventory` | Inventario |
| `favor` | Merchant's Favor |
| `collection` | Colección de recetas |
| `invest` | Inversiones: cartera (precio medio, beneficio, comisión, cartera de la cuenta), historial de Auctionator (simulado) y la pestaña |
| `assistant` | Asistente de ruta |
| `auction` | Casa de Subastas: escaneo, precios, historial, compras, vender |
| `vendors` | Vendedores de materiales e instructores |
| `options` | Opciones |
| `whatsnew` | Novedades |

- `tools/tests/wow.lua`: la API de WoW simulada (marcos, eventos, `C_Timer` con cola, AH clásica, bolsas, hechizos, profesiones). También un Auctionator simulado: `InstallAuctionator()` lo carga y `AUCTIONATOR_DAYS[itemID] = { { ago = días, max = cobre }, ... }` es su historial por día (`AUCTIONATOR_FAIL` y `AUCTIONATOR_ROWS` para que falle o devuelva otra forma), `AUCTIONATOR_LATEST[itemID] = { price, age }` el último mínimo de su API pública, y su escaneo completo (`Auctionator.State.FullScanFrameRef`: `AUCTIONATOR_FULL_SCANS` cuenta los lanzados, `AUCTIONATOR_WAITING = true` es su propia cuenta atrás). El addon solo escanea con Auctionator: una prueba que escanee necesita `InstallAuctionator()` (sin él, el botón Escanear sale en gris).
- `tools/tests/fixtures.lua`: lo guardado en tres estados (`empty`, `scan`, `full`) y los precios de la AH, fijos.
- `tools/tests/framework.lua`: `test`, `expect`… y ayudas para abrir pestañas y calcular rutas.
- `tools/tests/snapshots/`: las instantáneas guardadas.

Cada prueba corre con el addon recién cargado (un Lua nuevo por prueba), así que da lo mismo lanzar una categoría sola que todas, y en cualquier orden. La hora es fija (`NOW`).

## Escribir una prueba

En el archivo de su categoría:

```lua
test("Ganar dinero: el beneficio es venta menos coste", function()
  OpenPage("money")
  local idea = ...
  expect_eq(idea.profit, idea.sale - idea.cost, "beneficio")
  note("idea: %s", idea.name)            -- sale con -v
end, { state = "full" })                 -- "empty", "scan" (por defecto) o "full"
```

- `expect(cond, "mensaje %s", ...)`, `expect_eq(sale, esperado, "qué")`, `expect_near(sale, esperado, margen, "qué")`, `expect_finite(x, "qué")`.
- `Boot(db)` con `{ boot = false }`: la prueba arranca el addon ella misma, con lo guardado que quiera.
- `OpenMain()`, `OpenPage("money")`, `ProfessionPage("Leatherworking")`, `PlanRoute("Tailoring", 1, 300)`, `ProfessionKeys()`.
- `snapshot("clave", valor)`: compara `valor` con el guardado en `tools/tests/snapshots/<categoría>.json`.
- `SKILLS[skillLine] = { nivel, tope }`, `KNOWN_SPELLS[id] = true`, `BAGS[itemID] = n`, `IN_COMBAT = true`, `FireEvent(...)`, `RunTimers()`: el estado del juego simulado.
- El cliente simulado es el de Forever desde el parche del 21/11/2026: `REALM = ""` (no da el reino) y `GAME_MODE = 14` (el ruleset, `C_GameRules`). `SetGameMode(id)` cambia de ruleset y avisa como el juego; `GAME_MODE = 0` es un modo que aún no ha llegado. Lo guardado de `Fixtures` va con las claves de antes del parche (`"Realm-Alliance"`, `"Bruno-Realm"`) y cada prueba arranca migrándolo (`Keys.lua`). `BadKeys(ES.db)` lista las claves provisionales o vacías que no deben quedar. `tools/test_ui.py` es un cliente anterior: da el reino y no tiene `C_GameRules`.

Además de lo que compruebe la prueba, falla si el addon da un error de Lua, si apunta un error en su registro (`ES:RecordError`), si escribe una variable global sin querer o si llama a un método de marco que no está en la lista de la API real (`WIDGET_API` en `tools/tests/wow.lua`; si el método existe en el juego, se añade ahí).

## Fallos conocidos

Una prueba que destapa un fallo del addon aún sin arreglar se marca con su motivo:

```lua
test("...", function() ... end, { known = "la calculadora no cuenta la comisión de la AH" })
```

Sale aparte en el resumen y no hace fallar el comando. Si empieza a pasar, el resumen avisa («YA PASA») para quitar la marca. Cada fallo conocido se arregla en su propio change.

## Que las rutas no se vuelvan lentas

Cada ruta 1→300 de `route` mide lo que cuesta calcularla, con dos números que no dependen del equipo ni de lo que esté haciendo (con WoW abierto y las pruebas en paralelo, los segundos llegan a duplicarse sin cambiar nada):

- **pasadas** del planificador (`ES.Planner.passes`): cuántas rutas recorre para elegir la mejor;
- **millones de instrucciones** de Lua que ejecuta (contadas con `debug.sethook`).

Con el mismo código salen siempre iguales. Si cualquiera de las dos pasa de la referencia guardada en `tools/tests/snapshots/route.json` en más de un 15%, la prueba falla y dice cuánto ha crecido. Si el aumento es a propósito (la ruta ahora mira más cosas y compensa), se acepta con `--update-snapshots` y se dice en el commit. Los segundos de CPU salen solo como dato (`-v`).

Para declarar un presupuesto en otra prueba: `budget("clave", valor, 0.15, margen_fijo)`.

## Instantáneas

La categoría `route` guarda el resumen de la ruta 1→300 de cada profesión (pasos, recetas en orden, coste y paradas) con los precios de las pruebas. Si un cambio de código lo cambia, la prueba falla y enseña la diferencia. Si el cambio es a propósito (o se han regenerado los `Data/`), se acepta con `--update-snapshots` y se sube el `.json` en el mismo commit.
