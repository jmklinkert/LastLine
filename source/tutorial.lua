import "CoreLibs/graphics"
import "field"

local gfx = playdate.graphics

-- Interactive, guided tutorial. It runs on top of the shared Field simulation (the
-- same enemies, gates, boosters, fists and crosshair as the real game) but replaces
-- the wave spawner with a scripted list of steps and disables all punishment: nothing
-- costs health, and a step's props simply respawn until the player performs the action
-- it teaches. main.lua owns the player lane, the super-punch cooldown and the input;
-- this module owns the step machine, its on-screen prompts and its completion checks.
Tutorial = {}

-- Lane ids, matching main.lua (the right lane, 3, is only reached via otherLane).
local LEFTLANE, MIDDLELANE = 1, 2

-- A lane that isn't the player's current one, for lessons that require moving over.
local function otherLane(pl)
    if pl == MIDDLELANE then return LEFTLANE end
    return MIDDLELANE
end

-- ─── Per-step progress counters ──────────────────────────────────────────────
-- Reset whenever a new step begins; the step's `done` predicate reads them. They
-- accumulate across respawns within a step, so partial progress is never lost.
local c

local function resetCounters()
    c = {
        moves       = 0,      -- lane changes
        kills       = 0,      -- enemies punched
        pushes      = 0,      -- super-punches that shoved at least one enemy
        chains      = 0,      -- chain kills witnessed
        heals       = 0,      -- boosters collected
        gateDodged  = false,  -- a gate reached the end without hitting the player
    }
end

-- ─── Steps ───────────────────────────────────────────────────────────────────
-- Each step: an id (for hint targeting), the prompt to show, an optional spawn(pl)
-- that (re)creates its props while the field is empty and the step isn't yet done,
-- and a done(pl) predicate evaluated every frame.
local STEPS = {
    {
        id     = "move",
        prompt = "Use Left and Right to switch lanes",
        done   = function() return c.moves >= 2 end,
    },
    {
        id     = "punch",
        prompt = "Press A to punch the enemy ahead",
        spawn  = function(pl) Field.spawnEnemy(pl) end,
        done   = function() return c.kills >= 1 end,
    },
    {
        id     = "lineup",
        prompt = "Move onto the enemy's lane, then press A",
        spawn  = function(pl) Field.spawnEnemy(otherLane(pl)) end,
        done   = function() return c.kills >= 1 end,
    },
    {
        id     = "gate",
        prompt = "Dodge the gate - you can't punch it!",
        spawn  = function(pl) Field.spawnLaser(pl) end,
        done   = function() return c.gateDodged end,
    },
    {
        id     = "super",
        prompt = "Press B to defeat a cluster of them!",
        spawn  = function(pl)
            -- A short staggered column so the push visibly clears several at once.
            for k = 0, 2 do
                local e = Field.spawnEnemy(pl)
                e.progress = k * 0.12
            end
        end,
        done   = function() return c.pushes >= 1 end,
    },
    {
        id     = "health",
        prompt = "Collect the booster - don't punch it!",
        spawn  = function(pl) Field.spawnHealth(pl) end,
        done   = function() return c.heals >= 1 end,
    },
    {
        id     = "graduate",
        prompt = "Last drill: clear them both!",
        spawn  = function(pl)
            Field.spawnEnemy(pl)
            Field.spawnEnemy(otherLane(pl))
        end,
        done   = function() return c.kills >= 2 end,
    },
}

-- ─── State ───────────────────────────────────────────────────────────────────
local step         -- 1-based index into STEPS
local completing   -- true while the "complete" message holds before returning to menu
local finished     -- true once the tutorial is fully over (main returns to the menu)
local flashTimer   -- frames left on the "Nice!" step-cleared flash
local pauseTimer   -- frames left in the calm intermission before a step's props appear
local hintTimer    -- frames left on a transient corrective hint
local hintText     -- the current hint message

local FLASH_HOLD    = 40
local HINT_HOLD     = 75
local COMPLETE_HOLD = 70
-- Breathing room between steps: after one is cleared, the field stays quiet and the
-- next prompt sits on screen this many frames (~2.5s at 30 Hz) before its props spawn,
-- so the player can read and focus on one instruction at a time.
local STEP_PAUSE    = 75

local function setHint(text)
    hintText  = text
    hintTimer = HINT_HOLD
end

-- ─── Public API ──────────────────────────────────────────────────────────────

-- Reset the machine to the first step. Call when entering the tutorial scene.
function Tutorial.start()
    step       = 1
    completing = false
    finished   = false
    flashTimer = 0
    pauseTimer = 0     -- first step begins immediately; only later ones are eased in
    hintTimer  = 0
    hintText   = nil
    resetCounters()
end

function Tutorial.isFinished()
    return finished
end

-- (Re)spawn the current step's props when the field has emptied and the step still
-- isn't satisfied. Called before Field.update so a fresh spawn advances this frame.
function Tutorial.spawnIfNeeded(playerLane)
    if completing or pauseTimer > 0 then return end
    local s = STEPS[step]
    if s.spawn and Field.isEmpty() and not s.done(playerLane) then
        s.spawn(playerLane)
    end
end

-- Fold this frame's field events into the counters, then advance the step (or finish
-- the tutorial) if the current step's goal is met. Called after Field.update.
function Tutorial.update(events, playerLane)
    for _, ev in ipairs(events) do
        if ev.kind == "heal" then
            c.heals += 1
        elseif ev.kind == "chainKill" then
            c.chains += 1
        elseif ev.kind == "gatePassed" and not ev.hitPlayer then
            c.gateDodged = true
        end
    end

    if flashTimer > 0 then flashTimer -= 1 end
    if hintTimer  > 0 then hintTimer  -= 1 end
    if pauseTimer > 0 then pauseTimer -= 1 end

    if completing then
        if flashTimer <= 0 then finished = true end
        return
    end

    -- Intermission: let the new prompt breathe before its props spawn or its goal is
    -- checked, so one step can't blur into the next.
    if pauseTimer > 0 then return end

    if STEPS[step].done(playerLane) then
        if step >= #STEPS then
            completing = true
            flashTimer = COMPLETE_HOLD
        else
            step += 1
            resetCounters()
            flashTimer = FLASH_HOLD
            pauseTimer = STEP_PAUSE
        end
    end
end

-- ─── Input notifications (from main.lua's handlers) ──────────────────────────

function Tutorial.onLaneChange()
    c.moves += 1
end

-- result is Field.punch's return: nil, or { kind = "enemy"|"laser"|"health", ... }.
function Tutorial.onPunch(result)
    if not result then return end
    if result.kind == "enemy" then
        c.kills += 1
    elseif result.kind == "laser" and STEPS[step].id == "gate" then
        setHint("Gates can't be punched - dodge them!")
    elseif result.kind == "health" and STEPS[step].id == "health" then
        setHint("Punching wastes it - let it reach you.")
    end
end

-- pushed is Field.superPunch's return: the number of enemies actually shoved back.
function Tutorial.onSuperPunch(pushed)
    if pushed and pushed > 0 then c.pushes += 1 end
end

-- ─── Rendering ───────────────────────────────────────────────────────────────
-- Drawn over the field each frame (the crosshair keeps the whole screen redrawing,
-- so these overlays refresh cleanly). All text sits in white boxes to read against
-- the tunnel.

local BOX_PAD = 5

-- A rounded white box with a black border and centred black text, positioned by its
-- centre point. Returns nothing.
local function drawBoxedText(text, cx, cy)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
    local tw, th = gfx.getTextSize(text)
    local w, h = tw + BOX_PAD * 2, th + BOX_PAD * 2
    local x, y = cx - w // 2, cy - h // 2
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRoundRect(x, y, w, h, 4)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawRoundRect(x, y, w, h, 4)
    gfx.drawTextAligned(text, cx, y + BOX_PAD, kTextAlignment.center)
end

function Tutorial.draw()
    if completing then
        drawBoxedText("Tutorial complete!", 200, 118)
        return
    end

    -- Progress counter (top-left) and the skip affordance (top-right).
    drawBoxedText("Step " .. step .. " / " .. #STEPS, 56, 16)
    drawBoxedText("Menu: skip", 336, 16)

    -- A transient corrective hint takes over the prompt line when active; otherwise
    -- the current step's prompt is shown.
    local text = (hintTimer > 0 and hintText) or STEPS[step].prompt
    drawBoxedText(text, 200, 214)

    -- Brief "Nice!" flash centred after a step is cleared.
    if flashTimer > 0 then
        drawBoxedText("Nice!", 200, 118)
    end
end
