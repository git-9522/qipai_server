local skynet = require "skynet.manager"
local cjson = require "cjson"
local redis = require "redis"
local server_def = require "server_def"

local table_insert = table.insert
local table_remove = table.remove
local table_unpack = table.unpack
local string_format = string.format

local select_server = require "router_selector"

local redis_conf
local cache_connections = {}
local max_cache_connection_num
local allocated_cache_connection_num = 0
local sync_uids = {}

local CMD = {}

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
    redis_conf = {
        host = conf.redis_host,
        port = conf.redis_port,
        db = conf.redis_db,
    }

    local pre_alloc = conf.pre_alloc or 2
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
        errlog(ret)
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

    local ok,err = xpcall(f,debug.traceback)
    if not ok then errlog(err) end

    --再接着调度
    local waiting_list = sync_uids[uid]
    if waiting_list == true or #waiting_list == 0 then
        sync_uids[uid] = nil
        return
    end    

    local co = table_remove(waiting_list,1)
    skynet.wakeup(co)
end

local function notify_offline_op(uid)
    R().hallsvr({key=uid}):send('.msg_handler','notify_agent',uid,'pull_offline_op_info')
end

local function insert_offline_op(uid,offline_data)
   sync_run_by_uid(uid,function()
        local conn = get_conn_from_pool()
        local key = string_format('offline_%d',uid)
        local value = cjson.encode(offline_data)

        execute_redis_cmd(conn.rpush,conn,key,value)
        putback_to_pool(conn)
        skynet.retpack(true)
    end)

    notify_offline_op(uid)
end

CMD.insert_offline_op = insert_offline_op

local POP_ALL_ELEMS_LUA = [[
    local r = redis.call('lrange',KEYS[1],0,-1)
    redis.call('del',KEYS[1])
    return r
]]
function CMD.pull_offline_data(uid)
    sync_run_by_uid(uid,function()
        local conn = get_conn_from_pool()
        local key = string_format('offline_%d',uid)

        local result = execute_redis_cmd(conn.eval,conn,POP_ALL_ELEMS_LUA,1,key)

        putback_to_pool(conn)
        --先返回给对端会话
        skynet.retpack(result)
    end)
end

function CMD.save_frecord(uid,record_key,game_type)
    sync_run_by_uid(uid,function()
        local conn = get_conn_from_pool()
        local key = string_format('frecord_%d_%d',game_type,uid)
        execute_redis_cmd(conn.rpush,conn,key,record_key)

        putback_to_pool(conn)
        skynet.retpack(true)
    end)
end

function CMD.get_all_frecord_key(uid,game_type)
    sync_run_by_uid(uid,function()
        local conn = get_conn_from_pool()
        local key = string_format('frecord_%d_%d',game_type,uid)

        local result = execute_redis_cmd(conn.lrange,conn,key,0,-1)

        putback_to_pool(conn)
        --先返回给对端会话
        skynet.retpack(result)
    end)
end

skynet.start(function()
    skynet.dispatch("lua",function(session,addr,cmd,...)
        print('============got params ...... ',cmd,...)
        CMD[cmd](...)
    end)
end)

