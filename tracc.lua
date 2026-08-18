local libtracc = require "libtracc"
libtracc.interpolation = select(2, ...) or "none"

local globalParams = {
    loop = true,
    shownColumns = {
        note = true,
        instrument = true,
        volume = true,
        effect = true
    },
    autoSize = false,
}

local function waitForNextRow(state, stereo)
    os.pullEvent("speaker_audio_empty")
    if stereo then os.pullEvent("speaker_audio_empty") end
end

local state do
    local path = shell.resolve(...)
    if path == nil then error("Usage: tracc <file>") end
    local file = assert(fs.open(path, "rb"))
    local s = file.read(0x30)
    if s:sub(1, 17) == "Extended Module: " then
        file.seek("set")
        state = libtracc.readXMFile(file)
    elseif s:sub(1, 4) == "IMPM" then
        file.seek("set")
        state = libtracc.readITFile(file)
    elseif s:sub(0x2D, 0x30) == "SCRM" then
        file.seek("set")
        state = libtracc.readS3MFile(file)
    else
        file.seek("set")
        state = libtracc.readMODFile(file)
    end

    file.close()
end

local notemap = {[0] = "B-", "C-", "C#", "D-", "D#", "E-", "F-", "F#", "G-", "G#", "A-", "A#"}
local function formatNote(note) if note == 97 or note == 255 then return "== " elseif note == 254 then return "^^ " else return notemap[note % 12] .. tostring(math.floor(note / 12)+1) end end

term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
print("Name:", state.module.name, "Tempo:", state.tempo, "BPM:", state.bpm)
write("Tracker: " .. state.module.tracker .. " Channels: " .. #state.channels .. " ")
local timepos = term.getCursorPos()
print(("[%02d:%02d]"):format(0, 0))
for i = 1, #state.module.order do term.write(state.module.order[i] .. " ") end
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

local function formatEffect(effect, param) return effectString:sub(effect + 1, effect + 1) .. ("%02X"):format(param or 0) end
if state.type == "s3m" or state.type == "it" then
    effectString = "JFEGHLKRXODBCCSTVWIJKLMNOPQQSIUVWSYZ\\"
    volumeString = "-vvvvvdcbauhpefg"
    function formatEffect(effect, param)
        if effect == 0x0E then
            local h, l = bit32.rshift(param, 4), bit32.band(param, 15)
            if h == 0xB then effect, param = 0x0A, 0xF0 + l
            elseif h == 0xA then effect, param = 0x0A, 0x0F + l * 16
            elseif h == 0x2 then effect, param = 0x02, 0xF0 + l
            elseif h == 0x1 then effect, param = 0x01, 0xF0 + l
            elseif h == 0x3 then param = 0x10 + l
            elseif h == 0x5 then param = 0x20 + l
            elseif h == 0x4 then param = 0x30 + l
            elseif h == 0x7 then param = 0x40 + l
            elseif h == 0x6 then param = 0xB0 + l end
        elseif effect == 0x21 then
            local h, l = bit32.rshift(param, 4), bit32.band(param, 15)
            if h == 0x1 then effect, param = 0x02, 0xE0 + l
            elseif h == 0x2 then effect, param = 0x01, 0xE0 + l end
        elseif effect == 0x19 then
            local h, l = bit32.rshift(param, 4), bit32.band(param, 15)
            if h == 0 then param = l * 16
            elseif l == 0 then param = h end
        elseif effect == 0x08 then
            param = math.floor(param / 2)
        end
        return effectString:sub(effect + 1, effect + 1) .. ("%02X"):format(param or 0)
    end
end

local function redrawScreen(pat, ord, start)
    local cx, cy = term.getCursorPos()
    term.setCursorPos(timepos, 2)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    local activeChannels = #state.tempChannels
    for _, c in ipairs(state.sound.channels) do if c.wavetable and c.volume > 0 and c.frequency > 0 then activeChannels = activeChannels + 1 end end
    term.write(("[%2d] [%02d:%02d]"):format(activeChannels, math.floor((os.epoch "utc" - startTime) / 60000), math.floor((os.epoch "utc" - startTime) / 1000) % 60))
    term.setCursorPos(1, 3)
    local ordx = {}
    for i = 1, #state.module.order do ordx[i] = term.getCursorPos() term.write((state.module.order[i] == 254 and "-" or state.module.order[i]) .. " ") end
    term.setCursorPos(ordx[ord], 3)
    local s = pat >= 255 and "-" or tostring(pat - 1)
    term.blit(s, ("f"):rep(#s), ("0"):rep(#s))
    term.setCursorPos(1, 4)
    term.setBackgroundColor(colors.gray)
    term.clearLine()
    for i = scrollPos, #state.channels do
        local text = "Channel " .. i
        if cwidth < #text then text = "Ch. " .. i end
        if cwidth < #text then text = tostring(i) end
        term.setCursorPos(cwidth * (i - scrollPos) + 5 + math.floor((cwidth - #text) / 2), 4)
        term.blit(text, (state.mutedChannels[i] and "8" or "0"):rep(#text), ("7"):rep(#text))
    end
    term.setCursorPos(1, 5)
    term.clearLine()
    trackerwin.clear()
    if pat >= 255 then return end
    for yy = 0, h do
        if state.module.patterns[pat][trackerpos-math.ceil(h / 2)+1] then
            trackerwin.setCursorPos(1, yy)
            trackerwin.blit(("%3d"):format(trackerpos-math.ceil(h / 2)) .. " ", "8888", "ffff")
            for j = scrollPos, #state.channels do
                if state.module.patterns[pat][trackerpos-math.ceil(h / 2)+1][j] ~= nil then
                    local note = state.module.patterns[pat][trackerpos-math.ceil(h / 2)+1][j]
                    if globalParams.shownColumns.note then
                        if note.note then trackerwin.blit(formatNote(note.note), "bbb", "fff")
                        else trackerwin.blit("---", "000", "fff") end
                        if globalParams.shownColumns.instrument or not globalParams.shownColumns.volume then trackerwin.write(" ") end
                    end
                    if globalParams.shownColumns.instrument then
                        if note.instrument then trackerwin.blit(("%02d"):format(note.instrument):sub(-2), "99", "ff")
                        else trackerwin.blit("--", "00", "ff") end
                        if not globalParams.shownColumns.volume then trackerwin.write(" ") end
                    end
                    if globalParams.shownColumns.volume then
                        if note.volume then trackerwin.blit(volumeString:sub(math.floor(note.volume / 16) + 1, math.floor(note.volume / 16) + 1) .. ("%02d"):format(note.volume >= 0x10 and note.volume < 0x60 and math.min(note.volume - 0x10, 64) or note.volume % 16):sub(-2) .. " ", volumeColor[math.floor(note.volume / 16)]:rep(4), "ffff")
                        elseif note.note and note.instrument and state.module.instruments[note.instrument] and state.module.instruments[note.instrument].samples[note.note] and note.note ~= 97 then trackerwin.blit(("v%02d "):format(state.module.instruments[note.instrument].samples[note.note].volume), "dddd", "ffff")
                        else trackerwin.blit(" -- ", "0000", "ffff") end
                    end
                    if globalParams.shownColumns.effect then
                        if note.effect then trackerwin.blit(formatEffect(note.effect, note.effect_param or 0) .. " ", (note.effect == 0xE and effectColorE[bit32.rshift(note.effect_param or 0, 4)] or (note.effect == 0x21 and effectColorX[bit32.rshift(note.effect_param or 0, 4)] or effectColor[note.effect])):rep(4), "ffff")
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
    term.setCursorPos(cx, cy)
end

local function scrollScreen(pat)
    local cx, cy = term.getCursorPos()
    term.setCursorPos(timepos, 2)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    local activeChannels = #state.tempChannels
    for _, c in ipairs(state.sound.channels) do if c.wavetable and c.volume > 0 and c.frequency > 0 then activeChannels = activeChannels + 1 end end
    term.write(("[%2d] [%02d:%02d]"):format(activeChannels, math.floor((os.epoch "utc" - startTime) / 60000), math.floor((os.epoch "utc" - startTime) / 1000) % 60))
    trackerwin.scroll(1)
    if y > 0 then
        trackerwin.setCursorPos(1, math.ceil(h / 2) - 1)
        local line1, line2, line3 = trackerwin.getLine(math.ceil(h / 2) - 1)
        trackerwin.blit(("%3d"):format(y-1) .. " ", "8888", "ffff")
        trackerwin.blit(line1:sub(5), line2:sub(5), ("f"):rep(#line3 - 4))
    end
    if y <= #state.module.patterns[pat] then
        trackerwin.setCursorPos(1, math.ceil(h / 2))
        local line1, line2, line3 = trackerwin.getLine(math.ceil(h / 2))
        trackerwin.blit(("%3d"):format(y) .. " ", "0000", "7777")
        trackerwin.blit(line1:sub(5), line2:sub(5), ("7"):rep(#line3 - 4))
    end
    trackerwin.setCursorPos(1, h)
    if state.module.patterns[pat][trackerpos-math.ceil(h / 2)+1] then
        trackerwin.blit(("%3d"):format(trackerpos-math.ceil(h / 2)) .. " ", "8888", "ffff")
        for x = scrollPos, #state.channels do
            if state.module.patterns[pat][trackerpos-math.ceil(h / 2)+1] then
                if state.module.patterns[pat][trackerpos-math.ceil(h / 2)+1][x] ~= nil then
                    local note = state.module.patterns[pat][trackerpos-math.ceil(h / 2)+1][x]
                    if globalParams.shownColumns.note then
                        if note.note then trackerwin.blit(formatNote(note.note), "bbb", "fff")
                        else trackerwin.blit("---", "000", "fff") end
                        if globalParams.shownColumns.instrument or not globalParams.shownColumns.volume then trackerwin.write(" ") end
                    end
                    if globalParams.shownColumns.instrument then
                        if note.instrument then trackerwin.blit(("%02d"):format(note.instrument):sub(-2), "99", "ff")
                        else trackerwin.blit("--", "00", "ff") end
                        if not globalParams.shownColumns.volume then trackerwin.write(" ") end
                    end
                    if globalParams.shownColumns.volume then
                        if note.volume then trackerwin.blit(volumeString:sub(math.floor(note.volume / 16) + 1, math.floor(note.volume / 16) + 1) .. ("%02d"):format(note.volume >= 0x10 and note.volume < 0x60 and math.min(note.volume - 0x10, 64) or note.volume % 16):sub(-2) .. " ", volumeColor[math.floor(note.volume / 16)]:rep(4), "ffff")
                        elseif note.note and note.instrument and note.note ~= 97 and state.module.instruments[note.instrument] and state.module.instruments[note.instrument].samples[note.note] then trackerwin.blit(("v%02d "):format(state.module.instruments[note.instrument].samples[note.note].volume), "dddd", "ffff")
                        else trackerwin.blit(" -- ", "0000", "ffff") end
                    end
                    if globalParams.shownColumns.effect then
                        if note.effect then trackerwin.blit(formatEffect(note.effect, note.effect_param or 0) .. " ", (note.effect == 0xE and effectColorE[bit32.rshift(note.effect_param or 0, 4)] or (note.effect == 0x21 and effectColorX[bit32.rshift(note.effect_param or 0, 4)] or effectColor[note.effect])):rep(4), "ffff")
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
    term.setCursorPos(cx, cy)
end

local function drawVU(vu)
    local cx, cy = term.getCursorPos()
    for i = scrollPos, #state.channels do
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
    term.setCursorPos(cx, cy)
end

for i,v in ipairs{peripheral.find("speaker")} do state.speakers[i] = {usage = 0, speaker = v} end

local left, right = peripheral.wrap "left", peripheral.wrap "right"
if left and right and peripheral.hasType("left", "speaker") and peripheral.hasType("right", "speaker") then
    if left.setPosition then left.playAudio({0}, 0) left.setPosition(1, 0, 0) end
    if right.setPosition then right.playAudio({0}, 0) right.setPosition(-1, 0, 0) end
else
    left, right = peripheral.find "speaker", nil
    if not left then error("No speaker attached") end
    if left.setPosition then left.setPosition(0, 0, 0) end
end

if globalParams.autoSize then
    if #state.channels * 14 + 4 > w then globalParams.shownColumns.instrument = false end
    if #state.channels * 11 + 4 > w then globalParams.shownColumns.effect = false end
    if #state.channels * 7 + 4 > w then globalParams.shownColumns.volume = false end
    if #state.channels * 4 + 4 > w then
        -- still too small? just show everything and scroll instead
        globalParams.shownColumns.instrument = true
        globalParams.shownColumns.effect = true
        globalParams.shownColumns.volume = true
    end
    cwidth = (globalParams.shownColumns.note and 3 or 0) + (globalParams.shownColumns.volume and 3 or 0) + (globalParams.shownColumns.instrument and 3 or 0) + (globalParams.shownColumns.effect and 4 or 0) + 1
end

local skippedRow = false
local pauseState = nil

local empty_audio = {}
for i = 1, 2400 do empty_audio[i] = 0 end
left.playAudio(empty_audio)
if right then right.playAudio(empty_audio) end

local ok, err = pcall(parallel.waitForAny, function()

while state.order <= #state.module.order do
    trackerpos = state.row - 1
    y = state.row
    redrawScreen(state.module.order[state.order]+1, state.order)
    --scrollScreen(v+1)
    local currentOrder = state.order
    while state.module.order[state.order] < 254 and state.row <= #state.module.patterns[state.module.order[state.order]+1] do
        local currentRow, currentTempo, currentBPM = state.row, state.tempo, state.bpm
        local ls, rs, vu = libtracc.row(state, right ~= nil)
        if not ls or not vu then return end
        if state.tempo ~= currentTempo or state.bpm ~= currentBPM then
            term.setCursorPos(1, 1)
            term.clearLine()
            term.setBackgroundColor(colors.black)
            term.setTextColor(colors.white)
            print("Name:", state.module.name, "Tempo:", state.tempo, "BPM:", state.bpm)
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
        if state.order ~= currentOrder then
            break
        end
        if state.row ~= currentRow + 1 then
            y = state.row
            trackerpos = state.row - 1
            redrawScreen(state.module.order[state.order]+1, state.order)
        else
            scrollScreen(state.module.order[state.order]+1)
        end
    end
    if state.module.order[state.order] and state.module.order[state.order] >= 254 then state.order = state.order + 1 end
    if skippedRow then
        skippedRow = false
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
                        state.row = #state.module.patterns[state.module.order[state.order]]
                    end
                    pauseState = 1
                end
            elseif ch == keys.one then state.mutedChannels[1] = not state.mutedChannels[1] didChangeMuted = true
            elseif ch == keys.two then state.mutedChannels[2] = not state.mutedChannels[2] didChangeMuted = true
            elseif ch == keys.three then state.mutedChannels[3] = not state.mutedChannels[3] didChangeMuted = true
            elseif ch == keys.four then state.mutedChannels[4] = not state.mutedChannels[4] didChangeMuted = true
            elseif ch == keys.five then state.mutedChannels[5] = not state.mutedChannels[5] didChangeMuted = true
            elseif ch == keys.six then state.mutedChannels[6] = not state.mutedChannels[6] didChangeMuted = true
            elseif ch == keys.seven then state.mutedChannels[7] = not state.mutedChannels[7] didChangeMuted = true
            elseif ch == keys.eight then state.mutedChannels[8] = not state.mutedChannels[8] didChangeMuted = true
            elseif ch == keys.nine then state.mutedChannels[9] = not state.mutedChannels[9] didChangeMuted = true
            elseif ch == keys.zero then state.mutedChannels[10] = not state.mutedChannels[10] didChangeMuted = true
            elseif ch == keys.a and scrollPos > 1 then scrollPos = scrollPos - 1 y = state.row trackerpos = state.row - 1 redrawScreen(state.module.order[state.order]+1, state.order)
            elseif ch == keys.d and scrollPos < #state.channels then scrollPos = scrollPos + 1 y = state.row trackerpos = state.row - 1 redrawScreen(state.module.order[state.order]+1, state.order)
            elseif ch == keys.j then
                pauseState = 1
                term.setCursorPos(1, 1)
                term.clearLine()
                term.setBackgroundColor(colors.black)
                term.setTextColor(colors.lightBlue)
                write("Jump to order: ")
                term.setTextColor(colors.white)
                os.pullEvent("char") -- consume key
                local order = tonumber(read())
                if order and order > 0 and order <= #state.module.order then state.order, state.row = order, 1 end
                term.setCursorPos(1, 1)
                term.clearLine()
                term.setBackgroundColor(colors.black)
                term.setTextColor(colors.white)
                print("Name:", state.module.name, "Tempo:", state.tempo, "BPM:", state.bpm)
                pauseState = nil
            end
        elseif ev == "term_resize" then
            w, h = term.getSize()
            h = h - 5
            trackerwin.reposition(1, 6, w, h)
            redrawScreen(state.module.order[state.order]+1, state.order, 1)
        end
        if didChangeMuted then
            term.setCursorPos(1, 4)
            term.setBackgroundColor(colors.gray)
            term.clearLine()
            local cwidth = (globalParams.shownColumns.note and 3 or 0) + (globalParams.shownColumns.volume and 3 or 0) + (globalParams.shownColumns.instrument and 3 or 0) + (globalParams.shownColumns.effect and 4 or 0) + 1
            for i = scrollPos, #state.channels do
                local text = "Channel " .. i
                if cwidth < #text then text = "Ch. " .. i end
                if cwidth < #text then text = tostring(i) end
                term.setCursorPos(cwidth * (i - 1) + 5 + math.floor((cwidth - #text) / 2), 4)
                term.blit(text, (state.mutedChannels[i] and "8" or "0"):rep(#text), ("7"):rep(#text))
            end
        end
    end
end)

term.setCursorPos(1, 1)
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
if ok then term.clear()
else printError(err) end
left.stop()
if right then right.stop() end
