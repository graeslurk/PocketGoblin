-- Pocket Goblin's panel next to the vendor window: a "Sell junk" button
-- with what it would sell, an auto-sell suggestion for items you keep
-- selling yourself, what you can buy back (a button each, or all at once),
-- and what this visit earned.

local ADDON_NAME, ns = ...
local L = ns.L

local WIDTH = 270
local HEADER_HEIGHT = 44
local SELL_HEIGHT = 56     -- junk summary and the Sell junk button
local SUGGEST_HEIGHT = 104 -- "auto-sell this?" suggestion, when there is one
local SECTION_HEIGHT = 30  -- "BUY BACK" heading and the Buy back all button
local ROW_HEIGHT = 28
local FOOTER_HEIGHT = 36
local MAX_ROWS = 12 -- the vendor's buyback list holds 12 items

local panel
local rows = {}
local dismissed = false -- closed with the X for this vendor visit

local function QualityColor(quality)
    local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    return color and { color.r, color.g, color.b } or ns.UI.C.muted
end

local function CreateRow()
    local UI = ns.UI
    local row = CreateFrame("Frame", nil, panel)
    row:SetHeight(ROW_HEIGHT)
    row:EnableMouse(true)

    local hover = UI.Rounded(row, "BACKGROUND", { 1, 1, 1, 0.045 })
    hover:Hide()

    row.border = row:CreateTexture(nil, "ARTWORK", nil, 1)
    row.border:SetSize(22, 22)
    row.border:SetPoint("LEFT", 4, 0)
    row.icon = row:CreateTexture(nil, "ARTWORK", nil, 2)
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("CENTER", row.border)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.buy = UI.CreateButton(row, L["Buy"], 48)
    row.buy:SetHeight(22)
    row.buy:SetPoint("RIGHT", -2, 0)
    row.buy:SetScript("OnClick", function() ns.BuyBack(row.sold) end)

    row.value = UI.Text(row, 11, UI.C.muted)
    row.value:SetPoint("RIGHT", row.buy, "LEFT", -6, 0)
    row.value:SetJustifyH("RIGHT")

    row.name = UI.Text(row, 12, UI.C.text)
    row.name:SetPoint("LEFT", row.border, "RIGHT", 6, 0)
    row.name:SetPoint("RIGHT", row.value, "LEFT", -6, 0)
    row.name:SetWordWrap(false)

    row:SetScript("OnEnter", function(self)
        hover:Show()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(self.sold.link)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function()
        hover:Hide()
        GameTooltip_Hide()
    end)
    return row
end

local function UpdateRow(row, sold)
    row.sold = sold
    row.icon:SetTexture(select(5, C_Item.GetItemInfoInstant(sold.itemID)))
    local color = QualityColor(sold.quality)
    row.border:SetColorTexture(color[1], color[2], color[3], 0.9)
    local name = C_Item.GetItemInfo(sold.itemID) or (sold.link and sold.link:match("%[(.-)%]")) or "?"
    row.name:SetText(name .. (sold.count > 1 and ("  |cff8a8b93x" .. sold.count .. "|r") or ""))
    row.name:SetTextColor(color[1], color[2], color[3])
    row.value:SetText(GetMoneyString(sold.value, true))
end

local function CreatePanel()
    local UI = ns.UI
    local C = UI.C

    panel = CreateFrame("Frame", "PocketGoblinMerchantPanel", MerchantFrame, "BackdropTemplate")
    panel:SetWidth(WIDTH)
    panel:SetPoint("TOPLEFT", MerchantFrame, "TOPRIGHT", 6, 0)
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    panel:SetBackdropColor(0.047, 0.05, 0.058, 0.97)
    panel:SetBackdropBorderColor(0.17, 0.17, 0.19, 1)
    panel:EnableMouse(true)
    panel:Hide()

    local logo = UI.Icon(panel, "logo", 22, C.gold)
    logo:SetPoint("TOPLEFT", 12, -11)
    local title = UI.Text(panel, 14, C.text)
    title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
    title:SetText("|cffd4a72cPocket|r Goblin")

    local close = CreateFrame("Button", nil, panel)
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", -8, -10)
    local closeIcon = UI.Icon(close, "icon-close", 12, C.muted)
    closeIcon:SetPoint("CENTER")
    close:SetScript("OnEnter", function() UI.SetColor(closeIcon, C.text) end)
    close:SetScript("OnLeave", function() UI.SetColor(closeIcon, C.muted) end)
    close:SetScript("OnClick", function()
        dismissed = true
        panel:Hide()
    end)

    local line = panel:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.45)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 1, -HEADER_HEIGHT + 6)
    line:SetPoint("TOPRIGHT", -1, -HEADER_HEIGHT + 6)

    -- Sell: what would be sold, and a button to sell it now.
    local junkLabel = UI.Text(panel, 11, C.muted)
    junkLabel:SetPoint("TOPLEFT", 14, -HEADER_HEIGHT - 8)
    junkLabel:SetText(L["JUNK IN YOUR BAGS"])
    panel.junkText = UI.Text(panel, 13, C.text)
    panel.junkText:SetPoint("TOPLEFT", junkLabel, "BOTTOMLEFT", 0, -4)
    panel.junkText:SetWidth(WIDTH - 14 - 110)
    panel.junkText:SetWordWrap(false)

    panel.sell = UI.CreateButton(panel, L["Sell junk"], 96, true)
    panel.sell:SetHeight(28)
    panel.sell:SetPoint("TOPRIGHT", -12, -HEADER_HEIGHT - 10)
    panel.sell:SetScript("OnClick", function() ns.SellJunk(true) end)

    -- Suggestion: an item you keep selling yourself, with yes and no buttons.
    local suggest = CreateFrame("Frame", nil, panel)
    suggest:SetPoint("TOPLEFT", 0, -HEADER_HEIGHT - SELL_HEIGHT)
    suggest:SetPoint("TOPRIGHT", 0, -HEADER_HEIGHT - SELL_HEIGHT)
    suggest:SetHeight(SUGGEST_HEIGHT)
    local suggestLine = suggest:CreateTexture(nil, "ARTWORK")
    suggestLine:SetColorTexture(1, 1, 1, 0.06)
    suggestLine:SetHeight(1)
    suggestLine:SetPoint("TOPLEFT", 1, 0)
    suggestLine:SetPoint("TOPRIGHT", -1, 0)

    suggest.icon = suggest:CreateTexture(nil, "ARTWORK")
    suggest.icon:SetSize(20, 20)
    suggest.icon:SetPoint("TOPLEFT", 14, -10)
    suggest.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    suggest.name = UI.Text(suggest, 12, C.text)
    suggest.name:SetPoint("LEFT", suggest.icon, "RIGHT", 8, 0)
    suggest.name:SetPoint("RIGHT", -14, 0)
    suggest.name:SetWordWrap(false)
    suggest.text = UI.Text(suggest, 11, C.muted)
    suggest.text:SetPoint("TOPLEFT", suggest.icon, "BOTTOMLEFT", 0, -6)
    suggest.text:SetWidth(WIDTH - 28)

    suggest.yes = UI.CreateButton(suggest, L["Auto-sell"], 86, true)
    suggest.yes:SetHeight(24)
    suggest.yes:SetPoint("BOTTOMRIGHT", -12, 10)
    suggest.yes:SetScript("OnClick", function() ns.AnswerSuggestion(suggest.itemID, true) end)
    suggest.no = UI.CreateButton(suggest, L["No thanks"], 86)
    suggest.no:SetHeight(24)
    suggest.no:SetPoint("RIGHT", suggest.yes, "LEFT", -6, 0)
    suggest.no:SetScript("OnClick", function() ns.AnswerSuggestion(suggest.itemID, false) end)

    -- Hovering the item shows its tooltip.
    local itemHover = CreateFrame("Frame", nil, suggest)
    itemHover:SetPoint("TOPLEFT", suggest.icon)
    itemHover:SetPoint("BOTTOMRIGHT", suggest.name)
    itemHover:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(suggest.itemID)
        GameTooltip:Show()
    end)
    itemHover:SetScript("OnLeave", GameTooltip_Hide)
    panel.suggest = suggest

    -- Buy back: heading and Buy back all button over the list of sold items.
    panel.buyback = CreateFrame("Frame", nil, panel)
    panel.buyback:SetHeight(SECTION_HEIGHT)
    local divider = panel.buyback:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1, 1, 1, 0.06)
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", 1, 0)
    divider:SetPoint("TOPRIGHT", -1, 0)
    panel.buybackLabel = UI.Text(panel.buyback, 11, C.muted)
    panel.buybackLabel:SetPoint("LEFT", 14, -1)
    panel.buybackLabel:SetText(L["BUY BACK"])

    panel.buyAll = UI.CreateButton(panel.buyback, L["Buy back all"], 96)
    panel.buyAll:SetHeight(20)
    panel.buyAll.label:SetFont(panel.buyAll.label:GetFont(), 11, "")
    panel.buyAll:SetPoint("RIGHT", -10, -1)
    panel.buyAll:SetScript("OnClick", function() ns.BuyBackAll(panel.items) end)
    panel.buyAll:HookScript("OnEnter", function(self)
        local total = 0
        for _, sold in ipairs(panel.items or {}) do total = total + sold.value end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Buy back all"], 1, 1, 1)
        GameTooltip:AddLine(L["Buys back everything listed below."], nil, nil, nil, true)
        GameTooltip:AddDoubleLine(L["Total"], GetMoneyString(total, true), 0.7, 0.7, 0.7, 1, 1, 1)
        GameTooltip:Show()
    end)
    panel.buyAll:HookScript("OnLeave", GameTooltip_Hide)

    panel.visitLabel = UI.Text(panel, 11, C.muted)
    panel.visitLabel:SetPoint("BOTTOMLEFT", 14, 13)
    panel.visitLabel:SetText(L["SOLD THIS VISIT"])
    panel.visitTotal = UI.Text(panel, 13, C.text)
    panel.visitTotal:SetPoint("BOTTOMRIGHT", -14, 12)
    panel.visitTotal:SetJustifyH("RIGHT")
end

-- Shows the panel while a vendor is open (unless it's turned off or was
-- closed for this visit).
function ns.UpdateMerchantPanel()
    if not MerchantFrame then return end
    if not ns.IsMerchantOpen() then
        dismissed = false -- show again on the next visit
        if panel then panel:Hide() end
        return
    end
    if not ns.db.merchantPanel or dismissed then
        if panel then panel:Hide() end
        return
    end

    -- Newest sales first, as many as the buyback list can hold.
    local matches = ns.MatchBuybacks()
    local items = {}
    for _, visit in ipairs(ns.GetHistory()) do
        for i = #visit.items, 1, -1 do
            local sold = visit.items[i]
            if matches[sold] and #items < MAX_ROWS then items[#items + 1] = sold end
        end
    end
    if not panel then CreatePanel() end
    panel.items = items

    local busy = ns.IsSelling() or ns.IsBuyingBack()
    local count, money = ns.GetJunkSummary()
    if ns.IsSelling() then
        panel.sell.label:SetText(L["Selling..."])
        panel.sell:Disable()
    else
        panel.sell.label:SetText(L["Sell junk"])
        panel.sell:SetEnabled(count > 0 and not busy)
    end
    panel.junkText:SetText(count > 0
        and ("%d %s  |cff8a8b93-|r  %s"):format(count, count == 1 and "item" or "items", GetMoneyString(money, true))
        or L["Nothing to sell"])

    -- The suggestion, if there is one, sits between selling and buying back.
    local y = HEADER_HEIGHT + SELL_HEIGHT
    local suggestID, suggestCount = ns.GetSuggestion()
    local suggest = panel.suggest
    suggest:SetShown(suggestID ~= nil)
    if suggestID then
        local name, _, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(suggestID)
        local color = QualityColor(quality)
        suggest.itemID = suggestID
        suggest.icon:SetTexture(icon)
        suggest.name:SetText(name)
        suggest.name:SetTextColor(color[1], color[2], color[3])
        suggest.text:SetText(ns.GoblinVoice()
            and (L["Psst! You've hawked this %d times yourself. Shall I handle it from now on?"]):format(suggestCount)
            or (L["You've sold this yourself %d times. Auto-sell it from now on?"]):format(suggestCount))
        y = y + SUGGEST_HEIGHT
    end

    panel.buyback:SetShown(#items > 0)
    panel.buyback:SetPoint("TOPLEFT", 0, -y)
    panel.buyback:SetPoint("TOPRIGHT", 0, -y)
    if ns.IsBuyingBack() then
        panel.buyAll.label:SetText(L["Buying..."])
        panel.buyAll:Disable()
    else
        panel.buyAll.label:SetText(L["Buy back all"])
        panel.buyAll:SetEnabled(#items > 1 and not busy)
    end
    y = y + SECTION_HEIGHT

    for i, sold in ipairs(items) do
        local row = rows[i] or CreateRow()
        rows[i] = row
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 8, -y - (i - 1) * ROW_HEIGHT)
        row:SetPoint("TOPRIGHT", -8, -y - (i - 1) * ROW_HEIGHT)
        UpdateRow(row, sold)
        row.buy:SetEnabled(not busy)
        row:Show()
    end
    for i = #items + 1, #rows do
        rows[i]:Hide()
    end

    local visitTotal = 0
    local visit = ns.GetCurrentVisit()
    for _, sold in ipairs(visit and visit.items or {}) do
        if not sold.boughtBack then visitTotal = visitTotal + sold.value end
    end
    panel.visitTotal:SetText(visitTotal > 0 and GetMoneyString(visitTotal, true) or "0")
    local listHeight = #items > 0 and (SECTION_HEIGHT + #items * ROW_HEIGHT) or 0
    panel:SetHeight(y - SECTION_HEIGHT + listHeight + FOOTER_HEIGHT + 4)
    panel:Show()
end
