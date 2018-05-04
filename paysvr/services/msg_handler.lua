local skynet = require "skynet"
local proxypack = require "proxypack"
local mysql = require "mysql"
local redis = require "redis"
local util = require "util"
local cjson = require "cjson"

local table_insert = table.insert
local string_format = string.format

local polling_worker

local CMD = {}

function CMD.start(proxy_conn)
	print('begin to start -----------------------')
	assert(not polling_worker, 'duplicated starting')
	polling_worker = true

	skynet.call(proxy_conn,'lua','wait_for_registered')
	
 	polling_worker = skynet.newservice('polling_worker')
	local express_worker = skynet.newservice('express_worker')
	skynet.call(polling_worker,'lua','start',express_worker)

	print('end to start -----------------------')
	skynet.retpack(true)
end

skynet.start(function()
	skynet.dispatch("lua", function(session,source,cmd,...)
		local f = CMD[cmd]
		f(...)
	end)
end)
