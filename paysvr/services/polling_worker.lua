local skynet = require "skynet"
local mysql = require "mysql"
local util = require "util"
local cjson = require "cjson"
local server_def = require "server_def"

local table_insert = table.insert
local string_format = string.format

local select_server = require "router_selector"

local ORDER_STATUS_PAID = 1
local ORDER_STATUS_FINISH = 2	--已处理

local ORDER_ONCE_LIMTI = 100

local express_worker

local function notify_payment(results)
	for _,r in ipairs(results) do
		skynet.send(express_worker,'lua','new_payment',r)
	end
end

local function select_paid_order(mysql_conn)
	local query_sql = string_format("select `order_id`,`uid`,`product_id`,`amount`,`paid_time` from `order` where `status` = %d limit %d",
		ORDER_STATUS_PAID,ORDER_ONCE_LIMTI)

	local ret = mysql_conn:query(query_sql)
	local results = {}
	local sql_str_list = {}
	for k,v in pairs(ret) do
		local o = {
			order_id = v.order_id,
			uid = tonumber(v.uid),
			product_id = tonumber(v.product_id),
			amount = tonumber(v.amount),
			paid_time = tonumber(v.paid_time),
		}
		print(tostring_r(o))
		table_insert(results,o)
		table_insert(sql_str_list,string_format("update `order` set `status` = %d where `order_id` = %s",
			ORDER_STATUS_FINISH,mysql.quote_sql_str(v.order_id)))
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

	--TODO 此处记录账单

	notify_payment(results)
end

local function routine_check_new_payment(mysql_conn)
    while true do
        local ok,ret = xpcall(select_paid_order,debug.traceback,mysql_conn)
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

	skynet.fork(routine_check_new_payment,mysql_conn)
end

local CMD = {}

function CMD.start(_express_worker)
	init()
	express_worker = _express_worker
	skynet.retpack(true)
end

skynet.start(function()
	skynet.dispatch("lua", function(session, source, cmd, ...)
		local f = assert(CMD[cmd])
		f(...)
	end)

end)
