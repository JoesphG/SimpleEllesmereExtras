-- The window: a sidebar of pages, a scrolling body, and one top-down layout
-- pass. Knows nothing about what the addon does -- Model.lua supplies that.
--
-- Widgets are pooled per page and reconfigured, never rebuilt. See the note at
-- the top of Widgets.lua.

local _, ns = ...

local Panel = {}
ns.Panel = Panel

local CreateFrame = CreateFrame

local WIDTH, HEIGHT = 620, 480
local SIDEBAR_W = 150
local PAD = 14
local GAP = 6

local window, sidebar, body, scroll
local pageButtons, pageFrames = {}, {}
local currentKey

--------------------------------------------------------------------------------
-- Row blocks
--
-- One pool per page per kind. A page keeps the rows it has ever needed and
-- hides the surplus, because a WoW frame cannot be destroyed.
--------------------------------------------------------------------------------

local function Pool(page, kind, make)
    page.pools = page.pools or {}
    local pool = page.pools[kind]
    if not pool then
        pool = { made = {}, used = 0 }
        page.pools[kind] = pool
    end
    pool.used = pool.used + 1
    local widget = pool.made[pool.used]
    if not widget then
        widget = make(page.content)
        pool.made[pool.used] = widget
    end
    widget:Show()
    return widget
end

local function ResetPools(page)
    for _, pool in pairs(page.pools or {}) do
        for i = 1, #pool.made do
            pool.made[i]:Hide()
        end
        pool.used = 0
    end
end

-- A row is disabled when its model says so, and the reason doubles as the
-- tooltip: a greyed switch with no explanation reads as a bug.
local function DisabledReason(row)
    if not row.disabled then
        return nil
    end
    local reason = row.disabled()
    if reason == true then
        return ""
    end
    return reason or nil
end

local function BuildRow(page, row)
    local reason = DisabledReason(row)

    if row.kind == "text" then
        local widget = Pool(page, "text", ns.UI.Paragraph)
        widget:Configure(row.get(), row.color)
        return widget
    end

    if row.kind == "check" then
        local widget = Pool(page, "check", ns.UI.Check)
        widget:Configure(row.label, row.get(), reason == nil, reason or row.desc)
        widget.onClick = function(value)
            row.set(value)
            Panel.Refresh()
        end
        return widget
    end

    if row.kind == "slider" then
        local widget = Pool(page, "slider", ns.UI.Slider)
        widget:Configure(row.label, row.desc, row.min, row.max, row.step, row.get(), function(value)
            row.set(value)
        end)
        return widget
    end

    if row.kind == "buttons" then
        -- A row of buttons laid left to right, each sized to its own label.
        local host = Pool(page, "buttonrow", function(parent)
            local frame = CreateFrame("Frame", nil, parent)
            frame:SetHeight(22)
            frame.height = 22
            frame.buttons = {}
            return frame
        end)
        for index, spec in ipairs(row.buttons) do
            local btn = host.buttons[index]
            if not btn then
                btn = ns.UI.Button(host)
                host.buttons[index] = btn
            end
            btn:Configure(spec.label, spec.desc, function()
                spec.act()
                Panel.Refresh()
            end)
            btn:ClearAllPoints()
            if index == 1 then
                btn:SetPoint("LEFT")
            else
                btn:SetPoint("LEFT", host.buttons[index - 1], "RIGHT", GAP, 0)
            end
            btn:Show()
        end
        for index = #row.buttons + 1, #host.buttons do
            host.buttons[index]:Hide()
        end
        return host
    end
end

--------------------------------------------------------------------------------
-- Pages
--------------------------------------------------------------------------------

local function LayoutPage(page, model)
    ResetPools(page)

    local y = 0
    local previous

    for _, section in ipairs(model.sections) do
        local header = Pool(page, "section", ns.UI.Section)
        header:SetLabel(section.title)
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", 0, -y)
        header:SetPoint("TOPRIGHT", 0, -y)
        y = y + header.height + 4
        previous = header

        for _, row in ipairs(section.rows) do
            local widget = BuildRow(page, row)
            if widget then
                widget:ClearAllPoints()
                widget:SetPoint("TOPLEFT", 0, -y)
                widget:SetPoint("TOPRIGHT", 0, -y)
                y = y + (widget.height or 20) + GAP
                previous = widget
            end
        end

        y = y + 10
    end

    local _ = previous
    page.content:SetHeight(math.max(y, 1))
end

local function PageFor(model)
    local page = pageFrames[model.key]
    if page then
        return page
    end

    page = { key = model.key }
    page.frame = CreateFrame("Frame", nil, scroll)
    page.frame:SetPoint("TOPLEFT")
    page.frame:SetPoint("TOPRIGHT")
    page.content = page.frame
    page.frame:Hide()
    pageFrames[model.key] = page
    return page
end

--------------------------------------------------------------------------------
-- Sidebar
--------------------------------------------------------------------------------

local function LayoutSidebar(models)
    local y = PAD
    for index, model in ipairs(models) do
        local btn = pageButtons[index]
        if not btn then
            btn = ns.UI.SidebarButton(sidebar)
            pageButtons[index] = btn
        end
        btn:SetLabel(model.title)
        btn:SetSelected(model.key == currentKey)
        btn.onClick = function()
            Panel.ShowPage(model.key)
        end
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", 0, -y)
        btn:SetPoint("TOPRIGHT", 0, -y)
        btn:Show()
        y = y + btn.height
    end
    for index = #models + 1, #pageButtons do
        pageButtons[index]:Hide()
    end
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------

local function Build()
    if window then
        return window
    end

    window = ns.UI.Window("SimpleEllesmereExtrasOptions", WIDTH, HEIGHT)

    local title = window:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOPLEFT", PAD, -PAD)
    title:SetText("SimpleEllesmereExtras")

    local close = ns.UI.CloseButton(window)
    close:SetPoint("TOPRIGHT", -6, -6)

    sidebar = CreateFrame("Frame", nil, window)
    sidebar:SetPoint("TOPLEFT", PAD, -(PAD + 24))
    sidebar:SetPoint("BOTTOMLEFT", PAD, PAD)
    sidebar:SetWidth(SIDEBAR_W)

    body = CreateFrame("Frame", nil, window)
    body:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", PAD, 0)
    body:SetPoint("BOTTOMRIGHT", -PAD, PAD)

    scroll = CreateFrame("ScrollFrame", nil, body, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT")
    scroll:SetPoint("BOTTOMRIGHT", -22, 0)

    return window
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function Panel.Refresh()
    if not window or not window:IsShown() then
        return
    end

    local models = ns.Model.Pages()
    if not currentKey then
        currentKey = models[1].key
    end

    LayoutSidebar(models)

    for _, model in ipairs(models) do
        local page = PageFor(model)
        if model.key == currentKey then
            LayoutPage(page, model)
            scroll:SetScrollChild(page.frame)
            page.frame:SetWidth(scroll:GetWidth())
            page.frame:Show()
        else
            page.frame:Hide()
        end
    end
end

function Panel.ShowPage(key)
    currentKey = key
    Panel.Refresh()
end

function Panel.Open()
    Build()
    window:Show()
    Panel.Refresh()
end

function Panel.Close()
    if window then
        window:Hide()
    end
end

function Panel.Toggle()
    if window and window:IsShown() then
        Panel.Close()
    else
        Panel.Open()
    end
end

function Panel.IsShown()
    return window ~= nil and window:IsShown()
end

-- Blizzard's AddOns list gets a button that opens this, which is where people
-- look first. Registered at login, after the saved variables exist.
function Panel.RegisterSettingsCategory()
    if not (Settings and Settings.RegisterCanvasLayoutCategory) then
        return
    end
    local holder = CreateFrame("Frame")
    holder.name = "SimpleEllesmereExtras"

    local button = CreateFrame("Button", nil, holder, "UIPanelButtonTemplate")
    button:SetSize(200, 24)
    button:SetPoint("TOPLEFT", 16, -16)
    button:SetText("Open SimpleEllesmereExtras")
    button:SetScript("OnClick", function()
        if SettingsPanel then
            HideUIPanel(SettingsPanel)
        end
        Panel.Open()
    end)

    local category = Settings.RegisterCanvasLayoutCategory(holder, "SimpleEllesmereExtras")
    category.ID = "SimpleEllesmereExtras"
    Settings.RegisterAddOnCategory(category)
end

_G.SLASH_SEE1 = "/see"
_G.SlashCmdList.SEE = function()
    Panel.Toggle()
end
