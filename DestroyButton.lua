-- "Destroy cheapest junk" button for the bags: a trash can that shows the
-- item it would destroy, and its value, on hover. Clicking asks for
-- confirmation in a popup unless that's turned off.

local ADDON_NAME, ns = ...
local L = ns.L

-- Colours of Blizzard's own title-bar text, for the default bags.
local BLIZZARD_GOLD = { 1, 0.82, 0, 1 }
local BLIZZARD_GREY = { 0.5, 0.5, 0.5, 0.7 }

local buttons = {}
local baganatorButton
local popup

local function ShowTooltip(button)
    local UI = ns.UI
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetText(L["Destroy cheapest junk"], UI.C.gold[1], UI.C.gold[2], UI.C.gold[3])
    if ns.IsBagSpaceLow() then
        local free = ns.GetFreeBagSlots()
        GameTooltip:AddLine(ns.Say("bagsLow", L["Only %d free bag slot(s) left."], free),
            UI.C.danger[1], UI.C.danger[2], UI.C.danger[3])
    end

    local target, protected, destroyable = ns.FindCheapestJunk()
    if target then
        local count = target.count > 1 and (" x" .. target.count) or ""
        GameTooltip:AddLine(("|T%s:18:18:0:0:64:64:5:59:5:59|t %s%s"):format(target.icon, target.link, count))
        GameTooltip:AddDoubleLine(L["Value"],
            target.value > 0 and GetMoneyString(target.value, true) or L["No vendor value"],
            0.7, 0.7, 0.7, 1, 1, 1)
        GameTooltip:AddLine((L["%d junk %s to destroy%s."]):format(destroyable,
            destroyable == 1 and "item" or "items",
            ns.db.destroyProtect and L[" within your value limit"] or ""), 0.6, 0.6, 0.6, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Click to destroy it. This can't be undone."], 0.92, 0.32, 0.32, true)
    elseif protected > 0 then
        GameTooltip:AddLine((L["All your junk is worth more than your limit of %s."]):format(
            GetMoneyString(ns.db.destroyLimit, true)), 0.7, 0.7, 0.7, true)
    else
        GameTooltip:AddLine(L["No junk in your bags."], 0.7, 0.7, 0.7)
    end
    GameTooltip:Show()
end

-- The trash can is bright when there's something to destroy, highlighted
-- while hovered, dim when there's nothing, and red with the number of free
-- slots when the bags are nearly full.
local function PaintButton(button)
    local UI = ns.UI
    local warn = button.lowSpace and button.hasTarget
    button.freeText:SetShown(button.lowSpace)
    if button.blizzardStyle then
        UI.SetColor(button.trash, not button.hasTarget and BLIZZARD_GREY
            or button.hovered and UI.C.white or warn and UI.C.danger or BLIZZARD_GOLD)
        return
    end
    local color = not button.hasTarget and UI.C.muted or (button.hovered or warn) and UI.C.danger or UI.C.text
    UI.SetColor(button.trash, color)
    UI.SetColor(button.border, (button.hovered or warn) and button.hasTarget and UI.C.danger or UI.C.controlBorder)
end

local function UpdateButton(button, target, lowSpace, freeSlots)
    button.hasTarget = target ~= nil
    button.lowSpace = lowSpace
    button.freeText:SetText(freeSlots)
    PaintButton(button)
    if GameTooltip:IsOwned(button) then ShowTooltip(button) end
end

local function Inset(region, pixels)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", pixels, -pixels)
    region:SetPoint("BOTTOMRIGHT", -pixels, pixels)
end

-- Keeps the button above the bag frame it gets attached to. Bag windows
-- draw their border art (NineSlice) at a high frame level, so the button
-- has to sit above that and level with the window's own title-bar buttons.
local function MatchParentLayer(button)
    local parent = button:GetParent()
    if not parent or parent == UIParent then return end
    local level = parent:GetFrameLevel() + 10
    for _, region in ipairs({ parent.NineSlice, parent.CloseButton, parent.CustomiseButton }) do
        if region and region.GetFrameLevel then
            level = math.max(level, region:GetFrameLevel() + 1)
        end
    end
    button:SetFrameStrata(parent:GetFrameStrata())
    button:SetFrameLevel(level)
end
ns.MatchParentLayer = MatchParentLayer -- also used by the sort button

-- size is the frame size. The default style is Pocket Goblin's dark rounded
-- button; blizzardStyle is a bare gold icon that matches the default bags'
-- title bar.
local function CreateDestroyButton(parent, size, blizzardStyle)
    local UI = ns.UI
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(size, size)
    button.blizzardStyle = blizzardStyle

    if blizzardStyle then
        button.trash = UI.Icon(button, "icon-trash", size, BLIZZARD_GOLD)
        button.trash:SetPoint("CENTER")
        button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        -- Nudge the icon while pressed, like Blizzard's buttons.
        button:SetScript("OnMouseDown", function() button.trash:SetPoint("CENTER", 1, -1) end)
        button:SetScript("OnMouseUp", function() button.trash:SetPoint("CENTER") end)
    else
        Inset(UI.Rounded(button, "BACKGROUND", UI.C.control), 1)
        button.border = UI.Rounded(button, "BORDER", UI.C.controlBorder, "rounded-border")
        Inset(button.border, 1)

        button.trash = UI.Icon(button, "icon-trash", math.floor(size * 0.62), UI.C.muted)
        button.trash:SetPoint("CENTER")

        local highlight = UI.Rounded(button, "HIGHLIGHT", { 1, 1, 1, 0.08 })
        Inset(highlight, 1)
        highlight:SetBlendMode("ADD")
    end

    -- Free bag slots, shown in the corner when the bags are nearly full.
    button.freeText = button:CreateFontString(nil, "OVERLAY")
    button.freeText:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    button.freeText:SetTextColor(1, 0.4, 0.4)
    button.freeText:SetPoint("BOTTOMRIGHT", 2, -2)
    button.freeText:Hide()

    button:SetScript("OnClick", function() ns.DestroyCheapestJunk() end)
    button:SetScript("OnEnter", function(self)
        self.hovered = true
        PaintButton(self)
        ShowTooltip(self)
    end)
    button:SetScript("OnLeave", function(self)
        self.hovered = false
        PaintButton(self)
        GameTooltip_Hide()
    end)
    button:SetScript("OnShow", MatchParentLayer)

    buttons[#buttons + 1] = button
    return button
end

-- Default bags: sits to the left of the backpack's close button (combined
-- or not).
local function AttachToDefaultBags()
    local button = CreateDestroyButton(UIParent, 20, true)
    button:Hide()

    local function place()
        local frame
        if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
            frame = ContainerFrameCombinedBags
        elseif ContainerFrame1 and ContainerFrame1:IsShown() then
            frame = ContainerFrame1
        end
        if not frame or not ns.db.destroyButton then
            button:Hide()
            return
        end
        button:SetParent(frame)
        MatchParentLayer(button)
        button:ClearAllPoints()
        -- Left of the sort button when that's shown, otherwise of the close button.
        local close = frame.CloseButton or (frame:GetName() and _G[frame:GetName() .. "CloseButton"])
        if ns.sortButton and ns.db.sortButton then
            button:SetPoint("RIGHT", ns.sortButton, "LEFT", -2, 0)
        elseif close then
            button:SetPoint("RIGHT", close, "LEFT", -1, 0)
        else
            button:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -30, -4)
        end
        button:Show()
    end

    for _, frame in ipairs({ ContainerFrameCombinedBags, ContainerFrame1 }) do
        if frame then
            frame:HookScript("OnShow", place)
            frame:HookScript("OnHide", place)
        end
    end
    button.Place = place
end

-- Baganator: placed next to its own buttons at the top of the backpack.
-- Baganator only lays out regions that are shown, so the button stays shown
-- (with a trash can) even when there's nothing to destroy.
local function AttachToBaganator()
    if not (Baganator and Baganator.API and Baganator.API.RegisterRegion) then return end
    baganatorButton = CreateDestroyButton(UIParent, 30)
    baganatorButton:SetShown(ns.db.destroyButton)
    hooksecurefunc(baganatorButton, "SetParent", MatchParentLayer)
    Baganator.API.RegisterRegion("Pocket Goblin", "pocketgoblin_destroy", "backpack", "top_left", baganatorButton)
    Baganator.API.RequestLayoutUpdate()
end

------------------------------------------------------------------------
-- Confirmation popup
------------------------------------------------------------------------

local function CreatePopup()
    local UI = ns.UI
    local C = UI.C

    popup = CreateFrame("Frame", "PocketGoblinDestroyPopup", UIParent, "BackdropTemplate")
    popup:SetSize(360, 244)
    popup:SetPoint("CENTER", 0, 140)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetToplevel(true)
    popup:SetClampedToScreen(true)
    popup:EnableMouse(true)
    popup:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    popup:SetBackdropColor(0.047, 0.05, 0.058, 0.98)
    popup:SetBackdropBorderColor(0.17, 0.17, 0.19, 1)
    popup:Hide()

    local accent = popup:CreateTexture(nil, "ARTWORK")
    accent:SetColorTexture(C.danger[1], C.danger[2], C.danger[3], 0.8)
    accent:SetHeight(2)
    accent:SetPoint("TOPLEFT", 1, -1)
    accent:SetPoint("TOPRIGHT", -1, -1)

    local icon = UI.Icon(popup, "icon-trash", 20, C.danger)
    icon:SetPoint("TOPLEFT", 20, -20)
    local title = UI.Text(popup, 16, C.text)
    title:SetPoint("LEFT", icon, "RIGHT", 10, 0)
    title:SetText(L["Destroy this item?"])

    -- The item: icon with a quality border, name, and value.
    local card = CreateFrame("Frame", nil, popup)
    card:SetPoint("TOPLEFT", 20, -54)
    card:SetPoint("TOPRIGHT", -20, -54)
    card:SetHeight(58)
    UI.Rounded(card, "BACKGROUND", C.card)
    UI.Rounded(card, "BORDER", C.cardBorder, "rounded-border")

    popup.itemBorder = card:CreateTexture(nil, "ARTWORK", nil, 1)
    popup.itemBorder:SetSize(38, 38)
    popup.itemBorder:SetPoint("LEFT", 10, 0)
    popup.itemIcon = card:CreateTexture(nil, "ARTWORK", nil, 2)
    popup.itemIcon:SetSize(36, 36)
    popup.itemIcon:SetPoint("CENTER", popup.itemBorder)
    popup.itemIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    popup.itemName = UI.Text(card, 14, C.text)
    popup.itemName:SetPoint("TOPLEFT", popup.itemBorder, "TOPRIGHT", 10, -2)
    popup.itemName:SetWidth(250)
    popup.itemName:SetWordWrap(false)
    popup.itemValue = UI.Text(card, 12, C.muted)
    popup.itemValue:SetPoint("BOTTOMLEFT", popup.itemBorder, "BOTTOMRIGHT", 10, 2)

    -- Show the item's tooltip when hovering the card.
    card:EnableMouse(true)
    card:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetBagItem(popup.target.bag, popup.target.slot)
        GameTooltip:Show()
    end)
    card:SetScript("OnLeave", GameTooltip_Hide)

    local warning = UI.Text(popup, 12, C.muted)
    warning:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 0, -12)
    warning:SetText(L["This can't be undone."])

    -- "Don't ask again" switch.
    popup.dontAsk = UI.CreateToggle(popup,
        function() return not ns.db.destroyConfirm end,
        function(value)
            ns.db.destroyConfirm = not value
            if ns.RefreshWindow then ns.RefreshWindow() end
        end)
    popup.dontAsk:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 0, -38)
    local dontAskLabel = UI.Text(popup, 12, C.muted)
    dontAskLabel:SetPoint("LEFT", popup.dontAsk, "RIGHT", 10, 0)
    dontAskLabel:SetText(L["Don't ask again when destroying items"])

    local destroy = UI.CreateButton(popup, L["Destroy"], 96, "danger")
    destroy:SetPoint("BOTTOMRIGHT", -20, 18)
    destroy:SetScript("OnClick", function()
        -- Destroy before hiding: deleting needs this click to count as a
        -- hardware event, and a click on a frame that's already hidden
        -- doesn't count.
        ns.DestroyItem(popup.target)
        popup:Hide()
    end)

    local cancel = UI.CreateButton(popup, L["Cancel"], 96)
    cancel:SetPoint("RIGHT", destroy, "LEFT", -8, 0)
    cancel:SetScript("OnClick", function() popup:Hide() end)

    -- Escape cancels without also closing other windows (see UI.lua).
    popup:EnableKeyboard(true)
    popup:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then return end
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            self:Hide()
            C_Timer.After(0, function()
                if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
            end)
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
    popup:SetScript("OnShow", function(self)
        if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
        PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPEN or 850)
    end)
end

-- Asks before destroying target (from FindCheapestJunk).
function ns.ShowDestroyConfirm(target)
    if not popup then CreatePopup() end
    popup.target = target

    local name, _, quality = C_Item.GetItemInfo(target.itemID)
    local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    color = color and { color.r, color.g, color.b } or ns.UI.C.text

    popup.itemIcon:SetTexture(target.icon)
    popup.itemBorder:SetColorTexture(color[1], color[2], color[3], 0.9)
    popup.itemName:SetText((name or target.link) .. (target.count > 1 and ("  |cff8a8b93x" .. target.count .. "|r") or ""))
    popup.itemName:SetTextColor(color[1], color[2], color[3])
    popup.itemValue:SetText(target.value > 0 and (L["Worth "] .. GetMoneyString(target.value, true))
        or L["No vendor value"])
    popup.dontAsk:Update(true)
    popup:Show()
end

function ns.SetupDestroyButtons()
    AttachToDefaultBags()
    AttachToBaganator()
    ns.UpdateDestroyButtons()
end

function ns.UpdateDestroyButtons()
    if #buttons == 0 then return end

    for _, button in ipairs(buttons) do
        if button.Place then button.Place() end
    end
    if baganatorButton and baganatorButton:IsShown() ~= ns.db.destroyButton then
        baganatorButton:SetShown(ns.db.destroyButton)
        Baganator.API.RequestLayoutUpdate()
    end

    local target = ns.FindCheapestJunk()
    local lowSpace, freeSlots = ns.IsBagSpaceLow(), ns.GetFreeBagSlots()
    for _, button in ipairs(buttons) do
        UpdateButton(button, target, lowSpace, freeSlots)
    end
    if ns.UpdateSortButtons then ns.UpdateSortButtons() end
end

local function FrameName(frame)
    if not frame then return "none" end
    return (frame.GetDebugName and frame:GetDebugName()) or frame:GetName() or tostring(frame)
end

-- Lines for /goblin debug about where the destroy buttons are.
function ns.DebugDestroyButtons(print)
    print(("Destroy buttons: %d, setting %s, Baganator API: %s"):format(#buttons,
        ns.db.destroyButton and "on" or "off",
        (Baganator and Baganator.API and Baganator.API.RegisterRegion) and "yes" or "no"))
    for i, button in ipairs(buttons) do
        local parent = button:GetParent()
        local point, relativeTo = button:GetPoint(1)
        print(("  #%d%s: parent %s, shown %s, visible %s, level %d (parent %d), anchor %s to %s"):format(
            i, button == baganatorButton and " (Baganator)" or "", FrameName(parent),
            tostring(button:IsShown()), tostring(button:IsVisible()), button:GetFrameLevel(),
            parent and parent:GetFrameLevel() or 0, tostring(point), FrameName(relativeTo)))
    end
end
