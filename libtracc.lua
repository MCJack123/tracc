-- libtracc XM/S3M/IT module player library
-- Licensed under the MIT license.
-- Copyright (c) 2021-2024 JackMacWindows.

local libtracc = {
    interpolation = "none"
}

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

---@class tracc.sample
---@field size number
---@field loopStart number
---@field loopLength number
---@field volume number
---@field finetune number
---@field type number
---@field pan number
---@field note number
---@field name string
---@field wavetable number[]

---@class tracc.envelope
---@field points {x: number, y: number}[]
---@field sustain number
---@field loopStart number
---@field loopEnd number
---@field loopType number

---@class tracc.instrument
---@field samples tracc.sample[]
---@field samplesByNumber tracc.sample[]
---@field volumeEnvelope tracc.envelope
---@field panningEnvelope tracc.envelope
---@field vibrato {type: number, sweep: number, depth: number, rate: number, sweep_mult: number}
---@field fadeOut number

---@class tracc.note
---@field note number|nil
---@field instrument number|nil
---@field volume number|nil
---@field effect number|nil
---@field effect_param number|nil

---@class tracc.module
---@field instruments tracc.instrument[]
---@field patterns tracc.note[][]
---@field order number[]
---@field name string
---@field tracker string
---@field amigaSlides boolean
---@field restartPosition number

---@class tracc.channel
---@field num number
---@field effectMemory table
---@field playing {note: number, instrument: number, volume: number, effect: number, effect_param: number}
---@field volume number
---@field pan number
---@field volumeEnvelope {volume: number, pos: number, x: number, sustain: boolean, rate: number}
---@field panningEnvelope {panning: number, pos: number, x: number, sustain: boolean, rate: number}
---@field vibrato {type: number, pos: number}
---@field speaker table|nil
---@field note number|nil
---@field finetune number|nil
---@field frequency number|nil
---@field instrument tracc.instrument|nil
---@field didSetInstrument boolean|nil
---@field lastNote number|nil

---@class tracc
---@field tempo number
---@field bpm number
---@field channels tracc.channel[]
---@field module tracc.module
---@field order number
---@field row number
---@field tick number|nil
---@field globalVolume number
---@field mutedChannels table<number, boolean>
---@field mixVolume number
---@field loop boolean
---@field sound tracc.sound
---@field usedB boolean|nil
---@field usedD boolean|nil
---@field usedE6 number|nil
---@field usedEE number|nil
---@field currentOrder number
---@field currentRow number

-- Software mixer emulating craftos2-sound (custom waves only for now)
local function makeSound()
    ---@class tracc.sound
    local sound = {channels = {}, version = 2, interpolation = libtracc.interpolation}
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
    function sound.generate(state, length, cc, stereo)
        local retval, right, vu = {}, {}, {}
        for j = 1, length do
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
                        sample, rs = sample + s * math.min(c.pan+1, 1) * state.mixVolume, rs + s * math.min(1-c.pan, 1) * state.mixVolume
                        if vu[i] then vu[i][1], vu[i][2] = vu[i][1] + tovu(s * math.min(c.pan+1, 1) * state.mixVolume), vu[i][2] + tovu(s * math.min(1-c.pan, 1) * state.mixVolume)
                        else vu[i] = {tovu(s * math.min(c.pan+1, 1)), tovu(s * math.min(1-c.pan, 1) * state.mixVolume)} end
                    else
                        sample = sample + s * state.mixVolume
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
            retval[j] = math.max(math.min(sample / 2, 1), -1) * 127
            right[j] = math.max(math.min(rs / 2, 1), -1) * 127
        end
        for i = 1, (cc or 32) do vu[i] = vu[i] and {vu[i][1] / length, vu[i][2] / length} or {0, 0} end
        return retval, right, vu
    end
    return sound
end

local function fromLE(str)
    if not str then error(debug.traceback("Bad str"), 2) end
    local n = 0
    for i = 1, #str do n = n + bit32.lshift(str:byte(i), 8*(i-1)) end
    return n
end

---@param state tracc
---@param note number
---@param finetune number
---@param sample tracc.sample
---@return number
local function toFreq(state, note, finetune, sample)
    if state.amigaSlides then
        local a = ((note % 12)*8 + math.floor(finetune/16)) % 96
        return 14317456/((amigaTable[a]*(1-(finetune/16 % 1)) + amigaTable[(a+1) % 96]*((finetune/16 % 1))) * 16 / 2^math.floor(note / 12 - 1))
    else return 8363*2^((6*12*16*4 - (10*12*16*4 - (note-1)*16*4 - math.floor(finetune/2))) / (12*16*4)) end
end
---@param state tracc
---@param frequency number
---@param slide number
---@return number
local function slideFreq(state, frequency, slide)
    if state.amigaSlides then return 14317456 / (14317456 / frequency - slide * 2)
    else return frequency * 2^(slide / portaDrift) end
end
---@param note number
---@param name string
---@return number
local function toNote(note, name) return note - 12*(noteRange[name]-1) - 7 end
---@param note number
---@return number
local function toSpeed(note) return 2^((note - 49)/12) end
---@param state tracc
---@param channel number
---@param sample tracc.sample
local function getFrequency(state, channel, sample) return state.sound.getFrequency(channel) * #sample.wavetable end
---@param state tracc
---@param channel number
---@param freq number
---@param sample tracc.sample
local function setFrequency(state, channel, freq, sample) state.sound.setFrequency(channel, freq / #sample.wavetable) end

---@param state tracc
---@param channel tracc.channel
---@param vol number
local function setVolume(state, channel, vol)
    channel.volume = vol
    if not channel.speaker then
        if state.mutedChannels[channel.num] then state.sound.setVolume(channel.num, 0)
        else state.sound.setVolume(channel.num, vol / 64 * (state.globalVolume / 64) * (channel.volumeEnvelope.volume / 64) * (channel.instrument and channel.instrument.volume or 1)) end
    end
end

---@param state tracc
---@param channel tracc.channel
---@param pan number
local function setPan(state, channel, pan)
    channel.pan = pan
    if not channel.speaker then
        state.sound.setPan(channel.num, -math.max((pan - 127) / 127, -1))
    end
    -- TODO: Add stereo capability to CC speakers
end

---@param state tracc
---@param channel tracc.channel
---@param inst number
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

---@param state tracc
---@param channel tracc.channel
---@param note number
---@param keepPos? boolean
local function setNote(state, channel, note, keepPos)
    channel.speaker = nil
    if note == 97 or note >= 254 then
        if not channel.speaker then
            if channel.instrument and #channel.instrument.volumeEnvelope.points > 1 and not (channel.playing and channel.playing.effect == 0xE and channel.playing.effect_param and bit32.band(channel.playing.effect_param, 0xF0) == 0xD0) and channel.instrument.fadeOut > 0 then
                state.sound.fadeOut(channel.num, (32768 / channel.instrument.fadeOut) * (2.5 / state.bpm))
            elseif channel.instrument and #channel.instrument.volumeEnvelope.points - 1 == channel.instrument.volumeEnvelope.sustain then
                state.sound.fadeOut(channel.num, (channel.instrument.volumeEnvelope.points[#channel.instrument.volumeEnvelope.points].x - channel.instrument.volumeEnvelope.points[#channel.instrument.volumeEnvelope.points-1].x) * (2.5 / state.bpm))
            else state.sound.setVolume(channel.num, 0) state.sound.setFrequency(channel.num, 0) channel.frequency = 0 end
        end
        channel.note = nil
    elseif note ~= 0 and channel.instrument then
        local sample = channel.instrument.samples[note]
        if not sample then
        elseif sample.name == "unused" then
            if not channel.speaker then state.sound.setVolume(channel.num, 0) end
        elseif not channel.speaker and state.sound.version then
            channel.finetune = sample.finetune
            channel.frequency = toFreq(state, note+sample.note, channel.finetune, sample)
            state.sound.setWaveType(channel.num, "custom", sample.wavetable, sample.loopStart, bit32.band(sample.type, 3), keepPos)
            if sample.name:byte(1) == 33 then state.sound.setInterpolation(channel.num, "linear")
            else state.sound.setInterpolation(channel.num, nil) end
            setFrequency(state, channel.num, channel.frequency, sample)
        elseif noteRange[sample.name] then
            local spk
            for _,v in ipairs(state.speakers) do
                if v.usage < 1 then
                    spk = v.speaker
                    v.usage = v.usage + (1 / libtracc.notesPerTick)
                    break
                end
            end
            if not spk then error("Not enough speakers to play module") end
            channel.speaker = spk
            state.sound.setVolume(channel.num, 0)
            if toNote(note, sample.name) >= 0 and toNote(note, sample.name) <= 24 and not state.mutedChannels[channel.num] then spk.playNote(sample.name, channel.volume / 64 * (state.globalVolume / 64), toNote(note, sample.name)) end
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
            state.sound.setVolume(channel.num, 0)
            if not state.mutedChannels[channel.num] then spk.playSound(sample.name, channel.volume / 64 * (state.globalVolume / 64), toSpeed(note)) end
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
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    [0] = function(state, channel, param) end, -- (does not exist)
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- 1
        if param == 0 then param = channel.effectMemory[0xE1] or 0
        else channel.effectMemory[0xE1] = param end
        if not channel.speaker and state.tick == 1 and channel.note then
            channel.frequency = slideFreq(state, channel.frequency, param)
            setFrequency(state, channel.num, slideFreq(state, getFrequency(state, channel.num, channel.instrument.samples[channel.note]), param), channel.instrument.samples[channel.note])
        end
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- 2
        if param == 0 then param = channel.effectMemory[0xE2] or 0
        else channel.effectMemory[0xE2] = param end
        if not channel.speaker and state.tick == 1 and channel.note then
            channel.frequency = slideFreq(state, channel.frequency, -param)
            setFrequency(state, channel.num, slideFreq(state, getFrequency(state, channel.num, channel.instrument.samples[channel.note]), -param), channel.instrument.samples[channel.note])
        end
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- 3
        -- TODO
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- 4
        channel.vibrato.type = param
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- 5
        if not channel.speaker then
            channel.finetune = param
            if channel.playing then
                channel.frequency = toFreq(state, channel.playing.note+channel.instrument.samples[channel.playing.note].note, channel.finetune, channel.instrument.samples[channel.playing.note])
                setFrequency(state, channel.num, channel.frequency, channel.instrument.samples[channel.playing.note])
            end
        end
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- 6
        if param == 0 then channel.effectMemory[0xE6] = state.row
        else
            if not state.usedE6 or state.usedE6 > 0 then
                state.row = channel.effectMemory[0xE6] or state.row
                state.usedE6 = (state.usedE6 or param) - 1
            else state.usedE6 = nil end
        end
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- 7
        -- TODO
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- 8
        setPan(state, channel, param * 16)
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- 9
        if param > 0 and state.tick > 1 and (state.tick - 1) % param == 0 then
            setNote(state, channel, channel.playing.note or 97)
        end
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- A
        if param == 0 then param = channel.effectMemory[0xEA] or 0
        else channel.effectMemory[0xEA] = param end
        if state.tick == 1 then setVolume(state, channel, math.min(channel.volume + math.floor(param), 64)) end
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- B
        if param == 0 then param = channel.effectMemory[0xEB] or 0
        else channel.effectMemory[0xEB] = param end
        if state.tick == 1 then setVolume(state, channel, math.max(channel.volume - param, 0)) end
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- C
        if state.tick == param + 1 then
            setVolume(state, channel, 0)
        end
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- D
        if state.tick == 1 then
            --setNote(state, channel, 97)
            return 0
        end
        if state.tick - 1 == param then setNote(state, channel, channel.playing.note) end
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- E
        if not state.usedEE or state.usedEE > 0 then
            local ex = state.usedEE ~= nil
            state.row = state.row - 1
            state.usedEE = (state.usedEE or param) - 1
            if ex then return 0 end
        else state.usedEE = nil end
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- F
        -- unimplemented
    end
}

local x_effects = {
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    [0] = function(state, channel, param) end, -- (does not exist)
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- 1
        if param == 0 then param = channel.effectMemory[0x211] or 0
        else channel.effectMemory[0x211] = param end
        if not channel.speaker and state.tick == 1 and channel.note then
            channel.frequency = slideFreq(state, channel.frequency, param / 16)
            setFrequency(state, channel.num, slideFreq(state, getFrequency(state, channel.num, channel.instrument.samples[channel.note]), param / 16), channel.instrument.samples[channel.note])
        end
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- 2
        if param == 0 then param = channel.effectMemory[0x212] or 0
        else channel.effectMemory[0x212] = param end
        if not channel.speaker and state.tick == 1 and channel.note then
            channel.frequency = slideFreq(state, channel.frequency, param / -16)
            setFrequency(state, channel.num, slideFreq(state, getFrequency(state, channel.num, channel.instrument.samples[channel.note]), param / -16), channel.instrument.samples[channel.note])
        end
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) end, -- 3 (does not exist)
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) end, -- 4 (does not exist)
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) end, -- 5 (does not exist)
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) end, -- 6 (does not exist)
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) end, -- 7 (does not exist)
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) state.order = math.huge end, -- 8 (tracc hack - stops song)
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) end, -- 9 (does not exist)
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) end, -- A (does not exist)
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) end, -- B (does not exist)
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) end, -- C (does not exist)
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) end, -- D (does not exist)
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) end, -- E (does not exist)
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) end -- F (does not exist)
}

---@param state tracc
---@param channel tracc.channel
---@param t number
---@param speed number
---@param depth number
local function doVibrato(state, channel, t, speed, depth)
    local amplitude
    if t == 0 then amplitude = math.sin(channel.vibrato.pos * math.pi)
    elseif t == 1 then amplitude = channel.vibrato.pos * 2 - 1
    elseif t == 2 then amplitude = channel.vibrato.pos >= 0.5 and -1 or 1
    elseif t == 8 then amplitude = (1 - channel.vibrato.pos) * 2 - 1 -- ramp down (special)
    else amplitude = math.random() * 2 - 1 end
    if channel.instrument and channel.note then
        local sample = channel.instrument.samples[channel.note]
        setFrequency(state, channel.num, slideFreq(state, channel.frequency, amplitude * depth * 2), sample)
    end
    channel.vibrato.pos = (channel.vibrato.pos + (speed / 64)) % 1
end

local effects
effects = {
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    [0] = function(state, channel, param) -- 0
        if not channel.instrument then return end
        if state.tick % 3 == 1 then setNote(state, channel, channel.lastNote or channel.playing.note, true)
        elseif state.tick % 3 == 2 then setNote(state, channel, (channel.lastNote or channel.playing.note) + bit32.rshift(param, 4), true)
        else setNote(state, channel, (channel.lastNote or channel.playing.note) + bit32.band(param, 0xF), true) end
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- 1
        if param == 0 then param = channel.effectMemory[1] or 0
        else channel.effectMemory[1] = param end
        if not channel.speaker and state.tick > 1 and channel.note then
            channel.frequency = slideFreq(state, channel.frequency, param)
            setFrequency(state, channel.num, slideFreq(state, getFrequency(state, channel.num, channel.instrument.samples[channel.note]), param), channel.instrument.samples[channel.note])
        end
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- 2
        if param == 0 then param = channel.effectMemory[2] or 0
        else channel.effectMemory[2] = param end
        if not channel.speaker and state.tick > 1 and channel.note then
            channel.frequency = slideFreq(state, channel.frequency, -param)
            setFrequency(state, channel.num, math.max(slideFreq(state, getFrequency(state, channel.num, channel.instrument.samples[channel.note]), -param), 0), channel.instrument.samples[channel.note])
        end
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- 3
        if param == 0 then param = channel.effectMemory[3] or 0
        else channel.effectMemory[3] = param end
        if not channel.speaker and channel.note and channel.instrument then
            local note = channel.playing.note or channel.lastNote
            local sample = channel.instrument.samples[note]
            if sample then
                --print(sample.name, channel.playing.note, channel.lastNote, sample.note, getFrequency(state, channel.num, sample), toFreq(state, note+sample.note, sample.finetune, sample))
                if state.tick == 1 and channel.playing.note then
                    note = channel.lastNote
                    sample = channel.instrument.samples[note]
                    if sample then
                        channel.finetune = sample.finetune
                        channel.frequency = toFreq(state, note+sample.note, channel.finetune, sample)
                        setFrequency(state, channel.num, channel.frequency, sample)
                        if channel.playing and channel.playing.note then channel.lastNote = channel.playing.note end
                    end
                    return 0
                elseif channel.frequency < slideFreq(state, toFreq(state, note+sample.note, sample.finetune, sample), param * -2) then
                    channel.frequency = slideFreq(state, channel.frequency, param * 2)
                    setFrequency(state, channel.num, slideFreq(state, getFrequency(state, channel.num, sample), param * 2), sample)
                elseif channel.frequency > slideFreq(state, toFreq(state, note+sample.note, sample.finetune, sample), param * 2) then
                    channel.frequency = slideFreq(state, channel.frequency, param * -2)
                    setFrequency(state, channel.num, slideFreq(state, getFrequency(state, channel.num, sample), param * -2), sample)
                elseif channel.frequency ~= toFreq(state, note+sample.note, sample.finetune, sample) then
                    channel.frequency = toFreq(state, note+sample.note, sample.finetune, sample)
                    setFrequency(state, channel.num, channel.frequency, sample)
                end
            end
        end
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- 4
        if param == 0 then param = channel.effectMemory[4] or 0
        else channel.effectMemory[4] = param end
        if state.tick == 1 and channel.playing and channel.playing.note and bit32.btest(channel.vibrato.type, 4) then channel.vibrato.pos = 0 end
        doVibrato(state, channel, bit32.band(channel.vibrato.type, 3), bit32.rshift(param, 4), bit32.band(param, 0x0f))
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- 5
        effects[0x3](state, channel, 0)
        return effects[0xA](state, channel, param)
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- 6
        effects[0x4](state, channel, 0)
        return effects[0xA](state, channel, param)
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- 7
        -- TODO
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- 8
        setPan(state, channel, param)
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- 9
        if state.tick == 1 and not state.mutedChannels[channel.num] then state.sound.setPosition(channel.num, param * 256) end
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- A
        if param == 0 then param = channel.effectMemory[0xA] or 0
        else channel.effectMemory[0xA] = param end
        if state.tick > 1 then
            if param < 16 then setVolume(state, channel, math.max(channel.volume - param, 0))
            else setVolume(state, channel, math.min(channel.volume + math.floor(param / 16), 64)) end
        end
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- B
        if state.tick == 1 then state.order = param + 1 state.usedB = true end
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- C
        setVolume(state, channel, param)
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
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
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- E
        return e_effects[bit32.rshift(param, 4)](state, channel, bit32.band(param, 0xF))
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- F
        if param < 0x20 then
            if param == 0 then state.order = math.huge -- stop song
            else state.tempo = param end
        else state.bpm = param end
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- G
        state.globalVolume = param
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- H
        if param == 0 then param = channel.effectMemory[0x11] or 0
        else channel.effectMemory[0x11] = param end
        if state.tick > 1 then
            if param < 16 then state.globalVolume = math.max(state.globalVolume - param, 0)
            else state.globalVolume = math.min(state.globalVolume + math.floor(param / 16), 64) end
            setVolume(state, channel, channel.volume)
        end
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) end, -- I (does not exist)
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) end, -- J (does not exist)
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- K
        if state.tick == param + 1 then
            setNote(state, channel, 97)
        end
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
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
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) end, -- M (does not exist)
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) end, -- N (does not exist)
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) end, -- O (does not exist)
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- P
        if param == 0 then param = channel.effectMemory[0x19] or 0
        else channel.effectMemory[0x19] = param end
        if state.tick == 1 then
            if param < 16 then setPan(state, channel, math.max(channel.pan - param, 0))
            else setPan(state, channel, math.min(channel.pan + math.floor(param / 16), 128)) end
        end
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) end, -- Q (does not exist)
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
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
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) end, -- S (does not exist)
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- T
        -- TODO
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) end, -- U (does not exist)
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) end, -- V (does not exist)
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) end, -- W (does not exist)
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- X
        return x_effects[bit32.rshift(param, 4)](state, channel, bit32.band(param, 0xF))
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- Y
        -- unimplemented
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- Z
        -- unimplemented
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- \
        -- unimplemented
    end
}

local volume_effects
volume_effects = {
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    [0] = function(state, channel, param) end, -- do nothing
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- v
        setVolume(state, channel, param)
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) return volume_effects[1](state, channel, param + 16) end, -- v
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) return volume_effects[1](state, channel, param + 32) end, -- v
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) return volume_effects[1](state, channel, param + 48) end, -- v
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) return volume_effects[1](state, channel, 64) end, -- v
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- d
        return effects[0xA](state, channel, param)
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- c
        return effects[0xA](state, channel, param * 16)
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- b
        return e_effects[0xB](state, channel, param)
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- a
        return e_effects[0xA](state, channel, param)
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- u
        -- TODO
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- h
        -- TODO
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- p
        setPan(state, channel, param * 16)
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- l
        return effects[0x19](state, channel, param)
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- r
        return effects[0x19](state, channel, param * 16)
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- g
        return effects[3](state, channel, param * 16)
    end,
}

--- Creates a new tracc state from an XM file handle.
---@param file file The file to read
---@return tracc state The new tracc state
function libtracc.readXMFile(file)
    local patterns, order, instruments = {}, {}, {}
    local name, tracker
    local restartPosition, channelCount, tempo, bpm, amigaSlides
    local globalVolume = 64
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
                        for k = 1, size / 2 do
                            local d = fromLE(file.read(2))
                            if d > 0x7FFF then d = d - 0x10000 end
                            sample.wavetable[k], last = math.max(math.min((last + d) / ((last + d) > 0 and 0x7FFF or 0x8000), 1), -1), last + d
                            while last > 0x7FFF do last = last - 0x10000 end
                            while last < -0x8000 do last = last + 0x10000 end
                        end
                    else
                        local last = 0
                        for k = 1, size do
                            local d = file.read()
                            if d > 0x7F then d = d - 256 end
                            sample.wavetable[k], last = math.max(math.min((last + d) / ((last + d) > 0 and 127 or 128), 1), -1), last + d
                            while last > 127 do last = last - 256 end
                            while last < -128 do last = last + 256 end
                        end
                    end
                end
            end
        else file.seek("cur", instsize - 29) end
    end
    local state = {
        tempo = tempo,
        bpm = bpm,
        channels = {},
        module = {
            instruments = instruments,
            patterns = patterns,
            order = order,
            name = name,
            tracker = tracker,
            amigaSlides = amigaSlides,
            restartPosition = restartPosition
        },
        speakers = {},
        order = 1,
        row = 1,
        globalVolume = globalVolume,
        mutedChannels = {},
        mixVolume = 1,
        loop = true,
        sound = makeSound()
    }
    for i = 1, channelCount do
        state.channels[i] = {
            num = i,
            effectMemory = {},
            playing = {note = 0, instrument = 0, volume = 0, effect = 0, effect_param = 0},
            volume = 64,
            volumeEnvelope = {volume = 64, pos = 0, x = 0},
            vibrato = {type = 0, pos = 0}
        }
    end
    return state
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
        error("Unknown S effect")
    end,
    function(p) if p >= 0x20 then return 0x0F, p end end, -- T
    function(p) end, -- U (unimplemented)
    function(p) return 0x10, p end, -- V
    function(p) return 0x11, p end, -- W
    function(p) return 0x08, math.min(p * 2, 255) end, -- X
    function(p) return 0x22, p end, -- Y
    function(p) return 0x23, p end, -- Z
}

--- Creates a new tracc state from an S3M file handle. This is a lossy conversion to XM!
---@param file file The file to read
---@return tracc state The new tracc state
function libtracc.readS3MFile(file)
    local patterns, order, instruments, mutedChannels = {}, {}, {}, {}
    local name, tracker
    local restartPosition, channelCount, tempo, bpm, amigaSlides
    local globalVolume = 64
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
    --print(numOrders)
    --print(file.seek())
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
        --print(instPP[i])
        file.seek("set", instPP[i])
        file.read(13) -- type, filename
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
        --print(c2speed, note, sample.note, sample.finetune)
        file.read(12)
        inst.name = file.read(28):gsub("[ %z]+$", "")
        sample.name = inst.name
        --print(inst.name)
        if file.read(4) ~= "SCRS" then
            file.close()
            error("Invalid S3M module")
        end
        --print(dataPP)
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
    local state = {
        tempo = tempo,
        bpm = bpm,
        channels = {},
        module = {
            instruments = instruments,
            patterns = patterns,
            order = order,
            name = name,
            tracker = tracker,
            amigaSlides = amigaSlides,
            restartPosition = restartPosition
        },
        speakers = {},
        order = 1,
        row = 1,
        globalVolume = globalVolume,
        mutedChannels = mutedChannels,
        mixVolume = 1,
        loop = true,
        sound = makeSound()
    }
    for i = 1, channelCount do
        state.channels[i] = {
            num = i,
            effectMemory = {},
            playing = {note = 0, instrument = 0, volume = 0, effect = 0, effect_param = 0},
            volume = 64,
            volumeEnvelope = {volume = 64, pos = 0, x = 0},
            vibrato = {type = 0, pos = 0}
        }
    end
    return state
end

local itTrackerFmt = {
    [0] = "Impulse Tracker %d.%d%d",
    "Schism Tracker %d.%d%d",
    nil, nil,
    "pyIT %d.%d%d",
    "OpenMPT %d.%d%d",
    "BeRoTracker %d.%d%d",
    "ITMCK %d.%d.%d",
    "Tralala %d.%d%d",
    nil, nil, nil,
    "ChickDune ChipTune Tracker %d.%d%d"
}

local function itTrackers(num)
    if num == 0x7FFF then return "munch.py"
    elseif num == 0xDAEB then return "spc2it" end
    local fmt = itTrackerFmt[bit32.rshift(bit32.band(num, 0xF000), 12)]
    if fmt then return fmt:format(bit32.rshift(bit32.band(num, 0x0F00), 8), bit32.rshift(bit32.band(num, 0xF0), 4), bit32.band(num, 0xF))
    else return "Unknown" end
end

local itEffects = setmetatable({

}, {__index = s3mEffects})

--- Creates a new tracc state from an IT file handle. This is a lossy conversion to XM!
---@param file file The file to read
---@return tracc state The new tracc state
function libtracc.readITFile(file)
    local patterns, order, instruments, mutedChannels = {}, {}, {}, {}
    local name, tracker
    local restartPosition, channelCount, tempo, bpm, amigaSlides, mixVolume
    local globalVolume = 64
    if file.read(4) ~= "IMPM" then
        file.close()
        error("Not an IT module")
    end
    name = file.read(26):gsub("[ %z]+$", "")
    file.read(2)
    local numOrders = fromLE(file.read(2))
    local instrumentCount = fromLE(file.read(2))
    local sampleCount = fromLE(file.read(2))
    local patternCount = fromLE(file.read(2))
    tracker = itTrackers(fromLE(file.read(2))) or "Unknown"
    local compatver = fromLE(file.read(2))
    local flags = fromLE(file.read(2))
    file.read(2) -- special
    globalVolume = file.read() / 2
    mixVolume = file.read() / 128
    tempo = file.read()
    bpm = file.read()
    file.read() -- pan separation
    restartPosition = 0
    amigaSlides = not bit32.btest(flags, 8)
    file.read(11) -- padding/message
    for i = 1, 64 do
        local s = file.read()
        if s == 255 or channelCount then
        else
            if bit32.btest(s, 0x80) then
                if not channelCount then channelCount = i - 1 end
                mutedChannels[i] = true
            else channelCount = nil end
        end
    end
    mixVolume = mixVolume / channelCount
    file.read(64) -- TODO: channel volume
    if not channelCount then channelCount = 32 end
    --print(numOrders)
    --print(file.seek())
    for i = 1, numOrders do
        local n = file.read()
        order[i] = n
    end
    --if numOrders % 2 == 1 then file.read() end
    local instPP, patPP, sampPP = {}, {}, {}
    for i = 1, instrumentCount do instPP[i] = fromLE(file.read(4)) end
    for i = 1, sampleCount do sampPP[i] = fromLE(file.read(4)) end
    for i = 1, patternCount do patPP[i] = fromLE(file.read(4)) end

    local samples = {}
    for i = 1, sampleCount do
        local sample = {wavetable = {}, volume = 64, pan = 128}
        samples[i] = sample
        file.seek("set", sampPP[i])
        assert(file.read(4) == "IMPS", "Invalid file")
        file.read(12) -- DOS name
        file.read()
        sample.globalVolume = file.read()
        local sflags = file.read()
        sample.type = (bit32.btest(sflags, 0x10) and (bit32.btest(sflags, 0x40) and 2 or 1) or 0) + (bit32.btest(sflags, 2) and 0x10 or 0)
        sample.volume = file.read()
        sample.name = file.read(26):gsub("[ %z]+$", "")
        local convert = fromLE(file.read(2))
        local size = fromLE(file.read(4))
        sample.loopStart = fromLE(file.read(4))
        sample.loopLength = fromLE(file.read(4)) - sample.loopStart
        local c5speed = fromLE(file.read(4))
        local note = 12 * math.log(c5speed / 8363, 2)
        sample.note = math.ceil(note - 0.5)
        sample.finetune = math.floor((note - sample.note) * 127)
        file.read(8) -- TODO: sustain loop
        local addr = fromLE(file.read(4))
        sample.vibrato = {sweep = file.read(), depth = file.read(), type = file.read(), rate = file.read(), sweep_mult = 0} -- cloned to instrument
        file.seek("set", addr)
        local signed = bit32.btest(convert, 1)
        local bit16 = bit32.btest(sflags, 2)
        local ampl = bit16 and 32768 or 128
        local offset = signed and ampl or 0
        local format
        if bit16 then
            if bit32.btest(convert, 2) then format = ">"
            else format = "<" end
            if signed then format = format .. "h"
            else format = format .. "H" end
        else
            if signed then format = "b"
            else format = "B" end
        end
        local fmtsize = format:packsize()
        local isDelta = bit32.btest(convert, 0xC)
        local last = 0
        for j = 1, size do
            local n = format:unpack(file.read(fmtsize)) - offset
            if isDelta then n = last + n end
            last = n
            n = n / (n < 0 and ampl or (ampl - 1))
            sample.wavetable[j] = n
        end
    end

    for i = 1, instrumentCount do
        local inst = {
            samples = {},
            samplesByNumber = {},
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
            pitchEnvelope = {
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
        instruments[i] = inst
        --print(instPP[i])
        file.seek("set", instPP[i])
        assert(file.read(4) == "IMPI", "Invalid file")
        file.read(13) -- filename, null
        file.read(3) -- NNA, DCT, DNA
        inst.fadeOut = fromLE(file.read(2)) * 128
        file.read(2) -- PPS, PPC
        inst.volume = file.read() / 64
        file.read() -- DfP
        file.read(6) -- padding
        inst.name = file.read(26):gsub("[ %z]+$", "")
        file.read(6) -- padding
        for j = 0, 119 do
            file.read() -- ignored
            local n = file.read()
            inst.samples[j] = samples[n]
            if inst.samples[j] then inst.vibrato = inst.samples[j].vibrato end
        end

        do
            local type = file.read()
            inst.volumeEnvelope.loopType = bit32.band(type, 1) + (bit32.btest(type, 4) and 2 or 0) + (bit32.btest(type, 2) and 4 or 0)
            local npoints = file.read()
            inst.volumeEnvelope.loopStart = file.read() + 1
            inst.volumeEnvelope.loopEnd = file.read() + 1
            inst.volumeEnvelope.sustain = file.read() + 1
            file.read() -- sustain end
            for j = 1, npoints do
                inst.volumeEnvelope.points[j] = {y = file.read(), x = fromLE(file.read(2))}
            end
            file.read((25 - npoints) * 3 + 1)
        end

        do
            local type = file.read()
            inst.panningEnvelope.loopType = bit32.band(type, 1) + (bit32.btest(type, 4) and 2 or 0) + (bit32.btest(type, 2) and 4 or 0)
            local npoints = file.read()
            inst.panningEnvelope.loopStart = file.read() + 1
            inst.panningEnvelope.loopEnd = file.read() + 1
            inst.panningEnvelope.sustain = file.read() + 1
            file.read() -- sustain end
            for j = 1, npoints do
                inst.panningEnvelope.points[j] = {y = ("b"):unpack(file.read(1)) + 32, x = fromLE(file.read(2))}
            end
            file.read((25 - npoints) * 3 + 1)
        end

        do
            local type = file.read()
            inst.pitchEnvelope.loopType = bit32.band(type, 1) + (bit32.btest(type, 4) and 2 or 0) + (bit32.btest(type, 2) and 4 or 0)
            local npoints = file.read()
            inst.pitchEnvelope.loopStart = file.read() + 1
            inst.pitchEnvelope.loopEnd = file.read() + 1
            inst.pitchEnvelope.sustain = file.read() + 1
            file.read() -- sustain end
            for j = 1, npoints do
                inst.pitchEnvelope.points[j] = {y = file.read(), x = fromLE(file.read(2))}
            end
            file.read((25 - npoints) * 3 + 1)
        end
    end

    for i = 1, patternCount do
        file.seek("set", patPP[i] + 2) -- skip size
        patterns[i] = {}
        local rows = fromLE(file.read(2))
        file.read(4)
        local lastfollow, lastnote, lastinst, lastvol, lasteff = {}, {}, {}, {}, {}
        local g = {}
        for x = 1, channelCount do g[x] = {x = 0} end
        for y = 1, rows do
            patterns[i][y] = {}
            while true do
                local x = file.read()
                if x == 0 then break end
                local follow = bit32.btest(x, 0x80) and file.read() or lastfollow[bit32.band(x, 0x3F)]
                x = bit32.band(x, 0x3F)
                if follow ~= 0 then
                    patterns[i][y][x] = {}
                    if bit32.btest(follow, 0x01) then
                        lastnote[x] = file.read()
                        if lastnote[x] < 254 then lastnote[x] = lastnote[x] - 11 end
                        patterns[i][y][x].note = lastnote[x]
                    end
                    if bit32.btest(follow, 0x02) then
                        lastinst[x] = file.read()
                        patterns[i][y][x].instrument = lastinst[x]
                    end
                    if bit32.btest(follow, 0x04) then
                        local v = file.read()
                        if v <= 0x40 then v = v + 0x10
                        elseif v >= 0x80 and v < 0xC0 then v = 0xC0 + bit32.rshift(v - 0x80, 2)
                        elseif v >= 65 and v <= 74 then v = 0x80 + (v - 65)
                        elseif v >= 75 and v <= 84 then v = 0x90 + (v - 75)
                        elseif v >= 85 and v <= 94 then v = 0x60 + (v - 85)
                        elseif v >= 95 and v <= 104 then v = 0x70 + (v - 95)
                        elseif v >= 105 and v <= 114 then v = 0xD0 + (v - 105)
                        elseif v >= 115 and v <= 124 then v = 0xE0 + (v - 115)
                        elseif v >= 193 and v <= 203 then v = 0xF0 + (v - 193)
                        elseif v >= 203 and v <= 213 then v = 0xB0 + (v - 213) end
                        lastvol[x] = v
                        patterns[i][y][x].volume = lastvol[x]
                    end
                    if bit32.btest(follow, 0x08) then
                        lasteff[x] = {file.read(), file.read()}
                        patterns[i][y][x].effect, patterns[i][y][x].effect_param = itEffects[lasteff[x][1]](lasteff[x][2], g)
                    end
                    if bit32.btest(follow, 0x10) then
                        patterns[i][y][x].note = lastnote[x]
                    end
                    if bit32.btest(follow, 0x20) then
                        patterns[i][y][x].instrument = lastinst[x]
                    end
                    if bit32.btest(follow, 0x40) then
                        patterns[i][y][x].volume = lastvol[x]
                    end
                    if bit32.btest(follow, 0x80) then
                        patterns[i][y][x].effect, patterns[i][y][x].effect_param = itEffects[lasteff[x][1]](lasteff[x][2], g)
                    end
                end
                lastfollow[x] = follow
            end
        end
    end
    local state = {
        tempo = tempo,
        bpm = bpm,
        channels = {},
        module = {
            instruments = instruments,
            patterns = patterns,
            order = order,
            name = name,
            tracker = tracker,
            amigaSlides = amigaSlides,
            restartPosition = restartPosition
        },
        speakers = {},
        order = 1,
        row = 1,
        globalVolume = globalVolume,
        mutedChannels = mutedChannels,
        mixVolume = mixVolume,
        loop = true,
        sound = makeSound()
    }
    for i = 1, channelCount do
        state.channels[i] = {
            num = i,
            effectMemory = {},
            playing = {note = 0, instrument = 0, volume = 0, effect = 0, effect_param = 0},
            volume = 64,
            volumeEnvelope = {volume = 64, pos = 0, x = 0},
            vibrato = {type = 0, pos = 0}
        }
    end
    return state
end

---@param state tracc
---@param e boolean
---@param ls number[]
---@param rs number[]|nil
---@param vu table
local function processTick(state, e, ls, rs, vu)
    for _,c in ipairs(state.channels) do
        --if not c.playing or c.playing.effect ~= 2 then effects[2](state, c, 0x02) end
        if e and c.playing and c.playing.effect then effects[c.playing.effect](state, c, c.playing.effect_param or 0) end
        if e and c.playing and c.playing.volume and c.playing.volume > 0x50 then volume_effects[math.floor(c.playing.volume / 16)](state, c, c.playing.volume % 16) end
        if c.instrument and c.instrument.volumeEnvelope.loopType % 2 == 1 and c.volumeEnvelope.pos > 0 and not c.volumeEnvelope.sustain and not c.didSetInstrument and c.note then
            c.volumeEnvelope.x = c.volumeEnvelope.x + 1
            c.volumeEnvelope.volume = c.volumeEnvelope.volume + c.volumeEnvelope.rate
            if c.volumeEnvelope.x == c.instrument.volumeEnvelope.points[c.volumeEnvelope.pos+1].x then
                c.volumeEnvelope.pos = c.volumeEnvelope.pos + 1
                if bit32.btest(c.instrument.volumeEnvelope.loopType, 4) and c.volumeEnvelope.pos == c.instrument.volumeEnvelope.loopEnd then
                    c.volumeEnvelope.pos = c.instrument.volumeEnvelope.loopStart
                    c.volumeEnvelope.x = c.instrument.volumeEnvelope.points[c.volumeEnvelope.pos].x
                end
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
                if bit32.btest(c.instrument.panningEnvelope.loopType, 4) and c.panningEnvelope.pos == c.instrument.panningEnvelope.loopEnd then
                    c.panningEnvelope.pos = c.instrument.panningEnvelope.loopStart
                    c.panningEnvelope.x = c.instrument.panningEnvelope.points[c.panningEnvelope.pos].x
                end
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
    local lss, rss, vuu = state.sound.generate(state, (2.5 / state.bpm) * 48000, #state.channels, rs)
    local sl, sr = #ls, rs and #rs
    for i = 1, #lss do ls[sl+i] = lss[i] end
    if rs then for i = 1, #rss do rs[sr+i] = rss[i] end end
    if vu[1] then for i = 1, #vuu do vu[i][1], vu[i][2] = vu[i][1] + vuu[i][1], vu[i][2] + vuu[i][2] end
    else for i = 1, #vuu do vu[i] = vuu[i] end end
    vu.count = (vu.count or 0) + 1
end

--- Processes a single tick in a state, placing the generated samples in a table.
---@param state tracc The state to tick
---@param stereo boolean Whether to generate stereo sound
---@param left number[]|nil Previous samples to append to on the left/mono channel, if requested
---@param right number[]|nil Previous samples to append to on the right channel, if requested
---@param vu number[][]|nil Previous VU sample info, if requested
---@return number[]|nil left Left/mono channel samples to play
---@return number[]|nil right Right channel samples to play, if stereo is true
---@return number[][]|nil vu VU information
function libtracc.tick(state, stereo, left, right, vu)
    left = left or {}
    right = right or (stereo and {} or nil)
    vu = vu or {}
    if state.tick then
        if state.tick < state.tempo then
            state.tick = state.tick + 1
            processTick(state, true, left, right, vu)
            return left, right, vu
        end
        if state.order ~= state.currentOrder then
            if not state.usedD then state.row = 1 end
            state.currentOrder = state.order
        elseif state.row == state.currentRow then
            state.row = state.row + 1
        end
    end
    local v = state.module.order[state.order]
    if not v then return nil end
    while v >= 254 or state.row > #state.module.patterns[v+1] do
        if state.order == state.currentOrder then
            state.row = 1
            state.order = state.order + 1
            if state.loop and state.order > #state.module.order then state.order = state.module.restartPosition + 1 end
        end
        state.currentOrder = state.order
        v = state.module.order[state.order]
        if not v then return nil end
    end
    state.tick = 1
    state.currentRow = state.row
    state.usedB, state.usedD = nil, nil
    local row = state.module.patterns[v+1][state.row]
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
    processTick(state, false, left, right, vu)
    return left, right, vu
end

--- Processes a single row in a state, placing the generated samples in a table.
---@param state tracc The state to tick
---@param stereo boolean Whether to generate stereo sound
---@param left number[]|nil Previous samples to append to on the left/mono channel, if requested
---@param right number[]|nil Previous samples to append to on the right channel, if requested
---@param vu number[][]|nil Previous VU sample info, if requested
---@return number[]|nil left Left/mono channel samples to play
---@return number[]|nil right Right channel samples to play, if stereo is true
---@return number[][]|nil vu VU information
function libtracc.row(state, stereo, left, right, vu)
    left = left or {}
    right = right or (stereo and {} or nil)
    vu = vu or {}
    if not state.tick or state.tick >= state.tempo then if not libtracc.tick(state, stereo, left, right, vu) then return nil end end
    while state.tick < state.tempo do if not libtracc.tick(state, stereo, left, right, vu) then return nil end end
    return left, right, vu
end

-- Internal note: this function is the only code that explicitly requires CraftOS!

--- Plays a module state on supplied speakers. This can be put into a coroutine
--- manager like parallel or Taskmaster.
---@overload fun(state: tracc, ...)
---@overload fun(state: tracc, volume: number, ...)
---@param state tracc The state to play
---@param volume number The volume to play at (defaults to 1, 100%/16 blocks)
---@param bufferSize number The minimum number of samples to buffer at once (defaults to 48000) - set to 1 for realtime playback
---@param ... table The speaker(s) to play on - if there are multiple, left/right speakers alternate
function libtracc.play(state, volume, bufferSize, ...)
    local speakers = {...}
    if type(volume) == "table" then table.insert(speakers, 1, volume) volume = nil end
    if type(bufferSize) == "table" then table.insert(speakers, 1, bufferSize) bufferSize = nil end
    local wait = {}
    while true do
        local left, right = {}, {}
        while #left < (bufferSize or 48000) do
            if not libtracc.row(state, #speakers > 1, left, right) then return end
        end
        while next(wait) do
            local _, name = os.pullEvent("speaker_audio_empty")
            wait[name] = nil
        end
        for i = 1, #speakers do
            speakers[i].playAudio(i % 2 == 1 and left or right, volume)
            wait[peripheral.getName(speakers[i])] = true
        end
    end
end

--- Creates a "file handle" over string data, which is useful for loading modules
--- that are not in a file.
---@param data string The data that the file will represent
---@return file file The new file handle
function libtracc.makeFile(data)
    local pos = 1
    local closed = false
    return {
        readLine = function(newline)
            if closed then error("attempt to use a closed file", 2) end
            if pos > #data then return nil end
            local d
            d, pos = data:match("([^\n]*" .. (newline and "\n?)" or ")\n?") .. "()", pos)
            return d
        end,
        readAll = function()
            if closed then error("attempt to use a closed file", 2) end
            if pos > #data then return nil end
            local d = data:sub(pos)
            pos = #d + 1
            return d
        end,
        read = function(n)
            if closed then error("attempt to use a closed file", 2) end
            if n ~= nil and type(n) ~= "number" then error("bad argument #1 (expected number, got " .. type(n) .. ")", 2) end
            if pos > #data then return nil end
            if n then
                local d = data:sub(pos, pos + n - 1)
                pos = pos + n
                return d
            else
                local d = data:byte(pos)
                pos = pos + 1
                return d
            end
        end,
        seek = function(whence, offset)
            if whence ~= nil and type(whence) ~= "string" then error("bad argument #1 (expected string, got " .. type(whence) .. ")", 2) end
            if offset ~= nil and type(offset) ~= "number" then error("bad argument #2 (expected number, got " .. type(offset) .. ")", 2) end
            whence = whence or "cur"
            offset = offset or 0
            if closed then error("attempt to use closed file", 2) end
            if whence == "set" then pos = offset + 1
            elseif whence == "cur" then pos = pos + offset
            elseif whence == "end" then pos = math.max(#data - offset, 1)
            else error("Invalid whence", 2) end
            return pos - 1
        end,
        close = function()
            if closed then error("attempt to use a closed file", 2) end
            closed = true
        end
    }
end

return libtracc
