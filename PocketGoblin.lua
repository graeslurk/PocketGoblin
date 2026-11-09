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
local UNCOMMON = Enum.ItemQuality and Enum.ItemQuality.Uncommon or 2
local EPIC = Enum.ItemQuality and Enum.ItemQuality.Epic or 4
local DISENCHANT = 13262 -- the enchanter's Disenchant spell
local MAX_HISTORY = 30 -- vendor visits kept per character
local WEAPON = Enum.ItemClass and Enum.ItemClass.Weapon or 2
local ARMOR = Enum.ItemClass and Enum.ItemClass.Armor or 4
local FISHING_POLE = Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Fishingpole or 20
local THROWN = Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Thrown or 16
local REAGENT = Enum.ItemClass and Enum.ItemClass.Reagent or 5
local RECIPE = Enum.ItemClass and Enum.ItemClass.Recipe or 9
-- Profession and class tools no rule sells. Some count as weapons in Classic
-- (Mining Pick, Blacksmith Hammer, Skinning Knife, Arclight Spanner); the rest
-- are cheap white items (Thieves' Tools, Flint and Tinder, enchanting rods,
-- Gyromatic Micro-Adjustor).
local NEVER_SELL_TOOLS = {
    [2901] = true, [5956] = true, [7005] = true, [6219] = true,
    [5060] = true, [4471] = true, [6218] = true, [6339] = true, [11130] = true, [11145] = true,
    [16207] = true, [10498] = true,
}
local COSMETIC_SLOTS = { INVTYPE_BODY = true, INVTYPE_TABARD = true }

-- Armor types by item subclass ID (MISC: rings, necks, trinkets).
local MISC, CLOTH, LEATHER, MAIL, PLATE = 0, 1, 2, 3, 4

-- Weapon and armor types each class can ever use (Classic rules), by item
-- subclass ID. Used to sell gear the character can't use. The other type
-- names are only needed here, so they live in this block (a Lua file can
-- only have 200 top-level locals).
local CLASS_GEAR
do
local AXE1H, AXE2H, BOW, GUN, MACE1H, MACE2H, POLEARM, SWORD1H, SWORD2H = 0, 1, 2, 3, 4, 5, 6, 7, 8
local STAFF, FIST, DAGGER, CROSSBOW, WAND = 10, 13, 15, 18, 19
local SHIELD, LIBRAM, IDOL, TOTEM = 6, 7, 8, 9
CLASS_GEAR = {
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
end
local FALLBACK_ICON = "Interface\\Buttons\\UI-GroupLoot-Coin-Up"
local LOCK_ICON = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\icon-lock"
local LOCK_COLOR = { 0.55, 0.8, 1 }
local ASK_ICON = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\icon-ask"
local UPGRADE_ICON = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\icon-upgrade"
-- The bag icons, for other bag addons' item buttons (Ellesmere.lua).
ns.ICONS = { coinAtlas = JUNK_ATLAS, coin = FALLBACK_ICON, ask = ASK_ICON, upgrade = UPGRADE_ICON,
    lock = LOCK_ICON, lockColor = LOCK_COLOR, size = COIN_SIZE }
ns.LAST_BAG = LAST_BAG
local ASK_COLOR = { 1, 0.82, 0.25 }
local SET_FALLBACK_ICON = 134400 -- the question mark the Equipment Manager gives sets without an icon
local WORN_DAYS = 30 -- gear swapped to this recently is kept (the keepWorn rule)
local BAG_ADDONS = { "Baganator", "Bagnon", "AdiBags", "ArkInventory", "BetterBags", "Combuctor", "OneBag3" }

local defaults = {
    autoSell = true,  -- sell automatically when a vendor window opens
    warnOtherSellers = true, -- say so when another addon also sells junk at vendors
    sellBatchLimit = true, -- sell at most BUYBACK_SIZE items per go, so all of them can be bought back
    sellGreys = true, -- include all grey (poor) items
    sellWhiteGear = true, -- sell white weapons and armor...
    whiteGearLevel = 10,  -- ...from this character level (before it, you still use them)
    skipQuestGear = true, -- never sell gear that quests ask for (QuestGear.lua), unless flagged
    -- Chat messages: "goblin" (the goblin's voice, moods and milestones),
    -- "plain", "summaries" (only what was sold, repaired or bought back) or
    -- "none" (nothing on its own; replies to commands and clicks still print).
    messages = "goblin",
    tooltipValue = true, -- show why and for how much an item sells, in its tooltip
    sellCheapWhites = false,    -- sell white items cheaper than cheapWhiteLimit...
    cheapWhiteLimit = 1000,     -- ...copper per item (10 silver); not gear, food, drink, ammo or reagents
    sellOldFood = true,    -- sell food/drink when carrying a better kind you can use...
    oldFoodMinBetter = 5,  -- ...and at least this many of it
    sellSoulbound = false, -- sell soulbound gear this class can never use, or far below its level...
    outgrownLevels = 15,   -- ...by at least this many levels
    sellLighterArmor = false, -- sell soulbound cloth, leather or mail lighter than the heaviest armor you wear
    sellKnownRecipes = false, -- sell recipes this character already knows
    merchantPanel = true,  -- sell and buyback panel next to the vendor window
    autoRepair = true,     -- repair at vendors that can
    repairGuild = false,   -- use guild bank funds first
    bagWarning = true,     -- warn on the destroy button when bags are nearly full...
    bagWarningSlots = 3,   -- ...at this many free slots or fewer
    destroyButton = true,  -- show the "destroy cheapest junk" button on the bags
    sortButton = true,     -- show the "sort bags" button on the default bags
    destroyConfirm = true, -- ask before destroying
    lootMakeRoom = true,   -- with full bags, a button on the loot window destroys junk and loots
    openButton = true,     -- a button on the bags that opens clams, sacks and other containers
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
    protectUpgrades = true, -- never sell gear better than what you wear in its slot
    keepDisenchant = true,  -- on enchanters, never sell gear that can be disenchanted
    keepWorn = true,        -- never sell green or better gear you've put on more than once in WORN_DAYS days
    askQuality = 3,  -- a rule's sales of this quality (2 green, 3 blue, 4 epic) or better wait for your OK
    keepAuction = true,  -- with an auction addon, never sell items that earn at least...
    auctionProfit = 1000, -- ...this much copper more there than at a vendor (10 silver), after the house's cut
    keepIcon = true,  -- lock icon on items on the keep list
    setIcon = true,   -- the set's icon on items in an equipment set
    upgradeIcon = true, -- green arrow on gear Pawn calls an upgrade (needs Pawn)
    addedAt = {},     -- [itemID] = time() it was added to the auto-sell list
    manualSales = {},  -- [itemID] = times you sold it yourself (for auto-sell suggestions)
    noSuggest = {},    -- [itemID] = true: never suggest auto-selling it again
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
    repairsToday = 0, repairsGuildToday = 0, -- the same, since the day change
    ledgerDay = "",   -- the day the goblin last grumbled about repairs costing more than sales
    -- biggestRepair = { cost, time, vendor }: the most expensive vendor visit's repairs
    worn = {},        -- [itemID] = { seen = time() last seen equipped, equips = times put on }
    milestones = {}, -- [milestone key] = true once reached
}

local DEFAULT_PROFILE = "Default"

local db -- the active profile (PocketGoblinDB.profiles[name])
local characterKey
local charData -- PocketGoblinDB.characters[characterKey]
local session = { earned = 0, sold = 0, allEarned = 0, repairs = 0, repairsGuild = 0 }
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

-- Messages the user can mute with the messages setting.
local function Notify(msg, ...)
    if db and db.messages ~= "summaries" and db.messages ~= "none" then Print(msg, ...) end
end

-- Summaries of what the goblin did on its own (sold, repaired, bought back),
-- muted only by "none".
local function Summary(msg, ...)
    if db and db.messages ~= "none" then Print(msg, ...) end
end

-- True when the goblin speaks in its own voice (and shows moods and milestones).
function ns.GoblinVoice()
    return ns.db ~= nil and ns.db.messages == "goblin"
end

local MESSAGE_STYLES = { goblin = L["Goblin"], plain = L["Plain"], summaries = L["Summaries only"], none = L["None"] }
function ns.MessageStyleName(style)
    return MESSAGE_STYLES[style] or style
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

local IsUpgrade, AuctionPrice -- further down, with the class gear and the auction addons
local AUCTION_CUT = 0.05 -- the auction house keeps 5% of the sale

-- True if an item earns enough more at the auction house to keep it (with
-- Auctionator or TradeSkillMaster): its auction price, after the house's
-- cut, beats the vendor price by at least auctionProfit. So an empty vial,
-- 1c at a vendor and 17c at auction, still sells. Never grey items, which
-- always sell, nor soulbound or bind-on-pickup ones, which can't be
-- auctioned. Also checked for items on the auto-sell list: prices change.
local function WorthAuctioning(itemID, bound)
    if not db.keepAuction or bound then return false end
    local _, _, quality, _, _, _, _, _, _, _, price, _, _, bindType = C_Item.GetItemInfo(itemID)
    if not quality or quality == POOR or bindType == 1 then return false end
    local auction = AuctionPrice(itemID)
    return auction ~= nil and price ~= nil and auction * (1 - AUCTION_CUT) - price >= db.auctionProfit
end
ns.WorthAuctioning = WorthAuctioning

-- For Make room, which loots the most valuable item first.
function ns.AuctionPrice(itemID)
    return AuctionPrice(itemID)
end

-- True if this character knows Disenchant.
local function KnowsDisenchant()
    return IsPlayerSpell ~= nil and IsPlayerSpell(DISENCHANT)
end

-- True if this character could disenchant the item: green, blue or purple
-- weapons and armor (not shirts, tabards or fishing poles). Doesn't check
-- whether your Enchanting skill is high enough for it yet.
local function CanDisenchant(itemID)
    if not KnowsDisenchant() then return false end
    local _, _, _, equipLoc, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
    if classID ~= WEAPON and classID ~= ARMOR then return false end
    if not equipLoc or equipLoc == "" or COSMETIC_SLOTS[equipLoc] then return false end
    if classID == WEAPON and subClassID == FISHING_POLE then return false end
    local quality = C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(itemID)
        or select(3, C_Item.GetItemInfo(itemID))
    return quality ~= nil and quality >= UNCOMMON and quality <= EPIC
end

-- True if the item is green or better gear you've put on more than once in
-- the last WORN_DAYS days, like a resistance set or a swap weapon. Gear you
-- wore once and replaced (levelling gear) doesn't count.
local function SwappedTo(itemID)
    local worn = charData and charData.worn[itemID]
    if type(worn) ~= "table" or worn.equips < 2 or time() - worn.seen > WORN_DAYS * 86400 then return false end
    local quality = C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(itemID)
        or select(3, C_Item.GetItemInfo(itemID))
    return quality ~= nil and quality >= UNCOMMON
end

-- Notes what you have on: when each item was last seen on you, and how often
-- you've put it on (counted when it appears since the last check). Forgets
-- gear not worn in WORN_DAYS days.
local equippedBefore -- item IDs on you at the last check; nil until the first
local function RecordWorn()
    if not charData then return end
    local now, equipped = time(), {}
    for slot = 1, 19 do
        local itemID = GetInventoryItemID("player", slot)
        if itemID then equipped[itemID] = true end
    end
    for itemID in pairs(equipped) do
        local worn = charData.worn[itemID]
        if type(worn) ~= "table" then
            worn = { equips = 0 }
            charData.worn[itemID] = worn
        end
        -- Gear you already had on at login counts once, not again each login.
        if worn.equips == 0 or (equippedBefore and not equippedBefore[itemID]) then
            worn.equips = worn.equips + 1
        end
        worn.seen = now
    end
    equippedBefore = equipped
    for itemID, worn in pairs(charData.worn) do
        if type(worn) ~= "table" or now - worn.seen > WORN_DAYS * 86400 then charData.worn[itemID] = nil end
    end
end

-- Which keep rule protects an item (link: the exact item, for random stats
-- like "of the Bear"): "name" (plus the matching word),
-- "type", "valuable", "upgrade", "swapped", "disenchant" or "auction"; nil if
-- none does. bound: the
-- item in your bags is soulbound (so it can't be auctioned). Items you flag
-- yourself ignore these rules.
local function KeepRule(itemID, bound, link)
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
    if db.protectUpgrades and IsUpgrade(itemID, link) then return "upgrade" end
    if db.keepWorn and SwappedTo(itemID) then return "swapped" end
    if db.keepDisenchant and CanDisenchant(itemID) then return "disenchant" end
    if WorthAuctioning(itemID, bound) then return "auction" end
end
ns.KeepRule = KeepRule

-- A short description of a keep rule, e.g. 'name contains "potion"'.
function ns.KeepRuleText(rule, word)
    if rule == "name" then return (L['name contains "%s"']):format(word) end
    if rule == "type" then return L["its item type"] end
    if rule == "upgrade" then return L["an upgrade for you"] end
    if rule == "disenchant" then return L["for disenchanting"] end
    if rule == "swapped" then return L["gear you swap to"] end
    if rule == "auction" then return L["worth more at the auction house"] end
    return L["worth more than "] .. GetMoneyString(db.keepValueLimit, true)
end

-- True if the item should be sold, judged only by flags, keep rules and
-- quality (for items that aren't in the bags).
local function IsJunk(itemID, quality)
    local flag = db.items[itemID]
    if flag == true and WorthAuctioning(itemID) then return false end
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
    if NEVER_SELL_TOOLS[itemID] then return false end
    local _, _, _, equipLoc, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
    if not equipLoc or equipLoc == "" or COSMETIC_SLOTS[equipLoc] then return false end
    if classID == WEAPON then
        return subClassID ~= FISHING_POLE and subClassID ~= THROWN
    end
    return classID == ARMOR
end

-- The heaviest armor type you can wear now: PLATE, MAIL, LEATHER or CLOTH.
-- Warriors and paladins wear mail until they learn plate at 40, hunters
-- and shamans leather until they learn mail; the armor skills say which.
local ARMOR_SKILLS = { { PLATE, 750 }, { MAIL, 8737 }, { LEATHER, 9077 }, { CLOTH, 9078 } }

local function HeaviestArmor()
    CanClassUse(ARMOR, CLOTH) -- fills classUsable
    if not classUsable then return nil end -- unknown class
    for _, skill in ipairs(ARMOR_SKILLS) do
        local armor, spellID = skill[1], skill[2]
        if classUsable.armor[armor] and IsPlayerSpell and IsPlayerSpell(spellID) then return armor end
    end
    -- No skill found (it should be): go by level instead.
    local class, level = select(2, UnitClass("player")), UnitLevel("player")
    for _, skill in ipairs(ARMOR_SKILLS) do
        local armor = skill[1]
        if classUsable.armor[armor] then
            if armor == PLATE and level < 40 then armor = MAIL end
            if armor == MAIL and level < 40 and (class == "HUNTER" or class == "SHAMAN") then armor = LEATHER end
            return armor
        end
    end
end

-- Which equipment slots an item goes in; two for rings, trinkets and
-- one-handed weapons.
local SLOTS_FOR = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 },
    INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 },
    INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
    INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 },
    INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 },
    INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 },
    INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}

local function ItemLevel(item)
    local level = C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(item)
    return level or select(4, C_Item.GetItemInfo(item))
end

-- The item level in an equipment slot; 0 when it's empty. A two-handed
-- weapon fills the off-hand too.
local function EquippedLevel(slot)
    local link = GetInventoryItemLink("player", slot)
    if not link and slot == 17 then
        local mainHand = GetInventoryItemLink("player", 16)
        if mainHand and select(9, C_Item.GetItemInfo(mainHand)) == "INVTYPE_2HWEAPON" then link = mainHand end
    end
    return link and ItemLevel(link) or 0
end

-- Pawn can only answer once it has set itself up at login (asking earlier
-- makes it complain), and it keeps that to itself, so watch its setup
-- function. Pawn loads first (OptionalDeps in the TOC), so the hook is in
-- place before login.
local pawnReady = false
if type(PawnInitialize) == "function" then
    hooksecurefunc("PawnInitialize", function()
        pawnReady = true
        if ns.ForgetUpgradeArrows then ns.ForgetUpgradeArrows() end
        if db then ns.OnRulesChanged() end -- upgrades may keep different items now
    end)
end

local function PawnReady()
    return pawnReady and PawnShouldItemLinkHaveUpgradeArrowUnbudgeted ~= nil
end

-- Pawn's answer to "is this an upgrade?", by the scales you use in Pawn; nil
-- when Pawn isn't ready or can't tell yet. Pawn rations its answers to keep
-- the frame rate up and says "not sure yet" past the ration; budgeted takes
-- that (fine for the arrows, which ask again), the keep rule asks for a
-- definite answer, since it decides what's sold.
local function PawnUpgrade(link, checkLevel, budgeted)
    if not PawnReady() then return nil end
    local ask = budgeted and PawnShouldItemLinkHaveUpgradeArrow or PawnShouldItemLinkHaveUpgradeArrowUnbudgeted
    local ok, upgrade = pcall(ask, link, checkLevel)
    if not ok or upgrade == nil then return nil end
    return upgrade and true or false
end

-- Where upgrade answers come from, for the settings and debug info.
function ns.UpgradeSource()
    return PawnReady() and "Pawn" or "item level"
end

-- True if Pawn's own upgrade arrows are on in the default bags.
local function PawnShowsBagArrows()
    return PawnCommon ~= nil and PawnCommon.ShowBagUpgradeAdvisor == true
end

-- Pawn's answers for the arrows, by item link: Pawn rations its answers,
-- so asking again on every bag update made arrows blink. When Pawn says its
-- answers changed (new scales, new gear) or your gear or level changes, they
-- go out of date: each is asked again, and shown as it was until the new
-- answer comes, so arrows don't flash off in between.
local arrowAnswers = {} -- [link] = { upgrade = Pawn's answer, round = arrowRound when asked }
local arrowRound = 1
function ns.ForgetUpgradeArrows()
    arrowRound = arrowRound + 1
end
if type(PawnResetBags) == "function" then
    hooksecurefunc("PawnResetBags", function()
        ns.ForgetUpgradeArrows()
        if db then
            ns.RefreshOverlays()
            if ns.RefreshEllesmere then ns.RefreshEllesmere() end
        end
    end)
end

-- True if the item gets the upgrade arrow: only when Pawn says it's an
-- upgrade you can wear now. Item level alone would put arrows on gear with
-- the wrong stats (an intellect item on a rogue), so without Pawn there are
-- none. When Pawn can't tell yet, the bags are checked again a moment later.
local arrowRetry = false
local function ShowsUpgradeArrow(link)
    if not (link and db.upgradeIcon) then return false end
    local known = arrowAnswers[link]
    if known and known.round == arrowRound then return known.upgrade end
    local upgrade = PawnUpgrade(link, true, true)
    if upgrade ~= nil then
        arrowAnswers[link] = { upgrade = upgrade, round = arrowRound }
        return upgrade
    end
    if PawnReady() and not arrowRetry then
        arrowRetry = true
        C_Timer.After(0.25, function()
            arrowRetry = false
            ns.RefreshOverlays()
            if ns.RefreshEllesmere then ns.RefreshEllesmere() end
        end)
    end
    return known ~= nil and known.upgrade -- the old answer until the new one comes
end

-- True for gear that's better than what you wear, also gear you'll grow
-- into. With Pawn installed, Pawn decides, for grey gear too (so a grey item
-- Pawn shows as an upgrade isn't sold). Otherwise a higher item level than
-- the weaker of its slots, or filling an empty one; never grey items, gear
-- your class can't use, or armor lighter than yours. link is the exact item
-- when known (random stats like "of the Bear" differ per copy).
function IsUpgrade(itemID, link)
    local _, _, quality, _, _, _, _, _, equipLoc = C_Item.GetItemInfo(link or itemID)
    local slots = SLOTS_FOR[equipLoc or ""]
    if not slots or not quality then return false end
    local pawn = PawnUpgrade(link or ("item:" .. itemID), false)
    if pawn ~= nil then return pawn end
    if quality == POOR then return false end
    local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
    if not CanClassUse(classID, subClassID) then return false end
    if classID == ARMOR and subClassID >= CLOTH and subClassID <= PLATE and equipLoc ~= "INVTYPE_CLOAK" then
        local heaviest = HeaviestArmor()
        if heaviest and subClassID < heaviest then return false end
    end
    local level = ItemLevel(link or itemID)
    if not level then return false end
    local weakest
    for _, slot in ipairs(slots) do
        local equipped = EquippedLevel(slot)
        if not weakest or equipped < weakest then weakest = equipped end
    end
    return level > weakest
end

-- The auction house price of an item from Auctionator or TradeSkillMaster,
-- in copper; nil when neither is installed or knows a price.
function AuctionPrice(itemID)
    local auctionator = Auctionator and Auctionator.API and Auctionator.API.v1
    if auctionator and auctionator.GetAuctionPriceByItemID then
        local ok, price = pcall(auctionator.GetAuctionPriceByItemID, "Pocket Goblin", itemID)
        if ok and type(price) == "number" then return price end
    end
    if TSM_API and TSM_API.GetCustomPriceValue then
        local ok, price = pcall(TSM_API.GetCustomPriceValue, "dbmarket", "i:" .. itemID)
        if ok and type(price) == "number" then return price end
    end
end

-- Which auction addon prices come from, for the settings; nil if none.
function ns.AuctionAddon()
    if Auctionator and Auctionator.API and Auctionator.API.v1 then return "Auctionator" end
    if TSM_API then return "TradeSkillMaster" end
end

-- True if the tooltip of the recipe in a bag slot says you already know it.
local function IsKnownRecipe(bag, slot)
    local known = ITEM_SPELL_KNOWN
    if not known or not (C_TooltipInfo and C_TooltipInfo.GetBagItem) then return false end
    local data = C_TooltipInfo.GetBagItem(bag, slot)
    for _, line in ipairs(data and data.lines or {}) do
        if line.leftText == known then return true end
    end
    return false
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
    outgrown = L["you've outgrown it"],
    lighterArmor = L["lighter armor than you wear"],
    knownRecipe = L["recipe you already know"],
}
ns.REASONS = REASONS

-- Which junk rule would sell the item in a bag slot ("grey", "whiteGear",
-- "oldFood", "cheap", "unusable", "outgrown", "lighterArmor" or
-- "knownRecipe"), before your lists and keep rules have their say (see
-- JunkReason). info is the slot's C_Container.GetContainerItemInfo.
local function RuleReason(info, bag, slot)
    local itemID, quality = info.itemID, info.quality
    if quality == POOR then return db.sellGreys and "grey" or nil end
    if info.hasNoValue or NEVER_SELL_TOOLS[itemID] then return nil end
    if db.skipQuestGear and ns.QUEST_GEAR[itemID] then return nil end

    local _, _, _, equipLoc, _, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
    local isGear = (classID == WEAPON or classID == ARMOR) and equipLoc ~= nil and equipLoc ~= ""
        and not COSMETIC_SLOTS[equipLoc]

    -- White gear from the level you choose; below it, only what your class
    -- can never use (plate on a mage), since you might still wear the rest.
    if quality == COMMON and db.sellWhiteGear and IsWhiteGear(itemID) then
        if UnitLevel("player") >= db.whiteGearLevel then return "whiteGear" end
        if not CanClassUse(classID, subClassID) then return "unusable" end
    end

    local foodKind = FoodKind(itemID)
    if foodKind and db.sellOldFood and bestFood[foodKind] then
        local level = select(5, C_Item.GetItemInfo(itemID)) or 0
        if level < bestFood[foodKind] then return "oldFood" end
    end

    -- Cheap white items, apart from weapons and armor (the white-gear rule's
    -- job, which also spares fishing poles, shirts and tabards), food and
    -- drink (their own rule), ammo and class reagents (Ankh, Flash Powder...).
    if quality == COMMON and db.sellCheapWhites and not foodKind and classID ~= WEAPON and classID ~= ARMOR
        and classID ~= PROJECTILE and classID ~= REAGENT then
        local price = select(11, C_Item.GetItemInfo(itemID)) or 0
        if price > 0 and price < db.cheapWhiteLimit then return "cheap" end
    end

    if isGear and info.isBound and quality and quality <= EPIC and db.sellSoulbound then
        if not CanClassUse(classID, subClassID) then return "unusable" end
        local requiredLevel = select(5, C_Item.GetItemInfo(itemID)) or 0
        if requiredLevel > 0 and requiredLevel <= UnitLevel("player") - db.outgrownLevels then
            return "outgrown"
        end
    end

    -- Soulbound armor lighter than you wear, like leather on a warrior. Only
    -- soulbound: anything else could still go to the auction house. Cloaks
    -- are cloth for everyone, so they don't count.
    if isGear and info.isBound and quality and quality <= EPIC and db.sellLighterArmor and classID == ARMOR
        and subClassID >= CLOTH and subClassID <= PLATE and equipLoc ~= "INVTYPE_CLOAK" then
        local heaviest = HeaviestArmor()
        if heaviest and subClassID < heaviest then return "lighterArmor" end
    end

    if classID == RECIPE and db.sellKnownRecipes and IsKnownRecipe(bag, slot) then return "knownRecipe" end
end

-- Why the item in a bag slot will be sold, or nil if it won't: your lists
-- first (an auto-sell item worth more at the auction house waits), then
-- equipment sets, then the junk rules. The keep rules come last and only
-- for items a rule would sell: they're the slower checks (equipped item
-- levels, auction prices), and most items in the bags aren't junk.
-- ignoreKeepRules answers "would it be sold if no keep rule protected it?".
local function JunkReason(info, bag, slot, ignoreKeepRules)
    local itemID = info.itemID
    local flag = db.items[itemID]
    if flag ~= nil then
        if flag and not ignoreKeepRules and WorthAuctioning(itemID, info.isBound) then return nil end
        return flag and "flagged" or nil
    end
    if InEquipmentSet(bag, slot) then return nil end
    local reason = RuleReason(info, bag, slot)
    if reason and not ignoreKeepRules and KeepRule(itemID, info.isBound, info.hyperlink) then return nil end
    return reason
end
ns.JunkReason = JunkReason

-- True if an item a junk rule would sell waits for your OK at the vendor:
-- from the askQuality setting up, and epics always. Items on your auto-sell
-- list never ask.
local function AsksFirst(info, reason)
    if not reason or reason == "flagged" or not info.quality then return false end
    return info.quality >= math.min(db.askQuality, EPIC)
end
ns.AsksFirst = AsksFirst

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
    -- The game puts its own coin (the same picture) on every grey item. With
    -- our icons on, our rules decide instead, so a grey that's kept (like an
    -- upgrade) shows no coin at all.
    if db.showIcons and button.JunkIcon then
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

-- A coin with a "?" in the coin's corner, for items that wait for your OK.
-- A green arrow on gear that's an upgrade, in the coin's corner.
local function SetUpgrade(button, show)
    local arrow = button.PocketGoblinUpgrade
    if show and not arrow then
        arrow = button:CreateTexture(nil, "OVERLAY", nil, 7)
        arrow:SetTexture(UPGRADE_ICON) -- in colour, not tinted
        button.PocketGoblinUpgrade = arrow
    end
    if arrow then
        local size = COIN_SIZE * db.iconScale
        arrow:SetSize(size, size)
        arrow:ClearAllPoints()
        arrow:SetPoint(db.iconCorner, 0, 0)
        arrow:SetShown(show)
    end
end

local function SetAsk(button, show)
    local icon = button.PocketGoblinAsk
    if show and not icon then
        icon = button:CreateTexture(nil, "OVERLAY", nil, 7)
        icon:SetTexture(ASK_ICON) -- in colour, not tinted
        button.PocketGoblinAsk = icon
    end
    if icon then
        local size = COIN_SIZE * db.iconScale
        icon:SetSize(size, size)
        icon:ClearAllPoints()
        icon:SetPoint(db.iconCorner, 0, 0)
        icon:SetShown(show)
    end
end

-- Equipment set icons by set name, from the Equipment Manager.
local setIcons
local function SetIconFor(setNames)
    if not setIcons then
        setIcons = {}
        local sets = C_EquipmentSet and C_EquipmentSet.GetEquipmentSetIDs and C_EquipmentSet.GetEquipmentSetIDs()
        for _, setID in ipairs(sets or {}) do
            local name, icon = C_EquipmentSet.GetEquipmentSetInfo(setID)
            if name then setIcons[name] = icon end
        end
    end
    if type(setNames) ~= "string" then return SET_FALLBACK_ICON end
    -- The game lists the item's sets as "Tank, Fire resistance"; use the first.
    return setIcons[setNames] or setIcons[setNames:match("^(.-), ") or ""] or SET_FALLBACK_ICON
end

-- The icon of the item's equipment set, framed, in the coin's corner. icon
-- is nil to hide it.
local function SetSetIcon(button, icon)
    local frame = button.PocketGoblinSet
    if icon and not frame then
        frame = CreateFrame("Frame", nil, button)
        frame:SetFrameLevel(button:GetFrameLevel() + 2)
        local border = frame:CreateTexture(nil, "ARTWORK", nil, 1)
        border:SetAllPoints()
        border:SetColorTexture(0, 0, 0, 0.9)
        frame.icon = frame:CreateTexture(nil, "ARTWORK", nil, 2)
        frame.icon:SetPoint("TOPLEFT", 1, -1)
        frame.icon:SetPoint("BOTTOMRIGHT", -1, 1)
        frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        button.PocketGoblinSet = frame
    end
    if frame then
        if icon then frame.icon:SetTexture(icon) end
        local size = COIN_SIZE * db.iconScale * 0.8
        frame:SetSize(size, size)
        frame:ClearAllPoints()
        frame:SetPoint(db.iconCorner, 1, -1)
        frame:SetShown(icon ~= nil)
    end
end

-- The item's equipment set names, or nil if it isn't in one.
local function EquipmentSets(bag, slot)
    local getInfo = C_Container.GetContainerItemEquipmentSetInfo
    if not getInfo then return nil end
    local ok, inSet, names = pcall(getInfo, bag, slot)
    if ok and inSet then return names or "" end
end

-- The one icon an item in your bags gets, all in the same corner, in this
-- order: what happens at the vendor ("coin", or "ask" for the "?" coin), then
-- gear you've set aside on purpose ("lock", then "set", with the set's icon
-- as the second value), then "upgrade" for the rest; nil for none. The third
-- value is true for junk that sells (to grey it out). otherArrow: another
-- upgrade arrow already shows on it (Pawn's or the game's).
local function ItemIcon(bag, slot, info, otherArrow)
    if not info then return nil end
    local reason = not info.hasNoValue and JunkReason(info, bag, slot)
    local asks = AsksFirst(info, reason)
    local junk = (reason and not asks) and true or false
    if junk and db.showIcons then return "coin", nil, true end
    if asks and db.showIcons then return "ask", nil, false end
    if db.keepIcon and db.items[info.itemID] == false then return "lock", nil, junk end
    local sets = db.setIcon and EquipmentSets(bag, slot)
    if sets then return "set", SetIconFor(sets), junk end
    if not otherArrow and ShowsUpgradeArrow(info.hyperlink) then return "upgrade", nil, junk end
    return nil, nil, junk
end
ns.ItemIcon = ItemIcon

-- True if Pawn's arrows show in the bags (Pawn's own option; EllesmereUI's
-- bags follow it too).
ns.PawnShowsBagArrows = PawnShowsBagArrows

local function UpdateButtonOverlay(button)
    local bag, slot = GetBagAndSlot(button)
    local info = bag and C_Container.GetContainerItemInfo(bag, slot)
    -- No arrow of ours when Pawn draws its own in these bags, or the game's shows.
    local otherArrow = PawnShowsBagArrows() or (button.UpgradeIcon and button.UpgradeIcon:IsShown())
    local icon, setIcon, junk = ItemIcon(bag, slot, info, otherArrow)
    SetCoin(button, icon == "coin")
    SetAsk(button, icon == "ask")
    SetUpgrade(button, icon == "upgrade")
    SetLock(button, icon == "lock")
    SetSetIcon(button, icon == "set" and setIcon or nil)
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
            local reason = JunkReason(info, bag, slot)
            return reason ~= nil and not AsksFirst(info, reason)
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
        Baganator.API.RegisterCornerWidget(L["Pocket Goblin: upgrade"], "pocketgoblin_upgrade",
            function(_, details)
                if not details.itemID then return nil end -- item info not ready yet
                return ShowsUpgradeArrow(details.itemLink)
            end,
            function(itemButton)
                local arrow = itemButton:CreateTexture(nil, "OVERLAY")
                arrow:SetTexture(UPGRADE_ICON)
                arrow:SetSize(15, 15)
                return arrow
            end,
            { corner = "top_left", priority = 2 })
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
    local sellers = ns.OtherJunkSellers()
    for i, seller in ipairs(sellers) do sellers[i] = seller.name end
    add("Other addons selling junk: %s", #sellers > 0 and table.concat(sellers, ", ") or "none")

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
    if ns.DebugMakeRoom then ns.DebugMakeRoom(add) end
    if ns.DebugSortButton then ns.DebugSortButton(add) else add("Sort button: BagSort.lua not loaded") end
    add("Upgrades judged by %s; arrow %s (needs Pawn), keep rule %s.", ns.UpgradeSource(),
        db.upgradeIcon and "on" or "off", db.protectUpgrades and "on" or "off")
    add("Disenchant: %s, keep rule %s.", KnowsDisenchant() and "known" or "not known",
        db.keepDisenchant and "on" or "off")
    local worn, swapped = 0, 0
    for _, entry in pairs(charData.worn) do
        worn = worn + 1
        if type(entry) == "table" and entry.equips >= 2 then swapped = swapped + 1 end
    end
    add("Ask first from quality %d, %d items waiting. Gear remembered: %d, put on more than once: %d, keep rule %s.",
        db.askQuality, #ns.GetAskedItems(), worn, swapped, db.keepWorn and "on" or "off")
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
        "sellSoulbound", "skipQuestGear", "keepValuable", "autoRepair", "destroyButton", "messages" }) do
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
    if ns.RefreshEllesmere then ns.RefreshEllesmere() end
    RefreshWindow()
    if ns.UpdateDestroyButtons then ns.UpdateDestroyButtons() end
    if ns.UpdateMerchantPanel then ns.UpdateMerchantPanel() end
    if Baganator and Baganator.API and Baganator.API.RequestItemButtonsRefresh then
        Baganator.API.RequestItemButtonsRefresh()
    end
end

-- value: true = auto-sell list, false = keep list, nil = neither (the junk
-- rules decide). message optionally replaces the chat message.
-- Whether your copy of an item (the first in your bags) is soulbound; nil
-- if you carry none.
local function BoundInBags(itemID)
    for bag = 0, LAST_BAG do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID == itemID then return info.isBound end
        end
    end
end

local function SetFlag(itemID, value, message)
    db.items[itemID] = value
    db.addedAt[itemID] = value ~= nil and time() or nil
    local label = ItemLabel(itemID)
    if message then
        Notify(message, label)
    elseif value == true and WorthAuctioning(itemID, BoundInBags(itemID)) then
        Notify(L["%s added to the auto-sell list, but kept for now: it's worth more at the auction house "
            .. "(Junk rules, Kept automatically)."], label)
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

-- Key bindings (Bindings.xml): put the item under the mouse on a list. They
-- get their own "Pocket Goblin" section in the game's Key Bindings.
--
-- Unlike the menu's checkboxes, a key only ever adds: pressing it again on
-- an item that's already on the list leaves it there, so a quick tap on
-- something you marked earlier (say, a loot toast) can't undo it. The other
-- key moves the item to the other list; taking it off a list altogether is
-- for the Alt+Right-click menu, which shows where it is.
BINDING_NAME_POCKETGOBLIN_SELL = L["Auto-sell the item under the mouse"]
BINDING_NAME_POCKETGOBLIN_KEEP = L["Keep the item under the mouse"]

local function MarkSell(itemID)
    if db.items[itemID] == true then
        Notify(L["%s is already on the auto-sell list."], ItemLabel(itemID))
    else
        SetFlag(itemID, true)
    end
end

local function MarkKeep(itemID)
    if db.items[itemID] == false then
        Notify(L["%s is already on your keep list."], ItemLabel(itemID))
    else
        SetFlag(itemID, false)
    end
end

local function MarkHovered(mark)
    if not db then return end
    local itemID = GetHoveredItem()
    if not itemID then return end
    if select(11, C_Item.GetItemInfo(itemID)) == 0 then
        Notify(L["%s can't be sold to vendors."], ItemLabel(itemID))
        return
    end
    mark(itemID)
end

function PocketGoblin_SellHovered() MarkHovered(MarkSell) end
function PocketGoblin_KeepHovered() MarkHovered(MarkKeep) end

-- Like clicking the trash can (the key press counts as the hardware event
-- deleting needs), but says why when there's nothing to destroy.
BINDING_NAME_POCKETGOBLIN_DESTROY = L["Destroy cheapest junk"]

function PocketGoblin_DestroyCheapestJunk()
    if not db then return end
    local target, protected = ns.FindCheapestJunk()
    if target then
        ns.DestroyCheapestJunk()
    elseif protected > 0 then
        Print(L["All your junk is worth more than your limit of %s."], GetMoneyString(db.destroyLimit, true))
    else
        Print(L["No junk in your bags."])
    end
end

------------------------------------------------------------------------
-- Selling
------------------------------------------------------------------------

-- The item in a bag slot and its stack's value if it sells now; with asked,
-- only items that wait for your OK instead (see AsksFirst).
local function GetSellable(bag, slot, asked)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not info or not info.itemID or info.isLocked or info.hasNoValue then return end

    local reason = JunkReason(info, bag, slot)
    if reason and AsksFirst(info, reason) == (asked or false) then
        local price = select(11, C_Item.GetItemInfo(info.itemID)) or 0
        if price > 0 then
            return info, price * (info.stackCount or 1)
        end
    end
end

-- Starts the "today" counters afresh on a new day.
local function RollDay()
    local today = date("%Y-%m-%d")
    if charData.day ~= today then
        charData.day = today
        charData.today, charData.allToday = 0, 0
        charData.repairsToday, charData.repairsGuildToday = 0, 0
    end
end

-- Adds a sale to the earnings counters (negative for buybacks). Only
-- Pocket Goblin's own sales count as junk earnings; all sales count towards
-- the "all sales" totals.
local function AddEarnings(copper, stacks, byGoblin)
    RollDay()
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
    elseif db.items[entry.itemID] == nil and not db.noSuggest[entry.itemID] then
        db.manualSales[entry.itemID] = (db.manualSales[entry.itemID] or 0) + 1
    end
end

------------------------------------------------------------------------
-- Auto-sell suggestions: items you keep selling yourself
------------------------------------------------------------------------

local SUGGEST_AFTER = 3 -- times you sold an item yourself before it's suggested

-- The item you've sold yourself most often (at least SUGGEST_AFTER times)
-- that isn't on a list, wasn't declined and isn't junk already. Returns the
-- item ID and how many times, or nil.
function ns.GetSuggestion()
    local bestID, bestCount
    for itemID, count in pairs(db.manualSales) do
        if count >= SUGGEST_AFTER and db.items[itemID] == nil and not db.noSuggest[itemID]
            and (not bestCount or count > bestCount or (count == bestCount and itemID < bestID)) then
            local _, _, quality = C_Item.GetItemInfo(itemID)
            if quality == nil then
                C_Item.RequestLoadItemDataByID(itemID) -- try again on the next update
            elseif not IsJunk(itemID, quality) then
                bestID, bestCount = itemID, count
            end
        end
    end
    return bestID, bestCount
end

-- Answers a suggestion: yes puts the item on the auto-sell list, no stops
-- suggesting it.
function ns.AnswerSuggestion(itemID, accept)
    db.manualSales[itemID] = nil
    if accept then
        ns.SetFlag(itemID, true)
    else
        db.noSuggest[itemID] = true
        if ns.UpdateMerchantPanel then ns.UpdateMerchantPanel() end
    end
end

-- Marks milestones the character has reached; announces them unless quiet.
function ns.CheckMilestones(quiet)
    for _, milestone in ipairs(ns.MILESTONES) do
        local reached = (milestone.sold and charData.sold >= milestone.sold)
            or (milestone.earned and charData.earned >= milestone.earned)
            or (milestone.repaired and charData.repairs + charData.repairsGuild >= milestone.repaired)
        if reached and not charData.milestones[milestone.key] then
            charData.milestones[milestone.key] = true
            if not quiet and ns.GoblinVoice() then
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
        Summary(ns.Say("sold", L["Sold %d item(s) for %s."], sellSummary.count, GetMoneyString(sellSummary.money, true)))
        if sellSummary.leftOver > 0 then
            Summary(L["%d more junk items left. Press Sell junk to sell the next %d."], sellSummary.leftOver,
                math.min(sellSummary.leftOver, BUYBACK_SIZE))
        end
    end
    sellSummary = nil
end

-- Sells the junk in the bags. asked sells the items that wait for your OK
-- instead (you just gave it), all of them, or only the one at onlyBag and
-- onlySlot.
local function SellJunk(manual, asked, onlyBag, onlySlot)
    if not merchantOpen then
        Print(L["Open a vendor window first."])
        return
    end
    if ns.IsBuyingBack() then return end
    if ns.IsSorting() then
        if manual then Print(L["Wait until your bags are sorted."]) end
        return
    end
    StopSelling()

    local queue = {}
    for bag = 0, LAST_BAG do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = (not onlyBag or (bag == onlyBag and slot == onlySlot)) and GetSellable(bag, slot, asked)
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
        local info, value = GetSellable(entry.bag, entry.slot, asked)
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

-- Items that wait for your OK before they're sold:
-- { { bag, slot, info, reason, value }, ... }, most valuable first.
function ns.GetAskedItems()
    local found = {}
    for bag = 0, LAST_BAG do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info, value = GetSellable(bag, slot, true)
            if info then
                found[#found + 1] = { bag = bag, slot = slot, info = info, value = value,
                    reason = JunkReason(info, bag, slot) }
            end
        end
    end
    table.sort(found, function(a, b) return a.value > b.value end)
    return found
end

-- With the vendor panel off, say in chat which items are waiting, once a visit.
local function MentionAskedItems()
    if db.merchantPanel then return end
    local asked = ns.GetAskedItems()
    if #asked == 0 then return end
    local links = {}
    for _, entry in ipairs(asked) do links[#links + 1] = entry.info.hyperlink end
    Summary(L["Waiting for your OK, so not sold: %s. Turn on the vendor panel to sell them, or sell them yourself."],
        table.concat(links, ", "))
end

function ns.GetHistory()
    return charData.history
end

-- Earnings as { session, today, character, account } tables of
-- { junk = Pocket Goblin's sales, all = every vendor sale, repairs = repairs
-- paid from your gold, guildRepairs = repairs the guild paid }. character and
-- account also have biggestRepair ({ cost, time, vendor }, or nil), and
-- account the name of the character it belongs to (biggestRepairBy).
function ns.GetEarnings()
    local isToday = charData.day == date("%Y-%m-%d")
    local account = { junk = 0, all = 0, repairs = 0, guildRepairs = 0 }
    for key, character in pairs(PocketGoblinDB.characters) do
        account.junk = account.junk + (character.earned or 0)
        account.all = account.all + (character.allEarned or 0)
        account.repairs = account.repairs + (character.repairs or 0)
        account.guildRepairs = account.guildRepairs + (character.repairsGuild or 0)
        local biggest = character.biggestRepair
        if biggest and (not account.biggestRepair or biggest.cost > account.biggestRepair.cost) then
            account.biggestRepair = biggest
            account.biggestRepairBy = key:match("^(.-) %- ") or key
        end
    end
    return {
        session = { junk = session.earned, all = session.allEarned,
            repairs = session.repairs, guildRepairs = session.repairsGuild },
        today = { junk = isToday and charData.today or 0, all = isToday and charData.allToday or 0,
            repairs = isToday and charData.repairsToday or 0, guildRepairs = isToday and charData.repairsGuildToday or 0 },
        character = { junk = charData.earned, all = charData.allEarned,
            repairs = charData.repairs, guildRepairs = charData.repairsGuild, biggestRepair = charData.biggestRepair },
        account = account,
    }
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
            Summary(ns.Say("boughtBack", L["Bought back %s."], sold.link .. (sold.count > 1 and (" x" .. sold.count) or "")))
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

local BUYBACK_INTERVAL = 0.3 -- seconds between buybacks in "Buy back all"
local buybackTicker

local function StopBuyingBack()
    if buybackTicker then
        buybackTicker:Cancel()
        buybackTicker = nil
        ns.UpdateMerchantPanel()
    end
end

-- Buys back each of the sold history items in turn. Waits for the game to
-- confirm each buyback before the next, and stops when the bags are full,
-- the money runs out or the vendor closes.
function ns.BuyBackAll(items)
    if buybackTicker or ns.IsSelling() then return end
    local queue, index, waits = {}, 0, 0
    for i, sold in ipairs(items) do queue[i] = sold end
    buybackTicker = C_Timer.NewTicker(BUYBACK_INTERVAL, function()
        if not merchantOpen then
            StopBuyingBack()
            return
        end
        -- The last buyback hasn't reached the vendor's list yet.
        if GetNumBuybackItems() ~= #buybackSnapshot then
            waits = waits + 1
            if waits > 10 then StopBuyingBack() end
            return
        end
        waits = 0
        index = index + 1
        local sold = queue[index]
        if not sold then
            StopBuyingBack()
        elseif ns.GetFreeBagSlots() == 0 then
            Print(L["Your bags are full. Make room to buy back the rest."])
            StopBuyingBack()
        elseif GetMoney() < sold.value then
            Print(L["Not enough money to buy back the rest."])
            StopBuyingBack()
        elseif not sold.boughtBack then
            ns.BuyBack(sold)
        end
    end)
    ns.UpdateMerchantPanel()
end

function ns.IsBuyingBack()
    return buybackTicker ~= nil
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
            Summary(ns.Say("repairedGuild", L["Repaired for %s from guild funds."], GetMoneyString(cost, true)))
            return
        end
    end
    if GetMoney() >= cost then
        RepairAllItems()
        Summary(ns.Say("repaired", L["Repaired for %s."], GetMoneyString(cost, true)))
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
        RollDay()
        if guildRepairPending then
            charData.repairsGuild = charData.repairsGuild + spent
            charData.repairsGuildToday = charData.repairsGuildToday + spent
            session.repairsGuild = session.repairsGuild + spent
        else
            charData.repairs = charData.repairs + spent
            charData.repairsToday = charData.repairsToday + spent
            session.repairs = session.repairs + spent
        end
        ns.CheckMilestones()
        RefreshWindow()
    end
    guildRepairPending = false
    repairCost = cost
end

-- What a vendor visit's repairs cost, whoever paid.
local function VisitRepairCost(visit)
    local cost = 0
    for _, repair in ipairs(visit.repairs or {}) do cost = cost + repair.cost end
    return cost
end

-- The most expensive visit's repairs in the history, for characters that
-- repaired before the record was kept.
local function FindBiggestRepair()
    for _, visit in ipairs(charData.history) do
        local cost = VisitRepairCost(visit)
        if cost > 0 and (not charData.biggestRepair or cost > charData.biggestRepair.cost) then
            charData.biggestRepair = { cost = cost, time = visit.time, vendor = visit.vendor }
        end
    end
end

-- When a vendor visit with repairs ends: keeps the record for the most
-- expensive repairs, and in its own voice the goblin groans about a bill
-- three times the usual, and (once a day) about repairs costing more than
-- the day's sales.
local function ReviewRepairs(visit)
    local bill = visit and VisitRepairCost(visit) or 0
    if bill <= 0 then return end

    local total, bills = 0, 0 -- earlier bills in the history, for the usual one
    for _, earlier in ipairs(charData.history) do
        local cost = earlier ~= visit and VisitRepairCost(earlier) or 0
        if cost > 0 then total, bills = total + cost, bills + 1 end
    end
    local record = charData.biggestRepair
    local isRecord = not record or bill > record.cost
    if isRecord then
        charData.biggestRepair = { cost = bill, time = visit.time, vendor = visit.vendor }
    end
    if not ns.GoblinVoice() then return end

    if bills >= 5 and bill >= 3 * total / bills then
        Print(ns.Say(isRecord and "repairRecord" or "repairBig", "%s", GetMoneyString(bill, true)))
    end
    RollDay()
    if charData.repairsToday > charData.allToday and charData.ledgerDay ~= charData.day then
        charData.ledgerDay = charData.day
        Print(ns.Say("ledgerRed", "%s %s", GetMoneyString(charData.repairsToday, true),
            charData.allToday > 0 and GetMoneyString(charData.allToday, true) or "0"))
    end
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
            if reason and (not reasons or reasons[reason]) and not AsksFirst(info, reason) then
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
            local reason = info and info.itemID and not info.isLocked and JunkReason(info, bag, slot)
            if reason and not AsksFirst(info, reason) then
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
    if reason and db.tooltipValue and AsksFirst(info, reason) then
        tooltip:AddLine(L["Pocket Goblin: sells when you OK it at a vendor ("] .. REASONS[reason] .. ")",
            ASK_COLOR[1], ASK_COLOR[2], ASK_COLOR[3], true)
    elseif reason and db.tooltipValue then
        local price = select(11, C_Item.GetItemInfo(data.id)) or 0
        local count = info.stackCount or 1
        local value = price > 0 and GetMoneyString(price * count, true) or L["no value"]
        tooltip:AddDoubleLine(L["Pocket Goblin: sells ("] .. REASONS[reason] .. ")",
            value .. (count > 1 and ("  |cff8a8b93x" .. count .. "|r") or ""), 1, 0.82, 0, 1, 1, 1)
    elseif flag == true and info and info.itemID == data.id and WorthAuctioning(data.id, info.isBound) then
        tooltip:AddLine(L["Pocket Goblin: kept ("] .. ns.KeepRuleText("auction") .. ")",
            LOCK_COLOR[1], LOCK_COLOR[2], LOCK_COLOR[3], true)
    elseif flag == true then
        tooltip:AddLine(L["Pocket Goblin: auto-sell"], 1, 0.82, 0)
    elseif flag == false then
        tooltip:AddLine(L["Pocket Goblin: kept"], LOCK_COLOR[1], LOCK_COLOR[2], LOCK_COLOR[3])
    elseif info and info.itemID == data.id and db.tooltipValue then
        -- Say so when a keep rule is what stops it from being sold.
        local rule, word = KeepRule(data.id, info.isBound, info.hyperlink)
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
    print(L["  /goblin chat [goblin|plain|summaries|none] - choose how the goblin talks in chat"])
    print(L["  /goblin profile [name] - show or switch this character's profile"])
    print(L["  /goblin sell - sell now (vendor must be open)"])
    print(L["  /goblin sort - stack and sort your bags"])
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
    elseif cmd == "sort" then
        ns.SortBags()
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
        -- Sets the given style, or moves on to the next one.
        local order = { "goblin", "plain", "summaries", "none" }
        local style = arg:lower()
        if style == "off" then style = "none" end
        if not tContains(order, style) then
            local current = 0
            for i, key in ipairs(order) do
                if key == db.messages then current = i end
            end
            style = order[current % #order + 1]
        end
        db.messages = style
        Print(L["Chat messages: %s"], ns.MessageStyleName(style))
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

-- Brings a profile's settings up to date: renamed and merged settings, then
-- defaults for anything missing.
local function UpgradeProfile(profile)
    -- The auction rule's multiplier and minimum became one profit amount.
    profile.auctionFactor, profile.auctionMinimum = nil, nil
    -- White-gear auto-flagging became the white-gear rule.
    if profile.autoFlagGear ~= nil then
        profile.sellWhiteGear, profile.autoFlagGear = profile.autoFlagGear, nil
        profile.whiteGearLevel, profile.autoFlagLevel = profile.autoFlagLevel, nil
    end
    -- Chat, goblin voice and milestones became one "messages" setting.
    if profile.messages == nil and (profile.chat ~= nil or profile.goblinVoice ~= nil) then
        profile.messages = (profile.chat == false and "summaries") or (profile.goblinVoice == false and "plain") or "goblin"
    end
    -- "Off" still showed summaries, so it's now called that ("none" is new).
    if profile.messages == "off" then profile.messages = "summaries" end
    profile.chat, profile.goblinVoice, profile.milestones = nil, nil, nil
    -- "Gear your class can't use" and "outgrown gear" became one rule.
    if profile.sellSoulbound == nil and (profile.sellUnusable ~= nil or profile.sellOutgrown ~= nil) then
        profile.sellSoulbound = (profile.sellUnusable or profile.sellOutgrown) and true or false
    end
    profile.sellUnusable, profile.sellOutgrown = nil, nil
    -- Removed: the vendor panel always lists your own sales.
    profile.merchantPanelAll = nil

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
end

local function LoadProfile(name)
    local profile = PocketGoblinDB.profiles[name] or {}
    PocketGoblinDB.profiles[name] = profile
    UpgradeProfile(profile)
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
    UpgradeProfile(db) -- the source may not have been loaded since an update
    Print(L["Copied profile %s into %s."], source, ns.GetProfileName())
    ProfileChanged()
end

-- The other profiles with items on one list (flag true: auto-sell, false:
-- keep): { { name =, count = }, ... }, the most items first.
function ns.ListSources(flag)
    local sources = {}
    for name, profile in pairs(PocketGoblinDB.profiles) do
        if profile ~= db and profile.items then
            local count = 0
            for _, itemFlag in pairs(profile.items) do
                if itemFlag == flag then count = count + 1 end
            end
            if count > 0 then sources[#sources + 1] = { name = name, count = count } end
        end
    end
    table.sort(sources, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.name < b.name
    end)
    return sources
end

-- Adds another profile's auto-sell and keep lists to the active one,
-- without touching its settings. Items already on one of the active
-- profile's lists stay as they are.
function ns.ImportLists(source)
    local from = PocketGoblinDB.profiles[source]
    if not from or from == db then return end
    UpgradeProfile(from) -- the source may not have been loaded since an update
    local added = 0
    for itemID, flag in pairs(from.items) do
        if db.items[itemID] == nil then
            db.items[itemID] = flag
            db.addedAt[itemID] = from.addedAt[itemID] or time()
            added = added + 1
        end
    end
    if added == 0 then
        Print(L["Nothing to import from %s: every item on its lists is on yours already."], source)
    elseif added == 1 then
        Print(L["Imported 1 item from %s."], source)
    else
        Print(L["Imported %d items from %s."], added, source)
    end
    ProfileChanged()
end

function ns.ResetProfile()
    wipe(db)
    UpgradeProfile(db)
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
-- Sharing lists and profiles (the text format itself is in Share.lua)
------------------------------------------------------------------------

do
    -- Profile settings that belong to you, not to the setup you share: where
    -- your minimap button is, your auto-sell suggestions and list filters.
    local PRIVATE = { showMinimap = true, minimapAngle = true, addedAt = true, manualSales = true,
        noSuggest = true, filters = true }
    -- Settings with a fixed set of values.
    local CHOICES = {
        messages = { goblin = true, plain = true, summaries = true, none = true, off = true },
        iconCorner = { TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true },
        askQuality = { [2] = true, [3] = true, [4] = true },
    }

    local function IsID(value)
        return type(value) == "number" and value > 0 and value == math.floor(value) and value < 10000000
    end

    -- The lists in shared data, keeping only well-formed entries.
    local function CleanLists(data)
        local lists = { items = {}, keepWords = {}, keepClasses = {} }
        if type(data) ~= "table" then return lists end
        for itemID, flag in pairs(type(data.items) == "table" and data.items or {}) do
            if IsID(itemID) and type(flag) == "boolean" then lists.items[itemID] = flag end
        end
        local seen = {}
        for _, word in ipairs(type(data.keepWords) == "table" and data.keepWords or {}) do
            word = type(word) == "string" and strtrim(word:lower()) or ""
            if word ~= "" and #word <= 50 and not seen[word] then
                seen[word] = true
                lists.keepWords[#lists.keepWords + 1] = word
            end
        end
        for classID, on in pairs(type(data.keepClasses) == "table" and data.keepClasses or {}) do
            if type(classID) == "number" and classID >= 0 and classID < 100 and on == true then
                lists.keepClasses[classID] = true
            end
        end
        return lists
    end

    -- A profile from shared data: known settings of the right kind only, so
    -- a damaged or edited text can't put anything odd in your settings.
    local function CleanProfile(data)
        local profile = CleanLists(data)
        if type(data) ~= "table" then return profile end
        for key, default in pairs(defaults) do
            local value = data[key]
            if type(default) ~= "table" and not PRIVATE[key] and type(value) == type(default)
                and value == value -- not NaN
                and (not CHOICES[key] or CHOICES[key][value]) then
                profile[key] = value
            end
        end
        if type(data.version) == "number" then profile.version = data.version end
        if type(data.listsVersion) == "number" then profile.listsVersion = data.listsVersion end
        return profile
    end

    -- What to share: kind "lists" (auto-sell and keep lists, keep words and
    -- item types) or "profile" (the whole active profile, but not PRIVATE).
    function ns.ExportData(kind)
        local data
        if kind == "lists" then
            data = { items = DeepCopy(db.items), keepWords = DeepCopy(db.keepWords),
                keepClasses = DeepCopy(db.keepClasses) }
        else
            data = DeepCopy(db)
            for key in pairs(PRIVATE) do data[key] = nil end
        end
        return { v = 1, kind = kind, name = ns.GetProfileName(), from = UnitName("player"), data = data }
    end

    -- Counts for an import preview: items to auto-sell, to keep, keep words
    -- and item types.
    function ns.CountSharedLists(data)
        local lists = CleanLists(data)
        local sell, keep, types = 0, 0, 0
        for _, flag in pairs(lists.items) do
            if flag then sell = sell + 1 else keep = keep + 1 end
        end
        for _ in pairs(lists.keepClasses) do types = types + 1 end
        return sell, keep, #lists.keepWords, types
    end

    -- Adds shared lists to the active profile. Items you've already listed
    -- stay as they are, and nothing is removed.
    function ns.ImportSharedLists(data, source)
        local lists = CleanLists(data)
        local items, words, types = 0, 0, 0
        for itemID, flag in pairs(lists.items) do
            if db.items[itemID] == nil then
                db.items[itemID] = flag
                db.addedAt[itemID] = time()
                items = items + 1
            end
        end
        for _, word in ipairs(lists.keepWords) do
            if not tContains(db.keepWords, word) then
                db.keepWords[#db.keepWords + 1] = word
                words = words + 1
            end
        end
        for classID in pairs(lists.keepClasses) do
            if not db.keepClasses[classID] then
                db.keepClasses[classID] = true
                types = types + 1
            end
        end
        if items + words + types == 0 then
            Print(L["Nothing new from %s: everything on those lists is on yours already."], source)
        else
            Print(L["Imported from %s: %d items, %d name words and %d item types."], source, items, words, types)
        end
        ProfileChanged()
    end

    -- Makes a new profile from a shared one and switches to it; your own
    -- minimap button stays where it is. False if the name is empty or taken.
    function ns.CreateSharedProfile(name, data)
        name = name and strtrim(name)
        if not name or name == "" or PocketGoblinDB.profiles[name] then return false end
        local profile = CleanProfile(data)
        profile.showMinimap, profile.minimapAngle = db.showMinimap, db.minimapAngle
        PocketGoblinDB.profiles[name] = profile
        ns.SetProfile(name) -- loading it also brings older shared profiles up to date
        return true
    end
end

------------------------------------------------------------------------
-- Other addons that sell junk
------------------------------------------------------------------------

-- With two addons selling at the same vendor, the other one can sell what's on
-- the keep list, and its sales are missing from the history (some don't even
-- reach the buyback tab). For addons with a switch for it, on() reads that
-- switch and option names it; the rest count as selling whenever they're loaded.
local OTHER_SELLERS = {
    { addon = "NaowhForever_QoL", name = "Naowh Forever", option = "Auto Sell Junk", on = function()
        local settings = NaowhForever.QoLSettings
        return settings.Get("enabled") and settings.Get("sellJunk")
    end },
    { addon = "EnhanceQoLVendor", name = "Enhance QoL", option = "Automatically sell all junk items", on = function()
        local settings = EnhanceQoL.db
        if settings.sellAllJunk then return true end
        for _, quality in ipairs({ "Poor", "Common", "Uncommon", "Rare", "Epic" }) do
            if settings["vendor" .. quality .. "Enable"] then return true end
        end
        return false
    end },
    { addon = "EllesmereUIQoL", name = "EllesmereUI", option = "Auto Sell Junk", on = function()
        return EllesmereUIDB == nil or EllesmereUIDB.autoSellJunk ~= false -- on unless turned off
    end },
    { addon = "Leatrix_Plus", name = "Leatrix Plus", option = "Sell junk automatically", on = function()
        return LeaPlusDB.AutoSellJunk == "On"
    end },
    { addon = "ElvUI", name = "ElvUI", on = function() return ElvUI[1].db.general.vendorGrays end },
    { addon = "Scrap", name = "Scrap" },
    { addon = "Dejunk", name = "Dejunk" },
    { addon = "Peddler", name = "Peddler" },
    { addon = "AutoVendor", name = "AutoVendor" },
    { addon = "Vendor", name = "Vendor" },
    { addon = "SellJunk", name = "SellJunk" },
}

-- The loaded addons that will sell junk at the next vendor, as OTHER_SELLERS entries.
function ns.OtherJunkSellers()
    local found = {}
    if not (C_AddOns and C_AddOns.IsAddOnLoaded) then return found end
    for _, seller in ipairs(OTHER_SELLERS) do
        if C_AddOns.IsAddOnLoaded(seller.addon) then
            local selling = true
            if seller.on then
                -- If the addon has moved its settings, warn rather than stay quiet.
                local ok, on = pcall(seller.on)
                selling = not ok or on and true or false
            end
            if selling then found[#found + 1] = seller end
        end
    end
    return found
end

-- The other sellers worth a warning: none while Pocket Goblin doesn't sell on
-- its own or the warning is turned off.
function ns.ConflictingSellers()
    if not (db.autoSell and db.warnOtherSellers) then return {} end
    return ns.OtherJunkSellers()
end

ns.OTHER_SELLERS_PROBLEM = L["While another addon sells junk too, Pocket Goblin can't keep your keep list safe, and some sales won't show in your history or the buyback tab."]

-- What to do about it: turn off the other addon's selling, not Pocket Goblin's.
function ns.OtherSellersAdvice(count)
    return count == 1
        and L["Turn off junk selling in that addon, or Pocket Goblin may not work correctly."]
        or L["Turn off junk selling in those addons, or Pocket Goblin may not work correctly."]
end

-- The vendor panel shows the warning at every vendor. With the panel off, chat
-- says it once a session, and again if the other addon's selling is turned off
-- and later back on.
local otherSellersWarned = false
local function WarnOtherSellers()
    local sellers = ns.ConflictingSellers()
    if #sellers == 0 then
        otherSellersWarned = false
        return
    end
    if otherSellersWarned or db.merchantPanel or db.messages == "none" then return end
    otherSellersWarned = true
    C_Timer.After(1, function() -- after the sale messages
        for _, seller in ipairs(sellers) do
            if seller.option then
                Print(L["%s also sells junk at vendors (its \"%s\" option)."], seller.name, seller.option)
            else
                Print(L["%s also sells junk at vendors."], seller.name)
            end
        end
        Print(ns.OTHER_SELLERS_PROBLEM .. " " .. ns.OtherSellersAdvice(#sellers))
    end)
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------

local knewDisenchant = false -- whether this character knew Disenchant at the last check

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
frame:RegisterEvent("SPELLS_CHANGED")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
frame:RegisterEvent("EQUIPMENT_SETS_CHANGED")
frame:RegisterEvent("PLAYER_LOGOUT")

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
        if not charData.repairMilestones then
            -- Repair milestones came in 1.7: count what's already spent without cheering.
            charData.repairMilestones = true
            ns.CheckMilestones(true)
            FindBiggestRepair()
        end
    elseif event == "PLAYER_LOGIN" then
        HookContainerFrames()
        RegisterBaganatorPlugin()
        ns.UpdateMinimapButton()
        UpdateBestFood()
        ns.SetupDestroyButtons()
        ns.SetupSortButton()
        ns.SetupOpenButtons()
        RecordWorn()
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
        MentionAskedItems()
        WarnOtherSellers()
        ns.UpdateMerchantPanel()
    elseif event == "MERCHANT_CLOSED" then
        merchantOpen = false
        StopSelling()
        StopBuyingBack()
        ReviewRepairs(currentVisit)
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
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        RecordWorn()
        ns.ForgetUpgradeArrows() -- what's an upgrade depends on what you wear
        RefreshOverlays()
        if ns.RefreshEllesmere then ns.RefreshEllesmere() end
    elseif event == "EQUIPMENT_SETS_CHANGED" then
        setIcons = nil -- a set may have a new name or icon
        RefreshOverlays()
    elseif event == "PLAYER_LOGOUT" then
        RecordWorn() -- so gear worn all session counts until now
    elseif event == "SPELLS_CHANGED" then
        -- Learning (or unlearning) Enchanting changes what the disenchant rule keeps.
        local knows = KnowsDisenchant()
        if knows ~= knewDisenchant then
            knewDisenchant = knows
            ns.OnRulesChanged()
        end
    elseif event == "PLAYER_LEVEL_UP" then
        -- UnitLevel can lag behind the event, so check a moment later.
        -- (White gear and food rules depend on your level.)
        C_Timer.After(1, function()
            ns.ForgetUpgradeArrows() -- gear you couldn't wear yet may be wearable now
            ns.OnRulesChanged()
        end)
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
