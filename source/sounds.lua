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
    enemy_death = 0.8,
}

-- The exporter changed format partway through this project. Older files list one
-- value per step; newer ones list (pitch, octave, length) triplets, the same shape the
-- songs use. Both kinds sit in sounds/, so detect rather than convert: a triplet file
-- holds exactly three slots per tick, which no flat file does.
local function isTriplet(notes, ticks)
    return ticks ~= nil and #notes > 0 and #notes % 3 == 0 and #notes == ticks * 3
end

local cache = {}   -- name -> playdate.sound.sequence

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

    for _, t in ipairs(data) do
        bpm = t.bpm or bpm

        local synth = snd.synth.new(WAVEFORMS[t.type] or snd.kWaveSquare)
        local env = t.envelope or {}

        -- Newer exports carry sustain and a per-track volume; older ones have neither,
        -- and default to the percussive blip the originals were built around.
        local attack  = env.attack  or 0
        local decay   = env.decay   or 0
        local sustain = env.sustain or 0
        local release = env.release or 0

        -- With no decay stage AND no sustain level the envelope falls from peak to
        -- silence in zero time, so the note never sounds at all. The exporter leaves
        -- `decay` out entirely when it was never touched, which is exactly how a sound
        -- can come out of the editor fine and be inaudible here. Read that combination
        -- as "no decay stage" rather than "instant silence": hold the note at full for
        -- its length and let the release carry it out. Every effect that sets a real
        -- decay or a real sustain is untouched by this.
        if decay <= 0 and sustain <= 0 then sustain = 1 end

        synth:setADSR(attack, decay, sustain, release)
        synth:setVolume((env.volume or 1) * (VOLUMES[name] or DEFAULT_VOLUME))

        local track = seq:addTrack()
        track:setInstrument(snd.instrument.new(synth))

        local notes = t.notes or {}
        if isTriplet(notes, t.ticks) then
            -- (pitch, octave, length) per step; pitch is a 1-based piano-roll row and
            -- 0 means rest, matching how music.lua reads the songs.
            for i = 1, #notes - 2, 3 do
                local pitch, octave, length = notes[i], notes[i + 1], notes[i + 2]
                if pitch > 0 then
                    track:addNote((i - 1) // 3 + 1,
                                  (octave + 1) * 12 + pitch - 1,
                                  math.max(length, 1))
                end
            end
        else
            for i, note in ipairs(notes) do
                if note ~= 0 then
                    track:addNote(i, BASE_NOTE + note, 1)  -- step i, one step long
                end
            end
        end
    end

    seq:setTempo(bpm / 60 * STEPS_PER_BEAT)  -- steps per second
    cache[name] = seq
    return seq
end

-- Pre-load a sound so the first playback doesn't hitch.
function Sounds.load(name)
    build(name)
end

-- Play a sound from the start, restarting it if it's already playing.
function Sounds.play(name)
    local seq = build(name)
    if not seq then return end
    seq:stop()
    seq:goToStep(1)
    seq:play()
end
