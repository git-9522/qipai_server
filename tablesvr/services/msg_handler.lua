local skynet = require "skynet"
local proxypack = require "proxypack"


skynet.register_protocol {
	name = "client",
	id = skynet.PTYPE_CLIENT,
	pack = skynet.pack
}

local agents = {}

local CMD = {}
local close_response = {}

function CMD.data(game_session,data,uid)
	print('got data',game_session,uid,data)
	skynet.send('.table_mgr','client',game_session,uid,data)
end

function CMD.close(uid,game_session,reason)
	skynet.send('.table_mgr','lua','disconnect',uid,game_session)
end

function CMD.start()
	print('start....')
	skynet.retpack(true)
end

function CMD.force_close(game_session)
	close_response[game_session] = skynet.response()
end

function CMD.close_server()
	dbglog("close_server begin!!!")
	skynet.send('.table_mgr','lua','close_server')
end

skynet.start(function()
	skynet.dispatch("lua", function(session, source, cmd, ...)
		local f = assert(CMD[cmd],'unknown cmd '.. cmd)
		f(...)
	end)
end)
