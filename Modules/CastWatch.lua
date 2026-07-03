-- Vigil/Modules/CastWatch.lua
--
-- Detects enemy casts and drives the plate cast bar, then hands off to the
-- InterruptCue module for the kick/padlock decision.
--
-- Two detection paths, because the Classic client is inconsistent about exposing
-- enemy cast info:
--   1) UNIT_SPELLCAST_* on the nameplate unit  -> accurate timing via the API.
--   2) CLEU SPELL_CAST_START (always fires)     -> fallback that animates the bar
--      from our Intel Pack's castTime when the API gives us nothing.
-- Path 1 wins when available; path 2 guarantees we never miss a cast outright.
local addonName, Vigil = ...
local M = Vigil:NewModule("CastWatch")

-- ---------------------------------------------------------------------------
-- Path 1: live unit cast info
-- ---------------------------------------------------------------------------
local function startFromAPI(unit)
    local overlay = Vigil.plates[unit]
    if not overlay or not Vigil.db.showCastbar then return false end

    local name, _, texture, startMS, endMS, _, _, _, spellID = UnitCastingInfo(unit)
    local channeling = false
    if not name then
        name, _, texture, startMS, endMS, _, _, spellID = UnitChannelInfo(unit)
        channeling = name ~= nil
    end
    if not name then return false end

    local duration = (endMS - startMS) / 1000
    overlay:ShowCast(name, texture, duration, channeling)
    overlay.active = { name = name, spellID = spellID,
                       info = Vigil.GetKickInfo(name, spellID) }
    Vigil.Cue:Evaluate(overlay, unit, name, overlay.active.info)
    return true
end

-- Re-check a unit (called when its plate first appears, to catch in-progress casts).
function M:Refresh(unit)
    startFromAPI(unit)
end

-- ---------------------------------------------------------------------------
-- Path 2: combat-log fallback
-- ---------------------------------------------------------------------------
local myGUID

local function onCLEU()
    local _, sub, _, srcGUID, _, _, _, dstGUID = CombatLogGetCurrentEventInfo()

    -- YOUR interrupt landing on a cast marked do-not-kick: the padlock's lesson,
    -- delivered at the exact moment it was ignored. (Checked before the caster
    -- lookup below — here the source is you, not the mob.)
    if sub == "SPELL_CAST_SUCCESS" and srcGUID == myGUID then
        local kickName = select(13, CombatLogGetCurrentEventInfo())
        if Vigil.IsMyInterrupt and Vigil:IsMyInterrupt(kickName) then
            local tUnit = Vigil.guidToUnit[dstGUID]
            local tOverlay = tUnit and Vigil.plates[tUnit]
            if tOverlay and tOverlay.active and tOverlay.active.code == "locked" then
                tOverlay:FlashWasted() -- label only; the locked cast is still going
            end
        end
    end

    local unit = Vigil.guidToUnit[srcGUID]
    if not unit then return end
    local overlay = Vigil.plates[unit]
    if not overlay then return end

    if sub == "SPELL_CAST_START" then
        -- if a bar is already running (live API beat us here), don't double up
        if overlay.active then return end
        if not Vigil.db.showCastbar then return end
        local spellID, spellName = select(12, CombatLogGetCurrentEventInfo())
        local info = Vigil.GetKickInfo(spellName, spellID)
        local castTime = (info and info.castTime and info.castTime > 0) and info.castTime or 2.0
        local _, _, icon = GetSpellInfo(spellID)
        overlay:ShowCast(spellName, icon, castTime, false)
        overlay.active = { name = spellName, spellID = spellID, info = info }
        Vigil.Cue:Evaluate(overlay, unit, spellName, info)

    elseif sub == "SPELL_INTERRUPT" then
        -- somebody stopped it (you or a groupmate): the win flash
        if overlay.active then
            overlay:FlashOutcome("kicked", "KICKED")
        end

    elseif sub == "SPELL_CAST_SUCCESS" then
        if overlay.active and not overlay.castbar.channeling then
            local spellName = select(13, CombatLogGetCurrentEventInfo())
            if spellName == overlay.active.name then
                if overlay.active.code == "ready" then
                    -- it completed while your stop sat ready — the stat this
                    -- addon exists to drive down, called out in the moment
                    overlay:FlashOutcome("missed", "MISSED")
                else
                    overlay:Reset()
                end
            end
            -- a DIFFERENT spell succeeding mid-cast is an instant proc, not this
            -- cast resolving — leave the bar alone (it self-expires on time)
        end

    elseif sub == "SPELL_CAST_FAILED" then
        if overlay.active and not overlay.castbar.channeling then
            overlay:Reset()
        end
    end
end

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------
local function unitEvent(_, unit)
    if Vigil.plates[unit] then startFromAPI(unit) end
end

local function unitStop(_, unit)
    local overlay = Vigil.plates[unit]
    if overlay and overlay.active then overlay:Reset() end
end

local function unitInterrupted(_, unit)
    local overlay = Vigil.plates[unit]
    if overlay and overlay.active then overlay:FlashOutcome("kicked", "KICKED") end
end

local function unitSucceeded(_, unit, _, spellID)
    local overlay = Vigil.plates[unit]
    local a = overlay and overlay.active
    if not a then return end
    -- SUCCEEDED fires for the mob's instants too; only resolve OUR tracked cast
    if spellID and a.spellID then
        if spellID ~= a.spellID then return end
    elseif spellID and a.name then
        local n = GetSpellInfo(spellID)
        if n and n ~= a.name then return end
    end
    if a.code == "ready" and not overlay.castbar.channeling then
        overlay:FlashOutcome("missed", "MISSED")
    else
        overlay:Reset()
    end
end

function M:OnEnable()
    myGUID = UnitGUID("player")

    -- Path 1 (best-effort; harmless if the client doesn't fire these for plates)
    Vigil:RegisterEvent("UNIT_SPELLCAST_START",         unitEvent)
    Vigil:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START", unitEvent)
    Vigil:RegisterEvent("UNIT_SPELLCAST_STOP",          unitStop)
    Vigil:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP",  unitStop)
    Vigil:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED",   unitInterrupted)
    Vigil:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED",     unitSucceeded)

    -- Path 2 (the reliable backbone)
    Vigil:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED",  onCLEU)
end

Vigil.CastWatch = M
