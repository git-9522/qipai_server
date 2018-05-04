local skynet = require "skynet.manager"
local cjson = require "cjson"
local redis = require "redis"
local table_insert = table.insert
local table_remove = table.remove
local table_unpack = table.unpack
local string_format = string.format
local math_floor = math.floor
local table_concat = table.concat
local mongo = require "mongo"
local server_def = require "server_def"
local util = require "util"

local EXPIRED_TIME = 30
local MAIL_COUNT_LIMIT = 50
--[[
该模块主要处理hall发过来的平台邮件请求
--]]
local proxy_conn
local redis_conf = {}
local cache_connections = {}
local max_cache_connection_num
local allocated_cache_connection_num = 0
local sync_uids = {}

local CMD = {}

local mongodb_conf = {}

local function get_conn_from_pool()
    if #cache_connections > 0 then
        return table_remove(cache_connections)
    end

    while allocated_cache_connection_num >= max_cache_connection_num do
        --超上限了，唯有空转等了
        skynet.sleep(5)
        if #cache_connections > 0 then
            return table_remove(cache_connections)
        end
    end

    local ok,ret = pcall(redis.connect,redis_conf)
    while not ok do
        print('failed to connect redis',ret)
        skynet.error('failed to connect redis')
        skynet.sleep(100)
        ok,ret = pcall(redis.connect,redis_conf)
    end

    local conn = ret
    allocated_cache_connection_num = allocated_cache_connection_num + 1
    return conn
end

local function putback_to_pool(conn)
    table_insert(cache_connections,conn)
end

function CMD.open(conf)
    redis_conf.host = conf.redis_host
    redis_conf.port = conf.redis_port
    redis_conf.db = conf.redis_db

    local pre_alloc = conf.pre_alloc or 5
    max_cache_connection_num = conf.max_cache_connection_num or 100

    for i = 1,pre_alloc do
        table_insert(cache_connections,redis.connect(redis_conf))
    end

    allocated_cache_connection_num = pre_alloc

    skynet.retpack(true)
end

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

local function sync_run_by_uid(uid,f)
    local waiting_list = sync_uids[uid]
    if waiting_list == nil then
        sync_uids[uid] = true
    else
        if waiting_list == true then
            waiting_list = {}
            sync_uids[uid] = waiting_list
        end
        local co = coroutine.running()
        table_insert(waiting_list,co)
        skynet.wait(co) --等待唤醒
    end

    f()

    --再接着调度
    local waiting_list = sync_uids[uid]
    if waiting_list == true or #waiting_list == 0 then
        sync_uids[uid] = nil
        return
    end    

    local co = table_remove(waiting_list,1)
    skynet.wakeup(co)
end

local function make_plat_mail_key(uid)
    return string_format('plat_mail_%d',uid)
end

local function del_oldest_mail(keys)
    local oldest_time = 0
	local oldest_seq = -1
    local mail_list = {}
    for i=1,#keys,2 do
        if oldest_time == 0 then
			oldest_time = keys[i+1].send_time
			oldest_seq = keys[i]
		end
		local mail_info_send_time = keys[i+1].send_time
		if mail_info_send_time < oldest_time then
			oldest_time = mail_info_send_time
			oldest_seq = keys[i]
		end
    end  
end

function CMD.select_mail_list(uid)
     sync_run_by_uid(uid,function()
        local conn = get_conn_from_pool()
        local key = make_plat_mail_key(uid)
        local keys = execute_redis_cmd(conn.hgetall,conn,key)
        --过滤掉seq
        while #keys > MAIL_COUNT_LIMIT * 2 do
            del_oldest_mail(keys)
        end

        local mail_list = {}
        local time_sec = util.get_now_time()
        for i=1,#keys,2 do
            if keys[i] ~= "seq" then 
                print(keys[i+1])
                local data = cjson.decode(keys[i+1])
                if time_sec - data.send_time < EXPIRED_TIME * 86400 then
                    table_insert(mail_list,data)
                else
                    --邮件过期删除
                    execute_redis_cmd(conn.hdel,conn,key,keys[i])
                    billlog({_op="mail_expired",uid=uid,mail_name = data.title})
                end    
            end    
        end
        putback_to_pool(conn)
        --先返回给对端会话
        skynet.retpack(mail_list)
    end)
end

function CMD.take_attach(uid,mail_seq)
    sync_run_by_uid(uid,function()
        print("mail_seq",mail_seq)
        local conn = get_conn_from_pool()
        local key = make_plat_mail_key(uid)
        local data = execute_redis_cmd(conn.hget,conn,key,mail_seq)
        if not data then
            errlog(uid,"find mail failed",mail_seq)
            return skynet.retpack(false)   
        end
        data = cjson.decode(data)
        local attach_list = data.attach_list
        --日志
        billlog({op="take_attach",uid=uid,mail_seq=seq,mail_title=data.title})
        --删除邮件
        execute_redis_cmd(conn.hdel,conn,key,mail_seq)
        putback_to_pool(conn)
        return skynet.retpack(attach_list)
    end)
end

function CMD.del_mail(uid,mail_seq)
    sync_run_by_uid(uid,function()
        local conn = get_conn_from_pool()
        local key = make_plat_mail_key(uid)
        local seq = execute_redis_cmd(conn.hdel,conn,key,mail_seq)
        billlog({op="del_mail",uid=uid,seq=mail_seq})
        putback_to_pool(conn)
        return skynet.retpack(true)
    end)
end

function CMD.take_all_attach(uid)
    sync_run_by_uid(uid,function()
        local conn = get_conn_from_pool()
        local key = make_plat_mail_key(uid)
        local keys = execute_redis_cmd(conn.hgetall,conn,key)
        local mail_attach_list = {}
  
        for i=1,#keys,2 do
            if keys[i] ~= "seq" then 
                local data = keys[i+1]
                data = cjson.decode(data)
                if data.attach_list then
                    local mail_attach_info = {}
                    mail_attach_info.mail_seq = keys[i]
                    mail_attach_info.attach_list = data.attach_list  
                    table_insert(mail_attach_list,mail_attach_info)
                    execute_redis_cmd(conn.hdel,conn,uid,keys[i])
                end
            end    
        end

        billlog({op="take_all_attach",uid=uid,keys=table_concat(keys,",")})
        
        return skynet.retpack(mail_attach_list)
    end)    
end

skynet.start(function()
    skynet.dispatch("lua",function(session,addr,action,...)
        local f = CMD[action]
        if not f then
            print('could not find action',action)
            return
        end
        if f then
            f(...)
        end
    end)
end)

