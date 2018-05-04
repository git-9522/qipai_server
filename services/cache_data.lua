local skynet = require "skynet.manager"

local cache = {}

local CMD = {}

function CMD.set(key,value)
	cache[key] = value
end

function CMD.get(key)
	return cache[key]
end

skynet.start(function()
   skynet.dispatch("lua", function (session, source ,cmd, ...)
		local f = assert(CMD[cmd])

		skynet.retpack(f(...))
	end)
	skynet.register(".cache_data")
end)