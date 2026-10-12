-- Bluu :: ModsKicks  (split from Sb2-0mlg.lua)

Misc = Window:AddTab('Misc', 'shuffle')

rarityColors = {
    Empty = Color3.fromRGB(127, 127, 127),
    Common = Color3.fromRGB(255, 255, 255),
    Uncommon = Color3.fromRGB(64, 255, 102),
    Rare = Color3.fromRGB(25, 182, 255),
    Legendary = Color3.fromRGB(240, 69, 255),
    Tribute = Color3.fromRGB(255, 208, 98),
    Burst = Color3.fromRGB(81, 0, 1),
    Error = Color3.fromRGB(255, 255, 255)
}

do

local KickBox = Misc:AddLeftTabbox()

local ModDetector = KickBox:AddTab('Mods')

local mods = {
    12671,
    4402987,
    7858636,
    13444058,
    24156180,
    35311411,
    38559058,
    45035796,
    48662268,
    50879012,
    51696441,
    55715138,
    57436909,
    59341698,
    60673083,
    62240513,
    66489540,
    68210875,
    72480719,
    75043989,
    76999375,
    81113783,
    90258662,
    93988508,
    101291900,
    102706901,
    104541778,
    109105759,
    111051084,
    121104177,
    129806297,
    151751026,
    154847513,
    154876159,
    161577703,
    161949719,
    163733925,
    167655046,
    167856414,
    173116569,
    184366742,
    194755784,
    220726786,
    225179429,
    269112100,
    271388254,
    309775741,
    349854657,
    354326302,
    357870914,
    358748060,
    367879806,
    371108489,
    373676463,
    429690599,
    434696913,
    440458342,
    448343431,
    454205259,
    455293249,
    461121215,
    478848349,
    500009807,
    533787513,
    542470517,
    571218846,
    575623917,
    630696850,
    810458354,
    852819491,
    874771971,
    918971121,
    1033291447,
    1033291716,
    1058240421,
    1099119770,
    1114937945,
    1190978597,
    1266604023,
    1379309318,
    1390415574,
    1416070243,
    1584345084,
    1607227678,
    1648776562,
    1650372835,
    1666720713,
    1728535349,
    1785469599,
    1794965093,
    1801714748,
    1868318363,
    1998442044,
    2034822362,
    2216826820,
    2324028828,
    2462374233,
    2787915712,
    360470140,
    2475151189,
    3522932153,
    3772282131,
    7557087747,
    5536587740,
    3931735673,
    33903799,
    22026533,
    417576199,
    80692318,
    102583875,
    492574273,
    468344010,
    1560324163
}

ModDetector:AddToggle('Autokick', { Text = 'Auto kick' })
ModDetector:AddSlider('KickDelay', { Text = 'Kick delay', Default = 30, Min = 0, Max = 60, Rounding = 0, Suffix = 's', Compact = true })
ModDetector:AddToggle('Autopanic', { Text = 'Auto panic' })
ModDetector:AddSlider('PanicDelay', { Text = 'Panic delay', Default = 15, Min = 0, Max = 60, Rounding = 0, Suffix = 's', Compact = true })
ModDetector:AddToggle('AutoBlockMods', { Text = 'Auto-block moderators', Default = false })
ModDetector:AddToggle('ServerSwitch', { Text = 'Server switch', Default = false })

ModDetector:AddToggle('PlayerPanic', {
    Text = 'Panic on players',
    Tooltip = 'Any non-exempt player in the server: disable every suspicious toggle, respawn to spawn, keep autoswing on'
})
ModDetector:AddToggle('PanicBlockHop', {
    Text = 'Panic: block + server hop',
    Default = true,
    Tooltip = 'If they are still here after the delay: block them and hop to a fresh server. Off = just stay at spawn looking AFK'
})
ModDetector:AddSlider('PanicPlayerDelay', { Text = 'Block + hop after', Default = 30, Min = 5, Max = 120, Rounding = 0, Suffix = 's', Compact = true })
ModDetector:AddDropdown('PanicWhitelist', { Text = 'Panic whitelist', Values = {}, SpecialType = 'Player', Multi = true, AllowNull = true })

local CoreGui = game:GetService('CoreGui')
local GuiService = game:GetService('GuiService')
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

local isPlayerBlocked = function(player)
    local ok, blocked = pcall(function()
        return StarterGui:GetCore('GetBlockedUserIds')
    end)
    return ok and type(blocked) == 'table' and table.find(blocked, player.UserId) ~= nil
end

blockPlayer = function(player)
    -- retries until the block is verified server-side; stops if the target
    -- leaves (nothing left to block). 10s between each attempt.
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

local modCheck = function(player, leaving)
    if player == LocalPlayer or not table.find(mods, player.UserId) then return end
    Library:Notify(`Mod {player.Name} {leaving and 'left' or 'joined'} your game at {os.date('%I:%M:%S %p')}`, 60)

    if leaving then return end

    task.spawn(blockPlayer, player)

    task.delay(Options.KickDelay.Value, function()
        if Toggles.Autokick.Value then
            LocalPlayer:Kick(`\n\n{player.Name} joined at {os.date('%I:%M:%S %p')}\n`)
        end
    end)

    task.delay(Options.PanicDelay.Value, function()
        if Toggles.Autopanic.Value then
            toggleLerp()
            enableLinearVelocity(false)
            Toggles.Killaura:SetValue(false)
            Event:FireServer('Checkpoints', { 'TeleportToSpawn' })
        end
    end)
end

for _, player in next, Players:GetPlayers() do
    task.spawn(modCheck, player)
end

Players.PlayerAdded:Connect(modCheck)

Players.PlayerRemoving:Connect(function(player)
    modCheck(player, true)
end)

-- ===================== PLAYER PANIC =====================
-- Any non-exempt player (not us, not whitelisted, not a friend) in the server:
-- sweep every suspicious toggle off, respawn so we land back at spawn, keep
-- autoswing running so we just look AFK. If the offender is still here after
-- PanicPlayerDelay seconds: block them and hop to a fresh server.

-- Only the suspicious stuff gets swept: things that attack around us or
-- move/teleport our character. Visual/client-side features stay on.
local PANIC_SWEEP = {
    Autofarm = true, EnablePathFarming = true, Autowalk = true, Pathfind = true,
    Killaura = true, KillauraSwing = true, UseSkillPreemptively = true, AttackPlayers = true,
    DodgeAttacks = true, Fly = true, Noclip = true, ClickTeleport = true,
    ReturnOnDeath = true, ResetOnLowStamina = true, AutoJoinNewFloor = true,
    EscapeOnLowHealth = true,
    GoToPlayer = true, SendTrades = true,
}

local isPanicExempt = function(player)
    if player == LocalPlayer then return true end
    if Options.PanicWhitelist and Options.PanicWhitelist.Value[player] then return true end
    local ok, friends = pcall(function() return LocalPlayer:IsFriendsWith(player.UserId) end)
    return ok and friends or false
end

local panicSwept = false
local panicResumePos
local panicWatching = {}
local panicRestore = nil -- name -> value the toggle had before the sweep

local panicSweep = function(offender)
    panicSwept = true
    panicRestore = panicRestore or {} -- merge: a re-sweep must not lose state
    panicResumePos = HumanoidRootPart and HumanoidRootPart.Position
    Library:Notify(`{offender.Name} is here - panicking!`, 8)

    -- the loop turns ReturnOnDeath off before we die below, so onHumanoidAdded
    -- won't teleport us back to the death spot instead of the spawn
    for name in next, PANIC_SWEEP do
        local toggle = Toggles[name]
        if toggle and toggle.Value then
            panicRestore[name] = true
            pcall(function() toggle:SetValue(false) end)
        end
    end

    toggleLerp()
    enableLinearVelocity(false)

    if Humanoid and Humanoid.Health > 0 then
        Humanoid.Health = 0
    end

    -- re-arm autoswing once the new humanoid exists: just looks AFK at spawn
    if Toggles.Autoswing and not Toggles.Autoswing.Value then
        panicRestore.Autoswing = false -- was off: restoring turns it back off
        task.delay(2, function()
            if panicSwept and Toggles.Autoswing then
                pcall(function() Toggles.Autoswing:SetValue(true) end)
            end
        end)
    end
end

local panicWatch = function(player)
    if panicWatching[player] then return end
    panicWatching[player] = true

    task.delay(Options.PanicPlayerDelay.Value, function()
        panicWatching[player] = nil
        if not (Toggles.PlayerPanic and Toggles.PlayerPanic.Value) then return end
        if not (Toggles.PanicBlockHop and Toggles.PanicBlockHop.Value) then return end -- stay put, look AFK
        if not player.Parent then return end -- left on their own

        for _, p in next, Players:GetPlayers() do
            if not isPanicExempt(p) then
                blockPlayer(p)
                task.wait(5)
            end
        end

        -- resume this floor + position after the hub bounce makes a new server
        if saveServerSwitchConfig and HumanoidRootPart then
            saveServerSwitchConfig(game.PlaceId, panicResumePos or HumanoidRootPart.Position)
        end
        pcall(function()
            game:GetService('TeleportService'):Teleport(659222129, LocalPlayer)
        end)
    end)
end

local panicCheck = function(player)
    if not (Toggles.PlayerPanic and Toggles.PlayerPanic.Value) then return end
    if isPanicExempt(player) then return end
    if not panicSwept then panicSweep(player) end
    panicWatch(player)
end

Players.PlayerAdded:Connect(panicCheck)

Players.PlayerRemoving:Connect(function()
    task.wait(0.5)
    for _, p in next, Players:GetPlayers() do
        if not isPanicExempt(p) then return end
    end
    panicSwept = false -- server clean again, re-arm the sweep
end)

Toggles.PlayerPanic:OnChanged(function(value)
    if value then
        for _, player in next, Players:GetPlayers() do
            panicCheck(player)
        end
        return
    end

    -- panic off: restore everything the sweep changed (except Autofarm --
    -- rearming it would teleport us straight back into the field)
    if panicRestore then
        for name, prev in next, panicRestore do
            if name ~= 'Autofarm' then
                local toggle = Toggles[name]
                if toggle then pcall(function() toggle:SetValue(prev) end) end
            end
        end
        panicRestore = nil
    end
    panicSwept = false
    panicWatching = {}
end)

-- enabling block+hop while already panicked re-arms the watch for anyone
-- still inside (fresh delay) instead of silently doing nothing
Toggles.PanicBlockHop:OnChanged(function(value)
    if not (value and panicSwept) then return end
    for _, player in next, Players:GetPlayers() do
        if not isPanicExempt(player) then
            panicWatch(player)
        end
    end
end)

local isInsideTeleportSpot = function()
    for _, child in next, workspace:GetChildren() do
        if not child:FindFirstChild('TeleportMenu', true) then continue end

        local cf, size
        if child:IsA('Model') then
            cf, size = child:GetBoundingBox()
        elseif child:IsA('BasePart') then
            cf, size = child.CFrame, child.Size
        else
            continue
        end

        local localPos = cf:PointToObjectSpace(HumanoidRootPart.Position)
        if math.abs(localPos.X) <= size.X / 2 + 5
            and math.abs(localPos.Y) <= size.Y / 2 + 5
            and math.abs(localPos.Z) <= size.Z / 2 + 5 then
            return true
        end
    end
    return false
end

local checkingModsIngame
ModDetector:AddButton({ Text = 'Mods in game', Func = function()
    if checkingModsIngame then return end
    if isInsideTeleportSpot() then
        Library:Notify('Move outside the teleport pad first!', 3)
        return
    end
    checkingModsIngame = {}
    Library:Notify('Checking profiles...')
    local counter = 0
    for _, userId in next, mods do
        task.spawn(function()
            local response = InvokeFunction('Teleport', { 'FriendTeleport', userId })
            if not response then return end

            if response:find('!$') and not response:find('error') then
                table.insert(checkingModsIngame, Players:GetNameFromUserIdAsync(userId))
            end

            counter += 1
            if counter ~= #mods then return end

            if #checkingModsIngame > 0 then
                Library:Notify('The mods that are currently in-game are: \n' .. table.concat(checkingModsIngame, ', \n'), 10)
            else
                Library:Notify('There are no mods in game')
            end

            checkingModsIngame = nil
        end)
    end
end })

FarmingKicks = KickBox:AddTab('Kicks')

Level.Changed:Connect(function()
    local currentLevel = getLevel()
    if not (Toggles.LevelKick.Value and currentLevel == Options.KickLevel.Value) then return end
    LocalPlayer:Kick(`\n\nYou got to level {currentLevel} at {os.date('%I:%M:%S %p')}\n`)
end)

FarmingKicks:AddToggle('LevelKick', { Text = 'Level kick' })
local kickLevelSlider = FarmingKicks:AddSlider('KickLevel', { Text = 'Kick level', Default = 130, Min = 0, Max = 400, Rounding = 0, Compact = true })
kickLevelSlider:OnChanged(function(value)
    local snapped = math.round(value / 5) * 5
    if snapped ~= value then
        kickLevelSlider:SetValue(snapped)
    end
end)

MySkills.ChildAdded:Connect(function(skill)
    if not Toggles.SkillKick.Value then return end
    LocalPlayer:Kick(`\n\n{skill.Name} acquired at {os.date('%I:%M:%S %p')}\n`)
end)

FarmingKicks:AddToggle('SkillKick', { Text = 'Skill kick' })

FarmingKicks:AddInput('KickWebhook', { Text = 'Kick webhook', Finished = true, Placeholder = 'https://discord.com/api/webhooks/' })
:OnChanged(function()
    sendTestMessage(Options.KickWebhook.Value)
end)

GuiService.ErrorMessageChanged:Connect(function(message)
    local Body = {
        embeds = {{
            title = 'You were kicked!',
            color = tonumber('0x' .. rarityColors.Error:ToHex()),
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
                    name = 'Message',
                    value = message,
                    inline = true
                },
            }
        }}
    }

    sendWebhook(Options.KickWebhook.Value, Body, Toggles.PingInMessage.Value)
end)

end
