

-- Importing libraries used for drawCircleAtPoint and crankIndicator
import "CoreLibs/graphics"
import "CoreLibs/sprites"
import "CoreLibs/ui"
import "enemy"
import "laser"
import "health"
import "menuScreen"
import "field"
import "tutorial"
import "fists"
import "deathAnimation"
import "diamond"
import "crosshair"
import "sounds"
import "gameOver"
import "score"
import "scoreboard"

-- Localizing commonly used globals
local pd = playdate
local gfx = playdate.graphics

-- Pre-build sound effects so the first playback doesn't hitch.
Sounds.load("taking_damage")
Sounds.load("healing")


--Scenes
local SCENE_MENU = "menu"
local SCENE_GAME = "game"
local SCENE_GAMEOVER = "gameover"
local SCENE_SCOREBOARD = "scoreboard"
local SCENE_TUTORIAL = "tutorial"
local currentScene = SCENE_MENU

-- Scoring point values
local WAVE_CLEAR_POINTS = 300   -- awarded for clearing all hazards of a wave
local HEALTH_POINTS     = 200   -- awarded for collecting a health booster
local DAMAGE_PENALTY    = 200   -- lost on each instance of taking damage
local CHAIN_STEP        = 50    -- chain-kill bonus, growing by this per kill by a pushed enemy

-- The current run's reached wave, stamped onto the leaderboard entry at death.
local currentWave = 0

-- Result of the run just finished, stashed at death so the scoreboard can show it
-- when the player advances past the game-over screen.
local finalEntries, finalIndex = {}, nil

-- Death sequence: the moment the player dies, time stops dead and the last frame
-- holds on screen for FREEZE_DURATION, then we hand that frame to the GameOver
-- module to disintegrate. `deathPhase` is nil during normal play and "freeze"
-- while the hold plays out.
local FREEZE_DURATION = 30   -- real frames the frozen frame holds (~1.5 s at 30 Hz)
local deathPhase  = nil
local freezeTimer = 0        -- real frames elapsed within the freeze

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
    Score.add(-DAMAGE_PENALTY)
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

-- Score readout, flush in the top-right corner. Uses a tiny font and a fixed-width,
-- zero-padded number so the box never changes size (and reads all-zeros at the
-- start). Drawn black on white; the white tab hugs the corner, so only the bottom
-- and left borders (the edges facing into the screen) are drawn — no top or right line.
local SCORE_FONT   = gfx.font.new("fonts/font-rains-1x")
local SCORE_DIGITS = 6
local SCORE_PAD    = 2
-- Width is locked to the widest possible string (all digits at maximum).
local SCORE_TEXT_W = SCORE_FONT:getTextWidth("Score:" .. string.rep("0", SCORE_DIGITS))
local SCORE_BOX_W  = SCORE_TEXT_W + SCORE_PAD * 2
local SCORE_BOX_H  = SCORE_FONT:getHeight() + SCORE_PAD * 2

local function drawScore()
    local text = "Score:" .. string.format("%0" .. SCORE_DIGITS .. "d", Score.get())
    local x = 400 - SCORE_BOX_W
    local y = 0

    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(x, y, SCORE_BOX_W, SCORE_BOX_H)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawLine(x, y + SCORE_BOX_H - 1, x + SCORE_BOX_W, y + SCORE_BOX_H - 1)  -- bottom
    gfx.drawLine(x, y, x, y + SCORE_BOX_H - 1)                                  -- left
    SCORE_FONT:drawText(text, x + SCORE_PAD, y + SCORE_PAD)
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

-- Field entities (enemies, laser gates, health boosters) and the per-frame field
-- simulation live in the Field module now; main.lua just drives it.
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
local waveClearScored = false  -- whether the current wave's clear bonus was already paid



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


-- Defined with the system-menu helpers below; forward-declared so switchToMenu can
-- tear the "Skip Tutorial" item down on the way out of any scene.
local removeTutorialSkip

local function switchToMenu()
    -- MenuScreen.enter() calls gfx.sprite.removeAll(), so the sprites are torn
    -- down there; here we just drop our references to every field entity.
    removeTutorialSkip()
    Field.reset()
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

    -- Clear any death sequence left from a previous run
    deathPhase  = nil
    freezeTimer = 0

    -- Reset damage/heal feedback state
    shakeTimer = 0
    healthFlickerTimer = 0
    pd.display.setOffset(0, 0)

    -- Clear any field entities left from a previous run
    Field.reset()

    -- Reset wave state; first wave arrives after the clear delay
    waveCount  = 0
    waveTimer  = WAVE_CLEAR_DELAY
    spawnQueue = {}
    spawnDelay = 0
    waveClearScored = false
    waveMsgTimer = 0
    waveMsgImage = nil

    -- Reset scoring for the new run
    Score.reset()
    currentWave = 0


    background:add()
    updateBg()
    Field.enter()

    currentScene = SCENE_GAME
end

-- ─── Tutorial skip (system menu) ─────────────────────────────────────────────
-- The tutorial is skippable at any point via the Playdate system menu, since its
-- face buttons are all in use teaching moves. The item exists only while the
-- tutorial is active.
local sysMenu = pd.getSystemMenu()
local tutorialMenuItem = nil

local function addTutorialSkip()
    if not tutorialMenuItem then
        tutorialMenuItem = sysMenu:addMenuItem("Skip Tutorial", function()
            switchToMenu()
        end)
    end
end

function removeTutorialSkip()
    if tutorialMenuItem then
        sysMenu:removeMenuItem(tutorialMenuItem)
        tutorialMenuItem = nil
    end
end

-- From the game-over screen to the scoreboard, showing the run just played and the
-- leaderboard recorded for it at death.
local function switchToScoreboard()
    Scoreboard.enter(finalEntries, finalIndex, Score.get(), currentWave)
    currentScene = SCENE_SCOREBOARD
end

-- From the menu into the scoreboard to browse the saved leaderboard. There's no
-- current run, so the "this run" row is omitted and nothing is highlighted.
local function switchToLeaderboard()
    Scoreboard.enter(Score.entries(), nil, nil, nil)
    currentScene = SCENE_SCOREBOARD
end

-- From the menu into the interactive tutorial. Sets up the same field scene as the
-- game (background, fists, targeting) but hands pacing to the Tutorial step machine.
-- No scoring or health: the run state is irrelevant here.
local function switchToTutorial()
    playerLane = MIDDLELANE
    superPunchTimer = 0
    deathPhase  = nil
    shakeTimer = 0
    pd.display.setOffset(0, 0)

    Field.reset()
    background:add()
    updateBg()
    Field.enter()

    Tutorial.start()
    addTutorialSkip()
    currentScene = SCENE_TUTORIAL
end

-- ─── Boot into menu ─────────────────────────────────────────────────────────
 
MenuScreen.enter()

-- ─── Input ──────────────────────────────────────────────────────────────────

-- Shift the player one lane in dir (-1 = left, +1 = right), clamped to the three
-- lanes. Returns true if the lane actually changed. Shared by the game and tutorial.
local function shiftLane(dir)
    local previousLane = playerLane
    playerLane = math.max(LEFTLANE, math.min(RIGHTLANE, playerLane + dir))
    if playerLane ~= previousLane then
        -- Perspective shifted; the baked death animation no longer lines up
        DeathAnim.stop()
    end
    updateBg()
    return playerLane ~= previousLane
end


-- On the menu, all four arrows cycle the highlighted option (up/left back,
-- down/right forward); in the game and tutorial, left/right change lanes and
-- up/down do nothing.
function pd.upButtonDown()
    if currentScene == SCENE_MENU then
        MenuScreen.moveSelection(-1)
    end
end

function pd.downButtonDown()
    if currentScene == SCENE_MENU then
        MenuScreen.moveSelection(1)
    end
end

function pd.leftButtonDown()
    if currentScene == SCENE_MENU then
        MenuScreen.moveSelection(-1)
        return
    end
    if currentScene == SCENE_TUTORIAL then
        if shiftLane(-1) then Tutorial.onLaneChange() end
        return
    end
    if currentScene ~= SCENE_GAME or deathPhase ~= nil then return end
    shiftLane(-1)
end

function pd.rightButtonDown()
    if currentScene == SCENE_MENU then
        MenuScreen.moveSelection(1)
        return
    end
    if currentScene == SCENE_TUTORIAL then
        if shiftLane(1) then Tutorial.onLaneChange() end
        return
    end
    if currentScene ~= SCENE_GAME or deathPhase ~= nil then return end
    shiftLane(1)
end


function pd.AButtonDown() 

    if currentScene == SCENE_MENU then
        local choice = MenuScreen.selectedId()
        if choice == "start" then
            switchToGame()
        elseif choice == "leaderboard" then
            switchToLeaderboard()
        elseif choice == "tutorial" then
            switchToTutorial()
        end
        return
    end

    if currentScene == SCENE_TUTORIAL then
        Tutorial.onPunch(Field.punch(playerLane, playerRange))
        return
    end

    if currentScene == SCENE_GAMEOVER then
        -- Once the title screen is up, A advances to the scoreboard (no-op mid-dissolve)
        if GameOver.isInteractive() then switchToScoreboard() end
        return
    end

    if currentScene == SCENE_SCOREBOARD then
        switchToMenu()
        return
    end

    -- Dead and slowing down: ignore further punches
    if deathPhase ~= nil then return end

    -- In-game punch: Field resolves the hit (kill/hurt + punch pose + death flash);
    -- here we apply the run's consequences — score an enemy, take damage from a gate.
    local hit = Field.punch(playerLane, playerRange)
    if hit then
        if hit.kind == "enemy" then
            Score.add(hit.points)
        elseif hit.kind == "laser" then
            takeDamage(hit.damage)
        end
        -- health: destroyed without collecting; no score or damage
    end
end

function pd.BButtonDown()
    if currentScene == SCENE_TUTORIAL then
        if superPunchTimer > 0 then return end
        superPunchTimer = SUPER_PUNCH_COOLDOWN
        Tutorial.onSuperPunch(Field.superPunch(playerLane, playerRange))
        return
    end
    if currentScene ~= SCENE_GAME or deathPhase ~= nil then return end
    if superPunchTimer > 0 then return end
    superPunchTimer = SUPER_PUNCH_COOLDOWN
    Field.superPunch(playerLane, playerRange)
end

-- ─── Update loop ────────────────────────────────────────────────────────────

-- One full frame of live gameplay: simulation + render. Pulled out of pd.update
-- so the death slow-motion can run it on only some real frames to slow time down.
local function runGameFrame()

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
                Field.spawnEnemy(Field.pickSpawnLane())
            elseif what == "laser" then
                Field.spawnLaser(Field.pickSpawnLane())
            elseif what == "health" then
                Field.spawnHealth(Field.pickSpawnLane())
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
        if Field.hasActiveHazards() then
            waveTimer = WAVE_CLEAR_DELAY
        else
            -- The field just cleared: pay the wave-clear bonus once (every wave but the
            -- very first, which had nothing to clear). Paid here, not at the next wave's
            -- start, so dying during the clear delay still banks the bonus.
            if not waveClearScored and waveCount > 0 then
                Score.add(WAVE_CLEAR_POINTS)
                waveClearScored = true
            end
            waveTimer -= 1
            if waveTimer <= 0 then
                -- Start a new wave; the first entity spawns immediately (spawnDelay = 0)
                spawnQueue = buildSpawnQueue(waveCount)
                spawnDelay = 0
                waveClearScored = false
                -- waveCount counts completed waves, so the one starting is waveCount + 1
                currentWave = waveCount + 1
                showWaveMessage(waveCount + 1)
            end
        end
    end


    -- Field simulation + render for this frame. Consequences that cross back into
    -- the run (a booster collected, a chain kill, an enemy or gate reaching the end)
    -- come back as events, which we translate into score, healing and damage here.
    local events = Field.update(playerLane, playerRange)
    for _, ev in ipairs(events) do
        if ev.kind == "damage" then
            takeDamage(ev.amount)
        elseif ev.kind == "heal" then
            heal(HEALTH_HEAL)
            Score.add(HEALTH_POINTS)
        elseif ev.kind == "chainKill" then
            Score.add(CHAIN_STEP * ev.count)
        end
    end

    if superPunchTimer > 0 then
        superPunchTimer -= 1
    end
    drawHealthBar()
    drawScore()
    drawSuperCooldownBar()
    drawWaveMessage()
    pd.drawFPS(0,220)
end

-- Hand the death slow-motion's final frame off to the GameOver module and tear
-- down all live gameplay, so the disintegration runs against a static capture
-- instead of the still-updating scene.
local function startGameOver()
    pd.display.setOffset(0, 0)          -- drop any lingering shake offset
    local snapshot = gfx.getDisplayImage()  -- the last frame the player saw

    Field.reset()
    DeathAnim.stop()
    gfx.sprite.removeAll()

    -- Bank this run on the leaderboard, stashing the result for the scoreboard.
    finalEntries, finalIndex = Score.record(Score.get(), currentWave)

    GameOver.begin(snapshot)
    currentScene = SCENE_GAMEOVER
    deathPhase   = nil
end

-- Advance the death slow-motion. Real time keeps ticking every frame, but the
-- gameplay simulation only steps when the accumulator (fed by a time scale that
-- ramps 1→0 over SLOWMO_DURATION) crosses a whole step, so motion visibly stalls
-- and then freezes. On non-step frames nothing is redrawn, leaving the last frame
-- on screen — which is what we eventually capture and disintegrate.
-- Time is fully stopped: don't run any gameplay, just hold the frozen frame on
-- screen (nothing is redrawn, so the last frame persists) until the hold elapses,
-- then kick off the disintegration.
local function updateFreeze()
    freezeTimer += 1
    if freezeTimer >= FREEZE_DURATION then
        startGameOver()
    end
end

-- One frame of the tutorial: the shared field runs exactly as in the game, but the
-- Tutorial step machine spawns the props and the field's damage/heal events are left
-- unapplied — nothing here costs (or restores) health, so the player can't fail. The
-- only run-style HUD kept is the super-punch cooldown, for the B-button lesson.
local function runTutorialFrame()
    Tutorial.spawnIfNeeded(playerLane)
    local events = Field.update(playerLane, playerRange)
    Tutorial.update(events, playerLane)

    if Tutorial.isFinished() then
        switchToMenu()
        return
    end

    if superPunchTimer > 0 then
        superPunchTimer -= 1
    end
    drawSuperCooldownBar()
    Tutorial.draw()
end

function pd.update()
    if currentScene == SCENE_MENU then
        MenuScreen.update()
        return
    end

    if currentScene == SCENE_GAMEOVER then
        GameOver.update()
        return
    end

    if currentScene == SCENE_SCOREBOARD then
        Scoreboard.update()
        return
    end

    if currentScene == SCENE_TUTORIAL then
        runTutorialFrame()
        return
    end

    -- Game scene. The player's death stops time and freezes the frame instead of
    -- cutting straight to the menu.
    if deathPhase == nil and playerHealth <= 0 then
        deathPhase  = "freeze"
        freezeTimer = 0
    end

    if deathPhase == "freeze" then
        updateFreeze()
        return
    end

    runGameFrame()
end