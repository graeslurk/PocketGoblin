-- The first-time tour: small speech bubbles, like Fanny Pack's, each with a
-- pointer at what it explains. Pocket Goblin has nothing on screen at login,
-- so the tour comes in two parts that wait for what they show: the bags part
-- the first time your bags open (the coin on junk, the trash can, the open
-- button and the window), the vendor part the first time the vendor panel
-- shows. A new install gets both; /goblin tour or the General page's "Show
-- the tour" plays them again. Closing the bags or the vendor pauses a part
-- until they open again; a fight pauses it until the fight is over.

local ADDON_NAME, ns = ...
local L = ns.L

local MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\"
local WIDTH = 290
local PADDING = 16
local POINTER = 22 -- the pointer's size; it reaches about 14 out of the bubble
local GAP = 20     -- between the bubble and what it points at

-- The first of the frames that's on screen.
local function FirstVisible(list)
    for _, frame in ipairs(list or {}) do
        if frame and frame:IsVisible() then return frame end
    end
end

local function TrashCan() return FirstVisible(ns.destroyButtons) end
local function OpenButton() return FirstVisible(ns.openButtons) end
local function AnyBagButton() return TrashCan() or OpenButton() end

local function VendorPanel()
    local panel = PocketGoblinMerchantPanel
    return panel and panel:IsVisible() and panel or nil
end

-- Whether what a part shows is open: the bags (a trash can or open button
-- on screen), or the vendor panel.
local OPEN = { bags = AnyBagButton, vendor = VendorPanel }

local PARTS = {
    bags = {
        {
            title = L["Junk gets a coin"],
            text = L["Items with a coin are sold at the next vendor. Alt+Right-click any item to put it on the auto-sell list or the keep list."],
            target = function() return (ns.VisibleCoinItem and ns.VisibleCoinItem()) or AnyBagButton() end,
        },
        {
            title = L["The trash can"],
            text = L["Bags full and no vendor near? It destroys your cheapest junk, after asking. Hover it to see what goes. You can also set a key for it in Key Bindings, under Pocket Goblin."],
            target = TrashCan,
        },
        {
            title = L["Open containers"],
            text = L["Opens clams, sacks of loot and other containers in your bags, one per click. There's a hotkey for it too."],
            target = OpenButton,
        },
        {
            title = L["Your goblin's window"],
            text = L["Your auto-sell and keep lists, the history of every sale, and all the settings. Type /goblin or click the minimap button."],
            target = function()
                local minimap = PocketGoblinMinimapButton
                return (minimap and minimap:IsVisible() and minimap) or AnyBagButton()
            end,
        },
    },
    vendor = {
        {
            title = L["Your goblin at the vendor"],
            text = L["This panel sells your junk, lists the items that wait for your OK, and buys back anything sold by mistake."],
            target = VendorPanel,
            side = true, -- beside the panel: it's tall
        },
    },
}

local bubble
local part, steps, step -- the part showing (or paused), its steps with a target, and the step
local paused = false

-- Saved per account: [part] = "pending" or "done".
local function State()
    PocketGoblinDB.tour = PocketGoblinDB.tour or {}
    return PocketGoblinDB.tour
end

local function Pending(key)
    return State()[key] == "pending"
end

-- Ends the part showing; skip ends the whole tour.
local function Finish(skip)
    local state = State()
    if part then state[part] = "done" end
    if skip then
        for key in pairs(PARTS) do state[key] = "done" end
    end
    part, steps, step, paused = nil, nil, nil, false
    if bubble then bubble:Hide() end
end

local function CreateBubble()
    local UI = ns.UI
    local C = UI.C
    bubble = CreateFrame("Frame", "PocketGoblinTour", UIParent)
    bubble:SetFrameStrata("FULLSCREEN_DIALOG") -- above the bags and the vendor
    bubble:SetClampedToScreen(true)
    bubble:EnableMouse(true)
    bubble:SetWidth(WIDTH)
    UI.Rounded(bubble, "BACKGROUND", C.bg)
    -- A gold border, two pixels wide, so the bubble stands out on any scenery.
    UI.Rounded(bubble, "BORDER", C.gold, "rounded-border")
    local inner = UI.Rounded(bubble, "BORDER", C.gold, "rounded-border")
    inner:ClearAllPoints()
    inner:SetPoint("TOPLEFT", 1, -1)
    inner:SetPoint("BOTTOMRIGHT", -1, 1)
    bubble:Hide()

    -- The pointer: dark, in a gold outline (a bigger gold one behind it).
    bubble.pointerEdge = bubble:CreateTexture(nil, "BORDER", nil, -1)
    bubble.pointerEdge:SetTexture(MEDIA .. "pointer")
    bubble.pointerEdge:SetSize(POINTER + 8, POINTER + 8)
    bubble.pointerEdge:SetVertexColor(C.gold[1], C.gold[2], C.gold[3], 1)
    bubble.pointer = bubble:CreateTexture(nil, "ARTWORK", nil, -8) -- over the border where they join
    bubble.pointer:SetTexture(MEDIA .. "pointer")
    bubble.pointer:SetSize(POINTER, POINTER)
    bubble.pointer:SetVertexColor(C.bg[1], C.bg[2], C.bg[3], 1)

    -- A thin gold line on the left, like the window's cards.
    local accent = bubble:CreateTexture(nil, "ARTWORK")
    accent:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    accent:SetSize(3, 14)
    accent:SetPoint("TOPLEFT", PADDING, -PADDING - 1)

    bubble.title = UI.Text(bubble, 14, C.text)
    bubble.title:SetPoint("TOPLEFT", PADDING + 10, -PADDING)
    bubble.counter = UI.Text(bubble, 11, C.muted)
    bubble.counter:SetPoint("TOPRIGHT", -PADDING, -PADDING - 2)
    bubble.text = UI.Text(bubble, 12, C.muted)
    bubble.text:SetPoint("TOPLEFT", bubble.title, "BOTTOMLEFT", -10, -8)
    bubble.text:SetWidth(WIDTH - PADDING * 2)

    bubble.next = UI.CreateButton(bubble, L["Next"], 80, "primary")
    bubble.next:SetHeight(26)
    bubble.next:SetPoint("BOTTOMRIGHT", -PADDING + 4, PADDING - 4)
    bubble.next:SetScript("OnClick", function()
        if step >= #steps then
            Finish()
        else
            ns.ShowTourStep(step + 1)
        end
    end)

    bubble.open = UI.CreateButton(bubble, L["Open Pocket Goblin"], 140)
    bubble.open:SetHeight(26)
    bubble.open:SetPoint("RIGHT", bubble.next, "LEFT", -8, 0)
    bubble.open:SetScript("OnClick", function()
        Finish()
        ns.ToggleWindow(true)
    end)

    -- "Skip tour": a quiet link at the bottom left.
    bubble.skip = CreateFrame("Button", nil, bubble)
    bubble.skip.label = UI.Text(bubble.skip, 12, C.muted)
    bubble.skip.label:SetPoint("LEFT")
    bubble.skip.label:SetText(L["Skip tour"])
    bubble.skip:SetSize(bubble.skip.label:GetStringWidth() + 4, 20)
    bubble.skip:SetPoint("BOTTOMLEFT", PADDING, PADDING - 1)
    bubble.skip:SetScript("OnEnter", function(self) self.label:SetTextColor(C.text[1], C.text[2], C.text[3]) end)
    bubble.skip:SetScript("OnLeave", function(self) self.label:SetTextColor(C.muted[1], C.muted[2], C.muted[3]) end)
    bubble.skip:SetScript("OnClick", function() Finish(true) end)

    -- The bags or the vendor closed: wait for them to open again.
    bubble:SetScript("OnUpdate", function(self)
        if self.target and not self.target:IsVisible() then
            paused = true
            self:Hide()
        end
    end)
end

-- Places the bubble above or below the target (or beside it, for side),
-- wherever there's room, with the pointer at it.
local function Place(target, side)
    bubble:ClearAllPoints()
    for _, pointer in ipairs({ bubble.pointer, bubble.pointerEdge }) do
        pointer:ClearAllPoints()
        pointer:SetTexCoord(0, 1, 0, 1)
        pointer:SetRotation(0)
    end
    -- The pointer art points down; the dark pointer covers the border where
    -- they meet, so the bubble and its pointer read as one shape.
    local function point(rotation, flip, anchor, relative, x, y)
        for _, pointer in ipairs({ bubble.pointer, bubble.pointerEdge }) do
            if flip then pointer:SetTexCoord(0, 1, 1, 0) end
            if rotation ~= 0 then pointer:SetRotation(rotation) end
            pointer:SetPoint(anchor, bubble, relative, x, y)
        end
    end
    if side then
        local right = (target:GetRight() or 0) + WIDTH + GAP + 10 < UIParent:GetRight()
        if right then
            bubble:SetPoint("LEFT", target, "RIGHT", GAP, 0)
            point(-math.pi / 2, false, "RIGHT", "LEFT", 2, 0) -- pointing left
        else
            bubble:SetPoint("RIGHT", target, "LEFT", -GAP, 0)
            point(math.pi / 2, false, "LEFT", "RIGHT", -2, 0) -- pointing right
        end
        return
    end
    local above = (target:GetTop() or 0) + bubble:GetHeight() + GAP + 10 < UIParent:GetTop()
    if above then
        bubble:SetPoint("BOTTOM", target, "TOP", 0, GAP)
        point(0, false, "TOP", "BOTTOM", 0, 2) -- pointing down
    else
        bubble:SetPoint("TOP", target, "BOTTOM", 0, -GAP)
        point(0, true, "BOTTOM", "TOP", 0, -2) -- pointing up
    end
end

-- Shows step i of the part showing; a step whose target has gone is skipped.
-- With the bags or the vendor closed, it waits for them instead.
function ns.ShowTourStep(i)
    local info = steps and steps[i]
    if not info then return Finish() end
    if not OPEN[part]() then
        step, paused = i, true
        if bubble then bubble:Hide() end
        return
    end
    local target = info.target()
    if not target then return ns.ShowTourStep(i + 1) end
    if not bubble then CreateBubble() end
    step = i

    local last = i == #steps
    bubble.title:SetText(info.title)
    bubble.counter:SetText(#steps > 1 and L["%d of %d"]:format(i, #steps) or "")
    bubble.text:SetText(info.text)
    bubble.next.label:SetText(last and L["Done"] or L["Next"])
    bubble.open:SetShown(last and part == "bags")
    bubble.skip:SetShown(not last)
    bubble:SetHeight(PADDING + bubble.title:GetStringHeight() + 8 + bubble.text:GetStringHeight() + 14 + 26
        + PADDING - 4)

    Place(target, info.side)
    bubble.target = target
    paused = false
    bubble:Show()
end

-- Starts a part from its first step, with the steps there's something to
-- point at for (no open button step with that button off). In a fight it
-- waits for the fight to end.
local function StartPart(key)
    if not Pending(key) or (bubble and bubble:IsShown()) then return end
    local list = {}
    for _, info in ipairs(PARTS[key]) do
        if info.target() then list[#list + 1] = info end
    end
    if #list == 0 then return end
    part, steps, step = key, list, 1
    if InCombatLockdown() then
        paused = true
        return
    end
    ns.ShowTourStep(1)
end

-- What's open now decides where it goes on: the part that was paused, or
-- one waiting to start. A moment later, once the bags have painted their
-- icons and the panel has its size.
local waiting = false
local function Resume(key)
    if waiting then return end
    waiting = true
    C_Timer.After(0.4, function()
        waiting = false
        if InCombatLockdown() or (bubble and bubble:IsShown()) then return end
        if part == key and paused then
            ns.ShowTourStep(step)
        else
            -- Another part waiting for its window starts over next time.
            part, steps, step, paused = nil, nil, nil, false
            StartPart(key)
        end
    end)
end

-- A trash can or open button came on screen: the bags opened.
function ns.OnBagButtonShown()
    if part == "bags" or Pending("bags") then Resume("bags") end
end

function ns.OnVendorPanelShown()
    if part == "vendor" or Pending("vendor") then Resume("vendor") end
end

-- /goblin tour and the General page: plays both parts again, the bags part
-- straight away (opening the bags), the vendor part at the next vendor.
function ns.StartTour()
    Finish()
    local state = State()
    for key in pairs(PARTS) do state[key] = "pending" end
    if VendorPanel() then
        Resume("vendor")
    elseif AnyBagButton() then
        Resume("bags")
    else
        OpenAllBags() -- the bags part starts as they open
        C_Timer.After(0.5, function()
            if not AnyBagButton() and not VendorPanel() then
                -- No trash can or open button in these bags (both turned off).
                ns.Print(L["Open your bags or visit a vendor to see the tour."])
            end
        end)
    end
end

-- At login: a new install gets the tour, when the bags or a vendor open.
function ns.InitTour()
    if not ns.freshInstall then return end
    local state = State()
    for key in pairs(PARTS) do
        if state[key] == nil then state[key] = "pending" end
    end
end

-- A fight pauses the tour; it goes on with the same step afterwards.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        if bubble and bubble:IsShown() then
            paused = true
            bubble:Hide()
        end
    elseif paused and part then
        Resume(part)
    end
end)
