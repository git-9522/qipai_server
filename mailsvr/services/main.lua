local skynet = require "skynet.manager"

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
	
	skynet.uniqueservice('opration_message_worker_mgr')

	local msg_handler = skynet.newservice('msg_handler')
	skynet.name('.msg_handler',msg_handler)
	skynet.call(msg_handler,'lua','start')

	local online_worker = skynet.newservice('online_worker')
	skynet.call(online_worker,'lua','start')

	local polling_platform_gm = skynet.newservice('polling_platform_gm')
	skynet.call(polling_platform_gm,"lua","start")
	skynet.exit()
end)

