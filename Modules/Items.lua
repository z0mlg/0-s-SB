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
