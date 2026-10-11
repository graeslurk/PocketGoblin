-- The goblin's voice: chat lines, milestones and moods. Every line in a
-- group takes the same format arguments, in the same order, as the plain
-- message it replaces.

local ADDON_NAME, ns = ...
local L = ns.L

local LINES = {
    -- count, money
    sold = {
        L["Haggled %d items for %s. Pleasure doin' business!"],
        L["Sold %d items for %s. Time is money, friend!"],
        L["%d items gone, %s in the pocket. Heh heh."],
        L["Cha-ching! %d items for %s."],
        L["Unloaded %d pieces of junk for %s. Don't ask how."],
        L["%d items, %s. The vendor never stood a chance."],
        L["Sold %d bits of rubbish for %s. One goblin's trash is another goblin's treasure!"],
        L["Moved %d items for %s. I'll take my cut later."],
        L["That's %d items sold for %s. Smells like profit!"],
        L["Cleared out %d items for %s. Your bags can breathe again."],
        L["%d items for %s! I've seen worse deals. Mostly my own."],
        L["Flipped %d items for %s. No questions asked, no refunds given."],
    },
    -- nothing
    nothingToSell = {
        L["Nothing to sell. You're making me look bad, boss."],
        L["No junk? Suspicious. Very suspicious."],
        L["Empty-handed again. I'll be in the bag."],
        L["Not a single grey in sight. I'm bored."],
        L["Your bags are clean. Too clean."],
        L["Nothing for me to sell. Go hit something and bring me loot!"],
        L["I checked twice. No junk. Not even a broken tooth."],
    },
    -- money
    repaired = {
        L["Patched up your gear for %s. Don't tell the smith I haggled."],
        L["Repairs done for %s. Try not to break it so fast next time!"],
        L["%s for repairs. Highway robbery, but it's done."],
        L["Fixed you up for %s. Good as new. Mostly."],
        L["%s to un-break your stuff. Worth every copper."],
        L["Your armor's whole again for %s. Maybe try dodging?"],
    },
    repairedGuild = {
        L["Repaired for %s on the guild's coin. Generous bunch!"],
        L["Guild paid %s for your repairs. Free money is the best money."],
        L["%s on the guild tab. Shh, nobody's watching."],
        L["The guild bank just covered %s in repairs. Bless 'em."],
    },
    cantRepair = {
        L["Repairs cost %s and you can't afford it. Sell more junk, boss!"],
        L["We're %s short of fixing your gear. Embarrassing."],
        L["Repairs need %s and your purse says no. Let's go find junk!"],
    },
    -- item, value
    destroyed = {
        L["Tossed %s (worth %s). Into the furnace!"],
        L["%s is gone. Worth %s, so who's counting?"],
        L["Chucked %s. That's %s we'll never see again."],
        L["Into the trash with %s. Worth %s, rest in pieces."],
        L["Goodbye, %s. Your %s of value will be missed. Not really."],
        L["%s went poof. That's %s gone, but think of the bag space!"],
    },
    -- item
    boughtBack = {
        L["Fine, fine, %s is back. No refunds on my time!"],
        L["Bought back %s. Changed your mind, eh?"],
        L["Got %s back for you. Goblins never lose a receipt."],
        L["%s is back in your bags. Sentimental, are we?"],
        L["Retrieved %s. That's what I call customer service!"],
        L["%s returned. The vendor looked offended."],
    },
    -- free slots
    bagsLow = {
        L["Oi! Only %d bag slots left. Want me to toss something?"],
        L["Bags are bursting, just %d slots left! Find a vendor, quick."],
        L["%d free slots. I'm getting squished in here!"],
        L["Only %d slots left! Even goblins need elbow room."],
        L["We're down to %d bag slots. Something's gotta go!"],
        L["%d slots left, boss. Shall I start tossing?"],
    },
}

-- The message in goblin voice if that's on, otherwise the plain one, with
-- the arguments filled in.
function ns.Say(key, plain, ...)
    local lines = ns.db and ns.db.goblinVoice and LINES[key]
    local template = lines and lines[math.random(#lines)] or plain
    return template:format(...)
end

------------------------------------------------------------------------
-- Milestones
------------------------------------------------------------------------

-- Checked against the character's lifetime numbers (sold = item stacks,
-- earned = copper, both from the goblin's own sales).
ns.MILESTONES = {
    { key = "firstSale", sold = 1, text = L["Your goblin made its first sale. The start of an empire!"] },
    { key = "sold50", sold = 50, text = L["50 sales. The goblin has started keeping a ledger."] },
    { key = "sold100", sold = 100, text = L["100 sales! The goblin is pleased."] },
    { key = "sold500", sold = 500, text = L["500 sales. Vendors know you by name now."] },
    { key = "sold1000", sold = 1000, text = L["1,000 sales! The goblin is shopping for a bigger pocket."] },
    { key = "sold5000", sold = 5000, text = L["5,000 sales. The goblin has started a union."] },
    { key = "gold1", earned = 10000, text = L["Your goblin has made its first gold!"] },
    { key = "gold5", earned = 50000, text = L["5 gold from junk. The goblin is pricing out a second pocket."] },
    { key = "gold10", earned = 100000, text = L["10 gold from junk! The goblin bought itself a tiny hat."] },
    { key = "gold50", earned = 500000, text = L["50 gold from junk. The tiny hat now has a tiny feather."] },
    { key = "gold100", earned = 1000000, text = L["100 gold from junk. Trade Princes are taking notice."] },
    { key = "gold1000", earned = 10000000,
        text = L["1,000 gold from junk! The goblin has retired to a private island. (It's still in your pocket.)"] },
}

------------------------------------------------------------------------
-- Moods
------------------------------------------------------------------------

-- Logo texture for each mood (in Media/).
ns.MOOD_LOGOS = {
    happy = "logo",
    eager = "logo-eager",
    worried = "logo-worried",
    sleepy = "logo-sleepy",
}

-- Lines for each mood, with the same arguments within a mood.
local MOOD_LINES = {
    worried = { -- free slots, "slot"/"slots"
        L["Your goblin is worried: only %d bag %s left!"],
        L["Your goblin is sweating: %d bag %s left!"],
        L["Your goblin is getting squished: %d free bag %s!"],
    },
    happy = { -- money this session
        L["Your goblin is counting coins: %s this session."],
        L["Your goblin is grinning: %s earned this session."],
        L["Your goblin is polishing %s worth of coins."],
    },
    eager = { -- count, "item"/"items", money
        L["Your goblin is eager to sell %d junk %s (%s)."],
        L["Your goblin is rubbing its hands: %d junk %s worth %s."],
        L["Your goblin can smell profit: %d junk %s (%s)."],
    },
    sleepy = {
        L["Your goblin is napping. No junk in your bags."],
        L["Your goblin is snoring on a pile of coins."],
        L["Your goblin is dozing. Wake it up with some junk!"],
    },
}

-- One line per mood is picked when the mood changes, so the text doesn't
-- jump around on every refresh.
local currentMood, moodLine

local function MoodLine(mood, ...)
    if mood ~= currentMood then
        currentMood = mood
        moodLine = MOOD_LINES[mood][math.random(#MOOD_LINES[mood])]
    end
    return moodLine:format(...)
end

-- The goblin's mood: worried when the bags are nearly full, happy right
-- after selling, eager when junk is waiting, and napping otherwise.
-- Returns the mood and a line describing it.
function ns.GetMood()
    if ns.IsBagSpaceLow() then
        local free = ns.GetFreeBagSlots()
        return "worried", MoodLine("worried", free, free == 1 and "slot" or "slots")
    end
    local earned, recently = ns.GetRecentSales()
    if recently then
        return "happy", MoodLine("happy", GetMoneyString(earned, true))
    end
    local count, money = ns.GetJunkSummary()
    if count > 0 then
        return "eager", MoodLine("eager", count, count == 1 and "item" or "items", GetMoneyString(money, true))
    end
    return "sleepy", MoodLine("sleepy")
end
