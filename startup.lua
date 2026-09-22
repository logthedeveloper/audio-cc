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

-- Safely clears the speaker block's internal buffer
local function clearSpeakerBuffer()
    if socket.clear then
        socket.clear()
    elseif socket.stop then
        socket.stop()
    end
end

local function playURL(trackUrl)
    -- Wipe any leftover audio sitting in the speaker before starting
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
        -- Cut audio and break instantly if stop was requested
        if stopRequested then
            clearSpeakerBuffer()
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

    -- Clear remaining buffer state upon exit
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

            -- If the song finishes naturally and loop is disabled, stop playback
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
                print("Playback stopped. Microphone clear.")

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
