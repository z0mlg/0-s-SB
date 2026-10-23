-- Bluu :: ESP  (split from Sb2-0mlg.lua)

local EspTab = Window:AddTab('ESP', 'eye')

do
    local PlayerEspBox = EspTab:AddLeftGroupbox('Player ESP')
    local MobEspBox = EspTab:AddRightGroupbox('Mob ESP')

    -- shared option-set builder; ids prefixed PlayerEsp/MobEsp
    local function buildEspOptions(box, prefix, isPlayer)
        box:AddToggle(prefix, { Text = 'Enable', Default = false })
        if isPlayer then
            box:AddToggle(prefix .. 'TeamCheck', { Text = 'Team check', Default = false })
            box:AddToggle(prefix .. 'SelfEsp', { Text = 'Self ESP', Default = false })
            box:AddToggle(prefix .. 'TeamColor', { Text = 'Team based color', Default = false })
        end
        box:AddToggle(prefix .. 'Outline', { Text = 'Outline', Default = true })
        box:AddSlider(prefix .. 'RenderDist', {
            Text = 'Render distance',
            Default = 3000,
            Min = 0,
            Max = 10000,
            Rounding = 0,
            FormatDisplayValue = function(_, v)
                return v >= 10000 and 'Infinite' or tostring(v)
            end
        }):OnChanged(function(v)
            local snapped = math.floor(v / 100 + 0.5) * 100
            if snapped ~= v then
                Options[prefix .. 'RenderDist']:SetValue(snapped)
            end
        end)

        box:AddDivider({ Text = 'Box' })
        box:AddToggle(prefix .. 'Box', { Text = 'Box', Default = true }):AddColorPicker(prefix .. 'BoxColor', { Default = Color3.new(1, 1, 1) })
        box:AddToggle(prefix .. 'HealthBased', { Text = 'Health based', Default = false })
        box:AddToggle(prefix .. 'FillBox', { Text = 'Fill box', Default = false }):AddColorPicker(prefix .. 'FillColor', { Default = Color3.new(1, 1, 1) })
        box:AddDropdown(prefix .. 'BoxType', {
            Text = 'Box type',
            Values = { '2D', '3D', 'Corners' },
            Default = 'Corners'
        })
        box:AddDivider({ Text = 'Text' })
        box:AddToggle(prefix .. 'Name', { Text = 'Name', Default = true }):AddColorPicker(prefix .. 'NameColor', { Default = Color3.new(1, 1, 1) })
        if isPlayer then
            box:AddDropdown(prefix .. 'NameType', {
                Text = 'Name type',
                Values = { 'Name', 'Display name' },
                Default = 'Name'
            })
        end
        box:AddToggle(prefix .. 'Distance', { Text = 'Distance', Default = true }):AddColorPicker(prefix .. 'DistColor', { Default = Color3.fromRGB(170, 170, 170) })
        box:AddToggle(prefix .. 'HealthText', { Text = 'Health text', Default = false })
        box:AddDropdown(prefix .. 'HealthTextPos', {
            Text = 'Health text pos',
            Values = { 'Above name', 'Below box' },
            Default = 'Above name'
        })

        box:AddDivider({ Text = 'Health' })
        box:AddToggle(prefix .. 'HealthBar', { Text = 'Health bar', Default = true })

        if isPlayer then
            box:AddDivider({ Text = 'Indicators' })
            box:AddToggle(prefix .. 'EquipItem', { Text = 'Equipped item', Default = false })
            box:AddToggle(prefix .. 'Equipment', { Text = 'Equipment', Default = false })
            box:AddToggle(prefix .. 'ProfilePic', { Text = 'Profile picture', Default = false })
        end

        box:AddDivider({ Text = 'Chams' })
        box:AddToggle(prefix .. 'Chams', { Text = 'Chams', Default = false }):AddColorPicker(prefix .. 'ChamsColor', { Default = isPlayer and Color3.fromRGB(255, 70, 70) or Color3.fromRGB(125, 85, 255) })
        box:AddToggle(prefix .. 'ChamsFilled', { Text = 'Filled', Default = true })
        box:AddDropdown(prefix .. 'ChamsMode', {
            Text = 'Chams mode',
            Values = { 'Default', 'Fill only', 'Outline only' },
            Default = 'Default'
        })
        box:AddDropdown(prefix .. 'ChamsRender', {
            Text = 'Rendering type',
            Values = { 'Static', 'Health based' },
            Default = 'Static'
        })

        box:AddDivider({ Text = 'Tracer' })
        box:AddToggle(prefix .. 'Tracer', { Text = 'Tracer', Default = false }):AddColorPicker(prefix .. 'TracerColor', { Default = Color3.new(1, 1, 1) })
        box:AddDropdown(prefix .. 'TracerOrigin', {
            Text = 'Origin',
            Values = { 'Top', 'Center', 'Bottom' },
            Default = 'Top'
        })
        box:AddToggle(prefix .. 'Arrows', { Text = 'Arrows', Default = false }):AddColorPicker(prefix .. 'ArrowColor', { Default = Color3.new(1, 1, 1) })

        -- hide dependent controls until their master toggle is on
        local function setVis(id, v)
            local el = Toggles[id] or Options[id]
            if el and el.SetVisible then el:SetVisible(v) end
        end
        local function syncVis()
            local boxOn = Toggles[prefix .. 'Box'].Value
            local chamsOn = Toggles[prefix .. 'Chams'].Value
            setVis(prefix .. 'FillBox', boxOn)
            setVis(prefix .. 'BoxType', boxOn)
            setVis(prefix .. 'NameType', Toggles[prefix .. 'Name'].Value)
            setVis(prefix .. 'HealthTextPos', Toggles[prefix .. 'HealthText'].Value)
            setVis(prefix .. 'ChamsFilled', chamsOn)
            setVis(prefix .. 'ChamsMode', chamsOn)
            setVis(prefix .. 'ChamsRender', chamsOn)
            setVis(prefix .. 'TracerOrigin', Toggles[prefix .. 'Tracer'].Value)
        end
        for _, id in ipairs({ 'Box', 'Name', 'HealthText', 'Chams', 'Tracer' }) do
            Toggles[prefix .. id]:OnChanged(syncVis)
        end
        syncVis()
    end

    buildEspOptions(PlayerEspBox, 'PlayerEsp', true)
    buildEspOptions(MobEspBox, 'MobEsp', false)

    local espFolder = Instance.new('Folder')
    espFolder.Name = 'BluuEsp'
    espFolder.Parent = game:GetService('CoreGui')

    local espGui = Instance.new('ScreenGui')
    espGui.Name = 'BluuEspGui'
    espGui.ResetOnSpawn = false
    espGui.DisplayOrder = 50
    espGui.IgnoreGuiInset = true
    espGui.Parent = espFolder.Parent

    -- Probe instead of type-checking: some executors (Potassium) expose
    -- Drawing as a userdata library, not a table.
    local hasDrawing = pcall(function()
        local probe = Drawing.new('Square')
        probe:Remove()
        return true
    end)
    if not hasDrawing then
        Library:Notify('ESP needs the Drawing API - unsupported executor', 5)
    end

    local WHITE = Color3.new(1, 1, 1)
    local BLACK = Color3.new(0, 0, 0)
    local BOX_EDGES = {
        {1, 2}, {2, 4}, {4, 3}, {3, 1},
        {5, 6}, {6, 8}, {8, 7}, {7, 5},
        {1, 5}, {2, 6}, {3, 7}, {4, 8}
    }
    local CORNER_SIGNS = {
        {-1, -1, -1}, {1, -1, -1}, {-1, 1, -1}, {1, 1, -1},
        {-1, -1, 1}, {1, -1, 1}, {-1, 1, 1}, {1, 1, 1}
    }
    -- game's own palette (Theme module)
    local RARITY_COLORS = {
        Empty = Color3.fromRGB(127, 127, 127),
        Common = Color3.fromRGB(255, 255, 255),
        Uncommon = Color3.fromRGB(64, 255, 102),
        Rare = Color3.fromRGB(25, 182, 255),
        Legendary = Color3.fromRGB(240, 69, 255),
        Tribute = Color3.fromRGB(255, 208, 98),
        Burst = Color3.fromRGB(81, 0, 1)
    }
    local RARITY_BORDERS = {
        Empty = Color3.fromRGB(21, 21, 21),
        Common = Color3.fromRGB(125, 125, 125),
        Uncommon = Color3.fromRGB(127, 158, 14),
        Rare = Color3.fromRGB(0, 84, 211),
        Legendary = Color3.fromRGB(211, 160, 57),
        Tribute = Color3.fromRGB(231, 231, 231),
        Burst = Color3.fromRGB(255, 86, 1)
    }

    local kits = {}
    local itemNameCache = {}
    local frameDt = 0

    -- equip slots hold inventory instance ids; the matching IntValue's name in
    -- the player's Inventory is the item name
    local function itemNameInInventory(inv, id)
        if not inv or id == nil or id == 0 then return nil end
        local bucket = itemNameCache[inv]
        local cached = bucket and bucket[id]
        if cached ~= nil then return cached or nil end
        local found
        for _, v in ipairs(inv:GetChildren()) do
            local ok, val = pcall(function() return v.Value end)
            if ok and val == id then
                found = v.Name
                break
            end
        end
        bucket = bucket or {}
        itemNameCache[inv] = bucket
        bucket[id] = found or false
        return found
    end

    local DEFAULT_ICON = 'rbxassetid://142257783'

    local function itemByInventoryId(inv, id)
        if not inv or id == nil or id == 0 then return nil end
        for _, v in ipairs(inv:GetChildren()) do
            local ok, val = pcall(function() return v.Value end)
            if ok and val == id then return v end
        end
    end

    -- icon + rarity straight out of Database.Items[name]
    local function dbItemInfo(name)
        local db = Items:FindFirstChild(name)
        if not db then return DEFAULT_ICON, 'Common' end
        local icon = DEFAULT_ICON
        local ic = db:FindFirstChild('Icon')
        if ic then
            if ic:IsA('Decal') and ic.Texture ~= '' then
                icon = ic.Texture
            elseif ic:IsA('StringValue') and ic.Value ~= '' then
                icon = ic.Value
            end
        end
        local r = db:FindFirstChild('Rarity')
        return icon, r and r.Value or 'Common'
    end

    local EQUIP_ORDER = { 'Right', 'Left', 'Clothing', 'Accessory1', 'Accessory2', 'Accessory3', 'Accessory4', 'Companion' }
    local function getEquipSlots(plr)
        local prof = Profiles:FindFirstChild(plr.Name)
        local eq = prof and prof:FindFirstChild('Equip')
        local inv = prof and prof:FindFirstChild('Inventory')
        if not eq or not inv then return nil end
        local slots = {}
        local auraDone = false
        for _, slotName in ipairs(EQUIP_ORDER) do
            local sv = eq:FindFirstChild(slotName)
            if sv and sv.Value ~= 0 then
                local it = itemByInventoryId(inv, sv.Value)
                if it then
                    local icon, rarity = dbItemInfo(it.Name)
                    local up = it:FindFirstChild('Upgrade')
                    slots[#slots + 1] = { icon = icon, rarity = rarity, upgrade = up and up.Value or 0 }
                    -- aura = Skin attached to a weapon slot
                    if not auraDone and (slotName == 'Right' or slotName == 'Left') then
                        local sk = it:FindFirstChild('Skin')
                        local skDb = sk and Items:FindFirstChild(sk.Value)
                        if skDb then
                            auraDone = true
                            local sIcon, sRarity = dbItemInfo(skDb.Name)
                            if sIcon == DEFAULT_ICON then
                                local pe = skDb:FindFirstChildWhichIsA('ParticleEffect')
                                if pe and pe.Texture ~= '' then sIcon = pe.Texture end
                            end
                            slots[#slots + 1] = { icon = sIcon, rarity = sRarity, upgrade = 0 }
                        end
                    end
                end
            end
        end
        return #slots > 0 and slots or nil
    end

    -- clone the game's own ItemSlot template when the UI is loaded = pixel-perfect
    local slotTemplate = nil
    local function getSlotTemplate()
        if slotTemplate == nil then
            slotTemplate = 'none'
            local pg = LocalPlayer:FindFirstChildWhichIsA('PlayerGui') or LocalPlayer.PlayerGui
            if pg then
                for _, d in ipairs(pg:GetDescendants()) do
                    if d.Name == 'ItemSlot' and d.Parent and d.Parent.Name == 'Templates' then
                        slotTemplate = d
                        break
                    end
                end
            end
        end
        return slotTemplate ~= 'none' and slotTemplate or nil
    end

    -- ItemSlot.Set / SetRarity / SetUpgrade, on the real template
    local function fillGameSlot(slot, s)
        local v = slot:FindFirstChild('Frame') or slot
        local ii = v:FindFirstChild('ItemImage')
        if ii then ii.Image = s.icon end
        pcall(function()
            v.ImageColor3 = RARITY_COLORS[s.rarity] or RARITY_COLORS.Common
        end)
        local sh = v:FindFirstChild('InnerShadow')
        if sh then
            pcall(function()
                sh.ImageColor3 = RARITY_BORDERS[s.rarity] or RARITY_BORDERS.Common
            end)
        end
        for _, name in ipairs({ 'Count', 'Level', 'Skin', 'IconBackground', 'Favorited', 'Lock' }) do
            local c = v:FindFirstChild(name)
            if c then
                if name == 'Count' or name == 'Level' then
                    c.Text = ''
                elseif name == 'Skin' then
                    c.Image = ''
                else
                    c.Visible = false
                end
            end
        end
        local up = v:FindFirstChild('Upgrade')
        if up then
            up.Text = s.upgrade > 0 and ('+' .. s.upgrade) or ''
            local g = up:FindFirstChildWhichIsA('UIGradient')
            if g then
                local bc = RARITY_BORDERS[s.rarity] or RARITY_BORDERS.Common
                local mc = RARITY_COLORS[s.rarity] or RARITY_COLORS.Common
                g.Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, bc),
                    ColorSequenceKeypoint.new(0.35, mc),
                    ColorSequenceKeypoint.new(1, bc)
                })
            end
        end
    end

    local function makeFallbackSlot(s)
        local slot = Instance.new('ImageLabel')
        slot.Size = UDim2.fromOffset(SLOT_PX, SLOT_PX)
        slot.BackgroundTransparency = 1
        slot.Image = 'rbxassetid://3570695787'
        slot.ImageColor3 = RARITY_COLORS[s.rarity] or RARITY_COLORS.Common
        local stroke = Instance.new('UIStroke')
        stroke.Color = RARITY_BORDERS[s.rarity] or RARITY_BORDERS.Common
        stroke.Thickness = 1.5
        stroke.Parent = slot
        local img = Instance.new('ImageLabel')
        img.AnchorPoint = Vector2.new(0.5, 0.5)
        img.Position = UDim2.new(0.5, 0, 0.5, 0)
        img.Size = UDim2.new(1, -6, 1, -6)
        img.BackgroundTransparency = 1
        img.Image = s.icon
        img.Parent = slot
        if s.upgrade > 0 then
            local t = Instance.new('TextLabel')
            t.Size = UDim2.new(1, -2, 0, 10)
            t.Position = UDim2.new(0, 0, 1, -10)
            t.BackgroundTransparency = 1
            t.Text = '+' .. tostring(s.upgrade)
            t.TextSize = 8
            t.Font = Enum.Font.GothamBold
            t.TextColor3 = Color3.fromRGB(255, 220, 100)
            t.TextStrokeTransparency = 0.4
            t.TextXAlignment = Enum.TextXAlignment.Right
            t.ZIndex = 2
            t.Parent = slot
        end
        return slot
    end

    local SLOT_PX = 48
    local function updateEquipBar(kit, slots)
        local tpl = getSlotTemplate()
        local parts = {}
        for i, s in ipairs(slots) do
            parts[i] = s.icon .. ':' .. s.rarity .. ':' .. tostring(s.upgrade)
        end
        local sig = table.concat(parts, '|') .. (tpl and ':t' or ':f')
        if sig == kit.equipSig then return end
        kit.equipSig = sig
        if not kit.equipBar then
            local bar = Instance.new('Frame')
            bar.BackgroundTransparency = 1
            local lay = Instance.new('UIListLayout')
            lay.FillDirection = Enum.FillDirection.Horizontal
            lay.HorizontalAlignment = Enum.HorizontalAlignment.Center
            lay.VerticalAlignment = Enum.VerticalAlignment.Center
            lay.Padding = UDim.new(0, 3)
            lay.Parent = bar
            bar.Parent = espGui
            kit.equipBar = bar
        end
        for _, c in ipairs(kit.equipBar:GetChildren()) do
            if c:IsA('GuiObject') then c:Destroy() end
        end
        local w = #slots * SLOT_PX + (#slots - 1) * 3
        kit.equipBarW = w
        kit.equipBarH = SLOT_PX + 4
        kit.equipBar.Size = UDim2.fromOffset(w, SLOT_PX + 4)
        local tplBase = tpl and math.max(tpl.Size.Y.Offset, 1)
        for _, s in ipairs(slots) do
            local slot
            if tpl then
                slot = tpl:Clone()
                slot.Size = UDim2.fromOffset(SLOT_PX, SLOT_PX)
                local sc = Instance.new('UIScale')
                sc.Scale = SLOT_PX / tplBase
                sc.Parent = slot
                fillGameSlot(slot, s)
            else
                slot = makeFallbackSlot(s)
            end
            slot.Parent = kit.equipBar
        end
    end

    -- smooth red > orange > yellow > green sweep
    local function healthColor(pct)
        return Color3.fromHSV(math.clamp(pct, 0, 1) * 0.33, 0.95, 0.95)
    end

    local function newText(size)
        local t = Drawing.new('Text')
        t.Outline = true
        t.Center = true
        t.Size = size
        t.Font = Drawing.Fonts.Plex
        t.Color = WHITE
        t.Visible = false
        return t
    end

    local function newSquare(filled, color, thickness)
        local s = Drawing.new('Square')
        s.Filled = filled
        s.Thickness = thickness or 1
        s.Color = color or WHITE
        s.Visible = false
        return s
    end

    local function newLine(thickness)
        local l = Drawing.new('Line')
        l.Thickness = thickness or 1
        l.Color = WHITE
        l.Visible = false
        return l
    end

    local function makeKit()
        return {
            maxHp = 0,
            nameT = newText(14),
            distT = newText(13),
            hpT = newText(13),
            equipT = newText(12),
            hpBg = newSquare(true, BLACK),
            hpFill = newSquare(true),
            fillSq = newSquare(true, WHITE),
            boxOut = nil, boxIn = nil,
            cornersW = nil, cornersB = nil,
            edgesW = nil, edgesB = nil,
            tracer = nil,
            arrow = nil,
            equipBar = nil, equipSig = nil, equipBarW = 0,
            pfp = nil, pfpImg = nil, pfpFor = nil,
            hl = nil
        }
    end

    local KIT_OBJECTS = { 'nameT', 'distT', 'hpT', 'equipT', 'hpBg', 'hpFill', 'fillSq', 'boxOut', 'boxIn', 'tracer', 'arrow' }
    local KIT_TABLES = { 'cornersW', 'cornersB', 'edgesW', 'edgesB' }

    local function killDrawing(o)
        if o == nil then return end
        if not pcall(function() o:Remove() end) then
            pcall(function() o:Destroy() end)
        end
        pcall(function() o.Visible = false end)
    end

    local function destroyKit(key)
        local kit = kits[key]
        if not kit then return end
        kits[key] = nil
        for _, f in ipairs(KIT_OBJECTS) do
            killDrawing(kit[f])
        end
        for _, f in ipairs(KIT_TABLES) do
            if kit[f] then
                for _, o in ipairs(kit[f]) do
                    killDrawing(o)
                end
            end
        end
        if kit.hl then pcall(function() kit.hl:Destroy() end) end
        if kit.pfp then pcall(function() kit.pfp:Destroy() end) end
        if kit.equipBar then pcall(function() kit.equipBar:Destroy() end) end
    end

    local function hideBoxVisuals(kit)
        kit.nameT.Visible = false
        kit.distT.Visible = false
        kit.hpT.Visible = false
        kit.equipT.Visible = false
        kit.hpBg.Visible = false
        kit.hpFill.Visible = false
        kit.fillSq.Visible = false
        if kit.boxOut then
            kit.boxOut.Visible = false
            kit.boxIn.Visible = false
        end
        if kit.cornersW then
            for i = 1, 8 do
                kit.cornersW[i].Visible = false
                kit.cornersB[i].Visible = false
            end
        end
        if kit.edgesW then
            for i = 1, 12 do
                kit.edgesW[i].Visible = false
                kit.edgesB[i].Visible = false
            end
        end
        if kit.pfp then kit.pfp.Enabled = false end
        if kit.equipBar then kit.equipBar.Visible = false end
    end

    local function drawEsp(model, key, cfg, plr)
        local kit = kits[key]
        local rootPart = model and model:FindFirstChild('HumanoidRootPart')
        local entity = model and model:FindFirstChild('Entity')
        local health = entity and entity:FindFirstChild('Health')
        local hpValue = health and health.Value

        local ok = cfg.enabled and hasDrawing and model and model.Parent and rootPart
            and hpValue and hpValue > 0 and HumanoidRootPart
        if ok then
            local hum = model:FindFirstChildWhichIsA('Humanoid')
            if hum and hum.Health <= 0 then ok = false end
        end

        local distance = ok and (rootPart.Position - HumanoidRootPart.Position).Magnitude or 0
        if ok and distance > cfg.renderDist then ok = false end
        if ok and cfg.teamCheck and plr and plr.Team ~= nil and plr.Team == LocalPlayer.Team then ok = false end

        if not ok then
            if kit then destroyKit(key) end
            return
        end

        kit = kit or makeKit()
        kits[key] = kit

        kit.maxHp = math.max(kit.maxHp, hpValue)
        local pct = math.clamp(hpValue / kit.maxHp, 0, 1)
        -- ease the displayed fraction toward the real one so hits fade instead of snapping
        kit.smoothPct = kit.smoothPct and (kit.smoothPct + (pct - kit.smoothPct) * math.min(frameDt * 8, 1)) or pct
        local hpCol = healthColor(kit.smoothPct)

        -- screen-space position of the target
        local rv = Camera:WorldToViewportPoint(rootPart.Position)
        local vp = Camera.ViewportSize
        local center = Vector2.new(vp.X / 2, vp.Y / 2)
        local dir2 = Vector2.new(rv.X - center.X, rv.Y - center.Y)
        if rv.Z < 1 then dir2 = -dir2 end
        if dir2.Magnitude < 0.001 then dir2 = Vector2.new(0, 1) end

        local edgeMargin = 40
        local sx = math.abs(dir2.X) > 0.001 and ((vp.X / 2 - edgeMargin) / math.abs(dir2.X)) or math.huge
        local sy = math.abs(dir2.Y) > 0.001 and ((vp.Y / 2 - edgeMargin) / math.abs(dir2.Y)) or math.huge
        local edge = center + dir2 * math.min(sx, sy)

        local onScreen = rv.Z > 1 and rv.X >= -50 and rv.Y >= -50 and rv.X <= vp.X + 50 and rv.Y <= vp.Y + 50

        -- colors
        local boxColor = cfg.boxColor
        if cfg.teamColor and plr and plr.TeamColor then
            boxColor = plr.TeamColor.Color
        end
        local lineColor = cfg.healthBased and hpCol or boxColor

        kit.nameT.Outline = cfg.outline
        kit.distT.Outline = cfg.outline
        kit.hpT.Outline = cfg.outline
        kit.equipT.Outline = cfg.outline

        local minX, minY, maxX, maxY, centerX, w, h

        if onScreen then
            -- players get the full character bounds; mobs use the HRP hitbox only
            local cf, size
            if plr then
                -- union of real body parts only: GetBoundingBox() counts
                -- accessories/hidden parts and balloons on streamed models
                local minP = Vector3.one * math.huge
                local maxP = -minP
                local any
                for _, d in model:GetDescendants() do
                    if d:IsA('BasePart') and not d:FindFirstAncestorOfClass('Accessory')
                        and not d:FindFirstAncestorOfClass('Tool') then
                        local e = d.CFrame:VectorToWorldSpace(d.Size / 2)
                        e = Vector3.new(math.abs(e.X), math.abs(e.Y), math.abs(e.Z))
                        minP = minP:Min(d.Position - e)
                        maxP = maxP:Max(d.Position + e)
                        any = true
                    end
                end
                if any then
                    cf = CFrame.new((minP + maxP) / 2)
                    size = maxP - minP
                else
                    cf, size = rootPart.CFrame, rootPart.Size
                end
            else
                cf, size = rootPart.CFrame, rootPart.Size
            end
            local half = size / 2

            local pts = {}
            minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
            local allIn = true
            for i = 1, 8 do
                local s = CORNER_SIGNS[i]
                local v = Camera:WorldToViewportPoint(cf * Vector3.new(s[1] * half.X, s[2] * half.Y, s[3] * half.Z))
                if v.Z < 1 then allIn = false break end
                pts[i] = v
                if v.X < minX then minX = v.X end
                if v.Y < minY then minY = v.Y end
                if v.X > maxX then maxX = v.X end
                if v.Y > maxY then maxY = v.Y end
            end

            if allIn then
                w, h = maxX - minX, maxY - minY
                centerX = (minX + maxX) / 2

                -- fill
                kit.fillSq.Position = Vector2.new(minX, minY)
                kit.fillSq.Size = Vector2.new(w, h)
                kit.fillSq.Color = cfg.fillColor
                kit.fillSq.Transparency = 0.12
                kit.fillSq.Visible = cfg.fillBox and cfg.box

                -- box
                if cfg.box and cfg.boxType == '2D' then
                    if not kit.boxOut then
                        kit.boxOut = newSquare(false, BLACK, 3)
                        kit.boxIn = newSquare(false, WHITE, 1)
                    end
                    kit.boxIn.Color = lineColor
                    kit.boxIn.Position = Vector2.new(minX, minY)
                    kit.boxIn.Size = Vector2.new(w, h)
                    kit.boxIn.Visible = true
                    kit.boxOut.Position = Vector2.new(minX - 1, minY - 1)
                    kit.boxOut.Size = Vector2.new(w + 2, h + 2)
                    kit.boxOut.Visible = cfg.outline
                else
                    if kit.boxOut then
                        kit.boxOut.Visible = false
                        kit.boxIn.Visible = false
                    end
                end

                if cfg.box and cfg.boxType == 'Corners' then
                    if not kit.cornersW then
                        kit.cornersW = {}
                        kit.cornersB = {}
                        for i = 1, 8 do
                            kit.cornersB[i] = newLine(3)
                            kit.cornersB[i].Color = BLACK
                            kit.cornersW[i] = newLine(1)
                        end
                    end
                    local lx, ly = w / 4, h / 4
                    local segs = {
                        {minX, minY, lx, 0}, {minX, minY, 0, ly},
                        {maxX, minY, -lx, 0}, {maxX, minY, 0, ly},
                        {minX, maxY, lx, 0}, {minX, maxY, 0, -ly},
                        {maxX, maxY, -lx, 0}, {maxX, maxY, 0, -ly}
                    }
                    for i = 1, 8 do
                        local s = segs[i]
                        local from = Vector2.new(s[1], s[2])
                        local to = Vector2.new(s[1] + s[3], s[2] + s[4])
                        kit.cornersW[i].Color = lineColor
                        kit.cornersW[i].From = from
                        kit.cornersW[i].To = to
                        kit.cornersW[i].Visible = true
                        kit.cornersB[i].From = from
                        kit.cornersB[i].To = to
                        kit.cornersB[i].Visible = cfg.outline
                    end
                else
                    if kit.cornersW then
                        for i = 1, 8 do
                            kit.cornersW[i].Visible = false
                            kit.cornersB[i].Visible = false
                        end
                    end
                end

                if cfg.box and cfg.boxType == '3D' then
                    if not kit.edgesW then
                        kit.edgesW = {}
                        kit.edgesB = {}
                        for i = 1, 12 do
                            kit.edgesB[i] = newLine(3)
                            kit.edgesB[i].Color = BLACK
                            kit.edgesW[i] = newLine(1)
                        end
                    end
                    for i = 1, 12 do
                        local e = BOX_EDGES[i]
                        local a, b = pts[e[1]], pts[e[2]]
                        kit.edgesW[i].Color = lineColor
                        kit.edgesW[i].From = Vector2.new(a.X, a.Y)
                        kit.edgesW[i].To = Vector2.new(b.X, b.Y)
                        kit.edgesW[i].Visible = true
                        kit.edgesB[i].From = Vector2.new(a.X, a.Y)
                        kit.edgesB[i].To = Vector2.new(b.X, b.Y)
                        kit.edgesB[i].Visible = cfg.outline
                    end
                else
                    if kit.edgesW then
                        for i = 1, 12 do
                            kit.edgesW[i].Visible = false
                            kit.edgesB[i].Visible = false
                        end
                    end
                end

                -- equipment bar sits directly on the head; texts stack above it
                local equipBarH = 0
                if cfg.equipment and plr then
                    local now = tick()
                    if (kit.equipNextCheck or 0) <= now then
                        kit.equipNextCheck = now + 0.35
                        kit.equipSlots = getEquipSlots(plr)
                    end
                    if kit.equipSlots then
                        updateEquipBar(kit, kit.equipSlots)
                        equipBarH = kit.equipBarH or 28
                    end
                end

                -- health bar (left side) - always health-colored
                if cfg.healthBar then
                    kit.hpBg.Position = Vector2.new(minX - 6, minY)
                    kit.hpBg.Size = Vector2.new(4, h)
                    kit.hpBg.Visible = true
                    kit.hpFill.Color = hpCol
                    kit.hpFill.Position = Vector2.new(minX - 5, minY + h * (1 - kit.smoothPct))
                    kit.hpFill.Size = Vector2.new(2, h * kit.smoothPct)
                    kit.hpFill.Visible = true
                else
                    kit.hpBg.Visible = false
                    kit.hpFill.Visible = false
                end

                -- text stack above box
                local topY = minY - 15
                if cfg.showName then
                    local name = (cfg.nameType == 'Display name' and plr) and plr.DisplayName or cfg.name
                    kit.nameT.Text = name
                    kit.nameT.Color = cfg.nameColor
                    kit.nameT.Position = Vector2.new(centerX, topY)
                    kit.nameT.Visible = true
                    topY = topY - 15
                else
                    kit.nameT.Visible = false
                end

                -- equipment bar docks directly on top of the name row,
                -- scaled by box height so it stays proportionate at range
                local equipBarTopY, equipScale
                if equipBarH > 0 then
                    equipScale = math.clamp(h / 110, 0.5, 1)
                    equipBarTopY = topY + 6 - equipBarH * equipScale
                    topY = equipBarTopY - 4
                end

                if cfg.equipItem and plr then
                    local prof = Profiles:FindFirstChild(plr.Name)
                    local eq = prof and prof:FindFirstChild('Equip')
                    local rvv = eq and eq:FindFirstChild('Right')
                    local itemName = rvv and itemNameInInventory(prof and prof:FindFirstChild('Inventory'), rvv.Value)
                    if itemName then
                        kit.equipT.Text = itemName
                        kit.equipT.Color = Color3.fromRGB(255, 220, 120)
                        kit.equipT.Position = Vector2.new(centerX, topY)
                        kit.equipT.Visible = true
                        topY = topY - 14
                    else
                        kit.equipT.Visible = false
                    end
                else
                    kit.equipT.Visible = false
                end

                if cfg.hpText then
                    local hpY = (cfg.hpTextPos == 'Above name') and topY or (maxY + 3)
                    kit.hpT.Text = tostring(math.floor(hpValue + 0.5))
                    kit.hpT.Color = hpCol
                    kit.hpT.Position = Vector2.new(centerX, hpY)
                    kit.hpT.Visible = true
                else
                    kit.hpT.Visible = false
                end

                if cfg.distance then
                    local dY = (cfg.hpText and cfg.hpTextPos == 'Below box') and (maxY + 16) or (maxY + 3)
                    kit.distT.Text = `{math.floor(distance + 0.5)}m`
                    kit.distT.Color = cfg.distColor
                    kit.distT.Position = Vector2.new(centerX, dY)
                    kit.distT.Visible = true
                else
                    kit.distT.Visible = false
                end

                -- profile picture (players)
                if cfg.profilePic and plr then
                    if not kit.pfp then
                        local bill = Instance.new('BillboardGui')
                        bill.AlwaysOnTop = true
                        bill.Size = UDim2.new(2, 0, 2, 0)
                        bill.StudsOffsetWorldSpace = Vector3.new(0, half.Y + 2.5, 0)
                        local img = Instance.new('ImageLabel')
                        img.Size = UDim2.new(1, 0, 1, 0)
                        img.BackgroundTransparency = 1
                        img.Parent = bill
                        bill.Adornee = rootPart
                        bill.Parent = espFolder
                        kit.pfp = bill
                        kit.pfpFor = plr
                    end
                    kit.pfp.Enabled = true
                    if kit.pfpImg ~= plr.UserId then
                        kit.pfpImg = plr.UserId
                        task.spawn(function()
                            local thumb = Players:GetUserThumbnailAsync(plr.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
                            local img = kit.pfp and kit.pfp:FindFirstChildWhichIsA('ImageLabel')
                            if img then img.Image = thumb end
                        end)
                    end
                else
                    if kit.pfp then kit.pfp.Enabled = false end
                end

                -- equipment bar above the name
                if equipBarTopY and kit.equipBar then
                    local sc = kit.equipBar:FindFirstChildOfClass('UIScale')
                    if not sc then
                        sc = Instance.new('UIScale')
                        sc.Parent = kit.equipBar
                    end
                    sc.Scale = equipScale
                    kit.equipBar.Position = UDim2.fromOffset(centerX - kit.equipBarW * equipScale / 2, equipBarTopY)
                    kit.equipBar.Visible = true
                else
                    if kit.equipBar then kit.equipBar.Visible = false end
                end
            else
                hideBoxVisuals(kit)
            end
        else
            hideBoxVisuals(kit)
        end

        -- chams (work off-screen too, Highlight is engine-rendered)
        if cfg.chams then
            local col = (cfg.chamsRender == 'Health based') and hpCol or cfg.chamsColor
            if not kit.hl or kit.hl.Adornee ~= model then
                if kit.hl then kit.hl:Destroy() end
                local hl = Instance.new('Highlight')
                hl.Adornee = model
                hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                hl.Parent = espFolder
                kit.hl = hl
            end
            local hl = kit.hl
            hl.FillColor = col
            hl.OutlineColor = col
            hl.FillTransparency = (cfg.chamsMode == 'Outline only') and 1 or (cfg.chamsFilled and 0.65 or 1)
            hl.OutlineTransparency = (cfg.chamsMode == 'Fill only') and 1 or 0.2
        else
            if kit.hl then
                kit.hl:Destroy()
                kit.hl = nil
            end
        end

        -- tracer: works on AND off screen
        if cfg.tracer then
            if not kit.tracer then
                kit.tracer = newLine(1)
            end
            local oy = 0
            if cfg.tracerOrigin == 'Center' then oy = vp.Y / 2
            elseif cfg.tracerOrigin == 'Bottom' then oy = vp.Y end
            kit.tracer.From = Vector2.new(vp.X / 2, oy)
            kit.tracer.To = (onScreen and maxY) and Vector2.new(centerX, maxY) or edge
            kit.tracer.Color = cfg.healthBased and hpCol or cfg.tracerColor
            kit.tracer.Visible = true
        else
            if kit.tracer then kit.tracer.Visible = false end
        end

        -- off-screen arrow pointing at the target
        if cfg.arrows and not onScreen then
            if not kit.arrow then
                local tri = Drawing.new('Triangle')
                tri.Filled = true
                tri.Visible = false
                kit.arrow = tri
            end
            local dir = dir2.Unit
            local perp = Vector2.new(-dir.Y, dir.X)
            local tip = edge + dir * 8
            local baseC = edge - dir * 14
            kit.arrow.PointA = tip
            kit.arrow.PointB = baseC + perp * 7
            kit.arrow.PointC = baseC - perp * 7
            kit.arrow.Color = cfg.healthBased and hpCol or cfg.arrowColor
            kit.arrow.Visible = true
        else
            if kit.arrow then kit.arrow.Visible = false end
        end
    end

    local function readCfg(prefix)
        local T, O = Toggles, Options
        local rd = O[prefix .. 'RenderDist'].Value
        return {
            enabled = T[prefix].Value,
            teamCheck = T[prefix .. 'TeamCheck'] and T[prefix .. 'TeamCheck'].Value,
            selfEsp = T[prefix .. 'SelfEsp'] and T[prefix .. 'SelfEsp'].Value,
            teamColor = T[prefix .. 'TeamColor'] and T[prefix .. 'TeamColor'].Value,
            outline = T[prefix .. 'Outline'].Value,
            renderDist = (rd >= 10000) and math.huge or rd,
            box = T[prefix .. 'Box'].Value,
            boxColor = O[prefix .. 'BoxColor'].Value,
            fillBox = T[prefix .. 'FillBox'].Value,
            fillColor = O[prefix .. 'FillColor'].Value,
            boxType = O[prefix .. 'BoxType'].Value,
            showName = T[prefix .. 'Name'].Value,
            nameColor = O[prefix .. 'NameColor'].Value,
            nameType = O[prefix .. 'NameType'] and O[prefix .. 'NameType'].Value,
            distance = T[prefix .. 'Distance'].Value,
            distColor = O[prefix .. 'DistColor'].Value,
            hpText = T[prefix .. 'HealthText'].Value,
            hpTextPos = O[prefix .. 'HealthTextPos'].Value,
            healthBar = T[prefix .. 'HealthBar'].Value,
            healthBased = T[prefix .. 'HealthBased'].Value,
            equipItem = T[prefix .. 'EquipItem'] and T[prefix .. 'EquipItem'].Value,
            equipment = T[prefix .. 'Equipment'] and T[prefix .. 'Equipment'].Value,
            profilePic = T[prefix .. 'ProfilePic'] and T[prefix .. 'ProfilePic'].Value,
            chams = T[prefix .. 'Chams'].Value,
            chamsColor = O[prefix .. 'ChamsColor'].Value,
            chamsFilled = T[prefix .. 'ChamsFilled'].Value,
            chamsMode = O[prefix .. 'ChamsMode'].Value,
            chamsRender = O[prefix .. 'ChamsRender'].Value,
            tracer = T[prefix .. 'Tracer'].Value,
            tracerColor = O[prefix .. 'TracerColor'].Value,
            tracerOrigin = O[prefix .. 'TracerOrigin'].Value,
            arrows = T[prefix .. 'Arrows'].Value,
            arrowColor = O[prefix .. 'ArrowColor'].Value
        }
    end

    local espConn
    espConn = RenderStepped:Connect(function(dt)
        if getgenv().Bluu == false or Library.Unloaded then
            for key in pairs(kits) do
                destroyKit(key)
            end
            if espConn then
                espConn:Disconnect()
                espConn = nil
            end
            return
        end
        frameDt = dt or 0.016
        if not Toggles.PlayerEsp.Value and not Toggles.MobEsp.Value then
            for key in pairs(kits) do
                destroyKit(key)
            end
            return
        end

        local pCfg = readCfg('PlayerEsp')
        local mCfg = readCfg('MobEsp')

        for _, plr in ipairs(Players:GetPlayers()) do
            if plr == LocalPlayer then
                if pCfg.selfEsp then
                    pCfg.name = plr.Name
                    drawEsp(Character, LocalPlayer, pCfg, plr)
                end
            else
                pCfg.name = plr.Name
                drawEsp(plr.Character, plr, pCfg, plr)
            end
        end

        for _, mob in ipairs(Mobs:GetChildren()) do
            mCfg.name = mob.Name
            mCfg.enabled = Toggles.MobEsp.Value and not isDead(mob)
            drawEsp(mob, mob, mCfg, nil)
        end

        for key in pairs(kits) do
            -- mobs get reparented out of Mobs on death, so a non-nil Parent isn't enough
            if not key.Parent or (key:IsA('Model') and (key.Parent ~= Mobs or isDead(key))) then
                destroyKit(key)
            end
        end
    end)

    if BluuCleanups then
        table.insert(BluuCleanups, function()
            if espConn then
                pcall(function() espConn:Disconnect() end)
                espConn = nil
            end
            for key in pairs(kits) do
                pcall(destroyKit, key)
            end
            pcall(function() if espFolder then espFolder:Destroy() end end)
            pcall(function() if espGui then espGui:Destroy() end end)
        end)
    end
end
