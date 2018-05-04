local skynet = require "skynet"
local c = require "protobuf.c"
local fs = require "fs"
local table_insert = table.insert

skynet.start(function()
	c._env_init_single()

	local pb = require "protobuf"
    local pbfile = {}
    local pbroot = skynet.getenv "pbroot"

    local pbdirs = {
        pbroot .. '/common',
        pbroot .. '/games',
        pbroot,
    }

    for _,pbdir in ipairs(pbdirs) do
        for filename in fs.dir(pbdir) do
            if filename:find('%.pb$') then
                table_insert(pbfile,pbdir .. '/' ..  filename)
            end
        end
    end

    for _,filepath in pairs(pbfile) do
        pb.register_file(filepath)
        print('registered file',filepath)
    end
end)
