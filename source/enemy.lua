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

    --full screen sprite 
    self:setCenter(0,0)
    self:moveTo(0,0)
    self:add() 
end

function Enemy:push() 
    self.pushed = true 
end

function Enemy:update()
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
    local offset = self.lane - currentPlayerLane
    local absOffset = math.abs(offset)

    local tableToUse = enemySame
    local flip = gfx.kImageUnflipped

    if absOffset == 0 then 
        tableToUse = enemySame
    elseif absOffset == 1 then
        tableToUse = enemyOne 
        if offset < 0 then flip = gfx.kImageFlippedX end 
    elseif absOffset == 2 then
        tableToUse = enemyTwo
        if offset < 0 then flip = gfx.kImageFlippedX end
    end
    local frame = math.min(
        math.max(1, math.floor(self.progress * (self.frameCount - 1)) + 1),
        self.frameCount
    )
    self:setImage(tableToUse:getImage(frame))
    self:setImageFlip(flip)
end

function Enemy:canBeHit(playerLane, playerRange)
    if self.lane ~= playerLane then
        return false
    end

    return self.progress >= (1-playerRange/100)
end


