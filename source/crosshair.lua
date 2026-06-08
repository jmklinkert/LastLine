import "CoreLibs/graphics"
import "CoreLibs/sprites"

local gfx = playdate.graphics

Crosshair = {}

-- ─── Assets ──────────────────────────────────────────────────────────────────
-- Three screen-wide (400x240) frames, all centered on the screen:
--   1: the center dot (always at 0,0)
--   2: an arrow, baked next to the dot. Drawn as-is on the left and mirrored on
--      the right, spread outward by arrowOffset.
--   3: the "punchable" reticle, shown alone when an enemy is in punching range.
local frames          = gfx.imagetable.new("images/crosshair")
local DOT_FRAME       = 1
local ARROW_FRAME     = 2
local PUNCHABLE_FRAME = 3

-- How far (px) the arrows sit from the dot when the lane is empty or the nearest
-- enemy is at maximum distance. They close in to 0 as the enemy nears punch range.
local MAX_ARROW_OFFSET = 140

-- ─── Sprite & state ──────────────────────────────────────────────────────────
local sprite
local arrowOffset = MAX_ARROW_OFFSET   -- current px spread of the arrows
local punchable   = false              -- when true, the dot/arrows are replaced

local function render()
    if punchable then
        frames:getImage(PUNCHABLE_FRAME):draw(0, 0)
        return
    end

    -- Center dot
    frames:getImage(DOT_FRAME):draw(0, 0)

    -- Arrows: left as-authored, right mirrored, spread outward by arrowOffset
    local arrow = frames:getImage(ARROW_FRAME)
    arrow:draw(-arrowOffset, 0,  gfx.kImageFlippedX)
    arrow:draw(arrowOffset, 0)
end

local function ensureSprite()
    if not sprite then
        sprite = gfx.sprite.new()
        sprite:setCenter(0, 0)
        sprite:moveTo(0, 0)
        sprite:setSize(400, 240)
        sprite:setZIndex(48)   -- above enemies (1-39) and the diamond (45), below the fists (50)
        sprite.draw = render
    end
end

-- ─── Public API ──────────────────────────────────────────────────────────────

-- Call when entering the game scene.
function Crosshair.enter()
    ensureSprite()
    arrowOffset = MAX_ARROW_OFFSET
    punchable   = false
    sprite:add()
end

-- Drive the crosshair each game-scene frame, BEFORE gfx.sprite.update().
--   lead          : nearest enemy on the player's current lane, or nil
--   isPunchable   : true if that enemy is within punching distance
--   punchThreshold: progress value at which an enemy becomes punchable (0..1)
function Crosshair.update(lead, isPunchable, punchThreshold)
    ensureSprite()

    punchable = isPunchable

    if isPunchable then
        -- Replaced by the punchable reticle; spread is irrelevant
        arrowOffset = 0
    elseif lead then
        -- Closer enemy -> tighter arrows; reaches 0 right at the punch threshold
        local t = lead.progress / punchThreshold   -- 0 (far) .. 1 (at threshold)
        if t > 1 then t = 1 end
        arrowOffset = math.floor(MAX_ARROW_OFFSET * (1 - t))
    else
        -- No enemy on this lane: arrows fully spread
        arrowOffset = MAX_ARROW_OFFSET
    end

    sprite:markDirty()
end
