local skynet = require "skynet"
local relay = require "relay"

local CMD = {}
local SOCKET = {}
local proxy_mgr
local dispatcher
local internal_servers = {}

function SOCKET.open(fd, addr)
	print("New internal server from : ",addr,fd)
	skynet.call(proxy_mgr,'lua','accept',fd)
	internal_servers[fd] = true
end

local function close_agent(fd)
	if internal_servers[fd] then
		internal_servers[fd] = nil
		skynet.call(proxy_mgr, "lua", "kick", fd)
		skynet.send(dispatcher, "lua", "disconnect",fd)
	end
end

function SOCKET.close(fd)
	print("socket close",fd)
	close_agent(fd)
end

function SOCKET.error(fd, msg)
	print("socket error",fd, msg)
	close_agent(fd)
end

function SOCKET.warning(fd, size)
	-- size K bytes havn't send out in fd
	print("socket warning", fd, size)
end

function SOCKET.data(fd, msg,sz)
	print('got data from client',fd,msg,sz)
end

function CMD.start(conf)
	conf.dispatcher = dispatcher
	skynet.call(proxy_mgr, "lua", "open" , conf)
end

function CMD.close(fd)
	close_agent(fd)
end

skynet.start(function()
	skynet.dispatch("lua", function(session, source, cmd, subcmd, ...)
		if cmd == "socket" then
			local f = SOCKET[subcmd]
			f(...)
			-- socket api don't need return
		else
			local f = assert(CMD[cmd])
			skynet.ret(skynet.pack(f(subcmd, ...)))
		end
	end)

	dispatcher = skynet.newservice('dispatcher')
	skynet.call(dispatcher,'lua','start',skynet.self())
	proxy_mgr = skynet.newservice("proxy_mgr")
end)
