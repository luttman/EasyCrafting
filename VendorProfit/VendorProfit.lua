local addonName, addon = ...
addon = addon or {}
local recipes, recipesByItem = {}, {}
local hookedFrame, routeHover, waitingForItem
local scanPending = false

local function MerchantPrice(itemID)
    return Auctionator.API.v1.GetVendorPriceByItemID(addonName, itemID)
        or (addon.VendorPrices and addon.VendorPrices[itemID])
end

-- A reagent that merchants sell is always bought from a merchant, never on the Auction House.
local function PurchasePrice(itemID)
    local vendor = MerchantPrice(itemID)
    if vendor then return vendor, "merchant" end
    return Auctionator.API.v1.GetAuctionPriceByItemID(addonName, itemID), "AH"
end

local QuoteItem

local function QuoteReagents(slots, batches, visiting, transaction, excluded)
    local total, steps = 0, {}
    local quantities, itemIDs = {}, {}
    local function Require(itemID, quantity)
        if excluded and excluded[itemID] then return end
        if not quantities[itemID] then itemIDs[#itemIDs + 1] = itemID end
        quantities[itemID] = (quantities[itemID] or 0) + quantity
    end
    local function AddQuote(quote)
        total = total + quote.cost
        for _, step in ipairs(quote.steps) do
            steps[#steps + 1] = step
        end
    end

    for slotIndex, slot in ipairs(slots) do
        local allocations = transaction and transaction:GetAllocations(slotIndex)
        local allocated = 0
        if allocations then
            for _, reagent in ipairs(slot.reagents) do
                local allocation = allocations:FindAllocationByReagent(reagent)
                local quantity = allocation and allocation:GetQuantity() or 0
                if quantity > 0 then
                    if not reagent.itemID then return nil end
                    Require(reagent.itemID, quantity * batches)
                    allocated = allocated + quantity
                end
            end
            if allocated ~= allocations:Accumulate() then return nil end
        end

        if slot.reagentType == Enum.CraftingReagentType.Basic then
            local remaining = (slot.quantityRequired - allocated) * batches
            if remaining > 0 then
                if #slot.reagents == 1 and slot.reagents[1].itemID then
                    Require(slot.reagents[1].itemID, remaining)
                else
                    local best
                    for _, reagent in ipairs(slot.reagents) do
                        local quote
                        if excluded and excluded[reagent.itemID] then
                            quote = { cost = 0, steps = {} }
                        else
                            quote = QuoteItem(reagent.itemID, remaining, visiting)
                        end
                        if quote and (not best or quote.cost < best.cost) then best = quote end
                    end
                    if not best then return nil end
                    AddQuote(best)
                end
            end
        end
    end

    for _, itemID in ipairs(itemIDs) do
        local quote = QuoteItem(itemID, quantities[itemID], visiting)
        if not quote then return nil end
        AddQuote(quote)
    end
    return { cost = total, steps = steps }
end

QuoteItem = function(itemID, quantity, visiting)
    if not itemID or visiting[itemID] then return nil end

    local price, source = PurchasePrice(itemID)
    local function Purchase(count)
        return { itemID = itemID, quantity = count, source = source, cost = price * count }
    end
    local best = price and { cost = price * quantity, steps = { Purchase(quantity) } }
    local recipesForItem = recipesByItem[itemID]
    if not recipesForItem then return best end

    visiting[itemID] = true
    for _, recipe in ipairs(recipesForItem) do
        -- Compare making the full amount with making complete batches and buying the remainder.
        local fullBatches = math.ceil(quantity / recipe.yield)
        local firstBatchCount = fullBatches
        if price and fullBatches > 1 and quantity % recipe.yield ~= 0 then
            firstBatchCount = fullBatches - 1
        end
        for batches = firstBatchCount, fullBatches do
            local materials = QuoteReagents(recipe.slots, batches, visiting)
            if materials then
                local output = batches * recipe.yield
                local remainder = math.max(0, quantity - output)
                local cost = materials.cost + remainder * (price or 0)
                if not best or cost < best.cost then
                    local steps = { {
                        itemID = itemID, quantity = output, needed = math.min(output, quantity), cost = materials.cost,
                        batches = batches, recipeID = recipe.id, recipeName = recipe.name, materials = materials.steps,
                    } }
                    if remainder > 0 then steps[#steps + 1] = Purchase(remainder) end
                    best = { cost = cost, steps = steps }
                end
            end
        end
    end
    visiting[itemID] = nil
    return best
end

local function FormatProfit(profit)
    local copper = math.floor(profit)
    if copper < 0 then
        return RED_FONT_COLOR:WrapTextInColorCode("-" .. GetMoneyString(-copper, true))
    end
    local color = copper > 0 and GREEN_FONT_COLOR or WHITE_FONT_COLOR
    return color:WrapTextInColorCode(GetMoneyString(copper, true))
end

local function QuoteVendor(schematic, transaction, batches, excluded)
    local itemID = schematic and schematic.outputItemID
    local yield = schematic and schematic.quantityMin
    if not schematic or not schematic.reagentSlotSchematics then return end
    local visiting = itemID and { [itemID] = true } or {}
    local quote = QuoteReagents(schematic.reagentSlotSchematics, batches or 1, visiting, transaction, excluded)
    if not itemID or itemID <= 0 or not yield or yield <= 0 then return quote end
    local salePrice = select(11, C_Item.GetItemInfo(itemID))
    if salePrice == nil and schematic.sale and schematic.sale > 0 then salePrice = schematic.sale end
    return quote, salePrice and salePrice * yield * (batches or 1)
end

local function VendorStatus(quote, revenue)
    if revenue == nil then return "Waiting for item data" end
    if revenue == 0 then return "No vendor value" end
    if not quote then return "Missing reagent price" end
end

local function AddRouteSteps(steps, depth)
    for _, step in ipairs(steps) do
        local name = C_Item.GetItemInfo(step.itemID) or ("Item #" .. step.itemID)
        local items = ("%d x %s"):format(step.quantity, name)
        local text
        if step.materials then
            text = step.recipeName and ("%s x %d (makes %s)"):format(step.recipeName, step.batches, items)
                or ("Craft %s"):format(items)
        else
            text = ("Buy %s (%s)"):format(items, step.source)
        end
        GameTooltip:AddDoubleLine(string.rep("  ", depth) .. text, GetMoneyString(math.floor(step.cost), true))
        if step.materials then AddRouteSteps(step.materials, depth + 1) end
    end
end

local function ShowRoute(hover)
    GameTooltip:SetOwner(hover, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    if hover.quote then
        GameTooltip:AddLine("Cheapest material route", 1, 0.82, 0)
        AddRouteSteps(hover.quote.steps, 0)
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Material cost", GetMoneyString(math.floor(hover.quote.cost), true))
        if hover.revenue then
            GameTooltip:AddDoubleLine("Vendor revenue", GetMoneyString(hover.revenue, true))
        end
    else
        GameTooltip:AddLine(hover.status or "Missing reagent price", 1, 0.82, 0)
    end
    GameTooltip:AddLine("Uses Auctionator prices and your learned recipes.", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end

local function HideRoute(hover)
    if GameTooltip:IsOwned(hover) then GameTooltip:Hide() end
end

local function IsOwnProfession(allowLoading)
    if not allowLoading and C_TradeSkillUI.IsDataSourceChanging and C_TradeSkillUI.IsDataSourceChanging() then
        return false
    end
    for _, method in ipairs({ "IsTradeSkillLinked", "IsTradeSkillGuild", "IsTradeSkillGuildMember", "IsNPCCrafting" }) do
        local check = C_TradeSkillUI[method]
        if check and check() then return false end
    end
    return true
end

local function RecipeIDs()
    local getRecipeIDs = C_TradeSkillUI.GetAllRecipeIDs or C_TradeSkillUI.GetFilteredRecipeIDs
    local ids = getRecipeIDs and getRecipeIDs()
    if (not ids or #ids == 0) and C_TradeSkillUI.GetFilteredRecipeIDs then
        ids = C_TradeSkillUI.GetFilteredRecipeIDs()
    end
    return ids or {}
end

function addon.ShoppingNeeds(quote, bagCount)
    local needed, available, crafts = {}, {}, {}
    local function Collect(steps)
        for _, step in ipairs(steps) do
            local id = step.itemID
            local quantity = step.needed or step.quantity
            local stock = available[id] or bagCount(id)
            local owned = math.min(quantity, stock)
            available[id] = stock - owned
            local remaining = quantity - owned
            if remaining > 0 then
                if step.materials and owned > 0 then
                    local adjusted = QuoteItem(id, remaining, {})
                    Collect(adjusted and adjusted.steps or step.materials)
                elseif step.materials then
                    Collect(step.materials)
                    available[id] = available[id] + step.quantity - remaining
                    if step.recipeID then crafts[#crafts + 1] = step end
                else
                    needed[id] = (needed[id] or 0) + remaining
                end
            end
        end
    end
    Collect(quote.steps)
    return needed, crafts
end

function addon.PlanShopping(demand, bagCount)
    local steps, ids = {}, {}
    for id in pairs(demand) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local count = demand[id]
        local quote = QuoteItem(id, count, {})
        for _, step in ipairs(quote and quote.steps or { { itemID = id, quantity = count } }) do
            steps[#steps + 1] = step
        end
    end
    return addon.ShoppingNeeds({ steps = steps }, bagCount)
end

function addon.PriceCandidates(schematic)
    local items = {}
    local function Collect(slots)
        for _, slot in ipairs(slots) do
            if slot.reagentType == Enum.CraftingReagentType.Basic then
                for _, reagent in ipairs(slot.reagents) do
                    local id = reagent.itemID
                    if id and not items[id] then
                        items[id] = true
                        for _, recipe in ipairs(recipesByItem[id] or {}) do Collect(recipe.slots) end
                    end
                end
            end
        end
    end
    if schematic and schematic.reagentSlotSchematics then Collect(schematic.reagentSlotSchematics) end
    return items
end

addon.RecipeIDs = RecipeIDs
addon.IsOwnProfession = IsOwnProfession
addon.QuoteVendor = QuoteVendor
addon.PurchasePrice = PurchasePrice
addon.MerchantPrice = MerchantPrice
addon.ShowRoute = ShowRoute
addon.HideRoute = HideRoute

local function RebuildItemIndex()
    recipesByItem = {}
    for id, recipe in pairs(recipes) do
        recipe.id = id
        local list = recipesByItem[recipe.itemID] or {}
        list[#list + 1] = recipe
        recipesByItem[recipe.itemID] = list
    end
end

local function ScanRecipes()
    if not ProfessionsFrame or not ProfessionsFrame:IsVisible() or not IsOwnProfession() then return end

    for _, id in ipairs(RecipeIDs()) do
        local info = C_TradeSkillUI.GetRecipeInfo(id)
        if info and info.learned and not info.isDummyRecipe then
            local schematic = C_TradeSkillUI.GetRecipeSchematic(id, false)
            if schematic and schematic.outputItemID and schematic.quantityMin and schematic.quantityMin > 0 then
                local slots = {}
                for _, slot in ipairs(schematic.reagentSlotSchematics) do
                    if slot.reagentType == Enum.CraftingReagentType.Basic then
                        local basic = { reagentType = slot.reagentType, quantityRequired = slot.quantityRequired, reagents = {} }
                        for _, reagent in ipairs(slot.reagents) do
                            basic.reagents[#basic.reagents + 1] = { itemID = reagent.itemID }
                        end
                        slots[#slots + 1] = basic
                    end
                end
                if #slots > 0 then
                    recipes[id] = {
                        name = info.name,
                        itemID = schematic.outputItemID,
                        yield = schematic.quantityMin,
                        variableYield = schematic.quantityMax and schematic.quantityMax > schematic.quantityMin,
                        slots = slots,
                    }
                end
            end
        elseif info then
            recipes[id] = nil
        end
    end
    RebuildItemIndex()
    if hookedFrame and hookedFrame:IsVisible() then hookedFrame:UpdateTotal() end
    if addon.RefreshWindow then addon.RefreshWindow() end
end

local function QueueScan()
    if scanPending then return end
    scanPending = true
    C_Timer.After(0.2, function()
        scanPending = false
        ScanRecipes()
    end)
end

local function AddVendorProfit(frame)
    waitingForItem = nil
    routeHover.quote, routeHover.revenue = nil, nil
    if addon.GetSetting and not addon.GetSetting("vendorProfit") then
        routeHover:Hide()
        return
    end
    local form = frame:GetParent()
    local info = form:GetRecipeInfo()
    if not info or info.isEnchantingRecipe then
        routeHover:Hide()
        return
    end

    local schematic = form.recipeSchematic
    if not schematic or schematic.recipeID ~= info.recipeID then
        schematic = C_TradeSkillUI.GetRecipeSchematic(info.recipeID, false, form:GetCurrentRecipeLevel())
    end
    if not schematic or not schematic.outputItemID or not schematic.quantityMin or schematic.quantityMin <= 0 then
        routeHover:Hide()
        return
    end

    local quote, revenue = QuoteVendor(schematic, form:GetTransaction())
    local label = "Profit to vendor"
    local status = VendorStatus(quote, revenue)
    if revenue == nil then
        waitingForItem = schematic.outputItemID
    end
    if not status and schematic.quantityMax and schematic.quantityMax > schematic.quantityMin then
        label = label .. " (min. yield)"
    end

    local value = status or FormatProfit(revenue - quote.cost)
    local vendorLine = label .. ": " .. value
    local currentText = frame.Total:GetText() or ""
    local profitLabel = AUCTIONATOR_L_PROFIT_COLON
    local lines = {}
    local vendorLineIndex
    for line in currentText:gmatch("[^\n]+") do
        lines[#lines + 1] = line
        if profitLabel and not vendorLineIndex and line:sub(1, #profitLabel) == profitLabel then
            lines[#lines + 1] = vendorLine
            vendorLineIndex = #lines
        end
    end
    if not vendorLineIndex then
        lines[#lines + 1] = vendorLine
        vendorLineIndex = #lines
    end
    frame.Total:SetText(table.concat(lines, "\n"))
    frame:SetHeight(16 * #lines)

    routeHover.quote, routeHover.revenue, routeHover.status = quote, revenue, status
    local spacing = frame.Total:GetSpacing()
    local lineHeight = (frame.Total:GetStringHeight() + spacing) / #lines
    routeHover:ClearAllPoints()
    routeHover:SetPoint("TOPLEFT", frame.Total, "TOPLEFT", 0, -(vendorLineIndex - 1) * lineHeight)
    local width = frame.Total:GetUnboundedStringWidthForText(vendorLine)
    routeHover:SetSize(math.max(1, width), math.max(1, lineHeight))
    routeHover:Show()
    if GameTooltip:IsOwned(routeHover) then ShowRoute(routeHover) end
end

local function AttachToAuctionator()
    local frame = AuctionatorCraftingInfoProfessionsFrame
    if not frame or frame == hookedFrame then return end
    hookedFrame = frame
    if routeHover then routeHover:Hide() end
    routeHover = CreateFrame("Frame", nil, frame)
    routeHover:Hide()
    routeHover:EnableMouse(true)
    routeHover:SetScript("OnEnter", ShowRoute)
    routeHover:SetScript("OnLeave", HideRoute)
    routeHover:SetScript("OnHide", HideRoute)
    hooksecurefunc(frame, "UpdateTotal", AddVendorProfit)
    if frame:IsVisible() then frame:UpdateTotal() end
end

local function AddItemTooltip(tooltip, data)
    if tooltip:IsForbidden() then return end
    if addon.GetSetting and not addon.GetSetting("itemTooltip") then return end
    local itemID = data and data.id
    if issecretvalue and issecretvalue(itemID) then return end
    local sources = itemID and recipesByItem[itemID]
    if not sources then return end

    local salePrice = select(11, C_Item.GetItemInfo(itemID))
    if not salePrice or salePrice <= 0 then return end
    local bestCost, variableYield
    for _, recipe in ipairs(sources) do
        local quote = QuoteReagents(recipe.slots, 1, { [itemID] = true })
        if quote then
            local unitCost = quote.cost / recipe.yield
            if not bestCost or unitCost < bestCost then
                bestCost, variableYield = unitCost, recipe.variableYield
            end
        end
    end
    local label = variableYield and "Profit to vendor (each, min. yield)" or "Profit to vendor (each)"
    local value = bestCost and FormatProfit(salePrice - bestCost) or "Missing reagent price"
    tooltip:AddDoubleLine(label, value, 1, 0.82, 0, 1, 1, 1)
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, id, success)
    if event == "ADDON_LOADED" and id == addonName then
        VendorProfitRecipes = VendorProfitRecipes or {}
        recipes = VendorProfitRecipes
        RebuildItemIndex()

        hooksecurefunc(Auctionator.CraftingInfo, "InitializeProfessionsFrame", AttachToAuctionator)
        AttachToAuctionator()
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, AddItemTooltip)

        self:UnregisterEvent("ADDON_LOADED")
        self:RegisterEvent("TRADE_SKILL_SHOW")
        self:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
        self:RegisterEvent("TRADE_SKILL_DATA_SOURCE_CHANGED")
        self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if success and waitingForItem == id and hookedFrame and hookedFrame:IsVisible() then
            hookedFrame:UpdateTotal()
        end
    else
        QueueScan()
    end
end)
