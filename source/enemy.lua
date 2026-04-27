import "CoreLibs/object"
import "CoreLibs/graphics"
import "CoreLibs/sprites"

local gfx = playdate.graphics

class("Enemy").extends(gfx.sprite)

--imagetables, for if the enemy is on the same lane as the player, one to the right or two to the right
--can be mirrored if the enemy is to the left of the player 
local enemySame = gfx.imagetable.new("images/enemy_same")
local enemyOne = gfx.imagetable.new("images/enemy_one")
local enemyTwo = gfx.imagetable.new("images/enemy_two")

local currentPlayerLane = 1

local DISSOLVE_FRAMES = 10

function Enemy.setPlayerLane(lane)
    currentPlayerLane = lane
end

print(enemySame:getLength(), enemyOne:getLength(), enemyTwo:getLength())
function Enemy:init(lane)
    Enemy.super.init(self)

    self.lane = lane
    self.progress = 0
    self.speed = 1 / 5
    self.frameCount = 150
    self.pushed = false
    self.dissolving = false
    self.dissolveAlpha = 1.0


    self.currentImage = nil
    self.currentFlip = gfx.kImageUnflipped 

    self.bakedDissolveImage = nil
    self.lastBakedOffset = nil


    --full screen sprite 
    self:setCenter(0,0)
    self:moveTo(0,0)
    self:setSize(400,240)
    self:add() 
end

-- ─── Helpers ─────────────────────────────────────────────────────────────────
function Enemy:getImageParams() 
    local offset = self.lane - currentPlayerLane
    local absOffset = math.abs(offset)
    local tbl = enemySame 
    local flip = gfx.kImageUnflipped 

    if absOffset == 1 then
        tbl = enemyOne 
        if offset < 0 then flip = gfx.kImageFlippedX end
    elseif absOffset == 2 then
        tbl = enemyTwo 
        if offset < 0 then flip = gfx.kImageFlippedX end 
    end

    local frame = math.min(
        math.max(1, math.floor(self.progress * (self.frameCount - 1)) + 1),
        self.frameCount
    )
    return tbl, flip, frame, offset 
end

function Enemy:bakeDissolveImage() 
    local tbl, flip, frame, offset = self:getImageParams()
    local src = tbl:getImage(frame)
    local w, h = src:getSize() 
    
    local baked = gfx.image.new(w,h,gfx.kColorClear)
    gfx.pushContext(baked)
    src:draw(0,0, flip)
    gfx.popContext()

    self.bakedDissolveImage = baked
    self.lastBakedOffset = offset
end

-- ─── Public API ──────────────────────────────────────────────────────────────
 
function Enemy:startDissolve() 
    self.dissolving = true
    self.dissolveAlpha = 1.0
    self:bakeDissolveImage() 
    self:markDirty() 
end

-- Triggered by Super Punch. Reverses enemy through the lane 
function Enemy:push() 
    self.pushed = true 
end


function Enemy:canBeHit(playerLane, playerRange)
    if self.lane ~= playerLane then return false end
    if self.dissolving then return false end 

    return self.progress >= (1-playerRange/100)
end

-- ─── Draw override ───────────────────────────────────────────────────────────
-- We never call setImage (which would reset this callback), so this function
-- is responsible for ALL visual output of the sprite.
function Enemy:draw() 
    if self.dissolving then 
        if self.bakedDissolveImage then 
            self.bakedDissolveImage:drawFaded(0,0, self.dissolveAlpha, gfx.image.kDitherTypeBayer8x8)
        end 
    elseif self.currentImage then 
        self.currentImage:draw(0,0, self.currentFlip)
    end 
end


function Enemy:update()

    -- ── Dissolving ──
    if self.dissolving then 
        self.dissolveAlpha -= 1.0 / DISSOLVE_FRAMES
        if self.dissolveAlpha <= 0 then
            self.dead = true 
            self:remove() 
            return 
        end
        -- Re-bake if the player changed lanes mid-dissolve
        local _,_,_, offset = self:getImageParams()
        if offset ~= self.lastBakedOffset then 
            self:bakeDissolveImage()
        end
        self:markDirty()
        return 
    end

    -- ── Progress ──
    if self.pushed then 
        --Move backwards at double speed 
        self.progress -= (self.speed*2)/30

        --Reached the far end of the lane -> simply destroyed, no player damage 
        if self.progress <= 0 then
            self.dead = true
            self:remove()
            return
        end
    else
        -- Normal Advance towards the player
        self.progress += self.speed / 30

        if self.progress >= 1 then
            self.reachedEnd = true --signals main.lua to deal damage
            self:remove()
            self.dead = true 
            return
        end
    end

    -- ── Image ──
    local tbl, flip, frame = self:getImageParams() 
    self.currentImage = tbl:getImage(frame)
    self.currentFlip = flip 
    self:markDirty() 
end



