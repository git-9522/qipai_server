local skynet = require "skynet"
local proxypack = require "proxypack"

local table_unpack = table.unpack

local data_workers = {}
local CMD = {}

local function init(worker_num)
	local conf = {
		redis_host = skynet.getenv "redis_host",
		redis_port = tonumber(skynet.getenv "redis_port"),
		redis_db = tonumber(skynet.getenv "redis_db"),
		dirty_queue_db = tonumber(skynet.getenv "dirty_queue_db"),
		dirty_queue_key = skynet.getenv "dirty_queue_key",
		pre_alloc = tonumber(skynet.getenv "pre_alloc"),
		max_cache_connection_num = tonumber(skynet.getenv "max_cache_connection_num"),

		db_host = skynet.getenv "db_host",
		db_port = tonumber(skynet.getenv "db_port"),
		db_name = skynet.getenv "db_name",
		db_coll_name = skynet.getenv "db_coll_name",
	}

	for i = 1,worker_num do
		local worker = skynet.newservice('data_worker')
		skynet.call(worker,'lua','open',conf)
		table.insert(data_workers,worker)
	end
end

function CMD.start()
	print('start....')

	local worker_num = tonumber(skynet.getenv("data_worker_num"))
	init(worker_num)

	skynet.dispatch('lua',function(_,_,cmd,uid, ...)
		local i = uid % #data_workers + 1
		local r = {skynet.call(data_workers[i],'lua',cmd,uid,...)}
		if #r > 0 then
			skynet.retpack(table_unpack(r))
		end
	end)

	skynet.retpack(true)
end

skynet.start(function()
	skynet.dispatch("lua", function(session, source, cmd, ...)
		local f = assert(CMD[cmd],'unknown cmd ' .. cmd)
		f(...)
	end)
end)
