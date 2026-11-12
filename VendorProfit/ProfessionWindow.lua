local addonName, addon = ...
local window, page, native
local pending, failed
local records, entries, rows = {}, {}, {}
local collapsed = {}
local mode, filter, offset = "recipes", "all", 0
local professionID
local Refresh, DrawRows, DrawDetail
local savedAlpha, dockedTab, openingUntil
local nativeMouse = {}
local craftingJob, rankInfo
local linked
local GetSetting = function(key)
    return not addon.GetSetting or addon.GetSetting(key)
end

local colors = {
    background = { 0.075, 0.085, 0.095 },
    panel = { 0.095, 0.105, 0.115 },
    button = { 0.13, 0.15, 0.17 },
    border = { 0.22, 0.25, 0.28 },
    group = { 0.15, 0.17, 0.19 },
    selected = { 0.07, 0.22, 0.32 },
    banner = { 0.18, 0.15, 0.075 },
    accent = { 0.33, 0.77, 1 },
    bar = { 0.07, 0.51, 0.79 },
    text = { 0.94, 0.95, 0.97 },
    muted = { 0.66, 0.71, 0.76 },
    gold = { 1, 0.83, 0.35 },
    gain = { 0.40, 0.88, 0.60 },
    loss = { 1, 0.47, 0.47 },
}
local difficulty = { [0] = "Orange", [1] = "Yellow", [2] = "Green", [3] = "Gray" }
local difficultyColors = {
    [0] = { 1, 0.62, 0.30 },
    [1] = { 1, 0.88, 0.30 },
    [2] = { 0.51, 0.87, 0.39 },
    [3] = { 0.65, 0.69, 0.72 },
}
local fontSizes = { GameFontNormalLarge = 16, GameFontHighlight = 13 }
local rowHeight, listWidth = 20, 376

local function TextColor(region, color)
    region:SetTextColor(unpack(color))
end

local function Fill(texture, color)
    texture:SetColorTexture(unpack(color))
end

local function Surface(parent, layer, color)
    local texture = parent:CreateTexture(nil, layer)
    texture:SetAllPoints()
    Fill(texture, color)
    return texture
end

local function Label(parent, font, color)
    local text = parent:CreateFontString(nil, "OVERLAY", font)
    text:SetFont("Fonts\\ARIALN.TTF", fontSizes[font] or 12, "")
    TextColor(text, color)
    return text
end

local function Button(parent, text, width, action)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, 24)
    button:EnableMouse(true)
    button:RegisterForClicks("LeftButtonUp")
    Surface(button, "BACKGROUND", colors.border)
    local inner = button:CreateTexture(nil, "BORDER")
    inner:SetPoint("TOPLEFT", 1, -1)
    inner:SetPoint("BOTTOMRIGHT", -1, 1)
    Fill(inner, colors.button)
    local hover = button:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints(inner)
    Fill(hover, colors.selected)
    hover:SetAlpha(0.2)
    button.label = Label(button, "GameFontNormalSmall", colors.text)
    button.label:SetPoint("CENTER")
    button.label:SetText(text)
    button:SetScript("OnClick", action)
    button:SetScript("OnEnable", function() TextColor(button.label, colors.text) end)
    button:SetScript("OnDisable", function() TextColor(button.label, colors.muted) end)
    return button
end

local function Money(value)
    return GetMoneyString(math.floor(math.abs(value)), true)
end

local function ProfitText(value)
    local copper = math.floor(value)
    local sign = copper < 0 and "-" or copper > 0 and "+" or ""
    local color = copper < 0 and colors.loss or copper > 0 and colors.gain or colors.text
    return sign .. Money(copper), color
end

local function BagCount(id)
    return C_Item.GetItemCount(id, false, false, true) or 0
end

local function ItemName(id)
    return C_Item.GetItemNameByID(id) or ("Item #" .. id)
end

local function GetSchematic(info)
    if info.offline then return addon.OfflineSchematic(info.recipeID) end
    local ok, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, info.recipeID, false)
    if ok and schematic and schematic.reagentSlotSchematics then return schematic end
    if addon.OfflineSchematic then return addon.OfflineSchematic(info.recipeID) end
end

local function SelectedRecipe()
    if window and window.preview then return window.preview end
    return page.SchematicForm:GetRecipeInfo(), page.SchematicForm.recipeSchematic
end

local function Quantity()
    return math.max(1, math.min(999, tonumber(window.quantity:GetText()) or 1))
end

local function IsLinkedProfession()
    return C_TradeSkillUI.IsTradeSkillLinked and C_TradeSkillUI.IsTradeSkillLinked() == true or false
end

local function Active(isLinked, allowLoading)
    return not failed and page and page:IsVisible() and GetSetting("window")
        and not (VendorProfitSettings and VendorProfitSettings.native)
        and (addon.IsOwnProfession(allowLoading) or (isLinked and GetSetting("orders")))
end

local function HideNative()
    if savedAlpha == nil then savedAlpha = native:GetAlpha() end
    native:SetAlpha(0)
end

local function RestoreNative()
    openingUntil = nil
    if savedAlpha ~= nil then
        native:SetAlpha(savedAlpha)
        savedAlpha = nil
    end
    if InCombatLockdown() then return end
    for region, state in pairs(nativeMouse) do
        if state.click then region:SetMouseClickEnabled(true) end
        if state.motion then region:SetMouseMotionEnabled(true) end
        if state.wheel then region:EnableMouseWheel(true) end
        nativeMouse[region] = nil
    end
    if dockedTab then
        local tab = dockedTab.frame
        tab:ClearAllPoints()
        for _, point in ipairs(dockedTab.points) do tab:SetPoint(unpack(point)) end
        for frame, ignore in pairs(dockedTab.alpha) do frame:SetIgnoreParentAlpha(ignore) end
        dockedTab = nil
    end
end

-- The native page stays open for crafting, even while its controls are transparent.
local function DisableNativeMouse(region)
    if dockedTab and dockedTab.alpha[region] ~= nil then return end
    if region.IsForbidden and region:IsForbidden() then return end
    local click = region.IsMouseClickEnabled and region:IsMouseClickEnabled()
    local motion = region.IsMouseMotionEnabled and region:IsMouseMotionEnabled()
    local wheel = region.IsMouseWheelEnabled and region:IsMouseWheelEnabled()
    if click or motion or wheel then
        local state = nativeMouse[region] or {}
        nativeMouse[region] = state
        if click then
            state.click = true
            region:SetMouseClickEnabled(false)
        end
        if motion then
            state.motion = true
            region:SetMouseMotionEnabled(false)
        end
        if wheel then
            state.wheel = true
            region:EnableMouseWheel(false)
        end
    end
    if region.GetRegions then
        for _, child in ipairs({ region:GetRegions() }) do DisableNativeMouse(child) end
    end
    if region.GetChildren then
        for _, child in ipairs({ region:GetChildren() }) do DisableNativeMouse(child) end
    end
end

local function DockNativeTabs()
    local tab = native.ProfessionsOverviewTab
    if dockedTab or not tab or InCombatLockdown() then return end
    dockedTab = { frame = tab, points = {}, alpha = {} }
    for index = 1, tab:GetNumPoints() do dockedTab.points[index] = { tab:GetPoint(index) } end
    local tabs = { tab }
    for _, frame in ipairs(native.rightProfessionTabs or {}) do tabs[#tabs + 1] = frame end
    for _, frame in ipairs(tabs) do
        dockedTab.alpha[frame] = frame:IsIgnoringParentAlpha()
        frame:SetIgnoreParentAlpha(true)
    end
    tab:ClearAllPoints()
    tab:SetPoint("TOPLEFT", window, "TOPRIGHT", 0, -42)
end

local function QueueRefresh()
    if pending then return end
    pending = true
    C_Timer.After(0.08, function()
        pending = nil
        local ok, failure = xpcall(Refresh, function(message)
            return debugstack and (tostring(message) .. "\n" .. debugstack(2, 12, 0)) or message
        end)
        if not ok then
            failed = true
            if window then window:Hide() end
            RestoreNative()
            if geterrorhandler then geterrorhandler()(failure) else error(failure) end
        end
    end)
end

local function BatchText()
    if not craftingJob or not GetSetting("timer") then return end
    local text = ("Crafting  %d / %d"):format(craftingJob.done, craftingJob.count)
    if craftingJob.duration and craftingJob.ends then
        local seconds = math.max(0, craftingJob.ends - GetTime())
            + math.max(0, craftingJob.count - craftingJob.done - 1) * craftingJob.duration
        text = text .. ("  ·  %ds remaining"):format(math.ceil(seconds))
    end
    return text
end

local function ReadRecipes()
    records = {}
    local known = {}
    for _, id in ipairs(addon.RecipeIDs()) do
        local info = C_TradeSkillUI.GetRecipeInfo(id)
        if info and not info.isDummyRecipe and (info.learned or GetSetting("unlearned")) then
            known[id] = true
            local category = info.categoryID and C_TradeSkillUI.GetCategoryInfo(info.categoryID)
            records[#records + 1] = {
                info = info,
                category = category and category.name or "Other",
                order = category and category.uiOrder or 0,
                index = #records + 1,
            }
        end
    end
    if GetSetting("unlearned") then
        for id, data in pairs(addon.RecipeData or {}) do
            if data.line == professionID and not known[id] then
                local name = C_Spell.GetSpellName(id)
                if name then
                    records[#records + 1] = { info = { recipeID = id, name = name,
                        icon = C_Spell.GetSpellTexture(id), offline = true, learned = false },
                        order = 0, category = "Unlearned" }
                end
            end
        end
    end
    table.sort(records, function(a, b)
        if a.info.learned ~= b.info.learned then return a.info.learned == true end
        if GetSetting("favorites") and a.info.learned and a.info.favorite ~= b.info.favorite then
            return a.info.favorite == true
        end
        if a.order ~= b.order then return a.order < b.order end
        if a.category ~= b.category then return a.category < b.category end
        if (a.index ~= nil) ~= (b.index ~= nil) then return a.index ~= nil end
        if a.index and b.index then return a.index < b.index end
        return a.info.name < b.info.name
    end)
end

local function PriceRecord(record)
    if record.priced then return end
    record.priced = true
    local schematic = GetSchematic(record.info)
    if record.info.learned and not linked and GetSetting("craftCounts") and addon.CraftCounts then
        record.bagCrafts, record.merchantCrafts = addon.CraftCounts(schematic, BagCount)
    end
    local owned = addon.GetWork and GetSetting("owned") and addon.GetWork().owned or nil
    local quote, revenue = addon.QuoteVendor(schematic, nil, nil, owned)
    if quote and revenue and revenue > 0 then
        record.profit = revenue - quote.cost
    end
    if quote then record.netCost = quote.cost - (revenue or 0) end
    if addon.SkillChance and rankInfo then
        record.skillChance = addon.SkillChance(record.info.recipeID,
            (rankInfo.skillLevel or 0) + (rankInfo.skillModifier or 0), record.info.maxTrivialLevel)
    end
    local auction = GetSetting("auctionProfit") and addon.AuctionRevenue and addon.AuctionRevenue(schematic)
    if quote and auction then record.ahProfit = auction - quote.cost end
end

local function ListEntries()
    entries = {}
    local query = window.search:GetText():lower()
    local previousGroup
    for _, record in ipairs(records) do
        local info = record.info
        local eligible = mode ~= "skill" or (info.learned and info.canSkillUp)
        if eligible and (query == "" or info.name:lower():find(query, 1, true)) then
            local show = filter == "all" or (filter == "learned" and info.learned)
                or (filter == "favorites" and info.learned and info.favorite)
            if filter == "profit" and info.learned then
                PriceRecord(record)
                show = record.profit and record.profit > 0
            end
            if mode == "skill" then
                PriceRecord(record)
                show = true
            end
            if show then
                if mode == "skill" then
                    entries[#entries + 1] = record
                else
                    local group = not info.learned and "Unlearned"
                        or GetSetting("favorites") and info.favorite and "Favorites" or record.category
                    if group ~= previousGroup then
                        entries[#entries + 1] = { group = group }
                        previousGroup = group
                    end
                    if query ~= "" or not collapsed[group] then entries[#entries + 1] = record end
                end
            end
        end
    end
    if mode == "skill" then
        table.sort(entries, function(a, b)
            local aChance, bChance = a.skillChance or 0, b.skillChance or 0
            local aCost = a.netCost and aChance > 0 and a.netCost / (aChance * math.max(1, a.info.numSkillUps or 1)) or math.huge
            local bCost = b.netCost and bChance > 0 and b.netCost / (bChance * math.max(1, b.info.numSkillUps or 1)) or math.huge
            if aCost ~= bCost then return aCost < bCost end
            if aChance ~= bChance then return aChance > bChance end
            local aDifficulty, bDifficulty = a.info.relativeDifficulty or 4, b.info.relativeDifficulty or 4
            if aDifficulty ~= bDifficulty then return aDifficulty < bDifficulty end
            return a.info.name < b.info.name
        end)
    end
    DrawRows()
end

local function SetMode(value)
    mode = mode == value and "recipes" or value
    offset = 0
    window.rightScroll:SetVerticalScroll(0)
    Refresh()
end

local function SelectRow(row, button)
    local entry = row.entry
    if entry.group then
        collapsed[entry.group] = not collapsed[entry.group]
        ListEntries()
    elseif button == "RightButton" then
        if not linked and GetSetting("favorites") and entry.info.learned and C_TradeSkillUI.SetRecipeFavorite then
            C_TradeSkillUI.SetRecipeFavorite(entry.info.recipeID, not entry.info.favorite)
            QueueRefresh()
        end
    else
        window.preview = entry.info.offline and entry.info or nil
        if not window.preview then page:SelectRecipe(entry.info) end
        if mode == "shopping" or mode == "queue" or mode == "tools" then mode = "recipes" end
        window.rightScroll:SetVerticalScroll(0)
        DrawRows()
        DrawDetail()
        QueueRefresh()
    end
end

local function HoverRow(row)
    if not row.entry.info then return end
    local info = row.entry.info
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    local ok = pcall(GameTooltip.SetRecipeResultItem, GameTooltip, info.recipeID)
    if not ok or GameTooltip:NumLines() == 0 then GameTooltip:SetSpellByID(info.recipeID) end
    local entry = row.entry
    if GetSetting("craftCounts") and entry.bagCrafts then
        GameTooltip:AddDoubleLine("Craftable with materials in bags", tostring(entry.bagCrafts))
        if entry.merchantCrafts and entry.merchantCrafts > entry.bagCrafts then
            GameTooltip:AddDoubleLine("Craftable after buying merchant reagents", tostring(entry.merchantCrafts))
        end
    end
    GameTooltip:Show()
end

local function NewRow(index)
    local row = CreateFrame("Button", nil, window.list)
    row:SetHeight(rowHeight)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * rowHeight)
    row:SetPoint("TOPRIGHT", -12, -(index - 1) * rowHeight)
    row.background = Surface(row, "BACKGROUND", colors.group)
    row.highlight = Surface(row, "HIGHLIGHT", colors.accent)
    row.highlight:SetAlpha(0.16)
    row.count = Label(row, "GameFontNormalSmall", colors.text)
    row.count:SetJustifyH("RIGHT")
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", 8, 0)
    row.name = Label(row, "GameFontNormalSmall", colors.text)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.profit = Label(row, "GameFontNormalSmall", colors.text)
    row.profit:SetJustifyH("RIGHT")
    row.difficulty = Label(row, "GameFontNormalSmall", colors.muted)
    row.difficulty:SetWidth(42)
    row.difficulty:SetPoint("RIGHT", -6, 0)
    row.difficulty:SetJustifyH("RIGHT")
    row.ah = Label(row, "GameFontNormalSmall", colors.text)
    row.ah:SetJustifyH("RIGHT")
    row.ah:SetWidth(65)
    row.ah:SetPoint("RIGHT", row.difficulty, "LEFT", -5, 0)
    row.profit:SetWidth(65)
    row.profit:SetPoint("RIGHT", row.ah, "LEFT", -5, 0)
    row.name:SetPoint("RIGHT", row.profit, "LEFT", -8, 0)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", SelectRow)
    row:SetScript("OnEnter", HoverRow)
    row:SetScript("OnLeave", addon.HideRoute)
    row:SetScript("OnHide", addon.HideRoute)
    return row
end

DrawRows = function()
    local visible = math.max(1, math.floor(window.list:GetHeight() / rowHeight))
    local maximum = math.max(0, #entries - visible)
    offset = math.min(offset, maximum)
    local selected = SelectedRecipe()
    local countWidth = 0
    for index = 1, visible do
        local entry = entries[index + offset]
        local row = rows[index]
        if entry then
            row = row or NewRow(index)
            rows[index] = row
            row.entry = entry
            row.ah:SetWidth(GetSetting("auctionProfit") and 65 or 1)
            row.profit:SetWidth(GetSetting("vendorProfit") and 65 or 1)
            if entry.group then
                Fill(row.background, colors.group)
                row.background:Show()
                row.icon:Hide()
                row.count:SetText("")
                row.name:SetText((collapsed[entry.group] and "+  " or "-  ") .. entry.group)
                TextColor(row.name, colors.gold)
                row.profit:SetText("")
                row.ah:SetText("")
                TextColor(row.profit, colors.muted)
                TextColor(row.ah, colors.muted)
                row.difficulty:SetText("")
            else
                local info = entry.info
                Fill(row.background, colors.selected)
                row.background:SetShown(selected ~= nil and selected.recipeID == info.recipeID)
                row.icon:SetTexture(info.icon)
                row.icon:Show()
                row.name:SetText((GetSetting("favorites") and info.favorite and "* " or "") .. info.name)
                PriceRecord(entry)
                local nameColor = info.learned and (difficultyColors[info.relativeDifficulty] or colors.text) or colors.muted
                TextColor(row.name, nameColor)
                local counts = ""
                if GetSetting("craftCounts") and entry.bagCrafts then
                    local have = entry.bagCrafts
                    if have > 0 then counts = tostring(have) end
                    if entry.merchantCrafts and entry.merchantCrafts > have then
                        local separator = have > 0 and " || " or ""
                        counts = counts .. separator .. "|cffffa550" .. entry.merchantCrafts .. "|r"
                    end
                end
                row.count:SetText(counts)
                if counts ~= "" then countWidth = math.max(countWidth, row.count:GetStringWidth()) end
                local text, color = "-", colors.muted
                if entry.profit then text, color = ProfitText(entry.profit) end
                row.profit:SetText(GetSetting("vendorProfit") and text or "")
                TextColor(row.profit, color)
                local ahText, ahColor = "-", colors.muted
                if entry.ahProfit then ahText, ahColor = ProfitText(entry.ahProfit) end
                row.ah:SetText(GetSetting("auctionProfit") and ahText or "")
                TextColor(row.ah, ahColor)
                local chance = GetSetting("skillChances") and entry.skillChance
                row.difficulty:SetText(chance and ("%d%%"):format(math.floor(chance * 100 + 0.5))
                    or (info.learned and difficulty[info.relativeDifficulty] or ""))
                TextColor(row.difficulty, chance and chance > 0 and nameColor or colors.muted)
            end
            row:Show()
        elseif row then
            row:Hide()
        end
    end
    local iconX = countWidth > 0 and math.min(72, math.max(26, math.ceil(countWidth) + 10)) or 9
    for index = 1, math.min(visible, #rows) do
        local row = rows[index]
        if row:IsShown() then
            row.count:ClearAllPoints()
            row.count:SetPoint("RIGHT", row, "LEFT", iconX - 5, 0)
            row.icon:ClearAllPoints()
            row.icon:SetPoint("LEFT", iconX, 0)
            row.name:ClearAllPoints()
            row.name:SetPoint("LEFT", row, "LEFT", row.entry.group and 8 or iconX + 21, 0)
            row.name:SetPoint("RIGHT", row.profit, "LEFT", -8, 0)
        end
    end
    for index = visible + 1, #rows do rows[index]:Hide() end
    window.scrollbar.syncing = true
    window.scrollbar:SetMinMaxValues(0, math.max(1, maximum))
    window.scrollbar:SetValue(offset)
    window.scrollbar:SetShown(maximum > 0)
    window.scrollbar.syncing = nil
    window.empty:SetText(mode == "skill" and "No matching recipes can raise your skill" or "No matching recipes")
    window.empty:SetShown(#entries == 0)
end

local function DirectReagents(schematic, batches)
    local amounts = {}
    for _, slot in ipairs(schematic and schematic.reagentSlotSchematics or {}) do
        local reagent = slot.reagents[1]
        if slot.reagentType == Enum.CraftingReagentType.Basic and reagent and reagent.itemID then
            local id = reagent.itemID
            amounts[id] = (amounts[id] or 0) + slot.quantityRequired * batches
        end
    end
    return amounts
end

local function MaterialIDs(amounts)
    local ids = {}
    for id in pairs(amounts) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b) return ItemName(a) < ItemName(b) end)
    return ids
end

local function MaterialLines(amounts)
    local lines = {}
    for _, id in ipairs(MaterialIDs(amounts)) do
        local icon = C_Item.GetItemIconByID(id) or 134400
        local amount = amounts[id]
        local unitPrice, source = addon.PurchasePrice(id)
        local cost = unitPrice and (Money(unitPrice * amount) .. "  " .. source) or "Price unavailable"
        lines[#lines + 1] = ("|T%d:16:16|t  %d x %s  |cff9eaab5%s|r"):format(icon, amount, ItemName(id), cost)
    end
    return table.concat(lines, "\n")
end

local function DrawShopping(info, schematic)
    if addon.ShoppingPlan then
        local needs, prerequisites, jobs = addon.ShoppingPlan(BagCount)
        window.needs, window.prerequisites, window.jobs = needs, prerequisites, jobs
        if #jobs > 0 then
            local lines = { "|cffffd459Saved crafts|r" }
            for _, job in ipairs(jobs) do
                lines[#lines + 1] = ("%d × %s"):format(job.quantity, C_Spell.GetSpellName(job.id) or ("Recipe #" .. job.id))
            end
            local merchant, auction = {}, {}
            for id, quantity in pairs(needs) do
                local _, source = addon.PurchasePrice(id)
                if source == "merchant" then merchant[id] = quantity else auction[id] = quantity end
            end
            if next(merchant) then
                lines[#lines + 1] = "\n|cffffd459Buy from a merchant|r\n" .. MaterialLines(merchant)
            end
            if next(auction) then
                lines[#lines + 1] = "\n|cffffd459Buy on the Auction House|r\n" .. MaterialLines(auction)
            end
            if not next(needs) then lines[#lines + 1] = "\nYou have the required materials in your bags." end
            if #prerequisites > 0 then
                lines[#lines + 1] = "\n|cffffd459Craft first|r"
                for _, step in ipairs(prerequisites) do
                    lines[#lines + 1] = ("%d × %s"):format(step.batches, step.recipeName or ItemName(step.itemID))
                end
            end
            return table.concat(lines, "\n")
        end
    end
    if not info then return "Select a recipe and add it to the list." end
    local count = Quantity()
    local quote = addon.QuoteVendor(schematic, page.SchematicForm:GetTransaction(), count)
    local needs
    if quote then
        needs = addon.ShoppingNeeds(quote, BagCount)
    else
        needs = DirectReagents(schematic, count)
        for id, amount in pairs(needs) do
            needs[id] = amount > BagCount(id) and amount - BagCount(id) or nil
        end
    end
    local intro = ("%d %s of %s"):format(count, count == 1 and "craft" or "crafts", info.name)
    window.needs = needs
    local details = next(needs) and MaterialLines(needs) or "You have the required materials in your bags."
    if not quote then intro = intro .. "\nSome prices are missing. Showing direct reagents." end
    return intro .. "\n\n" .. details
end

local function DrawQueue()
    local needs, prerequisites, jobs = addon.ShoppingPlan(BagCount)
    window.needs, window.prerequisites, window.jobs = needs, prerequisites, jobs
    if #jobs == 0 then return "Add a recipe to the shopping list to queue it." end
    local lines = {}
    for _, step in ipairs(prerequisites) do
        lines[#lines + 1] = ("%d × %s  |cffabb7c4Reagent|r"):format(step.batches, step.recipeName or ItemName(step.itemID))
    end
    for _, job in ipairs(jobs) do
        lines[#lines + 1] = ("%d × %s"):format(job.quantity, C_Spell.GetSpellName(job.id) or ("Recipe #" .. job.id))
    end
    if next(needs) then lines[#lines + 1] = "\nOpen the shopping list to see missing materials." end
    if craftingJob then
        lines[#lines + 1] = ("\nCrafting %d of %d complete"):format(craftingJob.done, craftingJob.count)
    end
    return table.concat(lines, "\n")
end

local function SetAmount(region, amount)
    region:SetText(amount and Money(amount) or "-")
end

local function DrawSkillBar(info)
    local bar = window.skillRange
    local first, yellow, green, gray
    if info and not linked and GetSetting("skillChances") then
        first, yellow, green, gray = addon.SkillRange(info.recipeID, info.maxTrivialLevel)
    end
    local show = first ~= nil and gray > first
    bar:SetShown(show)
    if not show then return false end

    local width = math.max(1, window.detail:GetWidth() - 36)
    local positions = { first, yellow, green, gray }
    local function X(skill)
        return width * 0.96 * math.max(0, math.min(1, (skill - first) / (gray - first)))
    end
    for index, value in ipairs(positions) do
        local segment = bar.segments[index]
        local start = X(value)
        local finish = positions[index + 1] and X(positions[index + 1]) or width
        segment:SetShown(finish > start)
        segment:SetPoint("TOPLEFT", start, 0)
        segment:SetWidth(math.max(1, finish - start))
        local label = bar.labels[index]
        label:SetShown(index == 1 or positions[index - 1] ~= value)
        label:SetPoint("TOP", bar, "TOPLEFT", start, -13)
        label:SetText(value)
    end
    local skill = (rankInfo.skillLevel or 0) + (rankInfo.skillModifier or 0)
    local marker = skill > gray and width or X(skill)
    bar.marker:SetPoint("TOPLEFT", marker - 1, 2)
    local chance = addon.SkillChance(info.recipeID, skill, info.maxTrivialLevel)
    bar.chance:SetText(("%d%%"):format(math.floor(chance * 100 + 0.5)))
    return true
end

local function ReagentRow(panel, index)
    local row = CreateFrame("Frame", nil, panel)
    row:SetPoint("TOPLEFT", 0, -20 - (index - 1) * 36)
    row:SetPoint("TOPRIGHT", 0, -20 - (index - 1) * 36)
    row:SetHeight(36)
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(self.itemID)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", addon.HideRoute)
    row:SetScript("OnHide", addon.HideRoute)
    row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.check:SetSize(18, 18)
    row.check:SetPoint("LEFT")
    row.check:SetScript("OnClick", function(check)
        addon.GetWork().owned[row.itemID] = not check:GetChecked() or nil
        QueueRefresh()
    end)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(28, 28)
    row.name = Label(row, "GameFontHighlight", colors.text)
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 7, 0)
    row.required = Label(row, "GameFontNormalSmall", colors.text)
    row.required:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 7, 0)
    row.bags = Label(row, "GameFontNormalSmall", colors.muted)
    row.bags:SetPoint("RIGHT", -46, 0)
    row.bank = Label(row, "GameFontNormalSmall", colors.muted)
    row.bank:SetPoint("RIGHT", -3, 0)
    return row
end

local function DrawReagents(schematic)
    local panel = window.reagents
    local amounts = DirectReagents(schematic, 1)
    local ids = MaterialIDs(amounts)
    local showInventory, showChecks = GetSetting("inventory"), GetSetting("owned") and not linked
    local owned = addon.GetWork().owned
    panel:SetShown(#ids > 0)
    panel.bags:SetShown(showInventory)
    panel.bank:SetShown(showInventory)
    for index, id in ipairs(ids) do
        local row = panel.rows[index] or ReagentRow(panel, index)
        panel.rows[index] = row
        row.itemID = id
        local have, need = BagCount(id), amounts[id]
        row.icon:SetTexture(C_Item.GetItemIconByID(id) or 134400)
        row.icon:SetPoint("LEFT", showChecks and 23 or 0, 0)
        row.name:SetText(ItemName(id))
        row.required:SetText(("%d/%d"):format(have, need))
        TextColor(row.required, have >= need and colors.text or colors.loss)
        row.check:SetShown(showChecks)
        row.check:SetChecked(not owned[id])
        row.bags:SetShown(showInventory)
        row.bank:SetShown(showInventory)
        if showInventory then
            row.bags:SetText(have)
            row.bank:SetText(math.max(0, (C_Item.GetItemCount(id, true, false, true) or have) - have))
        end
        row:Show()
    end
    for index = #ids + 1, #panel.rows do panel.rows[index]:Hide() end
    local height = #ids > 0 and 20 + #ids * 36 or 1
    panel:SetHeight(height)
    return #ids > 0 and height + 14 or 0
end

local function RecipeDescription(info)
    local description
    if C_TradeSkillUI.GetRecipeDescription then
        local ok, text = pcall(C_TradeSkillUI.GetRecipeDescription, info.recipeID, {})
        if ok then description = text end
    end
    description = description or C_Spell.GetSpellDescription(info.recipeID) or ""
    if C_TradeSkillUI.GetRecipeRequirements and not info.offline and not linked then
        local ok, requirements = pcall(C_TradeSkillUI.GetRecipeRequirements, info.recipeID)
        local names = {}
        for _, req in ipairs(ok and requirements or {}) do
            if req.name then names[#names + 1] = req.met and req.name or ("|cffff7878" .. req.name .. "|r") end
        end
        if #names > 0 then description = description .. "\nRequires: " .. table.concat(names, ", ") end
    end
    return description
end

DrawDetail = function()
    local info, schematic = SelectedRecipe()
    local shopping, queue, tools = mode == "shopping", mode == "queue", mode == "tools"
    local special = shopping or queue or tools
    window.detail:SetShown(info ~= nil or special)
    if not info and not special then return end
    window.rightContent:SetWidth(math.max(1, window.rightScroll:GetWidth()))
    schematic = schematic or (info and GetSchematic(info))
    local count = Quantity()
    local learned = info and info.learned == true and not linked
    local craftable = learned and page:GetCraftableCount() or 0
    local showBar = DrawSkillBar(not special and info or nil)
    window.rightScroll:SetPoint("TOPLEFT", 12, showBar and -115 or -65)
    window.rightScroll:SetPoint("BOTTOMRIGHT", -32, special and 82 or 184)
    local reagentsHeight = 0
    if special then window.reagents:Hide() end
    window.recipeName:SetText(shopping and "Shopping list"
        or queue and "Crafting queue" or tools and "Profession tools" or info.name)
    window.recipeIcon:SetTexture(info and info.icon or 134400)
    window.favorite:SetShown(learned == true and not special and GetSetting("favorites"))
    window.favorite.star:SetAtlas(info and info.favorite and "auctionhouse-icon-favorite" or "auctionhouse-icon-favorite-off")
    window.track:SetShown(learned == true and not special)
    if window.track:IsShown() then
        window.track:SetChecked(C_TradeSkillUI.IsRecipeTracked(info.recipeID, false))
    end
    window.searchPrices:SetShown(shopping and AuctionHouseFrame ~= nil and AuctionHouseFrame:IsShown())
    window.create:SetShown(not special)
    window.createAll:SetShown(not special)
    window.create:SetEnabled(learned == true and page.CreateButton:IsEnabled() and count <= craftable)
    window.createAll:SetEnabled(learned == true and page.CreateAllButton:IsEnabled() and craftable > 0)
    window.createAll.label:SetText(("Create all (%d)"):format(craftable))
    window.profitPanel:SetShown(not special)
    if window.addShopping then
        window.addShopping:SetShown(GetSetting("shopping") and not special and schematic ~= nil)
        window.queueNext:SetShown(queue)
        window.removeShopping:SetShown(shopping and info ~= nil and addon.GetWork().shopping[info.recipeID] ~= nil)
        window.manageShopping:SetShown(shopping and next(addon.GetWork().shopping) ~= nil)
        window.buy:SetShown(shopping and GetSetting("buy") and
            ((AuctionHouseFrame and AuctionHouseFrame:IsShown()) or (MerchantFrame and MerchantFrame:IsShown()) or false))
        window.moreQuantity:SetShown(not (queue or tools))
        window.lessQuantity:SetShown(not (queue or tools))
        window.quantity:SetShown(not (queue or tools))
        window.draft:SetShown(linked == true and not special and info ~= nil and info.learned == true)
        window.create:SetShown(not special and not linked)
        window.createAll:SetShown(not special and not linked)
    end

    if shopping then
        window.materials:SetText(DrawShopping(info, schematic))
    elseif queue then
        window.materials:SetText(DrawQueue())
    elseif tools then
        window.materials:SetText(addon.ToolText and addon.ToolText(window.tool, info, schematic) or "")
    else
        local description = RecipeDescription(info)
        if not info.learned then description = "Recipe not learned\n" .. description end
        if GetSetting("sources") and addon.RecipeSource then
            local source = addon.RecipeSource(info.recipeID)
            if source then description = description .. "\n" .. source end
        end
        window.materials:SetText(description)
        reagentsHeight = DrawReagents(schematic)
    end
    window.rightContent:SetHeight(math.max(1, window.materials:GetStringHeight() + reagentsHeight + 12))
    if special then return end
    local owned = addon.GetWork and GetSetting("owned") and addon.GetWork().owned or nil
    local transaction = not window.preview and page.SchematicForm:GetTransaction() or nil
    local quote, revenue = addon.QuoteVendor(schematic, transaction, nil, owned)
    SetAmount(window.cost, quote and quote.cost)
    SetAmount(window.revenue, revenue)
    local value, color = "-", colors.muted
    if quote and revenue and revenue > 0 then value, color = ProfitText(revenue - quote.cost) end
    window.profitValue:SetText(value)
    TextColor(window.profitValue, color)
    window.profitLabel:SetText(schematic and schematic.quantityMax and schematic.quantityMin
        and schematic.quantityMax > schematic.quantityMin and "Profit to vendor (min. yield)" or "Profit to vendor")
    window.profitHover.quote, window.profitHover.revenue = quote, revenue
    window.profitHover.status = not schematic and "Recipe data unavailable" or nil
    if GameTooltip:IsOwned(window.profitHover) then addon.ShowRoute(window.profitHover) end
    if window.auctionLine then
        local auction, gross
        if GetSetting("auctionProfit") then auction, gross = addon.AuctionRevenue(schematic) end
        local result = auction and quote and auction - quote.cost
        local ahText, ahColor = "-", colors.muted
        if result then ahText, ahColor = ProfitText(result) end
        if result and quote.cost > 0 and GetSetting("roi") then
            ahText = ahText .. ("  (%+.0f%% ROI)"):format(result * 100 / quote.cost)
        end
        window.auctionLine:SetShown(GetSetting("auctionProfit"))
        window.auctionValue:SetShown(GetSetting("auctionProfit"))
        window.auctionSaleLabel:SetShown(GetSetting("auctionProfit"))
        window.auctionSale:SetShown(GetSetting("auctionProfit"))
        SetAmount(window.auctionSale, gross)
        window.auctionValue:SetText(ahText)
        TextColor(window.auctionValue, ahColor)
        window.profitHover:SetShown(GetSetting("vendorProfit"))
    end
end

local function Craft(all)
    if linked or craftingJob or InCombatLockdown() or not Active(linked) then return end
    local info = SelectedRecipe()
    if not info or not info.learned then return end
    local craftable = page:GetCraftableCount()
    if all and craftable > 0 and page.CreateAllButton:IsEnabled() then
        craftingJob = { id = info.recipeID, count = craftable, done = 0 }
        page:CreateAll()
    elseif not all and Quantity() <= craftable and page.CreateButton:IsEnabled() then
        craftingJob = { id = info.recipeID, count = Quantity(), done = 0 }
        page.CreateMultipleInputBox:SetValue(Quantity())
        page:Create()
    end
    QueueRefresh()
end

local function LinkProfession()
    local link = C_TradeSkillUI.GetTradeSkillListLink()
    if not link then
        print("Vendor Profit: this profession has no chat link.")
        return
    end
    if not ChatEdit_InsertLink(link) then ChatFrame_OpenChat(link) end
end

local function SearchPrices()
    if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then return end
    local _, schematic = SelectedRecipe()
    if addon.SearchMaterials then
        local items = addon.PriceCandidates(schematic)
        for id in pairs(window.needs or {}) do items[id] = true end
        for _, job in ipairs(window.jobs or {}) do
            for id in pairs(addon.PriceCandidates(addon.OfflineSchematic(job.id))) do items[id] = true end
        end
        return addon.SearchMaterials(items)
    end
    local names = {}
    for id in pairs(addon.PriceCandidates(schematic)) do
        local name = C_Item.GetItemNameByID(id)
        if name then names[#names + 1] = name end
    end
    if #names == 0 then return end
    table.sort(names)
    local api = Auctionator.API.v1
    local search = api.MultiSearchExact or api.MultiSearch
    search(addonName, names)
end

local function ManageShopping(button)
    local shopping = addon.GetWork().shopping
    MenuUtil.CreateContextMenu(button, function(_, menu)
        local ids = {}
        for id in pairs(shopping) do ids[#ids + 1] = id end
        table.sort(ids)
        for _, id in ipairs(ids) do
            local recipe = id
            local name = C_Spell.GetSpellName(recipe) or ("Recipe #" .. recipe)
            local sub = menu:CreateButton(("%d × %s"):format(shopping[recipe].quantity, name))
            sub:CreateButton("Add one", function()
                shopping[recipe].quantity = math.min(999, shopping[recipe].quantity + 1)
                DrawDetail()
            end)
            sub:CreateButton("Remove one", function()
                shopping[recipe].quantity = shopping[recipe].quantity - 1
                if shopping[recipe].quantity == 0 then shopping[recipe] = nil end
                DrawDetail()
            end)
            sub:CreateButton("Remove recipe", function() shopping[recipe] = nil; DrawDetail() end)
        end
    end)
end

local function BuyMaterials()
    if AuctionHouseFrame and AuctionHouseFrame:IsShown() then
        local needed = {}
        for id, count in pairs(window.needs or {}) do
            local _, source = addon.PurchasePrice(id)
            if source ~= "merchant" then needed[id] = count end
        end
        addon.SearchMaterials(needed)
        return
    end
    local offers = addon.MerchantOffers(window.needs or {})
    if #offers == 0 then
        print("Vendor Profit: this merchant has none of the materials on your list.")
        return
    end
    local total = 0
    for _, offer in ipairs(offers) do total = total + offer.total end
    StaticPopupDialogs.VENDORPROFIT_BUY = StaticPopupDialogs.VENDORPROFIT_BUY or {
        text = "Buy these materials for %s?",
        button1 = BUY, button2 = CANCEL, timeout = 0, whileDead = false, hideOnEscape = true,
        OnAccept = function(_, pending)
            if not (MerchantFrame and MerchantFrame:IsShown()) then return end
            local current = addon.MerchantOffers(pending.needs)
            if #current ~= #pending.offers then return end
            for index, offer in ipairs(current) do
                local approved = pending.offers[index]
                if offer.id ~= approved.id or offer.index ~= approved.index or offer.total ~= approved.total
                    or offer.quantity ~= approved.quantity then return end
            end
            if GetMoney() < pending.total then return end
            for _, offer in ipairs(current) do BuyMerchantItem(offer.index, offer.quantity) end
            QueueRefresh()
        end,
    }
    StaticPopup_Show("VENDORPROFIT_BUY", Money(total), nil, { needs = window.needs, offers = offers, total = total })
end

local function CraftNext()
    if linked or craftingJob or InCombatLockdown() or not Active(linked) then return end
    local nextJob
    if window.prerequisites and window.prerequisites[1] then
        local step = window.prerequisites[1]
        nextJob = { id = step.recipeID, quantity = step.batches }
    elseif window.jobs then
        nextJob = window.jobs[1]
    end
    if not nextJob then return end
    local info = C_TradeSkillUI.GetRecipeInfo(nextJob.id)
    if not info or not info.learned or (C_TradeSkillUI.IsRecipeInSkillLine
        and not C_TradeSkillUI.IsRecipeInSkillLine(nextJob.id, professionID)) then
        print("Vendor Profit: open the profession for " .. (C_Spell.GetSpellName(nextJob.id) or nextJob.id) .. ".")
        return
    end
    window.preview = nil
    page:SelectRecipe(info)
    local count = math.min(nextJob.quantity, page:GetCraftableCount())
    if count <= 0 or not page.CreateButton:IsEnabled() then
        print("Vendor Profit: check the recipe's materials and crafting requirements.")
        return
    end
    craftingJob = { id = nextJob.id, count = count, done = 0 }
    page.CreateMultipleInputBox:SetValue(count)
    page:Create()
    QueueRefresh()
end

local function OpenTools(button)
    MenuUtil.CreateContextMenu(button, function(_, menu)
        menu:CreateButton("Settings", addon.OpenSettings)
        if GetSetting("queue") then menu:CreateButton("Crafting queue", function() SetMode("queue") end) end
        if GetSetting("skillChances") then menu:CreateButton("Best for skill-ups", function() SetMode("skill") end) end
        if addon.ToolEntries then
            local info, schematic = SelectedRecipe()
            for _, entry in ipairs(addon.ToolEntries(schematic or (info and GetSchematic(info)))) do
                local key = entry[1]
                menu:CreateButton(entry[2], function()
                    if entry[3] then
                        entry[3](SelectedRecipe())
                    else
                        window.tool = key
                        mode = "tools"
                        Refresh()
                    end
                end)
            end
        end
    end)
end

local function OpenFilter(button)
    MenuUtil.CreateContextMenu(button, function(_, menu)
        for _, option in ipairs({
            { "all", "All recipes" }, { "learned", "Learned recipes" },
            { "favorites", "Favorites" }, { "profit", "Vendor profit above zero" },
        }) do
            local key, label = unpack(option)
            menu:CreateRadio(label, function() return filter == key end, function()
                filter, mode, offset = key, "recipes", 0
                Refresh()
            end)
        end
    end)
end

local function BuildList()
    local search = CreateFrame("EditBox", nil, window, "SearchBoxTemplate")
    window.search = search
    search:SetSize(listWidth - 76, 24)
    search:SetPoint("TOPLEFT", 8, -69)
    search:SetAutoFocus(false)
    search:SetScript("OnTextChanged", function(self)
        SearchBoxTemplate_OnTextChanged(self)
        offset = 0
        ListEntries()
    end)
    local filters = Button(window, "Filter", 68, OpenFilter)
    filters:SetPoint("LEFT", search, "RIGHT", 8, 0)

    local columns = CreateFrame("Frame", nil, window)
    columns:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -7)
    columns:SetSize(listWidth, 22)
    Surface(columns, "BACKGROUND", colors.group)
    local columnRecipe = Label(columns, "GameFontNormalSmall", colors.muted)
    columnRecipe:SetPoint("LEFT", 9, 0)
    columnRecipe:SetText("Recipe")
    local columnSkill = Label(columns, "GameFontNormalSmall", colors.muted)
    columnSkill:SetPoint("RIGHT", -18, 0)
    columnSkill:SetText("Skill")
    window.columnAH = Label(columns, "GameFontNormalSmall", colors.muted)
    window.columnAH:SetPoint("RIGHT", -67, 0)
    window.columnAH:SetText("Auction")
    window.columnVendor = Label(columns, "GameFontNormalSmall", colors.muted)
    window.columnVendor:SetText("Vendor")

    local list = CreateFrame("Frame", nil, window)
    window.list = list
    list:SetPoint("TOPLEFT", columns, "BOTTOMLEFT", 0, -1)
    list:SetPoint("BOTTOMLEFT", 8, 8)
    list:SetWidth(listWidth)
    Surface(list, "BACKGROUND", colors.panel)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, offset - delta * 3)
        DrawRows()
    end)
    window.empty = Label(list, "GameFontNormalSmall", colors.muted)
    window.empty:SetPoint("TOPLEFT", 8, -8)
    window.empty:SetText("No matching recipes")

    local slider = CreateFrame("Slider", nil, list)
    window.scrollbar = slider
    slider:SetOrientation("VERTICAL")
    slider:SetPoint("TOPRIGHT", -2, -2)
    slider:SetPoint("BOTTOMRIGHT", -2, 2)
    slider:SetWidth(6)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    local thumb = slider:CreateTexture(nil, "ARTWORK")
    thumb:SetSize(6, 24)
    Fill(thumb, colors.bar)
    slider:SetThumbTexture(thumb)
    slider:EnableMouse(true)
    slider:SetScript("OnValueChanged", function(self, value)
        if not self.syncing then
            offset = math.floor(value)
            DrawRows()
        end
    end)

end

local function BuildDetail()
    local detail = CreateFrame("Frame", nil, window)
    window.detail = detail
    detail:SetPoint("TOPLEFT", listWidth + 16, -70)
    detail:SetPoint("BOTTOMRIGHT", -8, 8)
    Surface(detail, "BACKGROUND", colors.panel)
    window.recipeIcon = detail:CreateTexture(nil, "ARTWORK")
    window.recipeIcon:SetSize(42, 42)
    window.recipeIcon:SetPoint("TOPLEFT", 12, -12)
    window.recipeName = Label(detail, "GameFontNormalLarge", colors.text)
    window.recipeName:SetPoint("LEFT", window.recipeIcon, "RIGHT", 8, 0)
    window.recipeName:SetPoint("RIGHT", -144, 0)
    window.recipeName:SetJustifyH("LEFT")
    window.recipeName:SetWordWrap(false)

    window.favorite = Button(detail, "", 24, function()
        local info = SelectedRecipe()
        if info and C_TradeSkillUI.SetRecipeFavorite then
            C_TradeSkillUI.SetRecipeFavorite(info.recipeID, not info.favorite)
            QueueRefresh()
        end
    end)
    window.favorite:SetPoint("TOPRIGHT", -12, -21)
    window.favorite.star = window.favorite:CreateTexture(nil, "ARTWORK")
    window.favorite.star:SetSize(16, 16)
    window.favorite.star:SetPoint("CENTER")
    window.track = CreateFrame("CheckButton", nil, detail, "UICheckButtonTemplate")
    window.track:SetSize(22, 22)
    window.track:SetPoint("TOPRIGHT", -44, -22)
    local track = Label(window.track, "GameFontNormalSmall", colors.muted)
    track:SetPoint("RIGHT", window.track, "LEFT", -4, 0)
    track:SetText("Track recipe")
    window.track:SetScript("OnClick", function(self)
        local info = SelectedRecipe()
        if info then C_TradeSkillUI.SetRecipeTracked(info.recipeID, self:GetChecked(), false) end
    end)

    local range = CreateFrame("Frame", nil, detail)
    window.skillRange = range
    range:SetPoint("TOPLEFT", 12, -61)
    range:SetPoint("TOPRIGHT", -24, -61)
    range:SetHeight(42)
    range.segments, range.labels = {}, {}
    for index = 1, 4 do
        local segment = range:CreateTexture(nil, "ARTWORK")
        segment:SetHeight(9)
        Fill(segment, difficultyColors[index - 1])
        range.segments[index] = segment
        range.labels[index] = Label(range, "GameFontNormalSmall", colors.muted)
    end
    range.marker = range:CreateTexture(nil, "OVERLAY")
    range.marker:SetSize(2, 13)
    Fill(range.marker, colors.text)
    range.chance = Label(range, "GameFontNormalSmall", colors.text)
    range.chance:SetPoint("TOPRIGHT", 0, -28)

    local scroll = CreateFrame("ScrollFrame", nil, detail)
    window.rightScroll = scroll
    scroll:SetPoint("TOPLEFT", 12, -91)
    scroll:SetPoint("BOTTOMRIGHT", -32, 112)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local scrollTo = math.max(0, math.min(self:GetVerticalScrollRange(), self:GetVerticalScroll() - delta * 36))
        self:SetVerticalScroll(scrollTo)
    end)
    window.rightContent = content
    window.materials = Label(content, "GameFontHighlight", colors.text)
    window.materials:SetPoint("TOPLEFT")
    window.materials:SetPoint("TOPRIGHT")
    window.materials:SetJustifyH("LEFT")
    window.materials:SetJustifyV("TOP")
    window.materials:SetSpacing(4)
    scroll:SetScript("OnSizeChanged", function(self, width) content:SetWidth(math.max(1, width)) end)
    local reagents = CreateFrame("Frame", nil, content)
    window.reagents = reagents
    reagents:SetPoint("TOPLEFT", window.materials, "BOTTOMLEFT", 0, -12)
    reagents:SetPoint("TOPRIGHT", window.materials, "BOTTOMRIGHT", 0, -12)
    reagents:SetHeight(1)
    reagents.rows = {}
    local reagentTitle = Label(reagents, "GameFontHighlight", colors.gold)
    reagentTitle:SetPoint("TOPLEFT")
    reagentTitle:SetText("Reagents")
    reagents.bags = Label(reagents, "GameFontNormalSmall", colors.muted)
    reagents.bags:SetPoint("TOPRIGHT", -46, 0)
    reagents.bags:SetText("Bags")
    reagents.bank = Label(reagents, "GameFontNormalSmall", colors.muted)
    reagents.bank:SetPoint("TOPRIGHT", -3, 0)
    reagents.bank:SetText("Bank")

    local totals = CreateFrame("Frame", nil, detail)
    window.profitPanel = totals
    totals:SetPoint("BOTTOMLEFT", 12, 43)
    totals:SetPoint("BOTTOMRIGHT", -12, 43)
    totals:SetHeight(94)
    local totalsBackground = totals:CreateTexture(nil, "BACKGROUND")
    totalsBackground:SetPoint("TOPLEFT", -5, 2)
    totalsBackground:SetPoint("BOTTOMRIGHT", 5, -2)
    Fill(totalsBackground, colors.background)
    local function AmountRow(label, y, parent)
        local title = Label(parent, "GameFontNormalSmall", colors.gold)
        title:SetPoint("TOPLEFT", 0, y)
        title:SetText(label)
        local value = Label(parent, "GameFontHighlight", colors.text)
        value:SetPoint("TOPLEFT", 156, y)
        return value, title
    end
    window.cost = AmountRow("Buy for", -2, totals)
    window.revenue = AmountRow("Sell to vendor for", -21, totals)
    if addon.GetSetting then
        window.auctionSale, window.auctionSaleLabel = AmountRow("Sell on auction for", -39, totals)
        window.auctionValue, window.auctionLine = AmountRow("Auction profit after cut", -57, totals)
    end
    local hover = CreateFrame("Frame", nil, totals)
    window.profitHover = hover
    hover:SetPoint("BOTTOMLEFT")
    hover:SetPoint("BOTTOMRIGHT")
    hover:SetHeight(19)
    hover:EnableMouse(true)
    hover:SetScript("OnEnter", addon.ShowRoute)
    hover:SetScript("OnLeave", addon.HideRoute)
    hover:SetScript("OnHide", addon.HideRoute)
    window.profitValue, window.profitLabel = AmountRow("Profit to vendor", -1, hover)

    window.create = Button(detail, "Create", 88, function() Craft(false) end)
    window.create:SetPoint("BOTTOMRIGHT", -12, 9)
    window.createAll = Button(detail, "Create all", 112, function() Craft(true) end)
    window.createAll:SetPoint("BOTTOMLEFT", 12, 9)
    window.searchPrices = Button(detail, "Refresh prices", 112, SearchPrices)
    window.searchPrices:SetPoint("BOTTOMRIGHT", -12, 9)
    local qty = CreateFrame("EditBox", nil, detail, "InputBoxTemplate")
    window.quantity = qty
    qty:SetSize(36, 24)
    qty:SetPoint("BOTTOM", 9, 9)
    qty:SetAutoFocus(false)
    qty:SetNumeric(true)
    qty:SetMaxLetters(3)
    qty:SetText("1")
    qty:SetScript("OnTextChanged", function() if window:IsShown() then DrawDetail() end end)
    qty:SetScript("OnEditFocusLost", function(self) self:SetText(tostring(Quantity())) end)
    qty:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    qty:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local less = Button(detail, "-", 21, function() qty:SetText(tostring(math.max(1, Quantity() - 1))) end)
    less:SetPoint("RIGHT", qty, "LEFT", -4, 0)
    local more = Button(detail, "+", 21, function() qty:SetText(tostring(math.min(999, Quantity() + 1))) end)
    more:SetPoint("LEFT", qty, "RIGHT", 4, 0)
    window.lessQuantity, window.moreQuantity = less, more
    if addon.GetSetting then
        window.addShopping = Button(detail, "Add to list", 82, function()
            local info, schematic = SelectedRecipe()
            if not info then return end
            addon.AddToShopping(info.recipeID, Quantity(), schematic or GetSchematic(info))
            SetMode("shopping")
        end)
        window.addShopping:SetPoint("BOTTOMRIGHT", -12, 142)
        window.removeShopping = Button(detail, "Remove recipe", 112, function()
            local info = SelectedRecipe()
            if info then addon.GetWork().shopping[info.recipeID] = nil end
            DrawDetail()
        end)
        window.removeShopping:SetPoint("BOTTOMLEFT", 12, 44)
        window.manageShopping = Button(detail, "Manage list", 94, ManageShopping)
        window.manageShopping:SetPoint("BOTTOMLEFT", 12, 9)
        window.buy = Button(detail, "Review purchases", 126, BuyMaterials)
        window.buy:SetPoint("BOTTOMRIGHT", -12, 44)
        window.queueNext = Button(detail, "Craft next", 110, CraftNext)
        window.queueNext:SetPoint("BOTTOMRIGHT", -12, 9)
        window.draft = Button(detail, "Draft request", 108, function()
            local info = SelectedRecipe()
            local _, crafter = C_TradeSkillUI.IsTradeSkillLinked()
            if not info or type(crafter) ~= "string" or crafter == "" or not crafter:match("^[^%s]+$") then return end
            local text = ("Could you craft %d × %s for me? Please let me know the materials and your fee."):format(Quantity(), info.name)
            ChatFrame_OpenChat("/w " .. crafter .. " " .. text)
        end)
        window.draft:SetPoint("BOTTOMRIGHT", -12, 9)
    end
end

local function BuildWindow()
    window = CreateFrame("Frame", "VendorProfitProfessionWindow", UIParent)
    window:Hide()
    window:SetSize(828, 620)
    window:SetFrameStrata("DIALOG")
    window:SetMovable(true)
    window:SetClampedToScreen(true)
    window:SetClampRectInsets(0, -34, 0, 0)
    local position = VendorProfitSettings and VendorProfitSettings.position
    if position then
        window:SetPoint(position.point, UIParent, position.relative, position.x, position.y)
    else
        window:SetPoint("CENTER")
    end
    local scale = math.min(1, (UIParent:GetWidth() - 62) / 828, (UIParent:GetHeight() - 22) / 620)
    window:SetScale(math.max(0.4, scale))
    window:EnableMouse(true)
    Surface(window, "BACKGROUND", colors.background)
    local title = Label(window, "GameFontNormalLarge", colors.accent)
    window.title = title
    title:SetPoint("TOPLEFT", 10, -11)
    local close = Button(window, "X", 25, function() HideUIPanel(ProfessionsFrame) end)
    close:SetPoint("TOPRIGHT", -8, -6)
    local shop = Button(window, "Shopping list", 98, function() SetMode("shopping") end)
    shop:SetPoint("RIGHT", close, "LEFT", -6, 0)
    window.shop = shop
    local link = Button(window, "Link", 44, LinkProfession)
    link:SetPoint("RIGHT", shop, "LEFT", -6, 0)
    local firstButton = link
    if addon.GetSetting then
        local tools = Button(window, "Tools", 58, OpenTools)
        tools:SetPoint("RIGHT", link, "LEFT", -6, 0)
        local settings = Button(window, "Settings", 70, addon.OpenSettings)
        settings:SetPoint("RIGHT", tools, "LEFT", -6, 0)
        firstButton = settings
    end
    local drag = CreateFrame("Frame", nil, window)
    drag:SetPoint("TOPLEFT")
    drag:SetPoint("TOPRIGHT", firstButton, "TOPLEFT", -6, 6)
    drag:SetHeight(34)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() if not InCombatLockdown() then window:StartMoving() end end)
    drag:SetScript("OnDragStop", function()
        window:StopMovingOrSizing()
        local point, _, relative, x, y = window:GetPoint()
        VendorProfitSettings.position = { point = point, relative = relative, x = x, y = y }
    end)
    window.skill = CreateFrame("StatusBar", nil, window)
    window.skill:SetPoint("TOPLEFT", 8, -39)
    window.skill:SetPoint("TOPRIGHT", -8, -39)
    window.skill:SetHeight(17)
    Surface(window.skill, "BACKGROUND", colors.group)
    window.skill:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    window.skill:SetStatusBarColor(unpack(colors.bar))
    window.skill.label = Label(window.skill, "GameFontHighlightSmall", colors.text)
    window.skill.label:SetPoint("CENTER")
    window.batchBand = CreateFrame("Frame", nil, window)
    window.batchBand:SetPoint("TOPLEFT", 8, -62)
    window.batchBand:SetPoint("TOPRIGHT", -8, -62)
    window.batchBand:SetHeight(34)
    Surface(window.batchBand, "BACKGROUND", colors.banner)
    window.batch = Label(window.batchBand, "GameFontHighlight", colors.accent)
    window.batch:SetPoint("LEFT", 8, 0)
    window:SetScript("OnUpdate", function(self, elapsed)
        if not craftingJob or not GetSetting("timer") then return end
        self.batchElapsed = (self.batchElapsed or 0) + elapsed
        if self.batchElapsed >= 0.25 then
            self.batchElapsed = 0
            self.batch:SetText(BatchText())
        end
    end)
    BuildList()
    BuildDetail()
    window:SetScript("OnSizeChanged", QueueRefresh)
    window:HookScript("OnHide", function()
        window:StopMovingOrSizing()
        addon.HideRoute(window.profitHover)
    end)
end

local function OnNativeShow()
    if not page then
        local crafting = ProfessionsFrame and ProfessionsFrame.CraftingPage
        if not crafting or not crafting.SchematicForm or not crafting.CreateButton then return end
        page = crafting
        native = ProfessionsFrame
        local function OnNativeHide()
            if window then window:Hide() end
            RestoreNative()
        end
        page:HookScript("OnShow", OnNativeShow)
        native:HookScript("OnShow", OnNativeShow)
        page:HookScript("OnHide", OnNativeHide)
        native:HookScript("OnHide", OnNativeHide)
        native:HookScript("OnSizeChanged", QueueRefresh)
        hooksecurefunc(page, "SelectRecipe", QueueRefresh)
    end
    if Active(IsLinkedProfession(), true) then
        -- Keep the native window transparent while the profession data loads, then fall back if it stalls.
        openingUntil = GetTime() + 1
        HideNative()
    end
    QueueRefresh()
end

Refresh = function()
    if not page then return end
    local isLinked = IsLinkedProfession()
    if linked ~= isLinked and window then
        window.preview = nil
        mode, offset = "recipes", 0
    end
    linked = isLinked
    local info = Active(linked) and C_TradeSkillUI.GetBaseProfessionInfo()
    if not info or not info.professionName then
        if window then window:Hide() end
        if openingUntil and GetTime() < openingUntil and Active(linked, true) then
            QueueRefresh()
        else
            RestoreNative()
        end
        return
    end
    openingUntil = nil
    if not window then BuildWindow() end
    if professionID ~= info.professionID then
        professionID = info.professionID
        window.preview = nil
        mode, filter, offset = "recipes", "all", 0
        collapsed = {}
        window.search:SetText("")
    end
    local child = C_TradeSkillUI.GetChildProfessionInfo and C_TradeSkillUI.GetChildProfessionInfo()
    rankInfo = child and (child.maxSkillLevel or 0) > 0 and child or info
    local skill, maximum = rankInfo.skillLevel or 0, rankInfo.maxSkillLevel or 0
    if (mode == "shopping" and not GetSetting("shopping"))
        or (mode == "queue" and not GetSetting("queue"))
        or (mode == "skill" and not GetSetting("skillChances")) then mode = "recipes" end
    if mode == "tools" then
        local tool = window.tool or ""
        if (tool:match("^alt:") and not GetSetting("altProfessions"))
            or (tool:match("^reagent:") and not GetSetting("reagentUses"))
            or ((tool == "deals" or tool == "disenchant") and not GetSetting("disenchant")) then
            mode = "recipes"
        end
    end
    window.shop:SetShown(GetSetting("shopping"))
    window.columnAH:SetShown(GetSetting("auctionProfit"))
    window.columnVendor:ClearAllPoints()
    window.columnVendor:SetPoint("RIGHT", GetSetting("auctionProfit") and -137 or -68, 0)
    window.columnVendor:SetShown(GetSetting("vendorProfit"))
    window.title:SetText(info.professionName)
    window.skill:SetMinMaxValues(0, math.max(1, maximum))
    window.skill:SetValue(skill)
    window.skill.label:SetText(("%s %d/%d"):format(info.professionName, skill, maximum))
    local batchText = BatchText()
    window.batchBand:SetShown(batchText ~= nil)
    window.batch:SetText(batchText or "")
    local bodyY = batchText and -105 or -67
    window.search:SetPoint("TOPLEFT", 8, bodyY)
    window.detail:SetPoint("TOPLEFT", listWidth + 16, bodyY)
    ReadRecipes()
    ListEntries()
    DrawDetail()
    if not linked and GetSetting("altProfessions") and addon.RememberProfession then
        addon.RememberProfession(professionID, info.professionName, skill, maximum, records)
    end
    window:Show()
    DockNativeTabs()
    HideNative()
    if not InCombatLockdown() then DisableNativeMouse(native) end
end

addon.RefreshWindow = QueueRefresh

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, arg1, _, spellID)
    if event == "ADDON_LOADED" then
        if arg1 == "Blizzard_Professions" then OnNativeShow(); return end
        if arg1 ~= addonName then return end
        VendorProfitSettings = VendorProfitSettings or {}
        for _, name in ipairs({
            "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "TRADE_SKILL_LIST_UPDATE",
            "TRADE_SKILL_DATA_SOURCE_CHANGED", "NEW_RECIPE_LEARNED", "TRADE_SKILL_FAVORITES_CHANGED",
            "BAG_UPDATE_DELAYED", "PLAYERBANKSLOTS_CHANGED", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED",
            "GET_ITEM_INFO_RECEIVED", "UPDATE_TRADESKILL_CAST_STOPPED", "MERCHANT_SHOW", "MERCHANT_CLOSED",
            "PLAYER_REGEN_ENABLED", "TRADE_SKILL_NAME_UPDATE", "SKILL_LINES_CHANGED",
        }) do
            pcall(self.RegisterEvent, self, name)
        end
        local api = Auctionator.API.v1
        if api.RegisterForDBUpdate then api.RegisterForDBUpdate(addonName, QueueRefresh) end
        if self.RegisterUnitEvent then
            self:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
            self:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
            self:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
            self:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
        end
        OnNativeShow()
    elseif event == "UNIT_SPELLCAST_START" then
        if not craftingJob or craftingJob.id ~= spellID then return end
        local _, _, _, started, ends = UnitCastingInfo("player")
        if started and ends then
            craftingJob.duration = (ends - started) / 1000
            craftingJob.ends = ends / 1000
        end
        QueueRefresh()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if not craftingJob or craftingJob.id ~= spellID then return end
        craftingJob.done = craftingJob.done + 1
        if craftingJob.duration then craftingJob.ends = GetTime() + craftingJob.duration end
        local shopping = addon.GetWork().shopping
        local job = shopping[spellID]
        if job then
            job.quantity = job.quantity - 1
            if job.quantity <= 0 then shopping[spellID] = nil end
        end
        if craftingJob.done >= craftingJob.count then craftingJob = nil end
        QueueRefresh()
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" then
        if craftingJob and craftingJob.id == spellID then craftingJob = nil; QueueRefresh() end
    elseif event == "UPDATE_TRADESKILL_CAST_STOPPED" then
        local job = craftingJob
        C_Timer.After(0.2, function()
            if craftingJob == job then craftingJob = nil end
            QueueRefresh()
        end)
    elseif event == "TRADE_SKILL_SHOW" then
        OnNativeShow()
    elseif event == "TRADE_SKILL_CLOSE" or event == "PLAYER_REGEN_ENABLED"
        or (page and page:IsVisible()) then
        QueueRefresh()
    end
end)

SLASH_VENDORPROFITWINDOW1 = "/vendorprofit"
SlashCmdList.VENDORPROFITWINDOW = function()
    VendorProfitSettings = VendorProfitSettings or {}
    if addon.SetSetting then
        addon.SetSetting("window", not GetSetting("window"))
    else
        VendorProfitSettings.native = not VendorProfitSettings.native
    end
    print(VendorProfitSettings.native and "Vendor Profit: standard profession window." or "Vendor Profit: custom profession window.")
    QueueRefresh()
end
