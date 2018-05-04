local skynet = require "skynet.manager"

local max_client = tonumber(skynet.getenv "max_client")
local server_id = tonumber(skynet.getenv "server_id")
local debug_console_port = tonumber(skynet.getenv "debug_console_port")
local server_name = skynet.getenv "server_name"

skynet.start(function()
	skynet.error("Server start")
	local textfilter = skynet.uniqueservice('textfilter')
	skynet.name('.textfilter',textfilter)

	skynet.uniqueservice("pbloader")
	skynet.uniqueservice("conf_loader")

	if not skynet.getenv "daemon" then
		local console = skynet.newservice("console")
	end
	skynet.newservice("debug_console",debug_console_port)

	local proxy_conn = skynet.newservice('proxy_conn')
	skynet.call(proxy_conn,'lua','start')
	
	skynet.uniqueservice('opration_message_mgr')

	local msg_handler = skynet.newservice('msg_handler')
	skynet.name('.msg_handler',msg_handler)
	skynet.call(msg_handler,'lua','start')

	skynet.exit()
end)

