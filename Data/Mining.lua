-- Generado por tools/gen_profession.py (Mining). No editar a mano.
-- Datos: cliente de WoW Forever (wago.tools DB2).
-- Solo la fundición: Minería no es una profesión del addon (no tiene página ni ruta). La
-- ruta de otra profesión funde con estas recetas si el personaje las sabe (Planner, ForeignProducers).
-- t = { naranja, amarilla, verde, gris }; r = { {itemID, cantidad} }; out = { itemID, cantidad }
local _, ES = ...
ES.Data = ES.Data or {}
ES.Data.Mining = {
  skillLine = 186,
  recipes = {
    [2657] = { name = "Smelt Copper", t = { 1, 25, 47, 70 }, r = { { 2770, 1 } }, out = { 2840, 1 }, oq = 1 },
    [3304] = { name = "Smelt Tin", t = { 1, 50, 62, 75 }, r = { { 2771, 1 } }, out = { 3576, 1 }, oq = 1 },
    [2659] = { name = "Smelt Bronze", t = { 1, 65, 90, 115 }, r = { { 2840, 1 }, { 3576, 1 } }, out = { 2841, 2 }, oq = 1 },
    [2658] = { name = "Smelt Silver", t = { 1, 100, 112, 125 }, r = { { 2775, 1 } }, out = { 2842, 1 }, oq = 2 },
    [3307] = { name = "Smelt Iron", t = { 1, 130, 135, 140 }, r = { { 2772, 1 } }, out = { 3575, 1 }, oq = 1 },
    [3569] = { name = "Smelt Steel", t = { 1, 165, 165, 165 }, r = { { 3575, 1 }, { 3857, 1 } }, out = { 3859, 1 }, oq = 1 },
    [3308] = { name = "Smelt Gold", t = { 1, 170, 177, 185 }, r = { { 2776, 1 } }, out = { 3577, 1 }, oq = 2 },
    [10097] = { name = "Smelt Mithril", t = { 1, 175, 175, 175 }, r = { { 3858, 1 } }, out = { 3860, 1 }, oq = 1 },
    [10098] = { name = "Smelt Truesilver", t = { 1, 230, 230, 230 }, r = { { 7911, 1 } }, out = { 6037, 1 }, oq = 2 },
    [14891] = { name = "Smelt Dark Iron", t = { 1, 230, 230, 230 }, r = { { 11370, 8 } }, out = { 11371, 1 }, oq = 1 },
    [16153] = { name = "Smelt Thorium", t = { 1, 250, 250, 250 }, r = { { 10620, 1 } }, out = { 12359, 1 }, oq = 1 },
    [1249637] = { name = "Smelt Azerothium", t = { 1, 275, 275, 275 }, r = { { 249426, 2 }, { 3857, 1 } }, out = { 249726, 1 }, oq = 2 },
    [1306126] = { name = "Smelt Heavy Thorium", t = { 1, 300, 307, 315 }, r = { { 248815, 1 } }, out = { 251291, 1 }, oq = 2 },
  },
}

ES.Data.SellPrices = ES.Data.SellPrices or {}
ES.Data.SellPrices[2770] = 5
ES.Data.SellPrices[2771] = 25
ES.Data.SellPrices[2772] = 150
ES.Data.SellPrices[2775] = 75
ES.Data.SellPrices[2776] = 500
ES.Data.SellPrices[2840] = 10
ES.Data.SellPrices[2841] = 50
ES.Data.SellPrices[2842] = 100
ES.Data.SellPrices[3575] = 200
ES.Data.SellPrices[3576] = 35
ES.Data.SellPrices[3577] = 600
ES.Data.SellPrices[3857] = 125
ES.Data.SellPrices[3858] = 250
ES.Data.SellPrices[3859] = 60
ES.Data.SellPrices[3860] = 400
ES.Data.SellPrices[6037] = 1250
ES.Data.SellPrices[7911] = 500
ES.Data.SellPrices[10620] = 250
ES.Data.SellPrices[11370] = 500
ES.Data.SellPrices[11371] = 600
ES.Data.SellPrices[12359] = 600
ES.Data.SellPrices[248815] = 375
ES.Data.SellPrices[249426] = 375
ES.Data.SellPrices[249726] = 3000
ES.Data.SellPrices[251291] = 1500

ES.Data.ItemNames = ES.Data.ItemNames or {}
ES.Data.ItemNames[2770] = "Copper Ore"
ES.Data.ItemNames[2771] = "Tin Ore"
ES.Data.ItemNames[2772] = "Iron Ore"
ES.Data.ItemNames[2775] = "Silver Ore"
ES.Data.ItemNames[2776] = "Gold Ore"
ES.Data.ItemNames[2840] = "Copper Bar"
ES.Data.ItemNames[2841] = "Bronze Bar"
ES.Data.ItemNames[2842] = "Silver Bar"
ES.Data.ItemNames[3575] = "Iron Bar"
ES.Data.ItemNames[3576] = "Tin Bar"
ES.Data.ItemNames[3577] = "Gold Bar"
ES.Data.ItemNames[3857] = "Coal"
ES.Data.ItemNames[3858] = "Mithril Ore"
ES.Data.ItemNames[3859] = "Steel Bar"
ES.Data.ItemNames[3860] = "Mithril Bar"
ES.Data.ItemNames[6037] = "Truesilver Bar"
ES.Data.ItemNames[7911] = "Truesilver Ore"
ES.Data.ItemNames[10620] = "Thorium Ore"
ES.Data.ItemNames[11370] = "Dark Iron Ore"
ES.Data.ItemNames[11371] = "Dark Iron Bar"
ES.Data.ItemNames[12359] = "Thorium Bar"
ES.Data.ItemNames[248815] = "Heavy Thorium Ore"
ES.Data.ItemNames[249426] = "Pitchblende"
ES.Data.ItemNames[249726] = "Azerothium Bar"
ES.Data.ItemNames[251291] = "Heavy Thorium Bar"
