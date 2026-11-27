-- Bagnon's bags: Pocket Goblin's icons on its item slots, and the trash can
-- and open button in the row of buttons at the top left of its inventory
-- window (with its bag toggle, sort and search buttons). Its own sort button
-- stays (Pocket Goblin's isn't added there).

local ADDON_NAME, ns = ...

local Bagnon = Bagnon
if not (Bagnon and Bagnon.ContainerItem and Bagnon.Inventory and Bagnon.Frames) then return end

local BUTTON_SIZE = 20 -- Bagnon's own top-row buttons

------------------------------------------------------------------------
-- Icons on the item slots
------------------------------------------------------------------------

-- Bagnon's item buttons are the game's bag item buttons, so they take the
-- same icons as the default bags. Only your own bags: not the bank, and not
-- another character's bags (Bagnon shows those from its records).
local function Paint(button)
    local bag, slot = button:GetBag(), button:GetID()
    local own = ns.db and bag and slot and slot > 0 and bag >= 0 and bag <= ns.LAST_BAG
        and not button:IsCached()
    if own then
        ns.PaintItemOverlay(button, bag, slot)
    else
        ns.PaintItemOverlay(button, nil)
    end
end

-- UpdateBorder runs whenever Bagnon repaints a slot (item changed, locked,
-- searched), and puts back its own junk coin and greying, so ours go on after.
hooksecurefunc(Bagnon.ContainerItem, "UpdateBorder", Paint)

local function InventoryFrame()
    local frame = Bagnon.Frames:Get("inventory")
    if frame and frame[0] and frame:IsShown() then return frame end
end

-- Repaints the open inventory after Pocket Goblin's rules change (Bagnon
-- repaints on its own when the bags change). Called from RefreshOverlays,
-- which already waits a frame.
function ns.RefreshBagnon()
    local frame = InventoryFrame()
    local items = frame and rawget(frame, "ItemGroup")
    for _, button in ipairs(items and items.buttons or {}) do
        if button:IsShown() then Paint(button) end
    end
end

------------------------------------------------------------------------
-- Trash can and open button in the top row
------------------------------------------------------------------------

local trash, open
local shown = {} -- [button] = shown at the last layout, to redo it only on a change

local function Wanted(frame)
    -- Not while looking at another character's bags: they act on yours.
    if not ns.db or frame:IsCached() then return false, false end
    return ns.db.destroyButton and true or false, ns.db.openButton and true or false
end

-- Bagnon lays out its top row from this list, left to right after the bag
-- toggle, then its sort and search buttons; it shows and hides them itself.
local GetExtraButtons = Bagnon.Inventory.GetExtraButtons
function Bagnon.Inventory:GetExtraButtons(...)
    local list = {}
    for _, button in ipairs(GetExtraButtons(self, ...) or {}) do list[#list + 1] = button end

    if not trash then
        trash = ns.CreateDestroyButton(self, BUTTON_SIZE, "bagnon")
        open = ns.CreateOpenButton(BUTTON_SIZE, "bagnon")
        open:SetParent(self)
        ns.bagnonOpenButton = open
        C_Timer.After(0, function() -- fill them in (what to destroy, how many to open)
            ns.UpdateDestroyButtons()
            ns.UpdateOpenButtons()
        end)
    end
    local wantTrash, wantOpen = Wanted(self)
    shown[trash], shown[open] = wantTrash, wantOpen
    if not wantTrash then trash:Hide() end
    if not wantOpen then open:Hide() end
    list[#list + 1] = wantTrash and trash or false
    list[#list + 1] = wantOpen and open or false
    return list
end

-- Lays the row out again when one of our buttons was switched on or off
-- (Bagnon lays it out itself when the window opens).
function ns.SyncBagnon()
    local frame = trash and InventoryFrame()
    if not frame then return end
    local wantTrash, wantOpen = Wanted(frame)
    if shown[trash] == wantTrash and shown[open] == wantOpen then return end
    frame:Layout()
end
