-- The widget factory.
--
-- WIDGETS ARE BUILT ONCE AND RECONFIGURED, NEVER REBUILT. A WoW frame cannot be
-- destroyed, so a panel that recreated its rows on every refresh would grow for
-- the whole session. Hence Configure and SetLabel rather than constructor
-- arguments -- the same rule BonusRollGate's panel is built on.
--
-- Colours come from EllesmereUI when it is there, so the window matches the
-- suite rather than approximating it, and fall back to a flat dark panel when
-- it is not. The addon runs without EllesmereUI and its options have to as well.

local _, ns = ...

local UI = {}
ns.UI = UI

local CreateFrame = CreateFrame

local ROW_H = 24
local CHECK_BOX = 16

local FALLBACK = {
    panel = { 0.06, 0.06, 0.07, 0.96 },
    fill = { 1, 1, 1, 0.05 },
    hover = { 1, 1, 1, 0.08 },
    border = { 0, 0, 0, 1 },
    accent = { 0.047, 0.824, 0.616 },
}

local TEXT = {
    bright = { 1, 1, 1 },
    normal = { 0.85, 0.85, 0.87 },
    dim = { 0.6, 0.6, 0.63 },
}

function UI.Accent()
    if ns.S and ns.S.GetAccentColor then
        local r, g, b = ns.S.GetAccentColor()
        if r then
            return r, g, b
        end
    end
    return unpack(FALLBACK.accent)
end

function UI.PanelColor()
    if ns.S and ns.S.GetPanelColor then
        local r, g, b, a = ns.S.GetPanelColor()
        if r then
            return r, g, b, a or 1
        end
    end
    return unpack(FALLBACK.panel)
end

--------------------------------------------------------------------------------
-- Primitives
--------------------------------------------------------------------------------

local function Fill(frame, layer, r, g, b, a)
    local t = frame:CreateTexture(nil, layer or "BACKGROUND")
    t:SetAllPoints()
    t:SetColorTexture(r, g, b, a)
    return t
end

local function Border(frame, r, g, b, a)
    local edges = {}
    local function Edge(p1, p2, horizontal)
        local t = frame:CreateTexture(nil, "BORDER")
        t:SetColorTexture(r, g, b, a)
        t:SetPoint(p1)
        t:SetPoint(p2)
        if horizontal then
            t:SetHeight(1)
        else
            t:SetWidth(1)
        end
        edges[#edges + 1] = t
    end
    Edge("TOPLEFT", "TOPRIGHT", true)
    Edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
    Edge("TOPLEFT", "BOTTOMLEFT", false)
    Edge("TOPRIGHT", "BOTTOMRIGHT", false)

    return {
        SetColor = function(_, cr, cg, cb, ca)
            for _, t in ipairs(edges) do
                t:SetColorTexture(cr, cg, cb, ca)
            end
        end,
    }
end

local function Label(parent, template, text)
    local fs = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlight")
    if text then
        fs:SetText(text)
    end
    return fs
end

-- One tooltip owner for every widget that has a description, so no row needs
-- its own bookkeeping.
local function Tooltip(frame, get)
    frame:SetScript("OnEnter", function(self)
        local desc = get and get()
        if not desc or desc == "" then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(desc, 1, 1, 1, 1, true)
        GameTooltip:Show()
        if self.onEnter then
            self.onEnter(self)
        end
    end)
    frame:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        if self.onLeave then
            self.onLeave(self)
        end
    end)
end

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------

function UI.Window(name, width, height)
    local frame = CreateFrame("Frame", name, UIParent)
    frame:SetSize(width, height)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()

    local r, g, b, a = UI.PanelColor()
    frame.fill = Fill(frame, "BACKGROUND", r, g, b, a)
    frame.border = Border(frame, unpack(FALLBACK.border))

    -- Escape closes it, like every other panel in the game.
    tinsert(UISpecialFrames, name)

    return frame
end

-- A flat X. UIPanelCloseButton drags in Blizzard's raised gold frame, which is
-- the look this window is getting away from.
function UI.CloseButton(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(22, 22)

    local label = Label(btn, "GameFontNormalLarge", "\195\151") -- U+00D7
    label:SetPoint("CENTER", 0, 1)
    label:SetTextColor(unpack(TEXT.dim))

    btn:SetScript("OnEnter", function()
        label:SetTextColor(1, 0.35, 0.35)
    end)
    btn:SetScript("OnLeave", function()
        label:SetTextColor(unpack(TEXT.dim))
    end)
    btn:SetScript("OnClick", function()
        parent:Hide()
    end)

    return btn
end

--------------------------------------------------------------------------------
-- Sidebar
--------------------------------------------------------------------------------

function UI.SidebarButton(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(28)
    btn.height = 28

    local hover = Fill(btn, "BACKGROUND", 1, 1, 1, 0)
    local stripe = btn:CreateTexture(nil, "ARTWORK")
    stripe:SetPoint("TOPLEFT")
    stripe:SetPoint("BOTTOMLEFT")
    stripe:SetWidth(2)
    stripe:Hide()

    local label = Label(btn, "GameFontHighlight")
    label:SetPoint("LEFT", 12, 0)
    label:SetPoint("RIGHT", -8, 0)
    label:SetJustifyH("LEFT")
    btn.label = label

    local selected = false

    local function Paint()
        local r, g, b = UI.Accent()
        stripe:SetColorTexture(r, g, b, 1)
        stripe:SetShown(selected)
        hover:SetColorTexture(1, 1, 1, selected and 0.06 or 0)
        label:SetTextColor(unpack(selected and TEXT.bright or TEXT.normal))
    end

    btn:SetScript("OnEnter", function()
        if not selected then
            hover:SetColorTexture(unpack(FALLBACK.hover))
        end
    end)
    btn:SetScript("OnLeave", Paint)
    btn:SetScript("OnClick", function(self)
        if self.onClick then
            self.onClick()
        end
    end)

    function btn:SetLabel(text)
        label:SetText(text)
    end

    function btn:SetSelected(value)
        selected = value and true or false
        Paint()
    end

    Paint()
    return btn
end

--------------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------------

function UI.Section(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetHeight(26)
    frame.height = 26

    local label = Label(frame, "GameFontNormalSmall")
    label:SetPoint("BOTTOMLEFT", 0, 4)

    local rule = frame:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("BOTTOMLEFT", 0, 0)
    rule:SetPoint("BOTTOMRIGHT", 0, 0)
    rule:SetHeight(1)

    function frame:SetLabel(text)
        label:SetText((text or ""):upper())
        local r, g, b = UI.Accent()
        label:SetTextColor(r * 0.8, g * 0.8, b * 0.8)
        rule:SetColorTexture(1, 1, 1, 0.08)
    end

    return frame
end

function UI.Paragraph(parent)
    local frame = CreateFrame("Frame", nil, parent)
    local label = Label(frame, "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT")
    label:SetPoint("TOPRIGHT")
    label:SetJustifyH("LEFT")
    label:SetSpacing(2)

    function frame:Configure(text, color)
        label:SetText(text or "")
        label:SetTextColor(unpack(color == "dim" and TEXT.dim or TEXT.normal))
        -- Height follows the wrapped text, so the layout pass can ask for it.
        local h = math.max(label:GetStringHeight() or 0, 12)
        frame:SetHeight(h)
        frame.height = h
    end

    return frame
end

function UI.Check(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(ROW_H)
    btn.height = ROW_H

    local hover = Fill(btn, "BACKGROUND", 1, 1, 1, 0)

    local box = CreateFrame("Frame", nil, btn)
    box:SetSize(CHECK_BOX, CHECK_BOX)
    box:SetPoint("LEFT", 2, 0)
    local boxFill = Fill(box, "BACKGROUND", unpack(FALLBACK.fill))
    local boxBorder = Border(box, 0.35, 0.35, 0.38, 1)

    -- A filled square inset in the box. A tick glyph at 16 pixels is mush.
    local mark = box:CreateTexture(nil, "OVERLAY")
    mark:SetPoint("TOPLEFT", 4, -4)
    mark:SetPoint("BOTTOMRIGHT", -4, 4)
    mark:Hide()

    local label = Label(btn, "GameFontHighlight")
    label:SetPoint("LEFT", box, "RIGHT", 8, 0)
    label:SetPoint("RIGHT", -4, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)

    local checked, enabled = false, true

    local function Paint()
        local r, g, b = UI.Accent()
        mark:SetColorTexture(r, g, b, 1)
        mark:SetShown(checked)
        if enabled then
            boxBorder:SetColor(0.35, 0.35, 0.38, 1)
            boxFill:SetColorTexture(unpack(FALLBACK.fill))
            mark:SetAlpha(1)
            label:SetTextColor(unpack(checked and TEXT.bright or TEXT.normal))
        else
            hover:SetColorTexture(1, 1, 1, 0)
            boxBorder:SetColor(0.25, 0.25, 0.27, 1)
            boxFill:SetColorTexture(1, 1, 1, 0.02)
            mark:SetAlpha(0.35)
            label:SetTextColor(unpack(TEXT.dim))
        end
    end

    btn.onEnter = function()
        if enabled then
            hover:SetColorTexture(unpack(FALLBACK.hover))
            local r, g, b = UI.Accent()
            boxBorder:SetColor(r, g, b, 0.9)
        end
    end
    btn.onLeave = Paint

    btn:SetScript("OnClick", function(self)
        if enabled and self.onClick then
            self.onClick(not checked)
        end
    end)

    function btn:Configure(text, value, isEnabled, desc)
        label:SetText(text or "")
        checked = value and true or false
        enabled = isEnabled ~= false
        Tooltip(self, function()
            return desc
        end)
        Paint()
    end

    Paint()
    return btn
end

function UI.Button(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(22)
    btn.height = 22

    local fill = Fill(btn, "BACKGROUND", unpack(FALLBACK.fill))
    local border = Border(btn, 0.35, 0.35, 0.38, 1)
    local label = Label(btn, "GameFontHighlightSmall")
    label:SetPoint("CENTER")

    btn.onEnter = function()
        local r, g, b = UI.Accent()
        fill:SetColorTexture(r, g, b, 0.18)
        border:SetColor(r, g, b, 0.9)
    end
    btn.onLeave = function()
        fill:SetColorTexture(unpack(FALLBACK.fill))
        border:SetColor(0.35, 0.35, 0.38, 1)
    end

    btn:SetScript("OnClick", function(self)
        if self.act then
            self.act()
        end
    end)

    function btn:Configure(text, desc, act)
        label:SetText(text or "")
        self.act = act
        -- Wide enough for its own label, which is the only thing that sets it.
        self:SetWidth(math.max((label:GetStringWidth() or 40) + 24, 80))
        Tooltip(self, function()
            return desc
        end)
    end

    return btn
end

function UI.Slider(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetHeight(44)
    frame.height = 44

    local label = Label(frame, "GameFontHighlight")
    label:SetPoint("TOPLEFT")
    label:SetJustifyH("LEFT")

    local value = Label(frame, "GameFontHighlightSmall")
    value:SetPoint("TOPRIGHT")
    value:SetJustifyH("RIGHT")

    local slider = CreateFrame("Slider", nil, frame)
    slider:SetPoint("BOTTOMLEFT")
    slider:SetPoint("BOTTOMRIGHT")
    slider:SetHeight(16)
    slider:SetOrientation("HORIZONTAL")
    slider:SetObeyStepOnDrag(true)

    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetHeight(4)
    track:SetColorTexture(1, 1, 1, 0.08)

    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(10, 16)
    slider:SetThumbTexture(thumb)

    local setting

    slider:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v + 0.5)
        value:SetText(tostring(v))
        if setting and not self.quiet then
            setting(v)
        end
    end)

    function frame:Configure(text, desc, min, max, step, current, set)
        label:SetText(text or "")
        setting = nil -- so Configure cannot write back while it is loading
        slider.quiet = true
        slider:SetMinMaxValues(min, max)
        slider:SetValueStep(step or 1)
        slider:SetValue(current or min)
        slider.quiet = nil
        setting = set
        value:SetText(tostring(math.floor((current or min) + 0.5)))

        local r, g, b = UI.Accent()
        thumb:SetColorTexture(r, g, b, 1)
        Tooltip(self, function()
            return desc
        end)
    end

    return frame
end
