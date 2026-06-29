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

-- Parallel shadow sheets, indexed by absolute lane offset, frame-matched to the
-- enemy sheets above so a shadow can mirror its enemy's exact frame and flip.
local shadowTables = {
    [0] = gfx.imagetable.new("images/shadow_same"),
    [1] = gfx.imagetable.new("images/shadow_one"),
    [2] = gfx.imagetable.new("images/shadow_two"),
}

local currentPlayerLane = 1

-- Depth ordering: enemies closer to the player (higher progress) draw in front.
-- Kept below the death animation (z 40) and fists (z 50) so they stay foreground.
-- Shadows sit on a single flat layer (SHADOW_Z) beneath the whole enemy band, so
-- a shadow can never be drawn over any enemy.
local SHADOW_Z = 1
local Z_MIN = 2
local Z_MAX = 39

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
    self.damage = 20   -- damage dealt to the player on reaching the end
    self.points = 100  -- score awarded for defeating this enemy with a punch
    self.chainKills = 0 -- enemies this one has defeated while pushed (for the chain bonus)

    self.currentImage = nil
    self.currentFlip = gfx.kImageUnflipped

    --full screen sprite
    self:setCenter(0,0)
    self:moveTo(0,0)
    self:setSize(400,240)
    self:updateDepth()
    self:add()

    -- Companion shadow sprite, drawn on the flat SHADOW_Z layer beneath all enemies
    self.shadow = gfx.sprite.new()
    self.shadow:setCenter(0,0)
    self.shadow:moveTo(0,0)
    self.shadow:setSize(400,240)
    self.shadow:setZIndex(SHADOW_Z)
    self:refreshShadow()
    self.shadow:add()
end

-- Point the shadow sprite at the shadow frame matching this enemy's current
-- frame/flip/lane-offset, so it tracks the enemy exactly.
function Enemy:refreshShadow()
    local _, flip, frame, offset = self:getImageParams()
    self.shadow:setImage(shadowTables[math.abs(offset)]:getImage(frame), flip)
end

-- Map progress (0 = far, 1 = at the player) onto the enemy z-index band so
-- closer enemies always draw in front of further ones, regardless of spawn order.
function Enemy:updateDepth()
    self:setZIndex(Z_MIN + math.floor(self.progress * (Z_MAX - Z_MIN)))
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

-- For the diamond marker: which lane-offset sheet to use (0/1/2), how to flip,
-- and which frame, so the diamond can mirror this enemy exactly.
function Enemy:getMarkerParams()
    local _, flip, frame, offset = self:getImageParams()
    return math.abs(offset), flip, frame
end

-- ─── Public API ──────────────────────────────────────────────────────────────

-- Removing the enemy also disposes of its shadow. Every death path (kill,
-- reached-end, pushed off the lane) routes through here, so the shadow can
-- never outlive its enemy.
function Enemy:remove()
    if self.shadow then
        self.shadow:remove()
        self.shadow = nil
    end
    Enemy.super.remove(self)
end

-- Remove the enemy immediately. The death animation (if any) is driven
-- separately by the caller; the sprite itself just disappears.
function Enemy:kill()
    self.dead = true
    self:remove()
end

-- Triggered by Super Punch. Reverses enemy through the lane
function Enemy:push() 
    self.pushed = true 
end


function Enemy:canBeHit(playerLane, playerRange)
    if self.lane ~= playerLane then return false end

    return self.progress >= (1-playerRange/100)
end

-- ─── Draw override ───────────────────────────────────────────────────────────
-- We never call setImage (which would reset this callback), so this function
-- is responsible for ALL visual output of the sprite.
function Enemy:draw()
    if self.currentImage then
        self.currentImage:draw(0,0, self.currentFlip)
    end
end


function Enemy:update()

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

    -- ── Depth ──
    self:updateDepth()

    -- ── Image ──
    local tbl, flip, frame = self:getImageParams()
    self.currentImage = tbl:getImage(frame)
    self.currentFlip = flip
    self:refreshShadow()
    self:markDirty()
end



