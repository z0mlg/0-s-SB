-- Bluu :: DropsSwing  (split from Sb2-0mlg.lua)

do

local Drops = Misc:AddLeftGroupbox('Drops')

Rarities = { 'Common', 'Uncommon', 'Rare', 'Legendary', 'Tribute' }

Drops:AddDropdown('AutoDismantle', { Text = 'Auto dismantle', Values = Rarities, Multi = true, AllowNull = true })

Drops:AddInput('DropWebhook', { Text = 'Drop webhook', Placeholder = 'https://discord.com/api/webhooks/' })

Drops:AddToggle('PingInMessage', { Text = 'Ping in message' })

Drops:AddDropdown('RaritiesForWebhook', { Text = 'Rarities for webhook', Values = Rarities, Default = Rarities, Multi = true, AllowNull = true })

local dropList = {}

Drops:AddDropdown('DropList', { Text = 'Drop list (select to dismantle)', Values = {}, AllowNull = true })
:OnChanged(function(dropName)
    if not dropName then return end
    Options.DropList:SetValue()
    Event:FireServer('Equipment', { 'Dismantle', { dropList[dropName] } })
    dropList[dropName] = nil
    table.remove(Options.DropList.Values, table.find(Options.DropList.Values, dropName))
end)

Inventory.ChildAdded:Connect(function(item)
    local inDatabase = Items[item.Name]

    if item.Name:find('Novice') or item.Name:find('Aura') then return end

    local rarity = inDatabase.Rarity.Value

    if Options.AutoDismantle.Value[rarity] then
        return Event:FireServer('Equipment', { 'Dismantle', { item } })
    end

    if not Options.RaritiesForWebhook.Value[rarity] then return end

    local FormattedItem = os.date('[%I:%M:%S] ') .. item.Name
    dropList[FormattedItem] = item
    table.insert(Options.DropList.Values, 1, FormattedItem)
    Options.DropList:SetValues(Options.DropList.Values)
    sendWebhook(Options.DropWebhook.Value, {
        embeds = {{
            title = `You received {item.Name}!`,
            color = tonumber('0x' .. rarityColors[rarity]:ToHex()),
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
                    name = 'Item Stats',
                    value = `[Level {(inDatabase:FindFirstChild('Level') and inDatabase.Level.Value or 0)} {rarity}]`
                        .. `(https://swordburst2.fandom.com/wiki/{string.gsub(item.Name, ' ', '_')})`,
                    inline = true
                }
            }
        }}
    }, Toggles.PingInMessage.Value)
end)

local ownedSkillNames = {}

for _, skill in next, MySkills:GetChildren() do
    table.insert(ownedSkillNames, skill.Name)
end

MySkills.ChildAdded:Connect(function(skill)
    if table.find(ownedSkillNames, skill.Name) then return end
    table.insert(ownedSkillNames, skill.Name)

    local inDatabase = Skills[skill.Name]
    sendWebhook(Options.DropWebhook.Value, {
        embeds = {{
            title = `You received {skill.Name}!`,
            color = tonumber('0x' .. rarityColors.Burst:ToHex()),
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
                    name = 'Skill Stats',
                    value = `[Level {(inDatabase:FindFirstChild('Level') and inDatabase.Level.Value or 0)}]`
                        .. `(https://swordburst2.fandom.com/wiki/{string.gsub(skill.Name, ' ', '_')})`,
                    inline = true
                }
            }
        }}
    }, Toggles.PingInMessage.Value)
end)

local LevelsAndVelGained = Drops:AddLabel()

local levelsGained, velGained = 0, 0
local levelOld, velOld = getLevel(), Vel.Value

local UpdateLevelAndVel = function()
    local levelNew, velNew = getLevel(), Vel.Value
    levelsGained += levelNew > levelOld and levelNew - levelOld or 0
    velGained += velNew > velOld and velNew - velOld or 0
    LevelsAndVelGained:SetText(`{levelsGained} levels | {velGained} vel gained`)
    levelOld, velOld = levelNew, velNew
end

UpdateLevelAndVel()
Vel.Changed:Connect(UpdateLevelAndVel)
Level.Changed:Connect(UpdateLevelAndVel)

end

do

local SwingCheats = Misc:AddRightGroupbox('Swing cheats')

if RequiredServices then
    local Actions = RequiredServices.Actions
    local StopSwingOld = Actions.StopSwing

    SwingCheats:AddToggle('Autoswing', { Text = 'Auto swing' }):OnChanged(function(value)
        if value then
            Actions.StopSwing = function() end
            Actions.StartSwing()
        else
            Actions.StopSwing = StopSwingOld
            StopSwingOld()
        end
    end)

    local AttackRequestOld = RequiredServices.Combat.AttackRequest
    RequiredServices.Combat.AttackRequest = function(...)
        local args = {...}
        if Toggles.OverrideBurstState.Value then
            debug.setupvalue(args[3], 2, Options.BurstState.Value)
        end
        return AttackRequestOld(...)
    end

    SwingCheats:AddToggle('OverrideBurstState', { Text = 'Override burst state' })
    SwingCheats:AddSlider('BurstState', { Text = 'Burst state', Default = 0, Min = 0, Max = 10, Rounding = 0, Suffix = ' hits', Compact = true })
end

if swingFunction then
    SwingCheats:AddSlider('SwingDelay', { Text = 'Swing delay', Default = 0.55, Min = 0.25, Max = 0.85, Rounding = 2, Suffix = 's' })
    :OnChanged(function()
        debug.setconstant(swingFunction, 13, Options.SwingDelay.Value)
    end)

    SwingCheats:AddSlider('BurstDelayReduction', { Text = 'Burst delay reduction', Default = 0.2, Min = 0, Max = 0.4, Rounding = 2, Suffix = 's' })
    :OnChanged(function()
        debug.setconstant(swingFunction, 14, Options.BurstDelayReduction.Value)
    end)
end

-- if RequiredServices then
--     SwingCheats:AddSlider('SwingThreads', { Text = 'Threads', Default = 1, Min = 1, Max = 10, Rounding = 0, Suffix = ' attack(s)' })

--     RequiredServices.Combat.DealDamage = function(target, attackName)
--         if Toggles.Killaura.Value or onCooldown[target] then return end

--         for _ = 1, Options.SwingThreads.Value do
--             dealDamage(target, attackName)
--         end

--         onCooldown[target] = true
--         task.delay(Options.SwingThreads.Value * 0.25, function()
--             onCooldown[target] = nil
--         end)
--     end
-- end

end
