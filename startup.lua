local dfpwm = require("cc.audio.dfpwm")

-- Automatically find a connected Simple Radio socket, transmitter, or speaker
local socket = peripheral.find("simpleradio:socket") 
            or peripheral.find("simpleradio:transmitter") 
            or peripheral.find("simpleradio:speaker")

if not socket then
    error("No Simple Radio peripheral found! Ensure a socket/transmitter is connected via Wired Modem.")
end

print("Connected to Simple Radio peripheral: " .. peripheral.getName(socket))

-- Preset songs (map key to URL)
local SONGS = {
    ["goldenbrown"] = "https://github.com/logthedeveloper/audio-cc/raw/refs/heads/main/goldenbrown-mono.dfpwm"
}

-- Playback state variables
local currentSong = "goldenbrown"
local isLooping = false
local isPlaying = false
local stopRequested = false

local SEGMENT_SIZE = 960

-- Flushes the speaker's internal hardware buffer by broadcasting digital silence
local function clearSpeakerBuffer()
    local silentSegment = {}
    for i = 1, SEGMENT_SIZE do
        silentSegment[i] = 0
    end
    -- Push several silent frames to overwrite and empty the hardware audio queue
    for _ = 1, 10 do
        socket.route(silentSegment, 1)
    end
end

local function playURL(trackUrl)
    -- Flush existing buffer before playing
    clearSpeakerBuffer()

    local response, err = http.get(trackUrl, nil, true)
    if not response then
        print("Failed to fetch audio: " .. tostring(err))
        return
    end

    local decoder = dfpwm.make_decoder()
    local pending = {}

    local function flushSegments()
        while #pending >= SEGMENT_SIZE do
            local segment = {}
            for i = 1, SEGMENT_SIZE do
                segment[i] = pending[i]
            end
            
            local rest = {}
            for i = SEGMENT_SIZE + 1, #pending do
                rest[#rest + 1] = pending[i]
            end
            pending = rest

            socket.route(segment, 1)
        end
    end

    while true do
        -- Cut audio and exit instantly if stop command was given
        if stopRequested then
            break
        end

        local chunk = response.read(4 * 1024)
        if not chunk then break end

        local pcm8 = decoder(chunk)

        for i = 1, #pcm8 do
            pending[#pending + 1] = pcm8[i] * 256
        end

        flushSegments()
        sleep(0)
    end

    -- Overwrite remaining buffer with silence when stopped
    clearSpeakerBuffer()
    response.close()
end

-- Task 1: Handles continuous audio playback state
local function audioManager()
    while true do
        if isPlaying and currentSong then
            stopRequested = false
            local trackUrl = SONGS[currentSong] or currentSong

            print("\nNow playing: " .. currentSong .. (isLooping and " (Looping)" or ""))
            playURL(trackUrl)

            if not stopRequested and not isLooping then
                isPlaying = false
                print("Playback finished.")
            end
        else
            sleep(0.1)
        end
    end
end

-- Task 2: Terminal input command listener
local function commandListener()
    print("\n==================================")
    print("      RADIO CONTROL STATION       ")
    print("==================================")
    print("Commands:")
    print("  <songname>       : Play song once")
    print("  loop <songname>  : Loop song continuously")
    print("  stop             : Stop playback instantly")
    print("----------------------------------\n")

    while true do
        write("> ")
        local input = read()
        if input then
            local cmd, arg = input:match("^(%S+)%s*(.*)$")
            cmd = cmd and cmd:lower() or ""

            if cmd == "stop" or (cmd == "loop" and arg:lower() == "stop") or (cmd == "song" and arg:lower() == "stop") then
                stopRequested = true
                isPlaying = false
                isLooping = false
                clearSpeakerBuffer()
                print("Playback stopped. Speaker buffer cleared.")

            elseif cmd == "loop" and arg ~= "" then
                local songKey = arg:lower()
                currentSong = SONGS[songKey] and songKey or arg
                isLooping = true
                stopRequested = true
                isPlaying = true
                print("Set to loop: " .. currentSong)

            elseif cmd ~= "" then
                local songKey = (cmd == "song" and arg ~= "") and arg:lower() or input:lower()
                currentSong = SONGS[songKey] and songKey or input
                isLooping = false
                stopRequested = true
                isPlaying = true
                print("Playing once: " .. currentSong)
            end
        end
    end
end

-- Run playback and command listener simultaneously
parallel.waitForAny(audioManager, commandListener)
