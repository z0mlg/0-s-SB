-- Bluu :: Autofarm  (split from Sb2-0mlg.lua)

Farming = Main:AddLeftTabbox()

Autofarm = Farming:AddTab('Autofarm')


-- Assist mode: a mob only counts as a target once the selected player has dealt
-- the required share of its max health (SB2 credits kills to everyone over it).
-- Entity.Health is an IntValue (MaxValue = max hp); each attacker leaves a
-- NumberValue named after them inside it holding their dealt damage.
local MobDataCache = RequiredServices and RequiredServices.StatsUI and RequiredServices.StatsUI.MobDataCache

local mobMaxHp = function(mob, health)
    local maxHp
    -- MaxValue can sit below the real pool on scaled variants; the game's own
    -- stat table knows the type's real HP - take the larger of the two
    local ok, v = pcall(function() return health.MaxValue end)
    if ok and type(v) == 'number' and v > 0 then maxHp = v end
    local data = MobDataCache and MobDataCache[mob.Name]
    if data and type(data.HealthValue) == 'number' and data.HealthValue > 0 then
        maxHp = math.max(maxHp or 0, data.HealthValue)
    end
    return maxHp
end

local dealtShare = function(mob, playerName)
    local entity = mob:FindFirstChild('Entity')
    local health = entity and entity:FindFirstChild('Health')
    if not health then return end
    local maxHp = mobMaxHp(mob, health)
    if not maxHp then return end
    local dealt = health:FindFirstChild(playerName)
    return dealt and dealt.Value or 0, maxHp
end

assistRequirement = function(mob)
    if not (Toggles.AssistMode and Toggles.AssistMode.Value) then return true end
    local player = Options.AssistPlayer and Options.AssistPlayer.Value
    if type(player) ~= 'string' then return false end
    local dealt, maxHp = dealtShare(mob, player)
    if not dealt then return false end
    return dealt > 0 and dealt >= maxHp * (Options.AssistDamage.Value / 100)
end

-- tag mode: once LocalPlayer's own share is met the mob is "tagged" for kill
-- credit - the farm then leaves it alone and moves to the next one
isTagged = function(mob)
    local dealt, maxHp = dealtShare(mob, LocalPlayer.Name)
    if not dealt then return false end
    local pct = Options.AssistDamage.Value / 100
    if pct <= 0 then return dealt > 0 end -- any hit counts when the share is 0
    return dealt >= maxHp * pct
end

tagGate = function(mob) -- skip already-tagged mobs only while tag mode is on
    return Toggles.TagMode ~= nil and Toggles.TagMode.Value and isTagged(mob)
end

-- The Between blackout wave: while the soul light is up, only mobs inside it
-- are farmed and our stand point is kept inside the light (see TheBetween)
local inBlackoutLight = function()
    if not (IN_BETWEEN and BlackoutLight) then return end
    if not (Toggles.BetweenBlackoutLight and Toggles.BetweenBlackoutLight.Value) then return end
    return BlackoutLight()
end

-- wave objective mobs carry a 'Glow' object in their root part
local mobGlows = function(mob)
    if not (IN_BETWEEN and Toggles.BetweenGlowFirst and Toggles.BetweenGlowFirst.Value) then return false end
    local root = mob and mob:FindFirstChild('HumanoidRootPart')
    return root ~= nil and root:FindFirstChild('Glow') ~= nil
end

-- Rift wave: rifts are the objective - focus them over regular mobs
local inRiftWave = function()
    return IN_BETWEEN and BetweenWaveType == 'Rift'
        and Toggles.BetweenRiftFocus ~= nil and Toggles.BetweenRiftFocus.Value
end
local mobIsRift = function(mob)
    return mob.Name:find('Rift') ~= nil
end

-- unkillable mobs carry an 'Immortal' child under their Entity - the game's
-- own DamageArea skips those the same way. The nameplate mirrors it with an
-- 'Immortal' ImageLabel (SurfaceGui.Layout.Immortal) that's only Visible while
-- immortal; a raw recursive find can hit a non-nameplate 'Immortal' first and
-- shadow the label, so the label search is scoped to GUI descendants only.
-- The label instance is cached per mob and Visible is read live.
local immortalCache = setmetatable({}, { __mode = 'k' })
mobIsImmortal = function(mob)
    local entity = mob:FindFirstChild('Entity')
    if entity and entity:FindFirstChild('Immortal') then return true end

    local c = immortalCache[mob]
    if c then
        if c.marker then
            return c.marker.Parent ~= nil and c.marker.Visible == true
        end
        if tick() - c.t < 2 then return false end -- retry while a nameplate may still build
    end
    for _, d in next, mob:GetDescendants() do
        if d.Name == 'Immortal' and d:IsA('GuiObject')
            and d:FindFirstAncestorWhichIsA('LayerCollector') then
            immortalCache[mob] = { marker = d }
            return d.Visible == true
        end
    end
    immortalCache[mob] = { t = tick() }
    return false
end

-- 'Bob' survive wave: keep a large fixed distance from every Bob - it can't
-- reach past it, and Bob himself is never a valid target
local bobDistance = function()
    if not (IN_BETWEEN and BetweenWaveType == 'Bob') then return end
    if not (Toggles.BetweenBobFlee and Toggles.BetweenBobFlee.Value) then return end
    return Options.BetweenBobDistance and Options.BetweenBobDistance.Value or 300
end

local nearestBobPos = function()
    if not HumanoidRootPart then return end
    local bestPos, bestDist
    for _, mob in next, Mobs:GetChildren() do
        if not mob.Name:find('Bob') or isDead(mob) then continue end
        local root = mob:FindFirstChild('HumanoidRootPart')
        if not root then continue end
        local d = (root.Position - HumanoidRootPart.Position).Magnitude
        if not bestDist or d < bestDist then bestPos, bestDist = root.Position, d end
    end
    return bestPos
end

local getAutofarmTarget = function()
    local radius = Options.AutofarmRadius.Value
    radius = (radius == Options.AutofarmRadius.Max) and math.huge or radius

    local closestTarget, closestPrioTarget, closestGlowTarget, closestRiftTarget
    local minDistance, minPrioDistance, minGlowDistance, minRiftDistance = radius, radius, math.huge, math.huge

    local ignoreList = Options.IgnoreMobs.Value
    local prioritizeList = Options.PrioritizeMobs.Value
    local useWaypoint = Toggles.UseWaypoint.Value
    local waypointPos = waypoint.Position
    local myPos = HumanoidRootPart.Position
    local lightPos, lightRange = inBlackoutLight()
    local bobDist = bobDistance()

    for _, mob in next, Mobs:GetChildren() do
        if isDead(mob) or mobIsImmortal(mob) then continue end
        if bobDist and mob.Name:find('Bob') then continue end

        local mobRoot = mob:FindFirstChild('HumanoidRootPart')
        local mobPos = mobRoot and mobRoot.Position
        if not mobPos then continue end

        -- wave objective: glowing mobs must actually die, so they jump every
        -- queue - ignore/tag/assist/waypoint rules don't apply to them
        if mobGlows(mob) then
            if lightPos and (mobPos - lightPos).Magnitude > lightRange then continue end
            local dist = (mobPos - myPos).Magnitude
            if dist < minGlowDistance then
                minGlowDistance = dist
                closestGlowTarget = mob
            end
            continue
        end

        -- rift wave: rifts are the wave objective, chase them over everything
        -- (also ignoring the usual filters); regular mobs only fill in when
        -- no rift is alive
        if inRiftWave() and mobIsRift(mob) then
            if lightPos and (mobPos - lightPos).Magnitude > lightRange then continue end
            local dist = (mobPos - myPos).Magnitude
            if dist < minRiftDistance then
                minRiftDistance = dist
                closestRiftTarget = mob
            end
            continue
        end

        if ignoreList[mob.Name] then continue end
        if not assistRequirement(mob) then continue end
        if tagGate(mob) then continue end

        if lightPos then
            if (mobPos - lightPos).Magnitude > lightRange then continue end
        elseif useWaypoint and (mobPos - waypointPos).Magnitude > radius then continue end

        local dist = (mobPos - myPos).Magnitude

        if prioritizeList[mob.Name] then
            if dist < minPrioDistance then
                minPrioDistance = dist
                closestPrioTarget = mob
            end
        elseif not closestPrioTarget and dist < minDistance then
            minDistance = dist
            closestTarget = mob
        end
    end

    return closestGlowTarget or closestRiftTarget or closestPrioTarget or closestTarget
end

local calculateAutofarmOffset = (function()
    local ratioDirection = Vector2.new(1, 4).Unit
    local verticalRatio = ratioDirection.Y
    local horizontalRatio = ratioDirection.X

    return function(target)
        local rootPart = target:FindFirstChild('HumanoidRootPart')
        if not rootPart then return nil end

        local size = rootPart.Size
        local radius = math.max(size.X, size.Z) * 0.5 + 19

        local vertical = Options.AutofarmVerticalOffset.Value
        local horizontal = Options.AutofarmHorizontalOffset.Value

        if vertical == Options.AutofarmVerticalOffset.Max then
            if horizontal == Options.AutofarmHorizontalOffset.Max then
                vertical = radius * verticalRatio
                horizontal = radius * horizontalRatio
            else
                local root = math.sqrt(radius ^ 2 - horizontal ^ 2)
                vertical = root == root and root or 0
            end
        elseif vertical == Options.AutofarmVerticalOffset.Min then
            if horizontal == Options.AutofarmHorizontalOffset.Max then
                vertical = radius * -verticalRatio
                horizontal = radius * horizontalRatio
            else
                local root = -math.sqrt(radius ^ 2 - horizontal ^ 2)
                vertical = root == root and root or 0
            end
        elseif horizontal == Options.AutofarmHorizontalOffset.Max then
            horizontal = math.sqrt(radius ^ 2 - vertical ^ 2)
        end

        return rootPart, radius, vertical, horizontal
    end
end)()

local flipUpsideDown = function(part)
    HumanoidRootPart.CFrame = CFrame.Angles(0, 0, math.pi) + HumanoidRootPart.CFrame.Position
    local look = Vector3.new(
        part.CFrame.LookVector.X,
        0,
        part.CFrame.LookVector.Z
    ).Unit
    local yaw = math.atan2(-look.X, -look.Z)
    local baseRotation = CFrame.Angles(0, yaw, 0)
    local rollFlip = CFrame.fromAxisAngle(Vector3.new(0, 0, 1), math.pi)
    local finalRotation = baseRotation * rollFlip
    part.CFrame = CFrame.new(part.Position) * finalRotation
end

-- ===================== MOB ATTACK TELEGRAPH DODGE =====================
-- Enemy skills telegraph their hit areas three ways:
--   * server parts tagged '<Skill> Point' / ' Blast' / ' Ball' (ground markers; 'Lifetime' attr = fuse)
--   * positions passed through the ReplicateSkill remote (slams, gyzers, dashes, lasers)
--   * client parts with Touched connections (waves, tides, orbs)
-- All of them become X/Z danger zones; the autofarm destination (and our own
-- position) get pushed to the nearest safe point on X/Z, world Y is ignored.
local CollectionService = game:GetService('CollectionService')

local DangerZones = {
    List = {},
    HookedTags = {},
    LastSkillAt = 0,
}

local DANGER_TAG_SUFFIXES = { ' Point', ' Blast', ' Ball', ' Strike', ' Meteor', ' Hitbox', ' Zone', ' Telegraph' }
-- The Between (wave defense) bosses: Aegor / Rubricatus / Vaelith markers -
-- these generic suffixes exist on normal floors too, so only apply there
local BETWEEN_TAG_SUFFIXES = { ' Rock', ' Slam', ' Spike', ' Attack', ' Rift' }
local ACTIVE_TAG_SUFFIXES = DANGER_TAG_SUFFIXES
if IN_BETWEEN then
    ACTIVE_TAG_SUFFIXES = {}
    for _, s in next, DANGER_TAG_SUFFIXES do table.insert(ACTIVE_TAG_SUFFIXES, s) end
    for _, s in next, BETWEEN_TAG_SUFFIXES do table.insert(ACTIVE_TAG_SUFFIXES, s) end
end

local dodgeEnabled = function()
    return Toggles.DodgeAttacks and Toggles.DodgeAttacks.Value
end

-- +3: Touched fires on any limb, so the root must clear the edge by the
-- character's half-width, not just sit on the border
local dodgePadding = function()
    return ((Options.DodgePadding and Options.DodgePadding.Value) or 4) + 3
end

-- Client-reported skill damage: wave/tide/orb skills hit us via
-- Base:LocalHit -> Event:FireServer('Mobs', { 'DamageSelf', ... }) from OUR
-- client. Dropping that call nullifies every Touched-based attack outright.
if type(hookmetamethod) == 'function' and type(getnamecallmethod) == 'function' then
    local oldNamecall
    oldNamecall = hookmetamethod(game, '__namecall', function(self, ...)
        if self == Event and Toggles.BlockSkillDamage and Toggles.BlockSkillDamage.Value
            and getnamecallmethod() == 'FireServer' then
            local a1, a2 = ...
            if a1 == 'Mobs' and type(a2) == 'table' and a2[1] == 'DamageSelf' then
                return
            end
        end
        return oldNamecall(self, ...)
    end)
end

local dodgeDefaultRadius = function()
    return (Options.DodgeRadius and Options.DodgeRadius.Value) or 20
end

-- marker/arg sizes often understate the real damage range (e.g. OceanGyzer's
-- server hitbox, OmegaWave's wide wall) - scale zones up past the visual edge
local dodgeScale = function()
    return (Options.DodgeScale and Options.DodgeScale.Value) or 2
end

-- per-attack size overrides, configured in the Dodge tab and saved to
-- dodgescales.json. A zone made by skill X uses that skill's scale; anything
-- else (telegraph tags, moving hitboxes, wave warnings) uses the global scale.
DodgeSkillScales = {}
DodgeSkillIgnored = {} -- per-attack ignore (Dodge tab toggle): skill makes no zones
DodgeSeenSkills = {} -- skill names ReplicateSkill fired this session (attack list)
local pendingSkill -- set while a skill's remote event is being dispatched
local zoneScale = function(zone)
    local s = zone.Skill and DodgeSkillScales[zone.Skill]
    return type(s) == 'number' and s or dodgeScale()
end

-- 'Low' zones are escaped by dropping under them instead of sidestepping -
-- for the big attacks (lava sections, tempest strikes, wave-boss hits) where
-- below-floor diving is reserved for mechanics that can't be escaped on X/Z
-- (lava floor, Tempest slam). Everything else dodges horizontally only -
-- sinking under an attack is useless and breaks pillar cover during nukes.
local lowDepth = function()
    return (Options.DodgeLowDepth and Options.DodgeLowDepth.Value) or 80
end

local addZone = function(zone)
    if zone.Skill == nil then zone.Skill = pendingSkill end
    table.insert(DangerZones.List, zone)
    -- dodge the same instant the attack is detected, not on the next farm tick
    if DangerZones.ApplyNow then
        task.spawn(pcall, DangerZones.ApplyNow)
    end
    return zone
end

local addPointZone = function(pos, radius, duration, low)
    return addZone({
        Kind = 'point',
        X = pos.X,
        Y = pos.Y,
        Z = pos.Z,
        R = radius or dodgeDefaultRadius(),
        Expires = tick() + (duration or 4),
        Low = low,
    })
end

local addSegmentZone = function(fromPos, toPos, halfWidth, duration)
    if not (fromPos and toPos) then return end
    local from = Vector3.new(fromPos.X, 0, fromPos.Z)
    local to = Vector3.new(toPos.X, 0, toPos.Z)
    local len = (to - from).Magnitude
    if len < 1 then
        return addPointZone(fromPos, halfWidth, duration)
    end
    return addZone({
        Kind = 'box',
        CF = CFrame.lookAt((from + to) * 0.5, to) + Vector3.new(0, (fromPos.Y + toPos.Y) * 0.5, 0),
        Size = Vector3.new(math.max((halfWidth or 10) * 2, 4), 1, len),
        Expires = tick() + (duration or 4),
    })
end

local addPartZone = function(part, duration)
    local zone = addZone({ Kind = 'part', Part = part, Expires = tick() + duration })
    pcall(function()
        zone.LastCF, zone.LastSize, zone.LastShape = part.CFrame, part.Size, part.Shape
    end)
    return zone
end

-- 'LavaSmash Point' -> 'LavaSmash': the tag's skill for per-attack sizing
local tagSkill = function(tag)
    for _, suffix in next, ACTIVE_TAG_SUFFIXES do
        if string.sub(tag, -#suffix) == suffix then
            return string.sub(tag, 1, #tag - #suffix)
        end
    end
end

local trackTelegraph = function(inst, low, skill)
    if skill and DodgeSkillIgnored[skill] then return end -- ignored in the Dodge tab
    local life = inst.GetAttribute and inst:GetAttribute('Lifetime')
    local duration = (type(life) == 'number' and life or 4) + 2.5
    local zone
    if inst:IsA('BasePart') then
        zone = addPartZone(inst, duration)
    elseif inst:IsA('Model') then
        local ok, cf, size = pcall(function()
            return inst:GetPivot(), inst:GetExtentsSize()
        end)
        if ok and cf and size then
            zone = addZone({ Kind = 'box', CF = cf, Size = size, Expires = tick() + duration })
        end
    end
    if low and zone then zone.Low = true end
    if skill and zone then zone.Skill = skill end
end

-- circle hit: returns escape point on XZ or nil
local circleZoneHit = function(zone, x, z)
    local dx, dz = x - zone.X, z - zone.Z
    local rr = zone.R * zoneScale(zone) + dodgePadding()
    local d2 = dx * dx + dz * dz
    if d2 >= rr * rr then return end
    local d = math.sqrt(d2)
    if d < 1e-3 then return zone.X + rr, zone.Z end
    local scale = rr / d
    return zone.X + dx * scale, zone.Z + dz * scale
end

-- oriented box hit in local space; whichever local axis is most vertical in the
-- world gets ignored, so flat discs and tilted telegraphs work the same.
local boxZoneHit = function(cf, size, elliptical, x, z, scale)
    local pad = dodgePadding()
    scale = scale or dodgeScale()
    local rel = cf:PointToObjectSpace(Vector3.new(x, cf.Position.Y, z))
    local ax, ay, az = math.abs(cf.XVector.Y), math.abs(cf.YVector.Y), math.abs(cf.ZVector.Y)
    local skip = (ax >= ay and ax >= az) and 1 or (ay >= az and 2 or 3)
    local a, b = skip % 3 + 1, (skip + 1) % 3 + 1
    local comps = { rel.X, rel.Y, rel.Z }
    local half = { size.X * 0.5 * scale + pad, size.Y * 0.5 * scale + pad, size.Z * 0.5 * scale + pad }
    local h1, h2 = half[a], half[b]
    if h1 <= 0 or h2 <= 0 then return end
    local c1, c2 = comps[a], comps[b]
    if elliptical then
        local e = (c1 / h1) ^ 2 + (c2 / h2) ^ 2
        if e > 1 then return end
        if e < 1e-4 then
            c1, c2 = h1, 0
        else
            local f = 1 / math.sqrt(e)
            c1, c2 = c1 * f, c2 * f
        end
    else
        if math.abs(c1) > h1 or math.abs(c2) > h2 then return end
        if h1 - math.abs(c1) < h2 - math.abs(c2) then
            c1 = (c1 >= 0 and 1 or -1) * h1
        else
            c2 = (c2 >= 0 and 1 or -1) * h2
        end
    end
    comps[a], comps[b] = c1, c2
    comps[skip] = 0
    local world = cf * Vector3.new(comps[1], comps[2], comps[3])
    return world.X, world.Z
end

-- Y we'd have to drop to for this zone to stop hitting us, or nil when the
-- zone has no usable height (caller falls back to the normal XZ escape)
local zoneLowY = function(zone)
    local bottom
    if zone.Kind == 'point' then
        bottom = zone.Y - (zone.R or 0) * zoneScale(zone)
    elseif zone.Kind == 'box' then
        bottom = zone.CF.Position.Y - zone.Size.Y * 0.5 * zoneScale(zone)
    elseif zone.LastCF and zone.LastSize then
        bottom = zone.LastCF.Position.Y - zone.LastSize.Y * 0.5 * zoneScale(zone)
    end
    return bottom and bottom - lowDepth() or nil
end

-- returns escapeXZ, a 'low' escapeY, or 'dead' when the zone expired
local zoneHit = function(zone, x, z, now)
    if zone.Expires and now > zone.Expires then return 'dead' end

    local kind = zone.Kind
    local ex, ez
    if kind == 'point' then
        ex, ez = circleZoneHit(zone, x, z)
    elseif kind == 'box' then
        ex, ez = boxZoneHit(zone.CF, zone.Size, zone.Elliptical, x, z, zoneScale(zone))
    elseif kind == 'enemy' then
        if not (zone.Enemy and zone.Enemy.Parent) then return 'dead' end
        local root = zone.Enemy:FindFirstChild('HumanoidRootPart')
        if not root then return 'dead' end
        zone.X, zone.Z = root.Position.X, root.Position.Z
        ex, ez = circleZoneHit(zone, x, z)
    else
        local part = zone.Part
        local cf, size, shape
        if part and part:IsDescendantOf(workspace) then
            cf, size = part.CFrame, part.Size
            shape = part:IsA('Part') and part.Shape or nil -- MeshParts (Wave.Plane etc.) have no Shape
            zone.LastCF, zone.LastSize, zone.LastShape = cf, size, shape
        elseif zone.LastCF then
            zone.DeadAt = zone.DeadAt or now
            if now - zone.DeadAt > 1.25 then return 'dead' end
            cf, size, shape = zone.LastCF, zone.LastSize, zone.LastShape
        else
            return 'dead'
        end
        if shape == Enum.PartType.Ball then
            ex, ez = circleZoneHit({
                X = cf.Position.X,
                Z = cf.Position.Z,
                R = math.max(size.X, size.Y, size.Z) * 0.5,
                Skill = zone.Skill,
            }, x, z)
        else
            ex, ez = boxZoneHit(cf, size, shape == Enum.PartType.Cylinder, x, z, zoneScale(zone))
        end
    end

    -- big attacks: instead of stepping out sideways, report the height we
    -- need to drop under the zone; no usable bottom -> normal escape
    if ex and zone.Low then
        local ly = zoneLowY(zone)
        if ly then return nil, nil, ly end
    end
    return ex, ez
end

-- Rubricatus' nuke: the kill check is line-of-sight from the blast point and
-- the arena spawns 'Pillar' Models to hide behind. Pillars supply the SPOT;
-- the attack signal supplies the WINDOW: a RubricatusNuke remote or a pillar
-- spawn during a live-Rubricatus wave arms the window, and it stays up while
-- the server's WaveCountdown hides you / until it goes stale. Between casts
-- we farm normally again.
BetweenNukeCover = nil -- { Pos = Vector3, Pillar = inst, Expires = tick }
local nukeWatchRunning = false
local NukeBlastPos, NukeBlastAt
local NukeArmAt = 0
local nukeThreatPos -- forward: used by nukeCoverPoint, defined below

-- the far-side spot of one pillar along the threat->pillar axis - recomputed
-- live because spawned pillars tween up from underground and move
local pillarBehind = function(inst, threat)
    local ok, cf = pcall(inst.GetPivot, inst)
    if not (ok and cf) then return end
    threat = threat or cf.Position
    local ok2, ext = pcall(inst.GetExtentsSize, inst)
    local margin = ok2 and (math.max(ext.X, ext.Z) / 2 + 2) or 8
    local flat = Vector3.new(cf.X - threat.X, 0, cf.Z - threat.Z)
    if flat.Magnitude < 0.01 then return cf.Position end
    local behind = cf.Position + flat.Unit * margin
    local r = HumanoidRootPart
    -- keep our own Y: the shadow is X/Z-only
    return Vector3.new(behind.X, r and r.Position.Y or behind.Y, behind.Z)
end

local nukeCoverPoint = function()
    local c = BetweenNukeCover
    if not c then return end
    if tick() >= c.Expires then return end
    -- follow the tracked pillar's live pivot - it may still be rising
    if c.Pillar and c.Pillar.Parent then
        local b = pillarBehind(c.Pillar, nukeThreatPos())
        if b then return b end
    end
    return c.Pos
end

local rubricatusAlive = function()
    for _, mob in next, Mobs:GetChildren() do
        if mob.Name:find('Rubricatus', 1, true) and not isDead(mob) then
            local root = mob:FindFirstChild('HumanoidRootPart')
            if root then return root end
        end
    end
end

-- shadow direction: fresh blast point from the remote, else the boss's root,
-- else (inside findNukeCover) the pillar cluster centroid
nukeThreatPos = function()
    if NukeBlastPos and NukeBlastAt and tick() - NukeBlastAt < 25 then
        return NukeBlastPos
    end
    local root = rubricatusAlive()
    return root and root.Position
end

local findNukeCover = function(threat)
    if not HumanoidRootPart then return end
    local bestInst, bestDist
    for _, inst in next, workspace:GetDescendants() do
        -- boss cover pillars are Models; map 'Pillar' MeshParts are decor
        if inst:IsA('Model') and inst.Name:find('Pillar', 1, true) then
            local ok, cf = pcall(inst.GetPivot, inst)
            if ok and cf then
                local d = (cf.Position - HumanoidRootPart.Position).Magnitude
                if not bestDist or d < bestDist then bestDist, bestInst = d, inst end
            end
        end
    end
    if not bestInst then return end
    return pillarBehind(bestInst, threat), bestInst
end

-- the game's own alert: WaveDefense.Countdown.Note reads 'HIDE BEHIND A
-- PILLAR' exactly while the nuke is live; Countdown.Countdown shows 8..1 and
-- blanks at detonation. This is the authoritative window - more precise than
-- any remote/attribute guess.
local nukeAlertNote = function()
    local gui = LocalPlayer and LocalPlayer:FindFirstChild('PlayerGui')
    local wd = gui and gui:FindFirstChild('CardinalUI')
        and gui.CardinalUI:FindFirstChild('PlayerUI')
        and gui.CardinalUI.PlayerUI:FindFirstChild('Popups')
        and gui.CardinalUI.PlayerUI.Popups:FindFirstChild('WaveDefense')
    local cd = wd and wd:FindFirstChild('Countdown')
    local note = cd and cd:FindFirstChild('Note')
    return (note and note:IsA('TextLabel')) and note.Text or ''
end
local nukeAlertLive = function()
    return nukeAlertNote():upper():find('PILLAR', 1, true) ~= nil
end

-- one watcher owns the nuke window: while it's live and a pillar exists the
-- cover point tracks the nearest one's far side. Ends on: the game's 'HIDE
-- BEHIND A PILLAR' note disappearing (detonation), a 14s stale window, or
-- zero pillars - then holds a 2s tail because the nuke's damage outlives it.
local armNukeWatch
armNukeWatch = function()
    NukeArmAt = tick() -- every signal refreshes the window
    if nukeWatchRunning then return end
    nukeWatchRunning = true
    task.spawn(function()
        local sawAlert, tailAt
        while getgenv().Bluu ~= false do
            local now = tick()
            local ended = false
            if nukeAlertLive() then
                sawAlert = true
                NukeArmAt = now -- the game's hide alert is up
            elseif sawAlert then
                ended = true -- note blanked = detonation fired
            elseif now - NukeArmAt > 14 then
                ended = true -- window stale
            end
            local p, inst = findNukeCover(nukeThreatPos())
            if not p then ended = true end -- zero pillars = nothing left to hide
            if ended then
                if not tailAt then tailAt = now + 2 end
            else
                tailAt = nil -- a fresh signal cancels a pending release
            end
            if tailAt and now >= tailAt then break end
            if p then
                if not BetweenNukeCover then BetweenNukeCover = {} end
                BetweenNukeCover.Pos = p
                BetweenNukeCover.Pillar = inst
            end
            if BetweenNukeCover then BetweenNukeCover.Expires = now + 3 end
            task.wait(0.15)
        end
        BetweenNukeCover = nil
        nukeWatchRunning = false
    end)
end

-- the Note text flipping to the hide warning IS the nuke starting - arm the
-- instant the game's UI shows it (waits for the popup UI to exist first)
task.spawn(function()
    local ok, countdown = pcall(function()
        local wd = LocalPlayer.PlayerGui:WaitForChild('CardinalUI', 30)
        wd = wd and wd:WaitForChild('PlayerUI', 30)
        wd = wd and wd:WaitForChild('Popups', 30)
        wd = wd and wd:WaitForChild('WaveDefense', 30)
        return wd and wd:WaitForChild('Countdown', 30)
    end)
    local note = ok and countdown and countdown:FindFirstChild('Note')
    if not (note and note:IsA('TextLabel')) then return end
    note:GetPropertyChangedSignal('Text'):Connect(function()
        if getgenv().Bluu == false then return end
        if nukeAlertLive() then armNukeWatch() end
    end)
    if nukeAlertLive() then armNukeWatch() end -- already up when hooked
end)

-- a pillar spawning during a live Rubricatus wave = the nuke windup -
-- covers the case where neither the remote nor the UI hook reaches us
workspace.DescendantAdded:Connect(function(inst)
    if getgenv().Bluu == false then return end
    if not (inst:IsA('Model') and inst.Name:find('Pillar', 1, true)) then return end
    if not (IN_BETWEEN or rubricatusAlive() or
        (NukeBlastAt and tick() - NukeBlastAt < 25)) then return end
    task.defer(armNukeWatch)
end)

local resolveDodge = function(pos)
    if not dodgeEnabled() then return pos end
    local cover = nukeCoverPoint()
    if cover then return cover end
    local list = DangerZones.List
    if #list == 0 then return pos end
    local x, z = pos.X, pos.Z
    local lowY
    for _ = 1, 5 do
        local hit = false
        local now = tick()
        for i = #list, 1, -1 do
            local ok, ex, ez, ly = pcall(zoneHit, list[i], x, z, now)
            -- a zone that errors once gets dropped, not retried every frame --
            -- an unprotected error here would kill the whole autofarm loop
            if not ok or ex == 'dead' then
                table.remove(list, i)
            elseif ly then
                -- already under the zone's reach -> it's cleared; else dive
                if pos.Y > ly then
                    lowY = lowY and math.min(lowY, ly) or ly
                    hit = true
                end
            elseif ex then
                x, z = ex, ez
                hit = true
            end
        end
        if not hit then break end
    end
    if lowY then
        return Vector3.new(x, math.min(pos.Y, lowY), z)
    end
    return Vector3.new(x, pos.Y, z)
end
DangerZones.Resolve = resolveDodge

-- Bosses whose attacks can't reach our farm spot (we sit under the arena):
-- only the listed skills get zoned, every other cast is ignored entirely -
-- no zone, no caster zone, no Touched-hitbox window, no marker tags.
local BOSS_DODGE_ONLY = {
    Aeganatos = { OceanGyzer = true },
    -- also covers 'Corrupted Atheon': only the aerial slam reaches us under the floor
    Atheon = { LavaSmash = true },
}
local IGNORED_SKILL_TAGS = { 'OmegaWave' } -- known marker prefixes of ignored skills

bossSkillIgnored = function(enemy, skillName)
    local name = typeof(enemy) == 'Instance' and enemy.Name or ''
    for boss, keep in next, BOSS_DODGE_ONLY do
        if string.find(name, boss, 1, true) then
            return not keep[skillName]
        end
    end
    return false
end

-- The Between waves pull from the whole game roster (Atheon, Suspended
-- Unborn, wave bosses): every skill goes through the normal dispatch, the
-- boss keep-lists and Dodge-tab ignores do the filtering. Lava floors still
-- come via ReplicateWave, Bob and the soul light are positioning, not zones
local tagIsDangerous = function(tag)
    -- generic enemy hitbox tag: module-less bosses (Suspended Unborn etc.)
    -- telegraph through it - 'Lifetime' attr is the fade-in fuse
    if tag == 'EnemySkillHitbox' then return true end
    local sk = tagSkill(tag)
    if sk and DodgeSkillIgnored[sk] then return false end
    for _, prefix in next, IGNORED_SKILL_TAGS do
        if string.sub(tag, 1, #prefix) == prefix then return false end
    end
    for _, suffix in next, ACTIVE_TAG_SUFFIXES do
        if string.sub(tag, -#suffix) == suffix then return true end
    end
    return false
end

-- only these still dive under their attack (unavoidable-on-XZ mechanics);
-- every other zone resolves horizontally so nuke pillar cover keeps working
local LOW_DODGE_SKILLS = { TempestStrike = true }
local tagIsLow = function(tag)
    local sk = tagSkill(tag)
    return sk ~= nil and LOW_DODGE_SKILLS[sk] == true
end

-- ground telegraph markers + moving client hitboxes
workspace.DescendantAdded:Connect(function(inst)
    if getgenv().Bluu == false then return end
    if not (inst:IsA('BasePart') or inst:IsA('Model')) then return end
    task.defer(function()
        if not inst:IsDescendantOf(workspace) then return end
        local ok, tags = pcall(inst.GetTags, inst)
        if ok and type(tags) == 'table' then
            for _, tag in next, tags do
                if tagIsDangerous(tag) then
                    trackTelegraph(inst, tagIsLow(tag), tagSkill(tag))
                    return
                end
            end
        end
        if not inst:IsA('BasePart') then return end
        if tick() - DangerZones.LastSkillAt > 4 then return end
        if inst:IsDescendantOf(Mobs) then return end
        if type(getconnections) ~= 'function' then return end
        local model = inst:FindFirstAncestorOfClass('Model')
        if model and model:FindFirstChildOfClass('Humanoid') then return end
        local ok2, conns = pcall(getconnections, inst.Touched)
        if ok2 and type(conns) == 'table' and #conns > 0 then
            addPartZone(inst, 10)
        end
    end)
end)

-- catch markers that already existed when we loaded
task.defer(function()
    for _, inst in next, workspace:GetDescendants() do
        if not (inst:IsA('BasePart') or inst:IsA('Model')) then continue end
        local ok, tags = pcall(inst.GetTags, inst)
        if not (ok and type(tags) == 'table') then continue end
        for _, tag in next, tags do
            if tagIsDangerous(tag) then
                trackTelegraph(inst, tagIsLow(tag), tagSkill(tag))
                break
            end
        end
    end
end)

local hookSkillTags = function(skillName)
    for _, suffix in next, ACTIVE_TAG_SUFFIXES do
        local tag = skillName .. suffix
        if DangerZones.HookedTags[tag] then continue end
        DangerZones.HookedTags[tag] = true
        local low = tagIsLow(tag)
        for _, inst in next, CollectionService:GetTagged(tag) do
            trackTelegraph(inst, low, skillName)
        end
        CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst)
            trackTelegraph(inst, low, skillName)
        end)
    end
end

-- EnemySkillHitbox has no skill-name prefix so hookSkillTags can't reach it -
-- hook the tag directly; Suspended Unborn's whole kit telegraphs through it
for _, inst in next, CollectionService:GetTagged('EnemySkillHitbox') do
    trackTelegraph(inst)
end
CollectionService:GetInstanceAddedSignal('EnemySkillHitbox'):Connect(function(inst)
    if getgenv().Bluu == false then return end
    trackTelegraph(inst)
end)

local enemyRoot = function(enemy)
    return enemy and enemy:FindFirstChild('HumanoidRootPart')
end

-- known skill signatures from the decompiled EnemySkills modules; anything not
-- listed falls through to genericSkillZones which zones every position arg.
local SkillZoneHandlers = {
    -- Atheon aerial slam: Replicating(surfacePos, lifetime, jumpHeight, lastCFrame)
    -- fires while he's still standing on the landing point, so the generic path
    -- drops both positions as 'near caster' and leaves a caster zone that dies
    -- mid-jump. Zone the impact point AND the boss for the whole air window:
    -- jump tween is lifetime*0.25 up, then he falls back onto lastCFrame.
    LavaSmash = {
        Replicating = function(enemy, pos, lifetime, _, landCF)
            local dur = (type(lifetime) == 'number' and lifetime or 3) + 4
            if typeof(pos) == 'Vector3' then
                addPointZone(pos, nil, dur)
            end
            local land = typeof(landCF) == 'CFrame' and landCF.Position or nil
            if land and not (typeof(pos) == 'Vector3'
                and Vector3.new(pos.X - land.X, 0, pos.Z - land.Z).Magnitude < 8) then
                addPointZone(land, nil, dur)
            end
            if enemy then
                addZone({ Kind = 'enemy', Enemy = enemy, R = dodgeDefaultRadius(), X = 0, Z = 0, Expires = tick() + dur })
            end
        end,
        Initial = function(enemy, pos, lifetime)
            if typeof(pos) == 'Vector3' then
                addPointZone(pos, nil, (type(lifetime) == 'number' and lifetime or 2) + 2)
            end
        end,
        CreateImpact = function(enemy)
            if enemy then -- residual hitbox the moment he lands
                addZone({ Kind = 'enemy', Enemy = enemy, R = dodgeDefaultRadius(), X = 0, Z = 0, Expires = tick() + 2 })
            end
        end,
    },
    FireDash = { Initial = function(enemy, fromPos, toPos, endCFrame, speed, width)
        if typeof(fromPos) ~= 'Vector3' then return end
        local target = typeof(endCFrame) == 'CFrame' and endCFrame.Position or toPos
        if typeof(target) ~= 'Vector3' then return end
        local travel = typeof(toPos) == 'Vector3' and (toPos - fromPos).Magnitude or 0
        addSegmentZone(fromPos, target,
            math.max((type(width) == 'number' and width or 12) * 0.5, 8),
            travel / (type(speed) == 'number' and speed or 60) + 2)
    end },
    OceanGyzer = { CreateGyzer = function(enemy, pos, lifetime)
        if typeof(pos) == 'Vector3' then
            addPointZone(pos, nil, (type(lifetime) == 'number' and lifetime or 3) + 1.5)
        end
    end },
    OmegaWave = { FireWave = function(enemy, pos, dist)
        if typeof(pos) ~= 'Vector3' then return end
        local root = enemyRoot(enemy)
        local look = root and root.CFrame.LookVector or Vector3.new(0, 0, -1)
        addSegmentZone(pos, pos + look * (type(dist) == 'number' and dist or 80), 40, 5.5)
    end },
    GorillaSlam = { MakeImpact = function(enemy, cf)
        local pos = typeof(cf) == 'CFrame' and cf.Position or cf
        if typeof(pos) == 'Vector3' then addPointZone(pos, 26, 3) end
    end },
    GorillaTornado = { Initial = function(enemy)
        if enemy then
            addZone({ Kind = 'enemy', Enemy = enemy, R = 30, X = 0, Z = 0, Expires = tick() + 10 })
        end
    end },
    KrampusStomp = { Initial = function(enemy, cf)
        local pos = typeof(cf) == 'CFrame' and cf.Position or cf
        if typeof(pos) == 'Vector3' then addPointZone(pos, nil, 3) end
    end },
    FrozenDestuction = { Initial = function(enemy, pos)
        if typeof(pos) == 'Vector3' then addPointZone(pos, nil, 4) end
    end },
    LeviathanSlam = { Initial = function(enemy, pos)
        if typeof(pos) == 'Vector3' then addPointZone(pos, 35, 4) end
    end },
    -- Wendigo beam: Replicating carries the impact point the beam sweeps to
    SinisterLaser = (function()
        local beam = function(enemy, pos)
            if typeof(pos) ~= 'Vector3' then return end
            local root = enemyRoot(enemy)
            if root then
                addSegmentZone(root.Position, pos, 8, 5)
            else
                addPointZone(pos, 14, 5)
            end
        end
        return { Replicating = beam, Initial = beam }
    end)(),
    -- Warlord gas: Replicating(SurfacePosition, RadiusSize), then CreateImpact
    -- pulses grow the ring by RadiusSize every ~2s - grow our zone with it
    GasSmoke = (function()
        local smokes = setmetatable({}, { __mode = 'k' }) -- enemy -> { Zone, Step }
        return {
            Replicating = function(enemy, pos, radiusSize)
                if typeof(pos) ~= 'Vector3' then return end
                local r = type(radiusSize) == 'number' and radiusSize or 10
                smokes[enemy] = { Step = r, Zone = addPointZone(pos, r * 2, 10) }
            end,
            Initial = function(enemy, pos, radiusSize)
                if typeof(pos) ~= 'Vector3' then return end
                local r = type(radiusSize) == 'number' and radiusSize or 10
                smokes[enemy] = { Step = r, Zone = addPointZone(pos, r * 2, 10) }
            end,
            CreateImpact = function(enemy)
                local s = enemy and smokes[enemy]
                if s and s.Zone and s.Zone.Expires then
                    s.Zone.R = s.Zone.R + s.Step
                    s.Zone.Expires = tick() + 3
                end
            end,
        }
    end)(),
    -- The Between tempest wave: strike VFX lands at a CFrame; big attack -> low
    TempestStrike = { CreateStrike = function(enemy, cf)
        local pos = typeof(cf) == 'CFrame' and cf.Position or cf
        if typeof(pos) == 'Vector3' then addPointZone(pos, 35, 5, true) end
    end },
    -- Rubricatus nuke: the remote only contributes the blast point; the
    -- pillar watcher owns the window (spawn = windup, despawn = over)
    RubricatusNuke = {
        Replicating = function(enemy, pos)
            if typeof(pos) == 'Vector3' then NukeBlastPos, NukeBlastAt = pos, tick() end
            armNukeWatch()
        end,
        Trigger = function()
            armNukeWatch()
            NukeArmAt = tick() - 10 -- detonated: only a ~4s tail left
        end,
    },
}
SkillZoneHandlers.ShadowBeam = SkillZoneHandlers.SinisterLaser -- same beam-to-point layout

-- one caster-following zone per enemy; recasts extend it instead of stacking
local casterZones = setmetatable({}, { __mode = 'k' })
local addCasterZone = function(enemy, duration)
    if not (enemy and enemyRoot(enemy)) then return end
    if not (Toggles.DodgeCasterAoE == nil or Toggles.DodgeCasterAoE.Value) then return end
    local expires = tick() + duration
    local zone = casterZones[enemy]
    if zone and table.find(DangerZones.List, zone) then
        zone.Expires = math.max(zone.Expires, expires)
        zone.R = dodgeDefaultRadius()
        return
    end
    casterZones[enemy] = addZone({ Kind = 'enemy', Enemy = enemy, R = dodgeDefaultRadius(), X = 0, Z = 0, Expires = expires })
end

local genericSkillZones = function(enemy, args, low)
    local root = enemyRoot(enemy)
    local ePos = root and root.Position
    local duration = 4
    local casterAoE = true -- no remote position away from the caster -> it's an AoE on itself
    for _, arg in next, args do
        if type(arg) == 'number' and arg > 0.2 and arg < 45 then
            duration = arg + 1.5
            break
        end
    end
    for _, arg in next, args do
        local pos
        local t = typeof(arg)
        if t == 'Vector3' then
            pos = arg
        elseif t == 'CFrame' then
            pos = arg.Position
        elseif t == 'Instance' then
            if arg:IsA('Attachment') then
                pos = arg.WorldPosition
            elseif arg:IsA('BasePart') then
                pos = arg.Position
            else
                local ok, value = pcall(function() return arg.Value end)
                if ok and typeof(value) == 'Vector3' then
                    pos = value
                elseif ok and typeof(value) == 'CFrame' then
                    pos = value.Position
                end
            end
        end
        -- positions hugging the caster are covered by the caster zone below
        if pos and (not ePos or Vector3.new(pos.X - ePos.X, 0, pos.Z - ePos.Z).Magnitude > 16) then
            addPointZone(pos, nil, duration, low)
            casterAoE = false
        end
    end
    -- self-centred casts (stomps, spins, novas) used to produce NO zone, so we
    -- stood under the mob until the hit landed - zone the caster itself the
    -- instant the cast remote arrives
    if casterAoE then
        addCasterZone(enemy, math.min(duration, Options.CasterDodgeTime and Options.CasterDodgeTime.Value or 2.5))
    end
end

task.spawn(function()
    local ReplicateSkill = game:GetService('ReplicatedStorage'):WaitForChild('ReplicateSkill', 15)
    if not ReplicateSkill then return end

    ReplicateSkill.OnClientEvent:Connect(function(enemy, phase, skillName, ...)
        if getgenv().Bluu == false then return end
        if type(skillName) == 'string' then
            DodgeSeenSkills[skillName] = true -- feeds the Dodge tab attack list
        end
        if bossSkillIgnored(enemy, skillName) then return end
        if DodgeSkillIgnored[skillName] then return end -- ignored in the Dodge tab
        DangerZones.LastSkillAt = tick()
        if type(skillName) ~= 'string' then return end
        hookSkillTags(skillName)

        local args = { ... }
        local phaseKey = phase
        if phase == 'RunPhase' then
            phaseKey = args[1]
            table.remove(args, 1)
        end

        -- zones spawned by this dispatch get stamped with the skill name so a
        -- per-attack size override (Dodge tab) applies to all of them
        pendingSkill = skillName
        local fn = SkillZoneHandlers[skillName] and SkillZoneHandlers[skillName][phaseKey]
        if not (fn and pcall(fn, enemy, table.unpack(args))) then
            genericSkillZones(enemy, args, LOW_DODGE_SKILLS[skillName] == true)
        end
        pendingSkill = nil
    end)
end)

-- The Between special waves arrive on their own remote: ReplicateWave(waveType,
-- event, ...). Lava's 'Warning' shakes the floor section that's about to turn
-- to lava for <duration>s - zone its footprint for the warning + burn window.
task.spawn(function()
    if not IN_BETWEEN then return end -- ReplicateWave only exists there anyway
    local ReplicateWave = game:GetService('ReplicatedStorage'):WaitForChild('ReplicateWave', 30)
    if not ReplicateWave then return end
    ReplicateWave.OnClientEvent:Connect(function(waveType, event, model, duration)
        if getgenv().Bluu == false then return end
        if waveType ~= 'Lava' or event ~= 'Warning' then return end
        if typeof(model) ~= 'Instance' then return end
        local ok, cf, size = pcall(function()
            if model:IsA('BasePart') then return model.CFrame, model.Size end
            return model:GetPivot(), model:GetExtentsSize()
        end)
        if not (ok and cf and size) then return end
        addZone({
            Kind = 'box',
            CF = cf,
            Size = size,
            Expires = tick() + (type(duration) == 'number' and duration or 3) + (Options.LavaZoneTime and Options.LavaZoneTime.Value or 8),
            Low = true,
        })
    end)
end)

-- enforce every frame, before physics/touch processing, autofarm on or off --
-- the farm loop runs after task.wait() and would otherwise lag a frame behind
DangerZones.ApplyNow = function()
    if not dodgeEnabled() then return end
    if not (HumanoidRootPart and Humanoid) or Humanoid.Health == 0 then return end
    local pos = HumanoidRootPart.Position
    local resolved = resolveDodge(pos)
    if resolved ~= pos then
        HumanoidRootPart.CFrame = HumanoidRootPart.CFrame.Rotation + resolved
    end
end
local applyConns = {
    RunService.PreSimulation:Connect(function()
        if getgenv().Bluu == false then return end
        pcall(DangerZones.ApplyNow)
    end),
    RenderStepped:Connect(function()
        if getgenv().Bluu == false then return end
        pcall(DangerZones.ApplyNow)
    end),
}

-- purge dead zones so the list can't grow forever when dodging is idle
task.spawn(function()
    while getgenv().Bluu ~= false do
        task.wait(5)
        local now = tick()
        for i = #DangerZones.List, 1, -1 do
            local zone = DangerZones.List[i]
            if zone.Expires and now > zone.Expires then
                table.remove(DangerZones.List, i)
            end
        end
    end
end)

Autofarm:AddToggle('Autofarm', { Text = 'Enabled' }):OnChanged(function()
    toggleLerp(Toggles.Autofarm)
    enableLinearVelocity(Toggles.Autofarm.Value)
    toggleNoclip(Toggles.Autofarm)

    local target
    local shouldUpdateTarget = true
    local noTargetSince
    local sawTarget = false      -- becomes true once ANY killable target exists this session
    local farmStart = tick()     -- when this farm loop began (right after join)

    local farmTick = function(deltaTime)
        local inputVec = Vector3.new(controls.D - controls.A, 0, controls.S - controls.W)
        if inputVec.Magnitude ~= 0 then
            local flySpeed = 100
            local direction = Camera.CFrame.Rotation * inputVec.Unit
            local moveDelta = direction * flySpeed * deltaTime
            local movePos = HumanoidRootPart.Position + moveDelta * math.clamp(deltaTime * flySpeed / moveDelta.Magnitude, 0, 1)
            HumanoidRootPart.CFrame = HumanoidRootPart.CFrame.Rotation + resolveDodge(movePos)
            return
        end

        if lowHealthEscaping then return end -- emergency escape has movement priority

        if shouldUpdateTarget then
            shouldUpdateTarget = false
            target = getAutofarmTarget()
            task.delay(0.15, function()
                shouldUpdateTarget = true
            end)
        end

        if not target then
            -- Restart Server: wait for mobs to actually spawn first - the
            -- empty-timer only counts once we've seen a killable target this
            -- session, OR the give-up cap hit (truly dead server, bail anyway).
            -- The Between empties between every wave - never hop from there
            if not IN_BETWEEN and Toggles.RestartServer and Toggles.RestartServer.Value then
                local giveUpAfter = math.max(60, Options.RestartServerDelay.Value * 10)
                if sawTarget or tick() - farmStart >= giveUpAfter then
                    noTargetSince = noTargetSince or tick()
                    if tick() - noTargetSince >= Options.RestartServerDelay.Value then
                        if saveServerSwitchConfig and HumanoidRootPart then
                            saveServerSwitchConfig(game.PlaceId, HumanoidRootPart.Position)
                        end
                        pcall(function()
                            game:GetService('TeleportService'):Teleport(659222129, LocalPlayer)
                        end)
                    end
                end
            else
                noTargetSince = nil
            end

            -- Bob wave takes top priority: never idle at the waypoint or orb
            -- if they'd put us in his reach
            local bobDist = bobDistance()
            local bobPos = bobDist and nearestBobPos()
            if bobPos then
                if (HumanoidRootPart.Position - bobPos).Magnitude < bobDist then
                    local flat = Vector3.new(HumanoidRootPart.Position.X - bobPos.X, 0, HumanoidRootPart.Position.Z - bobPos.Z)
                    local dir = flat.Magnitude > 0 and flat.Unit or Vector3.new(0, 0, 1)
                    local edge = bobPos + dir * bobDist
                    local safePos = Vector3.new(edge.X, HumanoidRootPart.Position.Y, edge.Z)
                    HumanoidRootPart.CFrame = HumanoidRootPart.CFrame.Rotation + resolveDodge(safePos)
                end
                return
            end

            local lightPos = inBlackoutLight()
            if lightPos then
                HumanoidRootPart.CFrame = HumanoidRootPart.CFrame.Rotation + resolveDodge(lightPos)
            elseif Toggles.UseWaypoint.Value and waypoint then
                HumanoidRootPart.CFrame = HumanoidRootPart.CFrame.Rotation + resolveDodge(waypoint.Position)
            end
            return
        end
        noTargetSince = nil
        sawTarget = true

        -- objective mobs (glowing / rift on its wave) stay the target until
        -- they die, regardless of tag/ignore state - unless it goes immortal
        local objective = mobGlows(target) or (inRiftWave() and mobIsRift(target))
        if isDead(target) or mobIsImmortal(target) or (not objective
            and (Options.IgnoreMobs.Value[target.Name] or tagGate(target))) then
            shouldUpdateTarget = true
            return
        end

        local rootPart, radius, vertical, horizontal = calculateAutofarmOffset(target)
        if not rootPart then return end

		-- if Options.AutofarmVerticalOffset.Value < 0 then
		--     flipUpsideDown(HumanoidRootPart)
		-- end

		local targetPos = rootPart.Position
			+ Vector3.new(0, (HumanoidRootPart.Size.Y - rootPart.Size.Y) * 0.5 + vertical, 0)

        if rootPart:FindFirstChild('BodyVelocity') and rootPart.BodyVelocity.VectorVelocity.Magnitude > 0 then
            targetPos += rootPart.BodyVelocity.VectorVelocity.Unit
        end

        local diff = HumanoidRootPart.Position - rootPart.Position
        local horizOffset = Vector3.new(diff.X, 0, diff.Z)

        if horizontal > 0 and horizOffset.Magnitude ~= 0 then
            targetPos += horizOffset.Unit * horizontal
        end

        -- blackout: never stand outside the light - pull the point back toward
        -- the orb if the target sits near its edge
        local lightPos, lightRange = inBlackoutLight()
        if lightPos then
            local fromLight = targetPos - lightPos
            local maxDist = math.max(lightRange - 4, 0)
            if fromLight.Magnitude > maxDist then
                targetPos = lightPos + fromLight.Unit * maxDist
            end
        end

        -- bob wave: never let the stand point come within reach of him
        local bobDist = bobDistance()
        local bobPos = bobDist and nearestBobPos()
        if bobPos then
            local fromBob = targetPos - bobPos
            if fromBob.Magnitude < bobDist then
                local dir = fromBob.Magnitude > 0 and fromBob.Unit or Vector3.new(1, 0, 0)
                targetPos = bobPos + dir * bobDist
            end
        end

        HumanoidRootPart.CFrame = HumanoidRootPart.CFrame.Rotation + resolveDodge(targetPos)
    end

    while Toggles.Autofarm.Value do
        local deltaTime = task.wait()

        if Humanoid.Health == 0 then continue end

        -- pcall so a bad mob/zone/part can never kill the farm thread
        local ok, err = pcall(farmTick, deltaTime)
        if not ok then warn('[Autofarm]', err) end
    end
end)

Autofarm:AddSlider('AutofarmVerticalOffset', {
    Text = 'Vertical offset',
    Default = -60,
    Min = -60,
    Max = 60,
    Rounding = 0,
    Suffix = 'm',
    FormatDisplayValue = function(slider, value)
        if value == slider.Max then return 'Auto high' end
        if value == slider.Min then return 'Auto low' end
	end
})
Autofarm:AddSlider('AutofarmHorizontalOffset', {
    Text = 'Horizontal offset',
    Default = 0,
    Min = 0,
    Max = 60,
    Rounding = 0,
    Suffix = 'm',
    FormatDisplayValue = function(slider, value)
        if value == slider.Max then return 'Auto' end
	end
})
local autofarmRadiusSlider = Autofarm:AddSlider('AutofarmRadius', {
    Text = 'Radius',
    Default = 10000,
    Min = 0,
    Max = 10000,
    Rounding = 0,
    Suffix = 'm',
    FormatDisplayValue = function(slider, value)
        if value == slider.Max then return 'Infinite' end
	end
})
autofarmRadiusSlider:OnChanged(function(value)
    local snapped = math.round(value / 100) * 100
    if snapped ~= value then
        autofarmRadiusSlider:SetValue(snapped)
    end
end)

Autofarm:AddToggle('RestartServer', {
    Text = 'Restart server',
    Tooltip = 'When no killable mobs remain, hop through the hub into a fresh server so the boss respawns'
}):OnChanged(function(value)
    -- arms the main.lua join gate: while on, landing on a populated server means
    -- block everyone (no exemptions) + re-hop BEFORE autofarm ever starts
    if writefile and isfolder then
        if not isfolder('Bluu') then makefolder('Bluu') end
        if not isfolder('Bluu/Swordburst 2') then makefolder('Bluu/Swordburst 2') end
        writefile(RESTART_GATE_FILE or `Bluu/Swordburst 2/restartgate_{LocalPlayer.UserId}`, value and '1' or '0')
    end
end)
Autofarm:AddSlider('RestartServerDelay', {
    Text = 'Hop after empty',
    Default = 10,
    Min = 1,
    Max = 60,
    Rounding = 0,
    Suffix = 's',
    Compact = true
})
Autofarm:AddToggle('DodgeAttacks', { Text = 'Dodge attacks', Default = true })
Autofarm:AddToggle('BlockSkillDamage', {
    Text = 'Block wave/tide damage',
    Default = true,
    Tooltip = 'Drops the client-reported DamageSelf remote used by Touched skills (OmegaWave, Leviathan tides, PanStorm, GuardianBalls...)'
})
Autofarm:AddToggle('DodgeCasterAoE', {
    Text = 'Dodge self-centred casts',
    Default = true,
    Tooltip = 'Unknown skills with no target position: back off the casting mob (Unknown attack radius) the instant the cast starts'
})
Autofarm:AddSlider('CasterDodgeTime', {
    Text = 'Caster dodge time',
    Default = 2.5,
    Min = 0.5,
    Max = 6,
    Rounding = 1,
    Suffix = 's',
    Compact = true
})
Autofarm:AddSlider('LavaZoneTime', {
    Text = 'Lava avoid time',
    Tooltip = 'The Between lava wave: how long to keep off a section after its warning ends',
    Default = 8,
    Min = 0,
    Max = 30,
    Rounding = 0,
    Suffix = 's',
    Compact = true
})
Autofarm:AddSlider('DodgePadding', {
    Text = 'Dodge padding',
    Default = 4,
    Min = 0,
    Max = 20,
    Rounding = 0,
    Suffix = 'm'
})
Autofarm:AddSlider('DodgeRadius', {
    Text = 'Unknown attack radius',
    Default = 20,
    Min = 6,
    Max = 80,
    Rounding = 0,
    Suffix = 'm'
})
Autofarm:AddSlider('DodgeScale', {
    Text = 'Zone size multiplier',
    Tooltip = 'Inflates every danger zone - server hitboxes are often bigger than the visual marker',
    Default = 2,
    Min = 1,
    Max = 5,
    Rounding = 1,
    Suffix = 'x',
    Compact = true
})
Autofarm:AddSlider('DodgeLowSize', {
    Text = 'Go low above size',
    Tooltip = 'Danger zones with a footprint at least this big are escaped by dropping under them (lava sections, tempest strikes, wave bosses) instead of sidestepping',
    Default = 45,
    Min = 10,
    Max = 200,
    Rounding = 0,
    Suffix = 'm',
    Compact = true
})
Autofarm:AddSlider('DodgeLowDepth', {
    Text = 'Go low depth',
    Tooltip = 'How far below a big attack we drop until it expires',
    Default = 80,
    Min = 20,
    Max = 500,
    Rounding = 0,
    Suffix = 'm',
    Compact = true
})

local zoneVisuals = {}
Autofarm:AddToggle('ShowDangerZones', { Text = 'Show danger zones' }):OnChanged(function()
    while Toggles.ShowDangerZones.Value do
        local used = {}
        local now = tick()
        for _, zone in next, DangerZones.List do
            if zone.Expires and now > zone.Expires then continue end
            local cf, size
            if zone.Kind == 'point' or zone.Kind == 'enemy' then
                local rr = zone.R * zoneScale(zone) + dodgePadding()
                local root = zone.Kind == 'enemy' and zone.Enemy and zone.Enemy:FindFirstChild('HumanoidRootPart')
                if zone.Kind == 'enemy' and not root then continue end
                cf = zone.Kind == 'point' and CFrame.new(zone.X, zone.Y or HumanoidRootPart.Position.Y, zone.Z)
                    or CFrame.new(root.Position)
                size = Vector3.new(rr * 2, 0.2, rr * 2)
            elseif zone.Kind == 'box' then
                cf = zone.CF
                size = zone.Size * zoneScale(zone) + Vector3.new(dodgePadding() * 2, 0, dodgePadding() * 2)
            else
                local part = zone.Part
                if part and part:IsDescendantOf(workspace) then
                    cf = part.CFrame
                    size = part.Size * zoneScale(zone) + Vector3.new(dodgePadding() * 2, 0, dodgePadding() * 2)
                elseif zone.LastCF then
                    cf = zone.LastCF
                    size = zone.LastSize * zoneScale(zone) + Vector3.new(dodgePadding() * 2, 0, dodgePadding() * 2)
                end
            end
            if not cf then continue end
            local vis = zoneVisuals[zone]
            if not vis then
                vis = Instance.new('Part')
                vis.Name = 'DangerZoneVisual'
                vis.Anchored = true
                vis.CanCollide = false
                vis.CanQuery = false
                vis.CanTouch = false
                vis.CastShadow = false
                vis.Transparency = 0.6
                vis.Material = Enum.Material.Neon
                vis.Color = Color3.fromRGB(255, 60, 60)
                vis.Parent = workspace
                zoneVisuals[zone] = vis
            end
            vis.Size = Vector3.new(math.max(size.X, 0.2), 0.2, math.max(size.Z, 0.2))
            vis.CFrame = cf.Rotation + cf.Position
            used[zone] = true
        end
        for zone, vis in next, zoneVisuals do
            if not used[zone] then
                vis:Destroy()
                zoneVisuals[zone] = nil
            end
        end
        RenderStepped:Wait()
    end
    for _, vis in next, zoneVisuals do
        vis:Destroy()
    end
    table.clear(zoneVisuals)
end)

if BluuCleanups then
    table.insert(BluuCleanups, function()
        for _, c in next, applyConns do
            pcall(function() c:Disconnect() end)
        end
        for _, vis in next, zoneVisuals do
            pcall(function() vis:Destroy() end)
        end
        table.clear(zoneVisuals)
        table.clear(DangerZones.List)
        BetweenNukeCover = nil
    end)
end

radiusDisc = nil
Autofarm:AddToggle('ShowRadius', { Text = 'Show radius' }):OnChanged(function(value)
    if not value then return end
    if not radiusDisc then
        radiusDisc = Instance.new('Part')
        radiusDisc.Name = 'AutofarmRadiusDisc'
        radiusDisc.Shape = Enum.PartType.Cylinder
        radiusDisc.Anchored = true
        radiusDisc.CanCollide = false
        radiusDisc.CanQuery = false
        radiusDisc.CanTouch = false
        radiusDisc.CastShadow = false
        radiusDisc.Transparency = 0.75
        radiusDisc.Material = Enum.Material.Neon
        radiusDisc.Color = Color3.fromRGB(130, 100, 255)
        radiusDisc.Parent = workspace
    end
    while Toggles.ShowRadius.Value do
        local radius = Options.AutofarmRadius.Value
        if radius >= Options.AutofarmRadius.Max or not HumanoidRootPart.Parent then
            radiusDisc.Transparency = 1
        else
            radiusDisc.Transparency = 0.75
            radiusDisc.Size = Vector3.new(0.3, radius * 2, radius * 2)
            radiusDisc.CFrame = HumanoidRootPart.CFrame * CFrame.new(0, -2.8, 0) * CFrame.Angles(0, 0, math.rad(90))
        end
        RenderStepped:Wait()
    end
    radiusDisc.Transparency = 1
end)
Autofarm:AddToggle('UseWaypoint', { Text = 'Use waypoint' }):OnChanged(function(value)
    -- While restoring a config we keep the saved coords; don't overwrite with current pos.
    if not waypointRestoring then
        if value then
            waypoint.CFrame = HumanoidRootPart.CFrame
            local p = HumanoidRootPart.Position
            saveFloorData({ useWaypoint = true, wp = { p.X, p.Y, p.Z } })
        else
            saveFloorData({ useWaypoint = false })
        end
    end
    waypointLabel.Visible = value
end)

-- Restore the saved waypoint + path-farming state for the current floor.
function restoreFloorData()
    local data = getFloorData()
    if not data then
        waypointRestoring = false
        return
    end

    waypointRestoring = true

    if data.wp and #data.wp == 3 then
        waypoint.CFrame = CFrame.new(data.wp[1], data.wp[2], data.wp[3])
    end

    if data.useWaypoint and Toggles.UseWaypoint then
        Toggles.UseWaypoint:SetValue(true)
        waypointLabel.Visible = true
        -- re-apply in case SetValue's handler nudged the part
        if data.wp and #data.wp == 3 then
            waypoint.CFrame = CFrame.new(data.wp[1], data.wp[2], data.wp[3])
        end
    end

    task.spawn(function()
        task.wait(0.2)
        waypointRestoring = false

        if data.pathFarming then
            -- Path farming needs waypoints + autofarm; wait for the waypoint config to load.
            local timeout = tick() + 10
            while #WaypointSystem.waypoints == 0 and tick() < timeout do
                task.wait(0.2)
            end
            if #WaypointSystem.waypoints > 0 then
                if not Toggles.Autofarm.Value then
                    task.spawn(function()
                        Toggles.Autofarm:SetValue(true)
                    end)
                    task.wait(0.5)
                end
                if Toggles.EnablePathFarming then
                    Toggles.EnablePathFarming:SetValue(true)
                end
            end
        end
    end)
end

local mobList = (function()
    if RequiredServices then
        local MobDataCache = RequiredServices.StatsUI.MobDataCache
        if type(MobDataCache) ~= 'table' then
            return {}
        end
        local mobList = {}
        for mobName, _ in next, MobDataCache do
            table.insert(mobList, mobName)
        end
        table.sort(mobList, function(mobName1, mobName2)
            return MobDataCache[mobName1].HealthValue > MobDataCache[mobName2].HealthValue
        end)
        return mobList
    end

    local floorLists = {
        [540240728] = { -- Arcadia
            'Tremor',
            'Iris Dominus Dummy',
            'Dywane',
            'Nightmare Kobold Lord',
            'Platemail',
            'Statue',
            'Dummy'
        },
        [542351431] = { -- Floor 1 / Virhst Woodlands
            'Tremor',
            'Rahjin the Thief King',
            'Ruined Kobold Lord',
            'Dire Wolf',
            'Dementor',
            'Ruined Kobold Knight',
            'Ruin Kobold Knight',
            'Ruin Knight',
            'Draconite',
            'Bear',
            'Earthen Crab',
            'Earthen Boar',
            'Wolf',
            'Hermit Crab',
            'Frenzy Boar',
            'Item Crystal',
            'Iron Chest',
            'Wood Chest'
        },
        [737272595] = { -- Battle Arena
            'Tremor'
        },
        [548231754] = { -- Floor 2 / Redveil Grove
            'Tremor',
            'Gorrock the Grove Protector',
            'Borik the BeeKeeper',
            'Pearl Guardian',
            'Redthorn Tortoise',
            'Bushback Tortoise',
            'Giant Ruins Hornet',
            'Wasp',
            'Pearl Keeper',
            'Leafray',
            'Leaf Ogre',
            'Leaf Beetle',
            'Dementor',
            'Iron Chest',
            'Wood Chest'
        },
        [555980327] = { -- Floor 3 / Avalanche Expanse
            'Tremor',
            `Ra'thae the Ice King`,
            'Qerach the Forgotten Golem',
            'Alpha Icewhal',
            'Ice Elemental',
            'Ice Walker',
            'Icewhal',
            'Angry Snowman',
            'Snowhorse',
            'Snowgre',
            'Dementor',
            'Iron Chest',
            'Wood Chest'
        },
        [572487908] = { -- Floor 4 / Hidden Wilds
            'Tremor',
            'Irath the Lion',
            'Rotling',
            'Lion Protector',
            'Dungeon Dweller',
            'Bamboo Spider',
            'Boneling',
            'Birchman',
            'Treeray Old',
            'Treeray',
            'Bamboo Spiderling',
            'Treehorse',
            'Wattlechin Crocodile',
            'Dementor',
            'Ancient Chest',
            'Gold Chest',
            'Iron Chest',
            'Wood Chest'
        },
        [580239979] = { -- Floor 5 / Desolate Dunes
            'Tremor',
            `Sa'jun the Centurian Chieftain`,
            'Fire Scorpion',
            'Centaurian Defender',
            'Patrolman Elite',
            'Sand Scorpion',
            'Giant Centipede',
            'Green Patrolman',
            'Desert Vulture',
            'Angry Cactus',
            'Girdled Lizard',
            'Dementor',
            'Gold Chest',
            'Iron Chest',
            'Wood Chest'
        },
        [566212942] = { -- Floor 6 / Helmfirth
            'Tremor',
            'Rekindled Unborn'
        },
        [582198062] = { -- Floor 7 / Entoloma Gloomlands
            'Tremor',
            'Smashroom the Mushroom Behemoth',
            'Frogazoid',
            'Snapper',
            'Blightmouth',
            'Horned Sailfin Iguana',
            'Gloom Shroom',
            'Shroom Back Clam',
            'Firefly',
            'Jelly Wisp',
            'Dementor',
            'Gold Chest',
            'Iron Chest'
        },
        [548878321] = { -- Floor 8 / Blooming Plateau
            'Tremor',
            'Formaug the Jungle Giant',
            'Hippogriff',
            'Dungeon Crusader',
            'Wingless Hippogriff',
            'Forest Wanderer',
            'Sky Raven',
            'Leaf Rhino',
            'Petal Knight',
            'Giant Praying Mantis',
            'Dementor',
            'Gold Chest',
            'Iron Chest'
        },
        [573267292] = { -- Floor 9 / Va' Rok
            'Tremor',
            'Mortis the Flaming Sear',
            'Polyserpant',
            'Gargoyle Reaper',
            'Ent',
            'Undead Berserker',
            'Reptasaurus',
            'Undead Warrior',
            'Enraged Lingerer',
            'Fishrock Spider',
            'Lingerer',
            'Batting Eye',
            'Dementor',
            'Gold Chest',
            'Iron Chest'
        },
        [2659143505] = { -- Floor 10 / Transylvania
            'Tremor',
            'Grim, The Overseer',
            'Baal, The Tormentor',
            'Undead Servant',
            'Wendigo',
            'Clay Giant',
            'Guard Hound',
            'Grunt',
            'Winged Minion',
            'Shady Villager',
            'Minion',
            'Dementor',
            'Gold Chest',
            'Iron Chest'
        },
        [5287433115] = { -- Floor 11 / Hypersiddia
            'Tremor',
            'Saurus, the All-Seeing',
            'Za, the Eldest',
            'Da, the Demeanor',
            'Duality Reaper',
            'Duality Reaper (Old)',
            'Ka, the Mischief',
            'Ra, the Enlightener',
            'Neon Chest',
            'Wa, the Curious',
            'Meta Figure',
            'Rogue Android',
            '???????',
            'Shadow Figure',
            'DJ Reaper',
            'Armageddon Eagle',
            'Elite Reaper',
            'Watcher',
            'Command Falcon',
            'Soul Eater',
            'Reaper',
            'Sentry',
            'Dementor',
            'OG Duality Reaper',
            'OG Za, the Eldest',
            'Cybold',
            'Diamond Chest'
        },
        [6144637080] = { -- Floor 12 / Sector-235
            'Tremor',
            'Suspended Unborn',
            'Limor The Devourer',
            'Warlord',
            'Radioactive Experiment',
            'Ancient Wood Chest',
            'C-618 Uriotol, The Forgotten Hunter',
            'Bat',
            'Elite Scav',
            'Newborn Abomination',
            'Scav',
            'Radio Slug',
            'Crystal Lizard',
            'Orange Failed Experiment',
            'Failed Experiment',
            'Blue Failed Experiment',
            'Dementor',
            'Ancient Chest'
        },
        [13965775911] = { -- Atheon
            'Tremor',
            'Atheon',
            'Dementor'
        },
        [16810524216] = { -- Floor 12.5 / Eternal Garden
            'Azeis, Spirit of the Eternal Blossom',
            'Tworz, The Ancient',
            'Tremor',
            'Eternal Blossom Knight',
            'Ancient Blossom Knight',
            'Dementor'
        },
        [18729767954] = { -- Floor 12.5 / Glutton's Lair
            'Tremor',
            'Ramseis, Chef of Souls',
            'Meatball Abomination',
            'The Waiter',
            'Jelly Slime',
            'Rapapouillie',
            'Burger Mimic',
            'Cheese-Dip Slime',
            'Dementor'
        },
        [11331145451] = { -- Event Floor / Spooky Hollow
            'Tremor',
            'Tremor (Old)',
            'Terror Incarnate',
            'Enraged Wendigo',
            'Count Dracula, Vlad Tepes',
            'Watcher',
            'Cursed Giant',
            'Crumbling Gargoyle',
            'Rotten Brute',
            'Decayed Warrior',
            'Dark Spirit',
            'Abyssal Spider',
            'Vampiric Bat',
            'Dementor'
        },
        [15716179871] = { -- Event Floor / Frosty Fields
            'Tremor',
            'Vyroth, The Frostflame',
            'Ghost of the Future',
            'Krampus',
            'Kloff, Marauder of the Frost',
            'Ghost of the Present',
            'Ghost of the Past',
            'Rat',
            'Frostgre',
            'Icy Imp',
            'Dark Frost Goblin',
            'Crystalite',
            'Gemulite',
            'Glacius Howler',
            'Icy Snowman',
            'Dementor'
        },
    }

    if not IN_BETWEEN then
        return floorLists[game.PlaceId] or {}
    end

    -- The Between spawns waves from every floor's pool plus named minibosses /
    -- bosses (WaveDefenseConfigs Normal + Elite): its own bosses first, then
    -- the wave bosses, then every floor mob, de-duplicated
    local list, seen = {}, {}
    local add = function(name)
        if not seen[name] then seen[name] = true; table.insert(list, name) end
    end
    for _, name in next, {
        'Rubricatus, The Sentinel of Order', 'Vaelith, the Riftborn',
        'Nythrane, the Hollow Flame', 'Aegor, Warden of the Deep',
        'Corrupted Atheon', 'Atheon', 'Aeganatos, The Sunken Sovereign',
        'Azeis, Spirit of the Eternal Blossom', 'Ramseis, Chef of Souls',
        'Vyroth, The Frostflame', 'Terror Incarnate', 'Bob',
        'Suspended Unborn', 'Radioactive Experiment', 'Duality Reaper',
        'Za, the Eldest', 'Ra, the Enlightener', 'Da, the Demeanor', 'Ka, the Mischief',
        'Count Dracula, Vlad Tepes', 'Headless Horseman', 'The Cucurbita',
        'C-618 Uriotol, The Forgotten Hunter', 'Saurus, the All-Seeing',
        'Grim, The Overseer', 'Baal, The Tormentor', 'Egnor, the Undead King',
        'Magnor, the Necromancer', 'Gargoyle Reaper', 'Mortis the Flaming Sear',
        'Smashroom the Mushroom Behemoth', 'Formaug the Jungle Giant',
        'Gorrock the Grove Protector', 'Bulswick, the Elkwood Behemoth',
        "Ra'thae the Ice King", 'Qerach the Forgotten Golem', 'Alpha Icewhal',
        'Irath the Lion', "Sa'jun the Centurian Chieftain", 'Fire Scorpion',
        'Pearl Guardian', 'Hippogriff', 'Frogazoid', 'Borik the BeeKeeper',
        'Tworz, The Ancient', 'Kloff, Marauder of the Frost', 'Enraged Wendigo',
        'Meatball Abomination', 'The Waiter', 'Rotling', 'Warlord',
        'Rahjin the Thief King', 'Ruined Kobold Lord', 'Dire Wolf',
    } do add(name) end
    for _, names in next, floorLists do
        for _, name in next, names do add(name) end
    end
    return list
end)()

-- Autofarm:AddButton({ Text = 'Copy moblist', Func = function()
--     if #mobList == 0 then
--         return setclipboard(`[{game.PlaceId}] = \{\}`)
--     end
--     setclipboard(`[{game.PlaceId}] = \{\n'{table.concat(mobList, `',\n'`)}'\n\}`)
-- end })

Autofarm:AddDropdown('PrioritizeMobs', { Text = 'Prioritize mobs', Values = mobList, Multi = true, AllowNull = true })
Autofarm:AddDropdown('IgnoreMobs', { Text = 'Ignore mobs', Values = mobList, Multi = true, AllowNull = true })

Autofarm:AddToggle('DisableOnDeath', { Text = 'Disable on death' })

Autofarm:AddToggle('AssistMode', { Text = 'Assist mode' })

local assistPlayerNames = function()
    local names = {}
    for _, player in next, Players:GetPlayers() do
        if player ~= LocalPlayer then
            table.insert(names, player.Name)
        end
    end
    return names
end

local assistPlayerDropdown = Autofarm:AddDropdown('AssistPlayer', {
    Text = 'Assist player',
    Values = assistPlayerNames(),
    AllowNull = true
})

Autofarm:AddSlider('AssistDamage', {
    Text = 'Assist damage',
    Default = 5,
    Min = 0,
    Max = 100,
    Rounding = 0,
    Suffix = '%',
    Compact = true
})

Autofarm:AddToggle('TagMode', {
    Text = 'Tag mode',
    Tooltip = 'Hit each mob just enough to secure kill credit (Assist damage %), then move to the next one'
})

-- Persist the assist pick: rejoin a server with them in it -> auto-select again
local ASSIST_SAVE_PATH = 'Bluu/Swordburst 2/assistplayer'

local saveAssistPlayer = function(name)
    if not writefile then return end
    if not isfolder('Bluu') then makefolder('Bluu') end
    if not isfolder('Bluu/Swordburst 2') then makefolder('Bluu/Swordburst 2') end
    writefile(ASSIST_SAVE_PATH, name or '')
end

local getSavedAssistPlayer = function()
    if not (isfile and readfile and isfile(ASSIST_SAVE_PATH)) then return end
    local saved = readfile(ASSIST_SAVE_PATH)
    return saved ~= '' and saved or nil
end

local refreshAssistPlayers = function()
    Options.AssistPlayer:SetValues(assistPlayerNames())
    -- stale pick points at a player who left: clear it so assist mode doesn't
    -- silently block every target
    local pick = Options.AssistPlayer.Value
    if pick and not Players:FindFirstChild(pick) then
        Options.AssistPlayer:SetValue()
    end
end

assistPlayerDropdown:OnChanged(function(value)
    saveAssistPlayer(value)
end)

local assistMenuOpen = assistPlayerDropdown.Menu.Open
assistPlayerDropdown.Menu.Open = function(self, ...)
    refreshAssistPlayers()
    return assistMenuOpen(self, ...)
end

-- restore the saved pick once players have loaded in
task.spawn(function()
    task.wait(2)
    local saved = getSavedAssistPlayer()
    if saved and Players:FindFirstChild(saved) then
        Options.AssistPlayer:SetValue(saved)
    end
end)

Players.PlayerAdded:Connect(function(player)
    refreshAssistPlayers()
    -- saved player joined mid-session -> pick them automatically
    if player.Name == getSavedAssistPlayer() then
        Options.AssistPlayer:SetValue(player.Name)
    end
end)

Players.PlayerRemoving:Connect(function()
    task.defer(refreshAssistPlayers)
end)


-- ===================== AUTO DODGE TAB =====================
-- Per-attack zone sizes: every zone spawned by a skill's remote event (or its
-- telegraph tags) carries the skill name, so a configured scale replaces the
-- global 'Dodge scale' for that attack only. Saved instantly to
-- dodgescales.json - shared across floors, accounts and reloads.

DodgeTab = Window:AddTab('Dodge', 'shield')

local DODGE_SCALES_FILE = 'Bluu/Swordburst 2/dodgescales.json'
pcall(function() -- load saved per-attack scales
    if not (isfile and readfile) or not isfile(DODGE_SCALES_FILE) then return end
    local data = game:GetService('HttpService'):JSONDecode(readfile(DODGE_SCALES_FILE))
    if type(data) ~= 'table' then return end
    for name, scale in next, data do
        if type(name) == 'string' and type(scale) == 'number' then
            DodgeSkillScales[name] = scale
        end
    end
end)

local saveDodgeScales = function()
    pcall(function()
        if not writefile then return end
        if not isfolder('Bluu') then makefolder('Bluu') end
        if not isfolder('Bluu/Swordburst 2') then makefolder('Bluu/Swordburst 2') end
        writefile(DODGE_SCALES_FILE, game:GetService('HttpService'):JSONEncode(DodgeSkillScales))
    end)
end

-- per-attack ignore list, same deal: json array of skill names
local DODGE_IGNORED_FILE = 'Bluu/Swordburst 2/dodgeignored.json'
pcall(function()
    if not (isfile and readfile) or not isfile(DODGE_IGNORED_FILE) then return end
    local data = game:GetService('HttpService'):JSONDecode(readfile(DODGE_IGNORED_FILE))
    if type(data) ~= 'table' then return end
    for _, name in next, data do
        if type(name) == 'string' then DodgeSkillIgnored[name] = true end
    end
end)

local saveDodgeIgnored = function()
    pcall(function()
        if not writefile then return end
        if not isfolder('Bluu') then makefolder('Bluu') end
        if not isfolder('Bluu/Swordburst 2') then makefolder('Bluu/Swordburst 2') end
        local list = {}
        for name in next, DodgeSkillIgnored do table.insert(list, name) end
        writefile(DODGE_IGNORED_FILE, game:GetService('HttpService'):JSONEncode(list))
    end)
end

-- boss keyword -> its attacks (from the decompiled EnemySkills tree). A boss
-- sitting in workspace.Mobs seeds the list with every attack it can throw.
local DODGE_SKILL_CATALOG = {
    Atheon = { 'FireDash', 'LavaGyzer', 'LavaSmash' }, -- matches Corrupted Atheon
    Aeganatos = { 'OceanGyzer', 'OmegaWave' },
    Leviathan = { 'LeviathanRoar', 'LeviathanSlam' },
    Warlord = { 'GasSmoke' },
    Gorilla = { 'GorillaSlam', 'GorillaTornado' },
    Krampus = { 'KrampusStomp' },
    Kloff = { 'FrozenDestuction' },
    Vyroth = { 'Frostflare' },
    Dracula = { 'MagicStakes' },
    ['Skeletal Mage'] = { 'ArcaneBlasts' },
    ['Terror Incarnate'] = { 'CrimsonSmite', 'SummonEyes' },
    ['Incarnātus'] = { 'NightmareBarrage', 'SummonMasks' },
    Watcher = { 'EyeLaser' },
    Wendigo = { 'SinisterLaser' },
    Dementor = { 'ShadowBeam' },
    Yato = { 'DeathRays' },
    Guardian = { 'GuardianBalls', 'GuardianBeam', 'GuardianBox', 'GuardianCrystals' },
    ['Pan Ku'] = { 'PanStorm' },
    Aegor = { 'AegorSlam', 'AegorSpike' },
    Nythrane = { 'PurpleFireyOrb' },
    Rubricatus = { 'FallingStones', 'RedGroundSpikes', 'RedLightningDiscs',
        'RedLightningLaser', 'RedLightningWave', 'RubricatusAttack',
        'RubricatusLasers', 'RubricatusNuke', 'RubricatusSlam' },
    Vaelith = { 'RiftDetonation' },
}

-- fixed places -> every attack that can show up there (ReplicatedStorage
-- Database.Locations place ids + the EnemySkills tree)
local DODGE_PLACE_SKILLS = {
    [13965775911] = { 'FireDash', 'LavaGyzer', 'LavaSmash' }, -- Atheon arena
    [6144637080] = { 'FireDash', 'LavaGyzer', 'LavaSmash', 'GasSmoke' }, -- Sector-235
    [134019705603409] = { 'OceanGyzer', 'OmegaWave', 'LeviathanRoar', 'LeviathanSlam' }, -- Atlantis
    [140451479334590] = { 'GuardianBalls', 'GuardianBeam', 'GuardianBox', 'GuardianCrystals', 'PanStorm' }, -- Eternal Domain
    [15716179871] = { 'KrampusStomp', 'FrozenDestuction', 'Frostflare' }, -- Frosty Fields
    [100233121448291] = { 'KrampusStomp', 'FrozenDestuction', 'Frostflare' }, -- Permafrost Purgatory
    [11331145451] = { 'MagicStakes', 'ArcaneBlasts', 'CrimsonSmite', 'SummonEyes',
        'NightmareBarrage', 'SummonMasks', 'EyeLaser', 'SinisterLaser' }, -- Spooky Hollow
}
local BETWEEN_SKILLS = { 'AegorSlam', 'AegorSpike', 'PurpleFireyOrb', 'FallingStones',
    'RedGroundSpikes', 'RedLightningDiscs', 'RedLightningLaser', 'RedLightningWave',
    'RubricatusAttack', 'RubricatusLasers', 'RubricatusNuke', 'RubricatusSlam',
    'RiftDetonation', 'TempestStrike', 'FireyOrb' }
if IN_BETWEEN or game.PlaceId == 121252145396212 then
    DODGE_PLACE_SKILLS[game.PlaceId] = BETWEEN_SKILLS
end

local DodgeBox = DodgeTab:AddLeftGroupbox('Attack sizes', 'scaling')
local DodgeListBox = DodgeTab:AddRightGroupbox('Configured', 'list')

local manualDodgeSkills = {} -- names added by hand via the input box
local dodgeControls = {} -- attack name -> slider option id (section exists)
local suppressScaleWrite = false

-- one groupbox per attack, alternating columns so the tab stays balanced.
-- Created on demand as attacks get discovered.
local dodgeColumnRight = false
local makeDodgeSection
makeDodgeSection = function(name)
    if dodgeControls[name] then return end
    local key = 'DodgeScale_' .. string.gsub(name, '[^%w]', '_')
    local ignoreKey = 'DodgeOn_' .. string.gsub(name, '[^%w]', '_')
    dodgeControls[name] = key

    local box = dodgeColumnRight and DodgeTab:AddRightGroupbox(name) or DodgeTab:AddLeftGroupbox(name)
    dodgeColumnRight = not dodgeColumnRight
    box:AddToggle(ignoreKey, {
        Text = 'Dodge this attack',
        Default = DodgeSkillIgnored[name] ~= true,
        Tooltip = `Off: {name} casts produce no danger zones at all`,
    }):OnChanged(function(value)
        DodgeSkillIgnored[name] = not value or nil
        saveDodgeIgnored()
    end)
    box:AddSlider(key, {
        Text = 'Zone size',
        Default = DodgeSkillScales[name] or dodgeScale(),
        Min = 0.5,
        Max = 10,
        Rounding = 1,
        Suffix = 'x',
        Compact = true,
        Tooltip = `Dodge zone size for {name} - overrides the global scale`,
    }):OnChanged(function(value)
        if suppressScaleWrite then return end
        DodgeSkillScales[name] = value
        saveDodgeScales()
    end)
    box:AddButton({
        Text = 'Use global size',
        Func = function()
            DodgeSkillScales[name] = nil
            saveDodgeScales()
            suppressScaleWrite = true
            pcall(function() Options[key]:SetValue(dodgeScale()) end)
            suppressScaleWrite = false
        end,
    })
end

local refreshDodgeAttacks
refreshDodgeAttacks = function()
    local set = {}
    for name in next, DodgeSeenSkills do set[name] = true end -- seen live this session
    for name in next, manualDodgeSkills do set[name] = true end
    for _, name in next, DODGE_PLACE_SKILLS[game.PlaceId] or {} do set[name] = true end
    for boss, skills in next, DODGE_SKILL_CATALOG do
        for _, mob in next, Mobs:GetChildren() do
            if string.find(mob.Name, boss, 1, true) then
                for _, name in next, skills do set[name] = true end
                break
            end
        end
    end
    for name in next, DodgeSkillScales do set[name] = true end -- overrides never hide

    local names = {}
    for name in next, set do table.insert(names, name) end
    table.sort(names)
    for _, name in next, names do makeDodgeSection(name) end
end

DodgeBox:AddInput('DodgeAttackName', {
    Text = 'Add attack by name',
    Tooltip = 'Exact skill name (e.g. LavaSmash) - creates a section for attacks not seen yet',
    Finished = true,
    Placeholder = 'LavaSmash'
}):OnChanged(function(name)
    if type(name) ~= 'string' or name == '' then return end
    manualDodgeSkills[name] = true
    makeDodgeSection(name)
end)

DodgeListBox:AddButton('Reset all to global', function()
    table.clear(DodgeSkillScales)
    saveDodgeScales()
    suppressScaleWrite = true
    for _, key in next, dodgeControls do
        pcall(function() Options[key]:SetValue(dodgeScale()) end)
    end
    suppressScaleWrite = false
end)

local dodgeCfgLabel = DodgeListBox:AddLabel('')
task.spawn(function()
    while getgenv().Bluu ~= false do
        refreshDodgeAttacks()
        local lines = {}
        for name, scale in next, DodgeSkillScales do
            table.insert(lines, `{name} = {scale}x`)
        end
        table.sort(lines)
        pcall(function()
            dodgeCfgLabel:SetText(#lines > 0 and table.concat(lines, '\n') or 'No per-attack sizes yet')
        end)
        task.wait(2)
    end
end)
