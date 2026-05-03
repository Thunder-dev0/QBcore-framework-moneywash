local QBCore = exports['qb-core']:GetCoreObject()

local Config = {
    TaxRate = 0.10,
    WashTime = 15, 
    ExpiryTime = 60,
    BlackMoneyItem = "spawncode for dirtymoney",
    TokenItem = "if you want to do a item token",
    TokenPrice = 5000,
    Webhook = 'for discord logs enter webhook here' 
}

local function DiscordLog(name, title, color, message)
    local embed = {
        {
            ["color"] = color,
            ["title"] = "**".. title .."**",
            ["description"] = message,
            ["footer"] = { ["text"] = os.date("%Y-%m-%d %H:%M:%S") },
        }
    }
    PerformHttpRequest(Config.Webhook, function(err, text, headers) end, 'POST', json.encode({username = name, embeds = embed}), { ['Content-Type'] = 'application/json' })
end

local function GenerateID(coords)
    return string.format("WASH_%.2f_%.2f_%.2f", coords.x, coords.y, coords.z)
end

-- CHECK MACHINE STATUS
QBCore.Functions.CreateCallback('xt-moneywash:checkWasher', function(source, cb, coords)
    local machineID = GenerateID(coords)
    exports.oxmysql:execute('SELECT * FROM washer_data WHERE machine_id = ? LIMIT 1', {machineID}, function(result)
        if result and result[1] then
            local data = result[1]
            local currentTime = os.time()
            local finishTime = tonumber(data.end_time) or 0
            local expiryThreshold = finishTime + (Config.ExpiryTime * 60)

            if currentTime > expiryThreshold then
                exports.oxmysql:execute('UPDATE washer_data SET machine_id = "MANAGER" WHERE id = ?', {data.id})
                DiscordLog("Laundromat Logs", "Sent to Lost & Found", 15105570, "**Machine:** "..machineID.."\n**Amount:** $"..data.amount.."\n**Reason:** Uncollected Expiry")
                return cb(nil)
            end

            cb({
                time_left = math.max(0, math.ceil((finishTime - currentTime) / 60)),
                original_amount = tonumber(data.original_amount) or 0,
                amount = tonumber(data.amount) or 0,
                password = data.password or "0000"
            })
        else cb(nil) end
    end)
end)

-- CHECK MANAGER STOCK
QBCore.Functions.CreateCallback('xt-moneywash:server:checkManagerStock', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    local cid = Player.PlayerData.citizenid
    local currentTime = os.time()
    
    exports.oxmysql:execute('UPDATE washer_data SET machine_id = "MANAGER" WHERE citizenid = ? AND machine_id != "MANAGER" AND ? > (end_time + ?)', 
    {cid, currentTime, (Config.ExpiryTime * 60)}, function()
        exports.oxmysql:execute('SELECT SUM(amount) as total FROM washer_data WHERE citizenid = ? AND machine_id = "MANAGER"', {cid}, function(result)
            cb(tonumber(result[1] and result[1].total or 0))
        end)
    end)
end)

-- START WASH (Includes One-Machine-Per-Player Check)
RegisterNetEvent('xt-moneywash:startWash', function(data)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local cid = Player.PlayerData.citizenid
    local fullName = Player.PlayerData.charinfo.firstname .. " " .. Player.PlayerData.charinfo.lastname
    local inputAmount = tonumber(data.amount)
    local machineID = GenerateID(data.coords)

    -- Limit Check: Is player already using a machine?
    exports.oxmysql:execute('SELECT id FROM washer_data WHERE citizenid = ? AND machine_id != "MANAGER" LIMIT 1', {cid}, function(result)
        if result and result[1] then
            TriggerClientEvent('QBCore:Notify', src, "You are already using another machine!", "error")
            return
        end

        local hasToken = exports.ox_inventory:Search(src, 'count', Config.TokenItem) >= 1
        local hasDirty = exports.ox_inventory:Search(src, 'count', Config.BlackMoneyItem) >= inputAmount

        if not hasToken or not hasDirty then
            TriggerClientEvent('QBCore:Notify', src, "Missing required items or cash.", "error")
            return
        end

        local payoutAmount = math.floor(inputAmount * (1 - Config.TaxRate))
        local finishTime = os.time() + (Config.WashTime * 60)

        exports.oxmysql:insert('INSERT INTO washer_data (machine_id, citizenid, password, amount, original_amount, end_time) VALUES (?, ?, ?, ?, ?, ?)', 
        {machineID, cid, tostring(data.password), payoutAmount, inputAmount, finishTime}, function(id)
            if id then
                exports.ox_inventory:RemoveItem(src, Config.TokenItem, 1)
                exports.ox_inventory:RemoveItem(src, Config.BlackMoneyItem, inputAmount)
                TriggerClientEvent('QBCore:Notify', src, "Washing cycle started.", "success")
                
                DiscordLog("Laundromat Logs", "Cycle Started", 3447003, 
                    "**Player:** " .. fullName .. "\n" ..
                    "**CitizenID:** " .. cid .. "\n" ..
                    "**Input:** $" .. inputAmount .. "\n" ..
                    "**Machine:** " .. machineID)
            end
        end)
    end)
end)

-- CLAIM FROM MACHINE
RegisterNetEvent('xt-moneywash:claimMoney', function(coords)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local cid = Player.PlayerData.citizenid
    local fullName = Player.PlayerData.charinfo.firstname .. " " .. Player.PlayerData.charinfo.lastname
    local machineID = GenerateID(coords)

    exports.oxmysql:execute('SELECT id, amount FROM washer_data WHERE machine_id = ?', {machineID}, function(result)
        if result and result[1] then
            local amount = tonumber(result[1].amount)
            Player.Functions.AddMoney('cash', amount, "laundry-claim")
            exports.oxmysql:execute('DELETE FROM washer_data WHERE id = ?', {result[1].id})
            
            DiscordLog("Laundromat Logs", "Machine Claimed", 3066993, 
                "**Player:** " .. fullName .. "\n" ..
                "**CitizenID:** " .. cid .. "\n" ..
                "**Amount:** $" .. amount .. "\n" ..
                "**Machine:** " .. machineID)
        end
    end)
end)

-- CLAIM FROM MANAGER
RegisterNetEvent('xt-moneywash:server:claimFromManager', function()
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local cid = Player.PlayerData.citizenid
    local fullName = Player.PlayerData.charinfo.firstname .. " " .. Player.PlayerData.charinfo.lastname
    
    exports.oxmysql:execute('SELECT id, amount FROM washer_data WHERE citizenid = ? AND machine_id = "MANAGER"', {cid}, function(result)
        if result and #result > 0 then
            local totalPayout = 0
            for _, row in ipairs(result) do
                totalPayout = totalPayout + tonumber(row.amount)
                exports.oxmysql:execute('DELETE FROM washer_data WHERE id = ?', {row.id})
            end
            Player.Functions.AddMoney('cash', totalPayout, "manager-claim")
            TriggerClientEvent('QBCore:Notify', src, "Recovered $"..totalPayout.." from Manager.", "success")
            
            DiscordLog("Laundromat Logs", "Manager Claimed", 15844367, 
                "**Player:** " .. fullName .. "\n" ..
                "**CitizenID:** " .. cid .. "\n" ..
                "**Total Recovered:** $" .. totalPayout)
        end
    end)
end)

-- BUY TOKEN
RegisterNetEvent('xt-moneywash:server:purchaseToken', function()
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local fullName = Player.PlayerData.charinfo.firstname .. " " .. Player.PlayerData.charinfo.lastname
    if Player.Functions.RemoveMoney('cash', Config.TokenPrice, "laundry-token") or Player.Functions.RemoveMoney('bank', Config.TokenPrice, "laundry-token") then
        exports.ox_inventory:AddItem(src, Config.TokenItem, 1)
        DiscordLog("Laundromat Logs", "Token Purchased", 15105570, "**Player:** " .. fullName .. "\n**Cost:** $" .. Config.TokenPrice)
    end
end)
