local skynet = require "skynet"
local proxypack = require "proxypack"

local CMD = {}

skynet.register_protocol {
	name = "client",
	id = skynet.PTYPE_CLIENT,
	pack = proxypack.pack_raw
}

function CMD.data(game_session,data)
	print('got a request',game_session,#data)

	local agent = skynet.newservice("agent")
	skynet.call(agent, "lua", "start", game_session)
	skynet.send(agent,'client',data)
end

skynet.start(function()
	skynet.dispatch("lua",function(_,_,action, ...)
		local f = assert(CMD[action])
		f(...)
	end)
end)


