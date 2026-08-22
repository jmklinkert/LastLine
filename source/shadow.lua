import "CoreLibs/object"
import "CoreLibs/graphics"
import "CoreLibs/sprites"

-- Ground shadows for anything travelling down a lane. The art is a flat ellipse
-- on the tunnel floor, frame-matched to the enemy and booster sheets, so a shadow
-- is simply the same frame number drawn from a parallel sheet: it tracks whatever
-- casts it for free, including the way the gap between caster and shadow opens up
-- as a hovering object gets closer.
--
-- The sheets live here rather than inside enemy.lua or health.lua because both
-- need them and they are 150 frames apiece; owning them in one place keeps a
-- second copy of that art out of memory.

local gfx = playdate.graphics

Shadow = {}

-- Indexed by absolute lane offset, matching the caster sheets' same/one/two split.
local shadowTables = {
    [0] = gfx.imagetable.new("images/shadow_same"),
    [1] = gfx.imagetable.new("images/shadow_one"),
    [2] = gfx.imagetable.new("images/shadow_two"),
}

-- Shadows sit on a single flat layer beneath the whole entity band (z 2-39), so a
-- shadow can never be drawn over its own caster or over anything nearer than it.
Shadow.Z = 1

-- A companion sprite for one caster, full-screen like the casters themselves.
-- The caller owns it: refresh it once, add it, and remove it with the caster.
function Shadow.new()
    local sprite = gfx.sprite.new()
    sprite:setCenter(0, 0)
    sprite:moveTo(0, 0)
    sprite:setSize(400, 240)
    sprite:setZIndex(Shadow.Z)
    return sprite
end

-- Point a shadow sprite at the frame matching its caster's current frame, lane
-- offset and flip.
function Shadow.apply(sprite, absOffset, frame, flip)
    sprite:setImage(shadowTables[absOffset]:getImage(frame), flip)
end
