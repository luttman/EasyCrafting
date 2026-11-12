local _, addon = ...

local options = {
    { "Window", {
        { "window", "Use Vendor Profit's profession window", true },
        { "favorites", "Recipe favorites", true },
        { "unlearned", "Show unlearned recipes", true },
        { "inventory", "Show bag and bank counts", true },
        { "craftCounts", "Show craftable and merchant counts in the recipe list", true },
        { "altProfessions", "Remember your alts' professions", true },
    } },
    { "Prices and shopping", {
        { "vendorProfit", "Vendor profit in the recipe list", true },
        { "auctionProfit", "Auction House profit", true },
        { "roi", "Return on material cost", true },
        { "itemTooltip", "Vendor profit in item tooltips", true },
        { "owned", "Allow excluding materials you own", true },
        { "shopping", "Saved shopping lists", true },
        { "buy", "Auction House and merchant buy buttons", true },
        { "queue", "Crafting queue", true },
        { "reagentUses", "Show what a reagent makes", true },
    } },
    { "Skills and other tools", {
        { "skillChances", "Skill thresholds and estimated chances", true },
        { "sources", "Recipe sources", true },
        { "timer", "Batch crafting progress", true },
        { "orders", "Draft requests from profession links", true },
        { "disenchant", "Disenchant values", true },
        { "gathering", "Gathering tracking reminder", false },
    } },
}

local defaults, toggles = {}, {}
for _, group in ipairs(options) do
    for _, row in ipairs(group[2]) do defaults[row[1]] = row[3] end
end

function addon.GetSetting(key)
    local value = VendorProfitSettings and VendorProfitSettings[key]
    if value == nil then return defaults[key] end
    return value
end

function addon.SetSetting(key, value)
    VendorProfitSettings = VendorProfitSettings or {}
    VendorProfitSettings[key] = value
    if key == "window" then VendorProfitSettings.native = not value end
    if toggles[key] then toggles[key]:SetChecked(value) end
    if addon.RefreshWindow then addon.RefreshWindow() end
    if addon.UpdateGathering then addon.UpdateGathering() end
end

local settings
function addon.OpenSettings()
    if not settings then
        settings = CreateFrame("Frame", "VendorProfitOptions", UIParent, "BasicFrameTemplateWithInset")
        settings:SetSize(530, 620)
        settings:SetPoint("CENTER")
        settings:SetFrameStrata("FULLSCREEN_DIALOG")
        settings:SetClampedToScreen(true)
        settings:EnableMouse(true)
        local backdrop = settings:CreateTexture(nil, "BACKGROUND", nil, -8)
        backdrop:SetPoint("TOPLEFT", 4, -4)
        backdrop:SetPoint("BOTTOMRIGHT", -4, 4)
        backdrop:SetColorTexture(0.055, 0.063, 0.073, 1)
        settings.TitleText:SetText("Vendor Profit settings")
        if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = "VendorProfitOptions" end

        local scroll = CreateFrame("ScrollFrame", nil, settings, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 14, -37)
        scroll:SetPoint("BOTTOMRIGHT", -35, 14)
        local content = CreateFrame("Frame", nil, scroll)
        content:SetWidth(465)
        scroll:SetScrollChild(content)
        local top = 0
        for _, group in ipairs(options) do
            local heading = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            heading:SetPoint("TOPLEFT", 5, -top)
            heading:SetText(group[1])
            top = top + 24
            for _, row in ipairs(group[2]) do
                local key, label = row[1], row[2]
                local check = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
                check:SetPoint("TOPLEFT", 5, -top)
                check:SetSize(22, 22)
                local text = check:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                text:SetPoint("LEFT", check, "RIGHT", 6, 0)
                text:SetText(label)
                check:SetHitRectInsets(0, -text:GetStringWidth() - 8, 0, 0)
                check:SetScript("OnClick", function(self) addon.SetSetting(key, self:GetChecked() == true) end)
                toggles[key] = check
                top = top + 25
            end
            top = top + 13
        end
        content:SetHeight(top)
    end
    for key, check in pairs(toggles) do check:SetChecked(addon.GetSetting(key)) end
    settings:Show()
    settings:Raise()
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
    if name ~= "VendorProfit" then return end
    VendorProfitSettings = VendorProfitSettings or {}
    if VendorProfitSettings.window == nil and VendorProfitSettings.native ~= nil then
        VendorProfitSettings.window = not VendorProfitSettings.native
    end
    self:UnregisterEvent("ADDON_LOADED")
end)

SLASH_VENDORPROFITSETTINGS1 = "/vpsettings"
SlashCmdList.VENDORPROFITSETTINGS = addon.OpenSettings
