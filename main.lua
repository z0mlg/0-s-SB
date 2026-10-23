-- Bluu - Swordburst 2 (modular build)
-- Usage:  loadstring(game:HttpGet('https://raw.githubusercontent.com/z0mlg/Sb2Cheats/refs/heads/main/main.lua'))()
SCRIPT_BASE = 'https://raw.githubusercontent.com/z0mlg/Sb2Cheats/refs/heads/main/'

-- Dev mode: load modules from disk instead of GitHub (needs readfile)
DEV_LOCAL = false
DEV_PATH = 'E:/Roblox GUI/VapeV4/Sb2Cheats/'

-- Runs spawned by our own queue_on_teleport carry this flag. 'Auto execute' off
-- (also written by Unload) makes queued copies die here instead of re-running
-- on every floor join; manual executes always run.
local AUTOEXEC_FILE = 'Bluu/Swordburst 2/autoexec'
local autoexecOff = false
pcall(function()
    autoexecOff = isfile and isfile(AUTOEXEC_FILE) and readfile(AUTOEXEC_FILE) == 'false'
end)
if getgenv().BluuQueued then
    getgenv().BluuQueued = nil
    if autoexecOff then return end
end

if getgenv().Bluu then
    -- Block while a run is alive: GUI exists once loaded, BluuLoading covers
    -- the load window before it. Only a flag BOTH old and GUI-less is stale
    -- (crashed run) - that one clears so re-execute still works.
    local loading = getgenv().BluuLoading and (os.clock() - getgenv().BluuLoading < 120)
    if loading or game:GetService('CoreGui'):FindFirstChild('Obsidian') then
        warn('[Bluu] Already running - unload it first (Settings > Unload)')
        return
    end
    warn('[Bluu] Stale flag from a previous run, re-executing')
end
getgenv().Bluu = true
getgenv().BluuLoading = os.clock()
BluuCleanups = {} -- modules register unload cleanup fns; Settings > Unload runs them

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
if queue_on_teleport and OML_SCRIPT_URL ~= '' and not autoexecOff then
    queue_on_teleport(`getgenv().BluuQueued = true; loadstring(game:HttpGet('{OML_SCRIPT_URL}'))()`)
end

if game.PlaceId == OML_RELOAD_PLACE then -- Arcadia 'hub' - a transit stop, not a place to farm
    print('[Bluu] Hub world - logging in')
    Function:InvokeServer('Login')
    -- Login alone may bounce us back to our floor; only if we're still parked
    -- on Arcadia after giving it time do we fall back to the remote resume.
    -- (modules never load here - this block is the only resume path)
    task.spawn(function()
        task.wait(10)
        if game.PlaceId ~= OML_RELOAD_PLACE then return end -- Login moved us already
        local cfg
        pcall(function()
            for _, file in next, { 'Bluu/Swordburst 2/serverswitch', 'Bluu/Swordburst 2/emptyserver' } do
                if isfile and isfile(file) then
                    local c = game:GetService('HttpService'):JSONDecode(readfile(file))
                    if c and c.active and c.targetPlace and c.targetPlace ~= OML_RELOAD_PLACE then
                        cfg = c
                        break
                    elseif c and c.targetPlace == OML_RELOAD_PLACE and delfile then
                        delfile(file) -- poisoned by an old hub write - dead config
                    end
                end
            end
        end)
        if not cfg then return end -- manual hub visit - nothing saved to resume
        print('[Bluu] Resuming floor:', cfg.targetPlace)
        while game.PlaceId == OML_RELOAD_PLACE do
            pcall(function()
                Function:InvokeServer('Teleport', { 'Teleport', cfg.targetPlace })
            end)
            task.wait(4)
        end
    end)
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
            at = os.time(),
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

-- did the game's own bootstrap actually fail? (profile + entity present = fine)
local bootstrapAlive = function()
    local profiles = game:GetService('ReplicatedStorage'):FindFirstChild('Profiles')
    local character = LocalPlayer and LocalPlayer.Character
    return profiles and profiles:FindFirstChild(LocalPlayer.Name) ~= nil
        and character and character:FindFirstChild('Entity') ~= nil
end

-- game-init crashes surface in the console; only fresh-join errors count, and
-- even then only rejoin if bootstrap really is dead - every game script lives
-- under CardinalClient, so mid-game errors mentioning it are NOT stuck joins
game:GetService('LogService').MessageOut:Connect(function(message, messageType)
    if tick() - joinStart > 120 then return end
    if messageType ~= Enum.MessageType.MessageError then return end
    if not (message:find('Cardinal') or message:find('LoadingScreen')) then return end
    task.spawn(function()
        task.wait(10) -- give the init chain a moment to finish on its own
        if not bootstrapAlive() then rejoinFreshServer() end
    end)
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
getgenv().BluuLoading = nil -- window exists: GUI check covers the guard from here

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
    if not ok then return false end
    -- some cores hand it back as a JSON string instead of a table
    if type(blocked) == 'string' then
        local ok2, decoded = pcall(function()
            return game:GetService('HttpService'):JSONDecode(blocked)
        end)
        blocked = ok2 and decoded or nil
    end
    if type(blocked) ~= 'table' then return false end
    for _, id in next, blocked do
        if tonumber(id) == player.UserId then return true end
    end
    return false
end

-- don't hop until every target is confirmed in the server-side blocklist (or
-- has left - nothing to block). Capped so a dead modal can't seat us forever.
waitAllBlocked = function(targets, timeout)
    local deadline = tick() + (timeout or 15)
    while tick() < deadline do
        local pending = false
        for _, p in next, targets do
            if p.Parent and not isPlayerBlocked(p) then
                pending = true
                break
            end
        end
        if not pending then return true end
        task.wait(0.2)
    end
    return false
end

blockPlayer = function(player)
    -- retries until the block is verified server-side; stops if the target
    -- leaves (nothing left to block). Tight pacing: we want the verified block
    -- fast so whoever called us can hop before we're seen.
    while player.Parent do
        if isPlayerBlocked(player) then return true end

        -- a previous attempt may have left the modal open - PromptBlockPlayer
        -- no-ops while one is up, so reuse it instead of waiting for a new one
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
            if button then
                clickBlockButton(button)
            end
        end

        task.wait(0.3)
        if isPlayerBlocked(player) then return true end

        task.wait(0.7)
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

-- ===================== WRONG-FLOOR RESCUE =====================
-- Every hop channel (Server Switch, Restart Server, panic/admin block+rejoin,
-- empty server) leaves an armed config naming the floor it wants. A bad hop
-- can drop us somewhere else entirely - Floor 1's Woodlands while we farmed
-- floor 10. If this isn't the hop's target floor, leave BEFORE the gate or
-- any module runs: teleport straight to the right floor (hub bounce as the
-- fallback - its resume block reads the same config). Blocking players on a
-- floor we don't even want is pointless.
-- stale lastfloor_<UserId> from older versions: read by nothing, kill it once
if isfile and delfile then
    local stale = `Bluu/Swordburst 2/lastfloor_{LocalPlayer.UserId}`
    if isfile(stale) then pcall(delfile, stale) end
end
local hopTargetFloor = function()
    for _, file in next, { 'Bluu/Swordburst 2/serverswitch', 'Bluu/Swordburst 2/emptyserver' } do
        if isfile and isfile(file) then
            local ok, cfg = pcall(function()
                return game:GetService('HttpService'):JSONDecode(readfile(file))
            end)
            if ok and type(cfg) == 'table' and cfg.active and type(cfg.targetPlace) == 'number' then
                -- only a hop in actual flight counts: fresh (under 10 min) and
                -- pointed at a real floor. Stale leftovers from old sessions
                -- and hub-pointing writes get deleted so a MANUAL floor switch
                -- can never trip the rescue
                if cfg.at and os.time() - cfg.at < 600 and cfg.targetPlace ~= OML_RELOAD_PLACE then
                    return cfg.targetPlace
                end
                if delfile then pcall(delfile, file) end
            end
        end
    end
end

local wantFloor = hopTargetFloor()

-- The Between is a party place: never yank someone out of a dungeon run for a
-- stale floor config
if wantFloor and wantFloor ~= game.PlaceId
    and game.PlaceId ~= OML_RELOAD_PLACE and not IN_BETWEEN then
    warn('[Bluu] Landed on the wrong floor - returning to', wantFloor)
    task.spawn(function()
        for _ = 1, 3 do
            pcall(function()
                Function:InvokeServer('Teleport', { 'Teleport', wantFloor })
            end)
            task.wait(6) -- still here? the invoke didn't take
        end
        pcall(function()
            game:GetService('TeleportService'):Teleport(OML_RELOAD_PLACE, LocalPlayer)
        end)
    end)
    return -- nothing runs on a floor we didn't ask for
end

local joinGateArmed = (function()
    if IN_BETWEEN then return false end -- the other players are your party
    if not (isfile and readfile) or not isfile(RESTART_GATE_FILE) then return false end
    local ok, flag = pcall(readfile, RESTART_GATE_FILE)
    if not (ok and flag == '1') then return false end
    -- the flag alone is NOT enough: it lingers after the toggle's turned off
    -- and a manual floor change would get blocked+hopped. Only gate right
    -- after one of our own hops actually wrote a config
    return hopTargetFloor() ~= nil
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
    -- block 1 of them in the BACKGROUND: the modal flow keeps retrying while
    -- a 0.5s poll watches GetBlockedUserIds - the instant any target confirms
    -- (or just leaves), we hub. No serial block-then-wait.
    local targets = {}
    for _, p in next, Players:GetPlayers() do
        if #targets >= 1 then break end
        if not isGateExempt(p) then
            table.insert(targets, p)
        end
    end
    for _, p in next, targets do
        task.spawn(blockPlayer, p)
    end
    pcall(function()
        if writefile and isfolder and HumanoidRootPart then
            if not isfolder('Bluu') then makefolder('Bluu') end
            if not isfolder('Bluu/Swordburst 2') then makefolder('Bluu/Swordburst 2') end
            -- keep the ORIGINAL saved spot: every hop lands us at spawn, and
            -- overwriting with our current pos would erase the farm position
            local pos = HumanoidRootPart.Position
            local saved
            if isfile('Bluu/Swordburst 2/serverswitch') then
                local prev = game:GetService('HttpService'):JSONDecode(readfile('Bluu/Swordburst 2/serverswitch'))
                if prev and prev.position then saved = prev.position end
            end
            writefile('Bluu/Swordburst 2/serverswitch', game:GetService('HttpService'):JSONEncode({
                active = true,
                targetPlace = game.PlaceId,
                position = saved or { x = pos.X, y = pos.Y, z = pos.Z },
                at = os.time(),
            }))
        end
    end)
    local hop = function()
        -- 8s debounce only - TeleportInitFailed clears it instantly so a
        -- silent reject retries on the next gate pass, not half a min later
        if lastGateTeleport and tick() - lastGateTeleport < 8 then return end
        lastGateTeleport = tick()
        pcall(function()
            game:GetService('TeleportService'):Teleport(659222129, LocalPlayer)
        end)
    end
    -- 0.5s poll: leave as soon as ONE target is verified blocked or gone;
    -- 15s cap so a dead modal can't seat us forever
    local deadline = tick() + 15
    while #targets > 0 and tick() < deadline do
        for _, p in next, targets do
            if not p.Parent or isPlayerBlocked(p) then
                hop()
                return
            end
        end
        task.wait(0.5)
    end
    hop()
end

game:GetService('TeleportService').TeleportInitFailed:Connect(function(player)
    if player == LocalPlayer then lastGateTeleport = nil end
end)

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

-- mid-session watch for the whole run: while Restart Server stays on, anyone
-- joining at any point triggers the same block + hub bounce (the gate re-arms
-- on the next join via the restartgate file)
Players.PlayerAdded:Connect(function(player)
    if getgenv().Bluu == false then return end
    if IN_BETWEEN then return end
    if not (Toggles and Toggles.RestartServer and Toggles.RestartServer.Value) then return end
    if isGateExempt(player) then return end
    warn('[Bluu] Restart server: player joined mid-session - blocking and hopping')
    joinGateBlockAndHop()
end)

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
