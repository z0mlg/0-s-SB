-- Bluu :: ServerHop  (split from Sb2-0mlg.lua)

do

function saveServerSwitchConfig(targetPlace, position)
    if not isfolder then return end
    if not isfolder('Bluu') then makefolder('Bluu') end
    if not isfolder('Bluu/Swordburst 2') then makefolder('Bluu/Swordburst 2') end
    
    local config = {
        active = true,
        targetPlace = targetPlace,
        position = {x = position.X, y = position.Y, z = position.Z}
    }
    
    writefile('Bluu/Swordburst 2/serverswitch', game:GetService("HttpService"):JSONEncode(config))
end

local function loadServerSwitchConfig()
    if not isfile or not isfile('Bluu/Swordburst 2/serverswitch') then return nil end
    
    local success, config = pcall(function()
        return game:GetService("HttpService"):JSONDecode(readfile('Bluu/Swordburst 2/serverswitch'))
    end)
    
    return success and config or nil
end

local function clearServerSwitchConfig()
    if isfile and isfile('Bluu/Swordburst 2/serverswitch') then
        delfile('Bluu/Swordburst 2/serverswitch')
    end
end

local function autoBlockModerator(player)
    if not Toggles.AutoBlockMods or not Toggles.AutoBlockMods.Value then return end
    if player == LocalPlayer then return end
    
    local isMod = false
    
    pcall(function()
        local badges = game:GetService("BadgeService"):GetBadgeInfoAsync(1)
        if badges then
            isMod = true
        end
    end)
    
    if not isMod then
        pcall(function()
            if player:IsInGroup(1200769) then
                isMod = true
            end
        end)
    end
    
    if not isMod then
        local staffBadges = {1, 2, 3, 4, 5, 6}
        for _, badgeId in ipairs(staffBadges) do
            pcall(function()
                if game:GetService("BadgeService"):UserHasBadgeAsync(player.UserId, badgeId) then
                    isMod = true
                end
            end)
            if isMod then break end
        end
    end
    
    if isMod then
        print("[Mod Blocker] Detected moderator:", player.Name, "- Blocking...")

        task.wait(0.5)

        task.spawn(function()
            if blockPlayer(player) then
                print("[Mod Blocker] Successfully blocked moderator:", player.Name)
            else
                warn("[Mod Blocker] Failed to block moderator:", player.Name)
            end

            if Toggles.ServerSwitch and Toggles.ServerSwitch.Value then
                -- block verified: leave immediately, before they can inspect us
                print("[Server Switch] Moderator detected! Switching servers...")
                Library:Notify('⚠ Moderator detected!\nSwitching servers...', 5)

                local originalFloor = game.PlaceId
                local currentPosition = HumanoidRootPart and HumanoidRootPart.Position
                if currentPosition then
                    saveServerSwitchConfig(originalFloor, currentPosition)
                    print('[Server Switch] Saved position:', currentPosition)
                end

                print('[Server Switch] Teleporting to Hub World...')
                pcall(function()
                    game:GetService("TeleportService"):Teleport(659222129, LocalPlayer)
                end)
            end
        end)
    end
end

Players.PlayerAdded:Connect(autoBlockModerator)

for _, player in pairs(Players:GetPlayers()) do
    if player ~= LocalPlayer then
        task.spawn(function()
            autoBlockModerator(player)
        end)
    end
end

task.spawn(function()
    task.wait(3)
    
    if game.PlaceId == 659222129 then
        print('[Hub World] Detected hub world, firing Login remote in loop...')
        task.spawn(function()
            while game.PlaceId == 659222129 do
                pcall(function()
                    local args = {"Login"}
                    game:GetService("ReplicatedStorage"):WaitForChild("Function"):InvokeServer(unpack(args))
                end)
                task.wait(1)
            end
        end)
    end
    
    local config = loadServerSwitchConfig()
    if config and config.active then
        if game.PlaceId == 659222129 and config.targetPlace ~= 659222129 then
            print('[Server Switch] In Hub World, auto-executing script...')
            task.wait(2)
            
            local success, result = pcall(function()
                return game:HttpGet('https://raw.githubusercontent.com/z0mlg/Sb2Cheats/refs/heads/main/Test')
            end)
            
            if success and result then
                print('[Server Switch] Script loaded, executing...')
                loadstring(result)()
            else
                warn('[Server Switch] Failed to load auto-execute script')
            end
            
            print('[Server Switch] Teleporting back to original floor:', config.targetPlace)
            task.wait(1)
            Function:InvokeServer("Teleport", {"Teleport", config.targetPlace})
        elseif config.targetPlace == game.PlaceId and config.position then
            print('[Server Switch] Restoring position:', config.position.x, config.position.y, config.position.z)
            task.wait(1)
            
            local targetPosition = Vector3.new(config.position.x, config.position.y, config.position.z)
            HumanoidRootPart.CFrame = CFrame.new(targetPosition)
            
            Library:Notify('✓ Server switched!\nPosition restored', 5)
            print('[Server Switch] Position restored successfully')
            
            clearServerSwitchConfig()
        end
    end
end)

end

do

local EmptyServerBox = Misc:AddRightGroupbox('Empty server finder')

local emptyServerActive = false
local emptyServerTargetPlace = nil
local emptyServerMaxPlayers = 2

local function saveEmptyServerConfig(targetPlace, maxPlayers, serversChecked)
    if not isfolder then return end
    if not isfolder('Bluu') then makefolder('Bluu') end
    if not isfolder('Bluu/Swordburst 2') then makefolder('Bluu/Swordburst 2') end
    
    local config = {
        active = true,
        targetPlace = targetPlace,
        maxPlayers = maxPlayers,
        serversChecked = serversChecked
    }
    
    writefile('Bluu/Swordburst 2/emptyserver', game:GetService("HttpService"):JSONEncode(config))
end

local function loadEmptyServerConfig()
    if not isfile or not isfile('Bluu/Swordburst 2/emptyserver') then return nil end
    
    local success, config = pcall(function()
        return game:GetService("HttpService"):JSONDecode(readfile('Bluu/Swordburst 2/emptyserver'))
    end)
    
    return success and config or nil
end

local function clearEmptyServerConfig()
    if isfile and isfile('Bluu/Swordburst 2/emptyserver') then
        delfile('Bluu/Swordburst 2/emptyserver')
    end
end

EmptyServerBox:AddSlider('MaxPlayersInEmpty', { Text = 'Max players allowed', Default = 2, Min = 0, Max = 5, Rounding = 0 })

local function startEmptyServerFinder(resuming, serversChecked)
    emptyServerActive = true
    emptyServerTargetPlace = game.PlaceId
    emptyServerMaxPlayers = Options.MaxPlayersInEmpty.Value
    
    if not resuming then
        serversChecked = 0
        Library:Notify('Empty server finder started!\nLooking for servers with ≤' .. emptyServerMaxPlayers .. ' players', 5)
    else
        Library:Notify('Empty server finder resumed!\nServers checked: ' .. serversChecked, 5)
    end
    
    task.spawn(function()
        local blockedThisSession = {}
        
        while emptyServerActive do
            local currentPlayers = #Players:GetPlayers() - 1
            
            print('[Empty Server] Current server has', currentPlayers, 'other players')
            
            if currentPlayers <= emptyServerMaxPlayers then
                Library:Notify('✓ Found empty server!\nPlayers: ' .. currentPlayers .. '\nServers checked: ' .. serversChecked, 10)
                clearEmptyServerConfig()
                emptyServerActive = false
                break
            end
            
            local playersToBlock = math.min(1, currentPlayers)
            local playersList = {}
            
            for _, player in pairs(Players:GetPlayers()) do
                if player ~= LocalPlayer and not blockedThisSession[player.UserId] then
                    table.insert(playersList, player)
                end
            end
            
            if #playersList > 0 then
                for i = 1, playersToBlock do
                    if #playersList == 0 then break end
                    
                    local randomIndex = math.random(1, #playersList)
                    local playerToBlock = playersList[randomIndex]
                    table.remove(playersList, randomIndex)
                    
                    print('[Empty Server] Blocking player:', playerToBlock.Name)
                    blockedThisSession[playerToBlock.UserId] = true
                    blockPlayer(playerToBlock) -- verified inside: returns once actually blocked
                    task.wait(10)
                end
            end
            
            serversChecked = serversChecked + 1
            print('[Empty Server] Servers checked:', serversChecked, '| Server hopping via Hub World...')
            
            saveEmptyServerConfig(emptyServerTargetPlace, emptyServerMaxPlayers, serversChecked)
            
            print('[Empty Server] Teleporting to Hub World...')
            game:GetService("TeleportService"):Teleport(659222129, LocalPlayer)
            
            task.wait(10)
        end
    end)
end

EmptyServerBox:AddButton({ Text = 'Find empty server', Func = function()
    startEmptyServerFinder(false, 0)
end })

EmptyServerBox:AddButton({ Text = 'Stop finder', Func = function()
    emptyServerActive = false
    clearEmptyServerConfig()
    Library:Notify('Empty server finder stopped', 3)
end })

task.spawn(function()
    task.wait(3)
    
    local config = loadEmptyServerConfig()
    if config and config.active then
        if game.PlaceId == 659222129 and config.targetPlace ~= 659222129 then
            print('[Empty Server] In Hub World, auto-executing script...')
            task.wait(2)
            
            local success, result = pcall(function()
                return game:HttpGet('https://raw.githubusercontent.com/z0mlg/Sb2Cheats/refs/heads/main/Test')
            end)
            
            if success and result then
                print('[Empty Server] Script loaded, executing...')
                loadstring(result)()
            else
                warn('[Empty Server] Failed to load auto-execute script')
            end
            
            print('[Empty Server] Teleporting back to original floor:', config.targetPlace)
            task.wait(1)
            Function:InvokeServer("Teleport", {"Teleport", config.targetPlace})
        elseif config.targetPlace == game.PlaceId then
            print('[Empty Server] Resuming empty server finder from previous session')
            startEmptyServerFinder(true, config.serversChecked or 0)
        end
    end
end)

end
