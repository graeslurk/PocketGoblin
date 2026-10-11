-- Pocket Goblin: sells grey items and flagged items automatically at vendors.
-- Alt+Right-click an item in your bags to flag it (or to keep a grey item).

local ADDON_NAME, ns = ...
local L = ns.L

local PREFIX = "|cffd4a72cPocket Goblin|r: "
local SELL_INTERVAL = 0.2 -- seconds between each sale, avoids server throttling
local BUYBACK_SIZE = 12   -- the vendor's buyback list holds this many sales
local POOR = Enum.ItemQuality and Enum.ItemQuality.Poor or 0
local LAST_BAG = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
local JUNK_ATLAS = "bags-junkcoin"
local COIN_SIZE = 17 -- at 100% icon scale
local COMMON = Enum.ItemQuality and Enum.ItemQuality.Common or 1
local RARE = Enum.ItemQuality and Enum.ItemQuality.Rare or 3
local MAX_HISTORY = 30 -- vendor visits kept per character
local WEAPON = Enum.ItemClass and Enum.ItemClass.Weapon or 2
local ARMOR = Enum.ItemClass and Enum.ItemClass.Armor or 4
local FISHING_POLE = Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Fishingpole or 20
local THROWN = Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Thrown or 16
-- White gear the white-gear rule never sells: profession tools count as weapons
-- in Classic (Mining Pick, Blacksmith Hammer, Skinning Knife, Arclight Spanner).
local NEVER_SELL_GEAR = { [2901] = true, [5956] = true, [7005] = true, [6219] = true }
local COSMETIC_SLOTS = { INVTYPE_BODY = true, INVTYPE_TABARD = true }

-- Weapon and armor types each class can ever use (Classic rules), by item
-- subclass ID. Used to sell soulbound gear the character can't use.
local AXE1H, AXE2H, BOW, GUN, MACE1H, MACE2H, POLEARM, SWORD1H, SWORD2H = 0, 1, 2, 3, 4, 5, 6, 7, 8
local STAFF, FIST, DAGGER, THROWN, CROSSBOW, WAND = 10, 13, 15, 16, 18, 19
local MISC, CLOTH, LEATHER, MAIL, PLATE, SHIELD, LIBRAM, IDOL, TOTEM = 0, 1, 2, 3, 4, 6, 7, 8, 9
local CLASS_GEAR = {
    WARRIOR = {
        weapons = { AXE1H, AXE2H, BOW, GUN, MACE1H, MACE2H, POLEARM, SWORD1H, SWORD2H, STAFF, FIST, DAGGER, THROWN, CROSSBOW },
        armor = { CLOTH, LEATHER, MAIL, PLATE, SHIELD },
    },
    PALADIN = {
        weapons = { AXE1H, AXE2H, MACE1H, MACE2H, POLEARM, SWORD1H, SWORD2H },
        armor = { CLOTH, LEATHER, MAIL, PLATE, SHIELD, LIBRAM },
    },
    HUNTER = {
        weapons = { AXE1H, AXE2H, BOW, GUN, POLEARM, SWORD1H, SWORD2H, STAFF, FIST, DAGGER, THROWN, CROSSBOW },
        armor = { CLOTH, LEATHER, MAIL },
    },
    ROGUE = {
        weapons = { BOW, GUN, MACE1H, SWORD1H, FIST, DAGGER, THROWN, CROSSBOW },
        armor = { CLOTH, LEATHER },
    },
    PRIEST = { weapons = { MACE1H, STAFF, DAGGER, WAND }, armor = { CLOTH } },
    SHAMAN = {
        weapons = { AXE1H, AXE2H, MACE1H, MACE2H, STAFF, FIST, DAGGER },
        armor = { CLOTH, LEATHER, MAIL, SHIELD, TOTEM },
    },
    MAGE = { weapons = { SWORD1H, STAFF, DAGGER, WAND }, armor = { CLOTH } },
    WARLOCK = { weapons = { SWORD1H, STAFF, DAGGER, WAND }, armor = { CLOTH } },
    DRUID = { weapons = { MACE1H, MACE2H, STAFF, FIST, DAGGER }, armor = { CLOTH, LEATHER, IDOL } },
}
local FALLBACK_ICON = "Interface\\Buttons\\UI-GroupLoot-Coin-Up"
local LOCK_ICON = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\icon-lock"
local LOCK_COLOR = { 0.55, 0.8, 1 }
local BAG_ADDONS = { "Baganator", "Bagnon", "AdiBags", "ArkInventory", "BetterBags", "Combuctor", "OneBag3" }

local defaults = {
    autoSell = true,  -- sell automatically when a vendor window opens
    sellBatchLimit = true, -- sell at most BUYBACK_SIZE items per go, so all of them can be bought back
    sellGreys = true, -- include all grey (poor) items
    sellWhiteGear = true, -- sell white weapons and armor...
    whiteGearLevel = 10,  -- ...from this character level (before it, you still use them)
    skipQuestGear = true, -- never sell gear that quests ask for (QuestGear.lua), unless flagged
    chat = true,         -- print messages to chat (sale summaries always print)
    goblinVoice = true,  -- chat lines and moods in the goblin's own words
    milestones = true,   -- celebrate sales milestones in chat
    tooltipValue = true, -- show why and for how much an item sells, in its tooltip
    sellCheapWhites = false,    -- sell white items cheaper than cheapWhiteLimit...
    cheapWhiteLimit = 1000,     -- ...copper per item (10 silver); not food, drink or ammo
    sellUnusable = false,  -- sell soulbound gear this class can never use
    sellOldFood = true,    -- sell food/drink when carrying a better kind you can use...
    oldFoodMinBetter = 5,  -- ...and at least this many of it
    sellOutgrown = false,  -- sell soulbound gear far below this character's level...
    outgrownLevels = 15,   -- ...by at least this many levels
    merchantPanel = true,  -- buyback panel next to the vendor window...
    merchantPanelAll = true, -- ...listing your own sales too, not just Pocket Goblin's
    autoRepair = true,     -- repair at vendors that can
    repairGuild = false,   -- use guild bank funds first
    bagWarning = true,     -- warn on the destroy button when bags are nearly full...
    bagWarningSlots = 3,   -- ...at this many free slots or fewer
    destroyButton = true,  -- show the "destroy cheapest junk" button on the bags
    destroyConfirm = true, -- ask before destroying
    destroyProtect = true, -- never destroy junk worth more than destroyLimit
    destroyLimit = 5000,   -- copper (50 silver); stacks count their total value
    showMinimap = true,
    minimapAngle = 220,  -- degrees around the minimap
    showIcons = true, -- coin icon on junk in the default bags
    greyOut = true,   -- desaturate junk in the default bags
    iconScale = 1,    -- coin icon size, 1 = 100%
    iconCorner = "TOPLEFT", -- TOPLEFT, TOPRIGHT, BOTTOMLEFT or BOTTOMRIGHT
    items = {},       -- [itemID] = true (auto-sell list) | false (keep list: never sold)
    keepWords = {},   -- never sell items whose name contains one of these (lowercase)
    keepClasses = {}, -- [item class ID] = true: never sell items of this type
    keepValuable = false, -- never sell items worth more than keepValueLimit...
    keepValueLimit = 10000, -- ...copper per item (1 gold)
    keepIcon = true,  -- lock icon on items on the keep list
    addedAt = {},     -- [itemID] = time() it was added to the auto-sell list
    -- List filters in the window. Unset keys (classID etc.) mean "all".
    filters = {
        sell = { qualities = {}, inBags = false, sort = "name" },
        quest = { qualities = {}, flaggedOnly = false, hideLow = false, hideHigh = false, sort = "name" },
        keep = { qualities = {}, inBags = false, sort = "name" },
        history = { source = "all" }, -- "all", "goblin" or "you"
    },
}

-- Per-character data (not part of profiles).
local CHARACTER_DEFAULTS = {
    history = {},  -- vendor visits, newest first: { time, vendor, items = { ... }, repairs = { ... } }
    earned = 0,    -- copper from Pocket Goblin's sales, all time
    sold = 0,      -- item stacks Pocket Goblin sold, all time
    allEarned = 0, -- copper from every vendor sale (Pocket Goblin's and yours)
    day = "",      -- date of the "today" counters
    today = 0,
    allToday = 0,
    repairs = 0,      -- copper spent on repairs (your own gold)
    repairsGuild = 0, -- copper the guild bank paid for repairs
    milestones = {}, -- [milestone key] = true once reached
}

local DEFAULT_PROFILE = "Default"

local db -- the active profile (PocketGoblinDB.profiles[name])
local characterKey
local charData -- PocketGoblinDB.characters[characterKey]
local session = { earned = 0, sold = 0, allEarned = 0 }
local pendingOwnSales = {} -- { itemID, count } Pocket Goblin sold, not yet seen in the buyback list
local vendorName
local currentVisit -- history entry for the open vendor window
local merchantOpen = false
local sellTicker, sellSummary

ns.POOR = POOR
ns.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(ADDON_NAME, "Version")
if not ns.VERSION or ns.VERSION:find("^@") then
    ns.VERSION = "dev" -- running from source; the CurseForge packager fills in the real version
else
    ns.VERSION = ns.VERSION:gsub("^v", "") -- the packager uses the tag name, e.g. "v1.0.0"
end

local function Print(msg, ...)
    print(PREFIX .. (select("#", ...) > 0 and msg:format(...) or msg))
end
ns.Print = Print

-- Messages the user can mute with the chat setting.
local function Notify(msg, ...)
    if db and db.chat then Print(msg, ...) end
end

local function ItemIDFromLink(link)
    return link and tonumber(link:match("item:(%d+)"))
end

local function ItemLabel(itemID)
    local _, link = C_Item.GetItemInfo(itemID)
    return link or ("item:" .. itemID)
end


local function GetMouseFrame()
    if GetMouseFoci then
        return GetMouseFoci()[1]
    elseif GetMouseFocus then
        return GetMouseFocus()
    end
end

local function RefreshWindow()
    if ns.RefreshWindow then ns.RefreshWindow() end
end

-- Which keep rule protects an item: "name" (plus the matching word),
-- "type" or "valuable"; nil if none does. Items you flag yourself ignore
-- these rules.
local function KeepRule(itemID)
    if #db.keepWords > 0 then
        local name = C_Item.GetItemInfo(itemID)
        if name then
            name = name:lower()
            for _, word in ipairs(db.keepWords) do
                if name:find(word, 1, true) then return "name", word end
            end
        end
    end
    local classID = select(6, C_Item.GetItemInfoInstant(itemID))
    if classID and db.keepClasses[classID] then return "type" end
    if db.keepValuable then
        local price = select(11, C_Item.GetItemInfo(itemID)) or 0
        if price > db.keepValueLimit then return "valuable" end
    end
end
ns.KeepRule = KeepRule

-- A short description of a keep rule, e.g. 'name contains "potion"'.
function ns.KeepRuleText(rule, word)
    if rule == "name" then return (L['name contains "%s"']):format(word) end
    if rule == "type" then return L["its item type"] end
    return L["worth more than "] .. GetMoneyString(db.keepValueLimit, true)
end

-- True if the item should be sold, judged only by flags, keep rules and
-- quality (for items that aren't in the bags).
local function IsJunk(itemID, quality)
    local flag = db.items[itemID]
    if flag ~= nil then return flag end
    if KeepRule(itemID) then return false end
    return db.sellGreys and quality == POOR
end

local classUsable -- { weapons = set, armor = set } for the player's class

local function CanClassUse(classID, subClassID)
    if not classUsable then
        local gear = CLASS_GEAR[select(2, UnitClass("player"))]
        if not gear then return true end -- unknown class: never call gear unusable
        classUsable = { weapons = {}, armor = { [MISC] = true } }
        for _, id in ipairs(gear.weapons) do classUsable.weapons[id] = true end
        for _, id in ipairs(gear.armor) do classUsable.armor[id] = true end
    end
    if classID == WEAPON then return classUsable.weapons[subClassID] == true end
    if classID == ARMOR then return classUsable.armor[subClassID] == true end
    return true
end

-- White weapons and armor the white-gear rule may sell: not profession
-- tools, fishing poles, thrown weapons, shirts or tabards.
local function IsWhiteGear(itemID)
    if NEVER_SELL_GEAR[itemID] then return false end
    local _, _, _, equipLoc, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
    if not equipLoc or equipLoc == "" or COSMETIC_SLOTS[equipLoc] then return false end
    if classID == WEAPON then
        return subClassID ~= FISHING_POLE and subClassID ~= THROWN
    end
    return classID == ARMOR
end

local function InEquipmentSet(bag, slot)
    local getInfo = C_Container.GetContainerItemEquipmentSetInfo
    if not getInfo then return false end
    local ok, inSet = pcall(getInfo, bag, slot)
    return ok and inSet or false
end

------------------------------------------------------------------------
-- Food and drink you've outgrown
------------------------------------------------------------------------

local CONSUMABLE = Enum.ItemClass and Enum.ItemClass.Consumable or 0
local PROJECTILE = Enum.ItemClass and Enum.ItemClass.Projectile or 6
local FOOD_SPELL, DRINK_SPELL = 433, 430 -- the basic "Food" and "Drink" effects

local foodKinds = {} -- [itemID] = "food" | "drink" | false (cached)
local bestFood = {}  -- [kind] = highest required level you carry enough of and can use

local function SpellName(spellID)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(spellID) end
    return GetSpellInfo and GetSpellInfo(spellID)
end

-- Conjured food and water vanish when you log out, so they never count as
-- better than food you'd keep. Recognised by the game's "Conjured Item"
-- tooltip line.
local conjured = {} -- [itemID] = true/false (cached)

local function IsConjured(itemID)
    if conjured[itemID] == nil then
        local data = C_TooltipInfo and C_TooltipInfo.GetItemByID(itemID)
        local found = false
        for _, line in ipairs(data and data.lines or {}) do
            if ITEM_CONJURED and line.leftText == ITEM_CONJURED then found = true end
        end
        if not data then return false end -- not loaded yet; check again later
        conjured[itemID] = found
    end
    return conjured[itemID]
end

-- Food that gives Well Fed is eaten for its buff, so it's never outgrown.
local function IsBuffFood(itemID)
    local data = C_TooltipInfo and C_TooltipInfo.GetItemByID(itemID)
    for _, line in ipairs(data and data.lines or {}) do
        local text = line.leftText and line.leftText:lower()
        if text and text:find(L["well fed"], 1, true) then return true end
    end
    return false
end

-- "food" or "drink" for plain food and drink, nil for anything else,
-- including buff food and food-and-drink combos. Goes by the item's use
-- effect: Classic items are plain "Consumable", without a food subtype.
local function FoodKind(itemID)
    local kind = foodKinds[itemID]
    if kind ~= nil then return kind or nil end

    local classID = select(6, C_Item.GetItemInfoInstant(itemID))
    if classID ~= CONSUMABLE or not C_Item.GetItemSpell then
        foodKinds[itemID] = false
        return nil
    end
    local spell = C_Item.GetItemSpell(itemID)
    local foodName, drinkName = SpellName(FOOD_SPELL), SpellName(DRINK_SPELL)
    if not spell or not foodName or not C_Item.IsItemDataCachedByID(itemID) then
        C_Item.RequestLoadItemDataByID(itemID)
        return nil -- not loaded yet; decide (and remember) next time
    end
    kind = (spell == foodName and "food") or (spell == drinkName and "drink") or false
    if kind and IsBuffFood(itemID) then kind = false end
    foodKinds[itemID] = kind
    return kind or nil
end

-- Finds the best food and drink in the bags: the highest required level
-- you can use, counting only kinds you carry at least oldFoodMinBetter of.
-- Conjured items (and anything without a vendor price) don't count.
local function UpdateBestFood()
    wipe(bestFood)
    if not db or not db.sellOldFood then return end
    local playerLevel = UnitLevel("player")
    local carried = { food = {}, drink = {} } -- [kind][required level] = count
    for bag = 0, LAST_BAG do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local kind = info and not info.hasNoValue and FoodKind(info.itemID)
            if kind and not IsConjured(info.itemID) then
                local level = select(5, C_Item.GetItemInfo(info.itemID)) or 0
                if level <= playerLevel then
                    carried[kind][level] = (carried[kind][level] or 0) + (info.stackCount or 1)
                end
            end
        end
    end
    for kind, levels in pairs(carried) do
        for level, count in pairs(levels) do
            if count >= db.oldFoodMinBetter and level > (bestFood[kind] or -1) then
                bestFood[kind] = level
            end
        end
    end
end
ns.UpdateBestFood = UpdateBestFood

local REASONS = {
    flagged = L["on your list"],
    grey = L["grey item"],
    whiteGear = L["white gear"],
    oldFood = L["you have better"],
    cheap = L["cheap white item"],
    unusable = L["your class can't use it"],
    outgrown = "outgrown",
}
ns.REASONS = REASONS

-- Why the item in a bag slot will be sold ("flagged", "grey", "cheap",
-- "unusable" or "outgrown"), or nil if it won't. info is the slot's
-- C_Container.GetContainerItemInfo. ignoreKeepRules answers "would it be
-- sold if no keep rule protected it?".
local function JunkReason(info, bag, slot, ignoreKeepRules)
    local itemID, quality = info.itemID, info.quality
    local flag = db.items[itemID]
    if flag ~= nil then return flag and "flagged" or nil end -- your lists come first
    if not ignoreKeepRules and KeepRule(itemID) then return nil end
    if InEquipmentSet(bag, slot) then return nil end
    if quality == POOR then return db.sellGreys and "grey" or nil end
    if info.hasNoValue or NEVER_SELL_GEAR[itemID] then return nil end
    if db.skipQuestGear and ns.QUEST_GEAR[itemID] then return nil end

    local _, _, _, equipLoc, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
    local isGear = (classID == WEAPON or classID == ARMOR) and equipLoc ~= nil and equipLoc ~= ""
        and not COSMETIC_SLOTS[equipLoc]

    if quality == COMMON and db.sellWhiteGear and UnitLevel("player") >= db.whiteGearLevel
        and IsWhiteGear(itemID) then
        return "whiteGear"
    end

    local foodKind = FoodKind(itemID)
    if foodKind and db.sellOldFood and bestFood[foodKind] then
        local level = select(5, C_Item.GetItemInfo(itemID)) or 0
        if level < bestFood[foodKind] then return "oldFood" end
    end

    -- Cheap white items, apart from food and drink (their own rule) and ammo.
    if quality == COMMON and db.sellCheapWhites and not foodKind and classID ~= PROJECTILE then
        local price = select(11, C_Item.GetItemInfo(itemID)) or 0
        if price > 0 and price < db.cheapWhiteLimit then return "cheap" end
    end

    if isGear and info.isBound and quality and quality <= RARE and (db.sellUnusable or db.sellOutgrown) then
        if db.sellUnusable and not CanClassUse(classID, subClassID) then return "unusable" end
        if db.sellOutgrown then
            local requiredLevel = select(5, C_Item.GetItemInfo(itemID)) or 0
            if requiredLevel > 0 and requiredLevel <= UnitLevel("player") - db.outgrownLevels then
                return "outgrown"
            end
        end
    end
end
ns.JunkReason = JunkReason

------------------------------------------------------------------------
-- Bag overlay: coin icon and greyed-out icon on items that will be sold
------------------------------------------------------------------------

local containerFrames, containerFrameSet = {}, {}
local overlayPending = false

local function GetBagAndSlot(button)
    local slot = button.GetID and button:GetID()
    if not slot or slot <= 0 then return end

    local bag
    if button.GetBagID then
        local ok, value = pcall(button.GetBagID, button)
        if ok then bag = value end
    end
    if bag == nil then
        bag = button.bagID
    end
    if bag == nil then
        -- Classic-style bags: the container frame's ID is the bag ID.
        local parent = button:GetParent()
        if parent and containerFrameSet[parent] and parent ~= ContainerFrameCombinedBags then
            bag = parent:GetID()
        end
    end
    if type(bag) == "number" then
        return bag, slot
    end
end

local function SetCoin(button, show)
    local coin = button.PocketGoblinIcon
    if show and not coin then
        coin = button:CreateTexture(nil, "OVERLAY", nil, 7)
        if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(JUNK_ATLAS) then
            coin:SetAtlas(JUNK_ATLAS)
        else
            coin:SetTexture(FALLBACK_ICON)
        end
        button.PocketGoblinIcon = coin
    end
    if coin then
        local size = COIN_SIZE * db.iconScale
        coin:SetSize(size, size)
        coin:ClearAllPoints()
        coin:SetPoint(db.iconCorner, 0, 0)
        coin:SetShown(show)
    end
    -- Blizzard shows its own coin on greys at vendors; ours replaces it.
    if show and button.JunkIcon then
        button.JunkIcon:Hide()
    end
end

local function GetIconTexture(button)
    local name = button:GetName()
    return button.icon or button.Icon or (name and _G[name .. "IconTexture"])
end

local function SetGreyedOut(button, greyed, locked)
    local icon = GetIconTexture(button)
    if not icon then return end
    if greyed then
        icon:SetDesaturated(true)
        icon:SetAlpha(0.6)
        button.PocketGoblinGreyed = true
    elseif button.PocketGoblinGreyed then
        -- Only undo our own change; Blizzard desaturates locked items.
        icon:SetDesaturated(locked)
        icon:SetAlpha(1)
        button.PocketGoblinGreyed = nil
    end
end

-- Lock icon on items on the keep list, in the same corner as the coin
-- (an item is never both junk and kept).
local function SetLock(button, show)
    local lock = button.PocketGoblinLock
    if show and not lock then
        lock = button:CreateTexture(nil, "OVERLAY", nil, 7)
        lock:SetTexture(LOCK_ICON)
        lock:SetVertexColor(LOCK_COLOR[1], LOCK_COLOR[2], LOCK_COLOR[3])
        button.PocketGoblinLock = lock
    end
    if lock then
        local size = COIN_SIZE * db.iconScale * 0.85
        lock:SetSize(size, size)
        lock:ClearAllPoints()
        lock:SetPoint(db.iconCorner, 0, 0)
        lock:SetShown(show)
    end
end

local function UpdateButtonOverlay(button)
    local bag, slot = GetBagAndSlot(button)
    local info = bag and C_Container.GetContainerItemInfo(bag, slot)
    local junk = info ~= nil and not info.hasNoValue and JunkReason(info, bag, slot) ~= nil

    SetCoin(button, junk and db.showIcons)
    SetLock(button, info ~= nil and db.keepIcon and db.items[info.itemID] == false)
    SetGreyedOut(button, junk and db.greyOut, info ~= nil and info.isLocked or false)
end

local function IsItemButton(frame)
    return type(frame) == "table" and frame.IconBorder ~= nil and frame.GetID ~= nil
end

-- Finds item buttons in the open bag frames several ways, since the
-- container code differs between client builds.
local function ForEachBagButton(fn)
    local seen = {}
    local function visit(button)
        if IsItemButton(button) and not seen[button] then
            seen[button] = true
            fn(button)
        end
    end

    for _, frame in ipairs(containerFrames) do
        if frame:IsShown() then
            if type(frame.Items) == "table" then
                for _, button in pairs(frame.Items) do visit(button) end
            end
            if frame.EnumerateValidItems then
                pcall(function()
                    for a, b in frame:EnumerateValidItems() do
                        visit(type(b) == "table" and b or a)
                    end
                end)
            end
            for _, child in ipairs({ frame:GetChildren() }) do
                visit(child)
            end
        end
    end
end

-- Batched to once per frame; also lets Blizzard finish updating the bags first.
local function RefreshOverlays()
    if overlayPending or not db then return end
    overlayPending = true
    C_Timer.After(0, function()
        overlayPending = false
        ForEachBagButton(UpdateButtonOverlay)
    end)
end
ns.RefreshOverlays = RefreshOverlays

local function HookContainerFrames()
    local function add(frame)
        if not frame or containerFrameSet[frame] then return end
        containerFrameSet[frame] = true
        containerFrames[#containerFrames + 1] = frame
        frame:HookScript("OnShow", RefreshOverlays)
        if frame.UpdateItems then
            hooksecurefunc(frame, "UpdateItems", RefreshOverlays)
        end
    end
    add(ContainerFrameCombinedBags)
    for i = 1, (NUM_CONTAINER_FRAMES or 13) do
        add(_G["ContainerFrame" .. i])
    end

    -- Blizzard resets the icon when an item changes or is (un)locked, so
    -- reapply straight away, then once more after the whole bag has updated.
    local function onButtonUpdated(button)
        if IsItemButton(button) and button.GetParent and containerFrameSet[button:GetParent()] then
            UpdateButtonOverlay(button)
            RefreshOverlays()
        end
    end
    for _, func in ipairs({ "SetItemButtonTexture", "SetItemButtonDesaturated" }) do
        if type(_G[func]) == "function" then
            hooksecurefunc(func, onButtonUpdated)
        end
    end
end

local function RegisterBaganatorPlugin()
    if not (Baganator and Baganator.API and Baganator.API.RegisterJunkPlugin) then return end
    Baganator.API.RegisterJunkPlugin("Pocket Goblin", "pocketgoblin", function(bag, slot, itemID, itemLink)
        itemID = itemID or ItemIDFromLink(itemLink)
        if not itemID then return false end
        -- Items in the bags get the full rules; others (bank etc.) flags only.
        local info = bag and slot and bag >= 0 and bag <= LAST_BAG and C_Container.GetContainerItemInfo(bag, slot)
        if info and info.itemID == itemID then
            return JunkReason(info, bag, slot) ~= nil
        end
        local _, _, quality = C_Item.GetItemInfo(itemLink or itemID)
        return IsJunk(itemID, quality) and true or false
    end)

    if Baganator.API.RegisterCornerWidget then
        Baganator.API.RegisterCornerWidget(L["Pocket Goblin: kept"], "pocketgoblin_keep",
            function(_, details)
                if not details.itemID then return nil end -- item info not ready yet
                return db.keepIcon and db.items[details.itemID] == false
            end,
            function(itemButton)
                local corner = CreateFrame("Frame", nil, itemButton)
                corner:SetSize(14, 14)
                local lock = corner:CreateTexture(nil, "OVERLAY")
                lock:SetAllPoints()
                lock:SetTexture(LOCK_ICON)
                lock:SetVertexColor(LOCK_COLOR[1], LOCK_COLOR[2], LOCK_COLOR[3])
                return corner
            end,
            { corner = "top_left", priority = 1 })
    end
end

local function FrameName(frame)
    if not frame then return "none" end
    return (frame.GetDebugName and frame:GetDebugName()) or frame:GetName() or tostring(frame)
end

-- Prints what the overlay code can see, to diagnose missing coin icons.
-- Collects details for a bug report and opens them in a window to copy
-- (or prints them to chat).
local function Debug(toChat)
    local lines = {}
    local function add(text, ...)
        lines[#lines + 1] = select("#", ...) > 0 and text:format(...) or text
    end

    local version, build, _, interface = GetBuildInfo()
    add("Pocket Goblin %s, client %s (%s, interface %s), locale %s",
        tostring(ns.VERSION), tostring(version), tostring(build), tostring(interface), GetLocale())
    add("Character: level %d %s, profile %s", UnitLevel("player"), select(2, UnitClass("player")) or "?",
        tostring(ns.GetProfileName()))

    local loaded = {}
    for _, name in ipairs(BAG_ADDONS) do
        if C_AddOns and C_AddOns.IsAddOnLoaded(name) then loaded[#loaded + 1] = name end
    end
    add("Bag addons loaded: %s", #loaded > 0 and table.concat(loaded, ", ") or "none")

    local shown, buttons, mapped, flagged = 0, 0, 0, 0
    for _, frame in ipairs(containerFrames) do
        if frame:IsShown() then shown = shown + 1 end
    end
    ForEachBagButton(function(button)
        buttons = buttons + 1
        local bag, slot = GetBagAndSlot(button)
        if bag then
            mapped = mapped + 1
            local itemID = C_Container.GetContainerItemID(bag, slot)
            if itemID and db.items[itemID] == true then flagged = flagged + 1 end
        end
    end)
    add("Bag frames: %d known, %d open. Item buttons: %d, with bag/slot: %d, flagged: %d.",
        #containerFrames, shown, buttons, mapped, flagged)

    ns.DebugDestroyButtons(add)
    add("Outgrown food: %s. Best food you carry enough of: level %s. Best drink: level %s.",
        db.sellOldFood and "on" or "off", tostring(bestFood.food or "none"), tostring(bestFood.drink or "none"))

    local sellCount, keepCount = 0, 0
    for _, flag in pairs(db.items) do
        if flag then sellCount = sellCount + 1 else keepCount = keepCount + 1 end
    end
    add("Lists: %d on the auto-sell list, %d kept. Junk in bags: %d items.", sellCount, keepCount,
        (ns.GetJunkSummary()))
    local settings = {}
    for _, key in ipairs({ "autoSell", "sellGreys", "sellWhiteGear", "sellOldFood", "sellCheapWhites",
        "sellUnusable", "sellOutgrown", "skipQuestGear", "keepValuable", "autoRepair", "destroyButton" }) do
        settings[#settings + 1] = key .. "=" .. tostring(db[key])
    end
    add("Settings: %s", table.concat(settings, ", "))

    local focus = GetMouseFrame()
    if focus then
        add("Mouse over: %s (parent %s), GetBagID: %s, bagID: %s, ID: %s, IconBorder: %s",
            FrameName(focus), FrameName(focus:GetParent()), tostring(focus.GetBagID ~= nil),
            tostring(focus.bagID), tostring(focus.GetID and focus:GetID()), tostring(focus.IconBorder ~= nil))
    end

    if toChat then
        for _, line in ipairs(lines) do Print(line) end
    else
        ns.ShowCopyWindow(L["Debug info"], table.concat(lines, "\n"))
    end
end

------------------------------------------------------------------------
-- Flagging
------------------------------------------------------------------------

-- Updates everything that shows which items will be sold.
function ns.OnRulesChanged()
    UpdateBestFood()
    RefreshOverlays()
    RefreshWindow()
    if ns.UpdateDestroyButtons then ns.UpdateDestroyButtons() end
    if Baganator and Baganator.API and Baganator.API.RequestItemButtonsRefresh then
        Baganator.API.RequestItemButtonsRefresh()
    end
end

-- value: true = auto-sell list, false = keep list, nil = neither (the junk
-- rules decide). message optionally replaces the chat message.
local function SetFlag(itemID, value, message)
    db.items[itemID] = value
    db.addedAt[itemID] = value ~= nil and time() or nil
    local label = ItemLabel(itemID)
    if message then
        Notify(message, label)
    elseif value == true then
        Notify(L["%s added to the auto-sell list."], label)
    elseif value == false then
        Notify(L["%s added to your keep list. It will never be sold."], label)
    else
        Notify(L["%s is no longer flagged."], label)
    end
    ns.OnRulesChanged()
end
ns.SetFlag = SetFlag

-- Takes an item off the auto-sell list. The junk rules decide about it again;
-- put it on the keep list to make sure it's never sold.
local function Unflag(itemID)
    SetFlag(itemID, nil, L["%s removed from the auto-sell list."])
end
ns.Unflag = Unflag

local function Unkeep(itemID)
    SetFlag(itemID, nil, L["%s removed from your keep list."])
end
ns.Unkeep = Unkeep

local function ToggleSell(itemID)
    if db.items[itemID] == true then Unflag(itemID) else SetFlag(itemID, true) end
end

local function ToggleKeep(itemID)
    if db.items[itemID] == false then Unkeep(itemID) else SetFlag(itemID, false) end
end

local function ShowFlagMenu(itemID, owner)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        ToggleSell(itemID) -- no modern menu API: just toggle auto-sell
        return
    end

    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(ItemLabel(itemID))

        local sellPrice = select(11, C_Item.GetItemInfo(itemID))
        if sellPrice == 0 then
            root:CreateTitle(L["|cffff6060Cannot be sold to vendors|r"])
            return
        end

        root:CreateCheckbox(L["Auto-sell at vendors"],
            function() return db.items[itemID] == true end,
            function() ToggleSell(itemID) end)
        root:CreateCheckbox(L["Never sell (keep)"],
            function() return db.items[itemID] == false end,
            function() ToggleKeep(itemID) end)

        local rule, word = KeepRule(itemID)
        if rule and db.items[itemID] == nil then
            root:CreateTitle(L["|cff8a8b93Kept by a rule: "] .. ns.KeepRuleText(rule, word) .. "|r")
        end
    end)
end

-- Works with the default bags, and with bag addons that use GameTooltip.
local function GetHoveredItem()
    local focus = GetMouseFrame()
    if not focus then return end

    if GameTooltip:IsShown() and GameTooltip:GetOwner() == focus then
        local _, link, itemID = GameTooltip:GetItem()
        itemID = itemID or ItemIDFromLink(link)
        if itemID then return itemID, focus end
    end

    if focus.GetBagID and focus.GetID then
        local ok, bag = pcall(focus.GetBagID, focus)
        local slot = focus:GetID()
        if ok and bag and slot and slot > 0 then
            local itemID = C_Container.GetContainerItemID(bag, slot)
            if itemID then return itemID, focus end
        end
    end
end

------------------------------------------------------------------------
-- Selling
------------------------------------------------------------------------

local function GetSellable(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not info or not info.itemID or info.isLocked or info.hasNoValue then return end

    if JunkReason(info, bag, slot) then
        local price = select(11, C_Item.GetItemInfo(info.itemID)) or 0
        if price > 0 then
            return info, price * (info.stackCount or 1)
        end
    end
end

-- Adds a sale to the earnings counters (negative for buybacks). Only
-- Pocket Goblin's own sales count as junk earnings; all sales count towards
-- the "all sales" totals.
local function AddEarnings(copper, stacks, byGoblin)
    local today = date("%Y-%m-%d")
    if charData.day ~= today then
        charData.day = today
        charData.today = 0
        charData.allToday = 0
    end
    charData.allToday = charData.allToday + copper
    charData.allEarned = charData.allEarned + copper
    session.allEarned = session.allEarned + copper
    if byGoblin then
        charData.today = charData.today + copper
        charData.earned = charData.earned + copper
        charData.sold = charData.sold + stacks
        session.earned = session.earned + copper
        session.sold = session.sold + stacks
    end
end

-- Records a sale in the history entry for this vendor visit. source is
-- "goblin" or "you".
-- The history entry for the open vendor window, created on first use.
local function CurrentVisit()
    if not currentVisit then
        currentVisit = { time = time(), vendor = vendorName, items = {} }
        table.insert(charData.history, 1, currentVisit)
        for i = #charData.history, MAX_HISTORY + 1, -1 do
            charData.history[i] = nil
        end
    end
    return currentVisit
end

local function RecordSale(entry, source)
    CurrentVisit()
    local quality = entry.link and select(3, C_Item.GetItemInfo(entry.link))
    local items = currentVisit.items
    items[#items + 1] = {
        itemID = entry.itemID, link = entry.link, quality = quality,
        count = entry.count, value = entry.price, source = source,
    }
    AddEarnings(entry.price, 1, source == "goblin")
    if source == "goblin" then
        session.lastSale = GetTime()
        ns.CheckMilestones()
    end
end

-- Marks milestones the character has reached; announces them unless quiet.
function ns.CheckMilestones(quiet)
    for _, milestone in ipairs(ns.MILESTONES) do
        local reached = (milestone.sold and charData.sold >= milestone.sold)
            or (milestone.earned and charData.earned >= milestone.earned)
        if reached and not charData.milestones[milestone.key] then
            charData.milestones[milestone.key] = true
            if not quiet and db.milestones then
                Print("|cffffd100" .. milestone.text .. "|r")
                if SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_COMPLETE then PlaySound(SOUNDKIT.IG_QUEST_LIST_COMPLETE) end
            end
        end
    end
end

-- Copper the goblin earned this session, and whether it sold something in
-- the last five minutes.
function ns.GetRecentSales()
    local recently = session.lastSale ~= nil and GetTime() - session.lastSale < 300 and session.earned > 0
    return session.earned, recently
end

-- Takes a matching sale off Pocket Goblin's not-yet-seen list. True if found.
local function ClaimOwnSale(entry)
    for i, own in ipairs(pendingOwnSales) do
        if own.itemID == entry.itemID and own.count == entry.count then
            table.remove(pendingOwnSales, i)
            return true
        end
    end
    return false
end

local function StopSelling()
    if sellTicker then
        sellTicker:Cancel()
        sellTicker = nil
        if ns.UpdateMerchantPanel then ns.UpdateMerchantPanel() end
    end
    if sellSummary and sellSummary.count > 0 then
        Print(ns.Say("sold", L["Sold %d item(s) for %s."], sellSummary.count, GetMoneyString(sellSummary.money, true)))
        if sellSummary.leftOver > 0 then
            Print(L["%d more junk items left. Press Sell junk to sell the next %d."], sellSummary.leftOver,
                math.min(sellSummary.leftOver, BUYBACK_SIZE))
        end
    end
    sellSummary = nil
end

local function SellJunk(manual)
    if not merchantOpen then
        Print(L["Open a vendor window first."])
        return
    end
    StopSelling()

    local queue = {}
    for bag = 0, LAST_BAG do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = GetSellable(bag, slot)
            if info then
                queue[#queue + 1] = { bag = bag, slot = slot, itemID = info.itemID }
            end
        end
    end

    if #queue == 0 then
        if manual then Print(ns.Say("nothingToSell", L["Nothing to sell."])) end
        return
    end

    -- Sell one buyback list's worth at a time, so every sale can be bought back.
    local leftOver = 0
    if db.sellBatchLimit and #queue > BUYBACK_SIZE then
        leftOver = #queue - BUYBACK_SIZE
        for i = #queue, BUYBACK_SIZE + 1, -1 do queue[i] = nil end
    end

    sellSummary = { count = 0, money = 0, leftOver = leftOver }
    local index = 0
    sellTicker = C_Timer.NewTicker(SELL_INTERVAL, function()
        index = index + 1
        local entry = queue[index]
        -- "Using" an item only sells it while a vendor is open; otherwise it
        -- would equip or use it. So stop the moment the vendor window closes.
        if not entry or not merchantOpen or (MerchantFrame and not MerchantFrame:IsShown()) then
            StopSelling()
            return
        end
        local info, value = GetSellable(entry.bag, entry.slot)
        if info and info.itemID == entry.itemID then
            C_Container.UseContainerItem(entry.bag, entry.slot)
            sellSummary.count = sellSummary.count + 1
            sellSummary.money = sellSummary.money + value
            -- Recorded once it shows up in the vendor's buyback list.
            pendingOwnSales[#pendingOwnSales + 1] = { itemID = info.itemID, count = info.stackCount or 1 }
        end
    end, #queue + 1)
    ns.UpdateMerchantPanel() -- show "Selling..." on the panel
end
ns.SellJunk = SellJunk

function ns.GetHistory()
    return charData.history
end

-- Copper earned: this session, today, by this character, and by all
-- characters; plus copper this character spent on repairs.
-- Earnings as { session, today, character, account } tables of
-- { junk = Pocket Goblin's sales, all = every vendor sale }, plus copper this
-- character spent on repairs.
function ns.GetEarnings()
    local isToday = charData.day == date("%Y-%m-%d")
    local account = { junk = 0, all = 0 }
    for _, character in pairs(PocketGoblinDB.characters) do
        account.junk = account.junk + (character.earned or 0)
        account.all = account.all + (character.allEarned or 0)
    end
    return {
        session = { junk = session.earned, all = session.allEarned },
        today = { junk = isToday and charData.today or 0, all = isToday and charData.allToday or 0 },
        character = { junk = charData.earned, all = charData.allEarned },
        account = account,
    }, charData.repairs, charData.repairsGuild
end

function ns.GetCurrentVisit()
    return currentVisit
end

-- The vendor's buyback list, oldest first: { { itemID, count, price, link } }.
-- itemID is 0 if the game hasn't sent the item yet.
local function ReadBuybackList()
    local list = {}
    for index = 1, GetNumBuybackItems() do
        local link = GetBuybackItemLink(index)
        local _, _, price, quantity = GetBuybackItemInfo(index)
        list[index] = {
            itemID = link and ItemIDFromLink(link) or 0, link = link,
            count = quantity or 1, price = price or 0,
        }
    end
    return list
end

local function SameEntry(a, b)
    return a.itemID == b.itemID and a.count == b.count
end

-- New sales are added to the end of the buyback list, and when it's full
-- the oldest entries drop off the front. Finds how far the old list shifted
-- and returns the indices in the new list that weren't there before, plus
-- whether the lists still overlapped (if not, we can't be sure what's new).
local function FindNewEntries(old, new)
    for shift = 0, #old do
        local overlaps = true
        for i = shift + 1, #old do
            local entry = new[i - shift]
            if not entry or not SameEntry(old[i], entry) then
                overlaps = false
                break
            end
        end
        if overlaps then
            local added = {}
            for i = #old - shift + 1, #new do added[#added + 1] = i end
            return added, shift < #old or #old == 0
        end
    end
    return {}, false
end

-- The buyback list as of the last vendor update. A buyback removes its
-- entry right away, so this is what tells us which item was bought back.
local buybackSnapshot = {}

-- Matches sold history items to a buyback list, newest sales first. Each
-- buyback entry matches at most one sale, so two identical stacks get one
-- each. Returns { [sold] = index } and { [sold] = its vendor visit }.
local function MatchSales(buybackList)
    local available = {} -- "itemID:count" -> buyback indices
    for index, entry in ipairs(buybackList) do
        if entry.itemID ~= 0 then
            local key = entry.itemID .. ":" .. entry.count
            available[key] = available[key] or {}
            table.insert(available[key], index)
        end
    end
    local matches, visits = {}, {}
    for _, visit in ipairs(charData.history) do
        for _, sold in ipairs(visit.items) do
            local indices = not sold.boughtBack and available[sold.itemID .. ":" .. sold.count]
            if indices and #indices > 0 then
                matches[sold] = table.remove(indices)
                visits[sold] = visit
            end
        end
    end
    return matches, visits
end

function ns.MatchBuybacks()
    if not merchantOpen then return {} end
    return (MatchSales(ReadBuybackList()))
end

-- Runs after every buyback, whether from Pocket Goblin or the vendor's own
-- Buyback tab: marks the sale as bought back and takes it off the earnings.
local function OnBuyback(index)
    local matches = MatchSales(buybackSnapshot)
    for sold, matchedIndex in pairs(matches) do
        if matchedIndex == index then
            sold.boughtBack = true
            AddEarnings(-sold.value, -1, sold.source ~= "you")
            Print(ns.Say("boughtBack", L["Bought back %s."], sold.link .. (sold.count > 1 and (" x" .. sold.count) or "")))
            break
        end
    end
    -- Keep the snapshot in step, so the next update isn't mistaken for sales.
    table.remove(buybackSnapshot, index)
    RefreshWindow()
    ns.UpdateMerchantPanel()
end

-- Records sales that appeared in the buyback list since the last update.
local function OnBuybackListChanged()
    local list = ReadBuybackList()
    local added, certain = FindNewEntries(buybackSnapshot, list)
    for _, index in ipairs(added) do
        local entry = list[index]
        if entry.itemID ~= 0 then
            local own = ClaimOwnSale(entry)
            -- If the lists didn't overlap, only trust sales we know we made.
            if own or certain then
                RecordSale(entry, own and "goblin" or "you")
            end
        end
    end
    buybackSnapshot = list
end

-- Buys back a sold history item (from a click); OnBuyback does the rest.
function ns.BuyBack(sold)
    OnBuybackListChanged() -- record any sales the game hasn't reported yet
    local index = MatchSales(buybackSnapshot)[sold]
    if index then BuybackItem(index) end
end

------------------------------------------------------------------------
-- Repairs
------------------------------------------------------------------------

local function AutoRepair()
    if not db.autoRepair or not CanMerchantRepair or not CanMerchantRepair() then return end
    local cost, canRepair = GetRepairAllCost()
    if not canRepair or not cost or cost <= 0 then return end

    if db.repairGuild and IsInGuild() and CanGuildBankRepair and CanGuildBankRepair() then
        local withdraw = GetGuildBankWithdrawMoney and GetGuildBankWithdrawMoney() or 0
        local bank = GetGuildBankMoney and GetGuildBankMoney() or 0
        if (withdraw == -1 or withdraw >= cost) and bank >= cost then
            RepairAllItems(true)
            Print(ns.Say("repairedGuild", L["Repaired for %s from guild funds."], GetMoneyString(cost, true)))
            return
        end
    end
    if GetMoney() >= cost then
        RepairAllItems()
        Print(ns.Say("repaired", L["Repaired for %s."], GetMoneyString(cost, true)))
    else
        Print(ns.Say("cantRepair", L["Not enough money to repair (%s needed)."], GetMoneyString(cost, true)))
    end
end

-- Repairs are noticed by watching what it costs to repair everything while
-- a vendor is open: when that drops, the difference was just spent, however
-- the repair was made (Pocket Goblin, the vendor's Repair All button, or
-- the repair hammer on a single item).
local repairCost = 0               -- repair-all cost as of the last check
local guildRepairPending = false   -- the last Repair All was paid by the guild

local function ReadRepairCost()
    if not (CanMerchantRepair and CanMerchantRepair()) then return 0 end
    return GetRepairAllCost() or 0
end

local function OnDurabilityChanged()
    if not merchantOpen then return end
    local cost = ReadRepairCost()
    if cost < repairCost then
        local spent = repairCost - cost
        local visit = CurrentVisit()
        visit.repairs = visit.repairs or {}
        table.insert(visit.repairs, { cost = spent, guild = guildRepairPending })
        if guildRepairPending then
            charData.repairsGuild = charData.repairsGuild + spent
        else
            charData.repairs = charData.repairs + spent
        end
        RefreshWindow()
    end
    guildRepairPending = false
    repairCost = cost
end

------------------------------------------------------------------------
-- Bag space
------------------------------------------------------------------------

-- Free slots in bags that hold any item (not profession bags).
function ns.GetFreeBagSlots()
    local free = 0
    for bag = 0, LAST_BAG do
        local slots, family = C_Container.GetContainerNumFreeSlots(bag)
        if family == 0 then free = free + slots end
    end
    return free
end

function ns.IsBagSpaceLow()
    return db.bagWarning and ns.GetFreeBagSlots() <= db.bagWarningSlots
end

local lastFreeSlots
-- Says so in chat when the bags drop to the warning threshold.
local function CheckBagSpace()
    local free = ns.GetFreeBagSlots()
    if db.bagWarning and lastFreeSlots and lastFreeSlots > db.bagWarningSlots and free <= db.bagWarningSlots then
        Notify(ns.Say("bagsLow", L["Only %d free bag slot(s) left."], free))
    end
    lastFreeSlots = free
end

-- Junk in the bags whose reason is in the reasons set (all junk if nil):
-- { { info, reason, value }, ... }.
function ns.ScanJunk(reasons)
    local found = {}
    for bag = 0, LAST_BAG do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local reason = info and info.itemID and JunkReason(info, bag, slot)
            if reason and (not reasons or reasons[reason]) then
                local price = select(11, C_Item.GetItemInfo(info.itemID)) or 0
                found[#found + 1] = { info = info, reason = reason, value = price * (info.stackCount or 1) }
            end
        end
    end
    return found
end

-- Set of item IDs currently in the bags.
function ns.GetBagItemIDs()
    local ids = {}
    for bag = 0, LAST_BAG do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local itemID = C_Container.GetContainerItemID(bag, slot)
            if itemID then ids[itemID] = true end
        end
    end
    return ids
end

-- Number of items and total value that would be sold right now.
function ns.GetJunkSummary()
    local count, money = 0, 0
    for bag = 0, LAST_BAG do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info, value = GetSellable(bag, slot)
            if info then
                count = count + (info.stackCount or 1)
                money = money + value
            end
        end
    end
    return count, money
end

------------------------------------------------------------------------
-- Destroying junk
------------------------------------------------------------------------

-- The junk slot with the lowest total value (vendor price x stack size).
-- Also returns how many junk slots were skipped by the value limit, and how
-- many can be destroyed (including the cheapest).
function ns.FindCheapestJunk()
    local best, protected, destroyable = nil, 0, 0
    for bag = 0, LAST_BAG do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and not info.isLocked and JunkReason(info, bag, slot) then
                local price = (not info.hasNoValue and select(11, C_Item.GetItemInfo(info.itemID))) or 0
                local count = info.stackCount or 1
                local value = price * count
                if db.destroyProtect and value > db.destroyLimit then
                    protected = protected + 1
                else
                    destroyable = destroyable + 1
                    if not best or value < best.value or (value == best.value and price < best.price) then
                        best = {
                            bag = bag, slot = slot, itemID = info.itemID, link = info.hyperlink,
                            icon = info.iconFileID, count = count, price = price, value = value,
                        }
                    end
                end
            end
        end
    end
    return best, protected, destroyable
end

-- Destroys target (from FindCheapestJunk) if it's still in the same slot
-- with the same stack size. Must run from a click: deleting items needs a
-- hardware event.
function ns.DestroyItem(target)
    if CursorHasItem() then
        Print(L["Put down the item on your cursor first."])
        return
    end
    local info = C_Container.GetContainerItemInfo(target.bag, target.slot)
    if not info or info.itemID ~= target.itemID or (info.stackCount or 1) ~= target.count or info.isLocked then
        Print(L["That item has moved or changed. Nothing was destroyed."])
        return
    end

    C_Container.PickupContainerItem(target.bag, target.slot)
    local kind, itemID = GetCursorInfo()
    if kind ~= "item" or itemID ~= target.itemID then
        ClearCursor()
        return
    end
    DeleteCursorItem()
    Print(ns.Say("destroyed", L["Destroyed %s (worth %s)."],
        target.link .. (target.count > 1 and (" x" .. target.count) or ""),
        target.value > 0 and GetMoneyString(target.value, true) or "nothing"))
end

-- The destroy button's click: asks first unless that's turned off.
function ns.DestroyCheapestJunk()
    if CursorHasItem() then
        Print(L["Put down the item on your cursor first."])
        return
    end
    local target = ns.FindCheapestJunk()
    if not target then return end
    if db.destroyConfirm then
        ns.ShowDestroyConfirm(target)
    else
        ns.DestroyItem(target)
    end
end

function ns.IsSelling()
    return sellTicker ~= nil
end

function ns.IsMerchantOpen()
    return merchantOpen
end

------------------------------------------------------------------------
-- Tooltip
------------------------------------------------------------------------

-- The bag and slot of the item a tooltip shows, if it's in the bags.
local function TooltipBagSlot(tooltip)
    local info = tooltip.GetPrimaryTooltipInfo and tooltip:GetPrimaryTooltipInfo()
    if info and info.getterName == "GetBagItem" and info.getterArgs then
        local bag, slot = info.getterArgs[1], info.getterArgs[2]
        if type(bag) == "number" and bag >= 0 and bag <= LAST_BAG then return bag, slot end
    end
end

local function AddTooltipLine(tooltip, data)
    if not db or not data or not data.id then return end
    if issecretvalue and issecretvalue(data.id) then return end
    local flag = db.items[data.id]

    -- In the bags: say why it sells and what the stack is worth.
    local bag, slot = TooltipBagSlot(tooltip)
    local info = bag and C_Container.GetContainerItemInfo(bag, slot)
    local reason = info and info.itemID == data.id and JunkReason(info, bag, slot)
    if reason and db.tooltipValue then
        local price = select(11, C_Item.GetItemInfo(data.id)) or 0
        local count = info.stackCount or 1
        local value = price > 0 and GetMoneyString(price * count, true) or L["no value"]
        tooltip:AddDoubleLine(L["Pocket Goblin: sells ("] .. REASONS[reason] .. ")",
            value .. (count > 1 and ("  |cff8a8b93x" .. count .. "|r") or ""), 1, 0.82, 0, 1, 1, 1)
    elseif flag == true then
        tooltip:AddLine(L["Pocket Goblin: auto-sell"], 1, 0.82, 0)
    elseif flag == false then
        tooltip:AddLine(L["Pocket Goblin: kept"], LOCK_COLOR[1], LOCK_COLOR[2], LOCK_COLOR[3])
    elseif info and info.itemID == data.id and db.tooltipValue then
        -- Say so when a keep rule is what stops it from being sold.
        local rule, word = KeepRule(data.id)
        if rule and JunkReason(info, bag, slot, true) then
            tooltip:AddLine(L["Pocket Goblin: kept ("] .. ns.KeepRuleText(rule, word) .. ")",
                LOCK_COLOR[1], LOCK_COLOR[2], LOCK_COLOR[3], true)
        end
    end
    local questGear = ns.QUEST_GEAR[data.id]
    if questGear and db.skipQuestGear and flag == nil then
        tooltip:AddLine(L["Pocket Goblin: used in "] .. questGear[2], 0.5, 0.8, 1, true)
    end
end

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------

local function ParseItem(arg)
    return ItemIDFromLink(arg) or tonumber(arg)
end

local function OnOff(value)
    return value and "|cff00ff00on|r" or "|cffff4040off|r"
end

local function ShowHelp()
    Print(L["Alt+Right-click an item in your bags to flag it."])
    print(L["  /goblin - open the Pocket Goblin window"])
    print(L["  /goblin settings - open the settings"])
    print(L["  /goblin minimap - show or hide the minimap button"])
    print(L["  /goblin chat - mute or unmute chat messages"])
    print(L["  /goblin profile [name] - show or switch this character's profile"])
    print(L["  /goblin sell - sell now (vendor must be open)"])
    print(L["  /goblin auto - toggle selling when a vendor opens ("] .. OnOff(db.autoSell) .. ")")
    print(L["  /goblin greys - toggle selling all grey items ("] .. OnOff(db.sellGreys) .. ")")
    print(L["  /goblin add <item> - always sell an item"])
    print(L["  /goblin keep <item> - never sell an item"])
    print(L["  /goblin remove <item> - take an item off your lists"])
    print(L["  /goblin list - show your lists in chat"])
    print(L["  /goblin clear confirm - empty both lists"])
    print(L["  /goblin welcome - show the welcome window again"])
    print(L["  /goblin debug - details to copy into a bug report"])
end

local function ListFlags()
    local sell, keep = {}, {}
    for itemID, flag in pairs(db.items) do
        local list = flag and sell or keep
        list[#list + 1] = ItemLabel(itemID)
    end
    if #sell == 0 and #keep == 0 then
        Print(L["No flagged items."])
        return
    end
    if #sell > 0 then Print("Auto-sell: %s", table.concat(sell, ", ")) end
    if #keep > 0 then Print(L["Keep: %s"], table.concat(keep, ", ")) end
end

SLASH_POCKETGOBLIN1 = "/goblin"
SLASH_POCKETGOBLIN2 = "/pocketgoblin"
SlashCmdList.POCKETGOBLIN = function(msg)
    local cmd, arg = msg:match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()

    if cmd == "" then
        ns.ToggleWindow()
    elseif cmd == "sell" then
        SellJunk(true)
    elseif cmd == "auto" then
        db.autoSell = not db.autoSell
        Print(L["Auto-sell on vendor open: %s"], OnOff(db.autoSell))
        ns.OnRulesChanged()
    elseif cmd == "greys" or cmd == "grays" then
        db.sellGreys = not db.sellGreys
        Print(L["Sell grey items: %s"], OnOff(db.sellGreys))
        ns.OnRulesChanged()
    elseif cmd == "add" or cmd == "keep" or cmd == "remove" then
        local itemID = ParseItem(arg)
        if not itemID then
            Print(L["Usage: /goblin %s <item link or item ID>"], cmd)
            return
        end
        if cmd == "add" then
            SetFlag(itemID, true)
        elseif cmd == "keep" then
            SetFlag(itemID, false)
        elseif db.items[itemID] == false then
            Unkeep(itemID)
        else
            Unflag(itemID)
        end
    elseif cmd == "list" then
        ListFlags()
    elseif cmd == "clear" then
        if arg:lower() == "confirm" then
            wipe(db.items)
            wipe(db.addedAt)
            ns.OnRulesChanged()
            Print(L["All flags removed."])
        else
            Print(L["Type /goblin clear confirm to empty both lists."])
        end
    elseif cmd == "minimap" then
        db.showMinimap = not db.showMinimap
        Print(L["Minimap button: %s"], OnOff(db.showMinimap))
        ns.UpdateMinimapButton()
        RefreshWindow()
    elseif cmd == "chat" then
        db.chat = not db.chat
        Print(L["Chat messages: %s (sale summaries always show)"], OnOff(db.chat))
        RefreshWindow()
    elseif cmd == "profile" then
        if arg == "" then
            Print(L["Profile: %s. Profiles: %s"], ns.GetProfileName(), table.concat(ns.GetProfileNames(), ", "))
        elseif tContains(ns.GetProfileNames(), arg) then
            ns.SetProfile(arg)
        else
            Print(L["No profile called %s. Create one on the Profiles page (/goblin)."], arg)
        end
    elseif cmd == "settings" then
        ns.ToggleWindow(true, "settings")
    elseif cmd == "welcome" then
        ns.ShowWelcome()
    elseif cmd == "debug" then
        Debug(arg:lower() == "chat")
    else
        ShowHelp()
    end
end

------------------------------------------------------------------------
-- Profiles
------------------------------------------------------------------------

-- Fills in missing settings from defaults, recursing into tables.
local function ApplyDefaults(target, source)
    for key, value in pairs(source) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then target[key] = {} end
            ApplyDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
end

local function DeepCopy(source)
    local copy = {}
    for key, value in pairs(source) do
        copy[key] = type(value) == "table" and DeepCopy(value) or value
    end
    return copy
end

-- Moves the old single set of settings into a "Default" profile.
-- Returns true if this is the first time Pocket Goblin runs on the account.
local function MigrateSavedVariables()
    local firstRun = PocketGoblinDB == nil
    if PocketGoblinDB and not PocketGoblinDB.profiles then
        PocketGoblinDB = { profiles = { [DEFAULT_PROFILE] = PocketGoblinDB }, profileKeys = {} }
    end
    PocketGoblinDB = PocketGoblinDB or {}
    PocketGoblinDB.profiles = PocketGoblinDB.profiles or {}
    PocketGoblinDB.profileKeys = PocketGoblinDB.profileKeys or {}
    PocketGoblinDB.characters = PocketGoblinDB.characters or {}
    if not firstRun and PocketGoblinDB.welcomed == nil then
        PocketGoblinDB.welcomed = true -- installed before the welcome existed
    end
    return firstRun
end

-- Brings older saved lists up to date with the current rules (once per
-- profile). Some checks need item data, so they finish when it has loaded.
--   v1: before the keep list, "keep" also meant "removed from the auto-sell
--       list". Greys stay kept; white gear stays kept (so the white-gear rule
--       doesn't sell what you'd taken off the list); anything else becomes
--       neutral.
--   v2: white gear used to be added to the auto-sell list; now a rule sells
--       it. Auto-added entries leave the list, and white gear you'd taken off
--       the list goes on the keep list instead.
local function MigrateLists(profile)
    local version = profile.listsVersion or (profile.keepListVersion and 1) or 0
    profile.keepListVersion = nil
    if version >= 2 then return end
    profile.listsVersion = 2

    local function whenLoaded(itemID, callback)
        local item = Item:CreateFromItemID(itemID)
        item:ContinueOnItemLoad(function() callback(item:GetItemQuality()) end)
    end

    if version < 1 then
        for itemID, flag in pairs(profile.items) do
            if flag == false then
                whenLoaded(itemID, function(quality)
                    if profile.items[itemID] == false and quality ~= POOR
                        and not (quality == COMMON and IsWhiteGear(itemID)) then
                        profile.items[itemID] = nil
                    end
                end)
            end
        end
    end

    for itemID in pairs(profile.autoFlagged or {}) do
        if profile.items[itemID] == true then
            profile.items[itemID] = nil
            profile.addedAt[itemID] = nil
        end
    end
    for itemID in pairs(profile.noAutoFlag or {}) do
        whenLoaded(itemID, function(quality)
            if profile.items[itemID] == nil and quality == COMMON and IsWhiteGear(itemID) then
                profile.items[itemID] = false
            end
        end)
    end
    -- "Cheap white items: only weapons and armor" is now covered by the
    -- white-gear rule, and the cheap rule covers other white items.
    if profile.cheapWhitesGearOnly and profile.sellCheapWhites and profile.sellWhiteGear then
        profile.sellCheapWhites = false
    end
    profile.autoFlagged, profile.noAutoFlag, profile.cheapWhitesGearOnly = nil, nil, nil
    if profile.filters and profile.filters.sell then profile.filters.sell.addedBy = nil end
end

local function LoadProfile(name)
    local profile = PocketGoblinDB.profiles[name] or {}
    PocketGoblinDB.profiles[name] = profile
    -- Renamed settings (white-gear auto-flagging became the white-gear rule).
    if profile.autoFlagGear ~= nil then
        profile.sellWhiteGear, profile.autoFlagGear = profile.autoFlagGear, nil
        profile.whiteGearLevel, profile.autoFlagLevel = profile.autoFlagLevel, nil
    end
    ApplyDefaults(profile, defaults)
    if (profile.version or 0) < 2 then
        -- The coin got bigger in v2 (old 120% is the new 100%).
        if math.abs(profile.iconScale - 1.2) < 0.01 then profile.iconScale = 1 end
        profile.version = 2
    end
    MigrateLists(profile)
    if profile.filters.history.source == "junkseller" then
        profile.filters.history.source = "goblin" -- renamed with the addon
    end
    PocketGoblinDB.profileKeys[characterKey] = name
    db = profile
    ns.db = profile
end

-- Redraws everything after the active profile changed.
local function ProfileChanged()
    ns.UpdateMinimapButton()
    ns.OnRulesChanged()
end

function ns.GetProfileName()
    return PocketGoblinDB.profileKeys[characterKey]
end

function ns.GetProfileNames()
    local names = {}
    for name in pairs(PocketGoblinDB.profiles) do names[#names + 1] = name end
    table.sort(names)
    return names
end

-- Other characters that use the profile.
function ns.GetProfileUsers(name)
    local users = {}
    for key, profileName in pairs(PocketGoblinDB.profileKeys) do
        if profileName == name and key ~= characterKey then users[#users + 1] = key end
    end
    table.sort(users)
    return users
end

function ns.SetProfile(name)
    if not PocketGoblinDB.profiles[name] or name == ns.GetProfileName() then return end
    LoadProfile(name)
    Print(L["Using profile %s."], name)
    ProfileChanged()
end

-- Creates a profile as a copy of the current one and switches to it.
-- Returns false if the name is empty or already taken.
function ns.CreateProfile(name)
    name = name and strtrim(name)
    if not name or name == "" or PocketGoblinDB.profiles[name] then return false end
    PocketGoblinDB.profiles[name] = DeepCopy(db)
    ns.SetProfile(name)
    return true
end

-- Replaces the current profile's contents with a copy of another profile.
function ns.CopyProfile(source)
    local from = PocketGoblinDB.profiles[source]
    if not from or from == db then return end
    wipe(db)
    for key, value in pairs(DeepCopy(from)) do db[key] = value end
    ApplyDefaults(db, defaults)
    Print(L["Copied profile %s into %s."], source, ns.GetProfileName())
    ProfileChanged()
end

function ns.ResetProfile()
    wipe(db)
    ApplyDefaults(db, defaults)
    db.version = 2
    Print(L["Profile %s was reset."], ns.GetProfileName())
    ProfileChanged()
end

-- Deletes a profile other than the active one or Default. Characters that
-- used it go back to Default.
function ns.DeleteProfile(name)
    if name == DEFAULT_PROFILE or name == ns.GetProfileName() or not PocketGoblinDB.profiles[name] then return end
    PocketGoblinDB.profiles[name] = nil
    for key, profileName in pairs(PocketGoblinDB.profileKeys) do
        if profileName == name then PocketGoblinDB.profileKeys[key] = DEFAULT_PROFILE end
    end
    Print(L["Deleted profile %s."], name)
    if ns.RefreshWindow then ns.RefreshWindow() end
end

ns.DEFAULT_PROFILE = DEFAULT_PROFILE

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("MERCHANT_SHOW")
frame:RegisterEvent("MERCHANT_CLOSED")
frame:RegisterEvent("MERCHANT_UPDATE")
frame:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
frame:RegisterEvent("BAG_UPDATE_DELAYED")
frame:RegisterEvent("GLOBAL_MOUSE_UP")
frame:RegisterEvent("PLAYER_LEVEL_UP")

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        characterKey = UnitName("player") .. " - " .. GetRealmName()
        MigrateSavedVariables()
        local name = PocketGoblinDB.profileKeys[characterKey]
        LoadProfile(PocketGoblinDB.profiles[name] and name or DEFAULT_PROFILE)
        charData = PocketGoblinDB.characters[characterKey] or {}
        PocketGoblinDB.characters[characterKey] = charData
        if charData.earned and not charData.allEarned then
            -- Before 2.3 only Pocket Goblin's sales were tracked.
            charData.allEarned, charData.allToday = charData.earned, charData.today
        end
        local firstMilestoneCheck = charData.milestones == nil
        ApplyDefaults(charData, CHARACTER_DEFAULTS)
        if firstMilestoneCheck then ns.CheckMilestones(true) end
    elseif event == "PLAYER_LOGIN" then
        HookContainerFrames()
        RegisterBaganatorPlugin()
        ns.UpdateMinimapButton()
        UpdateBestFood()
        ns.SetupDestroyButtons()
        hooksecurefunc("BuybackItem", OnBuyback)
        hooksecurefunc("RepairAllItems", function(guildBank) guildRepairPending = guildBank and true or false end)
        if TooltipDataProcessor and Enum.TooltipDataType then
            TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, AddTooltipLine)
        end
        if not PocketGoblinDB.welcomed then
            C_Timer.After(3, ns.ShowWelcome) -- once the login screen has settled
        end
    elseif event == "MERCHANT_SHOW" then
        merchantOpen = true
        vendorName = UnitName("npc")
        buybackSnapshot = ReadBuybackList()
        repairCost = ReadRepairCost()
        AutoRepair()
        RefreshOverlays()
        RefreshWindow()
        if db.autoSell then SellJunk(false) end
        ns.UpdateMerchantPanel()
    elseif event == "MERCHANT_CLOSED" then
        merchantOpen = false
        StopSelling()
        currentVisit = nil
        wipe(pendingOwnSales)
        RefreshWindow()
        ns.UpdateMerchantPanel()
    elseif event == "MERCHANT_UPDATE" then
        -- The buyback list changed (something was sold or bought back).
        OnBuybackListChanged()
        RefreshWindow()
        ns.UpdateMerchantPanel()
    elseif event == "UPDATE_INVENTORY_DURABILITY" then
        OnDurabilityChanged()
    elseif event == "PLAYER_LEVEL_UP" then
        -- UnitLevel can lag behind the event, so check a moment later.
        -- (White gear and food rules depend on your level.)
        C_Timer.After(1, ns.OnRulesChanged)
    elseif event == "BAG_UPDATE_DELAYED" then
        -- Selling changes the bags, so this also catches sales if the vendor
        -- update is late. Unchanged lists record nothing.
        if merchantOpen then
            OnBuybackListChanged()
            ns.UpdateMerchantPanel() -- the junk to sell may have changed
        end
        UpdateBestFood()
        CheckBagSpace()
        RefreshOverlays()
        RefreshWindow()
        ns.UpdateDestroyButtons()
    elseif event == "GLOBAL_MOUSE_UP" then
        if arg1 == "RightButton" and IsAltKeyDown() and db then
            local itemID, owner = GetHoveredItem()
            if itemID then
                -- Defer a frame so the click that opened the menu doesn't close it.
                C_Timer.After(0, function() ShowFlagMenu(itemID, owner) end)
            end
        end
    end
end)
