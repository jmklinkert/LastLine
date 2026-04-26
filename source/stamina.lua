import "CoreLibs/graphics"

local gfx = playdate.graphics
local pd  = playdate

Stamina = {}

-- ─── Constants ───────────────────────────────────────────────────────────────

local MAIN_MAX   = 100
local BONUS_MAX  = 33
local PUNCH_COST = 10

-- Fills the full main bar in exactly 3 seconds at 30 Hz
local FILL_RATE       = MAIN_MAX / (3 * 30)  -- ≈ 1.111 per frame
local CRANK_MIN_SPEED = 1.0                   -- |degrees/frame| required to recover

-- Bar sprite dimensions and screen position
-- Screen is 400×240; bar is 32×176 → right-edge flush, centred vertically
local BAR_W = 32
local BAR_X = 400 - BAR_W                    -- 368
local BAR_Y = math.floor((240 - 176) / 2)    -- 32

-- Pixel regions within the 32×176 sprite (sprite-local coords)
--   Crystal:   y = 0  .. 26  (height 27)
--   Main bar:  y = 28 .. 172 (height 145)
local CRYSTAL_TOP    = 0
local CRYSTAL_HEIGHT = 27   -- 26 - 0 + 1

local MAIN_TOP    = 28
local MAIN_HEIGHT = 145     -- 172 - 28 + 1

-- ─── State ───────────────────────────────────────────────────────────────────

local main  = MAIN_MAX
local bonus = 0

-- ─── Asset ───────────────────────────────────────────────────────────────────

local barImage = gfx.image.new("images/stamina_bar.png")

-- ─── Public API ──────────────────────────────────────────────────────────────

-- Reset to full main stamina and zero bonus (call when starting a new game).
function Stamina.reset()
    main  = MAIN_MAX
    bonus = 0
end

--Returns true if the player has enough stamina to punch 
function Stamina.canPunch()
    return main >= PUNCH_COST
end


-- Drain stamina by PUNCH_COST. Bonus is never consumed.
-- Called once per punch action, regardless of how many enemies are hit.
function Stamina.drain()
    main = math.max(0, main - PUNCH_COST)
end
-- Super Punch  can only be used when the Bonus Bar is full
function Stamina.canSuperPunch() 
    return bonus >= BONUS_MAX
end
-- Super Punch consumes the whole bonus Bar 
function Stamina.drainBonus() 
    bonus = 0 
end

-- Must be called each game-scene frame from pd.update().
-- Reads the crank, updates values, then draws the bar.
function Stamina.update()
    -- Both crank directions recover stamina; a minimum speed prevents accidental drift
    local delta = pd.getCrankChange()
    if math.abs(delta) >= CRANK_MIN_SPEED then
        if main < MAIN_MAX then
            -- Fill main first
            main  = math.min(MAIN_MAX, main + FILL_RATE)
        else
            -- Only fill bonus once main is full
            bonus = math.min(BONUS_MAX, bonus + FILL_RATE)
        end
    end

    Stamina.draw()
end

-- ─── Drawing ─────────────────────────────────────────────────────────────────

function Stamina.draw()
    -- 1. Draw the base (empty) bar image
    barImage:draw(BAR_X, BAR_Y)

    -- 2. Calculate filled pixel heights, clamped to whole pixels
    local mainFilledPx  = math.floor((main  / MAIN_MAX)  * MAIN_HEIGHT)
    local bonusFilledPx = math.floor((bonus / BONUS_MAX) * CRYSTAL_HEIGHT)

    -- 3. Redraw the image inverted, but only within the filled clip region.
    --    The clip restricts the inverted paint to the "full" part of each bar.
    gfx.setImageDrawMode(gfx.kDrawModeInverted)

    -- Main bar: grow upward from y=172 toward y=28
    if mainFilledPx > 0 then
        local clipY = BAR_Y + MAIN_TOP + (MAIN_HEIGHT - mainFilledPx)
        gfx.setClipRect(BAR_X, clipY, BAR_W, mainFilledPx)
        barImage:draw(BAR_X, BAR_Y)
        gfx.clearClipRect()
    end

    -- Bonus crystal: grow upward from y=26 toward y=0
    if bonusFilledPx > 0 then
        local clipY = BAR_Y + CRYSTAL_TOP + (CRYSTAL_HEIGHT - bonusFilledPx)
        gfx.setClipRect(BAR_X, clipY, BAR_W, bonusFilledPx)
        barImage:draw(BAR_X, BAR_Y)
        gfx.clearClipRect()
    end

    -- 4. Always restore draw mode so nothing else is accidentally inverted
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
end