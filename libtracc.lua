-- libtracc XM/S3M/IT module player library
-- Licensed under the MIT license.
-- Copyright (c) 2021-2025 JackMacWindows.

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
    508,505,502,498,494,491,487,484,480,477,474,470,467,463,460,457,453
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
---@field length number

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
---@field pitchEnvelope tracc.envelope|nil
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
---@field pan number|nil
---@field volumeEnvelope {volume: number, pos: number, x: number, sustain: boolean|nil, rate: number}
---@field panningEnvelope {panning: number, pos: number, x: number, sustain: boolean|nil, rate: number}
---@field pitchEnvelope {pitch: number, pos: number, x: number, sustain: boolean|nil, rate: number}|nil
---@field vibrato {type: number, pos: number}
---@field speaker table|nil
---@field note number|nil
---@field finetune number|nil
---@field frequency number|nil
---@field lastFrequency number|nil
---@field instrument tracc.instrument|nil
---@field didSetInstrument boolean|nil
---@field lastNote number|nil
---@field midiMacro number

---@class tracc
---@field type "xm"|"s3m"|"it"|"mod"
---@field tempo number
---@field bpm number
---@field channels tracc.channel[]
---@field tempChannels tracc.channel[]
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
---@field freqMemo table
---@field midiMacros {parametered: fun(state: tracc, channel: tracc.channel, param: number)[], fixed: fun(state: tracc, channel: tracc.channel)[]}

local log, abs, floor, min, max = math.log, math.abs, math.floor, math.min, math.max

-- Software mixer emulating craftos2-sound (custom waves only for now)
local function makeSound()
    ---@class tracc.sound
    local sound = {channels = {}, version = 2, interpolation = libtracc.interpolation}
    for i = 1, 32 do sound.channels[i] = {frequency = 0, volume = 0, panning = 0} end
    function sound.getFrequency(c) return sound.channels[c].frequency end
    function sound.setFrequency(c, freq) sound.channels[c].frequency = freq end
    function sound.getVolume(c) return sound.channels[c].volume end
    function sound.setVolume(c, vol) sound.channels[c].volume = vol end
    function sound.setWaveType(c, type, tab, loopStart, loopType, keepPos, filter)
        if type == "none" then sound.channels[c].wavetable = nil
        elseif type == "custom" then
            local ch = sound.channels[c]
            if _G.type(tab[1]) == "table" then
                if loopStart >= #tab[1] then loopStart = 0 end
                ch.wavetable, ch.wavetableR, ch.pos, ch.loopStart, ch.loopType, ch.dir, ch.nwavetable = tab[1], tab[2], keepPos and ch.pos or 0, loopStart or 0, loopType or 1, 1, #tab[1]
                ch.filter, ch.a1l, ch.a2l, ch.a1r, ch.a2r, ch.b1l, ch.b2l, ch.b1r, ch.b2r = filter, 0, 0, 0, 0, 0, 0, 0, 0
            else
                if loopStart >= #tab then loopStart = 0 end
                ch.wavetable, ch.wavetableR, ch.pos, ch.loopStart, ch.loopType, ch.dir, ch.nwavetable = tab, nil, keepPos and ch.pos or 0, loopStart or 0, loopType or 1, 1, #tab
                ch.filter, ch.a1l, ch.a2l, ch.a1r, ch.a2r, ch.b1l, ch.b2l, ch.b1r, ch.b2r = filter, 0, 0, 0, 0, 0, 0, 0, 0
            end
            ch.fadeSamplesInit, ch.fadeSamples, ch.fadeSamplesMax, ch.fadeDirection = nil
        else error("Invalid wave type", 2) end
    end
    function sound.setPan(c, p) sound.channels[c].pan = p end
    function sound.fadeOut(c, time)
        local info = sound.channels[c] or c
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
    function sound.tempClone(c, callback)
        if not sound.channels[c] or sound.channels[c].frequency == 0 or not sound.channels[c].wavetable then return nil end
        local newc = {temp = true, callback = callback}
        for k, v in pairs(sound.channels[c]) do newc[k] = v end
        return newc
    end
    function sound.setPosition(c, p) sound.channels[c].pos = (p / #sound.channels[c].wavetable) % 1 end
    function sound.setInterpolation(c, i) sound.channels[c].interpolation = i end
    local function tovu(n) return log(1+9*abs(n), 10) end
    function sound.generate(state, length, cc, stereo)
        cc = cc or 32
        local retval, right, vu = {}, {}, {}
        local channels, interpolation, globalVolume, mixVolume = sound.channels, sound.interpolation, state.globalVolume / 64, state.mixVolume
        local vuVolume = globalVolume * mixVolume
        local nTempChannels = table.maxn(state.tempChannels)
        for j = 1, length do
            local sample, rs = 0, 0
            local num = 0
            for i = 1, cc + nTempChannels do
                local c = i > cc and (state.tempChannels[i-cc] and state.tempChannels[i-cc].sound) or channels[i] or {}
                local interp = c.interpolation or interpolation
                local wavetable, wavetableR, nwavetable, filter = c.wavetable, c.wavetableR, c.nwavetable, c.filter
                if wavetable and c.volume > 0 and c.frequency > 0 then
                    local p = c.pos * nwavetable
                    local fp = floor(p) + 1
                    local s, sR
                    if interp == "none" then
                        s = wavetable[fp] * c.volume
                        if wavetableR and stereo then sR = wavetableR[fp] * c.volume
                        else sR = s end
                    elseif interp == "linear" then
                        local a, b = wavetable[fp], wavetable[fp % nwavetable + 1]
                        s = (a + (b - a) * (p - (fp - 1))) * c.volume
                        if wavetableR and stereo then
                            a, b = wavetableR[fp], wavetableR[fp % nwavetable + 1]
                            sR = (a + (b - a) * (p - (fp - 1))) * c.volume
                        else sR = s end
                    end
                    if filter then
                        s = s * filter[1] - c.a1l * filter[4] - c.a2l * filter[5]
                        sR = sR * filter[1] - c.a1r * filter[4] - c.a2r * filter[5]
                        c.a1l, c.a2l, c.a1r, c.a2r = s, c.a1l, sR, c.a1r
                    end
                    if stereo then
                        local l, r = min(c.pan+1, 1), min(1-c.pan, 1)
                        sample, rs = sample + s * l * mixVolume, rs + sR * r * mixVolume
                        if i <= cc then
                            local vc = vu[i]
                            if vc then vc[1], vc[2] = vc[1] + tovu(vuVolume * s * l), vc[2] + tovu(vuVolume * sR * r)
                            else vu[i] = {tovu(vuVolume * s * l), tovu(vuVolume * sR * r)} end
                        end
                    else
                        sample = sample + s * mixVolume
                        if i <= cc then
                            local v = tovu(vuVolume * s)
                            local vc = vu[i]
                            if vc then vc[1], vc[2] = vc[1] + v, vc[2] + v
                            else vu[i] = {v, v} end
                        end
                    end
                    c.pos = c.pos + c.frequency / 48000 * c.dir
                    local lstart = c.loopStart / nwavetable
                    if c.dir == -1 and c.pos < lstart then
                        c.dir = 1
                        while c.pos < lstart do c.pos = c.pos + c.frequency / 48000 end
                    end
                    while c.pos >= 1 do
                        if c.loopType == 0 then
                            c.wavetable, c.wavetableR, c.volume = nil, nil, 0
                            if c.temp then c.callback(i) end
                            break
                        elseif c.loopType == 1 then c.pos = c.pos - 1 + lstart
                        else c.pos, c.dir = c.pos - c.frequency / 48000, -1 end
                    end
                    if ((c.fadeSamplesMax or 0) > 0) then
                        c.volume = c.volume + (c.fadeSamplesInit / c.fadeSamplesMax * c.fadeDirection)
                        c.fadeSamples = c.fadeSamples - 1
                        if (c.fadeSamples <= 0) then
                            c.fadeSamples, c.fadeSamplesMax = 0, 0
                            c.fadeSamplesInit = 0.0
                            c.volume = c.fadeDirection == 1 and 1 or 0
                            if c.temp then c.callback(i) end
                        end
                    end
                    num = num + 1
                end
            end
            --if num > 0 then sample, rs = sample / (cc or num), rs / (cc or num) end
            retval[j] = max(min(globalVolume * sample / 2, 1), -1) * 127
            right[j] = max(min(globalVolume * rs / 2, 1), -1) * 127
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
---@return number
local function toFreq(state, note, finetune)
    if state.module.amigaSlides then
        local a = ((note % 12)*8 + floor(finetune/16)) % 96
        return 14317456/((amigaTable[a]*(1-(finetune/16 % 1)) + amigaTable[a+1]*((finetune/16 % 1))) * 16 / 2^floor(note / 12 - 1))
    else return 8363*2^((6*12*16*4 - (10*12*16*4 - (note-1)*16*4 - floor(finetune/2))) / (12*16*4)) end
end
do
    local toFreq_impl = toFreq
    ---@param state tracc
    ---@param note number
    ---@param finetune number
    ---@return number
    function toFreq(state, note, finetune)
        local memo = state.freqMemo
        local k = note*256+finetune
        if memo[k] then return memo[k] end
        local v = toFreq_impl(state, note, finetune)
        memo[k] = v
        return v
    end
end
local function modPeriodToNote(period)
    local octave = 3
    while period > amigaTable[0] do octave, period = octave - 1, floor(period / 2 + 0.5) end
    while period < amigaTable[96] do octave, period = octave + 1, period * 2 end
    local idx, sz = 48, 24
    while sz >= 1 do
        if period == amigaTable[idx] then break
        elseif period > amigaTable[idx] then idx = idx - sz
        else idx = idx + sz end
        sz = floor(sz / 2)
    end
    return floor(idx / 8 + 0.5) + octave * 12
end
---@param state tracc
---@param frequency number
---@param slide number
---@return number
local function slideFreq(state, frequency, slide, isPorta)
    if isPorta and state.type == "xm" then slide = slide * 2 end
    --elseif isPorta and state.type == "s3m" then slide = slide / 2 end
    if state.module.amigaSlides then
        local f = state.type == "xm" and 3579364 or 3546895
        return f / max(f / frequency - slide, 1)
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
local function getFrequency(state, channel, sample) return state.sound.getFrequency(channel) * sample.length end
---@param state tracc
---@param channel number
---@param freq number
---@param sample tracc.sample
local function setFrequency(state, channel, freq, sample) state.sound.setFrequency(channel, freq / sample.length) end

---@param state tracc
---@param channel tracc.channel
---@param vol number
local function setVolume(state, channel, vol)
    channel.volume = vol
    if not channel.speaker then
        if state.mutedChannels[channel.num] then if channel.sound then channel.sound.volume = 0 else state.sound.setVolume(channel.num, 0) end
        else
            local n = vol / 64 * (channel.volumeEnvelope.volume / 64) * (channel.instrument and channel.instrument.volume or 1)
            if state.type == "it" then
                local note = channel.note or (channel.playing and channel.playing.note)
                if channel.instrument and note and channel.instrument.samples[note] then n = n * (channel.instrument.samples[note].volume / 64) end
            end
            if channel.sound then channel.sound.volume = n else state.sound.setVolume(channel.num, n) end
        end
    end
end

---@param state tracc
---@param channel tracc.channel
---@param pan number
local function setPan(state, channel, pan)
    channel.pan = pan
    if not channel.speaker then
        state.sound.setPan(channel.num, -max((pan - 127) / 127, -1))
    end
    -- TODO: Add stereo capability to CC speakers
end

---@param envelope tracc.envelope
---@param key string
---@param default number
local function setupEnvelope(envelope, key, default)
    if #envelope.points > 0 --[[and channel.instrument.volumeEnvelope.loopType % 2 == 1]] then
        if #envelope.points == 1 then return {[key] = envelope.points[1].y, pos = 1, x = 0, sustain = true}
        else
            local e = {[key] = envelope.points[1].y, pos = 1, x = 0, rate = (envelope.points[2].y - envelope.points[1].y) / (envelope.points[2].x - envelope.points[1].x), sustain = (bit32.btest(envelope.loopType, 2) and envelope.sustain == 1) or nil}
            while e.pos + 1 <= #envelope.points and envelope.points[e.pos+1].x == envelope.points[e.pos].x do
                e.pos = e.pos + 1
                e.rate = (envelope.points[e.pos+1].y - envelope.points[e.pos].y) / (envelope.points[e.pos+1].x - envelope.points[e.pos].x)
                e[key] = envelope.points[e.pos].y
            end
            return e
        end
    else
        return {[key] = default, pos = 0, x = 0}
    end
end

---@param state tracc
---@param channel tracc.channel
---@param inst number
local function setInstrument(state, channel, inst)
    if not state.module.instruments[inst] then return end
    local nna = channel.instrument and channel.instrument.newNoteAction
    if nna and channel.volume > 0 and channel.playing.note and not (channel.playing.note == 97 or channel.playing.note >= 254) and channel.playing.effect ~= 3 and not (channel.playing.volume and channel.playing.volume >= 0xF0 and channel.playing.volume <= 0xFF) and channel.instrument then
        local dct = channel.instrument.duplicateCheckType
        if (dct == 1 and channel.playing.note == channel.note) or (dct == 2 and channel.instrument.samples[channel.playing.note or channel.note] == state.module.instruments[inst].samples[channel.note]) or (dct == 3 and state.module.instruments[inst] == channel.instrument) then
            nna = channel.instrument.duplicateNoteAction
        end
        if nna == 1 then
            local id = #state.tempChannels+1
            local tempc = state.sound.tempClone(channel.num, function() state.tempChannels[id] = nil end)
            if tempc then
                local newchannel = {temp = true, sound = tempc}
                state.tempChannels[id] = newchannel
                for k, v in pairs(channel) do
                    if k == "volumeEnvelope" or k == "panningEnvelope" or k == "vibrato" then
                        local t = {}
                        newchannel[k] = t
                        for kk, vv in pairs(v) do t[kk] = vv end
                    else newchannel[k] = v end
                end
                newchannel.num = #state.channels + id
                newchannel.playing = nil
            end
        elseif nna == 2 then
            local id = #state.tempChannels+1
            local tempc = state.sound.tempClone(channel.num, function() state.tempChannels[id] = nil end)
            if tempc then
                local newchannel = {temp = true, sound = tempc}
                state.tempChannels[id] = newchannel
                for k, v in pairs(channel) do
                    if k == "volumeEnvelope" or k == "panningEnvelope" or k == "vibrato" then
                        local t = {}
                        newchannel[k] = t
                        for kk, vv in pairs(v) do t[kk] = vv end
                    else newchannel[k] = v end
                end
                newchannel.num = #state.channels + id
                newchannel.playing = nil
                local channel = newchannel ---@diagnostic disable-line:redefined-local
                if not channel.speaker and channel.instrument then
                    if channel.instrument.volumeEnvelope.loopType % 2 == 0 then
                        state.sound.fadeOut(channel.sound, (32768 / channel.instrument.fadeOut) * (2.5 / state.bpm))
                    elseif channel.volumeEnvelope.pos >= #channel.instrument.volumeEnvelope.points then
                        if #channel.instrument.volumeEnvelope.points > 1 and not (channel.playing and channel.playing.effect == 0xE and channel.playing.effect_param and bit32.band(channel.playing.effect_param, 0xF0) == 0xD0) and channel.instrument.fadeOut > 0 then
                            state.sound.fadeOut(channel.sound, (32768 / channel.instrument.fadeOut) * (2.5 / state.bpm))
                        else state.tempChannels[id] = nil end
                    --elseif #channel.instrument.volumeEnvelope.points - 1 == channel.instrument.volumeEnvelope.sustain and channel.volumeEnvelope.sustain then
                    --    state.sound.fadeOut(channel.sound, (channel.instrument.volumeEnvelope.points[#channel.instrument.volumeEnvelope.points].x - channel.instrument.volumeEnvelope.points[#channel.instrument.volumeEnvelope.points-1].x) * (2.5 / state.bpm))
                    else channel.volumeEnvelope.sustain = false end
                end
            end
        --elseif nna == 3 then
        end
    end
    channel.instrument = state.module.instruments[inst]
    if not (state.type == "it" and (channel.playing.effect == 3 or (channel.playing.volume and channel.playing.volume >= 0xF0 and channel.playing.volume <= 0xFF))) then
        channel.volumeEnvelope = setupEnvelope(channel.instrument.volumeEnvelope, "volume", 64)
        channel.panningEnvelope = setupEnvelope(channel.instrument.panningEnvelope, "panning", 32)
        if channel.instrument.pitchEnvelope then channel.pitchEnvelope = setupEnvelope(channel.instrument.pitchEnvelope, "pitch", 32) end
        if channel.instrument.vibrato.sweep > 0 then channel.instrument.vibrato.sweep_mult = 0
        else channel.instrument.vibrato.sweep_mult = 1 end
    end
end

---@param state tracc
---@param channel tracc.channel
---@param note number
---@param keepPos? boolean
local function setNote(state, channel, note, keepPos)
    channel.speaker = nil
    if note == 97 or note >= 254 then
        if not channel.speaker then
            if channel.instrument and note ~= 254 then
                if channel.instrument.volumeEnvelope.loopType % 2 == 0 then
                    state.sound.fadeOut(channel.num, (32768 / channel.instrument.fadeOut) * (2.5 / state.bpm))
                elseif channel.volumeEnvelope.pos >= #channel.instrument.volumeEnvelope.points then
                    if #channel.instrument.volumeEnvelope.points > 1 and not (channel.playing and channel.playing.effect == 0xE and channel.playing.effect_param and bit32.band(channel.playing.effect_param, 0xF0) == 0xD0) and channel.instrument.fadeOut > 0 then
                        state.sound.fadeOut(channel.num, (32768 / channel.instrument.fadeOut) * (2.5 / state.bpm))
                    else state.sound.setVolume(channel.num, 0) state.sound.setFrequency(channel.num, 0) channel.frequency = 0 end
                --elseif #channel.instrument.volumeEnvelope.points - 1 == channel.instrument.volumeEnvelope.sustain and channel.volumeEnvelope.sustain then
                --    state.sound.fadeOut(channel.num, (channel.instrument.volumeEnvelope.points[#channel.instrument.volumeEnvelope.points].x - channel.instrument.volumeEnvelope.points[#channel.instrument.volumeEnvelope.points-1].x) * (2.5 / state.bpm))
                else channel.volumeEnvelope.sustain = false end
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
            channel.frequency = toFreq(state, note+sample.note, channel.finetune)
            state.sound.setWaveType(channel.num, "custom", sample.wavetable, sample.loopStart, bit32.band(sample.type, 3), keepPos, channel.instrument.filter)
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
    function(v) return max(v - 1, 0) end,
    function(v) return max(v - 2, 0) end,
    function(v) return max(v - 4, 0) end,
    function(v) return max(v - 8, 0) end,
    function(v) return max(v - 16, 0) end,
    function(v) return max(v * (2/3), 0) end,
    function(v) return max(v / 2, 0) end,
    function(v) return v end,
    function(v) return min(v + 1, 0) end,
    function(v) return min(v + 2, 0) end,
    function(v) return min(v + 4, 0) end,
    function(v) return min(v + 8, 0) end,
    function(v) return min(v + 16, 0) end,
    function(v) return min(v / (2/3), 0) end,
    function(v) return min(v * 2, 0) end,
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
            local sample = channel.instrument.samples[channel.note]
            setFrequency(state, channel.num, slideFreq(state, getFrequency(state, channel.num, sample), param), sample)
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
            local sample = channel.instrument.samples[channel.note]
            setFrequency(state, channel.num, slideFreq(state, getFrequency(state, channel.num, sample), -param), sample)
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
                local sample = channel.instrument.samples[channel.note]
                channel.frequency = toFreq(state, channel.playing.note+sample.note, channel.finetune)
                setFrequency(state, channel.num, channel.frequency, sample)
            end
        end
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- 6
        if state.tick == 1 then
            if param == 0 then channel.effectMemory[0xE6] = state.row
            else
                if not state.usedE6 or state.usedE6 > 0 then
                    state.row = channel.effectMemory[0xE6] or state.row
                    state.usedE6 = (state.usedE6 or param) - 1
                else state.usedE6 = nil end
            end
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
        if state.tick == 1 then setVolume(state, channel, min(channel.volume + floor(param), 64)) end
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- B
        if param == 0 then param = channel.effectMemory[0xEB] or 0
        else channel.effectMemory[0xEB] = param end
        if state.tick == 1 then setVolume(state, channel, max(channel.volume - param, 0)) end
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
        channel.midiMacro = param
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
            local sample = channel.instrument.samples[channel.note]
            setFrequency(state, channel.num, slideFreq(state, getFrequency(state, channel.num, sample), param / 16), sample)
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
            local sample = channel.instrument.samples[channel.note]
            setFrequency(state, channel.num, slideFreq(state, getFrequency(state, channel.num, sample), param / -16), sample)
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
            local sample = channel.instrument.samples[channel.note]
            setFrequency(state, channel.num, slideFreq(state, getFrequency(state, channel.num, sample), param), sample)
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
            local sample = channel.instrument.samples[channel.note]
            setFrequency(state, channel.num, max(slideFreq(state, getFrequency(state, channel.num, sample), -param), 0), sample)
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
                        channel.frequency = channel.lastFrequency or toFreq(state, note+sample.note, channel.finetune)
                        setFrequency(state, channel.num, channel.frequency, sample)
                        if channel.playing and channel.playing.note then channel.lastNote = channel.playing.note end
                    end
                    return 0
                elseif slideFreq(state, channel.frequency, param, true) < toFreq(state, note+sample.note, sample.finetune) then
                    channel.frequency = slideFreq(state, channel.frequency, param, true)
                    setFrequency(state, channel.num, slideFreq(state, getFrequency(state, channel.num, sample), param, true), sample)
                elseif slideFreq(state, channel.frequency, -param, true) > toFreq(state, note+sample.note, sample.finetune) then
                    channel.frequency = slideFreq(state, channel.frequency, -param, true)
                    setFrequency(state, channel.num, slideFreq(state, getFrequency(state, channel.num, sample), -param, true), sample)
                elseif channel.frequency ~= toFreq(state, note+sample.note, sample.finetune) then
                    channel.frequency = toFreq(state, note+sample.note, sample.finetune)
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
        if state.tick == 1 and not state.mutedChannels[channel.num] and channel.playing and channel.playing.note then
            local pos = param * 256
            local ch = state.sound.channels[channel.num]
            while pos > ch.nwavetable do
                pos = ch.loopStart + (ch.nwavetable - pos)
            end
            state.sound.setPosition(channel.num, pos)
        end
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- A
        if param == 0 then param = channel.effectMemory[0xA] or 0
        else channel.effectMemory[0xA] = param end
        if state.tick > 1 then
            if param < 16 then setVolume(state, channel, max(channel.volume - param, 0))
            else setVolume(state, channel, min(channel.volume + floor(param / 16), 64)) end
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
        state.globalVolume = min(max(param, 0), 64)
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- H
        if param == 0 then param = channel.effectMemory[0x11] or 0
        else channel.effectMemory[0x11] = param end
        if state.tick > 1 then
            if param < 16 then state.globalVolume = max(state.globalVolume - param, 0)
            else state.globalVolume = min(state.globalVolume + floor(param / 16), 64) end
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
            if channel.volumeEnvelope.pos + 1 > #channel.instrument.volumeEnvelope.points or (bit32.btest(channel.instrument.volumeEnvelope.loopType, 2) and channel.volumeEnvelope.pos == channel.instrument.volumeEnvelope.sustain) and channel.volumeEnvelope.sustain == nil then
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
            if param < 16 then setPan(state, channel, max(channel.pan - param, 0))
            else setPan(state, channel, min(channel.pan + floor(param / 16), 128)) end
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
        if floor(param / 16) == 0 then param = param + (channel.effectMemory[0x1B0] or 0x80)
        else channel.effectMemory[0x1B0] = bit32.band(param, 0xF0) end
        if state.tick > 1 and (state.tick - 1) % (param % 16) == 0 then
            setVolume(state, channel, retrigVolume[floor(param / 16)](channel.volume))
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
        if param >= 0x80 then if state.midiMacros.fixed[param - 0x80] then state.midiMacros.fixed[param - 0x80](state, channel) end
        elseif state.midiMacros.parametered[channel.midiMacro] then state.midiMacros.parametered[channel.midiMacro](state, channel, param) end
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- \
        -- unimplemented
    end
}

local itGVolMap = {[0] = 0x00, 0x01, 0x04, 0x08, 0x10, 0x20, 0x40, 0x60, 0x80, 0xFF}

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
        channel.effectMemory[4] = bit32.band(channel.effectMemory[4] or 0, 0x0F) + param * 16
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- h
        return effects[4](state, channel, param + bit32.band(channel.effectMemory[4] or 0, 0xF0))
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
    function(state, channel, param) -- l / e
        if state.type == "it" then return effects[2](state, channel, param * 16) end
        return effects[0x19](state, channel, param)
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- r / f
        if state.type == "it" then return effects[1](state, channel, param * 16) end
        return effects[0x19](state, channel, param * 16)
    end,
    ---@param state tracc
    ---@param channel tracc.channel
    ---@param param number
    function(state, channel, param) -- g
        if state.type == "it" then return effects[3](state, channel, itGVolMap[param]) end
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
        local pat = {}
        patterns[i] = pat
        preHeaderPos = file.seek()
        local patternHeaderSize = fromLE(file.read(4))
        file.read()
        local rows = fromLE(file.read(2))
        local size = fromLE(file.read(2))
        if patternHeaderSize > 9 then file.seek("set", preHeaderPos + patternHeaderSize) end
        local prePatternPos = file.seek()
        for y = 1, rows do
            local row = {}
            pat[y] = row
            for x = 1, channelCount do
                local follow = file.read()
                local cmd = {}
                if bit32.btest(follow, 0x80) then
                    if follow ~= 0x80 then
                        row[x] = cmd
                        if bit32.btest(follow, 0x01) then
                            cmd.note = file.read()
                        end
                        if bit32.btest(follow, 0x02) then
                            cmd.instrument = file.read()
                        end
                        if bit32.btest(follow, 0x04) then
                            cmd.volume = file.read()
                        end
                        if bit32.btest(follow, 0x08) then
                            cmd.effect = file.read()
                        end
                        if bit32.btest(follow, 0x10) then
                            if not cmd.effect then cmd.effect = 0 end
                            cmd.effect_param = file.read()
                        end
                    end
                else
                    row[x] = cmd
                    cmd.note = follow
                    cmd.instrument = file.read()
                    cmd.volume = file.read()
                    cmd.effect = file.read()
                    cmd.effect_param = file.read()
                end
            end
        end
        file.seek("set", prePatternPos + size)
    end

    for i = 1, instrumentCount do
        --print(i, ("%X"):format(file.seek()))
        local inst = {}
        local instsize = fromLE(file.read(4))
        inst.name = file.read(22):gsub("[ %z]+$", "")
        file.read()
        local sampleCount = fromLE(file.read(2))
        --print(sampleCount)
        if sampleCount > 0 then
            instruments[i] = inst
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
                sample.pan = file.read() --max((file.read() - 128) / 127, -1)
                sample.note = file.read()
                if sample.note > 0x7F then sample.note = sample.note - 256 end
                file.read() -- reserved
                sample.name = file.read(22):gsub("[ %z]+$", "")
                file.seek("cur", samplesize - 40)
            end
            for j = 1, sampleCount do
                local sample = inst.samplesByNumber[j]
                local size = sample.size
                local wavetable = {}
                sample.wavetable = wavetable
                for c = 1, bit32.btest(sample.type, 0x20) and 2 or 1 do
                    if bit32.btest(sample.type, 0x10) then
                        local last = 0
                        for k = 1, size / 2 do
                            local d = fromLE(file.read(2))
                            if d > 0x7FFF then d = d - 0x10000 end
                            wavetable[k], last = max(min((last + d) / ((last + d) > 0 and 0x7FFF or 0x8000), 1), -1), last + d
                            while last > 0x7FFF do last = last - 0x10000 end
                            while last < -0x8000 do last = last + 0x10000 end
                        end
                    else
                        local last = 0
                        for k = 1, size do
                            local d = file.read()
                            if d > 0x7F then d = d - 256 end
                            wavetable[k], last = max(min((last + d) / ((last + d) > 0 and 127 or 128), 1), -1), last + d
                            while last > 127 do last = last - 256 end
                            while last < -128 do last = last + 256 end
                        end
                    end
                end
                sample.length = #wavetable
            end
        else file.seek("cur", instsize - 29) end
    end
    local state = { ---@type tracc
        type = "xm",
        tempo = tempo,
        bpm = bpm,
        channels = {},
        tempChannels = {},
        module = {
            instruments = instruments,
            patterns = patterns,
            order = order,
            name = name,
            tracker = tracker,
            amigaSlides = amigaSlides,
            restartPosition = restartPosition
        },
        midiMacros = {parametered = {}, fixed = {}},
        speakers = {},
        order = 1,
        row = 1,
        globalVolume = globalVolume,
        mutedChannels = {},
        mixVolume = 1,
        loop = true,
        freqMemo = {},
        currentOrder = 1,
        currentRow = 1,
        sound = makeSound()
    }
    for i = 1, channelCount do
        state.channels[i] = {
            num = i,
            effectMemory = {},
            midiMacro = 0,
            playing = {note = 0, instrument = 0, volume = 0, effect = 0, effect_param = 0},
            volume = 64,
            volumeEnvelope = {volume = 64, pos = 0, x = 0},
            vibrato = {type = 0, pos = 0},
            panningEnvelope = {panning = 128, pos = 0, x = 0}
        }
    end
    return state
end

--- Creates a new tracc state from a MOD file handle.
---@param file file The file to read
---@return tracc state The new tracc state
function libtracc.readMODFile(file)
    local patterns, order, instruments = {}, {}, {}
    local name = file.read(20):gsub("[ %z]+$", "")

    for i = 1, 31 do
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
        --print(instPP[i])
        inst.name = file.read(22):gsub("[ %z]+$", "")
        sample.name = inst.name
        sample.size = (file.read() * 512 + file.read() * 2)
        sample.length = sample.size
        if sample.size > 2 then instruments[i] = inst end
        local finetune = bit32.band(file.read(), 0xF)
        sample.finetune = (finetune > 7 and finetune - 16 or finetune) * 16
        sample.volume = file.read()
        sample.loopStart = file.read() * 512 + file.read() * 2
        sample.loopLength = file.read() * 512 + file.read() * 2
        sample.type = sample.loopLength > 2 and 1 or 0
        sample.note = 0
    end

    local numOrders = file.read()
    local patternCount = 0
    file.read()
    for i = 1, numOrders do
        order[i] = file.read()
        patternCount = max(patternCount, order[i])
    end
    file.read(128 - numOrders)
    local sig = file.read(4)
    local channelCount = 4
    if sig == "FLT8" or sig == "8CHN" then channelCount = 8
    elseif sig == "6CHN" then channelCount = 6 end

    for i = 1, patternCount + 1 do
        patterns[i] = {}
        for y = 1, 64 do
            patterns[i][y] = {}
            for x = 1, channelCount do
                local num = (">I4"):unpack(file.read(4))
                patterns[i][y][x] = {
                    note = bit32.btest(num, 0x0FFF0000) and modPeriodToNote(bit32.extract(num, 16, 12)) or nil,
                    instrument = bit32.btest(num, 0xF000F000) and bit32.extract(num, 28, 4) * 16 + bit32.extract(num, 12, 4) or nil,
                    effect = bit32.btest(num, 0x00000FFF) and bit32.extract(num, 8, 4) or nil,
                    effect_param = bit32.btest(num, 0x00000FFF) and bit32.extract(num, 0, 8) or nil
                }
            end
        end
    end

    for i = 1, 31 do
        --print(instruments[i].samples[1].size, ("%x"):format(file.seek()))
        if instruments[i] then
            for j = 1, instruments[i].samples[1].size do
                local sample = file.read()
                instruments[i].samples[1].wavetable[j] = (sample > 127 and sample - 256 or sample) / (sample > 127 and 128 or 127)
            end
        end
    end

    local state = { ---@type tracc
        type = "mod",
        tempo = 6,
        bpm = 125,
        channels = {},
        tempChannels = {},
        module = {
            instruments = instruments,
            patterns = patterns,
            order = order,
            name = name,
            tracker = "ProTracker",
            amigaSlides = true,
            restartPosition = 1
        },
        midiMacros = {parametered = {}, fixed = {}},
        speakers = {},
        order = 1,
        row = 1,
        globalVolume = 64,
        mutedChannels = {},
        mixVolume = 1,
        loop = true,
        currentOrder = 1,
        currentRow = 1,
        freqMemo = {},
        sound = makeSound()
    }
    for i = 1, channelCount do
        state.channels[i] = {
            num = i,
            effectMemory = {},
            midiMacro = 0,
            playing = {note = 0, instrument = 0, volume = 0, effect = 0, effect_param = 0},
            volume = 64,
            pan = (i == 1 or i == 4 or i == 5 or i == 8) and 0 or 255,
            volumeEnvelope = {volume = 64, pos = 0, x = 0},
            vibrato = {type = 0, pos = 0},
            panningEnvelope = {panning = 128, pos = 0, x = 0}
        }
        setPan(state, state.channels[i], state.channels[i].pan)
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
    function(p) return 0x08, min(p * 2, 255) end, -- X
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
    globalVolume = file.read() / 256
    tempo = file.read()
    bpm = file.read()
    restartPosition = 0
    amigaSlides = true
    local isStereo = bit32.btest(file.read(), 0x80) -- master volume
    file.read() -- ultra click
    local hasChannelPan = file.read() == 252
    file.read(10)
    local channelPan = {}
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
            channelPan[i] = isStereo and (bit32.btest(s, 0x08) and 0xCC or 0x33) or 0x77
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
    if hasChannelPan then
        for i = 1, channelCount do
            local p = file.read()
            if bit32.btest(p, 0x20) then channelPan[i] = bit32.band(p, 0x0F) * 16 + bit32.band(p, 0x0F) end
        end
    end

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
        local note = 12 * log(c2speed / 8363, 2)
        sample.note = floor(note)
        sample.finetune = floor((note - sample.note) * 127)
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
        sample.length = #sample.wavetable
        if bit32.btest(sflags, 0x02) then file.seek("cur", sample.size * bit32.btest(sflags, 0x04) / 2) end
    end

    for i = 1, patternCount do
        local pattern = {}
        patterns[i] = pattern
        file.seek("set", patPP[i] + 2) -- skip size
        local g = {}
        for x = 1, 32 do g[x] = {x = 0} end
        for y = 1, 64 do
            local row = {}
            pattern[y] = row
            repeat
                local b = file.read()
                if b ~= 0 then
                    local x = bit32.band(b, 0x1F) + 1
                    row[x] = {}
                    if bit32.btest(b, 0x20) then
                        local n = file.read()
                        if n == 254 then row[x].note = 254
                        elseif n <= 127 then row[x].note = bit32.rshift(n, 4) * 12 + bit32.band(n, 15) + 1 end
                        n = file.read()
                        if n ~= 0 then row[x].instrument = n end
                    end
                    if bit32.btest(b, 0x40) then
                        local v = file.read()
                        if v ~= 255 then row[x].volume = v + 0x10 end
                    end
                    if bit32.btest(b, 0x80) then
                        local e, p = file.read(), file.read()
                        if e ~= 0 and s3mEffects[e] then
                            local ne, np, nv = s3mEffects[e](p, g[x])
                            row[x].effect, row[x].effect_param = ne, np
                            if nv and not row[x].volume then row[x].volume = nv end
                        end
                    end
                end
            until b == 0
        end
    end
    local state = { ---@type tracc
        type = "s3m",
        tempo = tempo,
        bpm = bpm,
        channels = {},
        tempChannels = {},
        module = {
            instruments = instruments,
            patterns = patterns,
            order = order,
            name = name,
            tracker = tracker,
            amigaSlides = amigaSlides,
            restartPosition = restartPosition
        },
        midiMacros = {parametered = {}, fixed = {}},
        speakers = {},
        order = 1,
        row = 1,
        globalVolume = globalVolume,
        mutedChannels = mutedChannels,
        mixVolume = 1,
        loop = true,
        currentOrder = 1,
        currentRow = 1,
        freqMemo = {},
        sound = makeSound()
    }
    for i = 1, channelCount do
        state.channels[i] = {
            num = i,
            effectMemory = {},
            midiMacro = 0,
            playing = {note = 0, instrument = 0, volume = 0, effect = 0, effect_param = 0},
            volume = 64,
            pan = channelPan[i],
            volumeEnvelope = {volume = 64, pos = 0, x = 0},
            vibrato = {type = 0, pos = 0},
            panningEnvelope = {panning = 128, pos = 0, x = 0}
        }
        if channelPan[i] then setPan(state, state.channels[i], channelPan[i]) end
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
    local special = fromLE(file.read(2))
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
        if bit32.btest(sflags, 8) then error("Compressed samples not supported") end
        sample.type = (bit32.btest(sflags, 0x10) and (bit32.btest(sflags, 0x40) and 2 or 1) or 0) + (bit32.btest(sflags, 2) and 0x10 or 0)
        sample.volume = file.read()
        sample.name = file.read(26):gsub("[ %z]+$", "")
        local convert = file.read()
        sample.pan = file.read()
        if sample.pan >= 128 then sample.pan = (sample.pan - 128) * 2
        else sample.pan = 128 end
        local size = fromLE(file.read(4))
        sample.loopStart = fromLE(file.read(4))
        sample.loopLength = fromLE(file.read(4)) - sample.loopStart
        local c5speed = fromLE(file.read(4))
        local note = 12 * log(c5speed / 8363, 2)
        sample.note = math.ceil(note - 0.5)
        sample.finetune = floor((note - sample.note) * 127)
        file.read(8) -- TODO: sustain loop
        local addr = fromLE(file.read(4))
        sample.vibrato = {sweep = file.read(), depth = file.read(), type = file.read(), rate = file.read(), sweep_mult = 0} -- cloned to instrument
        file.seek("set", addr)
        local signed = bit32.btest(convert, 1)
        local bit16 = bit32.btest(sflags, 2)
        local ampl = bit16 and 32768 or 128
        local offset = signed and 0 or ampl
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
        sample.length = #sample.wavetable
        if bit32.btest(sflags, 4) then
            local wavetableR = {}
            sample.wavetable = {sample.wavetable, wavetableR}
            last = 0
            for j = 1, size do
                local n = format:unpack(file.read(fmtsize)) - offset
                if isDelta then n = last + n end
                last = n
                n = n / (n < 0 and ampl or (ampl - 1))
                wavetableR[j] = n
            end
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
        inst.newNoteAction = file.read()
        inst.duplicateCheckType = file.read()
        inst.duplicateNoteAction = file.read()
        inst.fadeOut = fromLE(file.read(2)) * 128
        file.read(2) -- PPS, PPC
        inst.volume = file.read() / 128
        file.read() -- DfP
        file.read(6) -- padding
        inst.name = file.read(26):gsub("[ %z]+$", "")
        if compatver >= 0x0200 then
            inst.initialCutoff, inst.initialResonance = ("bb"):unpack(file.read(2))
            inst.initialCutoff, inst.initialResonance = inst.initialCutoff + 128, inst.initialResonance + 128
            file.read(4) -- MIDI (unused)
            if inst.initialCutoff < 0x7F or inst.initialResonance > 0 then
                local r = (2 * math.pi * 110 * (2^.25)) / (2^(inst.initialCutoff / 24)) / 48000
                local p = 10^((-inst.initialResonance * 24) / (128 * 20))
                local d = 2 * p * r + 2 * p - 1
                local e = r^2
                local n = 1 + d + e
                inst.filter = {1 / n, 0, 0, -(d + 2 * e) / n, e / n}
                --[[
                -- https://github.com/velipso/sndfilter/blob/master/src/biquad.c
                local resonance = 10^(-inst.initialResonance / 206.66666666666666)
                local cutoff = (110*2^(0.25+inst.initialCutoff/48)) / 24000
                local theta = math.pi * 2 * cutoff
                local alpha = math.sin(theta) / (2 * resonance)
                local cosw = math.cos(theta)
                local beta = (1 + cosw) / 2
                local a0inv = 1 / (1 + alpha)
                inst.filter = {a0inv * beta, a0inv * 2 * beta, a0inv * beta, a0inv * -2 * cosw, a0inv * (1 - alpha)}
                --]]
            end
        else file.read(6) end -- padding
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
            inst.volumeEnvelope.sustainStart = file.read() + 1
            inst.volumeEnvelope.sustain = file.read() + 1 -- sustain end
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
            inst.panningEnvelope.sustainStart = file.read() + 1
            inst.panningEnvelope.sustain = file.read() + 1 -- sustain end
            for j = 1, npoints do
                inst.panningEnvelope.points[j] = {y = ("b"):unpack(file.read(1)) + 32, x = fromLE(file.read(2))}
            end
            file.read((25 - npoints) * 3 + 1)
        end

        do
            local type = file.read()
            inst.pitchEnvelope.loopType = bit32.band(type, 1) + (bit32.btest(type, 4) and 2 or 0) + (bit32.btest(type, 2) and 4 or 0) + bit32.band(type, 0x80)
            local npoints = file.read()
            inst.pitchEnvelope.loopStart = file.read() + 1
            inst.pitchEnvelope.loopEnd = file.read() + 1
            inst.pitchEnvelope.sustainStart = file.read() + 1
            inst.pitchEnvelope.sustain = file.read() + 1 -- sustain end
            for j = 1, npoints do
                inst.pitchEnvelope.points[j] = {y = ("b"):unpack(file.read(1)) + 32, x = fromLE(file.read(2))}
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
                        elseif v >= 65 and v <= 74 then v = 0x90 + (v - 65)
                        elseif v >= 75 and v <= 84 then v = 0x80 + (v - 75)
                        elseif v >= 85 and v <= 94 then v = 0x70 + (v - 85)
                        elseif v >= 95 and v <= 104 then v = 0x60 + (v - 95)
                        elseif v >= 105 and v <= 114 then v = 0xD0 + (v - 105)
                        elseif v >= 115 and v <= 124 then v = 0xE0 + (v - 115)
                        elseif v >= 193 and v <= 202 then v = 0xF0 + (v - 193)
                        elseif v >= 203 and v <= 212 then v = 0xB0 + (v - 203) end
                        lastvol[x] = v
                        patterns[i][y][x].volume = lastvol[x]
                    end
                    if bit32.btest(follow, 0x08) then
                        lasteff[x] = {file.read(), file.read()}
                        local nv
                        patterns[i][y][x].effect, patterns[i][y][x].effect_param, nv = itEffects[lasteff[x][1]](lasteff[x][2], g)
                        if nv and not patterns[i][y][x].volume then patterns[i][y][x].volume = nv end
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
                        local nv
                        patterns[i][y][x].effect, patterns[i][y][x].effect_param, nv = itEffects[lasteff[x][1]](lasteff[x][2], g)
                        if nv and not patterns[i][y][x].volume then patterns[i][y][x].volume = nv end
                    end
                end
                lastfollow[x] = follow
            end
        end
    end
    local state = { ---@type tracc
        type = "it",
        tempo = tempo,
        bpm = bpm,
        channels = {},
        tempChannels = {},
        module = {
            instruments = instruments,
            patterns = patterns,
            order = order,
            name = name,
            tracker = tracker,
            amigaSlides = amigaSlides,
            restartPosition = restartPosition
        },
        midiMacros = {parametered = {}, fixed = {}},
        speakers = {},
        order = 1,
        row = 1,
        globalVolume = globalVolume,
        mutedChannels = mutedChannels,
        mixVolume = mixVolume,
        loop = true,
        currentOrder = 1,
        currentRow = 1,
        freqMemo = {},
        sound = makeSound()
    }
    for i = 1, channelCount do
        state.channels[i] = {
            num = i,
            effectMemory = {},
            midiMacro = 0,
            playing = {note = 0, instrument = 0, volume = 0, effect = 0, effect_param = 0},
            volume = 64,
            volumeEnvelope = {volume = 64, pos = 0, x = 0},
            vibrato = {type = 0, pos = 0},
            panningEnvelope = {panning = 128, pos = 0, x = 0}
        }
    end
    return state
end

---@param iEnvelope tracc.envelope
---@param envelope table
---@param key string
---@return boolean|nil
local function processEnvelope(iEnvelope, envelope, key)
    if iEnvelope.loopType % 2 == 1 and envelope.pos > 0 and not envelope.sustain then
        local points = iEnvelope.points
        envelope.x = envelope.x + 1
        envelope[key] = envelope[key] + envelope.rate
        if envelope.x == points[envelope.pos+1].x then
            envelope.pos = envelope.pos + 1
            if bit32.btest(iEnvelope.loopType, 4) and envelope.pos == iEnvelope.loopEnd then
                envelope.pos = iEnvelope.loopStart
                envelope.x = points[envelope.pos].x
            end
            envelope[key] = points[envelope.pos].y
            while envelope.pos < #points and points[envelope.pos].x == points[envelope.pos+1].x do envelope.pos = envelope.pos + 1 end
            if envelope.pos < #points then envelope.rate = (points[envelope.pos+1].y - points[envelope.pos].y) / (points[envelope.pos+1].x - points[envelope.pos].x) end
            if envelope.pos >= #points or (bit32.btest(iEnvelope.loopType, 2) and envelope.pos == iEnvelope.sustain) and envelope.sustain == nil then
                if envelope.sustainStart and envelope.sustainStart ~= envelope.sustain then
                    envelope.pos = envelope.sustainStart
                    envelope.x = points[envelope.pos].x
                    envelope[key] = points[envelope.pos].y
                    while envelope.pos < #points and points[envelope.pos].x == points[envelope.pos+1].x do envelope.pos = envelope.pos + 1 end
                    if envelope.pos < #points then envelope.rate = (points[envelope.pos+1].y - points[envelope.pos].y) / (points[envelope.pos+1].x - points[envelope.pos].x) end
                else envelope.sustain = true end
            end
        end
        return true
    end
end

---@param state tracc
---@param e boolean
---@param ls number[]
---@param rs number[]|nil
---@param vu table
local function processTick(state, e, ls, rs, vu)
    for _,c in ipairs(state.channels) do
        --if not c.playing or c.playing.effect ~= 2 then effects[2](state, c, 0x02) end
        local playing, instrument = c.playing, c.instrument
        if e and playing and playing.effect then effects[c.playing.effect](state, c, c.playing.effect_param or 0) end
        if e and playing and playing.volume and playing.volume > 0x50 then volume_effects[floor(c.playing.volume / 16)](state, c, c.playing.volume % 16) end
        if instrument then
            if processEnvelope(instrument.volumeEnvelope, c.volumeEnvelope, "volume") then setVolume(state, c, c.volume) end
            if processEnvelope(instrument.panningEnvelope, c.panningEnvelope, "panning") then setPan(state, c, c.panningEnvelope.panning * 4) end
            if instrument.pitchEnvelope and processEnvelope(instrument.pitchEnvelope, c.pitchEnvelope, "pitch") then
                if bit32.btest(instrument.pitchEnvelope.loopType, 0x80) then
                    local r = (2 * math.pi * 110 * (2^.25)) / (2^(c.pitchEnvelope.pitch / 12)) / 48000
                    local p = 10^((-instrument.initialResonance * 24) / (128 * 20))
                    local d = 2 * p * r + 2 * p - 1
                    local e = r^2
                    local n = 1 + d + e
                    state.sound.channels[c.num].filter = {1 / n, 0, 0, -(d + 2 * e) / n, e / n}
                else
                    c.finetune = (c.pitchEnvelope.pitch - 32) * 8
                    if c.note and c.frequency and c.frequency > 0 then setFrequency(state, c.num, c.frequency * 2^((c.pitchEnvelope.pitch - 32) / 24), instrument.samples[c.note]) end
                end
            end
            if instrument.vibrato.depth > 0 then
                local vibrato = instrument.vibrato
                doVibrato(state, c, vibrato.type, vibrato.rate / 4, vibrato.depth * vibrato.sweep_mult / 4)
                if vibrato.sweep_mult < 1 then vibrato.sweep_mult = vibrato.sweep_mult + (1 / vibrato.sweep) end
            end
        end
        c.didSetInstrument = false
    end
    for i,c in pairs(state.tempChannels) do
        local instrument = c.instrument
        if instrument and instrument.volumeEnvelope.loopType % 2 == 1 and c.volumeEnvelope.pos > 0 then
            local volumeEnvelope, iVolumeEnvelope = c.volumeEnvelope, instrument.volumeEnvelope
            local points = iVolumeEnvelope.points
            volumeEnvelope.x = volumeEnvelope.x + 1
            volumeEnvelope.volume = volumeEnvelope.volume + volumeEnvelope.rate
            if volumeEnvelope.pos >= #iVolumeEnvelope.points then state.tempChannels[i] = nil
            elseif volumeEnvelope.x == points[volumeEnvelope.pos+1].x then
                volumeEnvelope.pos = volumeEnvelope.pos + 1
                if bit32.btest(iVolumeEnvelope.loopType, 4) and volumeEnvelope.pos == iVolumeEnvelope.loopEnd then
                    volumeEnvelope.pos = iVolumeEnvelope.loopStart
                    volumeEnvelope.x = points[volumeEnvelope.pos].x
                end
                volumeEnvelope.volume = points[volumeEnvelope.pos].y
                if volumeEnvelope.pos >= #points then state.tempChannels[i] = nil
                else volumeEnvelope.rate = (points[volumeEnvelope.pos+1].y - points[volumeEnvelope.pos].y) / (points[volumeEnvelope.pos+1].x - points[volumeEnvelope.pos].x) end
            end
            setVolume(state, c, c.volume)
        elseif c.sound.volume == 0 or c.sound.pos >= 1 then state.tempChannels[i] = nil end
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
    local module = state.module
    local patterns, instruments, order = module.patterns, module.instruments, module.order
    local v = state.module.order[state.order]
    if not v then return nil end
    while v >= 254 or state.row > #patterns[v+1] do
        if state.order == state.currentOrder then
            state.row = 1
            state.order = state.order + 1
            if state.loop and state.order > #order then state.order = module.restartPosition + 1 end
        end
        state.currentOrder = state.order
        v = order[state.order]
        if not v then return nil end
    end
    state.tick = 1
    state.currentRow = state.row
    state.usedB, state.usedD = nil, nil
    local row = patterns[v+1][state.row]
    if not row then error((v + 1) .. "/" .. state.row) end
    for _,x in ipairs(state.speakers) do x.usage = 0 end
    for k,c in ipairs(state.channels) do
        local playing = row[k]
        c.playing = playing
        if playing then
            local setLastFrequency = false
            if playing.instrument and instruments[playing.instrument] then
                setInstrument(state, c, playing.instrument)
                if (state.type == "xm" or c.pan == nil) and (playing.note or c.lastNote) < 97 then setPan(state, c, c.instrument.samples[playing.note or c.lastNote].pan) end
                if state.type ~= "xm" and not (playing.note and playing.note ~= 0) and c.lastNote then
                    c.lastFrequency = getFrequency(state, c.num, instruments[playing.instrument].samples[c.lastNote])
                    setLastFrequency = true
                    setNote(state, c, c.lastNote)
                    if state.type ~= "mod" then setVolume(state, c, c.instrument.samples[c.lastNote].volume) end
                end
            end
            local vol_ret
            if playing.note and playing.note ~= 0 and not setLastFrequency then c.lastFrequency = c.instrument and getFrequency(state, c.num, c.instrument.samples[c.lastNote or playing.note]) or c.frequency end
            if playing.volume then vol_ret = volume_effects[floor(playing.volume / 16)](state, c, playing.volume % 16) end
            if playing.note and playing.note ~= 0 then
                if (not playing.volume or playing.volume < 0x10 or playing.volume >= 0x60) and playing.note < 97 and c.instrument.samples[playing.note] then setVolume(state, c, c.instrument.samples[playing.note].volume) end
                if (not playing.effect or playing.effect == 9 or effects[playing.effect](state, c, playing.effect_param or 0) ~= 0) and vol_ret ~= 0 then
                    if playing.note < 97 then c.lastNote = playing.note end
                    setNote(state, c, playing.note)
                end
            end
            if (not playing.note or playing.note == 0 or playing.effect == 9) and playing.effect then effects[playing.effect](state, c, playing.effect_param or 0) end
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
            elseif whence == "end" then pos = max(#data - offset, 1)
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
