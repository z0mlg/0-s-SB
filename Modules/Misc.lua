-- Bluu :: Misc  (split from Sb2-0mlg.lua)

local Miscs = Main:AddLeftTabbox()

local Misc1 = Miscs:AddTab('Misc')

local AnimPackNames = {}
for _, AnimPack in next, game:GetService('StarterPlayer').StarterCharacterScripts.Animate.Packs:GetChildren() do
    table.insert(AnimPackNames, AnimPack.Name)
end

local getCurrentAnimSetting = function()
    if leftSword then return 'DualWield' end
    if not rightSword then return 'Unarmed' end
    local SwordClass = Items[rightSword.Name].Class.Value
    return SwordClass == '1HSword' and 'SingleSword' or SwordClass
end

Misc1:AddDropdown('ChangeAnimationPack', {
    Text = 'Change animation pack',
    Values = AnimPackNames,
    AllowNull = true
}):OnChanged(function(animPackName)
    if not animPackName then return end
    Options.ChangeAnimationPack:SetValue()
    Function:InvokeServer('CashShop', {
        'SetAnimPack', {
            Name = animPackName,
            Value = getCurrentAnimSetting(),
            Parent = AnimPacks
        }
    })
end)

local animPackAnimSettings = {
    Berserker = '2HSword',
    Ninja = 'Katana',
    Noble = 'SingleSword',
    Vigilante = 'DualWield',
    SwissSabre = 'Rapier',
    Swiftstrike = 'Spear',
    Reaper = 'Scythe'
}

local unownedAnimPacks = {}
for animPackName, swordClass in next, animPackAnimSettings do
    if AnimPacks:FindFirstChild(animPackName) then continue end
    local animPack = Instance.new('StringValue')
    animPack.Name = animPackName
    animPack.Value = swordClass
    unownedAnimPacks[animPackName] = animPack
end

Misc1:AddToggle('UnlockAllAnimations', { Text = 'Unlock all animations' }):OnChanged(function(value)
    for _, animPack in next, unownedAnimPacks do
        animPack.Parent = value and AnimPacks or nil
    end
end)

PlayerUI.MainFrame.TabFrames.Settings.Attachments.AnimPacks.ChildAdded:Connect(function(entry)
    entry.Activated:Connect(function()
        local animPackName = (function()
            for _, item in next, Database.CashShop:GetChildren() do
                if item.Icon.Texture ~= entry.Frame.Icon.Image then continue end
                return item.Name:gsub(' Animation Pack', ''):gsub(' ', '')
            end
        end)()
        if not unownedAnimPacks[animPackName] then return end
        local swordClass = animPackAnimSettings[animPackName]
        -- local animSetting = Profile.AnimSettings[swordClass]
        -- animSetting.Value = animSetting.Value == animPackName and '' or animPackName
        Function:InvokeServer('CashShop', {
            'SetAnimPack', {
                Name = animPackName,
                Value = swordClass,
                Parent = AnimPacks
            }
        })
    end)
end)

chatSize = Chat.Size
local chatSizeStretched = UDim2.fromScale(Chat.Size.X.Scale, Chat.Size.Y.Scale * 2)
Misc1:AddToggle('StretchChat', { Text = 'Stretch chat' }):OnChanged(function(value)
    Chat.Size = value and chatSizeStretched or chatSize
end)

Camera:GetPropertyChangedSignal('ViewportSize'):Connect(function()
    if not Toggles.StretchChat.Value then return end
    Chat.Size = UDim2.new(0, 600, 0, Camera.ViewportSize.Y - 177)
end)

defaultCameraMaxZoomDistance = LocalPlayer.CameraMaxZoomDistance

Misc1:AddToggle('InfiniteZoomDistance', { Text = 'Infinite zoom distance' })
:OnChanged(function(value)
    LocalPlayer.CameraMaxZoomDistance = value and math.huge or defaultCameraMaxZoomDistance
    LocalPlayer.DevCameraOcclusionMode = value and 1 or 0
end)

Misc1:AddDropdown('PerformanceBoosters', {
    Text = 'Performance boosters',
    Values = {
        'No damage text',
        'No damage particles',
        'Delete dead mobs',
        'No vel obtained in chat',
        'Disable rendering',
        'Limit FPS'
    },
    Multi = true,
    AllowNull = true
}):OnChanged(function(values)
    RunService:Set3dRenderingEnabled(not values['Disable rendering'])
    if setfpscap then
        setfpscap(values['Limit FPS'] and 15 or UserSettings():GetService('UserGameSettings').FramerateCap)
    end
end)

workspace:WaitForChild('HitEffects').ChildAdded:Connect(function(hitPart)
    if not Options.PerformanceBoosters.Value['No damage particles'] then return end
    task.wait()
    hitPart:Destroy()
end)

if RequiredServices then
    local GraphicsServerEventOld = RequiredServices.Graphics.ServerEvent
    RequiredServices.Graphics.ServerEvent = function(...)
        local args = {...}
        if args[1][1] == 'Damage Text' then
            if Options.PerformanceBoosters.Value['No damage text'] then return end
        elseif args[1][1] == 'KillFade' then
            if Options.PerformanceBoosters.Value['Delete dead mobs'] then
                return args[1][2]:Destroy()
            end
        end
        return GraphicsServerEventOld(...)
    end

    local UIServerEventOld = RequiredServices.UI.ServerEvent
    RequiredServices.UI.ServerEvent = function(...)
        local args = {...}
        if args[1][2] == 'VelObtained' then
            if Options.PerformanceBoosters.Value['No vel obtained in chat'] then return end
        end
        return UIServerEventOld(...)
    end
else
    workspace.ChildAdded:Connect(function(part)
        if not Options.PerformanceBoosters.Value['Damage Text'] then return end
        if part:IsA('Part') then return end
        if not part:WaitForChild('DamageText', 1) then return end
        part:Destroy()
    end)

    Chat.ScrollContent.ChildAdded:Connect(function(frame)
        if not Options.PerformanceBoosters.Value['No vel obtained in chat'] then return end
        if frame.Name ~= 'ChatVelTemplate' then return end
        frame.Visible = false
        frame.Size = UDim2.fromOffset(0, -5)
        frame:GetPropertyChangedSignal('Position'):Wait()
        frame:Destroy()
    end)
end

local Misc2 = Miscs:AddTab('More misc')

local equipBestWeapon = function()
    if not Toggles.EquipBestWeapon.Value then return end
    if rightSword and Items[rightSword.Name].Level.Value > getLevel() then return end

    local highestDamage = 0
    local bestKatana = false
    local highestStamina = 0
    local bestWeapon

    for _, item in next, Inventory:GetChildren() do
        local inDatabase = Items[item.Name]
        local level = inDatabase:FindFirstChild('Level') and inDatabase.Level.Value or 0
        if level > getLevel() then continue end
        local itemType = inDatabase.Type.Value
        if itemType ~= 'Weapon' then continue end
        local damage = getItemDamageOrDefense(item)
        local isKatana = inDatabase.Class.Value == 'Katana'
        local stamina = inDatabase:FindFirstChild('Buffs')
            and inDatabase.Buffs:FindFirstChild('StaminaRegeneration')
            and inDatabase.Buffs.StaminaRegeneration.Value
            or 0
        if (
			damage > highestDamage or (
                damage == highestDamage and isKatana and (
                    not bestKatana or stamina > highestStamina
                )
            )
        ) then
            highestDamage = damage
            bestKatana = isKatana
            highestStamina = stamina
            bestWeapon = item
        end
    end

    if bestWeapon and Equip.Right.Value ~= bestWeapon.Value then
        task.spawn(InvokeFunction, 'Equipment', { 'EquipWeapon', bestWeapon, 'Right' })
    end
end

local equipBestArmor = function()
    if not Toggles.EquipBestArmor.Value then return end
    local armor = getItemById(Equip.Clothing.Value)
    if armor and Items[armor.Name].Level.Value > getLevel() then return end

    local highestDefense = 0
    local highestStamina = 0
    local bestArmor

    for _, item in next, Inventory:GetChildren() do
        local inDatabase = Items[item.Name]
        local level = inDatabase:FindFirstChild('Level') and inDatabase.Level.Value or 0
        if level > getLevel() then continue end
        local itemType = inDatabase.Type.Value
        if itemType ~= 'Clothing' then continue end
        local defense = getItemDamageOrDefense(item)
        local stamina = inDatabase:FindFirstChild('Buffs')
            and inDatabase.Buffs:FindFirstChild('StaminaRegeneration')
            and inDatabase.Buffs.StaminaRegeneration.Value
            or 0
        if defense > highestDefense or (
            defense == highestDefense and stamina > highestStamina
        ) then
            highestDefense = defense
            highestStamina = stamina
            bestArmor = item
        end
    end

    if bestArmor and Equip.Clothing.Value ~= bestArmor.Value then
        task.spawn(InvokeFunction, 'Equipment', { 'Wear', bestArmor })
    end
end

local equipBestAccessory = function()
    if not Toggles.EquipBestAccessory.Value then return end

    local highestStamina = 0
    local highestDefense = 0
    local highestHealth = 0
    local bestAccessory

    for _, item in next, Inventory:GetChildren() do
        local inDatabase = Items[item.Name]
        local level = inDatabase:FindFirstChild('Level') and inDatabase.Level.Value or 0
        if level > getLevel() then continue end
        local itemType = inDatabase.Type.Value
        if itemType ~= 'Accessory' then continue end
        local Buffs = inDatabase:FindFirstChild('Buffs')
        if not Buffs then continue end
        local stamina = Buffs:FindFirstChild('StaminaRegeneration')
            and Buffs.StaminaRegeneration.Value
            or 0
        local health = Buffs:FindFirstChild('HealthRegeneration')
            and Buffs.HealthRegeneration.Value
            or 0
        local defense = inDatabase:FindFirstChild('Stats')
            and inDatabase.Stats:FindFirstChild('Defense')
            and inDatabase.Stats.Defense.Value
            or 0
        if stamina > highestStamina or (
            stamina == highestStamina and (
                defense > highestDefense or (
                    defense == highestDefense and health > highestHealth
                )
            )
        ) then
            highestStamina = stamina
            highestDefense = defense
            highestHealth = health
            bestAccessory = item
        end
    end

    if not bestAccessory then return end

    task.spawn(InvokeFunction, 'Equipment', { 'Wear', bestAccessory })
    task.spawn(InvokeFunction, 'Equipment', { 'Wear', bestAccessory })
end

Misc2:AddToggle('EquipBestWeapon', { Text = 'Equip best weapon' }):OnChanged(function()
    task.spawn(equipBestWeapon)
end)
Misc2:AddToggle('EquipBestArmor', { Text = 'Equip best armor' }):OnChanged(function()
    task.spawn(equipBestArmor)
end)
Misc2:AddToggle('EquipBestAccessory', { Text = 'Equip best accessory' }):OnChanged(function(value)
    if not value then return end
    while Toggles.EquipBestAccessory.Value do
        equipBestAccessory()
        task.wait(0.1)
    end
end)

-- debounce: inventory load fires ChildAdded once per item — one delayed scan is enough
local equipWeaponQueued = false
local queueEquipBestWeapon = function()
    if equipWeaponQueued then return end
    equipWeaponQueued = true
    task.delay(0.25, function()
        equipWeaponQueued = false
        task.spawn(equipBestWeapon)
    end)
end
Inventory.ChildAdded:Connect(queueEquipBestWeapon)
Level.Changed:Connect(queueEquipBestWeapon)

Misc2:AddToggle('ReturnOnDeath', { Text = 'Return on death' })

-- Emergency escape: instead of dying (and losing the boss to the respawn wait
-- or its despawn/reset), teleport straight up when HP drops, hover there until
-- healed past the resume threshold or the max hover time, then drop back in.
Misc2:AddToggle('EscapeOnLowHealth', {
    Text = 'Emergency escape',
    Tooltip = 'Teleport straight up when HP drops below the threshold instead of dying, drop back once healed'
}):OnChanged(function(value)
    if value and not pcall(function() return Health.MaxValue > 0 end) then
        Library:Notify('Emergency escape: Health.MaxValue unavailable on this rig', 4)
    end
end)
Misc2:AddSlider('EscapeBelowHealth', { Text = 'Escape below HP', Default = 25, Min = 5, Max = 90, Rounding = 0, Suffix = '%', Compact = true })
Misc2:AddSlider('EscapeResumeHealth', { Text = 'Return above HP', Default = 60, Min = 10, Max = 100, Rounding = 0, Suffix = '%', Compact = true })
Misc2:AddSlider('EscapeMaxTime', { Text = 'Escape max time', Default = 15, Min = 3, Max = 60, Rounding = 0, Suffix = 's', Compact = true })
Misc2:AddSlider('EscapeHeight', { Text = 'Escape height', Default = 120, Min = 40, Max = 300, Rounding = 0, Suffix = 'm', Compact = true })

lowHealthEscaping = false -- global: autofarm/pathfarm yield while we hover
local escapePos
local escapeStart

RenderStepped:Connect(function()
    pcall(function()
        if not (Toggles.EscapeOnLowHealth and Toggles.EscapeOnLowHealth.Value)
            or not HumanoidRootPart
            or not (Health and Health.MaxValue and Health.MaxValue > 0)
            or Humanoid.Health == 0 then
            lowHealthEscaping = false
            return
        end

        local frac = Health.Value / Health.MaxValue
        if not lowHealthEscaping then
            if frac > Options.EscapeBelowHealth.Value / 100 then return end
            lowHealthEscaping = true
            escapePos = HumanoidRootPart.Position
            escapeStart = tick()
            return
        end

        if frac >= math.max(Options.EscapeBelowHealth.Value, Options.EscapeResumeHealth.Value) / 100
            or tick() - escapeStart >= Options.EscapeMaxTime.Value then
            lowHealthEscaping = false
            HumanoidRootPart.CFrame = CFrame.new(escapePos) -- drop back into the fight
            return
        end

        HumanoidRootPart.CFrame = CFrame.new(escapePos + Vector3.new(0, Options.EscapeHeight.Value, 0))
    end)
end)

Misc2:AddToggle('ResetOnLowStamina', { Text = 'Reset on low stamina' })

Misc2:AddToggle('AutoJoinNewFloor', { Text = 'Auto join new floor' })
Profile.Locations.ChildAdded:Connect(function(location)
    if not Toggles.AutoJoinNewFloor.Value then
        return
    end

    while true do
        local success, response = pcall(Function.InvokeServer, Function, 'Teleport', {
            'Teleport',
            tonumber(location.Name)
        })
        -- print(response)
        if not success then
        elseif not response or response == 'Already teleporting...' then
            local teleporting = Profile:WaitForChild('TELEPORTING', 1)
            teleporting = teleporting and teleporting.Destroying:Wait()
            break
        elseif response == 'You must be on a teleport pad to teleport!' then
            if Profile:FindFirstChild('Checkpoint') then
                Event:FireServer('Checkpoints', { 'TeleportToSpawn' })
            else
                Humanoid.Health = 0
            end
        else
            break
        end
        task.wait(0.3)
    end
end)

