import "CoreLibs/graphics"
import "CoreLibs/sprites"

local gfx = playdate.graphics

DeathAnim = {}

-- ─── Assets ──────────────────────────────────────────────────────────────────
-- Three screen-wide (400x240) frames, played once when an enemy dies to a
-- normal punch. Perspective is baked into the frames, so the animation is only
-- valid for the lane it started on (see DeathAnim.stop / lane-change handling).
local frames      = gfx.imagetable.new("images/enemy_death")
local FRAME_COUNT = 3
local FRAME_HOLD  = 2   -- ticks each frame stays on screen (~0.2 s total at 30 Hz)

-- ─── Sprite & state ──────────────────────────────────────────────────────────
local sprite
local timer = -1   -- -1 = idle, otherwise elapsed ticks within the animation

local function ensureSprite()
    if not sprite then
        sprite = gfx.sprite.new()
        sprite:setCenter(0, 0)
        sprite:moveTo(0, 0)
        sprite:setSize(400, 240)
        sprite:setZIndex(40)      -- above enemies (0) and fists (50)
        sprite:setVisible(false)
    end
end

-- ─── Public API ──────────────────────────────────────────────────────────────

-- Call when entering the game scene.
function DeathAnim.enter()
    ensureSprite()
    sprite:add()
    timer = -1
    sprite:setVisible(false)
end

-- Start (or restart) the death animation from its first frame.
function DeathAnim.play()
    ensureSprite()
    timer = 0
end

-- Abort the animation immediately, e.g. when the player changes lanes and the
-- baked perspective no longer matches. Safe to call at any time.
function DeathAnim.stop()
    if not sprite then return end
    timer = -1
    sprite:setVisible(false)
end

-- Must be called every game-scene frame, BEFORE gfx.sprite.update().
function DeathAnim.update()
    if timer < 0 then return end

    local frame = math.floor(timer / FRAME_HOLD) + 1
    if frame > FRAME_COUNT then
        DeathAnim.stop()
        return
    end

    sprite:setImage(frames:getImage(frame))
    sprite:setVisible(true)
    timer += 1
end
