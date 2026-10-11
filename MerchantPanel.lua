-- Pocket Goblin's panel next to the vendor window: a "Sell junk" button
-- with what it would sell, what you can buy back (a button each), and what
-- this visit earned.

local ADDON_NAME, ns = ...
local L = ns.L

local WIDTH = 270
local HEADER_HEIGHT = 44
local SELL_HEIGHT = 56     -- junk summary and the Sell junk button
local SECTION_HEIGHT = 24  -- "BUY BACK" heading
local LIST_TOP = HEADER_HEIGHT + SELL_HEIGHT + SECTION_HEIGHT
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

local function CreateRow(index)
    local UI = ns.UI
    local row = CreateFrame("Frame", nil, panel)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 8, -LIST_TOP - (index - 1) * ROW_HEIGHT)
    row:SetPoint("TOPRIGHT", -8, -LIST_TOP - (index - 1) * ROW_HEIGHT)
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

    -- Buy back: heading over the list of sold items.
    panel.buybackLabel = UI.Text(panel, 11, C.muted)
    panel.buybackLabel:SetPoint("TOPLEFT", 14, -HEADER_HEIGHT - SELL_HEIGHT - 6)
    panel.buybackLabel:SetText(L["BUY BACK"])
    local divider = panel:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1, 1, 1, 0.06)
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", 1, -HEADER_HEIGHT - SELL_HEIGHT)
    divider:SetPoint("TOPRIGHT", -1, -HEADER_HEIGHT - SELL_HEIGHT)

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
            local include = ns.db.merchantPanelAll or sold.source ~= "you"
            if matches[sold] and include and #items < MAX_ROWS then items[#items + 1] = sold end
        end
    end
    if not panel then CreatePanel() end

    local count, money = ns.GetJunkSummary()
    if ns.IsSelling() then
        panel.sell.label:SetText("Selling...")
        panel.sell:Disable()
    else
        panel.sell.label:SetText(L["Sell junk"])
        panel.sell:SetEnabled(count > 0)
    end
    panel.junkText:SetText(count > 0
        and ("%d %s  |cff8a8b93-|r  %s"):format(count, count == 1 and "item" or "items", GetMoneyString(money, true))
        or L["Nothing to sell"])
    panel.buybackLabel:SetShown(#items > 0)

    for i, sold in ipairs(items) do
        rows[i] = rows[i] or CreateRow(i)
        UpdateRow(rows[i], sold)
        rows[i]:Show()
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
    panel:SetHeight(HEADER_HEIGHT + SELL_HEIGHT + listHeight + FOOTER_HEIGHT + 4)
    panel:Show()
end
