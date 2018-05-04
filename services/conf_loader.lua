local skynet = require "skynet"
local fs = require "fs"
local table_insert = table.insert
local sharedata = require "sharedata"

skynet.start(function()
    local global_configs = {}
    local configs = skynet.getenv "configs"
    local file_list = {}
    for filename in fs.dir(configs) do
        if filename:find('%.lua$') then
            table_insert(file_list,{
                path = configs .. '/' .. filename,
                name = filename
            })
        end
    end
    
    for _,info in ipairs(file_list) do
        local s = info.name
        local key = s:sub(1,-s:reverse():find('%.') - 1)
        global_configs[key] = dofile(info.path) 
    end

    sharedata.new("global_configs", global_configs)
end)
