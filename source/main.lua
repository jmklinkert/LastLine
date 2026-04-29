

-- Importing libraries used for drawCircleAtPoint and crankIndicator
import "CoreLibs/graphics"
import "CoreLibs/sprites"
import "CoreLibs/ui"
import "enemy"
import "menuScreen"
import "stamina"
import "fists"

-- Localizing commonly used globals
local pd = playdate
local gfx = playdate.graphics


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
local playerRange = 10


--Health 
local MAX_Lives = 3
local playerLives = MAX_Lives
local heartImage = gfx.image.new("images/heart.png")


local function takeDamage() 
    playerLives = math.max(0,playerLives - 1)
end

local function drawHearts() 
    for i = 1, playerLives do 
        heartImage:draw((i-1)*32, 0)
    end
end

--Enemy Spawning
local enemies = {}
local spawnTimer = 150 -- 5 Seconds at 30 Hz



-- ─── Wave / Difficulty System ─────────────────────────────────────────────────
--
local WAVE_INTERVAL_START = 5 * 30   -- frames (5 s at 30 Hz)
local WAVE_INTERVAL_MIN   = 3 * 30   -- frames (3 s at 30 Hz)
local ENEMIES_START       = 2
local ENEMIES_MAX         = 6
local RAMP_EVERY          = 3        -- waves between each difficulty step
local RAMP_STEPS          = 4        -- ramp 0..4
 
-- Returns the ramp level (0–RAMP_STEPS) for a given completed-wave count
local function rampLevel(waveCount)
    return math.min(RAMP_STEPS, math.floor(waveCount / RAMP_EVERY))
end
 
local function waveInterval(waveCount)
    return math.max(WAVE_INTERVAL_MIN,
                    WAVE_INTERVAL_START - rampLevel(waveCount) * 15)
end
 
local function enemiesPerWave(waveCount)
    return math.min(ENEMIES_MAX, ENEMIES_START + rampLevel(waveCount))
end
 
-- Wave state (reset in switchToGame)
local waveCount  = 0   -- fully-spawned waves so far
local waveTimer  = 0   -- frames until the next wave begins
local spawnQueue = 0   -- enemies still to be spawned in the current wave
local spawnDelay = 0   -- frames until the next queued enemy is spawned



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
    --Remove all enemies
    for i = #enemies, 1, -1 do
        enemies[i]:remove() 
        table.remove(enemies,i) 
    end
    currentScene = SCENE_MENU
    MenuScreen.enter()    
end

local function switchToGame()
    playerLives = MAX_Lives
    playerLane = MIDDLELANE
    spawnTimer = 150
    Stamina.reset()

    -- Reset wave state; first wave arrives after a full interval
    waveCount  = 0
    waveTimer  = waveInterval(0)
    spawnQueue = 0
    spawnDelay = 0


    background:add()
    updateBg()
    Fists.enter()

    currentScene = SCENE_GAME
end

-- ─── Boot into menu ─────────────────────────────────────────────────────────
 
MenuScreen.enter()

-- ─── Input ──────────────────────────────────────────────────────────────────
 

function pd.leftButtonDown()
    if playerLane == RIGHTLANE then
        playerLane = MIDDLELANE
    elseif playerLane == MIDDLELANE then
        playerLane = LEFTLANE
    end
    updateBg()
end

function pd.rightButtonDown()
    if playerLane == LEFTLANE then
        playerLane = MIDDLELANE
    elseif playerLane == MIDDLELANE then
        playerLane = RIGHTLANE
    end
    updateBg()
end


function pd.AButtonDown() 

    if currentScene == SCENE_MENU then
        switchToGame() 
        return
    end

    if not Stamina.canPunch() then return end
    Stamina.drain()
    Fists.punch()

    --In-Game: Punch behaviour 
    for i = #enemies, 1, -1 do
        local e = enemies[i]
        if e:canBeHit(playerLane, playerRange) then
            e:startDissolve()
        end
    end
end 

function pd.BButtonDown()
    if currentScene ~= SCENE_GAME then return end
    if not Stamina.canSuperPunch() then return end 

    Stamina.drainBonus()
    Fists.superPunch()

    for i = 1, #enemies do 
        local e = enemies[i]
        if not e.dead and e:canBeHit(playerLane, playerRange) then 
            e:push()
        end
    end
end

-- ─── Update loop ────────────────────────────────────────────────────────────
 
local function spawnEnemy() 
    local enemyLane = math.random(1, 3) -- use 1–3 to match your LEFTLANE/MIDDLELANE/RIGHTLANE constants
    local enemy = Enemy(enemyLane)
    table.insert(enemies, enemy)
end


function pd.update() 

    -- Menu Scene
    if currentScene == SCENE_MENU then
        MenuScreen.update()
        return
    end

    --Game Scene 

    --Game Over Check 
    if playerLives <= 0 then
        switchToMenu()
        return 
    end


    -- Wave spawning logic
    if spawnQueue > 0 then
        -- Mid-wave: count down to the next enemy in the burst
        spawnDelay -= 1
        if spawnDelay <= 0 then
            spawnEnemy()
            spawnQueue -= 1
            if spawnQueue > 0 then
                -- More enemies to come; wait some frames before the next one
                spawnDelay = math.random(15, 18)
            else
                -- Wave fully spawned; increment counter and arm the next-wave timer
                waveCount += 1
                waveTimer  = waveInterval(waveCount)
            end
        end
    else
        -- Between waves: count down to the next wave
        waveTimer -= 1
        if waveTimer <= 0 then
            -- Start a new wave; first enemy spawns immediately (spawnDelay = 0)
            spawnQueue = enemiesPerWave(waveCount)
            spawnDelay = 0
        end
    end


    Enemy.setPlayerLane(playerLane)  -- push current lane into enemy module


    Fists.update()
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
                and not re.dissolving 
                and re.lane == pe.lane 
                and pe.progress <= re.progress
                then 
                    re:startDissolve() 
                end
            end
        end
    end


    --Clean up dead Enemies. Enemies that reached the end deal 1 damage.
    for i = #enemies, 1, -1 do 
        local e = enemies[i]
        if e.dead then 
            if e.reachedEnd then 
                takeDamage()
            end
            table.remove(enemies,i) 
        end
    end
    Stamina.update()
    drawHearts()
    pd.drawFPS(0,220)
end 