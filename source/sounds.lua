import "CoreLibs/object"

-- Plays the JSON sound effects stored under source/sounds/. Each file is an array
-- of tracks exported as { type, envelope, notes, bpm, ... }; we rebuild every track
-- as a synth + instrument on a sequence so the effect can be retriggered on demand.

local snd = playdate.sound

Sounds = {}

-- Waveform index used in the JSON `type` field -> Playdate waveform constant.
local WAVEFORMS = {
    [0] = snd.kWaveSine,
    [1] = snd.kWaveSquare,
    [2] = snd.kWaveSawtooth,
    [3] = snd.kWaveTriangle,
    [4] = snd.kWaveNoise,
    [5] = snd.kWavePOPhase,
    [6] = snd.kWavePODigital,
    [7] = snd.kWavePOVosim,
}

-- Note values in the JSON are small offsets; 0 means "rest". Anchor non-zero
-- values to a middle-C base so they map onto real MIDI notes.
local BASE_NOTE      = 60
local STEPS_PER_BEAT = 4   -- treat each note slot as a 1/16th step

-- Playback level per sound, 0..1. The JSON export carries no volume field, so this
-- table is the only place an effect's loudness can be set; anything not listed plays
-- at DEFAULT_VOLUME. Noise-based effects (type 4) need markedly lower numbers than
-- pitched ones to sit at the same apparent loudness, because their energy is spread
-- across the whole spectrum rather than concentrated at one frequency.
local DEFAULT_VOLUME = 1.0
local VOLUMES = {
    enemy_death = 0.35,
}

-- Per-playback randomisation, so an effect fired repeatedly doesn't read as the same
-- recording pasted over and over. `pitch` is the half-step range of a random
-- transpose (±, fractional values allowed, so small numbers read as detuning rather
-- than as a different note); `volume` is the fraction of the sound's level to jitter
-- by (±).
--
-- Pitch carries the variation on pitched waveforms. Noise (JSON type 4) has no
-- fundamental to shift, so a transpose may do little or nothing to it — those sounds
-- lean on the level jitter instead, which is why theirs is set wider. enemy_death and
-- taking_damage are both noise; healing is a triangle-wave motif whose three notes
-- spell a chord, so it gets only a touch of pitch to stay recognisable.
local DEFAULT_VARIATION = { pitch = 2, volume = 0.10 }
local VARIATION = {
    enemy_death   = { pitch = 5, volume = 0.22 },
    taking_damage = { pitch = 3, volume = 0.12 },
    healing       = { pitch = 1, volume = 0.05 },
}

-- A random value in [-range, +range].
local function spread(range)
    if not range or range <= 0 then return 0 end
    return (math.random() * 2 - 1) * range
end

-- name -> { seq, synths, instruments, volume }. The synths and instruments are kept
-- alongside the sequence because each playback retunes them (transpose on the
-- instrument, level on the synth) before starting it — far cheaper than rebuilding
-- the note data every time the sound fires.
local cache = {}

-- Build (and memoise) the sequence for a sound file under sounds/<name>.json.
local function build(name)
    if cache[name] then return cache[name] end

    local data = json.decodeFile("sounds/" .. name .. ".json")
    if not data then
        print("Sounds: could not load sounds/" .. name .. ".json")
        return nil
    end

    local seq = snd.sequence.new()
    local bpm = 120
    local synths, instruments = {}, {}

    for _, t in ipairs(data) do
        bpm = t.bpm or bpm

        local synth = snd.synth.new(WAVEFORMS[t.type] or snd.kWaveSquare)
        local env = t.envelope or {}
        -- No sustain level in the export, so these read as percussive blips.
        synth:setADSR(env.attack or 0, env.decay or 0, 0, env.release or 0)
        synth:setVolume(VOLUMES[name] or DEFAULT_VOLUME)

        local instrument = snd.instrument.new(synth)
        local track = seq:addTrack()
        track:setInstrument(instrument)

        synths[#synths+1] = synth
        instruments[#instruments+1] = instrument

        for i, note in ipairs(t.notes or {}) do
            if note ~= 0 then
                track:addNote(i, BASE_NOTE + note, 1)  -- step i, one step long
            end
        end
    end

    seq:setTempo(bpm / 60 * STEPS_PER_BEAT)  -- steps per second
    cache[name] = {
        seq         = seq,
        synths      = synths,
        instruments = instruments,
        volume      = VOLUMES[name] or DEFAULT_VOLUME,
    }
    return cache[name]
end

-- Pre-load a sound so the first playback doesn't hitch.
function Sounds.load(name)
    build(name)
end

-- Play a sound from the start, restarting it if it's already playing. Every playback
-- is retuned first, so the same effect fired twice in a row lands slightly differently.
function Sounds.play(name)
    local entry = build(name)
    if not entry then return end

    local v = VARIATION[name] or DEFAULT_VARIATION
    local transpose = spread(v.pitch)
    -- Jitter around the sound's configured level, clamped to what a synth accepts.
    local level = entry.volume * (1 + spread(v.volume))
    level = math.max(0, math.min(1, level))

    for i = 1, #entry.instruments do
        entry.instruments[i]:setTranspose(transpose)
        entry.synths[i]:setVolume(level)
    end

    entry.seq:stop()
    entry.seq:goToStep(1)
    entry.seq:play()
end
