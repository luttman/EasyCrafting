local scriptDirectory = arg[0]:match("^(.*[/\\])") or ""
local addonDirectory = scriptDirectory .. "../VendorProfit/"
local filename = arg[1] or addonDirectory .. "VendorProfit.lua"
local eventHandler, itemTooltip, currentRecipe, queued, routeHover
local visible = true
local scanMining, knowTin = false, true
local auction = { [2841] = 205, [2319] = 82, [2592] = 109, [12037] = 200, [2692] = 50, [9000] = 70 }
local merchants = { [2692] = 36 }
local sales = { [4382] = 600, [12209] = 300, [9999] = 500 }
local names = { [2841] = "Bronze Bar", [2319] = "Medium Leather", [2592] = "Wool Cloth",
    [2840] = "Copper Bar", [3576] = "Tin Bar", [2770] = "Copper Ore", [2771] = "Tin Ore" }

Enum = { CraftingReagentType = { Basic = 0 }, TooltipDataType = { Item = 0 } }
AUCTIONATOR_L_PROFIT_COLON = "Profit:"
local function Color(name)
    return { WrapTextInColorCode = function(_, text) return "[" .. name .. "]" .. text end }
end
RED_FONT_COLOR, GREEN_FONT_COLOR, WHITE_FONT_COLOR = Color("red"), Color("green"), Color("white")
function GetMoneyString(copper) return copper .. "c" end
function CreateFrame(_, _, parent)
    if parent then
        routeHover = {
            SetScript = function(self, name, callback) self[name] = callback end,
            EnableMouse = function(self, enabled) self.mouse = enabled end,
            Show = function(self) self.visible = true end,
            Hide = function(self)
                if self.visible and self.OnHide then self:OnHide() end
                self.visible = false
            end,
            ClearAllPoints = function() end,
            SetPoint = function(self, _, _, _, _, offset) self.offset = offset end,
            SetSize = function(self, width, height) self.width, self.height = width, height end,
        }
        return routeHover
    end
    return {
        RegisterEvent = function() end,
        UnregisterEvent = function() end,
        SetScript = function(self, _, callback)
            eventHandler = function(...) callback(self, ...) end
        end,
    }
end
GameTooltip = {
    SetOwner = function(self, owner) self.owner = owner end,
    IsOwned = function(self, owner) return self.owner == owner end,
    ClearLines = function(self) self.lines = {} end,
    AddLine = function(self, text) self.lines[#self.lines + 1] = text end,
    AddDoubleLine = function(self, label, text) self:AddLine(label .. " | " .. text) end,
    Show = function(self) self.visible = true end,
    Hide = function(self) self.owner, self.visible = nil, false end,
}
function hooksecurefunc(object, key, callback)
    local original = object[key]
    object[key] = function(...)
        original(...)
        callback(...)
    end
end

local function Reagent(quantity, itemID, kind)
    return { quantityRequired = quantity, reagentType = kind or 0, reagents = { { itemID = itemID } } }
end
local schematics = {
    [3953] = { recipeID = 3953, outputItemID = 4382, quantityMin = 1, quantityMax = 1,
        reagentSlotSchematics = { Reagent(2, 2841), Reagent(1, 2319), Reagent(1, 2592) } },
    [10002] = { recipeID = 10002, outputItemID = 12209, quantityMin = 2, quantityMax = 3,
        reagentSlotSchematics = { Reagent(1, 12037), Reagent(1, 2692) } },
    [10003] = { recipeID = 10003, outputItemID = 9999, quantityMin = 1, quantityMax = 1,
        reagentSlotSchematics = { Reagent(1, 12037), Reagent(1, 9000, 1) } },
    [10004] = { recipeID = 10004, outputItemID = 4382, quantityMin = 1, quantityMax = 1,
        reagentSlotSchematics = { Reagent(2, 2841), Reagent(1, 2841) } },
    [2659] = { recipeID = 2659, outputItemID = 2841, quantityMin = 2,
        reagentSlotSchematics = { Reagent(1, 2840), Reagent(1, 3576) } },
    [2657] = { recipeID = 2657, outputItemID = 2840, quantityMin = 1,
        reagentSlotSchematics = { Reagent(1, 2770) } },
    [3304] = { recipeID = 3304, outputItemID = 3576, quantityMin = 1,
        reagentSlotSchematics = { Reagent(1, 2771) } },
    [20000] = { recipeID = 20000, outputItemID = 2770, quantityMin = 10,
        reagentSlotSchematics = { Reagent(1, 2841) } },
}
local recipeNames = { [2659] = "Smelt Bronze", [2657] = "Smelt Copper", [3304] = "Smelt Tin", [20000] = "Cycle" }
local function RecipeInfo(id)
    return schematics[id] and { recipeID = id, name = recipeNames[id],
        learned = id ~= 10003 and (id ~= 3304 or knowTin) }
end
local transaction = { GetAllocations = function(_, index)
    if currentRecipe ~= 10003 or index ~= 2 then return nil end
    return {
        Accumulate = function() return 1 end,
        FindAllocationByReagent = function() return { GetQuantity = function() return 1 end } end,
    }
end }
local form = {
    GetRecipeInfo = function() return RecipeInfo(currentRecipe) end,
    GetCurrentRecipeLevel = function() return 0 end,
    GetTransaction = function() return transaction end,
}
local frame = {
    Total = {
        GetText = function(self) return self.text end,
        SetText = function(self, text) self.text = text end,
        GetSpacing = function() return 1.5 end,
        GetStringHeight = function(self) return 14 * (1 + select(2, self.text:gsub("\n", ""))) - 1.5 end,
        GetUnboundedStringWidthForText = function(_, text) return #text * 6 end,
    },
    GetParent = function() return form end,
    IsVisible = function() return visible end,
    SetHeight = function(self, height) self.height = height end,
    UpdateTotal = function(self) self.Total:SetText("To Craft: cost\nProfit: AH\nOther cost: here") end,
}
Auctionator = {
    API = { v1 = {
        GetVendorPriceByItemID = function(_, id) return merchants[id] end,
        GetAuctionPriceByItemID = function(_, id) return auction[id] end,
    } },
    CraftingInfo = { InitializeProfessionsFrame = function() AuctionatorCraftingInfoProfessionsFrame = frame end },
}
C_Item = { GetItemInfo = function(id)
    return names[id], nil, nil, nil, nil, nil, nil, nil, nil, nil, sales[id]
end }
C_TradeSkillUI = {
    GetFilteredRecipeIDs = function()
        return scanMining and { 2659, 2657, 3304, 20000 } or { 3953, 10002, 10003 }
    end,
    GetRecipeInfo = RecipeInfo,
    GetRecipeSchematic = function(id) return schematics[id] end,
}
C_Timer = { After = function(_, callback) queued = callback end }
ProfessionsFrame = { IsVisible = function() return visible end }
TooltipDataProcessor = { AddTooltipPostCall = function(_, callback) itemTooltip = callback end }
local tooltip = { IsForbidden = function() return false end, AddDoubleLine = function(self, label, text)
    self.label, self.text = label, text
end }

assert(loadfile(filename))("VendorProfit")
eventHandler("ADDON_LOADED", "VendorProfit")
currentRecipe = 3953
Auctionator.CraftingInfo.InitializeProfessionsFrame()
assert(frame.Total.text == "To Craft: cost\nProfit: AH\nProfit to vendor: [red]-1c\nOther cost: here")
assert(frame.height == 64)
assert(routeHover.visible and routeHover.mouse and routeHover.offset == -28 and routeHover.height == 14)
routeHover:OnEnter()
assert(GameTooltip.visible and GameTooltip.lines[2] == "Buy 2 x Bronze Bar (AH) | 410c")
routeHover:OnLeave()
assert(not GameTooltip.visible)
frame:UpdateTotal()
assert(select(2, frame.Total.text:gsub("Profit to vendor", "")) == 1)

eventHandler("TRADE_SKILL_SHOW")
assert(queued)
queued()
assert(VendorProfitRecipes[3953] and VendorProfitRecipes[10002] and not VendorProfitRecipes[10003])
itemTooltip(tooltip, { id = 4382 })
assert(tooltip.label == "Profit to vendor (each)" and tooltip.text == "[red]-1c")
currentRecipe = 10002
frame:UpdateTotal()
assert(frame.Total.text:find("Profit to vendor (min. yield): [green]364c", 1, true))
itemTooltip(tooltip, { id = 12209 })
assert(tooltip.label == "Profit to vendor (each, min. yield)" and tooltip.text == "[green]182c")

auction[12037] = nil
frame:UpdateTotal()
assert(frame.Total.text:find("Missing reagent price", 1, true))
itemTooltip(tooltip, { id = 12209 })
assert(tooltip.text == "Missing reagent price")
auction[12037] = 200
sales[12209] = nil
frame:UpdateTotal()
assert(frame.Total.text:find("Waiting for item data", 1, true))
sales[12209] = 300
eventHandler("GET_ITEM_INFO_RECEIVED", 12209, true)
assert(frame.Total.text:find("364c", 1, true))

currentRecipe = 10003
frame:UpdateTotal()
assert(frame.Total.text:find("[green]230c", 1, true))
tooltip.text = nil
itemTooltip(tooltip, { id = 9999 })
assert(tooltip.text == nil)
tooltip.IsForbidden = function() return true end
itemTooltip(tooltip, { id = 4382 })
assert(tooltip.text == nil)

-- Load Mining as a separate profession, and compare buying bars, mixed inputs, and smelting all the way from ore.
scanMining, knowTin, currentRecipe = true, false, 3953
auction[2840], auction[3576], auction[2770], auction[2771] = 187, 109, 174, 99
eventHandler("TRADE_SKILL_SHOW")
queued()
assert(VendorProfitRecipes[2659] and VendorProfitRecipes[2657] and not VendorProfitRecipes[3304])
assert(frame.Total.text:find("[green]126c", 1, true))
routeHover:OnEnter()
assert(GameTooltip.lines[2] == "Smelt Bronze x 1 (makes 2 x Bronze Bar) | 283c")
assert(GameTooltip.lines[3] == "  Smelt Copper x 1 (makes 1 x Copper Bar) | 174c")
assert(GameTooltip.lines[4] == "    Buy 1 x Copper Ore (AH) | 174c")
assert(GameTooltip.lines[5] == "  Buy 1 x Tin Bar (AH) | 109c")
assert(GameTooltip.lines[9] == "Material cost | 474c" and GameTooltip.lines[10] == "Vendor revenue | 600c")

knowTin = true
eventHandler("TRADE_SKILL_LIST_UPDATE")
queued()
assert(frame.Total.text:find("[green]136c", 1, true))
assert(GameTooltip.lines[5] == "  Smelt Tin x 1 (makes 1 x Tin Bar) | 99c")
assert(GameTooltip.lines[6] == "    Buy 1 x Tin Ore (AH) | 99c")
tooltip.IsForbidden = function() return false end
itemTooltip(tooltip, { id = 4382 })
assert(tooltip.text == "[green]136c")

currentRecipe = 10004
frame:UpdateTotal()
assert(frame.Total.text:find("[green]122c", 1, true))
assert(GameTooltip.lines[7] == "Buy 1 x Bronze Bar (AH) | 205c")
currentRecipe = 3953
auction[2841] = 100
frame:UpdateTotal()
assert(frame.Total.text:find("[green]209c", 1, true))
assert(GameTooltip.lines[2] == "Buy 2 x Bronze Bar (AH) | 200c")
auction[2841], auction[2840], auction[2770] = 205, nil, nil
frame:UpdateTotal()
assert(frame.Total.text:find("[red]-1c", 1, true))
assert(GameTooltip.lines[2] == "Buy 2 x Bronze Bar (AH) | 410c")
auction[2770] = 174
currentRecipe = nil
frame:UpdateTotal()
assert(not routeHover.visible and not GameTooltip.visible)

-- A second addon load with the saved recipe table populated restores tooltips before opening a profession.
visible = false
tooltip.IsForbidden = function() return false end
local addon = {}
assert(loadfile(filename))("VendorProfit", addon)
eventHandler("ADDON_LOADED", "VendorProfit")
itemTooltip(tooltip, { id = 4382 })
assert(tooltip.text == "[green]136c")
print("Vendor Profit: hover placement, learned recipes, nested smelting, mixed routes, cycle fallback, yields, allocations, and saved cache passed")

local have = { [2841] = 1 }
local function Count(id) return have[id] or 0 end
local quote, revenue = addon.QuoteVendor(schematics[3953], nil, 2)
assert(revenue == 1200 and quote.cost == 928)
local needs = addon.ShoppingNeeds(quote, Count)
assert(needs[2841] == 1 and needs[2770] == 1 and needs[2771] == 1)
assert(needs[2319] == 2 and needs[2592] == 2)
have[2841] = 4
needs = addon.ShoppingNeeds(quote, Count)
assert(not needs[2770] and not needs[2771] and not needs[2841])
local candidates = addon.PriceCandidates(schematics[3953])
assert(candidates[2841] and candidates[2840] and candidates[3576] and candidates[2770] and candidates[2771])

local widgets = {}
local widgetMethods = {
    SetScript = function(self, key, callback) self[key] = callback end,
    HookScript = function(self, key, callback)
        local original = self[key]
        self[key] = function(...) if original then original(...) end; callback(...) end
    end,
    SetText = function(self, value)
        self.text = tostring(value or "")
        if self.OnTextChanged then self:OnTextChanged() end
    end,
    GetText = function(self) return self.text or "" end,
    SetValue = function(self, value) self.value = value end,
    SetEnabled = function(self, value) self.enabled = value end,
    IsEnabled = function(self) return self.enabled ~= false end,
    SetHeight = function(self, height) self.height = height end,
    GetHeight = function(self) return self.height or 520 end,
    GetWidth = function() return 780 end,
    GetStringHeight = function() return 50 end,
    Show = function(self) self.shown = true end,
    Hide = function(self) self.shown = false end,
    IsShown = function(self) return self.shown ~= false end,
    IsVisible = function(self) return self.shown ~= false end,
    SetShown = function(self, shown) self.shown = shown == true end,
    SetChecked = function(self, checked) self.checked = checked end,
    GetChecked = function(self) return self.checked end,
    EnableMouse = function(self, enabled) self.mouse, self.motion = enabled, enabled end,
    SetMouseClickEnabled = function(self, enabled) self.mouse = enabled end,
    IsMouseClickEnabled = function(self) return self.mouse == true end,
    SetMouseMotionEnabled = function(self, enabled) self.motion = enabled end,
    IsMouseMotionEnabled = function(self) return self.motion == true end,
    EnableMouseWheel = function(self, enabled) self.wheel = enabled end,
    IsMouseWheelEnabled = function(self) return self.wheel == true end,
    GetChildren = function(self) return unpack(self.children) end,
    GetRegions = function(self) return unpack(self.regions) end,
    RegisterForClicks = function(self, ...)
        self.clicks = {}
        for _, click in ipairs({ ... }) do self.clicks[click] = true end
    end,
    Click = function(self)
        assert(self:IsShown() and self:IsEnabled() and self.mouse and self.clicks.LeftButtonUp)
        self:OnClick("LeftButton")
    end,
    Raise = function(self) self.raised = true end,
    RegisterEvent = function(self, name) self.events[name] = true end,
    UnregisterEvent = function(self, name) self.events[name] = nil end,
    RegisterUnitEvent = function(self, name) self.events[name] = true end,
    SetAlpha = function(self, alpha) self.alpha = alpha end,
    GetAlpha = function(self) return self.alpha or 1 end,
    SetFrameStrata = function(self, strata) self.strata = strata end,
    SetColorTexture = function(self, ...) self.textureColor = { ... } end,
    SetIgnoreParentAlpha = function(self, value) self.ignoresAlpha = value end,
    IsIgnoringParentAlpha = function(self) return self.ignoresAlpha == true end,
    GetPoint = function(self, index) return unpack(self.points[index or 1] or {}) end,
    GetNumPoints = function(self) return #self.points end,
    ClearAllPoints = function(self) self.points = {} end,
    SetPoint = function(self, ...) self.points[#self.points + 1] = { ... } end,
    GetStringWidth = function(self) return #self:GetText() * 6 end,
}
local function Widget(kind, name, parent, template)
    local widget = setmetatable({
        kind = kind, name = name, parent = parent, events = {}, points = {}, children = {}, regions = {},
    }, { __index = widgetMethods })
    if parent then
        local members = (kind == "Texture" or kind == "FontString") and parent.regions or parent.children
        members[#members + 1] = widget
    end
    if template == "BasicFrameTemplateWithInset" then widget.TitleText = Widget("FontString", nil, widget) end
    widgets[#widgets + 1] = widget
    return widget
end
widgetMethods.CreateTexture = function(self, _, layer)
    local texture = Widget("Texture", nil, self)
    texture.layer = layer
    return texture
end
widgetMethods.CreateFontString = function(self) return Widget("FontString", nil, self) end
for _, method in ipairs({
    "SetAllPoints", "SetTextColor", "SetFrameLevel",
    "SetSize", "SetWidth", "SetJustifyH", "SetJustifyV", "SetWordWrap", "SetOrientation", "SetValueStep",
    "SetObeyStepOnDrag", "SetThumbTexture", "SetMinMaxValues", "SetAutoFocus",
    "SetScrollChild", "SetVerticalScroll", "SetSpacing", "SetNumeric", "SetMaxLetters",
    "SetTexture", "SetStatusBarTexture", "SetStatusBarColor", "SetMovable",
    "SetClampedToScreen", "SetClampRectInsets", "SetScale", "RegisterForDrag", "StopMovingOrSizing", "SetHitRectInsets",
    "SetFont", "SetAtlas",
}) do
    widgetMethods[method] = function() end
end
widgetMethods.GetFrameLevel = function() return 100 end
local function FindText(text)
    for _, widget in ipairs(widgets) do
        if widget.text and widget.text:find(text, 1, true) then return widget end
    end
end
local function FindButton(text)
    for _, widget in ipairs(widgets) do
        if widget.text == text and widget.parent and widget.parent.kind == "Button" then return widget.parent end
    end
end

CreateFrame = Widget
SearchBoxTemplate_OnTextChanged = function() end
local inCombat = false
InCombatLockdown = function() return inCombat end
local now, loadingProfession = 0, false
GetTime = function() return now end
C_TradeSkillUI.IsDataSourceChanging = function() return loadingProfession end
SlashCmdList = {}
UIParent = Widget("Frame", "UIParent")
ProfessionsFrame = Widget("Frame")
ProfessionsFrame:EnableMouse(true)
local overview = Widget("Frame", nil, ProfessionsFrame)
overview:EnableMouse(true)
overview:SetPoint("TOPLEFT", ProfessionsFrame, "TOPRIGHT", 0, -34)
ProfessionsFrame.ProfessionsOverviewTab = overview
local professionTab = Widget("Button", nil, ProfessionsFrame)
professionTab:EnableMouse(true)
ProfessionsFrame.rightProfessionTabs = { professionTab }
local crafting = Widget("Frame", nil, ProfessionsFrame)
crafting:EnableMouseWheel(true)
local nativeRegion = crafting:CreateTexture(nil, "ARTWORK")
nativeRegion:SetMouseMotionEnabled(true)
ProfessionsFrame.CraftingPage = crafting
crafting.CreateButton = Widget("Button", nil, crafting)
crafting.CreateButton:EnableMouse(true)
crafting.CreateAllButton = Widget("Button", nil, crafting)
crafting.CreateMultipleInputBox = Widget("EditBox", nil, crafting)
crafting.GetCraftableCount = function() return 3 end
crafting.SchematicForm = {
    GetRecipeInfo = function() return C_TradeSkillUI.GetRecipeInfo(currentRecipe) end,
    GetTransaction = function() return transaction end,
}
crafting.SelectRecipe = function(self, info)
    currentRecipe = info.recipeID
    self.SchematicForm.recipeSchematic = schematics[currentRecipe]
end
local crafted
crafting.Create = function(self) crafted = self.CreateMultipleInputBox.value end
crafting.CreateAll = function() crafted = 3 end
C_TradeSkillUI.GetBaseProfessionInfo = function()
    return { professionID = 202, professionName = "Engineering", skillLevel = 150, maxSkillLevel = 155 }
end
C_TradeSkillUI.GetRecipeInfo = function(id)
    local info = RecipeInfo(id)
    if info then
        info.name = id == 3953 and "Bronze Framework" or id == 15863 and "Carrion Surprise" or "Other recipe " .. id
        info.relativeDifficulty = id == 3953 and 0 or 3
        info.canSkillUp = id == 3953
    end
    return info
end
C_TradeSkillUI.IsRecipeTracked = function() return false end
C_Item.GetItemNameByID = function(id) return names[id] end
C_Item.GetItemCount = Count
C_Item.GetItemIconByID = function() return 134400 end
C_Spell = {
    GetSpellDescription = function() return "Craft the selected recipe." end,
    GetSpellName = function(id) return id == 3953 and "Bronze Framework" or nil end,
    GetSpellTexture = function() return 134400 end,
}
UnitGUID = function() return "Player-test" end
UnitName = function() return "Crafter" end
UnitLevel = function() return 36 end
GetRealmName = function() return "Test realm" end
UnitFactionGroup = function() return "Alliance" end
C_Map = { GetBestMapForUnit = function() return 10 end }
local searched
AuctionHouseFrame = Widget("Frame")
Auctionator.API.v1.MultiSearchAdvanced = function(_, items)
    searched = {}
    for _, term in ipairs(items) do searched[#searched + 1] = term.searchString end
end
scanMining = false
schematics[15863] = { recipeID = 15863, outputItemID = 12213, quantityMin = 1, quantityMax = 1,
    reagentSlotSchematics = { Reagent(1, 2692), Reagent(1, 12037) } }
have[2692], have[12037] = 1, 11
C_TradeSkillUI.GetFilteredRecipeIDs = function() return { 3953, 10002, 10003, 15863 } end
crafting:SelectRecipe(C_TradeSkillUI.GetRecipeInfo(3953))
local blizzardFrame = ProfessionsFrame
ProfessionsFrame = nil
for _, file in ipairs({ "Settings", "ProfessionData", "Planning", "ProfessionTools", "ProfessionWindow" }) do
    assert(loadfile(addonDirectory .. file .. ".lua"))("VendorProfit", addon)
    if file == "Settings" then widgets[#widgets]:OnEvent("ADDON_LOADED", "VendorProfit") end
end
local windowEvents = widgets[#widgets]
windowEvents:OnEvent("ADDON_LOADED", "VendorProfit")
VendorProfitSettings.ranks = true
ProfessionsFrame = blizzardFrame
ProfessionsFrame:Hide()
crafting:Hide()
windowEvents:OnEvent("ADDON_LOADED", "Blizzard_Professions")
ProfessionsFrame:Show()
ProfessionsFrame:OnShow()
assert(ProfessionsFrame:GetAlpha() == 1)
loadingProfession = true
crafting:Show()
crafting:OnShow()
assert(ProfessionsFrame:GetAlpha() == 0)
now = 0.08
queued()
assert(ProfessionsFrame:GetAlpha() == 0 and not FindText("Engineering 150/155"))
now = 0.16
loadingProfession = false
queued()
assert(FindText("Engineering 150/155") and FindText("Profit to vendor") and FindText("+136c"))
local overlay = FindText("Engineering 150/155").parent.parent
assert(overlay.name == "VendorProfitProfessionWindow" and overlay.parent == UIParent)
assert(ProfessionsFrame:GetAlpha() == 0 and overview.ignoresAlpha and select(2, overview:GetPoint()) == overlay)
assert(not ProfessionsFrame:IsMouseClickEnabled() and not ProfessionsFrame:IsMouseMotionEnabled())
assert(not crafting:IsMouseWheelEnabled() and not nativeRegion:IsMouseMotionEnabled())
assert(crafting.CreateButton:IsEnabled() and not crafting.CreateButton:IsMouseClickEnabled())
assert(overview:IsMouseClickEnabled() and professionTab:IsMouseClickEnabled())
local lateControl = Widget("Button", nil, crafting)
lateControl:SetMouseClickEnabled(true)
addon.RefreshWindow()
queued()
assert(not lateControl:IsMouseClickEnabled())
local drag
for _, widget in ipairs(widgets) do
    if widget.parent == overlay and widget.OnDragStart then drag = widget end
end
local dragPoint, dragAnchor, anchorPoint, inset = drag:GetPoint(2)
assert(dragPoint == "TOPRIGHT" and dragAnchor == FindButton("Settings") and anchorPoint == "TOPLEFT" and inset < 0)
local menuItems = {}
MenuUtil = { CreateContextMenu = function(_, build)
    build(nil, { CreateButton = function(_, title) menuItems[title] = true end })
end }
FindButton("Tools"):Click()
assert(menuItems.Settings and menuItems["Crafting queue"] and menuItems["Best for skill-ups"])
local chat
C_TradeSkillUI.GetTradeSkillListLink = function() return "[Engineering]" end
ChatEdit_InsertLink = function() return false end
ChatFrame_OpenChat = function(text) chat = text end
FindButton("Link"):Click()
assert(chat == "[Engineering]")
FindButton("Settings"):Click()
local title = FindText("Vendor Profit settings")
assert(title and title.parent:IsShown() and title.parent.raised)
assert(overlay.strata == "DIALOG" and title.parent.strata == "FULLSCREEN_DIALOG")
local opaqueBackdrop
for _, widget in ipairs(widgets) do
    if widget.parent == title.parent and widget.layer == "BACKGROUND" and widget.textureColor then
        opaqueBackdrop = widget.textureColor[4] == 1
    end
end
assert(opaqueBackdrop)
local carrionRow = FindText("Carrion Surprise").parent
assert(carrionRow.count.text == "1 || |cffffa55011|r")
assert(carrionRow.highlight.layer == "HIGHLIGHT" and carrionRow.highlight:GetAlpha() < 0.25)
carrionRow:OnClick("LeftButton")
assert(currentRecipe == 15863 and carrionRow.background:IsShown())
assert(carrionRow.count.text == "1 || |cffffa55011|r")
crafting:SelectRecipe(C_TradeSkillUI.GetRecipeInfo(3953))
queued()
local inBags, withMerchant = addon.CraftCounts(schematics[15863], Count)
assert(inBags == 1 and withMerchant == 11)
assert(FindText("Bags") and FindText("Bank"))
local first, yellow, green, gray = addon.SkillRange(1229737)
assert(first == 1 and yellow == 1 and green == 3 and gray == 5)
addon.SetSetting("craftCounts", false)
queued()
assert(carrionRow.count.text == "")
addon.SetSetting("craftCounts", true)
queued()
assert(carrionRow.count.text == "1 || |cffffa55011|r")
auction[4382] = 700
assert(addon.AuctionRevenue(schematics[3953]) == 665)
assert(math.abs(addon.SkillChance(3953, 150) - 0.9) < 0.0001)
local ownedQuote = addon.QuoteVendor(schematics[3953], nil, 1, { [2319] = true })
assert(ownedQuote.cost == 382)
addon.SetSetting("auctionProfit", false)
queued()
assert(not FindText("Auction").shown)
addon.SetSetting("auctionProfit", true)
queued()
FindText("Create").parent:OnClick()
assert(crafted == 1)
windowEvents:OnEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 3953)
FindText("Create all (3)").parent:OnClick()
assert(crafted == 3)
queued()
local batch = FindText("Crafting  0 / 3")
assert(batch and batch.parent:IsShown())
for _ = 1, 3 do windowEvents:OnEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 3953) end
queued()
assert(not batch.parent:IsShown())
FindText("Profit to vendor").parent:OnEnter()
assert(GameTooltip.lines[2] == "Smelt Bronze x 1 (makes 2 x Bronze Bar) | 273c")
FindText("Profit to vendor").parent:OnLeave()
FindButton("Shopping list"):Click()
assert(FindText("1 craft of Bronze Framework"))
FindText("Refresh prices").parent:OnClick()
assert(table.concat(searched, ",") == "Bronze Bar,Copper Bar,Copper Ore,Medium Leather,Tin Bar,Tin Ore,Wool Cloth")
addon.AddToShopping(3953, 2, schematics[3953])
addon.AddToShopping(3953, 1, schematics[3953])
assert(addon.GetWork().shopping[3953].quantity == 3)
local savedNeeds, prerequisites = addon.ShoppingPlan(Count)
assert(savedNeeds[2319] == 3 and savedNeeds[2592] == 3 and prerequisites[1].recipeID == 2657)
assert(FindText("Use Vendor Profit's profession window") and FindText("Skill thresholds and estimated chances"))
assert(FindText("Recipe sources"))
assert(not FindText("Leveling plan") and not FindText("Include recipes you can train later"))
assert(not FindText("Next rank available") and not FindText("Next profession rank guidance"))
assert(not FindButton("Waypoint") and not FindButton("Skill-up plan"))
MerchantFrame = Widget("Frame")
GetMerchantNumItems = function() return 1 end
GetMerchantItemLink = function() return "item:2692" end
GetMerchantItemID = function() return 2692 end
GetMerchantItemMaxStack = function() return 20 end
C_MerchantFrame = { GetItemInfo = function()
    return { price = 50, stackCount = 5, numAvailable = -1, hasExtendedCost = false }
end }
local offer = addon.MerchantOffers({ [2692] = 6 })[1]
assert(offer.quantity == 10 and offer.total == 100)
SlashCmdList.VENDORPROFITWINDOW()
queued()
assert(not overlay:IsShown() and ProfessionsFrame:GetAlpha() == 1)
ProfessionsFrame:OnShow()
assert(ProfessionsFrame:GetAlpha() == 1)
assert(not overview.ignoresAlpha and select(2, overview:GetPoint()) == ProfessionsFrame)
assert(ProfessionsFrame:IsMouseClickEnabled() and ProfessionsFrame:IsMouseMotionEnabled())
assert(crafting:IsMouseWheelEnabled() and nativeRegion:IsMouseMotionEnabled() and not nativeRegion:IsMouseClickEnabled())
assert(lateControl:IsMouseClickEnabled() and not lateControl:IsMouseMotionEnabled())
SlashCmdList.VENDORPROFITWINDOW()
queued()
assert(overlay:IsShown())
HideUIPanel = function(frame)
    frame:Hide()
    crafting:Hide()
    frame:OnHide()
end
inCombat = true
FindButton("X"):Click()
assert(not overlay:IsShown() and ProfessionsFrame:GetAlpha() == 1)
assert(not ProfessionsFrame:IsMouseClickEnabled())
inCombat = false
windowEvents:OnEvent("PLAYER_REGEN_ENABLED")
queued()
assert(ProfessionsFrame:IsMouseClickEnabled() and crafting:IsMouseWheelEnabled())
loadingProfession = true
ProfessionsFrame:SetAlpha(0.8)
ProfessionsFrame:Show()
crafting:Show()
ProfessionsFrame:OnShow()
assert(ProfessionsFrame:GetAlpha() == 0)
now = now + 1.1
queued()
assert(ProfessionsFrame:GetAlpha() == 0.8 and not overlay:IsShown())
print("Vendor Profit: opening visibility, native fallback, header buttons, mouse input, crafting, shopping, and price search passed")
