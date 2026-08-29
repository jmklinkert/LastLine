import "CoreLibs/graphics"
import "CoreLibs/sprites"
import "field"
import "sounds"

local gfx = playdate.graphics

-- The boss fight: a starship that fills the tunnel, spanning all three lanes with a
-- blaster on each. It runs as a self-contained state machine on top of the ordinary
-- Field simulation — phase 1 shoots real Enemy entities that the player shoves back,
-- so the existing punch/super-punch/shadow code does the work — and reports anything
-- that crosses back into the run (laser damage, the kill) as an event list, the same
-- contract Field.update uses.
--
-- main.lua owns the wave that hosts the fight, the player lane and the input; this
-- module owns the phases, the boss's own health bar, its attacks and its animations.
Boss = {}

-- Lane ids, matching main.lua.
local LEFTLANE, MIDDLELANE, RIGHTLANE = 1, 2, 3

-- ─── Art ─────────────────────────────────────────────────────────────────────
-- Naming convention for these sheets (different from the tunnel background!): a
-- "_left" variant depicts the boss to the LEFT of the camera, which is what the
-- player sees from the RIGHT lane. The LEFT lane gets that same art mirrored, and
-- the middle lane has its own straight-on "_front" art. The boss spans every lane,
-- so those two perspectives cover all three positions.
local ART = "images/Boss-Sprites/"

local introTable      = gfx.imagetable.new(ART .. "1. Introduction/boss_introduction")
local transitionTable = gfx.imagetable.new(ART .. "2. Transition/boss_transition")

local deathTable = {
    front = gfx.imagetable.new(ART .. "6. Death/boss_death_front"),
    left  = gfx.imagetable.new(ART .. "6. Death/boss_death_left"),
}

local phase1Body = {
    front = gfx.image.new(ART .. "Phase1-sprites/Boss_Phase1_front"),
    left  = gfx.image.new(ART .. "Phase1-sprites/Boss_Phase1_left"),
}
local phase2Body = {
    front = gfx.image.new(ART .. "Phase2-sprites/Boss_Phase2_front"),
    left  = gfx.image.new(ART .. "Phase2-sprites/Boss_Phase2_left"),
}

-- Shoot indications (phase 1 only). Which image a blaster uses depends on how many
-- lanes away it is from the player: the centre blaster can only ever be 0 or 1 away,
-- while a side blaster can be 0, 1 or 2 — which is why only the sides have a "two".
local SI = ART .. "3. Shoot-Indication/"
local indMiddle = {
    [0] = gfx.image.new(SI .. "Shoot_indication_middle_front"),
    [1] = gfx.image.new(SI .. "Shoot_indication_middle_left"),
}
local indSides = {
    [0] = gfx.image.new(SI .. "Shoot_indication_sides_front"),
    [1] = gfx.image.new(SI .. "Shoot_indication_sides_one"),
    [2] = gfx.image.new(SI .. "Shoot_indication_sides_two"),
}

-- Laser charge and laser (phase 2 only). Neither is visible from two lanes away, so
-- these sets stop at one lane out; a lane-2 entry is deliberately absent and the
-- lookup returning nil is what makes the effect invisible at that distance.
local LC = ART .. "4. Laser-Charge/"
local chargeMiddle = {
    [0] = gfx.imagetable.new(LC .. "boss_lasercharge_middle_front"),
    [1] = gfx.imagetable.new(LC .. "boss_lasercharge_middle_left"),
}
local chargeSides = {
    [0] = gfx.imagetable.new(LC .. "boss_lasercharge_sides_front"),
    [1] = gfx.imagetable.new(LC .. "boss_lasercharge_sides_left"),
}
local LZ = ART .. "5. Laser/"
local laserMiddle = {
    [0] = gfx.imagetable.new(LZ .. "boss_laser_middle_front"),
    [1] = gfx.imagetable.new(LZ .. "boss_laser_middle_left"),
}
local laserSides = {
    [0] = gfx.imagetable.new(LZ .. "boss_laser_sides_front"),
    [1] = gfx.imagetable.new(LZ .. "boss_laser_sides_left"),
}

-- ─── Tuning ──────────────────────────────────────────────────────────────────

-- A boss arrives on every Nth wave. TEST_MODE overrides that and makes the very
-- first wave a boss wave, so the fight can be exercised without grinding to wave 30.
Boss.WAVE_INTERVAL = 15
Boss.TEST_MODE     = false

-- How many times the fight escalates before it stops getting harder. Level 0 is the
-- first boss and each later encounter steps up, so with 3 steps the first four bosses
-- run at levels 0, 1, 2, 3 and every boss after that fights at level 3.
Boss.SCALE_STEPS = 3

-- Which level the TEST_MODE boss fights at, so a tier can be exercised without
-- playing up to it. Ignored unless TEST_MODE is on.
Boss.TEST_LEVEL = 0

-- Where the ship sits in the tunnel, as a progress value on the shared 0..1 lane
-- path. Its blasters are already 120 frames into the 150-frame approach, so the
-- enemies it fires have only the last fifth of the lane to cover — and anything
-- shoved back this far has hit the hull.
local SHIP_PROGRESS = 120 / 150

local INTRO_FRAMES      = 150
local TRANSITION_FRAMES = 150
local DEATH_FRAMES      = 45

-- Phase 1: the indication lights up half a second before the shot and holds for a
-- quarter, leaving a beat of empty barrel before the enemy actually appears.
local INDICATION_LEAD  = 15
local INDICATION_FLASH = 8

-- Frames between the end of one attack pattern and the start of the next.
local BASE_ATTACK_REST = 45
local ATTACK_REST_STEP = 8    -- subtracted per level: phase 1 presses harder
local MIN_ATTACK_REST  = 15   -- floor, so patterns never run into each other
-- Gap between the individual shots of the three-shot burst. An enemy needs 30 frames
-- to cross from the ship to the player, so this spacing guarantees at most two lanes
-- are ever occupied at once and the player always has somewhere to stand.
local BURST_GAP = 20

-- Six enemies shoved back into it end phase 1 at level 0, two more each level up.
local BASE_PHASE1_HEALTH = 6
local PHASE1_HEALTH_STEP = 2

-- Phase 2 is a punching contest. Roughly thirty connected punches at level 0, which at
-- the 9-frame punch animation is about ten seconds of pure offence before dodging is
-- counted — long enough to feel like a duel, short enough not to drag. Tune freely.
local BASE_PHASE2_HEALTH = 30
local PHASE2_HEALTH_STEP = 10

local CHARGE_FRAMES = 30   -- 1 s telegraph, drawn 1:1 from the 30-frame sheet

-- The beam sheet holds 60 frames, but how long the beam is actually up is a balance
-- knob, and the art is resampled to fit.
local LASER_ART_FRAMES  = 60
local BASE_LASER_FRAMES = 35
local LASER_FRAMES_STEP = 4    -- subtracted per level: beams cycle faster
local MIN_LASER_FRAMES  = 20   -- floor, so a beam is always a beam and not a flicker

-- Breathing room between a beam dying and a neighbouring one lighting up, and the
-- single most important number in the fight.
--
-- Beams on adjacent lanes may not burn at once, so with no margin the next one is
-- allowed to start the instant the previous stops — meaning the lane the player is
-- fleeing TO comes clear on the very frame the lane they are standing in ignites. The
-- escape technically exists, which is why a "does an escape exist" check passes, but
-- taking it needs frame-perfect input. On the edge lanes the player has nowhere else
-- to go, so that is not a rare case, it is the normal rhythm.
--
-- This margin is exactly the dodge window: both lanes are clear together for this
-- many frames, and measuring the simulated fight gives back precisely this number as
-- the worst case. Volleys on adjacent lanes end up laserFrames + DODGE_MARGIN apart,
-- so the two together set the pace.
local DODGE_MARGIN = 20
-- Slightly over a second between volleys: long enough to step out, short enough that
-- beams from earlier volleys are still up and have to be worked around.
local LASER_INTERVAL = 40
local LASER_DAMAGE      = 30
local LASER_DAMAGE_GAP  = 15   -- 0.5 s between ticks while standing in a beam

-- The punch lands on frame 4 of the 9-frame Fists animation. Damage is scheduled to
-- that frame and locked out for the rest of the animation, so mashing A can't out-run
-- the animation and every point of damage matches a fist that visibly connected.
local PUNCH_IMPACT_FRAME = 4
local PUNCH_LOCKOUT      = 9

-- The hull flinches when hit; deliberately shorter than the player's own 12-frame
-- screen shake so the two never read as the same event.
local SHAKE_FRAMES    = 7
local SHAKE_MAGNITUDE = 3

local BOSS_POINTS = 5000

-- The fight's own effects. Paths are relative to sounds/, folder and all.
Boss.SFX_SPAWN  = "Boss sounds/boss_enemy_spawn"
Boss.SFX_CHARGE = "Boss sounds/Boss_laser_charge"
Boss.SONG       = "Boss sounds/Boss_music"

-- The beam deliberately reuses the spawn effect rather than Boss_laser.json. The two
-- never sound together — spawns belong to phase 1, beams to phase 2 — so sharing one
-- clip costs nothing. Point this back at "Boss sounds/Boss_laser" to split them again.
Boss.SFX_LASER  = "Boss sounds/Boss_laser"

-- Health bar, threaded between the player's bar (which ends at x=128) and the score
-- box (which is right-aligned and starts around x=290).
local BAR_X, BAR_Y, BAR_W, BAR_H, BAR_PAD = 136, 4, 148, 12, 2

-- Depth: the hull sits just above the tunnel and below the whole entity band (2-39),
-- so every enemy it fires draws in front of it. Its own effects sit one step higher
-- so they overlay the hull seamlessly.
local BODY_Z    = 1
local OVERLAY_Z = 2

-- ─── State ───────────────────────────────────────────────────────────────────

local STATE_IDLE    = "idle"       -- no fight in progress
local STATE_INTRO   = "intro"      -- ship flies in, bar fills, player pinned
local STATE_PHASE1  = "phase1"
local STATE_TRANS   = "transition" -- transition animation, bar refills
local STATE_PHASE2  = "phase2"
local STATE_DEATH   = "death"
local STATE_REWARD  = "reward"     -- three boosters, then the run resumes
local STATE_DONE    = "done"

-- Settings for the fight in progress, fixed when it begins. Everything that scales
-- lives here rather than as a constant, because the same boss module runs every
-- encounter at a different level. DODGE_MARGIN and BURST_GAP deliberately do NOT
-- scale: those two are the fairness and safety guarantees, not difficulty dials.
local level        = 0
local phase1Health = 0
local phase2Health = 0
local attackRest   = 0
local laserFrames  = 0

local state = STATE_IDLE
local timer = 0            -- frames elapsed in the current state
local health, maxHealth = 0, 0
local playerLane = MIDDLELANE

local shakeTimer = 0
local punchLockout = 0     -- frames until another punch may be scheduled
local pendingHit = -1      -- frames until a scheduled punch actually lands

local shots = {}           -- phase 1: { lane, at } queued shots, `at` in state frames
local nextAttackAt = 0
local lasers = {}          -- phase 2: { lane, start, damageTimer, playerIn }

local bodySprite, overlaySprite

-- ─── View selection ──────────────────────────────────────────────────────────

-- Which full-width perspective the hull is drawn in, and whether it is mirrored.
local function bodyView()
    if playerLane == MIDDLELANE then return "front", gfx.kImageUnflipped end
    if playerLane == RIGHTLANE  then return "left",  gfx.kImageUnflipped end
    return "left", gfx.kImageFlippedX
end

-- Off-centre effects are authored against the unmirrored view, so they follow the
-- hull's mirror when the player is on the left, and otherwise mirror only when the
-- blaster they belong to sits to the player's right.
--
-- A blaster dead ahead is the exception, and it is the opposite way round. Those
-- frames lean along the hull rather than towards a side of the screen, and from the
-- right lane the ship runs away to the left (and vice versa) — so the mirror there
-- keys off the hull's direction, not the blaster's. Checked against the art: get this
-- backwards and the glow sits off the side of the barrel with the rings still showing.
local function effectFlip(blasterLane)
    if blasterLane == playerLane then
        return (playerLane == RIGHTLANE) and gfx.kImageFlippedX or gfx.kImageUnflipped
    end
    if playerLane == LEFTLANE then return gfx.kImageFlippedX end
    if blasterLane > playerLane then return gfx.kImageFlippedX end
    return gfx.kImageUnflipped
end

-- Art for one blaster's effect, or nil when it can't be seen from this far away.
local function effectArt(blasterLane, middleSet, sideSet)
    local offset = math.abs(blasterLane - playerLane)
    local set = (blasterLane == MIDDLELANE) and middleSet or sideSet
    return set[offset]
end

-- ─── Sprites ─────────────────────────────────────────────────────────────────

local function drawBody()
    local view, flip = bodyView()
    local dx = 0
    if shakeTimer > 0 then
        -- Alternate sides each frame so the flinch reads as a judder, not a drift.
        local mag = math.ceil(SHAKE_MAGNITUDE * (shakeTimer / SHAKE_FRAMES))
        dx = (shakeTimer % 2 == 0) and mag or -mag
    end

    -- `timer` is already 1 on the first drawn frame of a state, so it indexes the
    -- 1-based frame directly; clamping holds the last frame if a state outlives its
    -- animation (the death pose has to persist while the boosters fly in).
    local function frameOf(n) return math.max(1, math.min(timer, n)) end

    local image
    if state == STATE_INTRO then
        image = introTable:getImage(frameOf(INTRO_FRAMES))
    elseif state == STATE_TRANS then
        image = transitionTable:getImage(frameOf(TRANSITION_FRAMES))
    elseif state == STATE_DEATH then
        image = deathTable[view]:getImage(frameOf(DEATH_FRAMES))
    elseif state == STATE_REWARD then
        -- The reward phase runs on its own clock, so hold the final wreck rather than
        -- restarting the animation from frame 1.
        image = deathTable[view]:getImage(DEATH_FRAMES)
    elseif state == STATE_PHASE1 then
        image = phase1Body[view]
    elseif state == STATE_PHASE2 then
        image = phase2Body[view]
    end

    if image then image:draw(dx, 0, flip) end
end

local function drawOverlay()
    if state == STATE_PHASE1 then
        for i = 1, #shots do
            local s = shots[i]
            local since = timer - (s.at - INDICATION_LEAD)
            if since >= 0 and since < INDICATION_FLASH then
                local art = effectArt(s.lane, indMiddle, indSides)
                if art then art:draw(0, 0, effectFlip(s.lane)) end
            end
        end
    elseif state == STATE_PHASE2 then
        for i = 1, #lasers do
            local l = lasers[i]
            local since = timer - l.start
            if since < CHARGE_FRAMES then
                local tbl = effectArt(l.lane, chargeMiddle, chargeSides)
                if tbl then tbl:getImage(since + 1):draw(0, 0, effectFlip(l.lane)) end
            else
                local tbl = effectArt(l.lane, laserMiddle, laserSides)
                local burn = since - CHARGE_FRAMES
                if tbl and burn < laserFrames then
                    -- The sheet is resampled onto however long the beam actually
                    -- burns, so the whole animation plays out whatever laserFrames
                    -- is set to rather than being cut off partway.
                    local f = math.floor(burn * LASER_ART_FRAMES / laserFrames) + 1
                    tbl:getImage(math.min(f, LASER_ART_FRAMES)):draw(0, 0, effectFlip(l.lane))
                end
            end
        end
    end
end

local function ensureSprites()
    if not bodySprite then
        bodySprite = gfx.sprite.new()
        bodySprite:setCenter(0, 0)
        bodySprite:moveTo(0, 0)
        bodySprite:setSize(400, 240)
        bodySprite:setZIndex(BODY_Z)
        bodySprite.draw = drawBody

        overlaySprite = gfx.sprite.new()
        overlaySprite:setCenter(0, 0)
        overlaySprite:moveTo(0, 0)
        overlaySprite:setSize(400, 240)
        overlaySprite:setZIndex(OVERLAY_Z)
        overlaySprite.draw = drawOverlay
    end
end

-- ─── Attack scheduling ───────────────────────────────────────────────────────

-- A lane counts as taken while a live enemy is on it, so no shot is ever fired into
-- a lane the player is already busy escaping.
local function laneTaken(lane)
    return Field.leadingTargetOnLane(lane) ~= nil
end

local function queueShot(lane, at)
    shots[#shots+1] = { lane = lane, at = at }
end

-- Pick the next pattern. Every pattern deliberately leaves one lane clear for the
-- whole time it is in the air, which is what keeps the fight dodgeable. Shot times are
-- absolute frames on the phase clock, not offsets, because `timer` keeps running.
local function scheduleAttack()
    local pattern = math.random(3)
    local duration = 0
    local first = timer + INDICATION_LEAD

    if pattern == 1 then
        -- Single shot on any lane that isn't already busy.
        local free = {}
        for lane = 1, 3 do
            if not laneTaken(lane) then free[#free+1] = lane end
        end
        if #free > 0 then queueShot(free[math.random(#free)], first) end

    elseif pattern == 2 then
        -- Two adjacent blasters at once; the far lane stays open.
        local pair = (math.random(2) == 1) and { LEFTLANE, MIDDLELANE }
                                            or { MIDDLELANE, RIGHTLANE }
        for _, lane in ipairs(pair) do
            if not laneTaken(lane) then queueShot(lane, first) end
        end

    else
        -- Three in quick succession across all three lanes. Spaced by BURST_GAP so
        -- each enemy has cleared before the third arrives.
        local order = { LEFTLANE, MIDDLELANE, RIGHTLANE }
        for i = #order, 2, -1 do
            local j = math.random(i)
            order[i], order[j] = order[j], order[i]
        end
        for i, lane in ipairs(order) do
            queueShot(lane, first + (i - 1) * BURST_GAP)
        end
        duration = 2 * BURST_GAP
    end

    nextAttackAt = first + duration + attackRest
end

-- Fire everything whose moment has come, and drop it from the queue.
local function releaseShots()
    for i = #shots, 1, -1 do
        local s = shots[i]
        if timer >= s.at then
            -- Skip if the lane filled up while the shot was telegraphing; the
            -- indication still played, which reads as the boss thinking better of it.
            if not laneTaken(s.lane) then
                Field.spawnEnemy(s.lane).progress = SHIP_PROGRESS
                Sounds.play(Boss.SFX_SPAWN)
            end
            table.remove(shots, i)
        end
    end
end

-- ─── Laser scheduling ────────────────────────────────────────────────────────

-- Two beams on ADJACENT lanes must never be *burning* at the same time. That is the
-- whole safety condition: it keeps the set of live beams to a single lane or the
-- outer pair {1,3}, so from wherever the player stands there is always a clear lane
-- one step away. Leaving merely "one lane clear" is not enough — with 1 and 2 lit the
-- only clear lane is 3, which a player on lane 1 can reach only by walking through 2.
--
-- Crucially the rule is about the burning window, not the lane. A beam that is still
-- charging is harmless, so a neighbour may charge while this one burns as long as it
-- lights up after this one dies. Banning the lane outright instead — which is what
-- this used to do — froze the middle lane open for the whole life of an {1,3} volley
-- and let the player park there and punch unopposed.
--
-- A beam on lane L starting at S burns [S+CHARGE, S+CHARGE+LASER). A new beam at T on
-- a neighbouring lane burns [T+CHARGE, ...), so the two are disjoint when
-- T >= S + LASER — and pushing that out by DODGE_MARGIN leaves both lanes clear
-- together for that many frames, which is the window the player actually dodges in.
local function canFire(lane, at)
    for i = 1, #lasers do
        local l = lasers[i]
        if math.abs(l.lane - lane) <= 1 and at < l.start + laserFrames + DODGE_MARGIN then
            return false
        end
    end
    return true
end

local function fireLaser(lane)
    lasers[#lasers+1] = { lane = lane, start = timer, damageTimer = 0, playerIn = false }
    -- The charge sound belongs to the telegraph, so it plays as the charge begins
    -- rather than when the beam lands.
    Sounds.play(Boss.SFX_CHARGE)
end

local function scheduleLasers()
    -- The boss always shoots at the lane the player is standing in, and if that shot
    -- isn't legal yet it WAITS for it rather than shooting somewhere else.
    --
    -- The waiting is the important half. Lanes 1 and 3 aren't adjacent, so each is
    -- legal the instant the other fires; a scheduler that takes any legal lane falls
    -- into a 1-3 ping-pong forever, and the middle — adjacent to both, so never clear
    -- at the moment of scheduling — is never shot at. The player works that out in
    -- seconds and simply stands in the middle punching. Holding fire until the shot
    -- the boss actually wants becomes legal is what breaks that cycle, and it paces
    -- the fight too: the wait is exactly one beam length, so volleys land in a steady
    -- rhythm instead of as fast as the rules allow.
    if not canFire(playerLane, timer) then return end
    fireLaser(playerLane)

    -- Sometimes a second beam alongside it. Anything adjacent is already illegal now
    -- the first has been fired, so this can only ever be the opposite outer lane —
    -- the two-blaster volley, with the middle still open to run to.
    if math.random(2) == 1 then
        for lane = 1, 3 do
            if lane ~= playerLane and canFire(lane, timer) then
                fireLaser(lane)
                break
            end
        end
    end

    nextAttackAt = timer + LASER_INTERVAL
end

-- Advance beams, retire finished ones, and bill the player for standing in one.
local function updateLasers(events)
    for i = #lasers, 1, -1 do
        local l = lasers[i]
        local since = timer - l.start
        if since >= CHARGE_FRAMES + laserFrames then
            table.remove(lasers, i)
        elseif since >= CHARGE_FRAMES then
            -- Exactly on the ignition frame, so it fires once per beam.
            if since == CHARGE_FRAMES then Sounds.play(Boss.SFX_LASER) end

            local inBeam = (playerLane == l.lane)
            if inBeam then
                -- Damage on entry as well as on the tick, so a beam can't be walked
                -- through between ticks.
                if not l.playerIn or l.damageTimer <= 0 then
                    events[#events+1] = { kind = "damage", amount = LASER_DAMAGE }
                    l.damageTimer = LASER_DAMAGE_GAP
                else
                    l.damageTimer -= 1
                end
            else
                l.damageTimer = 0
            end
            l.playerIn = inBeam
        end
    end
end

-- ─── Public API ──────────────────────────────────────────────────────────────

-- True when the wave starting after `waveCount` completed waves should be a boss wave.
function Boss.isBossWave(waveCount)
    if Boss.TEST_MODE then return waveCount == 0 end
    return (waveCount + 1) % Boss.WAVE_INTERVAL == 0
end

-- Which escalation level a boss appearing on `wave` fights at. Bosses land on every
-- WAVE_INTERVAL-th wave, so the first is level 0, the next level 1, and so on until
-- SCALE_STEPS increases have happened; after that every boss is at the hardest level.
function Boss.levelFor(wave)
    if Boss.TEST_MODE then
        return math.max(0, math.min(Boss.SCALE_STEPS, Boss.TEST_LEVEL))
    end
    local n = math.floor((wave - 1) / Boss.WAVE_INTERVAL)
    return math.max(0, math.min(Boss.SCALE_STEPS, n))
end

function Boss.isActive()
    return state ~= STATE_IDLE and state ~= STATE_DONE
end

function Boss.isFinished()
    return state == STATE_DONE
end

-- The player is pinned to the middle lane, and can't punch, while the ship is
-- manoeuvring: the arrival and the phase transition.
function Boss.locksPlayer()
    return state == STATE_INTRO or state == STATE_TRANS
end

-- Fraction of the boss's health remaining, for the bar.
function Boss.healthFraction()
    if maxHealth <= 0 then return 0 end
    return health / maxHealth
end

-- Clear everything. Called when a run starts or ends.
function Boss.reset()
    state = STATE_IDLE
    timer, health, maxHealth = 0, 0, 0
    shots, lasers = {}, {}
    shakeTimer, punchLockout, pendingHit = 0, 0, -1
    if bodySprite then
        bodySprite:remove()
        overlaySprite:remove()
    end
end

-- Start the fight. The caller has already cleared the field and shown the banner.
function Boss.begin(wave)
    ensureSprites()

    -- Lock in this encounter's difficulty. Both phases get tougher and both of the
    -- boss's rhythms tighten; the dodge window and the burst spacing are left alone
    -- on purpose, since those are what keep the fight survivable at any level.
    level        = Boss.levelFor(wave or 1)
    phase1Health = BASE_PHASE1_HEALTH + PHASE1_HEALTH_STEP * level
    phase2Health = BASE_PHASE2_HEALTH + PHASE2_HEALTH_STEP * level
    attackRest   = math.max(MIN_ATTACK_REST,  BASE_ATTACK_REST  - ATTACK_REST_STEP  * level)
    laserFrames  = math.max(MIN_LASER_FRAMES, BASE_LASER_FRAMES - LASER_FRAMES_STEP * level)

    state = STATE_INTRO
    timer = 0
    health, maxHealth = 0, phase1Health   -- bar fills over the arrival
    shots, lasers = {}, {}
    shakeTimer, punchLockout, pendingHit = 0, 0, -1
    bodySprite:add()
    overlaySprite:add()
end

-- True once the ship has closed to arm's length. While this holds, a punch belongs to
-- the boss and never falls through to the (empty) lane behind it — including a punch
-- the lockout rejects, which is simply ignored rather than restarting the fists.
function Boss.acceptsPunches()
    return state == STATE_PHASE2
end

-- A punch from the player. Only meaningful in phase 2, where the ship is close
-- enough to reach. Returns true if the punch was accepted (so main.lua knows the
-- punch was spent on the boss rather than on the empty lane behind it).
function Boss.onPunch()
    if state ~= STATE_PHASE2 then return false end
    if punchLockout > 0 then return false end
    punchLockout = PUNCH_LOCKOUT
    pendingHit   = PUNCH_IMPACT_FRAME
    return true
end

-- One frame of the fight. Runs before Field.update, so enemies it spawns this frame
-- are simulated immediately. Returns the same event shape Field.update uses.
function Boss.update(lane)
    local events = {}
    if not Boss.isActive() then return events end

    playerLane = lane
    timer += 1
    if shakeTimer > 0 then shakeTimer -= 1 end
    if punchLockout > 0 then punchLockout -= 1 end

    if state == STATE_INTRO then
        -- Bar fills in step with the approach.
        health = maxHealth * math.min(1, timer / INTRO_FRAMES)
        if timer >= INTRO_FRAMES then
            state, timer = STATE_PHASE1, 0
            health = maxHealth
            nextAttackAt = attackRest
        end

    elseif state == STATE_PHASE1 then
        if timer >= nextAttackAt then scheduleAttack() end
        releaseShots()

        -- Anything shoved back as far as the hull has hit it.
        local hits = Field.collectPushedPast(SHIP_PROGRESS)
        if hits > 0 then
            health = math.max(0, health - hits)
            shakeTimer = SHAKE_FRAMES
        end

        if health <= 0 then
            -- Wipe the board before pinning the player: anything still in flight
            -- would arrive while they're frozen for the transition, which is a hit
            -- they had no way to avoid. Queued shots go too, telegraphed or not.
            Field.clearEnemies()
            shots = {}
            -- The player roams freely during phase 1, so haul them back to the middle
            -- before pinning them. main.lua owns the lane, so ask for it.
            playerLane = MIDDLELANE
            events[#events+1] = { kind = "centerPlayer" }

            state, timer = STATE_TRANS, 0
            maxHealth = phase2Health
            health = 0
        end

    elseif state == STATE_TRANS then
        health = maxHealth * math.min(1, timer / TRANSITION_FRAMES)
        if timer >= TRANSITION_FRAMES then
            state, timer = STATE_PHASE2, 0
            health = maxHealth
            nextAttackAt = LASER_INTERVAL
        end

    elseif state == STATE_PHASE2 then
        if timer >= nextAttackAt then scheduleLasers() end
        updateLasers(events)

        if pendingHit >= 0 then
            pendingHit -= 1
            if pendingHit < 0 then
                health = math.max(0, health - 1)
                shakeTimer = SHAKE_FRAMES
            end
        end

        if health <= 0 then
            state, timer = STATE_DEATH, 0
            lasers = {}
            events[#events+1] = { kind = "bossDefeated", points = BOSS_POINTS }
        end

    elseif state == STATE_DEATH then
        if timer >= DEATH_FRAMES then
            state, timer = STATE_REWARD, 0
            -- One booster per lane, entering at the same point the ship's shots did.
            for lane2 = 1, 3 do
                Field.spawnHealth(lane2).progress = SHIP_PROGRESS
            end
        end

    elseif state == STATE_REWARD then
        -- A beat after the last booster is gone, hand the run back to the wave system.
        if Field.healthCount() == 0 and timer >= 30 then
            state = STATE_DONE
            bodySprite:remove()
            overlaySprite:remove()
        end
    end

    if bodySprite then
        bodySprite:markDirty()
        overlaySprite:markDirty()
    end
    return events
end

-- ─── Health bar ──────────────────────────────────────────────────────────────

function Boss.draw()
    if not Boss.isActive() then return end
    if state == STATE_DEATH or state == STATE_REWARD then return end

    gfx.setImageDrawMode(gfx.kDrawModeCopy)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(BAR_X, BAR_Y, BAR_W, BAR_H)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawRect(BAR_X, BAR_Y, BAR_W, BAR_H)

    local innerW = BAR_W - BAR_PAD * 2
    local fillW  = math.floor(innerW * Boss.healthFraction())
    if fillW > 0 then
        gfx.fillRect(BAR_X + BAR_PAD, BAR_Y + BAR_PAD, fillW, BAR_H - BAR_PAD * 2)
    end
end
