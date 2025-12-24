local _, L = ...

--- CONSTANTS & LOCALS ---

local DruidMacroHelper = LibStub("AceAddon-3.0"):NewAddon("DruidMacroHelper", "AceEvent-3.0")
local LibClassicSwingTimerAPI = LibStub("LibClassicSwingTimerAPI", true)

local tremove, tinsert, tContains = table.remove, table.insert, tContains
local strlower, strsplit, unpack = string.lower, strsplit, unpack
local GetTime, SetCVar, GetCVar = GetTime, SetCVar, GetCVar
local UnitExists, UnitIsPlayer, UnitName = UnitExists, UnitIsPlayer, UnitName
local GetSpellCooldown, IsSpellInRange = GetSpellCooldown, IsSpellInRange

local SPELL_ID_CAT_FORM = 768
local SPELL_ID_SHOCK_BLAST = 38509
local PET_ID_ALBINO_SNAKE = 7561

local LOC_IGNORED = { "SCHOOL_INTERRUPT", "DISARM", "PACIFYSILENCE", "SILENCE", "PACIFY" }
local LOC_SHIFTABLE = { "ROOT" }
local LOC_STUN = { "STUN", "STUN_MECHANIC", "FEAR", "CHARM", "CONFUSE", "POSSESS" }

--- INITIALIZATION ---

function DruidMacroHelper:OnEnable()
    self:RegisterItemShortcut("pot", 13446)
    self:RegisterItemShortcut("potion", 13446)
    self:RegisterItemShortcut("hs", 20520)
    self:RegisterItemShortcut("rune", 20520)
    self:RegisterItemShortcut("seed", 20520)
    self:RegisterItemShortcut("sapper", 10646)
    self:RegisterItemShortcut("supersapper", 23827)
    self:RegisterItemShortcut("drums", 13180)
    self:RegisterItemShortcut("holywater", 13180)

    self:RegisterSlashCommand("/dmh")
    self:RegisterSlashCommand("/druidmacro")

    self:RegisterSlashAction('help', 'OnSlashHelp', 'Show list of slash actions')
    self:RegisterSlashAction('start', 'OnSlashStart', 'Disable autoUnshift if player is stunned, on gcd or out of mana')
    self:RegisterSlashAction('end', 'OnSlashEnd', 'Enable autoUnshift again')
    self:RegisterSlashAction('stun', 'OnSlashStun', 'Disable autoUnshift if stunned')
    self:RegisterSlashAction('gcd', 'OnSlashGcd', 'Disable autoUnshift if on global cooldown')
    self:RegisterSlashAction('mana', 'OnSlashMana', 'Disable autoUnshift if you are missing mana to shift back into form')
    self:RegisterSlashAction('cd', 'OnSlashCooldown', 'Disable autoUnshift if items are on cooldown')
    self:RegisterSlashAction('charge', 'OnSlashCharge', 'Disable autoUnshift if unit is in range of Feral Charge')
    self:RegisterSlashAction('innervate', 'OnSlashInnervate', 'Cast Innervate on unit and whisper')
    self:RegisterSlashAction('debug', 'OnSlashDebug', 'Toggle debug output')
    self:RegisterSlashAction('maul', 'OnSlashMaul', 'Disable autoUnshift if you have Maul queued')
    self:RegisterSlashAction('snake', 'OnSlashSnake', 'Use Albino Snake to clip swing timer')
    self:RegisterSlashAction('snek', 'OnSlashSnake', 'Use Albino Snake (alias)')
    self:RegisterSlashAction('dismiss', 'OnSlashDismiss', 'Dismiss Albino Snake')

    self:CreateButton('dmhStart', '/changeactionbar [noform]1;[form:1]2;[form:3]3;[form:4]4;[form:5]5;6;\n/dmh start', 'Change actionbar based on current form (includes /dmh start)')
    self:CreateButton('dmhBar', '/changeactionbar [noform]1;[form:1]2;[form:3]3;[form:4]4;[form:5]5;6;', 'Change actionbar based on current form')
    self:CreateButton('dmhReset', '/changeactionbar 1', 'Change actionbar back to 1')
    self:CreateButton('dmhEnd', '/use [bar:2]!'..L["FORM_DIRE_BEAR"]..';[bar:3]!'..L["FORM_CAT"]..';[bar:4]!'..L["FORM_TRAVEL"]..'\n/click dmhReset\n/dmh end', 'Change back to form based on current bar (includes /dmh end)')
    
    self:CreateButton('dmhPot', '/dmh cd pot\n/dmh start', 'Disable autoUnshift if not ready to use potion')
    self:CreateButton('dmhHs', '/dmh cd hs\n/dmh start', 'Disable autoUnshift if not ready to use healthstone')
    self:CreateButton('dmhSap', '/dmh cd sapper\n/dmh start', 'Disable autoUnshift if not ready to use sapper')
    self:CreateButton('dmhSuperSap', '/dmh cd supersapper\n/dmh start', 'Disable autoUnshift if not ready to use super sapper')

    self.ChatThrottle = nil
    self.SpellQueueWindow = 400
    self.AutoUnsnake = false
end

--- SLASH COMMAND SYSTEM ---

function DruidMacroHelper:RegisterSlashCommand(cmd)
    if not self.slashCommands then
        self.slashCommands = {}
        SlashCmdList["DRUID_MACRO_HELPER"] = function(parameters)
            if (parameters == "") then parameters = "help" end
            DruidMacroHelper:OnSlashCommand({ strsplit(" ", parameters) })
        end
    end
    if not tContains(self.slashCommands, cmd) then
        local index = #(self.slashCommands) + 1
        tinsert(self.slashCommands, cmd)
        _G["SLASH_DRUID_MACRO_HELPER"..index] = cmd
    end
end

function DruidMacroHelper:RegisterSlashAction(action, callback, description)
    if (type(callback) ~= "function") and (type(callback) ~= "string") then
        self:LogOutput("Invalid callback for slash action:", action)
        return
    end
    if not self.slashActions then self.slashActions = {} end
    self.slashActions[action] = { ["callback"] = callback, ["description"] = description or "No description" }
end

function DruidMacroHelper:OnSlashCommand(parameters)
    if not self.slashActions then
        self:LogOutput("No slash actions registered!")
        return
    end
    self:LogDebug("Slash command called: ", unpack(parameters))
    
    while (#(parameters) > 0) do
        local action = tremove(parameters, 1)
        if not self.slashActions[action] then
            self:LogOutput("Slash action |cffffff00"..action.."|r not found!")
        else
            local actionData = self.slashActions[action]
            if type(actionData.callback) == "function" then
                actionData.callback(parameters)
            else
                self[actionData.callback](self, parameters)
            end
        end
    end
end

--- SLASH HANDLERS ---

function DruidMacroHelper:OnSlashHelp(parameters)
    if (#(parameters) > 0) then
        local action = tremove(parameters, 1)
        if not self.slashActions[action] then
            self:LogOutput("Slash action |cffffff00"..action.."|r not found!")
        else
            self:LogOutput("|cffffff00"..action.."|r", self.slashActions[action].description)
        end
    else
        self:LogOutput("Available slash commands:")
        for action in pairs(self.slashActions) do
            self:LogOutput("|cffffff00/dmh "..action.."|r", self.slashActions[action].description)
        end
        self:LogOutput("Available buttons:")
        for btnName in pairs(self.buttons) do
            self:LogOutput("|cffffff00/click "..btnName.."|r", self.buttons[btnName])
        end
    end
end

function DruidMacroHelper:OnSlashStart(parameters)
    self:OnSlashStun(parameters)
    self:OnSlashGcd(parameters)
    self:OnSlashMana(parameters)
    self:OnSlashCooldown(parameters)
    self:LogDebug("Setting SpellQueueWindow to 0")
    self.SpellQueueWindow = GetCVar("SpellQueueWindow")
    SetCVar("SpellQueueWindow", 0)
end

function DruidMacroHelper:OnSlashEnd(parameters)
    self:LogDebug("Enabling autoUnshift again...")
    SetCVar("autoUnshift", 1)
    self:LogDebug("Resetting SpellQueueWindow to " .. (self.SpellQueueWindow or 400))
    SetCVar("SpellQueueWindow", self.SpellQueueWindow or 400)
end

function DruidMacroHelper:OnSlashStun(parameters)
    if self:IsStunned() then
        self:LogDebug("You are stunned")
        SetCVar("autoUnshift", 0)
    end
end

function DruidMacroHelper:OnSlashGcd(parameters)
    if (GetSpellCooldown(SPELL_ID_CAT_FORM) > 0) then
        self:LogDebug("You are on global cooldown")
        SetCVar("autoUnshift", 0)
    end
end

function DruidMacroHelper:OnSlashMana(parameters)
    local manaCost = 580
    local manaCostTable = GetSpellPowerCost(SPELL_ID_CAT_FORM)
    if (manaCostTable) then
        for i in ipairs(manaCostTable) do
            if (manaCostTable[i].type == 0) then
                manaCost = manaCostTable[i].cost
            end
        end
    end
    if (UnitPower("player", 0) < manaCost) then
        self:LogDebug("You missing mana to shift back into form")
        SetCVar("autoUnshift", 0)
    end
end

function DruidMacroHelper:OnSlashMaul(parameters)
    if (IsCurrentSpell(GetSpellLink("Maul")[2]) and IsSpellInRange("Bash", "target") == 1) then
        self:LogDebug("You have Maul queued")
        SetCVar("autoUnshift", 0)
    end
end

function DruidMacroHelper:OnSlashCooldown(parameters)
    local prevent = false
    while (#(parameters) > 0) do
        local itemNameOrId = tremove(parameters, 1)
        if self:IsItemOnCooldown(itemNameOrId) then
            self:LogDebug("Item on cooldown: ", itemNameOrId)
            prevent = true
        end
    end
    if prevent then SetCVar("autoUnshift", 0) end
end

function DruidMacroHelper:OnSlashSnake(parameters)
    if GetCVar("autoUnshift") == "1" then
        if LibClassicSwingTimerAPI == nil then
            self:LogDebug("LibClassicSwingTimerAPI not installed, snaking naively")
            self:SnakeHelper(parameters)
        else
            local _, next_auto = LibClassicSwingTimerAPI:SwingTimerInfo("mainhand")
            local time_till_next_auto = next_auto - GetTime()
            if time_till_next_auto > (1 / (1 + GetMeleeHaste() / 100)) then
                self:LogDebug("Summoning snake to clip next swing down from", time_till_next_auto)
                self:SnakeHelper(parameters)
            else
                self:LogDebug("Your swing timer is less than 1, did not snake:", time_till_next_auto)
            end
        end
    end
    if (#(parameters) > 0) then tremove(parameters, 1) end
end

function DruidMacroHelper:OnSlashDismiss(parameters)
    self:LogDebug("Dismissed our snake if they were out")
    DismissCompanion("CRITTER")
end

function DruidMacroHelper:OnSlashCharge(parameters)
    local unit = (#(parameters) > 0) and tremove(parameters, 1) or "target"
    if not UnitExists(unit) then
        self:LogOutput("Unit not found:", unit)
        return
    end

    local prevent = false
    local range = IsSpellInRange(L["SPELL_CHARGE"], unit)
    if not range or (range == 0) then prevent = true end
    
    local _, duration = GetSpellCooldown(L["SPELL_CHARGE"])
    if duration > 0 then prevent = true end

    if prevent then SetCVar("autoUnshift", 0) end
end

function DruidMacroHelper:OnSlashInnervate(unitIds)
    local unit = (#(unitIds) > 0) and tremove(unitIds, 1) or "target"
    if not UnitExists(unit) or UnitIsEnemy(unit, "player") then
        if (#(unitIds) > 0) then
            self:OnSlashInnervate(unitIds)
        else
            self:LogOutput("Unit not found:", unit)
        end
        return
    end

    local prevent = false
    local start, duration = GetSpellCooldown(L["SPELL_INNERVATE"])
    
    if duration > 0 then
        if (duration > 1) then
            local durationLeft = ceil(duration - (GetTime() - start))
            self:ChatMessageThrottleUnit(L["NOTIFY_INNERVATE_COOLDOWN"].." ("..durationLeft.."s)", unit)
        end
        prevent = true
    end

    local range = IsSpellInRange(L["SPELL_INNERVATE"], unit)
    if not range or (range == 0) then
        if not prevent then
            self:ChatMessageThrottleUnit(L["NOTIFY_INNERVATE_RANGE"], unit)
        end
        prevent = true
    end

    if prevent then
        SetCVar("autoUnshift", 0)
    else
        self:ChatMessageThrottleUnit(L["NOTIFY_INNERVATE"], unit)
    end
    wipe(unitIds)
end

function DruidMacroHelper:OnSlashDebug(parameters)
    if (#(parameters) > 0) then
        self.debug = (tremove(parameters, 1) == "on")
    else
        self.debug = not self.debug
    end
    self:LogOutput("Debug output " .. (self.debug and "enabled" or "disabled"))
end

--- LOGIC & UTILITIES ---

function DruidMacroHelper:IsStunned()
    local i = C_LossOfControl.GetActiveLossOfControlDataCount()
    while (i > 0) do
        local locData = C_LossOfControl.GetActiveLossOfControlData(i)
        if (tContains(LOC_STUN, locData.locType)) then return true end
        i = i - 1
    end

    local GetDebuffData = C_UnitAuras and C_UnitAuras.GetDebuffDataByIndex or UnitDebuff
    i = 40
    while (i > 0) do
        local result = GetDebuffData("player", i) 
        -- Classic Era wrapper vs Modern compatibility
        local spellId
        if type(result) == "table" then spellId = result.spellId else _,_,_,_,_,_,_,_,_,spellId = UnitDebuff("player", i) end
        
        if spellId == SPELL_ID_SHOCK_BLAST then return true end
        i = i - 1
    end
    return false
end

function DruidMacroHelper:IsShiftableCC()
    if self:IsStunned() then return false end
    
    local _, _, playerSpeed = GetUnitSpeed("player")
    local playerSpeedNormal = IsStealthed() and 4.9 or 7
    if (playerSpeed < playerSpeedNormal) then return true end
    
    local i = C_LossOfControl.GetActiveLossOfControlDataCount()
    while (i > 0) do
        local locData = C_LossOfControl.GetActiveLossOfControlData(i)
        if (tContains(LOC_SHIFTABLE, locData.locType)) then return true end
        i = i - 1
    end
    return false
end

function DruidMacroHelper:SnakeHelper(parameters)
    for i=1, GetNumCompanions("CRITTER") do
        if select(1, GetCompanionInfo("CRITTER", i)) == PET_ID_ALBINO_SNAKE then
            CallCompanion("CRITTER", i)
            C_Timer.After(2, function() DismissCompanion("CRITTER") end)
            return
        end
    end
    self:LogOutput("This character has not learned the Albino Snake pet.")
end

function DruidMacroHelper:IsItemOnCooldown(itemNameOrId)
    local itemId = itemNameOrId
    itemNameOrId = strlower(itemNameOrId)
    if self.itemShortcuts and self.itemShortcuts[itemNameOrId] then
        itemId = self.itemShortcuts[itemNameOrId]
    end
    
    if C_Container and C_Container.GetItemCooldown then
        return (C_Container.GetItemCooldown(itemId) > 0)
    else
        return (GetItemCooldown(itemId) > 0)
    end
end

function DruidMacroHelper:ChatMessageThrottle(message, chatType, language, channel)
    if (self.ChatThrottle ~= nil) and (self.ChatThrottle > GetTime()) then
        self:LogDebug("Chat throttled!", self.ChatThrottle, GetTime())
        return
    end
    self.ChatThrottle = GetTime() + 2.0
    SendChatMessage(message, chatType, language, channel)
end

function DruidMacroHelper:ChatMessageThrottleUnit(message, unit)
    if UnitExists(unit) and UnitIsPlayer(unit) then
        local name, realm = UnitName(unit)
        if (realm ~= nil) and (realm ~= "") then name = name.."-"..realm end
        self:ChatMessageThrottle(message, "WHISPER", nil, name)
    end
end

function DruidMacroHelper:LogOutput(...)
    print("|cffff0000DMH|r", ...)
end

function DruidMacroHelper:LogDebug(...)
    if self.debug then print("|cffff0000DMH|r", "|cffffff00Debug|r", ...) end
end

--- BUTTON & MACRO MANAGEMENT ---

function DruidMacroHelper:CreateButton(name, macrotext, description)
    local b = _G[name] or CreateFrame('Button', name, nil, 'SecureActionButtonTemplate,SecureHandlerBaseTemplate')
    b:SetAttribute('type', 'macro')
    b:SetAttribute('macrotext', macrotext)
    if not self.buttons then self.buttons = {} end
    self.buttons[name] = description or "No description available"
end

function DruidMacroHelper:RegisterCondition(shortcut, itemId)
    self:RegisterItemShortcut(shortcut, itemId)
end

function DruidMacroHelper:RegisterItemShortcut(shortcut, itemId)
    if not self.itemShortcuts then self.itemShortcuts = {} end
    self.itemShortcuts[shortcut] = itemId
end
