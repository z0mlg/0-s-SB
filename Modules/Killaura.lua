-- Bluu :: Killaura  (split from Sb2-0mlg.lua)

local Killaura = Main:AddRightGroupbox('Killaura')

getItemById = function(id)
    if not id or id == 0 then return end
    for _, item in next, Inventory:GetChildren() do
        if item.Value == id then
            return item
        end
    end
end

getItemDamageOrDefense = (function()
    local maxUpgrades = {
        Common = 10,
        Uncommon = 10,
        Rare = 15,
        Legendary = 20,
        Tribute = 20,
        Burst = 25
    }

    local maxUpgradeMultipliers = {
        [10] = 0.4,
        [15] = 0.6,
        [20] = 1,
        [25] = 1.5
    }

    return function(item)
        local inDatabase = Items[item.Name]

        local Stats = inDatabase:FindFirstChild('Stats')
        if not Stats then return end

        local Stat = Stats:FindFirstChild('Damage') or Stats:FindFirstChild('Defense')
        if not Stat then return end

        local baseStat = Stat.Value

        local ScaleByLevel = inDatabase:FindFirstChild('ScaleByLevel')
        if ScaleByLevel then
            baseStat = baseStat * ScaleByLevel.Value * getLevel()
        end

        local Upgrade = item:FindFirstChild('Upgrade') and item.Upgrade.Value or 0
        if Upgrade == 0 then
            return baseStat
        end

        local Rarity = inDatabase.Rarity.Value

        local maxUpgrade = maxUpgrades[Rarity]

        local maxUpgradeAmount = 0.4

        if Stat.Name == 'Damage' then
            maxUpgradeAmount = maxUpgradeMultipliers[maxUpgrade]

            if Stats:FindFirstChild('DamageUpgrade') then
                maxUpgradeAmount = Stats.DamageUpgrade.Value or maxUpgradeAmount
            end
        end

        return math.floor(baseStat + (maxUpgrade and Upgrade / maxUpgrade * maxUpgradeAmount * baseStat or 0))
    end
end)()

KillauraSkill.Init = function(name, cost, cooldown, class, sword)
    local self = KillauraSkill
    self.Name = name
    self.Cost = cost or 0
    self.Cooldown = cooldown or 0
    self.Class = class
    self.Sword = sword
    self.OnCooldown = false
    self.Active = false
    -- self.LastHit = false
end

KillauraSkill.Init()

rightSword = getItemById(Equip.Right.Value)
leftSword = getItemById(Equip.Left.Value)

KillauraSkill.GetSword = function(class)
    local self = KillauraSkill
    if not class and (self.Sword and self.Sword.Parent) then
        return self.Sword
    end
    class = class or self.Class
    if rightSword and Items[rightSword.Name].Class.Value == class then
        self.Sword = rightSword
        return rightSword
    end
    for _, item in next, Inventory:GetChildren() do
        local inDatabase = Items[item.Name]
        if inDatabase.Type.Value == 'Weapon'
            and inDatabase.Class.Value == class
            and inDatabase.Level.Value <= getLevel()
        then
            self.Sword = item
            return item
        end
    end
end

-- local swordDamage = 0
-- local updateSwordDamage = function()
--     if leftSword then
--         swordDamage = math.floor(getItemDamageOrDefense(rightSword) * 0.6 + getItemDamageOrDefense(leftSword) * 0.4)
--     elseif rightSword then
--         swordDamage = getItemDamageOrDefense(rightSword)
--     else
--         swordDamage = 0
--     end
-- end

-- updateSwordDamage()

Equip.Right.Changed:Connect(function(id)
    rightSword = getItemById(id)
    -- updateSwordDamage()
end)

Equip.Left.Changed:Connect(function(id)
    leftSword = getItemById(id)
    -- updateSwordDamage()
end)

-- local getKillauraThreads = (function()
--     local skillMultipliers = {
--         ['Sweeping Strike'] = 3,
--         ['Leaping Slash'] = 3.3,
--         ['Summon Pistol'] = 4.35,
--         ['Meteor Shot'] = 3.1
--     }

--     local skillBaseDamages = {
--         ['Summon Pistol'] = 35000,
--         ['Meteor Shot'] = 55000
--     }

--     return function(entity)
--         if not entity.Health:FindFirstChild(LocalPlayer.Name) then
--             return 1
--         end

--         if Options.KillauraThreads.Value < Options.KillauraThreads.Max then
--             return Options.KillauraThreads.Value
--         end

--         -- if KillauraSkill.LastHit then
--         --     return 3
--         -- end

--         if entity:FindFirstChild('HitLives') then -- and (entity.HitLives.Value <= 3)
--             return entity.HitLives.Value
--         end

--         local damage = swordDamage

--         if KillauraSkill.Name and KillauraSkill.Active then
--             damage = swordDamage * skillMultipliers[KillauraSkill.Name]
--             damage = math.max(damage, skillBaseDamages[KillauraSkill.Name] or 0)
--         end

--         if damage == 0 then
--             return 0
--         end

--         if entity:FindFirstChild('MaxDamagePercent') then
--             local maxDamage = entity.Health.MaxValue * entity.MaxDamagePercent.Value / 100
--             damage = math.min(damage, maxDamage)
--         end

--         local hitsLeft = math.ceil(entity.Health.Value / damage)
--         -- if hitsLeft <= 3 then
--             return hitsLeft
--         -- end
--     end
-- end)()

local MiscSkill = {}

-- ===================== SKILL PRIORITY / STAMINA GATE =====================
-- Lower priority number fires first; the other skill waits until the first
-- one has been used (is on cooldown). 'Use skills at stamina' holds both
-- until stamina regens to that %; once the first one fires, a short combo
-- window lets the second follow even though stamina just dropped.
local skillComboUntil = 0
local SKILL_COMBO_WINDOW = 3

local staminaPercent = function()
    local maxValue = (pcall(function() return Stamina.MaxValue end)) and Stamina.MaxValue or nil
    if type(maxValue) ~= 'number' or maxValue <= 0 then maxValue = 100 end
    return Stamina.Value / maxValue * 100
end

local skillPriority = function(which)
    local opt = Options[which == 'Main' and 'MainSkillPriority' or 'MiscSkillPriority']
    return opt and opt.Value or 1
end

-- misc skills that only fire situationally (heal at low HP, tree at low
-- stamina) can't be waited on - otherwise Main would stall forever
local miscIsOrderable = function()
    return MiscSkill.Name == 'Cursed Enhancement'
end

skillGate = function(which)
    local self, other = KillauraSkill, MiscSkill
    if which == 'Misc' then self, other = MiscSkill, KillauraSkill end
    local otherName = other.Name and (which == 'Main' and miscIsOrderable() or which == 'Misc')

    -- ordering: the other skill has a lower priority number and hasn't gone yet
    if otherName and skillPriority(which == 'Main' and 'Misc' or 'Main') < skillPriority(which)
        and not other.OnCooldown then
        return false
    end

    if tick() < skillComboUntil then return true end

    local threshold = Options.SkillStaminaPercent and Options.SkillStaminaPercent.Value or 0
    if threshold > 0 then
        if staminaPercent() < threshold then return false end
        -- enough for both when they're paired, so the second one isn't starved
        if otherName and not other.OnCooldown and Stamina.Value < self.Cost + other.Cost then
            return false
        end
    end
    return true
end

-- called when a gated skill actually fires: opens the window for its partner
skillFired = function()
    skillComboUntil = tick() + SKILL_COMBO_WINDOW
end

local skillDurations = {
    ["Sweeping Strike"] = 1.4,
    ["Downward Smash"] = 1,
    ["Leaping Slash"] = 1.8,
    ["Piercing Dash"] = 1,
    ["Beam Rush"] = 2.8,
    -- ["Reaper Frenzy"] = 4.2,
    -- ["Whirlwind Spin"] = 1,

    -- ["Infinity Slash"] = 1,
    ["Summon Pistol"] = 0.2,
    ["Meteor Shot"] = 1,

    ["Everfrost Strike"] = 1.5,

    ["Cursed Three Fold Slash"] = 3.3,
    ["Water Blast"] = 1.2,

    -- idk these durations + cant test bc dont have skills :(
    ["Spearitual Strike"] = 1,
}

-- the game sends a different 3rd arg per skill (decompiled Skills service) -
-- most skills send NOTHING; spamming a Direction table gets the cast rejected
local SKILL_USE_ARGS = {
    ['Mending Spirit'] = 'Direction',
    ['Solstice Echoes'] = 'Direction',
    ['Meteor Shot'] = 'Direction',
    ['Summon Pistol'] = 'Direction',
    ['Summon Tree'] = 'Direction',
    ['Sweeping Strike'] = 'Direction',
    ['Leaping Slash'] = 'Direction',
    ['Cursed Three Fold Slash'] = 'TimeStarted',
}
local fireUseSkill = function(name)
    local payload = { 'UseSkill', name }
    local kind = SKILL_USE_ARGS[name]
    if kind == 'Direction' then
        payload[3] = { Direction = HumanoidRootPart.CFrame.LookVector }
    elseif kind == 'TimeStarted' then
        payload[3] = { TimeStarted = workspace:GetServerTimeNow() }
    end
    Event:FireServer('Skills', payload)
end

KillauraSkill._use = function()
    if MiscSkill._onKillauraSkill then
        MiscSkill._onKillauraSkill()
    end
    local self = KillauraSkill
    fireUseSkill(self.Name)
    skillFired()
    self.OnCooldown = true
    self.Active = true
    local skillDuration = skillDurations[self.Name] or 0
    task.delay(skillDuration, function()
        -- self.LastHit = true
        -- task.wait(0.5)
        -- self.LastHit = false
        self.Active = false
        if Toggles.ResetOnLowStamina.Value and Stamina.Value < KillauraSkill.Cost then
            Humanoid.Health = 0
        end
        task.wait(self.Cooldown - skillDuration)
        self.OnCooldown = false
    end)
end

KillauraSkill.Use = function()
    if Humanoid.Health == 0 then return end

    local self = KillauraSkill
    if not self.Name then return end
    if self.OnCooldown then return end
    if self.Cost > Stamina.Value then return end
    if not skillGate('Main') then
        -- misc only re-checks on Health/Stamina changes; at steady stamina
        -- nothing fires, so poke it or Main would wait on it forever
        if MiscSkill._tryUse then task.spawn(pcall, MiscSkill._tryUse) end
        return
    end

    if not self.Class then
        return self._use()
    end

    if not self.GetSword() then
        Library:Notify("Get a " .. self.Class:lower() .. " you can equip first")
        return Options.MainSkill:SetValue()
    end

    if self.Sword ~= rightSword then
        local rightSwordOld = rightSword
        local leftSwordOld = leftSword

        InvokeFunction('Equipment', { 'EquipWeapon', self.Sword, 'Right' })

        self._use()
        if rightSwordOld then
            local staminaOld = Stamina.Value
            awaitEventTimeout(Stamina.Changed, function(value)
                if staminaOld - value == self.Cost then
                    return true
                end
                staminaOld = value
            end, 0.1)
            task.wait(0.05)
            InvokeFunction('Equipment', { 'EquipWeapon', rightSwordOld, 'Right' })
            if leftSwordOld then
                InvokeFunction('Equipment', { 'EquipWeapon', leftSwordOld, 'Left' })
            end
        end
        return
    end

    if not leftSword then
        return self._use()
    end

    local leftSwordOld = leftSword
    InvokeFunction('Equipment', { 'Unequip', leftSwordOld })
    self._use()
    local staminaOld = Stamina.Value
    awaitEventTimeout(Stamina.Changed, function(value)
        if staminaOld - value == self.Cost then
            return true
        end
        staminaOld = value
    end, 0.1)
    InvokeFunction('Equipment', { 'EquipWeapon', leftSwordOld, 'Left' })
end

dealDamage = (function()
    if RequiredServices then
        return RequiredServices.Combat.DealDamage
    end

    local RPCKey = Function:InvokeServer('RPCKey', 'Combat') -- channel name, like the game
    return function(target, attackName)
        Event:FireServer('Combat', RPCKey, { 'Attack', target, attackName, '2' })
    end
end)()

onCooldown = {}

attack = function(target)
    if isDead(target) then return end

    if target.Entity.Health:FindFirstChild(LocalPlayer.Name) then -- Toggles.UseSkillPreemptively.Value or
        KillauraSkill.Use()
    end

    if isDead(target) then return end

    -- local threads = getKillauraThreads(target.Entity)

    -- for _ = 1, threads do
        dealDamage(target, KillauraSkill.Active and KillauraSkill.Name or nil)
    -- end

    onCooldown[target] = true
    task.delay(Options.KillauraDelay.Value, function()
        onCooldown[target] = nil
    end)

    return true
end

stopSwingFunction = nil
swingFunction = (function()
    -- prefer the Actions service swing: a bare getgc scan for 'Swing' can grab
    -- an enemy skill's u3.Swing (RubricatusSlam etc.) - calling it argless
    -- errors inside their module and never swings our sword
    if RequiredServices then
        stopSwingFunction = RequiredServices.Actions.StopSwing
        return RequiredServices.Actions.StartSwing
    end
    if not getgc then return end
    for _, func in next, getgc() do
        if type(func) == 'function' and debug.info(func, 'n') == 'Swing' then
            -- only the player swing inside the Actions service counts
            local src = debug.info(func, 's') or ''
            if src:find('Services.Actions') then
                stopSwingFunction = function() end
                return func
            end
        end
    end
end)()

Killaura:AddToggle('Killaura', { Text = 'Enabled' }):OnChanged(function()
    toggleSwingDamage(false)
    while Toggles.Killaura.Value do
        task.wait(0.01)

        if Humanoid.Health == 0 then continue end

        local attacked = 0

        for _, target in next, Mobs:GetChildren() do
            -- if attacked >= Options.KillauraMaxTargets.Value then
            --     break
            -- end
            if onCooldown[target] then continue end
            if isDead(target) or mobIsImmortal(target) then continue end
            if not assistRequirement(target) then continue end
            if tagGate(target) then continue end
            local rootPart = target:FindFirstChild('HumanoidRootPart')
            if not rootPart then continue end
            local targetPos = rootPart.Position + Vector3.new(
                0,
                (HumanoidRootPart.Size.Y - rootPart.Size.Y) * 0.5,
                0
            )
            if rootPart:FindFirstChild('BodyVelocity') and rootPart.BodyVelocity.VectorVelocity.Magnitude > 0 then
                targetPos += rootPart.BodyVelocity.VectorVelocity.Unit
            end
            local range = Options.KillauraRange.Value
            if range == Options.KillauraRange.Max then
                range = math.max(rootPart.Size.X, rootPart.Size.Z) * 0.5 + 20
            end
            if (targetPos - HumanoidRootPart.Position).Magnitude > range then
                continue
            end
            -- one malformed mob must never kill the whole attack loop
            local ok, err = pcall(attack, target)
            if ok then attacked += 1 end
        end

        if Toggles.AttackPlayers.Value then
            for _, player in next, Players:GetPlayers() do
                -- if attacked >= Options.KillauraMaxTargets.Value then
                --     break
                -- end
                if player == LocalPlayer then continue end
                if Options.IgnorePlayers.Value[player] then continue end
                local target = player.Character
                if not target then continue end
                if onCooldown[target] then continue end
                if isDead(target) then continue end
                local rootPart = target.HumanoidRootPart
                local range = Options.KillauraRange.Value
                if range == Options.KillauraRange.Max then
                    range = math.max(rootPart.Size.X, rootPart.Size.Z) * 0.5 + 20
                end
                if (rootPart.Position - HumanoidRootPart.Position).Magnitude > range then
                    continue
                end
                attack(target)
                attacked += 1
            end
        end

        if Toggles.KillauraSwing and Toggles.KillauraSwing.Value and swingFunction then
            task.spawn(attacked > 0 and swingFunction or stopSwingFunction)
        end
    end
    toggleSwingDamage(true)
end)

if swingFunction then
    Killaura:AddToggle('KillauraSwing', { Text = 'Swing', Default = true })
end

Killaura:AddSlider('KillauraDelay', {
    Text = 'Delay',
    Default = 0.3,
    Min = 0,
    Max = 2,
    Rounding = 1,
    Suffix = 's',
    -- FormatDisplayValue = function(slider, value)
    --     if value < 0.3 then return `{value}s/{slider.Max}s (debounce!)` end
	-- end
})
-- Killaura:AddSlider('KillauraThreads', {
--     Text = 'Threads',
--     Default = 11,
--     Min = 1,
--     Max = 11,
--     Rounding = 0,
--     Suffix = ' attack(s)',
--     FormatDisplayValue = function(slider, value)
--         if value == slider.Max then return 'Auto' end
--         return `{value} attack(s)/10 attack(s)`
-- 	end
-- })
Killaura:AddSlider('KillauraRange', {
    Text = 'Range',
    Default = 120,
    Min = 0,
    Max = 120,
    Rounding = 0,
    Suffix = 'm',
    FormatDisplayValue = function(slider, value)
        if value == slider.Max then return 'Auto' end
	end
})
-- Killaura:AddSlider('KillauraMaxTargets', {
--     Text = 'Max targets',
--     Default = 1,
--     Min = 1,
--     Max = 100,
--     Rounding = 0,
--     Suffix = ''
-- })
Killaura:AddToggle('AttackPlayers', {Text = 'Attack players' }):OnChanged(function(value)
    local holder = Options.IgnorePlayers and Options.IgnorePlayers.Holder
    if holder then
        holder.Visible = value
        Killaura:Resize()
    end
end)
local ignorePlayersDropdown = Killaura:AddDropdown('IgnorePlayers', { Text = 'Ignore players', Values = {}, Multi = true, SpecialType = 'Player' })
if ignorePlayersDropdown.Holder then
    ignorePlayersDropdown.Holder.Visible = false
    Killaura:Resize()
end

Killaura:AddDropdown('MainSkill', { Text = 'Main skill', Default = 1, Values = {}, AllowNull = true })
:OnChanged(function(value)
    if not value then
        return KillauraSkill.Init()
    end

    local name = value:gsub(' [(].+$', '')
    local inDatabase = Skills[name]
    local class = inDatabase:FindFirstChild('Class') and inDatabase.Class.Value
    if class then
        class = class == 'SingleSword' and '1HSword' or class

        if not KillauraSkill.GetSword(class) then
            Library:Notify("Get a " .. class .. " you can equip first")
            return Options.MainSkill:SetValue()
        end
    end

    KillauraSkill.Init(
        name,
        inDatabase.Cost.Value,
        inDatabase.Cooldown.Value,
        class,
        KillauraSkill.Sword
    )
end)

do
    local mainSkillNames = {
        ["Sweeping Strike"] = "Sweeping Strike (x3, 1.4s)",
        ["Downward Smash"] = "Downward Smash (x2.75, 1s)",
        ["Leaping Slash"] = "Leaping Slash (x3.3, 1.8s)",
        ["Piercing Dash"] = "Piercing Dash (x3.2, 1s)",
        ["Beam Rush"] = "Beam Rush (x2.8, 2.8s)",
        -- ["Reaper Frenzy"] = "Reaper Frenzy (x1)",
        -- ["Whirlwind Spin"] = "Whirlwind Spin (x4)",

        -- ["Infinity Slash"] = "Infinity Slash (x5)",
        ["Summon Pistol"] = "Summon Pistol (x4.35, 0.2s)",
        ["Meteor Shot"] = "Meteor Shot (x3.1, 1s)",

        -- ["Eggsellent Shield"] = "Eggsellent Shield (x4) (15k base)",
        ["Everfrost Strike"] = "Everfrost Strike (x3.5) (10k base)",
        -- ["Realm Judgement"] = "Realm Judgement (x1.25) (10k base)",
        -- ["Realm Banishment"] = "Realm Banishment (x0) (25k base)",

        ["Spearitual Strike"] = "Spearitual Strike (x7) (40k base)",
        ["Cursed Three Fold Slash"] = "Cursed Three Fold Slash (x5.1)",
        ["Water Blast"] = "Water Blast (x4) (75k base)",
    }

    MySkills.ChildAdded:Connect(function(skill)
        local displayName = mainSkillNames[skill.Name]
        if not displayName then return end
        table.insert(Options.MainSkill.Values, displayName)
        Options.MainSkill:SetValues(Options.MainSkill.Values)
        if Options.MainSkill.Holder then
            Options.MainSkill.Holder.Visible = true
            Killaura:Resize()
        end
    end)

    for skillName, displayName in next, mainSkillNames do
        local SkillInDatabase = Skills:FindFirstChild(skillName)
        if SkillInDatabase:FindFirstChild("Unlock") and not MySkills:FindFirstChild(skillName) then
            continue
        end
        if SkillInDatabase:FindFirstChild("Level") and getLevel() < SkillInDatabase.Level.Value then
            continue
        end
        table.insert(Options.MainSkill.Values, displayName)
    end
    Options.MainSkill:SetValues(Options.MainSkill.Values)
    if Options.MainSkill.Holder then
        Options.MainSkill.Holder.Visible = #Options.MainSkill.Values > 0
        Killaura:Resize()
    end
end

-- Killaura:AddToggle('UseSkillPreemptively', { Text = 'Use skill preemptively' })

MiscSkill.Init = function(name, cost, cooldown)
    local self = MiscSkill
    self.Name = name
    self.Cost = cost or 0
    self.Cooldown = cooldown or 0
    self.OnCooldown = false
    for _, connection in self._connections or {} do
        connection:Disconnect()
    end
    self._connections = {}
    self._onKillauraSkill = nil
    self._tryUse = nil
end

MiscSkill.Init()

MiscSkill._use = function()
    local self = MiscSkill
    fireUseSkill(self.Name)
    skillFired()
    self.OnCooldown = true
    task.delay(self.Cooldown, function()
        self.OnCooldown = false
    end)
end

Killaura:AddDropdown('MiscSkill', { Text = 'Misc skill', Values = {}, AllowNull = true })
:OnChanged(function(value)
    local self = MiscSkill

    if not value then
        return self.Init()
    end

    local name = value:gsub(' [(].+$', '')
    local inDatabase = Skills[name]

    self.Init(
        name,
        inDatabase.Cost.Value,
        inDatabase.Cooldown.Value
    )

    local func
    if name == 'Heal' or name == 'Mending Spirit' then
        func = function()
            if not Toggles.Killaura.Value then return end
            if Stamina.Value < self.Cost then return end
            if self.OnCooldown then return end
            if (Health.Value / Health.MaxValue) > 0.66 then return end
            self._use()
        end
    elseif name == 'Summon Tree' then
        func = function()
            if not Toggles.Killaura.Value then return end
            if Stamina.Value < self.Cost then return end
            if self.OnCooldown then return end
            if Stamina.Value > 66 then return end
            self._use()
        end
    elseif name == 'Cursed Enhancement' then
        func = function()
            if not Toggles.Killaura.Value then return end
            if Stamina.Value < self.Cost then return end
            if self.OnCooldown then return end
            if not skillGate('Misc') then return end
            self._use()
            awaitEventTimeout(
                Character:GetAttributeChangedSignal('CursedEnhancement'),
                function()
                    return Character:GetAttribute('CursedEnhancement')
                end,
                0.1
            )
        end
    end
    self._tryUse = func
    self._connections.health = Health.Changed:Connect(func)
    self._connections.stamina = Stamina.Changed:Connect(func)
end)

Killaura:AddSlider('MainSkillPriority', {
    Text = 'Main skill priority',
    Tooltip = 'Lower fires first. Misc 1 + Main 2 = wait for Misc, then Main',
    Default = 1, Min = 1, Max = 2, Rounding = 0, Compact = true
})
Killaura:AddSlider('MiscSkillPriority', {
    Text = 'Misc skill priority',
    Tooltip = 'Only Cursed Enhancement is ordered - Heal / Mending Spirit / Summon Tree stay situational',
    Default = 2, Min = 1, Max = 2, Rounding = 0, Compact = true
})
Killaura:AddSlider('SkillStaminaPercent', {
    Text = 'Use skills at stamina',
    Tooltip = 'Wait for stamina to regen to this % before firing the skill pair. 0 = off',
    Default = 0, Min = 0, Max = 100, Rounding = 0, Suffix = '%', Compact = true
})

do
    local miscSkillNames = {
        ["Cursed Enhancement"] = "Cursed Enhancement (x2.5)",
        ["Heal"] = "Heal (30%)",
        ["Mending Spirit"] = "Mending Spirit (4%/s)",
        ["Summon Tree"] = "Summon Tree (6%/s)",
    }

    MySkills.ChildAdded:Connect(function(skill)
        local displayName = miscSkillNames[skill.Name]
        if not displayName then return end
        table.insert(Options.MiscSkill.Values, displayName)
        Options.MiscSkill:SetValues(Options.MiscSkill.Values)
        if Options.MiscSkill.Holder then
            Options.MiscSkill.Holder.Visible = true
            Killaura:Resize()
        end
    end)

    for skillName, displayName in next, miscSkillNames do
        local SkillInDatabase = Skills:FindFirstChild(skillName)
        if SkillInDatabase:FindFirstChild("Unlock") and not MySkills:FindFirstChild(skillName) then
            continue
        end
        if SkillInDatabase:FindFirstChild("Level") and getLevel() < SkillInDatabase.Level.Value then
            continue
        end
        table.insert(Options.MiscSkill.Values, displayName)
    end
    Options.MiscSkill:SetValues(Options.MiscSkill.Values)
    if Options.MiscSkill.Holder then
        Options.MiscSkill.Holder.Visible = #Options.MiscSkill.Values > 0
        Killaura:Resize()
    end
end

