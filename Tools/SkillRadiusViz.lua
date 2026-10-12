--[[
    Skill Radius Visualizer (standalone)

    Draws a flat disc + radius label over every skill effect that spawns in the
    world (whirlpools/domains, telegraph markers, moving wave hitboxes), plus a
    probe circle you can park on a specific player to test farm coverage.

    Config is at the top of this file. Runs on its own -- does NOT need the
    Bluu loader.

    Keybinds:
        K   toggle all visuals on/off
        U/I probe circle radius -/+ 5 studs
        J   toggle the probe circle itself
]]

local Players = game:GetService('Players')
local RunService = game:GetService('RunService')
local Workspace = game:GetService('Workspace')
local CollectionService = game:GetService('CollectionService')
local UserInputService = game:GetService('UserInputService')
local LocalPlayer = Players.LocalPlayer
local Mobs = Workspace:FindFirstChild('Mobs')
local CharacterItems = Workspace:FindFirstChild('CharacterItems')

-- ===================== CONFIG =====================
local CONFIG = {
    -- probe circle: put a name here (exact account name or display name) to
    -- draw a circle under that player instead of yourself. '' = you.
    WatchPlayer = '',

    ProbeRadius = 60,      -- studs, adjustable in-game with U/I
    ProbeEnabled = true,   -- show the probe circle (J toggles)
    VisualsEnabled = true, -- master switch for skill discs (K toggles)

    DiscLife = 12,         -- seconds a disc lingers after its source dies
    MaxRadius = 400,       -- ignore footprints bigger than this (map clutter)
    MinRadius = 1,         -- ignore footprints smaller than this
}
-- ==================================================

local DISC_COLOR = Color3.fromRGB(80, 170, 255)
local TELEGRAPH_COLOR = Color3.fromRGB(255, 80, 80)
local PROBE_COLOR = Color3.fromRGB(120, 255, 140)

local DANGER_TAG_SUFFIXES = { ' Point', ' Blast', ' Ball', ' Strike', ' Meteor', ' Hitbox', ' Zone', ' Telegraph' }

local visuals = {} -- source -> { disc, label, born, lastSeen, isTelegraph }

local makeDisc = function(color)
    local p = Instance.new('Part')
    p.Name = 'SkillRadiusDisc'
    p.Shape = Enum.PartType.Cylinder
    p.Anchored = true
    p.CanCollide = false
    p.CanQuery = false
    p.CanTouch = false
    p.CastShadow = false
    p.Transparency = 0.55
    p.Material = Enum.Material.Neon
    p.Color = color
    p.Parent = Workspace

    local gui = Instance.new('BillboardGui')
    gui.Name = 'RadiusLabel'
    gui.AlwaysOnTop = true
    gui.Size = UDim2.fromOffset(160, 36)
    gui.StudsOffset = Vector3.new(0, 3, 0)
    gui.MaxDistance = 4000
    local text = Instance.new('TextLabel')
    text.BackgroundTransparency = 1
    text.Size = UDim2.fromScale(1, 1)
    text.Font = Enum.Font.GothamBold
    text.TextSize = 16
    text.TextColor3 = Color3.new(1, 1, 1)
    text.TextStrokeTransparency = 0.4
    text.TextStrokeColor3 = Color3.new(0, 0, 0)
    text.Parent = gui
    gui.Parent = p
    return p, text
end

local setDisc = function(entry, cf, radius)
    local d = math.max(radius * 2, 0.5)
    entry.disc.Size = Vector3.new(0.25, d, d)
    entry.disc.CFrame = CFrame.new(cf.Position) * CFrame.Angles(0, 0, math.rad(90))
    entry.label.Text = string.format('%s  R=%.1fm', entry.name or '?', radius)
end

local radiusOf = function(inst)
    -- footprint radius on XZ (ignore height)
    if inst:IsA('BasePart') then
        local s = inst.Size
        return math.max(s.X, s.Z) * 0.5, inst.CFrame
    end
    local ok, cf, size = pcall(function()
        return inst:GetPivot(), inst:GetExtentsSize()
    end)
    if not ok or not cf or not size then return end
    return math.max(size.X, size.Z) * 0.5, cf
end

local isInsideCharacterish = function(inst)
    local m = inst:FindFirstAncestorOfClass('Model')
    while m do
        if m:FindFirstChildOfClass('Humanoid') then return true end
        if Mobs and m:IsDescendantOf(Mobs) then return true end
        if CharacterItems and m:IsDescendantOf(CharacterItems) then return true end
        m = m:FindFirstAncestorOfClass('Model')
    end
    return false
end

local track = function(inst, isTelegraph)
    local r = radiusOf(inst)
    if not r then return end
    if r < CONFIG.MinRadius or r > CONFIG.MaxRadius then return end

    local disc, label = makeDisc(isTelegraph and TELEGRAPH_COLOR or DISC_COLOR)
    local entry = {
        disc = disc,
        label = label,
        inst = inst,
        name = inst.Name,
        born = tick(),
        lastSeen = tick(),
        isTelegraph = isTelegraph,
    }
    visuals[inst] = entry
end

local tagIsDangerous = function(tag)
    for _, suffix in next, DANGER_TAG_SUFFIXES do
        if string.sub(tag, -#suffix) == suffix then return true end
    end
    return false
end

local tryTrackTelegraph = function(inst)
    local ok, tags = pcall(inst.GetTags, inst)
    if ok and type(tags) == 'table' then
        for _, tag in next, tags do
            if tagIsDangerous(tag) then
                track(inst, true)
                return true
            end
        end
    end
    return false
end

local tryTrackSkillEffect = function(inst)
    if not (inst:IsA('BasePart') or inst:IsA('Model')) then return end
    if inst.Name == 'SkillRadiusDisc' or inst.Name == 'SkillRadiusProbe' then return end
    if isInsideCharacterish(inst) then return end
    if inst:IsDescendantOf(LocalPlayer.Character or script) then return end
    if inst:IsA('Terrain') then return end
    -- only fresh-looking spawns: anything that arrives already parented under
    -- map folders is ignored by the name filter below
    track(inst, false)
end

Workspace.DescendantAdded:Connect(function(inst)
    task.defer(function()
        if not inst:IsDescendantOf(Workspace) then return end
        if tryTrackTelegraph(inst) then return end
        if not (inst:IsA('BasePart') or inst:IsA('Model')) then return end
        -- telegraph parts are handled above; only track things that look like
        -- spawned skill assets (named clones at world root-ish depth)
        local depth = 0
        local p = inst.Parent
        while p and p ~= Workspace do
            depth += 1
            p = p.Parent
        end
        if depth <= 1 then
            tryTrackSkillEffect(inst)
        end
    end)
end)

-- per-frame: follow moving parts, expire dead ones, hide when disabled
RunService.RenderStepped:Connect(function()
    local now = tick()
    for inst, entry in next, visuals do
        if not entry.disc.Parent then
            visuals[inst] = nil
            continue
        end

        if not CONFIG.VisualsEnabled then
            entry.disc.Transparency = 1
            entry.label.Visible = false
            continue
        end

        if inst and inst:IsDescendantOf(Workspace) then
            entry.lastSeen = now
            local r, cf = radiusOf(inst)
            if r then
                entry.disc.Transparency = 0.55
                entry.label.Visible = true
                setDisc(entry, cf, math.min(r, CONFIG.MaxRadius))
            end
        elseif now - entry.lastSeen > CONFIG.DiscLife then
            entry.disc:Destroy()
            visuals[inst] = nil
        else
            -- fading out: dim it
            entry.disc.Transparency = math.min(0.9, 0.55 + (now - entry.lastSeen) * 0.1)
        end
    end
end)

-- ===================== PROBE CIRCLE =====================
local probe, probeLabel
local probeTarget = function()
    if CONFIG.WatchPlayer ~= '' then
        for _, p in next, Players:GetPlayers() do
            if p.Name == CONFIG.WatchPlayer or p.DisplayName == CONFIG.WatchPlayer then
                return p
            end
        end
    end
    return LocalPlayer
end

RunService.RenderStepped:Connect(function()
    if not CONFIG.ProbeEnabled then
        if probe then probe.Transparency = 1 probeLabel.Visible = false end
        return
    end
    local target = probeTarget()
    local root = target and target.Character and target.Character:FindFirstChild('HumanoidRootPart')
    if not root then
        if probe then probe.Transparency = 1 probeLabel.Visible = false end
        return
    end
    if not probe then
        probe, probeLabel = makeDisc(PROBE_COLOR)
        probe.Name = 'SkillRadiusProbe'
    end
    local entry = { disc = probe, label = probeLabel, name = target.Name .. ' (probe)' }
    setDisc(entry, root.CFrame, CONFIG.ProbeRadius)
    probe.Transparency = 0.45
    probeLabel.Visible = true
end)

-- ===================== KEYBINDS =====================
UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.K then
        CONFIG.VisualsEnabled = not CONFIG.VisualsEnabled
    elseif input.KeyCode == Enum.KeyCode.J then
        CONFIG.ProbeEnabled = not CONFIG.ProbeEnabled
    elseif input.KeyCode == Enum.KeyCode.U then
        CONFIG.ProbeRadius = math.max(5, CONFIG.ProbeRadius - 5)
    elseif input.KeyCode == Enum.KeyCode.I then
        CONFIG.ProbeRadius = CONFIG.ProbeRadius + 5
    end
end)

print('[SkillRadiusViz] loaded - K: toggle visuals | J: probe circle | U/I: probe radius -/+')
