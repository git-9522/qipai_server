local skynet = require "skynet"
local proxypack = require "proxypack"
local socketdriver = require "socketdriver"
local proxyserver = require "proxyserver"

local connections = {}

local handler = {}
function handler.open(source, conf)
	watchdog = conf.watchdog or source
	dispatcher = conf.dispatcher
end

function handler.message(fd, msg, sz)
	skynet.send(dispatcher,'lua','proxy',fd,msg,sz)
end

--其它服务连接上来
function handler.connect(fd, addr)
	local conn = {
		fd = fd,
		ip = addr,
	}
	connections[fd] = conn
	skynet.send(watchdog, "lua", "socket", "open", fd, addr)
end

local function close_fd(fd)
	local c = connections[fd]
	if c then
		connections[fd] = nil
	end
end

function handler.disconnect(fd)
	close_fd(fd)
	skynet.send(watchdog, "lua", "socket", "close", fd)
end

function handler.error(fd, msg)
	close_fd(fd)
	skynet.send(watchdog, "lua", "socket", "error", fd, msg)
end

function handler.warning(fd, size)
	skynet.send(watchdog, "lua", "socket", "warning", fd, size)
end

local CMD = {}

function CMD.accept(source, fd)
	assert(connections[fd])
	proxyserver.openclient(fd)
end

function CMD.kick(source, fd)
	proxyserver.closeclient(fd)
end

function handler.command(cmd, source, ...)
	local f = assert(CMD[cmd])
	return f(source, ...)
end

proxyserver.start(handler)
