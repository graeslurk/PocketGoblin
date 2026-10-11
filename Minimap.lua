-- Pocket Goblin minimap button: left-click opens the list, right-click the
-- settings, drag to move it around the minimap.

local ADDON_NAME, ns = ...
local L = ns.L

local ICON = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\icon"

local button

local function UpdatePosition()
    local angle = math.rad(ns.db.minimapAngle)
    local radius = Minimap:GetWidth() / 2 + 5
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function ShowTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Pocket Goblin", 1, 1, 1)
    if ns.db.goblinVoice then
        local _, mood = ns.GetMood()
        GameTooltip:AddLine(mood, 1, 0.82, 0.5, true)
    end

    local count, money = ns.GetJunkSummary()
    if count > 0 then
        GameTooltip:AddDoubleLine(L["Junk in bags"],
            ("%d %s  %s"):format(count, count == 1 and "item" or "items", GetMoneyString(money, true)),
            nil, nil, nil, 1, 1, 1)
    else
        GameTooltip:AddLine(L["No junk in your bags"], 0.6, 0.6, 0.6)
    end

    local earnings = ns.GetEarnings()
    GameTooltip:AddDoubleLine(L["Junk sold this session"], GetMoneyString(math.max(earnings.session.junk, 0), true),
        nil, nil, nil, 1, 1, 1)
    GameTooltip:AddDoubleLine(L["Junk sold today"], GetMoneyString(math.max(earnings.today.junk, 0), true),
        nil, nil, nil, 1, 1, 1)

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["|cff00ff00Left-click|r to open the auto-sell list"], 0.8, 0.8, 0.8)
    GameTooltip:AddLine(L["|cff00ff00Right-click|r for settings"], 0.8, 0.8, 0.8)
    GameTooltip:AddLine(L["|cff00ff00Drag|r to move this button"], 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

local function CreateButton()
    button = CreateFrame("Button", "PocketGoblinMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetSize(24, 24)
    background:SetPoint("CENTER")

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ICON)
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(50, 50)
    border:SetPoint("TOPLEFT")

    -- Nudge the icon while pressed, like the built-in minimap buttons.
    button:SetScript("OnMouseDown", function() icon:SetPoint("CENTER", 1, -1) end)
    button:SetScript("OnMouseUp", function() icon:SetPoint("CENTER") end)

    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            ns.ToggleWindow(true, "settings")
        else
            ns.ToggleWindow(nil, "list")
        end
    end)

    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", GameTooltip_Hide)

    button:SetScript("OnDragStart", function(self)
        GameTooltip_Hide()
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            ns.db.minimapAngle = math.deg(math.atan2(py / scale - my, px / scale - mx)) % 360
            UpdatePosition()
        end)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        icon:SetPoint("CENTER")
    end)
end

function ns.UpdateMinimapButton()
    if not ns.db.showMinimap then
        if button then button:Hide() end
        return
    end
    if not button then CreateButton() end
    UpdatePosition()
    button:Show()
end
