local _, addon = ...

local Money, ItemName, SpellName = addon.Money, addon.ItemName, addon.SpellName

local mapIDs
local function QuestieMap(area)
    if not mapIDs then
        local db = LibQuestieDB
        local zone = db and db.Support and db.Support.Get("ZoneDB")
        local source = zone and zone.private and zone.private.areaIdToUiMapId
        local chunk = type(source) == "string" and loadstring(source)
        if chunk then
            setfenv(chunk, {})
            local ok, result = pcall(chunk)
            if ok and type(result) == "table" then mapIDs = result end
        end
    end
    return mapIDs and mapIDs[area]
end

local function NPC(id)
    local db = LibQuestieDB
    if not db or not db.Npc or not db.Npc.GetAll then return end
    local ok, values = pcall(db.Npc.GetAll, id, { "name", "spawns", "friendlyToFaction" })
    if not ok or not values or not values[1] then return end
    local side = UnitFactionGroup("player")
    if values[3] == "A" and side ~= "Alliance" or values[3] == "H" and side ~= "Horde" then return end
    for area, points in pairs(values[2] or {}) do
        local map = QuestieMap(area)
        for _, point in ipairs(points) do
            if map and point[1] and point[2] and point[1] >= 0 and point[2] >= 0 then
                return values[1], map
            end
        end
    end
    return values[1]
end

local function SelectNPC(ids)
    local here = C_Map.GetBestMapForUnit("player")
    local best
    for _, id in ipairs(ids) do
        local name, map = NPC(id)
        if name and (not best or map and (not best[2] or map == here)) then
            best = { name, map }
            if map and map == here then break end
        end
    end
    if best then return best[1] end
end

local function Trainers(line, cap)
    local ids = {}
    for _, trainer in ipairs(addon.TrainerNPCs[line] or {}) do
        if trainer[2] >= cap then ids[#ids + 1] = trainer[1] end
    end
    return ids
end

local function ItemVendor(id)
    local db = LibQuestieDB
    if not db or not db.Item or not db.Item.GetAll then return end
    local ok, item = pcall(db.Item.GetAll, id, { "vendors" })
    if ok and item and type(item[1]) == "table" then return SelectNPC(item[1]) end
end

function addon.RecipeSource(id)
    local data = addon.RecipeData[id]
    if not data then return end
    if data.train then
        local cap = math.ceil(math.max(1, data.train) / 75) * 75
        local name = SelectNPC(Trainers(data.line, cap))
        local fee = data.fee > 0 and ("  ·  " .. Money(data.fee)) or ""
        return ("Trainer recipe at skill %d%s%s"):format(data.train, fee,
            name and ("  ·  Profession trainer " .. name) or "")
    end
    if data.scroll then
        local text = "Learn from " .. ItemName(data.scroll)
        local name = ItemVendor(data.scroll)
        if name then return text .. "  ·  Vendor " .. name end
        local drops = addon.RecipeDrops[data.scroll]
        if drops and drops[1] then
            local dropName = NPC(drops[1][1])
            if dropName then return text .. "  ·  Drop from " .. dropName end
        end
        return text
    end
end

function addon.RememberProfession(line, name, skill, cap, records)
    local guid = UnitGUID("player")
    if not guid or not line then return end
    VendorProfitSettings.alts = VendorProfitSettings.alts or {}
    local alts = VendorProfitSettings.alts
    local character = alts[guid] or { name = UnitName("player"), realm = GetRealmName(), professions = {} }
    alts[guid] = character
    local learned = {}
    for _, record in ipairs(records) do
        if record.info.learned then learned[#learned + 1] = record.info.recipeID end
    end
    character.professions[line] = { name = name, skill = skill, cap = cap, recipes = learned }
end

local function ReagentUses(id)
    local crafts = {}
    for recipe, data in pairs(addon.RecipeData) do
        for index = 1, #data.reagents, 2 do
            if data.reagents[index] == id then
                local quote, sale = addon.QuoteVendor(addon.OfflineSchematic(recipe))
                local profit = quote and sale and (sale - quote.cost)
                crafts[#crafts + 1] = { name = SpellName(recipe), count = data.reagents[index + 1], profit = profit }
                break
            end
        end
    end
    table.sort(crafts, function(a, b)
        if a.profit ~= b.profit then return (a.profit or -math.huge) > (b.profit or -math.huge) end
        return a.name < b.name
    end)
    local rows = { ItemName(id), "" }
    for _, craft in ipairs(crafts) do
        local amount = craft.profit and ((craft.profit < 0 and "-" or "+") .. Money(craft.profit))
        rows[#rows + 1] = ("%d × in %s%s"):format(craft.count, craft.name, amount and ("  ·  " .. amount .. " vendor profit") or "")
    end
    if #crafts == 0 then rows[#rows + 1] = "No bundled recipes use this material." end
    return table.concat(rows, "\n")
end

function addon.ToolText(key)
    local reagent = key and key:match("^reagent:(%d+)$")
    if reagent then return ReagentUses(tonumber(reagent)) end
    local guid, line = (key or ""):match("^alt:([^:]+):(%d+)$")
    if guid then
        local alt = VendorProfitSettings.alts[guid]
        local profession = alt and alt.professions[tonumber(line)]
        if not profession then return "" end
        local names = {}
        for _, id in ipairs(profession.recipes) do names[#names + 1] = SpellName(id) end
        table.sort(names)
        return ("%s  ·  %s %d/%d\n\n%s"):format(alt.name, profession.name, profession.skill, profession.cap,
            table.concat(names, "\n"))
    end
    return ""
end

function addon.ToolEntries(schematic)
    local entries = {}
    local seen = {}
    for _, slot in ipairs(schematic and schematic.reagentSlotSchematics or {}) do
        for _, reagent in ipairs(slot.reagents) do
            local id = reagent.itemID
            if id and not seen[id] then
                seen[id] = true
                entries[#entries + 1] = { "reagent:" .. id, "Uses for " .. ItemName(id) }
            end
        end
    end
    if addon.GetSetting("altProfessions") then
        local mine = UnitGUID("player")
        for guid, alt in pairs(VendorProfitSettings.alts or {}) do
            if guid ~= mine then
                for id, profession in pairs(alt.professions) do
                    entries[#entries + 1] = { "alt:" .. guid .. ":" .. id, alt.name .. " · " .. profession.name }
                end
            end
        end
    end
    return entries
end
