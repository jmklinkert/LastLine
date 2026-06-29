

-- Importing libraries used for drawCircleAtPoint and crankIndicator
import "CoreLibs/graphics"
import "CoreLibs/sprites"
import "CoreLibs/ui"
import "enemy"
import "laser"
import "health"
import "menuScreen"
import "fists"
import "deathAnimation"
import "diamond"
import "crosshair"
import "sounds"

-- Localizing commonly used globals
local pd = playdate
local gfx = playdate.graphics

-- Pre-build sound effects so the first playback doesn't hitch.
Sounds.load("taking_damage")
Sounds.load("healing")


--Scenes
local SCENE_MENU = "menu"
local SCENE_GAME = "game"
local currentScene = SCENE_MENU

--background
local bgMiddle = gfx.image.new("images/tunnel_m.png")
local bgLeft = gfx.image.new("images/tunnel_l.png")

local background = gfx.sprite.new()
background:setCenter(0,0)
background:moveTo(0,0)
background:setZIndex(0)


--lanes
local LEFTLANE = 1
local MIDDLELANE = 2
local RIGHTLANE = 3

--Player
local playerLane = 2
local playerRange = 15

--Super-Punch cooldown
local SUPER_PUNCH_COOLDOWN = 2 * 30  -- frames (2 s at 30 Hz)
local superPunchTimer = 0            -- frames until super-punch is ready again


--Health
local MAX_HEALTH = 100
local playerHealth = MAX_HEALTH

-- Health bar layout (drawn with gfx primitives; no sprite asset)
local HEALTHBAR_X = 8
local HEALTHBAR_Y = 8
local HEALTHBAR_W = 120   -- outer width including border
local HEALTHBAR_H = 14
local HEALTHBAR_PAD = 2   -- gap between border and the fill

-- Damage feedback: a short screen shake (whole-display offset) that decays out.
local SHAKE_DURATION  = 12   -- frames the shake lasts (~0.4 s at 30 Hz)
local SHAKE_MAGNITUDE = 5    -- max pixel displacement, strongest at the start
local shakeTimer = 0         -- frames of shake remaining

-- Heal feedback: the health bar blinks a few times.
local FLICKER_DURATION = 24  -- frames the flicker lasts (~0.8 s)
local FLICKER_PERIOD   = 4   -- frames per on/off cycle (so a few blinks total)
local healthFlickerTimer = 0 -- frames of flicker remaining

local function takeDamage(amount)
    playerHealth = math.max(0, playerHealth - amount)
    shakeTimer = SHAKE_DURATION
    Sounds.play("taking_damage")
end

local function heal(amount)
    playerHealth = math.min(MAX_HEALTH, playerHealth + amount)
    healthFlickerTimer = FLICKER_DURATION
    Sounds.play("healing")
end

-- Apply the current frame's shake offset to the whole display, decaying the
-- magnitude as the timer runs down and snapping back to centre when it ends.
local function applyScreenShake()
    if shakeTimer <= 0 then return end
    shakeTimer -= 1
    if shakeTimer <= 0 then
        pd.display.setOffset(0, 0)
        return
    end
    local mag = math.ceil(SHAKE_MAGNITUDE * (shakeTimer / SHAKE_DURATION))
    pd.display.setOffset(math.random(-mag, mag), math.random(-mag, mag))
end

local function drawHealthBar()
    -- Heal flicker: blink the whole bar off during the "off" half of each cycle.
    if healthFlickerTimer > 0 then
        healthFlickerTimer -= 1
        if (healthFlickerTimer // FLICKER_PERIOD) % 2 == 1 then
            return
        end
    end

    -- White backing so the bar reads on any background, then a black border
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(HEALTHBAR_X, HEALTHBAR_Y, HEALTHBAR_W, HEALTHBAR_H)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawRect(HEALTHBAR_X, HEALTHBAR_Y, HEALTHBAR_W, HEALTHBAR_H)

    -- Filled portion proportional to remaining health
    local innerW = HEALTHBAR_W - HEALTHBAR_PAD * 2
    local fillW  = math.floor(innerW * (playerHealth / MAX_HEALTH))
    if fillW > 0 then
        gfx.fillRect(HEALTHBAR_X + HEALTHBAR_PAD,
                     HEALTHBAR_Y + HEALTHBAR_PAD,
                     fillW,
                     HEALTHBAR_H - HEALTHBAR_PAD * 2)
    end
end

-- Super-punch cooldown bar: small bar in the bottom-left over the left fist.
-- Only shown while cooling down; drains from full to empty as it recharges.
local SPBAR_X   = 50
local SPBAR_H   = 16
local SPBAR_W   = 120
local SPBAR_Y   = 240 - SPBAR_H - 8   -- 8px up from the bottom edge
local SPBAR_PAD = 3

local function drawSuperCooldownBar()
    if superPunchTimer <= 0 then return end   -- ready: nothing to show

    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(SPBAR_X, SPBAR_Y, SPBAR_W, SPBAR_H)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawRect(SPBAR_X, SPBAR_Y, SPBAR_W, SPBAR_H)

    -- Filled portion proportional to remaining cooldown
    local innerW = SPBAR_W - SPBAR_PAD * 2
    local fillW  = math.floor(innerW * (superPunchTimer / SUPER_PUNCH_COOLDOWN))
    if fillW > 0 then
        gfx.fillRect(SPBAR_X + SPBAR_PAD,
                     SPBAR_Y + SPBAR_PAD,
                     fillW,
                     SPBAR_H - SPBAR_PAD * 2)
    end
end

-- Wave banner: a little "Wave N" message that slides in from the top, holds,
-- then fades out whenever a new wave starts.
local WAVE_MSG_LIFE  = 90   -- frames the banner is shown (3 s at 30 Hz)
local WAVE_MSG_Y     = 28   -- resting y once slid in
local WAVE_MSG_SLIDE = 10   -- frames of slide-in
local WAVE_MSG_FADE  = 20   -- frames of fade-out at the end
local WAVE_MSG_PAD   = 6    -- padding inside the banner box

local waveMsgImage = nil
local waveMsgTimer = 0

-- Bake the "Wave N" text into a small boxed image so it reads on any background
-- and can be faded as one unit.
local function bakeWaveMessage(n)
    local text = "Wave " .. n
    local tw, th = gfx.getTextSize(text)
    local w, h = tw + WAVE_MSG_PAD * 2, th + WAVE_MSG_PAD * 2

    local img = gfx.image.new(w, h)
    gfx.pushContext(img)
        gfx.setColor(gfx.kColorWhite)
        gfx.fillRoundRect(0, 0, w, h, 4)
        gfx.setColor(gfx.kColorBlack)
        gfx.drawRoundRect(0, 0, w, h, 4)
        gfx.drawText(text, WAVE_MSG_PAD, WAVE_MSG_PAD)
    gfx.popContext()
    return img
end

local function showWaveMessage(n)
    waveMsgImage = bakeWaveMessage(n)
    waveMsgTimer = WAVE_MSG_LIFE
end

local function drawWaveMessage()
    if waveMsgTimer <= 0 or not waveMsgImage then return end

    local imgW, imgH = waveMsgImage:getSize()
    local x = (400 - imgW) // 2
    local elapsed = WAVE_MSG_LIFE - waveMsgTimer

    -- Slide down from above into the resting position
    local y = WAVE_MSG_Y
    if elapsed < WAVE_MSG_SLIDE then
        local t = elapsed / WAVE_MSG_SLIDE
        y = -imgH + (WAVE_MSG_Y + imgH) * t
    end

    -- Fade out over the final frames
    local alpha = 1.0
    if waveMsgTimer < WAVE_MSG_FADE then
        alpha = waveMsgTimer / WAVE_MSG_FADE
    end

    waveMsgImage:drawFaded(x, math.floor(y), alpha, gfx.image.kDitherTypeBayer8x8)
    waveMsgTimer -= 1
end

--Field entities. Enemies are hazards that can be punched/pushed; laser gates are
--hazards that can't be removed and block punches; health boosters are boons.
local enemies = {}
local lasers  = {}
local healths = {}

local HEALTH_HEAL = math.floor(MAX_HEALTH * 0.2)  -- a booster restores 40% of max



-- ─── Wave / Difficulty System ─────────────────────────────────────────────────
--
local WAVE_CLEAR_DELAY     = math.floor(2.5 * 30)  -- frames; next wave starts 2.5s after the field is cleared
local ENEMIES_START       = 3
local ENEMIES_MAX         = 12
local SPAWN_DELAY_START   = 20       -- frames between enemies in a wave at ramp 0
local SPAWN_DELAY_MIN     = 12       -- frames between enemies in a wave at max ramp
local RAMP_EVERY          = 4        -- waves between each difficulty step
local RAMP_STEPS          = 8        -- ramp 0..4
 
-- Returns the ramp level (0–RAMP_STEPS) for a given completed-wave count
local function rampLevel(waveCount)
    return math.min(RAMP_STEPS, math.floor(waveCount / RAMP_EVERY))
end
 
local function enemiesPerWave(waveCount)
    return math.min(ENEMIES_MAX, ENEMIES_START + rampLevel(waveCount))
end

local function spawnInterval(waveCount)
    return math.max(SPAWN_DELAY_MIN,
                    SPAWN_DELAY_START - rampLevel(waveCount) * 2)
end

-- Laser gates: none in the early waves, climbing with the difficulty ramp.
local LASERS_MAX = 3
local function lasersPerWave(waveCount)
    return math.min(LASERS_MAX, math.floor(rampLevel(waveCount) / 2))
end

-- A gate's own lane stays closed to new spawns until the gate has advanced past
-- this progress, guaranteeing a gap behind it big enough to maneuver around.
-- Other lanes are unaffected, so the overall spawn cadence is unchanged.
local GATE_SPAWN_BLOCK = 0.15

-- Health boosters: each wave has at most one, with the chance climbing linearly
-- from HEALTH_CHANCE_MIN% on wave 1 to HEALTH_CHANCE_MAX% on HEALTH_CHANCE_WAVE_CAP.
local HEALTH_CHANCE_MIN      = 5
local HEALTH_CHANCE_MAX      = 85
local HEALTH_CHANCE_WAVE_CAP = 32
local function healthChance(wave)
    local t = math.min(1, (wave - 1) / (HEALTH_CHANCE_WAVE_CAP - 1))
    return HEALTH_CHANCE_MIN + (HEALTH_CHANCE_MAX - HEALTH_CHANCE_MIN) * t
end

-- Build the ordered spawn list for the wave starting after `waveCount` completed
-- waves: enemies plus any gates and an optional booster, shuffled so hazards and
-- boons are sprinkled throughout. Every entry shares the enemy spawn delay, so
-- nothing ever spawns right on top of a gate.
local function buildSpawnQueue(waveCount)
    local q = {}
    for _ = 1, enemiesPerWave(waveCount) do q[#q+1] = "enemy" end
    for _ = 1, lasersPerWave(waveCount) do q[#q+1] = "laser" end
    if math.random(100) <= healthChance(waveCount + 1) then
        q[#q+1] = "health"
    end

    -- Fisher–Yates shuffle
    for i = #q, 2, -1 do
        local j = math.random(i)
        q[i], q[j] = q[j], q[i]
    end
    return q
end

-- Wave state (reset in switchToGame)
local waveCount  = 0    -- fully-spawned waves so far
local waveTimer  = 0    -- frames until the next wave begins
local spawnQueue = {}   -- ordered list of "enemy"/"laser"/"health" left to spawn this wave
local spawnDelay = 0    -- frames until the next queued entity is spawned



-- ─── Scene helpers ──────────────────────────────────────────────────────────

local function updateBg()
    if playerLane == LEFTLANE then
        background:setImage(bgLeft)
        background:setImageFlip(gfx.kImageUnflipped)
    elseif playerLane == MIDDLELANE then
        background:setImage(bgMiddle)
        background:setImageFlip(gfx.kImageUnflipped)
    elseif playerLane == RIGHTLANE then
        background:setImage(bgLeft)
        background:setImageFlip(gfx.kImageFlippedX)
    end
end


local function switchToMenu()
    -- MenuScreen.enter() calls gfx.sprite.removeAll(), so the sprites are torn
    -- down there; here we just drop our references to every field entity.
    enemies = {}
    lasers  = {}
    healths = {}
    -- Clear any leftover shake so the menu isn't drawn off-centre
    shakeTimer = 0
    pd.display.setOffset(0, 0)
    currentScene = SCENE_MENU
    MenuScreen.enter()
end

local function switchToGame()
    playerHealth = MAX_HEALTH
    playerLane = MIDDLELANE
    spawnTimer = 150
    superPunchTimer = 0

    -- Reset damage/heal feedback state
    shakeTimer = 0
    healthFlickerTimer = 0
    pd.display.setOffset(0, 0)

    -- Clear any field entities left from a previous run
    enemies = {}
    lasers  = {}
    healths = {}

    -- Reset wave state; first wave arrives after the clear delay
    waveCount  = 0
    waveTimer  = WAVE_CLEAR_DELAY
    spawnQueue = {}
    spawnDelay = 0
    waveMsgTimer = 0
    waveMsgImage = nil


    background:add()
    updateBg()
    Fists.enter()
    DeathAnim.enter()
    Diamond.enter()
    Crosshair.enter()

    currentScene = SCENE_GAME
end

-- ─── Boot into menu ─────────────────────────────────────────────────────────
 
MenuScreen.enter()

-- ─── Input ──────────────────────────────────────────────────────────────────

-- The laser gate nearest the player (highest progress) that is on the player's
-- lane and within punching reach, or nil. A punch/super-punch can't pass it: it
-- shields anything behind it, and a regular punch into it hurts the player.
local function frontmostLaserInRange()
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


function pd.leftButtonDown()
    local previousLane = playerLane
    if playerLane == RIGHTLANE then
        playerLane = MIDDLELANE
    elseif playerLane == MIDDLELANE then
        playerLane = LEFTLANE
    end
    if playerLane ~= previousLane then
        -- Perspective shifted; the baked death animation no longer lines up
        DeathAnim.stop()
    end
    updateBg()
end

function pd.rightButtonDown()
    local previousLane = playerLane
    if playerLane == LEFTLANE then
        playerLane = MIDDLELANE
    elseif playerLane == MIDDLELANE then
        playerLane = RIGHTLANE
    end
    if playerLane ~= previousLane then
        DeathAnim.stop()
    end
    updateBg()
end


function pd.AButtonDown() 

    if currentScene == SCENE_MENU then
        switchToGame() 
        return
    end

    Fists.punch()

    --In-Game: Punch behaviour. A punch only connects with the single frontmost
    --object in range on the player's lane (closest = highest progress), whatever
    --its type. Anything behind it is untouched: enemies behind the first enemy
    --survive, a health booster behind an enemy isn't destroyed, and a gate behind
    --an enemy doesn't hurt the player.
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
    elseif targetKind == "health" then
        target:kill()             -- destroyed without collecting
    elseif targetKind == "laser" then
        takeDamage(target.damage) -- gate is indestructible; the player gets hurt
    end
end

function pd.BButtonDown()
    if currentScene ~= SCENE_GAME then return end
    if superPunchTimer > 0 then return end

    superPunchTimer = SUPER_PUNCH_COOLDOWN
    Fists.superPunch()

    -- A gate blocks the push too (enemies behind it are safe), but costs no health.
    local blockingLaser = frontmostLaserInRange()

    for i = 1, #enemies do
        local e = enemies[i]
        if not e.dead and e:canBeHit(playerLane, playerRange)
        and not (blockingLaser and blockingLaser.progress > e.progress) then
            e:push()
        end
    end
end

-- ─── Update loop ────────────────────────────────────────────────────────────

-- A lane is off-limits for new spawns while it still has a gate close to the
-- spawn point, so nothing lands right behind a gate on its own lane.
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
local function pickSpawnLane()
    local free = {}
    for lane = 1, 3 do
        if not laneBlockedByGate(lane) then free[#free+1] = lane end
    end
    if #free == 0 then return math.random(1, 3) end
    return free[math.random(#free)]
end

local function spawnEnemy()
    table.insert(enemies, Enemy(pickSpawnLane()))
end

local function spawnLaser()
    table.insert(lasers, Laser(pickSpawnLane()))
end

local function spawnHealth()
    table.insert(healths, Health(pickSpawnLane()))
end

-- The enemy nearest the player (highest progress), or nil if none are alive.
local function leadingEnemy()
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
local function leadingEnemyOnLane(lane)
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
-- boosters are boons and never delay the next wave.
local function fieldHasActiveHazards()
    for i = 1, #enemies do
        local e = enemies[i]
        if not e.dead and not e.pushed then
            return true
        end
    end
    for i = 1, #lasers do
        if not lasers[i].dead then
            return true
        end
    end
    return false
end


function pd.update()

    -- Menu Scene
    if currentScene == SCENE_MENU then
        MenuScreen.update()
        return
    end

    --Game Scene 

    --Game Over Check
    if playerHealth <= 0 then
        switchToMenu()
        return
    end

    -- Damage feedback: offset the whole display for this frame while shaking
    applyScreenShake()


    -- Wave spawning logic
    if #spawnQueue > 0 then
        -- Mid-wave: count down to the next entity in the burst. Every entity uses
        -- the same delay; gates additionally keep their own lane clear (see spawn lane pick).
        spawnDelay -= 1
        if spawnDelay <= 0 then
            local what = table.remove(spawnQueue, 1)
            if what == "enemy" then
                spawnEnemy()
            elseif what == "laser" then
                spawnLaser()
            elseif what == "health" then
                spawnHealth()
            end

            if #spawnQueue > 0 then
                -- More to come; wait the difficulty-scaled delay before the next one
                spawnDelay = spawnInterval(waveCount)
            else
                -- Wave fully spawned; the next wave waits until the field clears
                waveCount += 1
                waveTimer  = WAVE_CLEAR_DELAY
            end
        end
    else
        -- Between waves: only start the 2.5s countdown once every advancing hazard
        -- from the last wave is gone (defeated, reached the end, or—for gates—cleared
        -- the lane). Pushed enemies are retreating and don't count. While any remain,
        -- keep the timer pinned at full so it begins counting only after the field clears.
        if fieldHasActiveHazards() then
            waveTimer = WAVE_CLEAR_DELAY
        else
            waveTimer -= 1
            if waveTimer <= 0 then
                -- Start a new wave; the first entity spawns immediately (spawnDelay = 0)
                spawnQueue = buildSpawnQueue(waveCount)
                spawnDelay = 0
                -- waveCount counts completed waves, so the one starting is waveCount + 1
                showWaveMessage(waveCount + 1)
            end
        end
    end


    -- Push the current lane into every entity module so they pick the right
    -- lane-offset sheet and flip this frame.
    Enemy.setPlayerLane(playerLane)
    Laser.setPlayerLane(playerLane)
    Health.setPlayerLane(playerLane)

    -- Marker above the nearest enemy; blinks once that enemy is punchable
    local lead = leadingEnemy()
    local punchable = lead ~= nil and lead:canBeHit(playerLane, playerRange)
    Diamond.update(lead, punchable)

    -- Crosshair tracks the nearest enemy on the *current* lane: arrows close in as
    -- it approaches, and the punchable reticle replaces it once it's in range.
    local laneLead = leadingEnemyOnLane(playerLane)
    local lanePunchable = laneLead ~= nil and laneLead:canBeHit(playerLane, playerRange)
    Crosshair.update(laneLead, lanePunchable, 1 - playerRange / 100)

    Fists.update()
    DeathAnim.update()
    gfx.sprite.update()



    --Pushed-Enemy Collision: Pushed Enemies defeat other enemies they catch up with

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
                    -- Killed by a pushed enemy: no death animation
                    re:kill()
                end
            end
        end
    end


    --Pushed-Enemy / Gate Collision: a retreating enemy shoved back into a gate is
    --destroyed without passing through; the gate is unharmed. (Only enemies in front
    --of a gate ever get pushed, so a non-dead pushed enemy reaching the gate's
    --progress means it has just hit it.)
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


    --Passive Health pickup: collected when on the player's lane within heal range.
    --Pushing an enemy through a booster never affects it, so it's only ever removed
    --here (collected) or by a punch / reaching the end.
    for i = #healths, 1, -1 do
        local h = healths[i]
        if not h.dead and h:canCollect(playerLane) then
            heal(HEALTH_HEAL)
            h:kill()
        end
    end


    --Clean up dead Enemies. Enemies that reached the end deal their damage.
    for i = #enemies, 1, -1 do
        local e = enemies[i]
        if e.dead then
            if e.reachedEnd then
                takeDamage(e.damage)
            end
            table.remove(enemies,i)
        end
    end

    --Clean up gates. A gate reaching the end only hurts the player if they share its lane.
    for i = #lasers, 1, -1 do
        local l = lasers[i]
        if l.dead then
            if l.reachedEnd and l.lane == playerLane then
                takeDamage(l.damage)
            end
            table.remove(lasers, i)
        end
    end

    --Clean up boosters (collected, punched, or drifted past the end).
    for i = #healths, 1, -1 do
        if healths[i].dead then
            table.remove(healths, i)
        end
    end

    if superPunchTimer > 0 then
        superPunchTimer -= 1
    end
    drawHealthBar()
    drawSuperCooldownBar()
    drawWaveMessage()
    pd.drawFPS(0,220)
end 