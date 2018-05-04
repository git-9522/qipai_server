local skynet = require "skynet"
local proxypack = require "proxypack"

local table_insert = table.insert
local table_unpack = table.unpack

local data_workers = {}
local CMD = {}
local conf = {}

local function sync_mail()	
	local polling_mail = skynet.newservice('polling_mail')
	skynet.call(polling_mail,"lua","start")
end

local function init_all_worker(worker_num)
	conf = {
			redis_host = skynet.getenv "redis_host",
			redis_port = tonumber(skynet.getenv "redis_port"),
			redis_db = tonumber(skynet.getenv "redis_db"),
			dirty_queue_db = tonumber(skynet.getenv "dirty_queue_db"),
			dirty_queue_key = skynet.getenv "dirty_queue_key",
			new_mail_db = skynet.getenv "new_mail_db",
			mail_record_db = skynet.getenv "mail_record_db",
			user_db = skynet.getenv "user_db"
	}

	for i = 1,worker_num do
		local worker = skynet.newservice('data_worker')
		skynet.call(worker,'lua','open',conf)
		table_insert(data_workers,worker)
	end

	--开启邮件扫描服务
	sync_mail()
end

function CMD.start()
	print('start....')

	local worker_num = tonumber(skynet.getenv("data_worker_num"))
	init_all_worker(worker_num)

	skynet.dispatch('lua',function(_,_,cmd,uid, ...)
		print(cmd,uid, ...)
		local i = uid % #data_workers + 1
		local r = {skynet.call(data_workers[i],'lua',cmd,uid,...)}
		if #r > 0 then
			skynet.retpack(table_unpack(r))
		end
	end)

	local opration_message_worker = skynet.newservice('opration_message_worker')
	skynet.call(opration_message_worker,'lua','start')

	skynet.retpack(true)
end

skynet.start(function()
	skynet.dispatch("lua", function(session, source, cmd, ...)
		local f = assert(CMD[cmd])
		f(...)
	end)
end)
