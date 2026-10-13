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
    waveLabel:SetText(text)
end

for _, name in next, { 'Wave', 'MobsLeft', 'WaveProgressLeft', 'WaveCountdown', 'WDRunTime', 'CurrencyEarned', 'WaveDefenseMode' } do
    workspace:GetAttributeChangedSignal(name):Connect(updateLabel)
end
LocalPlayer:GetAttributeChangedSignal('Lives'):Connect(updateLabel)
updateLabel()

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
