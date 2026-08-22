import "CoreLibs/object"
import "CoreLibs/graphics"
import "CoreLibs/sprites"
import "shadow"

local gfx = playdate.graphics

class("Turret").extends(gfx.sprite)

-- Lane-offset sheets, frame-matched to the enemy sheets: same lane as the player,
-- one over, or two over. The "one"/"two" sheets are mirrored when the turret is to
-- the player's left.
local turretSame = gfx.imagetable.new("images/turret_same")
local turretOne  = gfx.imagetable.new("images/turret_one")
local turretTwo  = gfx.imagetable.new("images/turret_two")

local currentPlayerLane = 1

-- Share the enemy depth band so turrets interleave with everything else by progress.
-- Shadows sit on their own flat layer (Shadow.Z) beneath this whole band.
local Z_MIN = 2
local Z_MAX = 39

-- ─── Tuning ──────────────────────────────────────────────────────────────────

-- How far down the lane the turret advances before it digs in for good. Everything
-- about how the turret plays follows from this: it parks well outside the player's
-- punch reach (which only extends back to progress 0.85), which is what makes it
-- unreachable by fists and killable only by shoving something back into it. The
-- frame sheets run the full lane, so a lower value also means a smaller turret.
local STOP_PROGRESS = 0.60

-- Slower than an enemy's 1/5, so a turret takes its time claiming a lane.
local APPROACH_SPEED = 1 / 8

-- Frames between shots once parked. 30 Hz, so 45 frames is one shot every 1.5 s.
local FIRE_INTERVAL = 60

function Turret.setPlayerLane(lane)
    currentPlayerLane = lane
end

function Turret:init(lane)
    Turret.super.init(self)

    self.lane = lane
    self.progress = 0
    self.speed = APPROACH_SPEED
    self.frameCount = 150
    self.points = 250   -- score awarded for destroying this turret

    self.parked = false      -- true once it has reached STOP_PROGRESS
    self.fireTimer = 0       -- frames until the next shot
    self.fireReady = false   -- set for one frame when a shot is due; Field spawns it

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

-- Point the shadow sprite at the shadow frame matching this turret's current
-- frame/flip/lane-offset. A turret uses the ordinary ground shadow; only its
-- projectiles get the square one.
function Turret:refreshShadow()
    local _, flip, frame, offset = self:getImageParams()
    Shadow.apply(self.shadow, math.abs(offset), frame, flip)
end

-- Map progress (0 = far, 1 = at the player) onto the z-index band so closer
-- turrets draw in front of further ones.
function Turret:updateDepth()
    self:setZIndex(Z_MIN + math.floor(self.progress * (Z_MAX - Z_MIN)))
end

-- ─── Helpers ─────────────────────────────────────────────────────────────────
function Turret:getImageParams()
    local offset = self.lane - currentPlayerLane
    local absOffset = math.abs(offset)
    local tbl = turretSame
    local flip = gfx.kImageUnflipped

    if absOffset == 1 then
        tbl = turretOne
        if offset < 0 then flip = gfx.kImageFlippedX end
    elseif absOffset == 2 then
        tbl = turretTwo
        if offset < 0 then flip = gfx.kImageFlippedX end
    end

    local frame = math.min(
        math.max(1, math.floor(self.progress * (self.frameCount - 1)) + 1),
        self.frameCount
    )
    return tbl, flip, frame, offset
end

-- ─── Public API ──────────────────────────────────────────────────────────────

-- Removing the turret also disposes of its shadow, so the shadow can never
-- outlive it.
function Turret:remove()
    if self.shadow then
        self.shadow:remove()
        self.shadow = nil
    end
    Turret.super.remove(self)
end

-- Destroyed. The only route here is Field shoving a pushed enemy or projectile
-- back into it; nothing the player can reach directly will call this.
function Turret:kill()
    self.dead = true
    self:remove()
end

-- ─── Draw override ───────────────────────────────────────────────────────────
function Turret:draw()
    if self.currentImage then
        self.currentImage:draw(0,0, self.currentFlip)
    end
end

function Turret:update()
    -- Advance until the parking spot, then hold position forever. A turret never
    -- reaches the player, so it has no reachedEnd case and deals no contact damage;
    -- everything it does to the player comes out of the barrel.
    if not self.parked then
        self.progress += self.speed / 30
        if self.progress >= STOP_PROGRESS then
            self.progress = STOP_PROGRESS
            self.parked = true
            self.fireTimer = FIRE_INTERVAL
        end
        self:updateDepth()
    else
        -- Fixed cadence: every shot is the same interval apart, so the rhythm is
        -- learnable. Field polls fireReady and owns the projectile it spawns.
        self.fireTimer -= 1
        if self.fireTimer <= 0 then
            self.fireTimer = FIRE_INTERVAL
            self.fireReady = true
        end
    end

    local tbl, flip, frame = self:getImageParams()
    self.currentImage = tbl:getImage(frame)
    self.currentFlip = flip
    self:refreshShadow()
    self:markDirty()
end
