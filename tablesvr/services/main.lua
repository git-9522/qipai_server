local skynet = require "skynet.manager"

local max_client = tonumber(skynet.getenv "max_client")
local server_id = tonumber(skynet.getenv "server_id")
local watchdog_port = tonumber(skynet.getenv "listen_port")
local server_name = skynet.getenv "server_name"

skynet.start(function()
	skynet.error("Server start")
	skynet.uniqueservice("pbloader")
	skynet.uniqueservice("conf_loader")

	local textfilter = skynet.uniqueservice('textfilter')
	skynet.name('.textfilter',textfilter)

	if not skynet.getenv "daemon" then
		local console = skynet.newservice("console")
	end
	skynet.newservice("debug_console",10000 + watchdog_port)

	local proxy_conn = skynet.newservice('proxy_conn')
	skynet.call(proxy_conn,'lua','start')

	local table_mgr = skynet.uniqueservice('table_mgr')
	skynet.name('.table_mgr',table_mgr)

	local msg_handler = skynet.newservice('msg_handler')
	skynet.name('.msg_handler',msg_handler)
	skynet.call(msg_handler,'lua','start')

	if skynet.getenv "DEBUG" then
		skynet.uniqueservice('cache_data')
	end
	
	skynet.exit()
end)

