-- GearAlert.lua against stubs, plain Lua 5.1.
-- Stubs only the surface the patch touches.
local FILE = "GearAlert.lua"

local Widget = {}
Widget.__index = Widget
local function W(kind, name, parent)
    local w = setmetatable({
        kind = kind,
        name = name,
        parent = parent,
        regions = {},
        scripts = {},
        alpha = 1,
        level = 2,
        shown = true,
        id = 0,
    }, Widget)
    if name then
        _G[name] = w
    end
    return w
end
function Widget:CreateTexture()
    local t = W("Texture")
    self.regions[#self.regions + 1] = t
    return t
end
function Widget:SetPoint() end
function Widget:SetHeight(h)
    self.h = h
end
function Widget:SetWidth(w)
    self.w = w
end
function Widget:SetColorTexture(r, g, b, a)
    self.color = { r, g, b, a }
end
function Widget:SetAlpha(a)
    self.alpha = a
end
function Widget:SetFrameLevel(l)
    self.level = l
end
function Widget:GetFrameLevel()
    return self.level
end
function Widget:IsForbidden()
    return false
end
function Widget:Show()
    self.shown = true
end
function Widget:Hide()
    self.shown = false
end
function Widget:IsShown()
    return self.shown
end
function Widget:GetID()
    return self.id
end
function Widget:SetScript(s, f)
    self.scripts[s] = f
end
function Widget:HookScript(s, f)
    self.scripts[s] = self.scripts[s] or {}
    table.insert(self.scripts[s], f)
end
function Widget:RegisterEvent(e)
    self.events = self.events or {}
    self.events[e] = true
end

_G.CreateFrame = function(kind, name, parent)
    return W(kind, name, parent)
end
_G.GetTime = function()
    return 0
end
_G.C_Timer = { After = function() end }
_G.UnitExists = function(u)
    return u ~= "none"
end
_G.issecretvalue = function()
    return false
end

_G.INVSLOT_HEAD, _G.INVSLOT_SHOULDER, _G.INVSLOT_CHEST = 1, 3, 5
_G.INVSLOT_LEGS, _G.INVSLOT_FEET = 7, 8
_G.INVSLOT_FINGER1, _G.INVSLOT_FINGER2 = 11, 12
_G.INVSLOT_MAINHAND, _G.INVSLOT_OFFHAND = 16, 17
_G.INVSLOT_BACK, _G.INVSLOT_WRIST = 15, 9
_G.Enum = { ItemClass = { Weapon = 2 } }

-- Item model the tests drive.
local items, enchants, gems, sockets = {}, {}, {}, {}
_G.GetInventoryItemLink = function(_, slotID)
    return items[slotID]
end
_G.C_Item = {
    GetItemInfoInstant = function(link)
        return nil, nil, nil, nil, nil, (link == "shield" and 4 or 2)
    end,
    GetItemStats = function(link)
        local n = sockets[link]
        return n and { EMPTY_SOCKET_PRISMATIC = n } or {}
    end,
    GetItemGem = function(link, i)
        local g = gems[link]
        if g and i <= g then
            return nil, "gem" .. i
        end
        return nil, nil
    end,
}

local level = 90
_G.UnitLevel = function()
    return level
end

local ffd = setmetatable({}, { __mode = "k" })
_G.EllesmereUI = {
    _GetFFD = function(o)
        ffd[o] = ffd[o] or {}
        return ffd[o]
    end,
    GetEnchantText = function(slotID)
        return enchants[slotID] or ""
    end,
}
local ns = {}
_G.C_AddOns = {
    IsAddOnLoaded = function()
        return false
    end,
}

SlashCmdList = SlashCmdList or {}
assert(loadfile("Core.lua"))("SimpleEllesmereExtras", ns)
assert(loadfile("Gate.lua"))("SimpleEllesmereExtras", ns)
assert(loadfile(FILE))("SimpleEllesmereExtras", ns)

local out = io.write
local fails = 0
local function check(n, ok, extra)
    if ok then
        out("  ok   " .. n .. "\n")
    else
        fails = fails + 1
        out("  FAIL " .. n .. (extra and (" -- " .. tostring(extra)) or "") .. "\n")
    end
end
out("GearAlert test\n")

local GA = ns.GearAlert
check("waits for login and the inspect sheet", GA.boot.events.PLAYER_LOGIN and GA.boot.events.ADDON_LOADED)

-- Enchantable slots mirror EUI's view: back and wrist do NOT take one in 12.x.
items[INVSLOT_BACK] = "cloak"
items[INVSLOT_WRIST] = "bracers"
items[INVSLOT_CHEST] = "chest"
check("chest with no enchant is missing one", GA.MissingEnchant(INVSLOT_CHEST, "player", "chest"))
check("back is not flagged", GA.MissingEnchant(INVSLOT_BACK, "player", "cloak") == false)
check("wrist is not flagged", GA.MissingEnchant(INVSLOT_WRIST, "player", "bracers") == false)

enchants[INVSLOT_CHEST] = "+50 Stamina"
check("an enchanted chest is not flagged", GA.MissingEnchant(INVSLOT_CHEST, "player", "chest") == false)

-- Off hand depends on what is in it: a weapon takes an enchant, a shield does not.
check("an off-hand weapon is flagged", GA.MissingEnchant(INVSLOT_OFFHAND, "player", "sword"))
check("an off-hand shield is not", GA.MissingEnchant(INVSLOT_OFFHAND, "player", "shield") == false)

-- Sockets: total from stats, minus the ones holding a gem.
sockets.ring = 2
check("two empty sockets", GA.EmptySockets("ring") == 2, GA.EmptySockets("ring"))
gems.ring = 1
check("one gem in, one socket left", GA.EmptySockets("ring") == 1, GA.EmptySockets("ring"))
gems.ring = 2
check("both filled, nothing to flag", GA.EmptySockets("ring") == 0, GA.EmptySockets("ring"))
check("an item with no sockets is not flagged", GA.EmptySockets("chest") == 0)

-- The glow itself.
local slot = W("Button", "CharacterChestSlot")
slot.id = INVSLOT_CHEST
enchants[INVSLOT_CHEST] = nil
GA.UpdateSlot(slot, "player")
local overlay = ffd[slot].localGearAlert
check("a missing enchant lights the slot", overlay ~= nil and overlay:IsShown())
check(
    "and it is red",
    overlay.regions[1].color[1] == 1 and overlay.regions[1].color[2] == 0.25,
    overlay.regions[1].color[2]
)
check("the ticker runs while a slot is lit", GA.ticker:IsShown())

-- The pulse never drops to where EUI's does; that is the whole point.
GA.ticker.scripts.OnUpdate()
check("the pulse floor is well above EUI's 0.25", overlay.alpha >= 0.5, overlay.alpha)

enchants[INVSLOT_CHEST] = "+50 Stamina"
GA.UpdateSlot(slot, "player")
check("fixing the enchant clears the glow", overlay:IsShown() == false)
check("and the ticker retires", GA.ticker:IsShown() == false)

-- An empty socket is its own colour, so the two faults stay tellable apart.
items[INVSLOT_FINGER1] = "ring"
gems.ring = 0
enchants[INVSLOT_FINGER1] = "+40 Haste" -- enchanted, so only the socket is at fault
local ring = W("Button", "CharacterFinger0Slot")
ring.id = INVSLOT_FINGER1
GA.UpdateSlot(ring, "player")
local ringOv = ffd[ring].localGearAlert
check("an empty socket lights the slot", ringOv:IsShown())
check("in amber, not red", ringOv.regions[1].color[2] == 0.7, ringOv.regions[1].color[2])

-- A slot managing both faults reports the enchant, which is the bigger omission.
enchants[INVSLOT_FINGER1] = nil
GA.UpdateSlot(ring, "player")
check("enchant wins when a slot is missing both", ringOv.regions[1].color[2] == 0.25, ringOv.regions[1].color[2])
enchants[INVSLOT_FINGER1] = "+40 Haste"

-- Levelling gear churns too fast to be worth flagging, same cutoff as EUI.
level = 60
GA.UpdateSlot(slot, "player")
enchants[INVSLOT_CHEST] = nil
GA.UpdateSlot(slot, "player")
check("below level 90 no enchant is flagged", ffd[slot].localGearAlert:IsShown() == false)
level = 90

-- An empty slot has nothing to be missing.
local empty = W("Button", "CharacterHeadSlot")
empty.id = INVSLOT_HEAD
GA.UpdateSlot(empty, "player")
check("an empty slot is never lit", ffd[empty].localGearAlert == nil or ffd[empty].localGearAlert:IsShown() == false)

-- The alert has its own switch now. Unlike the skins it applies live, because
-- an overlay can simply be hidden again.
enchants[INVSLOT_CHEST] = nil
GA.UpdateSlot(slot, "player")
check("lit with the switch on", ffd[slot].localGearAlert:IsShown() == true)
SimpleEllesmereExtrasDB.gearAlert = false
GA.UpdateSlot(slot, "player")
check("switching it off clears a lit slot without a reload", ffd[slot].localGearAlert:IsShown() == false)
SimpleEllesmereExtrasDB.gearAlert = nil
GA.UpdateSlot(slot, "player")
check("and back on lights it again", ffd[slot].localGearAlert:IsShown() == true)

out(fails == 0 and "\nall checks passed\n" or ("\n" .. fails .. " FAILED\n"))
os.exit(fails == 0 and 0 or 1)
