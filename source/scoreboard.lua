import "CoreLibs/graphics"

local gfx = playdate.graphics

Scoreboard = {}

-- ─── Layout ────────────────────────────────────────────────────────────────────
local LIST_TOP  = 66    -- first leaderboard row
local ROW_H     = 16
local MAX_ROWS  = 8     -- rows that fit above the prompt (matches the stored count)

-- Column x positions (left edges) shared by every row
local COL_RANK  = 30
local COL_SCORE = 70
local COL_WAVE  = 188
local COL_DATE  = 250

-- ─── State ────────────────────────────────────────────────────────────────────
local entries       -- the leaderboard list { score, wave, date }
local currentIndex  -- row of this run, or nil if it didn't place
local currentScore
local currentWave
local blink

-- Draw one leaderboard row's columns at y. Caller sets the draw mode for colour.
local function drawRow(e, rank, y)
    gfx.drawText(rank .. ".", COL_RANK, y)
    gfx.drawText(tostring(e.score), COL_SCORE, y)
    gfx.drawText("W" .. e.wave, COL_WAVE, y)
    gfx.drawText(e.date, COL_DATE, y)
end

-- ─── Public API ────────────────────────────────────────────────────────────────

function Scoreboard.enter(entriesList, index, score, wave)
    entries      = entriesList or {}
    currentIndex = index
    currentScore = score
    currentWave  = wave
    blink        = 0
end

function Scoreboard.update()
    gfx.clear(gfx.kColorBlack)
    gfx.setImageDrawMode(gfx.kDrawModeFillWhite)   -- white text on the black screen

    gfx.drawTextAligned("*SCOREBOARD*", 200, 16, kTextAlignment.center)
    -- The "this run" line only applies when opened right after a run; from the menu
    -- there's no current run, so currentScore is nil and the line is skipped.
    if currentScore then
        gfx.drawTextAligned("This run: " .. currentScore .. "  (Wave " .. currentWave .. ")",
                            200, 40, kTextAlignment.center)
    end

    local rows = math.min(#entries, MAX_ROWS)
    for i = 1, rows do
        local y = LIST_TOP + (i - 1) * ROW_H
        if i == currentIndex then
            -- This run's entry: white bar with black text so it stands out.
            gfx.setColor(gfx.kColorWhite)
            gfx.fillRect(COL_RANK - 6, y - 1, 352, ROW_H)
            gfx.setImageDrawMode(gfx.kDrawModeCopy)        -- native (black) text
            drawRow(entries[i], i, y)
            gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
        else
            drawRow(entries[i], i, y)
        end
    end

    if #entries == 0 then
        gfx.drawTextAligned("No scores yet", 200, LIST_TOP + 20, kTextAlignment.center)
    end

    -- Blinking prompt
    if (blink % 30) < 21 then
        gfx.drawTextAligned("Press A for Menu", 200, 222, kTextAlignment.center)
    end
    blink += 1

    gfx.setImageDrawMode(gfx.kDrawModeCopy)
end
