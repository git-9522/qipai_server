local skynet = require "skynet.manager"
local cjson = require "cjson"
local redis = require "redis"
local table_insert = table.insert
local table_remove = table.remove
local table_unpack = table.unpack
local string_format = string.format
local math_floor = math.floor
local mongo = require "mongo"
local server_def = require "server_def"
local mysql = require "mysql"
local utils = require "utils"
local constant = require "constant"
local util = require "util"

local PLATFORM_SEQ_START = 2000000000
local PLATFORM_MAIL_STATUS_NEW = 0
local PLATFORM_MAIL_STATUS_FINISH = 1
local PLATFORM_MAIL_ONCE_LIMTI = 10
--[[
该模块做的事情就是平台邮件处理--]]

local proxy_conn
local redis_conf = {}
local CMD = {}

local function execute_redis_cmd(...)
    local ok,ret = pcall(...)
    while not ok do
        skynet.error(ret)
        print(ret)
        skynet.sleep(100)
        print('now retry....')
        ok,ret = pcall(...)
    end
    return ret
end

local function get_uid_from_mongo()
    local conf = {
        host = skynet.getenv "mongodb_host",
        port = skynet.getenv "mongodb_port",
    }
    local ok,ret = pcall(mongo.client,conf)
    while not ok do
        print('failed to connect mongodb',ret)
        skynet.error('failed to connect mongodb')
        skynet.sleep(100)
        ok,ret = pcall(mongo.client,conf)
    end
    local client = ret
    local db_name = skynet.getenv "mongodb_name"
    local coll_name = skynet.getenv "mongodb_collname"
    local ret = client[db_name][coll_name]:find({},{_id=1})--({},{['_id']=1})
    local result = {}
    while ret:hasNext() do
		local user = ret:next()
        table_insert(result,user._id)
	end
    return result
end

--先把数据写入,再做一个写标记，切记不可调换。用脚本同时可保证数据写入的原子性
local update_redis_script = [[
   redis.call('select',KEYS[4]) 
   redis.call('hset',KEYS[1],"seq",ARGV[1])
   redis.call('hset',KEYS[1],ARGV[1],ARGV[2])
   redis.call('select',KEYS[2])
   redis.call('rpush',KEYS[3],ARGV[3])
]]

local get_user_seq_scripts = [[
    redis.call('select',KEYS[1])
    local ret = redis.call('hget',KEYS[2],ARGV[1])
    return ret
]]

local function new_mail_seq(mail_seq)
	if tonumber(mail_seq) >= 4000000000 then
		mail_seq =  PLATFORM_SEQ_START + 1
	else
		mail_seq = mail_seq + 1 --新邮件必须保证先加seq
	end

	return tostring(math_floor(mail_seq))
end

local function make_plat_mail_key(uid)
    return string.format('plat_mail_%d',uid)
end

local function deal_mail(o,conn)
    --获取发送的uid
    local uids
    if o.mail_type == constant.PLATFORM_MAIL_TYPE_ALL then
        uids = get_uid_from_mongo()
    elseif o.mail_type == constant.PLATFORM_MAIL_TYPE_SPEC then
        uids = utils.str_split(o.range,",")
    end   
    for i=1,#uids do
        local key = make_plat_mail_key(uids[i])
        --execute_redis_cmd(conn.select,conn,redis_conf.user_mail_db)
        local seq = execute_redis_cmd(conn.eval,conn,get_user_seq_scripts,2,redis_conf.db,key,"seq")
        if not seq then
            seq = PLATFORM_SEQ_START
        end
        local seq = new_mail_seq(seq)
        local m_data = {
            mail_seq = seq,
            title = o.title,
            content = o.content,
            send_time = o.send_time,
            attach_list = o.attach_list
        }
        m_data = cjson.encode(m_data)
        --再做一个写标记，切记不可调换 
        execute_redis_cmd(conn.eval,conn,update_redis_script,4,
        key,redis_conf.dirty_queue_db,redis_conf.dirty_queue_key,redis_conf.db,
        seq,m_data,uid)
    end

    --新加的邮件发送至大厅
    R().hallsvr():broadcast('.msg_handler','new_platform_mail',o.mail_type,o.range)   
end

local function select_new_mails(mysql_conn,redis_conn)
    --获取新邮件所有的key值
    local curr_time = util.get_now_time()
    local query_sql = string_format("select `id`,`title`,`content`,`send_time`,`mail_type`,`range`,`attach_list` from `platform_mail` where `send_time` < %d and `status` = %d limit %d",
    curr_time,PLATFORM_MAIL_STATUS_NEW,PLATFORM_MAIL_ONCE_LIMTI)
    local ret = mysql_conn:query(query_sql)
	local results = {}
	local sql_str_list = {}
	for k,v in pairs(ret) do    
		local o = {
			mail_id = v.id,
			title = v.title,
			content = v.content,
			send_time = v.send_time,
            mail_type = tonumber(v.mail_type),
            range = v.range,
		}
        o.attach_list = cjson.decode(v.attach_list)
		print(tostring_r(o))
        deal_mail(o,redis_conn)
		local updat_sql = string_format("update `platform_mail` set `status` = %d where `id` = %s",
			PLATFORM_MAIL_STATUS_FINISH,v.id)
        local ret = mysql_conn:query(updat_sql)    
	end
end

local function routine_check_new_mail(mysql_conn,redis_conn)
    while true do
        local ok,ret = pcall(select_new_mails,mysql_conn,redis_conn)
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

    redis_conf = {
        host = skynet.getenv "redis_host",
        port = tonumber(skynet.getenv "redis_port"),
        db = tonumber(skynet.getenv "redis_db"),
        dirty_queue_db = tonumber(skynet.getenv "dirty_queue_db"),
        dirty_queue_key = skynet.getenv "dirty_queue_key",
    }
    local redis_conn = redis.connect(redis_conf)

	skynet.fork(routine_check_new_mail,mysql_conn,redis_conn)
end

function CMD.start()
    init()
    skynet.retpack(true)
end

skynet.start(function()
    skynet.dispatch("lua",function(session,addr,action,...)
        local f = assert(CMD[action])
        f(...)
    end)
end)

