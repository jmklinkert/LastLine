import "CoreLibs/graphics"
import "CoreLibs/sprites"

local gfx = playdate.graphics

Diamond = {}

-- ─── Assets ──────────────────────────────────────────────────────────────────
-- Three screen-wide (400x240) sheets, frame-matched to the enemy sheets, with
-- the diamond baked above the enemy for each lane offset. Indexed by abs lane
-- offset (0 = same lane, 1 = one over, 2 = two over).
local sheets = {
    [0] = gfx.imagetable.new("images/diamond_same"),
    [1] = gfx.imagetable.new("images/diamond_one"),
    [2] = gfx.imagetable.new("images/diamond_two"),
}

-- ─── Timing ──────────────────────────────────────────────────────────────────
local BLINK_PERIOD = 2   -- ticks per on/off cycle while the enemy is punchable

-- ─── Sprite & state ──────────────────────────────────────────────────────────
local sprite
local blinkTimer = 0

local function ensureSprite()
    if not sprite then
        sprite = gfx.sprite.new()
        sprite:setCenter(0, 0)
        sprite:moveTo(0, 0)
        sprite:setSize(400, 240)
        sprite:setZIndex(45)      -- above enemies (1-39) and the death flash (40)
        -- The diamond art is black-on-transparent. NXOR inverts whatever is
        -- behind the marker's pixels (NOT(dest XOR 0) = NOT dest), so it stays
        -- visible over both dark and light areas. (Plain XOR is a no-op on black
        -- pixels, and Inverted just makes the diamond white.) Free draw flag, so
        -- no separate inverted spritesheet is needed.
        sprite:setImageDrawMode(gfx.kDrawModeNXOR)
        sprite:setVisible(false)
    end
end

-- ─── Public API ──────────────────────────────────────────────────────────────

-- Call when entering the game scene.
function Diamond.enter()
    ensureSprite()
    sprite:add()
    blinkTimer = 0
    sprite:setVisible(false)
end

-- Drive the marker each game-scene frame, BEFORE gfx.sprite.update().
--   lead      : the enemy nearest the player (highest progress), or nil if none
--   punchable : true if that enemy can currently be hit (blink fast)
function Diamond.update(lead, punchable)
    ensureSprite()

    -- No enemy on screen: hide and reset the blink phase.
    if not lead then
        sprite:setVisible(false)
        blinkTimer = 0
        return
    end

    -- Mirror the leading enemy: same sheet (by lane offset), frame and flip.
    local absOffset, flip, frame = lead:getMarkerParams()
    sprite:setImage(sheets[absOffset]:getImage(frame), flip)

    if punchable then
        -- Fast blink while the enemy is in range
        blinkTimer = (blinkTimer + 1) % BLINK_PERIOD
        sprite:setVisible(blinkTimer < BLINK_PERIOD / 2)
    else
        blinkTimer = 0
        sprite:setVisible(true)
    end
end
