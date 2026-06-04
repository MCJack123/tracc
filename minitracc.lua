local libtracc = require "libtracc"

local state do
    local path = shell.resolve(...)
    if path == nil then error("Usage: minitracc <file>") end
    local file = fs.open(path, "rb")
    local s = file.read(17)
    if s == "Extended Module: " then
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

local function getSpeakers()
    if peripheral.isPresent("left") and peripheral.isPresent("right") and peripheral.hasType("left", "speaker") and peripheral.hasType("right", "speaker") then
        -- CraftOS-PC hack
        pcall(peripheral.call, "left", "setPosition", 1, 0, 0)
        pcall(peripheral.call, "right", "setPosition", -1, 0, 0)
        return peripheral.wrap "left", peripheral.wrap "right"
    else return peripheral.find "speaker" end
end

print("Name:", state.module.name, "Tempo:", state.tempo, "BPM:", state.bpm)
print("Tracker:", state.module.tracker, "Channels:", #state.channels)
print("Playing.")
parallel.waitForAny(
    function() libtracc.play(state, getSpeakers()) end,
    function() repeat local _, c = os.pullEvent("char") until c == "q" end
)
peripheral.find("speaker", function(_, s) s.stop() end)
