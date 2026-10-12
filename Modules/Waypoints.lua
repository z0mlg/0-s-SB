-- Bluu :: Waypoints  (split from Sb2-0mlg.lua)


-- Waypoint data storage
WaypointSystem = {
    waypoints = {},
    currentPath = {},
    isRunning = false,
    currentWaypointIndex = 1,
    waitTime = 7,
    visualMarkers = {},
    waypointToggles = {},
    waypointPriorities = {}
}

-- Per-floor (PlaceId-keyed) persistence for the autofarm waypoint + path farming state.
-- Lets the waypoint snap back to exactly where it was when you rejoin/reload a config.
local FLOOR_WP_FILE = 'Bluu/Swordburst 2/FloorWaypoints.json'
waypointRestoring = false

local function loadFloorStore()
    if not (readfile and isfile) then return {} end
    if not isfile(FLOOR_WP_FILE) then return {} end
    local ok, data = pcall(function()
        return game:GetService('HttpService'):JSONDecode(readfile(FLOOR_WP_FILE))
    end)
    if ok and type(data) == 'table' then return data end
    return {}
end

local function saveFloorStore(store)
    if not writefile then return end
    if isfolder and makefolder and not isfolder('Bluu/Swordburst 2') then
        makefolder('Bluu/Swordburst 2')
    end
    pcall(function()
        writefile(FLOOR_WP_FILE, game:GetService('HttpService'):JSONEncode(store))
    end)
end

-- Merge-update the entry for the current floor (skipped while we're restoring).
function saveFloorData(updates)
    if waypointRestoring then return end
    local store = loadFloorStore()
    local key = tostring(game.PlaceId)
    local entry = store[key] or {}
    for k, v in pairs(updates) do
        entry[k] = v
    end
    store[key] = entry
    saveFloorStore(store)
end

function getFloorData()
    return loadFloorStore()[tostring(game.PlaceId)]
end

-- Create visual marker for waypoint
local createWaypointMarker = function(position, name, index)
    local marker = Instance.new('Part')
    marker.Anchored = true
    marker.CanCollide = false
    marker.Size = Vector3.new(4, 8, 4)
    marker.Transparency = 0.5
    marker.Color = Color3.fromRGB(0, 255, 255)
    marker.Material = Enum.Material.Neon
    marker.Position = position
    marker.Parent = workspace
    
    local billboard = Instance.new('BillboardGui')
    billboard.Size = UDim2.new(0, 200, 0, 50)
    billboard.AlwaysOnTop = true
    billboard.Parent = marker
    
    local label = Instance.new('TextLabel')
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(1, 0, 1, 0)
    label.Font = Enum.Font.GothamBold
    label.TextSize = 18
    label.TextColor3 = Color3.new(1, 1, 1)
    label.TextStrokeTransparency = 0
    label.Text = name
    label.Parent = billboard
    
    return marker
end

-- Update all waypoint markers
local updateWaypointMarkers = function()
    for _, marker in pairs(WaypointSystem.visualMarkers) do
        if marker and marker.Parent then
            marker:Destroy()
        end
    end
    WaypointSystem.visualMarkers = {}
    
    if Toggles.ShowWaypointMarkers and Toggles.ShowWaypointMarkers.Value then
        for i, wp in ipairs(WaypointSystem.waypoints) do
            local marker = createWaypointMarker(wp.position, wp.name, i)
            table.insert(WaypointSystem.visualMarkers, marker)
        end
    end
end

-- Save waypoint configuration
local saveWaypointConfig = function(configName)
    if not writefile then
        Library:Notify('✗ Executor does not support file writing', 3)
        return
    end
    
    local config = {
        placeId = game.PlaceId,
        waypoints = {},
        waitTime = WaypointSystem.waitTime,
        waypointToggles = WaypointSystem.waypointToggles,
        waypointPriorities = WaypointSystem.waypointPriorities
    }
    
    for _, wp in ipairs(WaypointSystem.waypoints) do
        table.insert(config.waypoints, {
            name = wp.name,
            position = {wp.position.X, wp.position.Y, wp.position.Z}
        })
    end
    
    local HttpService = game:GetService('HttpService')
    local jsonData = HttpService:JSONEncode(config)
    
    if not isfolder('Bluu/Swordburst 2/Waypoints') then
        makefolder('Bluu/Swordburst 2/Waypoints')
    end
    
    writefile(`Bluu/Swordburst 2/Waypoints/{configName}.json`, jsonData)
    Library:Notify(`✓ Waypoint config '{configName}' saved!`, 3)
end

-- forward declarations: waypoint manager state (assigned further below)
local waypointGroupedByName = {}
local waypointGroupControls = {}
local nextWaypointGroupId = 0
local updateWaypointToggles = nil
local createWaypointToggles = nil

-- Load waypoint configuration
local loadWaypointConfig = function(configName, silent)
    if not readfile or not isfile then
        if not silent then
            Library:Notify('✗ Executor does not support file reading', 3)
        end
        return
    end
    
    local filePath = `Bluu/Swordburst 2/Waypoints/{configName}.json`
    if not isfile(filePath) then
        if not silent then
            Library:Notify(`✗ Config '{configName}' not found`, 3)
        end
        return
    end
    
    local HttpService = game:GetService('HttpService')
    local jsonData = readfile(filePath)
    local config = HttpService:JSONDecode(jsonData)
    
    if config.placeId and config.placeId ~= game.PlaceId then
        if not silent then
            Library:Notify(`✗ Config is for a different floor (PlaceId: {config.placeId})`, 3)
        end
        return
    end
    
    WaypointSystem.waypoints = {}
    for _, wp in ipairs(config.waypoints) do
        table.insert(WaypointSystem.waypoints, {
            name = wp.name,
            position = Vector3.new(wp.position[1], wp.position[2], wp.position[3])
        })
    end
    
    WaypointSystem.waitTime = 7
    WaypointSystem.waypointToggles = config.waypointToggles or {}
    WaypointSystem.waypointPriorities = config.waypointPriorities or {}
    
    updateWaypointMarkers()
    if not silent then
        Library:Notify(`✓ Loaded {#WaypointSystem.waypoints} waypoints from '{configName}'`, 3)
    end
    
    task.spawn(function()
        task.wait(0.5)
        if createWaypointToggles then
            createWaypointToggles()
        end
    end)
end

-- Get list of saved configs
local getSavedConfigs = function()
    if not listfiles or not isfolder then return {} end
    
    if not isfolder('Bluu/Swordburst 2/Waypoints') then
        return {}
    end
    
    local files = listfiles('Bluu/Swordburst 2/Waypoints')
    local configs = {}
    
    for _, file in ipairs(files) do
        local name = file:match('([^/\\]+)%.json$')
        if name then
            table.insert(configs, name)
        end
    end
    
    return configs
end

-- Decides when it's safe to advance to the next waypoint.
-- Normal mode: original behavior -- check only after a 7s warmup, advance when
-- no living mobs remain near the anchor. Tag mode: scan every cycle and advance
-- the instant every nearby mob is tagged (empty spots still wait the 7s so we
-- don't teleport-spam past mobs that haven't spawned/registered yet).
local pathFarmClear = function(anchorPos, elapsed)
    local tagMode = Toggles.TagMode and Toggles.TagMode.Value
    if not tagMode and elapsed < 7 then return false end

    local farmRadius = Options.AutofarmRadius.Value
    farmRadius = (farmRadius == Options.AutofarmRadius.Max) and math.huge or farmRadius

    local sawNearby = false
    for _, mob in next, Mobs:GetChildren() do
        if Options.IgnoreMobs.Value[mob.Name] then continue end
        if isDead(mob) then continue end
        local rootPart = mob:FindFirstChild('HumanoidRootPart')
        if not rootPart then continue end
        if (rootPart.Position - anchorPos).Magnitude > farmRadius then continue end
        sawNearby = true
        if tagMode and isTagged(mob) then continue end
        return false -- an unfinished mob is nearby
    end

    if tagMode and sawNearby then return true end -- everything nearby is tagged
    return elapsed >= 7 -- empty spot (either mode): keep the 7s spawn safety
end

local PathFarming = WaypointsTab:AddLeftGroupbox('Path farming')

PathFarming:AddToggle('EnablePathFarming', {
    Text = 'Enable path farming',
    Default = false
}):OnChanged(function(value)
    WaypointSystem.isRunning = value
    saveFloorData({ pathFarming = value })
    
    if not value then
        pathFarmingWaypoint = nil
        return
    end
    
    if #WaypointSystem.waypoints == 0 then
        Library:Notify('✗ No waypoints configured!', 3)
        Toggles.EnablePathFarming:SetValue(false)
        return
    end
    
    if not Toggles.Autofarm.Value then
        Library:Notify('Path farming will run once Autofarm is enabled', 3)
    end
    
    WaypointSystem.currentWaypointIndex = 1
    
    task.spawn(function()
        while WaypointSystem.isRunning and Toggles.EnablePathFarming.Value do
            task.wait(1)
            
            if not Toggles.Autofarm.Value then continue end
            
            if Humanoid.Health == 0 then
                task.wait(2)
                continue
            end
            
            local currentWaypoint = WaypointSystem.waypoints[WaypointSystem.currentWaypointIndex]
            if not currentWaypoint then
                WaypointSystem.currentWaypointIndex = 1
                continue
            end
            
            if WaypointSystem.waypointToggles[WaypointSystem.currentWaypointIndex] == false then
                WaypointSystem.currentWaypointIndex = WaypointSystem.currentWaypointIndex + 1
                if WaypointSystem.currentWaypointIndex > #WaypointSystem.waypoints then
                    WaypointSystem.currentWaypointIndex = 1
                end
                continue
            end
            
            local waypointPos = currentWaypoint.position
            if not lowHealthEscaping then
                HumanoidRootPart.CFrame = CFrame.new(waypointPos)
            end

            local startTime = tick()

            while WaypointSystem.isRunning and Toggles.EnablePathFarming.Value and Toggles.Autofarm.Value do
                task.wait(0.5)

                if Humanoid.Health == 0 then break end
                if lowHealthEscaping then continue end -- don't advance while hovering
                if pathFarmClear(waypointPos, tick() - startTime) then break end
            end
            
            for i, wp in ipairs(WaypointSystem.waypoints) do
                if WaypointSystem.waypointToggles[i] == false then continue end
                
                local priority = WaypointSystem.waypointPriorities[i] or 100
                if priority < 100 then
                    local distanceToWaypoint = (HumanoidRootPart.Position - wp.position).Magnitude
                    if distanceToWaypoint > 50 and not lowHealthEscaping then
                        HumanoidRootPart.CFrame = CFrame.new(wp.position)
                    end
                    
                    local priorityStartTime = tick()

                    while WaypointSystem.isRunning and Toggles.EnablePathFarming.Value and Toggles.Autofarm.Value do
                        task.wait(0.5)

                        if Humanoid.Health == 0 then break end
                        if lowHealthEscaping then continue end
                        if pathFarmClear(wp.position, tick() - priorityStartTime) then break end
                    end
                end
            end
            
            WaypointSystem.currentWaypointIndex = WaypointSystem.currentWaypointIndex + 1
            if WaypointSystem.currentWaypointIndex > #WaypointSystem.waypoints then
                WaypointSystem.currentWaypointIndex = 1
            end
        end
    end)
end)

PathFarming:AddButton({
    Text = 'View current progress',
    Func = function()
        if WaypointSystem.isRunning and #WaypointSystem.waypoints > 0 then
            local wp = WaypointSystem.waypoints[WaypointSystem.currentWaypointIndex]
            if wp then
                Library:Notify(`Current: {WaypointSystem.currentWaypointIndex}/{#WaypointSystem.waypoints} - {wp.name}`, 3)
            end
        else
            Library:Notify('Path farming not active', 2)
        end
    end
})

local ConfigManagement = WaypointsTab:AddLeftGroupbox('Configuration')

ConfigManagement:AddInput('ConfigName', {
    Text = 'Config name',
    Default = 'MyPath',
    Finished = false,
    Placeholder = 'Enter config name...'
})

ConfigManagement:AddButton({
    Text = 'Save',
    Func = function()
        local configName = Options.ConfigName.Value
        if configName == '' then
            Library:Notify('✗ Config name cannot be empty', 2)
            return
        end
        saveWaypointConfig(configName)
        local configs = getSavedConfigs()
        Options.LoadConfigDropdown:SetValues(configs)
    end
})

local loadConfigDropdown = ConfigManagement:AddDropdown('LoadConfigDropdown', {
    Text = 'Select config',
    Values = getSavedConfigs(),
    AllowNull = true
})

local loadConfigMenuOpen = loadConfigDropdown.Menu.Open
loadConfigDropdown.Menu.Open = function(self, ...)
    Options.LoadConfigDropdown:SetValues(getSavedConfigs())
    return loadConfigMenuOpen(self, ...)
end

ConfigManagement:AddButton({
    Text = 'Load',
    Func = function()
        local configName = Options.LoadConfigDropdown.Value
        if not configName then
            Library:Notify('✗ No config selected', 2)
            return
        end
        loadWaypointConfig(configName)
    end
})

ConfigManagement:AddButton({
    Text = 'Overwrite',
    Func = function()
        local configName = Options.LoadConfigDropdown.Value
        if not configName then
            Library:Notify('✗ No config selected', 2)
            return
        end
        
        if #WaypointSystem.waypoints == 0 then
            Library:Notify('✗ No waypoints to save', 2)
            return
        end
        
        saveWaypointConfig(configName)
        Library:Notify(`✓ Overwritten '{configName}' with current waypoints`, 3)
    end
})

ConfigManagement:AddButton({
    Text = 'Set auto load',
    Func = function()
        local configName = Options.LoadConfigDropdown.Value
        if not configName then
            Library:Notify('✗ No config selected', 2)
            return
        end
        
        local filePath = `Bluu/Swordburst 2/Waypoints/{configName}.json`
        if not isfile(filePath) then
            Library:Notify(`✗ Config '{configName}' not found!`, 3)
            return
        end
        
        if not isfolder('Bluu/Swordburst 2') then
            makefolder('Bluu/Swordburst 2')
        end
        
        writefile('Bluu/Swordburst 2/AutoLoadConfig.txt', configName)
        Library:Notify(`✓ '{configName}' will auto-load for PlaceId {game.PlaceId}`, 3)
    end
})

ConfigManagement:AddLabel(`Current PlaceId: {game.PlaceId}`)

local WaypointToggles = nil

updateWaypointToggles = function()
    waypointGroupedByName = {}

    for i, wp in ipairs(WaypointSystem.waypoints) do
        if not waypointGroupedByName[wp.name] then
            waypointGroupedByName[wp.name] = {}
        end
        table.insert(waypointGroupedByName[wp.name], i)

        if WaypointSystem.waypointToggles[i] == nil then
            WaypointSystem.waypointToggles[i] = true
        end
        if WaypointSystem.waypointPriorities[i] == nil then
            WaypointSystem.waypointPriorities[i] = 100
        end
    end

    -- resync each live group's controls (toggle ids are gid-based, so match by current name)
    for _, ctrl in ipairs(waypointGroupControls) do
        local indices = waypointGroupedByName[ctrl.state.name]
        if indices then
            ctrl.groupToggle:SetValue(WaypointSystem.waypointToggles[indices[1]] == true)
            ctrl.prioritySlider:SetValue(math.min(WaypointSystem.waypointPriorities[indices[1]] or 100, 100))
        end
    end
end

task.spawn(function()
    if not readfile or not isfile then return end
    
    local autoLoadFile = 'Bluu/Swordburst 2/AutoLoadConfig.txt'
    if not isfile(autoLoadFile) then return end
    
    local configName = readfile(autoLoadFile)
    if configName and configName ~= '' then
        task.wait(1)
        loadWaypointConfig(configName, true)
        if #WaypointSystem.waypoints > 0 then
            Library:Notify(`✓ Auto-loaded '{configName}' ({#WaypointSystem.waypoints} waypoints)`, 3)
        end
    end
end)

WaypointToggles = WaypointsTab:AddRightGroupbox('Waypoint Manager')

createWaypointToggles = function()
    updateWaypointToggles()

    local orderedNames = {}
    for wpName, _ in pairs(waypointGroupedByName) do
        table.insert(orderedNames, wpName)
    end
    table.sort(orderedNames, function(a, b)
        return waypointGroupedByName[a][1] < waypointGroupedByName[b][1]
    end)

    local activeNames = {}
    for _, wpName in ipairs(orderedNames) do
        activeNames[wpName] = true
    end

    -- hide rows whose group no longer exists (config reload/delete), index live rows
    local liveRows = {}
    for _, ctrl in ipairs(waypointGroupControls) do
        local alive = activeNames[ctrl.state.name] == true
        ctrl.inputHolder.Visible = alive
        if ctrl.sliderHolder then
            ctrl.sliderHolder.Visible = alive
        end
        if alive then
            liveRows[ctrl.state.name] = ctrl
        end
    end

    for _, wpName in ipairs(orderedNames) do
        local indices = waypointGroupedByName[wpName]
        local firstIndex = indices[1]
        local isEnabled = WaypointSystem.waypointToggles[firstIndex] == true
        local priority = WaypointSystem.waypointPriorities[firstIndex] or 100

        local existing = liveRows[wpName]
        if existing then
            -- row already exists for this name (rename/re-add) -> resync it
            existing.nameInput:SetValue(wpName)
            existing.groupToggle:SetValue(isEnabled)
            existing.prioritySlider:SetValue(math.min(priority, 100))
        else
            nextWaypointGroupId += 1
            local gid = nextWaypointGroupId
            local groupState = { name = wpName }

            local groupToggle = WaypointToggles:AddToggle(`WaypointToggle_{gid}`, {
                Text = '',
                Default = isEnabled
            })
            groupToggle:OnChanged(function(value)
                for i, wp in ipairs(WaypointSystem.waypoints) do
                    if wp.name == groupState.name then
                        WaypointSystem.waypointToggles[i] = value
                    end
                end
            end)

            -- name textbox + toggle share one row: shrink the toggle's holder to
            -- just the switch and dock it inside the input row
            local nameInput = WaypointToggles:AddInput(`WaypointName_{gid}`, {
                Text = '',
                Default = wpName,
                Finished = true,
                ClearTextOnFocus = false,
                ClearTextOnBlur = false,
                Placeholder = 'Waypoint name'
            })

            local inputHolder = nameInput.Holder
            local inputLabel = inputHolder:FindFirstChildWhichIsA('TextLabel')
            if inputLabel then inputLabel.Visible = false end
            local nameBox = inputHolder:FindFirstChildWhichIsA('TextBox')
            inputHolder.Size = UDim2.new(1, 0, 0, 22)
            if nameBox then
                nameBox.Size = UDim2.new(1, -70, 0, 21)
            end

            local deleteButton = Instance.new('TextButton')
            deleteButton.BackgroundTransparency = 1
            deleteButton.AnchorPoint = Vector2.new(1, 1)
            deleteButton.Position = UDim2.new(1, -38, 1, -1)
            deleteButton.Size = UDim2.new(0, 22, 0, 21)
            deleteButton.Text = ''
            deleteButton.Parent = inputHolder

            local deleteIcon = Instance.new('ImageLabel')
            deleteIcon.BackgroundTransparency = 1
            deleteIcon.AnchorPoint = Vector2.new(0.5, 0.5)
            deleteIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
            deleteIcon.Size = UDim2.new(0, 14, 0, 14)
            deleteIcon.ScaleType = Enum.ScaleType.Fit
            deleteIcon.ImageColor3 = Library.Scheme.FontColor
            deleteIcon.ImageTransparency = 0.3
            local trashIcon = Library.GetIcon and Library:GetIcon('trash')
            if trashIcon then
                deleteIcon.Image = trashIcon.Url
                deleteIcon.ImageRectOffset = trashIcon.ImageRectOffset
                deleteIcon.ImageRectSize = trashIcon.ImageRectSize
            else
                deleteIcon.Image = 'rbxassetid://92538770778833'
            end
            deleteIcon.Parent = deleteButton

            local toggleHolder = groupToggle.Holder
            toggleHolder.AnchorPoint = Vector2.new(1, 1)
            toggleHolder.Position = UDim2.new(1, 0, 1, -1)
            toggleHolder.Size = UDim2.new(0, 34, 0, 21)
            toggleHolder.Parent = inputHolder

            deleteButton.Activated:Connect(function()
                for i = #WaypointSystem.waypoints, 1, -1 do
                    if WaypointSystem.waypoints[i].name == groupState.name then
                        table.remove(WaypointSystem.waypoints, i)
                        table.remove(WaypointSystem.waypointToggles, i)
                        table.remove(WaypointSystem.waypointPriorities, i)
                    end
                end
                inputHolder.Visible = false
                local prioritySlider = Options[`WaypointPriority_{gid}`]
                if prioritySlider and prioritySlider.Holder then
                    prioritySlider.Holder.Visible = false
                end
                updateWaypointToggles()
                updateWaypointMarkers()
                if WaypointToggles.Resize then
                    WaypointToggles:Resize()
                end
                Library:Notify(`✓ Deleted '{groupState.name}'`, 2)
            end)

            nameInput:OnChanged(function(newName)
                newName = (newName or ''):gsub('^%s*(.-)%s*$', '%1')
                if newName == '' or newName == groupState.name then
                    -- revert without re-firing this callback (SetValue would recurse)
                    nameInput.Value = groupState.name
                    if nameBox then
                        nameBox.Text = groupState.name
                    end
                    return
                end
                for _, wp in ipairs(WaypointSystem.waypoints) do
                    if wp.name == groupState.name then
                        wp.name = newName
                    end
                end
                groupState.name = newName
                updateWaypointToggles()
                updateWaypointMarkers()
            end)

            local prioritySlider = WaypointToggles:AddSlider(`WaypointPriority_{gid}`, {
                Text = `  Priority`,
                Default = math.min(priority, 100),
                Min = 1,
                Max = 100,
                Rounding = 0,
                Compact = true,
                FormatDisplayValue = function(_, value)
                    if value >= 100 then
                        return '  Default'
                    end
                    return `  Priority: {value}`
                end
            })
            prioritySlider:OnChanged(function(value)
                for i, wp in ipairs(WaypointSystem.waypoints) do
                    if wp.name == groupState.name then
                        WaypointSystem.waypointPriorities[i] = value
                    end
                end
            end)

            table.insert(waypointGroupControls, {
                state = groupState,
                inputHolder = inputHolder,
                sliderHolder = prioritySlider.Holder,
                groupToggle = groupToggle,
                nameInput = nameInput,
                prioritySlider = prioritySlider
            })
        end
    end

    if WaypointToggles.Resize then
        WaypointToggles:Resize()
    end

    Library:Notify(`✓ Loaded {#WaypointSystem.waypoints} waypoint(s)`, 2)
end

task.spawn(function()
    task.wait(2)
    if #WaypointSystem.waypoints > 0 then
        createWaypointToggles()
    end
end)

WaypointToggles:AddButton({
    Text = 'Add',
    Func = function()
        local newWaypoint = {
            name = tostring(#WaypointSystem.waypoints + 1),
            position = HumanoidRootPart.Position
        }
        table.insert(WaypointSystem.waypoints, newWaypoint)
        WaypointSystem.waypointToggles[#WaypointSystem.waypoints] = true
        WaypointSystem.waypointPriorities[#WaypointSystem.waypoints] = 100
        updateWaypointMarkers()
        createWaypointToggles()
        Library:Notify(`✓ Added waypoint at current position`, 2)
    end
})

WaypointToggles:AddToggle('ShowWaypointMarkers', {
    Text = 'Show waypoint markers',
    Default = true
}):OnChanged(function()
    updateWaypointMarkers()
end)

WaypointToggles:AddButton({
    Text = 'Clear all',
    Func = function()
        WaypointSystem.waypoints = {}
        WaypointSystem.waypointToggles = {}
        WaypointSystem.waypointPriorities = {}
        updateWaypointMarkers()
        createWaypointToggles()
        Library:Notify('✓ All waypoints cleared', 2)
    end
})

WaypointToggles:AddDivider()

