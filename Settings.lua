local _, addon = ...

local options = {
    { "window", "Use Easy Crafting's profession window", true },
    { "blizzardStyle", "Blizzard window style (type /reload to apply)", false },
    { "unlearned", "Show unlearned recipes", true },
    { "craftCounts", "Show craftable and merchant counts in the recipe list", true },
    { "altProfessions", "Remember your alts' professions", true },
    { "vendorProfit", "Vendor profit in the recipe list", false },
    { "auctionProfit", "Auction House profit", true },
    { "bulkBuy", "Shift-click merchant items to buy in bulk", true },
}

local defaults, toggles = {}, {}
for _, row in ipairs(options) do defaults[row[1]] = row[3] end

function addon.GetSetting(key)
    local value = EasyCraftingSettings and EasyCraftingSettings[key]
    if value == nil then return defaults[key] end
    return value
end

function addon.SetSetting(key, value)
    EasyCraftingSettings = EasyCraftingSettings or {}
    EasyCraftingSettings[key] = value
    if toggles[key] then toggles[key]:SetChecked(value) end
    addon.RefreshWindow()
end

local settings
function addon.OpenSettings()
    if not settings then
        local skin = addon.Skin
        settings = skin.Window("EasyCraftingOptions", 430, 65 + #options * 25, "Easy Crafting settings")
        for index, row in ipairs(options) do
            local key, label = row[1], row[2]
            local check = CreateFrame("CheckButton", nil, settings, "UICheckButtonTemplate")
            check:SetPoint("TOPLEFT", 16, -15 - index * 25)
            check:SetSize(22, 22)
            local text = skin.Label(check, "GameFontHighlight", skin.colors.text)
            text:SetPoint("LEFT", check, "RIGHT", 6, 0)
            text:SetText(label)
            check:SetHitRectInsets(0, -text:GetStringWidth() - 8, 0, 0)
            check:SetScript("OnClick", function(self) addon.SetSetting(key, self:GetChecked() == true) end)
            toggles[key] = check
        end
    end
    for key, check in pairs(toggles) do check:SetChecked(addon.GetSetting(key)) end
    settings:Show()
    settings:Raise()
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
    if name ~= "EasyCrafting" then return end
    EasyCraftingSettings = EasyCraftingSettings or {}
    if EasyCraftingSettings.window == nil and EasyCraftingSettings.native ~= nil then
        EasyCraftingSettings.window = not EasyCraftingSettings.native
    end
    EasyCraftingSettings.native = nil
    self:UnregisterEvent("ADDON_LOADED")
end)

SLASH_EASYCRAFTINGSETTINGS1 = "/ecsettings"
SlashCmdList.EASYCRAFTINGSETTINGS = addon.OpenSettings
