-- Shift-click a merchant item to buy many at once. The idea comes from Multi Buyer and BuyEmAll.
local _, addon = ...
local dialog, confirm, offer, hooked

local MerchantItemID = addon.MerchantItemID

-- ponytail: only stackable items that cost plain money. Everything else keeps Blizzard's own
-- shift-click. Free space counts empty slots in normal bags, not partial stacks or profession bags.
local function ReadOffer(index)
    local info = C_MerchantFrame.GetItemInfo(index)
    local id = MerchantItemID(index)
    if not info or not id or info.hasExtendedCost or info.isPurchasable == false then return end
    local pack, price = info.stackCount or 1, info.price or 0
    local name, _, _, _, _, _, _, stack = C_Item.GetItemInfo(id)
    if price <= 0 or pack <= 0 or not stack or stack <= 1 then return end
    local free = 0
    for bag = 0, NUM_BAG_SLOTS or 4 do
        local slots, family = C_Container.GetContainerNumFreeSlots(bag)
        if family == 0 then free = free + (slots or 0) end
    end
    local limit = math.min(math.floor(GetMoney() / price) * pack, free * stack)
    if info.numAvailable and info.numAvailable >= 0 then limit = math.min(limit, info.numAvailable) end
    limit = math.floor(limit / pack) * pack
    if limit <= 0 then return end
    return { index = index, id = id, name = name or info.name, pack = pack, price = price, stack = stack, limit = limit }
end

local function Stop()
    addon.StopBuying()
    if dialog then dialog:Hide() end
    if confirm then confirm:Hide() end
end

-- The amount is always a whole number of the merchant's packs, between one pack and the limit.
local function Amount(value)
    value = math.floor((tonumber(value or dialog.amount:GetText()) or 0) / offer.pack) * offer.pack
    return math.max(offer.pack, math.min(offer.limit, value))
end

local function SetAmount(value)
    dialog.amount:SetText(tostring(Amount(value)))
    -- Select the number so that typing replaces it.
    dialog.amount:HighlightText()
end

local function Purchase(job, amount)
    local perCall = math.min(job.stack, GetMerchantItemMaxStack(job.index) or job.stack)
    addon.BuyPaced(job.index, job.id, amount, math.max(job.pack, math.floor(perCall / job.pack) * job.pack))
end

-- Buy asks once more before it spends money, naming the item, the amount, and the cost.
local function Buy()
    local job, amount = offer, Amount()
    Stop()
    if not confirm then
        local skin = addon.Skin
        confirm = skin.Window("EasyCraftingBulkConfirm", 340, 132, "Confirm purchase")
        confirm.question = skin.Label(confirm, "GameFontHighlight", skin.colors.text)
        confirm.question:SetPoint("TOPLEFT", 14, -46)
        confirm.question:SetPoint("RIGHT", -14, 0)
        confirm.question:SetJustifyH("LEFT")
        confirm.question:SetSpacing(4)
        local yes = skin.Button(confirm, "Buy now", 100, function()
            confirm:Hide()
            Purchase(confirm.job, confirm.amount)
        end)
        yes:SetPoint("BOTTOMRIGHT", -14, 12)
        local no = skin.Button(confirm, "Cancel", 90, function() confirm:Hide() end)
        no:SetPoint("RIGHT", yes, "LEFT", -6, 0)
    end
    confirm.job, confirm.amount = job, amount
    confirm.question:SetText(("Do you want to buy %d x %s for %s?"):format(
        amount, job.name, addon.Money(amount / job.pack * job.price)))
    confirm:Show()
    confirm:Raise()
end

local function Build()
    local skin = addon.Skin
    dialog = skin.Window("EasyCraftingBulkBuy", 270, 168, "Buy in bulk")
    dialog.item = skin.Label(dialog, "GameFontHighlight", skin.colors.text)
    dialog.item:SetPoint("TOPLEFT", 14, -44)
    dialog.item:SetPoint("RIGHT", -14, 0)
    dialog.item:SetJustifyH("LEFT")
    dialog.item:SetWordWrap(false)

    local amount = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
    dialog.amount = amount
    amount:SetSize(48, 22)
    amount:SetPoint("TOPLEFT", 48, -70)
    amount:SetAutoFocus(true)
    amount:SetNumeric(true)
    amount:SetMaxLetters(5)
    amount:SetScript("OnTextChanged", function()
        dialog.cost:SetText("Cost  " .. addon.Money(Amount() / offer.pack * offer.price))
    end)
    amount:SetScript("OnEnterPressed", Buy)
    amount:SetScript("OnEscapePressed", Stop)
    local less = skin.Button(dialog, "-", 22, function() SetAmount(Amount() - offer.pack) end)
    less:SetPoint("RIGHT", amount, "LEFT", -8, 0)
    local more = skin.Button(dialog, "+", 22, function() SetAmount(Amount() + offer.pack) end)
    more:SetPoint("LEFT", amount, "RIGHT", 4, 0)
    local stack = skin.Button(dialog, "Stack", 56, function()
        SetAmount((math.floor(Amount() / offer.stack) + 1) * offer.stack)
    end)
    stack:SetPoint("LEFT", more, "RIGHT", 10, 0)
    local most = skin.Button(dialog, "Max", 48, function() SetAmount(offer.limit) end)
    most:SetPoint("LEFT", stack, "RIGHT", 4, 0)

    dialog.cost = skin.Label(dialog, "GameFontHighlight", skin.colors.gold)
    dialog.cost:SetPoint("TOPLEFT", 14, -104)
    local buy = skin.Button(dialog, "Buy", 90, Buy)
    buy:SetPoint("BOTTOMRIGHT", -14, 12)
    local cancel = skin.Button(dialog, "Cancel", 90, Stop)
    cancel:SetPoint("RIGHT", buy, "LEFT", -6, 0)
end

local function OnModifiedClick(button)
    if not addon.GetSetting("bulkBuy") or MerchantFrame.selectedTab ~= 1 or not IsShiftKeyDown() then return end
    if ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow() then return end
    local found = ReadOffer(button:GetID())
    if not found then return end
    if StackSplitFrame then StackSplitFrame:Hide() end
    offer = found
    if not dialog then Build() end
    dialog.item:SetText(("|T%s:16|t %s"):format(C_Item.GetItemIconByID(found.id) or 134400, found.name))
    dialog:ClearAllPoints()
    dialog:SetPoint("BOTTOMLEFT", button, "TOPLEFT", 0, 4)
    dialog:Show()
    dialog:Raise()
    SetAmount(found.pack)
end

local function ShowNotice()
    local skin = addon.Skin
    local notice = skin.Window("EasyCraftingMultiBuyerNotice", 400, 176, "Easy Crafting")
    local text = skin.Label(notice, "GameFontHighlight", skin.colors.text)
    text:SetPoint("TOPLEFT", 14, -44)
    text:SetPoint("RIGHT", -14, 0)
    text:SetJustifyH("LEFT")
    text:SetSpacing(3)
    text:SetText("Multi Buyer is also installed. Easy Crafting now buys in bulk too, so you only need one of them.\n\n"
        .. "While Multi Buyer is on, Easy Crafting leaves shift-click at merchants to it.")
    local disable = skin.Button(notice, "Disable Multi Buyer and reload", 190, function()
        C_AddOns.DisableAddOn("MultiBuyer")
        ReloadUI()
    end)
    disable:SetPoint("BOTTOMRIGHT", -14, 12)
    local keep = skin.Button(notice, "Keep both", 90, function()
        EasyCraftingSettings.keepMultiBuyer = true
        notice:Hide()
    end)
    keep:SetPoint("RIGHT", disable, "LEFT", -6, 0)
    notice:Show()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("MERCHANT_CLOSED")
events:SetScript("OnEvent", function(_, event)
    if event == "MERCHANT_CLOSED" then
        Stop()
    elseif C_AddOns.IsAddOnLoaded("MultiBuyer") then
        -- Wait a moment so EllesmereUI has set its accent color before the notice reads the theme.
        if addon.GetSetting("bulkBuy") and not EasyCraftingSettings.keepMultiBuyer then C_Timer.After(3, ShowNotice) end
    elseif not hooked and type(MerchantItemButton_OnModifiedClick) == "function" then
        hooked = true
        hooksecurefunc(_G, "MerchantItemButton_OnModifiedClick", OnModifiedClick)
    end
end)
