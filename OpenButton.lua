-- Open containers: a bag button that opens the next clam, sack of loot or
-- other container you'd open with a right-click, one per click (the game
-- only opens them on a click or key press). Locked boxes are skipped. It
-- shows only while there's something to open, with a count, next to the
-- trash can; there's also a hotkey (Bindings.xml).

local ADDON_NAME, ns = ...
local L = ns.L

local LAST_BAG = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
local BLIZZARD_GOLD = { 1, 0.82, 0, 1 }

local button, baganatorButton

-- True if the item's tooltip says it's locked (a lockbox not picked yet).
-- Not cached: picking the lock changes it.
local function IsLockedBox(bag, slot)
    local data = LOCKED and C_TooltipInfo and C_TooltipInfo.GetBagItem(bag, slot)
    for _, line in ipairs(data and data.lines or {}) do
        if line.leftText == LOCKED then return true end
    end
    return false
end

-- Containers you can open now: { { bag =, slot = }, ... }, in bag order.
function ns.FindContainers()
    local found = {}
    for bag = 0, LAST_BAG do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.hasLoot and not info.isLocked and not IsLockedBox(bag, slot) then
                found[#found + 1] = { bag = bag, slot = slot }
            end
        end
    end
    return found
end

-- With these windows open, using an item from the bags doesn't open it: a
-- vendor buys it, and the bank, guild bank, trade, mail and auction house
-- take it.
local ITEM_TAKING_FRAMES = { "BankFrame", "GuildBankFrame", "TradeFrame", "SendMailFrame", "AuctionFrame",
    "AuctionHouseFrame" }

local function WindowWouldTakeItem()
    if ns.IsMerchantOpen() then return true end
    for _, name in ipairs(ITEM_TAKING_FRAMES) do
        local frame = _G[name]
        if frame and frame:IsVisible() then return true end
    end
    return false
end

-- Opens the next container. Must run from a click or key press.
function ns.OpenNextContainer()
    if InCombatLockdown() then
        ns.Print(L["You can't open containers in combat."])
        return
    end
    if WindowWouldTakeItem() then
        ns.Print(L["Close the vendor, bank, trade, mail or auction window first: it would take the container "
            .. "instead of opening it."])
        return
    end
    if CursorHasItem() then
        ns.Print(L["Put down the item on your cursor first."])
        return
    end
    local container = ns.FindContainers()[1]
    if container then C_Container.UseContainerItem(container.bag, container.slot) end
end

------------------------------------------------------------------------
-- Buttons
------------------------------------------------------------------------

local function ShowTooltip(self)
    local C = ns.UI.C
    local count = #ns.FindContainers()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L["Open containers"], C.gold[1], C.gold[2], C.gold[3])
    if count > 0 then
        GameTooltip:AddLine((count == 1 and L["1 container to open. Click to open it."]
            or L["%d containers to open. Each click opens the next one."]):format(count), 1, 1, 1, true)
    else
        GameTooltip:AddLine(L["Nothing to open."], 1, 1, 1, true)
    end
    GameTooltip:Show()
end

-- ellesmere: a bare light icon like EllesmereUI's header icons, instead of
-- the default bags' gold one.
local function CreateOpenButton(size, ellesmere)
    local open = CreateFrame("Button", nil, UIParent)
    open:SetSize(size, size)
    open.icon = ns.UI.Icon(open, "icon-bag", ellesmere and size - 4 or size - 2,
        ellesmere and { 0.9, 0.9, 0.9, 1 } or BLIZZARD_GOLD)
    open.icon:SetPoint("CENTER")
    open.count = open:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    open.count:SetPoint("BOTTOMRIGHT", 3, -2)
    if not ellesmere then
        open:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    end
    open:SetScript("OnMouseDown", function(self) self.icon:SetPoint("CENTER", 1, -1) end)
    open:SetScript("OnMouseUp", function(self) self.icon:SetPoint("CENTER") end)
    open:SetScript("OnClick", function(self)
        ns.OpenNextContainer()
        if GameTooltip:IsOwned(self) then C_Timer.After(0.2, function() ShowTooltip(self) end) end
    end)
    open:SetScript("OnEnter", ShowTooltip)
    open:SetScript("OnLeave", GameTooltip_Hide)
    if ellesmere then
        open:HookScript("OnEnter", function(self) self.icon:SetAlpha(1) end)
        open:HookScript("OnLeave", function(self) self.icon:SetAlpha(0.9) end)
        open.icon:SetAlpha(0.9)
    end
    return open
end
ns.CreateOpenButton = CreateOpenButton -- also for EllesmereUI's bags (Ellesmere.lua)

-- Default bags: next to the trash can, on its outer side (left of it on
-- the combined bags, right of it on the separate backpack), or where the
-- trash can would be when that's off.
local function Place(count)
    local frame
    if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
        frame = ContainerFrameCombinedBags
    elseif ContainerFrame1 and ContainerFrame1:IsShown() then
        frame = ContainerFrame1
    end
    if not frame or not ns.db.openButton or count == 0 then
        button:Hide()
        return
    end
    button:SetParent(frame)
    ns.MatchParentLayer(button)
    button:ClearAllPoints()
    local destroy = ns.defaultDestroyButton
    local close = frame.CloseButton or (frame:GetName() and _G[frame:GetName() .. "CloseButton"])
    if destroy and destroy:IsShown() and destroy:GetParent() == frame then
        if frame == ContainerFrameCombinedBags then
            button:SetPoint("RIGHT", destroy, "LEFT", -2, 0)
        else
            button:SetPoint("LEFT", destroy, "RIGHT", 2, 0)
        end
    elseif ns.sortButton and ns.sortButton:IsShown() then
        button:SetPoint("RIGHT", ns.sortButton, "LEFT", -2, 0)
    elseif close then
        button:SetPoint("RIGHT", close, "LEFT", -1, 0)
    else
        button:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -30, -4)
    end
    button:Show()
end

-- Count and place, after the bags or the setting change.
function ns.UpdateOpenButtons()
    if not button then return end
    -- Switched off: no need to search the bags.
    local count = ns.db.openButton and #ns.FindContainers() or 0
    Place(count)
    button.count:SetText(count > 1 and count or "")
    if baganatorButton then
        -- Baganator only lays out shown regions, so it stays, dimmed when empty.
        baganatorButton:SetShown(ns.db.openButton)
        baganatorButton:SetAlpha(count > 0 and 1 or 0.35)
        baganatorButton.count:SetText(count > 1 and count or "")
    end
    -- In EllesmereUI's header it stays too (the header lays it out once), dimmed when empty.
    local ellesmere = ns.ellesmereOpenButton
    if ellesmere then
        ellesmere:SetAlpha(count > 0 and 1 or 0.4)
        ellesmere.count:SetText(count > 1 and count or "")
    end
    if ns.SyncEllesmereHeader then ns.SyncEllesmereHeader() end
end

function ns.SetupOpenButtons()
    button = CreateOpenButton(20)
    button:Hide()
    for _, frame in ipairs({ ContainerFrameCombinedBags, ContainerFrame1 }) do
        if frame then
            -- After the trash can has placed itself.
            frame:HookScript("OnShow", function() C_Timer.After(0, ns.UpdateOpenButtons) end)
            frame:HookScript("OnHide", ns.UpdateOpenButtons)
        end
    end

    if Baganator and Baganator.API and Baganator.API.RegisterRegion then
        baganatorButton = CreateOpenButton(30)
        hooksecurefunc(baganatorButton, "SetParent", ns.MatchParentLayer)
        Baganator.API.RegisterRegion("Pocket Goblin", "pocketgoblin_open", "backpack", "top_left", baganatorButton)
        Baganator.API.RequestLayoutUpdate()
    end
    ns.UpdateOpenButtons()
end

-- Hotkey (Bindings.xml).
BINDING_NAME_POCKETGOBLIN_OPEN = L["Open the next container"]
function PocketGoblin_OpenContainer() ns.OpenNextContainer() end

local events = CreateFrame("Frame")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:SetScript("OnEvent", function() ns.UpdateOpenButtons() end)
