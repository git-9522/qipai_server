local skynet = require "skynet"

local max_client = tonumber(skynet.getenv "max_client")
local watchdog_port = tonumber(skynet.getenv "listen_port")

skynet.start(function()
	skynet.error("Server start")
	if not skynet.getenv "daemon" then
		local console = skynet.newservice("console")
	end
	skynet.newservice("debug_console",10000 + watchdog_port)
	local watchdog = skynet.newservice("watchdog")
	skynet.call(watchdog, "lua", "start", {
		port = watchdog_port,
		maxclient = max_client,
		nodelay = true,
	})
	skynet.error("Watchdog listen on", watchdog_port)
	skynet.exit()
end)

