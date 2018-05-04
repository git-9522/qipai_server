local skynet = require "skynet.manager"

local max_client = tonumber(skynet.getenv "max_client")
local watchdog_port = tonumber(skynet.getenv "listen_port")
local server_id = tonumber(skynet.getenv "server_id")

skynet.start(function()
	skynet.error("Server start")
	if not skynet.getenv "daemon" then
		local console = skynet.newservice("console")
	end
	skynet.newservice("debug_console",10000 + watchdog_port)

	local msg_handler = skynet.newservice("msg_handler")
	skynet.name('.msg_handler',msg_handler)

	local watchdog = skynet.newservice("watchdog")
	skynet.name('.watchdog',watchdog)
	skynet.call(watchdog, "lua", "start", {
		port = watchdog_port,
		maxclient = max_client,
		nodelay = true,
		server_id = server_id,
		server_name = skynet.getenv "server_name",
		msg_handler = msg_handler,
	})
	skynet.error("Watchdog listen on", watchdog_port)
	skynet.exit()
end)

