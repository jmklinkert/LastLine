import "CoreLibs/graphics"

local gfx = playdate.graphics

GameOver = {}

-- ─── Layout / timing ──────────────────────────────────────────────────────────
local CX, CY        = 200, 120     -- screen centre; the dissolve grows from here
local MAX_R         = 240          -- radius that fully covers the screen + corners
local DISSOLVE_TIME = 24          -- frames (~0.8 s at 30 Hz) for the screen to go black
local TEXT_SCALE    = 3            -- big "GAME OVER" is the default font scaled up
local TEXT_FADE     = 12           -- frames the title fades in once the screen is black

-- Ragged leading edge of the dissolve: a few black-dot rings just beyond the
-- solid core, getting sparser outward, so the screen looks like it crumbles away
-- rather than wiping with a clean circle. {extraRadius, blackCoverage}.
local EDGE_BANDS = {
    { 8,  0.65 },
    { 16, 0.35 },
    { 26, 0.15 },
}

-- ─── State ────────────────────────────────────────────────────────────────────
local snapshot      -- frozen final frame we disintegrate
local titleImage    -- pre-baked big white "GAME OVER"
local phase         -- "dissolve" | "screen"
local elapsed       -- frames within the current phase
local promptBlink   -- frame counter for the blinking prompt

-- ─── Helpers ──────────────────────────────────────────────────────────────────

-- Bake "GAME OVER" once: render the default font white onto a transparent image,
-- then scale that up into the final title image so it can be faded as one unit.
local function bakeTitle()
    local text = "GAME OVER"
    local tw, th = gfx.getTextSize(text)

    local small = gfx.image.new(tw, th)
    gfx.pushContext(small)
        gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
        gfx.drawText(text, 0, 0)
    gfx.popContext()
    gfx.setImageDrawMode(gfx.kDrawModeCopy)

    local big = gfx.image.new(tw * TEXT_SCALE, th * TEXT_SCALE)
    gfx.pushContext(big)
        small:drawScaled(0, 0, TEXT_SCALE)
    gfx.popContext()
    return big
end

-- ─── Public API ──────────────────────────────────────────────────────────────

-- Begin the game-over sequence. `image` is the last frame that was on screen
-- (captured by the caller); we disintegrate that rather than the live scene, so
-- no gameplay sprites need to keep updating behind the effect.
function GameOver.begin(image)
    snapshot    = image
    titleImage  = titleImage or bakeTitle()
    phase       = "dissolve"
    elapsed     = 0
    promptBlink = 0
end

-- True once the title screen is up and the player may press A to leave.
function GameOver.isInteractive()
    return phase == "screen"
end

-- Draw the static title screen: big white title plus a blinking prompt.
local function drawScreen()
    gfx.clear(gfx.kColorBlack)

    local tw, th = titleImage:getSize()
    local alpha = math.min(1, elapsed / TEXT_FADE)
    titleImage:drawFaded((400 - tw) // 2, 88, alpha, gfx.image.kDitherTypeBayer4x4)

    -- Prompt blinks on for ~0.7 s, off for ~0.3 s, only after the title is in.
    if elapsed >= TEXT_FADE and (promptBlink % 30) < 21 then
        gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
        gfx.drawTextAligned("Press A for Menu", 200, 172, kTextAlignment.center)
        gfx.setImageDrawMode(gfx.kDrawModeCopy)
    end
    promptBlink += 1
end

-- Draw one frame of the dissolve: the frozen snapshot eaten away by an expanding
-- black core with a grainy edge.
local function drawDissolve()
    snapshot:draw(0, 0)

    local radius = (elapsed / DISSOLVE_TIME) * MAX_R

    -- Solid black core
    gfx.setColor(gfx.kColorBlack)
    gfx.fillCircleAtPoint(CX, CY, radius)

    -- Grainy rings beyond the core, sparser the further out they go
    for i = 1, #EDGE_BANDS do
        local extra, coverage = EDGE_BANDS[i][1], EDGE_BANDS[i][2]
        gfx.setDitherPattern(coverage, gfx.image.kDitherTypeBayer8x8)
        gfx.fillCircleAtPoint(CX, CY, radius + extra)
    end
    gfx.setColor(gfx.kColorBlack)  -- clear the dither pattern for later draws
end

-- Drive the sequence; call every frame while the game-over scene is active.
function GameOver.update()
    if phase == "dissolve" then
        drawDissolve()
        elapsed += 1
        if elapsed > DISSOLVE_TIME then
            phase    = "screen"
            elapsed  = 0
            snapshot = nil   -- free the full-screen capture
        end
    else
        drawScreen()
        elapsed += 1
    end
end
