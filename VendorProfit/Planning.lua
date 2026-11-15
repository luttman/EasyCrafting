local addonName, addon = ...
local basic = Enum.CraftingReagentType.Basic

function addon.Money(value)
    return GetMoneyString(math.floor(math.abs(value)), true)
end

function addon.ItemName(id)
    return C_Item.GetItemNameByID(id) or ("Item #" .. id)
end

function addon.SpellName(id)
    return C_Spell.GetSpellName(id) or ("Recipe #" .. id)
end

function addon.DirectReagents(schematic, batches)
    local amounts = {}
    for _, slot in ipairs(schematic and schematic.reagentSlotSchematics or {}) do
        local reagent = slot.reagents[1]
        if slot.reagentType == basic and reagent and reagent.itemID then
            local id = reagent.itemID
            amounts[id] = (amounts[id] or 0) + slot.quantityRequired * batches
        end
    end
    return amounts
end

function addon.OfflineSchematic(id)
    local data = addon.RecipeData[id]
    if not data then return end
    local slots = {}
    for index = 1, #data.reagents, 2 do
        slots[#slots + 1] = {
            reagentType = basic, quantityRequired = data.reagents[index + 1],
            reagents = { { itemID = data.reagents[index] } },
        }
    end
    return {
        recipeID = id, outputItemID = data.item > 0 and data.item or nil,
        quantityMin = math.floor(data.yield), reagentSlotSchematics = slots, sale = data.sale,
    }
end

function addon.SkillRange(id, liveGray)
    local data = addon.RecipeData[id]
    if not data then return end
    local gray = liveGray and liveGray > 0 and liveGray or data.gray
    local yellow = math.min(data.yellow, gray)
    return math.min(data.first or yellow, yellow), yellow, math.floor((yellow + gray) / 2), gray
end

function addon.SkillChance(id, skill, liveGray)
    local _, yellow, _, gray = addon.SkillRange(id, liveGray)
    if not gray then return end
    if skill >= gray then return 0 end
    if skill < yellow then return 1 end
    return (gray - skill) / (gray - yellow)
end

function addon.CraftCounts(schematic, bagCount)
    local fixed, alternatives = {}, {}
    for _, slot in ipairs(schematic and schematic.reagentSlotSchematics or {}) do
        if slot.reagentType == basic and slot.quantityRequired > 0 then
            local reagent = slot.reagents[1]
            if #slot.reagents == 1 and reagent.itemID then
                fixed[reagent.itemID] = (fixed[reagent.itemID] or 0) + slot.quantityRequired
            else
                alternatives[#alternatives + 1] = slot
            end
        end
    end
    local fromBags, withMerchant = math.huge, math.huge
    for id, quantity in pairs(fixed) do
        local available = math.floor(bagCount(id) / quantity)
        fromBags = math.min(fromBags, available)
        if not addon.MerchantPrice(id) then withMerchant = math.min(withMerchant, available) end
    end
    for _, slot in ipairs(alternatives) do
        local stock, merchant = 0, false
        for _, reagent in ipairs(slot.reagents) do
            if reagent.itemID then
                stock = stock + bagCount(reagent.itemID)
                merchant = merchant or addon.MerchantPrice(reagent.itemID) ~= nil
            end
        end
        local available = math.floor(stock / slot.quantityRequired)
        fromBags = math.min(fromBags, available)
        if not merchant then withMerchant = math.min(withMerchant, available) end
    end
    return fromBags < math.huge and fromBags or 0, withMerchant < math.huge and withMerchant or nil
end

function addon.AuctionRevenue(schematic)
    local id = schematic and schematic.outputItemID
    local quantity = schematic and schematic.quantityMin
    if not id or not quantity or quantity <= 0 then return end
    local price = Auctionator.API.v1.GetAuctionPriceByItemID(addonName, id)
    if price and price > 0 then return math.floor(price * quantity * 0.95), price * quantity end
end

-- The highest unit price each reagent can have before one craft stops breaking even, with
-- the other reagents at today's prices. `amounts` is per craft; materials in `owned` cost nothing.
-- ponytail: prices every reagent as bought, not as crafted from cheaper parts.
function addon.BreakEvenPrices(amounts, owned, revenue)
    local costs, total, limits = {}, 0, {}
    if not revenue then return limits end
    for id, amount in pairs(amounts) do
        local price = owned and owned[id] and 0 or addon.PurchasePrice(id)
        if not price then return limits end
        costs[id] = price * amount
        total = total + costs[id]
    end
    for id, amount in pairs(amounts) do
        limits[id] = (revenue - (total - costs[id])) / amount
    end
    return limits
end

function addon.GetWork()
    VendorProfitWork = VendorProfitWork or {}
    VendorProfitWork.shopping = VendorProfitWork.shopping or {}
    VendorProfitWork.owned = VendorProfitWork.owned or {}
    VendorProfitWork.crafted = VendorProfitWork.crafted or {}
    return VendorProfitWork
end

function addon.AddToShopping(id, quantity, schematic)
    local shopping = addon.GetWork().shopping
    if not shopping[id] then
        local inputs = addon.DirectReagents(schematic, 1)
        if not next(inputs) then return end
        local last = 0
        for _, job in pairs(shopping) do last = math.max(last, job.order or 0) end
        shopping[id] = { quantity = 0, reagents = inputs, order = last + 1 }
    end
    shopping[id].quantity = math.min(999, shopping[id].quantity + quantity)
end

-- Saved crafts in queue order. Crafts saved before the order existed sort first, by recipe.
local function JobIDs(shopping)
    local ids = {}
    for id in pairs(shopping) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b)
        local first, second = shopping[a].order or 0, shopping[b].order or 0
        if first ~= second then return first < second end
        return a < b
    end)
    return ids
end

-- Moves a saved craft one place up (-1) or down (1) in the queue.
function addon.MoveJob(id, direction)
    local shopping = addon.GetWork().shopping
    local ids = JobIDs(shopping)
    for index, job in ipairs(ids) do
        local other = ids[index + direction]
        if job == id and other then
            ids[index], ids[index + direction] = other, job
            break
        end
    end
    for index, job in ipairs(ids) do shopping[job].order = index end
end

function addon.ShoppingPlan(bagCount)
    local demand, jobs = {}, {}
    local shopping = addon.GetWork().shopping
    for _, id in ipairs(JobIDs(shopping)) do
        local job = shopping[id]
        jobs[#jobs + 1] = { id = id, quantity = job.quantity }
        for item, perCraft in pairs(job.reagents) do
            demand[item] = (demand[item] or 0) + perCraft * job.quantity
        end
    end
    local needs, prerequisites = addon.PlanShopping(demand, bagCount)
    return needs, prerequisites, jobs
end

function addon.SearchMaterials(materials)
    if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then return end
    local terms = {}
    for id, quantity in pairs(materials) do
        local name = C_Item.GetItemNameByID(id)
        if name then
            terms[#terms + 1] = { searchString = name, isExact = true,
                quantity = type(quantity) == "number" and quantity or nil }
        end
    end
    if #terms == 0 then return end
    table.sort(terms, function(a, b) return a.searchString < b.searchString end)
    Auctionator.API.v1.MultiSearchAdvanced(addonName, terms)
end

local function MerchantOffer(index)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local item = C_MerchantFrame.GetItemInfo(index)
        if item then
            return item.price, item.stackCount, item.numAvailable, item.isPurchasable ~= false, item.hasExtendedCost
        end
    else
        local _, _, price, pack, stock, purchasable, _, extended = GetMerchantItemInfo(index)
        return price, pack, stock, purchasable, extended
    end
end

-- The stacks in your bags of items you crafted, with what a merchant pays for each.
function addon.CraftedStacks()
    local stacks, crafted = {}, addon.GetWork().crafted
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local item = C_Container.GetContainerItemInfo(bag, slot)
            if item and crafted[item.itemID] and not item.isLocked and not item.hasNoValue then
                local price = select(11, C_Item.GetItemInfo(item.itemID)) or 0
                if price > 0 then
                    stacks[#stacks + 1] = { bag = bag, slot = slot, id = item.itemID,
                        count = item.stackCount or 1, value = price * (item.stackCount or 1) }
                end
            end
        end
    end
    return stacks
end

function addon.MerchantItemID(index)
    local link = GetMerchantItemLink(index)
    return (GetMerchantItemID and GetMerchantItemID(index)) or (link and C_Item.GetItemInfoInstant(link))
end

-- Purchases wait in one queue and go out one at a time.
-- ponytail: a fixed half second between purchases, the pace Multi Buyer uses to stay under the server throttle.
local purchases, ticker = {}, nil

function addon.StopBuying()
    purchases = {}
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
end

local function BuyNext()
    local step = table.remove(purchases, 1)
    -- Stop if the merchant closed or its list changed since the player confirmed.
    if step and MerchantFrame:IsShown() and addon.MerchantItemID(step.index) == step.id then
        BuyMerchantItem(step.index, step.count)
    else
        purchases = {}
    end
    if #purchases == 0 and ticker then
        ticker:Cancel()
        ticker = nil
    end
end

-- Buys `quantity` of a merchant item, at most `perCall` in each purchase.
function addon.BuyPaced(index, id, quantity, perCall)
    local idle = #purchases == 0
    while quantity > 0 do
        local count = math.min(quantity, perCall)
        purchases[#purchases + 1] = { index = index, id = id, count = count }
        quantity = quantity - count
    end
    if not idle then return end
    BuyNext()
    if #purchases > 0 then
        if ticker then ticker:Cancel() end
        ticker = C_Timer.NewTicker(0.5, BuyNext)
    end
end

-- What this merchant sells from `needs`. One purchase holds at most a stack, so an offer covers
-- one stack unless `all` asks for the full amount, which is then bought in several purchases.
function addon.MerchantOffers(needs, all)
    local offers = {}
    if not (MerchantFrame and MerchantFrame:IsShown()) then return offers end
    for index = 1, GetMerchantNumItems() do
        local id = addon.MerchantItemID(index)
        if id and needs[id] then
            local price, pack, stock, purchasable, extended = MerchantOffer(index)
            if purchasable and not extended and price and price > 0 and pack and pack > 0 then
                local quantity = math.ceil(needs[id] / pack) * pack
                local max = GetMerchantItemMaxStack(index)
                local perCall = max and max > 0 and math.max(pack, math.floor(max / pack) * pack) or pack
                if not all then quantity = math.min(quantity, perCall) end
                if stock and stock >= 0 then quantity = math.min(quantity, math.floor(stock / pack) * pack) end
                if quantity > 0 then
                    offers[#offers + 1] = { id = id, index = index, quantity = quantity, perCall = perCall,
                        total = price * quantity / pack }
                end
            end
        end
    end
    return offers
end
