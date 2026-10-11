-- Pocket Goblin window: a dark, card-based settings window with a sidebar,
-- toggle switches and the list of flagged items.

local ADDON_NAME, ns = ...
local L = ns.L

local MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\"
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local QUESTION_MARK = 134400

-- Layout. The window has a fixed size, so widths are computed up front.
-- The window can be made taller and wider (not smaller than WIDTH, which
-- the list filters need); the widths below are where layouts start.
local WIDTH, HEIGHT = 840, 650
local SCREEN_MARGIN = 20 -- kept free around the window on small screens
local HEADER_HEIGHT = 72
local SIDEBAR_WIDTH = 210
local PAGE_WIDTH = WIDTH - SIDEBAR_WIDTH - 2
local SCROLL_WIDTH = PAGE_WIDTH - 16 -- leaves a gutter for the scrollbar
local CARD_WIDTH = SCROLL_WIDTH - 40
local ROW_WIDTH = CARD_WIDTH - 40
local ITEM_HEIGHT = 28

local C = {
    bg = { 0.047, 0.05, 0.058, 0.97 },
    sidebar = { 0.035, 0.037, 0.043, 1 },
    windowBorder = { 0.17, 0.17, 0.19, 1 },
    card = { 0.078, 0.081, 0.092, 1 },
    cardBorder = { 0.16, 0.165, 0.18, 1 },
    control = { 0.11, 0.114, 0.126, 1 },
    controlHover = { 0.15, 0.154, 0.168, 1 },
    controlBorder = { 0.24, 0.245, 0.265, 1 },
    gold = { 0.83, 0.65, 0.18, 1 },
    goldHover = { 0.92, 0.74, 0.26, 1 },
    goldDim = { 0.83, 0.65, 0.18, 0.13 },
    text = { 0.92, 0.92, 0.93, 1 },
    muted = { 0.53, 0.54, 0.58, 1 },
    dark = { 0.09, 0.07, 0.02, 1 },
    off = { 0.2, 0.205, 0.225, 1 },
    knobOff = { 0.78, 0.78, 0.82, 1 },
    white = { 1, 1, 1, 1 },
    danger = { 0.92, 0.32, 0.32, 1 },
}

-- Sidebar entries, top to bottom; { section = ... } entries are headings.
local PAGES = {
    { section = "LISTS" },
    { key = "list", title = L["Auto-sell list"], subtitle = L["Flagged items"], icon = "icon-list" },
    { key = "keep", title = L["Keep list"], subtitle = L["Kept items & quest gear"], icon = "icon-lock" },
    { key = "history", title = L["History"], subtitle = L["Sales & earnings"], icon = "icon-history" },
    { section = "SETTINGS" },
    { key = "general", title = L["General"], subtitle = L["Interface, chat & profiles"], icon = "icon-gear" },
    { key = "rules", title = L["Junk rules"], subtitle = L["What gets sold"], icon = "icon-filter" },
    { key = "vendor", title = L["Vendor"], subtitle = L["Selling & repairs"], icon = "icon-coin" },
    { key = "bags", title = L["Bags"], subtitle = L["Icons, destroy & space"], icon = "icon-bag" },
    { key = "about", title = L["About"], subtitle = L["How it works & commands"], icon = "icon-info" },
}
-- Old page keys that now live on another page: { page, keep list tab }.
local PAGE_ALIASES = { quest = { "keep", "quest" }, destroy = { "bags" }, profiles = { "general" } }
local NAV_HEIGHT, NAV_SPACING, SECTION_HEIGHT = 44, 46, 24

local window
local pages, navButtons, toggles = {}, {}, {}
local currentPage
local SelectPage -- defined with the window; pages use it for links
local refreshPending = false

-- List page widgets
local sellList, keepList, questList, junkText, sellButton
local keepTab, keepTabs, keepFrames = "keep", nil, {} -- Keep list page: "keep" or "quest" tab
local dependentRows = {} -- { regions, key }: rows dimmed while ns.db[key] is off

------------------------------------------------------------------------
-- Drawing helpers
------------------------------------------------------------------------

local function SetColor(texture, color)
    texture:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
end

local function Lerp(a, b, t)
    return a + (b - a) * t
end

-- A rounded rectangle that keeps its corners at any size (texture slicing).
-- file is "rounded" (filled) or "rounded-border" (1px outline).
local function Rounded(parent, layer, color, file)
    local texture = parent:CreateTexture(nil, layer or "BACKGROUND")
    texture:SetAllPoints()
    if texture.SetTextureSliceMargins then
        texture:SetTexture(MEDIA .. (file or "rounded"))
        texture:SetTextureSliceMargins(8, 8, 8, 8)
        texture:SetTextureSliceMode(Enum.UITextureSliceMode and Enum.UITextureSliceMode.Stretched or 0)
        SetColor(texture, color)
    elseif file == "rounded-border" then
        texture:Hide() -- no slicing support: skip outlines rather than draw a blob
    else
        texture:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    end
    return texture
end

local function Icon(parent, name, size, color, layer)
    local texture = parent:CreateTexture(nil, layer or "ARTWORK")
    texture:SetTexture(MEDIA .. name)
    texture:SetSize(size, size)
    SetColor(texture, color)
    return texture
end

local function Text(parent, size, color, layer)
    local text = parent:CreateFontString(nil, layer or "ARTWORK")
    text:SetFont(FONT, size, "")
    text:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    text:SetShadowColor(0, 0, 0, 0.6)
    text:SetShadowOffset(1, -1)
    text:SetJustifyH("LEFT")
    return text
end

-- Shared with the bag destroy button.
ns.UI = { C = C, SetColor = SetColor, Rounded = Rounded, Icon = Icon }

local function PlayToggleSound(on)
    if SOUNDKIT then
        PlaySound(on and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end
end

local function ShowTooltip(owner, title, body)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, 1, 1, 1)
    if body then GameTooltip:AddLine(body, nil, nil, nil, true) end
    GameTooltip:Show()
end

------------------------------------------------------------------------
-- Controls
------------------------------------------------------------------------

-- Pill-shaped on/off switch whose knob slides across.
local function CreateToggle(parent, get, set)
    local toggle = CreateFrame("Button", nil, parent)
    toggle:SetSize(48, 24)

    local track = toggle:CreateTexture(nil, "ARTWORK")
    track:SetTexture(MEDIA .. "pill")
    track:SetAllPoints()

    local knob = toggle:CreateTexture(nil, "OVERLAY")
    knob:SetTexture(MEDIA .. "circle")
    knob:SetSize(18, 18)

    local pos = get() and 1 or 0
    local hovered = false

    local function paint()
        knob:SetPoint("LEFT", 3 + pos * 24, 0)
        local on = hovered and C.goldHover or C.gold
        local off = hovered and C.controlBorder or C.off
        track:SetVertexColor(Lerp(off[1], on[1], pos), Lerp(off[2], on[2], pos), Lerp(off[3], on[3], pos))
        knob:SetVertexColor(Lerp(C.knobOff[1], 1, pos), Lerp(C.knobOff[2], 1, pos), Lerp(C.knobOff[3], 1, pos))
    end

    local function animate(self, elapsed)
        local target = get() and 1 or 0
        local step = elapsed * 7
        if math.abs(target - pos) <= step then
            pos = target
            self:SetScript("OnUpdate", nil)
        else
            pos = pos + (target > pos and step or -step)
        end
        paint()
    end

    -- Slides to the current value, or jumps there when not animating.
    function toggle:Update(instant)
        if instant then
            if not self:GetScript("OnUpdate") then
                pos = get() and 1 or 0
                paint()
            end
        else
            self:SetScript("OnUpdate", animate)
        end
    end

    toggle:SetScript("OnClick", function(self)
        local value = not get()
        set(value)
        PlayToggleSound(value)
        self:Update()
    end)
    toggle:SetScript("OnEnter", function() hovered = true; paint() end)
    toggle:SetScript("OnLeave", function() hovered = false; paint() end)

    paint()
    toggles[#toggles + 1] = toggle
    return toggle
end

-- Factory for AddRow: a toggle bound to a saved setting.
local function SettingToggle(key, onChange)
    return function(parent)
        return CreateToggle(parent,
            function() return ns.db[key] end,
            function(value)
                ns.db[key] = value
                if onChange then onChange() end
            end)
    end
end

-- Thin track with a gold fill, a round knob and the value on the right.
-- get() returns the current value; format may be nil for no value label;
-- width is the track width.
local function CreateSlider(parent, minValue, maxValue, step, get, format, onChange, width)
    width = width or 168
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(width + (format and 52 or 0), 24)

    local slider = CreateFrame("Slider", nil, holder)
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(width, 24)
    slider:SetPoint("LEFT")
    slider:SetMinMaxValues(minValue, maxValue)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetHitRectInsets(0, 0, -4, -4)

    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetColorTexture(C.off[1], C.off[2], C.off[3], 1)
    track:SetHeight(4)
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")

    local fill = slider:CreateTexture(nil, "ARTWORK")
    fill:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    fill:SetHeight(4)
    fill:SetPoint("LEFT")

    slider:SetThumbTexture(MEDIA .. "circle")
    local thumb = slider:GetThumbTexture()
    thumb:SetSize(16, 16)
    SetColor(thumb, C.white)

    local label
    if format then
        label = Text(holder, 13, C.text)
        label:SetPoint("RIGHT")
        label:SetJustifyH("RIGHT")
    end

    local initializing = true
    slider:SetScript("OnValueChanged", function(_, newValue)
        local fraction = (newValue - minValue) / (maxValue - minValue)
        fill:SetWidth(math.max(1, 8 + fraction * (slider:GetWidth() - 16)))
        if label then label:SetText(format(newValue)) end
        if not initializing then onChange(newValue) end
    end)
    slider:EnableMouseWheel(true)
    slider:SetScript("OnMouseWheel", function(self, delta)
        if self:IsEnabled() then self:SetValue(self:GetValue() + delta * step) end
    end)
    slider:SetValue(get())
    initializing = false

    -- Moves the knob without calling onChange.
    function holder:SetValueSilently(newValue)
        initializing = true
        slider:SetValue(newValue)
        initializing = false
    end

    function holder:Update()
        self:SetValueSilently(get())
    end
    toggles[#toggles + 1] = holder -- refreshed along with the toggles

    return holder
end

-- "1g 25s 50c" style text for an amount of copper.
local function FormatMoneyText(copper)
    local gold, silver, rest = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if gold > 0 then parts[#parts + 1] = gold .. "g" end
    if silver > 0 then parts[#parts + 1] = silver .. "s" end
    if rest > 0 or #parts == 0 then parts[#parts + 1] = rest .. "c" end
    return table.concat(parts, " ")
end

-- Parses "25s50c", "1g 2s", "75c" or a plain number (copper). Returns nil
-- if the text isn't a valid amount.
local function ParseMoneyText(text)
    text = text:lower():gsub("%s+", "")
    if text:match("^%d+$") then return tonumber(text) end
    local total = 0
    local rest = text:gsub("(%d+)([gsc])", function(amount, unit)
        total = total + tonumber(amount) * (unit == "g" and 10000 or unit == "s" and 100 or 1)
        return ""
    end)
    if text == "" or rest ~= "" then return nil end
    return total
end

-- A slider over preset amounts plus a text box for typing any amount. The
-- slider tops out at the last preset; typed amounts can go higher.
local function CreateMoneyInput(parent, presets, get, set)
    local function nearestIndex(copper)
        local best = 1
        for i, preset in ipairs(presets) do
            if math.abs(preset - copper) < math.abs(presets[best] - copper) then best = i end
        end
        return best
    end

    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(236, 30)

    local box = CreateFrame("EditBox", nil, holder)
    box:SetSize(96, 30)
    box:SetPoint("RIGHT")
    box:SetAutoFocus(false)
    box:SetFont(FONT, 13, "")
    box:SetTextColor(C.text[1], C.text[2], C.text[3])
    box:SetTextInsets(10, 10, 0, 0)
    box:SetMaxLetters(16)
    Rounded(box, "BACKGROUND", C.control)
    local border = Rounded(box, "BORDER", C.controlBorder, "rounded-border")
    box:SetText(FormatMoneyText(get()))

    local slider = CreateSlider(holder, 1, #presets, 1,
        function() return nearestIndex(math.min(get(), presets[#presets])) end, nil, function(index)
        set(presets[math.floor(index + 0.5)])
        box:SetText(FormatMoneyText(get()))
    end, 124)
    slider:SetPoint("LEFT")

    local function commit()
        local copper = ParseMoneyText(box:GetText())
        if copper then
            set(copper)
            slider:SetValueSilently(nearestIndex(math.min(copper, presets[#presets])))
        end
        box:SetText(FormatMoneyText(get())) -- tidy up, or undo invalid input
    end
    box:SetScript("OnEnterPressed", box.ClearFocus) -- focus loss commits
    box:SetScript("OnEscapePressed", function(self)
        self:SetText(FormatMoneyText(get()))
        self:ClearFocus()
    end)
    box:SetScript("OnEditFocusGained", function(self)
        SetColor(border, C.gold)
        self:HighlightText()
    end)
    box:SetScript("OnEditFocusLost", function(self)
        SetColor(border, C.controlBorder)
        self:HighlightText(0, 0)
        commit()
    end)
    box:SetScript("OnEnter", function(self)
        ShowTooltip(self, L["Value limit"], L["Type an amount like 25s50c, 1g 20s or 75c, then press Enter."])
    end)
    box:SetScript("OnLeave", GameTooltip_Hide)

    function holder:Update()
        if not box:HasFocus() then box:SetText(FormatMoneyText(get())) end
    end
    toggles[#toggles + 1] = holder

    return holder
end

local CORNERS = {
    { key = "TOPLEFT", label = L["Top left"] },
    { key = "TOPRIGHT", label = L["Top right"] },
    { key = "BOTTOMLEFT", label = L["Bottom left"] },
    { key = "BOTTOMRIGHT", label = L["Bottom right"] },
}

-- A small item slot with a dot in each corner; click a dot to pick that
-- corner. The chosen corner is gold and named on the left.
local function CreateCornerPicker(parent, get, set)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(160, 48)

    local slot = CreateFrame("Frame", nil, holder)
    slot:SetSize(48, 48)
    slot:SetPoint("RIGHT")
    Rounded(slot, "BACKGROUND", C.control)
    Rounded(slot, "BORDER", C.controlBorder, "rounded-border")
    local bag = Icon(slot, "icon-bag", 18, { 1, 1, 1, 0.12 })
    bag:SetPoint("CENTER")

    local label = Text(holder, 13, C.text)
    label:SetPoint("RIGHT", slot, "LEFT", -12, 0)
    label:SetJustifyH("RIGHT")

    local dots = {}
    function holder:Update()
        local current = get()
        for _, corner in ipairs(CORNERS) do
            local dot = dots[corner.key]
            local selected = corner.key == current
            SetColor(dot.texture, selected and C.gold or dot.hovered and C.muted or C.off)
            if selected then label:SetText(corner.label) end
        end
    end

    for _, corner in ipairs(CORNERS) do
        local dot = CreateFrame("Button", nil, slot)
        dot:SetSize(18, 18)
        dot:SetPoint(corner.key, corner.key:find("LEFT") and 3 or -3, corner.key:find("TOP") and -3 or 3)
        dot.texture = Icon(dot, "circle", 11, C.off)
        dot.texture:SetPoint("CENTER")
        dot:SetScript("OnClick", function()
            set(corner.key)
            PlayToggleSound(true)
            holder:Update()
        end)
        dot:SetScript("OnEnter", function(self)
            self.hovered = true
            holder:Update()
            ShowTooltip(self, corner.label)
        end)
        dot:SetScript("OnLeave", function(self)
            self.hovered = false
            holder:Update()
            GameTooltip_Hide()
        end)
        dots[corner.key] = dot
    end

    holder:Update()
    toggles[#toggles + 1] = holder -- refreshed along with the toggles
    return holder
end

-- A row of options where exactly one is chosen (gold), like tabs.
-- options: { { key, label }, ... }; get() returns the chosen key.
local function CreateSegmented(parent, options, get, set)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetHeight(30)
    Rounded(holder, "BACKGROUND", C.control)
    Rounded(holder, "BORDER", C.controlBorder, "rounded-border")

    local segments = {}
    function holder:Update()
        local current = get()
        for _, segment in ipairs(segments) do
            local selected = segment.key == current
            segment.bg:SetShown(selected or segment.hovered)
            SetColor(segment.bg, selected and C.gold or C.controlHover)
            local color = selected and C.dark or C.text
            segment.text:SetTextColor(color[1], color[2], color[3])
            segment.text:SetShadowOffset(selected and 0 or 1, selected and 0 or -1)
        end
    end

    local x = 3
    for _, option in ipairs(options) do
        local segment = CreateFrame("Button", nil, holder)
        segment.key = option[1]
        segment:SetHeight(24)
        segment:SetPoint("LEFT", x, 0)
        segment.bg = Rounded(segment, "BACKGROUND", C.gold)
        segment.text = Text(segment, 12, C.text)
        segment.text:SetPoint("CENTER")
        segment.text:SetJustifyH("CENTER")
        segment.text:SetText(option[2])
        segment:SetWidth(math.max(64, segment.text:GetStringWidth() + 24))
        segment:SetScript("OnClick", function(self)
            if get() == self.key then return end
            PlayToggleSound(true)
            set(self.key)
            holder:Update()
        end)
        segment:SetScript("OnEnter", function(self) self.hovered = true; holder:Update() end)
        segment:SetScript("OnLeave", function(self) self.hovered = false; holder:Update() end)
        segments[#segments + 1] = segment
        x = x + segment:GetWidth() + 2
    end
    holder:SetWidth(x + 1)

    holder:Update()
    toggles[#toggles + 1] = holder -- follows profile changes
    return holder
end

-- Filled button styles: { background, hovered background, text }.
local BUTTON_STYLES = {
    primary = { C.gold, C.goldHover, C.dark },
    danger = { C.danger, { 1, 0.45, 0.45, 1 }, C.white },
}

-- Rounded button. style: nil (dark outline), true or "primary" (gold), or
-- "danger" (red).
local function CreateButton(parent, label, width, style)
    local filled = BUTTON_STYLES[style == true and "primary" or style]
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, 32)

    local bg = Rounded(button, "BACKGROUND", filled and filled[1] or C.control)
    local border = Rounded(button, "BORDER", filled and filled[1] or C.controlBorder, "rounded-border")
    local text = Text(button, 13, filled and filled[3] or C.text)
    text:SetPoint("CENTER")
    text:SetJustifyH("CENTER")
    text:SetText(label)
    if filled then text:SetShadowOffset(0, 0) end
    button.label = text

    local hovered = false
    local function paint()
        if not button:IsEnabled() then
            SetColor(bg, C.control)
            SetColor(border, C.cardBorder)
            text:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
        elseif filled then
            SetColor(bg, hovered and filled[2] or filled[1])
            SetColor(border, hovered and filled[2] or filled[1])
            text:SetTextColor(filled[3][1], filled[3][2], filled[3][3])
        else
            SetColor(bg, hovered and C.controlHover or C.control)
            SetColor(border, C.controlBorder)
            text:SetTextColor(C.text[1], C.text[2], C.text[3])
        end
    end
    button:SetScript("OnEnable", paint)
    button:SetScript("OnDisable", paint)
    button:HookScript("OnEnter", function() hovered = true; paint() end)
    button:HookScript("OnLeave", function() hovered = false; paint() end)
    button:SetMotionScriptsWhileDisabled(true)
    paint()
    return button
end

ns.UI.Text = Text
ns.UI.CreateButton = CreateButton
ns.UI.CreateToggle = CreateToggle

-- Button that opens a menu of choices. getLabel() gives the button text;
-- buildMenu(root) fills the menu (MenuUtil).
local function CreateDropdown(parent, width, getLabel, buildMenu)
    local dropdown = CreateFrame("Button", nil, parent)
    dropdown:SetSize(width, 26)
    local bg = Rounded(dropdown, "BACKGROUND", C.control)
    Rounded(dropdown, "BORDER", C.controlBorder, "rounded-border")
    local text = Text(dropdown, 12, C.text)
    text:SetPoint("LEFT", 10, 0)
    text:SetPoint("RIGHT", -26, 0)
    text:SetWordWrap(false)
    local chevron = Icon(dropdown, "icon-chevron", 14, C.muted)
    chevron:SetPoint("RIGHT", -8, 0)

    function dropdown:UpdateLabel()
        text:SetText(getLabel())
    end
    dropdown.Update = dropdown.UpdateLabel
    dropdown:SetScript("OnClick", function(self)
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(self, function(_, root) buildMenu(root) end)
        end
    end)
    dropdown:SetScript("OnEnter", function() SetColor(bg, C.controlHover) end)
    dropdown:SetScript("OnLeave", function() SetColor(bg, C.control) end)
    dropdown:UpdateLabel()
    toggles[#toggles + 1] = dropdown -- label follows profile changes
    return dropdown
end

-- Single-line text box with a placeholder.
local function CreateTextInput(parent, width, placeholderText)
    local box = CreateFrame("EditBox", nil, parent)
    box:SetSize(width, 28)
    box:SetAutoFocus(false)
    box:SetFont(FONT, 13, "")
    box:SetTextColor(C.text[1], C.text[2], C.text[3])
    box:SetTextInsets(10, 10, 0, 0)
    box:SetMaxLetters(32)
    Rounded(box, "BACKGROUND", C.control)
    local border = Rounded(box, "BORDER", C.controlBorder, "rounded-border")
    local placeholder = Text(box, 13, C.muted)
    placeholder:SetPoint("LEFT", 10, 0)
    placeholder:SetText(placeholderText)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    box:SetScript("OnEditFocusGained", function() SetColor(border, C.gold) end)
    box:SetScript("OnEditFocusLost", function() SetColor(border, C.controlBorder) end)
    box:SetScript("OnTextChanged", function(self) placeholder:SetShown(self:GetText() == "") end)
    return box
end

-- Button for destructive actions: the first click asks "Click to confirm",
-- a second click within a few seconds runs onConfirm.
local function CreateConfirmButton(parent, label, width, style, onConfirm)
    local button = CreateButton(parent, label, width, style)
    local armed = false
    local function disarm()
        armed = false
        button.label:SetText(label)
    end
    button:SetScript("OnClick", function()
        if armed then
            disarm()
            onConfirm()
        else
            armed = true
            button.label:SetText(L["Confirm?"])
            C_Timer.After(3, function() if armed then disarm() end end)
        end
    end)
    return button
end

-- Small rounded label, e.g. the version number or an item count.
local function CreateBadge(parent, color, background)
    local badge = CreateFrame("Frame", nil, parent)
    badge:SetHeight(20)
    Rounded(badge, "BACKGROUND", background)
    badge.text = Text(badge, 11, color)
    badge.text:SetPoint("CENTER")
    badge.text:SetShadowOffset(0, 0)
    function badge:SetText(text)
        self.text:SetText(text)
        self:SetWidth(self.text:GetStringWidth() + 18)
    end
    return badge
end

-- Scroll frame with a slim gold scrollbar on its right.
local function CreateScrollArea(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(_, width) content:SetWidth(width) end)

    local bar = CreateFrame("Frame", nil, parent)
    bar:SetWidth(4)
    bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, -4)
    bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 6, 4)
    local barTrack = bar:CreateTexture(nil, "BACKGROUND")
    barTrack:SetAllPoints()
    barTrack:SetColorTexture(1, 1, 1, 0.04)

    local thumb = CreateFrame("Frame", nil, bar)
    thumb:SetWidth(4)
    thumb:EnableMouse(true)
    local thumbTexture = thumb:CreateTexture(nil, "ARTWORK")
    thumbTexture:SetAllPoints()
    thumbTexture:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.75)

    local function update()
        local range = scroll:GetVerticalScrollRange()
        if range <= 0 then
            bar:Hide()
            scroll:SetVerticalScroll(0)
            return
        end
        bar:Show()
        local height = bar:GetHeight()
        local thumbHeight = math.max(24, height * height / (height + range))
        thumb:SetHeight(thumbHeight)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", bar, "TOP", 0, -(scroll:GetVerticalScroll() / range) * (height - thumbHeight))
    end

    local function scrollTo(value)
        local range = scroll:GetVerticalScrollRange()
        scroll:SetVerticalScroll(math.max(0, math.min(range, value)))
        update()
    end

    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        scrollTo(self:GetVerticalScroll() - delta * 48)
    end)
    scroll:SetScript("OnScrollRangeChanged", function(self)
        scrollTo(self:GetVerticalScroll())
    end)

    -- Drag the thumb.
    thumb:SetScript("OnMouseDown", function(self)
        local _, startY = GetCursorPosition()
        local startScroll = scroll:GetVerticalScroll()
        self:SetScript("OnUpdate", function()
            local _, y = GetCursorPosition()
            local scale = bar:GetEffectiveScale()
            local range = scroll:GetVerticalScrollRange()
            local travel = bar:GetHeight() - thumb:GetHeight()
            if travel > 0 then
                scrollTo(startScroll + (startY - y) / scale / travel * range)
            end
        end)
    end)
    thumb:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)

    scroll.UpdateScrollBar = update
    return scroll, content
end

------------------------------------------------------------------------
-- Cards (settings sections)
------------------------------------------------------------------------

-- A rounded card with an uppercase title and a gold accent bar. Rows are
-- added with AddRow; call FinishCard once all rows are added.
local function CreateCard(parent, title)
    local card = CreateFrame("Frame", nil, parent)
    card:SetWidth(CARD_WIDTH)
    Rounded(card, "BACKGROUND", C.card)
    Rounded(card, "BORDER", C.cardBorder, "rounded-border")

    local bar = card:CreateTexture(nil, "ARTWORK")
    bar:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    bar:SetSize(3, 14)
    bar:SetPoint("TOPLEFT", 20, -22)

    local label = Text(card, 13, C.text)
    label:SetPoint("LEFT", bar, "RIGHT", 10, 0)
    label:SetText(title:upper())

    card.rows = {}
    return card
end

-- A row with a title, an optional description and an optional control on
-- the right. makeControl(card) creates the control. Returns the regions so
-- callers can dim them. LayoutCard positions the row.
local function AddRow(card, title, description, makeControl)
    local control = makeControl and makeControl(card)

    local titleText = Text(card, 14, C.text)
    titleText:SetText(title)

    local descText
    if description then
        descText = Text(card, 12, C.muted)
        descText:SetText(description)
        descText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -4)
    end

    card.rows[#card.rows + 1] = { title = titleText, desc = descText, control = control }
    return { titleText, descText, control }
end

-- Stacks a card's rows for the given card width (text wraps to fit) and
-- sizes the card to them.
local function LayoutCard(card, width)
    card:SetWidth(width)
    local y = -56
    for _, row in ipairs(card.rows) do
        local control = row.control
        local textWidth = width - 40 - (control and control:GetWidth() + 24 or 0)
        row.title:SetWidth(textWidth)
        local textHeight = row.title:GetStringHeight()
        if row.desc then
            row.desc:SetWidth(textWidth)
            textHeight = textHeight + 4 + row.desc:GetStringHeight()
        end

        local rowHeight = math.max(textHeight, control and control:GetHeight() or 0)
        row.title:ClearAllPoints()
        row.title:SetPoint("TOPLEFT", 20, y - (rowHeight - textHeight) / 2)
        if control then
            control:ClearAllPoints()
            control:SetPoint("RIGHT", card, "TOPRIGHT", -20, y - rowHeight / 2)
        end
        y = y - rowHeight - 20
    end
    card:SetHeight(-y)
end

local function FinishCard(card)
    LayoutCard(card, CARD_WIDTH)
end

-- Stacks cards in a scrollable page, and lays them out again when the
-- window is resized.
local function CreateCardPage(page, build)
    local scroll, content = CreateScrollArea(page)
    scroll:SetPoint("TOPLEFT", 0, -2)
    scroll:SetPoint("BOTTOMRIGHT", -16, 2)
    content:SetWidth(SCROLL_WIDTH)

    local cards = {}
    local function stack(width)
        local y = -20
        for _, card in ipairs(cards) do
            if width then LayoutCard(card, width - 40) end
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", 20, y)
            y = y - card:GetHeight() - 16
        end
        content:SetHeight(-y + 4)
    end

    local function addCard(title)
        local card = CreateCard(content, title)
        cards[#cards + 1] = card
        return card, function() FinishCard(card) end
    end
    build(addCard)
    stack()
    scroll:HookScript("OnSizeChanged", function(_, width)
        if width > 0 then stack(width) end
    end)
    -- The window may have been resized while this page was hidden.
    scroll:HookScript("OnShow", function(self)
        if self:GetWidth() > 0 then stack(self:GetWidth()) end
    end)
end

------------------------------------------------------------------------
-- Item lists (auto-sell list and quest gear)
------------------------------------------------------------------------

local QUALITY_FILTERS = { 1, 2, 3, 4 } -- Common, Uncommon, Rare, Epic
local QUALITY_NAMES = { L["Common"], L["Uncommon"], L["Rare"], L["Epic"] }

-- Skill line IDs used by quest requirements.
local PROFESSIONS = {
    [129] = L["First Aid"], [164] = L["Blacksmithing"], [165] = L["Leatherworking"], [171] = L["Alchemy"],
    [182] = L["Herbalism"], [185] = L["Cooking"], [186] = L["Mining"], [197] = L["Tailoring"],
    [202] = L["Engineering"], [333] = L["Enchanting"], [356] = L["Fishing"], [393] = L["Skinning"],
}

local function QualityColor(quality)
    local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    return color and { color.r, color.g, color.b, 1 } or C.muted
end

local function ItemClassName(classID)
    local getInfo = C_Item.GetItemClassInfo or GetItemClassInfo
    return getInfo and getInfo(classID) or (L["Type "] .. classID)
end

local function ItemSubClassName(classID, subClassID)
    local getInfo = C_Item.GetItemSubClassInfo or GetItemSubClassInfo
    return getInfo and getInfo(classID, subClassID) or (L["Subtype "] .. subClassID)
end

local function SlotName(equipLoc)
    return _G[equipLoc] or equipLoc
end

local function ProfessionName(skillID)
    if skillID == 0 then return L["No profession needed"] end
    return PROFESSIONS[skillID] or (L["Skill "] .. skillID)
end

-- Item info for a list row; fallbackName is used until the game has the
-- item cached.
local function ItemEntry(itemID, fallbackName)
    local name, link, quality, _, _, _, _, _, _, icon, sellPrice = C_Item.GetItemInfo(itemID)
    if not name then C_Item.RequestLoadItemDataByID(itemID) end
    local _, _, _, equipLoc, instantIcon, classID, subClassID = C_Item.GetItemInfoInstant(itemID)
    return {
        itemID = itemID,
        name = name or fallbackName or (L["Loading item "] .. itemID .. "..."),
        link = link,
        quality = quality,
        icon = icon or instantIcon,
        sellPrice = sellPrice,
        classID = classID,
        subClassID = subClassID,
        equipLoc = equipLoc ~= "" and equipLoc or nil,
    }
end

-- Flagged items of white quality and better. Grey items sell anyway.
local function GetFlaggedItems()
    local inBags = ns.GetBagItemIDs()
    local list = {}
    for itemID, flag in pairs(ns.db.items) do
        if flag == true then
            local item = ItemEntry(itemID)
            if item.quality ~= ns.POOR then
                item.addedAt = ns.db.addedAt[itemID] or 0
                item.inBags = inBags[itemID] or false
                item.detail = item.sellPrice and item.sellPrice > 0 and GetMoneyString(item.sellPrice, true)
                list[#list + 1] = item
            end
        end
    end
    return list
end

-- Items on the keep list (any quality).
local function GetKeptItems()
    local inBags = ns.GetBagItemIDs()
    local list = {}
    for itemID, flag in pairs(ns.db.items) do
        if flag == false then
            local item = ItemEntry(itemID)
            item.addedAt = ns.db.addedAt[itemID] or 0
            item.inBags = inBags[itemID] or false
            item.detail = item.sellPrice and item.sellPrice > 0 and GetMoneyString(item.sellPrice, true)
            list[#list + 1] = item
        end
    end
    return list
end

local function GetQuestGearItems()
    local list = {}
    for itemID, info in pairs(ns.QUEST_GEAR) do
        local item = ItemEntry(itemID, info[1])
        item.detail = info[2]
        item.minLevel, item.maxLevel, item.minRequired, item.skill = info[3], info[4], info[5], info[6]
        item.flagged = ns.db.items[itemID] == true
        item.badge = item.flagged and L["ON LIST"]
        list[#list + 1] = item
    end
    return list
end

-- Puts the item on the cursor (dragged from the bags) on the auto-sell
-- list, or on the keep list if keep is true.
local function AcceptCursorItem(keep)
    local kind, itemID = GetCursorInfo()
    if kind ~= "item" or not itemID then return end
    ClearCursor()
    if keep then
        ns.SetFlag(itemID, false)
    elseif select(11, C_Item.GetItemInfo(itemID)) == 0 then
        ns.Print(L["That item cannot be sold to vendors."])
    else
        ns.SetFlag(itemID, true)
    end
end

-- One line per item: icon, name, then detail text, badge and (if the list
-- has onRemove) a remove button from the right.
local function CreateItemRow(list, index)
    local row = CreateFrame("Button", nil, list.content)
    row:SetHeight(ITEM_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ITEM_HEIGHT)
    row:SetPoint("TOPRIGHT", 0, -(index - 1) * ITEM_HEIGHT)

    local hover = Rounded(row, "BACKGROUND", { 1, 1, 1, 0.045 })
    hover:Hide()

    row.border = row:CreateTexture(nil, "ARTWORK", nil, 1)
    row.border:SetSize(22, 22)
    row.border:SetPoint("LEFT", 8, 0)

    row.icon = row:CreateTexture(nil, "ARTWORK", nil, 2)
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("CENTER", row.border)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Rightmost element; details and badges line up to its left.
    row.edge = CreateFrame("Button", nil, row)
    row.edge:SetSize(list.onRemove and 22 or 1, 22)
    row.edge:SetPoint("RIGHT", -6, 0)
    if list.onRemove then
        local removeIcon = Icon(row.edge, "icon-close", 12, C.muted)
        removeIcon:SetPoint("CENTER")
        row.edge:SetScript("OnClick", function() list.onRemove(row.itemID) end)
        row.edge:SetScript("OnEnter", function(self)
            SetColor(removeIcon, C.danger)
            hover:Show()
            ShowTooltip(self, list.removeText)
        end)
        row.edge:SetScript("OnLeave", function()
            SetColor(removeIcon, C.muted)
            hover:Hide()
            GameTooltip_Hide()
        end)
    end

    row.badge = CreateBadge(row, C.gold, C.goldDim)
    row.badge:SetHeight(16)
    row.badge.text:SetFont(FONT, 10, "")
    row.badge:SetPoint("RIGHT", row.edge, "LEFT", -6, 0)

    row.detail = Text(row, 12, C.muted)
    row.detail:SetJustifyH("RIGHT")
    row.detail:SetWordWrap(false)

    row.name = Text(row, 13, C.text)
    row.name:SetPoint("LEFT", row.border, "RIGHT", 8, 0)
    row.name:SetPoint("RIGHT", row.detail, "LEFT", -10, 0)
    row.name:SetWordWrap(false)

    row:SetScript("OnEnter", function(self)
        hover:Show()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(self.itemID)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function()
        hover:Hide()
        GameTooltip_Hide()
    end)
    row:SetScript("OnClick", function(self)
        -- Shift-click links the item in chat, Ctrl-click previews it.
        if self.link and IsModifiedClick() then
            HandleModifiedItemClick(self.link)
        end
    end)
    return row
end

local MAX_DETAIL_WIDTH = 240

local function UpdateItemRow(row, item)
    row.itemID = item.itemID
    row.link = item.link
    row.icon:SetTexture(item.icon or QUESTION_MARK)
    row.name:SetText(item.name)

    row.badge:SetShown(item.badge and true or false)
    if item.badge then row.badge:SetText(item.badge) end

    row.detail:ClearAllPoints()
    row.detail:SetPoint("RIGHT", item.badge and row.badge or row.edge, "LEFT", -8, 0)
    row.detail:SetWidth(0) -- size to the text, up to a limit
    row.detail:SetText(item.detail or "")
    if row.detail:GetStringWidth() > MAX_DETAIL_WIDTH then row.detail:SetWidth(MAX_DETAIL_WIDTH) end

    local color = item.quality and QualityColor(item.quality) or C.muted
    row.name:SetTextColor(color[1], color[2], color[3])
    row.border:SetColorTexture(color[1], color[2], color[3], 0.9)
end

-- Small on/off pill with a coloured dot, used for the quality filters.
-- Call chip:SetActive to change it without onToggle.
local function CreateChip(parent, label, dotColor, onToggle)
    local chip = CreateFrame("Button", nil, parent)
    chip:SetHeight(24)
    local bg = Rounded(chip, "BACKGROUND", C.control)
    local border = Rounded(chip, "BORDER", C.controlBorder, "rounded-border")
    local dot = Icon(chip, "circle", 8, dotColor)
    dot:SetPoint("LEFT", 9, 0)
    local text = Text(chip, 11, C.muted)
    text:SetPoint("LEFT", dot, "RIGHT", 5, 0)
    text:SetText(label)
    chip:SetWidth(text:GetStringWidth() + 31)

    chip.active = false
    local hovered = false
    local function paint()
        SetColor(bg, chip.active and C.goldDim or hovered and C.controlHover or C.control)
        SetColor(border, chip.active and C.gold or C.controlBorder)
        local color = chip.active and C.text or C.muted
        text:SetTextColor(color[1], color[2], color[3])
        dot:SetAlpha(chip.active and 1 or 0.6)
    end
    function chip:SetActive(active)
        self.active = active and true or false
        paint()
    end
    chip:SetScript("OnClick", function()
        chip.active = not chip.active
        PlayToggleSound(chip.active)
        paint()
        onToggle(chip.active)
    end)
    chip:SetScript("OnEnter", function() hovered = true; paint() end)
    chip:SetScript("OnLeave", function() hovered = false; paint() end)
    paint()
    return chip
end

local function CreateSearchBox(parent, onChange)
    local search = CreateFrame("EditBox", nil, parent)
    search:SetSize(200, 30)
    search:SetAutoFocus(false)
    search:SetFont(FONT, 13, "")
    search:SetTextColor(C.text[1], C.text[2], C.text[3])
    search:SetTextInsets(30, 10, 0, 0)
    Rounded(search, "BACKGROUND", C.control)
    local border = Rounded(search, "BORDER", C.controlBorder, "rounded-border")
    local icon = Icon(search, "icon-search", 14, C.muted)
    icon:SetPoint("LEFT", 10, 0)
    local placeholder = Text(search, 13, C.muted)
    placeholder:SetPoint("LEFT", 30, 0)
    placeholder:SetText(L["Search items"])
    search:SetScript("OnEscapePressed", search.ClearFocus)
    search:SetScript("OnEnterPressed", search.ClearFocus)
    search:SetScript("OnEditFocusGained", function() SetColor(border, C.gold) end)
    search:SetScript("OnEditFocusLost", function() SetColor(border, C.controlBorder) end)
    search:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        placeholder:SetShown(text == "")
        onChange(text:lower())
    end)
    return search
end

-- Sorts a list of keys by their label.
local function SortedKeys(counts, label)
    local keys = {}
    for key in pairs(counts) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return label(a) < label(b) end)
    return keys
end

-- Radio option in a filter menu; set() runs before the list refreshes.
local function FilterRadio(menu, list, label, isSelected, set)
    menu:CreateRadio(label, isSelected, function()
        set()
        list:FiltersChanged()
    end)
end

local function FilterCheckbox(menu, list, label, filters, key)
    menu:CreateCheckbox(label, function() return filters[key] end, function()
        filters[key] = not filters[key]
        list:FiltersChanged()
    end)
end

-- How each list filters, sorts and builds its filter menu. filters is the
-- list's table in the profile (ns.db.filters.sell / .quest).
-- Filters shared by the auto-sell and keep lists: "only items in my bags"
-- and item type, subtype and slot.
local function MatchesBagAndType(filters, item)
    if filters.inBags and not item.inBags then return false end
    if filters.classID and item.classID ~= filters.classID then return false end
    if filters.subClassID and item.subClassID ~= filters.subClassID then return false end
    if filters.slot and item.equipLoc ~= filters.slot then return false end
    return true
end

local function ActiveBagAndType(filters)
    local count = 0
    for _, key in ipairs({ "inBags", "classID", "subClassID", "slot" }) do
        if filters[key] then count = count + 1 end
    end
    return count
end

local function ResetBagAndType(filters)
    filters.inBags = false
    filters.classID, filters.subClassID, filters.slot = nil, nil, nil
end

-- Counts for the menu: item types, and subtypes/slots within the chosen type.
local function CountBagAndType(filters, items, counts)
    counts.class, counts.sub, counts.slot = {}, {}, {}
    for _, item in ipairs(items) do
        if item.classID then
            counts.class[item.classID] = (counts.class[item.classID] or 0) + 1
            if item.classID == filters.classID then
                counts.sub[item.subClassID] = (counts.sub[item.subClassID] or 0) + 1
                if item.equipLoc then
                    counts.slot[item.equipLoc] = (counts.slot[item.equipLoc] or 0) + 1
                end
            end
        end
    end
end

local function BagAndTypeMenu(root, list, filters, counts)
    FilterCheckbox(root, list, L["Only items in my bags"], filters, "inBags")
    root:CreateDivider()

    local typeMenu = root:CreateButton(L["Type: "] .. (filters.classID and ItemClassName(filters.classID) or L["All"]))
    FilterRadio(typeMenu, list, L["All types"], function() return filters.classID == nil end, function()
        filters.classID, filters.subClassID, filters.slot = nil, nil, nil
    end)
    for _, classID in ipairs(SortedKeys(counts.class, ItemClassName)) do
        FilterRadio(typeMenu, list, ("%s (%d)"):format(ItemClassName(classID), counts.class[classID]),
            function() return filters.classID == classID end,
            function() filters.classID, filters.subClassID, filters.slot = classID, nil, nil end)
    end

    if filters.classID then
        local function subName(subClassID) return ItemSubClassName(filters.classID, subClassID) end
        local subMenu = root:CreateButton(L["Subtype: "] .. (filters.subClassID and subName(filters.subClassID) or L["All"]))
        FilterRadio(subMenu, list, L["All subtypes"], function() return filters.subClassID == nil end,
            function() filters.subClassID = nil end)
        for _, subClassID in ipairs(SortedKeys(counts.sub, subName)) do
            FilterRadio(subMenu, list, ("%s (%d)"):format(subName(subClassID), counts.sub[subClassID]),
                function() return filters.subClassID == subClassID end,
                function() filters.subClassID = subClassID end)
        end

        if next(counts.slot) then
            local slotMenu = root:CreateButton(L["Slot: "] .. (filters.slot and SlotName(filters.slot) or L["All"]))
            FilterRadio(slotMenu, list, L["All slots"], function() return filters.slot == nil end,
                function() filters.slot = nil end)
            for _, slot in ipairs(SortedKeys(counts.slot, SlotName)) do
                FilterRadio(slotMenu, list, ("%s (%d)"):format(SlotName(slot), counts.slot[slot]),
                    function() return filters.slot == slot end,
                    function() filters.slot = slot end)
            end
        end
    end
end

local ITEM_SORTS = {
    { "name", L["Name"] },
    { "price", L["Vendor price"] },
    { "recent", L["Recently added"] },
}
local ITEM_COMPARE = {
    price = function(a, b) return (a.sellPrice or 0) > (b.sellPrice or 0) end,
    recent = function(a, b) return a.addedAt > b.addedAt end,
}

-- The auto-sell and keep lists filter and sort the same way.
local ITEM_LIST_RULES = {
    sorts = ITEM_SORTS,
    compare = ITEM_COMPARE,
    matches = MatchesBagAndType,
    activeCount = ActiveBagAndType,
    reset = ResetBagAndType,
    count = CountBagAndType,
    buildMenu = BagAndTypeMenu,
}

local LIST_RULES = {
    keep = ITEM_LIST_RULES,
    sell = ITEM_LIST_RULES,

    quest = {
        sorts = {
            { "name", L["Name"] },
            { "level", L["Quest level"] },
        },
        compare = {
            level = function(a, b) return a.minLevel < b.minLevel end,
        },
        matches = function(filters, item)
            if filters.flaggedOnly and not item.flagged then return false end
            if filters.skill and item.skill ~= filters.skill then return false end
            local level = UnitLevel("player")
            if filters.hideLow and item.maxLevel > 0 and item.maxLevel < level - 10 then return false end
            if filters.hideHigh and item.minRequired > level then return false end
            return true
        end,
        activeCount = function(filters)
            local count = filters.skill and 1 or 0
            for _, key in ipairs({ "flaggedOnly", "hideLow", "hideHigh" }) do
                if filters[key] then count = count + 1 end
            end
            return count
        end,
        reset = function(filters)
            filters.flaggedOnly, filters.hideLow, filters.hideHigh, filters.skill = false, false, false, nil
        end,
        count = function(_, items, counts)
            counts.skill = {}
            for _, item in ipairs(items) do
                counts.skill[item.skill] = (counts.skill[item.skill] or 0) + 1
            end
        end,
        buildMenu = function(root, list, filters, counts)
            FilterCheckbox(root, list, L["Only items on my auto-sell list"], filters, "flaggedOnly")
            root:CreateDivider()
            local professionMenu = root:CreateButton(L["Profession: "]
                .. (filters.skill and ProfessionName(filters.skill) or L["All"]))
            FilterRadio(professionMenu, list, L["All"], function() return filters.skill == nil end,
                function() filters.skill = nil end)
            for _, skill in ipairs(SortedKeys(counts.skill, ProfessionName)) do
                FilterRadio(professionMenu, list, ("%s (%d)"):format(ProfessionName(skill), counts.skill[skill]),
                    function() return filters.skill == skill end,
                    function() filters.skill = skill end)
            end
            root:CreateDivider()
            FilterCheckbox(root, list, L["Hide quests far below my level"], filters, "hideLow")
            FilterCheckbox(root, list, L["Hide quests above my level"], filters, "hideHigh")
        end,
    },
}

-- A card with a title, item count, search box, quality chips, a filter menu,
-- a sort menu and a scrolling item list. options: key ("sell" or "quest"),
-- title, bottom (card's distance from the page bottom), emptyIcon, and
-- onRemove(itemID) with removeText for a remove button on each row.
local function CreateListCard(page, options)
    local rules = LIST_RULES[options.key]
    local list = {
        key = options.key, rules = rules, rows = {}, chips = {}, counts = {}, query = "",
        onRemove = options.onRemove, removeText = options.removeText,
    }
    local function filters() return ns.db.filters[list.key] end

    local card = CreateFrame("Frame", nil, page)
    card:SetPoint("TOPLEFT", 20, -20)
    card:SetPoint("BOTTOMRIGHT", -20, options.bottom)
    Rounded(card, "BACKGROUND", C.card)
    Rounded(card, "BORDER", C.cardBorder, "rounded-border")

    local bar = card:CreateTexture(nil, "ARTWORK")
    bar:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    bar:SetSize(3, 14)
    bar:SetPoint("TOPLEFT", 20, -24)

    local title = Text(card, 13, C.text)
    title:SetPoint("LEFT", bar, "RIGHT", 10, 0)
    title:SetText(options.title)

    list.count = CreateBadge(card, C.muted, { 1, 1, 1, 0.06 })
    list.count:SetPoint("LEFT", title, "RIGHT", 10, 0)

    local search = CreateSearchBox(card, function(text)
        list.query = text
        ns.RefreshWindow()
    end)
    search:SetPoint("TOPRIGHT", -16, -16)

    -- Filter bar: quality chips on the left, filter and sort menus on the right.
    local x = 20
    for _, quality in ipairs(QUALITY_FILTERS) do
        local chip = CreateChip(card, QUALITY_NAMES[quality], QualityColor(quality), function(active)
            filters().qualities[quality] = active or nil
            ns.RefreshWindow()
        end)
        chip:SetPoint("TOPLEFT", x, -58)
        x = x + chip:GetWidth() + 5
        list.chips[quality] = chip
    end

    list.sortMenu = CreateDropdown(card, 130,
        function()
            for _, sort in ipairs(rules.sorts) do
                if sort[1] == filters().sort then return L["Sort: "] .. sort[2] end
            end
            return L["Sort"]
        end,
        function(root)
            for _, sort in ipairs(rules.sorts) do
                FilterRadio(root, list, sort[2],
                    function() return filters().sort == sort[1] end,
                    function() filters().sort = sort[1] end)
            end
        end)
    list.sortMenu:SetPoint("TOPRIGHT", -16, -57)

    list.filterMenu = CreateDropdown(card, 100,
        function()
            local active = rules.activeCount(filters())
            return active > 0 and (L["Filters (%d)"]):format(active) or L["Filters"]
        end,
        function(root)
            rules.buildMenu(root, list, filters(), list.counts)
            root:CreateDivider()
            root:CreateButton(L["Reset filters"], function()
                rules.reset(filters())
                wipe(filters().qualities)
                list:FiltersChanged()
            end)
        end)
    list.filterMenu:SetPoint("RIGHT", list.sortMenu, "LEFT", -6, 0)

    function list:FiltersChanged()
        self.filterMenu:UpdateLabel()
        self.sortMenu:UpdateLabel()
        ns.RefreshWindow()
    end

    list.area = CreateFrame("Frame", nil, card)
    list.area:SetPoint("TOPLEFT", 10, -94)
    list.area:SetPoint("BOTTOMRIGHT", -10, 10)

    list.scroll, list.content = CreateScrollArea(list.area)
    list.scroll:SetPoint("TOPLEFT")
    list.scroll:SetPoint("BOTTOMRIGHT", -12, 0)

    -- Shown when the list is empty or nothing matches the search.
    local empty = CreateFrame("Frame", nil, list.area)
    empty:SetAllPoints()
    local emptyIcon = Icon(empty, options.emptyIcon, 40, { 1, 1, 1, 0.12 })
    emptyIcon:SetPoint("CENTER", 0, 30)
    empty.title = Text(empty, 15, C.text)
    empty.title:SetPoint("TOP", emptyIcon, "BOTTOM", 0, -12)
    empty.title:SetJustifyH("CENTER")
    empty.body = Text(empty, 12, C.muted)
    empty.body:SetPoint("TOP", empty.title, "BOTTOM", 0, -6)
    empty.body:SetWidth(300)
    empty.body:SetJustifyH("CENTER")
    list.empty = empty

    return list
end

-- Shows the items that match the search and filters, sorted. Returns how
-- many are shown.
local function SetListItems(list, items)
    local filters = ns.db.filters[list.key]
    local rules = list.rules
    rules.count(filters, items, list.counts)

    local shown = {}
    for _, item in ipairs(items) do
        if (list.query == "" or item.name:lower():find(list.query, 1, true))
            and (not next(filters.qualities) or (item.quality and filters.qualities[item.quality]))
            and rules.matches(filters, item) then
            shown[#shown + 1] = item
        end
    end
    local compare = rules.compare[filters.sort]
    table.sort(shown, function(a, b)
        if compare and compare(a, b) ~= compare(b, a) then return compare(a, b) end
        return a.name < b.name
    end)

    for i, item in ipairs(shown) do
        list.rows[i] = list.rows[i] or CreateItemRow(list, i)
        UpdateItemRow(list.rows[i], item)
        list.rows[i]:Show()
    end
    for i = #shown + 1, #list.rows do
        list.rows[i]:Hide()
    end
    list.content:SetHeight(math.max(#shown * ITEM_HEIGHT, 1))
    list.scroll.UpdateScrollBar()

    -- Controls follow the profile (it may have just changed).
    for quality, chip in pairs(list.chips) do
        chip:SetActive(filters.qualities[quality])
    end
    list.filterMenu:UpdateLabel()
    list.sortMenu:UpdateLabel()

    if #shown < #items then
        list.count:SetText((L["%d of %d items"]):format(#shown, #items))
    else
        list.count:SetText(#items == 1 and L["1 item"] or (#items .. " items"))
    end
    list.empty:SetShown(#shown == 0)
    return #shown
end

local dropOverlays = {} -- [page key] = overlay

local function UpdateDropOverlay()
    local holdingItem = GetCursorInfo() == "item"
    for page, overlay in pairs(dropOverlays) do
        overlay:SetShown(holdingItem and currentPage == page)
    end
end

-- Covers a list while an item is on the cursor, so it can be dropped in.
local function CreateDropOverlay(list, page, text, keep)
    local overlay = CreateFrame("Frame", nil, list.area)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(list.scroll:GetFrameLevel() + 20)
    overlay:EnableMouse(true)
    overlay:Hide()
    Rounded(overlay, "BACKGROUND", { C.gold[1], C.gold[2], C.gold[3], 0.12 })
    Rounded(overlay, "BORDER", C.gold, "rounded-border")
    local label = Text(overlay, 15, C.gold)
    label:SetPoint("CENTER")
    label:SetText(text)
    local function accept() AcceptCursorItem(keep) end
    overlay:SetScript("OnReceiveDrag", accept)
    overlay:SetScript("OnMouseUp", accept)
    dropOverlays[page] = overlay
end

local function BuildListPage(page)
    sellList = CreateListCard(page, {
        key = "sell",
        title = L["AUTO-SELL LIST"],
        bottom = 72,
        emptyIcon = "icon-coin",
        onRemove = ns.Unflag,
        removeText = L["Remove from the auto-sell list"],
    })

    CreateDropOverlay(sellList, "list", L["Drop to auto-sell this item"])

    -- Footer: what will be sold, and a button to sell it now.
    sellButton = CreateButton(page, L["Sell junk now"], 150, true)
    sellButton:SetPoint("BOTTOMRIGHT", -20, 22)
    sellButton:SetScript("OnClick", function() ns.SellJunk(true) end)
    sellButton:HookScript("OnEnter", function(self)
        if not self:IsEnabled() then ShowTooltip(self, L["Open a vendor window first."]) end
    end)
    sellButton:HookScript("OnLeave", GameTooltip_Hide)

    local junkLabel = Text(page, 12, C.muted)
    junkLabel:SetPoint("BOTTOMLEFT", 22, 40)
    junkLabel:SetText(L["JUNK IN YOUR BAGS"])
    junkText = Text(page, 14, C.text)
    junkText:SetPoint("TOPLEFT", junkLabel, "BOTTOMLEFT", 0, -4)
end

local function RefreshSellList()
    local items = GetFlaggedItems()
    SetListItems(sellList, items)
    if #items == 0 then
        sellList.empty.title:SetText(L["Nothing flagged yet"])
        sellList.empty.body:SetText(L["Alt+Right-click an item in your bags, or drag it here."])
    else
        sellList.empty.title:SetText(L["No matches"])
        sellList.empty.body:SetText(L["No flagged items match your search and filters."])
    end

    sellButton:SetEnabled(ns.IsMerchantOpen())
    local count, money = ns.GetJunkSummary()
    if count == 0 then
        junkText:SetText(L["Nothing to sell"])
    else
        junkText:SetText(("%d %s  |cff8a8b93-|r  %s"):format(
            count, count == 1 and "item" or "items", GetMoneyString(money, true)))
    end
end

-- Shows the "keep" or "quest" tab of the Keep list page.
local function SetKeepTab(tab)
    keepTab = tab
    for key, frame in pairs(keepFrames) do frame:SetShown(key == tab) end
    if keepTabs then keepTabs:Update() end
    ns.RefreshWindow()
end

-- The keep list, and on a second tab the quest gear the rules never sell.
local function BuildKeepPage(page)
    keepTabs = CreateSegmented(page, { { "keep", L["Keep list"] }, { "quest", L["Quest gear"] } },
        function() return keepTab end, SetKeepTab)
    keepTabs:SetPoint("TOPLEFT", 20, -18)

    for _, tab in ipairs({ "keep", "quest" }) do
        local frame = CreateFrame("Frame", nil, page)
        frame:SetPoint("TOPLEFT", 0, -48)
        frame:SetPoint("BOTTOMRIGHT")
        frame:SetShown(tab == keepTab)
        keepFrames[tab] = frame
    end

    local frame = keepFrames.keep
    keepList = CreateListCard(frame, {
        key = "keep",
        title = L["KEEP LIST"],
        bottom = 64,
        emptyIcon = "icon-lock",
        onRemove = ns.Unkeep,
        removeText = L["Remove from the keep list"],
    })
    CreateDropOverlay(keepList, "keep", L["Drop to always keep this item"], true)

    local note = Text(frame, 12, C.muted)
    note:SetPoint("BOTTOMLEFT", 22, 22)
    note:SetPoint("BOTTOMRIGHT", -22, 22)
    note:SetText(L["Items here are never sold or destroyed, whatever the junk rules say. Keep whole groups of items "
        .. "with the \"Always keep\" rules on the Junk rules page."])

    frame = keepFrames.quest
    questList = CreateListCard(frame, {
        key = "quest",
        title = L["QUEST GEAR"],
        bottom = 64,
        emptyIcon = "icon-quest",
    })
    questList.empty.title:SetText(L["No matches"])
    questList.empty.body:SetText(L["No quest gear matches your search and filters."])

    note = Text(frame, 12, C.muted)
    note:SetPoint("BOTTOMLEFT", 22, 22)
    note:SetPoint("BOTTOMRIGHT", -22, 22)
    note:SetText(L["Weapons and armor that quests ask you to bring. The junk rules never sell them while "
        .. "\"Quest gear\" is on (Junk rules, Always keep). Items you put on the auto-sell list still sell."])
end

local function RefreshKeepList()
    local items = GetKeptItems()
    SetListItems(keepList, items)
    if #items == 0 then
        keepList.empty.title:SetText(L["Nothing kept yet"])
        keepList.empty.body:SetText(L["Alt+Right-click an item and choose \"Never sell\", or drag it here."])
    else
        keepList.empty.title:SetText(L["No matches"])
        keepList.empty.body:SetText(L["No kept items match your search and filters."])
    end
end

local function RefreshQuestList()
    SetListItems(questList, GetQuestGearItems())
end

------------------------------------------------------------------------
-- Settings pages
------------------------------------------------------------------------

-- Price steps for the cheap white items limit, in copper (up to 1 gold).
local CHEAP_LIMITS = { 1, 5, 10, 25, 50, 100, 200, 500, 1000, 2500, 5000, 10000 }
local MAX_PREVIEW_LINES = 15

-- Tooltip listing everything Pocket Goblin would sell from the bags right now.
local function ShowRulePreview(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(L["Pocket Goblin would sell"], 1, 1, 1)
    local found = ns.ScanJunk()
    if #found == 0 then
        GameTooltip:AddLine(L["Nothing in your bags right now."], 0.7, 0.7, 0.7)
    end
    local total = 0
    for i, entry in ipairs(found) do
        total = total + entry.value
        if i <= MAX_PREVIEW_LINES then
            local count = (entry.info.stackCount or 1) > 1 and (" x" .. entry.info.stackCount) or ""
            GameTooltip:AddDoubleLine(("|T%s:16:16:0:0:64:64:5:59:5:59|t %s%s"):format(
                entry.info.iconFileID, entry.info.hyperlink, count), ns.REASONS[entry.reason],
                1, 1, 1, 0.6, 0.6, 0.6)
        end
    end
    if #found > MAX_PREVIEW_LINES then
        GameTooltip:AddLine((L["...and %d more"]):format(#found - MAX_PREVIEW_LINES), 0.6, 0.6, 0.6)
    end
    if total > 0 then
        GameTooltip:AddDoubleLine(L["Total"], GetMoneyString(total, true), 0.7, 0.7, 0.7, 1, 1, 1)
    end
    GameTooltip:Show()
end

-- Slider steps for "keep valuable items", in copper (up to 10 gold).
local VALUABLE_LIMITS = { 100, 500, 1000, 2500, 5000, 10000, 25000, 50000, 100000 }

-- Item types offered by "Always keep: item types" (item class IDs).
local KEEP_TYPES = { 0, 1, 2, 4, 5, 6, 7, 9, 11, 12, 13, 15 }

-- Comma-separated words for "Always keep: names containing".
local function CreateWordsInput(parent)
    local box = CreateTextInput(parent, 236, L["e.g. potion, elixir"])
    box:SetMaxLetters(200)
    local function show()
        box:SetText(table.concat(ns.db.keepWords, ", "))
    end
    local function save()
        if box.cancelled then -- Escape: drop the edit
            box.cancelled = nil
            show()
            return
        end
        local words = {}
        for word in box:GetText():gmatch("[^,]+") do
            word = strtrim(word):lower()
            if word ~= "" then words[#words + 1] = word end
        end
        ns.db.keepWords = words
        show()
        ns.OnRulesChanged()
    end
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEscapePressed", function(self)
        self.cancelled = true
        self:ClearFocus()
    end)
    box:HookScript("OnEditFocusLost", save)
    function box:Update()
        if not self:HasFocus() then show() end
    end
    show()
    toggles[#toggles + 1] = box
    return box
end

-- Dropdown with a checkbox per item type for "Always keep: item types".
local function CreateTypePicker(parent)
    return CreateDropdown(parent, 236,
        function()
            local names = {}
            for _, classID in ipairs(KEEP_TYPES) do
                if ns.db.keepClasses[classID] then names[#names + 1] = ItemClassName(classID) end
            end
            return #names > 0 and table.concat(names, ", ") or L["None"]
        end,
        function(root)
            for _, classID in ipairs(KEEP_TYPES) do
                root:CreateCheckbox(ItemClassName(classID),
                    function() return ns.db.keepClasses[classID] == true end,
                    function()
                        ns.db.keepClasses[classID] = not ns.db.keepClasses[classID] or nil
                        ns.OnRulesChanged()
                    end)
            end
        end)
end

-- Adds a row that is disabled while the setting `key` is off.
local function AddDependentRow(card, key, title, description, makeControl)
    dependentRows[#dependentRows + 1] = { AddRow(card, title, description, makeControl), key }
end

-- What counts as junk. These rules drive selling, the destroy button and
-- the coins in the bags.
local function BuildRulesPage(page)
    CreateCardPage(page, function(addCard)
        local card, finish = addCard(L["Preview"])
        AddRow(card, L["What would be sold now"],
            L["Hover to see everything Pocket Goblin would sell from your bags right now, and why."],
            function(parent)
                local preview = CreateButton(parent, L["Preview"], 100)
                preview:HookScript("OnEnter", ShowRulePreview)
                preview:HookScript("OnLeave", GameTooltip_Hide)
                return preview
            end)
        finish()

        card, finish = addCard(L["Always keep"])
        AddRow(card, L["Keep list"],
            L["Items you've chosen to never sell. Alt+Right-click an item and choose \"Never sell\" to add it."],
            function(parent)
                local open = CreateButton(parent, L["Keep list"], 110)
                open:SetScript("OnClick", function()
                    SetKeepTab("keep")
                    SelectPage("keep")
                end)
                return open
            end)
        AddRow(card, L["Quest gear"],
            L["Never sell weapons and armor that quests ask for. They're listed on the Keep list page, "
                .. "under Quest gear."],
            SettingToggle("skipQuestGear", ns.OnRulesChanged))
        AddRow(card, L["Names containing"],
            L["Never sell items whose name contains one of these words, e.g. potion, elixir. Separate them "
                .. "with commas and press Enter."],
            function(parent) return CreateWordsInput(parent) end)
        AddRow(card, L["Item types"], L["Never sell items of these types, whatever the other rules say."],
            function(parent) return CreateTypePicker(parent) end)
        AddRow(card, L["Valuable items"], L["Never sell items worth more than the amount below."],
            SettingToggle("keepValuable", ns.OnRulesChanged))
        AddDependentRow(card, "keepValuable", L["Worth more than"],
            L["Price per item. Drag, or type an amount like 1g or 50s."],
            function(parent)
                return CreateMoneyInput(parent, VALUABLE_LIMITS,
                    function() return ns.db.keepValueLimit end,
                    function(copper)
                        ns.db.keepValueLimit = copper
                        ns.OnRulesChanged()
                    end)
            end)
        AddRow(card, L["Always protected"],
            L["Items in an equipment set. And your own lists come first: an item on the auto-sell list "
                .. "is sold even if a rule here matches it."])
        finish()

        card, finish = addCard(L["Grey and white items"])
        AddRow(card, L["Sell grey items"],
            L["Every grey item is junk, unless you've put it on the keep list."],
            SettingToggle("sellGreys", ns.OnRulesChanged))
        AddRow(card, L["Sell white weapons and armor"],
            L["From the level below, white gear is junk: by then you've usually found better. Profession "
                .. "tools, fishing poles, thrown weapons, shirts and tabards are left alone."],
            SettingToggle("sellWhiteGear", ns.OnRulesChanged))
        local maxLevel = GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion() or 60
        AddDependentRow(card, "sellWhiteGear", L["From level"],
            L["Below this level white gear is left alone, since you can still use it."],
            function(parent)
                return CreateSlider(parent, 1, math.max(maxLevel, 10), 1, function() return ns.db.whiteGearLevel end,
                    function(value) return ("%d"):format(value + 0.5) end,
                    function(value)
                        ns.db.whiteGearLevel = math.floor(value + 0.5)
                        ns.OnRulesChanged()
                    end)
            end)
        AddRow(card, L["Sell cheap white items"],
            L["Other white items worth less than the amount below, like cheap trade goods. Weapons, armor, "
                .. "food and drink are left to their own rules; ammo, class reagents and profession tools are "
                .. "never sold this way."],
            SettingToggle("sellCheapWhites", ns.OnRulesChanged))
        AddDependentRow(card, "sellCheapWhites", L["Cheaper than"],
            L["Price per item. Drag, or type an amount like 10s or 1s50c."],
            function(parent)
                return CreateMoneyInput(parent, CHEAP_LIMITS,
                    function() return ns.db.cheapWhiteLimit end,
                    function(copper)
                        ns.db.cheapWhiteLimit = copper
                        ns.OnRulesChanged()
                    end)
            end)
        finish()

        card, finish = addCard(L["Food and drink"])
        AddRow(card, L["Sell outgrown food and drink"],
            L["When you carry better food or drink that you can already use, the lower-level kind is sold. "
                .. "Food and drink are compared separately. Food that gives Well Fed is never sold, and "
                .. "conjured food and water never count as better, since they vanish when you log out."],
            SettingToggle("sellOldFood", ns.OnRulesChanged))
        AddDependentRow(card, "sellOldFood", L["Only with at least"],
            L["How many of the better kind you need to carry first, so one lucky drop doesn't sell your supply."],
            function(parent)
                return CreateSlider(parent, 1, 20, 1, function() return ns.db.oldFoodMinBetter end,
                    function(value) return ("%d"):format(value + 0.5) end,
                    function(value)
                        ns.db.oldFoodMinBetter = math.floor(value + 0.5)
                        ns.OnRulesChanged()
                    end)
            end)
        finish()

        card, finish = addCard(L["Soulbound gear"])
        AddRow(card, L["Sell gear you can't use or have outgrown"],
            L["Weapons and armor your class can never equip, like plate on a mage or a wand on a warrior, "
                .. "and gear whose required level is far below yours. Up to rare quality."],
            SettingToggle("sellSoulbound", ns.OnRulesChanged))
        AddDependentRow(card, "sellSoulbound", L["Levels below you"],
            L["How far below your level gear has to be to count as outgrown."],
            function(parent)
                return CreateSlider(parent, 5, 30, 1, function() return ns.db.outgrownLevels end,
                    function(value) return ("%d"):format(value + 0.5) end,
                    function(value)
                        ns.db.outgrownLevels = math.floor(value + 0.5)
                        ns.OnRulesChanged()
                    end)
            end)
        finish()
    end)
end

-- What happens at a vendor.
local function BuildVendorPage(page)
    CreateCardPage(page, function(addCard)
        local card, finish = addCard(L["Selling"])
        AddRow(card, L["Sell when a vendor opens"],
            L["Sell junk as soon as you talk to a vendor. Otherwise use \"Sell junk now\" on the auto-sell list."],
            SettingToggle("autoSell"))
        AddRow(card, L["Sell 12 at a time"],
            L["The vendor's Buyback tab only holds your last 12 sales. Selling 12 at a time keeps every "
                .. "sale buyable; press Sell junk again for the next 12."],
            SettingToggle("sellBatchLimit"))
        AddRow(card, L["Vendor panel"],
            L["A small window next to the vendor with a Sell junk button and everything you sold, to buy "
                .. "back one by one or all at once. It also offers to auto-sell items you keep selling yourself."],
            SettingToggle("merchantPanel", ns.UpdateMerchantPanel))
        finish()

        card, finish = addCard(L["Repairs"])
        AddRow(card, L["Repair at vendors"], L["Repair all your gear whenever you visit a vendor that can repair."],
            SettingToggle("autoRepair"))
        AddDependentRow(card, "autoRepair", L["Use guild funds first"],
            L["Pays from the guild bank when you're allowed to, and from your own gold otherwise."],
            SettingToggle("repairGuild"))
        finish()
    end)
end

-- Slider steps for the destroy value limit, in copper (up to 5 gold).
local LIMITS = { 1, 10, 25, 50, 100, 200, 500, 1000, 2500, 5000, 10000, 20000, 30000, 40000, 50000 }

-- Icons in the bags, the destroy button and the bag space warning.
local function BuildBagsPage(page)
    CreateCardPage(page, function(addCard)
        local card, finish = addCard(L["Bag icons"])
        AddRow(card, L["Coin icon on junk"], L["Show a coin in the corner of items that will be sold."],
            SettingToggle("showIcons", ns.OnRulesChanged))
        AddRow(card, L["Lock on kept items"], L["Show a lock on items on your keep list. It uses the same "
                .. "size and corner as the coin (below)."],
            SettingToggle("keepIcon", ns.OnRulesChanged))
        AddRow(card, L["Icon size"], L["Size of the coin and lock in the corner of the item."],
            function(parent)
                return CreateSlider(parent, 0.5, 2, 0.1, function() return ns.db.iconScale end,
                    function(value) return ("%d%%"):format(value * 100 + 0.5) end,
                    function(value)
                        ns.db.iconScale = value
                        ns.RefreshOverlays()
                    end)
            end)
        AddRow(card, L["Icon position"], L["Which corner of the item the coin and lock sit in."],
            function(parent)
                return CreateCornerPicker(parent,
                    function() return ns.db.iconCorner end,
                    function(corner)
                        ns.db.iconCorner = corner
                        ns.RefreshOverlays()
                    end)
            end)
        AddRow(card, L["Grey out junk"], L["Fade and desaturate items that will be sold."],
            SettingToggle("greyOut", ns.OnRulesChanged))
        AddRow(card, "Baganator",
            L["Baganator draws its own junk coin using Pocket Goblin's rules. If it doesn't, pick Pocket Goblin "
                .. "as the junk plugin in Baganator's settings. Place the lock in Baganator's corner settings."])
        finish()

        card, finish = addCard(L["Destroy button"])
        AddRow(card, L["Show destroy button"],
            L["Adds a trash can to your bags that destroys the junk item worth the least. Hover it to "
                .. "see the item and its value before you click."],
            SettingToggle("destroyButton", ns.UpdateDestroyButtons))
        AddRow(card, L["Ask before destroying"],
            L["Show a confirmation with the item and its value before anything is destroyed."],
            SettingToggle("destroyConfirm"))
        AddRow(card, L["What counts as junk"],
            L["The same items Pocket Goblin would sell. Grey items you've marked to keep are never destroyed."],
            function(parent)
                local open = CreateButton(parent, L["Junk rules"], 110)
                open:SetScript("OnClick", function() SelectPage("rules") end)
                return open
            end)
        AddRow(card, L["Protect valuable junk"],
            L["Never destroy junk worth more than the limit below. For stacks, the value of the whole "
                .. "stack counts."],
            SettingToggle("destroyProtect", ns.UpdateDestroyButtons))
        dependentRows[#dependentRows + 1] = { AddRow(card, L["Value limit"],
            L["Junk worth more than this is left alone. Drag, or type an amount in the format of 1s50c."],
            function(parent)
                return CreateMoneyInput(parent, LIMITS,
                    function() return ns.db.destroyLimit end,
                    function(copper)
                        ns.db.destroyLimit = copper
                        ns.UpdateDestroyButtons()
                    end)
            end), "destroyProtect" }
        finish()

        card, finish = addCard(L["Bag space"])
        AddRow(card, L["Warn when bags are nearly full"],
            L["The trash can turns red and shows how many slots are free. You also get a chat message, "
                .. "unless chat messages are off."],
            SettingToggle("bagWarning", ns.UpdateDestroyButtons))
        dependentRows[#dependentRows + 1] = { AddRow(card, L["Free slots"],
            L["Warn at this many free bag slots or fewer."],
            function(parent)
                return CreateSlider(parent, 1, 10, 1, function() return ns.db.bagWarningSlots end,
                    function(value) return ("%d"):format(value + 0.5) end,
                    function(value)
                        ns.db.bagWarningSlots = math.floor(value + 0.5)
                        ns.UpdateDestroyButtons()
                    end)
            end), "bagWarning" }
        finish()
    end)
end

------------------------------------------------------------------------
-- History page: earnings and recent sales, with buyback
------------------------------------------------------------------------

local history = { rows = {} } -- widgets

local STAT_LABELS = { L["THIS SESSION"], "TODAY", L["THIS CHARACTER"], L["ALL CHARACTERS"] }
local REPAIR_COLOR = { 0.9, 0.55, 0.5 }
local STAT_KEYS = { "session", "today", "character", "account" }
local SOURCES = { { "all", L["Anyone"] }, { "goblin", "Pocket Goblin" }, { "you", L["You"] } }

local function FormatMoney(copper)
    return copper > 0 and GetMoneyString(copper, true) or "0"
end

local function VisitTime(timestamp)
    local day = date("%Y-%m-%d", timestamp)
    if day == date("%Y-%m-%d") then return L["Today "] .. date("%H:%M", timestamp) end
    if day == date("%Y-%m-%d", time() - 86400) then return L["Yesterday "] .. date("%H:%M", timestamp) end
    return date("%b %d, %H:%M", timestamp)
end

-- Rows are either a vendor visit (date, vendor, total) or an item sold on
-- that visit (icon, name, value, buy back).
local function CreateHistoryRow(index)
    local row = CreateFrame("Button", nil, history.content)
    row:SetHeight(ITEM_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ITEM_HEIGHT)
    row:SetPoint("TOPRIGHT", 0, -(index - 1) * ITEM_HEIGHT)

    row.band = Rounded(row, "BACKGROUND", { 1, 1, 1, 0.04 })
    local hover = Rounded(row, "BACKGROUND", { 1, 1, 1, 0.045 })
    hover:Hide()

    row.border = row:CreateTexture(nil, "ARTWORK", nil, 1)
    row.border:SetSize(22, 22)
    row.border:SetPoint("LEFT", 18, 0)
    row.icon = row:CreateTexture(nil, "ARTWORK", nil, 2)
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("CENTER", row.border)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.buy = CreateButton(row, L["Buy back"], 78)
    row.buy:SetHeight(22)
    row.buy:SetPoint("RIGHT", -6, 0)
    row.buy:SetScript("OnClick", function() ns.BuyBack(row.sold) end)

    row.badge = CreateBadge(row, C.muted, { 1, 1, 1, 0.06 })
    row.badge:SetHeight(16)
    row.badge.text:SetFont(FONT, 10, "")
    row.badge:SetText(L["BOUGHT BACK"])
    row.badge:SetPoint("RIGHT", -10, 0)

    row.detail = Text(row, 12, C.muted)
    row.detail:SetJustifyH("RIGHT")

    -- Marks sales you made yourself (Pocket Goblin's own have no badge).
    row.source = CreateBadge(row, C.muted, { 1, 1, 1, 0.06 })
    row.source:SetHeight(16)
    row.source.text:SetFont(FONT, 10, "")
    row.source:SetText(L["YOU"])
    row.source:SetPoint("RIGHT", row.detail, "LEFT", -8, 0)

    row.name = Text(row, 13, C.text)
    row.name:SetWordWrap(false)

    row:SetScript("OnEnter", function(self)
        if not self.sold then return end
        hover:Show()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(self.sold.link)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function()
        hover:Hide()
        GameTooltip_Hide()
    end)
    return row
end

local function UpdateHistoryRow(row, entry)
    row.name:ClearAllPoints()
    row.detail:ClearAllPoints()

    if entry.visit then
        local visit = entry.visit
        row.sold = nil
        row.band:Show()
        row.border:Hide()
        row.icon:Hide()
        row.buy:Hide()
        row.badge:Hide()
        row.source:Hide()
        row:SetAlpha(1)
        row.detail:SetPoint("RIGHT", -10, 0)
        row.detail:SetText(entry.total > 0 and FormatMoney(entry.total) or "")
        row.detail:SetTextColor(C.text[1], C.text[2], C.text[3])
        row.name:SetPoint("LEFT", 10, 0)
        row.name:SetPoint("RIGHT", row.detail, "LEFT", -10, 0)
        row.name:SetText(VisitTime(visit.time) .. (visit.vendor and ("  |cff8a8b93" .. visit.vendor .. "|r") or ""))
        row.name:SetTextColor(C.text[1], C.text[2], C.text[3])
        return
    end

    if entry.repair then
        local repair = entry.repair
        row.sold = nil
        row.band:Hide()
        row.border:Hide()
        row.buy:Hide()
        row.badge:Hide()
        row.source:Hide()
        row:SetAlpha(1)
        row.icon:Show()
        row.icon:SetTexture(MEDIA .. "icon-repair")
        row.icon:SetTexCoord(0, 1, 0, 1)
        SetColor(row.icon, C.muted)
        row.detail:SetPoint("RIGHT", -10, 0)
        row.detail:SetText("-" .. FormatMoney(repair.cost))
        row.detail:SetTextColor(REPAIR_COLOR[1], REPAIR_COLOR[2], REPAIR_COLOR[3])
        row.name:SetPoint("LEFT", row.border, "RIGHT", 8, 0)
        row.name:SetPoint("RIGHT", row.detail, "LEFT", -10, 0)
        row.name:SetText(L["Repairs"] .. (repair.guild and L["  |cff8a8b93paid by the guild|r"] or ""))
        row.name:SetTextColor(C.text[1], C.text[2], C.text[3])
        return
    end

    local sold = entry.sold
    row.sold = sold
    row.band:Hide()
    row.border:Show()
    row.icon:Show()
    row.icon:SetTexture(select(5, C_Item.GetItemInfoInstant(sold.itemID)) or QUESTION_MARK)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icon:SetVertexColor(1, 1, 1)

    local color = sold.quality and QualityColor(sold.quality) or C.muted
    row.border:SetColorTexture(color[1], color[2], color[3], 0.9)
    local name = C_Item.GetItemInfo(sold.itemID) or (sold.link and sold.link:match("%[(.-)%]")) or "?"
    row.name:SetText(name .. (sold.count > 1 and ("  |cff8a8b93x" .. sold.count .. "|r") or ""))
    row.name:SetTextColor(color[1], color[2], color[3])

    local canBuy = entry.canBuy
    row.buy:SetShown(canBuy)
    row.badge:SetShown(sold.boughtBack and true or false)
    row:SetAlpha(sold.boughtBack and 0.55 or 1)

    local anchor = canBuy and row.buy or sold.boughtBack and row.badge
    if anchor then
        row.detail:SetPoint("RIGHT", anchor, "LEFT", -8, 0)
    else
        row.detail:SetPoint("RIGHT", -10, 0)
    end
    row.detail:SetText(FormatMoney(sold.value))
    row.detail:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
    local byYou = sold.source == "you"
    row.source:SetShown(byYou)
    row.name:SetPoint("LEFT", row.border, "RIGHT", 8, 0)
    row.name:SetPoint("RIGHT", byYou and row.source or row.detail, "LEFT", -10, 0)
end

local function BuildHistoryPage(page)
    -- Earnings tiles
    local stats = CreateFrame("Frame", nil, page)
    stats:SetPoint("TOPLEFT", 20, -20)
    stats:SetPoint("TOPRIGHT", -20, -20)
    stats:SetHeight(86)
    Rounded(stats, "BACKGROUND", C.card)
    Rounded(stats, "BORDER", C.cardBorder, "rounded-border")

    history.stats = {}
    local captions, dividers = {}, {}
    for i, label in ipairs(STAT_LABELS) do
        local caption = Text(stats, 11, C.muted)
        caption:SetText(label)
        captions[i] = caption
        local value = Text(stats, 17, C.text)
        value:SetPoint("TOPLEFT", caption, "BOTTOMLEFT", 0, -6)
        local allSales = Text(stats, 11, C.muted)
        allSales:SetPoint("TOPLEFT", value, "BOTTOMLEFT", 0, -4)
        history.stats[i] = { junk = value, all = allSales }
        if i > 1 then
            local divider = stats:CreateTexture(nil, "ARTWORK")
            divider:SetColorTexture(1, 1, 1, 0.06)
            divider:SetWidth(1)
            dividers[i] = divider
        end
    end
    -- Equal-width tiles across the card, whatever the window's width.
    local function placeTiles(width)
        local tileWidth = width / #STAT_LABELS
        for i, caption in ipairs(captions) do
            local x = (i - 1) * tileWidth
            caption:SetPoint("TOPLEFT", x + 20, -18)
            if dividers[i] then
                dividers[i]:SetPoint("TOPLEFT", x, -14)
                dividers[i]:SetPoint("BOTTOMLEFT", x, 14)
            end
        end
    end
    placeTiles(PAGE_WIDTH - 40)
    stats:SetScript("OnSizeChanged", function(_, width)
        if width > 0 then placeTiles(width) end
    end)
    stats:SetScript("OnShow", function(self)
        if self:GetWidth() > 0 then placeTiles(self:GetWidth()) end
    end)

    -- Recent sales
    local card = CreateFrame("Frame", nil, page)
    card:SetPoint("TOPLEFT", stats, "BOTTOMLEFT", 0, -16)
    card:SetPoint("BOTTOMRIGHT", -20, 56)
    Rounded(card, "BACKGROUND", C.card)
    Rounded(card, "BORDER", C.cardBorder, "rounded-border")

    local bar = card:CreateTexture(nil, "ARTWORK")
    bar:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    bar:SetSize(3, 14)
    bar:SetPoint("TOPLEFT", 20, -22)
    local title = Text(card, 13, C.text)
    title:SetPoint("LEFT", bar, "RIGHT", 10, 0)
    title:SetText(L["RECENT VISITS"])
    history.count = CreateBadge(card, C.muted, { 1, 1, 1, 0.06 })
    history.count:SetPoint("LEFT", title, "RIGHT", 10, 0)

    local function sourceFilter() return ns.db.filters.history end
    history.sourceMenu = CreateDropdown(card, 150,
        function()
            for _, option in ipairs(SOURCES) do
                if option[1] == sourceFilter().source then return L["Sold by: "] .. option[2] end
            end
            return L["Sold by"]
        end,
        function(root)
            for _, option in ipairs(SOURCES) do
                root:CreateRadio(option[2], function() return sourceFilter().source == option[1] end, function()
                    sourceFilter().source = option[1]
                    history.sourceMenu:UpdateLabel()
                    ns.RefreshWindow()
                end)
            end
        end)
    history.sourceMenu:SetPoint("TOPRIGHT", -16, -14)

    history.repairs = Text(card, 11, C.muted)
    history.repairs:SetPoint("RIGHT", history.sourceMenu, "LEFT", -12, 0)
    history.repairs:SetJustifyH("RIGHT")

    local area = CreateFrame("Frame", nil, card)
    area:SetPoint("TOPLEFT", 10, -50)
    area:SetPoint("BOTTOMRIGHT", -10, 10)
    history.scroll, history.content = CreateScrollArea(area)
    history.scroll:SetPoint("TOPLEFT")
    history.scroll:SetPoint("BOTTOMRIGHT", -12, 0)

    local empty = CreateFrame("Frame", nil, area)
    empty:SetAllPoints()
    local emptyIcon = Icon(empty, "icon-history", 40, { 1, 1, 1, 0.12 })
    emptyIcon:SetPoint("CENTER", 0, 24)
    local emptyTitle = Text(empty, 15, C.text)
    emptyTitle:SetPoint("TOP", emptyIcon, "BOTTOM", 0, -12)
    emptyTitle:SetText(L["Nothing sold yet"])
    local emptyBody = Text(empty, 12, C.muted)
    emptyBody:SetPoint("TOP", emptyTitle, "BOTTOM", 0, -6)
    emptyBody:SetText(L["Sales and repairs show up here after you visit a vendor."])
    history.empty = empty

    local note = Text(page, 12, C.muted)
    note:SetPoint("BOTTOMLEFT", 22, 22)
    note:SetPoint("BOTTOMRIGHT", -22, 22)
    note:SetText(L["Buy back works while a vendor is open, for items still in its buyback list "
        .. "(the last 12 items you sold)."])
end

local function RefreshHistory()
    local earnings, repairs, guildRepairs = ns.GetEarnings()
    for i, key in ipairs(STAT_KEYS) do
        history.stats[i].junk:SetText(FormatMoney(math.max(earnings[key].junk, 0)))
        history.stats[i].all:SetText(L["All sales: "] .. FormatMoney(math.max(earnings[key].all, 0)))
    end
    local repairText = repairs > 0 and (L["Repairs: "] .. GetMoneyString(repairs, true)) or ""
    if guildRepairs > 0 then
        repairText = repairText .. (repairText ~= "" and "  " or L["Repairs: "])
            .. L["|cff8a8b93(guild paid "] .. GetMoneyString(guildRepairs, true) .. ")|r"
    end
    history.repairs:SetText(repairText)
    history.sourceMenu:UpdateLabel()

    -- Visits with the sales that match the "Sold by" filter, then their
    -- repairs; each visit's total is its sales, minus what was bought back.
    local source = ns.db.filters.history.source
    local visits = ns.GetHistory()
    local buybacks = ns.MatchBuybacks()
    local entries, shownVisits = {}, 0
    for _, visit in ipairs(visits) do
        local header = { visit = visit, total = 0 }
        local items = {}
        for _, sold in ipairs(visit.items) do
            local soldBy = sold.source == "you" and "you" or "goblin" -- older saves say "junkseller" or nothing
            if source == "all" or soldBy == source then
                items[#items + 1] = { sold = sold, canBuy = buybacks[sold] ~= nil }
                if not sold.boughtBack then header.total = header.total + sold.value end
            end
        end
        for _, repair in ipairs(visit.repairs or {}) do
            items[#items + 1] = { repair = repair }
        end
        if #items > 0 then
            shownVisits = shownVisits + 1
            entries[#entries + 1] = header
            for _, item in ipairs(items) do entries[#entries + 1] = item end
        end
    end

    for i, entry in ipairs(entries) do
        history.rows[i] = history.rows[i] or CreateHistoryRow(i)
        UpdateHistoryRow(history.rows[i], entry)
        history.rows[i]:Show()
    end
    for i = #entries + 1, #history.rows do
        history.rows[i]:Hide()
    end
    history.content:SetHeight(math.max(#entries * ITEM_HEIGHT, 1))
    history.scroll.UpdateScrollBar()

    history.count:SetText(shownVisits == 1 and L["1 visit"] or (shownVisits .. " visits"))
    history.empty:SetShown(shownVisits == 0)
end


local function ProfileExists(name)
    return name and tContains(ns.GetProfileNames(), name)
end

-- Holder with a dropdown on the left and a button on the right.
local function DropdownWithButton(parent, dropdown, button)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(236, 32)
    dropdown:SetParent(holder)
    dropdown:SetPoint("LEFT")
    button:SetParent(holder)
    button:SetPoint("RIGHT")
    return holder
end

-- The Profile and Manage profiles cards, for the General page.
local function AddProfileCards(addCard)
    local copySource, deleteTarget

    do
        local card, finish = addCard(L["Profile"])
        AddRow(card, L["Active profile"], L["The settings, auto-sell list and filters this character uses."],
            function(parent)
                return CreateDropdown(parent, 236,
                    function() return ns.GetProfileName() end,
                    function(root)
                        for _, name in ipairs(ns.GetProfileNames()) do
                            local others = #ns.GetProfileUsers(name)
                            local label = others > 0
                                and ("%s  |cff8a8b93(+%d %s)|r"):format(name, others, others == 1 and "character" or "characters")
                                or name
                            root:CreateRadio(label, function() return ns.GetProfileName() == name end,
                                function() ns.SetProfile(name) end)
                        end
                    end)
            end)
        AddRow(card, L["New profile"], L["Starts as a copy of the active profile, and this character switches to it."],
            function(parent)
                local holder = CreateFrame("Frame", nil, parent)
                holder:SetSize(236, 32)
                local box = CreateTextInput(holder, 156, L["Profile name"])
                box:SetPoint("LEFT")
                local create = CreateButton(holder, L["Create"], 72, true)
                create:SetPoint("RIGHT")
                local function submit()
                    if ns.CreateProfile(box:GetText()) then
                        box:SetText("")
                        box:ClearFocus()
                    else
                        ns.Print(L["Enter a name that isn't already used by a profile."])
                    end
                end
                create:SetScript("OnClick", submit)
                box:SetScript("OnEnterPressed", submit)
                return holder
            end)
        finish()

        card, finish = addCard(L["Manage profiles"])
        AddRow(card, L["Copy from"], L["Replace the active profile's settings and lists with a copy of another profile."],
            function(parent)
                local dropdown
                dropdown = CreateDropdown(parent, 156,
                    function() return ProfileExists(copySource) and copySource or L["Choose profile"] end,
                    function(root)
                        for _, name in ipairs(ns.GetProfileNames()) do
                            if name ~= ns.GetProfileName() then
                                root:CreateRadio(name, function() return copySource == name end, function()
                                    copySource = name
                                    dropdown:UpdateLabel()
                                end)
                            end
                        end
                    end)
                local copy = CreateConfirmButton(parent, L["Copy"], 72, nil, function()
                    if ProfileExists(copySource) then ns.CopyProfile(copySource) end
                end)
                return DropdownWithButton(parent, dropdown, copy)
            end)
        AddRow(card, L["Reset profile"], L["Back to default settings, with an empty auto-sell list."],
            function(parent)
                return CreateConfirmButton(parent, L["Reset"], 100, "danger", ns.ResetProfile)
            end)
        AddRow(card, L["Delete profile"],
            L["Characters using it switch to Default. Default and the active profile can't be deleted."],
            function(parent)
                local dropdown
                dropdown = CreateDropdown(parent, 156,
                    function() return ProfileExists(deleteTarget) and deleteTarget or L["Choose profile"] end,
                    function(root)
                        for _, name in ipairs(ns.GetProfileNames()) do
                            if name ~= ns.GetProfileName() and name ~= ns.DEFAULT_PROFILE then
                                root:CreateRadio(name, function() return deleteTarget == name end, function()
                                    deleteTarget = name
                                    dropdown:UpdateLabel()
                                end)
                            end
                        end
                    end)
                local delete = CreateConfirmButton(parent, L["Delete"], 72, "danger", function()
                    if ProfileExists(deleteTarget) then ns.DeleteProfile(deleteTarget) end
                    deleteTarget = nil
                    dropdown:UpdateLabel()
                end)
                return DropdownWithButton(parent, dropdown, delete)
            end)
        finish()
    end
end

local MESSAGE_STYLES = { { "goblin", L["Goblin"] }, { "plain", L["Plain"] }, { "off", L["Off"] } }

local function BuildGeneralPage(page)
    CreateCardPage(page, function(addCard)
        local card, finish = addCard(L["Interface"])
        AddRow(card, L["Show minimap button"], L["Left-click opens the list, right-click the settings."],
            SettingToggle("showMinimap", ns.UpdateMinimapButton))
        AddRow(card, L["Explain in tooltips"],
            L["Items in your bags say whether they'll be sold or kept, why, and what the stack sells for."],
            SettingToggle("tooltipValue"))
        finish()

        card, finish = addCard(L["Chat messages"])
        AddRow(card, L["How your goblin talks"],
            L["Goblin: messages in its own words, its mood under the title and a cheer at sales milestones. "
                .. "Plain: short, plain messages. Off: only the summaries after selling, repairing and buying back."],
            function(parent)
                return CreateSegmented(parent, MESSAGE_STYLES,
                    function() return ns.db.messages end,
                    function(style)
                        ns.db.messages = style
                        ns.RefreshWindow()
                    end)
            end)
        finish()

        AddProfileCards(addCard)
    end)
end

local function BuildAboutPage(page)
    CreateCardPage(page, function(addCard)
        local card, finish = addCard(L["How it works"])
        AddRow(card, L["Flag items"], L["Alt+Right-click an item in your bags, or drag it onto the auto-sell list."])
        AddRow(card, L["Keep an item"], L["Alt+Right-click it and choose \"Never sell\". Kept items are never "
            .. "sold or destroyed."])
        AddRow(card, L["Selling"], L["Junk is sold when you open a vendor. A summary of what you earned is "
            .. "always printed in chat."])
        AddRow(card, L["Destroying"], L["The button on your bags destroys the cheapest junk item, to make room "
            .. "when no vendor is around."])
        AddRow(card, L["Buying back"], L["The vendor panel and the History page list recent sales. While a vendor "
            .. "is open you can buy back items still in its buyback list (the last 12 items you sold), one by one "
            .. "or all at once."])
        AddRow(card, L["Suggestions"], L["Sell the same item yourself a few times and the vendor panel offers to "
            .. "put it on the auto-sell list."])
        finish()

        card, finish = addCard(L["Help"])
        AddRow(card, L["Found a bug?"],
            L["Type /goblin debug, copy the text from the window that opens, and include it in your "
                .. "report on Pocket Goblin's CurseForge page."])
        finish()

        card, finish = addCard(L["Slash commands"])
        local commands = {
            { "/goblin", L["Open or close this window"] },
            { "/goblin sell", L["Sell junk now (vendor must be open)"] },
            { "/goblin add, keep, remove <item>", L["Put an item on a list, or take it off, by link or item ID"] },
            { "/goblin list", L["Print your lists in chat"] },
            { "/goblin minimap", L["Show or hide the minimap button"] },
            { "/goblin chat [goblin|plain|off]", L["Choose how the goblin talks in chat"] },
            { "/goblin profile [name]", L["Show or switch this character's profile"] },
            { "/goblin clear confirm", L["Empty the auto-sell and keep lists"] },
            { "/goblin welcome", L["Show the welcome window again"] },
            { "/goblin debug", L["Details to copy into a bug report"] },
        }
        for _, command in ipairs(commands) do
            AddRow(card, command[1], command[2])
        end
        finish()
    end)
end

local BUILDERS = {
    list = BuildListPage,
    keep = BuildKeepPage,
    general = BuildGeneralPage,
    rules = BuildRulesPage,
    vendor = BuildVendorPage,
    bags = BuildBagsPage,
    history = BuildHistoryPage,
    about = BuildAboutPage,
}

------------------------------------------------------------------------
-- Refresh
------------------------------------------------------------------------

-- Enables or disables a control and everything in it.
local function SetFrameEnabled(frame, enabled)
    if frame.SetEnabled then frame:SetEnabled(enabled) end
    if not enabled and frame.HasFocus and frame:HasFocus() then frame:ClearFocus() end
    for _, child in ipairs({ frame:GetChildren() }) do
        SetFrameEnabled(child, enabled)
    end
end

local function Refresh()
    if not window or not window:IsShown() then return end
    for _, toggle in ipairs(toggles) do
        toggle:Update(true)
    end
    for _, dependent in ipairs(dependentRows) do
        local enabled = ns.db[dependent[2]] and true or false
        for _, region in pairs(dependent[1]) do
            region:SetAlpha(enabled and 1 or 0.35)
            if region.GetChildren then SetFrameEnabled(region, enabled) end
        end
    end
    RefreshSellList()
    if currentPage == "keep" then
        if keepTab == "quest" then RefreshQuestList() else RefreshKeepList() end
    end
    if currentPage == "history" then RefreshHistory() end
end

-- Batched so a burst of events only refreshes once.
function ns.RefreshWindow()
    if refreshPending or not window or not window:IsShown() then return end
    refreshPending = true
    C_Timer.After(0.05, function()
        refreshPending = false
        Refresh()
    end)
end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------

function SelectPage(key)
    local alias = PAGE_ALIASES[key]
    if alias then
        key = alias[1]
        if alias[2] then SetKeepTab(alias[2]) end
    end
    currentPage = key
    for _, page in ipairs(PAGES) do
        if page.key then
            local selected = page.key == key
            pages[page.key]:SetShown(selected)
            local nav = navButtons[page.key]
            nav.selected:SetShown(selected)
            nav.accent:SetShown(selected)
            SetColor(nav.icon, selected and C.gold or C.muted)
            local color = selected and C.gold or C.text
            nav.title:SetTextColor(color[1], color[2], color[3])
        end
    end
    UpdateDropOverlay()
    ns.RefreshWindow() -- the quest gear list only refreshes while it's shown
end

-- A sidebar entry. Long subtitles wrap onto more lines and the button grows
-- to fit; returns its height.
local function CreateNavButton(parent, page, y)
    local nav = CreateFrame("Button", nil, parent)
    nav:SetPoint("TOPLEFT", 10, y)

    nav.selected = Rounded(nav, "BACKGROUND", C.goldDim)
    local hover = Rounded(nav, "BACKGROUND", { 1, 1, 1, 0.035 })
    hover:Hide()

    nav.accent = nav:CreateTexture(nil, "ARTWORK")
    nav.accent:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    nav.accent:SetSize(3, 30)
    nav.accent:SetPoint("LEFT", 0, 0)

    nav.icon = Icon(nav, page.icon, 20, C.muted)
    nav.icon:SetPoint("LEFT", 16, 0)

    nav.title = Text(nav, 15, C.text)
    nav.title:SetText(page.title)

    local subtitle = Text(nav, 11, C.muted)
    subtitle:SetPoint("TOPLEFT", nav.title, "BOTTOMLEFT", 0, -4)
    subtitle:SetWidth(SIDEBAR_WIDTH - 20 - 56)
    subtitle:SetText(page.subtitle)

    -- Title and subtitle centred together, with at least NAV_HEIGHT.
    local textHeight = nav.title:GetStringHeight() + 4 + subtitle:GetStringHeight()
    local height = math.max(NAV_HEIGHT, math.ceil(textHeight) + 12)
    nav:SetSize(SIDEBAR_WIDTH - 20, height)
    nav.title:SetPoint("TOPLEFT", 48, -(height - textHeight) / 2)

    nav:SetScript("OnEnter", function() if currentPage ~= page.key then hover:Show() end end)
    nav:SetScript("OnLeave", function() hover:Hide() end)
    nav:SetScript("OnClick", function()
        hover:Hide()
        if SOUNDKIT then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
        SelectPage(page.key)
    end)
    navButtons[page.key] = nav
    return height
end

-- Remembers the window's size and position (for all characters).
local function SaveWindowGeometry()
    local point, _, relativePoint, x, y = window:GetPoint(1)
    PocketGoblinDB.window = {
        point = point, relativePoint = relativePoint, x = x, y = y,
        width = window:GetWidth(), height = window:GetHeight(),
    }
end

local function SetResizeBounds(frame, minWidth, minHeight, maxWidth, maxHeight)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(minWidth, minHeight, maxWidth, maxHeight)
    else -- older clients
        frame:SetMinResize(minWidth, minHeight)
        frame:SetMaxResize(maxWidth, maxHeight)
    end
end

-- Keeps the window on the screen: no bigger than the screen, and scaled
-- down when even its smallest size doesn't fit (small screens, large UI
-- scale). minHeight is what the sidebar needs.
local minHeight = HEIGHT
local function FitToScreen()
    local screenWidth, screenHeight = UIParent:GetWidth() - SCREEN_MARGIN, UIParent:GetHeight() - SCREEN_MARGIN
    local scale = math.min(1, screenWidth / WIDTH, screenHeight / minHeight)
    window:SetScale(scale)
    local maxWidth, maxHeight = math.max(WIDTH, screenWidth / scale), math.max(minHeight, screenHeight / scale)
    SetResizeBounds(window, WIDTH, minHeight, maxWidth, maxHeight)
    window:SetSize(math.max(WIDTH, math.min(window:GetWidth(), maxWidth)),
        math.max(minHeight, math.min(window:GetHeight(), maxHeight)))
end

-- Drag handle in the bottom-right corner.
local function CreateResizeGrip()
    local grip = CreateFrame("Button", nil, window)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -3, 3)
    grip:SetFrameLevel(window:GetFrameLevel() + 50)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then window:StartSizing("BOTTOMRIGHT") end
    end)
    grip:SetScript("OnMouseUp", function()
        window:StopMovingOrSizing()
        SaveWindowGeometry()
    end)
    grip:SetScript("OnEnter", function(self) ShowTooltip(self, L["Drag to resize"]) end)
    grip:SetScript("OnLeave", GameTooltip_Hide)
end

local function CreateHeader()
    local header = CreateFrame("Frame", nil, window)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(HEADER_HEIGHT)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() window:StartMoving() end)
    header:SetScript("OnDragStop", function()
        window:StopMovingOrSizing()
        SaveWindowGeometry()
    end)

    local logo = Icon(header, "logo", 48, C.gold)
    logo:SetPoint("LEFT", 16, 0)

    local title = Text(header, 26, C.text)
    title:SetPoint("BOTTOMLEFT", logo, "RIGHT", 14, 0)
    title:SetText("|cffd4a72cPocket|r Goblin")

    local version = CreateBadge(header, C.gold, { C.gold[1], C.gold[2], C.gold[3], 0.16 })
    version:SetPoint("LEFT", title, "RIGHT", 12, 0)
    version:SetText(ns.VERSION == "dev" and "dev" or ("v" .. (ns.VERSION or "?")))

    local profile = CreateBadge(header, C.muted, { 1, 1, 1, 0.06 })
    profile:SetPoint("LEFT", version, "RIGHT", 6, 0)
    function profile:Update()
        self:SetText(L["Profile: "] .. ns.GetProfileName())
    end
    profile:Update()
    toggles[#toggles + 1] = profile

    local subtitle = Text(header, 13, C.muted)
    subtitle:SetPoint("TOPLEFT", logo, "RIGHT", 14, -4)
    subtitle:SetWidth(WIDTH - 16 - 48 - 14 - 70)
    subtitle:SetWordWrap(false)
    header:SetScript("OnSizeChanged", function(_, width)
        if width > 0 then subtitle:SetWidth(width - 16 - 48 - 14 - 70) end
    end)

    -- The goblin's face and the subtitle follow its mood.
    local mood = {}
    function mood:Update()
        local key, text = ns.GetMood()
        logo:SetTexture(MEDIA .. ns.MOOD_LOGOS[key])
        subtitle:SetText(ns.GoblinVoice() and text or L["Sells your junk at vendors"])
    end
    mood:Update()
    toggles[#toggles + 1] = mood

    local close = CreateFrame("Button", nil, header)
    close:SetSize(32, 32)
    close:SetPoint("RIGHT", -18, 0)
    local closeIcon = Icon(close, "icon-close", 18, C.muted)
    closeIcon:SetPoint("CENTER")
    close:SetScript("OnEnter", function() SetColor(closeIcon, C.text) end)
    close:SetScript("OnLeave", function() SetColor(closeIcon, C.muted) end)
    close:SetScript("OnClick", function() window:Hide() end)

    local line = header:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.55)
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT", 1, 0)
    line:SetPoint("BOTTOMRIGHT", -1, 0)
end

local function CreateWindow()
    window = CreateFrame("Frame", "PocketGoblinFrame", UIParent, "BackdropTemplate")
    local saved = PocketGoblinDB.window
    window:SetSize(saved and saved.width or WIDTH, saved and saved.height or HEIGHT)
    if saved and saved.point then
        window:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
    else
        window:SetPoint("CENTER")
    end
    window:SetFrameStrata("DIALOG")
    window:SetToplevel(true)
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:SetResizable(true)
    if window.SetDontSavePosition then window:SetDontSavePosition(true) end -- saved by us instead
    window:EnableMouse(true)
    window:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    window:SetBackdropColor(unpack(C.bg))
    window:SetBackdropBorderColor(unpack(C.windowBorder))
    window:Hide()

    -- Escape closes only this window, not the game options behind it.
    -- (UISpecialFrames would close every open panel at once.) Keyboard
    -- propagation can't be changed in combat, so Escape is ignored then.
    window:EnableKeyboard(true)
    window:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then return end
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            self:Hide()
            C_Timer.After(0, function()
                if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
            end)
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)

    CreateHeader()

    local sidebar = CreateFrame("Frame", nil, window)
    sidebar:SetPoint("TOPLEFT", 1, -HEADER_HEIGHT - 1)
    sidebar:SetPoint("BOTTOMLEFT", 1, 1)
    sidebar:SetWidth(SIDEBAR_WIDTH)
    local sidebarBg = sidebar:CreateTexture(nil, "BACKGROUND")
    sidebarBg:SetAllPoints()
    sidebarBg:SetColorTexture(unpack(C.sidebar))
    local sidebarLine = sidebar:CreateTexture(nil, "ARTWORK")
    sidebarLine:SetColorTexture(1, 1, 1, 0.06)
    sidebarLine:SetWidth(1)
    sidebarLine:SetPoint("TOPRIGHT")
    sidebarLine:SetPoint("BOTTOMRIGHT")

    local y = -8
    for _, page in ipairs(PAGES) do
        if page.section then
            if y < -8 then y = y - 8 end
            local heading = Text(sidebar, 10, C.muted)
            heading:SetPoint("TOPLEFT", 22, y - 7)
            heading:SetText(page.section)
            y = y - SECTION_HEIGHT
        else
            y = y - CreateNavButton(sidebar, page, y) - (NAV_SPACING - NAV_HEIGHT)
            local frame = CreateFrame("Frame", nil, window)
            frame:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 0, 0)
            frame:SetPoint("BOTTOMRIGHT", -1, 1)
            frame:Hide()
            pages[page.key] = frame
            BUILDERS[page.key](frame)
        end
    end
    SelectPage("list")
    minHeight = HEADER_HEIGHT - y + 8 -- tall enough for the whole sidebar
    CreateResizeGrip()

    window:SetScript("OnShow", function(self)
        if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
        self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        self:RegisterEvent("CURSOR_CHANGED")
        self:RegisterEvent("DISPLAY_SIZE_CHANGED")
        self:RegisterEvent("UI_SCALE_CHANGED")
        FitToScreen()
        UpdateDropOverlay()
        Refresh()
    end)
    window:SetScript("OnHide", function(self)
        self:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
        self:UnregisterEvent("CURSOR_CHANGED")
        self:UnregisterEvent("DISPLAY_SIZE_CHANGED")
        self:UnregisterEvent("UI_SCALE_CHANGED")
        for _, overlay in pairs(dropOverlays) do overlay:Hide() end
    end)
    window:SetScript("OnEvent", function(_, event)
        if event == "CURSOR_CHANGED" then
            UpdateDropOverlay()
        elseif event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED" then
            FitToScreen()
        else
            ns.RefreshWindow()
        end
    end)
end

-- show: true/false, or nil to toggle. page: a page key, or "settings" for
-- the first settings page. Toggling while open on another page switches
-- pages instead of closing.
function ns.ToggleWindow(show, page)
    if not window then CreateWindow() end
    if page == "settings" then page = "general" end
    if show == nil then
        show = not window:IsShown() or (page ~= nil and page ~= currentPage)
    end
    if page then SelectPage(page) end
    window:SetShown(show)
end

------------------------------------------------------------------------
-- Copy window (for debug output: addons can't write to the clipboard, so
-- the text is shown selected, ready for Ctrl+C)
------------------------------------------------------------------------

-- Escape closes only this frame, not other open windows (see the main window).
local function CloseOnEscape(frame)
    frame:EnableKeyboard(true)
    frame:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then return end
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            self:Hide()
            C_Timer.After(0, function()
                if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
            end)
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
end
ns.UI.CloseOnEscape = CloseOnEscape

local copyWindow

local function CreateCopyWindow()
    copyWindow = CreateFrame("Frame", "PocketGoblinCopyWindow", UIParent, "BackdropTemplate")
    copyWindow:SetSize(560, 380)
    copyWindow:SetPoint("CENTER")
    copyWindow:SetFrameStrata("FULLSCREEN_DIALOG")
    copyWindow:SetToplevel(true)
    copyWindow:SetClampedToScreen(true)
    copyWindow:SetMovable(true)
    copyWindow:EnableMouse(true)
    copyWindow:RegisterForDrag("LeftButton")
    copyWindow:SetScript("OnDragStart", copyWindow.StartMoving)
    copyWindow:SetScript("OnDragStop", copyWindow.StopMovingOrSizing)
    copyWindow:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    copyWindow:SetBackdropColor(unpack(C.bg))
    copyWindow:SetBackdropBorderColor(unpack(C.windowBorder))
    copyWindow:Hide()
    CloseOnEscape(copyWindow)

    local logo = Icon(copyWindow, "logo", 24, C.gold)
    logo:SetPoint("TOPLEFT", 16, -14)
    copyWindow.title = Text(copyWindow, 15, C.text)
    copyWindow.title:SetPoint("LEFT", logo, "RIGHT", 8, 0)

    local close = CreateFrame("Button", nil, copyWindow)
    close:SetSize(28, 28)
    close:SetPoint("TOPRIGHT", -10, -10)
    local closeIcon = Icon(close, "icon-close", 14, C.muted)
    closeIcon:SetPoint("CENTER")
    close:SetScript("OnEnter", function() SetColor(closeIcon, C.text) end)
    close:SetScript("OnLeave", function() SetColor(closeIcon, C.muted) end)
    close:SetScript("OnClick", function() copyWindow:Hide() end)

    local hint = Text(copyWindow, 12, C.muted)
    hint:SetPoint("TOPLEFT", 16, -46)
    hint:SetText(L["The text is selected: press Ctrl+C to copy it, then paste it into your bug report."])

    local area = CreateFrame("Frame", nil, copyWindow)
    area:SetPoint("TOPLEFT", 12, -70)
    area:SetPoint("BOTTOMRIGHT", -12, 12)
    Rounded(area, "BACKGROUND", C.card)
    Rounded(area, "BORDER", C.cardBorder, "rounded-border")

    -- The text box is the scroll frame's own child (the usual setup for copy
    -- windows); the mouse wheel scrolls it.
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
    box:SetMaxLetters(100000)
    box:SetAutoFocus(false)
    box:SetWidth(560 - 24 - 24) -- window minus area and scroll insets
    box:SetHeight(380 - 70 - 12 - 20)
    box:SetFontObject(ChatFontNormal)
    box:SetTextColor(C.text[1], C.text[2], C.text[3])
    box:SetScript("OnEscapePressed", function() copyWindow:Hide() end)
    -- Read-only: typing puts the original text back.
    box:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText(copyWindow.text)
            self:HighlightText()
        end
    end)
    scroll:SetScrollChild(box)
    copyWindow.box = box
end

-- Shows text in a window, selected for copying.
function ns.ShowCopyWindow(title, text)
    if not copyWindow then CreateCopyWindow() end
    copyWindow.title:SetText(title)
    copyWindow.text = text
    copyWindow:Show()
    copyWindow.box:SetText(text)
    copyWindow.box:SetFocus()
    copyWindow.box:HighlightText()
end

------------------------------------------------------------------------
-- Welcome window (first run, or /goblin welcome)
------------------------------------------------------------------------

local WELCOME_WIDTH = 480
-- A small gold dot (the font has no bullet character).
local BULLET = "|T" .. MEDIA .. "circle:7:7:0:0:32:32:0:32:0:32:212:167:44|t  "
local welcome

-- What the current settings will sell and do, as lines of text.
local function WelcomeSummary()
    local db = ns.db
    local sells, also = {}, {}
    if db.sellGreys then sells[#sells + 1] = L["Grey items"] end
    if db.sellWhiteGear then
        sells[#sells + 1] = (L["White weapons and armor, from level %d"]):format(db.whiteGearLevel)
    end
    if db.sellOldFood then sells[#sells + 1] = L["Food and drink you've outgrown"] end
    if db.sellCheapWhites then
        sells[#sells + 1] = L["White items worth less than "] .. GetMoneyString(db.cheapWhiteLimit, true)
    end
    if db.sellSoulbound then sells[#sells + 1] = L["Soulbound gear your class can't use or you've outgrown"] end
    sells[#sells + 1] = L["Anything you put on the auto-sell list"]

    if db.autoSell then
        also[#also + 1] = L["Sells as soon as you open a vendor"]
    else
        also[#also + 1] = L["Sells when you press Sell junk at a vendor"]
    end
    if db.autoRepair then also[#also + 1] = L["Repairs your gear at vendors"] end
    if db.destroyButton then also[#also + 1] = L["Adds a trash can to your bags for the cheapest junk"] end
    also[#also + 1] = L["Never sells quest gear, equipment sets or anything on your keep list"]
    return sells, also
end

local function CreateWelcome()
    welcome = CreateFrame("Frame", "PocketGoblinWelcome", UIParent, "BackdropTemplate")
    welcome:SetWidth(WELCOME_WIDTH)
    welcome:SetPoint("CENTER", 0, 60)
    welcome:SetFrameStrata("FULLSCREEN_DIALOG")
    welcome:SetToplevel(true)
    welcome:SetClampedToScreen(true)
    welcome:EnableMouse(true)
    welcome:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    welcome:SetBackdropColor(unpack(C.bg))
    welcome:SetBackdropBorderColor(unpack(C.windowBorder))
    welcome:Hide()
    CloseOnEscape(welcome)
    welcome:SetScript("OnHide", function() PocketGoblinDB.welcomed = true end)

    local logo = Icon(welcome, "logo", 56, C.gold)
    logo:SetPoint("TOPLEFT", 20, -18)
    local title = Text(welcome, 22, C.text)
    title:SetPoint("BOTTOMLEFT", logo, "RIGHT", 14, 0)
    title:SetText(L["Welcome to |cffd4a72cPocket|r Goblin"])
    local subtitle = Text(welcome, 13, C.muted)
    subtitle:SetPoint("TOPLEFT", logo, "RIGHT", 14, -4)
    subtitle:SetText(L["Your goblin sells your junk whenever you visit a vendor."])

    local line = welcome:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.45)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 1, -90)
    line:SetPoint("TOPRIGHT", -1, -90)

    welcome.lines = {} -- text regions, reused when shown again

    local review = CreateButton(welcome, L["Review rules"], 130)
    review:SetPoint("BOTTOMRIGHT", -150, 18)
    review:SetScript("OnClick", function()
        welcome:Hide()
        ns.ToggleWindow(true, "rules")
    end)
    local ok = CreateButton(welcome, L["Looks good"], 120, true)
    ok:SetPoint("BOTTOMRIGHT", -20, 18)
    ok:SetScript("OnClick", function() welcome:Hide() end)
end

-- Lays out a heading and bullet lines from y down. Returns the new y and
-- the number of text regions used so far.
local function WelcomeSection(y, heading, items, used)
    local function textLine(size, color)
        used = used + 1
        local region = welcome.lines[used] or Text(welcome, size, color)
        welcome.lines[used] = region
        region:SetFont(FONT, size, "")
        region:SetTextColor(color[1], color[2], color[3])
        region:SetWidth(WELCOME_WIDTH - 60)
        region:ClearAllPoints()
        region:Show()
        return region
    end
    local label = textLine(12, C.muted)
    label:SetPoint("TOPLEFT", 24, y)
    label:SetText(heading)
    y = y - label:GetStringHeight() - 8
    for _, item in ipairs(items) do
        local bullet = textLine(13, C.text)
        bullet:SetPoint("TOPLEFT", 30, y)
        bullet:SetText(BULLET .. item)
        y = y - bullet:GetStringHeight() - 5
    end
    return y - 10, used
end

function ns.ShowWelcome()
    if not welcome then CreateWelcome() end
    for _, region in ipairs(welcome.lines) do region:Hide() end

    local sells, also = WelcomeSummary()
    local y, used = -106, 0
    y, used = WelcomeSection(y, L["WHAT YOUR GOBLIN WILL SELL"], sells, used)
    y, used = WelcomeSection(y, L["IT ALSO"], also, used)
    y, used = WelcomeSection(y, L["GOOD TO KNOW"], {
        L["Alt+Right-click any item in your bags to auto-sell it or keep it."],
        L["Open Pocket Goblin with /goblin or the minimap button."],
    }, used)
    welcome:SetHeight(-y + 60)
    welcome:Show()
end

------------------------------------------------------------------------
-- Entry points: AddOns options panel and the minimap addon compartment
------------------------------------------------------------------------

if Settings and Settings.RegisterCanvasLayoutCategory then
    local panel = CreateFrame("Frame")

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Pocket Goblin")

    local desc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetText(L["Settings and flagged items are in the Pocket Goblin window (/goblin)."])

    local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    open:SetSize(180, 24)
    open:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -12)
    open:SetText(L["Open Pocket Goblin"])
    open:SetScript("OnClick", function() ns.ToggleWindow(true) end)

    ns.settingsCategory = Settings.RegisterCanvasLayoutCategory(panel, "Pocket Goblin")
    Settings.RegisterAddOnCategory(ns.settingsCategory)
end

function PocketGoblin_OnAddonCompartmentClick()
    ns.ToggleWindow()
end
