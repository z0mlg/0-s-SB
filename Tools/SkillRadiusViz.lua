-- SkillRadiusViz :: standalone skill-range visualizer for Swordburst 2
-- Run on its own (no main script needed):
--   loadstring(game:HttpGet('https://raw.githubusercontent.com/z0mlg/Sb2Cheats/refs/heads/main/Tools/SkillRadiusViz.lua'))()
--
-- Keys:
--   [ / ]   shrink/grow the ring (hold Shift for +-1, default +-5)
--   N       cycle the ring anchor: you -> each player in the server -> you
--   F       freeze a marker disc at the current ring (for comparing spots)
--   V       clear frozen markers
--   G       print how many mobs are inside the ring right now
--   T       toggle auto-measure of newly spawned skill parts/models
--   P       print the last measurements again
--
-- Output goes to rconsole when available, else the normal print output.

local Players = game:GetService('Players')
local RunService = game:GetService('RunService')
local UserInputService = game:GetService('UserInputService')

local LocalPlayer = Players.LocalPlayer
local Mobs = workspace:WaitForChild('Mobs', 10)

local say
if type(rconsolecreate) == 'function' and type(rconsoleprint) == 'function' then
    pcall(rconsolecreate)
    pcall(function() rconsolesettitle('SkillRadiusViz') end)
    say = function(msg) pcall(rconsoleprint, msg .. '\n') end
else
    say = print
end
say('[SkillViz] loaded - keys: [ ] resize, N anchor, F mark, V clear, G mobs, T auto-measure, P reprint')

-- ===================== RING =====================
local ringRadius = 25
local anchorPlayer = LocalPlayer

local ring = Instance.new('Part')
ring.Name = 'SkillVizRing'
ring.Shape = Enum.PartType.Cylinder
ring.Anchored = true
ring.CanCollide = false
ring.CanQuery = false
ring.CanTouch = false
ring.CastShadow = false
ring.Transparency = 0.55
ring.Material = Enum.Material.Neon
ring.Color = Color3.fromRGB(80, 200, 255)
ring.Parent = workspace

local ringInner = ring:Clone()
ringInner.Color = Color3.fromRGB(30, 90, 120)
ringInner.Transparency = 0.75
ringInner.Parent = workspace

local function updateRing()
    local char = anchorPlayer and anchorPlayer.Character
    local root = char and char:FindFirstChild('HumanoidRootPart')
    if not root then
        ring.Transparency = 1
        ringInner.Transparency = 1
        return
    end
    ring.Transparency = 0.55
    ringInner.Transparency = 0.75
    local pos = root.Position - Vector3.new(0, root.Size.Y * 0.5 + 2.4, 0)
    -- cylinder axis is X: rotate 90 deg around Z so it lies flat
    ring.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
    ring.Size = Vector3.new(0.2, ringRadius * 2, ringRadius * 2)
    ringInner.CFrame = ring.CFrame
    ringInner.Size = Vector3.new(0.15, (ringRadius - 1) * 2, (ringRadius - 1) * 2)
end

local function mobsInside()
    local char = anchorPlayer and anchorPlayer.Character
    local root = char and char:FindFirstChild('HumanoidRootPart')
    if not (root and Mobs) then return 0, {} end
    local count, names = 0, {}
    for _, mob in ipairs(Mobs:GetChildren()) do
        local mroot = mob:FindFirstChild('HumanoidRootPart')
        if mroot then
            local d = (Vector3.new(mroot.Position.X, 0, mroot.Position.Z)
                - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude
            if d <= ringRadius then
                count += 1
                names[mob.Name] = (names[mob.Name] or 0) + 1
            end
        end
    end
    return count, names
end

RunService.RenderStepped:Connect(updateRing)

-- ===================== MARKERS =====================
local markers = {}
local function dropMarker()
    local char = anchorPlayer and anchorPlayer.Character
    local root = char and char:FindFirstChild('HumanoidRootPart')
    if not root then return end
    local m = Instance.new('Part')
    m.Name = 'SkillVizMarker'
    m.Shape = Enum.PartType.Cylinder
    m.Anchored = true
    m.CanCollide = false
    m.CanQuery = false
    m.CanTouch = false
    m.Transparency = 0.6
    m.Material = Enum.Material.Neon
    m.Color = Color3.fromRGB(255, 200, 60)
    m.CFrame = CFrame.new(root.Position - Vector3.new(0, root.Size.Y * 0.5 + 2.4, 0))
        * CFrame.Angles(0, 0, math.rad(90))
    m.Size = Vector3.new(0.15, ringRadius * 2, ringRadius * 2)
    m.Parent = workspace
    table.insert(markers, m)
    say(string.format('[SkillViz] marker dropped r=%d @ %s', ringRadius, tostring(root.Position)))
end

-- ===================== AUTO-MEASURE =====================
local autoMeasure = true
local lastPrints = {}
local tracked = setmetatable({}, { __mode = 'k' })

local function visualFor(inst, radius, cf)
    local v = tracked[inst]
    if not v then
        v = Instance.new('Part')
        v.Name = 'SkillVizMeasure'
        v.Shape = Enum.PartType.Cylinder
        v.Anchored = true
        v.CanCollide = false
        v.CanQuery = false
        v.CanTouch = false
        v.Transparency = 0.55
        v.Material = Enum.Material.Neon
        v.Color = Color3.fromRGB(255, 80, 80)
        v.Parent = workspace
        tracked[inst] = v
        task.delay(8, function()
            if v and v.Parent then v:Destroy() end
        end)
    end
    v.CFrame = CFrame.new(cf.Position) * CFrame.Angles(0, 0, math.rad(90))
    v.Size = Vector3.new(0.2, radius * 2, radius * 2)
    return v
end

local function nearestPlayerDist(pos)
    local best = math.huge
    for _, pl in ipairs(Players:GetPlayers()) do
        local root = pl.Character and pl.Character:FindFirstChild('HumanoidRootPart')
        if root then
            best = math.min(best, (root.Position - pos).Magnitude)
        end
    end
    return best
end

local function measure(inst)
    if not inst:IsDescendantOf(workspace) then return end
    -- skip characters, mobs and anything inside them
    local model = inst:FindFirstAncestorOfClass('Model')
    if model then
        if model:FindFirstChildOfClass('Humanoid') then return end
        if Mobs and inst:IsDescendantOf(Mobs) then return end
    end
    if inst:IsDescendantOf(LocalPlayer.Character or script) then return end

    local cf, size
    if inst:IsA('BasePart') then
        cf, size = inst.CFrame, inst.Size
    elseif inst:IsA('Model') then
        local ok, c, s = pcall(function()
            return inst:GetPivot(), inst:GetExtentsSize()
        end)
        if not ok then return end
        cf, size = c, s
    else
        return
    end

    if nearestPlayerDist(cf.Position) > 350 then return end

    -- resample over a few seconds: many skill visuals tween to full size
    local delay = 0
    for _, t in ipairs({ 0.1, 0.8, 2.0, 3.5 }) do
        task.delay(t, function()
            if not inst:IsDescendantOf(workspace) then return end
            local ok, c, s = pcall(function()
                if inst:IsA('BasePart') then
                    return inst.CFrame, inst.Size
                end
                return inst:GetPivot(), inst:GetExtentsSize()
            end)
            if not ok then return end
            cf, size = c, s
            local r = math.max(size.X, size.Z) * 0.5
            if r < 2 then return end
            visualFor(inst, r, cf)
            local line = string.format(
                '[SkillViz] %s (%s) XZ-radius ~%.1f @ %.0f away',
                inst:GetFullName(), inst.ClassName, r,
                nearestPlayerDist(cf.Position)
            )
            if lastPrints[#lastPrints] ~= line then
                table.insert(lastPrints, line)
                if #lastPrints > 15 then table.remove(lastPrints, 1) end
                say(line)
            end
        end)
        delay = t
    end
end

workspace.DescendantAdded:Connect(function(inst)
    if not autoMeasure then return end
    if not (inst:IsA('BasePart') or inst:IsA('Model')) then return end
    task.defer(measure, inst)
end)

-- ===================== KEYBINDS =====================
local anchorList = {}
local anchorIdx = 0

local function rebuildAnchors()
    anchorList = { LocalPlayer }
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl ~= LocalPlayer then table.insert(anchorList, pl) end
    end
    anchorIdx = math.min(anchorIdx, #anchorList)
end
rebuildAnchors()
Players.PlayerAdded:Connect(rebuildAnchors)
Players.PlayerRemoving:Connect(rebuildAnchors)

UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
        or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
    local step = shift and 1 or 5

    if input.KeyCode == Enum.KeyCode.RightBracket then
        ringRadius = math.min(500, ringRadius + step)
        say(('[SkillViz] radius = %d'):format(ringRadius))
    elseif input.KeyCode == Enum.KeyCode.LeftBracket then
        ringRadius = math.max(1, ringRadius - step)
        say(('[SkillViz] radius = %d'):format(ringRadius))
    elseif input.KeyCode == Enum.KeyCode.N then
        rebuildAnchors()
        anchorIdx = anchorIdx % #anchorList + 1
        anchorPlayer = anchorList[anchorIdx]
        say(('[SkillViz] ring anchored to %s'):format(anchorPlayer.Name))
    elseif input.KeyCode == Enum.KeyCode.F then
        dropMarker()
    elseif input.KeyCode == Enum.KeyCode.V then
        for _, m in ipairs(markers) do m:Destroy() end
        markers = {}
        say('[SkillViz] markers cleared')
    elseif input.KeyCode == Enum.KeyCode.G then
        local count, names = mobsInside()
        local parts = {}
        for n, c in pairs(names) do table.insert(parts, ('%sx %s'):format(c, n)) end
        say(('[SkillViz] mobs inside r=%d: %d%s'):format(
            ringRadius, count, #parts > 0 and (' - ' .. table.concat(parts, ', ')) or ''))
    elseif input.KeyCode == Enum.KeyCode.T then
        autoMeasure = not autoMeasure
        say(('[SkillViz] auto-measure %s'):format(autoMeasure and 'ON' or 'OFF'))
    elseif input.KeyCode == Enum.KeyCode.P then
        for _, line in ipairs(lastPrints) do say(line) end
    end
end)
