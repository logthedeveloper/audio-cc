local dfpwm = require("cc.audio.dfpwm")

-- Automatically find a connected Simple Radio socket or transmitter
local socket = peripheral.find("simpleradio:socket") 
            or peripheral.find("simpleradio:transmitter") 
            or peripheral.find("simpleradio:speaker")

if not socket then
    error("No Simple Radio transmitter/socket found! Ensure it is connected via Wired Modem.")
end

print("Connected to Simple Radio peripheral: " .. peripheral.getName(socket))

-- Tracks preset URLs by name (add your own song URLs here)
local SONGS = {
    ["goldenbrown"] = "https://github.com/logthedeveloper/audio-cc/raw/refs/heads/main/goldenbrown-mono.dfpwm"
}

-- Playback state variables
local currentSong = "goldenbrown"
local isLooping = false
local isPlaying = false
local stopRequested = false

local SEGMENT_SIZE = 960

local function playURL(trackUrl)
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
        -- Immediately break out if a stop command was issued
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

    response.close()
end

-- Task 1: Handles audio streaming execution based on control state
local function audioManager()
    while true do
        if isPlaying and currentSong then
            stopRequested = false
            local trackUrl = SONGS[currentSong] or currentSong

            print("Now playing: " .. currentSong .. (isLooping and " (Looping)" or ""))
            playURL(trackUrl)

            -- If stop wasn't triggered and looping is off, end playback after song finishes
            if not stopRequested and not isLooping then
                isPlaying = false
                print("Playback finished.")
            end
        else
            sleep(0.1) -- Idle until a command sets isPlaying to true
        end
    end
end

-- Task 2: Terminal Command Listener
local function commandListener()
    print("\n--- Audio Control Terminal ---")
    print("Commands:")
    print("  <songname>       : Play song once")
    print("  loop <songname>  : Play song on repeat")
    print("  stop             : Stop current playback")
    print("-----------------------------\n")

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
        
    -- Clear the Simple Radio speaker's internal audio buffer immediately
          if socket.clear then
        socket.clear()
            elseif socket.stop then
                socket.stop()
    end

    print("Playback stopped. Speaker buffer cleared.")

            elseif cmd == "loop" and arg ~= "" then
                local songKey = arg:lower()
                currentSong = SONGS[songKey] and songKey or arg
                isLooping = true
                stopRequested = true -- Cut previous track
                isPlaying = true
                print("Set to loop: " .. currentSong)

            elseif cmd ~= "" then
                -- Check if typed "song <name>" or just "<name>"
                local songKey = (cmd == "song" and arg ~= "") and arg:lower() or input:lower()
                currentSong = SONGS[songKey] and songKey or input
                isLooping = false
                stopRequested = true -- Cut previous track
                isPlaying = true
                print("Playing once: " .. currentSong)
            end
        end
    end
end

-- Run both background playback and input prompt simultaneously
parallel.waitForAny(audioManager, commandListener)
