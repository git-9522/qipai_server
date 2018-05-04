local skynet = require "skynet.manager"

local max_client = tonumber(skynet.getenv "max_client")
local server_id = tonumber(skynet.getenv "server_id")
local debug_console_port = tonumber(skynet.getenv "debug_console_port")

skynet.start(function()
	skynet.error("Server start")
	skynet.uniqueservice("conf_loader")
	if not skynet.getenv "daemon" then
		local console = skynet.newservice("console")
	end
	skynet.newservice("debug_console",debug_console_port)

	local proxy_conn = skynet.newservice('proxy_conn')
	skynet.call(proxy_conn,'lua','start')

	local msg_handler = skynet.newservice('msg_handler')
	skynet.name('.msg_handler',msg_handler)
	skynet.call(msg_handler,'lua','start',proxy_conn)

	skynet.exit()
end)

