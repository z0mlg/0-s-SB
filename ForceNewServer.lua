-- ForceNewServer.lua
-- Blocks EVERY player in the current server, then teleports back to the same
-- place. Roblox matchmaking refuses to put you in a server containing anyone
-- you blocked, so the current one is permanently excluded; every populated
-- server you land in gets the same treatment until it spawns you a fresh one.
--
-- Re-executes itself on each hop via queue_on_teleport until you land alone.
-- Stop early:  getgenv().ForceNewStop = true  then re-run, or just execute
-- this file again after landing somewhere empty (it self-cleans).

local PLACE = game.PlaceId -- same place we leave; hardcode an id if wanted
local FLAG = 'Bluu_forcenew' -- workspace flag so the re-run knows to continue

local Players = game:GetService('Players')
local StarterGui = game:GetService('StarterGui')
local CoreGui = game:GetService('CoreGui')
local GuiService = game:GetService('GuiService')
local VirtualInputManager = game:GetService('VirtualInputManager')
local TeleportService = game:GetService('TeleportService')
local HttpService = game:GetService('HttpService')
local LocalPlayer = Players.LocalPlayer

local function findBlockModal()
    local overlay = CoreGui:FindFirstChild('FoundationOverlay')
    if overlay then
        local modal = overlay:FindFirstChild('BlockingModalScreen', true)
        if modal and not modal:IsA('ModuleScript') then return modal end
    end
    for _, d in ipairs(CoreGui:GetDescendants()) do
        if d.Name == 'BlockingModalScreen' and not d:IsA('ModuleScript') then
            return d
        end
    end
end

local function findBlockButton(modal)
    for _, label in ipairs(modal:GetDescendants()) do
        if label:IsA('TextLabel') and label.Text == 'Block' then
            local parent = label.Parent
            while parent and parent ~= modal do
                if parent:IsA('GuiButton') then return parent end
                parent = parent.Parent
            end
        end
    end
    local footer = modal:FindFirstChild('Footer', true)
    local buttons = footer and footer:FindFirstChild('Buttons', true)
    return buttons and buttons:FindFirstChild('3')
end

local function clickBlockButton(button)
    if firesignal then
        pcall(firesignal, button.Activated)
        pcall(firesignal, button.MouseButton1Click)
    end
    task.wait(0.3)
    if not findBlockModal() then return end

    GuiService.SelectedCoreObject = button
    GuiService.SelectedObject = button
    task.wait(0.15)
    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Return, false, game)
    task.wait(0.05)
    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Return, false, game)
    task.wait(0.4)
    if not findBlockModal() then return end

    if getconnections then
        for _, c in ipairs(getconnections(button.Activated)) do
            pcall(function() c:Fire() end)
            pcall(function() c.Function(button) end)
        end
    end
    task.wait(0.5)
    if not findBlockModal() then return end

    local pos = button.AbsolutePosition + button.AbsoluteSize / 2
    VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, true, game, 0)
    task.wait(0.05)
    VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, false, game, 0)
    task.wait(0.5)
end

local function isPlayerBlocked(player)
    local ok, blocked = pcall(function()
        return StarterGui:GetCore('GetBlockedUserIds')
    end)
    if not ok then return false end
    if type(blocked) == 'string' then
        local ok2, decoded = pcall(function() return HttpService:JSONDecode(blocked) end)
        blocked = ok2 and decoded or nil
    end
    if type(blocked) ~= 'table' then return false end
    for _, id in next, blocked do
        if tonumber(id) == player.UserId then return true end
    end
    return false
end

local function blockPlayer(player)
    while player.Parent do
        if isPlayerBlocked(player) then return true end
        local modal = findBlockModal()
        if not modal then
            StarterGui:SetCore('PromptBlockPlayer', player)
            for _ = 1, 20 do
                modal = findBlockModal()
                if modal then break end
                task.wait(0.05)
            end
        end
        if modal then
            local button = findBlockButton(modal)
            if button then clickBlockButton(button) end
        end
        task.wait(0.3)
        if isPlayerBlocked(player) then return true end
        task.wait(0.7)
    end
    return true
end

-- landed alone? we're done - a fresh server found us
if getgenv().ForceNewStop then
    getgenv().ForceNewStop = nil
    if isfile and isfile(FLAG) then delfile(FLAG) end
    print('[ForceNew] Stopped')
    return
end

local others = {}
for _, p in next, Players:GetPlayers() do
    if p ~= LocalPlayer then table.insert(others, p) end
end

if #others == 0 then
    if isfile and isfile(FLAG) then delfile(FLAG) end
    print('[ForceNew] Fresh server reached - nobody else here')
    return
end

-- re-run ourselves on the next landing
if writefile and queue_on_teleport then
    if isfolder and not isfolder('Bluu') then makefolder('Bluu') end
    writefile(FLAG, '1')
    queue_on_teleport([[
        if isfile and isfile('Bluu_forcenew') then
            loadstring(game:HttpGet('https://raw.githubusercontent.com/z0mlg/Sb2Cheats/refs/heads/main/ForceNewServer.lua'))()
        end
    ]])
end

print(`[ForceNew] Blocking {#others} player(s), then re-joining place {PLACE}`)

-- block them ALL in parallel: everyone's server becomes unjoinable to us
for _, p in next, others do
    task.spawn(blockPlayer, p)
end

-- leave as soon as half of them confirm (or 15s cap - dead modals happen)
local deadline = tick() + 15
while tick() < deadline do
    local confirmed = 0
    for _, p in next, others do
        if not p.Parent or isPlayerBlocked(p) then confirmed += 1 end
    end
    if confirmed >= math.max(1, math.floor(#others / 2)) then break end
    task.wait(0.5)
end

print('[ForceNew] Hopping - matchmaking must find a server without them')
TeleportService:Teleport(PLACE, LocalPlayer)
