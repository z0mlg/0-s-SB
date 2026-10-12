-- Bluu :: Items  (split from Sb2-0mlg.lua)

do

local ItemsBox = Misc:AddLeftGroupbox('Items')

if RequiredServices then
    local UIModule = RequiredServices.UI
    ItemsBox:AddButton({ Text = 'Open upgrade', Func = UIModule.openUpgrade })
    ItemsBox:AddButton({ Text = 'Open dismantle', Func = UIModule.openDismantle })
    ItemsBox:AddButton({ Text = 'Open forge', Func = UIModule.openCrystalForge })
end

local unboxableItems = {}
local unboxableItemNames = {}

local function addUnboxable(item, dontRefreshDropdown)
    if not unboxableItems[item.Name] and Items[item.Name]:FindFirstChild('Unboxable') then
        unboxableItems[item.Name] = item
        table.insert(unboxableItemNames, item.Name)
        if not dontRefreshDropdown then
            Options.UseItem:SetValues(Options.UseItem.Values)
        end
    end
end

for _, item in Inventory:GetChildren() do
    addUnboxable(item, true)
end

Inventory.ChildAdded:Connect(addUnboxable)
Inventory.ChildRemoved:Connect(function(item)
    if unboxableItems[item.Name] then
        unboxableItems[item.Name] = nil
        table.remove(unboxableItemNames, table.find(unboxableItemNames, item.Name))
        Options.UseItem:SetValues(Options.UseItem.Values)
    end
end)

ItemsBox:AddDropdown('UseItem', { Text = 'Use item(s)', Values = unboxableItemNames, AllowNull = true })
:OnChanged(function(itemName)
    if not itemName then return end
    Options.UseItem:SetValue()

    local item = unboxableItems[itemName]
    if not item then return end

    Function:InvokeServer('Equipment', { 'UseItem', item, math.huge })
end)

do
    local connection
    ItemsBox:AddToggle("FreeCommonCrystals", { Text = "Free common crystals" })
    :OnChanged(function(value)
        if not value then
            if connection then
                connection:Disconnect()
            end
            return
        end

        for _, item in next, Inventory:GetChildren() do
            if item.Name == "Blue Novice Armor" then
                noviceArmor = item
                break
            elseif item.Name:find(" Novice Armor") then
                noviceArmor = item
            end
        end

        if not noviceArmor then
            Library:Notify("Get a Novice Armor first")
            return
        end

        InvokeFunction("Equipment", { "Wear", noviceArmor })
        Event:FireServer(
            "Equipment", {
                "Dismantle",
                { noviceArmor }
            }
        )
        Humanoid.Health = 0

        connection = Inventory.ChildAdded:Connect(function(item)
            if item.Name == "Blue Novice Armor" then
                noviceArmor = item
            end
        end)
    end)
end

ItemsBox:AddButton({
    Text = 'Dump weapon models',
    Func = function()
        task.spawn(function()
            local stash = Instance.new('Folder')
            stash.Name = 'SwordModelDump'
            stash.Parent = workspace

            local grabbed = {}
            local count = 0
            local grab = function(inst, name)
                if grabbed[name] then return end
                local ok, clone = pcall(inst.Clone, inst)
                if ok and clone then
                    clone.Name = name
                    clone.Parent = stash
                    grabbed[name] = true
                    count += 1
                end
            end

            -- pass 0: Database.Items - replicated item folders sometimes carry
            -- the actual Tool/Model template as a child; check before anything
            for _, data in ipairs(Items:GetChildren()) do
                for _, child in ipairs(data:GetChildren()) do
                    if child:IsA('Tool') or child:IsA('Model') then
                        grab(child, data.Name)
                    end
                end
            end

            -- pass 1: nil-parented instances - the game keeps assets like
            -- MainModule/Tagged/Weapons unloaded client-side
            if type(getnilinstances) == 'function' then
                local ok, nils = pcall(getnilinstances)
                if ok then
                    for _, inst in ipairs(nils) do
                        if not (inst:IsA('Tool') or inst:IsA('Model')) then continue end
                        local p, inAssets = inst, false
                        while p do
                            local n = p.Name
                            if n == 'Weapons' or n == 'Items' or n == 'Assets' or n == 'Models' then
                                inAssets = true
                                break
                            end
                            p = p.Parent
                        end
                        if inAssets then
                            grab(inst, inst.Name)
                        end
                    end
                end
            end

            -- pass 2: equip-loop - the server builds each owned weapon's model
            -- into workspace.CharacterItems.<uid>.RightWeapon on equip
            local origItem = getItemById and getItemById(Equip.Right.Value)
            local myFolder
            local charItems = workspace:FindFirstChild('CharacterItems')
            if charItems then
                myFolder = charItems:FindFirstChild(tostring(LocalPlayer.UserId))
            end

            for _, item in ipairs(Inventory:GetChildren()) do
                if grabbed[item.Name] then continue end
                local data = Items[item.Name]
                local class = data and data:FindFirstChild('Class')
                if not (class and tostring(class.Value):find('Sword')) then continue end

                local before = myFolder and myFolder:FindFirstChild('RightWeapon')
                if not pcall(InvokeFunction, 'Equipment', { 'EquipWeapon', item, 'Right' }) then continue end

                local weapon, deadline = before, tick() + 1.5
                repeat
                    task.wait(0.05)
                    weapon = myFolder and myFolder:FindFirstChild('RightWeapon')
                until (weapon and weapon ~= before) or tick() > deadline

                if weapon then
                    grab(weapon, item.Name)
                end
                task.wait(0.15) -- don't hammer the equip remote
            end

            if origItem then
                pcall(InvokeFunction, 'Equipment', { 'EquipWeapon', origItem, 'Right' })
            end

            -- pass 3: everyone else's equipped weapons - CharacterItems replicates
            -- for every player, and mob/boss models carry their own blades
            if charItems then
                for _, folder in ipairs(charItems:GetChildren()) do
                    for _, weapon in ipairs(folder:GetChildren()) do
                        if weapon:IsA('Model') then
                            grab(weapon, `{folder.Name}_{weapon.Name}`)
                        end
                    end
                end
            end
            for _, mob in ipairs(Mobs:GetChildren()) do
                for _, desc in ipairs(mob:GetDescendants()) do
                    if desc:IsA('Tool') then
                        grab(desc, `{mob.Name}_{desc.Name}`)
                    end
                end
            end

            Library:Notify(`Dumped {count} weapon models into workspace.SwordModelDump - run saveinstance now`, 8)
        end)
    end,
})

end

do

local PlayersBox = Misc:AddRightGroupbox('Players')

local selectedPlayer

PlayersBox:AddDropdown('PlayerList', { Text = 'Player list', Values = {}, SpecialType = 'Player' })
:OnChanged(function(player)
    selectedPlayer = player

    if RequiredServices and Toggles.ViewPlayersInventory and Toggles.ViewPlayersInventory.Value then
        debug.setupvalue(RequiredServices.InventoryUI.GetInventoryData, 2, Profiles[player.Name])
    end
end)

PlayersBox:AddButton({ Text = "View player's stats", Func = function()
    if not Options.PlayerList.Value then return end

    pcall(function()
        local profile = Profiles:FindFirstChild(selectedPlayer.Name)

        if profile.Locations:FindFirstChild('1') then
            profile.Locations['1']:Destroy()
        end

        local stats = {
            -- AnimPacks = 'no',
            Gamepasses = 'no',
            Skills = 'no'
        }

        for statName, _ in next, stats do
            local statChildrenNames = {}
            for _, stat in next, profile[statName]:GetChildren() do
                table.insert(statChildrenNames, stat.Name)
            end
            if #statChildrenNames > 0 then
                stats[statName] = 'the ' .. table.concat(statChildrenNames, ', '):lower()
            end
        end

		Library:Notify(
			`{selectedPlayer.Name}'s account is {selectedPlayer.AccountAge} days old,\n`
				.. `level {getLevel(profile.Stats.Exp.Value)},\n`
				.. `has {profile.Stats.Vel.Value} vel,\n`
				.. `floor {#profile.Locations:GetChildren() - 2},\n`
				-- .. `{stats.AnimPacks} animation packs bought,\n`
				.. `{stats.Gamepasses} gamepasses bought,\n`
				.. `and {stats.Skills} special skills unlocked`,
			10
		)
    end)
end })

if RequiredServices then
    PlayersBox:AddToggle('ViewPlayersInventory', { Text = `View player's inventory` }):OnChanged(function(value)
        if not value then
            debug.setupvalue(RequiredServices.InventoryUI.GetInventoryData, 2, Profile)
            return
        end

        local player = Options.PlayerList.Value
        if not player then return end
        debug.setupvalue(RequiredServices.InventoryUI.GetInventoryData, 2, Profiles[player.Name])
    end)
end

PlayersBox:AddToggle('ViewPlayer', { Text = 'View player' }):OnChanged(function(value)
    if not value then return end
    while Toggles.ViewPlayer.Value do
        if selectedPlayer and not isDead(selectedPlayer.Character) then
            Camera.CameraSubject = selectedPlayer.Character
        end
        task.wait(0.1)
    end
    Camera.CameraSubject = Character
end)

PlayersBox:AddToggle('GoToPlayer', { Text = 'Go to player' }):OnChanged(function(value)
    toggleLerp(Toggles.GoToPlayer)
    enableLinearVelocity(Toggles.GoToPlayer.Value)
    toggleNoclip(Toggles.GoToPlayer)
    if not value then return end
    while Toggles.GoToPlayer.Value do
        task.wait()

        if not selectedPlayer or isDead(selectedPlayer.Character) then continue end

        local rootPart = selectedPlayer.Character.HumanoidRootPart

        HumanoidRootPart.CFrame = rootPart.CFrame +
            Vector3.new(Options.XOffset.Value, Options.YOffset.Value, Options.ZOffset.Value)
    end
end)

PlayersBox:AddSlider('XOffset', { Text = 'X offset', Default = 0, Min = -20, Max = 20, Rounding = 0 })
PlayersBox:AddSlider('YOffset', { Text = 'Y offset', Default = 5, Min = -20, Max = 20, Rounding = 0 })
PlayersBox:AddSlider('ZOffset', { Text = 'Z offset', Default = 0, Min = -20, Max = 20, Rounding = 0 })

end
