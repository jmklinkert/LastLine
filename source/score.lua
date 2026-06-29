local pd = playdate

Score = {}

-- Persisted leaderboard lives in scores.json; we keep the best MAX_ENTRIES runs.
local DATASTORE_FILE = "scores"
local MAX_ENTRIES    = 8

local current     = 0      -- score of the run in progress
local leaderboard = nil    -- lazily-loaded list of { score, wave, date }

-- ─── Live score ───────────────────────────────────────────────────────────────

function Score.reset()
    current = 0
end

-- Add (or, with a negative amount, subtract) points. Never drops below zero.
function Score.add(points)
    current = math.max(0, current + points)
end

function Score.get()
    return current
end

-- ─── Leaderboard ───────────────────────────────────────────────────────────────

local function ensureLoaded()
    if leaderboard then return end
    local data = pd.datastore.read(DATASTORE_FILE)
    leaderboard = (data and data.entries) or {}
end

-- Current local date as "YYYY-MM-DD".
local function today()
    local t = pd.getTime()
    return string.format("%04d-%02d-%02d", t.year, t.month, t.day)
end

-- Record a finished run (score + wave reached, stamped with today's date) into the
-- leaderboard and persist it. Returns the sorted leaderboard and the 1-based index
-- of this run within it, or nil if the run didn't make the top MAX_ENTRIES.
function Score.record(score, wave)
    ensureLoaded()

    local entry = { score = score, wave = wave, date = today() }
    leaderboard[#leaderboard + 1] = entry

    table.sort(leaderboard, function(a, b) return a.score > b.score end)

    while #leaderboard > MAX_ENTRIES do
        table.remove(leaderboard)
    end

    -- Locate our entry by identity, so ties never confuse the highlight.
    local index = nil
    for i = 1, #leaderboard do
        if leaderboard[i] == entry then
            index = i
            break
        end
    end

    pd.datastore.write({ entries = leaderboard }, DATASTORE_FILE)
    return leaderboard, index
end
