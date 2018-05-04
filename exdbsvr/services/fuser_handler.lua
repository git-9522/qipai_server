local skynet = require "skynet"
local proxypack = require "proxypack"
local redis = require "redis"

local table_insert = table.insert
local table_unpack = table.unpack

local worker_name = ...

local data_workers = {}
local CMD = {}

local function init(worker_num)
	local conf = {
		redis_host = skynet.getenv "fuser_redis_host",
		redis_port = tonumber(skynet.getenv "fuser_redis_port"),
		redis_db = tonumber(skynet.getenv "fuser_redis_db"),
		pre_alloc = tonumber(skynet.getenv "pre_alloc"),
		max_cache_connection_num = tonumber(skynet.getenv "max_cache_connection_num"),
	}

	for i = 1,worker_num do
		local worker = skynet.newservice(worker_name)
		skynet.call(worker,'lua','open',conf)
		table.insert(data_workers,worker)
	end
end

function CMD.start()
	local worker_num = tonumber(skynet.getenv(worker_name .. "_num")) or 4
	
	init(worker_num)

	print('start.... worker num is ',worker_num)
	skynet.dispatch('lua',function(_,_,cmd,uid, ...)
		local i = uid % #data_workers + 1
		skynet.retpack(skynet.call(data_workers[i],'lua',cmd,uid,...))
	end)

	skynet.retpack(true)
end

skynet.start(function()
	skynet.dispatch("lua", function(_,_,action,...)
		local f = CMD[action]
		if f then
			f(...)
		end
	end)
end)
