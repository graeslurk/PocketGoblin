-- EllesmereUI's bags (EllesmereUIBags): Pocket Goblin's icons on its item
-- slots, through its public overlay API (EUI_Bags.RegisterItemOverlayIcon),
-- and the trash can and open button in its header, left of its own icons.
-- Its own sort button stays (Pocket Goblin's isn't added there).

local ADDON_NAME, ns = ...

local EUI = EUI_Bags
if not (EUI and EUI.RegisterItemOverlayIcon) then return end

local WINDOWS = { "EUI_Bags", "EUI_BagsReagent" }
local BUTTON_SIZE = 22 -- EllesmereUI's header icons
local GAP = 6          -- between header icons, as EllesmereUI spaces them
local ITEM_SIZE = 37   -- the default bags' item size, which the icon size is set for

------------------------------------------------------------------------
-- Icons on the item slots
------------------------------------------------------------------------

-- Our icon frame for each of EllesmereUI's item buttons. EllesmereUI asks
-- that nothing is stored on its (secure) buttons, so they're kept here.
local marks = setmetatable({}, { __mode = "k" })

local function Mark(button)
    local mark = marks[button]
    if mark then return mark end
    local parent = button._textOverlay or button -- covers the item icon
    mark = CreateFrame("Frame", nil, parent)
    mark:SetAllPoints(button)
    mark:SetFrameLevel(parent:GetFrameLevel() + 1)
    mark.icon = mark:CreateTexture(nil, "OVERLAY", nil, 7)
    -- The equipment set's own icon, in a thin dark frame.
    mark.setBorder = mark:CreateTexture(nil, "OVERLAY", nil, 5)
    mark.setBorder:SetColorTexture(0, 0, 0, 0.9)
    mark.setIcon = mark:CreateTexture(nil, "OVERLAY", nil, 6)
    mark.setIcon:SetPoint("TOPLEFT", mark.setBorder, 1, -1)
    mark.setIcon:SetPoint("BOTTOMRIGHT", mark.setBorder, -1, 1)
    mark.setIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    marks[button] = mark
    return mark
end

local function Hide(button)
    local mark = marks[button]
    if mark then mark:Hide() end
end

-- Runs for every slot EllesmereUI paints (bags, reagent bag, bank; grid and
-- list). data = { bag, slot, info, itemLink }.
local function Paint(button, data)
    local db = ns.db
    local bag, slot = data.bag, data.slot
    -- Only your bags: the bank has nothing to sell.
    if not (db and bag and slot and slot > 0 and bag >= 0 and bag <= ns.LAST_BAG) then return Hide(button) end
    local info = C_Container.GetContainerItemInfo(bag, slot)
    -- EllesmereUI shows Pawn's arrow (bottom right) when Pawn's bag arrows are on.
    local otherArrow = ns.PawnShowsBagArrows() or (button.UpgradeIcon and button.UpgradeIcon:IsShown())
    local icon, setIcon = ns.ItemIcon(bag, slot, info, otherArrow)
    if not icon then return Hide(button) end

    local mark = Mark(button)
    local icons = ns.ICONS
    local width = button:GetWidth()
    local size = icons.size * db.iconScale * (width > 0 and width / ITEM_SIZE or 1)
    local corner = db.iconCorner
    mark.icon:ClearAllPoints()
    mark.setBorder:ClearAllPoints()
    mark.icon:SetShown(icon ~= "set")
    mark.setBorder:SetShown(icon == "set")
    mark.setIcon:SetShown(icon == "set")
    if icon == "set" then
        mark.setBorder:SetSize(size * 0.8, size * 0.8)
        mark.setBorder:SetPoint(corner, button, corner, 1, -1)
        mark.setIcon:SetTexture(setIcon)
    else
        if icon == "coin" and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(icons.coinAtlas) then
            mark.icon:SetAtlas(icons.coinAtlas)
        else
            mark.icon:SetTexture(icon == "coin" and icons.coin or icon == "ask" and icons.ask
                or icon == "upgrade" and icons.upgrade or icons.lock)
        end
        local color = icon == "lock" and icons.lockColor or { 1, 1, 1 }
        mark.icon:SetVertexColor(color[1], color[2], color[3])
        local scale = icon == "lock" and 0.85 or 1
        mark.icon:SetSize(size * scale, size * scale)
        mark.icon:SetPoint(corner, button, corner, 0, 0)
    end
    mark:Show()
end

EUI.RegisterItemOverlayIcon(ADDON_NAME, Paint)

-- Repaints EllesmereUI's open bag windows, at most once a frame, after
-- Pocket Goblin's rules or Pawn's answers change (EllesmereUI repaints on
-- its own when the bags change).
local refreshPending = false
function ns.RefreshEllesmere()
    if refreshPending then return end
    refreshPending = true
    C_Timer.After(0, function()
        refreshPending = false
        for _, name in ipairs(WINDOWS) do
            local window = _G[name]
            if window and window.RefreshInventory and window:IsVisible() then window:RefreshInventory() end
        end
    end)
end

------------------------------------------------------------------------
-- Trash can and open button in the header
------------------------------------------------------------------------

local trash, open
local shown = {} -- [button] = shown at the last layout, to redo it only on a change

-- Called by EllesmereUI after it places its own header icons (right to left
-- from the search box): ours go on, leftwards, from its leftmost one.
local function PlaceHeaderButtons(bags)
    local header = bags._bagsBtn and bags._bagsBtn:GetParent()
    local edge = bags._hdrEdge
    if not (ns.db and header and edge) then return end
    if not trash then
        trash = ns.CreateDestroyButton(header, BUTTON_SIZE, "ellesmere")
        open = ns.CreateOpenButton(BUTTON_SIZE, true)
        open:SetParent(header)
        ns.ellesmereOpenButton = open
        C_Timer.After(0, function() -- fill them in (what to destroy, how many to open)
            ns.UpdateDestroyButtons()
            ns.UpdateOpenButtons()
        end)
    end
    local prev = edge
    for _, button in ipairs({ trash, open }) do
        local on = button == trash and ns.db.destroyButton or button == open and ns.db.openButton
        shown[button] = on and true or false
        button:SetShown(on)
        if on then
            button:ClearAllPoints()
            button:SetPoint("RIGHT", prev, "LEFT", -GAP, 0)
            prev = button
        end
    end
    if prev ~= edge then
        -- The leftmost icon bounds the window title, so it shortens instead of
        -- running under our buttons.
        bags._hdrEdge = prev
        if bags.FitHeaderText then bags:FitHeaderText() end
    end
end

if type(EUI.SyncHeaderIcons) == "function" then
    hooksecurefunc(EUI, "SyncHeaderIcons", PlaceHeaderButtons)
end

-- Lays the header out again when one of our buttons was switched on or off
-- (EllesmereUI lays it out itself when the bags first open).
function ns.SyncEllesmereHeader()
    if not (trash and ns.db and EUI.SyncHeaderIcons) then return end
    if shown[trash] == (ns.db.destroyButton and true or false)
        and shown[open] == (ns.db.openButton and true or false) then
        return
    end
    EUI:SyncHeaderIcons()
end
