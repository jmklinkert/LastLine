import "CoreLibs/object"
import "CoreLibs/graphics"
import "CoreLibs/sprites"

local gfx = playdate.graphics

class("Enemy").extends(gfx.sprite)

local enemySame = gfx.imagetable.new("images/enemy_same")
local enemyOne = gfx.imagetable.new("images/enemy_one")
local enemyTwo = gfx.imagetable.new("images/enemy_two")

print("same:", enemySame and enemySame:getLength())
print("one:", enemyOne and enemyOne:getLength())
print("two:", enemyTwo and enemyTwo:getLength())

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

    --full screen sprite 
    self:setCenter(0,0)
    self:moveTo(0,0)
    self:add() 
end

function Enemy:update()
    self.progress += self.speed / 30

    if self.progress >= 1 then
        self:remove()
        self.dead = true 
        return
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
local frame = math.min(math.floor(self.progress * (self.frameCount - 1)) + 1, self.frameCount)
    self:setImage(tableToUse:getImage(frame))
    self:setImageFlip(flip)
end

function Enemy:canBeHit(playerLane, playerRange)
    if self.lane ~= playerLane then
        return false
    end

    return self.progress >= (1-playerRange/100)
end


