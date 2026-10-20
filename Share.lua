-- Sharing lists and profiles as text: the export string, reading it back,
-- and the import window. The text is "PG1:" + the data, packed and written
-- in letters and digits only (so it survives being pasted anywhere), + ":" +
-- a checksum that catches a text cut short or changed.

local ADDON_NAME, ns = ...
local L = ns.L

local PREFIX = "PG1:"
local FORMAT_VERSION = 1
local MAX_DEPTH = 6 -- profiles nest two deep; anything deeper isn't ours

------------------------------------------------------------------------
-- Packing data into a string and back
------------------------------------------------------------------------

-- Tables, strings, numbers and booleans as a compact string: T...E for a
-- table (keys and values in turn), S<length>:<text>, N<number>; and B1/B0.
local function Pack(value, out)
    local kind = type(value)
    if kind == "table" then
        out[#out + 1] = "T"
        for key, item in pairs(value) do
            local keyKind, itemKind = type(key), type(item)
            if (keyKind == "string" or keyKind == "number")
                and (itemKind == "table" or itemKind == "string" or itemKind == "number" or itemKind == "boolean") then
                Pack(key, out)
                Pack(item, out)
            end
        end
        out[#out + 1] = "E"
    elseif kind == "string" then
        out[#out + 1] = "S" .. #value .. ":" .. value
    elseif kind == "number" then
        if value ~= value or value == math.huge or value == -math.huge then value = 0 end -- not a real number
        out[#out + 1] = "N" .. tostring(value) .. ";"
    elseif kind == "boolean" then
        out[#out + 1] = value and "B1" or "B0"
    end
end

-- Reads one packed value at pos; returns it and the position after it, or
-- nil if the text isn't well-formed. Never runs anything from the text.
local function Unpack(text, pos, depth)
    local tag = text:sub(pos, pos)
    if tag == "T" then
        if depth >= MAX_DEPTH then return nil end
        local result = {}
        pos = pos + 1
        while text:sub(pos, pos) ~= "E" do
            if pos > #text then return nil end
            local key, item
            key, pos = Unpack(text, pos, depth + 1)
            if key == nil or type(key) == "table" or type(key) == "boolean" then return nil end
            item, pos = Unpack(text, pos, depth + 1)
            if item == nil then return nil end
            result[key] = item
        end
        return result, pos + 1
    elseif tag == "S" then
        local length, rest = text:match("^(%d+):()", pos + 1)
        length = tonumber(length)
        if not length or rest + length - 1 > #text then return nil end
        return text:sub(rest, rest + length - 1), rest + length
    elseif tag == "N" then
        local number, rest = text:match("^([-%d%.eE+]+);()", pos + 1)
        number = tonumber(number)
        if not number then return nil end
        return number, rest
    elseif tag == "B" then
        local bit = text:sub(pos + 1, pos + 1)
        if bit ~= "1" and bit ~= "0" then return nil end
        return bit == "1", pos + 2
    end
    return nil
end

------------------------------------------------------------------------
-- Base64 (letters, digits, + and /), and a checksum
------------------------------------------------------------------------

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local DIGIT = {}
for i = 1, #ALPHABET do DIGIT[ALPHABET:sub(i, i)] = i - 1 end

local function Encode(text)
    local out = {}
    for i = 1, #text, 3 do
        local a, b, c = text:byte(i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local chars = {}
        for j = 4, 1, -1 do
            local d = n % 64
            n = math.floor(n / 64)
            chars[j] = ALPHABET:sub(d + 1, d + 1)
        end
        if not b then chars[3] = "" end
        if not c then chars[4] = "" end
        out[#out + 1] = table.concat(chars)
    end
    return table.concat(out)
end

local function Decode(text)
    if #text % 4 == 1 then return nil end
    local out = {}
    for i = 1, #text, 4 do
        local group = text:sub(i, i + 3)
        local n, count = 0, #group
        for j = 1, 4 do
            local d = 0
            if j <= count then
                d = DIGIT[group:sub(j, j)]
                if not d then return nil end
            end
            n = n * 64 + d
        end
        local a, b, c = math.floor(n / 65536), math.floor(n / 256) % 256, n % 256
        out[#out + 1] = string.char(a)
        if count >= 3 then out[#out + 1] = string.char(b) end
        if count >= 4 then out[#out + 1] = string.char(c) end
    end
    return table.concat(out)
end

local function Checksum(text)
    local sum = 0
    for i = 1, #text do sum = (sum * 31 + text:byte(i)) % 2147483647 end
    return ("%08x"):format(sum)
end

------------------------------------------------------------------------
-- Export and import strings
------------------------------------------------------------------------

-- The share text for kind "lists" or "profile".
function ns.ExportString(kind)
    local out = {}
    Pack(ns.ExportData(kind), out)
    local body = Encode(table.concat(out))
    return PREFIX .. body .. ":" .. Checksum(body)
end

-- Reads share text. Returns the shared data ({ kind, name, from, data }), or
-- nil and a message saying what's wrong with the text.
function ns.ReadShareString(text)
    text = (text or ""):gsub("%s+", "") -- chat and websites can add spaces or line breaks
    if text == "" then return nil end
    if text:sub(1, 2) == "PG" and text:sub(1, #PREFIX) ~= PREFIX then
        return nil, L["This text is from a newer Pocket Goblin. Update yours to import it."]
    end
    local body, sum = text:match("^" .. PREFIX .. "([%w%+/]+):(%x+)$")
    if not body and text:sub(1, #PREFIX) == PREFIX then
        return nil, L["The text is incomplete or was changed. Copy all of it again."]
    elseif not body then
        return nil, L["That isn't Pocket Goblin text. It starts with PG1: and is one long line."]
    end
    if Checksum(body) ~= sum then
        return nil, L["The text is incomplete or was changed. Copy all of it again."]
    end
    local packed = Decode(body)
    local shared = packed and Unpack(packed, 1, 0)
    if type(shared) ~= "table" or type(shared.data) ~= "table"
        or (shared.kind ~= "lists" and shared.kind ~= "profile") then
        return nil, L["The text is incomplete or was changed. Copy all of it again."]
    end
    if type(shared.v) ~= "number" or shared.v > FORMAT_VERSION then
        return nil, L["This text is from a newer Pocket Goblin. Update yours to import it."]
    end
    shared.name = type(shared.name) == "string" and shared.name:sub(1, 32) or L["Shared"]
    shared.from = type(shared.from) == "string" and shared.from:sub(1, 32) or nil
    return shared
end

------------------------------------------------------------------------
-- Import window
------------------------------------------------------------------------

local WIDTH, HEIGHT = 560, 400
local window

-- "Graeslurk's Default profile", or just "the Default profile".
local function SourceName(shared)
    if shared.from then return (L["%s's %s profile"]):format(shared.from, shared.name) end
    return (L["the %s profile"]):format(shared.name)
end

-- A free profile name based on the shared one.
local function FreeName(name)
    local names = {}
    for _, existing in ipairs(ns.GetProfileNames()) do names[existing] = true end
    if not names[name] then return name end
    for i = 2, 99 do
        local candidate = ("%s %d"):format(name, i)
        if not names[candidate] then return candidate end
    end
    return ""
end

-- Reads the pasted text and shows what it holds, or what's wrong with it.
local function Update()
    local shared, problem = ns.ReadShareString(window.box:GetText())
    window.shared = shared
    local C = ns.UI.C
    window.nameRow:SetShown(shared ~= nil and shared.kind == "profile")
    if not shared then
        window.status:SetText(problem or L["Paste the text here, then check what it holds before importing."])
        local color = problem and C.danger or C.muted
        window.status:SetTextColor(color[1], color[2], color[3])
        window.import:Disable()
        return
    end
    local sell, keep, words, types = ns.CountSharedLists(shared.data)
    local counts = (L["%d to auto-sell, %d to keep, %d name words, %d item types"]):format(sell, keep, words, types)
    if shared.kind == "lists" then
        window.status:SetText((L["Lists from %s: %s. They're added to your lists; nothing of yours is removed."])
            :format(SourceName(shared), counts))
    else
        window.status:SetText((L["The whole of %s: settings and lists (%s). It becomes a new profile, and this "
            .. "character switches to it."]):format(SourceName(shared), counts))
        if window.lastProfile ~= shared then
            window.name:SetText(FreeName(shared.name))
        end
    end
    window.lastProfile = shared
    window.status:SetTextColor(C.text[1], C.text[2], C.text[3])
    window.import:Enable()
end

local function Import()
    local shared = window.shared
    if not shared then return end
    if shared.kind == "lists" then
        ns.ImportSharedLists(shared.data, SourceName(shared))
    elseif not ns.CreateSharedProfile(window.name:GetText(), shared.data) then
        ns.Print(L["Enter a name that isn't already used by a profile."])
        return
    end
    window:Hide()
end

local function CreateWindow()
    local UI = ns.UI
    local C = UI.C
    window = CreateFrame("Frame", "PocketGoblinImportWindow", UIParent, "BackdropTemplate")
    window:SetSize(WIDTH, HEIGHT)
    window:SetPoint("CENTER")
    window:SetFrameStrata("FULLSCREEN_DIALOG")
    window:SetToplevel(true)
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    window:SetBackdropColor(unpack(C.bg))
    window:SetBackdropBorderColor(unpack(C.windowBorder))
    window:Hide()
    UI.CloseOnEscape(window)

    local logo = UI.Icon(window, "emblem-mono", 24, C.gold)
    logo:SetPoint("TOPLEFT", 16, -14)
    local title = UI.Text(window, 15, C.text)
    title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
    title:SetText(L["Import lists or a profile"])

    local close = CreateFrame("Button", nil, window)
    close:SetSize(28, 28)
    close:SetPoint("TOPRIGHT", -10, -10)
    local closeIcon = UI.Icon(close, "icon-close", 14, C.muted)
    closeIcon:SetPoint("CENTER")
    close:SetScript("OnEnter", function() UI.SetColor(closeIcon, C.text) end)
    close:SetScript("OnLeave", function() UI.SetColor(closeIcon, C.muted) end)
    close:SetScript("OnClick", function() window:Hide() end)

    local hint = UI.Text(window, 12, C.muted)
    hint:SetPoint("TOPLEFT", 16, -46)
    hint:SetText(L["Paste a text someone exported from Pocket Goblin (Ctrl+V)."])

    -- The paste box, scrolling inside a card.
    local area = CreateFrame("Frame", nil, window)
    area:SetPoint("TOPLEFT", 12, -70)
    area:SetPoint("TOPRIGHT", -12, -70)
    area:SetHeight(150)
    UI.Rounded(area, "BACKGROUND", C.card)
    UI.Rounded(area, "BORDER", C.cardBorder, "rounded-border")
    local scroll = CreateFrame("ScrollFrame", nil, area)
    scroll:SetPoint("TOPLEFT", 12, -10)
    scroll:SetPoint("BOTTOMRIGHT", -12, 10)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - delta * 40)))
    end)
    local box = CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(true)
    box:SetMaxLetters(0)
    box:SetAutoFocus(false)
    box:SetWidth(WIDTH - 24 - 24)
    box:SetHeight(130)
    box:SetFontObject(ChatFontNormal)
    box:SetTextColor(C.text[1], C.text[2], C.text[3])
    box:SetScript("OnEscapePressed", function() window:Hide() end)
    box:SetScript("OnTextChanged", Update)
    scroll:SetScrollChild(box)
    -- Clicking anywhere in the card puts the cursor in the box.
    area:EnableMouse(true)
    area:SetScript("OnMouseDown", function() box:SetFocus() end)
    window.box = box

    window.status = UI.Text(window, 12, C.muted)
    window.status:SetPoint("TOPLEFT", area, "BOTTOMLEFT", 4, -12)
    window.status:SetPoint("RIGHT", -16, 0)
    window.status:SetJustifyH("LEFT")

    -- The new profile's name, for a whole profile.
    local nameRow = CreateFrame("Frame", nil, window)
    nameRow:SetPoint("BOTTOMLEFT", 16, 20)
    nameRow:SetSize(300, 32)
    local nameLabel = UI.Text(nameRow, 13, C.text)
    nameLabel:SetPoint("LEFT")
    nameLabel:SetText(L["New profile name"])
    window.name = UI.CreateTextInput(nameRow, 156, L["Profile name"])
    window.name:SetPoint("LEFT", nameLabel, "RIGHT", 10, 0)
    window.name:SetScript("OnEnterPressed", Import)
    window.nameRow = nameRow

    window.import = UI.CreateButton(window, L["Import"], 100, true)
    window.import:SetPoint("BOTTOMRIGHT", -16, 20)
    window.import:SetScript("OnClick", Import)
    local cancel = UI.CreateButton(window, L["Cancel"], 90)
    cancel:SetPoint("RIGHT", window.import, "LEFT", -8, 0)
    cancel:SetScript("OnClick", function() window:Hide() end)
end

-- Opens the import window, empty and ready for a paste.
function ns.ShowImportWindow()
    if not window then CreateWindow() end
    window.lastProfile = nil
    window:Show()
    window.box:SetText("")
    window.name:SetText("")
    Update()
    window.box:SetFocus()
end

-- Shows the share text for kind "lists" or "profile", selected for copying.
function ns.ShowExport(kind)
    local title = kind == "lists" and L["Export lists"] or L["Export profile"]
    ns.ShowCopyWindow(title, ns.ExportString(kind),
        L["Press Ctrl+C to copy it, then paste it where you want to share it, like a message or a website."])
end
