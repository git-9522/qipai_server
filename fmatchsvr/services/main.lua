local skynet = require "skynet.manager"

local max_client = tonumber(skynet.getenv "max_client")
local server_id = tonumber(skynet.getenv "server_id")
local debug_console_port = tonumber(skynet.getenv "debug_console_port")

skynet.start(function()
	skynet.error("Server start")

	if not skynet.getenv "daemon" then
		local console = skynet.newservice("console")
	end
	skynet.newservice("debug_console",debug_console_port)

	local proxy_conn = skynet.uniqueservice('proxy_conn')
	skynet.call(proxy_conn,'lua','start')
	
	local table_mgr = skynet.uniqueservice('table_mgr')
	skynet.name('.table_mgr',table_mgr)
	skynet.call(table_mgr,'lua','start')
	
	skynet.exit()
end)

