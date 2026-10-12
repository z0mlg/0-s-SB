-- Water Domain (DomainMumur) radius probe -- standalone, no casting needed.
-- Finds the game's Whirlpool template model, measures it at several PowerScale
-- values, and draws rings + a real clone in front of you so you can see the
-- domain's actual footprint. Paste-execute in your executor.

local Players = game:GetService('Players')
local RunService = game:GetService('RunService')
local LocalPlayer = Players.LocalPlayer

local SCALES = { 0.75, 1, 1.5, 2, 2.5, 3 } -- PowerScale guesses to preview
local COLORS = {
    Color3.fromRGB(120, 120, 255), Color3.fromRGB(60, 170, 255), Color3.fromRGB(60, 255, 170),
    Color3.fromRGB(255, 220, 80), Color3.fromRGB(255, 140, 60), Color3.fromRGB(255, 70, 70),
}

local function modelRadius(model)
    local ok, size = pcall(model.GetExtentsSize, model)
    if not (ok and size) then return nil end
    return math.max(size.X, size.Z) * 0.5
end

-- the template lives inside the skill's module assets, usually nil-parented
local function findWhirlpoolTemplate()
    local function isWhirlpool(inst)
        return inst:IsA('Model') and inst.Name == 'Whirlpool'
    end
    for _, inst in ipairs(workspace:GetDescendants()) do
        if isWhirlpool(inst) then return inst end
    end
    for _, func in ipairs({ getloadedmodules, getnilinstances }) do
        if type(func) ~= 'function' then continue end
        local ok, list = pcall(func)
        if not ok then continue end
        for _, inst in ipairs(list) do
            if isWhirlpool(inst) then return inst end
            for _, d in ipairs(inst:GetDescendants()) do
                if isWhirlpool(d) then return d end
            end
        end
    end
end

-- ============ measure the template at each PowerScale ============
local results = {}
local template = findWhirlpoolTemplate()
if template then
    for _, scale in ipairs(SCALES) do
        local probe = template:Clone()
        local ok = pcall(probe.ScaleTo, probe, scale)
        results[scale] = ok and modelRadius(probe) or nil
        probe:Destroy()
    end
    local baseRadius = modelRadius(template)
    print(('[WaterDomain] template found. base radius (scale 1): %s'):format(
        baseRadius and ('%.1f studs'):format(baseRadius) or 'unmeasurable'))
    for _, scale in ipairs(SCALES) do
        local r = results[scale]
        print(('[WaterDomain]   PowerScale %.2f -> r = %s'):format(scale,
            r and ('%.1f studs'):format(r) or '?'))
    end
else
    warn('[WaterDomain] Whirlpool template not found - live tracking still active')
end

-- ============ draw rings at the preview spot ============
local cleanup = {}
local function spawnLabel(pos, text, color)
    local anchor = Instance.new('Part')
    anchor.Anchored = true
    anchor.CanCollide = false
    anchor.CanQuery = false
    anchor.CanTouch = false
    anchor.Transparency = 1
    anchor.Position = pos
    anchor.Size = Vector3.one
    anchor.Parent = workspace

    local gui = Instance.new('BillboardGui')
    gui.AlwaysOnTop = true
    gui.Size = UDim2.fromOffset(260, 30)
    gui.StudsOffset = Vector3.new(0, 3, 0)
    gui.Adornee = anchor
    gui.Parent = anchor

    local label = Instance.new('TextLabel')
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBold
    label.TextSize = 15
    label.TextColor3 = color
    label.TextStrokeTransparency = 0
    label.Text = text
    label.Parent = gui

    table.insert(cleanup, anchor)
    return anchor
end

local function drawRing(center, radius, color, text)
    local segs = math.clamp(math.floor(radius * 2), 32, 160)
    for i = 1, segs do
        local a = i / segs * math.pi * 2
        local p = Instance.new('Part')
        p.Shape = Enum.PartType.Ball
        p.Size = Vector3.new(0.8, 0.8, 0.8)
        p.Position = center + Vector3.new(math.cos(a) * radius, 0.5, math.sin(a) * radius)
        p.Anchored = true
        p.CanCollide = false
        p.CanQuery = false
        p.CanTouch = false
        p.CastShadow = false
        p.Material = Enum.Material.Neon
        p.Color = color
        p.Parent = workspace
        table.insert(cleanup, p)
    end
    spawnLabel(center + Vector3.new(radius, 0, 0), text, color)
end

local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild('HumanoidRootPart')
local center = root and (root.Position + root.CFrame.LookVector * 15) or Vector3.new()
center = Vector3.new(center.X, center.Y, center.Z) -- keep player's height

if template then
    for i, scale in ipairs(SCALES) do
        local r = results[scale]
        if r then
            drawRing(center, r, COLORS[i], ('scale %.2f: r = %.1f'):format(scale, r))
        end
    end
    -- real VFX clone at scale 1 so you see the actual footprint
    local preview = template:Clone()
    preview.Name = 'WhirlpoolPreview' -- renamed so the live tracker ignores it
    preview:ScaleTo(1)
    preview:PivotTo(CFrame.new(center))
    preview.Parent = workspace
    table.insert(cleanup, preview)
    print('[WaterDomain] rings + scale-1 preview drawn 15 studs ahead of you')
    print('[WaterDomain] run this to clear:  for _, p in next, _G.WD_cleanup do p:Destroy() end')
else
    spawnLabel(center, 'Whirlpool template not found', COLORS[6])
end
_G.WD_cleanup = cleanup

-- ============ live tracker: any real cast gets its measured disc ============
local tracked = {}
local function removeEntry(model)
    local entry = tracked[model]
    if not entry then return end
    tracked[model] = nil
    if entry.disc then entry.disc:Destroy() end
end

local function track(model)
    if tracked[model] or model.Name ~= 'Whirlpool' then return end

    local disc = Instance.new('Part')
    disc.Name = 'WaterDomainRadius'
    disc.Anchored = true
    disc.CanCollide = false
    disc.CanQuery = false
    disc.CanTouch = false
    disc.CastShadow = false
    disc.Material = Enum.Material.Neon
    disc.Color = Color3.fromRGB(255, 255, 255)
    disc.Transparency = 0.4
    disc.Shape = Enum.PartType.Cylinder
    disc.Parent = workspace

    local gui = Instance.new('BillboardGui')
    gui.AlwaysOnTop = true
    gui.Size = UDim2.fromOffset(220, 40)
    gui.StudsOffset = Vector3.new(0, 5, 0)
    gui.Adornee = disc
    gui.Parent = disc

    local label = Instance.new('TextLabel')
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBold
    label.TextSize = 16
    label.TextColor3 = Color3.new(1, 1, 1)
    label.TextStrokeTransparency = 0
    label.Parent = gui

    tracked[model] = { disc = disc, label = label }
    model.Destroying:Connect(function() removeEntry(model) end)
end

for _, inst in ipairs(workspace:GetDescendants()) do track(inst) end
workspace.DescendantAdded:Connect(function(inst)
    if inst:IsA('Model') then task.defer(track, inst) end
end)

RunService.RenderStepped:Connect(function()
    for model, entry in next, tracked do
        local ok, pivot = pcall(model.GetPivot, model)
        local radius = modelRadius(model)
        if not (ok and pivot and radius and radius > 0) then continue end
        local dia = radius * 2
        entry.disc.Size = Vector3.new(0.4, dia, dia)
        entry.disc.CFrame = CFrame.new(pivot.Position) * CFrame.Angles(0, 0, math.rad(90))
        entry.label.Text = ('LIVE Water Domain  r = %.1f  (d = %.1f)'):format(radius, dia)
    end
end)
