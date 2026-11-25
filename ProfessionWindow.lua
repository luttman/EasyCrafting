local addonName, addon = ...
local window, page, native
local pending, failed
local records, entries, rows = {}, {}, {}
local collapsed = {}
local mode, filter, offset = "recipes", "all", 0
local professionID, stayInQueue
local enchantTarget, enchantRecipe -- item GUID picked for the selected enchant; Enchanting casts need an item
local Refresh, DrawRows, DrawDetail
local savedAlpha, dockedTab, openingUntil
local nativeMouse = {}
local craftingJob, rankInfo
local linked, dismissed
local GetSetting = addon.GetSetting
local Money, ItemName, SpellName = addon.Money, addon.ItemName, addon.SpellName

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
local difficultyColors = {
    [0] = { 1, 0.62, 0.30 },
    [1] = { 1, 0.88, 0.30 },
    [2] = { 0.51, 0.87, 0.39 },
    [3] = { 0.65, 0.69, 0.72 },
}
local fontSizes = { GameFontNormalLarge = 16, GameFontHighlight = 13, GameFontNormal = 13 }
local blizzard, fontFile, fontFlags

-- Everything drawn in the accent color goes through Paint, so it can be redrawn when
-- EllesmereUI's accent changes.
local repaint = {}
local function Paint(apply)
    repaint[#repaint + 1] = apply
    apply()
end

-- Three looks share one layout: Blizzard templates, EllesmereUI's theme, or the built-in flat theme.
-- ponytail: the skin is read once when the window is built, so a change needs /reload.
local function ApplySkin()
    if fontFlags then return end
    blizzard = GetSetting("blizzardStyle")
    local overrides
    if blizzard then
        fontFile, fontFlags = nil, ""
        overrides = {
            background = { 0, 0, 0, 0.3 }, panel = { 0, 0, 0, 0.3 }, group = { 1, 1, 1, 0.07 },
            selected = { 1, 0.82, 0, 0.22 }, banner = { 1, 0.82, 0, 0.12 }, accent = { 1, 0.82, 0 },
            bar = { 0.25, 0.5, 0.85 }, text = { 1, 1, 1 }, muted = { 0.62, 0.62, 0.62 }, gold = { 1, 0.82, 0 },
        }
    elseif EllesmereUI then
        local accent = EllesmereUI.ACCENT_COLOR or EllesmereUI.ELLESMERE_GREEN or { r = 12 / 255, g = 210 / 255, b = 157 / 255 }
        local r, g, b = accent.r, accent.g, accent.b
        local ok, path = pcall(EllesmereUI.GetFontPath)
        local flagged, flags = pcall(EllesmereUI.GetFontOutlineFlag)
        fontFile = ok and type(path) == "string" and path ~= "" and path or ChatFontNormal:GetFont()
        fontFlags = flagged and type(flags) == "string" and flags or ""
        overrides = {
            background = { 0.08, 0.08, 0.08, 0.92 }, panel = { 0.04, 0.04, 0.04, 0.85 },
            button = { 0.11, 0.11, 0.11 }, border = { 0.20, 0.20, 0.20 }, group = { 0.14, 0.14, 0.14 },
            selected = { r * 0.3, g * 0.3, b * 0.3 }, banner = { 0.14, 0.14, 0.14 },
            accent = { r, g, b }, bar = { r, g, b }, text = { 1, 1, 1 }, muted = { 0.6, 0.6, 0.6 },
        }
        if EllesmereUI.RegAccent then
            EllesmereUI.RegAccent({ type = "callback", fn = function(red, green, blue)
                for _, key in ipairs({ "accent", "bar" }) do
                    colors[key][1], colors[key][2], colors[key][3] = red, green, blue
                end
                colors.selected[1], colors.selected[2], colors.selected[3] = red * 0.3, green * 0.3, blue * 0.3
                for _, apply in ipairs(repaint) do apply() end
                -- The recipe rows and the tabs take their colors when they are drawn.
                addon.RefreshWindow()
            end })
        end
    else
        -- The chat font is Arial Narrow on Latin clients and a font with the right glyphs elsewhere.
        fontFile, fontFlags = ChatFontNormal:GetFont(), ""
    end
    for key, color in pairs(overrides or {}) do colors[key] = color end
end

local rowHeight, listWidth, lineHeight = 20, 376, 24

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
    if fontFile then text:SetFont(fontFile, fontSizes[font] or 12, fontFlags) end
    TextColor(text, color)
    return text
end

local function Button(parent, text, width, action)
    if blizzard then
        local template = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        template:SetSize(width, 22)
        template:SetText(text)
        template.label = template:GetFontString()
        template:SetScript("OnClick", action)
        return template
    end
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, 22)
    button:EnableMouse(true)
    button:RegisterForClicks("LeftButtonUp")
    Surface(button, "BACKGROUND", colors.border)
    button.inner = button:CreateTexture(nil, "BORDER")
    button.inner:SetPoint("TOPLEFT", 1, -1)
    button.inner:SetPoint("BOTTOMRIGHT", -1, 1)
    Fill(button.inner, colors.button)
    local hover = button:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints(button.inner)
    Paint(function() Fill(hover, colors.accent) end)
    hover:SetAlpha(0.12)
    button.label = Label(button, "GameFontNormalSmall", colors.text)
    button.label:SetPoint("CENTER")
    button.label:SetText(text)
    button:SetScript("OnClick", action)
    button:SetScript("OnEnable", function() TextColor(button.label, colors.text) end)
    button:SetScript("OnDisable", function() TextColor(button.label, colors.muted) end)
    return button
end

-- A small themed dialog: the settings, the bulk-buy dialog, and notices all use it.
local function Window(name, width, height, title)
    ApplySkin()
    local frame = CreateFrame("Frame", name, UIParent, blizzard and "BasicFrameTemplateWithInset" or nil)
    frame:Hide()
    frame:SetSize(width, height)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    if blizzard then
        local backdrop = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        backdrop:SetPoint("TOPLEFT", 4, -4)
        backdrop:SetPoint("BOTTOMRIGHT", -4, 4)
        backdrop:SetColorTexture(0.055, 0.063, 0.073, 1)
        frame.title = frame.TitleText
    else
        local edge = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        edge:SetPoint("TOPLEFT", -1, 1)
        edge:SetPoint("BOTTOMRIGHT", 1, -1)
        edge:SetColorTexture(colors.border[1], colors.border[2], colors.border[3], 1)
        local backdrop = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(colors.background[1], colors.background[2], colors.background[3], 1)
        frame.title = Label(frame, "GameFontNormalLarge", colors.accent)
        Paint(function() TextColor(frame.title, colors.accent) end)
        frame.title:SetPoint("TOPLEFT", 10, -11)
        local close = Button(frame, "X", 25, function() frame:Hide() end)
        close:SetPoint("TOPRIGHT", -8, -7)
    end
    frame.title:SetText(title)
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = name end
    return frame
end

addon.Skin = { colors = colors, Label = Label, Button = Button, Window = Window }

local function ProfitText(value)
    local copper = math.floor(value)
    local sign = copper < 0 and "-" or copper > 0 and "+" or ""
    local color = copper < 0 and colors.loss or copper > 0 and colors.gain or colors.text
    return sign .. Money(copper), color
end

local function BagCount(id)
    return C_Item.GetItemCount(id, false, false, true) or 0
end

local function GetSchematic(info)
    if not info.offline then
        local ok, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, info.recipeID, false)
        if ok and schematic and schematic.reagentSlotSchematics then return schematic end
    end
    return addon.OfflineSchematic(info.recipeID)
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

local function AuctionHouseOpen()
    return AuctionHouseFrame ~= nil and AuctionHouseFrame:IsShown()
end

local function Active(isLinked, allowLoading)
    return not failed and page and page:IsVisible() and GetSetting("window")
        and (addon.IsOwnProfession(allowLoading) or isLinked)
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
-- This runs on every refresh because the native page creates controls after it opens.
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
    if not craftingJob then return end
    local text = ("Crafting  %d / %d"):format(craftingJob.done, craftingJob.count)
    if craftingJob.duration and craftingJob.ends then
        local seconds = math.max(0, craftingJob.ends - GetTime())
            + math.max(0, craftingJob.count - craftingJob.done - 1) * craftingJob.duration
        seconds = math.ceil(seconds)
        local time = seconds >= 60 and ("%dm %02ds"):format(math.floor(seconds / 60), seconds % 60) or (seconds .. "s")
        text = text .. "  ·  " .. time .. " remaining"
    end
    return text
end

-- ponytail: every refresh rebuilds the records, so the profit filter and the skill-up
-- sort price every recipe again. Cache quotes per recipe if that shows up in a profile.
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
        for id, data in pairs(addon.RecipeData) do
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
        if a.info.learned and a.info.favorite ~= b.info.favorite then return a.info.favorite == true end
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
    if record.info.learned and not linked and GetSetting("craftCounts") then
        record.bagCrafts, record.merchantCrafts = addon.CraftCounts(schematic, BagCount)
    end
    local quote, revenue = addon.QuoteVendor(schematic, nil, nil, addon.GetWork().owned)
    if quote and revenue and revenue > 0 then
        record.profit = revenue - quote.cost
    end
    if quote then record.netCost = quote.cost - (revenue or 0) end
    if rankInfo then
        record.skillChance = addon.SkillChance(record.info.recipeID,
            (rankInfo.skillLevel or 0) + (rankInfo.skillModifier or 0), record.info.maxTrivialLevel)
    end
    local auction = GetSetting("auctionProfit") and addon.AuctionRevenue(schematic)
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
            if filter == "materials" and info.learned then
                -- Only the main materials count. Reagents that a merchant sells are ignored, because
                -- they are always a short trip away; a recipe made only of those is listed too.
                if record.hasMain == nil then
                    local _, afterMerchant = addon.CraftCounts(GetSchematic(info), BagCount)
                    record.hasMain = afterMerchant == nil or afterMerchant > 0
                end
                show = record.hasMain
            end
            if mode == "skill" then
                PriceRecord(record)
                show = true
            end
            if show then
                if mode == "skill" then
                    entries[#entries + 1] = record
                else
                    local group = not info.learned and "Unlearned" or info.favorite and "Favorites" or record.category
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
    mode = value
    stayInQueue = nil
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
        if not linked and entry.info.learned and C_TradeSkillUI.SetRecipeFavorite then
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
    if entry.bagCrafts then
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
    Paint(function() Fill(row.highlight, colors.accent) end)
    row.highlight:SetAlpha(0.16)
    row.count = Label(row, "GameFontHighlightSmall", colors.text)
    row.count:SetJustifyH("RIGHT")
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.name = Label(row, "GameFontHighlightSmall", colors.text)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.skill = Label(row, "GameFontHighlightSmall", colors.muted)
    row.skill:SetWidth(34)
    row.skill:SetPoint("RIGHT", -6, 0)
    row.skill:SetJustifyH("RIGHT")
    row.ah = Label(row, "GameFontHighlightSmall", colors.text)
    row.ah:SetJustifyH("RIGHT")
    row.ah:SetPoint("RIGHT", row.skill, "LEFT", -5, 0)
    row.profit = Label(row, "GameFontHighlightSmall", colors.text)
    row.profit:SetJustifyH("RIGHT")
    row.profit:SetPoint("RIGHT", row.ah, "LEFT", -5, 0)
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
    local showVendor, showAuction = GetSetting("vendorProfit"), GetSetting("auctionProfit")
    local countWidth = 0
    for index = 1, visible do
        local entry = entries[index + offset]
        local row = rows[index]
        if entry then
            row = row or NewRow(index)
            rows[index] = row
            row.entry = entry
            row.ah:SetWidth(showAuction and 69 or 1)
            row.profit:SetWidth(showVendor and 69 or 1)
            if entry.group then
                Fill(row.background, colors.group)
                row.background:Show()
                row.icon:SetTexture(collapsed[entry.group] and "Interface\\Buttons\\UI-PlusButton-Up"
                    or "Interface\\Buttons\\UI-MinusButton-Up")
                row.count:SetText("")
                row.name:SetText(entry.group)
                TextColor(row.name, colors.gold)
                row.profit:SetText("")
                row.ah:SetText("")
                row.skill:SetText("")
            else
                local info = entry.info
                Fill(row.background, colors.selected)
                row.background:SetShown(selected ~= nil and selected.recipeID == info.recipeID)
                row.icon:SetTexture(info.icon)
                row.name:SetText((info.favorite and "|A:auctionhouse-icon-favorite:12:12|a " or "") .. info.name)
                PriceRecord(entry)
                local nameColor = info.learned and (difficultyColors[info.relativeDifficulty] or colors.text) or colors.muted
                TextColor(row.name, nameColor)
                local counts = ""
                if entry.bagCrafts then
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
                row.profit:SetText(showVendor and text or "")
                TextColor(row.profit, color)
                local ahText, ahColor = "-", colors.muted
                if entry.ahProfit then ahText, ahColor = ProfitText(entry.ahProfit) end
                row.ah:SetText(showAuction and ahText or "")
                TextColor(row.ah, ahColor)
                -- The name color already shows the difficulty, so this column only shows the chance.
                local chance = entry.skillChance
                row.skill:SetText(chance and ("%d%%"):format(math.floor(chance * 100 + 0.5)) or "")
                TextColor(row.skill, chance and chance > 0 and nameColor or colors.muted)
            end
            row:Show()
        elseif row then
            row:Hide()
        end
    end
    -- Keep room for the craft counts even when no visible recipe has one, so the icons
    -- stay in one column while the list scrolls.
    local iconX = GetSetting("craftCounts") and not linked
        and math.min(72, math.max(26, math.ceil(countWidth) + 10)) or 9
    for index = 1, math.min(visible, #rows) do
        local row = rows[index]
        if row:IsShown() then
            local x = row.entry.group and 6 or iconX
            row.count:ClearAllPoints()
            row.count:SetPoint("RIGHT", row, "LEFT", iconX - 5, 0)
            row.icon:ClearAllPoints()
            row.icon:SetPoint("LEFT", x, 0)
            row.name:ClearAllPoints()
            row.name:SetPoint("LEFT", row, "LEFT", x + 21, 0)
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

local function MaterialIDs(amounts)
    local ids = {}
    for id in pairs(amounts) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b) return ItemName(a) < ItemName(b) end)
    return ids
end

-- The shopping list and the queue are lists of lines: a header, a saved craft, a craft step, or a material.
local function AddMaterials(lines, header, amounts)
    if not next(amounts) then return end
    if header then lines[#lines + 1] = { header = header } end
    for _, id in ipairs(MaterialIDs(amounts)) do
        local unitPrice, source = addon.PurchasePrice(id)
        lines[#lines + 1] = {
            itemID = id, icon = C_Item.GetItemIconByID(id),
            text = ("%d x %s"):format(amounts[id], ItemName(id)),
            right = unitPrice and (Money(unitPrice * amounts[id]) .. "  " .. source) or "Price unavailable",
        }
    end
end

-- With `movable`, the lines also get buttons that change the craft's place in the queue.
-- How far the batch is, from 0 to 1, counting the part of the current cast that is done.
local function BatchProgress()
    local job, current = craftingJob, 0
    if job.duration and job.ends and job.duration > 0 then
        current = math.max(0, math.min(1, 1 - (job.ends - GetTime()) / job.duration))
    end
    return math.min(1, (job.done + current) / job.count)
end

-- A craft line shows what it makes: the product's icon, tooltip, and chat link. A recipe with
-- no item, such as an enchant, keeps the spell's icon and tooltip.
local function ProductIcon(recipeID, item)
    return item and C_Item.GetItemIconByID(item) or C_Spell.GetSpellTexture(recipeID)
end

local function AddJobs(lines, jobs, movable)
    for index, job in ipairs(jobs) do
        local schematic = GetSchematic({ recipeID = job.id })
        local item = schematic and schematic.outputItemID
        lines[#lines + 1] = { job = job.id, spellID = job.id, itemID = item, icon = ProductIcon(job.id, item),
            text = ("%d × %s"):format(job.quantity, SpellName(job.id)),
            movable = movable, first = index == 1, last = index == #jobs }
    end
end

local function AddCrafts(lines, steps, right)
    for _, step in ipairs(steps) do
        lines[#lines + 1] = { spellID = step.recipeID, itemID = step.itemID,
            icon = ProductIcon(step.recipeID, step.itemID), right = right,
            text = ("%d × %s"):format(step.batches, step.recipeName or ItemName(step.itemID)) }
    end
end

local function ShoppingLines(info, schematic)
    local lines = {}
    local needs, prerequisites, jobs = addon.ShoppingPlan(BagCount)
    window.needs, window.prerequisites, window.jobs = needs, prerequisites, jobs
    if #jobs > 0 then
        lines[1] = { header = "Saved crafts" }
        AddJobs(lines, jobs)
        local merchant, auction = {}, {}
        for id, quantity in pairs(needs) do
            local _, source = addon.PurchasePrice(id)
            if source == "merchant" then merchant[id] = quantity else auction[id] = quantity end
        end
        AddMaterials(lines, "Buy from a merchant", merchant)
        AddMaterials(lines, "Buy on the Auction House", auction)
        if #prerequisites > 0 then
            lines[#lines + 1] = { header = "Craft first" }
            AddCrafts(lines, prerequisites)
        end
        return next(needs) and "" or "You have the required materials in your bags.", lines
    end
    if not info then return "Select a recipe and add it to the list.", lines end
    local count = Quantity()
    local quote = addon.QuoteVendor(schematic, page.SchematicForm:GetTransaction(), count)
    if quote then
        needs = addon.ShoppingNeeds(quote, BagCount)
    else
        needs = addon.DirectReagents(schematic, count)
        for id, amount in pairs(needs) do
            needs[id] = amount > BagCount(id) and amount - BagCount(id) or nil
        end
    end
    window.needs = needs
    local intro = ("%d %s of %s"):format(count, count == 1 and "craft" or "crafts", info.name)
    if not quote then intro = intro .. "\nSome prices are missing. Showing direct reagents." end
    if not next(needs) then intro = intro .. "\nYou have the required materials in your bags." end
    AddMaterials(lines, nil, needs)
    return intro, lines
end

-- The time the whole queue takes: each craft casts for the recipe's cast time.
local function QueueSeconds(prerequisites, jobs)
    local seconds = 0
    local function Add(id, crafts)
        local info = C_Spell.GetSpellInfo(id)
        seconds = seconds + crafts * ((info and info.castTime or 0) / 1000)
    end
    for _, step in ipairs(prerequisites) do Add(step.recipeID, step.batches) end
    for _, job in ipairs(jobs) do Add(job.id, job.quantity) end
    return seconds
end

local function FormatDuration(seconds)
    seconds = math.ceil(seconds)
    local hours, minutes = math.floor(seconds / 3600), math.floor(seconds % 3600 / 60)
    seconds = seconds % 60
    if hours > 0 then return ("%d h %d min"):format(hours, minutes) end
    if minutes > 0 then return ("%d min %d s"):format(minutes, seconds) end
    return ("%d s"):format(seconds)
end

local function QueueLines()
    local lines = {}
    local needs, prerequisites, jobs = addon.ShoppingPlan(BagCount)
    window.needs, window.prerequisites, window.jobs = needs, prerequisites, jobs
    local notes = {}
    if #jobs == 0 then
        notes[1] = "Add a recipe to the shopping list to queue it."
    else
        AddCrafts(lines, prerequisites, "Reagent")
        AddJobs(lines, jobs, true)
        if next(needs) then notes[1] = "Open the shopping list to see missing materials." end
        local seconds = QueueSeconds(prerequisites, jobs)
        if seconds > 0 then notes[#notes + 1] = "Estimated time: " .. FormatDuration(seconds) end
    end
    if craftingJob then
        notes[#notes + 1] = ("Crafting %d of %d complete"):format(craftingJob.done, craftingJob.count)
    end
    -- What you crafted stays listed until you sell it at a merchant or remove it here.
    local crafted = MaterialIDs(addon.GetWork().crafted)
    if #crafted > 0 then lines[#lines + 1] = { header = "Crafted" } end
    for _, id in ipairs(crafted) do
        local count, price = BagCount(id), select(11, C_Item.GetItemInfo(id)) or 0
        lines[#lines + 1] = { itemID = id, crafted = id, icon = C_Item.GetItemIconByID(id),
            text = ("%d x %s"):format(count, ItemName(id)),
            right = price > 0 and Money(price * count) or "No vendor value" }
    end
    return table.concat(notes, "\n"), lines
end

local function ChangeJob(id, delta)
    local shopping = addon.GetWork().shopping
    local job = shopping[id]
    if not job then return end
    job.quantity = math.min(999, job.quantity + delta)
    if job.quantity <= 0 then shopping[id] = nil end
    DrawDetail()
end

local function ItemTooltip(self)
    local entry = self.entry
    if not (entry.itemID or entry.spellID) then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if entry.itemID then GameTooltip:SetItemByID(entry.itemID) else GameTooltip:SetSpellByID(entry.spellID) end
    for _, line in ipairs(entry.lines or {}) do
        GameTooltip:AddDoubleLine(line[1], line[2], 1, 0.82, 0, 1, 1, 1)
    end
    GameTooltip:Show()
end

-- Shift-click a material to link it in chat, like any other item in the game.
local function LinkItem(self)
    local id = self.entry.itemID
    local link = id and select(2, C_Item.GetItemInfo(id))
    if link then HandleModifiedItemClick(link) end
end

local function LineRow(panel, index)
    local row = CreateFrame("Frame", nil, panel)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * lineHeight)
    row:SetPoint("TOPRIGHT", 0, -(index - 1) * lineHeight)
    row:SetHeight(lineHeight)
    row:EnableMouse(true)
    row:SetScript("OnEnter", ItemTooltip)
    row:SetScript("OnMouseUp", LinkItem)
    row:SetScript("OnLeave", addon.HideRoute)
    row:SetScript("OnHide", addon.HideRoute)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT")
    row.label = Label(row, "GameFontHighlight", colors.text)
    row.right = Label(row, "GameFontHighlightSmall", colors.muted)
    row.right:SetPoint("RIGHT", -3, 0)
    row.remove = Button(row, "X", 22, function()
        if row.entry.job then return ChangeJob(row.entry.job, -999) end
        addon.GetWork().crafted[row.entry.crafted] = nil
        DrawDetail()
    end)
    row.remove:SetPoint("RIGHT", -3, 0)
    row.more = Button(row, "+", 22, function() ChangeJob(row.entry.job, 1) end)
    row.more:SetPoint("RIGHT", row.remove, "LEFT", -8, 0)
    row.less = Button(row, "-", 22, function() ChangeJob(row.entry.job, -1) end)
    row.less:SetPoint("RIGHT", row.more, "LEFT", -2, 0)
    local function MoveButton(direction, texture, anchor, gap)
        local button = Button(row, "", 22, function()
            addon.MoveJob(row.entry.job, direction)
            DrawDetail()
        end)
        button:SetPoint("RIGHT", anchor, "LEFT", gap, 0)
        local arrow = button:CreateTexture(nil, "OVERLAY")
        arrow:SetSize(14, 14)
        arrow:SetPoint("CENTER")
        arrow:SetTexture(texture)
        return button
    end
    row.down = MoveButton(1, "Interface\\Buttons\\Arrow-Down-Up", row.less, -8)
    row.up = MoveButton(-1, "Interface\\Buttons\\Arrow-Up-Up", row.down, -2)
    return row
end

local function DrawLines(lines)
    local panel = window.lines
    panel:SetShown(#lines > 0)
    for index, entry in ipairs(lines) do
        local row = panel.rows[index] or LineRow(panel, index)
        panel.rows[index] = row
        row.entry = entry
        row.icon:SetShown(not entry.header)
        row.icon:SetTexture(entry.icon or 134400)
        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT", entry.header and 0 or 24, 0)
        row.label:SetText(entry.header or entry.text)
        TextColor(row.label, entry.header and colors.gold or colors.text)
        row.right:SetText(entry.right or "")
        row.right:ClearAllPoints()
        row.right:SetPoint("RIGHT", entry.crafted and -33 or -3, 0)
        row.more:SetShown(entry.job ~= nil)
        row.remove:SetShown(entry.job ~= nil or entry.crafted ~= nil)
        row.less:SetShown(entry.job ~= nil)
        row.up:SetShown(entry.movable == true)
        row.down:SetShown(entry.movable == true)
        row.up:SetEnabled(not entry.first)
        row.down:SetEnabled(not entry.last)
        row:Show()
    end
    for index = #lines + 1, #panel.rows do panel.rows[index]:Hide() end
    panel:SetHeight(math.max(1, #lines * lineHeight))
    return #lines > 0 and #lines * lineHeight + 8 or 0
end

local function SetAmount(region, amount)
    region:SetText(amount and Money(amount) or "-")
end

local function DrawSkillBar(info)
    local bar = window.skillRange
    local first, yellow, green, gray
    if info and not linked then
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
    row:SetScript("OnEnter", ItemTooltip)
    row:SetScript("OnMouseUp", LinkItem)
    row:SetScript("OnLeave", addon.HideRoute)
    row:SetScript("OnHide", addon.HideRoute)
    row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.check:SetSize(18, 18)
    row.check:SetPoint("LEFT")
    row.check:SetScript("OnClick", function(check)
        addon.GetWork().owned[row.entry.itemID] = not check:GetChecked() or nil
        QueueRefresh()
    end)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(28, 28)
    row.name = Label(row, "GameFontHighlight", colors.text)
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 7, 0)
    row.required = Label(row, "GameFontHighlightSmall", colors.text)
    row.required:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 7, 0)
    row.bags = Label(row, "GameFontHighlightSmall", colors.muted)
    row.bags:SetPoint("RIGHT", -46, 0)
    row.bank = Label(row, "GameFontHighlightSmall", colors.muted)
    row.bank:SetPoint("RIGHT", -3, 0)
    row.limit = Label(row, "GameFontHighlightSmall", colors.muted)
    row.limit:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 52, 0)
    row.limit:SetPoint("RIGHT", row.bags, "LEFT", -8, 0)
    row.limit:SetJustifyH("LEFT")
    row.limit:SetWordWrap(false)
    return row
end

local function DrawReagents(schematic)
    local panel = window.reagents
    local amounts = addon.DirectReagents(schematic, 1)
    local ids = MaterialIDs(amounts)
    local owned = addon.GetWork().owned
    panel:SetShown(#ids > 0)
    local _, vendorRevenue = addon.QuoteVendor(schematic)
    local forVendor = GetSetting("vendorProfit") and addon.BreakEvenPrices(amounts, owned, vendorRevenue) or {}
    local forAuction = GetSetting("auctionProfit")
        and addon.BreakEvenPrices(amounts, owned, addon.AuctionRevenue(schematic)) or {}
    for index, id in ipairs(ids) do
        local row = panel.rows[index] or ReagentRow(panel, index)
        panel.rows[index] = row
        row.entry = { itemID = id }
        local have, need = BagCount(id), amounts[id]
        row.icon:SetTexture(C_Item.GetItemIconByID(id) or 134400)
        row.icon:SetPoint("LEFT", linked and 0 or 23, 0)
        row.name:SetText(ItemName(id))
        row.required:SetText(("%d/%d"):format(have, need))
        TextColor(row.required, have >= need and colors.text or colors.loss)
        row.check:SetShown(not linked)
        row.check:SetChecked(not owned[id])
        -- A merchant reagent has a fixed price, so it shows that price. Any other reagent shows the
        -- highest price worth paying; the tooltip spells out what AH and Vendor mean.
        local merchant = addon.MerchantPrice(id)
        local limits, lines = {}, {}
        if merchant then
            lines[1] = { "Sold by merchants for", Money(merchant) }
        else
            for _, limit in ipairs({
                { "AH", forAuction[id], "Highest price to pay, if you sell the result on the Auction House" },
                { "Vendor", forVendor[id], "Highest price to pay, if you sell the result to a vendor" },
            }) do
                if limit[2] then
                    local price = limit[2] >= 1 and Money(limit[2]) or "-"
                    limits[#limits + 1] = limit[1] .. " " .. price
                    lines[#lines + 1] = { limit[3], price }
                end
            end
        end
        row.entry.lines = lines
        row.limit:SetText(merchant and ("Merchant  " .. Money(merchant))
            or #limits > 0 and "Max  " .. table.concat(limits, "  ·  ") or "")
        row.bags:SetText(have)
        row.bank:SetText(math.max(0, (C_Item.GetItemCount(id, true, false, true) or have) - have))
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
    if not info.learned then description = "Recipe not learned\n" .. description end
    if C_TradeSkillUI.GetRecipeRequirements and not info.offline and not linked then
        local ok, requirements = pcall(C_TradeSkillUI.GetRecipeRequirements, info.recipeID)
        local names = {}
        for _, req in ipairs(ok and requirements or {}) do
            if req.name then names[#names + 1] = req.met and req.name or ("|cffff7878" .. req.name .. "|r") end
        end
        if #names > 0 then description = description .. "\nRequires: " .. table.concat(names, ", ") end
    end
    local source = addon.RecipeSource(info.recipeID)
    if source then description = description .. "\n" .. source end
    return description
end

DrawDetail = function()
    local info, schematic = SelectedRecipe()
    local shopping, queue, tools = mode == "shopping", mode == "queue", mode == "tools"
    local special = shopping or queue or tools
    for key, tab in pairs(window.tabs) do
        local active = key == mode or (key == "recipes" and not (shopping or queue))
        if tab.inner then
            Fill(tab.inner, active and colors.selected or colors.button)
            TextColor(tab.label, active and colors.accent or colors.text)
        elseif active then
            tab:LockHighlight()
        else
            tab:UnlockHighlight()
        end
    end
    window.detail:SetShown(info ~= nil or special)
    if not info and not special then return end
    window.rightContent:SetWidth(math.max(1, window.rightScroll:GetWidth()))
    schematic = schematic or (info and GetSchematic(info))
    local count = Quantity()
    local learned = info ~= nil and info.learned == true and not linked
    local craftable = learned and page:GetCraftableCount() or 0
    local enchant = not special and learned and info.isEnchantingRecipe == true
    if enchantRecipe ~= (info and info.recipeID) or not enchant
        or (enchantTarget and not C_TradeSkillUI.IsEnchantTargetValid(info.recipeID, enchantTarget)) then
        enchantTarget = nil
    end
    enchantRecipe = info and info.recipeID
    local showBar = DrawSkillBar(not special and info or nil)
    window.rightScroll:SetPoint("TOPLEFT", 12, showBar and -115 or -65)
    if special then
        window.rightScroll:SetPoint("BOTTOMRIGHT", -32, 42)
    else
        window.rightScroll:SetPoint("BOTTOMRIGHT", window.addShopping, "TOPRIGHT", -20, enchant and 22 or 10)
    end

    window.recipeName:SetText(shopping and "Shopping list"
        or queue and "Crafting queue" or tools and "Profession tools" or info.name)
    window.recipeIcon:SetTexture(not special and info.icon or 134400)
    window.iconHover.entry = { info = not special and info or nil }
    window.favorite:SetShown(learned and not special)
    window.favorite.star:SetAtlas(info and info.favorite and "auctionhouse-icon-favorite" or "auctionhouse-icon-favorite-off")
    window.track:SetShown(learned and not special)
    if window.track:IsShown() then
        window.track:SetChecked(C_TradeSkillUI.IsRecipeTracked(info.recipeID, false))
    end
    window.profitPanel:SetShown(not special)
    window.addShopping:SetShown(not special and schematic ~= nil)
    window.create:SetShown(not special and not linked)
    window.createAll:SetShown(not special and not linked)
    window.create:SetEnabled(learned and page.CreateButton:IsEnabled() and count <= craftable)
    window.createAll:SetEnabled(learned and page.CreateAllButton:IsEnabled() and craftable > 0)
    window.createAll.label:SetText(("Create all (%d)"):format(craftable))
    window.enchantSlot:SetShown(enchant)
    window.create.label:SetText(enchant and "Enchant" or "Create")
    if enchant then
        local item = enchantTarget and Item:CreateFromItemGUID(enchantTarget)
        local slot = window.enchantSlot
        slot.icon:SetTexture(item and item:GetItemIcon() or 134400)
        slot.label:SetText(item and ("1/1 " .. (item:GetItemLink() or item:GetItemName() or ""))
            or "Optional target: click to choose an item")
        window.create:SetEnabled(craftable > 0)
        window.createAll:Hide()
    end
    window.quantity:SetShown(not (queue or tools))
    window.lessQuantity:SetShown(not (queue or tools))
    window.moreQuantity:SetShown(not (queue or tools))
    window.searchPrices:SetShown(shopping and AuctionHouseOpen())
    window.searchRecipe:SetShown(not special and schematic ~= nil and AuctionHouseOpen())
    window.maxQuantity:SetShown(not special and learned)
    window.buy:SetShown(shopping and (AuctionHouseOpen() or (MerchantFrame ~= nil and MerchantFrame:IsShown())))
    window.queueNext:SetShown(queue)
    window.sell:SetShown(queue and MerchantFrame ~= nil and MerchantFrame:IsShown()
        and next(addon.GetWork().crafted) ~= nil)

    local text, lines, reagentsHeight = "", {}, 0
    if shopping then
        text, lines = ShoppingLines(info, schematic)
    elseif queue then
        text, lines = QueueLines()
    elseif tools then
        text = addon.ToolText(window.tool)
    else
        text = RecipeDescription(info)
    end
    window.materials:SetText(text)
    if special then window.reagents:Hide() else reagentsHeight = DrawReagents(schematic) end
    local linesHeight = DrawLines(lines)
    window.rightContent:SetHeight(math.max(1, window.materials:GetStringHeight() + reagentsHeight + linesHeight + 12))
    if special then return end

    local transaction = not window.preview and page.SchematicForm:GetTransaction() or nil
    local quote, revenue = addon.QuoteVendor(schematic, transaction, nil, addon.GetWork().owned)
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

    local showAuction = GetSetting("auctionProfit")
    window.profitPanel:SetHeight(showAuction and 93 or 57)
    local auction, gross
    if showAuction then auction, gross = addon.AuctionRevenue(schematic) end
    local result = auction and quote and auction - quote.cost
    local ahText, ahColor = "-", colors.muted
    if result then ahText, ahColor = ProfitText(result) end
    if result and quote.cost > 0 then
        ahText = ahText .. ("  (%+.0f%% ROI)"):format(result * 100 / quote.cost)
    end
    window.auctionLine:SetShown(showAuction)
    window.auctionValue:SetShown(showAuction)
    window.auctionSaleLabel:SetShown(showAuction)
    window.auctionSale:SetShown(showAuction)
    SetAmount(window.auctionSale, gross)
    window.auctionValue:SetText(ahText)
    TextColor(window.auctionValue, ahColor)
end

local function OpenEnchantTargets(button, mouse)
    local info = SelectedRecipe()
    if not info then return end
    if mouse == "RightButton" then
        enchantTarget = nil
        return QueueRefresh()
    end
    MenuUtil.CreateContextMenu(button, function(_, menu)
        local guids = C_TradeSkillUI.GetEnchantItems(info.recipeID)
        if #guids == 0 then menu:CreateTitle("None of your items take this enchant.") end
        for _, guid in ipairs(guids) do
            local item = Item:CreateFromItemGUID(guid)
            menu:CreateButton(item:GetItemLink() or item:GetItemName() or "Item", function()
                enchantTarget = guid
                QueueRefresh()
            end)
        end
    end)
end

local function Craft(all)
    if linked or craftingJob or InCombatLockdown() or not Active(linked) then return end
    local info = SelectedRecipe()
    if not info or not info.learned then return end
    local craftable = page:GetCraftableCount()
    if info.isEnchantingRecipe then
        -- An enchant goes on one item. With a chosen item it casts at once and the choice stays for the
        -- next cast; without one the game opens its targeting cursor.
        if all or craftable < 1 then return end
        local ok, err
        if enchantTarget and C_TradeSkillUI.IsEnchantTargetValid(info.recipeID, enchantTarget) then
            craftingJob = { id = info.recipeID, count = 1, done = 0 }
            ok, err = pcall(C_TradeSkillUI.CraftEnchant, info.recipeID, 1, nil, C_Item.GetItemLocation(enchantTarget))
            if not ok then craftingJob = nil end
        else
            ok, err = pcall(C_TradeSkillUI.CraftRecipe, info.recipeID, 1)
        end
        if not ok then print("Easy Crafting: could not enchant: " .. tostring(err)) end
        QueueRefresh()
        return
    end
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
        print("Easy Crafting: this profession has no chat link.")
        return
    end
    if not ChatEdit_InsertLink(link) then ChatFrame_OpenChat(link) end
end

local function SearchPrices()
    local _, schematic = SelectedRecipe()
    local items = addon.PriceCandidates(schematic)
    for id in pairs(window.needs or {}) do items[id] = true end
    for _, job in ipairs(window.jobs or {}) do
        for id in pairs(addon.PriceCandidates(addon.OfflineSchematic(job.id))) do items[id] = true end
    end
    addon.SearchMaterials(items)
end

local function BuyMaterials()
    if AuctionHouseOpen() then
        local needed = {}
        for id, count in pairs(window.needs or {}) do
            local _, source = addon.PurchasePrice(id)
            if source ~= "merchant" then needed[id] = count end
        end
        addon.SearchMaterials(needed)
        return
    end
    -- With shift, buy the full amount of each material; without it, at most one stack of each.
    local all = IsShiftKeyDown()
    local offers = addon.MerchantOffers(window.needs or {}, all)
    if #offers == 0 then
        print("Easy Crafting: this merchant has none of the materials on your list.")
        return
    end
    -- The dialog lists every purchase and the total, so the player sees what Buy does.
    local dialog = window.buyDialog
    if not dialog then
        dialog = Window("EasyCraftingBuyConfirm", 340, 120, "Buy from this merchant")
        window.buyDialog = dialog
        dialog.list = Label(dialog, "GameFontHighlight", colors.text)
        dialog.list:SetPoint("TOPLEFT", 14, -44)
        dialog.list:SetPoint("RIGHT", -14, 0)
        dialog.list:SetJustifyH("LEFT")
        dialog.list:SetSpacing(4)
        local buy = Button(dialog, "Buy materials", 110, function()
            local approved = dialog.approved
            dialog:Hide()
            if not (MerchantFrame and MerchantFrame:IsShown()) then return end
            -- Buy only if the merchant still offers exactly what the dialog listed.
            local current = addon.MerchantOffers(approved.needs, approved.all)
            local same = #current == #approved.offers
            for index, offer in ipairs(current) do
                local expected = approved.offers[index]
                same = same and expected ~= nil and offer.id == expected.id and offer.index == expected.index
                    and offer.total == expected.total and offer.quantity == expected.quantity
            end
            if not same then
                print("Easy Crafting: the merchant's offers changed. Review the purchases again.")
            elseif GetMoney() < approved.total then
                print("Easy Crafting: you don't have enough money for these materials.")
            else
                for _, offer in ipairs(current) do
                    addon.BuyPaced(offer.index, offer.id, offer.quantity, offer.perCall)
                end
                QueueRefresh()
            end
        end)
        buy:SetPoint("BOTTOMRIGHT", -14, 12)
        local cancel = Button(dialog, "Cancel", 90, function() dialog:Hide() end)
        cancel:SetPoint("RIGHT", buy, "LEFT", -6, 0)
    end
    local total, lines = 0, {}
    for _, offer in ipairs(offers) do
        total = total + offer.total
        lines[#lines + 1] = ("%d x %s  |cff9eaab5%s|r"):format(offer.quantity, ItemName(offer.id), Money(offer.total))
    end
    lines[#lines + 1] = "\nTotal  " .. Money(total)
    dialog.list:SetText(table.concat(lines, "\n"))
    dialog.approved = { needs = window.needs, offers = offers, total = total, all = all }
    dialog:SetHeight(112 + #offers * 18)
    dialog:Show()
    dialog:Raise()
end

-- Sells every stack of the items you crafted, after a dialog that lists them and the total.
local function SellCrafts()
    local function Totals()
        local stacks, counts, values, total = addon.CraftedStacks(), {}, {}, 0
        for _, stack in ipairs(stacks) do
            counts[stack.id] = (counts[stack.id] or 0) + stack.count
            values[stack.id] = (values[stack.id] or 0) + stack.value
            total = total + stack.value
        end
        return stacks, counts, values, total
    end
    local stacks, counts, values, total = Totals()
    if #stacks == 0 then
        print("Easy Crafting: none of your crafted items are in your bags.")
        return
    end
    local dialog = window.sellDialog
    if not dialog then
        dialog = Window("EasyCraftingSellConfirm", 340, 120, "Sell to this merchant")
        window.sellDialog = dialog
        dialog.list = Label(dialog, "GameFontHighlight", colors.text)
        dialog.list:SetPoint("TOPLEFT", 14, -44)
        dialog.list:SetPoint("RIGHT", -14, 0)
        dialog.list:SetJustifyH("LEFT")
        dialog.list:SetSpacing(4)
        local sell = Button(dialog, "Sell items", 100, function()
            dialog:Hide()
            if not (MerchantFrame and MerchantFrame:IsShown()) then return end
            -- Sell only if the bags still hold what the dialog listed.
            local current, _, _, value = Totals()
            if value ~= dialog.total then
                print("Easy Crafting: your bags changed. Open Sell crafts again.")
                return
            end
            local crafted = addon.GetWork().crafted
            for _, stack in ipairs(current) do
                C_Container.UseContainerItem(stack.bag, stack.slot)
                crafted[stack.id] = nil
            end
            QueueRefresh()
        end)
        sell:SetPoint("BOTTOMRIGHT", -14, 12)
        local cancel = Button(dialog, "Cancel", 90, function() dialog:Hide() end)
        cancel:SetPoint("RIGHT", sell, "LEFT", -6, 0)
    end
    local lines = {}
    for _, id in ipairs(MaterialIDs(counts)) do
        lines[#lines + 1] = ("%d x %s  |cff9eaab5%s|r"):format(counts[id], ItemName(id), Money(values[id]))
    end
    dialog.total = total
    dialog.list:SetText(table.concat(lines, "\n") .. "\n\nTotal  " .. Money(total))
    dialog:SetHeight(112 + #lines * 18)
    dialog:Show()
    dialog:Raise()
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
    -- A craft from another profession opens that profession. Crafting needs a click of its own,
    -- so the queue stays open for the next click on Craft next.
    local data = addon.RecipeData[nextJob.id]
    if data and data.line ~= professionID then
        if C_TradeSkillUI.OpenTradeSkill then
            stayInQueue = true
            C_TradeSkillUI.OpenTradeSkill(data.line)
            print("Easy Crafting: opening the profession for " .. SpellName(nextJob.id) .. ". Click Craft next again.")
        else
            print("Easy Crafting: open the profession for " .. SpellName(nextJob.id) .. ".")
        end
        return
    end
    local info = C_TradeSkillUI.GetRecipeInfo(nextJob.id)
    if not info or not info.learned or (not data and C_TradeSkillUI.IsRecipeInSkillLine
        and not C_TradeSkillUI.IsRecipeInSkillLine(nextJob.id, professionID)) then
        print("Easy Crafting: open the profession for " .. SpellName(nextJob.id) .. ".")
        return
    end
    window.preview = nil
    page:SelectRecipe(info)
    local count = math.min(nextJob.quantity, page:GetCraftableCount())
    if count <= 0 or not page.CreateButton:IsEnabled() then
        print("Easy Crafting: check the recipe's materials and crafting requirements.")
        return
    end
    craftingJob = { id = nextJob.id, count = count, done = 0 }
    page.CreateMultipleInputBox:SetValue(count)
    page:Create()
    QueueRefresh()
end

local function OpenTools(button)
    MenuUtil.CreateContextMenu(button, function(_, menu)
        local info, schematic = SelectedRecipe()
        for _, entry in ipairs(addon.ToolEntries(schematic or (info and GetSchematic(info)))) do
            local key = entry[1]
            menu:CreateButton(entry[2], function()
                window.tool = key
                SetMode("tools")
            end)
        end
    end)
end

local function OpenFilter(button)
    MenuUtil.CreateContextMenu(button, function(_, menu)
        for _, option in ipairs({
            { "all", "All recipes" }, { "learned", "Learned recipes" },
            { "favorites", "Favorites" }, { "profit", "Vendor profit above zero" },
            { "materials", "Have Material" },
            { "skill", "Best for skill-ups" },
        }) do
            local key, label = unpack(option)
            menu:CreateRadio(label, function()
                if mode == "skill" or key == "skill" then return mode == key end
                return filter == key
            end, function()
                if key ~= "skill" then filter = key end
                SetMode(key == "skill" and "skill" or "recipes")
            end)
        end
    end)
end

local function BuildList()
    local search = CreateFrame("EditBox", nil, window, "SearchBoxTemplate")
    window.search = search
    search:SetSize(listWidth - 76, 24)
    search:SetPoint("TOPLEFT", 8, -67)
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
    window.columnAH:SetPoint("RIGHT", -57, 0)
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
    window.empty = Label(list, "GameFontHighlightSmall", colors.muted)
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
    Paint(function() Fill(thumb, colors.bar) end)
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
    detail:SetPoint("TOPLEFT", listWidth + 16, -67)
    detail:SetPoint("BOTTOMRIGHT", -8, 8)
    Surface(detail, "BACKGROUND", colors.panel)
    window.recipeIcon = detail:CreateTexture(nil, "ARTWORK")
    window.recipeIcon:SetSize(42, 42)
    window.recipeIcon:SetPoint("TOPLEFT", 12, -12)
    -- Hover the icon for the crafted item's tooltip; shift-click it to link the item in chat.
    local iconHover = CreateFrame("Button", nil, detail)
    window.iconHover = iconHover
    iconHover:SetAllPoints(window.recipeIcon)
    iconHover:RegisterForClicks("LeftButtonUp")
    iconHover:SetScript("OnEnter", HoverRow)
    iconHover:SetScript("OnLeave", addon.HideRoute)
    iconHover:SetScript("OnHide", addon.HideRoute)
    iconHover:SetScript("OnClick", function(self)
        local info = self.entry.info
        local link = info and C_TradeSkillUI.GetRecipeItemLink and C_TradeSkillUI.GetRecipeItemLink(info.recipeID)
        if link then HandleModifiedItemClick(link) end
    end)
    window.recipeName = Label(detail, "GameFontNormalLarge", colors.text)
    window.recipeName:SetPoint("TOPLEFT", window.recipeIcon, "TOPRIGHT", 8, -1)
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
    window.favorite:SetPoint("TOPRIGHT", -12, -12)
    window.favorite.star = window.favorite:CreateTexture(nil, "OVERLAY")
    window.favorite.star:SetSize(16, 16)
    window.favorite.star:SetPoint("CENTER")
    window.track = CreateFrame("CheckButton", nil, detail, "UICheckButtonTemplate")
    window.track:SetSize(22, 22)
    window.track:SetPoint("TOPRIGHT", -44, -12)
    local track = Label(window.track, "GameFontHighlightSmall", colors.muted)
    track:SetPoint("RIGHT", window.track, "LEFT", -4, 0)
    track:SetText("Track recipe")
    window.track:SetScript("OnClick", function(self)
        local info = SelectedRecipe()
        if info then C_TradeSkillUI.SetRecipeTracked(info.recipeID, self:GetChecked(), false) end
    end)

    local range = CreateFrame("Frame", nil, detail)
    window.skillRange = range
    range:SetPoint("TOPLEFT", 12, -64)
    range:SetPoint("TOPRIGHT", -24, -64)
    range:SetHeight(42)
    range.segments, range.labels = {}, {}
    for index = 1, 4 do
        local segment = range:CreateTexture(nil, "ARTWORK")
        segment:SetHeight(9)
        Fill(segment, difficultyColors[index - 1])
        range.segments[index] = segment
        range.labels[index] = Label(range, "GameFontHighlightSmall", colors.muted)
    end
    range.marker = range:CreateTexture(nil, "OVERLAY")
    range.marker:SetSize(2, 13)
    Fill(range.marker, colors.text)
    range.chance = Label(range, "GameFontHighlightSmall", colors.text)
    range.chance:SetPoint("TOPRIGHT", 0, -28)

    local scroll = CreateFrame("ScrollFrame", nil, detail)
    window.rightScroll = scroll
    scroll:SetPoint("TOPLEFT", 12, -65)
    scroll:SetPoint("BOTTOMRIGHT", -32, 165)
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
    scroll:SetScript("OnSizeChanged", function(_, width) content:SetWidth(math.max(1, width)) end)

    local reagents = CreateFrame("Frame", nil, content)
    window.reagents = reagents
    reagents:SetPoint("TOPLEFT", window.materials, "BOTTOMLEFT", 0, -12)
    reagents:SetPoint("TOPRIGHT", window.materials, "BOTTOMRIGHT", 0, -12)
    reagents:SetHeight(1)
    reagents.rows = {}
    local reagentTitle = Label(reagents, "GameFontNormal", colors.gold)
    reagentTitle:SetPoint("TOPLEFT")
    reagentTitle:SetText("Reagents")
    local bags = Label(reagents, "GameFontHighlightSmall", colors.muted)
    bags:SetPoint("TOPRIGHT", -46, 0)
    bags:SetText("Bags")
    local bank = Label(reagents, "GameFontHighlightSmall", colors.muted)
    bank:SetPoint("TOPRIGHT", -3, 0)
    bank:SetText("Bank")

    local lines = CreateFrame("Frame", nil, content)
    window.lines = lines
    lines:SetPoint("TOPLEFT", window.materials, "BOTTOMLEFT", 0, -8)
    lines:SetPoint("TOPRIGHT", window.materials, "BOTTOMRIGHT", 0, -8)
    lines:SetHeight(1)
    lines.rows = {}

    local totals = CreateFrame("Frame", nil, detail)
    window.profitPanel = totals
    totals:SetPoint("BOTTOMLEFT", 12, 43)
    totals:SetPoint("BOTTOMRIGHT", -12, 43)
    totals:SetHeight(93)
    local totalsBackground = totals:CreateTexture(nil, "BACKGROUND")
    totalsBackground:SetPoint("TOPLEFT", -5, 4)
    totalsBackground:SetPoint("BOTTOMRIGHT", 5, -2)
    Fill(totalsBackground, colors.background)
    local function AmountRow(label, y, parent)
        parent = parent or totals
        local title = Label(parent, "GameFontNormalSmall", colors.gold)
        title:SetPoint("TOPLEFT", 0, y)
        title:SetText(label)
        local value = Label(parent, "GameFontHighlight", colors.text)
        value:SetPoint("TOPLEFT", 156, y)
        return value, title
    end
    window.cost = AmountRow("Buy for", -2)
    window.revenue = AmountRow("Sell to vendor for", -20)
    local hover = CreateFrame("Frame", nil, totals)
    window.profitHover = hover
    hover:SetPoint("TOPLEFT", 0, -38)
    hover:SetPoint("TOPRIGHT", 0, -38)
    hover:SetHeight(18)
    hover:EnableMouse(true)
    hover:SetScript("OnEnter", addon.ShowRoute)
    hover:SetScript("OnLeave", addon.HideRoute)
    hover:SetScript("OnHide", addon.HideRoute)
    window.profitValue, window.profitLabel = AmountRow("Profit to vendor", 0, hover)
    window.auctionSale, window.auctionSaleLabel = AmountRow("Sell on auction for", -56)
    window.auctionValue, window.auctionLine = AmountRow("Auction profit after cut", -74)

    window.create = Button(detail, "Create", 88, function() Craft(false) end)
    window.create:SetPoint("BOTTOMRIGHT", -12, 9)
    window.createAll = Button(detail, "Create all", 112, function() Craft(true) end)
    window.createAll:SetPoint("BOTTOMLEFT", 12, 9)
    window.searchPrices = Button(detail, "Search prices", 112, SearchPrices)
    window.searchPrices:SetPoint("BOTTOMRIGHT", -12, 9)
    window.buy = Button(detail, "Review purchases", 126, BuyMaterials)
    window.buy:SetPoint("BOTTOMLEFT", 12, 9)
    window.buy:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Review purchases")
        GameTooltip:AddLine("Lists what this merchant sells from your list, up to one stack of each.", 1, 1, 1, true)
        GameTooltip:AddLine("Shift-click: the full amount of each material.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    window.buy:SetScript("OnLeave", addon.HideRoute)
    window.queueNext = Button(detail, "Craft next", 110, CraftNext)
    window.queueNext:SetPoint("BOTTOMRIGHT", -12, 9)
    window.sell = Button(detail, "Sell crafts", 100, SellCrafts)
    window.sell:SetPoint("BOTTOMLEFT", 12, 9)
    window.addShopping = Button(detail, "Add to list", 88, function()
        local info, schematic = SelectedRecipe()
        if not info then return end
        addon.AddToShopping(info.recipeID, Quantity(), schematic or GetSchematic(info))
        SetMode("shopping")
    end)
    window.addShopping:SetPoint("BOTTOMRIGHT", totals, "TOPRIGHT", 0, 5)
    local slot = CreateFrame("Button", nil, detail)
    window.enchantSlot = slot
    slot:SetSize(28, 28)
    slot:SetPoint("BOTTOMLEFT", totals, "TOPLEFT", 0, 5)
    slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    Surface(slot, "BACKGROUND", colors.border)
    slot.icon = slot:CreateTexture(nil, "ARTWORK")
    slot.icon:SetPoint("TOPLEFT", 1, -1)
    slot.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    slot.label = Label(slot, "GameFontHighlightSmall", colors.text)
    slot.label:SetPoint("LEFT", slot, "RIGHT", 8, 0)
    slot:SetScript("OnClick", OpenEnchantTargets)
    slot:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Item to enchant")
        GameTooltip:AddLine("Click to choose the item. Enchant then casts on it, and it stays chosen for the next cast. "
            .. "Right-click to clear it and use the targeting cursor.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    slot:SetScript("OnLeave", addon.HideRoute)

    local qty = CreateFrame("EditBox", nil, detail, "InputBoxTemplate")
    window.quantity = qty
    qty:SetSize(36, 22)
    qty:SetPoint("BOTTOM", 9, 9)
    qty:SetAutoFocus(false)
    qty:SetNumeric(true)
    qty:SetMaxLetters(3)
    qty:SetText("1")
    qty:SetScript("OnTextChanged", function() if window:IsShown() then DrawDetail() end end)
    qty:SetScript("OnEditFocusLost", function(self) self:SetText(tostring(Quantity())) end)
    qty:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    qty:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local less = Button(detail, "-", 22, function() qty:SetText(tostring(math.max(1, Quantity() - 1))) end)
    less:SetPoint("RIGHT", qty, "LEFT", -8, 0)
    local more = Button(detail, "+", 22, function() qty:SetText(tostring(math.min(999, Quantity() + 1))) end)
    more:SetPoint("LEFT", qty, "RIGHT", 4, 0)
    window.lessQuantity, window.moreQuantity = less, more
    window.maxQuantity = Button(detail, "Max", 40, function()
        local most = page:GetCraftableCount()
        if IsShiftKeyDown() then
            -- Count by the material you have the most of, for planning what to buy.
            local info, schematic = SelectedRecipe()
            most = 0
            for id, amount in pairs(addon.DirectReagents(schematic or (info and GetSchematic(info)), 1)) do
                most = math.max(most, math.floor(BagCount(id) / amount))
            end
        end
        qty:SetText(tostring(math.max(1, math.min(999, most))))
    end)
    window.maxQuantity:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Max")
        GameTooltip:AddLine("Sets the amount you can craft with the materials in your bags.", 1, 1, 1, true)
        GameTooltip:AddLine("Shift-click: the amount your most plentiful material allows.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    window.maxQuantity:SetScript("OnLeave", addon.HideRoute)
    window.maxQuantity:SetPoint("LEFT", more, "RIGHT", 4, 0)
    -- Auctionator's own search button sits on the hidden native page, so the window has one too.
    window.searchRecipe = Button(detail, "Search on AH", 100, function()
        local info, schematic = SelectedRecipe()
        schematic = schematic or (info and GetSchematic(info))
        -- Search what the cheapest route buys on the AH for the full quantity, ignoring bag stock,
        -- so you can buy more than you hold.
        local needs = addon.PlanShopping(addon.DirectReagents(schematic, Quantity()), function() return 0 end)
        local buy = {}
        for id, count in pairs(needs) do
            local _, source = addon.PurchasePrice(id)
            if source ~= "merchant" then buy[id] = count end
        end
        -- Nothing to buy (all owned, or all from merchants): still search the direct reagents.
        addon.SearchMaterials(next(buy) and buy or addon.DirectReagents(schematic, Quantity()))
    end)
    window.searchRecipe:SetPoint("RIGHT", window.addShopping, "LEFT", -6, 0)
end

-- An addon can't hide the profession frame in combat. Hide only this window there, leave the
-- native frame open but invisible, and close it when combat ends.
local function CloseProfession()
    if InCombatLockdown() then
        dismissed = true
        window:Hide()
    else
        HideUIPanel(native)
    end
end

local function BuildWindow()
    ApplySkin()
    -- Blizzard's frame has its own title bar, so the content starts below it.
    local top = blizzard and 22 or 0
    window = CreateFrame("Frame", "EasyCraftingProfessionWindow", UIParent, blizzard and "BasicFrameTemplateWithInset" or nil)
    window.top = top
    window:Hide()
    window:SetSize(828, 620)
    -- Sit in the same layer as the profession frame it replaces, and come to the front as one
    -- piece when clicked, like any other game window.
    window:SetFrameStrata(native:GetFrameStrata())
    window:SetToplevel(true)
    window:SetMovable(true)
    window:SetClampedToScreen(true)
    window:SetClampRectInsets(0, -34, 0, 0)
    local position = EasyCraftingSettings.position
    if position then
        window:SetPoint(position.point, UIParent, position.relative, position.x, position.y)
    else
        window:SetPoint("CENTER")
    end
    local scale = math.min(1, (UIParent:GetWidth() - 62) / 828, (UIParent:GetHeight() - 22) / 620)
    window:SetScale(math.max(0.4, scale))
    window:EnableMouse(true)
    local settings = Button(window, "Settings", 70, addon.OpenSettings)
    if blizzard then
        window.title = window.TitleText
        window.CloseButton:SetScript("OnClick", CloseProfession)
        settings:SetPoint("TOPRIGHT", -10, -7 - top)
    else
        Surface(window, "BACKGROUND", colors.background)
        window.title = Label(window, "GameFontNormalLarge", colors.accent)
        Paint(function() TextColor(window.title, colors.accent) end)
        window.title:SetPoint("TOPLEFT", 10, -11)
        local close = Button(window, "X", 25, CloseProfession)
        close:SetPoint("TOPRIGHT", -8, -7)
        settings:SetPoint("RIGHT", close, "LEFT", -6, 0)
    end
    local tools = Button(window, "Tools", 58, OpenTools)
    tools:SetPoint("RIGHT", settings, "LEFT", -6, 0)
    local link = Button(window, "Link", 44, LinkProfession)
    link:SetPoint("RIGHT", tools, "LEFT", -6, 0)

    local drag = CreateFrame("Frame", nil, window)
    drag:SetPoint("TOPLEFT")
    if blizzard then
        drag:SetPoint("TOPRIGHT", -28, 0)
    else
        drag:SetPoint("TOPRIGHT", link, "TOPLEFT", -6, 7)
    end
    drag:SetHeight(blizzard and 22 or 34)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() if not InCombatLockdown() then window:StartMoving() end end)
    drag:SetScript("OnDragStop", function()
        window:StopMovingOrSizing()
        local point, _, relative, x, y = window:GetPoint()
        EasyCraftingSettings.position = { point = point, relative = relative, x = x, y = y }
    end)

    -- The three views are tabs, so the current one is always visible. They sit above the drag area.
    window.tabs = {}
    local previous
    for _, tab in ipairs({ { "recipes", "Recipes", 74 }, { "shopping", "Shopping list", 98 }, { "queue", "Queue", 64 } }) do
        local key = tab[1]
        local button = Button(window, tab[2], tab[3], function() SetMode(key) end)
        if previous then button:SetPoint("LEFT", previous, "RIGHT", 4, 0) else button:SetPoint("TOPLEFT", blizzard and 10 or 150, -7 - top) end
        button:SetFrameLevel(drag:GetFrameLevel() + 2)
        window.tabs[key] = button
        previous = button
    end

    window.skill = CreateFrame("StatusBar", nil, window)
    window.skill:SetPoint("TOPLEFT", 8, -39 - top)
    window.skill:SetPoint("TOPRIGHT", -8, -39 - top)
    window.skill:SetHeight(17)
    Surface(window.skill, "BACKGROUND", colors.group)
    window.skill:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    Paint(function() window.skill:SetStatusBarColor(unpack(colors.bar)) end)
    window.skill.label = Label(window.skill, "GameFontHighlightSmall", colors.text)
    window.skill.label:SetPoint("CENTER")
    -- The band is a progress bar: its fill grows behind the text as the batch runs.
    window.batchBand = CreateFrame("StatusBar", nil, window)
    window.batchBand:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    Paint(function() window.batchBand:SetStatusBarColor(colors.bar[1], colors.bar[2], colors.bar[3], 0.45) end)
    window.batchBand:SetMinMaxValues(0, 1)
    window.batchBand:SetPoint("TOPLEFT", 8, -62 - top)
    window.batchBand:SetPoint("TOPRIGHT", -8, -62 - top)
    window.batchBand:SetHeight(34)
    Surface(window.batchBand, "BACKGROUND", colors.banner)
    window.batch = Label(window.batchBand, "GameFontHighlight", colors.text)
    window.batch:SetPoint("LEFT", 8, 0)
    window:SetScript("OnUpdate", function(self, elapsed)
        if not craftingJob then return end
        self.batchBand:SetValue(BatchProgress())
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
            dismissed = nil
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
    if not page or dismissed then return end
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
        mode, filter, offset = stayInQueue and "queue" or "recipes", "all", 0
        stayInQueue = nil
        collapsed = {}
        window.search:SetText("")
    end
    local child = C_TradeSkillUI.GetChildProfessionInfo and C_TradeSkillUI.GetChildProfessionInfo()
    rankInfo = child and (child.maxSkillLevel or 0) > 0 and child or info
    local skill, maximum = rankInfo.skillLevel or 0, rankInfo.maxSkillLevel or 0
    if mode == "tools" and (window.tool or ""):match("^alt:") and not GetSetting("altProfessions") then
        mode = "recipes"
    end
    local showAuction = GetSetting("auctionProfit")
    window.columnAH:SetShown(showAuction)
    window.columnVendor:ClearAllPoints()
    window.columnVendor:SetPoint("RIGHT", showAuction and -131 or -57, 0)
    window.columnVendor:SetShown(GetSetting("vendorProfit"))
    window.title:SetText(info.professionName)
    window.skill:SetMinMaxValues(0, math.max(1, maximum))
    window.skill:SetValue(skill)
    window.skill.label:SetText(("%s %d/%d"):format(info.professionName, skill, maximum))
    local batchText = BatchText()
    window.batchBand:SetShown(batchText ~= nil)
    window.batch:SetText(batchText or "")
    if craftingJob then window.batchBand:SetValue(BatchProgress()) end
    local bodyY = (batchText and -105 or -67) - window.top
    window.search:SetPoint("TOPLEFT", 8, bodyY)
    window.detail:SetPoint("TOPLEFT", listWidth + 16, bodyY)
    ReadRecipes()
    ListEntries()
    DrawDetail()
    if not linked and GetSetting("altProfessions") then
        addon.RememberProfession(professionID, info.professionName, skill, maximum, records)
    end
    if not window:IsShown() then
        window:Show()
        window:Raise()
    end
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
        EasyCraftingSettings = EasyCraftingSettings or {}
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
        local made = GetSchematic({ recipeID = spellID })
        if made and made.outputItemID then addon.GetWork().crafted[made.outputItemID] = true end
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
    elseif event == "PLAYER_REGEN_ENABLED" and dismissed then
        dismissed = nil
        HideUIPanel(native)
    elseif event == "TRADE_SKILL_CLOSE" or event == "PLAYER_REGEN_ENABLED"
        or (page and page:IsVisible()) then
        QueueRefresh()
    end
end)

SLASH_EASYCRAFTINGWINDOW1 = "/easycrafting"
SlashCmdList.EASYCRAFTINGWINDOW = function()
    addon.SetSetting("window", not GetSetting("window"))
    print(GetSetting("window") and "Easy Crafting: custom profession window." or "Easy Crafting: standard profession window.")
end
