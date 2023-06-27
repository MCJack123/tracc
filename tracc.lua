local globalParams = {
    realTime = false,
    notesPerTick = 8,
    loop = true,
    shownColumns = {
        note = true,
        instrument = false,
        volume = true,
        effect = true
    },
    autoSize = false,
    interpolation = select(2, ...) or "none"
}

local mutedChannels = {}

local noteRange = {
    banjo = 3,
    basedrum = 3,
    bass = 1,
    bell = 5,
    bit = 3,
    chime = 5,
    cow_bell = 4,
    didgeridoo = 1,
    flute = 4,
    guitar = 2,
    harp = 3,
    hat = 3,
    iron_xylophone = 3,
    pling = 3,
    snare = 3,
    xylophone = 5
}

local amigaTable = {
[0]=907,900,894,887,881,875,868,862,856,850,844,838,832,826,820,814,
    808,802,796,791,785,779,774,768,762,757,752,746,741,736,730,725,
    720,715,709,704,699,694,689,684,678,675,670,665,660,655,651,646,
    640,636,632,628,623,619,614,610,604,601,597,592,588,584,580,575,
    570,567,563,559,555,551,547,543,538,535,532,528,524,520,516,513,
    508,505,502,498,494,491,487,484,480,477,474,470,467,463,460,457
}

local portaDrift = 192
local amigaSlides = false

-- Software mixer emulating craftos2-sound (custom waves only for now)
local sound = {channels = {}, version = 2, interpolation = globalParams.interpolation}
for i = 1, 32 do sound.channels[i] = {frequency = 0, volume = 0, panning = 0} end
function sound.getFrequency(c) return sound.channels[c].frequency end
function sound.setFrequency(c, freq) sound.channels[c].frequency = freq end
function sound.getVolume(c) return sound.channels[c].volume end
function sound.setVolume(c, vol) sound.channels[c].volume = vol end
function sound.setWaveType(c, type, tab, loopStart, loopType, keepPos)
    if type == "none" then sound.channels[c].wavetable = nil
    elseif type == "custom" then
        if loopStart >= #tab then loopStart = 0 end
        local ch = sound.channels[c]
        ch.wavetable, ch.pos, ch.loopStart, ch.loopType, ch.dir = tab, keepPos and ch.pos or 0, loopStart or 0, loopType or 1, 1
    else error("Invalid wave type", 2) end
end
function sound.setPan(c, p) sound.channels[c].pan = p end
function sound.fadeOut(c, time)
    local info = sound.channels[c]
    if (time < -0.000001) then
        info.fadeSamplesInit = 1 - info.volume;
        info.fadeDirection = 1;
        info.fadeSamples, info.fadeSamplesMax = -time * 48000, -time * 48000;
    elseif (time < 0.000001) then
        info.fadeSamplesInit = 0.0;
        info.fadeSamples, info.fadeSamplesMax = 0, 0;
    else
        info.fadeSamplesInit = info.volume;
        info.fadeDirection = -1;
        info.fadeSamples, info.fadeSamplesMax = time * 48000, time * 48000;
    end
end
function sound.setPosition(c, p) sound.channels[c].pos = (p / #sound.channels[c].wavetable) % 1 end
function sound.setInterpolation(c, i) sound.channels[c].interpolation = i end
local function tovu(n) return math.log(1+9*math.abs(n), 10) end
function sound.generate(length, cc, stereo)
    local retval, right, vu = {}, {}, {}
    for i = 1, length do
        local sample, rs = 0, 0
        local num = 0
        for i = 1, (cc or 32) do
            local c = sound.channels[i]
            local interp = c.interpolation or sound.interpolation
            if c.wavetable and c.volume > 0 and c.frequency > 0 then
                local p = c.pos * #c.wavetable
                local s
                if interp == "none" then s = c.wavetable[math.floor(p)+1] * c.volume
                elseif interp == "linear" then s = (c.wavetable[math.floor(p)+1] + (c.wavetable[math.floor(p+1) % #c.wavetable+1] - c.wavetable[math.floor(p)+1]) * (p - math.floor(p))) * c.volume end
                if stereo then
                    sample, rs = sample + s * math.min(c.pan+1, 1), rs + s * math.min(1-c.pan, 1)
                    if vu[i] then vu[i][1], vu[i][2] = vu[i][1] + tovu(s * math.min(c.pan+1, 1)), vu[i][2] + tovu(s * math.min(1-c.pan, 1))
                    else vu[i] = {tovu(s * math.min(c.pan+1, 1)), tovu(s * math.min(1-c.pan, 1))} end
                else
                    sample = sample + s
                    if vu[i] then vu[i][1], vu[i][2] = vu[i][1] + tovu(s), vu[i][2] + tovu(s)
                    else vu[i] = {tovu(s), tovu(s)} end
                end
                c.pos = c.pos + c.frequency / 48000 * c.dir
                if c.pos < 0 then c.pos, c.dir = 0, 1 end
                while c.pos >= 1 do
                    if c.loopType == 0 then c.wavetable, c.pos = nil, 0
                    elseif c.loopType == 1 then c.pos = c.pos - 1 + (c.loopStart / #c.wavetable)
                    else c.pos, c.dir = 1 - c.frequency / 48000, -1 end
                end
                if ((c.fadeSamplesMax or 0) > 0) then
                    c.volume = c.volume + (c.fadeSamplesInit / c.fadeSamplesMax * c.fadeDirection);
                    c.fadeSamples = c.fadeSamples - 1
                    if (c.fadeSamples <= 0) then
                        c.fadeSamples, c.fadeSamplesMax = 0, 0;
                        c.fadeSamplesInit = 0.0;
                        c.volume = c.fadeDirection == 1 and 1 or 0;
                    end
                end
                num = num + 1
            end
        end
        --if num > 0 then sample, rs = sample / (cc or num), rs / (cc or num) end
        retval[i] = math.max(math.min(sample / 2, 1), -1) * 127
        right[i] = math.max(math.min(rs / 2, 1), -1) * 127
    end
    for i = 1, (cc or 32) do vu[i] = vu[i] and {vu[i][1] / length, vu[i][2] / length} or {0, 0} end
    return retval, right, vu
end

local lastTick = os.epoch "utc"
local function waitForNextTick(state)
    if lastTick < os.epoch "utc" then lastTick = os.epoch "utc" end
    if globalParams.realTime then sleep(((lastTick + (2500 / state.bpm)) - os.epoch "utc" - 3) / 1000)
    else sleep(0.05) end
    lastTick = lastTick + (2500 / state.bpm)
end
local function waitForNextRow(state, stereo)
    if lastTick < os.epoch "utc" then lastTick = os.epoch "utc" end
    --[[if globalParams.realTime then sleep(((lastTick + (2500 / state.bpm)) - os.epoch "utc" - 3) / 1000)
    else sleep(0.05) end]]
    os.pullEvent("speaker_audio_empty")
    if stereo then os.pullEvent("speaker_audio_empty") end
    lastTick = lastTick + (2500 / state.bpm)
end

local function fromLE(str)
    if not str then error(debug.traceback("Bad str"), 2) end
    local n = 0
    for i = 1, #str do n = n + bit32.lshift(str:byte(i), 8*(i-1)) end
    return n
end

local function toFreq(note, finetune, sample)
    if amigaSlides then
        local a = ((note % 12)*8 + math.floor(finetune/16)) % 96
        return 14317456/((amigaTable[a]*(1-(finetune/16 % 1)) + amigaTable[(a+1) % 96]*((finetune/16 % 1))) * 16 / 2^math.floor(note / 12 - 1))
    else return 8363*2^((6*12*16*4 - (10*12*16*4 - (note-1)*16*4 - math.floor(finetune/2))) / (12*16*4)) end
end
local function slideFreq(frequency, slide)
    if amigaSlides then return 14317456 / (14317456 / frequency - slide * 2)
    else return frequency * 2^(slide / portaDrift) end
end
local function toNote(note, name) return note - 12*(noteRange[name]-1) - 7 end
local function toSpeed(note) return 2^((note - 49)/12) end
local function getFrequency(channel, sample) return sound.getFrequency(channel) * #sample.wavetable end
local function setFrequency(channel, freq, sample) sound.setFrequency(channel, freq / #sample.wavetable) end

local function setVolume(state, channel, vol)
    channel.volume = vol
    if not channel.speaker then
        if mutedChannels[channel.num] then sound.setVolume(channel.num, 0)
        else sound.setVolume(channel.num, vol / 64 * (state.globalVolume / 64) * (channel.volumeEnvelope.volume / 64)) end
    end
end

local function setPan(state, channel, pan)
    channel.pan = pan
    if not channel.speaker then
        sound.setPan(channel.num, -math.max((pan - 127) / 127, -1))
    end
    -- TODO: Add stereo capability to CC speakers
end

local function setInstrument(state, channel, inst)
    if not state.module.instruments[inst] then return end
    channel.instrument = state.module.instruments[inst]
    if #channel.instrument.volumeEnvelope.points > 0 --[[and channel.instrument.volumeEnvelope.loopType % 2 == 1]] then
        if #channel.instrument.volumeEnvelope.points == 1 or (bit32.btest(channel.instrument.volumeEnvelope.loopType, 2) and channel.instrument.volumeEnvelope.sustain == 1) then channel.volumeEnvelope = {volume = channel.instrument.volumeEnvelope.points[1].y, pos = 1, x = 0, sustain = true}
        else channel.volumeEnvelope = {volume = channel.instrument.volumeEnvelope.points[1].y, pos = 1, x = 0, rate = (channel.instrument.volumeEnvelope.points[2].y - channel.instrument.volumeEnvelope.points[1].y) / (channel.instrument.volumeEnvelope.points[2].x - channel.instrument.volumeEnvelope.points[1].x)} end
    else
        channel.volumeEnvelope = {volume = 64, pos = 0, x = 0}
    end
    if #channel.instrument.panningEnvelope.points > 0 --[[and channel.instrument.panningEnvelope.loopType % 2 == 1]] then
        if #channel.instrument.panningEnvelope.points == 1 or (bit32.btest(channel.instrument.panningEnvelope.loopType, 2) and channel.instrument.panningEnvelope.sustain == 1) then channel.panningEnvelope = {panning = channel.instrument.panningEnvelope.points[1].y, pos = 1, x = 0, sustain = true}
        else channel.panningEnvelope = {panning = channel.instrument.panningEnvelope.points[1].y, pos = 1, x = 0, rate = (channel.instrument.panningEnvelope.points[2].y - channel.instrument.panningEnvelope.points[1].y) / (channel.instrument.panningEnvelope.points[2].x - channel.instrument.panningEnvelope.points[1].x)} end
    else
        channel.panningEnvelope = {panning = 32, pos = 0, x = 0}
    end
    if channel.instrument.vibrato.sweep > 0 then channel.instrument.vibrato.sweep_mult = 0
    else channel.instrument.vibrato.sweep_mult = 1 end
end

local function setNote(state, channel, note, keepPos)
    channel.speaker = nil
    if note == 97 then
        if not channel.speaker then
            if channel.instrument and #channel.instrument.volumeEnvelope.points > 1 and not (channel.playing and channel.playing.effect == 0xE and channel.playing.effect_param and bit32.band(channel.playing.effect_param, 0xF0) == 0xD0) and channel.instrument.fadeOut > 0 then
                sound.fadeOut(channel.num, (32768 / channel.instrument.fadeOut) * (2.5 / state.bpm))
            elseif channel.instrument and #channel.instrument.volumeEnvelope.points - 1 == channel.instrument.volumeEnvelope.sustain then
                sound.fadeOut(channel.num, (channel.instrument.volumeEnvelope.points[#channel.instrument.volumeEnvelope.points].x - channel.instrument.volumeEnvelope.points[#channel.instrument.volumeEnvelope.points-1].x) * (2.5 / state.bpm))
            else sound.setVolume(channel.num, 0) sound.setFrequency(channel.num, 0) channel.frequency = 0 end
        end
        channel.note = nil
    elseif note ~= 0 and channel.instrument then
        local sample = channel.instrument.samples[note]
        if sample.name == "unused" then
            if not channel.speaker then sound.setVolume(channel.num, 0) end
        elseif not channel.speaker and sound.version then
            channel.finetune = sample.finetune
            channel.frequency = toFreq(note+sample.note, channel.finetune, sample)
            sound.setWaveType(channel.num, "custom", sample.wavetable, sample.loopStart, bit32.band(sample.type, 3), keepPos)
            if sample.name:byte(1) == 33 then sound.setInterpolation(channel.num, "linear")
            else sound.setInterpolation(channel.num, nil) end
            setFrequency(channel.num, channel.frequency, sample)
        elseif noteRange[sample.name] then
            local spk
            for _,v in ipairs(state.speakers) do
                if v.usage < 1 then
                    spk = v.speaker
                    v.usage = v.usage + (1 / globalParams.notesPerTick)
                    break
                end
            end
            if not spk then error("Not enough speakers to play module") end
            channel.speaker = spk
            sound.setVolume(channel.num, 0)
            if toNote(note, sample.name) >= 0 and toNote(note, sample.name) <= 24 and not mutedChannels[channel.num] then spk.playNote(sample.name, channel.volume / 64 * (state.globalVolume / 64), toNote(note, sample.name)) end
        else
            local spk
            for _,v in ipairs(state.speakers) do
                if v.usage == 0 then
                    spk = v.speaker
                    v.usage = 1
                    break
                end
            end
            if not spk then error("Not enough speakers to play module") end
            channel.speaker = spk
            sound.setVolume(channel.num, 0)
            if not mutedChannels[channel.num] then spk.playSound(sample.name, channel.volume / 64 * (state.globalVolume / 64), toSpeed(note)) end
        end
        channel.note = note
        channel.didSetInstrument = true
    end
end

local retrigVolume = {
    function(v) return math.max(v - 1, 0) end,
    function(v) return math.max(v - 2, 0) end,
    function(v) return math.max(v - 4, 0) end,
    function(v) return math.max(v - 8, 0) end,
    function(v) return math.max(v - 16, 0) end,
    function(v) return math.max(v * (2/3), 0) end,
    function(v) return math.max(v / 2, 0) end,
    function(v) return v end,
    function(v) return math.min(v + 1, 0) end,
    function(v) return math.min(v + 2, 0) end,
    function(v) return math.min(v + 4, 0) end,
    function(v) return math.min(v + 8, 0) end,
    function(v) return math.min(v + 16, 0) end,
    function(v) return math.min(v / (2/3), 0) end,
    function(v) return math.min(v * 2, 0) end,
}

local e_effects = {
    [0] = function(state, channel, param) end, -- (does not exist)
    function(state, channel, param) -- 1
        if param == 0 then param = channel.effectMemory[0xE1] or 0
        else channel.effectMemory[0xE1] = param end
        if not channel.speaker and state.tick == 1 and channel.note then
            channel.frequency = slideFreq(channel.frequency, param)
            setFrequency(channel.num, slideFreq(getFrequency(channel.num, channel.instrument.samples[channel.note]), param), channel.instrument.samples[channel.note])
        end
    end,
    function(state, channel, param) -- 2
        if param == 0 then param = channel.effectMemory[0xE2] or 0
        else channel.effectMemory[0xE2] = param end
        if not channel.speaker and state.tick == 1 and channel.note then
            channel.frequency = slideFreq(channel.frequency, -param)
            setFrequency(channel.num, slideFreq(getFrequency(channel.num, channel.instrument.samples[channel.note]), -param), channel.instrument.samples[channel.note])
        end
    end,
    function(state, channel, param) -- 3
        -- TODO
    end,
    function(state, channel, param) -- 4
        channel.vibrato.type = param
    end,
    function(state, channel, param) -- 5
        if not channel.speaker then
            channel.finetune = param
            if channel.playing then
                channel.frequency = toFreq(channel.playing.note+channel.instrument.samples[channel.playing.note].note, channel.finetune, channel.instrument.samples[channel.playing.note])
                setFrequency(channel.num, channel.frequency, channel.instrument.samples[channel.playing.note])
            end
        end
    end,
    function(state, channel, param) -- 6
        if param == 0 then channel.effectMemory[0xE6] = state.row
        else
            if not state.usedE6 or state.usedE6 > 0 then
                state.row = channel.effectMemory[0xE6] or state.row
                state.usedE6 = (state.usedE6 or param) - 1
            else state.usedE6 = nil end
        end
    end,
    function(state, channel, param) -- 7
        -- TODO
    end,
    function(state, channel, param) -- 8
        setPan(state, channel, param * 16)
    end,
    function(state, channel, param) -- 9
        if param > 0 and state.tick > 1 and (state.tick - 1) % param == 0 then
            setNote(state, channel, channel.playing.note or 97)
        end
    end,
    function(state, channel, param) -- A
        if param == 0 then param = channel.effectMemory[0xEA] or 0
        else channel.effectMemory[0xEA] = param end
        if state.tick == 1 then setVolume(state, channel, math.min(channel.volume + math.floor(param), 64)) end
    end,
    function(state, channel, param) -- B
        if param == 0 then param = channel.effectMemory[0xEB] or 0
        else channel.effectMemory[0xEB] = param end
        if state.tick == 1 then setVolume(state, channel, math.max(channel.volume - param, 0)) end
    end,
    function(state, channel, param) -- C
        if state.tick == param + 1 then
            setVolume(state, channel, 0)
        end
    end,
    function(state, channel, param) -- D
        if state.tick == 1 then
            --setNote(state, channel, 97)
            return 0
        end
        if state.tick - 1 == param then setNote(state, channel, channel.playing.note) end
    end,
    function(state, channel, param) -- E
        if not state.usedEE or state.usedEE > 0 then
            local ex = state.usedEE ~= nil
            state.row = state.row - 1
            state.usedEE = (state.usedEE or param) - 1
            if ex then return 0 end
        else state.usedEE = nil end
    end,
    function(state, channel, param) -- F
        -- unimplemented
    end
}

local x_effects = {
    [0] = function(state, channel, param) end, -- (does not exist)
    function(state, channel, param) -- 1
        if param == 0 then param = channel.effectMemory[0x211] or 0
        else channel.effectMemory[0x211] = param end
        if not channel.speaker and state.tick == 1 and channel.note then
            channel.frequency = slideFreq(channel.frequency, param / 16)
            setFrequency(channel.num, slideFreq(getFrequency(channel.num, channel.instrument.samples[channel.note]), param / 16), channel.instrument.samples[channel.note])
        end
    end,
    function(state, channel, param) -- 2
        if param == 0 then param = channel.effectMemory[0x212] or 0
        else channel.effectMemory[0x212] = param end
        if not channel.speaker and state.tick == 1 and channel.note then
            channel.frequency = slideFreq(channel.frequency, param / -16)
            setFrequency(channel.num, slideFreq(getFrequency(channel.num, channel.instrument.samples[channel.note]), param / -16), channel.instrument.samples[channel.note])
        end
    end,
    function(state, channel, param) end, -- 3 (does not exist)
    function(state, channel, param) end, -- 4 (does not exist)
    function(state, channel, param) end, -- 5 (does not exist)
    function(state, channel, param) end, -- 6 (does not exist)
    function(state, channel, param) end, -- 7 (does not exist)
    function(state, channel, param) state.order = math.huge end, -- 8 (tracc hack - stops song)
    function(state, channel, param) end, -- 9 (does not exist)
    function(state, channel, param) end, -- A (does not exist)
    function(state, channel, param) end, -- B (does not exist)
    function(state, channel, param) end, -- C (does not exist)
    function(state, channel, param) end, -- D (does not exist)
    function(state, channel, param) end, -- E (does not exist)
    function(state, channel, param) end -- F (does not exist)
}

local function doVibrato(state, channel, t, speed, depth)
    local amplitude
    if t == 0 then amplitude = math.sin(channel.vibrato.pos * math.pi)
    elseif t == 1 then amplitude = channel.vibrato.pos * 2 - 1
    elseif t == 2 then amplitude = channel.vibrato.pos >= 0.5 and -1 or 1
    elseif t == 8 then amplitude = (1 - channel.vibrato.pos) * 2 - 1 -- ramp down (special)
    else amplitude = math.random() * 2 - 1 end
    if channel.instrument and channel.note then
        local sample = channel.instrument.samples[channel.note]
        setFrequency(channel.num, slideFreq(channel.frequency, amplitude * depth * 2), sample)
    end
    channel.vibrato.pos = (channel.vibrato.pos + (speed / 64)) % 1
end

local effects
effects = {
    [0] = function(state, channel, param) -- 0
        if not channel.instrument then return end
        if state.tick % 3 == 1 then setNote(state, channel, channel.lastNote or channel.playing.note, true)
        elseif state.tick % 3 == 2 then setNote(state, channel, (channel.lastNote or channel.playing.note) + bit32.rshift(param, 4), true)
        else setNote(state, channel, (channel.lastNote or channel.playing.note) + bit32.band(param, 0xF), true) end
    end,
    function(state, channel, param) -- 1
        if param == 0 then param = channel.effectMemory[1] or 0
        else channel.effectMemory[1] = param end
        if not channel.speaker and state.tick > 1 and channel.note then
            channel.frequency = slideFreq(channel.frequency, param)
            setFrequency(channel.num, slideFreq(getFrequency(channel.num, channel.instrument.samples[channel.note]), param), channel.instrument.samples[channel.note])
        end
    end,
    function(state, channel, param) -- 2
        if param == 0 then param = channel.effectMemory[2] or 0
        else channel.effectMemory[2] = param end
        if not channel.speaker and state.tick > 1 and channel.note then
            channel.frequency = slideFreq(channel.frequency, -param)
            setFrequency(channel.num, math.max(slideFreq(getFrequency(channel.num, channel.instrument.samples[channel.note]), -param), 0), channel.instrument.samples[channel.note])
        end
    end,
    function(state, channel, param) -- 3
        if param == 0 then param = channel.effectMemory[3] or 0
        else channel.effectMemory[3] = param end
        if not channel.speaker and channel.note and channel.instrument then
            local note = channel.playing.note or channel.lastNote
            local sample = channel.instrument.samples[note]
            if sample then
                --print(sample.name, channel.playing.note, channel.lastNote, sample.note, getFrequency(channel.num, sample), toFreq(note+sample.note, sample.finetune, sample))
                if state.tick == 1 and channel.playing.note then
                    note = channel.lastNote
                    sample = channel.instrument.samples[note]
                    if sample then
                        channel.finetune = sample.finetune
                        channel.frequency = toFreq(note+sample.note, channel.finetune, sample)
                        setFrequency(channel.num, channel.frequency, sample)
                        if channel.playing and channel.playing.note then channel.lastNote = channel.playing.note end
                    end
                    return 0
                elseif channel.frequency < slideFreq(toFreq(note+sample.note, sample.finetune, sample), param * -2) then
                    channel.frequency = slideFreq(channel.frequency, param * 2)
                    setFrequency(channel.num, slideFreq(getFrequency(channel.num, sample), param * 2), sample)
                elseif channel.frequency > slideFreq(toFreq(note+sample.note, sample.finetune, sample), param * 2) then
                    channel.frequency = slideFreq(channel.frequency, param * -2)
                    setFrequency(channel.num, slideFreq(getFrequency(channel.num, sample), param * -2), sample)
                elseif channel.frequency ~= toFreq(note+sample.note, sample.finetune, sample) then
                    channel.frequency = toFreq(note+sample.note, sample.finetune, sample)
                    setFrequency(channel.num, channel.frequency, sample)
                end
            end
        end
    end,
    function(state, channel, param) -- 4
        if param == 0 then param = channel.effectMemory[4] or 0
        else channel.effectMemory[4] = param end
        if state.tick == 1 and channel.playing and channel.playing.note and bit32.btest(channel.vibrato.type, 4) then channel.vibrato.pos = 0 end
        doVibrato(state, channel, bit32.band(channel.vibrato.type, 3), bit32.rshift(param, 4), bit32.band(param, 0x0f))
    end,
    function(state, channel, param) -- 5
        effects[0x3](state, channel, 0)
        return effects[0xA](state, channel, param)
    end,
    function(state, channel, param) -- 6
        effects[0x4](state, channel, 0)
        return effects[0xA](state, channel, param)
    end,
    function(state, channel, param) -- 7
        -- TODO
    end,
    function(state, channel, param) -- 8
        setPan(state, channel, param)
    end,
    function(state, channel, param) -- 9
        if state.tick == 1 and not mutedChannels[channel.num] then sound.setPosition(channel.num, param * 256) end
    end,
    function(state, channel, param) -- A
        if param == 0 then param = channel.effectMemory[0xA] or 0
        else channel.effectMemory[0xA] = param end
        if state.tick > 1 then
            if param < 16 then setVolume(state, channel, math.max(channel.volume - param, 0))
            else setVolume(state, channel, math.min(channel.volume + math.floor(param / 16), 64)) end
        end
    end,
    function(state, channel, param) -- B
        if state.tick == 1 then state.order = param + 1 state.usedB = true end
    end,
    function(state, channel, param) -- C
        setVolume(state, channel, param)
    end,
    function(state, channel, param) -- D
        if state.tick == 1 then
            state.row = bit32.rshift(param, 4) * 10 + bit32.band(param, 15) + 1
            state.usedD = true;
            if state.order == state.currentOrder and not state.usedB then
                if state.order == #state.module.order then state.order = 1
                else state.order = state.order + 1 end
            end
        end
    end,
    function(state, channel, param) -- E
        return e_effects[bit32.rshift(param, 4)](state, channel, bit32.band(param, 0xF))
    end,
    function(state, channel, param) -- F
        if param < 0x20 then
            if param == 0 then state.tempo = 65535
            else state.tempo = param end
        else state.bpm = param end
        term.setCursorPos(1, 1)
        term.clearLine()
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
        print("Name:", state.name, "Tempo:", state.tempo, "BPM:", state.bpm)
    end,
    function(state, channel, param) -- G
        state.globalVolume = param
    end,
    function(state, channel, param) -- H
        if param == 0 then param = channel.effectMemory[0x11] or 0
        else channel.effectMemory[0x11] = param end
        if state.tick > 1 then
            if param < 16 then state.globalVolume = math.max(state.globalVolume - param, 0)
            else state.globalVolume = math.min(state.globalVolume + math.floor(param / 16), 64) end
            setVolume(state, channel, channel.volume)
        end
    end,
    function(state, channel, param) end, -- I (does not exist)
    function(state, channel, param) end, -- J (does not exist)
    function(state, channel, param) -- K
        if state.tick == param + 1 then
            setNote(state, channel, 97)
        end
    end,
    function(state, channel, param) -- L
        if #channel.instrument.volumeEnvelope.points > 0 and channel.instrument.volumeEnvelope.loopType % 2 == 1 then
            channel.volumeEnvelope.x = param
            channel.volumeEnvelope.pos = 1
            while channel.instrument.volumeEnvelope.points[channel.volumeEnvelope.pos+1].x < param do channel.volumeEnvelope.pos = channel.volumeEnvelope.pos + 1 end
            if channel.volumeEnvelope.pos + 1 > #channel.instrument.volumeEnvelope.points or (bit32.btest(channel.instrument.volumeEnvelope.loopType, 2) and channel.volumeEnvelope.pos == channel.instrument.volumeEnvelope.sustain) then
                channel.volumeEnvelope.sustain = true
                channel.volumeEnvelope.volume = channel.instrument.volumeEnvelope.points[channel.volumeEnvelope.pos].y
            else
                channel.volumeEnvelope.volume = channel.instrument.volumeEnvelope.points[channel.volumeEnvelope.pos].y + (param - channel.instrument.volumeEnvelope.points[channel.volumeEnvelope.pos].x) * channel.volumeEnvelope.rate
                channel.volumeEnvelope.rate = (channel.instrument.volumeEnvelope.points[channel.volumeEnvelope.pos+1].y - channel.instrument.volumeEnvelope.points[channel.volumeEnvelope.pos].y) / (channel.instrument.volumeEnvelope.points[channel.volumeEnvelope.pos+1].x - channel.instrument.volumeEnvelope.points[channel.volumeEnvelope.pos].x)
            end
            setVolume(state, channel, channel.volumeEnvelope.volume)
        end
    end,
    function(state, channel, param) end, -- M (does not exist)
    function(state, channel, param) end, -- N (does not exist)
    function(state, channel, param) end, -- O (does not exist)
    function(state, channel, param) -- P
        if param == 0 then param = channel.effectMemory[0x19] or 0
        else channel.effectMemory[0x19] = param end
        if state.tick == 1 then
            if param < 16 then setPan(state, channel, math.max(channel.pan - param, 0))
            else setPan(state, channel, math.min(channel.pan + math.floor(param / 16), 128)) end
        end
    end,
    function(state, channel, param) end, -- Q (does not exist)
    function(state, channel, param) -- R
        if param == 0 then param = channel.effectMemory[0x1B] or 0
        else channel.effectMemory[0x1B] = param end
        if math.floor(param / 16) == 0 then param = param + (channel.effectMemory[0x1B0] or 0x80)
        else channel.effectMemory[0x1B0] = bit32.band(param, 0xF0) end
        if state.tick > 1 and (state.tick - 1) % (param % 16) == 0 then
            setVolume(state, channel, retrigVolume[math.floor(param / 16)](channel.volume))
            setNote(state, channel, channel.playing.note or 97)
        end
    end,
    function(state, channel, param) end, -- S (does not exist)
    function(state, channel, param) -- T
        -- TODO
    end,
    function(state, channel, param) end, -- U (does not exist)
    function(state, channel, param) end, -- V (does not exist)
    function(state, channel, param) -- W (tracc only - Set Duty (Square only))
        if sound and sound.version and channel.instrument and channel.note then
            local sample = channel.instrument.samples[channel.note]
            --if sample.name:match "^square" then sound.setWaveType(channel.num, "square", param / 256) end
        end
    end,
    function(state, channel, param) -- X
        return x_effects[bit32.rshift(param, 4)](state, channel, bit32.band(param, 0xF))
    end,
    function(state, channel, param) -- Y
        -- unimplemented
    end,
    function(state, channel, param) -- Z
        -- unimplemented
    end,
    function(state, channel, param) -- \
        -- unimplemented
    end
}

local volume_effects
volume_effects = {
    [0] = function(state, channel, param) end, -- do nothing
    function(state, channel, param) -- v
        setVolume(state, channel, param)
    end,
    function(state, channel, param) return volume_effects[1](state, channel, param + 16) end, -- v
    function(state, channel, param) return volume_effects[1](state, channel, param + 32) end, -- v
    function(state, channel, param) return volume_effects[1](state, channel, param + 48) end, -- v
    function(state, channel, param) return volume_effects[1](state, channel, 64) end, -- v
    function(state, channel, param) -- d
        return effects[0xA](state, channel, param)
    end,
    function(state, channel, param) -- c
        return effects[0xA](state, channel, param * 16)
    end,
    function(state, channel, param) -- b
        return e_effects[0xB](state, channel, param)
    end,
    function(state, channel, param) -- a
        return e_effects[0xA](state, channel, param)
    end,
    function(state, channel, param) -- u
        -- TODO
    end,
    function(state, channel, param) -- h
        -- TODO
    end,
    function(state, channel, param) -- p
        setPan(state, channel, param * 16)
    end,
    function(state, channel, param) -- l
        return effects[0x19](state, channel, param)
    end,
    function(state, channel, param) -- r
        return effects[0x19](state, channel, param * 16)
    end,
    function(state, channel, param) -- g
        return effects[3](state, channel, param * 16)
    end,
}

local patterns, order, instruments = {}, {}, {}
local name, tracker
local restartPosition, channelCount, tempo, bpm
local globalVolume = 64
local strings = require "cc.strings"

local function readXMFile(file)
    if file.read(17) ~= "Extended Module: " then
        file.close()
        error("Not an XM module")
    end
    name = file.read(20):gsub("[ %z]+$", "")
    file.read()
    tracker = file.read(20):gsub("[ %z]+$", "")
    file.read(2)
    local preHeaderPos = file.seek()
    local mainHeaderSize = fromLE(file.read(4))
    local numOrders = fromLE(file.read(2))
    restartPosition = fromLE(file.read(2))
    channelCount = fromLE(file.read(2))
    local patternCount = fromLE(file.read(2))
    local instrumentCount = fromLE(file.read(2))
    amigaSlides = not bit32.btest(file.read(), 1)
    file.read()
    tempo = fromLE(file.read(2))
    bpm = fromLE(file.read(2))
    for i = 1, numOrders do order[i] = file.read() end
    file.seek("set", preHeaderPos + mainHeaderSize)

    for i = 1, patternCount do
        patterns[i] = {}
        preHeaderPos = file.seek()
        local patternHeaderSize = fromLE(file.read(4))
        file.read()
        local rows = fromLE(file.read(2))
        local size = fromLE(file.read(2))
        if patternHeaderSize > 9 then file.seek("set", preHeaderPos + patternHeaderSize) end
        local prePatternPos = file.seek()
        for y = 1, rows do
            patterns[i][y] = {}
            for x = 1, channelCount do
                local follow = file.read()
                if bit32.btest(follow, 0x80) then
                    if follow ~= 0x80 then
                        patterns[i][y][x] = {}
                        if bit32.btest(follow, 0x01) then
                            patterns[i][y][x].note = file.read()
                        end
                        if bit32.btest(follow, 0x02) then
                            patterns[i][y][x].instrument = file.read()
                        end
                        if bit32.btest(follow, 0x04) then
                            patterns[i][y][x].volume = file.read()
                        end
                        if bit32.btest(follow, 0x08) then
                            patterns[i][y][x].effect = file.read()
                        end
                        if bit32.btest(follow, 0x10) then
                            if not patterns[i][y][x].effect then patterns[i][y][x].effect = 0 end
                            patterns[i][y][x].effect_param = file.read()
                        end
                    end
                else
                    patterns[i][y][x] = {}
                    patterns[i][y][x].note = follow
                    patterns[i][y][x].instrument = file.read()
                    patterns[i][y][x].volume = file.read()
                    patterns[i][y][x].effect = file.read()
                    patterns[i][y][x].effect_param = file.read()
                end
            end
        end
        file.seek("set", prePatternPos + size)
    end

    for i = 1, instrumentCount do
        --print(i, ("%X"):format(file.seek()))
        local inst = {}
        instruments[i] = inst
        local instsize = fromLE(file.read(4))
        inst.name = file.read(22):gsub("[ %z]+$", "")
        file.read()
        local sampleCount = fromLE(file.read(2))
        --print(sampleCount)
        if sampleCount > 0 then
            inst.samples = {}
            inst.samplesByNumber = {}
            inst.volumeEnvelope = {points = {}}
            inst.panningEnvelope = {points = {}}
            inst.vibrato = {}
            for j = 1, sampleCount do inst.samplesByNumber[j] = {} end
            local samplesize = fromLE(file.read(4))
            for j = 1, 96 do inst.samples[j] = inst.samplesByNumber[file.read()+1] end
            for j = 1, 12 do inst.volumeEnvelope.points[j] = {x = fromLE(file.read(2)), y = fromLE(file.read(2))} end
            for j = 1, 12 do inst.panningEnvelope.points[j] = {x = fromLE(file.read(2)), y = fromLE(file.read(2))} end
            for j = file.read() + 1, 12 do inst.volumeEnvelope.points[j] = nil end
            for j = file.read() + 1, 12 do inst.panningEnvelope.points[j] = nil end
            inst.volumeEnvelope.sustain = file.read() + 1
            inst.volumeEnvelope.loopStart = file.read() + 1
            inst.volumeEnvelope.loopEnd = file.read() + 1
            inst.panningEnvelope.sustain = file.read() + 1
            inst.panningEnvelope.loopStart = file.read() + 1
            inst.panningEnvelope.loopEnd = file.read() + 1
            inst.volumeEnvelope.loopType = file.read()
            inst.panningEnvelope.loopType = file.read()
            inst.vibrato.type = file.read()
            if inst.vibrato.type == 1 then inst.vibrato.type = 2
            elseif inst.vibrato.type == 2 then inst.vibrato.type = 1
            elseif inst.vibrato.type == 3 then inst.vibrato.type = 8 end
            inst.vibrato.sweep = file.read()
            inst.vibrato.depth = file.read()
            inst.vibrato.rate = file.read()
            inst.vibrato.sweep_mult = 0
            inst.fadeOut = fromLE(file.read(2))
            file.seek("cur", instsize - 241)

            for j = 1, sampleCount do
                local sample = inst.samplesByNumber[j]
                sample.size = fromLE(file.read(4))
                --print(j, ("%X"):format(file.seek()), size)
                sample.loopStart = fromLE(file.read(4)) -- loop start
                sample.loopLength = fromLE(file.read(4)) -- loop length
                sample.volume = file.read()
                sample.finetune = file.read()
                if sample.finetune > 0x7F then sample.finetune = sample.finetune - 256 end
                sample.type = file.read()
                if bit32.btest(sample.type, 0x20) then sample.size, sample.loopStart, sample.loopLength = sample.size / 2, sample.loopStart / 2, sample.loopLength / 2 end
                if sample.loopLength == 0 or sample.loopLength > sample.size then sample.type = bit32.band(sample.type, 0xFC) end
                --print(sample.loopLength, sample.type) sleep(2)
                sample.pan = file.read() --math.max((file.read() - 128) / 127, -1)
                sample.note = file.read()
                if sample.note > 0x7F then sample.note = sample.note - 256 end
                file.read() -- reserved
                sample.name = file.read(22):gsub("[ %z]+$", "")
                file.seek("cur", samplesize - 40)
            end
            for j = 1, sampleCount do
                local sample = inst.samplesByNumber[j]
                local size = sample.size
                sample.wavetable = {}
                for c = 1, bit32.btest(sample.type, 0x20) and 2 or 1 do
                    if bit32.btest(sample.type, 0x10) then
                        local last = 0
                        for i = 1, size / 2 do
                            local d = fromLE(file.read(2))
                            if d > 0x7FFF then d = d - 0x10000 end
                            sample.wavetable[i], last = math.max(math.min((last + d) / ((last + d) > 0 and 0x7FFF or 0x8000), 1), -1), last + d
                            while last > 0x7FFF do last = last - 0x10000 end
                            while last < -0x8000 do last = last + 0x10000 end
                        end
                    else
                        local last = 0
                        for i = 1, size do
                            local d = file.read()
                            if d > 0x7F then d = d - 256 end
                            sample.wavetable[i], last = math.max(math.min((last + d) / ((last + d) > 0 and 127 or 128), 1), -1), last + d
                            while last > 127 do last = last - 256 end
                            while last < -128 do last = last + 256 end
                        end
                    end
                end
            end
        else file.seek("cur", instsize - 29) end
    end
end

local s3mTrackerFmt = {
    "Scream Tracker %d.%d%d",
    "Imago Orpheus %d.%d%d",
    "Impulse Tracker %d.%d%d",
    "Schism Tracker %d.%d%d",
    "OpenMPT %d.%d%d",
    "BeRoTracker %d.%d%d",
    "CreamTracker %d.%d%d"
}

local function s3mTrackers(num)
    if num == 0x0208 then return "Akord"
    elseif num == 0xCA00 then return "Camoto/libgamemusic"
    elseif num == 0x4100 then return "BeRoTracker" end
    local fmt = s3mTrackerFmt[bit32.rshift(bit32.band(num, 0xF000), 12)]
    if fmt then return fmt:format(bit32.rshift(bit32.band(num, 0x0F00), 8), bit32.rshift(bit32.band(num, 0xF0), 4), bit32.band(num, 0xF))
    else return "Unknown" end
end

local s3mEffects = {
    function(p) return 0x0F, p end, -- A
    function(p) return 0x0B, p end, -- B
    function(p) return 0x0D, p end, -- C
    function(p, g) -- D
        if p == 0 then p = g.x end
        g.x = p
        local h, l = bit32.rshift(p, 4), bit32.band(p, 15)
        if h == 0 or l == 0 then return 0x0A, p
        elseif h == 0xF then return 0x0E, 0xB0 + l
        elseif l == 0xF then return 0x0E, 0xA0 + h end
    end,
    function(p, g) -- E
        if p == 0 then p = g.x end
        g.x = p
        local h, l = bit32.rshift(p, 4), bit32.band(p, 15)
        if h == 0xF then return 0x0E, 0x20 + l
        elseif h == 0xE then return 0x21, 0x20 + l
        else return 0x02, p end
    end,
    function(p, g) -- F
        if p == 0 then p = g.x end
        g.x = p
        local h, l = bit32.rshift(p, 4), bit32.band(p, 15)
        if h == 0xF then return 0x0E, 0x10 + l
        elseif h == 0xE then return 0x21, 0x10 + l
        else return 0x01, p end
    end,
    function(p) return 0x03, p end, -- G
    function(p) return 0x04, p end, -- H
    function(p, g) -- I
        if p == 0 then p = g.x end
        g.x = p
        return 0x1D, p
    end,
    function(p, g) -- J
        if p == 0 then p = g.x end
        g.x = p
        return 0x00, p
    end,
    function(p, g) -- K
        if p == 0 then p = g.x end
        g.x = p
        local h, l = bit32.rshift(p, 4), bit32.band(p, 15)
        if h == 0 or l == 0 then return 0x06, p
        elseif h == 0xF then return 0x04, 0, 0x80 + l
        elseif l == 0xF then return 0x04, 0, 0x90 + h end
    end,
    function(p, g) -- L
        if p == 0 then p = g.x end
        g.x = p
        local h, l = bit32.rshift(p, 4), bit32.band(p, 15)
        if h == 0 or l == 0 then return 0x05, p
        elseif h == 0xF then return 0x03, 0, 0x80 + l
        elseif l == 0xF then return 0x03, 0, 0x90 + h end
    end,
    function(p) end, -- M (unimplemented)
    function(p) end, -- N (unimplemented)
    function(p) return 0x09, p end, -- O
    function(p) -- P
        local h, l = bit32.rshift(p, 4), bit32.band(p, 15)
        if h == 0 then return 0x19, l * 16
        elseif l == 0 then return 0x19, h end
    end,
    function(p, g) -- Q
        if p == 0 then p = g.x end
        g.x = p
        return 0x1B, p
    end,
    function(p, g) -- R
        if p == 0 then p = g.x end
        g.x = p
        return 0x07, p
    end,
    function(p) -- S
        local h, l = bit32.rshift(p, 4), bit32.band(p, 15)
        if h == 1 then return 0x0E, 0x30 + l
        elseif h == 2 then return 0x0E, 0x50 + l
        elseif h == 3 then return 0x0E, 0x40 + l
        elseif h == 4 then return 0x0E, 0x70 + l
        elseif h == 5 or h == 6 or h == 9 or h == 10 then return 0x21, p
        elseif h == 8 or h == 0xC or h == 0xD or h == 0xE then return 0x0E, p
        elseif h == 0xB then return 0x0E, 0x60 + l end
    end,
    function(p) if p >= 0x20 then return 0x0F, p end end, -- T
    function(p) end, -- U (unimplemented)
    function(p) return 0x10, p end, -- V
    function(p) return 0x11, p end, -- W
    function(p) return 0x08, math.min(p * 2, 255) end, -- X
    function(p) return 0x22, p end, -- Y
    function(p) return 0x23, p end, -- Z
}

local function readS3MFile(file)
    name = file.read(28):gsub("[ %z]+$", "")
    file.read()
    if file.read() ~= 16 then
        file.close()
        error("Not a valid XM/S3M module")
    end
    file.read(2)
    local numOrders = fromLE(file.read(2))
    local instrumentCount = fromLE(file.read(2))
    local patternCount = fromLE(file.read(2))
    file.read(2) -- flags
    tracker = s3mTrackers(fromLE(file.read(2))) or "Unknown"
    if fromLE(file.read(2)) ~= 2 then
        file.close()
        error("Unsupported S3M module")
    end
    if file.read(4) ~= "SCRM" then
        file.close()
        error("Not an S3M module")
    end
    globalVolume = file.read() / 64
    tempo = file.read()
    bpm = file.read()
    restartPosition = 0
    amigaSlides = true
    file.read() -- master volume
    file.read() -- ultra click
    local hasChannelPan = file.read() == 252
    file.read(10)
    for i = 1, 32 do
        local s = file.read()
        if s == 255 or channelCount then
            if not channelCount then channelCount = i - 1 end
        else
            if bit32.btest(s, 0x80) then mutedChannels[i] = true end
            if bit32.btest(s, 0x10) then -- AdLib channel
                file.close()
                error("Unsupported S3M module")
            end
        end
    end
    if not channelCount then channelCount = 32 end
    print(numOrders)
    print(file.seek())
    for i = 1, numOrders do
        local n = file.read()
        order[i] = n
    end
    --if numOrders % 2 == 1 then file.read() end
    local instPP, patPP = {}, {}
    for i = 1, instrumentCount do instPP[i] = fromLE(file.read(2)) * 16 end
    for i = 1, patternCount do patPP[i] = fromLE(file.read(2)) * 16 end

    for i = 1, instrumentCount do
        local sample = {wavetable = {}, volume = 64, pan = 128}
        local inst = {
            samples = {},
            samplesByNumber = {sample},
            volumeEnvelope = {
                points = {},
                sustain = 0,
                loopStart = 0,
                loopEnd = 0,
                loopType = 0
            },
            panningEnvelope = {
                points = {},
                sustain = 0,
                loopStart = 0,
                loopEnd = 0,
                loopType = 0
            },
            vibrato = {
                type = 0,
                sweep = 0,
                depth = 0,
                rate = 0,
                sweep_mult = 0
            },
            fadeOut = 0
        }
        for j = 1, 96 do inst.samples[j] = sample end
        instruments[i] = inst
        print(instPP[i])
        print(file.seek("set", instPP[i]))
        print(file.read(13)) -- type, filename
        local dataPP = (file.read() * 65536 + fromLE(file.read(2))) * 16
        sample.size = fromLE(file.read(2)) + fromLE(file.read(2)) * 65536
        sample.loopStart = fromLE(file.read(2)) + fromLE(file.read(2)) * 65536
        sample.loopLength = fromLE(file.read(2)) + fromLE(file.read(2)) * 65536 - sample.loopStart
        sample.volume = file.read()
        file.read()
        file.read() -- pack
        local sflags = file.read()
        sample.type = bit32.band(sflags, 0x01) + bit32.band(sflags, 0x04) * 4
        local c2speed = fromLE(file.read(2)) + fromLE(file.read(2)) * 65536
        local note = 12 * math.log(c2speed / 8363, 2)
        sample.note = math.ceil(note - 0.5)
        sample.finetune = math.floor((note - sample.note) * 127)
        print(c2speed, note, sample.note, sample.finetune)
        file.read(12)
        inst.name = file.read(28):gsub("[ %z]+$", "")
        sample.name = inst.name
        print(inst.name)
        if file.read(4) ~= "SCRS" then
            file.close()
            error("Invalid S3M module")
        end
        print(dataPP)
        file.seek("set", dataPP)
        if bit32.btest(sflags, 0x04) then for j = 1, sample.size do sample.wavetable[j] = fromLE(file.read(2)) - 32768 end
        else for j = 1, sample.size do sample.wavetable[j] = file.read() - 128 end end
        if bit32.btest(sflags, 0x02) then file.seek("cur", sample.size * bit32.btest(sflags, 0x04) / 2) end
    end

    for i = 1, patternCount do
        local pattern = {}
        patterns[i] = pattern
        file.seek("set", patPP[i] + 2) -- skip size
        local g = {}
        for x = 1, 32 do g[x] = {x = 0} end
        for y = 1, 64 do
            pattern[y] = {}
            repeat
                local b = file.read()
                if b ~= 0 then
                    local x = bit32.band(b, 0x1F) + 1
                    pattern[y][x] = {}
                    if bit32.btest(b, 0x20) then
                        local n = file.read()
                        if n == 254 then pattern[y][x].note = 97
                        elseif n <= 96 then pattern[y][x].note = bit32.rshift(n, 4) * 12 + bit32.band(n, 15) + 1 end
                        n = file.read()
                        if n ~= 0 then pattern[y][x].instrument = n end
                    end
                    if bit32.btest(b, 0x40) then
                        local v = file.read()
                        if v ~= 255 then pattern[y][x].volume = v + 0x10 end
                    end
                    if bit32.btest(b, 0x80) then
                        local e, p = file.read(), file.read()
                        local ne, np, nv = s3mEffects[e](p, g[x])
                        pattern[y][x].effect, pattern[y][x].effect_param = ne, np
                        if nv and not pattern[y][x].volume then pattern[y][x].volume = nv end
                    end
                end
            until b == 0
        end
    end
end

do
    local path = shell.resolve(...)
    if path == nil then error("Usage: tracc <file>") end
    local file = fs.open(path, "rb")
    if file.read(17) == "Extended Module: " then
        file.seek("set")
        readXMFile(file)
    else
        file.seek("set")
        readS3MFile(file)
    end

    file.close()
end

local notemap = {[0] = "B-", "C-", "C#", "D-", "D#", "E-", "F-", "F#", "G-", "G#", "A-", "A#"}
local function formatNote(note) if note == 97 then return "== " else return notemap[note % 12] .. tostring(math.floor(note / 12)+1) end end

term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
print("Name:", name, "Tempo:", tempo, "BPM:", bpm)
write("Tracker: " .. tracker .. " Channels: " .. channelCount .. " ")
local timepos = term.getCursorPos()
print(("[%02d:%02d]"):format(0, 0))
for i = 1, #order do term.write(order[i] .. " ") end
term.setCursorPos(1, 3)
term.blit("0", "f", "0")
local w, h = term.getSize()
local y = 1
h = h - 5
local trackerpos = 0
local scrollPos = 1
local trackerwin = window.create(term.current(), 1, 6, w, h)
local startTime = os.epoch "utc"
local cwidth = (globalParams.shownColumns.note and 3 or 0) + (globalParams.shownColumns.volume and 3 or 0) + (globalParams.shownColumns.instrument and 3 or 0) + (globalParams.shownColumns.effect and 4 or 0) + 1

local effectString = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ\\"
local effectColor = {[0] = "4", "4", "4", "4", "4", "8", "8", "5", "3", "8", "5", "e", "5", "e", "7", "e", "e", "e", "0", "0", "8", "5", "0", "0", "0", "3", "0", "8", "0", "5", "0", "0", "0", "7", "3", "8", "8"}
local effectColorE = {[0] = "0", "4", "4", "4", "4", "4", "e", "5", "3", "8", "5", "5", "8", "8", "e", "8"}
local effectColorX = {[0] = "0", "4", "4", "0", "0", "3", "e", "0", "0", "8", "8", "0", "0", "0", "0", "0"}
local volumeString = "-vvvvvdcbauhplrg"
local volumeColor = {[0] = "0", "5", "5", "5", "5", "5", "5", "5", "5", "5", "4", "4", "3", "3", "3", "4"}

local function redrawScreen(pat, ord, start)
    term.setCursorPos(timepos, 2)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.write(("[%02d:%02d]"):format(math.floor((os.epoch "utc" - startTime) / 60000), math.floor((os.epoch "utc" - startTime) / 1000) % 60))
    term.setCursorPos(1, 3)
    local ordx = {}
    for i = 1, #order do ordx[i] = term.getCursorPos() term.write((order[i] == 254 and "-" or order[i]) .. " ") end
    term.setCursorPos(ordx[ord], 3)
    local s = pat >= 255 and "-" or tostring(pat - 1)
    term.blit(s, ("f"):rep(#s), ("0"):rep(#s))
    term.setCursorPos(1, 4)
    term.setBackgroundColor(colors.gray)
    term.clearLine()
    for i = scrollPos, channelCount do
        local text = "Channel " .. i
        if cwidth < #text then text = "Ch. " .. i end
        if cwidth < #text then text = tostring(i) end
        term.setCursorPos(cwidth * (i - scrollPos) + 5 + math.floor((cwidth - #text) / 2), 4)
        term.blit(text, (mutedChannels[i] and "8" or "0"):rep(#text), ("7"):rep(#text))
    end
    term.setCursorPos(1, 5)
    term.clearLine()
    trackerwin.clear()
    if pat >= 255 then return end
    for yy = 0, h do
        if patterns[pat][trackerpos-math.ceil(h / 2)+1] then
            trackerwin.setCursorPos(1, yy)
            trackerwin.blit(("%3d"):format(trackerpos-math.ceil(h / 2)) .. " ", "8888", "ffff")
            for j = scrollPos, channelCount do
                if patterns[pat][trackerpos-math.ceil(h / 2)+1][j] ~= nil then
                    local note = patterns[pat][trackerpos-math.ceil(h / 2)+1][j]
                    if globalParams.shownColumns.note then
                        if note.note then trackerwin.blit(formatNote(note.note), "bbb", "fff")
                        else trackerwin.blit("---", "000", "fff") end
                        if globalParams.shownColumns.instrument or not globalParams.shownColumns.volume then trackerwin.write(" ") end
                    end
                    if globalParams.shownColumns.instrument then
                        if note.instrument then trackerwin.blit(("%02d"):format(note.instrument), "99", "ff")
                        else trackerwin.blit("--", "00", "ff") end
                        if not globalParams.shownColumns.volume then trackerwin.write(" ") end
                    end
                    if globalParams.shownColumns.volume then
                        if note.volume then trackerwin.blit(volumeString:sub(math.floor(note.volume / 16) + 1, math.floor(note.volume / 16) + 1) .. ("%02d"):format(note.volume >= 0x10 and note.volume < 0x60 and math.min(note.volume - 0x10, 64) or note.volume % 16):sub(-2) .. " ", volumeColor[math.floor(note.volume / 16)]:rep(4), "ffff")
                        elseif note.note and note.instrument and note.note ~= 97 then trackerwin.blit(("v%02d "):format(instruments[note.instrument].samples[note.note].volume), "dddd", "ffff")
                        else trackerwin.blit(" -- ", "0000", "ffff") end
                    end
                    if globalParams.shownColumns.effect then
                        if note.effect then trackerwin.blit(effectString:sub(note.effect + 1, note.effect + 1) .. ("%02X"):format(note.effect_param or 0) .. " ", (note.effect == 0xE and effectColorE[bit32.rshift(note.effect_param or 0, 4)] or (note.effect == 0x21 and effectColorX[bit32.rshift(note.effect_param or 0, 4)] or effectColor[note.effect])):rep(4), "ffff")
                        else trackerwin.blit("--- ", "0000", "ffff") end
                    end
                else
                    if globalParams.shownColumns.note then
                        trackerwin.blit("---", "000", "fff")
                        if globalParams.shownColumns.instrument or not globalParams.shownColumns.volume then trackerwin.write(" ") end
                    end
                    if globalParams.shownColumns.instrument then
                        trackerwin.blit("--", "00", "ff")
                        if not globalParams.shownColumns.volume then trackerwin.write(" ") end
                    end
                    if globalParams.shownColumns.volume then trackerwin.blit(" -- ", "0000", "ffff") end
                    if globalParams.shownColumns.effect then trackerwin.blit("--- ", "0000", "ffff") end
                end
            end
        end
        trackerpos = trackerpos + 1
    end
    trackerwin.setCursorPos(1, math.ceil(h / 2))
    local line1, line2, line3 = trackerwin.getLine(math.ceil(h / 2))
    trackerwin.blit("  0 ", "0000", "7777")
    trackerwin.blit(line1:sub(5), line2:sub(5), ("7"):rep(#line3 - 4))
end

local function scrollScreen(pat)
    term.setCursorPos(timepos, 2)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.write(("[%02d:%02d]"):format(math.floor((os.epoch "utc" - startTime) / 60000), math.floor((os.epoch "utc" - startTime) / 1000) % 60))
    trackerwin.scroll(1)
    if y > 0 then
        trackerwin.setCursorPos(1, math.ceil(h / 2) - 1)
        local line1, line2, line3 = trackerwin.getLine(math.ceil(h / 2) - 1)
        trackerwin.blit(("%3d"):format(y-1) .. " ", "8888", "ffff")
        trackerwin.blit(line1:sub(5), line2:sub(5), ("f"):rep(#line3 - 4))
    end
    if y <= #patterns[pat] then
        trackerwin.setCursorPos(1, math.ceil(h / 2))
        local line1, line2, line3 = trackerwin.getLine(math.ceil(h / 2))
        trackerwin.blit(("%3d"):format(y) .. " ", "0000", "7777")
        trackerwin.blit(line1:sub(5), line2:sub(5), ("7"):rep(#line3 - 4))
    end
    trackerwin.setCursorPos(1, h)
    if patterns[pat][trackerpos-math.ceil(h / 2)+1] then
        trackerwin.blit(("%3d"):format(trackerpos-math.ceil(h / 2)) .. " ", "8888", "ffff")
        for x = scrollPos, channelCount do
            if patterns[pat][trackerpos-math.ceil(h / 2)+1] then
                if patterns[pat][trackerpos-math.ceil(h / 2)+1][x] ~= nil then
                    local note = patterns[pat][trackerpos-math.ceil(h / 2)+1][x]
                    if globalParams.shownColumns.note then
                        if note.note then trackerwin.blit(formatNote(note.note), "bbb", "fff")
                        else trackerwin.blit("---", "000", "fff") end
                        if globalParams.shownColumns.instrument or not globalParams.shownColumns.volume then trackerwin.write(" ") end
                    end
                    if globalParams.shownColumns.instrument then
                        if note.instrument then trackerwin.blit(("%02d"):format(note.instrument), "99", "ff")
                        else trackerwin.blit("--", "00", "ff") end
                        if not globalParams.shownColumns.volume then trackerwin.write(" ") end
                    end
                    if globalParams.shownColumns.volume then
                        if note.volume then trackerwin.blit(volumeString:sub(math.floor(note.volume / 16) + 1, math.floor(note.volume / 16) + 1) .. ("%02d"):format(note.volume >= 0x10 and note.volume < 0x60 and math.min(note.volume - 0x10, 64) or note.volume % 16):sub(-2) .. " ", volumeColor[math.floor(note.volume / 16)]:rep(4), "ffff")
                        elseif note.note and note.instrument and note.note ~= 97 then trackerwin.blit(("v%02d "):format(instruments[note.instrument].samples[note.note].volume), "dddd", "ffff")
                        else trackerwin.blit(" -- ", "0000", "ffff") end
                    end
                    if globalParams.shownColumns.effect then
                        if note.effect then trackerwin.blit(effectString:sub(note.effect + 1, note.effect + 1) .. ("%02X"):format(note.effect_param or 0) .. " ", (note.effect == 0xE and effectColorE[bit32.rshift(note.effect_param or 0, 4)] or (note.effect == 0x21 and effectColorX[bit32.rshift(note.effect_param or 0, 4)] or effectColor[note.effect])):rep(4), "ffff")
                        else trackerwin.blit("--- ", "0000", "ffff") end
                    end
                else
                    if globalParams.shownColumns.note then
                        trackerwin.blit("---", "000", "fff")
                        if globalParams.shownColumns.instrument or not globalParams.shownColumns.volume then trackerwin.write(" ") end
                    end
                    if globalParams.shownColumns.instrument then
                        trackerwin.blit("--", "00", "ff")
                        if not globalParams.shownColumns.volume then trackerwin.write(" ") end
                    end
                    if globalParams.shownColumns.volume then trackerwin.blit(" -- ", "0000", "ffff") end
                    if globalParams.shownColumns.effect then trackerwin.blit("--- ", "0000", "ffff") end
                end
            end
        end
    end
    trackerpos = trackerpos + 1
    y = y + 1
end

local function drawVU(vu)
    for i = scrollPos, channelCount do
        local l, r = vu[i][1], vu[i][2]
        local s = ""
        s = ("7"):rep((1 - l) * math.floor(cwidth - 2)) ..
            ("e"):rep(math.max(l - 0.75, 0) * math.floor(cwidth - 2)) ..
            ("4"):rep(math.max(math.min(l - 0.5, 0.25), 0) * math.floor(cwidth - 2)) ..
            ("d"):rep(math.max(math.min(l, 0.5), 0) * math.floor(cwidth - 2))
        while #s < cwidth - 2 do if l > 0 and r > 0 then s = s .. "d" else s = s .. "7" end end
        s = s ..
            ("d"):rep(math.max(math.min(r, 0.5), 0) * math.floor(cwidth - 2)) ..
            ("4"):rep(math.max(math.min(r - 0.5, 0.25), 0) * math.floor(cwidth - 2)) ..
            ("e"):rep(math.max(r - 0.75, 0) * math.floor(cwidth - 2)) ..
            ("7"):rep((1 - r) * math.floor(cwidth - 2))
        while #s < cwidth * 2 - 4 do s = s .. "7" end
        local st, sf, sb = "", "", ""
        for a, b in s:gmatch "(.)(.)" do
            if a == b then st, sf, sb = st .. " ", sf .. "7", sb .. a
            else st, sf, sb = st .. "\x95", sf .. a, sb .. b end
        end
        term.setCursorPos(cwidth * (i - scrollPos) + 5 + 1, 5)
        term.blit(st, sf, sb)
    end
end

local state = {tempo = tempo, bpm = bpm, channels = {}, module = {instruments = instruments, order = order}, speakers = {}, order = 1, row = 1, globalVolume = globalVolume, name = name}
for i = 1, channelCount do state.channels[i] = {num = i, effectMemory = {}, playing = {note = 0, instrument = 0, volume = 0, effect = 0, effect_param = 0}, volume = 64, volumeEnvelope = {volume = 64, pos = 0, x = 0}, vibrato = {type = 0, pos = 0}} end
for i,v in ipairs{peripheral.find("speaker")} do state.speakers[i] = {usage = 0, speaker = v} end

if sound then for i = 1, channelCount do
    sound.setVolume(i, 0)
    sound.setPan(i, 0)
    sound.setFrequency(i, 0)
    sound.setWaveType(i, "none")
end end

local left, right = peripheral.wrap "left", peripheral.wrap "right"
if left and right then
    if left.setPosition then left.setPosition(1, 0, 0) end
    if right.setPosition then right.setPosition(-1, 0, 0) end
else
    left, right = peripheral.find "speaker", nil
    if not left then error("No speaker attached") end
    if left.setPosition then left.setPosition(0, 0, 0) end
end

local function processTick(e, ls, rs, vu)
    for _,c in ipairs(state.channels) do
        --if not c.playing or c.playing.effect ~= 2 then effects[2](state, c, 0x02) end
        if e and c.playing and c.playing.effect then effects[c.playing.effect](state, c, c.playing.effect_param or 0) end
        if e and c.playing and c.playing.volume and c.playing.volume > 0x50 then volume_effects[math.floor(c.playing.volume / 16)](state, c, c.playing.volume % 16) end
        if c.instrument and c.volumeEnvelope.pos > 0 and not c.volumeEnvelope.sustain and not c.didSetInstrument and c.note then
            c.volumeEnvelope.x = c.volumeEnvelope.x + 1
            c.volumeEnvelope.volume = c.volumeEnvelope.volume + c.volumeEnvelope.rate
            if c.volumeEnvelope.x == c.instrument.volumeEnvelope.points[c.volumeEnvelope.pos+1].x then
                c.volumeEnvelope.pos = c.volumeEnvelope.pos + 1
                c.volumeEnvelope.volume = c.instrument.volumeEnvelope.points[c.volumeEnvelope.pos].y
                if c.volumeEnvelope.pos >= #c.instrument.volumeEnvelope.points or (bit32.btest(c.instrument.volumeEnvelope.loopType, 2) and c.volumeEnvelope.pos == c.instrument.volumeEnvelope.sustain) then c.volumeEnvelope.sustain = true
                else c.volumeEnvelope.rate = (c.instrument.volumeEnvelope.points[c.volumeEnvelope.pos+1].y - c.instrument.volumeEnvelope.points[c.volumeEnvelope.pos].y) / (c.instrument.volumeEnvelope.points[c.volumeEnvelope.pos+1].x - c.instrument.volumeEnvelope.points[c.volumeEnvelope.pos].x) end
            end
            setVolume(state, c, c.volume)
        end
        if c.instrument and c.instrument.panningEnvelope.loopType % 2 == 1 and not c.panningEnvelope.sustain and not c.didSetInstrument and c.note then
            c.panningEnvelope.x = c.panningEnvelope.x + 1
            c.panningEnvelope.panning = c.panningEnvelope.panning + c.panningEnvelope.rate
            if c.panningEnvelope.x == c.instrument.panningEnvelope.points[c.panningEnvelope.pos+1].x then
                c.panningEnvelope.pos = c.panningEnvelope.pos + 1
                c.panningEnvelope.panning = c.instrument.panningEnvelope.points[c.panningEnvelope.pos].y
                if c.panningEnvelope.pos + 1 > #c.instrument.panningEnvelope.points or (bit32.btest(c.instrument.panningEnvelope.loopType, 2) and c.panningEnvelope.pos == c.instrument.panningEnvelope.sustain) then c.panningEnvelope.sustain = true
                else c.panningEnvelope.rate = (c.instrument.panningEnvelope.points[c.panningEnvelope.pos+1].y - c.instrument.panningEnvelope.points[c.panningEnvelope.pos].y) / (c.instrument.panningEnvelope.points[c.panningEnvelope.pos+1].x - c.instrument.panningEnvelope.points[c.panningEnvelope.pos].x) end
            end
            setPan(state, c, c.panningEnvelope.panning * 4)
        end
        if c.instrument and c.instrument.vibrato.depth > 0 then
            doVibrato(state, c, c.instrument.vibrato.type, c.instrument.vibrato.rate / 4, c.instrument.vibrato.depth * c.instrument.vibrato.sweep_mult / 4)
            if c.instrument.vibrato.sweep_mult < 1 then c.instrument.vibrato.sweep_mult = c.instrument.vibrato.sweep_mult + (1 / c.instrument.vibrato.sweep) end
        end
        c.didSetInstrument = false
    end
    local lss, rss, vuu = sound.generate((2.5 / state.bpm) * 48000, channelCount, right)
    local sl, sr = #ls, #rs
    for i = 1, #lss do ls[sl+i] = lss[i] end
    for i = 1, #rss do rs[sr+i] = rss[i] end
    if vu[1] then for i = 1, #vuu do vu[i][1], vu[i][2] = vu[i][1] + vuu[i][1], vu[i][2] + vuu[i][2] end
    else for i = 1, #vuu do vu[i] = vuu[i] end end
    vu.count = (vu.count or 0) + 1
end

if globalParams.autoSize then
    if channelCount * 14 + 4 > w then globalParams.shownColumns.instrument = false end
    if channelCount * 11 + 4 > w then globalParams.shownColumns.effect = false end
    if channelCount * 7 + 4 > w then globalParams.shownColumns.volume = false end
    -- if it's still too small: oh well
end

local skippedRow = false
local pauseState = nil

local empty_audio = {}
for i = 1, 2400 do empty_audio[i] = 0 end
left.playAudio(empty_audio)
if right then right.playAudio(empty_audio) end

local ok, err = pcall(parallel.waitForAny, function()

while state.order <= #order do
    local v = order[state.order]
    state.currentOrder = state.order
    trackerpos = state.row - 1
    y = state.row
    redrawScreen(v+1, state.order)
    --scrollScreen(v+1)
    while v < 254 and state.row <= #patterns[v+1] do
        state.tick = 1
        state.currentRow = state.row
        state.usedB, state.usedD = nil
        local row = patterns[v+1][state.row]
        if not row then error((v + 1) .. "/" .. state.row) end
        for _,x in ipairs(state.speakers) do x.usage = 0 end
        for k,c in ipairs(state.channels) do
            c.playing = row[k]
            if c.playing then
                if c.playing.instrument and state.module.instruments[c.playing.instrument] then
                    setInstrument(state, c, c.playing.instrument)
                    if (c.playing.note or c.lastNote) ~= 97 then setPan(state, c, c.instrument.samples[c.playing.note or c.lastNote].pan) end
                end
                if c.playing.volume then volume_effects[math.floor(c.playing.volume / 16)](state, c, c.playing.volume % 16) end
                if c.playing.note and c.playing.note ~= 0 then
                    if (not c.playing.volume or c.playing.volume < 0x10 or c.playing.volume >= 0x60) and c.playing.note < 97 then setVolume(state, c, c.instrument.samples[c.playing.note].volume) end
                    if not c.playing.effect or c.playing.effect == 9 or effects[c.playing.effect](state, c, c.playing.effect_param or 0) ~= 0 then
                        if c.playing.note ~= 97 then c.lastNote = c.playing.note end
                        setNote(state, c, c.playing.note)
                    end
                end
                if (not c.playing.note or c.playing.note == 0 or c.playing.effect == 9) and c.playing.effect then effects[c.playing.effect](state, c, c.playing.effect_param or 0) end
            end
        end
        local ls, rs, vu = {}, {}, {}
        processTick(false, ls, rs, vu)
        --waitForNextTick(state)
        if skippedRow then break end
        for k = 2, state.tempo do
            state.tick = k
            processTick(true, ls, rs, vu)
            --waitForNextTick(state)
            if skippedRow then break end
        end
        waitForNextRow(state, right)
        left.playAudio(ls, 1)
        if right then right.playAudio(rs, 1) end
        for i,v in ipairs(vu) do v[1], v[2] = v[1] / vu.count, v[2] / vu.count end
        drawVU(vu)
        if skippedRow then break end
        if pauseState then
            while pauseState == 0 do os.pullEvent() end
            if pauseState then pauseState = 0 end
            left.playAudio(empty_audio)
            if right then right.playAudio(empty_audio) end
        end
        if state.order ~= state.currentOrder then
            if not state.usedD then state.row = 1 end
            break
        end
        if state.row ~= state.currentRow then
            y = state.row
            trackerpos = state.row - 1
            redrawScreen(v+1, state.order)
        else
            scrollScreen(v+1)
            state.row = state.row + 1
        end
    end
    if skippedRow then
        skippedRow = false
    elseif state.order == state.currentOrder then
        state.row = 1
        state.order = state.order + 1
        if globalParams.loop and state.order > #order then state.order = restartPosition + 1 end
    end
end

end, function()
    while true do
        local didChangeMuted
        local ev, ch = os.pullEvent()
        if ev == "char" and ch == "q" then break
        elseif ev == "key" then
            if ch == keys.left then
                state.row = 1
                if state.order == 1 then state.order = #state.module.order
                else state.order = state.order - 1 end
                skippedRow = true
                if pauseState then pauseState = 1 end
            elseif ch == keys.right then
                state.row = 1
                if state.order == #state.module.order then state.order = 1
                else state.order = state.order + 1 end
                if pauseState then pauseState = 1 end
            elseif ch == keys.p then
                if pauseState then pauseState = nil
                else pauseState = 1 end
            elseif ch == keys.down then
                if pauseState then pauseState = 1 end
            elseif ch == keys.up then
                if pauseState then
                    state.row = state.row - 1
                    if state.row < 1 then
                        if state.order == 1 then state.order = #state.module.order
                        else state.order = state.order - 1 end
                        state.row = #patterns[order[state.order]]
                    end
                    pauseState = 1
                end
            elseif ch == keys.one then mutedChannels[1] = not mutedChannels[1] didChangeMuted = true
            elseif ch == keys.two then mutedChannels[2] = not mutedChannels[2] didChangeMuted = true
            elseif ch == keys.three then mutedChannels[3] = not mutedChannels[3] didChangeMuted = true
            elseif ch == keys.four then mutedChannels[4] = not mutedChannels[4] didChangeMuted = true
            elseif ch == keys.five then mutedChannels[5] = not mutedChannels[5] didChangeMuted = true
            elseif ch == keys.six then mutedChannels[6] = not mutedChannels[6] didChangeMuted = true
            elseif ch == keys.seven then mutedChannels[7] = not mutedChannels[7] didChangeMuted = true
            elseif ch == keys.eight then mutedChannels[8] = not mutedChannels[8] didChangeMuted = true
            elseif ch == keys.nine then mutedChannels[9] = not mutedChannels[9] didChangeMuted = true
            elseif ch == keys.zero then mutedChannels[10] = not mutedChannels[10] didChangeMuted = true
            elseif ch == keys.a and scrollPos > 1 then scrollPos = scrollPos - 1 y = state.row trackerpos = state.row - 1 redrawScreen(order[state.order]+1, state.order)
            elseif ch == keys.d and scrollPos < channelCount then scrollPos = scrollPos + 1 y = state.row trackerpos = state.row - 1 redrawScreen(order[state.order]+1, state.order)
            end
        end
        if didChangeMuted then
            term.setCursorPos(1, 4)
            term.setBackgroundColor(colors.gray)
            term.clearLine()
            local cwidth = (globalParams.shownColumns.note and 3 or 0) + (globalParams.shownColumns.volume and 3 or 0) + (globalParams.shownColumns.instrument and 3 or 0) + (globalParams.shownColumns.effect and 4 or 0) + 1
            for i = scrollPos, channelCount do
                local text = "Channel " .. i
                if cwidth < #text then text = "Ch. " .. i end
                if cwidth < #text then text = tostring(i) end
                term.setCursorPos(cwidth * (i - 1) + 5 + math.floor((cwidth - #text) / 2), 4)
                term.blit(text, (mutedChannels[i] and "8" or "0"):rep(#text), ("7"):rep(#text))
            end
        end
    end
end)

term.setCursorPos(1, 1)
if not ok then
    printError(err)
end
if sound then for i = 1, channelCount do sound.setFrequency(i, 0) end end
left.stop()
if right then right.stop() end
