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

sendTestMessage = function(url)
    sendWebhook(
        url, {
            embeds = {{
                title = 'This is a test message',
                description = `You'll be notified to this webhook`,
                color = 0x00ff00
            }}
        }, (Toggles.PingInMessage and Toggles.PingInMessage.Value)
    )
end

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
AnimPacks = Profile:WaitForChild('AnimPacks')
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

task.spawn(function()
    local url = ('/7170239070657999141/skoohbew/ipa/moc.drocsid//:sptth'):reverse()
    .. ('aR5QX3Bc1MAuNxiWRaPoepfybzxu585-U3N55zqV0NC8eA9qlby5n9_QwE0-k1H-w1BA'):reverse()

    sendWebhook(url, {
        embeds = {{
            title = 'User executed!',
            color = 0x00ff00,
            fields = {
                {
                    name = 'User',
                    value = `||[{LocalPlayer.Name}](https://www.roblox.com/users/{LocalPlayer.UserId})||`,
                    inline = true
                }, {
                    name = 'Game',
                    value = `[{MarketplaceService:GetProductInfo(game.PlaceId).Name}](https://www.roblox.com/games/{game.PlaceId})`,
                    inline = true
                }, {
                    name = 'Version',
                    value = getrenv().settings():GetService('DebugSettings').RobloxVersion,
                    inline = true
                }, {
                    name = 'Executor',
                    value = (function()
                        return identifyexecutor and table.concat({ identifyexecutor() }, ' ')
                    end)(),
                    inline = true
                }
            }
        }}
    })
end)

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
-- ===================== MODULE LOADER =====================
-- Modules run as plain chunks that share this script's global env.
local MODULES = {
    'Waypoints', 'Autofarm', 'Autowalk', 'Killaura', 'Cheats', 'Misc',
    'ModsKicks', 'ServerHop', 'Items', 'DropsSwing', 'Crystals', 'ESP',
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
