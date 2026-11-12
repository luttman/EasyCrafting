local source = assert(arg[1])
local output = assert(arg[2])
local facts = {}
for _, file in ipairs({ "Thresholds", "Recipes", "Trainer", "Vendor", "Sources" }) do
    local chunk = assert(loadfile(source .. "/Data/" .. file .. ".lua"))
    setfenv(chunk, {})
    chunk("Data", facts)
end

local out = assert(io.open(output, "w"))
out:write([[
-- Numeric game facts extracted from the installed SkillUp Forever 1.9.0 data.
-- Profession thresholds and item/reagent facts: WoW Forever 1.60.1.70888 DB2, https://wago.tools/db2/SkillLineAbility/csv?build=1.60.1.70888
-- Trainer observations and Classic references: https://github.com/cjber/skillup-forever and https://github.com/cmangos/classic-db
-- Format and implementation are specific to Vendor Profit.
local _, addon = ...
addon.RecipeData = {
]])
local function IDs(map)
    local ids = {}
    for id in pairs(map) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
end

for _, id in ipairs(IDs(facts.RecipeData)) do
    local r = facts.RecipeData[id]
    local thresholds = facts.Thresholds[id]
    if thresholds and r.skillLine then
        local fee = facts.TrainerFees[id]
        local yield = r.output and r.output.quantity
        local sell = r.output and facts.ItemSellPrices[r.output.itemID]
        out:write(("    [%d]={line=%d,first=%d,yellow=%d,gray=%d,item=%d,yield=%s,sale=%d"):format(
            id, r.skillLine, thresholds[1], thresholds[2], thresholds[4], r.output and r.output.itemID or 0,
            tostring(yield or 0), sell or 0))
        if fee then out:write((",train=%d,fee=%d"):format(fee[2], fee[1])) end
        local scroll = facts.RecipeScrolls[id]
        if type(scroll) == "table" then scroll = scroll[1] end
        if type(scroll) == "number" then out:write((",scroll=%d"):format(scroll)) end
        out:write(",reagents={")
        for _, reagent in ipairs(r.reagents) do
            out:write(("%d,%d,"):format(reagent.itemID, reagent.quantity))
        end
        out:write("}},\n")
    end
end
out:write("}\n")

local function Table(name, values, format)
    out:write("addon.", name, " = {\n")
    for _, id in ipairs(IDs(values)) do out:write(("    [%d]=%s,\n"):format(id, format(values[id]))) end
    out:write("}\n")
end
local function Rows(rows)
    local list = {}
    for _, row in ipairs(rows) do
        local fields = {}
        for i, v in ipairs(row) do fields[i] = type(v) == "string" and string.format("%q", v) or tostring(v) end
        list[#list + 1] = "{" .. table.concat(fields, ",") .. "}"
    end
    return "{" .. table.concat(list, ",") .. "}"
end
Table("VendorPrices", facts.VendorPrices, tostring)
Table("TrainerNPCs", facts.ProfessionTrainers, Rows)
Table("RecipeDrops", facts.ScrollDrops, Rows)
out:close()
