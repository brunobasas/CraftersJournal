exec(open(__file__.replace("craft_cost.py", "harness.py"), encoding="utf-8").read())
print(run(r"""
local out = {}
UnitFactionGroup = function() return "Alliance" end
out[#out+1] = string.format("%-15s %-9s | %12s %8s | %12s %8s | %s", "profesión", "tramo", "más barata", "fabric.", "elegida", "fabric.", "")
for _, key in ipairs({ "Cooking", "FirstAid", "Leatherworking", "Tailoring", "Blacksmithing", "Alchemy", "Engineering", "Enchanting" }) do
  for _, rg in ipairs({ { 1, 225 }, { 75, 150 }, { 150, 225 } }) do
    local o = ES:PlanOptions(key, rg[1], rg[2], nil)
    local cheapO = {} for k, v in pairs(o) do cheapO[k] = v end
    cheapO.craftCost = 0
    local cheap = ES.Planner:Plan(ES.Data[key], cheapO)
    local chosen = ES.Planner:Plan(ES.Data[key], o)
    local cc, ch = ES.Planner.TotalCrafts(cheap), ES.Planner.TotalCrafts(chosen)
    out[#out+1] = string.format("%-15s %3d-%-5d | %12.0f %8d | %12.0f %8d | %s", key, rg[1], rg[2], cheap.net, cc, chosen.net, ch,
      chosen.cheapest and string.format("-%d fabricaciones por +%.0f (%.1f%% de materiales)", cc - ch, chosen.net - cheap.net,
        (chosen.net - cheap.net) / math.max(1, cheap.reagentCost) * 100) or "igual")
  end
end
return table.concat(out, "\n")
"""))
