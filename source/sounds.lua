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
        -- No sustain level in the export, so these read as percussive blips.
        synth:setADSR(env.attack or 0, env.decay or 0, 0, env.release or 0)

        local track = seq:addTrack()
        track:setInstrument(snd.instrument.new(synth))

        for i, note in ipairs(t.notes or {}) do
            if note ~= 0 then
                track:addNote(i, BASE_NOTE + note, 1)  -- step i, one step long
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
