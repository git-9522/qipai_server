local skynet = require "skynet.manager"

local max_client = tonumber(skynet.getenv "max_client")
local server_id = tonumber(skynet.getenv "server_id")
local debug_console_port = tonumber(skynet.getenv "debug_console_port")

skynet.start(function()
	skynet.error("Server start")
	if not skynet.getenv "daemon" then
		skynet.newservice("console")
	end
	skynet.newservice("debug_console",debug_console_port)
	
	skynet.uniqueservice("pbloader")
	local proxy_conn = skynet.newservice('proxy_conn')
	skynet.call(proxy_conn,'lua','start')

	local msg_handler = skynet.newservice('msg_handler')
	skynet.name('.msg_handler',msg_handler)

	local info_mgr = skynet.newservice('info_mgr')
	skynet.name('.info_mgr',info_mgr)


	skynet.exit()
end)

