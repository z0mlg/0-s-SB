-- Water Domain (DomainMumur) radius visualizer -- standalone, no main script.
-- Paste-execute in your executor. Every 'Whirlpool' model in workspace gets a
-- neon disc + a billboard label with its X/Z radius, so you can place the
-- domain where it covers the most mob spawns.

local RunService = game:GetService('RunService')

local tracked = {} -- model -> { disc, label }

local function modelRadius(model)
    local ok, size = pcall(model.GetExtentsSize, model)
    if not (ok and size) then return nil end
    return math.max(size.X, size.Z) * 0.5
end

local function removeEntry(model)
    local entry = tracked[model]
    if not entry then return end
    tracked[model] = nil
    if entry.disc then entry.disc:Destroy() end
end

local function track(model)
    if tracked[model] then return end

    local disc = Instance.new('Part')
    disc.Name = 'WaterDomainRadius'
    disc.Anchored = true
    disc.CanCollide = false
    disc.CanQuery = false
    disc.CanTouch = false
    disc.CastShadow = false
    disc.Material = Enum.Material.Neon
    disc.Color = Color3.fromRGB(60, 170, 255)
    disc.Transparency = 0.45
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
    label.TextColor3 = Color3.fromRGB(140, 220, 255)
    label.TextStrokeTransparency = 0
    label.Parent = gui

    tracked[model] = { disc = disc, label = label }
    model.Destroying:Connect(function() removeEntry(model) end)

    print(('[WaterDomain] whirlpool detected at %s'):format(tostring(model:GetPivot().Position)))
end

local function scan(model)
    if model:IsA('Model') and model.Name == 'Whirlpool' then
        task.defer(track, model)
    end
end

for _, inst in ipairs(workspace:GetDescendants()) do scan(inst) end
workspace.DescendantAdded:Connect(scan)

-- keep discs glued to their whirlpool (size/pos settle a few frames late)
RunService.RenderStepped:Connect(function()
    for model, entry in next, tracked do
        local ok, pivot = pcall(model.GetPivot, model)
        local radius = modelRadius(model)
        if not (ok and pivot and radius and radius > 0) then continue end

        local dia = radius * 2
        -- cylinder axis is X: tip it on its side so it lies flat as a disc
        entry.disc.Size = Vector3.new(0.4, dia, dia)
        entry.disc.CFrame = CFrame.new(pivot.Position) * CFrame.Angles(0, 0, math.rad(90))
        entry.label.Text = ('Water Domain  r = %.1f  (d = %.1f)'):format(radius, dia)
    end
end)

print('[WaterDomain] radius visualizer running - cast Water Domain to see its size')
