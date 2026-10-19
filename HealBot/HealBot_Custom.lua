--[[
  HealBot_Custom.lua
  Support for custom classes (Grimfal Conquest of Azeroth, classless realms, ...).

  HealBot only knows the spells of the 10 original WotLK classes. For any other
  class this module scans the spellbook tooltips (English client) and detects:
    * HoTs / absorb shields  -> HoT icons on the bars
    * friendly dispels       -> Options > Debuffs list, debuff warnings
    * long buffs             -> Options > Buffs list
    * resurrection           -> Smart Cast
  Every spell can be set by hand in the "Custom Spells" window
  (button below the HealBot Options window, or /hb cs). Those settings are
  saved per class and realm in HealBot_Globals.CustomSpells.
]]

-- Optional file overrides (applied after the in-game settings). Keys: class
-- token ("CULTIST"), full HealBot class key ("DRUID-Hero@Realm") or "*".
--   hots    = { ["Spell"]="C" },    -- "C" my casts, "A" anyone's, false = never
--   dispels = { ["Spell"]={"Magic","Curse","Poison","Disease"} },  -- false = not a dispel
--   buffs   = { ["Spell"]=true },   -- false = not a buff
--   res     = "Spell",
--   ignore  = { ["Spell"]=true },
HealBot_Custom_Overrides = {}

-- Result of the last scan
HealBot_Custom = { spells={}, auto={}, hots={}, dispels={}, buffs={}, res=nil, scanned=0 }

local strlower, strfind = strlower, strfind
local TYPES = { "Magic", "Curse", "Poison", "Disease" }

local MODES = { "auto", "hotC", "hotA", "dispel", "buff", "res", "ignore" }
local MODE_LABEL = {
    auto   = "Auto",
    hotC   = "HoT (mine)",
    hotA   = "HoT (all)",
    dispel = "Dispel",
    buff   = "Buff",
    res    = "Resurrect",
    ignore = "Ignore",
}
local KIND_LABEL = { hot="HoT", dispel="Dispel", buff="Buff", res="Resurrect" }

local function wipe(t) for k in pairs(t) do t[k] = nil end end
local function msg(m) DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99HealBot:|r "..m) end

-- ---------------------------------------------------------------------
-- Saved settings: HealBot_Globals.CustomSpells[classKey][spell] = {mode=, types={}}
-- ---------------------------------------------------------------------
local function classKey()
    return (HealBot_GetPlayerClassKey and HealBot_GetPlayerClassKey()) or "?"
end

function HealBot_Custom_GetSaved(create)
    if not HealBot_Globals then return nil end
    if not HealBot_Globals.CustomSpells then
        if not create then return nil end
        HealBot_Globals.CustomSpells = {}
    end
    local k = classKey()
    if not HealBot_Globals.CustomSpells[k] and create then HealBot_Globals.CustomSpells[k] = {} end
    return HealBot_Globals.CustomSpells[k]
end

local function getSetting(name)
    local s = HealBot_Custom_GetSaved(false)
    return s and s[name]
end

local function setSetting(name, mode, types)
    local s = HealBot_Custom_GetSaved(true)
    if not s then return end
    if mode == "auto" and not types then
        s[name] = nil
    else
        s[name] = s[name] or {}
        s[name].mode = mode
        if types then s[name].types = types end
    end
end

-- ---------------------------------------------------------------------
-- Tooltip detection
-- ---------------------------------------------------------------------
local function tooltipText(id)
    HealBot_TooltipInit()
    HealBot_ScanTooltip:SetSpell(id, BOOKTYPE_SPELL)
    local t = ""
    for i = 2, HealBot_ScanTooltip:NumLines() do
        local l = _G["HealBot_ScanTooltipTextLeft"..i]
        if l and l:GetText() then t = t.." "..l:GetText() end
    end
    HealBot_ScanTooltip:ClearLines()
    return strlower(t)
end

local function isHostile(t)
    return strfind(t, "enemy") or strfind(t, "hostile") or strfind(t, "beneficial")
        or strfind(t, "deals ") or strfind(t, "causes %d") or strfind(t, "inflicts")
end

local function detect(t)
    if strfind(t, "back to life") or strfind(t, "resurrect") or strfind(t, "returns the spirit")
       or strfind(t, "brings a dead") or strfind(t, "revives? .*dead") then
        return { kind="res" }
    end
    if not isHostile(t) and (strfind(t, "remove") or strfind(t, "dispel") or strfind(t, "cleanse")
       or strfind(t, "cure") or strfind(t, "purif")) then
        local types = nil
        for _, w in ipairs(TYPES) do
            if strfind(t, strlower(w)) then
                types = types or {}
                types[w] = true
            end
        end
        if types then return { kind="dispel", types=types } end
    end
    if strfind(t, "absorb") and strfind(t, "damage") and not isHostile(t) then return { kind="hot" } end
    if not isHostile(t) then
        if (strfind(t, "heal") or strfind(t, "restor")) and strfind(t, "over %d+") then return { kind="hot" } end
        if strfind(t, "health") and strfind(t, "every %d+") then return { kind="hot" } end
        if strfind(t, "for %d+ min") or strfind(t, "for 1 hour") or strfind(t, "for %d+ hours?") then
            return { kind="buff" }
        end
    end
    return nil
end

local function typeList(set)
    local r = {}
    for _, w in ipairs(TYPES) do if set and set[w] then table.insert(r, w) end end
    return r
end

-- ---------------------------------------------------------------------
-- Scan + apply settings
-- ---------------------------------------------------------------------
function HealBot_Custom_Scan()
    local C = HealBot_Custom
    wipe(C.spells); wipe(C.auto); wipe(C.hots); wipe(C.dispels); wipe(C.buffs)
    C.res = nil; C.scanned = 0

    local key = classKey()
    local isCustom = HealBot_IsBaseClassKey and not HealBot_IsBaseClassKey(key)

    -- all active spells in the spellbook (last rank wins)
    local seen, id = {}, 1
    while true do
        local name = GetSpellName(id, BOOKTYPE_SPELL)
        if not name then break end
        if not IsPassiveSpell(id, BOOKTYPE_SPELL) then
            if not seen[name] then table.insert(C.spells, name) end
            seen[name] = id
        end
        id = id + 1
    end
    table.sort(C.spells)

    -- automatic detection only for custom classes; the original classes keep
    -- HealBot's own spell data (manual settings still work for them)
    if isCustom then
        for name, sid in pairs(seen) do
            C.auto[name] = detect(tooltipText(sid))
            C.scanned = C.scanned + 1
        end
    end

    local manualRes = nil
    for _, name in ipairs(C.spells) do
        local set = getSetting(name)
        local mode = (set and set.mode) or "auto"
        local a = C.auto[name]
        if mode == "auto" then
            if a then
                if a.kind == "hot" then C.hots[name] = "C"
                elseif a.kind == "dispel" then C.dispels[name] = typeList((set and set.types) or a.types)
                elseif a.kind == "buff" then C.buffs[name] = true
                elseif a.kind == "res" and not C.res then C.res = name end
            end
        elseif mode == "hotC" then C.hots[name] = "C"
        elseif mode == "hotA" then C.hots[name] = "A"
        elseif mode == "dispel" then
            local tl = typeList((set and set.types) or (a and a.types))
            if #tl == 0 then tl = { "Magic" } end
            C.dispels[name] = tl
        elseif mode == "buff" then C.buffs[name] = true
        elseif mode == "res" then manualRes = manualRes or name
        end
    end
    if manualRes then C.res = manualRes end

    -- optional file overrides
    local _, token = UnitClass("player")
    for _, k in ipairs({ "*", token, key }) do
        local o = k and HealBot_Custom_Overrides[k]
        if o then
            if o.ignore then for n, v in pairs(o.ignore) do if v then C.hots[n]=nil; C.dispels[n]=nil; C.buffs[n]=nil; if C.res==n then C.res=nil end end end end
            if o.hots then for n, v in pairs(o.hots) do C.hots[n] = v or nil end end
            if o.dispels then for n, v in pairs(o.dispels) do C.dispels[n] = v or nil end end
            if o.buffs then for n, v in pairs(o.buffs) do C.buffs[n] = v or nil end end
            if o.res then C.res = o.res end
        end
    end
end

-- HoT icons: called with HealBot's (local) HoT watch table
local hbAppliedHoTs = {}
function HealBot_Custom_ApplyHoTs(watch)
    if not watch then return end
    for name, mode in pairs(hbAppliedHoTs) do
        if watch[name] == mode then watch[name] = nil end
        hbAppliedHoTs[name] = nil
    end
    for name, mode in pairs(HealBot_Custom.hots) do
        if mode then
            watch[name] = mode
            hbAppliedHoTs[name] = mode
        end
    end
end

local TYPE_CONST = {
    Magic   = function() return HEALBOT_MAGIC_en end,
    Curse   = function() return HEALBOT_CURSE_en end,
    Poison  = function() return HEALBOT_POISON_en end,
    Disease = function() return HEALBOT_DISEASE_en end,
}
function HealBot_Custom_DebuffTypes(sName)
    local types = sName and HealBot_Custom.dispels[sName]
    if not types then return nil end
    local r = {}
    for _, w in ipairs(types) do
        if TYPE_CONST[w] then table.insert(r, TYPE_CONST[w]()) end
    end
    return r
end

function HealBot_Custom_AddToList(list, kind)
    local src = (kind == "dispels" and HealBot_Custom.dispels) or HealBot_Custom.buffs
    local out, have = {}, {}
    for _, v in ipairs(list or {}) do table.insert(out, v); have[v] = true end
    for name in pairs(src) do
        if not have[name] then table.insert(out, name) end
    end
    table.sort(out)
    return out
end

-- Rescan and push the result into HealBot (HoTs, buff/debuff lists, Smart Cast)
function HealBot_Custom_Refresh()
    HealBot_Custom_Scan()
    if HealBot_Custom_ApplyHoTsNow then HealBot_Custom_ApplyHoTsNow() end
    if HealBot_Options_InitBuffClassList then HealBot_Options_InitBuffClassList() end
    if HealBot_setOptions_Timer then
        HealBot_setOptions_Timer(5)    -- buff spell list
        HealBot_setOptions_Timer(40)   -- buff reset
        HealBot_setOptions_Timer(50)   -- debuff reset
    end
    if HealBot_Init_SmartCast then HealBot_Init_SmartCast() end
end

function HealBot_Custom_Report()
    local function names(t)
        local r = {}
        for n, v in pairs(t) do
            if type(v) == "table" then table.insert(r, n.." ("..table.concat(v, "/")..")")
            elseif type(v) == "string" then table.insert(r, n.." ("..v..")")
            else table.insert(r, n) end
        end
        table.sort(r)
        return #r > 0 and table.concat(r, ", ") or "none"
    end
    msg("class settings: "..classKey()..", spells scanned: "..HealBot_Custom.scanned)
    msg("HoTs/shields: "..names(HealBot_Custom.hots))
    msg("Dispels: "..names(HealBot_Custom.dispels))
    msg("Buffs: "..names(HealBot_Custom.buffs))
    msg("Resurrection: "..(HealBot_Custom.res or "none"))
end

-- ---------------------------------------------------------------------
-- Help text (Help button in the window, and Docs\CustomSpells.txt)
-- ---------------------------------------------------------------------
HEALBOT_CUSTOM_HELP = {
    "|cffffd100What is this?|r",
    "HealBot only knows the spells of the 10 original classes. For custom classes "..
    "(e.g. Conquest of Azeroth) and classless characters it reads your spellbook "..
    "tooltips and guesses what each spell is good for. Here you can check the guess "..
    "and change it.",
    " ",
    "|cffffd100Opening the window|r",
    "- Click 'Custom Spells' next to the 'Other' tab of HealBot Options, or",
    "- type /hb cs (also prints the current result to chat).",
    " ",
    "|cffffd100Use as|r  (left-click: next, right-click: previous)",
    "- |cffffffffAuto|r: detected from the tooltip, e.g. 'Auto: HoT'. 'Auto: -' means not used.",
    "- |cffffffffHoT (mine)|r: show an icon on the bars while YOUR cast is active.",
    "- |cffffffffHoT (all)|r: show an icon for anyone's cast of this spell.",
    "- |cffffffffDispel|r: this spell removes debuffs from friends. Tick the types it "..
    "removes: M = Magic, C = Curse, P = Poison, D = Disease.",
    "- |cffffffffBuff|r: long buff; appears in Options > Buffs, so HealBot can warn when it is missing.",
    "- |cffffffffResurrect|r: used by Smart Cast on dead players.",
    "- |cffffffffIgnore|r: HealBot never uses this spell.",
    " ",
    "|cffffd100After setting a spell|r",
    "- Dispels: pick the spell in Options > Debuffs (Cure spell 1-3).",
    "- Buffs: pick the spell in Options > Buffs.",
    "- Healing on click: type the spell name in Options > Spells (any spellbook spell or macro works).",
    " ",
    "|cffffd100Good to know|r",
    "- Changes apply at once, no reload needed.",
    "- Settings are saved per class AND realm, so your CoA and classless characters don't mix.",
    "- Hover a spell name to see its tooltip.",
    "- 'Rescan' re-reads the spellbook (e.g. after learning new spells).",
    "- 'Reset all to Auto' clears your settings for this class.",
    "- The original 10 classes are not auto-detected; manual settings still work for them.",
}

-- ---------------------------------------------------------------------
-- "Custom Spells" window
-- ---------------------------------------------------------------------
local ROWS, ROW_H = 16, 22
local frame, rows, scroll, helpFrame

local function toggleHelp()
    if not helpFrame then
        helpFrame = CreateFrame("Frame", "HealBot_CustomSpellsHelp", frame)
        helpFrame:SetWidth(360); helpFrame:SetHeight(frame:GetHeight())
        helpFrame:SetPoint("TOPLEFT", frame, "TOPRIGHT", -4, 0)
        helpFrame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
        local t = helpFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        t:SetPoint("TOP", 0, -16); t:SetText("How to use")
        local body = helpFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        body:SetPoint("TOPLEFT", 20, -42)
        body:SetWidth(320)
        body:SetJustifyH("LEFT"); body:SetJustifyV("TOP")
        body:SetText(table.concat(HEALBOT_CUSTOM_HELP, "\n"))
        helpFrame:SetHeight(math.max(frame:GetHeight(), body:GetHeight() + 60))
        helpFrame:Hide()
    end
    if helpFrame:IsShown() then helpFrame:Hide() else helpFrame:Show() end
end

local function modeIndex(mode)
    for i, m in ipairs(MODES) do if m == mode then return i end end
    return 1
end

local function rowMode(name)
    local s = getSetting(name)
    return (s and s.mode) or "auto"
end

local function effectiveTypes(name)
    local s = getSetting(name)
    if s and s.types then return s.types end
    local a = HealBot_Custom.auto[name]
    return (a and a.types) or {}
end

local function modeText(name)
    local mode = rowMode(name)
    if mode == "auto" then
        local a = HealBot_Custom.auto[name]
        if a then return "Auto: "..KIND_LABEL[a.kind] end
        return "Auto: -"
    end
    return MODE_LABEL[mode]
end

local function isDispelRow(name)
    local mode = rowMode(name)
    if mode == "dispel" then return true end
    if mode == "auto" then
        local a = HealBot_Custom.auto[name]
        return a and a.kind == "dispel"
    end
    return false
end

local function updateList()
    if not frame or not frame:IsShown() then return end
    local list = HealBot_Custom.spells
    FauxScrollFrame_Update(scroll, #list, ROWS, ROW_H)
    local offset = FauxScrollFrame_GetOffset(scroll)
    for i = 1, ROWS do
        local r = rows[i]
        local name = list[i + offset]
        r.name = name
        if name then
            r.text:SetText(name)
            r.mode:SetText(modeText(name))
            local show = isDispelRow(name)
            local types = effectiveTypes(name)
            for j, w in ipairs(TYPES) do
                r.types[j]:SetChecked(types[w] and true or false)
                if show then r.types[j]:Show() else r.types[j]:Hide() end
            end
            r:Show()
        else
            r:Hide()
        end
    end
    frame.info:SetText("Class: "..classKey().."   |   Spells: "..#list)
end

local function changed()
    HealBot_Custom_Refresh()
    updateList()
end

local function createFrame()
    frame = CreateFrame("Frame", "HealBot_CustomSpellsFrame", UIParent)
    frame:SetWidth(470); frame:SetHeight(ROWS * ROW_H + 120)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetMovable(true); frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    frame:SetPoint("CENTER")
    frame:Hide()
    table.insert(UISpecialFrames, "HealBot_CustomSpellsFrame")  -- close with Escape

    local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("HealBot - Custom Spells")

    frame.info = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    frame.info:SetPoint("TOP", 0, -38)

    local h1 = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    h1:SetPoint("TOPLEFT", 24, -58); h1:SetText("Spell")
    local h2 = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    h2:SetPoint("TOPLEFT", 222, -58); h2:SetText("Use as")
    -- one letter above each dispel checkbox (Magic, Curse, Poison, Disease)
    for j, w in ipairs(TYPES) do
        local h = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        h:SetPoint("TOP", frame, "TOPLEFT", 20 + 318 + (j - 1) * 22 + 11, -58)
        h:SetText(strsub(w, 1, 1))
    end

    scroll = CreateFrame("ScrollFrame", "HealBot_CustomSpellsScroll", frame, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 16, -74)
    scroll:SetPoint("BOTTOMRIGHT", -38, 46)
    scroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H, updateList)
    end)

    rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Frame", nil, frame)
        r:SetHeight(ROW_H); r:SetWidth(400)
        r:SetPoint("TOPLEFT", 20, -74 - (i - 1) * ROW_H)

        r.text = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        r.text:SetPoint("LEFT", 4, 0); r.text:SetWidth(190); r.text:SetJustifyH("LEFT")

        r.mode = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
        r.mode:SetWidth(118); r.mode:SetHeight(20)
        r.mode:SetPoint("LEFT", 196, 0)
        r.mode:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        r.mode:SetScript("OnClick", function(self, button)
            local name = r.name
            if not name then return end
            local i2 = modeIndex(rowMode(name)) + ((button == "RightButton") and -1 or 1)
            if i2 > #MODES then i2 = 1 elseif i2 < 1 then i2 = #MODES end
            local s = getSetting(name)
            setSetting(name, MODES[i2], s and s.types)
            changed()
        end)
        r.mode:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Use as")
            GameTooltip:AddLine("Left-click: next   Right-click: previous", 1, 1, 1)
            GameTooltip:AddLine("Auto = detected from the spell tooltip", 1, 1, 1)
            GameTooltip:Show()
        end)
        r.mode:SetScript("OnLeave", function() GameTooltip:Hide() end)

        r.types = {}
        for j, w in ipairs(TYPES) do
            local cb = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
            cb:SetWidth(22); cb:SetHeight(22)
            cb:SetPoint("LEFT", 318 + (j - 1) * 22, 0)
            cb:SetScript("OnClick", function(self)
                local name = r.name
                if not name then return end
                local t = {}
                for k, v in pairs(effectiveTypes(name)) do t[k] = v end
                t[w] = self:GetChecked() and true or nil
                setSetting(name, rowMode(name), t)
                changed()
            end)
            cb:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine("Removes "..w)
                GameTooltip:Show()
            end)
            cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
            r.types[j] = cb
        end

        -- spell tooltip on the name
        r:EnableMouse(true)
        r:SetScript("OnEnter", function(self)
            if not self.name then return end
            local sid = HealBot_GetSpellId(self.name)
            if sid then
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                GameTooltip:SetSpell(sid, BOOKTYPE_SPELL)
                GameTooltip:Show()
            end
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        rows[i] = r
    end

    local close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    close:SetWidth(90); close:SetHeight(22)
    close:SetPoint("BOTTOMRIGHT", -20, 16)
    close:SetText("Close")
    close:SetScript("OnClick", function() frame:Hide() end)

    local rescan = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    rescan:SetWidth(90); rescan:SetHeight(22)
    rescan:SetPoint("RIGHT", close, "LEFT", -6, 0)
    rescan:SetText("Rescan")
    rescan:SetScript("OnClick", function() changed(); HealBot_Custom_Report() end)

    local help = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    help:SetWidth(60); help:SetHeight(22)
    help:SetPoint("RIGHT", rescan, "LEFT", -6, 0)
    help:SetText("Help")
    help:SetScript("OnClick", toggleHelp)

    local reset = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    reset:SetWidth(110); reset:SetHeight(22)
    reset:SetPoint("BOTTOMLEFT", 20, 16)
    reset:SetText("Reset all to Auto")
    reset:SetScript("OnClick", function()
        if HealBot_Globals and HealBot_Globals.CustomSpells then
            HealBot_Globals.CustomSpells[classKey()] = nil
        end
        changed()
    end)

    frame:SetScript("OnShow", function() HealBot_Custom_Scan(); updateList() end)
end

function HealBot_Custom_Toggle()
    if not frame then createFrame() end
    if frame:IsShown() then
        frame:Hide()
    else
        if HealBot_Options and HealBot_Options:IsShown() then
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", HealBot_Options, "TOPRIGHT", 0, 0)
        end
        frame:Show()
    end
end

-- Button below the HealBot Options window
function HealBot_Custom_CreateOptionsButton()
    if not HealBot_Options or HealBot_Options_CustomSpellsButton then return end
    local b = CreateFrame("Button", "HealBot_Options_CustomSpellsButton", HealBot_Options, "UIPanelButtonTemplate")
    b:SetWidth(56); b:SetHeight(30)
    if HealBot_OptionsTab7 then
        b:SetPoint("LEFT", HealBot_OptionsTab7, "RIGHT", 0, 2)   -- after the "Other" tab
    else
        b:SetPoint("TOPRIGHT", HealBot_Options, "BOTTOMRIGHT", 0, 4)
    end
    b:SetText("Custom\nSpells")
    local fs = b:GetFontString()
    if fs then
        fs:SetFontObject(GameFontNormalSmall)
        fs:SetWidth(52)
    end
    b:SetScript("OnClick", HealBot_Custom_Toggle)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Custom Spells")
        GameTooltip:AddLine("Choose how HealBot uses each spell:", 1, 1, 1)
        GameTooltip:AddLine("HoT, dispel, buff or resurrection.", 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
