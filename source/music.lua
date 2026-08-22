import "CoreLibs/object"

-- Plays the looping background songs stored under source/sounds/. These use a
-- different export format than the one-shot effects in sounds.lua: a file is an
-- array of *songs*, and a song's `notes` holds five voices, each a flat array of
-- (pitch, octave, length) triplets — one triplet per step. We rebuild each voice
-- as its own synth + instrument on a track so the whole song can loop endlessly
-- and be swapped when the scene changes.

local snd = playdate.sound

Music = {}

-- ─── Tone ───────────────────────────────────────────────────────────────────
-- Nothing in this section comes from the song files; the export carries no
-- waveform and no master level, so the timbre is chosen entirely here. It is
-- also where harshness has to be fixed: every note in both songs sits between
-- MIDI 60 and 71 — one octave from middle C, 262-494 Hz — and all five voices
-- crowd into that same octave with no bass underneath them.

-- Square and sawtooth waves carry loud harmonics well above their fundamental
-- (a square's 3rd and 5th land near 1.5 kHz and 2.5 kHz for the top notes here),
-- which is the band the ear is most sensitive to, so the high notes turn piercing
-- on headphones. That is a problem of spectrum rather than level, which is why
-- turning the volume down doesn't tame it. Triangle rolls its harmonics off far
-- faster and sine has none at all. Put a lead back on kWaveSquare if you want
-- more bite once the rest of the mix is settled.
local VOICE_WAVEFORMS = {
    snd.kWaveTriangle,   -- lead
    snd.kWaveTriangle,   -- harmony
    snd.kWaveSine,       -- pad
    snd.kWaveSine,       -- pad
    snd.kWaveTriangle,   -- counter-line
}

-- Envelope defaults for voices whose params are partial or missing entirely
-- (In-Game_song's fourth voice has 316 notes but a null params entry). Sustain
-- has to default to full, not to 0 like the percussive effects in sounds.lua:
-- with no sustain and no decay a note would fall silent the instant it starts.
-- The small release keeps notes from clicking off at the end of their length.
local DEFAULT_ATTACK  = 0
local DEFAULT_DECAY   = 0
local DEFAULT_SUSTAIN = 1
local DEFAULT_RELEASE = 0.05

-- A zero attack snaps the amplitude from silence to full in a single sample, and
-- that step is a click — broadband energy on every note onset, which reads as the
-- mix spitting rather than as a note starting. A few milliseconds is far too short
-- to hear as a fade-in but long enough to remove it. The floor applies even where
-- a file asks for attack 0, since no export can actually want the click.
local MIN_ATTACK = 0.004

-- Level for a voice that never had one set in the editor. Full scale is too hot
-- here: the hand-set voices in both songs sit between 0.2 and 0.6, so leaving the
-- untouched ones at 1.0 let them dominate everything around them — in the menu
-- song that is the lead, in the in-game song the fully sustained fourth voice.
local DEFAULT_VOLUME = 0.5

-- Master level for the music alone; the sound effects are unaffected.
local MUSIC_VOLUME = 0.6

-- Gentle low-pass across the whole music mix — the broad "less shrill" knob. The
-- highest fundamental in either song is 494 Hz, so a 2 kHz corner leaves every
-- note and its first harmonics intact and only shaves the shrill top end. Raise
-- it toward 4000 for a brighter mix, drop it toward 1200 for a softer one.
local TONE_CUTOFF_HZ = 2000

local STEPS_PER_BEAT = 4   -- same 1/16th step grid the effects use

-- ─── Output ─────────────────────────────────────────────────────────────────

-- The music gets its own channel so the filter and the master level apply to it
-- alone, leaving taking_damage and healing untouched on the default channel.
local musicChannel = snd.channel.new()
musicChannel:setVolume(MUSIC_VOLUME)

local toneFilter = snd.twopolefilter.new(snd.kFilterLowPass)
toneFilter:setFrequency(TONE_CUTOFF_HZ)
toneFilter:setResonance(0)   -- resonance peaks *at* the corner, undoing the point
musicChannel:addEffect(toneFilter)

-- ─── Note mapping ───────────────────────────────────────────────────────────

-- A triplet is (pitch, octave, length). Pitch is a 1-based piano-roll row, so
-- 1..12 spans exactly one octave and pitch 1 is the octave's root; 0 means rest.
-- Subtracting the 1 is what makes the songs' note sets land on real scales.
local function midiNote(pitch, octave)
    return (octave + 1) * 12 + (pitch - 1)
end

-- ─── Building ───────────────────────────────────────────────────────────────

local cache = {}   -- name -> playdate.sound.sequence

-- The editor keeps blank song slots around (Menu_song.json ships an empty second
-- one), so take the first entry that actually has a length.
local function firstNonEmptySong(data)
    for _, song in ipairs(data) do
        if (song.ticks or 0) > 0 then return song end
    end
    return nil
end

-- Build (and memoise) the sequence for sounds/<name>.json.
local function build(name)
    if cache[name] then return cache[name] end

    local data = json.decodeFile("sounds/" .. name .. ".json")
    if not data then
        print("Music: could not load sounds/" .. name .. ".json")
        return nil
    end

    local song = firstNonEmptySong(data)
    if not song then
        print("Music: no playable song in sounds/" .. name .. ".json")
        return nil
    end

    local seq = snd.sequence.new()

    for voiceIndex, voiceNotes in ipairs(song.notes or {}) do
        if #voiceNotes > 0 then
            -- Null entries decode to nil and leave `voices` sparse, so index it
            -- directly rather than iterating it, and fall back to the defaults.
            local params = (song.voices or {})[voiceIndex]
            if type(params) ~= "table" then params = {} end

            local synth = snd.synth.new(VOICE_WAVEFORMS[voiceIndex] or snd.kWaveTriangle)
            synth:setADSR(
                math.max(params.attack or DEFAULT_ATTACK, MIN_ATTACK),
                params.decay   or DEFAULT_DECAY,
                params.sustain or DEFAULT_SUSTAIN,
                params.release or DEFAULT_RELEASE
            )
            synth:setVolume(params.volume or DEFAULT_VOLUME)

            -- Route the voice to the music channel; a source left unassigned
            -- plays on the default channel and would miss the filter entirely.
            local instrument = snd.instrument.new(synth)
            musicChannel:addSource(instrument)

            local track = seq:addTrack()
            track:setInstrument(instrument)

            for i = 1, #voiceNotes - 2, 3 do
                local pitch, octave, length = voiceNotes[i], voiceNotes[i + 1], voiceNotes[i + 2]
                if pitch > 0 then
                    -- Each triplet is one step; note length is already in steps.
                    track:addNote((i - 1) // 3 + 1, midiNote(pitch, octave), math.max(length, 1))
                end
            end
        end
    end

    seq:setTempo((song.bpm or 120) / 60 * STEPS_PER_BEAT)  -- steps per second
    -- Voices are trimmed to their own last note, so the song's `ticks` — not the
    -- longest track — is the authored loop length. A loop count of 0 is endless.
    seq:setLoops(1, song.ticks, 0)

    cache[name] = seq
    return seq
end

-- ─── Playback ───────────────────────────────────────────────────────────────

local currentName = nil

-- Pre-build a song so the first playback doesn't hitch.
function Music.load(name)
    build(name)
end

-- Start a song looping, replacing whatever was playing. Asking for the song
-- that's already running is a no-op, so scene hops that share a track (menu ->
-- leaderboard -> menu) keep playing instead of restarting from the top.
function Music.play(name)
    if currentName == name then return end

    Music.stop()

    local seq = build(name)
    if not seq then return end

    seq:goToStep(1)
    seq:play()
    currentName = name
end

-- Stop the current song, if any.
function Music.stop()
    if not currentName then return end

    local seq = cache[currentName]
    if seq then
        seq:stop()
        seq:allNotesOff()   -- kill any note still sounding its release tail
    end
    currentName = nil
end
