

-- Importing libraries used for drawCircleAtPoint and crankIndicator
import "CoreLibs/graphics"
import "CoreLibs/sprites"
import "CoreLibs/ui"
import "enemy"
import "menuScreen"

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

    background:add()
    updateBg()

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

    --In-Game: Punch behaviour 
    for i = #enemies, 1, -1 do
        local e = enemies[i]
        if e:canBeHit(playerLane, playerRange) then
            e:remove()
            table.remove(enemies, i)
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


    spawnTimer -= 1
    if spawnTimer <= 0 then
        spawnEnemy()
        spawnTimer = 150
    end


    Enemy.setPlayerLane(playerLane)  -- push current lane into enemy module
    gfx.sprite.update()


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

    drawHearts()
    pd.drawFPS(0,220)
end 