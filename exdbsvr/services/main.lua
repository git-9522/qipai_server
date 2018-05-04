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
	local proxy_conn = skynet.newservice('proxy_conn')
	skynet.call(proxy_conn,'lua','start')

	local fuser_handler = skynet.uniqueservice('fuser_handler','fuser_worker')
	skynet.name('.fuser_handler',fuser_handler)
	skynet.call(fuser_handler,'lua','start')
	
	local ftable_handler = skynet.uniqueservice('ftable_handler')
	skynet.name('.ftable_handler',ftable_handler)
	skynet.call(ftable_handler,'lua','start')

	local tlock_mgr = skynet.uniqueservice('tlock_mgr')
	skynet.name('.tlock_mgr',tlock_mgr)
	skynet.call(tlock_mgr,'lua','start')

	local msg_handler = skynet.newservice('msg_handler')
	skynet.name('.msg_handler',msg_handler)
	skynet.call(msg_handler,'lua','start')

	skynet.exit()
end)

