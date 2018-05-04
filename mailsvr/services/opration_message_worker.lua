local skynet = require "skynet"
local mysql = require "mysql"
local redis = require "redis"
local util = require "util"
local cjson = require "cjson"
local server_def = require "server_def"

local table_insert = table.insert
local string_format = string.format

local OPRATION_MESSAGE_STATUS_NEW = 0
local OPRATION_MESSAGE_STATUS_FINISH = 1	--已处理

local MESSAGE_ONCE_LIMTI = 10


local function notify_opration_message(results)
	R().hallsvr():broadcast('.msg_handler','notify_all_agent',results)
end

local function select_new_opration_message(mysql_conn)
	local curr_time = util.get_now_time()
	local query_sql = string_format("select `id`,`begine_time`,`end_time`,`interval`,`message` from `opration_message` where `status` = %d and `begine_time` < %d and `end_time` > %d limit %d",
		OPRATION_MESSAGE_STATUS_NEW,curr_time,curr_time,MESSAGE_ONCE_LIMTI)
	local ret = mysql_conn:query(query_sql)
	local results = {}
	local sql_str_list = {}

	for k,v in pairs(ret) do
		local o = {
			id = v.id,
			begine_time = tonumber(v.begine_time),
			end_time = tonumber(v.end_time),
			interval = tonumber(v.interval),
			message = v.message,
		}
		print(tostring_r(o))
		table_insert(results,o)
		table_insert(sql_str_list,string_format("update `opration_message` set `status` = %d where `id` = %s",
			OPRATION_MESSAGE_STATUS_FINISH,v.id))
	end

	if #sql_str_list < 1 then
		return false
	end
	
	print('now select ....',tostring_r(sql_str_list))

	mysql_conn:query("start transaction")
	for _,sql_str in ipairs(sql_str_list) do
		mysql_conn:query(sql_str)
	end
	mysql_conn:query("commit")

	--广播给hallsvr
	notify_opration_message(results)
end

local function routine_check_new_opration_message(mysql_conn)
    while true do
        local ok,ret = pcall(select_new_opration_message,mysql_conn)
        if not ok then
            errlog(ret)
        end
        skynet.sleep(3 * 100)
    end
end

local function init()
	local function on_connect(db)
		db:query("set charset utf8");
	end

	local mysql_conf = {
		host = skynet.getenv "db_host",
		port = tonumber(skynet.getenv "db_port"),
		user = skynet.getenv "db_user",
		password = skynet.getenv "db_password",
		database = skynet.getenv "db_name",
		max_packet_size = 1024 * 1024,
		on_connect = on_connect
	}

	local mysql_conn = mysql.connect(mysql_conf)

	skynet.fork(routine_check_new_opration_message,mysql_conn)
end

local CMD = {}

function CMD.start()
	print("eeeee")
	init()
	skynet.retpack(true)
end

skynet.start(function()
	skynet.dispatch("lua", function(session, source, cmd, ...)
		local f = assert(CMD[cmd])
		f(...)
	end)
end)
