-- Bluu :: TheBetween  (wave-defense place helpers; inert everywhere else)
-- State comes from attributes the game's WaveDefense UI reads:
--   workspace: Wave, MobsLeft, WaveProgressLeft, WaveCountdown, WDRunTime,
--              WaveDefenseMode, CurrencyEarned
--   LocalPlayer: Lives, Revives
-- Remotes (UniqueFloorTypes -> WaveDefense): Revive (Function), Return (Event)

if not IN_BETWEEN then return end

local Between = Misc:AddRightGroupbox('The Between')

local waveLabel = Between:AddLabel('Wave: -', true)

Between:AddToggle('BetweenAutoRevive', {
    Text = 'Auto revive',
    Default = true,
    Tooltip = 'Uses a life to revive the moment you die (only while you still have lives)'
})
Between:AddToggle('BetweenLeaveAtWave', {
    Text = 'Leave at wave',
    Tooltip = 'Return to the lobby once the selected wave is reached (secures the run rewards)'
})
Between:AddSlider('BetweenLeaveWave', { Text = 'Wave', Default = 30, Min = 1, Max = 100, Rounding = 0, Compact = true })

Between:AddToggle('BetweenBlackoutLight', {
    Text = 'Stay in soul light',
    Default = true,
    Tooltip = 'Blackout wave: stay near the light orb and only farm mobs inside its light'
})

Between:AddToggle('BetweenGlowFirst', {
    Text = 'Kill glowing mobs first',
    Default = true,
    Tooltip = 'Waves that mark objective mobs with a Glow inside their root: only those count - target them over everything else'
})

Between:AddToggle('BetweenBobFlee', {
    Text = 'Flee from Bob',
    Default = true,
    Tooltip = 'Bob wave: keep this distance from every Bob - out of reach of its attacks'
})
Between:AddSlider('BetweenBobDistance', { Text = 'Bob distance', Default = 300, Min = 50, Max = 1000, Rounding = 0, Compact = true })

-- active special-wave type ('Blackout', 'Bob', 'Wisp', ...), set by ReplicateWave
BetweenWaveType = nil

-- Blackout wave: the orb is the only light source; its LightDuration attribute
-- is both the remaining "Souls" count and the light radius (PointLight.Range).
-- The orb instance arrives on ReplicateWave as ('StartReplicatedOrb', orb, max).
BlackoutOrb = nil
BlackoutLight = function()
    local orb = BlackoutOrb
    if not (orb and orb.Parent) then return end
    local part = orb:FindFirstChild('Part')
    if not part then return end
    local range = orb:GetAttribute('LightDuration')
    if type(range) ~= 'number' then
        local light = part:FindFirstChildOfClass('PointLight')
        range = light and light.Range
    end
    if not range or range <= 0 then return end
    return part.Position, range
end

local attr = function(name, default)
    local v = workspace:GetAttribute(name)
    if v == nil then return default end
    return v
end

local updateLabel = function()
    local lives = LocalPlayer:GetAttribute('Lives')
    local left = attr('WaveProgressLeft', nil) or attr('MobsLeft', 0)
    local countdown = attr('WaveCountdown', nil)
    local text = `Wave #{attr('Wave', 0)} ({attr('WaveDefenseMode', '?')})  |  Mobs left: {left}`
    text ..= `\nLives: {lives or '?'}  |  Time: {attr('WDRunTime', '-')}  |  Remnants: {attr('CurrencyEarned', 0)}`
    if countdown then text ..= `\nNext wave in: {countdown}` end
    if BetweenWaveType then text ..= `\nSpecial wave: {BetweenWaveType}` end
    local _, lightRange = BlackoutLight()
    if lightRange then text ..= `\nSoul light: {math.floor(lightRange)} studs` end
    waveLabel:SetText(text)
end

for _, name in next, { 'Wave', 'MobsLeft', 'WaveProgressLeft', 'WaveCountdown', 'WDRunTime', 'CurrencyEarned', 'WaveDefenseMode' } do
    workspace:GetAttributeChangedSignal(name):Connect(updateLabel)
end
LocalPlayer:GetAttributeChangedSignal('Lives'):Connect(updateLabel)
updateLabel()

task.spawn(function()
    local ReplicateWave = game:GetService('ReplicatedStorage'):WaitForChild('ReplicateWave', 30)
    if not ReplicateWave then return end
    ReplicateWave.OnClientEvent:Connect(function(waveType, event, a)
        if event == 'Start' then
            BetweenWaveType = waveType
            updateLabel()
        elseif event == 'StartReplicatedOrb' and typeof(a) == 'Instance' then
            BlackoutOrb = a
            a:GetAttributeChangedSignal('LightDuration'):Connect(updateLabel)
            a.AncestryChanged:Connect(function(_, parent)
                if not parent and BlackoutOrb == a then BlackoutOrb = nil end
            end)
            updateLabel()
        elseif event == 'Stop' then
            BetweenWaveType = nil
            BlackoutOrb = nil
            updateLabel()
        end
    end)
end)

-- revive as soon as we're dead and have lives; the server rejects it while
-- we're alive, so retry until the new character spawns
local reviving = false
local tryRevive = function()
    if reviving or not Toggles.BetweenAutoRevive.Value then return end
    reviving = true
    task.spawn(function()
        local deadChar = Character
        for _ = 1, 20 do
            if Character ~= deadChar and Humanoid and Humanoid.Health > 0 then break end
            if not Toggles.BetweenAutoRevive.Value then break end
            if (LocalPlayer:GetAttribute('Lives') or 0) <= 0 then break end
            pcall(function()
                Function:InvokeServer('UniqueFloorTypes', { 'WaveDefense', 'Revive' })
            end)
            task.wait(1)
        end
        reviving = false
    end)
end

local hookDeath = function(character)
    local humanoid = character:WaitForChild('Humanoid', 10)
    if humanoid then humanoid.Died:Connect(tryRevive) end
end
if Character then task.spawn(hookDeath, Character) end
LocalPlayer.CharacterAdded:Connect(hookDeath)

local leaving = false
workspace:GetAttributeChangedSignal('Wave'):Connect(function()
    if leaving or not Toggles.BetweenLeaveAtWave.Value then return end
    if attr('Wave', 0) < Options.BetweenLeaveWave.Value then return end
    leaving = true
    Library:Notify(`Reached wave {attr('Wave', 0)} - returning to the lobby`, 5)
    Event:FireServer('UniqueFloorTypes', { 'WaveDefense', 'Return' })
end)
