-- Bluu :: Settings  (split from Sb2-0mlg.lua)

Settings = Window:AddTab('Settings', 'settings')

Menu = Settings:AddLeftGroupbox('Menu', 'menu')

Menu:AddLabel('Menu keybind'):AddKeyPicker('MenuKeybind', { Default = 'End', NoUI = true })

Library.ToggleKeybind = Options.MenuKeybind

autoexecute = true
if isfile('Bluu/Swordburst 2/autoexec') and readfile('Bluu/Swordburst 2/autoexec') == 'false' then
    autoexecute = false
end

Menu:AddToggle('Autoexecute', { Text = 'Auto execute', Default = autoexecute }):OnChanged(function(value)
    writefile('Bluu/Swordburst 2/autoexec', tostring(value))
end)

Menu:AddButton("Unload script", function()
    for _, toggle in next, Toggles do
        if toggle.Value then
            toggle:SetValue(false)
        end
    end

    pcall(function()
        linearVelocity.Parent = nil
        waypoint:Destroy()
        if radiusDisc then radiusDisc:Destroy() end
        local espFolder = game:GetService('CoreGui'):FindFirstChild('BluuEsp')
        if espFolder then espFolder:Destroy() end
        local espGuiOld = game:GetService('CoreGui'):FindFirstChild('BluuEspGui')
        if espGuiOld then espGuiOld:Destroy() end
        Humanoid.WalkSpeed = 20
        Camera.CameraSubject = Character
        LocalPlayer.CameraMaxZoomDistance = defaultCameraMaxZoomDistance
        LocalPlayer.DevCameraOcclusionMode = 0
        Chat.Size = chatSize
        Library:Unload()
    end)

    getgenv().Bluu = false
end)

ThemeManager = loadstring(game:HttpGet(UIRepo .. 'addons/ThemeManager.lua'))()
ThemeManager:SetLibrary(Library)
ThemeManager:SetFolder('Bluu/Swordburst 2')
ThemeManager:ApplyToTab(Settings)

SaveManager = loadstring(game:HttpGet(UIRepo .. 'addons/SaveManager.lua'))()
SaveManager:SetLibrary(Library)
SaveManager:SetFolder('Bluu/Swordburst 2')
SaveManager:IgnoreThemeSettings()

-- Per-account autoload: one JSON map (autoloads.json) holds every account's
-- pick, e.g. {"Swordburst2lover1":"test1","0mlgg":"test2"}. The config pool
-- stays shared, but autoload NEVER falls back to a shared marker - an account
-- with no entry loads nothing. (autoload_<UserId>.txt is kept as a backup
-- marker; a stale shared autoload.txt is deleted once, below.)
if writefile and readfile then
    local HttpService = game:GetService('HttpService')
    local AUTOLOADS_FILE = 'Bluu/Swordburst 2/autoloads.json'

    local function loadAutoloadMap()
        local ok, raw = pcall(readfile, AUTOLOADS_FILE)
        if not ok or type(raw) ~= 'string' or raw == '' then return {} end
        local ok2, map = pcall(HttpService.JSONDecode, HttpService, raw)
        return (ok2 and type(map) == 'table') and map or {}
    end

    local function saveAutoloadMap(map)
        writefile(AUTOLOADS_FILE, HttpService:JSONEncode(map))
    end

    local function readMarkerFile(path)
        local ok, name = pcall(readfile, path)
        if not ok then return 'none' end
        name = tostring(name)
        return name == '' and 'none' or name
    end

    local function settingsBase()
        local base = SaveManager.Folder .. '/settings/'
        if SaveManager:CheckSubFolder(true) then
            base ..= SaveManager.SubFolder .. '/'
        end
        return base
    end

    local function legacyAutoloadName()
        -- per-UserId marker only - never the shared autoload.txt
        return readMarkerFile(settingsBase() .. 'autoload_' .. LocalPlayer.UserId .. '.txt')
    end

    -- resolution order: this account's map entry -> this account's uid marker
    local function autoloadName()
        local mine = loadAutoloadMap()[LocalPlayer.Name]
        if type(mine) == 'string' and mine ~= '' then return mine end
        return legacyAutoloadName()
    end

    function SaveManager:GetAutoloadConfig()
        SaveManager:CheckFolderTree()
        return autoloadName()
    end

    function SaveManager:LoadAutoloadConfig()
        SaveManager:CheckFolderTree()
        local name = autoloadName()
        if name == 'none' then return end
        local success, err = self:Load(name)
        if not success then
            Library:Notify('Failed to load autoload config: ' .. err)
            return
        end
        Library:Notify(string.format('Auto loaded config %q for %s', name, LocalPlayer.Name))
    end

    function SaveManager:SaveAutoloadConfig(name)
        SaveManager:CheckFolderTree()
        local map = loadAutoloadMap()
        map[LocalPlayer.Name] = name
        if not pcall(saveAutoloadMap, map) then
            return false, 'write file error'
        end
        -- backup per-account uid marker: if the json map is ever lost this
        -- account still resolves its own config instead of nothing
        pcall(writefile, settingsBase() .. 'autoload_' .. LocalPlayer.UserId .. '.txt', name)
        return true, ''
    end

    function SaveManager:DeleteAutoLoadConfig()
        SaveManager:CheckFolderTree()
        local map = loadAutoloadMap()
        map[LocalPlayer.Name] = nil
        if not pcall(saveAutoloadMap, map) then
            return false, 'delete file error'
        end
        -- drop this account's uid marker too so it really has no autoload
        if delfile then
            pcall(delfile, settingsBase() .. 'autoload_' .. LocalPlayer.UserId .. '.txt')
        end
        return true, ''
    end

    -- one-time cleanup: the old shared marker poisons every account without a
    -- map entry - it must never be read again
    if delfile then
        pcall(delfile, settingsBase() .. 'autoload.txt')
    end

    Menu:AddDivider({ Text = `Autoload is per-account ({LocalPlayer.Name})` })
end

SaveManager:BuildConfigSection(Settings)

-- After any config load (manual or autoload), snap the waypoint back to where it was
-- on this floor and re-enable path farming if it was saved on.
local _origSaveManagerLoad = SaveManager.Load
SaveManager.Load = function(self, name, ...)
    -- Suppress the UseWaypoint OnChanged during load so it can't overwrite our saved
    -- coords with the current (spawn) position before restoreFloorData runs.
    waypointRestoring = true
    local a, b = _origSaveManagerLoad(self, name, ...)
    task.spawn(function()
        task.wait(0.3)
        restoreFloorData()
    end)
    return a, b
end

SaveManager:LoadAutoloadConfig()

Credits = Settings:AddRightGroupbox('Credits')

Credits:AddLabel('de_Neuublue - Script')
Credits:AddLabel('Inori - UI library')
Credits:AddLabel('wally - UI addons')

-- Auto-refresh the theme/config dropdowns every time they're opened
for _, pair in next, {
    { Options.SaveManager_ConfigList, function() return SaveManager:RefreshConfigList() end },
    { Options.ThemeManager_CustomThemeList, function() return ThemeManager:ReloadCustomThemes() end },
} do
    local dropdown, reload = pair[1], pair[2]
    if dropdown and dropdown.Menu then
        local open = dropdown.Menu.Open
        dropdown.Menu.Open = function(self, ...)
            dropdown:SetValues(reload())
            return open(self, ...)
        end
    end
end

-- Strip dividers + 'Refresh list' buttons, shorten addon button labels
local buttonRenames = {
    ['Load selected'] = 'Load',
    ['Load config'] = 'Load',
    ['Save config'] = 'Save',
    ['Overwrite config'] = 'Overwrite',
    ['Set autoload'] = 'Autoload',
    ['Delete'] = 'Delete',
}
for _, tab in next, Library.Tabs do
    local function stripElements(container)
        local stripped = false
        for _, element in next, container.Elements do
            if element.Type == 'Divider' or (element.Type == 'Button' and element.Text == 'Refresh list') then
                element.Holder.Visible = false
                stripped = true
            elseif element.Type == 'Button' and buttonRenames[element.Text] then
                for _, descendant in next, element.Holder:GetDescendants() do
                    if descendant:IsA('TextLabel') then
                        descendant.Text = buttonRenames[element.Text]
                    end
                end
            end
        end
        if stripped and container.Resize then
            container:Resize()
        end
    end

    for _, groupbox in next, tab.Groupboxes do
        stripElements(groupbox)
    end
    for _, tabbox in next, tab.Tabboxes do
        for _, subtab in next, tabbox.Tabs do
            stripElements(subtab)
        end
    end
end

