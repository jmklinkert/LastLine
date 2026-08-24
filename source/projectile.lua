import "CoreLibs/object"
import "CoreLibs/graphics"
import "CoreLibs/sprites"
import "shadow"

local gfx = playdate.graphics

class("Projectile").extends(gfx.sprite)

-- Lane-offset sheets, frame-matched to the enemy sheets: same lane as the player,
-- one over, or two over. The "one"/"two" sheets are mirrored when the shot is to
-- the player's left.
local projectileSame = gfx.imagetable.new("images/projectile_same")
local projectileOne  = gfx.imagetable.new("images/projectile_one")
local projectileTwo  = gfx.imagetable.new("images/projectile_two")

local currentPlayerLane = 1

-- Share the enemy depth band so shots interleave with everything else by progress.
-- Shadows sit on their own flat layer (Shadow.Z) beneath this whole band.
local Z_MIN = 2
local Z_MAX = 39

-- ─── Tuning ──────────────────────────────────────────────────────────────────

-- Well above an enemy's 1/5: a shot crosses the whole lane in about 2.5 s where an
-- enemy takes 5 s, so it reads as fast and has to be reacted to rather than planned
-- around. Fired from the turret's parking spot it only has the rest of the lane to
-- cover, which takes about a second.
local SPEED = 1 / 2.5

-- A shot only hurts the player it actually reaches, so it's cheaper than walking
-- into an enemy; the pressure comes from the cadence, not from any single hit.
local DAMAGE = 10

function Projectile.setPlayerLane(lane)
    currentPlayerLane = lane
end

-- Spawned at the firing turret's position rather than at the top of the lane, so it
-- appears to leave the barrel.
function Projectile:init(lane, progress)
    Projectile.super.init(self)

    self.lane = lane
    self.progress = progress or 0
    self.speed = SPEED
    self.frameCount = 150
    self.damage = DAMAGE
    self.pushed = false

    self.currentImage = nil
    self.currentFlip = gfx.kImageUnflipped

    --full screen sprite
    self:setCenter(0,0)
    self:moveTo(0,0)
    self:setSize(400,240)
    self:updateDepth()
    self:add()

    -- Companion shadow sprite. Projectiles use the square-cornered shadow set so a
    -- shot on the floor is never mistaken for an enemy or a booster.
    self.shadow = Shadow.new()
    self:refreshShadow()
    self.shadow:add()
end

function Projectile:refreshShadow()
    local _, flip, frame, offset = self:getImageParams()
    Shadow.apply(self.shadow, math.abs(offset), frame, flip, Shadow.PROJECTILE)
end

-- Map progress (0 = far, 1 = at the player) onto the z-index band so closer shots
-- draw in front of further ones.
function Projectile:updateDepth()
    self:setZIndex(Z_MIN + math.floor(self.progress * (Z_MAX - Z_MIN)))
end

-- ─── Helpers ─────────────────────────────────────────────────────────────────
function Projectile:getImageParams()
    local offset = self.lane - currentPlayerLane
    local absOffset = math.abs(offset)
    local tbl = projectileSame
    local flip = gfx.kImageUnflipped

    if absOffset == 1 then
        tbl = projectileOne
        if offset < 0 then flip = gfx.kImageFlippedX end
    elseif absOffset == 2 then
        tbl = projectileTwo
        if offset < 0 then flip = gfx.kImageFlippedX end
    end

    local frame = math.min(
        math.max(1, math.floor(self.progress * (self.frameCount - 1)) + 1),
        self.frameCount
    )
    return tbl, flip, frame, offset
end

-- ─── Public API ──────────────────────────────────────────────────────────────

-- Removing the shot also disposes of its shadow, so the shadow can never outlive it.
function Projectile:remove()
    if self.shadow then
        self.shadow:remove()
        self.shadow = nil
    end
    Projectile.super.remove(self)
end

-- Shot down by a punch, or consumed destroying the turret that fired it.
function Projectile:kill()
    self.dead = true
    self:remove()
end

-- Triggered by Super Punch. Sends the shot back up its own lane, where it becomes
-- the ammunition for taking out the turret that fired it.
function Projectile:push()
    self.pushed = true
end

-- True when on the player's lane and within punching reach.
function Projectile:canBeHit(playerLane, playerRange)
    if self.lane ~= playerLane then return false end
    return self.progress >= (1 - playerRange/100)
end

-- ─── Draw override ───────────────────────────────────────────────────────────
function Projectile:draw()
    if self.currentImage then
        self.currentImage:draw(0,0, self.currentFlip)
    end
end

function Projectile:update()
    if self.pushed then
        -- Travelling back up the lane at double speed, same as a pushed enemy.
        self.progress -= (self.speed * 2) / 30

        -- Off the far end without hitting anything: simply gone.
        if self.progress <= 0 then
            self.dead = true
            self:remove()
            return
        end
    else
        self.progress += self.speed / 30

        if self.progress >= 1 then
            self.reachedEnd = true   -- signals Field to damage the player if same-lane
            self:remove()
            self.dead = true
            return
        end
    end

    self:updateDepth()

    local tbl, flip, frame = self:getImageParams()
    self.currentImage = tbl:getImage(frame)
    self.currentFlip = flip
    self:refreshShadow()
    self:markDirty()
end
