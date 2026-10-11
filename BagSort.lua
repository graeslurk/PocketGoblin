-- Sort bags: a button on the default bags that stacks and sorts everything
-- in your bags. Items fill the bags from the backpack's first slot: your
-- hearthstone, then consumables, reagents, ammo, bags, weapons, armor,
-- trade goods and so on, best quality first; junk goes last.
--
-- Items move like dragging them by hand, but many at once: each pass
-- starts every swap that doesn't touch a slot another swap uses, then waits
-- for those items to land (they're locked until they have).

local ADDON_NAME, ns = ...
local L = ns.L

local LAST_BAG = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
local STEP_INTERVAL = 0.03 -- seconds between passes while sorting
local MAX_BATCH = 12       -- moves started in one pass
local MAX_STALL = 3        -- seconds without a move before giving up
local MAX_MOVES = 1000     -- safety stop
local MAX_REPLANS = 3      -- times to start over if the bags change while sorting
local HEARTHSTONE = 6948

-- Where each item type goes, by item class ID; unknown types go after these.
local CLASS_ORDER = {
    [0] = 1,  -- consumables
    [5] = 2,  -- reagents
    [6] = 3,  -- ammo
    [11] = 4, -- quivers and ammo pouches
    [1] = 5,  -- bags
    [2] = 6,  -- weapons
    [4] = 7,  -- armor
    [3] = 8,  -- gems
    [7] = 9,  -- trade goods
    [9] = 10, -- recipes
    [12] = 11, -- quest items
    [13] = 12, -- keys
    [15] = 13, -- miscellaneous
}

local sorter -- the running sort, or nil

------------------------------------------------------------------------
-- Bag contents
------------------------------------------------------------------------

-- Every slot in the bags that take any item (not profession bags), in
-- order: backpack first.
local function SortableSlots()
    local slots = {}
    for bag = 0, LAST_BAG do
        local _, family = C_Container.GetContainerNumFreeSlots(bag)
        if family == 0 then
            for slot = 1, C_Container.GetContainerNumSlots(bag) do
                slots[#slots + 1] = { bag = bag, slot = slot }
            end
        end
    end
    return slots
end

local function ReadSlot(position)
    return C_Container.GetContainerItemInfo(position.bag, position.slot)
end

local function SameItem(info, wanted)
    return info ~= nil and info.hyperlink == wanted.link and (info.stackCount or 1) == wanted.count
end

local function AnyLocked(slots)
    for _, position in ipairs(slots) do
        local info = ReadSlot(position)
        if info and info.isLocked then return true end
    end
    return false
end

local function Move(from, to)
    C_Container.PickupContainerItem(from.bag, from.slot)
    C_Container.PickupContainerItem(to.bag, to.slot) -- swaps, or merges a stack
end

------------------------------------------------------------------------
-- Stacking: partial stacks of the same item are merged first
------------------------------------------------------------------------

-- Merges partial stacks of the same item (and the same bound state) in
-- pairs: the first with the last, the second with the second last, and so
-- on, for all items at once. Slots still moving are left alone. Returns how
-- many merges it started. Each item gets as many merges as it had partial
-- stacks, less one, so items that won't stack can't keep it busy.
local function StackStep(state)
    local partial = {} -- key -> positions
    for _, position in ipairs(state.slots) do
        local info = ReadSlot(position)
        if info and not info.isLocked then
            local maxStack = select(8, C_Item.GetItemInfo(info.itemID)) or 1
            if maxStack > 1 and (info.stackCount or 1) < maxStack then
                local key = info.itemID .. ":" .. tostring(info.isBound)
                partial[key] = partial[key] or {}
                table.insert(partial[key], position)
            end
        end
    end
    local moves = 0
    for key, positions in pairs(partial) do
        state.stackTries[key] = state.stackTries[key] or #positions - 1
        for k = 1, math.floor(#positions / 2) do
            if state.stackTries[key] <= 0 or moves >= MAX_BATCH then break end
            state.stackTries[key] = state.stackTries[key] - 1
            Move(positions[#positions - k + 1], positions[k])
            moves = moves + 1
        end
    end
    return moves
end

------------------------------------------------------------------------
-- Sorting
------------------------------------------------------------------------

-- The bags' items in the order they should end up in, or nil while item
-- info is still loading.
local function Plan(slots)
    local items = {}
    for _, position in ipairs(slots) do
        local info = ReadSlot(position)
        if info then
            local name, _, quality, itemLevel, _, _, _, _, _, _, _, classID, subClassID = C_Item.GetItemInfo(info.itemID)
            if not name then
                C_Item.RequestLoadItemDataByID(info.itemID)
                return nil
            end
            local junk = not info.hasNoValue and ns.JunkReason(info, position.bag, position.slot) ~= nil
            items[#items + 1] = {
                link = info.hyperlink, count = info.stackCount or 1, itemID = info.itemID, name = name,
                group = (info.itemID == HEARTHSTONE and 0) or (junk and 100) or CLASS_ORDER[classID] or 50,
                subClass = subClassID or 0, quality = quality or 0, itemLevel = itemLevel or 0,
            }
        end
    end
    table.sort(items, function(a, b)
        if a.group ~= b.group then return a.group < b.group end
        if a.subClass ~= b.subClass then return a.subClass < b.subClass end
        if a.quality ~= b.quality then return a.quality > b.quality end
        if a.itemLevel ~= b.itemLevel then return a.itemLevel > b.itemLevel end
        if a.name ~= b.name then return a.name < b.name end
        if a.link ~= b.link then return a.link < b.link end
        return a.count > b.count
    end)
    return items
end

-- Starts moves that put out-of-place items where they belong: each swap
-- brings the wanted item into a slot, and no slot takes part in two swaps
-- in one pass. Slots still moving are skipped until they land. Returns the
-- number of moves started and whether everything is in place, or nil if
-- nothing can move but the bags don't match the plan (they changed).
local function SortStep(state)
    local slots, plan = state.slots, state.plan
    local contents, busy, anyLocked = {}, {}, false
    for i, position in ipairs(slots) do
        contents[i] = ReadSlot(position)
        if contents[i] and contents[i].isLocked then
            busy[i] = true
            anyLocked = true
        end
    end

    local moves, done = 0, true
    for i, wanted in ipairs(plan) do
        if not SameItem(contents[i], wanted) then
            done = false
            if not busy[i] and moves < MAX_BATCH then
                -- Take the item from a slot that isn't moving and doesn't
                -- already hold what belongs there.
                for j = 1, #slots do
                    if j ~= i and not busy[j] and SameItem(contents[j], wanted)
                        and not (plan[j] and SameItem(contents[j], plan[j])) then
                        Move(slots[j], slots[i])
                        busy[i], busy[j] = true, true
                        moves = moves + 1
                        break
                    end
                end
            end
        end
    end

    if moves == 0 and not anyLocked then
        if done then return 0, true end
        return nil
    end
    return moves, false
end

------------------------------------------------------------------------
-- Running it
------------------------------------------------------------------------

local function Stop(message)
    if not sorter then return end
    sorter.ticker:Cancel()
    sorter = nil
    if message then ns.Print(message) end
    if ns.UpdateSortButtons then ns.UpdateSortButtons() end
    ns.RefreshOverlays()
end

-- Gives up when nothing has moved for a while (an item is stuck, or item
-- info never loads).
local function CheckStalled(state)
    if GetTime() - state.lastMove > MAX_STALL then
        Stop(L["Sorting stopped: nothing moved for a few seconds. Try again."])
    end
end

local function Step()
    local state = sorter
    if InCombatLockdown() then
        Stop(L["Sorting stopped: you're in combat."])
        return
    end
    if CursorHasItem() then ClearCursor() end -- puts back anything left on the cursor
    if state.moves >= MAX_MOVES then
        Stop(L["Sorting stopped: too many moves. Try again."])
        return
    end

    local moved = 0
    if state.phase == "stack" then
        moved = StackStep(state)
        if moved == 0 then
            if AnyLocked(state.slots) then -- let the merges land first
                CheckStalled(state)
                return
            end
            state.phase = "sort"
        end
    end

    if state.phase == "sort" then
        if not state.plan then
            state.plan = Plan(state.slots)
            if not state.plan then -- item info is loading
                CheckStalled(state)
                return
            end
        end
        local moves, finished = SortStep(state)
        if moves == nil then
            -- Something was used, looted or moved meanwhile: start over.
            state.replans = state.replans + 1
            if state.replans > MAX_REPLANS then
                Stop(L["Sorting stopped: your bags kept changing. Try again."])
            else
                state.plan, state.phase = nil, "stack"
            end
            return
        elseif finished then
            Stop(ns.Say("sorted", L["Bags sorted."]))
            return
        end
        moved = moves
    end

    if moved > 0 then
        state.moves = state.moves + moved
        state.lastMove = GetTime()
    else
        CheckStalled(state)
    end
end

-- Starts sorting the bags, or stops a sort that's running.
function ns.SortBags()
    if sorter then
        Stop(L["Sorting stopped."])
        return
    end
    if InCombatLockdown() then
        ns.Print(L["You can't sort your bags in combat."])
        return
    end
    if ns.IsSelling() or ns.IsBuyingBack() then
        ns.Print(L["Wait until your goblin has finished at the vendor."])
        return
    end
    if CursorHasItem() then
        ns.Print(L["Put down the item on your cursor first."])
        return
    end
    sorter = {
        slots = SortableSlots(), phase = "stack", stackTries = {},
        moves = 0, replans = 0, lastMove = GetTime(),
    }
    sorter.ticker = C_Timer.NewTicker(STEP_INTERVAL, Step)
    if ns.UpdateSortButtons then ns.UpdateSortButtons() end
end

function ns.IsSorting()
    return sorter ~= nil
end

------------------------------------------------------------------------
-- Button on the default bags
------------------------------------------------------------------------

local BLIZZARD_GOLD = { 1, 0.82, 0, 1 }
local button

local function PaintButton()
    local color = sorter and ns.UI.C.text or BLIZZARD_GOLD
    button.icon:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
end

local function ShowTooltip(self)
    local C = ns.UI.C
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L["Sort bags"], C.gold[1], C.gold[2], C.gold[3])
    if sorter then
        GameTooltip:AddLine(L["Sorting... Click to stop."], 1, 1, 1, true)
    else
        GameTooltip:AddLine(L["Stacks and sorts everything in your bags. Junk goes last."], 1, 1, 1, true)
    end
    GameTooltip:Show()
end

-- Sits between the close button and the destroy button on the backpack,
-- combined or not (the destroy button places itself to its left).
local function Place()
    local frame
    if ContainerFrameCombinedBags and ContainerFrameCombinedBags:IsShown() then
        frame = ContainerFrameCombinedBags
    elseif ContainerFrame1 and ContainerFrame1:IsShown() then
        frame = ContainerFrame1
    end
    if not frame or not ns.db.sortButton then
        button:Hide()
        return
    end
    button:SetParent(frame)
    ns.MatchParentLayer(button) -- above the bag's border art and close button
    button:ClearAllPoints()
    local close = frame.CloseButton or (frame:GetName() and _G[frame:GetName() .. "CloseButton"])
    if close then
        button:SetPoint("RIGHT", close, "LEFT", -1, 0)
    else
        button:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -30, -4)
    end
    button:Show()
end

function ns.SetupSortButton()
    button = CreateFrame("Button", nil, UIParent)
    ns.sortButton = button -- the destroy button sits to its left
    button:SetSize(20, 20)
    button:Hide()
    button.icon = ns.UI.Icon(button, "icon-sort", 18, BLIZZARD_GOLD)
    button.icon:SetPoint("CENTER")
    button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    button:SetScript("OnMouseDown", function() button.icon:SetPoint("CENTER", 1, -1) end)
    button:SetScript("OnMouseUp", function() button.icon:SetPoint("CENTER") end)
    button:SetScript("OnClick", function(self)
        ns.SortBags()
        if GameTooltip:IsOwned(self) then ShowTooltip(self) end
    end)
    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", GameTooltip_Hide)

    for _, frame in ipairs({ ContainerFrameCombinedBags, ContainerFrame1 }) do
        if frame then
            frame:HookScript("OnShow", Place)
            frame:HookScript("OnHide", Place)
        end
    end
    Place()
    if ns.UpdateDestroyButtons then ns.UpdateDestroyButtons() end -- make room for it
end

-- Follows the setting, the destroy button's place and whether a sort runs.
function ns.UpdateSortButtons()
    if not button then return end
    Place()
    PaintButton()
end

-- A line for /goblin debug about the sort button.
function ns.DebugSortButton(add)
    if not button then
        add("Sort button: not created (BagSort.lua not loaded?)")
        return
    end
    local parent = button:GetParent()
    local point, relativeTo = button:GetPoint(1)
    add("Sort button: setting %s, shown %s, visible %s, parent %s, level %d, anchor %s to %s, icon %s",
        tostring(ns.db.sortButton), tostring(button:IsShown()), tostring(button:IsVisible()),
        (parent and (parent:GetName() or tostring(parent))) or "none", button:GetFrameLevel(), tostring(point),
        (relativeTo and (relativeTo:GetName() or tostring(relativeTo))) or "none", tostring(button.icon:GetTexture()))
end
