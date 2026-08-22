import "CoreLibs/object"
import "CoreLibs/graphics"
import "CoreLibs/sprites"
import "shadow"

local gfx = playdate.graphics

class("Health").extends(gfx.sprite)

-- Lane-offset sheets, frame-matched to the enemy sheets: same lane as the player,
-- one over, or two over. The "one"/"two" sheets are mirrored when the booster is
-- to the player's left.
local healthSame = gfx.imagetable.new("images/health_same")
local healthOne  = gfx.imagetable.new("images/health_one")
local healthTwo  = gfx.imagetable.new("images/health_two")

local currentPlayerLane = 1

-- Share the enemy depth band so boosters interleave with enemies/gates by progress.
-- Shadows sit on their own flat layer (Shadow.Z) beneath this whole band.
local Z_MIN = 2
local Z_MAX = 39

-- Passively picked up once on the player's lane and within this reach (%).
local COLLECT_RANGE = 5

function Health.setPlayerLane(lane)
    currentPlayerLane = lane
end

function Health:init(lane)
    Health.super.init(self)

    self.lane = lane
    self.progress = 0
    self.speed = 1 / 5
    self.frameCount = 150

    self.currentImage = nil
    self.currentFlip = gfx.kImageUnflipped

    --full screen sprite
    self:setCenter(0,0)
    self:moveTo(0,0)
    self:setSize(400,240)
    self:updateDepth()
    self:add()

    -- Companion shadow sprite, drawn on the flat shadow layer beneath all entities
    self.shadow = Shadow.new()
    self:refreshShadow()
    self.shadow:add()
end

-- Point the shadow sprite at the shadow frame matching this booster's current
-- frame/flip/lane-offset, so it tracks the booster exactly.
function Health:refreshShadow()
    local _, flip, frame, offset = self:getImageParams()
    Shadow.apply(self.shadow, math.abs(offset), frame, flip)
end

-- Map progress (0 = far, 1 = at the player) onto the z-index band so closer
-- boosters draw in front of further ones.
function Health:updateDepth()
    self:setZIndex(Z_MIN + math.floor(self.progress * (Z_MAX - Z_MIN)))
end

-- ─── Helpers ─────────────────────────────────────────────────────────────────
function Health:getImageParams()
    local offset = self.lane - currentPlayerLane
    local absOffset = math.abs(offset)
    local tbl = healthSame
    local flip = gfx.kImageUnflipped

    if absOffset == 1 then
        tbl = healthOne
        if offset < 0 then flip = gfx.kImageFlippedX end
    elseif absOffset == 2 then
        tbl = healthTwo
        if offset < 0 then flip = gfx.kImageFlippedX end
    end

    local frame = math.min(
        math.max(1, math.floor(self.progress * (self.frameCount - 1)) + 1),
        self.frameCount
    )
    return tbl, flip, frame, offset
end

-- ─── Public API ──────────────────────────────────────────────────────────────

-- Removing the booster also disposes of its shadow. Every disposal path
-- (collected, punched away, drifted past the end) routes through here, so the
-- shadow can never outlive its booster.
function Health:remove()
    if self.shadow then
        self.shadow:remove()
        self.shadow = nil
    end
    Health.super.remove(self)
end

-- Used both for passive collection and for punching it away.
function Health:kill()
    self.dead = true
    self:remove()
end

-- True when on the player's lane and within the passive pickup reach.
function Health:canCollect(playerLane)
    if self.lane ~= playerLane then return false end
    return self.progress >= (1 - COLLECT_RANGE/100)
end

-- True when on the player's lane and within punching reach (destroyed, not collected).
function Health:inRange(playerLane, playerRange)
    if self.lane ~= playerLane then return false end
    return self.progress >= (1 - playerRange/100)
end

-- ─── Draw override ───────────────────────────────────────────────────────────
function Health:draw()
    if self.currentImage then
        self.currentImage:draw(0,0, self.currentFlip)
    end
end

function Health:update()
    -- Boosters only ever drift towards the player; uncollected ones vanish at the end.
    self.progress += self.speed / 30
    if self.progress >= 1 then
        self.dead = true
        self:remove()
        return
    end

    self:updateDepth()

    local tbl, flip, frame = self:getImageParams()
    self.currentImage = tbl:getImage(frame)
    self.currentFlip = flip
    self:refreshShadow()
    self:markDirty()
end
