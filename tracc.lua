local globalParams = {
    realTime = true,
    notesPerTick = 8,
    loop = true,
    shownColumns = {
        note = true,
        instrument = true,
        volume = true,
        effect = true
    },
    autoSize = false
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

local portaDrift = 192

local lastTick = os.epoch "utc"
local function waitForNextTick(state)
    if lastTick < os.epoch "utc" then lastTick = os.epoch "utc" end
    if globalParams.realTime then sleep(((lastTick + (2500 / state.bpm)) - os.epoch "utc") / 1000)
    else sleep(0.05) end
    lastTick = lastTick + (2500 / state.bpm)
end

local function toFreq(note, finetune, sample)
    if sample.name == "custom" then return 8363*2^((6*12*16*4 - (10*12*16*4 - (note-1)*16*4 - finetune/2)) / (12*16*4))
    else return 8363*2^((2^(-1.5/12)*12*16*4 - (10*12*16*4 - note*16*4 - finetune/2)) / (12*16*4)) end
end
local function toNote(note, name) return note - 12*(noteRange[name]-1) - 7 end
local function toSpeed(note) return 2^((note - 49)/12) end
local function getFrequency(channel, sample) if sample.name == "custom" then return sound.getFrequency(channel) * #sample.wavetable else return sound.getFrequency(channel) end end
local function setFrequency(channel, freq, sample) if sample.name == "custom" then return sound.setFrequency(channel, freq / #sample.wavetable) else return sound.setFrequency(channel, freq) end end

local function setVolume(state, channel, vol)
    channel.volume = vol
    if not channel.speaker then
        if mutedChannels[channel.num] then sound.setVolume(channel.num, 0)
        else sound.setVolume(channel.num, vol / 64 / 10 * (state.globalVolume / 64) * (channel.volumeEnvelope.volume / 64)) end
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
    channel.instrument = state.module.instruments[inst]
    if #channel.instrument.volumeEnvelope.points > 0 and channel.instrument.volumeEnvelope.loopType % 2 == 1 then
        if #channel.instrument.volumeEnvelope.points == 1 or (bit32.btest(channel.instrument.volumeEnvelope.loopType, 2) and channel.instrument.volumeEnvelope.sustain == 1) then channel.volumeEnvelope = {volume = channel.instrument.volumeEnvelope.points[1].y, pos = 1, x = 0, sustain = true}
        else channel.volumeEnvelope = {volume = channel.instrument.volumeEnvelope.points[1].y, pos = 1, x = 0, rate = (channel.instrument.volumeEnvelope.points[2].y - channel.instrument.volumeEnvelope.points[1].y) / (channel.instrument.volumeEnvelope.points[2].x - channel.instrument.volumeEnvelope.points[1].x)} end
    else
        channel.volumeEnvelope = {volume = 64, pos = 0, x = 0}
    end
    if #channel.instrument.panningEnvelope.points > 0 and channel.instrument.panningEnvelope.loopType % 2 == 1 then
        if #channel.instrument.panningEnvelope.points == 1 or (bit32.btest(channel.instrument.panningEnvelope.loopType, 2) and channel.instrument.panningEnvelope.sustain == 1) then channel.panningEnvelope = {panning = channel.instrument.panningEnvelope.points[1].y, pos = 1, x = 0, sustain = true}
        else channel.panningEnvelope = {panning = channel.instrument.panningEnvelope.points[1].y, pos = 1, x = 0, rate = (channel.instrument.panningEnvelope.points[2].y - channel.instrument.panningEnvelope.points[1].y) / (channel.instrument.panningEnvelope.points[2].x - channel.instrument.panningEnvelope.points[1].x)} end
    else
        channel.panningEnvelope = {panning = 32, pos = 0, x = 0}
    end
end

local function setNote(state, channel, note)
    channel.speaker = nil
    if note == 97 then
        if not channel.speaker then
            if channel.instrument and #channel.instrument.volumeEnvelope.points > 1 and not (channel.playing and channel.playing.effect == 0xE and channel.playing.effect_param and bit32.band(channel.playing.effect_param, 0xF0) == 0xD0) and channel.instrument.fadeOut > 0 then
                sound.fadeOut(channel.num, (32768 / channel.instrument.fadeOut) * (2.5 / state.bpm))
            elseif channel.instrument and #channel.instrument.volumeEnvelope.points - 1 == channel.instrument.volumeEnvelope.sustain then
                sound.fadeOut(channel.num, (channel.instrument.volumeEnvelope.points[#channel.instrument.volumeEnvelope.points].x - channel.instrument.volumeEnvelope.points[#channel.instrument.volumeEnvelope.points-1].x) * (2.5 / state.bpm))
            else sound.setVolume(channel.num, 0) sound.setFrequency(channel.num, 0) end
        end
        channel.note = nil
    elseif note ~= 0 then
        local sample = channel.instrument.samples[note]
        if sample.name == "unused" then
            if not channel.speaker then sound.setVolume(channel.num, 0) end
        elseif not channel.speaker and (sample.name == "sine" or sample.name == "triangle" or sample.name == "sawtooth" or sample.name == "rsawtooth" or sample.name == "square" or sample.name == "noise" or sample.name == "pnoise") then
            channel.finetune = sample.finetune
            sound.setWaveType(channel.num, sample.name)
            setFrequency(channel.num, toFreq(note+sample.note, channel.finetune, sample), sample)
            --if channel.instrument.fadeOut then sound.fadeOut(channel.num, 1 / math.log(channel.instrument.fadeOut, 2)) end
        elseif not channel.speaker and sound.version and sample.name:match "square:[0-9]+%.?[0-9]*" then
            channel.finetune = sample.finetune
            sound.setWaveType(channel.num, "square", tonumber(sample.name:match "square:([0-9%.]+)"))
            setFrequency(channel.num, toFreq(note+sample.note, channel.finetune, sample), sample)
        elseif not channel.speaker and sound.version and sample.name == "custom" then
            channel.finetune = sample.finetune
            sound.setWaveType(channel.num, "custom", sample.wavetable)
            setFrequency(channel.num, toFreq(note+sample.note, channel.finetune, sample), sample)
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
            setFrequency(channel.num, getFrequency(channel.num, channel.instrument.samples[channel.note]) * (2^(param / portaDrift)), channel.instrument.samples[channel.note])
        end
    end,
    function(state, channel, param) -- 2
        if param == 0 then param = channel.effectMemory[0xE2] or 0
        else channel.effectMemory[0xE2] = param end
        if not channel.speaker and state.tick == 1 and channel.note then
            setFrequency(channel.num, getFrequency(channel.num, channel.instrument.samples[channel.note]) / (2^(param / portaDrift)), channel.instrument.samples[channel.note])
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
            if channel.playing then setFrequency(channel.num, toFreq(channel.playing.note+channel.instrument.samples[channel.playing.note].note, channel.finetune, channel.instrument.samples[channel.playing.note]), channel.instrument.samples[channel.playing.note]) end
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
            setFrequency(channel.num, getFrequency(channel.num, channel.instrument.samples[channel.note]) * (2^(param / (portaDrift*16))), channel.instrument.samples[channel.note])
        end
    end,
    function(state, channel, param) -- 2
        if param == 0 then param = channel.effectMemory[0x212] or 0
        else channel.effectMemory[0x212] = param end
        if not channel.speaker and state.tick == 1 and channel.note then
            setFrequency(channel.num, getFrequency(channel.num, channel.instrument.samples[channel.note]) / (2^(param / (portaDrift*16))), channel.instrument.samples[channel.note])
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

local effects
effects = {
    [0] = function(state, channel, param) -- 0
        if state.tick % 3 == 1 then setNote(state, channel, channel.lastNote or channel.playing.note)
        elseif state.tick % 3 == 2 then setNote(state, channel, (channel.lastNote or channel.playing.note) + bit32.rshift(param, 4))
        else setNote(state, channel, (channel.lastNote or channel.playing.note) + bit32.band(param, 0xF)) end
    end,
    function(state, channel, param) -- 1
        if param == 0 then param = channel.effectMemory[1] or 0
        else channel.effectMemory[1] = param end
        if not channel.speaker and state.tick > 1 and channel.note then
            setFrequency(channel.num, math.min(getFrequency(channel.num, channel.instrument.samples[channel.note]) * (2^(param / portaDrift)), 8363), channel.instrument.samples[channel.note])
        end
    end,
    function(state, channel, param) -- 2
        if param == 0 then param = channel.effectMemory[2] or 0
        else channel.effectMemory[2] = param end
        if not channel.speaker and state.tick > 1 and channel.note then
            setFrequency(channel.num, math.max(getFrequency(channel.num, channel.instrument.samples[channel.note]) / (2^(param / portaDrift)), 0), channel.instrument.samples[channel.note])
        end
    end,
    function(state, channel, param) -- 3
        if param == 0 then param = channel.effectMemory[3] or 0
        else channel.effectMemory[3] = param end
        if not channel.speaker and channel.note then
            local note = channel.playing.note or channel.lastNote
            local sample = channel.instrument.samples[note]
            --print(sample.name, channel.playing.note, channel.lastNote, sample.note, getFrequency(channel.num, sample), toFreq(note+sample.note, sample.finetune, sample))
            if state.tick == 1 then
                setNote(state, channel, channel.lastNote)
                if channel.playing and channel.playing.note then channel.lastNote = channel.playing.note end
                return 0
            elseif getFrequency(channel.num, sample) < toFreq(note+sample.note, sample.finetune, sample) / 2^(param / portaDrift) then
                setFrequency(channel.num, getFrequency(channel.num, sample) * 2^(param / portaDrift), sample)
            elseif getFrequency(channel.num, sample) > toFreq(note+sample.note, sample.finetune, sample) * 2^(param / portaDrift) then
                setFrequency(channel.num, getFrequency(channel.num, sample) / 2^(param / portaDrift), sample)
            else--if getFrequency(channel.num, sample) < toFreq(channel.lastNote or channel.playing.note) then
                setFrequency(channel.num, toFreq(note+sample.note, sample.finetune, sample), sample)
            end
        end
    end,
    function(state, channel, param) -- 4
        if param == 0 then param = channel.effectMemory[4] or 0
        else channel.effectMemory[4] = param end
        if state.tick == 1 and channel.playing and channel.playing.note and bit32.btest(channel.vibrato.type, 4) then channel.vibrato.pos = 0 end
        local t, speed, depth, amplitude = bit32.band(channel.vibrato.type, 3), bit32.rshift(param, 4), bit32.band(param, 0x0f)
        if t == 0 then amplitude = math.sin(channel.vibrato.pos * math.pi)
        elseif t == 1 then amplitude = channel.vibrato.pos * 2 - 1
        elseif t == 2 then amplitude = channel.vibrato.pos >= 0.5 and -1 or 1
        else amplitude = math.random() * 2 - 1 end
        if channel.instrument and channel.note then
            local sample = channel.instrument.samples[channel.note]
            setFrequency(channel.num, toFreq(channel.note+sample.note, sample.finetune, sample) * 2^(amplitude * depth / (12*8)), sample)
        end
        channel.vibrato.pos = (channel.vibrato.pos + (speed / 64)) % 1
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
        -- unimplemented
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
            if sample.name:match "^square" then sound.setWaveType(channel.num, "square", param / 256) end
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
        return effects[0xA](state, channel, param * 16)
    end,
    function(state, channel, param) -- c
        return effects[0xA](state, channel, param)
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
local strings = require "cc.strings"

do
    local function fromLE(str)
        if not str then error("Bad str", 2) end
        local n = 0
        for i = 1, #str do n = n + bit32.lshift(str:byte(i), 8*(i-1)) end
        return n
    end

    local path = ...
    if path == nil then error("Usage: tracc <file>") end
    local file = fs.open(path, "rb")

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
    file.read(2) -- flags
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
        print(i, ("%X"):format(file.seek()))
        local inst = {}
        instruments[i] = inst
        local instsize = fromLE(file.read(4))
        inst.name = file.read(22):gsub("[ %z]+$", "")
        file.read()
        local sampleCount = fromLE(file.read(2))
        print(sampleCount)
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
            inst.vibrato.sweep = file.read()
            inst.vibrato.depth = file.read()
            inst.vibrato.rate = file.read()
            inst.fadeOut = fromLE(file.read(2))
            file.seek("cur", instsize - 241)

            for j = 1, sampleCount do
                local sample = inst.samplesByNumber[j]
                local size = fromLE(file.read(4))
                print(j, ("%X"):format(file.seek()), size)
                file.read(4) -- loop start
                file.read(4) -- loop length
                sample.volume = file.read()
                sample.finetune = file.read()
                if sample.finetune > 0x7F then sample.finetune = sample.finetune - 256 end
                sample.type = file.read()
                sample.pan = file.read() --math.max((file.read() - 128) / 127, -1)
                sample.note = file.read()
                if sample.note > 0x7F then sample.note = sample.note - 256 end
                file.read() -- reserved
                sample.name = file.read(22):gsub("[ %z]+$", "")
                file.seek("cur", samplesize - 40)
                if sample.name == "custom" then
                    sample.wavetable = {}
                    if bit32.btest(sample.type, 0x10) then
                        local last = 0
                        for i = 1, size / 2 do
                            local d = fromLE(file.read(2))
                            if d > 0x7FFF then d = d - 65536 end
                            d = d / (d > 0 and 65535 or 65536)
                            sample.wavetable[i], last = last + d, d
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
                else file.seek("cur", size) end
            end
        else file.seek("cur", instsize - 29) end
    end

    file.close()
end

local notemap = {[0] = "B-", "C-", "C#", "D-", "D#", "E-", "F-", "F#", "G-", "G#", "A-", "A#"}
local function formatNote(note) if note == 97 then return "== " else return notemap[note % 12] .. tostring(math.floor(note / 12)+1) end end

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
h = h - 4
local trackerpos = 0
local trackerwin = window.create(term.current(), 1, 5, w, h)
local startTime = os.epoch "utc"

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
    for i = 1, #order do ordx[i] = term.getCursorPos() term.write(order[i] .. " ") end
    term.setCursorPos(ordx[ord], 3)
    local s = tostring(pat - 1)
    term.blit(s, ("f"):rep(#s), ("0"):rep(#s))
    term.setCursorPos(1, 4)
    term.setBackgroundColor(colors.gray)
    term.clearLine()
    local cwidth = (globalParams.shownColumns.note and 3 or 0) + (globalParams.shownColumns.volume and 3 or 0) + (globalParams.shownColumns.instrument and 3 or 0) + (globalParams.shownColumns.effect and 4 or 0) + 1
    for i = 1, channelCount do
        local text = "Channel " .. i
        if cwidth < #text then text = "Ch. " .. i end
        if cwidth < #text then text = tostring(i) end
        term.setCursorPos(cwidth * (i - 1) + 5 + math.floor((cwidth - #text) / 2), 4)
        term.blit(text, (mutedChannels[i] and "8" or "0"):rep(#text), ("7"):rep(#text))
    end
    trackerwin.clear()
    for yy = 0, h do
        if patterns[pat][trackerpos-math.ceil(h / 2)+1] then
            trackerwin.setCursorPos(1, yy)
            trackerwin.blit(("%3d"):format(trackerpos-math.ceil(h / 2)) .. " ", "8888", "ffff")
            for j = 1, channelCount do
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
                        elseif note.note and note.note ~= 97 then trackerwin.blit(("v%02d "):format(instruments[note.instrument].samples[note.note].volume), "dddd", "ffff")
                        else trackerwin.blit(" -- ", "0000", "ffff") end
                    end
                    if globalParams.shownColumns.effect then
                        if note.effect then trackerwin.blit(effectString:sub(note.effect + 1, note.effect + 1) .. ("%02X"):format(note.effect_param or 0) .. " ", (note.effect == 0xE and effectColorE[bit32.rshift(note.effect_param, 4)] or (note.effect == 0x21 and effectColorX[bit32.rshift(note.effect_param, 4)] or effectColor[note.effect])):rep(4), "ffff")
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
        for x = 1, channelCount do
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
                        elseif note.note and note.note ~= 97 then trackerwin.blit(("v%02d "):format(instruments[note.instrument].samples[note.note].volume), "dddd", "ffff")
                        else trackerwin.blit(" -- ", "0000", "ffff") end
                    end
                    if globalParams.shownColumns.effect then
                        if note.effect then trackerwin.blit(effectString:sub(note.effect + 1, note.effect + 1) .. ("%02X"):format(note.effect_param or 0) .. " ", (note.effect == 0xE and effectColorE[bit32.rshift(note.effect_param, 4)] or (note.effect == 0x21 and effectColorX[bit32.rshift(note.effect_param, 4)] or effectColor[note.effect])):rep(4), "ffff")
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

local state = {tempo = tempo, bpm = bpm, channels = {}, module = {instruments = instruments, order = order}, speakers = {}, order = 1, row = 1, globalVolume = 64, name = name}
for i = 1, channelCount do state.channels[i] = {num = i, effectMemory = {}, playing = {note = 0, instrument = 0, volume = 0, effect = 0, effect_param = 0}, volume = 64, volumeEnvelope = {volume = 64, pos = 0, x = 0}, vibrato = {type = 0, pos = 0}} end
for i,v in ipairs{peripheral.find("speaker")} do state.speakers[i] = {usage = 0, speaker = v} end

if sound then for i = 1, channelCount do
    sound.setVolume(i, 0)
    sound.setPan(i, 0)
    sound.setFrequency(i, 0)
    sound.setWaveType(i, "none")
end end

local function processTick(e)
    for _,c in ipairs(state.channels) do
        if e and c.playing and c.playing.effect then effects[c.playing.effect](state, c, c.playing.effect_param or 0) end
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
        c.didSetInstrument = false
    end
end

if globalParams.autoSize then
    if channelCount * 14 + 4 > w then globalParams.shownColumns.instrument = false end
    if channelCount * 11 + 4 > w then globalParams.shownColumns.effect = false end
    if channelCount * 7 + 4 > w then globalParams.shownColumns.volume = false end
    -- if it's still too small: oh well
end

local skippedRow = false
local pauseState = nil

local ok, err = pcall(parallel.waitForAny, function()

while state.order <= #order do
    local v = order[state.order]
    state.currentOrder = state.order
    trackerpos = state.row - 1
    y = state.row
    redrawScreen(v+1, state.order)
    --scrollScreen(v+1)
    while state.row <= #patterns[v+1] do
        state.tick = 1
        state.currentRow = state.row
        state.usedB, state.usedD = nil
        local row = patterns[v+1][state.row]
        if not row then error((v + 1) .. "/" .. state.row) end
        for _,x in ipairs(state.speakers) do x.usage = 0 end
        for k,c in ipairs(state.channels) do
            c.playing = row[k]
            if c.playing then
                if c.playing.instrument then
                    setInstrument(state, c, c.playing.instrument)
                    setPan(state, c, c.instrument.samples[c.playing.note or c.lastNote].pan)
                end
                if c.playing.volume then volume_effects[math.floor(c.playing.volume / 16)](state, c, c.playing.volume % 16) end
                if c.playing.note and c.playing.note ~= 0 then
                    if (not c.playing.volume or c.playing.volume < 0x10 or c.playing.volume >= 0x60) and c.playing.note < 97 then setVolume(state, c, c.instrument.samples[c.playing.note].volume) end
                    if not c.playing.effect or effects[c.playing.effect](state, c, c.playing.effect_param or 0) ~= 0 then
                        if c.playing.note ~= 97 then c.lastNote = c.playing.note end
                        setNote(state, c, c.playing.note)
                    end
                end
                if (not c.playing.note or c.playing.note == 0) and c.playing.effect then effects[c.playing.effect](state, c, c.playing.effect_param or 0) end
            end
        end
        processTick(false)
        waitForNextTick(state)
        if skippedRow then break end
        for k = 2, state.tempo do
            state.tick = k
            processTick(true)
            waitForNextTick(state)
            if skippedRow then break end
        end
        if skippedRow then break end
        if pauseState then
            while pauseState == 0 do os.pullEvent() end
            if pauseState then pauseState = 0 end
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
            end
        end
        if didChangeMuted then
            term.setCursorPos(1, 4)
            term.setBackgroundColor(colors.gray)
            term.clearLine()
            local cwidth = (globalParams.shownColumns.note and 3 or 0) + (globalParams.shownColumns.volume and 3 or 0) + (globalParams.shownColumns.instrument and 3 or 0) + (globalParams.shownColumns.effect and 4 or 0) + 1
            for i = 1, channelCount do
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
