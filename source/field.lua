import "CoreLibs/graphics"
import "CoreLibs/sprites"
import "enemy"
import "laser"
import "health"
import "fists"
import "deathAnimation"
import "diamond"
import "crosshair"

local gfx = playdate.graphics

-- The Field owns every live gameplay entity (enemies, laser gates, health boosters)
-- and runs one frame of the shared simulation: entity movement, targeting markers,
-- collisions and cleanup. It knows nothing about scoring, player health, waves or the
-- tutorial — those are the caller's concern. Effects that cross that boundary (a hit
-- landing, a booster collected, a chain kill, a gate reaching the end) are reported
-- back as an event list from Field.update, so the game and the tutorial can react to
-- them differently (the game scores and takes damage; the tutorial ignores damage and
-- uses the events to drive its lessons).
Field = {}

-- Field entities. Enemies are hazards that can be punched/pushed; laser gates are
-- hazards that can't be removed and block punches; health boosters are boons.
local enemies = {}
local lasers  = {}
local healths = {}

-- A gate's own lane stays closed to new spawns until the gate has advanced past this
-- progress, guaranteeing a gap behind it big enough to maneuver around.
local GATE_SPAWN_BLOCK = 0.15

-- ─── Setup / teardown ────────────────────────────────────────────────────────

-- Add the field's shared presentation sprites (fists, death flash, targeting
-- markers) to the display list. Call after gfx.sprite.removeAll() when entering a
-- scene that uses the field (the game or the tutorial).
function Field.enter()
    Fists.enter()
    DeathAnim.enter()
    Diamond.enter()
    Crosshair.enter()
end

-- Drop every live entity. The sprites themselves are torn down by the caller's
-- gfx.sprite.removeAll(); here we just clear our references.
function Field.reset()
    enemies = {}
    lasers  = {}
    healths = {}
end

-- ─── Spawning ────────────────────────────────────────────────────────────────

-- A lane is off-limits for new spawns while it still has a gate close to the spawn
-- point, so nothing lands right behind a gate on its own lane.
local function laneBlockedByGate(lane)
    for i = 1, #lasers do
        local l = lasers[i]
        if not l.dead and l.lane == lane and l.progress < GATE_SPAWN_BLOCK then
            return true
        end
    end
    return false
end

-- Pick a random lane (1–3) that isn't blocked by a freshly-spawned gate. If every
-- lane is blocked (unlikely), fall back to any lane rather than skipping the spawn.
function Field.pickSpawnLane()
    local free = {}
    for lane = 1, 3 do
        if not laneBlockedByGate(lane) then free[#free+1] = lane end
    end
    if #free == 0 then return math.random(1, 3) end
    return free[math.random(#free)]
end

-- Spawn one entity on the given lane. spawnEnemy returns the enemy so callers (the
-- tutorial) can nudge its progress to build a staggered cluster.
function Field.spawnEnemy(lane)
    local e = Enemy(lane)
    table.insert(enemies, e)
    return e
end

function Field.spawnLaser(lane)
    table.insert(lasers, Laser(lane))
end

function Field.spawnHealth(lane)
    table.insert(healths, Health(lane))
end

-- ─── Queries ─────────────────────────────────────────────────────────────────

-- The enemy nearest the player (highest progress), or nil if none are alive.
function Field.leadingEnemy()
    local lead, best = nil, -1
    for i = 1, #enemies do
        local e = enemies[i]
        if not e.dead and e.progress > best then
            best = e.progress
            lead = e
        end
    end
    return lead
end

-- The nearest enemy on a specific lane (highest progress), or nil if none.
function Field.leadingEnemyOnLane(lane)
    local lead, best = nil, -1
    for i = 1, #enemies do
        local e = enemies[i]
        if not e.dead and e.lane == lane and e.progress > best then
            best = e.progress
            lead = e
        end
    end
    return lead
end

-- True while any advancing hazard remains. Pushed enemies are retreating and are
-- ignored, so a super-punch doesn't hold up the next wave's countdown. Laser gates
-- always count until they clear the lane, since they can't be removed. Health
-- boosters are boons and never count.
function Field.hasActiveHazards()
    for i = 1, #enemies do
        local e = enemies[i]
        if not e.dead and not e.pushed then return true end
    end
    for i = 1, #lasers do
        if not lasers[i].dead then return true end
    end
    return false
end

local function countLive(list)
    local n = 0
    for i = 1, #list do
        if not list[i].dead then n += 1 end
    end
    return n
end

function Field.enemyCount()  return countLive(enemies) end
function Field.laserCount()  return countLive(lasers)  end
function Field.healthCount() return countLive(healths) end

-- No live entity of any kind on the field. Used by the tutorial to know when a step's
-- props have all been dealt with (so it can advance or respawn them).
function Field.isEmpty()
    return countLive(enemies) == 0 and countLive(lasers) == 0 and countLive(healths) == 0
end

-- The laser gate nearest the player (highest progress) that is on the player's lane
-- and within punching reach, or nil. It shields anything behind it from a push.
local function frontmostLaserInRange(playerLane, playerRange)
    local front = nil
    for i = 1, #lasers do
        local l = lasers[i]
        if not l.dead and l:inRange(playerLane, playerRange) then
            if not front or l.progress > front.progress then
                front = l
            end
        end
    end
    return front
end

-- ─── Player actions ──────────────────────────────────────────────────────────

-- A punch connects with the single frontmost object in range on the player's lane
-- (closest = highest progress), whatever its type; anything behind it is untouched.
-- Applies the entity-level result (enemy/booster destroyed, gate leaves the player to
-- be hurt) and plays the punch pose plus the enemy death flash, since both the game
-- and the tutorial want those. Returns a descriptor of what was hit so the caller can
-- score / react, or nil if the punch connected with nothing:
--   { kind = "enemy", points = n } | { kind = "health" } | { kind = "laser", damage = n }
function Field.punch(playerLane, playerRange)
    Fists.punch()

    local rangeThreshold = 1 - playerRange / 100
    local target, targetKind, targetProgress = nil, nil, -1

    for i = 1, #enemies do
        local e = enemies[i]
        if not e.dead and e.lane == playerLane
        and e.progress >= rangeThreshold and e.progress > targetProgress then
            target, targetKind, targetProgress = e, "enemy", e.progress
        end
    end
    for i = 1, #lasers do
        local l = lasers[i]
        if not l.dead and l.lane == playerLane
        and l.progress >= rangeThreshold and l.progress > targetProgress then
            target, targetKind, targetProgress = l, "laser", l.progress
        end
    end
    for i = 1, #healths do
        local h = healths[i]
        if not h.dead and h.lane == playerLane
        and h.progress >= rangeThreshold and h.progress > targetProgress then
            target, targetKind, targetProgress = h, "health", h.progress
        end
    end

    if targetKind == "enemy" then
        target:kill()
        DeathAnim.play()          -- death animation only on an actual enemy hit
        return { kind = "enemy", points = target.points }
    elseif targetKind == "health" then
        target:kill()             -- destroyed without collecting
        return { kind = "health" }
    elseif targetKind == "laser" then
        return { kind = "laser", damage = target.damage }  -- gate is indestructible
    end
    return nil
end

-- Super-punch: shove back every enemy in range on the player's lane. A gate blocks
-- the push (enemies behind it are safe). Plays the super-punch pose. Returns the
-- number of enemies actually pushed. The caller owns the cooldown.
function Field.superPunch(playerLane, playerRange)
    Fists.superPunch()

    local blockingLaser = frontmostLaserInRange(playerLane, playerRange)
    local pushed = 0
    for i = 1, #enemies do
        local e = enemies[i]
        if not e.dead and e:canBeHit(playerLane, playerRange)
        and not (blockingLaser and blockingLaser.progress > e.progress) then
            e:push()
            pushed += 1
        end
    end
    return pushed
end

-- ─── Per-frame simulation + render ───────────────────────────────────────────

-- One frame of field simulation and render for the given player lane/range. Moves
-- and draws every entity, updates the targeting markers, resolves collisions and
-- cleans up finished entities. Player-facing consequences are returned as an event
-- list rather than applied here:
--   { kind = "damage",    source = "enemy"|"laser", amount = n }
--   { kind = "heal" }                          -- a booster was collected
--   { kind = "chainKill", count = n }          -- a pushed enemy's nth chain kill
--   { kind = "gatePassed", hitPlayer = bool }  -- a gate reached the end
function Field.update(playerLane, playerRange)
    local events = {}

    -- Push the current lane into every entity module so they pick the right
    -- lane-offset sheet and flip this frame.
    Enemy.setPlayerLane(playerLane)
    Laser.setPlayerLane(playerLane)
    Health.setPlayerLane(playerLane)

    -- Marker above the nearest enemy; blinks once that enemy is punchable.
    local lead = Field.leadingEnemy()
    local punchable = lead ~= nil and lead:canBeHit(playerLane, playerRange)
    Diamond.update(lead, punchable)

    -- Crosshair tracks the nearest enemy on the current lane: arrows close in as it
    -- approaches, and the punchable reticle replaces it once it's in range.
    local laneLead = Field.leadingEnemyOnLane(playerLane)
    local lanePunchable = laneLead ~= nil and laneLead:canBeHit(playerLane, playerRange)
    Crosshair.update(laneLead, lanePunchable, 1 - playerRange / 100)

    Fists.update()
    DeathAnim.update()
    gfx.sprite.update()

    -- Pushed-Enemy Collision: pushed enemies defeat other enemies they catch up with.
    for i = 1, #enemies do
        local pe = enemies[i]
        if pe.pushed and not pe.dead then
            for j = 1, #enemies do
                local re = enemies[j]
                if i ~= j
                and not re.pushed
                and not re.dead
                and re.lane == pe.lane
                and pe.progress <= re.progress
                then
                    -- Killed by a pushed enemy: no death animation. The chain count
                    -- grows for each successive kill this enemy racks up.
                    re:kill()
                    pe.chainKills += 1
                    events[#events+1] = { kind = "chainKill", count = pe.chainKills }
                end
            end
        end
    end

    -- Pushed-Enemy / Gate Collision: a retreating enemy shoved back into a gate is
    -- destroyed without passing through; the gate is unharmed.
    for i = 1, #enemies do
        local pe = enemies[i]
        if pe.pushed and not pe.dead then
            for j = 1, #lasers do
                local l = lasers[j]
                if not l.dead and l.lane == pe.lane and pe.progress <= l.progress then
                    pe:kill()
                    break
                end
            end
        end
    end

    -- Passive Health pickup: collected when on the player's lane within heal range.
    for i = #healths, 1, -1 do
        local h = healths[i]
        if not h.dead and h:canCollect(playerLane) then
            h:kill()
            events[#events+1] = { kind = "heal" }
        end
    end

    -- Clean up dead Enemies. Enemies that reached the end deal their damage.
    for i = #enemies, 1, -1 do
        local e = enemies[i]
        if e.dead then
            if e.reachedEnd then
                events[#events+1] = { kind = "damage", source = "enemy", amount = e.damage }
            end
            table.remove(enemies, i)
        end
    end

    -- Clean up gates. A gate reaching the end reports whether it hit the player (only
    -- if they share its lane); either way it announces its passing for the tutorial.
    for i = #lasers, 1, -1 do
        local l = lasers[i]
        if l.dead then
            if l.reachedEnd then
                local hitPlayer = l.lane == playerLane
                if hitPlayer then
                    events[#events+1] = { kind = "damage", source = "laser", amount = l.damage }
                end
                events[#events+1] = { kind = "gatePassed", hitPlayer = hitPlayer }
            end
            table.remove(lasers, i)
        end
    end

    -- Clean up boosters (collected, punched, or drifted past the end).
    for i = #healths, 1, -1 do
        if healths[i].dead then
            table.remove(healths, i)
        end
    end

    return events
end
