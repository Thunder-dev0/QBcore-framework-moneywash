fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Thunders'
description 'Advanced Industrial Laundering System'

shared_script '@ox_lib/init.lua'

client_scripts {
    'client/main.lua',
    'client/ped.lua' -- Ensure this is here!
}

server_scripts {
    '@oxmysql/lib/utils.lua',
    'server/main.lua'
}

dependencies {
    'qb-core',
    'ox_lib',
    'ox_target',
    'oxmysql'
}