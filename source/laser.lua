import "CoreLibs/object"
import "CoreLibs/graphics"
import "CoreLibs/sprites"

local gfx = playdate.graphics

class("Laser").extends(gfx.sprite)

-- Lane-offset sheets, frame-matched to the enemy sheets: same lane as the player,
-- one over, or two over. The "one"/"two" sheets are mirrored when the gate is to
-- the player's left.
local laserSame = gfx.imagetable.new("images/laser_same")
local laserOne  = gfx.imagetable.new("images/laser_one")
local laserTwo  = gfx.imagetable.new("images/laser_two")

local currentPlayerLane = 1

-- Share the enemy depth band so gates and enemies interleave purely by progress:
-- whatever is closer to the player draws in front, gate or not.
local Z_MIN = 2
local Z_MAX = 39

function Laser.setPlayerLane(lane)
    currentPlayerLane = lane
end

function Laser:init(lane)
    Laser.super.init(self)

    self.lane = lane
    self.progress = 0
    self.speed = 1 / 5
    self.frameCount = 150
    self.damage = 20   -- dealt to the player when the gate reaches the end on their lane

    self.currentImage = nil
    self.currentFlip = gfx.kImageUnflipped

    --full screen sprite
    self:setCenter(0,0)
    self:moveTo(0,0)
    self:setSize(400,240)
    self:updateDepth()
    self:add()
end

-- Map progress (0 = far, 1 = at the player) onto the z-index band so closer
-- gates draw in front of further ones.
function Laser:updateDepth()
    self:setZIndex(Z_MIN + math.floor(self.progress * (Z_MAX - Z_MIN)))
end

-- ─── Helpers ─────────────────────────────────────────────────────────────────
function Laser:getImageParams()
    local offset = self.lane - currentPlayerLane
    local absOffset = math.abs(offset)
    local tbl = laserSame
    local flip = gfx.kImageUnflipped

    if absOffset == 1 then
        tbl = laserOne
        if offset < 0 then flip = gfx.kImageFlippedX end
    elseif absOffset == 2 then
        tbl = laserTwo
        if offset < 0 then flip = gfx.kImageFlippedX end
    end

    local frame = math.min(
        math.max(1, math.floor(self.progress * (self.frameCount - 1)) + 1),
        self.frameCount
    )
    return tbl, flip, frame, offset
end

-- ─── Public API ──────────────────────────────────────────────────────────────

-- Gates can never be destroyed by the player; this only exists so a pushed enemy
-- that retreats into the gate can be removed (the gate itself stays).
function Laser:kill()
    self.dead = true
    self:remove()
end

-- True when the gate is on the player's lane and within punching reach. A punch
-- here hurts the player and leaves the gate intact.
function Laser:inRange(playerLane, playerRange)
    if self.lane ~= playerLane then return false end
    return self.progress >= (1 - playerRange/100)
end

-- ─── Draw override ───────────────────────────────────────────────────────────
function Laser:draw()
    if self.currentImage then
        self.currentImage:draw(0,0, self.currentFlip)
    end
end

function Laser:update()
    -- Gates only ever advance towards the player; they can't be pushed or killed.
    self.progress += self.speed / 30
    if self.progress >= 1 then
        self.reachedEnd = true   -- signals main.lua to damage the player if same-lane
        self:remove()
        self.dead = true
        return
    end

    self:updateDepth()

    local tbl, flip, frame = self:getImageParams()
    self.currentImage = tbl:getImage(frame)
    self.currentFlip = flip
    self:markDirty()
end
