-- What's new: after an update with new features, one line in chat at the
-- first login, a card at the top of the window until "Got it", and a dot
-- on the sidebar pages that changed until you visit them. A first install
-- gets none of it: everything is new then. Bug-fix releases without an
-- entry below stay quiet. (The same as Fanny Pack's.)

local ADDON_NAME, ns = ...
local L = ns.L

-- Newest first. version: the release; chat: what the chat line says is
-- new; points: the card's lines, each with the window page it's on and,
-- optionally, the setting (a key UI.lua's NewsDot gives its row) that gets
-- a dot.
ns.WHATS_NEW = {
    {
        version = "1.12.0",
        chat = L["a breakdown of what you sell with gold per day, and a search for your vendor visits"],
        points = {
            { text = L["What you sold: on the History page, see which kinds of items and which junk rules earn you the most gold, your top items, and your gold per day."],
                page = "history" },
            { text = L["Search your vendor visits for an item or a vendor, and fold visits away."],
                page = "history" },
            { text = L["Characters: forget a character you deleted, or merge one the game listed twice after renaming its realm."],
                page = "general", setting = "characters" },
            { text = L["Buy back something Pocket Goblin sold twice, and the vendor panel offers to keep it from then on."] },
        },
    },
    {
        version = "1.11.0",
        chat = L["a short tour of your bags and the vendor panel, and this news"],
        points = {
            { text = L["A short tour of your bags and the vendor panel for new players: replay it from the General page."],
                page = "general", setting = "tour" },
            { text = L["What's new: after an update, this card says what's new, with a dot on the pages and settings that changed."],
                page = "general", setting = "newsChat" },
        },
    },
    {
        version = "1.10.0",
        chat = L["Bagnon support"],
        points = {
            { text = L["Bagnon: the coin and other icons on your items, and the trash can and open button in its top row."],
                page = "bags" },
            { text = L["Make room shows on the loot window whenever your loot doesn't all fit, not only with full bags."],
                page = "bags", setting = "lootMakeRoom" },
        },
    },
}

-- Version numbers as { major, minor, patch }; "1.10.0" > "1.9.1".
local function Parse(version)
    local a, b, c = tostring(version):match("^(%d+)%.(%d+)%.?(%d*)")
    return { tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0 }
end

local function Newer(a, b)
    local x, y = Parse(a), Parse(b)
    for i = 1, 3 do
        if x[i] ~= y[i] then return x[i] > y[i] end
    end
    return false
end

-- The running version. From source ("dev") it's the newest entry, so the
-- news can be tried out before a release.
local function Current()
    if ns.VERSION and ns.VERSION:match("^%d") then return ns.VERSION end
    return ns.WHATS_NEW[1] and ns.WHATS_NEW[1].version or "0"
end

-- Entries newer than seen (and than the version Pocket Goblin was installed
-- with), up to the running one, newest first.
local function EntriesAfter(seen)
    local account = ns.account
    local current = Current()
    local list = {}
    for _, entry in ipairs(ns.WHATS_NEW) do
        if Newer(entry.version, seen or "0") and Newer(entry.version, account.newsBaseline or "0")
            and not Newer(entry.version, current) then
            list[#list + 1] = entry
        end
    end
    return list
end

-- At login: remember the version, and on the first login after an update
-- with news, say so in chat (a moment later, after the login messages).
function ns.InitNews()
    local account = ns.account
    local current = Current()
    account.newsPages = account.newsPages or {}
    if ns.freshInstall then
        account.newsBaseline = current
        account.newsLastRun = current
        return
    end
    local news = EntriesAfter(account.newsLastRun)
    account.newsLastRun = current
    -- Quiet too when the goblin's chat messages are off altogether.
    if #news > 0 and account.newsChat ~= false and ns.db.messages ~= "none" then
        C_Timer.After(8, function()
            ns.Print(L["new in %s: %s. Type /goblin to see."], news[1].version, news[1].chat)
        end)
    end
end

-- The entries the window's "What's new" card shows, newest first.
function ns.UnseenNews()
    if not ns.account then return {} end
    return EntriesAfter(ns.account.newsSeen)
end

-- "Got it": the card stays away until the next release with news.
function ns.DismissNews()
    ns.account.newsSeen = Current()
end

-- Whether a window page has news you haven't looked at yet.
function ns.PageIsNew(key)
    if not ns.account then return false end
    for _, entry in ipairs(EntriesAfter((ns.account.newsPages or {})[key])) do
        for _, point in ipairs(entry.points) do
            if point.page == key then return true end
        end
    end
    return false
end

function ns.MarkPageSeen(key)
    if not ns.account then return end
    ns.account.newsPages = ns.account.newsPages or {}
    ns.account.newsPages[key] = Current()
end

-- The chat line after an update (true by default).
function ns.SetNewsChat(value)
    ns.account.newsChat = value and true or false
end
