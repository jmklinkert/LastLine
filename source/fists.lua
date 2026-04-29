import "CoreLibs/graphics"
import "CoreLibs/sprites"

local gfx = playdate.graphics

Fists = {}

-- ─── Assets ──────────────────────────────────────────────────────────────────

local fistImages     = gfx.imagetable.new("images/fists")
local IDLE_FRAME     = 1   -- ready pose
local EXTENDED_FRAME = 2   -- impact pose

-- ─── Layout ──────────────────────────────────────────────────────────────────

local BASE_Y = 3   -- both fists drawn 3px lower than the image's natural origin

-- ─── Idle bob ────────────────────────────────────────────────────────────────

local IDLE_PERIOD    = 30  -- 1 second cycle at 30 Hz
local IDLE_HALF      = 15
local IDLE_AMPLITUDE = 5   -- max downward displacement
local LEFT_LAG       = 2   -- frames the left fist trails the right

-- ─── Punch animation keyframes ───────────────────────────────────────────────
-- Format per row: {frame, xOffset, yOffset}
-- Offsets are relative to rest position. Linear interpolation between rows.

-- The fist that's actually throwing the punch
local punchKeyframes = {
    {0,   0,   0},
    {2,  16,  32},   -- windup end
    {4,  -2,  -3},   -- impact end
    {6,  -2,  -3},   -- linger end (held position)
    {9,   0,   0},   -- recovery end
}

-- The other fist, which braces and pulls back
local supportKeyframes = {
    {0,   0,   0},
    {2,  16,  -3},   -- windup end
    {4, -64,  29},   -- impact end
    {6, -64,  29},   -- linger end
    {9,   0,   0},   -- recovery end
}

local PUNCH_DURATION = 9
-- Extended sprite shown while punching: from start of impact movement
-- through the first frame of recovery (per spec).
local EXTENDED_START = 3
local EXTENDED_END   = 7

-- ─── Sprites & state ─────────────────────────────────────────────────────────

local rightSprite, leftSprite
local idleTimer  = 0
local punchTimer = -1   -- -1 = idle, otherwise current frame within punch
local isSuper    = false

-- ─── Helpers ─────────────────────────────────────────────────────────────────

local function lerpKeyframes(kfs, t)
    if t <= kfs[1][1] then return kfs[1][2], kfs[1][3] end
    for i = 1, #kfs - 1 do
        local a, b = kfs[i], kfs[i + 1]
        if t <= b[1] then
            local alpha = (t - a[1]) / (b[1] - a[1])
            return a[2] + alpha * (b[2] - a[2]),
                   a[3] + alpha * (b[3] - a[3])
        end
    end
    return kfs[#kfs][2], kfs[#kfs][3]
end

-- Triangle wave: rises from 0 to IDLE_AMPLITUDE over IDLE_HALF frames,
-- then falls back. Negative inputs are handled by Lua's % returning non-negative.
local function idleYOffset(timer)
    local t = timer % IDLE_PERIOD
    if t < IDLE_HALF then
        return (t / IDLE_HALF) * IDLE_AMPLITUDE
    else
        return ((IDLE_PERIOD - t) / IDLE_HALF) * IDLE_AMPLITUDE
    end
end

local function ensureSprites()
    if not rightSprite then
        rightSprite = gfx.sprite.new()
        rightSprite:setCenter(0, 0)
        rightSprite:setZIndex(50)   -- above enemies
    end
    if not leftSprite then
        leftSprite = gfx.sprite.new()
        leftSprite:setCenter(0, 0)
        leftSprite:setZIndex(50)
    end
end

-- ─── Public API ──────────────────────────────────────────────────────────────

-- Call when entering the game scene (after the menu's sprite.removeAll).
function Fists.enter()
    ensureSprites()
    rightSprite:add()
    leftSprite:add()
    idleTimer  = 0
    punchTimer = -1
    isSuper    = false
end

-- Trigger a regular punch (right fist). No-op if a punch is already in flight.
function Fists.punch()
    if punchTimer < 0 then
        punchTimer = 1
        isSuper    = false
    end
end

-- Trigger a super punch (left fist). No-op if a punch is already in flight.
function Fists.superPunch()
    if punchTimer < 0 then
        punchTimer = 1
        isSuper    = true
    end
end

-- Must be called every game-scene frame, BEFORE gfx.sprite.update(),
-- so the sprite positions/images are committed for that frame's render.
function Fists.update()
    local rx, ry, lx, ly         = 0, 0, 0, 0
    local rExtended, lExtended   = false, false

    if punchTimer >= 0 then
        local punchX, punchY = lerpKeyframes(punchKeyframes, punchTimer)
        local supX,   supY   = lerpKeyframes(supportKeyframes, punchTimer)
        local extended = punchTimer >= EXTENDED_START
                         and punchTimer <= EXTENDED_END

        if isSuper then
            -- Left fist punches; both x values mirrored
            lx, ly    = -punchX, punchY
            rx, ry    = -supX,   supY
            lExtended = extended
        else
            rx, ry    = punchX, punchY
            lx, ly    = supX,   supY
            rExtended = extended
        end

        punchTimer += 1
        if punchTimer > PUNCH_DURATION then
            punchTimer = -1
        end
    else
        -- Idle bob; left fist trails by LEFT_LAG frames for a natural feel
        ry = idleYOffset(idleTimer)
        ly = idleYOffset(idleTimer - LEFT_LAG)
        idleTimer = (idleTimer + 1) % IDLE_PERIOD
    end

    -- Commit to sprites. Flip is set every frame on setImage so it survives
    -- any potential image-swap reset and stays explicit.
    local rightImage = fistImages:getImage(rExtended and EXTENDED_FRAME or IDLE_FRAME)
    local leftImage  = fistImages:getImage(lExtended and EXTENDED_FRAME or IDLE_FRAME)

    rightSprite:setImage(rightImage)
    leftSprite:setImage(leftImage, gfx.kImageFlippedX)

    rightSprite:moveTo(math.floor(rx), BASE_Y + math.floor(ry))
    leftSprite:moveTo(math.floor(lx),  BASE_Y + math.floor(ly))
end