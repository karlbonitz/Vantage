-- Vigil/Modules/Parse.lua
--
-- VIGIL PARSE, phase 1: the in-game collector. Every enemy-cast decision the
-- cue engine makes becomes a row, and combat-log outcomes attach to it:
--
--   row = { t (epoch), z (zone), src (caster), sp/sid (spell), pvp,
--           tier ("ready"/"cd"/"aware"/"locked"/"unknown"),
--           win  (a kick window was shown to you),
--           tool (the interrupt Vigil offered),
--           out  ("int" interrupted / "done" completed / "stop" fizzled / nil open),
--           by   ("me"/"other", for out=="int"),
--           rx   (ms from cue shown -> YOUR interrupt landing),
--           miss (completed while your stop was ready — the headline stat),
--           wk   (you kicked a cast marked uninterruptible) }
--
-- This is the data Warcraft Logs can't show: not "how many interrupts did you
-- cast" but "how many casts did you LET THROUGH while your kick sat ready".
--
-- Storage: VigilParseDB.sessions (SavedVariables — flushes to disk on logout
-- or /reload). One session per login, oldest sessions pruned. Read-only and
-- cheap: rows only exist for casts Vigil already evaluated on visible plates.
local addonName, Vigil = ...
local M = Vigil:NewModule("Parse")

local MAX_SESSIONS = 8     -- keep this many sessions in SavedVariables
local MAX_ROWS     = 4000  -- per-session row cap (then stop logging, count drops)

local session              -- current session (last entry in VigilParseDB.sessions)
local openByGuid = {}      -- srcGUID -> its one in-flight row
local myGUID
local myInterruptNames = {}
local zone = ""

-- ---------------------------------------------------------------------------
-- Row lifecycle
-- ---------------------------------------------------------------------------
local function finish(row, out, by, rx)
    if row.out then return end
    row.out = out
    if by then row.by = by end
    if rx then row.rx = rx end
    if out == "done" and row.readyAt then row.miss = true end
    row.readyAt = nil -- transient (GetTime-based); never useful after close
end

local function closeGuid(guid, out, by, rx)
    local row = guid and openByGuid[guid]
    if not row then return end
    finish(row, out, by, rx)
    openByGuid[guid] = nil
end

local function pushRow(row)
    local rows = session.rows
    if #rows >= MAX_ROWS then
        session.counters.dropped = session.counters.dropped + 1
        if session.counters.dropped == 1 then
            Vigil:Print("Parse: session log is full — new casts won't be recorded until next login.")
        end
        return false
    end
    rows[#rows + 1] = row
    return true
end

-- Called by InterruptCue for every evaluated cast; re-evaluations (cooldown
-- changes mid-cast) update the SAME row via overlay.active.__prow.
function M:OnDecision(overlay, unit, spellName, code, readyEntry)
    if not (Vigil.db.parse and session) then return end
    local a = overlay.active
    if not a then return end -- demo casts have no active record; don't log them

    local guid = overlay.guid
    local row = a.__prow
    if not row then
        closeGuid(guid, "?") -- a stale open cast from this mob can't resolve now
        row = {
            t    = time(),
            z    = zone,
            src  = (unit and UnitName(unit)) or "?",
            sp   = spellName,
            sid  = a.spellID,
            pvp  = (unit and UnitIsPlayer(unit)) and true or nil,
            tier = code,
        }
        if not pushRow(row) then return end
        a.__prow = row
        if guid then openByGuid[guid] = row end
    else
        row.tier = code
    end

    if code == "ready" then
        row.win = true
        row.tool = (readyEntry and (readyEntry.label or readyEntry.spell)) or row.tool
        if not row.readyAt then row.readyAt = GetTime() end
    end
end

-- ---------------------------------------------------------------------------
-- Outcomes from the combat log
-- ---------------------------------------------------------------------------
local function onCLEU()
    if not (Vigil.db.parse and session) then return end
    local _, sub, _, srcGUID, _, _, _, dstGUID = CombatLogGetCurrentEventInfo()

    if sub == "SPELL_INTERRUPT" then
        local row = openByGuid[dstGUID]
        if row then
            local by = (srcGUID == myGUID) and "me" or "other"
            local rx
            if by == "me" and row.readyAt then
                rx = math.floor((GetTime() - row.readyAt) * 1000)
            end
            finish(row, "int", by, rx)
            openByGuid[dstGUID] = nil
        end
        if srcGUID == myGUID then
            session.counters.myInterrupts = session.counters.myInterrupts + 1
        end

    elseif sub == "SPELL_CAST_SUCCESS" then
        local spellName = select(13, CombatLogGetCurrentEventInfo())
        local row = openByGuid[srcGUID]
        if row and row.sp == spellName then
            finish(row, "done")
            openByGuid[srcGUID] = nil
        end
        if srcGUID == myGUID and myInterruptNames[spellName] then
            session.counters.kickCasts = session.counters.kickCasts + 1
            local tr = openByGuid[dstGUID]
            if tr and tr.tier == "locked" then
                session.counters.wastedKicks = session.counters.wastedKicks + 1
                tr.wk = true
            end
        end

    elseif sub == "SPELL_CAST_FAILED" then
        closeGuid(srcGUID, "stop")

    elseif sub == "UNIT_DIED" then
        closeGuid(dstGUID, "stop")
    end
end

-- ---------------------------------------------------------------------------
-- Session summary (chat): /vigil parse
-- ---------------------------------------------------------------------------
function M:Summary()
    if not session then
        Vigil:Print("Parse: no session data yet.")
        return
    end
    local rows = session.rows
    local windows, intMe, intOther, thru, rxSum, rxN = 0, 0, 0, 0, 0, 0
    for i = 1, #rows do
        local r = rows[i]
        if r.win then windows = windows + 1 end
        if r.out == "int" then
            if r.by == "me" then intMe = intMe + 1 else intOther = intOther + 1 end
        end
        if r.miss then thru = thru + 1 end
        if r.rx then rxSum = rxSum + r.rx; rxN = rxN + 1 end
    end
    local c = session.counters
    Vigil:Print("Parse — this session:")
    print(("  enemy casts logged: |cffffffff%d|r%s"):format(#rows,
        c.dropped > 0 and (" (|cffff4444%d dropped, log full|r)"):format(c.dropped) or ""))
    print(("  kick windows shown to you: |cffffd100%d|r"):format(windows))
    print(("  interrupted by you: |cff44ff44%d|r   by others: %d"):format(intMe, intOther))
    print(("  |cffff4444let through while your stop was ready: %d|r"):format(thru))
    if rxN > 0 then
        print(("  avg reaction (cue -> your interrupt): |cffffffff%d ms|r over %d"):format(
            math.floor(rxSum / rxN + 0.5), rxN))
    end
    print(("  your interrupt casts: %d   wasted on uninterruptible casts: %d")
        :format(c.kickCasts, c.wastedKicks))
    print("  |cffffd100/vigil export|r — copy this data into the web report")
end

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------
function M:OnEnable()
    VigilParseDB = VigilParseDB or {}
    VigilParseDB.sessions = VigilParseDB.sessions or {}

    myGUID = UnitGUID("player")
    local list = Vigil.ClassInterrupts and Vigil.ClassInterrupts[Vigil.playerClass]
    if list then
        for i = 1, #list do myInterruptNames[list[i].spell] = true end
    end

    local _, class = UnitClass("player")
    session = {
        meta = {
            player = UnitName("player"),
            realm  = GetRealmName(),
            class  = class,
            addon  = Vigil.version,
            start  = time(),
        },
        counters = { kickCasts = 0, myInterrupts = 0, wastedKicks = 0, dropped = 0 },
        rows = {},
    }
    table.insert(VigilParseDB.sessions, session)
    while #VigilParseDB.sessions > MAX_SESSIONS do
        table.remove(VigilParseDB.sessions, 1)
    end

    local function updateZone()
        zone = GetRealZoneText() or GetZoneText() or ""
    end
    updateZone()
    Vigil:RegisterEvent("ZONE_CHANGED_NEW_AREA", updateZone)
    Vigil:RegisterEvent("PLAYER_ENTERING_WORLD", updateZone)

    Vigil:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", onCLEU)

    -- casts still open when the world unloads can never resolve
    Vigil:RegisterEvent("PLAYER_LEAVING_WORLD", function()
        for guid in pairs(openByGuid) do closeGuid(guid, "?") end
    end)
end

Vigil.Parse = M
