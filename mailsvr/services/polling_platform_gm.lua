local skynet = require "skynet"
local mysql = require "mysql"
local redis = require "redis"
local util = require "util"
local cjson = require "cjson"
local server_def = require "server_def"
local utils = require "utils"
local reason = require "reason"
local constant = require "constant"

local table_insert = table.insert
local string_format = string.format

local OPRATION_MESSAGE_STATUS_NEW = 0
local OPRATION_MESSAGE_STATUS_FINISH = 1	--已处理
local OPRATION_MESSAGE_STATUS_FAILED = 2	--操作失败

local GM_TYPE_ALL = 1
local GM_TYPE_SPECAIL = 2

local MESSAGE_ONCE_LIMTI = 10

local CMD_ADD = 1
local CMD_REDUCE = 2

local function notify_money_changed(uid,chg_tb)
	R().hallsvr({key=uid}):send('.msg_handler','money_change',uid,chg_tb)
end

local function check_money_change(uid,item_id,curr_count)
	if item_id == constant.ITEM_COIN_ID then
		notify_money_changed(uid,{coins = curr_count})
	elseif item_id == constant.ITEM_GEM_ID then
		notify_money_changed(uid,{gems = curr_count})
	elseif item_id == constant.ITEM_ROOMCARD_ID then
		notify_money_changed(uid,{roomcards = curr_count})
	end
end

local function deal_gm(uid,data)
	local cmd = data.cmd
	local item_id = data.item_id
	local params = utils.str_split(data.params,",")
	print_r(params)
	local reason = data.reason or ''

	if cmd == CMD_ADD then
		local ok,succ,ret = R().basesvr({key = uid}):call('.msg_handler','add_item',uid,item_id,params[1],reason)
		if not ok or not succ then
			errlog("add_item failed",uid,cmd,params[1],item_id)
			return
		end
		check_money_change(uid,item_id,ret.curr)
	elseif cmd == CMD_REDUCE then
		local ok,succ,ret = R().basesvr({key = uid}):call('.msg_handler','reduce_item',uid,item_id,params[1],reason)
		if not ok or not succ then
			errlog("reduce_item failed",uid,cmd,params[1],item_id)
			return
		end
		check_money_change(uid,item_id,ret.curr)	
    else
        errlog(uid,"invalid cmd",cmd)
        return false    
    end

	dbglog(uid,"already deal_gm "..cmd..",operate time is "..data.operate_time,reason)
    return true
end

local function select_new_platform_gm(mysql_conn)
	local curr_time = util.get_now_time()
	local query_sql = string_format("select `id`,`uid`,`cmd`,`item_id`,`params`,`operate_time`,`reason` from `platform_operation` where `status` = %d limit %d",
		OPRATION_MESSAGE_STATUS_NEW,MESSAGE_ONCE_LIMTI)
	local ret = mysql_conn:query(query_sql)
	local results = {}
	local sql_str_list = {}

	for k,v in pairs(ret) do
		local o = {
			id = v.id,
			uid = v.uid,
			cmd = tonumber(v.cmd),
			item_id = v.item_id,
			params = v.params,
			operate_time = tonumber(v.operate_time),
			reason = v.reason
		}
		print(tostring_r(o))
		table_insert(results,o)
	end
	if #ret < 1 then
		return false
	end
	
	print('now select ....',tostring_r(sql_str_list))

	for _,data in pairs(results) do
		local succ = deal_gm(data.uid,data)
		if succ == true then
			table_insert(sql_str_list,string_format("update `platform_operation` set `status` = %d where `id` = %s",
			OPRATION_MESSAGE_STATUS_FINISH,data.id))
		else
			table_insert(sql_str_list,string_format("update `platform_operation` set `status` = %d where `id` = %s",
			OPRATION_MESSAGE_STATUS_FAILED,data.id))
		end
	end

	mysql_conn:query("start transaction")
	for _,sql_str in ipairs(sql_str_list) do
		mysql_conn:query(sql_str)
	end
	mysql_conn:query("commit")
end

local function routine_check_new_gm(mysql_conn)
    while true do
        local ok,ret = pcall(select_new_platform_gm,mysql_conn)
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

	skynet.fork(routine_check_new_gm,mysql_conn)
end

local CMD = {}

function CMD.start()
	init()
	skynet.retpack(true)
end

skynet.start(function()
	skynet.dispatch("lua", function(session, source, cmd, ...)
		local f = assert(CMD[cmd])
		f(...)
	end)
end)
