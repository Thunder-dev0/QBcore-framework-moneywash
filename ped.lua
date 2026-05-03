local QBCore = exports['qb-core']:GetCoreObject()
local SpawnedManagers = {}

local ManagerLocs = {
    vec4(1132.36, -987.83, 46.11, 176.36),
    vector4(841.06, -123.86, 79.77, 332.29),
}

function OpenManagerMenu()
    QBCore.Functions.TriggerCallback('xt-moneywash:server:checkManagerStock', function(total)
        local options = {
            {
                title = 'Buy Laundry Token',
                description = '$5,000',
                icon = 'shopping-basket',
                onSelect = function() TriggerServerEvent('xt-moneywash:server:purchaseToken') end
            }
        }

        if total and total > 0 then
            table.insert(options, {
                title = 'Claim Lost & Found',
                description = 'The manager recovered $' .. total .. ' from the machines.',
                icon = 'sack-dollar',
                iconColor = '#FFD700',
                onSelect = function() TriggerServerEvent('xt-moneywash:server:claimFromManager') end
            })
        end

        lib.registerContext({ id = 'manager_menu', title = 'Laundromat Manager', options = options })
        lib.showContext('manager_menu')
    end)
end

function SpawnPeds()
    local model = `s_m_m_dockwork_01`
    RequestModel(model)
    while not HasModelLoaded(model) do Wait(0) end

    for _, loc in ipairs(ManagerLocs) do
        local ped = CreatePed(0, model, loc.x, loc.y, loc.z - 1.0, loc.w, false, false)
        FreezeEntityPosition(ped, true)
        SetEntityInvincible(ped, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
        TaskStartScenarioInPlace(ped, "WORLD_HUMAN_CLIPBOARD", 0, true)
        exports.ox_target:addLocalEntity(ped, {
            { label = "Talk to Manager", icon = "fas fa-user-tie", onSelect = function() OpenManagerMenu() end }
        })
        table.insert(SpawnedManagers, ped)
    end
end

CreateThread(function() SpawnPeds() end)