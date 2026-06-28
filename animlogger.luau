local repo = "https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/"
local Library      = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager  = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local HttpService  = game:GetService("HttpService")
local LocalPlayer  = Players.LocalPlayer

local LOG_FILE = "deep anim logger.jsonl"

local State = {
    Hooks      = {},
    LogCount   = 0,
}
-- logging
local function writeLog(record)
    State.LogCount = State.LogCount + 1
    local line = HttpService:JSONEncode(record)
    print("[AnimLog] " .. line)
    if appendfile then
        pcall(appendfile, LOG_FILE, line .. "\n")
    end
end

local function snapshotTrack(player, track)
    local animation = track.Animation
    if not animation then return end

    local record = {
        ts        = os.time(),
        player    = player.Name,
        userId    = player.UserId,
        animId    = animation.AnimationId,
        animName  = animation.Name,
        trackName = track.Name,
        length    = track.Length,
        speed     = track.Speed,
        weight    = track.WeightCurrent,
        weightT   = track.WeightTarget,
        looped    = track.Looped,
        priority  = tostring(track.Priority),
        isPlaying = track.IsPlaying,
    }

    local key = player.UserId .. ":" .. animation.AnimationId
    if not Toggles.LogDuplicates.Value then
        if State.Seen[key] then
            local prev = State.Seen[key]
            local speedDelta  = math.abs((prev.speed  or 0) - record.speed)
            local weightDelta = math.abs((prev.weight or 0) - record.weight)
            if speedDelta < 0.1 and weightDelta < 0.1 then
                return
            end
        end
        State.Seen[key] = { speed = record.speed, weight = record.weight }
    end

    writeLog(record)
end

local function bindCharacter(player, character)
    local humanoid = character:WaitForChild("Humanoid", 5)
    if not humanoid then return end

    local animator = humanoid:WaitForChild("Animator", 5)
    if not animator then return end

    local hookData = State.Hooks[player] or { conns = {} }

    local conn = animator.AnimationPlayed:Connect(function(track)
        if not Toggles.Enabled.Value then return end
        if Toggles.LocalOnly.Value and player ~= LocalPlayer then return end
        if not Toggles.LogLocal.Value and player == LocalPlayer then return end

        snapshotTrack(player, track)
        if Toggles.WatchSpeedChange.Value then
            local speedConn = track:GetPropertyChangedSignal("Speed"):Connect(function()
                if math.abs(track.Speed) > 5 then
                    writeLog({
                        ts        = os.time(),
                        player    = player.Name,
                        userId    = player.UserId,
                        animId    = track.Animation.AnimationId,
                        event     = "SPEED_SPIKE",
                        newSpeed  = track.Speed,
                        weight    = track.WeightCurrent,
                    })
                end
            end)
            table.insert(hookData.conns, speedConn)
            
            track.Stopped:Connect(function() speedConn:Disconnect() end)
        end
    end)

    table.insert(hookData.conns, conn)
    hookData.char = character
    State.Hooks[player] = hookData
end

local function bindPlayer(player)
    if State.Hooks[player] then
    else
        State.Hooks[player] = { conns = {} }
    end

    if player.Character then bindCharacter(player, player.Character) end

    local conn = player.CharacterAdded:Connect(function(char)
        bindCharacter(player, char)
    end)
    table.insert(State.Hooks[player].conns, conn)
end

local function unbindPlayer(player)
    local data = State.Hooks[player]
    if not data then return end
    for _, c in ipairs(data.conns) do
        pcall(function() c:Disconnect() end)
    end
    State.Hooks[player] = nil
end


local Window = Library:CreateWindow({
    Title        = "Deep anim logger",
    Center       = true,
    AutoShow     = true,
    TabPadding   = 8,
    MenuFadeTime = 0.2,
})

local Tabs = {
    Main = Window:AddTab("Main"),
    ["UI Settings"] = Window:AddTab("UI Settings"),
}
do
    local Left = Tabs.Main:AddLeftGroupbox("Logging")

    Left:AddToggle("Enabled", {
        Text = "Enable Logging", Default = false,
        Tooltip = "Toggle",
    })

    Left:AddToggle("LocalOnly", {
        Text = "Local Player Only", Default = false,
        Tooltip = "Log your own animations (useful for debugging)",
    })

    Left:AddToggle("LogLocal", {
        Text = "Include Local Player", Default = false,
        Tooltip = "Include your own animations when logging globally",
    })

    Left:AddToggle("LogDuplicates", {
        Text = "Log Duplicates", Default = false,
        Tooltip = "Log every play even if same animId seen before",
    })

    Left:AddToggle("WatchSpeedChange", {
        Text = "Watch Speed Changes", Default = true,
        Tooltip = "Logs mid-animation speed spikes (>5x). AP breaker signature.",
    })

    local Right = Tabs.Main:AddRightGroupbox("Output")

    Right:AddLabel("Log file: " .. LOG_FILE)
    local countLabel = Right:AddLabel("Logged: 0 entries")

    Right:AddButton({
        Text = "Clear Dedupe Cache",
        Func = function()
            State.Seen = {}
            Library:Notify("Dedupe cache cleared — duplicates will re-log", 2)
        end,
    })

    Right:AddButton({
        Text = "Delete Log File",
        Func = function()
            if delfile then
                pcall(delfile, LOG_FILE)
                State.LogCount = 0
                Library:Notify("Log file deleted", 2)
            end
        end,
    })

    Right:AddButton({
        Text = "Open Log Folder",
        Func = function()
            if getcustomasset then
                print("[AnimLog] File at workspace/" .. LOG_FILE)
            end
            Library:Notify("Log saved to executor workspace folder", 3)
        end,
    })

    task.spawn(function()
        while Library and not Library.Unloaded do
            countLabel:SetText("Logged: " .. State.LogCount .. " entries")
            task.wait(1)
        end
    end)
end

do
    local Menu = Tabs["UI Settings"]:AddLeftGroupbox("Menu")
    Menu:AddButton({ Text = "Unload", Func = function()
        for player, _ in pairs(State.Hooks) do unbindPlayer(player) end
        Library:Unload()
    end })
    Menu:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind", {
        Default = "End", NoUI = true, Text = "Menu keybind",
    })
    Library.ToggleKeybind = Options.MenuKeybind

    ThemeManager:SetLibrary(Library)
    SaveManager:SetLibrary(Library)
    SaveManager:IgnoreThemeSettings()
    SaveManager:SetIgnoreIndexes({ "MenuKeybind" })
    ThemeManager:SetFolder("DWAnimLogger")
    SaveManager:SetFolder("DWAnimLogger")
    SaveManager:BuildConfigSection(Tabs["UI Settings"])
    ThemeManager:ApplyToTab(Tabs["UI Settings"])
    SaveManager:LoadAutoloadConfig()
end

for _, p in ipairs(Players:GetPlayers()) do bindPlayer(p) end
Players.PlayerAdded:Connect(bindPlayer)
Players.PlayerRemoving:Connect(unbindPlayer)

Library:Notify("Deep anim logger", 3)
