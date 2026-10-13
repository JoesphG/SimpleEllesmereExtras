-------------------------------------------------------------------------------
--  GearAlert.lua
--
--  LOCAL PATCH -- not upstream. Tracked in AddOns/.git; see
--  .addon-patches/README.md.
--
--  Make a slot missing an enchant or a gem impossible to miss, on the character
--  sheet AND the inspect sheet.
--
--  WHAT EUI ALREADY DOES, AND WHY IT IS NOT ENOUGH
--
--  EUI does detect a missing enchant. It draws a small red hex icon by the
--  slot, and on the CHARACTER sheet a 2px border that pulses down to alpha
--  0.25 -- so for half of every cycle the only cue is a 14px icon. On the
--  INSPECT sheet there is no border at all, just the icon. An empty gem socket
--  gets an icon in both and no alert of any kind.
--
--  So this adds one loud, consistent cue to both sheets, for both faults.
--
--  IT DRAWS OUTSIDE THE SLOT, ON PURPOSE
--
--  EUI's own border is drawn just inside the slot edge. Ours is anchored a few
--  pixels OUTSIDE it, so on the character sheet the two reinforce rather than
--  overlap -- two borders on the same pixels, pulsing out of phase, reads as a
--  rendering fault rather than a warning.
--
--  DETECTION MIRRORS EUI'S OWN RULES so the glow never disagrees with the icon
--  beside it: the same public GetEnchantText, the same "level 90+" cutoff (gear
--  churns too fast while levelling to be worth flagging), and the same view of
--  which slots take an enchant at all -- note that in 12.x back and wrist do
--  not, and the off hand only counts when it is a weapon.
-------------------------------------------------------------------------------
local _, ns = ...
local EUI = EllesmereUI
if not (EUI and EUI._GetFFD) then
    return
end

local GetFFD = EUI._GetFFD
local CreateFrame = CreateFrame
local issecretvalue = issecretvalue or function()
    return false
end

-- Which slots take a permanent enchant. Mirrors EUI's INSPECT_ENCHANT_SLOTS;
-- keep the two in step or the glow and the icon will disagree.
local ENCHANTABLE = {
    [INVSLOT_HEAD] = true,
    [INVSLOT_SHOULDER] = true,
    [INVSLOT_CHEST] = true,
    [INVSLOT_LEGS] = true,
    [INVSLOT_FEET] = true,
    [INVSLOT_FINGER1] = true,
    [INVSLOT_FINGER2] = true,
    [INVSLOT_MAINHAND] = true,
    -- Off hand is decided per item below: a weapon takes one, a shield does not.
}

local EMPTY_SOCKET_STATS = {
    EMPTY_SOCKET_META = true,
    EMPTY_SOCKET_RED = true,
    EMPTY_SOCKET_YELLOW = true,
    EMPTY_SOCKET_BLUE = true,
    EMPTY_SOCKET_HYDRAULIC = true,
    EMPTY_SOCKET_COGWHEEL = true,
    EMPTY_SOCKET_PRISMATIC = true,
    EMPTY_SOCKET_DOMINATION = true,
    EMPTY_SOCKET_CYPHER = true,
    EMPTY_SOCKET_PRIMORDIAL = true,
    EMPTY_SOCKET_TINKER = true,
    EMPTY_SOCKET_PUNCHCARDRED = true,
    EMPTY_SOCKET_PUNCHCARDYELLOW = true,
    EMPTY_SOCKET_PUNCHCARDBLUE = true,
}

local ENCHANT_LEVEL = 90
local OUTSET = 3
local THICKNESS = 2

-- Alpha floor is the whole point: EUI's own pulse bottoms out at 0.25, which is
-- why the warning reads as decoration. This one never drops below half.
local PULSE_LOW, PULSE_HIGH, PULSE_PERIOD = 0.5, 1, 1.5

local ENCHANT_COLOR = { 1, 0.25, 0.25 }
local GEM_COLOR = { 1, 0.7, 0.1 }

-------------------------------------------------------------------------------
--  Detection
-------------------------------------------------------------------------------
local function AtEnchantLevel(unit)
    local level = UnitLevel(unit)
    if not level or issecretvalue(level) then
        return false
    end
    return level >= ENCHANT_LEVEL
end

local function CanHaveEnchant(slotID, link)
    if slotID == INVSLOT_OFFHAND then
        if not (link and C_Item and C_Item.GetItemInfoInstant) then
            return false
        end
        local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(link)
        return classID == (Enum and Enum.ItemClass and Enum.ItemClass.Weapon)
    end
    return ENCHANTABLE[slotID] == true
end

local function MissingEnchant(slotID, unit, link)
    if not link or not CanHaveEnchant(slotID, link) then
        return false
    end
    if not EUI.GetEnchantText then
        return false
    end
    local text = EUI.GetEnchantText(slotID, unit)
    return text == nil or text == ""
end

-- Total sockets from the item's stats, minus the ones with a gem in them.
--
-- Gem data hydrates a few frames behind the item itself after a reload, so a
-- socket that looks empty right now may not be; the callers re-run on
-- SOCKET_INFO_UPDATE and GET_ITEM_INFO_RECEIVED rather than trusting one pass.
local function EmptySockets(link)
    if not (link and C_Item and C_Item.GetItemStats and C_Item.GetItemGem) then
        return 0
    end

    local total = 0
    local stats = C_Item.GetItemStats(link)
    if stats then
        for key, count in pairs(stats) do
            if EMPTY_SOCKET_STATS[key] and count and count > 0 then
                total = total + count
            end
        end
    end
    if total == 0 then
        return 0
    end

    local filled = 0
    for i = 1, 4 do
        local _, gemLink = C_Item.GetItemGem(link, i)
        if gemLink then
            filled = filled + 1
        end
    end

    return math.max(0, total - filled)
end

-------------------------------------------------------------------------------
--  The glow
--
--  One ticker for every lit slot, and it hides itself when none are lit, so an
--  unequipped-and-fixed character costs nothing.
-------------------------------------------------------------------------------
local lit = {}
local ticker = CreateFrame("Frame")
ticker:Hide()
ticker:SetScript("OnUpdate", function()
    local mid = (PULSE_LOW + PULSE_HIGH) / 2
    local swing = (PULSE_HIGH - PULSE_LOW) / 2
    local alpha = mid + swing * math.sin(GetTime() * math.pi * 2 / PULSE_PERIOD)
    for frame in pairs(lit) do
        frame:SetAlpha(alpha)
    end
end)

local function Overlay(slot)
    local d = GetFFD(slot)
    if d.localGearAlert then
        return d.localGearAlert
    end

    local f = CreateFrame("Frame", nil, slot)
    f:SetPoint("TOPLEFT", slot, "TOPLEFT", -OUTSET, OUTSET)
    f:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", OUTSET, -OUTSET)
    -- Above EUI's own slot border, which sits just inside the edge.
    f:SetFrameLevel(math.min(slot:GetFrameLevel() + 4, 128))
    f:Hide()

    f.edges = {}
    local function Edge(p1, p2, horizontal)
        local t = f:CreateTexture(nil, "OVERLAY")
        t:SetPoint(p1)
        t:SetPoint(p2)
        if horizontal then
            t:SetHeight(THICKNESS)
        else
            t:SetWidth(THICKNESS)
        end
        f.edges[#f.edges + 1] = t
    end
    Edge("TOPLEFT", "TOPRIGHT", true)
    Edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
    Edge("TOPLEFT", "BOTTOMLEFT", false)
    Edge("TOPRIGHT", "BOTTOMRIGHT", false)

    d.localGearAlert = f
    return f
end

local function SetAlert(slot, color)
    if not slot or (slot.IsForbidden and slot:IsForbidden()) then
        return
    end

    local d = GetFFD(slot)
    if not color then
        local f = d.localGearAlert
        if f then
            f:Hide()
            lit[f] = nil
        end
        if not next(lit) then
            ticker:Hide()
        end
        return
    end

    local f = Overlay(slot)
    for _, t in ipairs(f.edges) do
        t:SetColorTexture(color[1], color[2], color[3], 1)
    end
    f:Show()
    lit[f] = true
    if not ticker:IsShown() then
        ticker:Show()
    end
end

-------------------------------------------------------------------------------
--  Driving it
-------------------------------------------------------------------------------
local function UpdateSlot(slot, unit)
    if not (slot and slot.GetID) then
        return
    end

    -- Live, unlike the skins: an overlay can simply be hidden again.
    if not ns.GearAlertEnabled() then
        return SetAlert(slot, nil)
    end

    local slotID = slot:GetID()
    if not slotID or slotID == 0 then
        return SetAlert(slot, nil)
    end

    local link = GetInventoryItemLink(unit, slotID)
    if not link or issecretvalue(link) then
        return SetAlert(slot, nil)
    end

    -- An enchant is the bigger omission, so it wins the colour when a slot
    -- manages both.
    if AtEnchantLevel(unit) and MissingEnchant(slotID, unit, link) then
        return SetAlert(slot, ENCHANT_COLOR)
    end
    if EmptySockets(link) > 0 then
        return SetAlert(slot, GEM_COLOR)
    end
    SetAlert(slot, nil)
end

local function UpdateAll(prefix, unit)
    if not unit or not UnitExists(unit) then
        return
    end
    for _, name in ipairs({
        "Head",
        "Neck",
        "Shoulder",
        "Back",
        "Chest",
        "Wrist",
        "Hands",
        "Waist",
        "Legs",
        "Feet",
        "Finger0",
        "Finger1",
        "Trinket0",
        "Trinket1",
        "MainHand",
        "SecondaryHand",
    }) do
        UpdateSlot(_G[prefix .. name .. "Slot"], unit)
    end
end

local function RefreshCharacter()
    if CharacterFrame and CharacterFrame:IsShown() then
        UpdateAll("Character", "player")
    end
end

local function RefreshInspect()
    local unit = InspectFrame and InspectFrame.unit
    if unit and InspectFrame:IsShown() then
        UpdateAll("Inspect", unit)
    end
end

-- Item and gem data land in pieces, so a single pass on show is not enough.
local function Later(fn)
    fn()
    C_Timer.After(0.3, fn)
    C_Timer.After(1.5, fn)
end

local function WatchCharacter()
    local watcher = CreateFrame("Frame")
    for _, event in ipairs({
        "PLAYER_EQUIPMENT_CHANGED",
        "UNIT_INVENTORY_CHANGED",
        "SOCKET_INFO_UPDATE",
        "GET_ITEM_INFO_RECEIVED",
        "PLAYER_LEVEL_UP",
    }) do
        pcall(watcher.RegisterEvent, watcher, event)
    end
    watcher:SetScript("OnEvent", RefreshCharacter)

    if CharacterFrame and CharacterFrame.HookScript then
        CharacterFrame:HookScript("OnShow", function()
            Later(RefreshCharacter)
        end)
    end
    if CharacterFrame and CharacterFrame:IsShown() then
        Later(RefreshCharacter)
    end
end

local inspectWatched = false
local function WatchInspect()
    if inspectWatched then
        return
    end
    inspectWatched = true
    local watcher = CreateFrame("Frame")
    pcall(watcher.RegisterEvent, watcher, "INSPECT_READY")
    pcall(watcher.RegisterEvent, watcher, "GET_ITEM_INFO_RECEIVED")
    watcher:SetScript("OnEvent", RefreshInspect)

    if InspectFrame and InspectFrame.HookScript then
        InspectFrame:HookScript("OnShow", function()
            Later(RefreshInspect)
        end)
        -- Blizzard reuses the same global slot frames for whoever is being
        -- inspected next, so a stale glow has to be cleared on the way out.
        InspectFrame:HookScript("OnHide", function()
            UpdateAll("Inspect", "none")
            for _, name in ipairs({
                "Head",
                "Neck",
                "Shoulder",
                "Back",
                "Chest",
                "Wrist",
                "Hands",
                "Waist",
                "Legs",
                "Feet",
                "Finger0",
                "Finger1",
                "Trinket0",
                "Trinket1",
                "MainHand",
                "SecondaryHand",
            }) do
                SetAlert(_G["Inspect" .. name .. "Slot"], nil)
            end
        end)
    end
end

-- The character sheet exists at login; the inspect sheet is load-on-demand.
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("ADDON_LOADED")
boot:SetScript("OnEvent", function(_, event, name)
    if event == "PLAYER_LOGIN" then
        WatchCharacter()
        if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_InspectUI") then
            WatchInspect()
        end
    elseif event == "ADDON_LOADED" and name == "Blizzard_InspectUI" then
        WatchInspect()
    end
end)

ns.GearAlert = {
    boot = boot,
    MissingEnchant = MissingEnchant,
    EmptySockets = EmptySockets,
    UpdateSlot = UpdateSlot,
    SetAlert = SetAlert,
    lit = lit,
    ticker = ticker,
}
