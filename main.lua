-- Bluu - Swordburst 2 (modular build)
-- Usage:  loadstring(game:HttpGet('https://raw.githubusercontent.com/z0mlg/Sb2Cheats/refs/heads/main/main.lua'))()
SCRIPT_BASE = 'https://raw.githubusercontent.com/z0mlg/Sb2Cheats/refs/heads/main/'

-- Dev mode: load modules from disk instead of GitHub (needs readfile)
DEV_LOCAL = false
DEV_PATH = 'E:/Roblox GUI/VapeV4/Sb2Cheats/'

if getgenv().Bluu then
    -- Flag left over from a dead/crashed run (GUI is gone): clear it and continue
    if game:GetService('CoreGui'):FindFirstChild('Obsidian') then
        warn('[Bluu] Already running - unload it first (Settings > Unload)')
        return
    end
    warn('[Bluu] Stale flag from a previous run, re-executing')
end
getgenv().Bluu = true

if not game:IsLoaded() then
    game.Loaded:Wait()
end

if game.GameId ~= 212154879 then -- Swordburst 2
    warn('[Bluu] Not in Swordburst 2 - aborting')
    return
end

Function = game:GetService('ReplicatedStorage'):WaitForChild('Function')

-- The Between: wave-defense party place. Everyone in the server is your party,
-- and the field empties between waves - player/empty-server logic must not run.
BETWEEN_PLACE = 78945654064532
IN_BETWEEN = game.PlaceId == BETWEEN_PLACE

-- ===================== OML AUTO FARM CONFIG =====================
OML_FARM_PLACE = 573267292    -- Floor 9 / Va' Rok (where we farm)
OML_RELOAD_PLACE = 659222129  -- Main menu / hub (teleport here to reload + repeat)
-- Raw URL where THIS OML Farm script is hosted. Used to re-run it after each teleport so the
-- farm -> hub -> farm loop keeps the mob automation. Leave '' if you run the file via autoexec.
local OML_SCRIPT_URL = SCRIPT_BASE .. 'main.lua'

-- Re-queue OML after every teleport. Set BEFORE the hub check so even when we bounce through
-- the hub, OML re-runs once we land back on the floor.
local queue_on_teleport = queue_on_teleport or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)
if queue_on_teleport and OML_SCRIPT_URL ~= '' then
    queue_on_teleport(`loadstring(game:HttpGet('{OML_SCRIPT_URL}'))()`)
end

if game.PlaceId == OML_RELOAD_PLACE then -- Main menu: log in to bounce back to our floor
    print('[Bluu] Hub world - logging in to return to the floor')
    Function:InvokeServer('Login')
    return
end

getgenv().BluuRejoining = nil -- fresh join: rejoin failsafe is armed again

-- ===================== STUCK-JOIN FAILSAFE =====================
-- If the game's own client init dies (e.g. CardinalClient.LoadingScreen
-- errors) the load never finishes and the WaitForChild chain below hangs
-- forever. On a matching console error, or if bootstrap still isn't done
-- after ~75s, save our floor+position and bounce through the hub into a
-- fresh server.
local joinStart = tick()

local rejoinFreshServer
rejoinFreshServer = function()
    if getgenv().BluuRejoining then return end
    getgenv().BluuRejoining = true
    warn('[Bluu] Join failed - rejoining a fresh server')
    pcall(function()
        if not (isfolder and writefile and HumanoidRootPart) then return end
        if not isfolder('Bluu') then makefolder('Bluu') end
        if not isfolder('Bluu/Swordburst 2') then makefolder('Bluu/Swordburst 2') end
        local pos = HumanoidRootPart.Position
        writefile('Bluu/Swordburst 2/serverswitch', game:GetService('HttpService'):JSONEncode({
            active = true,
            targetPlace = game.PlaceId,
            position = { x = pos.X, y = pos.Y, z = pos.Z },
        }))
    end)
    for _ = 1, 2 do
        local ok = pcall(function()
            game:GetService('TeleportService'):Teleport(659222129, LocalPlayer)
        end)
        if ok then return end
        task.wait(15)
    end
end

-- game-init crashes surface in the console; only fresh-join errors count
game:GetService('LogService').MessageOut:Connect(function(message, messageType)
    if tick() - joinStart > 120 then return end
    if messageType ~= Enum.MessageType.MessageError then return end
    if message:find('Cardinal') or message:find('LoadingScreen') then
        task.spawn(rejoinFreshServer)
    end
end)

-- bootstrap watchdog: Profile + Entity must exist within ~75s or we're stuck
task.spawn(function()
    local RS = game:GetService('ReplicatedStorage')
    for _ = 1, 15 do
        task.wait(5)
        local character = LocalPlayer and LocalPlayer.Character
        local profiles = RS:FindFirstChild('Profiles')
        if profiles and LocalPlayer and profiles:FindFirstChild(LocalPlayer.Name)
            and character and character:FindFirstChild('Entity') then
            return -- joined fine
        end
    end
    rejoinFreshServer()
end)

sendWebhook = (function()
    local http_request = (syn and syn.request) or (fluxus and fluxus.request) or http_request or request
    local HttpService = game:GetService('HttpService')

    return function(url, body, ping)
        assert(type(url) == 'string')
        assert(type(body) == 'table')
        if not string.match(url, '^https://discord') then return end

        body.content = ping and '@everyone' or nil
        body.username = 'Bluu'
        body.avatar_url = 'https://raw.githubusercontent.com/Neuublue/Bluu/main/Bluu.png'

        local embed = type(body.embeds) == 'table' and body.embeds[1]
        if embed then
            embed.timestamp = DateTime:now():ToIsoDate()
            embed.footer = {
                text = 'Bluu',
                icon_url = body.avatar_url
            }
        end

        http_request({
            Url = url,
            Body = HttpService:JSONEncode(body),
            Method = 'POST',
            Headers = { ['content-type'] = 'application/json' }
        })
    end
end)()

Players = game:GetService('Players')
LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    Players:GetPropertyChangedSignal('LocalPlayer'):Wait()
    LocalPlayer = Players.LocalPlayer
end
Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
Humanoid = Character:WaitForChild('Humanoid')
HumanoidRootPart = Character:WaitForChild('HumanoidRootPart')

Entity = Character:WaitForChild('Entity')
Health = Entity:WaitForChild('Health')
Stamina = Entity:WaitForChild('Stamina')

Camera = workspace.CurrentCamera
if not Camera then
    workspace:GetPropertyChangedSignal('CurrentCamera'):Wait()
    Camera = workspace.CurrentCamera
end

Profiles = game:GetService('ReplicatedStorage'):WaitForChild('Profiles')
Profile = Profiles:WaitForChild(LocalPlayer.Name)

MySkills = Profile:WaitForChild('Skills')
Inventory = Profile:WaitForChild('Inventory')
-- removed from profiles in the October update: optional, never block on it
AnimPacks = Profile:WaitForChild('AnimPacks', 5)
Equip = Profile:WaitForChild('Equip')

Exp = Profile:WaitForChild('Stats'):WaitForChild('Exp')
getLevel = function(value)
    return math.floor((value or Exp.Value) ^ (1/3))
end
Vel = Exp.Parent:WaitForChild('Vel')

Database = game:GetService('ReplicatedStorage'):WaitForChild('Database')
Items = Database:WaitForChild('Items')
Skills = Database:WaitForChild('Skills')

Event = game:GetService('ReplicatedStorage'):WaitForChild('Event')
InvokeFunction = function(...)
    local success, result
    while not success do
        success, result = pcall(Function.InvokeServer, Function, ...)
        if not success then task.wait() end
    end
    return result
end

PlayerUI = LocalPlayer:WaitForChild('PlayerGui'):WaitForChild('CardinalUI'):WaitForChild('PlayerUI')
Level = PlayerUI:WaitForChild('HUD'):WaitForChild('LevelBar'):WaitForChild('Level')
Chat = PlayerUI:WaitForChild('Chat')

Mobs = workspace:WaitForChild('Mobs')

RunService = game:GetService('RunService')
RenderStepped = RunService.RenderStepped
Stepped = RunService.Stepped

UserInputService = game:GetService('UserInputService')
MarketplaceService = game:GetService('MarketplaceService')
StarterGui = game:GetService('StarterGui')

pcall(function()
    for _, connection in getconnections(LocalPlayer.Idled) do
        connection:Disable()
    end
end)
LocalPlayer.Idled:Connect(function()
    game:GetService('VirtualUser'):ClickButton2(Vector2.new())
end)

if workspace:GetAttribute('DungeonFloor') then
    Event:FireServer('UniqueFloorTypes', { 'Dungeons', 'Start' })
end

local identifyexecutor = identifyexecutor or getexecutorname or function() return 'Unknown' end

RequiredServices = (function()
    if identifyexecutor() == 'Xeno' then -- fuck you
        StarterGui:SetCore('SendNotification', {
            Title = 'Xeno is bad',
            Text = 'please stop using this piece of shit'
        })
        return
    end
    local methods = {}
    methods[1] = function()
        local RequiredServices
        for _, func in next, { getgc, getreg } do
            if type(func) ~= 'function' then
                continue
            end
            for _, object in next, select(2, pcall(func, true)) do
                if type(object) ~= 'table' then
                    continue
                end
                local Services = rawget(object, 'Services')
                if Services and rawget(Services, 'Combat') then
                    RequiredServices = Services
                    break
                end
            end
            if RequiredServices then
                break
            end
        end
        if not RequiredServices then return end
        local UISafeInit = RequiredServices.UI.SafeInit
        RequiredServices.InventoryUI = debug.getupvalue(UISafeInit, 18)
        RequiredServices.StatsUI = debug.getupvalue(UISafeInit, 40)
        RequiredServices.TradeUI = debug.getupvalue(UISafeInit, 31)
        return RequiredServices
    end
    methods[2] = function()
        local MainModule
        for _, func in next, { getloadedmodules, getnilinstances } do
            if type(func) ~= 'function' then
                continue
            end
            for _, instance in next, select(2, pcall(func)) do
                if instance.Name == 'MainModule' and instance:FindFirstChild('Services') then
                    MainModule = instance
                    break
                end
            end
            if MainModule then
                break
            end
        end
        if not MainModule then return end
        local require = require or getrenv().require
        local RequiredServices = require(MainModule).Services
        local UI = MainModule.Services.UI
        RequiredServices.InventoryUI = require(UI.Inventory)
        RequiredServices.StatsUI = require(UI.Stats)
        RequiredServices.TradeUI = require(UI.Trade)
        return RequiredServices
    end
    for _, method in methods do
        local success, RequiredServices = pcall(method)
        if success and type(RequiredServices) == 'table' then
            return RequiredServices
        end
    end
end)()

UIRepo = 'https://raw.githubusercontent.com/Neuublue/Obsidian/main/'
Library = loadstring(game:HttpGet(UIRepo .. 'Library.lua'))()

Options = Library.Options
Toggles = Library.Toggles

local lastUpdated = (function()
    local success, result = pcall(function()
        local latestCommit = 'https://api.github.com/repos/Neuublue/Bluu/commits?path=Swordburst2.lua&page=1&per_page=1'
        local isoDate = game:GetService('HttpService'):JSONDecode(game:HttpGet(latestCommit))[1].commit.committer.date
        return DateTime.fromIsoDate(isoDate):FormatLocalTime('l', 'en-us')
    end)
    return success and result or 'unknown'
end)()

Window = Library:CreateWindow({
    Title = 'Bluu',
	Footer = 'Swordburst 2 | discord.gg/nKQp6VqzJF | Updated ' .. lastUpdated,
    Center = true,
    AutoShow = true,
    ToggleKeybind = Enum.KeyCode.End,
    NotifySide = 'Left',
    ShowCustomCursor = false,
    -- CornerRadius = 0,
    Icon = 166652117,
    Resizable = true,
    MobileButtonsSide = 'Right',
    -- TabPadding = 8,
    -- MenuFadeTime = 0.1,
    Size = UDim2.fromOffset(700, 500)
})

Main = Window:AddTab('Main', 'user')

-- Helper function to check if entity is dead
isDead = function(entity)
    return not (
        entity
        and entity.Parent
        and entity:FindFirstChild('HumanoidRootPart')
        and entity:FindFirstChild('Entity')
        and entity.Entity:FindFirstChild('Health')
        and entity.Entity.Health.Value > 0
        and (
            not entity.Entity:FindFirstChild('HitLives')
            or entity.Entity.HitLives.Value > 0
        )
    )
end

-- Waypoint System Tab
WaypointsTab = Window:AddTab('Waypoints', 'map-pin')
linearVelocity = Instance.new('LinearVelocity')
linearVelocity.MaxForce = math.huge

KillauraSkill = {}

awaitEventTimeout = function(event, callback, timeout, yield)
    local signal = Instance.new('BoolValue')
    local connection
    connection = event:Connect(function(...)
        if callback and not callback(...) then return end
        signal.Value = true
    end)
    if type(timeout) == 'number' then
        task.delay(timeout, function()
            signal.Value = true
        end)
    end
    local await = function()
        signal:GetPropertyChangedSignal('Value'):Wait()
        connection:Disconnect()
        signal:Destroy()
    end
    if yield == false then task.spawn(await) else await() end
end

local lastDeathCFrame

local CharacterItems = workspace:WaitForChild("CharacterItems")
local myCharacterItems = CharacterItems:WaitForChild(LocalPlayer.UserId)

local swingDamageEnabled = true
toggleSwingDamage = function(value)
    swingDamageEnabled = value

    local RightWeapon = myCharacterItems:FindFirstChild('RightWeapon')
    if RightWeapon and RightWeapon:FindFirstChild('Tool') and RightWeapon.Tool:FindFirstChild('Blade') then
        RightWeapon.Tool.Blade.CanTouch = value
    else
        return
    end

    local LeftWeapon = myCharacterItems:FindFirstChild('LeftWeapon')
    if LeftWeapon and LeftWeapon:FindFirstChild('Tool') and LeftWeapon.Tool:FindFirstChild('Blade') then
        LeftWeapon.Tool.Blade.CanTouch = value
    end
end

myCharacterItems.ChildAdded:Connect(function(child)
    if child.Name == 'RightWeapon' or child.Name == 'LeftWeapon' then
        child:WaitForChild('Tool', 1e6):WaitForChild('Blade', 1e6).CanTouch = swingDamageEnabled
    end
end)
toggleSwingDamage(swingDamageEnabled)

noviceArmor = nil

local onHumanoidAdded = function()
    Humanoid.Died:Connect(function()
        lastDeathCFrame = HumanoidRootPart.CFrame

        -- Snapshot states BEFORE anything disables them
        local hadAutofarm = Toggles.Autofarm and Toggles.Autofarm.Value
        local hadKillaura = Toggles.Killaura and Toggles.Killaura.Value

        if Toggles.DisableOnDeath.Value then
            if hadAutofarm then
                Toggles.Autofarm:SetValue(false)
                if hadKillaura then
                    Toggles.Killaura:SetValue(false)
                end
            end
        end
    end)

    Humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)

    HumanoidRootPart:GetPropertyChangedSignal('Anchored'):Connect(function()
        if HumanoidRootPart.Anchored then
            HumanoidRootPart.Anchored = false
        end
    end)

    linearVelocity.Attachment0 = HumanoidRootPart:WaitForChild('RootAttachment')

    Stamina.Changed:Connect(function(value)
        if not Toggles.ResetOnLowStamina.Value then return end
        if not KillauraSkill.Active and value < KillauraSkill.Cost then
            Humanoid.Health = 0
        end
    end)

    if lastDeathCFrame and Toggles.ReturnOnDeath.Value then
        HumanoidRootPart.CFrame = lastDeathCFrame
    end
    lastDeathCFrame = nil

    if Toggles.FreeCommonCrystals and Toggles.FreeCommonCrystals.Value then
        Event:FireServer(
            "Equipment", {
                "Dismantle",
                { noviceArmor }
            }
        )
        Humanoid.Health = 0
    end
end

onHumanoidAdded()

LocalPlayer.CharacterAdded:Connect(function(newCharacter)
    lastDeathCFrame = lastDeathCFrame or HumanoidRootPart.CFrame
    Character = newCharacter
    HumanoidRootPart = Character:WaitForChild('HumanoidRootPart') -- first: it exists before Humanoid does

    -- INSTANT TELEPORT - as soon as HumanoidRootPart exists
    if lastDeathCFrame and Toggles.ReturnOnDeath.Value then
        HumanoidRootPart.CFrame = lastDeathCFrame

        -- Keep forcing teleport for a second to override spawn location
        local deathCFrame = lastDeathCFrame
        task.spawn(function()
            local teleportUntil = tick() + 1
            while tick() < teleportUntil do
                HumanoidRootPart.CFrame = deathCFrame
                task.wait()
            end
        end)
    end

    Humanoid = Character:WaitForChild('Humanoid')
    
    Entity = Character:WaitForChild('Entity', 2)
    if not Entity then
        Humanoid.Health = 0
        return
    end
    Health = Entity:WaitForChild('Health')
    Stamina = Entity:WaitForChild('Stamina')
    onHumanoidAdded()
end)

toggleLerp = (function()
    local lerpToggles = {}
    return function(changedToggle)
        if changedToggle then
            if not lerpToggles[changedToggle] then
                lerpToggles[changedToggle] = changedToggle
            end
            if not changedToggle.Value then return end
        end

        local disabledToggle

        for _, toggle in next, lerpToggles do
            if toggle == changedToggle then continue end
            if not toggle.Value then continue end
            disabledToggle = toggle
            toggle:SetValue(false)
        end

        return disabledToggle
    end
end)()

enableLinearVelocity = function(enable)
    linearVelocity.Parent = enable and workspace or nil
end

toggleNoclip = (function()
    local noclipConnection
    local noclipToggles = {}
    return function(changedToggle)
        if changedToggle and not noclipToggles[changedToggle] then
            noclipToggles[changedToggle] = changedToggle
        end

        for _, toggle in next, noclipToggles do
            if not toggle.Value then continue end
            if noclipConnection then return end
            noclipConnection = Stepped:Connect(function()
                for _, child in next, Character:GetChildren() do
                    if not child:IsA('BasePart') then continue end
                    child.CanCollide = false
                end
            end)
            return
        end

        if noclipConnection then
            noclipConnection:Disconnect()
            noclipConnection = nil
        end
    end
end)()

waypoint = Instance.new('Part')
waypoint.Anchored = true
waypoint.CanCollide = false
waypoint.Transparency = 1
waypoint.Parent = workspace
local waypointBillboard = Instance.new('BillboardGui')
waypointBillboard.Size = UDim2.new(0, 200, 0, 200)
waypointBillboard.AlwaysOnTop = true
waypointBillboard.Parent = waypoint
waypointLabel = Instance.new('TextLabel')
waypointLabel.BackgroundTransparency = 1
waypointLabel.Size = waypointBillboard.Size
waypointLabel.Font = Enum.Font.Arial
waypointLabel.TextSize = 16
waypointLabel.TextColor3 = Color3.new(1, 1, 1)
waypointLabel.TextStrokeTransparency = 0
waypointLabel.Text = 'Waypoint position'
waypointLabel.TextWrapped = false
waypointLabel.Visible = false
waypointLabel.Parent = waypointBillboard

controls = { W = 0, S = 0, D = 0, A = 0 }

UserInputService.InputBegan:Connect(function(key, gameProcessed)
    if gameProcessed or not controls[key.KeyCode.Name] then return end
    controls[key.KeyCode.Name] = 1
end)

UserInputService.InputEnded:Connect(function(key, gameProcessed)
    if gameProcessed or not controls[key.KeyCode.Name] then return end
    controls[key.KeyCode.Name] = 0
end)

-- ===================== BLOCK ENGINE =====================
-- global so the join gate AND modules (panic, server hop, mod kicks) share it
local CoreGui = game:GetService('CoreGui')
GuiService = GuiService or game:GetService('GuiService')
local VirtualInputManager = game:GetService('VirtualInputManager')

local findBlockModal = function()
    local overlay = CoreGui:FindFirstChild('FoundationOverlay')
    if overlay then
        local modal = overlay:FindFirstChild('BlockingModalScreen', true)
        if modal and not modal:IsA('ModuleScript') then return modal end
    end
    for _, descendant in ipairs(CoreGui:GetDescendants()) do
        if descendant.Name == 'BlockingModalScreen' and not descendant:IsA('ModuleScript') then
            return descendant
        end
    end
end

local findBlockButton = function(modal)
    for _, label in ipairs(modal:GetDescendants()) do
        if label:IsA('TextLabel') and label.Text == 'Block' then
            local parent = label.Parent
            while parent and parent ~= modal do
                if parent:IsA('GuiButton') then return parent end
                parent = parent.Parent
            end
        end
    end
    -- Footer stack order: Cancel = 1, BlockAndReport = 2, Block = 3
    local footer = modal:FindFirstChild('Footer', true)
    local buttons = footer and footer:FindFirstChild('Buttons', true)
    return buttons and buttons:FindFirstChild('3')
end

local clickBlockButton = function(button)
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
        for _, connection in ipairs(getconnections(button.Activated)) do
            pcall(function() connection:Fire() end)
            pcall(function() connection.Function(button) end)
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

isPlayerBlocked = function(player)
    local ok, blocked = pcall(function()
        return StarterGui:GetCore('GetBlockedUserIds')
    end)
    return ok and type(blocked) == 'table' and table.find(blocked, player.UserId) ~= nil
end

blockPlayer = function(player)
    -- retries until the block is verified server-side; stops if the target
    -- leaves (nothing left to block). 5s between each attempt.
    while player.Parent do
        if isPlayerBlocked(player) then return true end

        StarterGui:SetCore('PromptBlockPlayer', player)

        local modal
        for _ = 1, 50 do
            modal = findBlockModal()
            if modal then break end
            task.wait(0.1)
        end

        if modal then
            local button = findBlockButton(modal)
            if button then
                clickBlockButton(button)
            end
        end

        task.wait(0.5)
        if isPlayerBlocked(player) then return true end

        task.wait(5)
    end
    return true -- target left: nothing left to block
end

-- ===================== JOIN GATE =====================
-- While RestartServer is on, landing on a populated server is a no-go: block
-- every non-exempt player BEFORE modules/autofarm ever start, then bounce back
-- through the hub into a fresh server. Repeats until we land somewhere empty.
-- Zero exemptions: every non-local player counts, friends included.
-- flag is per-account (restartgate_<UserId>): the executor workspace is shared
-- by every account, so a single file would arm the gate for all of them
RESTART_GATE_FILE = `Bluu/Swordburst 2/restartgate_{LocalPlayer.UserId}`
pcall(function() -- legacy shared flag armed every account - remove it
    if isfile and isfile('Bluu/Swordburst 2/restartgate') then delfile('Bluu/Swordburst 2/restartgate') end
end)
local joinGateArmed = (function()
    if IN_BETWEEN then return false end -- the other players are your party
    if not (isfile and readfile) or not isfile(RESTART_GATE_FILE) then return false end
    local ok, flag = pcall(readfile, RESTART_GATE_FILE)
    return ok and flag == '1'
end)()

local isGateExempt = function(player)
    -- restart gate: EVERYONE else is a threat - no friend/whitelist exemptions
    return player == LocalPlayer
end

local lastGateTeleport
local joinGateBlockAndHop = function()
    -- if modules/autoload already spun automation up, kill it before blocking
    -- (same suspicious-toggle list as the panic sweep: attacks + movement)
    if Toggles then
        for _, name in next, {
            'Autofarm', 'Killaura', 'KillauraSwing', 'UseSkillPreemptively',
            'AttackPlayers', 'SendTrades', 'EnablePathFarming', 'Autowalk',
            'Pathfind', 'Fly', 'Noclip', 'ClickTeleport', 'DodgeAttacks',
            'ReturnOnDeath', 'ResetOnLowStamina', 'AutoJoinNewFloor',
            'GoToPlayer', 'EmergencyEscape',
        } do
            local t = Toggles[name]
            if t and t.Value then pcall(function() t:SetValue(false) end) end
        end
    end
    for _, p in next, Players:GetPlayers() do
        if not isGateExempt(p) then
            blockPlayer(p)
            task.wait(5)
        end
    end
    pcall(function()
        if writefile and isfolder and HumanoidRootPart then
            if not isfolder('Bluu') then makefolder('Bluu') end
            if not isfolder('Bluu/Swordburst 2') then makefolder('Bluu/Swordburst 2') end
            local pos = HumanoidRootPart.Position
            writefile('Bluu/Swordburst 2/serverswitch', game:GetService('HttpService'):JSONEncode({
                active = true,
                targetPlace = game.PlaceId,
                position = { x = pos.X, y = pos.Y, z = pos.Z },
            }))
        end
    end)
    pcall(function()
        if lastGateTeleport and tick() - lastGateTeleport < 30 then return end
        lastGateTeleport = tick()
        game:GetService('TeleportService'):Teleport(659222129, LocalPlayer)
    end)
end

if joinGateArmed then
    -- hold module loading hostage until the server is empty
    while true do
        local offenders = {}
        for _, p in next, Players:GetPlayers() do
            if not isGateExempt(p) then table.insert(offenders, p) end
        end
        if #offenders == 0 then break end
        warn(`[Bluu] Join gate: {#offenders} player(s) here - blocking and re-hopping`)
        joinGateBlockAndHop()
        task.wait(5) -- if the teleport didn't fire yet, re-evaluate
    end

    -- keep watching for the first 20s while modules/autoload spin up: anyone
    -- who joins gets the same treatment so we never farm in front of them
    task.spawn(function()
        local deadline = tick() + 20
        while tick() < deadline do
            task.wait(0.5)
            for _, p in next, Players:GetPlayers() do
                if not isGateExempt(p) then
                    warn('[Bluu] Join gate: late joiner - blocking and re-hopping')
                    joinGateBlockAndHop()
                    return
                end
            end
        end
    end)
end

-- ===================== MODULE LOADER =====================
-- Modules run as plain chunks that share this script's global env.
local MODULES = {
    'Waypoints', 'Autofarm', 'Autowalk', 'Killaura', 'Cheats', 'Misc',
    'ModsKicks', 'ServerHop', 'Items', 'DropsSwing', 'Crystals', 'ESP', 'TheBetween',
    'Settings',
    -- 'OMLFarm', -- floor-9 farm -> hub -> farm loop (disabled)
}

local function loadModule(name)
    local src
    if DEV_LOCAL and readfile then
        src = readfile(DEV_PATH .. 'Modules/' .. name .. '.lua')
    else
        src = game:HttpGet(SCRIPT_BASE .. 'Modules/' .. name .. '.lua')
    end
    local chunk, err = loadstring(src, '@Bluu/' .. name)
    assert(chunk, `[Bluu] failed to compile {name}: {err}`)
    local ok, rerr = pcall(chunk)
    assert(ok, `[Bluu] {name} crashed: {rerr}`)
end

for _, moduleName in ipairs(MODULES) do
    loadModule(moduleName)
end
